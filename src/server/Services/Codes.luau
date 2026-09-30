-- Redeem codes: players type a code (from socials / the group) to claim rewards once each.
-- The codes live server-only in ServerScriptService.RelicRNG.CodeList.
-- Also adds core.GrantRewards(player, rewards, revealTitle) -> ok, parts, used by Daily rewards too.
local CodeList = require(script.Parent.Parent:WaitForChild("CodeList"))

local Codes = { Priority = 40 }

local MAX_RAW_LENGTH = 64
local MAX_CODE_LENGTH = 32
local ATTEMPT_COOLDOWN = 2 -- seconds between attempts
local FAIL_WINDOW = 60 -- failed attempts are counted over this many seconds...
local MAX_FAILS = 10 -- ...and locked out past this many

-- Trims whitespace and upper-cases; nil if it can't be a code.
function Codes.Normalize(raw)
	if type(raw) ~= "string" or #raw > MAX_RAW_LENGTH then
		return nil
	end
	local code = raw:match("^%s*(.-)%s*$"):upper()
	if #code == 0 or #code > MAX_CODE_LENGTH or code:find("[^%w_%-]") then
		return nil
	end
	return code
end

local function formatSeconds(seconds)
	if seconds >= 3600 and seconds % 3600 == 0 then
		local hours = seconds // 3600
		return hours .. (hours == 1 and " hour" or " hours")
	end
	return math.max(1, seconds // 60) .. " min"
end

-- Builds the case-insensitive lookup and warns about typos in the list.
function Codes.BuildLookup(list, Config)
	local lookup = {}
	for key, entry in pairs(list) do
		local code = Codes.Normalize(key)
		local rewards = type(entry) == "table" and entry.Rewards
		if not code or type(rewards) ~= "table" then
			warn("[RelicRNG] CodeList: skipping bad entry " .. tostring(key))
			continue
		end
		if rewards.Relic and Config and not Config.RelicsById[rewards.Relic] then
			warn(("[RelicRNG] CodeList: %s gives unknown relic %s"):format(code, tostring(rewards.Relic)))
		end
		if rewards.Boost and (rewards.Boost.Kind ~= "Luck" and rewards.Boost.Kind ~= "Income" or type(rewards.Boost.Seconds) ~= "number") then
			warn("[RelicRNG] CodeList: " .. code .. " has an invalid Boost")
		end
		lookup[code] = entry
	end
	return lookup
end

function Codes.Init(core)
	local Config = core.Config
	local lookup = Codes.BuildLookup(CodeList, Config)

	core.DataService.AddDefaults({
		RedeemedCodes = {}, -- [CODE] = unix time redeemed
	})

	-- Grants a reward table (Coins, Tickets, Credits, Relic, Boost) and syncs the client.
	-- A relic plays the reveal card titled `revealTitle`. Returns ok, { "+50 Dig Tickets", ... }.
	function core.GrantRewards(player, rewards, revealTitle)
		local data = core.GetData(player)
		if not data or type(rewards) ~= "table" then
			return false, {}
		end
		local parts = {}
		local tickets = tonumber(rewards.Tickets)
		if tickets and tickets > 0 then
			core.AddTickets(player, tickets)
			table.insert(parts, ("+%s Dig Ticket%s"):format(Config.FormatNumber(tickets), tickets == 1 and "" or "s"))
		end
		local coins = tonumber(rewards.Coins)
		if coins and coins > 0 then
			core.AddCoins(player, coins, false)
			table.insert(parts, ("+%s Coins"):format(Config.FormatNumber(coins)))
		end
		local credits = tonumber(rewards.Credits)
		if credits and credits > 0 and core.AddCredits then
			core.AddCredits(player, credits)
			table.insert(parts, ("+%s Security Credits"):format(Config.FormatNumber(credits)))
		end
		local boost = rewards.Boost
		if type(boost) == "table" and core.AddBoost and core.AddBoost(player, boost.Kind, tonumber(boost.Seconds) or 0) then
			table.insert(parts, ("%s %s Boost (x2)"):format(formatSeconds(boost.Seconds), boost.Kind))
		end
		local relic = rewards.Relic and Config.RelicsById[rewards.Relic]
		if relic then
			local isNew = not data.Discovered[relic.Id]
			if core.GrantRelic(player, relic.Id, 1) then
				table.insert(parts, relic.Name .. " relic")
				core.FireClient(player, "Codes", "Reveal", { RelicId = relic.Id, Tier = relic.Tier, IsNew = isNew, Title = revealTitle or "REWARD" })
			end
		end
		core.Sync(player)
		return true, parts
	end

	function core.Actions.RedeemCode(player, raw)
		local profile = core.GetProfile(player)
		local limits = profile.Session.CodeLimits
		if not limits then
			limits = { Last = -math.huge, Fails = {} }
			profile.Session.CodeLimits = limits
		end

		local now = os.clock()
		if now - limits.Last < ATTEMPT_COOLDOWN then
			return false, "Slow down! Try again in a moment."
		end
		local recent = {}
		for _, t in ipairs(limits.Fails) do
			if now - t < FAIL_WINDOW then
				table.insert(recent, t)
			end
		end
		limits.Fails = recent
		if #recent >= MAX_FAILS then
			return false, ("Too many wrong codes. Try again in %ds."):format(math.ceil(FAIL_WINDOW - (now - recent[1])))
		end
		limits.Last = now

		local code = Codes.Normalize(raw)
		local entry = code and lookup[code]
		if not entry then
			table.insert(limits.Fails, now)
			return false, "Invalid code. Check the spelling and try again."
		end
		local data = profile.Data
		if data.RedeemedCodes[code] then
			return false, "You already redeemed that code."
		end
		if tonumber(entry.Expires) and os.time() >= entry.Expires then
			return false, "That code has expired."
		end
		if tonumber(entry.MinLevel) and data.Level < entry.MinLevel then
			return false, ("Reach Curator Level %d to use this code."):format(entry.MinLevel)
		end

		data.RedeemedCodes[code] = os.time()
		local _, parts = core.GrantRewards(player, entry.Rewards, "CODE REWARD")
		return true, "Code redeemed! " .. table.concat(parts, ", ")
	end
end

return Codes
