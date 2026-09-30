-- Robux Store: game passes and boosts/tickets (developer products), plus the Auto-Dig toggle
-- and its compact results feed. Ownership comes from the server's "Pass_<Key>" player attributes.
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

return function(ctx)
	local Config, Theme, player = ctx.Config, ctx.Theme, ctx.player
	local new, label, button, corner, fmt = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.fmt
	local StoreConfig = require(ctx.Shared:WaitForChild("FeatureConfig"):WaitForChild("Store"))
	local gui = ctx.gui

	local function owns(key)
		return player:GetAttribute("Pass_" .. key) == true
	end

	local function prompt(item, isPass)
		if item.Id == 0 then
			ctx.toast("Not set up yet", "error")
			return
		end
		local ok, err = pcall(function()
			if isPass then
				MarketplaceService:PromptGamePassPurchase(player, item.Id)
			else
				MarketplaceService:PromptProductPurchase(player, item.Id)
			end
		end)
		if not ok then
			warn("[RelicRNG] Purchase prompt failed: " .. tostring(err))
			ctx.toast("The store is unavailable right now.", "error")
		end
	end

	---------------------------------------------------------------- store modal

	local frame, content, titleLabel = ctx.createModal("Store", "Store")
	titleLabel.Size = UDim2.new(0, 96, 0, 32)
	local grid = new("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 132), CellPadding = UDim2.new(0, 10, 0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

	local tab = "Passes"
	local tabButtons = {}
	local tabBar = new("Frame", { Position = UDim2.new(0, 112, 0, 11), Size = UDim2.new(1, -170, 0, 32), BackgroundTransparency = 1, ZIndex = 5, Parent = frame })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabBar })

	local function styleTabs()
		for name, b in pairs(tabButtons) do
			local active = name == tab
			b.BackgroundColor3 = active and Theme.Gold or Theme.Button
			b.TextColor3 = active and Theme.Dark or Theme.Text
		end
	end

	for i, info in ipairs({ { "Passes", "Passes" }, { "Products", "Boosts & Tickets" } }) do
		local b = button({ Size = UDim2.new(0.5, -4, 1, 0), Text = info[2], LayoutOrder = i, ZIndex = 6, Parent = tabBar }, function()
			tab = info[1]
			styleTabs()
			ctx.renderers.Store()
			content.CanvasPosition = Vector2.zero
		end, 16)
		new("UISizeConstraint", { MaxSize = Vector2.new(170, 32), Parent = b })
		tabButtons[info[1]] = b
	end
	styleTabs()

	-- One column when the modal is narrow (phones in portrait).
	local function fitGrid()
		local wide = content.AbsoluteSize.X >= 440
		grid.CellSize = wide and UDim2.new(0.5, -6, 0, 132) or UDim2.new(1, 0, 0, 132)
	end
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGrid)

	local live = {} -- status labels refreshed every second while open

	-- Glyph per item (emoji or a drawn icon) instead of cramped text labels.
	local GLYPHS = {
		AutoDig = "⛏️",
		DoubleIncome = "💰",
		ExtraPedestals = "🏛️",
		LuckyScanner = "🍀",
		VIP = "👑",
		ExtraHeistEnergy = "⚡",
		LuckBoost15 = "🍀",
		IncomeBoost30 = "💰",
	}
	local function iconBlock(parent, item)
		local block = new("Frame", { Position = UDim2.new(0, 10, 0, 10), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = item.Color, BorderSizePixel = 0, ZIndex = 5, Parent = parent })
		corner(block, UDim.new(0, 12))
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)), Parent = block })
		ctx.stroke(block, Color3.new(1, 1, 1), 1.5, 0.5)
		local glyph = GLYPHS[item.Key]
		if glyph then
			ctx.icon(glyph, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.66, 0.66), ZIndex = 6, Parent = block })
		else
			ctx.icon("Ticket", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.62, 0.62), ZIndex = 6, Parent = block })
		end
		-- Small amount/multiplier chip (e.g. "250", "x2") on the bottom edge when the item has one.
		local amount = tostring(item.Icon or "")
		if amount ~= "" and (not glyph or amount:match("^x?%d")) then
			local chip = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.fromOffset(40, 18), BackgroundColor3 = Color3.fromRGB(20, 16, 28), BorderSizePixel = 0, ZIndex = 7, Parent = block })
			corner(chip, UDim.new(1, 0))
			ctx.stroke(chip, Theme.GoldLight, 1, 0.3)
			label({ Size = UDim2.fromScale(1, 1), Text = amount, Font = Theme.FontBlack, TextColor3 = Theme.GoldLight, ZIndex = 8, Parent = chip }, 14)
		end
	end

	local function statusFor(item, isPass)
		if isPass then
			return owns(item.Key) and "Owned forever" or "Permanent", owns(item.Key) and Theme.Success or Theme.Muted
		end
		local reward = item.Grant
		if reward.Boost then
			local left = (player:GetAttribute("Boost" .. reward.Boost .. "Until") or 0) - workspace:GetServerTimeNow()
			if left > 0 then
				return ("Active  ·  %s left"):format(ctx.duration(left)), Theme.Success
			end
			return "Not active", Theme.Muted
		end
		return ("You have %s tickets"):format(fmt(player:GetAttribute("Tickets") or 0)), Theme.Muted
	end

	local function card(item, isPass)
		local owned = isPass and owns(item.Key)
		local c = ctx.card({ LayoutOrder = item.Order, Parent = content }, owned and Theme.Success or nil)
		iconBlock(c, item)
		label({ Position = UDim2.new(0, 78, 0, 10), Size = UDim2.new(1, -88, 0, 22), Text = item.Name, Font = Theme.FontBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = c }, 18)
		label({ Position = UDim2.new(0, 78, 0, 36), Size = UDim2.new(1, -88, 0, 40), Text = item.Description, TextColor3 = Theme.Muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5, Parent = c }, 14)
		local status = label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -14), Size = UDim2.new(1, -150, 0, 18), Text = "", Font = Theme.FontBold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = c }, 14)
		table.insert(live, { Label = status, Item = item, IsPass = isPass })
		local buy = button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10), Size = UDim2.fromOffset(118, 34), Text = owned and "Owned" or ("R$ " .. fmt(item.PriceRobux)), ZIndex = 6, Parent = c }, function()
			if not owned then
				prompt(item, isPass)
			end
		end, 17)
		if owned then
			ctx.setEnabled(buy, false)
			buy.Text = "Owned ✓"
			buy.TextColor3 = Theme.Success
		else
			buy.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
			buy.TextColor3 = Color3.new(1, 1, 1)
		end
	end

	local function refreshLive()
		for _, entry in ipairs(live) do
			local text, color = statusFor(entry.Item, entry.IsPass)
			entry.Label.Text = text
			entry.Label.TextColor3 = color
		end
	end

	ctx.renderers.Store = function()
		ctx.clear(content)
		table.clear(live)
		fitGrid()
		for _, item in ipairs(tab == "Passes" and StoreConfig.PassList or StoreConfig.ProductList) do
			card(item, tab == "Passes")
		end
		refreshLive()
	end
	for _, item in ipairs(StoreConfig.PassList) do
		player:GetAttributeChangedSignal("Pass_" .. item.Key):Connect(function()
			if frame.Visible then
				ctx.renderers.Store()
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			if frame.Visible then
				refreshLive()
			end
		end
	end)

	local storeButton = ctx.AddMenuButton("Store", 70, function()
		ctx.openModal("Store")
	end)
	storeButton.TextColor3 = Theme.GoldLight

	---------------------------------------------------------------- Auto-Dig toggle + feed

	local autoDig = new("Frame", { Name = "AutoDig", AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(186, 58), BackgroundTransparency = 1, Visible = false, Parent = gui })
	local togglePanel = ctx.panel({ Size = UDim2.fromScale(1, 1), Parent = autoDig })
	label({ Position = UDim2.new(0, 12, 0, 7), Size = UDim2.new(1, -80, 0, 22), Text = "AUTO-DIG", Font = Theme.FontBlack, TextColor3 = Theme.Gold, TextXAlignment = Enum.TextXAlignment.Left, Parent = togglePanel }, 18)
	local statusLabel = label({ Position = UDim2.new(0, 12, 0, 31), Size = UDim2.new(1, -24, 0, 18), Text = "Off", TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, Parent = togglePanel }, 13)
	local switch = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(48, 22), BackgroundColor3 = Color3.fromRGB(60, 58, 68), BorderSizePixel = 0, Parent = togglePanel })
	corner(switch, UDim.new(1, 0))
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Theme.Text, BorderSizePixel = 0, Parent = switch })
	corner(knob, UDim.new(1, 0))
	local hit = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 3, Parent = togglePanel })

	local busy = false
	hit.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		ctx.act("SetAutoDig", not player:GetAttribute("AutoDigOn"))
		busy = false
	end)

	local function refreshToggle()
		local on = player:GetAttribute("AutoDigOn") == true
		autoDig.Visible = owns("AutoDig")
		TweenService:Create(knob, TweenInfo.new(0.15), { Position = on and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }):Play()
		switch.BackgroundColor3 = on and Theme.Success or Color3.fromRGB(60, 58, 68)
		local status = player:GetAttribute("AutoDigStatus")
		statusLabel.Text = on and (status ~= nil and status ~= "" and status or "On") or "Off  ·  tap to start"
		statusLabel.TextColor3 = on and (status and status:find("^Digging") and Theme.Success or Theme.GoldLight) or Theme.Muted
	end
	for _, name in ipairs({ "AutoDigOn", "AutoDigStatus", "Pass_AutoDig" }) do
		player:GetAttributeChangedSignal(name):Connect(refreshToggle)
	end
	refreshToggle()

	local FEED_WIDTH = 260
	local feed = new("Frame", { Name = "Feed", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 0, -6), Size = UDim2.fromOffset(FEED_WIDTH, 128), BackgroundTransparency = 1, Parent = autoDig })
	new("UIListLayout", { Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder, Parent = feed })
	local feedOrder = 0
	local maxLines = 4

	-- Wide screens: bottom-right, feed stacked above the toggle.
	-- Narrow screens: just above the roll panel's top edge, feed to the toggle's left, fewer lines.
	local function placeAutoDig()
		local wide = gui.AbsoluteSize.X >= 420 + 2 * (186 + 24)
		autoDig.Position = wide and UDim2.new(1, -12, 1, -12) or UDim2.new(1, -12, 1, -214)
		feed.AnchorPoint = Vector2.new(1, 1)
		feed.Position = wide and UDim2.new(1, 0, 0, -6) or UDim2.new(0, -8, 1, 0)
		maxLines = wide and 4 or 2
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeAutoDig)
	placeAutoDig()

	ctx.OnEvent("AutoDig", function(result)
		local relic = type(result) == "table" and Config.RelicsById[result.RelicId]
		local rarity = relic and Config.Rarities[result.Tier]
		if not rarity then
			return
		end
		feedOrder += 1
		local line = new("Frame", { Size = UDim2.fromOffset(FEED_WIDTH, 24), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.2, BorderSizePixel = 0, LayoutOrder = feedOrder, Parent = feed })
		corner(line, UDim.new(0, 6))
		local s = ctx.stroke(line, rarity.Color, 1, result.Tier >= 3 and 0.2 or 0.7)
		local text = ('<font color="#%s"><b>%s</b></font>  %s%s'):format(rarity.Color:ToHex(), rarity.Name, relic.Name, result.IsNew and '  <font color="#F5D778"><b>NEW</b></font>' or "")
		local l = new("TextLabel", { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), BackgroundTransparency = 1, Font = Theme.Font, TextColor3 = Theme.Text, TextSize = 14, Text = text, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, Parent = line })
		local lines = {}
		for _, child in ipairs(feed:GetChildren()) do
			if child:IsA("Frame") then
				table.insert(lines, child)
			end
		end
		table.sort(lines, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #lines - maxLines do
			lines[i]:Destroy()
		end
		task.delay(10, function()
			if line.Parent then
				local info = TweenInfo.new(0.6)
				TweenService:Create(line, info, { BackgroundTransparency = 1 }):Play()
				TweenService:Create(l, info, { TextTransparency = 1 }):Play()
				TweenService:Create(s, info, { Transparency = 1 }):Play()
				task.wait(0.65)
				line:Destroy()
			end
		end)
	end)
end
