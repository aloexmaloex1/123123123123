-- Shard forge: melt spare relic copies into Shards and craft discovered relics from them.
-- Actions: SellDuplicates(relicId or nil for all), Craft(relicId). Attribute: Shards. Snapshot: Shards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.RelicRNG:WaitForChild("FeatureConfig"):WaitForChild("Shop"))

local Forge = {}

function Forge.Init(core)
	local Config = core.Config
	core.DataService.AddDefaults({ Shards = 0 })

	local function displayedCounts(data)
		local counts = {}
		for _, relicId in pairs(data.Displayed) do
			counts[relicId] = (counts[relicId] or 0) + 1
		end
		return counts
	end

	-- Removes every spare copy of relicId; returns copies sold and shards gained.
	local function melt(data, relicId, shown)
		local spare = ShopConfig.SpareCount(data.Inventory[relicId], shown)
		if spare <= 0 then
			return 0, 0
		end
		data.Inventory[relicId] -= spare
		return spare, spare * ShopConfig.GetShardValue(Config.RelicsById[relicId].Tier)
	end

	core.Hook("Stats", function(player, data)
		player:SetAttribute("Shards", data.Shards)
	end)
	core.Hook("Snapshot", function(_, data, snapshot)
		snapshot.Shards = data.Shards
	end)

	function core.Actions.SellDuplicates(player, relicId)
		local data = core.GetData(player)
		local shown = displayedCounts(data)
		local sold, gained = 0, 0
		if relicId == nil then
			for id in pairs(data.Inventory) do
				if Config.RelicsById[id] then
					local copies, shards = melt(data, id, shown[id])
					sold += copies
					gained += shards
				end
			end
		elseif type(relicId) == "string" and Config.RelicsById[relicId] then
			sold, gained = melt(data, relicId, shown[relicId])
		else
			return false, "Unknown relic."
		end
		if sold == 0 then
			return false, "No spare copies to melt down."
		end
		data.Shards += gained
		core.Sync(player)
		return true, ("Melted %d spare cop%s into %s Shards."):format(sold, sold == 1 and "y" or "ies", Config.FormatNumber(gained))
	end

	function core.Actions.Craft(player, relicId)
		local data = core.GetData(player)
		local relic = type(relicId) == "string" and Config.RelicsById[relicId]
		if not relic then
			return false, "Unknown relic."
		end
		if not data.Discovered[relicId] then
			return false, "Discover this relic before you can craft it."
		end
		local cost = ShopConfig.CraftCost(relic.Tier)
		if data.Shards < cost then
			return false, ("You need %s Shards."):format(Config.FormatNumber(cost))
		end
		data.Shards -= cost
		core.GrantRelic(player, relicId, 1)
		core.Sync(player)
		return true, ("Forged a %s!"):format(relic.Name)
	end
end

return Forge
