-- Daily login rewards: claim once every 20 hours for a 7-day escalating streak (resets after 48 hours).
-- Tuning and streak maths live in ReplicatedStorage.RelicRNG.FeatureConfig.Daily; rewards are granted
-- through core.GrantRewards from the Codes service.
local Daily = { Priority = 41 }

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return ("%dh %dm"):format(seconds // 3600, (seconds % 3600) // 60)
	elseif seconds >= 60 then
		return ("%dm %ds"):format(seconds // 60, seconds % 60)
	end
	return seconds .. "s"
end

function Daily.Init(core)
	local DailyConfig = require(core.Shared:WaitForChild("FeatureConfig"):WaitForChild("Daily"))

	core.DataService.AddDefaults({
		Daily = { Streak = 0, LastClaim = 0 }, -- consecutive claims, unix time of the last claim
	})

	local function getStatus(data)
		return DailyConfig.GetStatus(data.Daily.Streak, data.Daily.LastClaim, os.time())
	end

	function core.Actions.ClaimDaily(player)
		local data = core.GetData(player)
		local status = getStatus(data)
		if not status.Claimable then
			return false, "Your next daily reward is ready in " .. formatDuration(status.ReadyAt - os.time()) .. "."
		end
		if not core.GrantRewards then
			return false, "Daily rewards are unavailable right now."
		end
		data.Daily.Streak = status.Streak + 1
		data.Daily.LastClaim = os.time()
		local _, parts = core.GrantRewards(player, DailyConfig.Days[status.Day], "DAILY REWARD")
		core.FireClient(player, "Daily", "Claimed", status.Day)
		return true, ("Day %d reward claimed! %s"):format(status.Day, table.concat(parts, ", "))
	end

	core.Hook("Stats", function(player, data)
		local status = getStatus(data)
		player:SetAttribute("DailyReadyAt", status.ReadyAt) -- unix; claimable when <= now (0 = never claimed)
		player:SetAttribute("DailyStreak", status.Streak) -- current streak after any reset
		player:SetAttribute("DailyResetAt", status.ResetAt) -- unix the streak breaks if unclaimed (0 = no streak)
	end)

	core.Hook("PlayerAdded", function(_, profile, greeting)
		local status = getStatus(profile.Data)
		if status.Claimable then
			greeting.Extra = greeting.Extra or {}
			local line = ("Your daily reward is ready! Open Daily to claim Day %d."):format(status.Day)
			if status.Broken then
				line ..= " (Your streak reset, so it starts again from Day 1.)"
			end
			table.insert(greeting.Extra, line)
		end
	end)
end

return Daily
