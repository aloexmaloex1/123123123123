-- Relic RNG server entry point (the only server Script): creates remotes, owns player lifecycle,
-- rolling, displays, income and levels, and hosts the feature hook system.
-- The server owns all game state; clients only send requests and display what they're told.
--
-- Feature services live in ServerScriptService.RelicRNG.Services. Each ModuleScript returns a table
-- with optional Init(core) and Start(core). Startup is two-phase: every service's Init runs (in
-- Priority order) before any Start. Services plug in through core.Hook / core.Actions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("RelicRNG")
local Config = require(Shared:WaitForChild("Config"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local DataService = require(script.Parent.DataService)
local RollService = require(script.Parent.RollService)
local MuseumService = require(script.Parent.MuseumService)
local RateLimit = require(script.Parent.RateLimit)

local Economy = Config.Economy

---------------------------------------------------------------- remotes (created here, never by clients)

local Remotes = Shared:FindFirstChild("Remotes")
local remotesIsNew = Remotes == nil
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
end
for className, names in pairs({ RemoteEvent = RemoteNames.Events, RemoteFunction = RemoteNames.Functions }) do
	for _, name in ipairs(names) do
		if not Remotes:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = Remotes
		end
	end
end
if remotesIsNew then
	-- Parent last so clients see a complete folder.
	Remotes.Parent = Shared
end

local digSitesFolder = workspace:WaitForChild("RelicRNG"):WaitForChild("DigSites")

local core = {
	Config = Config,
	Remotes = Remotes,
	Shared = Shared,
	DataService = DataService,
	RollService = RollService,
	MuseumService = MuseumService,
	RateLimit = RateLimit,
	Actions = {}, -- [name] = function(player, arg) -> ok, message?, extra?
	-- Optional per-action limits: RateLimits[name] = { rate, burst }. Default below.
	RateLimits = {},
}

local DEFAULT_ACTION_RATE = { 6, 10 } -- tokens per second, burst
local ROLL_RATE = { 2, 3 }

local hooks = {
	IncomeMultiplier = {}, -- fn(player, data) -> factor (1 = no change)
	LuckMultiplier = {}, -- fn(player, data) -> factor
	DisplaySlots = {}, -- fn(player, data) -> extra pedestals
	OfflineSeconds = {}, -- fn(player, data) -> extra offline seconds
	Snapshot = {}, -- fn(player, data, snapshot) adds fields to the client snapshot
	Stats = {}, -- fn(player, data) sets extra player attributes (runs every second)
	PlayerAdded = {}, -- fn(player, profile, greeting) after load; may add fields to greeting
	PlayerRemoving = {}, -- fn(player, profile) before save
	Tick = {}, -- fn(player, profile, now) once per second
	Rolled = {}, -- fn(player, data, result) after every dig-site roll
	LevelUp = {}, -- fn(player, data, newLevel)
}

---------------------------------------------------------------- Feature API

function core.Hook(event, fn)
	assert(hooks[event], "Unknown hook " .. tostring(event))
	table.insert(hooks[event], fn)
end

function core.GetProfile(player)
	return DataService.Get(player)
end

function core.GetData(player)
	local profile = DataService.Get(player)
	return profile and profile.Data
end

function core.Notify(player, text, kind)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

-- Sends a feature-specific message to one client; client features listen with ctx.OnEvent(name, fn).
function core.FireClient(player, featureName, ...)
	Remotes.FeatureEvent:FireClient(player, featureName, ...)
end

function core.FireAllClients(featureName, ...)
	Remotes.FeatureEvent:FireAllClients(featureName, ...)
end

-- True when n is a finite whole number within [min, max]. Use on every numeric remote argument.
function core.IsInt(n, min, max)
	return type(n) == "number" and n == n and n == math.floor(n) and n >= min and n <= max
end

-- Sum of an active set bonus kind ("Income", "Luck", "OfflineHours", "HeistSeconds").
function core.SetBonus(data, kind)
	local total = 0
	for _, set in ipairs(Config.Sets) do
		local value = set.Bonus[kind]
		if value and core.IsSetComplete(data, set) then
			total += value
		end
	end
	return total
end

function core.IsSetComplete(data, set)
	for _, relicId in ipairs(set.Relics) do
		if (data.Inventory[relicId] or 0) < 1 then
			return false
		end
	end
	return true
end

function core.GetDisplaySlots(player, data)
	local slots = Economy.DisplaySlots
	for _, fn in ipairs(hooks.DisplaySlots) do
		slots += fn(player, data) or 0
	end
	return math.clamp(slots, 1, Economy.MaxDisplaySlots)
end

function core.GetIncomeMultiplier(player, data)
	local mult = 1 + core.SetBonus(data, "Income")
	for _, fn in ipairs(hooks.IncomeMultiplier) do
		mult *= fn(player, data) or 1
	end
	return mult
end

function core.GetBaseIncome(player, data)
	local slots = core.GetDisplaySlots(player, data)
	local total = 0
	for slot, relicId in pairs(data.Displayed) do
		if tonumber(slot) <= slots then
			total += Config.GetIncome(relicId)
		end
	end
	return total
end

function core.GetIncomePerMinute(player, data)
	return core.GetBaseIncome(player, data) * core.GetIncomeMultiplier(player, data)
end

-- Personal luck (not including the dig site's own luck).
function core.GetLuck(player, data)
	local luck = 1 + core.SetBonus(data, "Luck")
	for _, fn in ipairs(hooks.LuckMultiplier) do
		luck *= fn(player, data) or 1
	end
	return luck
end

function core.GetOfflineCap(player, data)
	local seconds = Economy.OfflineCapSeconds + core.SetBonus(data, "OfflineHours") * 3600
	for _, fn in ipairs(hooks.OfflineSeconds) do
		seconds += fn(player, data) or 0
	end
	return seconds
end

function core.AddCoins(player, amount, earned)
	local data = core.GetData(player)
	if not data or amount ~= amount then
		return
	end
	amount = math.floor(amount)
	data.Coins = math.max(0, data.Coins + amount)
	if earned and amount > 0 then
		data.Stats.TotalEarned += amount
	end
end

function core.AddTickets(player, amount)
	local data = core.GetData(player)
	if data and amount == amount then
		data.Tickets = math.max(0, data.Tickets + math.floor(amount))
	end
end

function core.GrantRelic(player, relicId, count)
	local data = core.GetData(player)
	if not data or not Config.RelicsById[relicId] then
		return false
	end
	data.Inventory[relicId] = (data.Inventory[relicId] or 0) + (count or 1)
	data.Discovered[relicId] = true
	local tier = Config.RelicsById[relicId].Tier
	if tier > (data.Stats.BestTier or 1) then
		data.Stats.BestTier = tier
	end
	return true
end

function core.AddXP(player, amount)
	local data = core.GetData(player)
	if not data or amount ~= amount or amount <= 0 then
		return
	end
	data.XP += math.floor(amount)
	local leveled = false
	while data.XP >= Config.XPForLevel(data.Level) do
		data.XP -= Config.XPForLevel(data.Level)
		data.Level += 1
		leveled = true
		for _, fn in ipairs(hooks.LevelUp) do
			task.spawn(fn, player, data, data.Level)
		end
		local unlocked
		for _, siteId in ipairs(Config.DigSiteOrder) do
			if Config.DigSites[siteId].Level == data.Level then
				unlocked = Config.DigSites[siteId].Name
			end
		end
		core.Notify(player, ("Curator Level %d!%s"):format(data.Level, unlocked and (" " .. unlocked .. " unlocked!") or ""), "levelup")
	end
	if leveled then
		core.Sync(player)
	end
end

function core.RefreshMuseum(player)
	local data = core.GetData(player)
	if data then
		MuseumService.Refresh(player, data.Displayed, core.GetDisplaySlots(player, data))
	end
end

function core.SyncStats(player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local data = profile.Data
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("Tickets", data.Tickets)
	player:SetAttribute("TotalRolls", data.TotalRolls)
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("XPNeeded", Config.XPForLevel(data.Level))
	player:SetAttribute("IncomePerMin", math.floor(core.GetIncomePerMinute(player, data) * 10) / 10)
	player:SetAttribute("IncomeMultiplier", core.GetIncomeMultiplier(player, data))
	player:SetAttribute("Luck", core.GetLuck(player, data))
	player:SetAttribute("DisplaySlots", core.GetDisplaySlots(player, data))
	player:SetAttribute("OfflineCapSeconds", core.GetOfflineCap(player, data))
	local start = profile.Session.FreeTicketStart
	player:SetAttribute("NextFreeTicketAt", start and start + Economy.FreeTicketInterval or 0)
	for _, fn in ipairs(hooks.Stats) do
		fn(player, data)
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Coins.Value = data.Coins
		leaderstats.Level.Value = data.Level
	end
end

function core.BuildSnapshot(player)
	local data = core.GetData(player)
	local snapshot = {
		Inventory = data.Inventory,
		Discovered = data.Discovered,
		Displayed = data.Displayed,
		Pity = data.Pity,
		Stats = data.Stats,
	}
	for _, fn in ipairs(hooks.Snapshot) do
		fn(player, data, snapshot)
	end
	return snapshot
end

function core.SendSnapshot(player)
	if core.GetData(player) then
		Remotes.DataUpdated:FireClient(player, core.BuildSnapshot(player))
	end
end

function core.Sync(player)
	core.SyncStats(player)
	core.SendSnapshot(player)
end

-- Moves the character, streaming the destination in first so geometry exists on arrival.
function core.Teleport(player, cframe)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end
	pcall(function()
		player:RequestStreamAroundAsync(cframe.Position, 5)
	end)
	if character.Parent then
		character:PivotTo(cframe + Vector3.new(0, 3, 0))
		return true
	end
	return false
end

function core.GetDigSiteModel(siteId)
	return digSitesFolder:FindFirstChild(siteId)
end

function core.IsSiteUnlocked(data, siteId)
	local site = Config.DigSites[siteId]
	return site ~= nil and data.Level >= site.Level
end

---------------------------------------------------------------- rolling

local function playRevealEffect(siteId, tier)
	local model = core.GetDigSiteModel(siteId)
	local attachment = model and model:FindFirstChild("PromptAttachment", true)
	if not attachment then
		return
	end
	local dust = attachment:FindFirstChild("Dust")
	if dust then
		dust:Emit(20 + tier * 4)
	end
	local light = attachment:FindFirstChild("RevealLight")
	if light and tier >= 3 then
		light.Color = Config.Rarities[tier].Color
		light.Brightness = 2 + tier
		task.delay(1.2, function()
			light.Brightness = 0
		end)
	end
end

-- Rolls at `siteId` for the player, spending tickets. `quiet` skips the reveal (auto-dig).
function core.RollAt(player, siteId, quiet)
	local profile = DataService.Get(player)
	local site = Config.DigSites[siteId]
	if not profile or not site then
		return nil, "Unknown dig site."
	end
	local data = profile.Data
	if data.Level < site.Level then
		return nil, ("%s unlocks at Curator Level %d."):format(site.Name, site.Level)
	end
	if data.Tickets < site.TicketCost then
		return nil, ("You need %d Dig Ticket%s here. Buy more or wait for a free one."):format(site.TicketCost, site.TicketCost == 1 and "" or "s")
	end

	data.Tickets -= site.TicketCost
	local result = RollService.Roll(data, siteId, site.Luck * core.GetLuck(player, data))
	result.XP = Config.RollXP(result.Tier, site.TicketCost)
	for _, fn in ipairs(hooks.Rolled) do
		fn(player, data, result)
	end
	core.AddXP(player, result.XP)
	core.Sync(player)
	if not quiet then
		Remotes.RollResult:FireClient(player, result)
		playRevealEffect(siteId, result.Tier)
	end
	if result.Tier >= Economy.AnnounceMinTier then
		-- Wait for the finder's reveal to finish so the server-wide banner doesn't spoil it.
		task.delay(if quiet then 0 else 4.5, function()
			Remotes.Announce:FireAllClients(player.DisplayName, result.RelicId, result.Tier)
		end)
	end
	return result
end

local lastRoll = {}

local function tryRoll(player)
	if not RateLimit.Allow(player, "Roll", ROLL_RATE[1], ROLL_RATE[2]) then
		return
	end
	local profile = DataService.Get(player)
	if not profile or profile.Session.Busy then
		return
	end
	local now = os.clock()
	if lastRoll[player] and now - lastRoll[player] < Economy.RollCooldown then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local siteId = Config.SiteAt(root.Position)
	if not siteId then
		core.Notify(player, "Head to a dig site to excavate.", "error")
		return
	end
	lastRoll[player] = now
	local result, err = core.RollAt(player, siteId)
	if not result then
		core.Notify(player, err, "error")
	end
end

-- RequestRoll takes no arguments; anything the client sends is ignored.
Remotes.RequestRoll.OnServerEvent:Connect(function(player)
	tryRoll(player)
end)

local function connectPrompt(siteModel)
	local prompt = siteModel:FindFirstChild("ExcavatePrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(tryRoll)
	end
end
for _, siteModel in ipairs(digSitesFolder:GetChildren()) do
	connectPrompt(siteModel)
end
digSitesFolder.ChildAdded:Connect(function(siteModel)
	siteModel:WaitForChild("DigSpot", 5)
	connectPrompt(siteModel)
end)

---------------------------------------------------------------- core actions

local actions = core.Actions
local welcome = {}

local function displayedCount(data, relicId)
	local count = 0
	for _, id in pairs(data.Displayed) do
		if id == relicId then
			count += 1
		end
	end
	return count
end

function actions.GetSnapshot(player)
	local greeting = welcome[player]
	welcome[player] = nil
	return true, core.BuildSnapshot(player), greeting
end

function actions.Display(player, relicId)
	local data = core.GetData(player)
	if type(relicId) ~= "string" or not Config.RelicsById[relicId] then
		return false, "Unknown relic."
	end
	if (data.Inventory[relicId] or 0) <= displayedCount(data, relicId) then
		return false, "You have no spare copy of that relic."
	end
	for slot = 1, core.GetDisplaySlots(player, data) do
		local key = tostring(slot)
		if not data.Displayed[key] then
			data.Displayed[key] = relicId
			core.RefreshMuseum(player)
			core.Sync(player)
			return true, Config.RelicsById[relicId].Name .. " is now on display!"
		end
	end
	return false, "All display pedestals are full."
end

function actions.Undisplay(player, slot)
	local data = core.GetData(player)
	if not core.IsInt(slot, 1, Economy.MaxDisplaySlots) then
		return false, "Invalid pedestal."
	end
	local key = tostring(slot)
	if not data.Displayed[key] then
		return false, "That pedestal is empty."
	end
	data.Displayed[key] = nil
	core.RefreshMuseum(player)
	core.Sync(player)
	return true
end

-- Fills pedestals with the highest-income relics, swapping out weaker ones.
function actions.AutoDisplay(player)
	local data = core.GetData(player)
	local slots = core.GetDisplaySlots(player, data)
	-- Work per relic id (not per copy) so cost doesn't grow with how many duplicates someone owns:
	-- pick the best `slots` relics overall, then place them.
	local ids = {}
	for relicId, count in pairs(data.Inventory) do
		if count > 0 and Config.RelicsById[relicId] then
			table.insert(ids, relicId)
		end
	end
	table.sort(ids, function(a, b)
		return Config.GetIncome(a) > Config.GetIncome(b)
	end)
	local wanted = {} -- relicId -> copies to show
	local remaining = slots
	for _, relicId in ipairs(ids) do
		if remaining <= 0 then
			break
		end
		local take = math.min(data.Inventory[relicId], remaining)
		wanted[relicId] = take
		remaining -= take
	end
	-- Keep pedestals that already show a wanted relic; clear the rest; fill gaps.
	local before = table.clone(data.Displayed)
	local keep = {}
	for slot = 1, Economy.MaxDisplaySlots do
		local key = tostring(slot)
		local current = data.Displayed[key]
		if current and slot <= slots and (wanted[current] or 0) > (keep[current] or 0) then
			keep[current] = (keep[current] or 0) + 1
		else
			data.Displayed[key] = nil
		end
	end
	local nextSlot = 1
	for _, relicId in ipairs(ids) do
		for _ = 1, (wanted[relicId] or 0) - (keep[relicId] or 0) do
			while data.Displayed[tostring(nextSlot)] do
				nextSlot += 1
			end
			data.Displayed[tostring(nextSlot)] = relicId
		end
	end
	local placed = 0
	for slot = 1, Economy.MaxDisplaySlots do
		local key = tostring(slot)
		if data.Displayed[key] ~= before[key] then
			placed += 1
		end
	end
	core.RefreshMuseum(player)
	core.Sync(player)
	return true, placed > 0 and "Museum arranged for maximum income." or "Your museum is already at its best."
end

function actions.BuyTickets(player, amount)
	if amount ~= 1 and amount ~= 10 and amount ~= 100 then
		return false, "Invalid amount."
	end
	local data = core.GetData(player)
	local cost = amount * Economy.TicketCost
	if data.Coins < cost then
		return false, ("You need %s coins."):format(Config.FormatNumber(cost))
	end
	data.Coins -= cost
	data.Tickets += amount
	core.SyncStats(player)
	return true, ("Bought %d Dig Ticket%s."):format(amount, amount == 1 and "" or "s")
end

function actions.Teleport(player, destination)
	local profile = DataService.Get(player)
	if profile.Session.Busy then
		return false, "You can't travel right now."
	end
	if type(destination) ~= "string" then
		return false, "Nowhere to go."
	end
	local target
	if destination == "Museum" then
		local plot = MuseumService.GetPlot(player)
		target = plot and plot:FindFirstChild("TeleportPoint")
	elseif Config.DigSites[destination] then
		if not core.IsSiteUnlocked(profile.Data, destination) then
			return false, ("%s unlocks at Curator Level %d."):format(Config.DigSites[destination].Name, Config.DigSites[destination].Level)
		end
		local model = core.GetDigSiteModel(destination)
		target = model and model:FindFirstChild("TeleportPoint")
	end
	if not target then
		return false, "Nowhere to go."
	end
	core.Teleport(player, target.CFrame)
	return true
end

-- Every client request enters here: rate limit -> action name check -> handler (which validates its arg).
Remotes.Action.OnServerInvoke = function(player, action, arg)
	if type(action) ~= "string" or #action > 40 then
		return false
	end
	local handler = actions[action]
	if not handler then
		return false, "Unknown action."
	end
	local limit = core.RateLimits[action] or DEFAULT_ACTION_RATE
	if not RateLimit.Allow(player, "Action:" .. action, limit[1], limit[2]) then
		return false, "Slow down a little."
	end
	if not DataService.Get(player) or not player:GetAttribute("Loaded") then
		return false, "Still loading your museum."
	end
	local ok, a, b, c = pcall(handler, player, arg)
	if not ok then
		warn("[RelicRNG] Action " .. action .. " failed: " .. tostring(a))
		return false, "Something went wrong."
	end
	return a, b, c
end

---------------------------------------------------------------- feature services (phase 1: Init)

local services = {}
for _, module in ipairs(script.Parent:WaitForChild("Services"):GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, service = pcall(require, module)
		if ok and type(service) == "table" then
			service.Name = module.Name
			table.insert(services, service)
		else
			warn("[RelicRNG] Failed to load service " .. module.Name .. ": " .. tostring(service))
		end
	end
end
table.sort(services, function(a, b)
	return (a.Priority or 100) < (b.Priority or 100)
end)
for _, service in ipairs(services) do
	if service.Init then
		local ok, err = pcall(service.Init, core)
		if not ok then
			warn("[RelicRNG] Service " .. service.Name .. " failed to init: " .. tostring(err))
		end
	end
end

---------------------------------------------------------------- player lifecycle

local function onPlayerAdded(player)
	local profile = DataService.Load(player)
	if not profile then
		return -- kicked (couldn't load safely) or already left
	end
	if not player.Parent then
		DataService.Release(player)
		return
	end
	local data = profile.Data

	local greeting
	if profile.IsNew then
		greeting = { IsNew = true, Saving = profile.CanSave }
	else
		local cap = core.GetOfflineCap(player, data)
		local away = math.clamp(os.time() - (data.LastOnline or os.time()), 0, cap)
		local earned = math.floor(core.GetIncomePerMinute(player, data) / 60 * away)
		greeting = { Seconds = away, Earned = earned, Capped = away >= cap, CapSeconds = cap }
		if earned > 0 then
			core.AddCoins(player, earned, true)
		end
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in ipairs({ "Coins", "Level" }) do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = leaderstats
	end
	leaderstats.Parent = player

	if MuseumService.Assign(player) then
		core.RefreshMuseum(player)
	else
		core.Notify(player, "All museum plots are taken on this server.", "error")
	end

	for _, fn in ipairs(hooks.PlayerAdded) do
		local ok, err = pcall(fn, player, profile, greeting)
		if not ok then
			warn("[RelicRNG] PlayerAdded hook failed: " .. tostring(err))
		end
	end
	if not player.Parent then
		return -- left while hooks were yielding; onPlayerRemoving has already cleaned up
	end
	if greeting.IsNew or (greeting.Earned or 0) > 0 or greeting.Extra then
		welcome[player] = greeting
	end

	core.SyncStats(player)
	player:SetAttribute("Loaded", true)
	core.SendSnapshot(player)
end

local function onPlayerRemoving(player)
	local profile = DataService.Get(player)
	if profile then
		for _, fn in ipairs(hooks.PlayerRemoving) do
			local ok, err = pcall(fn, player, profile)
			if not ok then
				warn("[RelicRNG] PlayerRemoving hook failed: " .. tostring(err))
			end
		end
	end
	MuseumService.Release(player)
	DataService.Release(player) -- final save + lock release
	lastRoll[player] = nil
	welcome[player] = nil
end

---------------------------------------------------------------- phase 2: Start

DataService.Start()
for _, service in ipairs(services) do
	if service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start, core)
			if not ok then
				warn("[RelicRNG] Service " .. service.Name .. " failed to start: " .. tostring(err))
			end
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Passive income, free tickets and feature ticks, once per second.
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.time()
		for player, profile in pairs(DataService.All()) do
			if player.Parent and player:GetAttribute("Loaded") then
				local data = profile.Data
				data.CoinRemainder += core.GetIncomePerMinute(player, data) / 60
				local whole = math.floor(data.CoinRemainder)
				if whole > 0 then
					core.AddCoins(player, whole, true)
					data.CoinRemainder -= whole
				end

				if data.Tickets < Economy.FreeTicketCap then
					local start = profile.Session.FreeTicketStart
					if not start then
						profile.Session.FreeTicketStart = now
					elseif now - start >= Economy.FreeTicketInterval then
						data.Tickets += 1
						profile.Session.FreeTicketStart = data.Tickets < Economy.FreeTicketCap and now or nil
					end
				else
					profile.Session.FreeTicketStart = nil
				end

				for _, fn in ipairs(hooks.Tick) do
					local ok, err = pcall(fn, player, profile, now)
					if not ok then
						warn("[RelicRNG] Tick hook failed: " .. tostring(err))
					end
				end
				core.SyncStats(player)
			end
		end
	end
end)
