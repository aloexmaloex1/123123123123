-- Daily rewards panel: 7 day cards (claimed / today / upcoming) with reward icons, a big golden Day 7,
-- countdown, claim button, and a pulsing "!" badge on the Daily menu button while a reward is waiting.
local TweenService = game:GetService("TweenService")

return function(ctx)
	local Config, Theme, player = ctx.Config, ctx.Theme, ctx.player
	local new, label, button, corner, stroke = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.stroke
	local DailyConfig = require(ctx.Shared:WaitForChild("FeatureConfig"):WaitForChild("Daily"))
	local days = DailyConfig.Days
	local Left = Enum.TextXAlignment.Left
	local BIG_UNITS = 1.7 -- Day 7 card is this many normal cards wide

	local frame, content = ctx.createModal("Daily", "Daily Rewards")
	frame:FindFirstChildOfClass("UISizeConstraint").MaxSize = Vector2.new(700, 328)
	content.ScrollBarThickness = 0

	local function now()
		return workspace:GetServerTimeNow()
	end

	-- Mirrors the server's status from the attributes it sets every second.
	local function status()
		local readyAt = player:GetAttribute("DailyReadyAt") or 0
		local streak = player:GetAttribute("DailyStreak") or 0
		local claimable = player:GetAttribute("DailyReadyAt") ~= nil and readyAt <= now()
		return {
			Claimable = claimable,
			Streak = streak,
			ReadyAt = readyAt,
			ResetAt = player:GetAttribute("DailyResetAt") or 0,
			Day = DailyConfig.NextDay(streak),
			Claimed = DailyConfig.ClaimedInCycle(streak, claimable),
		}
	end

	-- { icon kind, short text, long text } per reward in a day.
	local function rewardItems(rewards)
		local items = {}
		if rewards.Tickets then
			table.insert(items, { "Ticket", ctx.abbr(rewards.Tickets), ctx.abbr(rewards.Tickets) .. " Tickets" })
		end
		if rewards.Coins then
			table.insert(items, { "Coin", ctx.abbr(rewards.Coins), ctx.abbr(rewards.Coins) .. " Coins" })
		end
		if rewards.Credits then
			table.insert(items, { "Credits", ctx.abbr(rewards.Credits), ctx.abbr(rewards.Credits) .. " Credits" })
		end
		if rewards.Boost then
			local minutes = rewards.Boost.Seconds // 60
			table.insert(items, { rewards.Boost.Kind == "Luck" and "🍀" or "💰", ("2x %dm"):format(minutes), ("2x %s %dm"):format(rewards.Boost.Kind, minutes) })
		end
		if rewards.Relic then
			local relic = Config.RelicsById[rewards.Relic]
			table.insert(items, { "🏺", "Relic", relic and relic.Name or "Relic" })
		end
		return items
	end

	---------------------------------------------------------------- layout

	local header = new("Frame", { Size = UDim2.new(1, -10, 0, 50), BackgroundTransparency = 1, ZIndex = 5, Parent = content })
	local streakLabel = label({ Position = UDim2.new(0, 4, 0, 2), Size = UDim2.new(0.6, -8, 0, 26), Font = Theme.FontBlack, TextColor3 = Theme.GoldLight, TextXAlignment = Left, Text = "", ZIndex = 5, Parent = header }, 22)
	local timerLabel = label({ Position = UDim2.new(0, 4, 0, 30), Size = UDim2.new(0.6, -8, 0, 18), Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Left, Text = "", ZIndex = 5, Parent = header }, 15)
	local busy = false
	local claimButton
	claimButton = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.36, 0, 0, 46), Text = "Claim", Font = Theme.FontBlack, BackgroundColor3 = Theme.Gold, TextColor3 = Theme.Dark, ZIndex = 6, Parent = header }, function()
		if busy or not claimButton.Active then
			return
		end
		busy = true
		ctx.setEnabled(claimButton, false)
		ctx.act("ClaimDaily")
		busy = false
		if ctx.renderers.Daily then
			ctx.renderers.Daily()
		end
	end, 22)

	local cards = new("Frame", { Position = UDim2.new(0, 0, 0, 60), Size = UDim2.new(1, -10, 0, 160), BackgroundTransparency = 1, ZIndex = 5, Parent = content })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = cards })
	label({ Position = UDim2.new(0, 4, 0, 228), Size = UDim2.new(1, -14, 0, 18), Text = ("Claim every %dh to build your streak. Miss %dh and it resets to Day 1."):format(DailyConfig.Cooldown // 3600, DailyConfig.ResetAfter // 3600), TextColor3 = Theme.Muted, ZIndex = 5, Parent = content }, 14)

	local todayStroke -- pulsed while the modal is open
	local pulse = TweenService:Create(Instance.new("NumberValue"), TweenInfo.new(0.1), {}) -- placeholder, replaced per render

	local function buildCard(day, state)
		local isToday = state == "today"
		local claimed = state == "claimed"
		local big = day == #days
		local units = (#days - 1) + BIG_UNITS
		local gaps = 6 * (#days - 1)
		local share = (big and BIG_UNITS or 1) / units
		local card = new("Frame", {
			Name = "Day" .. day,
			LayoutOrder = day,
			Size = UDim2.new(share, -gaps * share, 1, big and 0 or -12),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = claimed and 0.45 or 0,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = cards,
		})
		corner(card, UDim.new(0, 12))
		if big then
			ctx.lipGradient(card, Color3.fromRGB(120, 88, 24), Color3.fromRGB(56, 38, 12), Color3.fromRGB(30, 20, 6), 4)
		elseif isToday then
			ctx.lipGradient(card, Color3.fromRGB(88, 70, 30), Color3.fromRGB(44, 34, 16), Color3.fromRGB(24, 18, 8), 4)
		else
			ctx.lipGradient(card, Theme.PanelLight, Color3.fromRGB(30, 26, 40), Color3.fromRGB(16, 13, 22), 4)
		end
		local cardStroke = stroke(card, claimed and Theme.Success or ((isToday or big) and Theme.Gold or Theme.Muted), (isToday or big) and 2.5 or 1.2, (isToday or claimed or big) and 0 or 0.6)
		if isToday then
			todayStroke = cardStroke
		end

		label({ Position = UDim2.new(0, 4, 0, 6), Size = UDim2.new(1, -8, 0, big and 24 or 18), Text = big and "DAY 7  ★" or ("DAY " .. day), Font = Theme.FontBlack, TextColor3 = big and Theme.GoldLight or Theme.Text, TextTransparency = claimed and 0.35 or 0, ZIndex = 6, Parent = card }, big and 22 or 16)
		local items = rewardItems(days[day])
		local rowH = big and 26 or 24
		local top = big and 36 or 30
		for i, item in ipairs(items) do
			local row = new("Frame", { Position = UDim2.new(0, 8, 0, top + (i - 1) * rowH), Size = UDim2.new(1, -12, 0, rowH - 4), BackgroundTransparency = 1, ZIndex = 6, Parent = card })
			local iconSize = big and 22 or 18
			ctx.icon(item[1], { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(iconSize, iconSize), ZIndex = 6, Parent = row })
			local text = label({ Position = UDim2.new(0, iconSize + 5, 0, 0), Size = UDim2.new(1, -(iconSize + 5), 1, 0), Text = big and item[3] or item[2], Font = Theme.FontBold, TextColor3 = big and Theme.GoldLight or Theme.Text, TextXAlignment = Left, TextTransparency = claimed and 0.4 or 0, ZIndex = 6, Parent = row }, big and 17 or 15)
			text:FindFirstChildOfClass("UITextSizeConstraint").MinTextSize = 14
		end

		local chipText, chipColor, chipTextColor
		if claimed then
			chipText, chipColor, chipTextColor = "CLAIMED", Theme.Success, Theme.Dark
		elseif isToday then
			chipText, chipColor, chipTextColor = "TODAY", Theme.Gold, Theme.Dark
		elseif state == "next" then
			chipText, chipColor, chipTextColor = "NEXT", Theme.Button, Theme.GoldLight
		elseif big then
			chipText, chipColor, chipTextColor = "BIG REWARD!", Theme.Gold, Theme.Dark
		end
		if chipText then
			local chip = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -12, 0, 22), BackgroundColor3 = chipColor, BorderSizePixel = 0, ZIndex = 6, Parent = card })
			corner(chip, UDim.new(1, 0))
			label({ Size = UDim2.new(1, -6, 1, -4), Position = UDim2.new(0, 3, 0, 2), Text = chipText, Font = Theme.FontBlack, TextColor3 = chipTextColor, ZIndex = 7, Parent = chip }, 14)
		end
	end

	local lastClaimable
	local function refreshTimer()
		local s = status()
		if s.Streak > 0 then
			streakLabel.Text = ("🔥 Streak: %d day%s"):format(s.Streak, s.Streak == 1 and "" or "s")
		else
			streakLabel.Text = "Start your streak!"
		end
		if s.Claimable then
			timerLabel.Text = (s.ResetAt > 0 and s.Streak > 0) and ("Ready! Claim within %s to keep your streak."):format(ctx.duration(s.ResetAt - now())) or "Your Day " .. s.Day .. " reward is ready!"
			timerLabel.TextColor3 = Theme.Success
		else
			timerLabel.Text = "Next reward in " .. ctx.duration(s.ReadyAt - now())
			timerLabel.TextColor3 = Theme.Muted
		end
		if not busy then
			claimButton.Text = s.Claimable and ("Claim Day " .. s.Day) or "Come back later"
			claimButton.BackgroundColor3 = s.Claimable and Theme.Gold or Theme.Button
			claimButton.TextColor3 = s.Claimable and Theme.Dark or Theme.Muted
			ctx.setEnabled(claimButton, s.Claimable)
		end
		return s
	end

	ctx.renderers.Daily = function()
		pulse:Cancel()
		todayStroke = nil
		ctx.clear(cards)
		local s = refreshTimer()
		lastClaimable = s.Claimable
		for day = 1, #days do
			local state = "upcoming"
			if day <= s.Claimed then
				state = "claimed"
			elseif day == s.Day then
				state = s.Claimable and "today" or "next"
			end
			buildCard(day, state)
		end
		if todayStroke then
			pulse = TweenService:Create(todayStroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 })
			pulse:Play()
		end
	end

	---------------------------------------------------------------- menu button + badge

	-- AddMenuButton returns the square tile (a TextButton named "Daily"); the badge sits on its top-right corner.
	local menuButton = ctx.AddMenuButton("Daily", 61, function()
		ctx.openModal("Daily")
	end)
	local badge = new("Frame", { Name = "Badge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Theme.Error, BorderSizePixel = 0, Visible = false, ZIndex = 5, Parent = menuButton })
	corner(badge, UDim.new(1, 0))
	stroke(badge, Color3.new(1, 1, 1), 2, 0)
	label({ Size = UDim2.fromScale(1, 1), Text = "!", Font = Theme.FontBlack, ZIndex = 6, Parent = badge }, 16)
	local badgeScale = new("UIScale", { Parent = badge })
	TweenService:Create(badgeScale, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.2 }):Play()

	ctx.OnEvent("Daily", function(kind, day)
		if kind == "Claimed" and type(day) == "number" and day == #days and ctx.ShowBanner then
			ctx.ShowBanner("Day 7 complete! Big reward claimed. Your streak keeps going!", Theme.Gold, 4)
		end
	end)

	task.spawn(function()
		while true do
			local s = status()
			badge.Visible = player:GetAttribute("Loaded") == true and s.Claimable
			if frame.Visible then
				if s.Claimable ~= lastClaimable then
					ctx.renderers.Daily()
				else
					refreshTimer()
				end
			end
			task.wait(1)
		end
	end)
end
