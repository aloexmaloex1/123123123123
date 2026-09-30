-- Shared currencies and timed boosts used by several features (codes, daily rewards, store, heists).
-- Adds to core: AddBoost, GetBoostRemaining, AddCredits, HasPass.
local Boosts = { Priority = 1 }

-- Boost kinds and what they multiply while active.
local KINDS = {
	Luck = 2, -- x2 luck
	Income = 2, -- x2 museum income
}

function Boosts.Init(core)
	core.DataService.AddDefaults({
		Boosts = { Luck = 0, Income = 0 }, -- unix time each boost expires
		SecurityCredits = 0,
	})

	-- Stacks: adding time to an active boost extends it.
	function core.AddBoost(player, kind, seconds)
		local data = core.GetData(player)
		if not data or not KINDS[kind] then
			return false
		end
		local now = os.time()
		data.Boosts[kind] = math.max(data.Boosts[kind] or 0, now) + math.floor(seconds)
		core.SyncStats(player)
		return true
	end

	function core.GetBoostRemaining(data, kind)
		return math.max(0, (data.Boosts[kind] or 0) - os.time())
	end

	function core.AddCredits(player, amount)
		local data = core.GetData(player)
		if data then
			data.SecurityCredits = math.max(0, data.SecurityCredits + math.floor(amount))
		end
	end

	-- Game passes are owned by the Store service, which sets "Pass_<Name>" attributes.
	function core.HasPass(player, passName)
		return player:GetAttribute("Pass_" .. passName) == true
	end

	core.Hook("LuckMultiplier", function(_, data)
		return core.GetBoostRemaining(data, "Luck") > 0 and KINDS.Luck or 1
	end)
	core.Hook("IncomeMultiplier", function(_, data)
		return core.GetBoostRemaining(data, "Income") > 0 and KINDS.Income or 1
	end)
	core.Hook("Stats", function(player, data)
		player:SetAttribute("SecurityCredits", data.SecurityCredits)
		player:SetAttribute("BoostLuckUntil", data.Boosts.Luck or 0)
		player:SetAttribute("BoostIncomeUntil", data.Boosts.Income or 0)
	end)
end

return Boosts
