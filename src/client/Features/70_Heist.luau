-- Heists: the NPC museum heist menu (museums, energy, notoriety, tool shop) and the in-heist HUD:
-- timer, alarm meter, objective, tool bar (keys 1-5), detection flashes, lockdown banner and results.
-- The server (Services.Heist) runs the heist; this only draws what it's told via "Heist" events.
-- Guards and camera heads exist on the server only as numbers: they are built and animated here,
-- locally, from the Start / State payloads (FeatureConfig.Heist has the model builders). Once the
-- museum has streamed in this sends HeistReady so the server lets the thief go.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local Config, Theme, player = ctx.Config, ctx.Theme, ctx.player
	local new, label, button, corner, stroke, fmt, abbr = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.stroke, ctx.fmt, ctx.abbr
	local gui = ctx.gui
	local Tuning = require(ctx.Shared:WaitForChild("FeatureConfig"):WaitForChild("Heist"))

	local RED = Color3.fromRGB(255, 60, 70)
	local GREEN = Color3.fromRGB(70, 240, 140)
	local BLUE = Color3.fromRGB(90, 175, 255)
	local PURPLE = Color3.fromRGB(165, 110, 255)
	local AMBER = Color3.fromRGB(255, 190, 60)
	local SLOT = Color3.fromRGB(38, 36, 50)

	-- Per-museum colour grade applied locally while inside.
	local MOOD = {
		GildedGallery = Color3.fromRGB(255, 222, 205),
		ObsidianVault = Color3.fromRGB(200, 215, 255),
		SkyPalace = Color3.fromRGB(228, 214, 255),
	}
	local FAIL_TITLES = {
		Caught = "BUSTED!",
		Timeout = "TIME'S UP",
		KnockedOut = "KNOCKED OUT",
		Abandoned = "HEIST ABANDONED",
		Left = "HEIST FAILED",
		Cancelled = "HEIST CANCELLED",
	}
	local FAIL_LINES = {
		Caught = "A guard caught you red-handed.",
		Timeout = "The doors sealed before you got out.",
		KnockedOut = "You went down inside the museum.",
		Abandoned = "You slipped out empty-handed.",
		Left = "You left the museum.",
		Cancelled = "Couldn't get you inside. Your energy was refunded.",
	}

	local function serverNow()
		return workspace:GetServerTimeNow()
	end

	local function clock(seconds)
		seconds = math.max(0, math.ceil(seconds))
		return ("%d:%02d"):format(seconds // 60, seconds % 60)
	end

	local function heistState()
		return ctx.State().Heist or { Tools = {}, Wins = 0, Fails = 0, BestTimes = {} }
	end

	---------------------------------------------------------------- lobby modal

	local frame, content = ctx.createModal("Heists", "Museum Heists")
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	local live = {} -- labels refreshed every second while the modal is open

	local function block(order, height, transparent)
		local f = new("Frame", { Size = UDim2.new(1, -8, 0, height), BackgroundColor3 = Theme.PanelLight, BackgroundTransparency = transparent and 1 or 0.2, LayoutOrder = order, ZIndex = 5, Parent = content })
		if not transparent then
			corner(f, UDim.new(0, 8))
		end
		return f
	end

	local function energyLine()
		local energy = player:GetAttribute("HeistEnergy") or 0
		local cap = player:GetAttribute("HeistMaxEnergy") or Tuning.BaseEnergy
		local nextAt = player:GetAttribute("HeistEnergyNextAt") or 0
		if energy >= cap or nextAt <= 0 then
			return "Energy full"
		end
		return "+1 energy in " .. clock(nextAt - serverNow())
	end

	local function cooldownLeft()
		return math.max(0, (player:GetAttribute("HeistCooldownUntil") or 0) - serverNow())
	end

	local function startBlocker(mapId)
		local info = Tuning.Maps[mapId]
		if player:GetAttribute("InHeist") then
			return "In a heist"
		elseif (player:GetAttribute("Level") or 1) < info.Level then
			return "Locked · Curator Lv " .. info.Level
		elseif (player:GetAttribute("HeistEnergy") or 0) < 1 then
			return "No energy"
		elseif cooldownLeft() > 0 then
			return "Lie low " .. clock(cooldownLeft())
		end
		return nil
	end

	local refreshLive
	local function render()
		ctx.clear(content)
		table.clear(live)
		local hs = heistState()
		local notoriety = player:GetAttribute("Notoriety") or 0
		local rankIndex, rank, nextRank = Tuning.GetRank(notoriety)

		-- Header: rank + progress, energy pips, credits.
		local header = block(1, 84)
		stroke(header, rank.Color, 1.5, 0.35)
		label({ Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(0.55, -12, 0, 14), Text = ("NOTORIETY RANK %d / %d"):format(rankIndex, #Tuning.Ranks), Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = header }, 12)
		label({ Position = UDim2.new(0, 12, 0, 20), Size = UDim2.new(0.55, -12, 0, 28), Text = rank.Name, Font = Theme.FontBlack, TextColor3 = rank.Color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = header }, 24)
		local bar = new("Frame", { Position = UDim2.new(0, 12, 0, 54), Size = UDim2.new(0.55, -12, 0, 18), BackgroundColor3 = SLOT, BorderSizePixel = 0, ZIndex = 5, Parent = header })
		corner(bar, UDim.new(1, 0))
		local progress = nextRank and (notoriety - rank.Min) / (nextRank.Min - rank.Min) or 1
		local fill = new("Frame", { Size = UDim2.fromScale(math.clamp(progress, 0.03, 1), 1), BackgroundColor3 = rank.Color, BorderSizePixel = 0, ZIndex = 5, Parent = bar })
		corner(fill, UDim.new(1, 0))
		label({ Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = nextRank and ("%s  ·  %s to %s"):format(fmt(notoriety), fmt(nextRank.Min - notoriety), nextRank.Name) or (fmt(notoriety) .. "  ·  max rank"), Font = Theme.FontBold, TextStrokeTransparency = 0.4, ZIndex = 6, Parent = bar }, 12)

		local energy = player:GetAttribute("HeistEnergy") or 0
		local cap = player:GetAttribute("HeistMaxEnergy") or Tuning.BaseEnergy
		local pips = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.new(0.42, 0, 0, 22), BackgroundTransparency = 1, ZIndex = 5, Parent = header })
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 5), Parent = pips })
		label({ Size = UDim2.new(0, 60, 1, 0), Text = "ENERGY", Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 0, ZIndex = 5, Parent = pips }, 13)
		for i = 1, cap do
			local pip = new("Frame", { Size = UDim2.new(0, 22, 0, 22), BackgroundColor3 = i <= energy and PURPLE or SLOT, BorderSizePixel = 0, LayoutOrder = i, ZIndex = 5, Parent = pips })
			corner(pip, UDim.new(0, 6))
			stroke(pip, i <= energy and Color3.fromRGB(215, 185, 255) or Color3.fromRGB(70, 65, 90), 1, 0.2)
		end
		live.Energy = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 36), Size = UDim2.new(0.42, 0, 0, 18), Text = energyLine(), TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5, Parent = header }, 14)
		label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 56), Size = UDim2.new(0.42, 0, 0, 18), Text = ("%s Security Credits  ·  %d won  ·  %d failed"):format(fmt(player:GetAttribute("SecurityCredits") or 0), hs.Wins or 0, hs.Fails or 0), TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5, Parent = header }, 13)

		-- Museum cards.
		local cards = block(2, 286, true)
		new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 1, 0), CellPadding = UDim2.new(0, 9, 0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = cards })
		local level = player:GetAttribute("Level") or 1
		local income = player:GetAttribute("IncomePerMin") or 0
		live.Starts = {}
		for i, mapId in ipairs(Tuning.MapOrder) do
			local info = Tuning.Maps[mapId]
			local locked = level < info.Level
			local card = new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 18, 28), BackgroundTransparency = 0.05, LayoutOrder = i, ZIndex = 5, ClipsDescendants = true, Parent = cards })
			corner(card, UDim.new(0, 10))
			stroke(card, info.Color, 1.5, locked and 0.6 or 0.15)
			local stripe = new("Frame", { Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = info.Color, BorderSizePixel = 0, ZIndex = 6, Parent = card })
			new("UIGradient", { Transparency = NumberSequence.new(0, 0.7), Parent = stripe })
			label({ Position = UDim2.new(0, 10, 0, 12), Size = UDim2.new(1, -20, 0, 22), Text = info.Name, Font = Theme.FontBlack, TextColor3 = locked and Theme.Muted or info.Color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = card }, 18)
			local pill = label({ Position = UDim2.new(0, 10, 0, 38), Size = UDim2.new(0, 64, 0, 18), Text = info.Difficulty:upper(), Font = Theme.FontBlack, TextColor3 = Theme.Dark, BackgroundTransparency = 0, BackgroundColor3 = info.Color, ZIndex = 6, Parent = card }, 12)
			corner(pill, UDim.new(1, 0))
			label({ Position = UDim2.new(0, 82, 0, 38), Size = UDim2.new(1, -92, 0, 18), Text = "Curator Lv " .. info.Level, Font = Theme.FontBold, TextColor3 = locked and Theme.Error or Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = card }, 13)
			label({ Position = UDim2.new(0, 10, 0, 62), Size = UDim2.new(1, -20, 0, 40), Text = info.Blurb, TextColor3 = Theme.Muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 6, Parent = card }, 14)
			local estimate = Tuning.Rewards(mapId, income, Tuning.Duration / 2, Tuning.Duration, false, level)
			local lines = {
				{ "~" .. abbr(estimate.Coins) .. " coins", Theme.GoldLight },
				{ ("+%d Security Credits"):format(estimate.Credits), BLUE },
				{ ("+%d Notoriety"):format(estimate.Notoriety), PURPLE },
				{ Config.Rarities[info.MinTier].Name .. "+ relic loot", Config.Rarities[info.MinTier].Color },
			}
			for j, line in ipairs(lines) do
				label({ Position = UDim2.new(0, 10, 0, 108 + (j - 1) * 23), Size = UDim2.new(1, -20, 0, 20), Text = line[1], Font = Theme.FontBold, TextColor3 = line[2], TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = card }, 16)
			end
			local best = hs.BestTimes and hs.BestTimes[mapId]
			label({ Position = UDim2.new(0, 10, 0, 202), Size = UDim2.new(1, -20, 0, 18), Text = best and ("Best escape " .. clock(best)) or "Not cracked yet", TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = card }, 14)
			local start = button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 38), Text = startBlocker(mapId) or "START HEIST", Font = Theme.FontBlack, ZIndex = 7, Parent = card }, function()
				if startBlocker(mapId) then
					return
				end
				local ok = ctx.act("StartHeist", mapId)
				if ok then
					ctx.closeModals()
				end
			end, 16)
			live.Starts[mapId] = start
		end

		-- Tool shop.
		label({ Size = UDim2.new(1, -8, 0, 24), Text = "BLACK MARKET TOOLS", Font = Theme.FontBlack, TextColor3 = Theme.Gold, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3, ZIndex = 5, Parent = content }, 18)
		for i, toolId in ipairs(Tuning.ToolOrder) do
			local tool = Tuning.Tools[toolId]
			local row = block(3 + i, 48)
			local key = label({ Position = UDim2.new(0, 8, 0.5, -15), Size = UDim2.new(0, 30, 0, 30), Text = tostring(tool.Key), Font = Theme.FontBlack, TextColor3 = Theme.Dark, BackgroundTransparency = 0, BackgroundColor3 = tool.Color, ZIndex = 6, Parent = row }, 16)
			corner(key, UDim.new(0, 8))
			label({ Position = UDim2.new(0, 48, 0, 5), Size = UDim2.new(0.62, -48, 0, 20), Text = tool.Name, Font = Theme.FontBold, TextColor3 = tool.Color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = row }, 16)
			label({ Position = UDim2.new(0, 48, 0, 25), Size = UDim2.new(0.62, -48, 0, 17), Text = tool.Description, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = row }, 13)
			local owned = (hs.Tools and hs.Tools[toolId]) or 0
			label({ Position = UDim2.new(0.62, 0, 0, 0), Size = UDim2.new(0.12, 0, 1, 0), Text = "x" .. owned, Font = Theme.FontBlack, TextColor3 = owned > 0 and Theme.Text or Theme.Muted, ZIndex = 6, Parent = row }, 18)
			local canAfford = (player:GetAttribute("Coins") or 0) >= tool.Price
			button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0.24, 0, 0, 34), Text = "Buy  ·  " .. abbr(tool.Price), BackgroundColor3 = canAfford and Theme.Gold or Theme.Button, TextColor3 = canAfford and Theme.Dark or Theme.Muted, ZIndex = 7, Parent = row }, function()
				ctx.act("BuyHeistTool", toolId)
			end, 15)
		end
		label({ Size = UDim2.new(1, -8, 0, 36), Text = "Reach the relic, hold E to steal it, then get back to the green EXIT. Guards, cameras, lasers and pressure plates raise the alarm; at 100% the museum locks down.", TextWrapped = true, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 20, ZIndex = 5, Parent = content }, 13)
		refreshLive()
	end

	-- Cheap per-second refresh of the countdowns and Start buttons.
	function refreshLive()
		if live.Energy then
			live.Energy.Text = energyLine()
		end
		for mapId, start in pairs(live.Starts or {}) do
			if start.Parent then
				local blocker = startBlocker(mapId)
				start.Text = blocker or "START HEIST"
				start.BackgroundColor3 = blocker and Theme.Button or Tuning.Maps[mapId].Color
				start.TextColor3 = blocker and Theme.Muted or Theme.Dark
				ctx.setEnabled(start, blocker == nil)
			end
		end
	end

	ctx.renderers.Heists = render
	for _, name in ipairs({ "HeistEnergy", "HeistMaxEnergy", "Notoriety", "Level", "SecurityCredits" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if frame.Visible then
				render()
			end
		end)
	end
	ctx.AddMenuButton("Heists", 50, function()
		ctx.openModal("Heists")
	end)

	---------------------------------------------------------------- in-heist HUD

	local scaleTargets = {}
	local function autoScale(inst)
		table.insert(scaleTargets, new("UIScale", { Parent = inst }))
	end

	local hud = ctx.panel({ Name = "HeistHud", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.new(0, 272, 0, 178), Visible = false, ZIndex = 8, Parent = gui })
	autoScale(hud)
	local hudStroke = hud:FindFirstChildOfClass("UIStroke")
	local mapLabel = label({ Position = UDim2.new(0, 14, 0, 8), Size = UDim2.new(1, -110, 0, 16), Text = "", Font = Theme.FontBold, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = hud }, 13)
	local timerLabel = label({ Position = UDim2.new(0, 14, 0, 24), Size = UDim2.new(0.6, -14, 0, 40), Text = "3:00", Font = Theme.FontBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = hud }, 38)
	button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.new(0, 84, 0, 26), Text = "Abandon", BackgroundColor3 = Color3.fromRGB(60, 24, 30), ZIndex = 10, Parent = hud }, function()
		ctx.act("AbandonHeist")
	end, 13)
	local alarmTitle = label({ Position = UDim2.new(0, 14, 0, 68), Size = UDim2.new(0.5, 0, 0, 14), Text = "ALARM", Font = Theme.FontBlack, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = hud }, 12)
	local alarmPct = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 66), Size = UDim2.new(0.4, 0, 0, 16), Text = "0%", Font = Theme.FontBlack, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 9, Parent = hud }, 14)
	local alarmBar = new("Frame", { Position = UDim2.new(0, 14, 0, 86), Size = UDim2.new(1, -28, 0, 16), BackgroundColor3 = SLOT, BorderSizePixel = 0, ZIndex = 9, Parent = hud })
	corner(alarmBar, UDim.new(1, 0))
	local alarmBarStroke = stroke(alarmBar, RED, 1.5, 1)
	local alarmFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0, ZIndex = 10, Parent = alarmBar })
	corner(alarmFill, UDim.new(1, 0))
	for _, x in ipairs({ 0.25, 0.5, 0.75 }) do
		new("Frame", { Position = UDim2.fromScale(x, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 11, Parent = alarmBar })
	end
	local objective = label({ Position = UDim2.new(0, 14, 0, 110), Size = UDim2.new(1, -28, 0, 24), Text = "", Font = Theme.FontBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = hud }, 19)
	local statusLine = label({ Position = UDim2.new(0, 14, 0, 138), Size = UDim2.new(1, -28, 0, 30), Text = "", TextColor3 = Theme.Muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 9, Parent = hud }, 13)

	-- Tool bar (bottom centre, where the roll panel normally sits).
	local toolbar = new("Frame", { Name = "HeistTools", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(0, 5 * 84 + 4 * 8, 0, 92), BackgroundTransparency = 1, Visible = false, ZIndex = 8, Parent = gui })
	autoScale(toolbar)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = toolbar })
	local toolSlots = {}
	local useTool

	for i, toolId in ipairs(Tuning.ToolOrder) do
		local tool = Tuning.Tools[toolId]
		local slot = new("TextButton", { Size = UDim2.new(0, 84, 0, 92), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.1, AutoButtonColor = true, Text = "", LayoutOrder = i, ZIndex = 9, Parent = toolbar })
		corner(slot, UDim.new(0, 12))
		local slotStroke = stroke(slot, tool.Color, 2, 0.3)
		local keyBadge = label({ Position = UDim2.new(0, 6, 0, 6), Size = UDim2.new(0, 22, 0, 22), Text = tostring(tool.Key), Font = Theme.FontBlack, TextColor3 = Theme.Dark, BackgroundTransparency = 0, BackgroundColor3 = tool.Color, ZIndex = 10, Parent = slot }, 14)
		corner(keyBadge, UDim.new(0, 6))
		local count = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.new(0, 40, 0, 22), Text = "x0", Font = Theme.FontBlack, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 10, Parent = slot }, 17)
		label({ Position = UDim2.new(0, 6, 0, 34), Size = UDim2.new(1, -12, 0, 34), Text = tool.Name, Font = Theme.FontBold, TextWrapped = true, TextColor3 = tool.Color, ZIndex = 10, Parent = slot }, 15)
		local state = label({ Position = UDim2.new(0, 6, 1, -22), Size = UDim2.new(1, -12, 0, 16), Text = "", Font = Theme.FontBlack, TextColor3 = Theme.Text, ZIndex = 10, Parent = slot }, 12)
		slot.Activated:Connect(function()
			useTool(toolId)
		end)
		toolSlots[toolId] = { Slot = slot, Stroke = slotStroke, Count = count, State = state }
	end

	-- Red screen-edge vignette for detection and lockdown.
	local vignette = new("Frame", { Name = "HeistVignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 1, Parent = gui })
	local edges = {}
	for _, e in ipairs({
		{ UDim2.new(1, 0, 0.24, 0), UDim2.new(0, 0, 0, 0), 90 },
		{ UDim2.new(1, 0, 0.24, 0), UDim2.new(0, 0, 0.76, 0), 270 },
		{ UDim2.new(0.18, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 },
		{ UDim2.new(0.18, 0, 1, 0), UDim2.new(0.82, 0, 0, 0), 180 },
	}) do
		local edge = new("Frame", { Size = e[1], Position = e[2], BackgroundColor3 = RED, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1, Parent = vignette })
		new("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new(0, 1), Parent = edge })
		table.insert(edges, edge)
	end
	local flashAlpha = 0
	local flashColor = RED
	local function setVignette(alpha, color)
		for _, edge in ipairs(edges) do
			edge.BackgroundTransparency = 1 - math.clamp(alpha, 0, 1)
			if color then
				edge.BackgroundColor3 = color
			end
		end
	end

	local lockdownBanner = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.18, 0), Size = UDim2.new(0, 520, 0, 92), BackgroundTransparency = 1, Visible = false, ZIndex = 12, Parent = gui })
	autoScale(lockdownBanner)
	local lockdownTitle = label({ Size = UDim2.new(1, 0, 0, 60), Text = "LOCKDOWN", Font = Theme.FontBlack, TextColor3 = RED, TextStrokeTransparency = 0, TextStrokeColor3 = Color3.fromRGB(40, 0, 0), ZIndex = 12, Parent = lockdownBanner }, 56)
	local lockdownSub = label({ Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 0, 26), Text = "The guards are hunting you. Run for the EXIT!", Font = Theme.FontBold, TextStrokeTransparency = 0.2, ZIndex = 12, Parent = lockdownBanner }, 20)

	-- "SNEAKING IN..." while the museum streams in and the thief is held at the door, then "GO!".
	local readyLabel = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.new(0.8, 0, 0, 64), Text = "", Font = Theme.FontBlack, TextColor3 = Theme.GoldLight, TextStrokeTransparency = 0.15, TextStrokeColor3 = Color3.fromRGB(30, 20, 5), Visible = false, ZIndex = 12, Parent = gui }, 52)
	local readyScale = new("UIScale", { Parent = readyLabel })

	local function refreshScale()
		local width = gui.AbsoluteSize.X
		local s = math.clamp(width / 1100, 0.62, 1)
		for _, scale in ipairs(scaleTargets) do
			scale.Scale = s
		end
		-- Below the top bar on narrow screens so nothing overlaps.
		hud.Position = width >= 1180 and UDim2.new(1, -12, 0, 10) or UDim2.new(1, -12, 0, 176 * s + 10)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshScale)
	refreshScale()

	---------------------------------------------------------------- heist state

	local heist -- current heist info from the server, nil when not in one
	local mood
	local hidden = {}
	local heistToken = 0 -- bumps on every Start / End so stale waits and delays can tell they're stale

	---------------------------------------------------------------- world visuals (local only)

	local Sec = Tuning.Security
	local CEILING_LIGHT_TAG = "HeistCeilingLight"
	local STATE_INTERVAL = 1 / Sec.TickRate -- guards glide from one State sample to the next over one tick
	local FLASHLIGHT_PITCH = math.rad(-10)
	local LED_DARK = Color3.fromRGB(70, 12, 16)
	local EMP_DIM = Tuning.EmpBlue:Lerp(Color3.new(0, 0, 0), 0.45)
	local BEAM_CALM = NumberSequence.new(0.72, 0.93)
	local BEAM_WATCHING = NumberSequence.new(0.4, 0.78)

	local fx -- workspace folder with this heist's guard and camera-head models
	local guards = {} -- [i] = { Parts, From, To, FromYaw, ToYaw, At, Moving, Range }
	local cams = {} -- [i] = { Parts, Pos, BaseYaw, Pitch, Phase, Mode }
	local watching = {} -- [camera index] = true while that camera can see the thief (reused every frame)
	local litCeiling = {} -- [SpotLight] = brightness before the lockdown pulse
	local beamParams = RaycastParams.new()
	beamParams.FilterType = Enum.RaycastFilterType.Include
	beamParams.FilterDescendantsInstances = {}

	local function angleLerp(a, b, t)
		local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
		return a + diff * t
	end

	local function clearWorld()
		for _, guard in ipairs(guards) do
			guard.Parts.End:Destroy()
		end
		for _, cam in ipairs(cams) do
			cam.Parts.End:Destroy()
		end
		table.clear(guards)
		table.clear(cams)
		if fx then
			fx:Destroy()
			fx = nil
		end
		-- The server never changes these brightnesses, so put them back here, or the next heist in this
		-- pooled museum would start with the lights stuck mid-pulse.
		for light, brightness in pairs(litCeiling) do
			if light.Parent then
				light.Brightness = brightness
			end
		end
		table.clear(litCeiling)
		beamParams.FilterDescendantsInstances = {}
	end

	local function buildWorld(cameras)
		clearWorld()
		fx = new("Folder", { Name = "HeistClientFx", Parent = workspace })
		for i, cam in ipairs(type(cameras) == "table" and cameras or {}) do
			local parts = Tuning.BuildCameraHead(fx, Tuning.CameraCFrame(cam.Pos, cam.BaseYaw, cam.Pitch), workspace.Terrain)
			cams[i] = { Parts = parts, Pos = cam.Pos, BaseYaw = cam.BaseYaw, Pitch = cam.Pitch, Phase = cam.Phase }
		end
	end

	-- G packs every guard as x, z, yaw, look. Guards are built on first sight and glide between samples.
	local function syncGuards(g)
		if not fx or type(g) ~= "table" then
			return
		end
		local now = os.clock()
		local floorY = heist.FloorY or 0
		for i = 1, #g // 4 do
			local x, z, yaw, look = g[i * 4 - 3], g[i * 4 - 2], g[i * 4 - 1], g[i * 4]
			local target = Vector3.new(x, floorY, z)
			local guard = guards[i]
			if not guard then
				guard = { Parts = Tuning.BuildGuardModel(fx, target, workspace.Terrain), From = target, To = target, FromYaw = yaw, ToYaw = yaw, At = now }
				guards[i] = guard
			else
				local alpha = math.clamp((now - guard.At) / STATE_INTERVAL, 0, 1)
				guard.From = guard.From:Lerp(guard.To, alpha)
				guard.FromYaw = angleLerp(guard.FromYaw, guard.ToYaw, alpha)
				guard.To, guard.ToYaw, guard.At = target, yaw, now
			end
			guard.Moving = (guard.To - guard.From).Magnitude > 0.05
			Tuning.SetGuardLook(guard.Parts, look)
		end
	end

	-- Remembers the ceiling lights of this museum so the lockdown can pulse them (and End restore them).
	local function collectCeilingLights()
		if not heist or not heist.Model or next(litCeiling) then
			return
		end
		for _, panel in ipairs(CollectionService:GetTagged(CEILING_LIGHT_TAG)) do
			local light = panel:IsDescendantOf(heist.Model) and panel:FindFirstChildOfClass("SpotLight")
			if light then
				litCeiling[light] = light.Brightness
			end
		end
	end

	-- Moves guards, flashlight beams (as long as the guard's real sight range) and sweeping cameras.
	local function animateWorld(t)
		if not fx then
			return
		end
		local now = os.clock()
		local range = (heist.ShoesUntil or 0) > t and Sec.SilentRange or Sec.GuardRange
		for i, guard in ipairs(guards) do
			local alpha = math.clamp((now - guard.At) / STATE_INTERVAL, 0, 1)
			local pos = guard.From:Lerp(guard.To, alpha)
			local facing = CFrame.Angles(0, angleLerp(guard.FromYaw, guard.ToYaw, alpha), 0)
			local stride = guard.Moving and math.sin(now * 9 + i) or 0
			local root = CFrame.new(pos.X, pos.Y + 3 + math.abs(stride) * 0.18, pos.Z) * facing * CFrame.Angles(0, 0, stride * 0.05)
			local parts = guard.Parts
			parts.Root.CFrame = root
			if guard.Range ~= range then
				guard.Range = range
				parts.Light.Range = range
			end
			if parts.Beam.Enabled then
				local origin = (root * CFrame.new(1.45, 1.35, -2.5)).Position
				local reach = (facing * CFrame.Angles(FLASHLIGHT_PITCH, 0, 0)).LookVector * range
				local hit = workspace:Raycast(origin, reach, beamParams)
				parts.End.WorldPosition = hit and hit.Position or origin + reach
			end
		end

		local elapsed = heist.Go and t - heist.StartedAt or 0
		local emp = (heist.EmpUntil or 0) > t
		table.clear(watching)
		for _, index in ipairs(type(heist.CS) == "table" and heist.CS or {}) do
			watching[index] = true
		end
		for i, cam in ipairs(cams) do
			local parts = cam.Parts
			local cf = Tuning.CameraCFrame(cam.Pos, Tuning.CameraYaw(cam.BaseYaw, cam.Phase, elapsed), cam.Pitch)
			parts.Pivot.CFrame = cf
			local mode = emp and "Emp" or (watching[i] and "Watching" or "Calm")
			if cam.Mode ~= mode then
				cam.Mode = mode
				parts.Light.Enabled = mode ~= "Emp"
				parts.Beam.Enabled = mode ~= "Emp"
				parts.Beam.Transparency = mode == "Watching" and BEAM_WATCHING or BEAM_CALM
				parts.Lens.Color = mode == "Emp" and EMP_DIM or Tuning.CameraRed
			end
			if mode ~= "Emp" then
				local reach = cf.LookVector * Sec.CameraRange
				local hit = workspace:Raycast(cf.Position, reach, beamParams)
				parts.End.WorldPosition = hit and hit.Position or cf.Position + reach
			end
			-- LED: a slow blink while sweeping, a fast strobe while it can see you, off during an EMP.
			local lit = (mode == "Watching" and now % 0.2 < 0.1) or (mode == "Calm" and now % 1.2 < 0.15)
			parts.Led.Color = mode == "Emp" and EMP_DIM or (lit and Tuning.CameraRed or LED_DARK)
		end

		if heist.Lockdown then
			collectCeilingLights()
			local pulse = 0.5 + 0.5 * math.sin(now * 7)
			for light in pairs(litCeiling) do
				light.Brightness = 0.6 + pulse * 4
			end
		end
	end

	local function empBurst(pos)
		if not fx or typeof(pos) ~= "Vector3" then
			return
		end
		local ball = new("Part", { Name = "EmpBurst", Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Material = Enum.Material.ForceField, Color = BLUE, Parent = fx })
		ball.Size = Vector3.one * 3
		ball.Position = pos
		local glow = new("PointLight", { Color = BLUE, Range = 40, Brightness = 6, Parent = ball })
		local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(ball, info, { Size = Vector3.one * 70, Transparency = 1 }):Play()
		TweenService:Create(glow, info, { Brightness = 0 }):Play()
		task.delay(0.8, ball.Destroy, ball)
	end

	-- Waits for the museum to stream in (floor plus every wall), then tells the server we're ready.
	-- The server starts anyway after its own timeout, so this never blocks a heist.
	local function reportReady(token, modelName)
		local deadline = os.clock() + 10
		local root = workspace:WaitForChild("RelicRNG", 10)
		local folder = root and root:WaitForChild("ActiveHeists", 10)
		local model
		while folder and os.clock() < deadline and heistToken == token do
			local candidate = folder:FindFirstChild(modelName)
			local solid = candidate and candidate:FindFirstChild("Solid")
			if solid and candidate:FindFirstChild("Floor") and #solid:GetChildren() >= (candidate:GetAttribute("SolidCount") or 0) then
				model = candidate
				break
			end
			task.wait(0.1)
		end
		if heistToken ~= token then
			return
		end
		if model then
			heist.Model = model
			beamParams.FilterDescendantsInstances = { model.Solid, model.Floor }
		end
		pcall(function()
			ctx.Remotes.Action:InvokeServer("HeistReady")
		end)
	end

	local function setWorldHud(inHeist)
		local rollPanel = gui:FindFirstChild("RollPanel")
		if inHeist then
			table.clear(hidden)
			for _, inst in ipairs({ rollPanel, ctx.menu }) do
				if inst and inst.Visible then
					inst.Visible = false
					table.insert(hidden, inst)
				end
			end
		else
			for _, inst in ipairs(hidden) do
				inst.Visible = true
			end
			table.clear(hidden)
		end
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, not inHeist)
	end

	local function setMood(mapId)
		if mood then
			mood:Destroy()
			mood = nil
		end
		if mapId then
			mood = new("ColorCorrectionEffect", { Name = "HeistMood", Brightness = -0.04, Contrast = 0.22, Saturation = 0.12, TintColor = MOOD[mapId] or Color3.new(1, 1, 1), Parent = Lighting })
		end
	end

	local function refreshTools()
		if not heist then
			return
		end
		local tools = heistState().Tools or {}
		local t = serverNow()
		for toolId, s in pairs(toolSlots) do
			local count = tools[toolId] or 0
			s.Count.Text = "x" .. count
			s.Count.TextColor3 = count > 0 and Theme.Text or Theme.Muted
			s.Slot.BackgroundTransparency = count > 0 and 0.1 or 0.45
			local status = ""
			if toolId == "Lockpick" and heist.Lockpick then
				status = "READY"
			elseif toolId == "EMP" and (heist.EmpUntil or 0) > t then
				status = ("ACTIVE %ds"):format(math.ceil(heist.EmpUntil - t))
			elseif toolId == "SilentShoes" and (heist.ShoesUntil or 0) > t then
				status = ("ACTIVE %ds"):format(math.ceil(heist.ShoesUntil - t))
			elseif count == 0 then
				status = "NONE"
			end
			s.State.Text = status
			s.State.TextColor3 = status == "NONE" and Theme.Muted or Tuning.Tools[toolId].Color
		end
	end

	function useTool(toolId)
		if not heist then
			return
		end
		local tools = heistState().Tools or {}
		if (tools[toolId] or 0) < 1 then
			ctx.toast(("No %s left. Buy them in the Heists menu before your next run."):format(Tuning.Tools[toolId].Name), "error")
			return
		end
		task.spawn(ctx.act, "UseHeistTool", toolId)
	end

	local keyToTool = {}
	local keyCodes = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
	for _, toolId in ipairs(Tuning.ToolOrder) do
		local code = keyCodes[Tuning.Tools[toolId].Key]
		if code then
			keyToTool[code] = toolId
		end
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not heist then
			return
		end
		local toolId = keyToTool[input.KeyCode]
		if toolId then
			useTool(toolId)
		end
	end)

	local function flash(strength, color)
		flashAlpha = math.max(flashAlpha, strength)
		flashColor = color or RED
	end

	local function showSummary(s)
		local success = s.Success
		local accent = success and GREEN or RED
		local height = success and 330 or 250
		local card = ctx.panel({ Name = "HeistSummary", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.new(0, 420, 0, height), ZIndex = 30, Parent = gui })
		autoScale(card)
		refreshScale()
		local cardStroke = card:FindFirstChildOfClass("UIStroke")
		cardStroke.Color = accent
		cardStroke.Thickness = 2.5
		label({ Position = UDim2.new(0, 16, 0, 14), Size = UDim2.new(1, -32, 0, 40), Text = success and "HEIST COMPLETE" or (FAIL_TITLES[s.Reason] or "HEIST FAILED"), Font = Theme.FontBlack, TextColor3 = accent, ZIndex = 31, Parent = card }, 36)
		local sub = ("%s  ·  %s"):format(s.MapName or "", clock(s.Time or 0))
		if success and s.NewBest then
			sub ..= "  ·  NEW BEST!"
		elseif not success then
			sub = FAIL_LINES[s.Reason] or sub
		end
		label({ Position = UDim2.new(0, 16, 0, 56), Size = UDim2.new(1, -32, 0, 20), Text = sub, TextColor3 = Theme.Muted, ZIndex = 31, Parent = card }, 16)
		local rows = {}
		if success then
			table.insert(rows, { ("+%s coins"):format(fmt(s.Coins or 0)), Theme.GoldLight })
			table.insert(rows, { ("+%d Security Credits"):format(s.Credits or 0), BLUE })
			table.insert(rows, { ("+%d Notoriety%s"):format(s.NotorietyGained or 0, s.Ghost and "  ·  GHOST BONUS" or ""), PURPLE })
			table.insert(rows, { ("+%s XP"):format(fmt(s.XP or 0)), Theme.Text })
			local relic = s.RelicId and Config.RelicsById[s.RelicId]
			if relic then
				table.insert(rows, { ("Loot: %s (%s)"):format(relic.Name, Config.Rarities[s.Tier].Name), Config.Rarities[s.Tier].Color })
			end
		elseif s.Reason == "Cancelled" then
			table.insert(rows, { "No notoriety lost and no cooldown.", Theme.Muted })
		else
			table.insert(rows, { ("-%d Notoriety"):format(s.NotorietyLost or 0), RED })
			local wait = s.CooldownUntil and math.ceil(s.CooldownUntil - serverNow()) or Tuning.FailCooldown
			table.insert(rows, { ("Lie low for %ds before your next heist."):format(math.max(wait, 0)), Theme.Muted })
		end
		local _, rank = Tuning.GetRank(s.Notoriety or 0)
		table.insert(rows, { ("Rank: %s  ·  %s notoriety"):format(rank.Name, fmt(s.Notoriety or 0)), rank.Color })
		for i, row in ipairs(rows) do
			label({ Position = UDim2.new(0, 16, 0, 84 + (i - 1) * 30), Size = UDim2.new(1, -32, 0, 26), Text = row[1], Font = Theme.FontBold, TextColor3 = row[2], ZIndex = 31, Parent = card }, 20)
		end
		button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(0, 180, 0, 40), Text = success and "Claim loot" or "Continue", BackgroundColor3 = success and Theme.Gold or Theme.Button, TextColor3 = success and Theme.Dark or Theme.Text, ZIndex = 32, Parent = card }, function()
			card:Destroy()
			if success and s.RelicId then
				ctx.ShowReveal({ RelicId = s.RelicId, Tier = s.Tier, IsNew = s.IsNew, Title = "HEIST LOOT" })
			end
		end, 18)
		card.Size = UDim2.new(0, 420, 0, height * 0.85)
		TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 420, 0, height) }):Play()
	end

	local function endHeist(summary)
		heist = nil
		heistToken += 1
		clearWorld()
		readyLabel.Visible = false
		hud.Visible = false
		toolbar.Visible = false
		vignette.Visible = false
		lockdownBanner.Visible = false
		setMood(nil)
		setWorldHud(false)
		if summary then
			showSummary(summary)
		end
	end

	local function applyState(payload)
		if not heist then
			return
		end
		for key, value in pairs(payload) do
			heist[key] = value
		end
		heist.CS = payload.CS -- nil when no camera sees you, so it must be cleared explicitly
		syncGuards(payload.G)
		refreshTools()
	end

	ctx.OnEvent("Heist", function(event, payload)
		payload = payload or {}
		if event == "Start" then
			heistToken += 1
			heist = {
				MapId = payload.MapId,
				EndsAt = payload.EndsAt,
				StartedAt = payload.StartedAt or serverNow(),
				Duration = payload.Duration or Tuning.Duration,
				FloorY = payload.FloorY or 0,
				Go = false,
				Alarm = 0,
				Stolen = false,
				Lockdown = false,
				EmpUntil = 0,
				ShoesUntil = 0,
			}
			buildWorld(payload.Cameras)
			task.spawn(reportReady, heistToken, payload.ModelName)
			ctx.closeModals()
			local old = gui:FindFirstChild("HeistSummary")
			if old then
				old:Destroy()
			end
			mapLabel.Text = (payload.MapName or ""):upper()
			hudStroke.Color = Tuning.Maps[payload.MapId] and Tuning.Maps[payload.MapId].Color or Theme.Gold
			hud.Visible = true
			toolbar.Visible = true
			vignette.Visible = true
			setVignette(0, RED)
			setMood(payload.MapId)
			setWorldHud(true)
			refreshTools()
			heist.TargetName = payload.TargetName or "the relic"
			readyLabel.Text = "SNEAKING IN..."
			readyLabel.TextColor3 = Theme.GoldLight
			readyLabel.TextTransparency = 0
			readyLabel.TextStrokeTransparency = 0.15
			readyScale.Scale = 1
			readyLabel.Visible = true
		elseif event == "Go" then
			if not heist then
				return
			end
			heist.Go = true
			heist.StartedAt = payload.StartedAt or serverNow()
			heist.EndsAt = payload.EndsAt or heist.EndsAt
			local token = heistToken
			readyLabel.Text = "GO!"
			readyLabel.TextColor3 = GREEN
			readyLabel.Visible = true
			readyScale.Scale = 1.6
			TweenService:Create(readyScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			task.delay(0.7, function()
				if heistToken == token then
					TweenService:Create(readyLabel, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				end
			end)
			task.delay(1.05, function()
				if heistToken == token then
					readyLabel.Visible = false
				end
			end)
			ctx.ShowBanner(("Steal %s and escape!"):format(heist.TargetName or "the relic"), Tuning.Maps[heist.MapId] and Tuning.Maps[heist.MapId].Color, 4)
		elseif event == "State" then
			applyState(payload)
		elseif event == "Detected" then
			flash(0.6)
			if payload.Kind == "Laser" then
				ctx.toast(("Laser tripped! +%d alarm"):format(Tuning.Security.LaserAlarm), "error")
			elseif payload.Kind == "Plate" then
				ctx.toast(("Pressure plate! +%d alarm"):format(Tuning.Security.PlateAlarm), "error")
			end
		elseif event == "Sticky" then
			ctx.toast("Sticky floor! You're slowed down.", "error")
		elseif event == "Stolen" then
			if heist then
				heist.Stolen = true
			end
			ctx.ShowBanner("RELIC SECURED! Get back to the green EXIT!", GREEN, 4)
		elseif event == "Lockdown" then
			if heist then
				heist.Lockdown = true
				heist.EndsAt = payload.EndsAt or heist.EndsAt
			end
			collectCeilingLights()
			lockdownBanner.Visible = true
			lockdownBanner.Size = UDim2.new(0, 780, 0, 138)
			TweenService:Create(lockdownBanner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 520, 0, 92) }):Play()
			if mood then
				TweenService:Create(mood, TweenInfo.new(0.6), { TintColor = Color3.fromRGB(255, 175, 175) }):Play()
			end
		elseif event == "ToolUsed" then
			if payload.Tool == "EMP" then
				empBurst(payload.Pos)
				flash(0.5, BLUE)
			end
		elseif event == "End" then
			endHeist(payload)
		elseif event == "Announce" then
			local relic = Config.RelicsById[payload.RelicId]
			local rarity = Config.Rarities[payload.Tier]
			if relic and rarity then
				local text = ("%s robbed the %s and escaped with a %s %s!"):format(payload.Name, payload.MapName, rarity.Name, relic.Name)
				ctx.SystemChat("[Heist] " .. text, rarity.Color)
				if not heist then
					ctx.ShowBanner(text, rarity.Color, 5)
				end
			end
		end
	end)
	ctx.OnSnapshot(function()
		refreshTools()
	end)

	---------------------------------------------------------------- per-frame HUD

	local lastSecond = 0
	RunService.RenderStepped:Connect(function(dt)
		local t = serverNow()
		if heist then
			animateWorld(t)
			local left = heist.Go and (heist.EndsAt or t) - t or heist.Duration
			timerLabel.Text = clock(left)
			timerLabel.TextColor3 = left <= 30 and (t % 0.5 < 0.25 and RED or Theme.Text) or Theme.Text
			local alarm = math.clamp(heist.Alarm or 0, 0, 100)
			local current = alarmFill.Size.X.Scale
			local target = alarm / 100
			alarmFill.Size = UDim2.fromScale(current + (target - current) * math.min(1, dt * 10), 1)
			alarmPct.Text = heist.Lockdown and "LOCKDOWN" or (math.floor(alarm) .. "%")
			local color = alarm < 40 and GREEN:Lerp(AMBER, alarm / 40) or AMBER:Lerp(RED, math.clamp((alarm - 40) / 40, 0, 1))
			alarmFill.BackgroundColor3 = color
			alarmPct.TextColor3 = color
			local danger = heist.Lockdown or alarm >= 70
			local pulse = (math.sin(t * (heist.Lockdown and 12 or 8)) + 1) / 2
			alarmBarStroke.Transparency = danger and (0.6 - pulse * 0.6) or 1
			alarmTitle.TextColor3 = danger and RED or Theme.Muted
			objective.Text = not heist.Go and "Get ready..." or (heist.Stolen and "ESCAPE! Reach the green EXIT" or "Find the relic and hold E")
			objective.TextColor3 = heist.Stolen and GREEN or Theme.GoldLight
			local bits = {}
			if (heist.EmpUntil or 0) > t then
				table.insert(bits, ("EMP %ds"):format(math.ceil(heist.EmpUntil - t)))
			end
			if (heist.ShoesUntil or 0) > t then
				table.insert(bits, ("Silent Shoes %ds"):format(math.ceil(heist.ShoesUntil - t)))
			end
			if heist.Lockpick then
				table.insert(bits, "Lockpick ready")
			end
			if heist.Seen and not heist.Lockdown then
				table.insert(bits, "YOU'VE BEEN SPOTTED!")
			end
			statusLine.Text = #bits > 0 and table.concat(bits, "  ·  ") or "Stay out of flashlights, camera cones and lasers."
			statusLine.TextColor3 = heist.Seen and RED or Theme.Muted

			-- Vignette: fades after each detection flash, pulses during lockdown.
			flashAlpha = math.max(0, flashAlpha - dt * 1.4)
			local base = heist.Lockdown and (0.28 + pulse * 0.25) or (heist.Seen and 0.22 or 0)
			-- The flash keeps its own colour (blue for an EMP) until it fades under the red base.
			setVignette(math.max(base, flashAlpha), flashAlpha > base and flashColor or RED)
			if heist.Lockdown then
				lockdownTitle.TextTransparency = 0.15 * pulse
				lockdownSub.Text = ("The guards are hunting you. EXIT in %s!"):format(clock(left))
			end
			if math.floor(t) ~= lastSecond then
				lastSecond = math.floor(t)
				refreshTools()
			end
		elseif frame.Visible and math.floor(t) ~= lastSecond then
			lastSecond = math.floor(t)
			refreshLive()
		end
	end)

	-- If this script restarts mid-heist (it shouldn't: ResetOnSpawn is off) the server still ends the heist.
	player:GetAttributeChangedSignal("InHeist"):Connect(function()
		if not player:GetAttribute("InHeist") and heist then
			endHeist(nil)
		end
	end)
end
