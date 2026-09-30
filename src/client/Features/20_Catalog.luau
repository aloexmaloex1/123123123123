-- Relic Catalog: every relic per dig site, found or not, with a 3D thumbnail, its odds and how many you own.
return function(ctx)
	local Config, Theme = ctx.Config, ctx.Theme
	local new, label, button, corner = ctx.new, ctx.label, ctx.button, ctx.corner

	local _, content, title = ctx.createModal("Catalog", "Relic Catalog")
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	local selected = "DustyDunes"
	local GAP = 8

	local function columnsFor(width)
		if width >= 600 then
			return 4
		elseif width >= 430 then
			return 3
		end
		return 2
	end

	ctx.renderers.Catalog = function()
		ctx.clear(content)
		local state = ctx.State()
		local foundTotal = 0
		for _, relic in ipairs(Config.Relics) do
			if state.Discovered[relic.Id] then
				foundTotal += 1
			end
		end
		title.Text = ("Relic Catalog  ·  %d/%d found"):format(foundTotal, #Config.Relics)

		local tabs = new("Frame", { Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1, LayoutOrder = 0, ZIndex = 5, Parent = content })
		new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, 34), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabs })
		for i, siteId in ipairs(Config.DigSiteOrder) do
			local site = Config.DigSites[siteId]
			local found, total = 0, #Config.RelicsBySite[siteId]
			for _, relic in ipairs(Config.RelicsBySite[siteId]) do
				if state.Discovered[relic.Id] then
					found += 1
				end
			end
			local isSelected = siteId == selected
			local tab = button({ Text = ("%s  %d/%d"):format(site.Name, found, total), LayoutOrder = i, ZIndex = 6, BackgroundColor3 = isSelected and site.Color or Theme.Button, TextColor3 = isSelected and Theme.Dark or (found > 0 and Theme.Text or Theme.Muted), Parent = tabs }, function()
				selected = siteId
				ctx.renderers.Catalog()
			end, 15)
			local s = tab:FindFirstChildOfClass("UIStroke")
			s.Color = site.Color
			s.Transparency = isSelected and 0 or 0.35
		end

		local width = content.AbsoluteWindowSize.X - 14
		local cols = columnsFor(width)
		local grid = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 5, Parent = content })
		new("UIGridLayout", { CellSize = UDim2.new(1 / cols, -GAP * (cols - 1) / cols, 0, 176), CellPadding = UDim2.new(0, GAP, 0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for index, relic in ipairs(Config.RelicsBySite[selected]) do
			local rarity = Config.Rarities[relic.Tier]
			local known = state.Discovered[relic.Id]
			local owned = state.Inventory[relic.Id] or 0
			local cell = ctx.card({ LayoutOrder = index, Parent = grid }, known and rarity.Color or Theme.Muted)
			if not known then
				cell:FindFirstChildOfClass("UIStroke").Transparency = 0.7
			end
			ctx.RelicViewport(cell, relic.Id, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, -16, 0, 90), Silhouette = not known, ZIndex = 5 })
			if owned > 0 then
				local badge = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(38, 20), BackgroundColor3 = Color3.fromRGB(14, 11, 20), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 8, Parent = cell })
				corner(badge, UDim.new(1, 0))
				label({ Size = UDim2.fromScale(1, 1), Text = "x" .. owned, Font = Theme.FontBlack, ZIndex = 9, Parent = badge }, 14)
			end
			label({ Position = UDim2.new(0, 8, 0, 102), Size = UDim2.new(1, -16, 0, 20), Text = known and relic.Name or "???", Font = Theme.FontBold, TextColor3 = known and Theme.Text or Theme.Muted, ZIndex = 5, Parent = cell }, 16)
			label({ Position = UDim2.new(0, 8, 0, 124), Size = UDim2.new(1, -16, 0, 18), Text = rarity.Name, TextColor3 = rarity.Color, Font = Theme.FontBlack, ZIndex = 5, Parent = cell }, 15)
			label({ Position = UDim2.new(0, 8, 0, 146), Size = UDim2.new(1, -16, 0, 18), Text = ctx.oneIn(Config.GetRelicChance(relic.Id, Config.DigSites[relic.Site].Luck)), TextColor3 = Theme.Muted, ZIndex = 5, Parent = cell }, 14)
		end
	end

	ctx.AddMenuButton("Catalog", 20, function()
		ctx.openModal("Catalog")
	end)
end
