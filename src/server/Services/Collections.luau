-- Collections: one-time rewards for completing a Config.Sets set (set bonuses themselves are applied by core).
-- Action: ClaimSet(setId). Snapshot: ClaimedSets.
local Collections = {}

function Collections.Init(core)
	local Config = core.Config
	core.DataService.AddDefaults({ ClaimedSets = {} })

	local setsById = {}
	for _, set in ipairs(Config.Sets) do
		setsById[set.Id] = set
	end

	core.Hook("Snapshot", function(_, data, snapshot)
		snapshot.ClaimedSets = data.ClaimedSets
	end)

	-- Grants a set reward table; returns a readable summary.
	local function grant(player, data, reward)
		local parts = {}
		if reward.Tickets then
			core.AddTickets(player, reward.Tickets)
			table.insert(parts, Config.FormatNumber(reward.Tickets) .. " Dig Tickets")
		end
		if reward.Coins then
			core.AddCoins(player, reward.Coins, false)
			table.insert(parts, Config.FormatNumber(reward.Coins) .. " coins")
		end
		if reward.Shards then
			data.Shards = (data.Shards or 0) + reward.Shards
			table.insert(parts, Config.FormatNumber(reward.Shards) .. " Shards")
		end
		if reward.SecurityCredits and core.AddCredits then
			core.AddCredits(player, reward.SecurityCredits)
			table.insert(parts, Config.FormatNumber(reward.SecurityCredits) .. " Security Credits")
		end
		if reward.Relic and Config.RelicsById[reward.Relic] then
			core.GrantRelic(player, reward.Relic, 1)
			table.insert(parts, Config.RelicsById[reward.Relic].Name)
		end
		return table.concat(parts, ", ")
	end

	function core.Actions.ClaimSet(player, setId)
		local data = core.GetData(player)
		local set = type(setId) == "string" and setsById[setId]
		if not set then
			return false, "Unknown collection."
		end
		if data.ClaimedSets[setId] then
			return false, "You already claimed this reward."
		end
		if not core.IsSetComplete(data, set) then
			return false, "Own every relic in " .. set.Name .. " first."
		end
		data.ClaimedSets[setId] = true
		local summary = grant(player, data, set.Reward or {})
		core.Sync(player)
		return true, ("%s complete! Claimed %s."):format(set.Name, summary ~= "" and summary or "your reward")
	end
end

return Collections
