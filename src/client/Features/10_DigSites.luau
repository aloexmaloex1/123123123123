-- Dig Sites panel: pick a site, see its odds at your current luck, and travel there.
return function(ctx)
	local Config, Theme, player = ctx.Config, ctx.Theme, ctx.player
	local new, label, button, corner, fmt = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.fmt
	local Left = Enum.TextXAlignment.Left

	local SITE_GLYPHS = {
		DustyDunes = "🏜️",
		SunkenVault = "🌊",
		FrozenReliquary = "❄️",
		MeteorCrater = "☄️",
		HauntedBazaar = "👻",
		CelestialRuins = "✨",
	}

	local frame, content = ctx.createModal("DigSites", "Dig Sites")
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	local selected = "DustyDunes"

	local function oddsRow(order, cells, color, header)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Theme.PanelLight, BackgroundTransparency = header and 1 or 0.35, LayoutOrder = order, ZIndex = 5, Parent = content })
		corner(row, UDim.new(0, 6))
		local widths = { 0.34, 0.2, 0.22, 0.24 }
		local x = 0
		for i, text in ipairs(cells) do
			local inset = (i == 1 and not header) and 30 or 10
			label({ Position = UDim2.new(x, inset, 0, 0), Size = UDim2.new(widths[i], -inset - 4, 1, 0), Text = text, TextXAlignment = Left, Font = (header or i == 1) and Theme.FontBold or Theme.Font, TextColor3 = (i == 1 and color) or (header and Theme.Gold) or Theme.Text, ZIndex = 5, Parent = row }, header and 14 or 16)
			x += widths[i]
		end
		if not header then
			local swatch = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 6, Parent = row })
			corner(swatch, UDim.new(0, 4))
		end
	end

	ctx.renderers.DigSites = function()
		ctx.clear(content)
		local level = player:GetAttribute("Level") or 1
		local personalLuck = player:GetAttribute("Luck") or 1

		local tabs = new("Frame", { Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1, LayoutOrder = 0, ZIndex = 5, Parent = content })
		new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, 34), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabs })
		for i, siteId in ipairs(Config.DigSiteOrder) do
			local site = Config.DigSites[siteId]
			local unlocked = level >= site.Level
			local isSelected = siteId == selected
			local text = unlocked and site.Name or ("🔒 " .. site.Name .. "  Lv " .. site.Level)
			local tab = button({ Text = text, LayoutOrder = i, ZIndex = 6, BackgroundColor3 = isSelected and site.Color or Theme.Button, TextColor3 = isSelected and Theme.Dark or (unlocked and Theme.Text or Theme.Disabled), Parent = tabs }, function()
				selected = siteId
				ctx.renderers.DigSites()
			end, 15)
			local s = tab:FindFirstChildOfClass("UIStroke")
			s.Color = unlocked and site.Color or Theme.Disabled
			s.Transparency = isSelected and 0 or (unlocked and 0.3 or 0.7)
			if not unlocked and not isSelected then
				tab.BackgroundTransparency = 0.5
			end
		end

		local site = Config.DigSites[selected]
		local unlocked = level >= site.Level
		local totalLuck = site.Luck * personalLuck
		local info = ctx.card({ Size = UDim2.new(1, 0, 0, 104), LayoutOrder = 1, Parent = content }, site.Color)
		local emblem = new("Frame", { Position = UDim2.fromOffset(12, 14), Size = UDim2.fromOffset(76, 76), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 5, Parent = info })
		corner(emblem, UDim.new(0, 12))
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ctx.lighten(site.Color, 0.1), ctx.darken(site.Color, 0.55)), Parent = emblem })
		ctx.stroke(emblem, ctx.lighten(site.Color, 0.4), 1.5, 0.3)
		label({ Size = UDim2.fromScale(1, 1), Text = unlocked and (SITE_GLYPHS[selected] or "⛏️") or "🔒", Font = Theme.FontBlack, ZIndex = 6, Parent = emblem }, 40)
		label({ Position = UDim2.new(0, 100, 0, 8), Size = UDim2.new(0.7, -110, 0, 26), Text = site.Name, Font = Theme.FontBlack, TextColor3 = site.Color, TextXAlignment = Left, ZIndex = 5, Parent = info }, 22)
		label({ Position = UDim2.new(0, 100, 0, 36), Size = UDim2.new(0.7, -110, 0, 36), Text = site.Blurb, TextColor3 = Theme.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Left, ZIndex = 5, Parent = info }, 14)
		label({ Position = UDim2.new(0, 100, 0, 76), Size = UDim2.new(0.7, -110, 0, 18), Text = ("%d ticket%s  ·  site luck x%.1f  ·  you x%.2f"):format(site.TicketCost, site.TicketCost == 1 and "" or "s", site.Luck, totalLuck), Font = Theme.FontBold, TextXAlignment = Left, ZIndex = 5, Parent = info }, 14)
		local travel = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0.26, 0, 0, 48), Text = unlocked and "Travel" or ("🔒 Lv " .. site.Level), Font = Theme.FontBlack, BackgroundColor3 = unlocked and Theme.Gold or Theme.Button, TextColor3 = unlocked and Theme.Dark or Theme.Muted, ZIndex = 6, Parent = info }, function()
			if unlocked then
				local ok = ctx.act("Teleport", selected)
				if ok then
					frame.Visible = false
				end
			end
		end, 20)
		ctx.setEnabled(travel, unlocked)

		oddsRow(2, { "Rarity", "Chance", "Odds", "Income" }, Theme.Gold, true)
		local chances = Config.GetTierChances(totalLuck)
		for tier, rarity in ipairs(Config.Rarities) do
			oddsRow(2 + tier, { rarity.Name, ctx.percent(chances[tier]), ctx.oneIn(chances[tier]), "+" .. fmt(rarity.Income) .. "/min" }, rarity.Color)
		end
		local lines = { "Pity guarantees (shared across all sites):" }
		for _, rule in ipairs(Config.Pity) do
			table.insert(lines, ("  •  %d rolls without one: %s or better"):format(rule.Every, Config.Rarities[rule.MinTier].Name))
		end
		label({ Size = UDim2.new(1, 0, 0, 100), Text = table.concat(lines, "\n"), TextXAlignment = Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Theme.Muted, LayoutOrder = 50, ZIndex = 5, Parent = content }, 16)
	end

	ctx.AddMenuButton("Dig Sites", 10, function()
		local here = ctx.CurrentSite()
		if here then
			selected = here
		end
		ctx.openModal("DigSites")
	end)
	ctx.AddMenuButton("My Museum", 15, function()
		ctx.act("Teleport", "Museum")
	end)
end
