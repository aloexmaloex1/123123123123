--!strict
-- Player profile persistence. Gameplay code only ever touches the in-memory profile; this module
-- is the only place that talks to DataStores.
--
-- Guarantees:
--   * Every DataStore call is pcall'd with retry + exponential backoff.
--   * Writes use UpdateAsync only (atomic read-modify-write), never SetAsync.
--   * Session locking: one server owns a profile at a time. A fresh lock held by another server
--     means the player is asked to rejoin rather than loading (loading anyway is how dupes happen).
--   * Schema versioning with step-by-step migrations, run inside the claiming UpdateAsync.
--   * If a load fails, the player is kicked instead of playing on a default profile that would
--     overwrite their real save. (Exception: DataStores are unreachable in Studio, e.g. API access
--     disabled — then the session plays unsaved with a loud warning, for development only.)
--   * Staggered autosaves, final save + lock release on leave and on BindToClose.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("RelicRNG")
local Config = require(Shared:WaitForChild("Config")) :: any
local Types = require(Shared:WaitForChild("Types"))

type PlayerData = Types.PlayerData
type Profile = Types.Profile
type SavedRecord = Types.SavedRecord

local STORE_NAME = "RelicRNG_PlayerData_v1"
local SCHEMA_VERSION = 2
local AUTOSAVE_INTERVAL: number = Config.Economy.AutosaveInterval
local LOCK_STALE_SECONDS = AUTOSAVE_INTERVAL * 2 + 30 -- a crashed server's lock self-heals after this
local LOCK_RETRIES = 5
local LOCK_RETRY_DELAY = 3
local CALL_ATTEMPTS = 4

local DataService = {}

local profiles: { [Player]: Profile } = {}
local extraDefaults: { [string]: any } = {}
local jobId = if game.JobId ~= "" then game.JobId else "studio"

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[RelicRNG] DataStore unavailable:", result)
	end
end

---------------------------------------------------------------- helpers

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

-- Retries fn with exponential backoff (1, 2, 4 ... capped at 16 s). Returns ok, result.
local function withRetry<T>(label: string, fn: () -> T): (boolean, T?)
	local delaySeconds = 1
	for attempt = 1, CALL_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[RelicRNG] {label} attempt {attempt}/{CALL_ATTEMPTS} failed: {result}`)
		if attempt < CALL_ATTEMPTS then
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, 16)
		end
	end
	return false, nil
end

local function defaultData(): PlayerData
	local starter: string = Config.Economy.StarterRelic
	local data: PlayerData = {
		Coins = 0,
		CoinRemainder = 0,
		Tickets = Config.Economy.StartingTickets,
		TotalRolls = 0,
		Level = 1,
		XP = 0,
		Inventory = { [starter] = 1 },
		Discovered = { [starter] = true },
		Displayed = {},
		Pity = { 0, 0, 0, 0 },
		Stats = { TotalEarned = 0, BestTier = 1 },
		LastOnline = os.time(),
	}
	for key, value in extraDefaults do
		data[key] = deepCopy(value)
	end
	return data
end

-- Fills fields added since this profile was saved and drops references to things that no longer exist.
local function reconcile(data: PlayerData): PlayerData
	for key, value in defaultData() do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" then
			for subKey, subValue in value do
				if data[key][subKey] == nil then
					data[key][subKey] = subValue
				end
			end
		end
	end
	for i = 1, #Config.Pity do
		data.Pity[i] = tonumber(data.Pity[i]) or 0
	end
	for id in data.Inventory do
		if not Config.RelicsById[id] then
			data.Inventory[id] = nil
		end
	end
	for slot, id in data.Displayed do
		local n = tonumber(slot)
		if not Config.RelicsById[id] or not n or n < 1 or n > Config.Economy.MaxDisplaySlots then
			data.Displayed[slot] = nil
		end
	end
	return data
end

---------------------------------------------------------------- schema migrations

-- MIGRATIONS[v] upgrades a record from schema v to v + 1. Never delete a step.
-- Schema 1 (the original release) stored the bare data table with no Schema field.
local MIGRATIONS: { [number]: (any) -> any } = {
	-- v1 -> v2: wrap the bare data table with Schema + Lock.
	[1] = function(bareData)
		return { Schema = 2, Data = bareData, Lock = nil }
	end,
}

-- Turns whatever is in the key into a current-schema record (or nil for a brand new player).
local function normalise(stored: any): SavedRecord?
	if stored == nil then
		return nil
	end
	if type(stored) ~= "table" then
		error("stored value is not a table")
	end
	local record = stored
	if record.Schema == nil then
		record = MIGRATIONS[1](stored)
	end
	while record.Schema < SCHEMA_VERSION do
		local step = MIGRATIONS[record.Schema]
		if not step then
			error(`missing migration from schema {record.Schema}`)
		end
		record = step(record)
	end
	if record.Schema > SCHEMA_VERSION then
		error(`stored schema {record.Schema} is newer than this server ({SCHEMA_VERSION})`)
	end
	return record :: SavedRecord
end

DataService._normalise = normalise -- exposed for specs

---------------------------------------------------------------- load / claim

type ClaimStatus = "loaded" | "new" | "locked" | "error"

local function claim(player: Player): (ClaimStatus, PlayerData?)
	local status: ClaimStatus = "error"
	local loaded: PlayerData? = nil
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(stored)
			-- May run more than once; must not yield. Reset outputs every run.
			status, loaded = "error", nil
			local record = normalise(stored)
			local now = os.time()
			if record and record.Lock and record.Lock.JobId ~= jobId and now - record.Lock.Time < LOCK_STALE_SECONDS then
				status = "locked"
				return nil -- abort the write; someone else owns this profile
			end
			if record == nil then
				status = "new"
				record = { Schema = SCHEMA_VERSION, Data = defaultData(), Lock = nil }
			else
				status = "loaded"
			end
			local claimed = record :: SavedRecord
			claimed.Lock = { JobId = jobId, Time = now }
			loaded = claimed.Data
			return claimed
		end)
	end)
	if not ok then
		warn(`[RelicRNG] Claim failed for {player.Name}: {err}`)
		return "error", nil
	end
	return status, loaded
end

-- Loads and locks the player's profile. Returns nil (after kicking) if it can't be loaded safely.
function DataService.Load(player: Player): Profile?
	if not store then
		if RunService:IsStudio() then
			warn("[RelicRNG] No DataStore access in Studio: playing on an unsaved profile.")
			local profile: Profile = {
				Data = defaultData(),
				CanSave = false,
				IsNew = true,
				Released = false,
				NextAutosave = math.huge,
				Session = {},
			}
			profiles[player] = profile
			return profile
		end
		player:Kick("We couldn't reach the save servers. Please rejoin in a moment.")
		return nil
	end

	local status: ClaimStatus, data: PlayerData? = "error", nil
	local errors = 0
	for _ = 1, LOCK_RETRIES do
		if not player.Parent then
			return nil
		end
		status, data = claim(player)
		if status == "loaded" or status == "new" then
			break
		elseif status == "error" then
			errors += 1
			if errors >= CALL_ATTEMPTS then
				break
			end
			task.wait(2 ^ errors)
		else -- locked: the previous server may still be releasing it
			task.wait(LOCK_RETRY_DELAY)
		end
	end

	if status == "locked" then
		player:Kick("Your museum is still saving from another server. Please rejoin in a moment.")
		return nil
	elseif status == "error" or data == nil then
		player:Kick("Your data couldn't be loaded. Please rejoin — nothing was lost.")
		return nil
	end
	if not player.Parent then
		-- Left while loading: give the lock straight back.
		DataService.ReleaseLockOnly(player)
		return nil
	end

	local profile: Profile = {
		Data = reconcile(data :: PlayerData),
		CanSave = true,
		IsNew = status == "new",
		Released = false,
		-- Stagger autosaves by UserId so a full server doesn't save on the same tick.
		NextAutosave = os.clock() + AUTOSAVE_INTERVAL + (player.UserId % AUTOSAVE_INTERVAL),
		Session = {},
	}
	profiles[player] = profile
	return profile
end

---------------------------------------------------------------- save / release

local function write(player: Player, data: PlayerData, release: boolean): boolean
	local lostLock = false
	local ok = withRetry("Save " .. player.Name, function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(stored)
			lostLock = false
			local record = normalise(stored)
			if record and record.Lock and record.Lock.JobId ~= jobId then
				-- Another server took over (our lock went stale). Never overwrite its data.
				lostLock = true
				return nil
			end
			if not release and (not record or not record.Lock) then
				-- A late autosave racing our own release: writing now would re-lock a released profile.
				return nil
			end
			local out: SavedRecord = {
				Schema = SCHEMA_VERSION,
				Data = data,
				Lock = if release then nil else { JobId = jobId, Time = os.time() },
			}
			return out
		end)
		return true
	end)
	if lostLock then
		warn(`[RelicRNG] {player.Name}'s profile is owned by another server; save skipped.`)
		local profile = profiles[player]
		if profile then
			-- Nothing this session does can be saved any more; don't let them keep playing for nothing.
			profile.CanSave = false
		end
		if player.Parent and not release then
			player:Kick("Your museum was opened on another server. Please rejoin.")
		end
		return false
	end
	return ok
end

function DataService.ReleaseLockOnly(player: Player)
	if not store then
		return
	end
	withRetry("Release " .. player.Name, function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(stored)
			local record = normalise(stored)
			if not record or not record.Lock or record.Lock.JobId ~= jobId then
				return nil
			end
			record.Lock = nil
			return record
		end)
		return true
	end)
end

-- Saves the profile. `release` also clears the session lock (use on leave / shutdown).
function DataService.Save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile or not profile.CanSave or profile.Released or not store then
		return false
	end
	profile.Data.LastOnline = os.time()
	if release then
		profile.Released = true
	end
	profile.NextAutosave = os.clock() + AUTOSAVE_INTERVAL
	local ok = write(player, profile.Data, release == true)
	if not ok and not release then
		warn(`[RelicRNG] Autosave failed for {player.Name}; will retry next interval.`)
	end
	return ok
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

function DataService.All(): { [Player]: Profile }
	return profiles
end

-- Saves (and releases) then forgets the profile. Call on PlayerRemoving.
function DataService.Release(player: Player)
	if profiles[player] then
		DataService.Save(player, true)
	end
	profiles[player] = nil
end

-- Features call this during Init to add saved fields (nested tables get missing keys filled on load).
function DataService.AddDefaults(defaults: { [string]: any })
	for key, value in defaults do
		extraDefaults[key] = value
	end
end

-- QA only (see Services/CheatCommands): replaces the in-memory profile data with a fresh default.
function DataService.ResetData(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	profile.Data = defaultData()
	return true
end

---------------------------------------------------------------- lifecycle

function DataService.Start()
	-- Staggered autosaves, checked once a second.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, profile in profiles do
				if player.Parent and profile.CanSave and not profile.Released and now >= profile.NextAutosave then
					profile.NextAutosave = now + AUTOSAVE_INTERVAL
					local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
					if budget > 0 then
						task.spawn(DataService.Save, player, false)
					else
						profile.NextAutosave = now + 10 -- low budget: defer
					end
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true)
				pending -= 1
			end)
		end
		-- Studio: don't make stopping a playtest painful, but still try to release locks.
		local deadline = os.clock() + (if RunService:IsStudio() then 5 else 25)
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
