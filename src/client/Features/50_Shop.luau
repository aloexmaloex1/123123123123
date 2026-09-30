-- Coin Shop: permanent museum upgrades with level pips, plus timed Luck / Income potions.
return function(ctx)
	local Config, Theme, player = ctx.Config, ctx.Theme, ctx.player
	local new, label, button, corner, fmt = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.fmt
	local ShopConfig = require(ctx.Shared:WaitForChild("FeatureConfig"):WaitForChild("Shop"))

	local frame, content = ctx.createModal("Shop", "Coin Shop")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

	local live = {} -- { Button, Cost, Maxed, Status?, Boost? } refreshed as coins tick / timers run down
	local coinsLabel

	local function percent(value)
		return ("+%d%%"):format(math.floor(value * 100 + 0.5))
	end

	-- "current -> next" text for an upgrade at `level`.
	local function effectText(id, level)
		local upgrade = ShopConfig.Upgrades[id]
		local maxed = level >= upgrade.Max
		local cur, nxt
		if id == "ExtraPedestal" then
			local slots = player:GetAttribute("DisplaySlots") or (Config.Economy.DisplaySlots + level)
			cur, nxt = ("%d pedestals"):format(slots), ("%d"):format(slots + 1)
			if not maxed and slots >= Config.Economy.MaxDisplaySlots then
				return ("%d pedestals (museum full)"):format(slots)
			end
		elseif id == "VaultStorage" then
			local hours = math.floor((player:GetAttribute("OfflineCapSeconds") or Config.Economy.OfflineCapSeconds) / 3600 + 0.5)
			cur, nxt = ("%dh offline"):format(hours), ("%dh"):format(hours + upgrade.PerLevel)
		else
			local noun = id == "LuckyBrush" and "luck" or "income"
			cur, nxt = ("%s %s"):format(percent(level * upgrade.PerLevel), noun), percent((level + 1) * upgrade.PerLevel)
		end
		if maxed then
			return cur .. "  (max)"
		end
		return cur .. "  →  " .. nxt
	end

	local function card(parent, order, accent)
		return ctx.card({ LayoutOrder = order, Parent = parent }, accent)
	end

	local function buyButton(parent, onClick)
		return button({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.new(1, -20, 0, 38), Text = "", Font = Theme.FontBlack, ZIndex = 6, Parent = parent }, onClick, 18)
	end

	local function styleBuy(entry)
		local b = entry.Button
		if entry.Maxed then
			b.Text = "MAXED"
			b.BackgroundColor3 = Theme.Button
			b.TextColor3 = Theme.GoldLight
			ctx.setEnabled(b, false)
			return
		end
		local affordable = (player:GetAttribute("Coins") or 0) >= entry.Cost
		ctx.setEnabled(b, true)
		if affordable then
			b.Text = ("Buy  ·  %s"):format(fmt(entry.Cost))
			b.BackgroundColor3 = Theme.Gold
			b.TextColor3 = Theme.Dark
		else
			-- Muted but intentional: dark button, price shown in red. Not clickable.
			b.Text = ("Need %s"):format(fmt(entry.Cost))
			b.BackgroundColor3 = Color3.fromRGB(34, 29, 44)
			b.TextColor3 = Theme.Error
			b.AutoButtonColor = false
			b.Active = false
		end
	end

	local function refreshLive()
		if coinsLabel then
			coinsLabel.Text = fmt(player:GetAttribute("Coins") or 0) .. " coins"
		end
		local now = workspace:GetServerTimeNow()
		for _, entry in ipairs(live) do
			styleBuy(entry)
			if entry.Status then
				local left = (player:GetAttribute("Boost" .. entry.Boost .. "Until") or 0) - now
				entry.Status.Text = left > 0 and ("Active  ·  %s left"):format(ctx.duration(left)) or "Not active"
				entry.Status.TextColor3 = left > 0 and Theme.Success or Theme.Muted
			end
		end
	end

	local function section(order, title)
		label({ Size = UDim2.new(1, -8, 0, 24), Text = title, Font = Theme.FontBlack, TextColor3 = Theme.Gold, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, ZIndex = 5, Parent = content }, 18)
		local grid = new("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order + 1, ZIndex = 5, Parent = content })
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 152), CellPadding = UDim2.new(0, 10, 0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		return grid
	end

	ctx.renderers.Shop = function()
		ctx.clear(content)
		table.clear(live)
		local state = ctx.State()
		local levels = state.Upgrades or {}

		local header = new("Frame", { Size = UDim2.new(1, -8, 0, 30), BackgroundTransparency = 1, LayoutOrder = 0, ZIndex = 5, Parent = content })
		ctx.icon("Coin", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(24, 24), Parent = header })
		coinsLabel = label({ Position = UDim2.fromOffset(30, 0), Size = UDim2.new(0.5, -30, 1, 0), Font = Theme.FontBlack, TextColor3 = Theme.Gold, TextXAlignment = Enum.TextXAlignment.Left, Text = "", ZIndex = 5, Parent = header }, 22)
		label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.new(0.5, 0, 1, -8), TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Right, Text = "Upgrades are permanent", ZIndex = 5, Parent = header }, 14)

		local upgradesGrid = section(10, "Museum Upgrades")
		for i, id in ipairs(ShopConfig.UpgradeOrder) do
			local upgrade = ShopConfig.Upgrades[id]
			local level = math.clamp(levels[id] or 0, 0, upgrade.Max)
			local c = card(upgradesGrid, i, level >= upgrade.Max and Theme.Success or nil)
			label({ Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -90, 0, 22), Text = upgrade.Name, Font = Theme.FontBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = c }, 18)
			label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.new(0, 72, 0, 18), Text = ("Lv %d/%d"):format(level, upgrade.Max), Font = Theme.FontBold, TextColor3 = Theme.GoldLight, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5, Parent = c }, 15)
			local pips = new("Frame", { Position = UDim2.new(0, 12, 0, 38), Size = UDim2.new(1, -24, 0, 14), BackgroundTransparency = 1, ZIndex = 5, Parent = c })
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pips })
			for p = 1, upgrade.Max do
				local on = p <= level
				local pip = new("Frame", { Size = UDim2.new(1 / upgrade.Max, -4, 1, 0), BackgroundColor3 = on and Color3.new(1, 1, 1) or Color3.fromRGB(20, 17, 28), BorderSizePixel = 0, LayoutOrder = p, ZIndex = 5, Parent = pips })
				corner(pip, UDim.new(0, 4))
				if on then
					new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Theme.GoldLight, Color3.fromRGB(205, 140, 30)), Parent = pip })
				else
					ctx.stroke(pip, Theme.Muted, 1, 0.75)
				end
			end
			label({ Position = UDim2.new(0, 12, 0, 58), Size = UDim2.new(1, -24, 0, 20), Text = effectText(id, level), Font = Theme.FontBold, TextColor3 = Theme.Success, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = c }, 16)
			label({ Position = UDim2.new(0, 12, 0, 80), Size = UDim2.new(1, -24, 0, 18), Text = upgrade.Blurb, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = c }, 14)
			local cost = ShopConfig.UpgradeCost(id, level)
			local full = id == "ExtraPedestal" and (player:GetAttribute("DisplaySlots") or 0) >= Config.Economy.MaxDisplaySlots
			local entry = { Cost = cost or 0, Maxed = cost == nil or full }
			entry.Button = buyButton(c, function()
				if entry.Button.Active then
					ctx.act("BuyUpgrade", id)
				end
			end)
			table.insert(live, entry)
		end

		local potionsGrid = section(20, "Potions")
		local prices = state.PotionPrices or {}
		for i, id in ipairs(ShopConfig.PotionOrder) do
			local potion = ShopConfig.Potions[id]
			local c = card(potionsGrid, i)
			label({ Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -24, 0, 22), Text = potion.Name, Font = Theme.FontBlack, TextColor3 = potion.Boost == "Luck" and Color3.fromRGB(120, 230, 140) or Theme.GoldLight, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = c }, 18)
			label({ Position = UDim2.new(0, 12, 0, 36), Size = UDim2.new(1, -24, 0, 20), Text = ("%s for %d min"):format(potion.Effect, potion.Seconds // 60), Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = c }, 16)
			local status = label({ Position = UDim2.new(0, 12, 0, 62), Size = UDim2.new(1, -24, 0, 18), Text = "", Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = c }, 15)
			local entry = { Cost = prices[id] or ShopConfig.PotionCost(id, 0), Maxed = false, Status = status, Boost = potion.Boost }
			entry.Button = buyButton(c, function()
				if entry.Button.Active then
					ctx.act("BuyConsumable", id)
				end
			end)
			table.insert(live, entry)
		end
		label({ Size = UDim2.new(1, -8, 0, 18), Text = ("Potion prices scale with your museum income. Stack up to %d hours."):format(ShopConfig.MaxBoostSeconds // 3600), TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 30, ZIndex = 5, Parent = content }, 14)
		refreshLive()
	end

	player:GetAttributeChangedSignal("Coins"):Connect(function()
		if frame.Visible then
			refreshLive()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if frame.Visible then
				refreshLive()
			end
		end
	end)

	ctx.AddMenuButton("Shop", 40, function()
		ctx.openModal("Shop")
	end)
end
