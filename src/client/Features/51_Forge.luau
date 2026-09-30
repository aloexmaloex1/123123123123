-- Shard Forge: melt spare relic copies into Shards, and craft any discovered relic from Shards.
return function(ctx)
	local Config, Theme, player = ctx.Config, ctx.Theme, ctx.player
	local new, label, button, corner, fmt = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.fmt
	local ShopConfig = require(ctx.Shared:WaitForChild("FeatureConfig"):WaitForChild("Shop"))

	local _, content = ctx.createModal("Forge", "Shard Forge")
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

	local function shownCounts(state)
		local counts = {}
		for _, relicId in pairs(state.Displayed or {}) do
			counts[relicId] = (counts[relicId] or 0) + 1
		end
		return counts
	end

	ctx.renderers.Forge = function()
		ctx.clear(content)
		local state = ctx.State()
		local shards = state.Shards or player:GetAttribute("Shards") or 0
		local shown = shownCounts(state)

		local rows, totalSpare, totalGain = {}, 0, 0
		for relicId in pairs(state.Discovered or {}) do
			local relic = Config.RelicsById[relicId]
			if relic then
				local owned = (state.Inventory or {})[relicId] or 0
				local spare = ShopConfig.SpareCount(owned, shown[relicId])
				local value = ShopConfig.GetShardValue(relic.Tier)
				totalSpare += spare
				totalGain += spare * value
				table.insert(rows, { Id = relicId, Relic = relic, Owned = owned, Shown = shown[relicId] or 0, Spare = spare, Value = value })
			end
		end
		table.sort(rows, function(a, b)
			if (a.Spare > 0) ~= (b.Spare > 0) then
				return a.Spare > 0
			end
			if a.Relic.Tier ~= b.Relic.Tier then
				return a.Relic.Tier > b.Relic.Tier
			end
			return a.Relic.Name < b.Relic.Name
		end)

		local header = ctx.card({ Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 0, Parent = content }, Theme.Shard)
		ctx.icon("Shard", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(44, 44), Parent = header })
		label({ Position = UDim2.new(0, 62, 0, 8), Size = UDim2.new(0.5, -66, 0, 16), Text = "SHARDS", Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = header }, 14)
		local shardLabel = label({ Position = UDim2.new(0, 62, 0, 24), Size = UDim2.new(0.5, -66, 0, 32), Text = fmt(shards), Font = Theme.FontBlack, TextColor3 = Theme.Shard, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = header }, 28)
		new("UIStroke", { Color = Color3.fromRGB(40, 16, 70), Thickness = 1.5, Transparency = 0.2, Parent = shardLabel })
		local sellAll = button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0.5, -10, 0, 44),
			Font = Theme.FontBlack,
			Text = totalSpare > 0 and ("Sell all duplicates  ·  +%s"):format(fmt(totalGain)) or "No duplicates to sell",
			BackgroundColor3 = totalSpare > 0 and Theme.Gold or Theme.Button,
			TextColor3 = totalSpare > 0 and Theme.Dark or Theme.Text,
			ZIndex = 6,
			Parent = header,
		}, function()
			if totalSpare > 0 then
				ctx.act("SellDuplicates")
			end
		end, 16)
		ctx.setEnabled(sellAll, totalSpare > 0)

		label({ Size = UDim2.new(1, 0, 0, 38), Text = ("Spare copies (not on display, one always kept) melt into Shards. Craft any relic you've discovered for %dx its shard value."):format(ShopConfig.CraftMultiplier), TextWrapped = true, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, ZIndex = 5, Parent = content }, 14)

		for i, row in ipairs(rows) do
			local rarity = Config.Rarities[row.Relic.Tier]
			local frame = ctx.card({ Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 10 + i, Parent = content }, rarity.Color)
			frame:FindFirstChildOfClass("UIStroke").Transparency = 0.6
			ctx.RelicViewport(frame, row.Id, { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(44, 44), CornerRadius = UDim.new(0, 8), ZIndex = 5 })
			label({ Position = UDim2.new(0, 58, 0, 7), Size = UDim2.new(0.52, -62, 0, 20), Text = row.Relic.Name, Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = frame }, 16)
			label({ Position = UDim2.new(0, 58, 0, 30), Size = UDim2.new(0.52, -62, 0, 18), Text = ("%s  ·  x%d  ·  %d shown"):format(rarity.Name, row.Owned, row.Shown), Font = Theme.FontBold, TextColor3 = rarity.Color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = frame }, 14)

			local sell = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.76, -4, 0.5, 0), Size = UDim2.new(0.24, -6, 0, 36), Text = row.Spare > 0 and ("Sell x%d  +%s"):format(row.Spare, ctx.abbr(row.Spare * row.Value)) or "No spares", ZIndex = 6, Parent = frame }, function()
				if row.Spare > 0 then
					ctx.act("SellDuplicates", row.Id)
				end
			end, 14)
			ctx.setEnabled(sell, row.Spare > 0)

			local cost = ShopConfig.CraftCost(row.Relic.Tier)
			local canCraft = shards >= cost
			local craft = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.new(0.24, -6, 0, 36), Text = ("Craft  ·  %s"):format(ctx.abbr(cost)), BackgroundColor3 = canCraft and Color3.fromRGB(140, 90, 230) or Theme.Button, ZIndex = 6, Parent = frame }, function()
				if canCraft then
					ctx.act("Craft", row.Id)
				end
			end, 14)
			ctx.setEnabled(craft, canCraft)
		end
		if #rows == 0 then
			label({ Size = UDim2.new(1, -8, 0, 22), Text = "Discover relics at the dig sites to forge them here.", TextColor3 = Theme.Muted, LayoutOrder = 10, ZIndex = 5, Parent = content }, 15)
		end
	end

	ctx.AddMenuButton("Forge", 41, function()
		ctx.openModal("Forge")
	end)
end
