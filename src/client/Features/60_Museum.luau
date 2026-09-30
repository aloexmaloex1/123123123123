-- Museum Security menu: star rating breakdown, Security Level upgrades, recent thief log,
-- the break-in alert (flashing red border, banner, alarm beeps) and the sweep of security cameras.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

return function(ctx)
	local Theme, player = ctx.Theme, ctx.player
	local new, label, button, corner, fmt = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.fmt
	local Tuning = require(ctx.Shared:WaitForChild("FeatureConfig"):WaitForChild("Security"))
	local Left, Right = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
	local RED = Color3.fromRGB(235, 60, 60)
	local STAR_EMPTY = Color3.fromRGB(62, 64, 84)
	local STAR_GOLD = Color3.fromRGB(255, 205, 70)
	local TRACK = Color3.fromRGB(45, 45, 58)

	local _, content = ctx.createModal("Security", "Museum Security")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

	local function trimNumber(n)
		return (("%.1f"):format(n):gsub("%.0$", ""))
	end

	local function ago(t)
		local s = math.max(0, workspace:GetServerTimeNow() - (t or 0))
		if s < 60 then
			return "just now"
		elseif s < 3600 then
			return ("%dm ago"):format(s // 60)
		elseif s < 86400 then
			return ("%dh ago"):format(s // 3600)
		end
		return ("%dd ago"):format(s // 86400)
	end

	-- Five stars; partial (half) fills use a hard-edged UIGradient on the glyph, so edges stay smooth.
	local function starRow(parent, size, value, position)
		local gap = math.floor(size * 0.15)
		local row = new("Frame", { Position = position, Size = UDim2.fromOffset(size * 5 + gap * 4, size), BackgroundTransparency = 1, ZIndex = 5, Parent = parent })
		for i = 1, 5 do
			local fill = math.clamp(value - (i - 1), 0, 1)
			local star = new("TextLabel", { Position = UDim2.fromOffset((i - 1) * (size + gap), 0), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Font = Theme.FontBlack, TextSize = size, Text = "★", TextColor3 = Color3.new(1, 1, 1), ZIndex = 5, Parent = row })
			new("UIStroke", { Color = Color3.fromRGB(90, 60, 10), Thickness = 1, Transparency = fill > 0 and 0.2 or 0.7, Parent = star })
			local color
			if fill >= 1 then
				color = ColorSequence.new(STAR_GOLD)
			elseif fill <= 0 then
				color = ColorSequence.new(STAR_EMPTY)
			else
				-- the glyph's ink spans roughly 8%..92% of the label, so map the fill into that range
				local at = math.clamp(0.08 + fill * 0.84, 0.02, 0.98)
				color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, STAR_GOLD),
					ColorSequenceKeypoint.new(at - 0.001, STAR_GOLD),
					ColorSequenceKeypoint.new(at, STAR_EMPTY),
					ColorSequenceKeypoint.new(1, STAR_EMPTY),
				})
			end
			new("UIGradient", { Color = color, Parent = star })
		end
		return row
	end

	local function card(order, height)
		local frame = ctx.card({ Size = UDim2.new(1, 0, 0, height), LayoutOrder = order, Parent = content })
		return new("Frame", { Position = UDim2.new(0, 14, 0, 12), Size = UDim2.new(1, -28, 1, -24), BackgroundTransparency = 1, ZIndex = 5, Parent = frame })
	end

	local function bar(parent, position, size, fraction, color)
		local track = new("Frame", { Position = position, Size = size, BackgroundColor3 = TRACK, BorderSizePixel = 0, ZIndex = 5, Parent = parent })
		corner(track, UDim.new(1, 0))
		if fraction > 0 then
			local fill = new("Frame", { Size = UDim2.fromScale(math.clamp(fraction, 0.04, 1), 1), BackgroundColor3 = color or Theme.Gold, BorderSizePixel = 0, ZIndex = 5, Parent = track })
			corner(fill, UDim.new(1, 0))
		end
	end

	---------------------------------------------------------------- sections

	local function renderRating(order, rating)
		local inner = card(order, 234)
		label({ Size = UDim2.new(1, 0, 0, 16), Text = "MUSEUM RATING", Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 14)
		starRow(inner, 32, rating.Stars, UDim2.fromOffset(0, 20))
		label({
			Position = UDim2.new(0, 0, 0, 58),
			Size = UDim2.new(1, 0, 0, 22),
			Text = ("%s / 5 stars  ·  +%d%% museum income"):format(trimNumber(rating.Stars), math.floor(Tuning.GetIncomeBonus(rating.Stars) * 100 + 0.5)),
			Font = Theme.FontBlack,
			TextColor3 = Theme.Gold,
			TextXAlignment = Left,
			ZIndex = 5,
			Parent = inner,
		}, 20)
		-- Plain-language labels so "relics shown" isn't read as a pedestal count (My Relics shows pedestals used).
		local partText = {
			Displayed = function(p)
				return ("Relics shown %s  ·  full rating at %s"):format(fmt(p.Value), fmt(p.Target))
			end,
			Variety = function(p)
				return ("Different relics %s  ·  full at %s"):format(fmt(p.Value), fmt(p.Target))
			end,
			Rarity = function(p)
				return ("Rarity score %s  ·  full at %s"):format(fmt(p.Value), fmt(p.Target))
			end,
			Security = function(p)
				return ("Security level %s  ·  full at %s"):format(fmt(p.Value), fmt(p.Target))
			end,
		}
		for i, part in ipairs(rating.Parts) do
			local row = new("Frame", { Position = UDim2.new(0, 0, 0, 86 + (i - 1) * 26), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, ZIndex = 5, Parent = inner })
			local text = partText[part.Key] and partText[part.Key](part) or ("%s  %s/%s"):format(part.Name, fmt(part.Value), fmt(part.Target))
			label({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0.56, -8, 1, 0), Text = text, Font = Theme.FontBold, TextXAlignment = Left, ZIndex = 5, Parent = row }, 15)
			bar(row, UDim2.new(0.56, 0, 0.5, -6), UDim2.new(0.3, 0, 0, 12), part.Points / part.Max)
			label({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0.14, -6, 1, 0), Text = ("%s/%d"):format(trimNumber(part.Points), part.Max), Font = Theme.FontBlack, TextColor3 = Theme.GoldLight, TextXAlignment = Right, ZIndex = 5, Parent = row }, 15)
		end
		local hint
		if rating.Stars >= 5 then
			hint = "A five-star museum! Visitors can't get enough."
		else
			local needed = (rating.Stars + 0.5 - 1) * 25
			hint = ("Score %s/100  ·  next half star at %s. Show more, rarer and different relics."):format(trimNumber(rating.Score), trimNumber(needed))
		end
		label({ Position = UDim2.new(0, 0, 0, 192), Size = UDim2.new(1, 0, 0, 18), Text = hint, TextColor3 = Theme.Muted, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 14)
	end

	local function renderSecurity(order, security)
		local level = security.Level
		local credits = player:GetAttribute("SecurityCredits") or 0
		local cost = Tuning.GetUpgradeCost(level)
		local inner = card(order, 206)
		label({ Size = UDim2.new(1, 0, 0, 24), Text = ("SECURITY LEVEL %d / %d"):format(level, Tuning.MaxLevel), Font = Theme.FontBlack, TextColor3 = Theme.Gold, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 20)
		for i = 1, Tuning.MaxLevel do
			local pip = new("Frame", { Position = UDim2.new((i - 1) / Tuning.MaxLevel, 2, 0, 30), Size = UDim2.new(1 / Tuning.MaxLevel, -4, 0, 14), BackgroundColor3 = i <= level and Color3.new(1, 1, 1) or TRACK, BorderSizePixel = 0, ZIndex = 5, Parent = inner })
			corner(pip, UDim.new(0, 4))
			if i <= level then
				new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Theme.GoldLight, Color3.fromRGB(205, 140, 30)), Parent = pip })
			end
		end
		local chance = Tuning.GetCatchChance(level)
		local chanceText, perkText
		if cost then
			chanceText = ("Thief catch chance  %d%%  →  %d%% at level %d"):format(chance, Tuning.GetCatchChance(level + 1), level + 1)
			perkText = "Next: " .. (Tuning.LevelPerks[level + 1] or "Better protection")
		else
			chanceText = ("Thief catch chance  %d%%  (maximum)"):format(chance)
			perkText = "Every security upgrade is installed."
		end
		label({ Position = UDim2.new(0, 0, 0, 50), Size = UDim2.new(1, 0, 0, 20), Text = chanceText, Font = Theme.FontBold, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 16)
		label({ Position = UDim2.new(0, 0, 0, 72), Size = UDim2.new(1, 0, 0, 18), Text = perkText, TextColor3 = Theme.GoldLight, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 15)
		ctx.icon("Credits", { Position = UDim2.fromOffset(0, 104), Size = UDim2.fromOffset(22, 22), Parent = inner })
		label({ Position = UDim2.new(0, 28, 0, 104), Size = UDim2.new(0.5, -36, 0, 22), Text = fmt(credits) .. " Security Credits", Font = Theme.FontBold, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 18)
		local affordable = cost ~= nil and credits >= cost
		local balanceNote = "your balance"
		if cost and not affordable then
			balanceNote = ("%d more needed for level %d"):format(cost - credits, level + 1)
		end
		label({ Position = UDim2.new(0, 28, 0, 128), Size = UDim2.new(0.5, -36, 0, 18), Text = balanceNote, TextColor3 = cost and not affordable and Theme.Error or Theme.Muted, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 14)
		local upgrade = button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 100),
			Size = UDim2.new(0.5, 0, 0, 42),
			Text = cost and ("Upgrade  ·  %d credits"):format(cost) or "Max level",
			BackgroundColor3 = affordable and Theme.Gold or Theme.Button,
			TextColor3 = affordable and Theme.Dark or Theme.Text,
			Font = Theme.FontBlack,
			ZIndex = 6,
			Parent = inner,
		}, function()
			ctx.act("UpgradeSecurity")
		end, 18)
		ctx.setEnabled(upgrade, affordable)
		local thief = Tuning.Thief
		label({
			Position = UDim2.new(0, 0, 0, 160),
			Size = UDim2.new(1, 0, 0, 18),
			Text = ("Catching a thief pays %d credits at this level. Heists pay credits too."):format(thief.CaughtCredits + level * thief.CaughtCreditsPerLevel),
			TextColor3 = Theme.Muted,
			TextXAlignment = Left,
			ZIndex = 5,
			Parent = inner,
		}, 14)
	end

	local function renderLog(order, security)
		local log = security.Log or {}
		local rows = math.max(#log, 1)
		local inner = card(order, 56 + rows * 28)
		label({ Size = UDim2.new(0.55, 0, 0, 22), Text = "RECENT BREAK-INS", Font = Theme.FontBlack, TextColor3 = Theme.Gold, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 18)
		label({ Position = UDim2.new(0.55, 0, 0, 2), Size = UDim2.new(0.45, 0, 0, 18), Text = ("Caught %d  ·  Escaped %d"):format(security.Caught or 0, security.Escaped or 0), TextColor3 = Theme.Muted, TextXAlignment = Right, ZIndex = 5, Parent = inner }, 14)
		if #log == 0 then
			label({ Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 20), Text = "No break-ins yet. Thieves strike every 8-15 minutes while relics are on display.", TextColor3 = Theme.Muted, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 14)
			return
		end
		for i, entry in ipairs(log) do
			local y = 30 + (i - 1) * 28
			local dot = new("Frame", { Position = UDim2.new(0, 0, 0, y + 6), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = entry.Caught and Theme.Success or Theme.Error, BorderSizePixel = 0, ZIndex = 5, Parent = inner })
			corner(dot, UDim.new(1, 0))
			local text = entry.Caught and ("Caught  ·  +%d Security Credits"):format(entry.Credits or 0) or ("Escaped  ·  stole %s coins"):format(fmt(entry.Coins or 0))
			label({ Position = UDim2.new(0, 18, 0, y), Size = UDim2.new(0.72, -18, 0, 22), Text = text, Font = Theme.FontBold, TextColor3 = entry.Caught and Theme.Success or Theme.Error, TextXAlignment = Left, ZIndex = 5, Parent = inner }, 15)
			label({ Position = UDim2.new(0.72, 0, 0, y), Size = UDim2.new(0.28, 0, 0, 22), Text = ("Lv %d  ·  %s"):format(entry.Level or 0, ago(entry.T)), TextColor3 = Theme.Muted, TextXAlignment = Right, ZIndex = 5, Parent = inner }, 14)
		end
	end

	ctx.renderers.Security = function()
		ctx.clear(content)
		local security = ctx.State().Security
		if not security then
			label({ Size = UDim2.new(1, -8, 0, 24), Text = "Loading your museum...", TextColor3 = Theme.Muted, ZIndex = 5, Parent = content }, 16)
			return
		end
		renderRating(1, security.Rating)
		renderSecurity(2, security)
		renderLog(3, security)
	end

	player:GetAttributeChangedSignal("SecurityCredits"):Connect(function()
		if ctx.modals.Security.Visible then
			ctx.renderers.Security()
		end
	end)

	ctx.AddMenuButton("Security", 45, function()
		ctx.openModal("Security")
	end)

	---------------------------------------------------------------- break-in alert

	local alert = new("Frame", { Name = "ThiefAlert", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 45, Parent = ctx.gui })
	local edges = {}
	local function edge(position, size, rotation)
		local f = new("Frame", { Position = position, Size = size, BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 45, Parent = alert })
		new("UIGradient", { Rotation = rotation, Transparency = NumberSequence.new(0, 1), Parent = f })
		table.insert(edges, f)
	end
	edge(UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 110), 90)
	edge(UDim2.new(0, 0, 1, -110), UDim2.new(1, 0, 0, 110), -90)
	edge(UDim2.new(0, 0, 0, 0), UDim2.new(0, 110, 1, 0), 0)
	edge(UDim2.new(1, -110, 0, 0), UDim2.new(0, 110, 1, 0), 180)
	local flash = new("Frame", { Name = "ThiefFlash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = RED, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 44, Parent = ctx.gui })
	local beep = new("Sound", { Name = "AlarmBeep", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Parent = ctx.gui })

	local alertToken = 0
	local function runAlert(seconds, color, beeping)
		alertToken += 1
		local token = alertToken
		for _, e in ipairs(edges) do
			e.BackgroundColor3 = color
		end
		alert.Visible = true
		task.spawn(function()
			local stopAt = os.clock() + seconds
			local nextBeep = 0
			while os.clock() < stopAt and alertToken == token do
				local pulse = 0.5 + 0.5 * math.sin(os.clock() * 9)
				for _, e in ipairs(edges) do
					e.BackgroundTransparency = 0.1 + 0.55 * (1 - pulse)
				end
				if beeping and os.clock() >= nextBeep then
					nextBeep = os.clock() + 0.45
					beep.PlaybackSpeed = beep.PlaybackSpeed == 1.25 and 0.95 or 1.25
					beep:Play()
				end
				RunService.RenderStepped:Wait()
			end
			if alertToken == token then
				alert.Visible = false
			end
		end)
	end

	local function screenFlash(color)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.55
		TweenService:Create(flash, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	end

	local function shake(strength, duration)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local stopAt = os.clock() + duration
		local connection
		connection = RunService.RenderStepped:Connect(function()
			if os.clock() > stopAt or not humanoid.Parent then
				humanoid.CameraOffset = Vector3.zero
				connection:Disconnect()
				return
			end
			humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * strength
		end)
	end

	local function banner(text, color, seconds)
		if ctx.ShowBanner then
			ctx.ShowBanner(text, color, seconds)
		else
			ctx.toast(text, color == RED and "error" or "success")
		end
	end

	ctx.OnEvent("Security", function(kind, info)
		if kind ~= "Thief" or type(info) ~= "table" then
			return
		end
		if info.Phase == "Alert" then
			local seconds = info.Seconds or 5
			banner("A thief is breaking into your museum!", RED, seconds + 0.5)
			runAlert(seconds, RED, true)
			screenFlash(RED)
			shake(0.35, 0.4)
		elseif info.Phase == "Result" then
			if info.Caught then
				banner(("Thief caught! +%d Security Credits"):format(info.Credits or 0), Theme.Success, 5)
				runAlert(1.2, Theme.Success, false)
				screenFlash(Theme.Success)
			else
				banner(("The thief escaped with %s coins! Upgrade your Security."):format(fmt(info.Coins or 0)), RED, 6)
				runAlert(1.5, RED, false)
				screenFlash(RED)
				shake(0.25, 0.3)
			end
		end
	end)

	---------------------------------------------------------------- camera sweep

	local cameras = {}
	local function track(model)
		if model:IsA("Model") then
			cameras[model] = { Base = model:GetPivot(), Phase = math.random() * math.pi * 2 }
		end
	end
	CollectionService:GetInstanceAddedSignal("SecurityCam"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("SecurityCam"):Connect(function(model)
		cameras[model] = nil
	end)
	for _, model in ipairs(CollectionService:GetTagged("SecurityCam")) do
		track(model)
	end
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for model, info in pairs(cameras) do
			local body = model.Parent and model:FindFirstChild("Body")
			if body and body.Transparency < 1 then
				model:PivotTo(info.Base * CFrame.Angles(0, math.sin(t * 0.5 + info.Phase) * 0.55, 0))
			end
		end
	end)
end
