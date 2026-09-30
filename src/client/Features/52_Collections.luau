-- Collections: every relic set, its progress, the bonus it grants while complete and a one-time reward.
return function(ctx)
	local Config, Theme = ctx.Config, ctx.Theme
	local new, label, button, corner, fmt = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.fmt

	local _, content = ctx.createModal("Collections", "Collections")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

	local CHIP_HEIGHT, CHIP_GAP = 38, 6

	local function bonusText(bonus)
		local parts = {}
		if bonus.Income then
			table.insert(parts, ("+%d%% income"):format(math.floor(bonus.Income * 100 + 0.5)))
		end
		if bonus.Luck then
			table.insert(parts, ("+%d%% luck"):format(math.floor(bonus.Luck * 100 + 0.5)))
		end
		if bonus.OfflineHours then
			table.insert(parts, ("+%sh offline cap"):format(bonus.OfflineHours))
		end
		if bonus.HeistSeconds then
			table.insert(parts, ("+%ds heist time"):format(bonus.HeistSeconds))
		end
		return table.concat(parts, ", ")
	end

	local function rewardText(reward)
		local parts = {}
		if reward.Tickets then
			table.insert(parts, fmt(reward.Tickets) .. " Tickets")
		end
		if reward.Coins then
			table.insert(parts, fmt(reward.Coins) .. " Coins")
		end
		if reward.Shards then
			table.insert(parts, fmt(reward.Shards) .. " Shards")
		end
		if reward.SecurityCredits then
			table.insert(parts, fmt(reward.SecurityCredits) .. " Credits")
		end
		if reward.Relic and Config.RelicsById[reward.Relic] then
			table.insert(parts, Config.RelicsById[reward.Relic].Name)
		end
		return table.concat(parts, " + ")
	end

	-- Small green check drawn on the thumbnail's corner for owned relics.
	local function tick(parent, owned)
		if not owned then
			return
		end
		local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 36, 1, -8), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Theme.Success, BorderSizePixel = 0, ZIndex = 9, Parent = parent })
		corner(box, UDim.new(1, 0))
		ctx.stroke(box, Theme.Dark, 1.5, 0)
		do
			-- A drawn check mark, so it never depends on font glyph support.
			new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(5, 9), Size = UDim2.fromOffset(6, 2), Rotation = 45, BackgroundColor3 = Theme.Dark, BorderSizePixel = 0, ZIndex = 10, Parent = box })
			new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(9, 7), Size = UDim2.fromOffset(9, 2), Rotation = -50, BackgroundColor3 = Theme.Dark, BorderSizePixel = 0, ZIndex = 10, Parent = box })
		end
	end

	ctx.renderers.Collections = function()
		ctx.clear(content)
		local state = ctx.State()
		local inventory, discovered, claimed = state.Inventory or {}, state.Discovered or {}, state.ClaimedSets or {}

		local completeCount = 0
		for _, set in ipairs(Config.Sets) do
			local complete = true
			for _, relicId in ipairs(set.Relics) do
				if (inventory[relicId] or 0) < 1 then
					complete = false
				end
			end
			if complete then
				completeCount += 1
			end
		end
		label({ Size = UDim2.new(1, 0, 0, 22), Text = ("%d/%d sets complete  ·  own every relic in a set to activate its bonus"):format(completeCount, #Config.Sets), TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, ZIndex = 5, Parent = content }, 15)

		for i, set in ipairs(Config.Sets) do
			local found, complete = 0, true
			for _, relicId in ipairs(set.Relics) do
				if (inventory[relicId] or 0) > 0 then
					found += 1
				else
					complete = false
				end
			end
			local isClaimed = claimed[set.Id] == true
			local rows = math.ceil(#set.Relics / 2)
			local chipsHeight = rows * (CHIP_HEIGHT + CHIP_GAP) - CHIP_GAP

			local card = ctx.card({ Size = UDim2.new(1, 0, 0, 64 + chipsHeight + 56), LayoutOrder = i, Parent = content }, complete and Theme.Gold or nil)
			if complete then
				card:FindFirstChildOfClass("UIStroke").Thickness = 2
			end

			label({ Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -124, 0, 24), Text = set.Name, Font = Theme.FontBlack, TextColor3 = complete and Theme.Gold or Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = card }, 20)
			if complete then
				local badge = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 9), Size = UDim2.fromOffset(96, 24), BackgroundColor3 = Theme.Gold, BorderSizePixel = 0, ZIndex = 6, Parent = card })
				corner(badge, UDim.new(1, 0))
				label({ Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), Text = "ACTIVE", Font = Theme.FontBlack, TextColor3 = Theme.Dark, ZIndex = 7, Parent = badge }, 14)
			else
				label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 11), Size = UDim2.fromOffset(100, 20), Text = ("%d/%d owned"):format(found, #set.Relics), Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5, Parent = card }, 15)
			end
			label({ Position = UDim2.new(0, 12, 0, 36), Size = UDim2.new(1, -24, 0, 18), Text = "Set bonus: " .. bonusText(set.Bonus or {}), Font = Theme.FontBold, TextColor3 = complete and Theme.Success or Theme.GoldLight, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = card }, 15)

			local chips = new("Frame", { Position = UDim2.new(0, 12, 0, 62), Size = UDim2.new(1, -24, 0, chipsHeight), BackgroundTransparency = 1, ZIndex = 5, Parent = card })
			new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, CHIP_HEIGHT), CellPadding = UDim2.new(0, 6, 0, CHIP_GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = chips })
			for j, relicId in ipairs(set.Relics) do
				local relic = Config.RelicsById[relicId]
				local owned = (inventory[relicId] or 0) > 0
				local seen = discovered[relicId] == true
				local chip = new("Frame", { BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.2, LayoutOrder = j, ZIndex = 5, Parent = chips })
				corner(chip, UDim.new(0, 8))
				if relic then
					ctx.RelicViewport(chip, relicId, { Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(CHIP_HEIGHT - 6, CHIP_HEIGHT - 6), CornerRadius = UDim.new(0, 6), Silhouette = not (owned or seen), ZIndex = 6 })
				end
				tick(chip, owned)
				local text, color = "???", Theme.Muted
				if relic and (owned or seen) then
					text = relic.Name
					color = owned and Config.Rarities[relic.Tier].Color or Theme.Muted
				end
				label({ Position = UDim2.new(0, CHIP_HEIGHT + 6, 0, 6), Size = UDim2.new(1, -(CHIP_HEIGHT + 12), 1, -12), Text = text, Font = owned and Theme.FontBold or Theme.Font, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = chip }, 14)
			end

			local rewardY = 62 + chipsHeight + 10
			label({ Position = UDim2.new(0, 12, 0, rewardY + 6), Size = UDim2.new(0.55, -12, 0, 20), Text = "Reward: " .. rewardText(set.Reward or {}), TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = card }, 15)
			local claimable = complete and not isClaimed
			local claim = button({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, rewardY),
				Size = UDim2.new(0.4, 0, 0, 38),
				Font = Theme.FontBlack,
				Text = isClaimed and "Claimed" or (complete and "Claim reward" or "Complete to claim"),
				BackgroundColor3 = claimable and Theme.Gold or Theme.Button,
				TextColor3 = claimable and Theme.Dark or (isClaimed and Theme.Success or Theme.Text),
				ZIndex = 6,
				Parent = card,
			}, function()
				if claimable then
					ctx.act("ClaimSet", set.Id)
				end
			end, 16)
			ctx.setEnabled(claim, claimable)
		end
	end

	ctx.AddMenuButton("Collections", 42, function()
		ctx.openModal("Collections")
	end)
end
