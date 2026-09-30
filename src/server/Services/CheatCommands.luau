--!strict
-- QA cheat commands, gated SERVER-SIDE: always on in Studio; in live servers only for the game's
-- creator (or DEV_USER_IDS). Every command goes through the same core APIs real gameplay uses,
-- so cheats exercise the real code paths. Client: Features/99_DevPanel (shown only when IsDev).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CheatCommands = { Priority = 90 }

-- Extra accounts allowed to use cheats in live servers (the place's creator is always allowed).
local DEV_USER_IDS: { [number]: true } = {}

local function isAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if DEV_USER_IDS[player.UserId] then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function num(value: unknown, min: number, max: number): number?
	if type(value) ~= "number" or value ~= value or value < min or value > max then
		return nil
	end
	return math.floor(value)
end

function CheatCommands.Init(core: any)
	local Config = core.Config

	local commands: { [string]: (player: Player, value: unknown) -> (boolean, string?) } = {}

	commands.Coins = function(player, value)
		local n = num(value, -1e12, 1e12)
		if not n then
			return false, "Coins needs a number."
		end
		core.AddCoins(player, n, false)
		return true, `Coins {n >= 0 and "+" or ""}{n}`
	end

	commands.Tickets = function(player, value)
		local n = num(value, -1e7, 1e7)
		if not n then
			return false, "Tickets needs a number."
		end
		core.AddTickets(player, n)
		return true, `Tickets +{n}`
	end

	commands.Credits = function(player, value)
		local n = num(value, -1e7, 1e7)
		if not n or not core.AddCredits then
			return false, "Credits unavailable."
		end
		core.AddCredits(player, n)
		return true, `Security Credits +{n}`
	end

	commands.XP = function(player, value)
		local n = num(value, 1, 1e9)
		if not n then
			return false, "XP needs a positive number."
		end
		core.AddXP(player, n)
		return true, `XP +{n}`
	end

	-- Raises the player to `value` by granting exactly the XP needed (so level-up hooks run).
	commands.Level = function(player, value)
		local target = num(value, 1, 500)
		local data = core.GetData(player)
		if not target or not data then
			return false, "Level needs a number."
		end
		if target <= data.Level then
			return false, "Can only raise the level."
		end
		local needed = Config.XPForLevel(data.Level) - data.XP
		for level = data.Level + 1, target - 1 do
			needed += Config.XPForLevel(level)
		end
		core.AddXP(player, needed)
		return true, `Now Curator Level {target}`
	end

	commands.Relic = function(player, value)
		if type(value) ~= "string" or not Config.RelicsById[value] then
			return false, "Unknown relic id."
		end
		core.GrantRelic(player, value, 1)
		return true, `Granted {Config.RelicsById[value].Name}`
	end

	commands.AllRelics = function(player)
		for _, relic in Config.Relics do
			core.GrantRelic(player, relic.Id, 1)
		end
		return true, `Granted all {#Config.Relics} relics`
	end

	-- Sets pity counter `index` to one roll before its guarantee, to test the pity reveal.
	commands.PityNext = function(player, value)
		local index = num(value, 1, #Config.Pity)
		local data = core.GetData(player)
		if not index or not data then
			return false, "PityNext needs 1-4."
		end
		data.Pity[index] = Config.Pity[index].Every - 1
		return true, `Next roll triggers the {Config.Rarities[Config.Pity[index].MinTier].Name}+ pity`
	end

	commands.Boost = function(player, value)
		if (value ~= "Luck" and value ~= "Income") or not core.AddBoost then
			return false, "Boost needs Luck or Income."
		end
		core.AddBoost(player, value, 15 * 60)
		return true, `{value} boost +15 min`
	end

	commands.Thief = function(player)
		if not core.Security or not core.Security.TriggerThief then
			return false, "Security service not loaded."
		end
		task.spawn(core.Security.TriggerThief, player)
		return true, "Thief incoming"
	end

	commands.HeistEnergy = function(player)
		local data = core.GetData(player)
		if not data or type(data.Heist) ~= "table" then
			return false, "No heist data."
		end
		data.Heist.Energy = 5
		data.Heist.EnergyAt = os.time()
		local profile = core.GetProfile(player)
		if profile then
			profile.Session.HeistCooldownUntil = 0
		end
		return true, "Heist energy refilled"
	end

	commands.Reset = function(player)
		if not core.DataService.ResetData(player) then
			return false, "No profile."
		end
		core.RefreshMuseum(player)
		return true, "Profile reset to a brand-new save"
	end

	core.Actions.Dev = function(player: Player, arg: unknown)
		if not isAuthorized(player) then
			return false -- silently ignore: remote names are public
		end
		if type(arg) ~= "table" then
			return false, "Bad dev command."
		end
		local request = arg :: { [string]: unknown }
		local name = request.Command
		if type(name) ~= "string" or not commands[name] then
			return false, "Unknown dev command."
		end
		local ok, message = commands[name](player, request.Value)
		core.Sync(player)
		return ok, message and ("[DEV] " .. message) or nil
	end

	core.Hook("PlayerAdded", function(player: Player)
		player:SetAttribute("IsDev", isAuthorized(player))
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("IsDev", isAuthorized(player))
	end
end

return CheatCommands
