-- Core HUD: currency bar, curator level, excavate panel with pity (or a "Go dig" pill away from dig sites),
-- the roll reveal, announcements, welcome popup and the idle animation for displayed relics.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

return function(ctx)
	local Config, Theme, player = ctx.Config, ctx.Theme, ctx.player
	local new, label, button, panel, corner, fmt = ctx.new, ctx.label, ctx.button, ctx.panel, ctx.corner, ctx.fmt
	local gui = ctx.gui
	local Left, Right = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right

	local function renderStep(fn)
		local ok, connection = pcall(function()
			return RunService.RenderStepped:Connect(fn)
		end)
		return ok and connection or RunService.Heartbeat:Connect(fn)
	end

	-- Converts a design-space rect (pixels inside a W x H panel) into Scale UDim2s, so panels shrink on phones.
	local function designer(W, H)
		return function(props, x, y, w, h)
			props.Position = UDim2.fromScale(x / W, y / H)
			props.Size = UDim2.fromScale(w / W, h / H)
			return props
		end
	end

	---------------------------------------------------------------- top bar

	local topBar = panel({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		Parent = ctx.topArea,
	})
	new("UIAspectRatioConstraint", { AspectRatio = 600 / 64, Parent = topBar }) -- 600x64 on desktop, narrower + shorter on phones
	local T = designer(600, 64)
	local function divider(x)
		new("Frame", T({ BackgroundColor3 = Theme.Gold, BackgroundTransparency = 0.7, BorderSizePixel = 0, Parent = topBar }, x, 12, 1, 40))
	end
	-- Coins
	ctx.icon("Coin", T({ Parent = topBar }, 14, 9, 28, 28))
	local coinsLabel = label(T({ Font = Theme.FontBlack, TextColor3 = Theme.GoldLight, TextXAlignment = Left, Text = "0", Parent = topBar }, 50, 6, 150, 30), 26)
	new("UIStroke", { Color = Color3.fromRGB(70, 42, 6), Thickness = 1.5, Transparency = 0.3, Parent = coinsLabel })
	local incomeLabel = label(T({ Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Left, Text = "+0 /min", Parent = topBar }, 16, 40, 184, 17), 14)
	divider(206)
	-- Tickets
	ctx.icon("Ticket", T({ Parent = topBar }, 218, 9, 28, 28))
	local ticketsLabel = label(T({ Font = Theme.FontBlack, TextXAlignment = Left, Text = "0", Parent = topBar }, 252, 6, 142, 30), 24)
	local freeLabel = label(T({ Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Left, Text = "", Parent = topBar }, 220, 40, 174, 17), 14)
	divider(400)
	-- Level + XP bar (bar sits directly under the level label, same left edge)
	ctx.icon("XP", T({ Parent = topBar }, 412, 8, 24, 24))
	local levelLabel = label(T({ Font = Theme.FontBlack, TextColor3 = Theme.GoldLight, TextXAlignment = Left, Text = "Curator Lv 1", Parent = topBar }, 442, 8, 144, 24), 18)
	local xpBar = new("Frame", T({ BackgroundColor3 = Color3.fromRGB(14, 11, 20), BorderSizePixel = 0, Parent = topBar }, 412, 36, 174, 18))
	corner(xpBar, UDim.new(1, 0))
	ctx.stroke(xpBar, Theme.XP, 1, 0.4)
	local xpFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = xpBar })
	corner(xpFill, UDim.new(1, 0))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(196, 170, 255), Color3.fromRGB(120, 80, 235)), Parent = xpFill })
	local xpText = label({ Size = UDim2.fromScale(1, 1), Font = Theme.FontBold, TextStrokeTransparency = 0.3, Text = "", ZIndex = 2, Parent = xpBar }, 14)
	new("UIPadding", { PaddingTop = UDim.new(0.1, 0), PaddingBottom = UDim.new(0.1, 0), Parent = xpText })

	local function refreshTopBar()
		coinsLabel.Text = fmt(player:GetAttribute("Coins") or 0)
		local mult = player:GetAttribute("IncomeMultiplier") or 1
		incomeLabel.Text = ("+%s coins/min%s"):format(fmt(player:GetAttribute("IncomePerMin") or 0), mult > 1.001 and (" (x%.2f)"):format(mult) or "")
		local tickets = player:GetAttribute("Tickets") or 0
		ticketsLabel.Text = fmt(tickets) .. " Ticket" .. (tickets == 1 and "" or "s")
		local nextAt = player:GetAttribute("NextFreeTicketAt") or 0
		if nextAt > 0 then
			local left = math.max(0, math.ceil(nextAt - workspace:GetServerTimeNow()))
			freeLabel.Text = ("free ticket in %d:%02d"):format(left // 60, left % 60)
		else
			freeLabel.Text = ("free tickets full (%d)"):format(Config.Economy.FreeTicketCap)
		end
		local level, xp, needed = player:GetAttribute("Level") or 1, player:GetAttribute("XP") or 0, player:GetAttribute("XPNeeded") or 1
		levelLabel.Text = "Curator Lv " .. level
		xpFill.Size = UDim2.fromScale(math.clamp(xp / math.max(needed, 1), 0, 1), 1)
		xpFill.Visible = xp > 0
		xpText.Text = ("%s / %s XP"):format(ctx.abbr(xp), ctx.abbr(needed))
	end
	for _, name in ipairs({ "Coins", "IncomePerMin", "Tickets", "NextFreeTicketAt", "Level", "XP" }) do
		player:GetAttributeChangedSignal(name):Connect(refreshTopBar)
	end

	---------------------------------------------------------------- roll panel

	local rollPanel = panel({
		Name = "RollPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromScale(0.94, 0.45),
		Visible = false,
		Parent = gui,
	})
	new("UIAspectRatioConstraint", { AspectRatio = 420 / 192, Parent = rollPanel })
	new("UISizeConstraint", { MaxSize = Vector2.new(420, 192), Parent = rollPanel })
	local R = designer(420, 192)
	local siteDot = new("Frame", R({ BackgroundColor3 = Theme.Gold, BorderSizePixel = 0, Parent = rollPanel }, 14, 11, 10, 10))
	corner(siteDot, UDim.new(1, 0))
	local siteLabel = label(R({ Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Left, Text = "", Parent = rollPanel }, 30, 6, 376, 20), 15)
	local currentSite
	local rollButton = button(R({
		BackgroundColor3 = Theme.Gold,
		TextColor3 = Theme.Dark,
		Font = Theme.FontBlack,
		Text = "",
		Parent = rollPanel,
	}, 10, 30, 400, 54), function()
		if currentSite then
			ctx.Remotes.RequestRoll:FireServer()
		else
			ctx.openModal("DigSites", true)
		end
	end, 24)
	local rollStroke = rollButton:FindFirstChildOfClass("UIStroke")
	rollStroke.Color, rollStroke.Thickness, rollStroke.Transparency = Theme.GoldLight, 2, 0.1
	local cost = Config.Economy.TicketCost
	for i, amount in ipairs({ 1, 10, 100 }) do
		local b = button(R({ Text = ("+%d  ·  %s"):format(amount, ctx.abbr(cost * amount)), Parent = rollPanel }, 10 + (i - 1) * 136, 90, 128, 32), function()
			ctx.act("BuyTickets", amount)
		end, 15)
		b.TextXAlignment = Enum.TextXAlignment.Right
		ctx.icon("Ticket", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.95), DominantAxis = Enum.DominantAxis.Height, ZIndex = 2, Parent = b })
	end

	-- Pity chips: identical rounded swatch + label + soft fill for every rule.
	local pityBars = {}
	for i, rule in ipairs(Config.Pity) do
		local col, row = (i - 1) % 2, (i - 1) // 2
		local color = Config.Rarities[rule.MinTier].Color
		local chip = new("Frame", R({
			BackgroundColor3 = Color3.fromRGB(14, 11, 20),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Parent = rollPanel,
		}, 10 + col * 204, 128 + row * 30, 196, 26))
		corner(chip, UDim.new(0, 8))
		ctx.stroke(chip, color, 1, 0.55)
		local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, BackgroundTransparency = 0.62, BorderSizePixel = 0, Parent = chip })
		corner(fill, UDim.new(0, 8))
		local swatch = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 5, 0.5, 0), Size = UDim2.fromScale(1, 0.7), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 2, Parent = chip })
		new("UIAspectRatioConstraint", { DominantAxis = Enum.DominantAxis.Height, Parent = swatch })
		corner(swatch, UDim.new(0.28, 0))
		ctx.stroke(swatch, Color3.new(1, 1, 1), 1, 0.6)
		local name = label({ Position = UDim2.fromScale(0.15, 0.12), Size = UDim2.fromScale(0.5, 0.76), Font = Theme.FontBold, TextStrokeTransparency = 0.5, TextXAlignment = Left, Text = Config.Rarities[rule.MinTier].Name .. "+", ZIndex = 2, Parent = chip }, 14)
		local count = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.96, 0.12), Size = UDim2.fromScale(0.34, 0.76), Font = Theme.FontBold, TextColor3 = Theme.Muted, TextStrokeTransparency = 0.5, TextXAlignment = Right, Text = "", ZIndex = 2, Parent = chip }, 14)
		pityBars[i] = { Fill = fill, Name = name, Count = count, Rule = rule }
	end

	local function refreshPity()
		local pity = ctx.State().Pity or {}
		for i, bar in ipairs(pityBars) do
			local n = pity[i] or 0
			bar.Fill.Size = UDim2.fromScale(math.clamp(n / bar.Rule.Every, 0, 1), 1)
			bar.Count.Text = ("in %d"):format(math.max(bar.Rule.Every - n, 1))
		end
	end
	ctx.OnSnapshot(refreshPity)

	-- Away from dig sites the roll panel collapses into this pill.
	local goDig = button({
		Name = "GoDigPill",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromScale(0.6, 0.12),
		BackgroundColor3 = Theme.Gold,
		TextColor3 = Theme.Dark,
		Font = Theme.FontBlack,
		Text = "⛏️  GO DIG!",
		Visible = false,
		Parent = gui,
	}, function()
		ctx.openModal("DigSites", true)
	end, 24)
	goDig:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	new("UIAspectRatioConstraint", { AspectRatio = 230 / 56, Parent = goDig })
	new("UISizeConstraint", { MaxSize = Vector2.new(230, 56), Parent = goDig })
	local goStroke = goDig:FindFirstChildOfClass("UIStroke")
	goStroke.Color, goStroke.Thickness, goStroke.Transparency = Theme.GoldLight, 2.5, 0
	local goScale = new("UIScale", { Parent = goDig })
	TweenService:Create(goScale, ctx.Anim.Pulse, { Scale = 1.05 }):Play()

	local function refreshHudVisibility()
		local hudHidden = not ctx.menu.Visible -- heists hide the menu and world HUD
		local modal = ctx.AnyModalOpen()
		rollPanel.Visible = currentSite ~= nil and not modal and not hudHidden
		goDig.Visible = currentSite == nil and not modal and not hudHidden
	end
	ctx.OnModalChanged(refreshHudVisibility)

	local function refreshRollButton()
		local siteId = ctx.CurrentSite()
		currentSite = siteId
		local luck = player:GetAttribute("Luck") or 1
		if siteId then
			local site = Config.DigSites[siteId]
			local locked = (player:GetAttribute("Level") or 1) < site.Level
			siteLabel.Text = ("%s  ·  luck x%.2f"):format(site.Name, site.Luck * luck)
			siteLabel.TextColor3 = site.Color
			siteDot.BackgroundColor3 = site.Color
			if locked then
				rollButton.Text = ("🔒  Unlocks at Curator Lv %d"):format(site.Level)
				rollButton.BackgroundColor3 = Theme.Button
				rollButton.TextColor3 = Theme.Muted
			else
				rollButton.Text = ("EXCAVATE  ·  %d Ticket%s"):format(site.TicketCost, site.TicketCost == 1 and "" or "s")
				rollButton.BackgroundColor3 = Theme.Gold
				rollButton.TextColor3 = Theme.Dark
			end
		end
		refreshHudVisibility()
	end

	---------------------------------------------------------------- reveal

	local CARD_W, CARD_H = 320, 392
	local revealLayer = new("Frame", { Name = "Reveal", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 20, Parent = gui })
	local flash = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20, Parent = revealLayer })
	local stage = new("Frame", { Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundTransparency = 1, ZIndex = 21, Parent = revealLayer })
	local stageScale = new("UIScale", { Parent = stage })

	-- Rays: thin frames through the card centre, each fading toward both tips. Rotated every frame.
	local rays = {}
	local RAY_COUNT = 12
	for i = 1, RAY_COUNT do
		local ray = new("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(i % 2 == 0 and 26 or 46, 980),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ZIndex = 21,
			Parent = stage,
		})
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.22, 0.75),
				NumberSequenceKeypoint.new(0.5, 0.1),
				NumberSequenceKeypoint.new(0.78, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
		rays[i] = ray
	end
	local halo = new("Frame", { Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(470, 470), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 22, Parent = stage })
	corner(halo, UDim.new(1, 0))

	local card = new("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 23, Parent = stage })
	corner(card, UDim.new(0, 20))
	local cardGradient = new("UIGradient", { Rotation = 90, Parent = card })
	local cardStroke = new("UIStroke", { Thickness = 5, Color = Theme.Gold, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card })
	local cardScale = new("UIScale", { Parent = card })
	local shine = new("Frame", { Size = UDim2.new(1, 0, 0.45, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 23, Parent = card })
	corner(shine, UDim.new(0, 20))
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.2, 1), Parent = shine })

	local titleChip = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(190, 26), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 24, Parent = card })
	corner(titleChip, UDim.new(1, 0))
	local titleText = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Theme.FontBlack, TextSize = 15, TextColor3 = Theme.Text, Text = "", ZIndex = 25, Parent = titleChip })
	local viewHolder = new("Frame", { Name = "ViewHolder", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.fromOffset(196, 186), BackgroundTransparency = 1, ZIndex = 24, Parent = card })
	local question = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Theme.FontBlack, TextSize = 120, Text = "?", TextColor3 = Color3.new(1, 1, 1), ZIndex = 26, Parent = viewHolder })
	local questionStroke = new("UIStroke", { Thickness = 4, Color = Theme.Gold, Parent = question })
	local rarityLabel = new("TextLabel", { Position = UDim2.new(0, 10, 0, 238), Size = UDim2.new(1, -20, 0, 46), BackgroundTransparency = 1, Font = Theme.FontBlack, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 25, Parent = card })
	ctx.maxText(rarityLabel, 42)
	local rarityStroke = new("UIStroke", { Thickness = 3, Color = Theme.Gold, Parent = rarityLabel })
	local nameLabel = label({ Position = UDim2.new(0, 12, 0, 286), Size = UDim2.new(1, -24, 0, 30), Font = Theme.FontBlack, Text = "", TextStrokeTransparency = 0.5, ZIndex = 25, Parent = card }, 24)
	local infoLabel = label({ Position = UDim2.new(0, 12, 0, 318), Size = UDim2.new(1, -24, 0, 20), Font = Theme.FontBold, TextColor3 = Color3.fromRGB(225, 220, 235), Text = "", ZIndex = 25, Parent = card }, 15)
	local tagsRow = new("Frame", { Position = UDim2.new(0, 12, 0, 348), Size = UDim2.new(1, -24, 0, 28), BackgroundTransparency = 1, ZIndex = 25, Parent = card })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tagsRow })

	local function tag(order, text, bg, fg)
		local chip = new("Frame", { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = bg, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 25, Parent = tagsRow })
		corner(chip, UDim.new(1, 0))
		ctx.stroke(chip, Color3.new(1, 1, 1), 1.5, 0.4)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = chip })
		new("TextLabel", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Font = Theme.FontBlack, TextSize = 15, TextColor3 = fg, Text = text, ZIndex = 26, Parent = chip })
		local s = new("UIScale", { Scale = 0.2, Parent = chip })
		TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, order * 0.08), { Scale = 1 }):Play()
	end

	local function setCardColor(color)
		cardGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, ctx.darken(color, 0.25)),
			ColorSequenceKeypoint.new(0.55, ctx.darken(color, 0.7)),
			ColorSequenceKeypoint.new(1, ctx.darken(color, 0.86)),
		})
		cardStroke.Color = color
		rarityStroke.Color = ctx.darken(color, 0.35)
		questionStroke.Color = color
		for _, ray in ipairs(rays) do
			ray.BackgroundColor3 = ctx.lighten(color, 0.25)
		end
		halo.BackgroundColor3 = color
	end

	local revealToken = 0
	-- Rays spin with looping TweenService tweens (180 deg is a full cycle since each ray crosses the centre).
	local rayTweens = {}
	local function stopRays()
		for i, tween in ipairs(rayTweens) do
			tween:Cancel()
			rayTweens[i] = nil
		end
	end
	local function startRays(degreesPerSecond)
		stopRays()
		local info = TweenInfo.new(180 / degreesPerSecond, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
		for i, ray in ipairs(rays) do
			local base = i * (180 / RAY_COUNT)
			ray.Rotation = base
			rayTweens[i] = TweenService:Create(ray, info, { Rotation = base + 180 })
			rayTweens[i]:Play()
		end
	end

	local function shakeCamera(strength, duration)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local stopAt = os.clock() + duration
		local connection
		connection = renderStep(function()
			if os.clock() > stopAt or not humanoid.Parent then
				humanoid.CameraOffset = Vector3.zero
				connection:Disconnect()
				return
			end
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * strength
		end)
	end

	local function flashScreen(color, from, seconds)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = from
		ctx.tween(flash, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	end

	-- Fit the card between the top bar and the roll panel; on very short screens just centre it.
	local function fitStage()
		local size = gui.AbsoluteSize
		local top, bottom = 84, size.Y - 214
		local scale = math.min((bottom - top) / CARD_H, (size.X - 40) / CARD_W, 1)
		if scale < 0.7 then
			top, bottom = 8, size.Y - 8
			scale = math.min((bottom - top) / CARD_H, (size.X - 40) / CARD_W, 1)
		end
		stageScale.Scale = math.max(scale, 0.5)
		stage.Position = UDim2.new(0.5, 0, 0, math.floor((top + bottom) / 2))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitStage)
	fitStage()

	-- Shows a relic reveal card. Other features (heist loot, codes, store) call ctx.ShowReveal too.
	-- result = { RelicId, Tier, IsNew?, Pity?, XP?, Title? }
	function ctx.ShowReveal(result)
		local relic = Config.RelicsById[result.RelicId]
		if not relic then
			return
		end
		local tier = math.clamp(tonumber(result.Tier) or relic.Tier, 1, #Config.Rarities)
		local rarity = Config.Rarities[tier]
		revealToken += 1
		local token = revealToken

		for _, child in ipairs(viewHolder:GetChildren()) do
			if child ~= question then
				child:Destroy()
			end
		end
		for _, child in ipairs(tagsRow:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		revealLayer.Visible = true
		question.Visible = true
		question.Rotation = 0
		for _, ray in ipairs(rays) do
			ray.Visible = false
		end
		halo.Visible = false
		titleText.Text = result.Title or "EXCAVATING..."
		nameLabel.Text = ""
		infoLabel.Text = ""
		flash.BackgroundTransparency = 1
		cardScale.Scale = 0.7
		ctx.tween(cardScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })

		-- ~0.8 s build-up: cycle rarity colours/names with a scale pulse on each tick.
		local maxCycle = math.min(#Config.Rarities, tier + 1)
		for i = 1, 10 do
			if revealToken ~= token then
				return
			end
			local fake = Config.Rarities[math.random(1, maxCycle)]
			setCardColor(fake.Color)
			rarityLabel.Text = fake.Name:upper()
			rarityLabel.TextColor3 = ctx.lighten(fake.Color, 0.5)
			question.Rotation = (i % 2 == 0) and -8 or 8
			cardScale.Scale = 1.06
			ctx.tween(cardScale, TweenInfo.new(0.07), { Scale = 1 })
			task.wait(0.05 + i * 0.0055)
		end
		if revealToken ~= token then
			return
		end

		setCardColor(rarity.Color)
		question.Visible = false
		ctx.RelicViewport(viewHolder, result.RelicId, { Size = UDim2.fromScale(1, 1), Background = false, Spin = 1.1, ZIndex = 24, Zoom = 1.0 })
		titleText.Text = result.Title or (result.IsNew and "NEW DISCOVERY!" or "YOU FOUND")
		rarityLabel.Text = rarity.Name:upper()
		rarityLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.Text = relic.Name
		infoLabel.Text = ("+%s coins/min  ·  %s"):format(fmt(rarity.Income), ctx.oneIn(Config.GetRelicChance(result.RelicId)))
		local order = 0
		if result.IsNew then
			order += 1
			tag(order, "NEW!", Theme.Gold, Theme.Dark)
		end
		if result.Pity then
			order += 1
			tag(order, "PITY", Color3.fromRGB(150, 90, 240), Color3.new(1, 1, 1))
		end
		if result.XP then
			order += 1
			tag(order, "+" .. tostring(result.XP) .. " XP", Color3.fromRGB(70, 140, 235), Color3.new(1, 1, 1))
		end

		for _, ray in ipairs(rays) do
			ray.Visible = true
			ray.BackgroundTransparency = tier >= 6 and 0 or (tier >= 4 and 0.15 or 0.45)
		end
		halo.Visible = true
		halo.Size = UDim2.fromOffset(300, 300)
		halo.BackgroundTransparency = 0.6
		local haloSize = tier >= 6 and 560 or 470
		ctx.tween(halo, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(haloSize, haloSize), BackgroundTransparency = tier >= 4 and 0.72 or 0.85 })
		startRays(tier >= 6 and 45 or (tier >= 4 and 30 or 16))

		cardScale.Scale = tier >= 6 and 0.45 or 0.6
		ctx.tween(cardScale, TweenInfo.new(tier >= 6 and 0.5 or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })

		if tier >= 6 then
			flashScreen(Color3.new(1, 1, 1), 0, 0.25)
			task.delay(0.12, function()
				if revealToken == token then
					flashScreen(rarity.Color, 0.05, 1.2)
				end
			end)
		elseif tier >= 4 then
			flashScreen(rarity.Color, 0.35, 0.6)
		end
		if tier >= 4 then
			shakeCamera(0.25 + (tier - 4) * 0.15, 0.35 + tier * 0.05)
		end

		task.delay(tier >= 5 and 4 or 2.6, function()
			if revealToken == token then
				ctx.tween(cardScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.8 })
				task.wait(0.15)
				if revealToken == token then
					revealLayer.Visible = false
					stopRays()
				end
			end
		end)
	end
	ctx.Remotes.RollResult.OnClientEvent:Connect(ctx.ShowReveal)

	---------------------------------------------------------------- announcements

	-- Scale width capped at 580 px so long announcements fit on phones; pops in and shrinks away.
	local banner = panel({ Name = "Announcement", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 122), Size = UDim2.new(0.94, 0, 0, 46), Visible = false, ZIndex = 15, Parent = gui })
	new("UISizeConstraint", { MaxSize = Vector2.new(580, 46), Parent = banner })
	local bannerScale = new("UIScale", { Parent = banner })
	local bannerText = label({ Size = UDim2.new(1, -24, 1, -10), Position = UDim2.new(0, 12, 0, 4), Font = Theme.FontBlack, Text = "", TextStrokeTransparency = 0.4, ZIndex = 15, Parent = banner }, 20)
	local bannerStroke = banner:FindFirstChildOfClass("UIStroke")
	local bannerToken = 0

	function ctx.ShowBanner(text, color, seconds)
		bannerToken += 1
		local token = bannerToken
		bannerText.Text = text
		bannerText.TextColor3 = color or Theme.Gold
		bannerStroke.Color, bannerStroke.Thickness, bannerStroke.Transparency = color or Theme.Gold, 2, 0.1
		banner.Visible = true
		bannerScale.Scale = 0.82
		ctx.tween(bannerScale, ctx.Anim.Pop, { Scale = 1 })
		task.delay(seconds or 6, function()
			if bannerToken ~= token then
				return
			end
			ctx.tween(bannerScale, ctx.Anim.Close, { Scale = 0.85 })
			task.wait(ctx.Anim.Close.Time)
			if bannerToken == token then
				banner.Visible = false
			end
		end)
	end

	function ctx.SystemChat(text, color)
		pcall(function()
			local channels = TextChatService:FindFirstChild("TextChannels")
			local channel = channels and channels:FindFirstChild("RBXGeneral")
			if channel then
				channel:DisplaySystemMessage(("<font color=\"#%s\">%s</font>"):format((color or Theme.Gold):ToHex(), text))
			end
		end)
	end

	ctx.Remotes.Announce.OnClientEvent:Connect(function(playerName, relicId, tier)
		local relic = Config.RelicsById[relicId]
		local rarity = Config.Rarities[tier]
		if not relic or not rarity then
			return
		end
		local text = ("%s excavated a %s relic: %s!"):format(playerName, rarity.Name, relic.Name)
		ctx.ShowBanner(text, rarity.Color)
		ctx.SystemChat("[Relic] " .. text, rarity.Color)
	end)

	---------------------------------------------------------------- welcome popup

	local function showWelcome(greeting)
		local lines
		if greeting.IsNew then
			lines = "You have 5 free Dig Tickets and a Rusty Coin. Excavate at Dusty Dunes, then put relics on your museum pedestals to earn coins, even while you're offline."
			if not greeting.Saving then
				lines ..= "\n\n(Progress isn't saving in this session.)"
			end
		else
			lines = ""
			if (greeting.Earned or 0) > 0 then
				lines = ("While you were away (%s) your museum earned %s coins."):format(ctx.duration(greeting.Seconds), fmt(greeting.Earned))
				if greeting.Capped then
					lines ..= ("\nOffline earnings cap at %s. Upgrade it in the Shop."):format(ctx.duration(greeting.CapSeconds))
				end
			end
		end
		for _, line in ipairs(greeting.Extra or {}) do
			lines ..= (lines == "" and "" or "\n\n") .. line
		end
		local popup = panel({ Name = "Welcome", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.new(0, 440, 0, 270), ZIndex = 30, Parent = gui })
		local title = label({ Position = UDim2.new(0, 16, 0, 12), Size = UDim2.new(1, -32, 0, 34), Font = Theme.FontBlack, TextColor3 = Theme.GoldLight, Text = greeting.IsNew and "Welcome, Curator!" or "Welcome back, Curator!", ZIndex = 30, Parent = popup }, 28)
		new("UIStroke", { Color = Color3.fromRGB(60, 36, 8), Thickness = 1.5, Parent = title })
		label({ Position = UDim2.new(0, 20, 0, 54), Size = UDim2.new(1, -40, 1, -120), Text = lines, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 30, Parent = popup }, 18)
		button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(0, 180, 0, 44), Text = greeting.IsNew and "Let's dig!" or "Collect", Font = Theme.FontBlack, BackgroundColor3 = Theme.Gold, TextColor3 = Theme.Dark, ZIndex = 31, Parent = popup }, function()
			popup:Destroy()
		end, 22)
	end
	ctx.ShowWelcome = showWelcome

	---------------------------------------------------------------- startup and loops

	task.spawn(function()
		while not player:GetAttribute("Loaded") do
			player:GetAttributeChangedSignal("Loaded"):Wait()
		end
		local ok, snapshot, greeting = ctx.Remotes.Action:InvokeServer("GetSnapshot")
		if ok then
			ctx.ApplySnapshot(snapshot)
			if greeting then
				showWelcome(greeting)
			end
		end
	end)

	task.spawn(function()
		while true do
			refreshRollButton()
			refreshTopBar()
			task.wait(0.25)
		end
	end)

	---------------------------------------------------------------- relic idle animation

	-- Displayed relics bob and turn client-side. Heartbeat at 30 Hz, no per-frame tables or closures;
	-- models leave the table when untagged, streamed out or destroyed.
	local spinning = {} -- [model] = base pivot
	local function track(model)
		if model:IsA("Model") then
			spinning[model] = model:GetPivot()
		end
	end
	local function untrack(model)
		spinning[model] = nil
	end
	CollectionService:GetInstanceAddedSignal("RelicSpin"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("RelicSpin"):Connect(untrack)
	for _, model in ipairs(CollectionService:GetTagged("RelicSpin")) do
		track(model)
	end
	local SPIN_STEP = 1 / 30
	local accumulated = 0
	local sin, angles, offset = math.sin, CFrame.Angles, CFrame.new
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < SPIN_STEP then
			return
		end
		accumulated = 0
		local t = os.clock()
		for model, base in pairs(spinning) do
			if not model.Parent then
				spinning[model] = nil
			elseif model.PrimaryPart then
				model:PivotTo(base * offset(0, sin(t * 2 + base.X) * 0.25, 0) * angles(0, t * 0.9, 0))
			end
		end
	end)
end
