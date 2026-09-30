-- Coin shop: permanent museum upgrades (pedestals, vault, luck, marketing) and timed potions.
-- Actions: BuyUpgrade(upgradeId), BuyConsumable(potionId). Snapshot: Upgrades, PotionPrices.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.RelicRNG:WaitForChild("FeatureConfig"):WaitForChild("Shop"))

local Shop = {}

function Shop.Init(core)
	local Config = core.Config
	local Upgrades = ShopConfig.Upgrades

	local defaults = {}
	for _, id in ipairs(ShopConfig.UpgradeOrder) do
		defaults[id] = 0
	end
	core.DataService.AddDefaults({ Upgrades = defaults })

	local function levelOf(data, id)
		local level = tonumber(data.Upgrades and data.Upgrades[id]) or 0
		return math.clamp(math.floor(level), 0, Upgrades[id].Max)
	end

	core.Hook("DisplaySlots", function(_, data)
		return levelOf(data, "ExtraPedestal") * Upgrades.ExtraPedestal.PerLevel
	end)
	core.Hook("OfflineSeconds", function(_, data)
		return levelOf(data, "VaultStorage") * Upgrades.VaultStorage.PerLevel * 3600
	end)
	core.Hook("LuckMultiplier", function(_, data)
		return 1 + levelOf(data, "LuckyBrush") * Upgrades.LuckyBrush.PerLevel
	end)
	core.Hook("IncomeMultiplier", function(_, data)
		return 1 + levelOf(data, "Marketing") * Upgrades.Marketing.PerLevel
	end)

	core.Hook("Snapshot", function(player, data, snapshot)
		local levels = {}
		for _, id in ipairs(ShopConfig.UpgradeOrder) do
			levels[id] = levelOf(data, id)
		end
		snapshot.Upgrades = levels
		local baseIncome = core.GetBaseIncome(player, data)
		local prices = {}
		for _, id in ipairs(ShopConfig.PotionOrder) do
			prices[id] = ShopConfig.PotionCost(id, baseIncome)
		end
		snapshot.PotionPrices = prices
	end)

	function core.Actions.BuyUpgrade(player, id)
		local data = core.GetData(player)
		if type(id) ~= "string" or not Upgrades[id] then
			return false, "Unknown upgrade."
		end
		local upgrade = Upgrades[id]
		local level = levelOf(data, id)
		local cost = ShopConfig.UpgradeCost(id, level)
		if not cost then
			return false, upgrade.Name .. " is already maxed."
		end
		if id == "ExtraPedestal" and core.GetDisplaySlots(player, data) >= Config.Economy.MaxDisplaySlots then
			return false, "Your museum has no room for more pedestals."
		end
		if data.Coins < cost then
			return false, ("You need %s coins."):format(Config.FormatNumber(cost))
		end
		data.Coins -= cost
		data.Upgrades[id] = level + 1
		if id == "ExtraPedestal" then
			core.RefreshMuseum(player)
		end
		core.Sync(player)
		return true, ("%s upgraded to level %d!"):format(upgrade.Name, level + 1)
	end

	function core.Actions.BuyConsumable(player, id)
		local data = core.GetData(player)
		local potion = type(id) == "string" and ShopConfig.Potions[id]
		if not potion then
			return false, "Unknown item."
		end
		if not core.AddBoost or not core.GetBoostRemaining then
			return false, "Potions are unavailable right now."
		end
		if core.GetBoostRemaining(data, potion.Boost) + potion.Seconds > ShopConfig.MaxBoostSeconds then
			return false, ("You can stack at most %d hours of %s."):format(ShopConfig.MaxBoostSeconds // 3600, potion.Name)
		end
		local cost = ShopConfig.PotionCost(id, core.GetBaseIncome(player, data))
		if data.Coins < cost then
			return false, ("You need %s coins."):format(Config.FormatNumber(cost))
		end
		data.Coins -= cost
		core.AddBoost(player, potion.Boost, potion.Seconds)
		core.Sync(player)
		return true, ("%s active: %s for %d minutes!"):format(potion.Name, potion.Effect, potion.Seconds // 60)
	end
end

return Shop
