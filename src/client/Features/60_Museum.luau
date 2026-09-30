-- Museum Security menu: star rating breakdown, Security Level upgrades, recent thief log, the
-- break-in alert (catch card, off-screen arrow, red edge pulse, beeps), the thief NPC itself (drawn
-- locally from "ThiefFx" events) and the sweep of security cameras.
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

	---------------------------------------------------------------- break-in alert (the museum owner)
	-- A card under the top bar says what to do, counts down and shows how far away the thief is, with a
	-- "Go to museum" button when you're far off; an arrow at the screen edge points at an off-screen thief.
	-- The red edge pulse and beeps are strong for the first seconds and the last five, soft in between.

	local AMBER = Color3.fromRGB(255, 170, 60)
	local GREEN = Theme.Success
	local LOUD_SECONDS = 2.5
	local URGENT_SECONDS = 5

	local function serverNow()
		return workspace:GetServerTimeNow()
	end

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

	local alertCard = ctx.panel({ Name = "ThiefCard", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 84), Size = UDim2.new(0.94, 0, 0, 132), Visible = false, ZIndex = 46, Parent = ctx.gui })
	new("UISizeConstraint", { MaxSize = Vector2.new(460, 132), Parent = alertCard })
	local cardStroke = alertCard:FindFirstChildOfClass("UIStroke")
	cardStroke.Color, cardStroke.Thickness, cardStroke.Transparency = RED, 2, 0
	local cardScale = new("UIScale", { Parent = alertCard })
	local cardTitle = label({ Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -96, 0, 26), Text = "THIEF IN YOUR MUSEUM!", Font = Theme.FontBlack, TextColor3 = RED, TextXAlignment = Left, ZIndex = 47, Parent = alertCard }, 22)
	local cardTime = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.new(0, 76, 0, 30), Text = "", Font = Theme.FontBlack, TextXAlignment = Right, ZIndex = 47, Parent = alertCard }, 26)
	local cardHint = label({ Position = UDim2.new(0, 14, 0, 40), Size = UDim2.new(1, -28, 0, 20), Text = "", Font = Theme.FontBold, TextXAlignment = Left, ZIndex = 47, Parent = alertCard }, 16)
	local timeTrack = new("Frame", { Position = UDim2.new(0, 14, 0, 66), Size = UDim2.new(1, -28, 0, 12), BackgroundColor3 = TRACK, BorderSizePixel = 0, ZIndex = 47, Parent = alertCard })
	corner(timeTrack, UDim.new(1, 0))
	local timeFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = AMBER, BorderSizePixel = 0, ZIndex = 48, Parent = timeTrack })
	corner(timeFill, UDim.new(1, 0))
	local cardOdds = label({ Position = UDim2.new(0, 14, 0, 86), Size = UDim2.new(1, -176, 0, 36), Text = "", TextColor3 = Theme.Muted, TextWrapped = true, TextXAlignment = Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 47, Parent = alertCard }, 14)
	local goHome = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 86), Size = UDim2.new(0, 150, 0, 34), Text = "Go to museum", BackgroundColor3 = Theme.Gold, TextColor3 = Theme.Dark, Font = Theme.FontBlack, ZIndex = 48, Parent = alertCard }, function()
		ctx.act("Teleport", "Museum")
	end, 16)

	local arrow = new("Frame", { Name = "ThiefArrow", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(64, 64), BackgroundTransparency = 1, Visible = false, ZIndex = 46, Parent = ctx.gui })
	local arrowGlyph = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1, Font = Theme.FontBlack, TextSize = 40, Text = "▲", TextColor3 = RED, TextStrokeTransparency = 0.1, ZIndex = 46, Parent = arrow })
	local arrowText = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(110, 18), BackgroundTransparency = 1, Font = Theme.FontBlack, TextSize = 15, TextColor3 = Theme.Text, TextStrokeTransparency = 0.2, Text = "", ZIndex = 46, Parent = arrow })

	local alertToken = 0
	-- Short flash of the screen edges (results). The live alarm below drives the edges itself.
	local function runAlert(seconds, color)
		alertToken += 1
		local token = alertToken
		for _, e in ipairs(edges) do
			e.BackgroundColor3 = color
		end
		alert.Visible = true
		task.spawn(function()
			local stopAt = os.clock() + seconds
			while os.clock() < stopAt and alertToken == token do
				local pulse = 0.5 + 0.5 * math.sin(os.clock() * 9)
				for _, e in ipairs(edges) do
					e.BackgroundTransparency = 0.1 + 0.55 * (1 - pulse)
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

	-- Places the arrow on the screen edge in the direction of `pos` (hidden while `pos` is on screen).
	local function pointAt(pos, distance)
		local camera = workspace.CurrentCamera
		local screen = ctx.gui.AbsoluteSize
		local point, onScreen = camera:WorldToScreenPoint(pos)
		local margin = 56
		if onScreen and point.Z > 0 and point.X > margin and point.X < screen.X - margin and point.Y > margin and point.Y < screen.Y - margin then
			arrow.Visible = false
			return
		end
		local center = screen / 2
		local dir = Vector2.new(point.X, point.Y) - center
		if point.Z < 0 then
			dir = -dir -- behind the camera: the projection is mirrored
		end
		dir = dir.Magnitude > 1 and dir.Unit or Vector2.new(0, -1)
		local reach = math.min((center.X - margin) / math.max(math.abs(dir.X), 1e-3), (center.Y - margin) / math.max(math.abs(dir.Y), 1e-3))
		local at = center + dir * reach
		arrow.Position = UDim2.fromOffset(at.X, at.Y)
		arrowGlyph.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90
		arrowText.Text = distance and ("%d studs"):format(distance) or ""
		arrow.Visible = true
	end

	local alarm -- { Position, EndsAt, Seconds, StartedAt, NextBeep, FarLayout } while the owner has a thief to catch
	local alarmConnection

	local function stopAlarm()
		alarm = nil
		if alarmConnection then
			alarmConnection:Disconnect()
			alarmConnection = nil
		end
		alertCard.Visible = false
		arrow.Visible = false
		alert.Visible = false
	end

	local function updateAlarm()
		local a = alarm
		if not a then
			return
		end
		local now = os.clock()
		local left = a.EndsAt - serverNow()
		if left < -4 then
			stopAlarm() -- the result never arrived (it normally lands right at 0)
			return
		end
		left = math.max(0, left)
		local urgent = left <= URGENT_SECONDS
		cardTime.Text = ("%ds"):format(math.ceil(left))
		cardTime.TextColor3 = urgent and RED or Theme.Text
		local fraction = math.clamp(left / a.Seconds, 0, 1)
		timeFill.Size = UDim2.fromScale(fraction, 1)
		timeFill.BackgroundColor3 = RED:Lerp(AMBER, fraction)

		-- Edges and beeps: loud at first and at the end, a soft reminder in between.
		local loud = now - a.StartedAt < LOUD_SECONDS or urgent
		local pulse = 0.5 + 0.5 * math.sin(now * (urgent and 12 or 7))
		local strength = loud and 1 or 0.35
		for _, e in ipairs(edges) do
			e.BackgroundTransparency = 1 - strength * (0.35 + 0.55 * pulse)
		end
		cardTitle.TextTransparency = urgent and 0.35 * pulse or 0
		if now >= a.NextBeep and left > 0 then
			a.NextBeep = now + (now - a.StartedAt < LOUD_SECONDS and 0.45 or (urgent and 0.6 or 2))
			beep.PlaybackSpeed = beep.PlaybackSpeed == 1.25 and 0.95 or 1.25
			beep:Play()
		end

		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local distance = root and a.Position and math.floor((root.Position - a.Position).Magnitude)
		if distance and distance <= 14 then
			cardHint.Text = "Hold E on the thief to catch them!"
			cardHint.TextColor3 = GREEN
		elseif distance then
			cardHint.Text = ("Run to the thief and hold E  ·  %d studs away"):format(distance)
			cardHint.TextColor3 = Theme.Text
		else
			cardHint.Text = "Run to the thief and hold E to catch them."
			cardHint.TextColor3 = Theme.Text
		end
		local far = distance == nil or distance > 60
		if a.FarLayout ~= far then
			a.FarLayout = far
			goHome.Visible = far
			cardOdds.Size = far and UDim2.new(1, -176, 0, 36) or UDim2.new(1, -28, 0, 36)
		end
		if a.Position then
			pointAt(a.Position, distance)
		end
	end

	local function startAlarm(info)
		stopAlarm()
		local seconds = tonumber(info.Seconds) or Tuning.Thief.CatchSeconds
		alarm = {
			Position = typeof(info.Position) == "Vector3" and info.Position or nil,
			EndsAt = tonumber(info.EndsAt) or serverNow() + seconds,
			Seconds = math.max(seconds, 1),
			StartedAt = os.clock(),
			NextBeep = 0,
		}
		cardOdds.Text = ("If they get away, your Security (Lv %d) still catches them %d%% of the time."):format(info.Level or 0, info.Chance or Tuning.GetCatchChance(info.Level or 0))
		for _, e in ipairs(edges) do
			e.BackgroundColor3 = RED
		end
		alertToken += 1 -- stops a result flash that might still be running
		alert.Visible = true
		alertCard.Visible = true
		cardScale.Scale = 0.6
		ctx.tween(cardScale, ctx.Anim.Pop, { Scale = 1 })
		alarmConnection = RunService.RenderStepped:Connect(updateAlarm)
		updateAlarm()
	end

	ctx.OnEvent("Security", function(kind, info)
		if kind ~= "Thief" or type(info) ~= "table" then
			return
		end
		if info.Phase == "Alert" then
			startAlarm(info)
			screenFlash(RED)
			shake(0.35, 0.4)
		elseif info.Phase == "Result" then
			stopAlarm()
			if info.Caught then
				local how = info.ByPlayer and "You caught the thief red-handed!" or "Your security caught the thief!"
				banner(("%s +%d Security Credits"):format(how, info.Credits or 0), GREEN, 5)
				runAlert(1.2, GREEN)
				screenFlash(GREEN)
			else
				banner(("The thief escaped with %s coins! Upgrade Security to stop the next one."):format(fmt(info.Coins or 0)), RED, 6)
				runAlert(1.5, RED)
				screenFlash(RED)
				shake(0.25, 0.3)
			end
		end
	end)

	---------------------------------------------------------------- the thief (drawn locally for everyone)
	-- The server only decides where the thief stands and how it ends ("Security" "ThiefFx" to every client).
	-- Here the thief slides down a rope through the ceiling, works on the display case with a progress
	-- bar over its head, then is either caught (knocked down, stars, poof) or climbs out with the loot.
	-- The owner sees it through walls (Highlight + billboard); only the owner keeps the Catch prompt.

	local THIEF_DARK = Color3.fromRGB(26, 26, 32)
	local THIEF_STRIPE = Color3.fromRGB(236, 236, 242)
	local THIEF_SKIN = Color3.fromRGB(224, 178, 138)
	local SACK_BROWN = Color3.fromRGB(150, 108, 58)
	local LOOT_GOLD = Color3.fromRGB(255, 205, 70)
	local ROPE_BROWN = Color3.fromRGB(92, 70, 44)
	local DROP_SECONDS = 1.1
	local CLIMB_SECONDS = 0.9
	local KNOCKDOWN_SECONDS = 0.35
	local CAUGHT_LINGER = 1.6 -- seconds the knocked-down thief stays before the poof
	local SKY_DROP = 30 -- rope length when there's no ceiling above the pedestal
	local HEAD_ROOM = 4.4 -- root sits this far below the ceiling at the top of the rope

	local thiefFolder = new("Folder", { Name = "ThiefFx", Parent = workspace })
	local thieves = {} -- [id] = thief state
	local ceilingParams = RaycastParams.new()
	ceilingParams.FilterType = Enum.RaycastFilterType.Exclude

	local function fxPart(parent, size, color, material, shape)
		local p = Instance.new("Part")
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		return p
	end

	-- A masked cat burglar in a striped shirt with a loot sack, reaching forward with a crowbar.
	-- Move it by setting Root.CFrame (hip height: the feet are 3 studs below the root).
	local function buildThief(parent, cf)
		local model = Instance.new("Model")
		model.Name = "Thief"
		local root = fxPart(model, Vector3.new(2, 2, 1), THIEF_DARK)
		root.Name = "Root"
		root.Transparency = 1
		root.CFrame = cf
		model.PrimaryPart = root
		local function limb(size, offset, color, material, shape)
			local p = fxPart(model, size, color, material, shape)
			p.CFrame = cf * offset
			p.Anchored = false
			p.Massless = true
			new("WeldConstraint", { Part0 = root, Part1 = p, Parent = p })
			return p
		end
		local ball, cyl = Enum.PartType.Ball, Enum.PartType.Cylinder
		local upright = CFrame.Angles(0, 0, math.rad(90))
		local fabric = Enum.Material.Fabric
		limb(Vector3.new(0.85, 2.9, 0.85), CFrame.new(-0.5, -1.55, 0), THIEF_DARK)
		limb(Vector3.new(0.85, 2.9, 0.85), CFrame.new(0.5, -1.55, 0), THIEF_DARK)
		limb(Vector3.new(2.1, 2.5, 1.1), CFrame.new(0, 1.15, 0), THIEF_STRIPE, fabric)
		for _, y in ipairs({ 0.35, 0.95, 1.55, 2.15 }) do
			limb(Vector3.new(2.14, 0.26, 1.14), CFrame.new(0, y, 0), THIEF_DARK, fabric)
		end
		for _, x in ipairs({ -1.45, 1.45 }) do
			limb(Vector3.new(0.7, 2.3, 0.8), CFrame.new(x, 1.35, -0.55) * CFrame.Angles(math.rad(55), 0, 0), THIEF_STRIPE, fabric)
		end
		limb(Vector3.new(0.25, 0.25, 2), CFrame.new(0, 0.95, -1.95), Color3.fromRGB(150, 155, 165), Enum.Material.Metal) -- crowbar
		limb(Vector3.new(1.35, 1.35, 1.35), CFrame.new(0, 3.05, 0), THIEF_SKIN, nil, ball)
		limb(Vector3.new(0.36, 1.42, 1.42), CFrame.new(0, 3.12, 0) * upright, THIEF_DARK, fabric, cyl) -- eye mask
		for _, x in ipairs({ -0.27, 0.27 }) do
			limb(Vector3.new(0.2, 0.2, 0.2), CFrame.new(x, 3.13, -0.7), Color3.new(1, 1, 1), Enum.Material.Neon, ball)
		end
		limb(Vector3.new(0.75, 1.46, 1.46), CFrame.new(0, 3.55, 0) * upright, THIEF_DARK, fabric, cyl) -- beanie
		limb(Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 4.02, 0), Color3.fromRGB(220, 50, 60), fabric, ball)
		local sack = limb(Vector3.new(2, 2, 2), CFrame.new(0, 1.5, 1.15), SACK_BROWN, fabric, ball)
		limb(Vector3.new(0.5, 0.6, 0.6), CFrame.new(0, 2.55, 1.15) * upright, Color3.fromRGB(110, 78, 40), fabric, cyl)
		local smoke = new("ParticleEmitter", {
			Enabled = false,
			Color = ColorSequence.new(Color3.fromRGB(190, 190, 200)),
			Transparency = NumberSequence.new(0.15, 1),
			Size = NumberSequence.new(1.5, 4.5),
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(4, 9),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 3,
			Parent = root,
		})
		model.Parent = parent
		return { Model = model, Root = root, Sack = sack, Smoke = smoke }
	end

	local function thiefBillboard(root, isOwner, ownerName)
		local gui = new("BillboardGui", { Size = UDim2.fromOffset(180, 58), StudsOffsetWorldSpace = Vector3.new(0, 5.8, 0), AlwaysOnTop = isOwner, LightInfluence = 0, MaxDistance = isOwner and 100000 or 160, Parent = root })
		local title = new("TextLabel", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = Theme.FontBlack, TextScaled = true, TextColor3 = RED, TextStrokeTransparency = 0.2, Text = "THIEF!", Parent = gui })
		local back = new("Frame", { Position = UDim2.new(0.12, 0, 0, 28), Size = UDim2.new(0.76, 0, 0, 9), BackgroundColor3 = Color3.fromRGB(30, 26, 36), BorderSizePixel = 0, Parent = gui })
		corner(back, UDim.new(1, 0))
		ctx.stroke(back, Color3.new(0, 0, 0), 1, 0.4)
		local bar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = AMBER, BorderSizePixel = 0, Parent = back })
		corner(bar, UDim.new(1, 0))
		local sub = new("TextLabel", { Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 17), BackgroundTransparency = 1, Font = Theme.FontBold, TextScaled = true, TextColor3 = Theme.Text, TextStrokeTransparency = 0.3, Parent = gui })
		sub.Text = isOwner and "Hold E to catch!" or (ownerName and ("Robbing %s's museum"):format(ownerName) or "Cracking the case...")
		return { Title = title, Bar = bar, Back = back, Sub = sub }
	end

	local function placeRope(rope, top, bottomY)
		local length = math.max(top.Y - bottomY, 0.1)
		rope.Size = Vector3.new(length, 0.22, 0.22)
		rope.CFrame = CFrame.new(top.X, top.Y - length / 2, top.Z) * CFrame.Angles(0, 0, math.rad(90))
	end

	local function removeThief(id)
		local thief = thieves[id]
		if thief then
			thieves[id] = nil
			thief.Folder:Destroy()
		end
	end

	-- Smoke puff, then the thief is gone (the emitter lives on a leftover part until the smoke clears).
	local function poof(thief)
		if thief.Poofed then
			return
		end
		thief.Poofed = true
		local puff = fxPart(thief.Folder, Vector3.new(1, 1, 1), THIEF_DARK)
		puff.Transparency = 1
		puff.CFrame = thief.Parts.Root.CFrame
		thief.Parts.Smoke.Parent = puff
		thief.Parts.Smoke:Emit(26)
		thief.Parts.Model:Destroy()
		for _, star in ipairs(thief.Stars or {}) do
			star:Destroy()
		end
		thief.Rope.Transparency = 1
		thief.Sparks.Enabled = false
		thief.Spark.Enabled = false
		local folder = thief.Folder
		task.delay(1.4, function()
			if thieves[thief.Id] == thief then
				thieves[thief.Id] = nil
			end
			folder:Destroy()
		end)
	end

	local function onThiefEnter(info)
		if typeof(info.Frame) ~= "CFrame" or typeof(info.StandAt) ~= "Vector3" or typeof(info.Target) ~= "Vector3" then
			return
		end
		removeThief(info.Id)
		local frame = info.Frame
		local stand = (frame * CFrame.new(info.StandAt)).Position
		local target = (frame * CFrame.new(info.Target)).Position
		local floorY = frame.Position.Y
		local toTarget = Vector3.new(target.X - stand.X, 0, target.Z - stand.Z)
		local facing = toTarget.Magnitude > 0.1 and CFrame.lookAt(Vector3.zero, toTarget) or CFrame.new()
		local ground = CFrame.new(stand.X, floorY + 3, stand.Z) * facing

		-- Rope from the ceiling above (a cut hole) or, with no roof, from high in the sky.
		local exclude = { thiefFolder }
		if player.Character then
			table.insert(exclude, player.Character)
		end
		ceilingParams.FilterDescendantsInstances = exclude
		-- Look past low things (display glass, light fittings) for the real ceiling.
		local origin = Vector3.new(stand.X, floorY + 5, stand.Z)
		local hit
		for _ = 1, 4 do
			hit = workspace:Raycast(origin, Vector3.new(0, floorY + 60 - origin.Y, 0), ceilingParams)
			if not hit or hit.Position.Y >= floorY + 9 then
				break
			end
			origin = hit.Position + Vector3.new(0, 0.05, 0) -- inside that part now, so the next ray skips it
			hit = nil
		end
		local top = hit and hit.Position or Vector3.new(stand.X, floorY + SKY_DROP, stand.Z)

		local folder = new("Folder", { Name = "Thief" .. tostring(info.Id), Parent = thiefFolder })
		local parts = buildThief(folder, ground + Vector3.new(0, top.Y - HEAD_ROOM - ground.Y, 0))
		local isOwner = info.Owner == player.UserId
		local board = thiefBillboard(parts.Root, isOwner, info.OwnerName)
		if isOwner then
			new("Highlight", { FillTransparency = 1, OutlineColor = RED, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Adornee = parts.Model, Parent = folder })
		end
		local rope = fxPart(folder, Vector3.new(1, 0.22, 0.22), ROPE_BROWN, Enum.Material.Fabric, Enum.PartType.Cylinder)
		if hit then
			local hole = fxPart(folder, Vector3.new(0.12, 3.4, 3.4), Color3.fromRGB(8, 8, 10), nil, Enum.PartType.Cylinder)
			hole.CFrame = CFrame.new(top - Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
		-- Sparks where the crowbar meets the display case.
		local spark = fxPart(folder, Vector3.new(0.4, 0.4, 0.4), AMBER, Enum.Material.Neon)
		spark.Transparency = 1
		spark.CFrame = CFrame.new(stand:Lerp(target, 0.62) + Vector3.new(0, 4, 0))
		local sparks = new("ParticleEmitter", {
			Enabled = false,
			Color = ColorSequence.new(Color3.fromRGB(255, 230, 140), AMBER),
			LightEmission = 1,
			Size = NumberSequence.new(0.18, 0),
			Lifetime = NumberRange.new(0.2, 0.45),
			Rate = 30,
			Speed = NumberRange.new(6, 12),
			SpreadAngle = Vector2.new(70, 70),
			Acceleration = Vector3.new(0, -35, 0),
			EmissionDirection = Enum.NormalId.Top,
			Parent = spark,
		})
		local sparkLight = new("PointLight", { Color = AMBER, Range = 8, Brightness = 0, Enabled = false, Parent = spark })
		thieves[info.Id] = {
			Id = info.Id,
			Folder = folder,
			Parts = parts,
			Board = board,
			Rope = rope,
			Sparks = sparks,
			Spark = sparkLight,
			Ground = ground,
			FloorY = floorY,
			Top = top,
			EndsAt = tonumber(info.EndsAt) or serverNow() + Tuning.Thief.CatchSeconds,
			State = "Drop",
			StateAt = os.clock(),
		}
	end

	local function onThiefOutcome(id, phase)
		local thief = thieves[id]
		if not thief or thief.Poofed then
			return
		end
		if phase == "Cancel" then
			poof(thief)
			return
		end
		thief.State = phase
		thief.StateAt = os.clock()
		thief.Sparks.Enabled = false
		thief.Spark.Enabled = false
		local board = thief.Board
		board.Back.Visible = false
		if phase == "Caught" then
			board.Title.Text = "CAUGHT!"
			board.Title.TextColor3 = GREEN
			board.Sub.Text = "Back to jail!"
			thief.Stars = {}
			for i = 1, 3 do
				thief.Stars[i] = fxPart(thief.Folder, Vector3.new(0.45, 0.45, 0.45), Color3.fromRGB(255, 225, 80), Enum.Material.Neon, Enum.PartType.Ball)
			end
		else
			board.Title.Text = "ESCAPED!"
			board.Title.TextColor3 = RED
			board.Sub.Text = "...with a sack of coins"
			thief.Parts.Sack.Color = LOOT_GOLD
			thief.Parts.Sack.Material = Enum.Material.Neon
		end
	end

	ctx.OnEvent("Security", function(kind, info)
		if kind ~= "ThiefFx" or type(info) ~= "table" or info.Id == nil then
			return
		end
		if info.Phase == "Enter" then
			onThiefEnter(info)
		elseif info.Phase == "Caught" or info.Phase == "Escaped" or info.Phase == "Cancel" then
			onThiefOutcome(info.Id, info.Phase)
		end
	end)

	local function easeOut(x)
		return 1 - (1 - x) * (1 - x)
	end

	RunService.Heartbeat:Connect(function()
		if next(thieves) == nil then
			return
		end
		local now = os.clock()
		for id, thief in pairs(thieves) do
			if thief.Poofed then
				continue
			end
			local root = thief.Parts.Root
			local ground = thief.Ground
			local topY = thief.Top.Y - HEAD_ROOM
			local since = now - thief.StateAt
			if thief.State == "Drop" then
				local k = math.clamp(since / DROP_SECONDS, 0, 1)
				local y = topY + (ground.Y - topY) * easeOut(k)
				root.CFrame = ground + Vector3.new(0, y - ground.Y, 0)
				placeRope(thief.Rope, thief.Top, y + 3.8)
				if k >= 1 then
					thief.State = "Work"
					thief.StateAt = now
					thief.Sparks.Enabled = true
					thief.Spark.Enabled = true
				end
			elseif thief.State == "Work" then
				-- Crouch-bob and crowbar jiggle; the rope is left hanging behind.
				root.CFrame = ground * CFrame.new(0, -0.3 * math.abs(math.sin(now * 5)), 0) * CFrame.Angles(math.sin(now * 17) * 0.05, 0, 0)
				placeRope(thief.Rope, thief.Top, thief.FloorY + 1)
				thief.Spark.Brightness = 1 + math.random() * 2
				local left = thief.EndsAt - serverNow()
				thief.Board.Bar.Size = UDim2.fromScale(math.clamp(1 - left / Tuning.Thief.CatchSeconds, 0, 1), 1)
				if left < -6 then
					poof(thief) -- the outcome never arrived
				end
			elseif thief.State == "Caught" then
				-- Knocked flat on its back, stars circling, then a poof.
				local tip = easeOut(math.clamp(since / KNOCKDOWN_SECONDS, 0, 1)) * math.rad(80)
				root.CFrame = ground * CFrame.new(0, -3, 0) * CFrame.Angles(tip, 0, 0) * CFrame.new(0, 3, 0)
				local head = (root.CFrame * CFrame.new(0, 3.2, 0)).Position
				for i, star in ipairs(thief.Stars) do
					local a = now * 5 + i * (math.pi * 2 / 3)
					star.CFrame = CFrame.new(head + Vector3.new(math.cos(a) * 1.3, 1.2, math.sin(a) * 1.3))
				end
				placeRope(thief.Rope, thief.Top, math.min(thief.Top.Y, thief.FloorY + 1 + since * 30))
				if since >= CAUGHT_LINGER then
					poof(thief)
				end
			elseif thief.State == "Escaped" then
				-- Clips back onto the rope and zips up through the hole with the loot.
				local k = math.clamp(since / CLIMB_SECONDS, 0, 1)
				local y = ground.Y + (topY - ground.Y) * k * k
				root.CFrame = ground + Vector3.new(0, y - ground.Y, 0)
				placeRope(thief.Rope, thief.Top, y + 3.8)
				if k >= 1 then
					removeThief(id)
				end
			end
		end
	end)

	-- Only the robbed museum's owner can catch its thief: hide everyone else's copy of the Catch prompt.
	task.spawn(function()
		local museums = workspace:WaitForChild("RelicRNG"):WaitForChild("Museums")
		local function hideForeignPrompt(inst)
			if inst:IsA("ProximityPrompt") and inst.Name == "CatchPrompt" then
				local point = inst.Parent
				if point and point:GetAttribute("OwnerUserId") ~= player.UserId then
					inst.Enabled = false
				end
			end
		end
		museums.DescendantAdded:Connect(hideForeignPrompt)
		for _, inst in ipairs(museums:GetDescendants()) do
			hideForeignPrompt(inst)
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
