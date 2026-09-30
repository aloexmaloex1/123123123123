-- Store tuning: game passes, developer products and Auto-Dig.
--
-- ALEX: every Id below is 0 until you create the item. In the Creator Dashboard open this experience ->
-- Monetization -> Passes (for Passes) / Developer Products (for Products), create each one with the
-- name, description and price listed here, then paste its numeric id into Id. Items with Id = 0 show
-- "Not set up yet" when bought and are never checked for ownership. PriceRobux is display-only; the
-- real price is whatever you set on the dashboard, so keep the two in sync.
local Store = {}

-- Order = display order in the store. Icon = short glyph drawn on the coloured icon block.
Store.Passes = {
	AutoDig = { Order = 1, Id = 0, PriceRobux = 399, Name = "Auto-Dig", Icon = "AUTO", Color = Color3.fromRGB(230, 170, 60),
		Description = "Digs for you every 3s while you stand at a dig site, and keeps digging while you're offline." },
	DoubleIncome = { Order = 2, Id = 0, PriceRobux = 299, Name = "2x Income", Icon = "2x", Color = Color3.fromRGB(90, 200, 100),
		Description = "Doubles all museum income, online and offline. Forever." },
	ExtraPedestals = { Order = 3, Id = 0, PriceRobux = 249, Name = "Extra Pedestals", Icon = "+4", Color = Color3.fromRGB(70, 150, 255),
		Description = "Adds 4 display pedestals to your museum for more passive income." },
	LuckyScanner = { Order = 4, Id = 0, PriceRobux = 349, Name = "Lucky Scanner", Icon = "LUCK", Color = Color3.fromRGB(80, 220, 200),
		Description = "A relic scanner that nudges every dig toward rarer finds: +10% luck." },
	VIP = { Order = 5, Id = 0, PriceRobux = 199, Name = "VIP", Icon = "VIP", Color = Color3.fromRGB(245, 205, 80),
		Description = "+10% income and a golden VIP title above your head." },
	ExtraHeistEnergy = { Order = 6, Id = 0, PriceRobux = 149, Name = "Extra Heist Energy", Icon = "+E", Color = Color3.fromRGB(220, 70, 80),
		Description = "More heist energy so you can raid rival museums more often." },
}

-- Grant = what the product gives: { Tickets = n } or { Boost = "Luck"|"Income", Seconds = n }.
Store.Products = {
	Tickets50 = { Order = 1, Id = 0, PriceRobux = 49, Name = "50 Dig Tickets", Icon = "50", Color = Color3.fromRGB(222, 196, 140),
		Description = "A satchel of 50 Dig Tickets.", Grant = { Tickets = 50 } },
	Tickets250 = { Order = 2, Id = 0, PriceRobux = 199, Name = "250 Dig Tickets", Icon = "250", Color = Color3.fromRGB(230, 170, 60),
		Description = "A crate of 250 Dig Tickets. Best for steady digging.", Grant = { Tickets = 250 } },
	Tickets1000 = { Order = 3, Id = 0, PriceRobux = 599, Name = "1,000 Dig Tickets", Icon = "1K", Color = Color3.fromRGB(245, 120, 50),
		Description = "A vault of 1,000 Dig Tickets. Best value.", Grant = { Tickets = 1000 } },
	LuckBoost15 = { Order = 4, Id = 0, PriceRobux = 79, Name = "Luck Boost (15 min)", Icon = "x2", Color = Color3.fromRGB(165, 85, 240),
		Description = "Doubles your luck for 15 minutes. Stacks with time already left.", Grant = { Boost = "Luck", Seconds = 15 * 60 } },
	IncomeBoost30 = { Order = 5, Id = 0, PriceRobux = 99, Name = "Income Boost (30 min)", Icon = "x2", Color = Color3.fromRGB(90, 200, 100),
		Description = "Doubles museum income for 30 minutes. Stacks with time already left.", Grant = { Boost = "Income", Seconds = 30 * 60 } },
}

-- Pass effects.
Store.DoubleIncomeMultiplier = 2
Store.VIPIncomeMultiplier = 1.1
Store.ExtraPedestals = 4
Store.LuckyScannerLuck = 1.1

-- Auto-Dig.
Store.AutoDigInterval = 3 -- seconds between automatic rolls
Store.OfflineDigEvery = 300 -- one offline roll per this many seconds away
Store.OfflineDigMax = 100 -- max offline rolls per return

-- Receipts remembered per player to stop double grants.
Store.RecentPurchaseIds = 50

-- Sorted lists for UIs.
local function sorted(map)
	local list = {}
	for key, item in pairs(map) do
		item.Key = key
		table.insert(list, item)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end
Store.PassList = sorted(Store.Passes)
Store.ProductList = sorted(Store.Products)

return Store
