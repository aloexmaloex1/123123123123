-- My Relics: what's on your pedestals, your collection, and display / take-down controls.
return function(ctx)
	local Config, Theme, player = ctx.Config, ctx.Theme, ctx.player
	local new, label, button, corner, fmt = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.fmt
	local Left = Enum.TextXAlignment.Left

	local _, content = ctx.createModal("MyRelics", "My Relics")
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

	local function relicRow(order, relicId, detail, buttonText, onClick, enabled, primary)
		local relic = Config.RelicsById[relicId]
		local rarity = Config.Rarities[relic.Tier]
		local row = ctx.card({ Size = UDim2.new(1, 0, 0, 58), LayoutOrder = order, Parent = content }, rarity.Color)
		row:FindFirstChildOfClass("UIStroke").Transparency = 0.55
		ctx.RelicViewport(row, relicId, { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(46, 46), CornerRadius = UDim.new(0, 8), ZIndex = 5 })
		label({ Position = UDim2.new(0, 62, 0, 7), Size = UDim2.new(0.68, -66, 0, 22), Text = relic.Name, Font = Theme.FontBold, TextXAlignment = Left, ZIndex = 5, Parent = row }, 17)
		label({ Position = UDim2.new(0, 62, 0, 31), Size = UDim2.new(0.68, -66, 0, 18), Text = rarity.Name .. "  ·  " .. detail, Font = Theme.FontBold, TextColor3 = rarity.Color, TextXAlignment = Left, ZIndex = 5, Parent = row }, 14)
		local b = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0.28, 0, 0, 36), Text = buttonText, BackgroundColor3 = primary and Theme.Gold or Theme.Button, TextColor3 = primary and Theme.Dark or Theme.Text, ZIndex = 6, Parent = row }, onClick, 16)
		ctx.setEnabled(b, enabled)
	end

	local function sectionTitle(order, text)
		label({ Size = UDim2.new(1, 0, 0, 28), Text = text, Font = Theme.FontBlack, TextColor3 = Theme.Gold, TextXAlignment = Left, LayoutOrder = order, ZIndex = 5, Parent = content }, 19)
	end

	ctx.renderers.MyRelics = function()
		ctx.clear(content)
		local state = ctx.State()
		local slots = player:GetAttribute("DisplaySlots") or Config.Economy.DisplaySlots
		local shownCount, shownById = 0, {}
		for slot, relicId in pairs(state.Displayed) do
			if tonumber(slot) <= slots then
				shownCount += 1
			end
			shownById[relicId] = (shownById[relicId] or 0) + 1
		end

		local header = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 0, ZIndex = 5, Parent = content })
		label({ Size = UDim2.new(0.66, 0, 0, 24), Text = ("Pedestals used  %d / %d"):format(shownCount, slots), Font = Theme.FontBlack, TextColor3 = Theme.GoldLight, TextXAlignment = Left, ZIndex = 5, Parent = header }, 20)
		local incomeRow = new("Frame", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(0.66, 0, 0, 16), BackgroundTransparency = 1, ZIndex = 5, Parent = header })
		ctx.icon("Coin", { Size = UDim2.fromOffset(16, 16), Parent = incomeRow })
		label({ Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 1, 0), Text = ("+%s coins/min from your museum"):format(fmt(player:GetAttribute("IncomePerMin") or 0)), Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Left, ZIndex = 5, Parent = incomeRow }, 14)
		button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.new(0.3, 0, 0, 36), Text = "Auto-arrange", Font = Theme.FontBlack, BackgroundColor3 = Theme.Gold, TextColor3 = Theme.Dark, ZIndex = 6, Parent = header }, function()
			ctx.act("AutoDisplay")
		end, 16)

		local order = 1
		for slot = 1, Config.Economy.MaxDisplaySlots do
			local relicId = state.Displayed[tostring(slot)]
			if relicId and Config.RelicsById[relicId] then
				relicRow(order, relicId, ("Pedestal %d  ·  +%s/min"):format(slot, fmt(Config.GetIncome(relicId))), "Take down", function()
					ctx.act("Undisplay", slot)
				end, true)
				order += 1
			end
		end
		if shownCount == 0 then
			label({ Size = UDim2.new(1, 0, 0, 22), Text = "Nothing on display yet. Put a relic on a pedestal to earn coins.", TextColor3 = Theme.Muted, TextXAlignment = Left, LayoutOrder = order, ZIndex = 5, Parent = content }, 15)
		end

		sectionTitle(500, "Collection")
		local owned = {}
		for relicId, count in pairs(state.Inventory) do
			if count > 0 and Config.RelicsById[relicId] then
				table.insert(owned, relicId)
			end
		end
		table.sort(owned, function(a, b)
			local ta, tb = Config.RelicsById[a].Tier, Config.RelicsById[b].Tier
			if ta ~= tb then
				return ta > tb
			end
			return Config.RelicsById[a].Name < Config.RelicsById[b].Name
		end)
		local full = shownCount >= slots
		for i, relicId in ipairs(owned) do
			local count = state.Inventory[relicId]
			local shown = shownById[relicId] or 0
			local canShow = count > shown and not full
			relicRow(500 + i, relicId, ("x%d owned, %d shown  ·  +%s/min"):format(count, shown, fmt(Config.GetIncome(relicId))), canShow and "Display" or (full and "Museum full" or "All shown"), function()
				ctx.act("Display", relicId)
			end, canShow, canShow)
		end
		if #owned == 0 then
			label({ Size = UDim2.new(1, 0, 0, 22), Text = "Excavate at a dig site to start your collection.", TextColor3 = Theme.Muted, TextXAlignment = Left, LayoutOrder = 501, ZIndex = 5, Parent = content }, 15)
		end
	end

	ctx.AddMenuButton("My Relics", 30, function()
		ctx.openModal("MyRelics")
	end)
end
