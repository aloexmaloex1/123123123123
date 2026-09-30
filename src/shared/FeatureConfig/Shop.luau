-- Tuning for the coin shop (upgrades + potions), the shard forge and collection rewards.
-- Shared by Services.Shop / Forge / Collections and the client Shop / Forge / Collections screens.
local Shop = {}

-- Permanent upgrades, bought with coins. Cost of the next level = Base * Growth ^ currentLevel (rounded).
-- Balanced against 1-3,000 coins/min per displayed relic on 8 base pedestals (roughly 8/min early, 24K/min endgame).
Shop.UpgradeOrder = { "ExtraPedestal", "VaultStorage", "LuckyBrush", "Marketing" }
Shop.Upgrades = {
	ExtraPedestal = { Name = "Extra Pedestal", Max = 8, BaseCost = 750, Growth = 2.6, PerLevel = 1, Blurb = "+1 display pedestal per level" },
	VaultStorage = { Name = "Vault Storage", Max = 12, BaseCost = 400, Growth = 1.9, PerLevel = 1, Blurb = "+1 hour of offline earnings per level" },
	LuckyBrush = { Name = "Lucky Brush", Max = 10, BaseCost = 1000, Growth = 2.1, PerLevel = 0.05, Blurb = "+5% luck per level" },
	Marketing = { Name = "Marketing", Max = 10, BaseCost = 800, Growth = 2.0, PerLevel = 0.05, Blurb = "+5% museum income per level" },
}

-- Timed potions. Price = max(MinCost, base museum income per minute * IncomeMinutes), so they stay a
-- meaningful coin sink late game. Boost strength (x2) is defined by Services/Boosts.
Shop.PotionOrder = { "LuckPotion", "IncomePotion" }
Shop.Potions = {
	LuckPotion = { Name = "Luck Potion", Boost = "Luck", Seconds = 15 * 60, MinCost = 2500, IncomeMinutes = 10, Effect = "x2 luck" },
	IncomePotion = { Name = "Income Potion", Boost = "Income", Seconds = 30 * 60, MinCost = 2000, IncomeMinutes = 15, Effect = "x2 museum income" },
}
Shop.MaxBoostSeconds = 2 * 60 * 60 -- can't stack a boost beyond this with coin potions

-- Forge: spare copies (owned - on display - 1 kept) melt into shards; crafting costs CraftMultiplier x the tier's value.
Shop.ShardValue = { 1, 2, 5, 12, 30, 75, 180, 450, 1000, 3000 }
Shop.CraftMultiplier = 10

-- Rounds to two significant figures so prices read cleanly (1,950 / 13,000 / 600,000).
function Shop.Nice(n)
	n = math.max(0, n)
	if n < 100 then
		return math.floor(n + 0.5)
	end
	local magnitude = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / magnitude + 0.5) * magnitude
end

-- Cost of buying the next level, or nil when maxed / unknown.
function Shop.UpgradeCost(id, level)
	local upgrade = Shop.Upgrades[id]
	level = level or 0
	if not upgrade or level >= upgrade.Max then
		return nil
	end
	return Shop.Nice(upgrade.BaseCost * upgrade.Growth ^ level)
end

function Shop.PotionCost(id, baseIncomePerMinute)
	local potion = Shop.Potions[id]
	if not potion then
		return nil
	end
	return Shop.Nice(math.max(potion.MinCost, (baseIncomePerMinute or 0) * potion.IncomeMinutes))
end

function Shop.GetShardValue(tier)
	return Shop.ShardValue[tier] or 0
end

function Shop.CraftCost(tier)
	return Shop.GetShardValue(tier) * Shop.CraftMultiplier
end

-- Copies that can be melted: everything not on a pedestal, keeping one in the collection.
function Shop.SpareCount(owned, displayed)
	return math.max(0, (owned or 0) - (displayed or 0) - 1)
end

return Shop
