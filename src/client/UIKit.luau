-- Shared client toolkit: theme, UI builders, toasts, modals, icon menu, relic thumbnails and the feature context (ctx).
-- Every feature module in RelicRNGClient.Features receives the ctx built here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("RelicRNG")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = Shared:WaitForChild("Remotes")

local ctx = {
	Config = Config,
	Remotes = Remotes,
	Shared = Shared,
	player = player,
	fmt = Config.FormatNumber,
	abbr = Config.Abbreviate,
}

local Theme = {
	Gold = Color3.fromRGB(232, 188, 64),
	GoldLight = Color3.fromRGB(255, 222, 128),
	Panel = Color3.fromRGB(21, 18, 28),
	PanelLight = Color3.fromRGB(46, 40, 60),
	PanelTop = Color3.fromRGB(42, 36, 56),
	PanelBottom = Color3.fromRGB(21, 18, 28),
	PanelLip = Color3.fromRGB(9, 7, 13),
	Text = Color3.fromRGB(244, 240, 232),
	Muted = Color3.fromRGB(172, 166, 186),
	Disabled = Color3.fromRGB(128, 124, 138),
	Button = Color3.fromRGB(62, 54, 80),
	Error = Color3.fromRGB(240, 86, 86),
	Success = Color3.fromRGB(110, 220, 120),
	Dark = Color3.fromRGB(34, 24, 10),
	Coin = Color3.fromRGB(255, 200, 60),
	Ticket = Color3.fromRGB(255, 140, 90),
	XP = Color3.fromRGB(150, 110, 255),
	Shard = Color3.fromRGB(196, 150, 255),
	Credits = Color3.fromRGB(110, 180, 255),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontBlack = Enum.Font.GothamBlack,
}
ctx.Theme = Theme

-- Shared animation vocabulary so every panel/button moves the same way.
local Anim = {
	Press = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Release = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Open = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Fade = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Pulse = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
}
ctx.Anim = Anim

-- One live tween per instance: starting a new one cancels the previous, so rapid open/close never fight.
local liveTweens = setmetatable({}, { __mode = "k" })
function ctx.tween(instance, info, goals)
	local previous = liveTweens[instance]
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(instance, info, goals)
	liveTweens[instance] = tween
	tween:Play()
	return tween
end

---------------------------------------------------------------- builders

function ctx.new(className, props)
	local inst = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end
local new = ctx.new

function ctx.corner(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 10), Parent = parent })
end

function ctx.stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or Theme.Gold,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.25,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function ctx.maxText(parent, size)
	return new("UITextSizeConstraint", { MaxTextSize = size, Parent = parent })
end

function ctx.padding(parent, px)
	local u = UDim.new(0, px)
	return new("UIPadding", { PaddingLeft = u, PaddingRight = u, PaddingTop = u, PaddingBottom = u, Parent = parent })
end

local function darken(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount)
end
local function lighten(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount)
end
ctx.darken, ctx.lighten = darken, lighten

-- Vertical top->bottom gradient with a darker `lipPx` band along the bottom edge (the "3D lip").
-- Keeps the lip a constant pixel height as the frame resizes.
function ctx.lipGradient(frame, top, bottom, lip, lipPx)
	local gradient = new("UIGradient", { Rotation = 90, Parent = frame })
	lipPx = lipPx or 4
	local function update()
		local h = frame.AbsoluteSize.Y
		local at = h > lipPx * 3 and math.clamp(1 - lipPx / h, 0.5, 0.995) or 0.995
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(at - 0.002, bottom),
			ColorSequenceKeypoint.new(at, lip),
			ColorSequenceKeypoint.new(1, lip),
		})
	end
	update()
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	return gradient
end

-- Standard panel: purple-charcoal gradient, 4 px bottom lip, rounded corners, thin gold outline.
function ctx.panel(props)
	local tint = props.BackgroundColor3
	props.BackgroundColor3 = Color3.new(1, 1, 1)
	props.BackgroundTransparency = props.BackgroundTransparency or 0.06
	props.BorderSizePixel = 0
	local frame = new("Frame", props)
	ctx.corner(frame, UDim.new(0, 14))
	ctx.stroke(frame, Theme.Gold, 1.5, 0.35)
	if tint then
		ctx.lipGradient(frame, lighten(tint, 0.08), darken(tint, 0.35), darken(tint, 0.7))
	else
		ctx.lipGradient(frame, Theme.PanelTop, Theme.PanelBottom, Theme.PanelLip)
	end
	return frame
end

-- Inner card for modal content (lighter than the panel, subtle outline).
function ctx.card(props, accent)
	props.BackgroundColor3 = props.BackgroundColor3 or Theme.PanelLight
	props.BackgroundTransparency = props.BackgroundTransparency or 0.1
	props.BorderSizePixel = 0
	props.ZIndex = props.ZIndex or 5
	local frame = new("Frame", props)
	ctx.corner(frame, UDim.new(0, 10))
	ctx.stroke(frame, accent or Theme.Gold, 1, accent and 0.3 or 0.7)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 196, 210)), Parent = frame })
	return frame
end

function ctx.label(props, max)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Theme.Font
	props.TextColor3 = props.TextColor3 or Theme.Text
	props.TextScaled = true
	local l = new("TextLabel", props)
	ctx.maxText(l, math.max(max or 20, 14))
	return l
end

-- Pressed scale pop (0.93 on press, bouncy release). Connections live on the button, so they die with it.
function ctx.pressPop(b)
	local pop = new("UIScale", { Name = "PressScale", Parent = b })
	b.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if b.Active and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			ctx.tween(pop, Anim.Press, { Scale = 0.93 })
		end
	end)
	b.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			ctx.tween(pop, Anim.Release, { Scale = 1 })
		end
	end)
	return pop
end

function ctx.button(props, onClick, max)
	props.BackgroundColor3 = props.BackgroundColor3 or Theme.Button
	props.Font = props.Font or Theme.FontBold
	props.TextColor3 = props.TextColor3 or Theme.Text
	props.TextScaled = true
	props.AutoButtonColor = true
	props.BorderSizePixel = 0
	local b = new("TextButton", props)
	ctx.corner(b, UDim.new(0, 9))
	ctx.stroke(b, Theme.Gold, 1, 0.5)
	ctx.maxText(b, math.max(max or 18, 14))
	ctx.lipGradient(b, Color3.new(1, 1, 1), Color3.fromRGB(205, 200, 210), Color3.fromRGB(120, 115, 125), 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 7), Parent = b })
	ctx.pressPop(b)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

-- Disabled state: 40% opacity, desaturated fill, grey text, faded outline. Keeps the click handler.
-- Callers may set colours before or after; re-enabling restores whatever the caller last chose.
local function desaturate(c)
	local l = c.R * 0.3 + c.G * 0.59 + c.B * 0.11
	return c:Lerp(Color3.new(l, l, l), 0.85):Lerp(Color3.new(0, 0, 0), 0.25)
end

function ctx.setEnabled(b, enabled)
	local wasDisabled = b:GetAttribute("UIDisabled") == true
	local s = b:FindFirstChildOfClass("UIStroke")
	local isText = b:IsA("TextButton") or b:IsA("TextLabel")
	if enabled then
		if wasDisabled then
			b.BackgroundTransparency = b:GetAttribute("UIEnabledBg") or 0
			if b.BackgroundColor3 == b:GetAttribute("UIDisabledColor") then
				b.BackgroundColor3 = b:GetAttribute("UIEnabledColor") or b.BackgroundColor3
			end
			if isText and b.TextColor3 == Theme.Disabled then
				b.TextColor3 = b:GetAttribute("UIEnabledText") or Theme.Text
			end
			if s then
				s.Transparency = b:GetAttribute("UIEnabledStroke") or 0.5
			end
			b:SetAttribute("UIDisabled", nil)
		end
	else
		if not wasDisabled then
			b:SetAttribute("UIEnabledBg", b.BackgroundTransparency)
			if s then
				b:SetAttribute("UIEnabledStroke", s.Transparency)
			end
		end
		if not wasDisabled or b.BackgroundColor3 ~= b:GetAttribute("UIDisabledColor") then
			b:SetAttribute("UIEnabledColor", b.BackgroundColor3)
			local grey = desaturate(b.BackgroundColor3)
			b:SetAttribute("UIDisabledColor", grey)
			b.BackgroundColor3 = grey
		end
		if isText and (not wasDisabled or b.TextColor3 ~= Theme.Disabled) then
			b:SetAttribute("UIEnabledText", b.TextColor3)
			b.TextColor3 = Theme.Disabled
		end
		b.BackgroundTransparency = 0.6
		if s then
			s.Transparency = 0.85
		end
		b:SetAttribute("UIDisabled", true)
	end
	if b:IsA("GuiButton") then
		b.AutoButtonColor = enabled
	end
	b.Active = enabled
end

function ctx.clear(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIGridStyleLayout") and not child:IsA("UIPadding") and not child:IsA("UISizeConstraint") then
			child:Destroy()
		end
	end
end

function ctx.oneIn(chance)
	return "1 in " .. Config.FormatNumber(100 / chance + 0.5)
end

function ctx.percent(chance)
	if chance >= 0.001 then
		return (string.format("%.3f", chance):gsub("0+$", ""):gsub("%.$", "")) .. "%"
	end
	return string.format("%.2g", chance) .. "%"
end

function ctx.duration(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return ("%dh %dm"):format(seconds // 3600, (seconds % 3600) // 60)
	elseif seconds >= 60 then
		return ("%dm %ds"):format(seconds // 60, seconds % 60)
	end
	return seconds .. "s"
end

---------------------------------------------------------------- icons (drawn from UI primitives, no images)

-- ctx.icon(kind, props) -> Frame. Kinds: Coin, Ticket, XP, Shard, Credits, or any text/emoji glyph.
function ctx.icon(kind, props)
	props = props or {}
	local size = props.Size or UDim2.fromOffset(24, 24)
	local z = props.ZIndex or 5
	local holder = new("Frame", {
		Name = "Icon" .. tostring(kind),
		Size = size,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = props.Parent,
	})
	new("UIAspectRatioConstraint", { DominantAxis = props.DominantAxis or Enum.DominantAxis.Width, Parent = holder })
	local function disc(color, scale, zOffset)
		local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(scale, scale), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z + (zOffset or 0), Parent = holder })
		ctx.corner(f, UDim.new(1, 0))
		return f
	end
	if kind == "Coin" then
		local outer = disc(Color3.fromRGB(214, 140, 30), 1)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(205, 130, 25)), Parent = outer })
		local inner = disc(Theme.Coin, 0.64, 1)
		new("UIGradient", { Rotation = -90, Color = ColorSequence.new(Color3.fromRGB(255, 236, 150), Color3.fromRGB(240, 170, 40)), Parent = inner })
		ctx.stroke(inner, Color3.fromRGB(190, 120, 20), 1, 0.2)
	elseif kind == "Ticket" then
		local body = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 0.66), Rotation = -14, BackgroundColor3 = Theme.Ticket, BorderSizePixel = 0, ZIndex = z, Parent = holder })
		ctx.corner(body, UDim.new(0.18, 0))
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 190, 120), Color3.fromRGB(235, 100, 70)), Parent = body })
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.62, 0.5), Size = UDim2.new(0, 2, 0.6, 0), BackgroundColor3 = Color3.fromRGB(255, 235, 200), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = z + 1, Parent = body })
		new("TextLabel", { Size = UDim2.fromScale(0.55, 1), Position = UDim2.fromScale(0.06, 0), BackgroundTransparency = 1, Text = "★", TextScaled = true, Font = Theme.FontBlack, TextColor3 = Color3.fromRGB(255, 245, 225), ZIndex = z + 1, Parent = body })
	elseif kind == "XP" then
		local badge = disc(Theme.XP, 1)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(190, 160, 255), Color3.fromRGB(110, 70, 230)), Parent = badge })
		ctx.stroke(badge, Color3.fromRGB(230, 215, 255), 1.5, 0.2)
		new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "XP", TextScaled = true, Font = Theme.FontBlack, TextColor3 = Color3.new(1, 1, 1), ZIndex = z + 1, Parent = badge })
		new("UIPadding", { PaddingLeft = UDim.new(0.18, 0), PaddingRight = UDim.new(0.18, 0), PaddingTop = UDim.new(0.26, 0), PaddingBottom = UDim.new(0.26, 0), Parent = badge })
	elseif kind == "Shard" then
		local gem = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.68, 0.68), Rotation = 45, BackgroundColor3 = Theme.Shard, BorderSizePixel = 0, ZIndex = z, Parent = holder })
		ctx.corner(gem, UDim.new(0.15, 0))
		new("UIGradient", { Rotation = 45, Color = ColorSequence.new(Color3.fromRGB(235, 215, 255), Color3.fromRGB(140, 80, 240)), Parent = gem })
		local shine = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.4, 0.4), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = z + 1, Parent = gem })
		ctx.corner(shine, UDim.new(0.2, 0))
	elseif kind == "Credits" then
		local shield = disc(Theme.Credits, 1)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(170, 215, 255), Color3.fromRGB(60, 120, 230)), Parent = shield })
		new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "★", TextScaled = true, Font = Theme.FontBlack, TextColor3 = Color3.new(1, 1, 1), ZIndex = z + 1, Parent = shield })
	else
		new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = tostring(kind), TextScaled = true, Font = Theme.FontBlack, TextColor3 = props.Color or Theme.Text, ZIndex = z, Parent = holder })
	end
	return holder
end

ctx.gui = new("ScreenGui", {
	Name = "RelicRNGHud",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

---------------------------------------------------------------- relic thumbnails

local relicModels -- the RelicModels module once it exists
local pendingViewports = {} -- viewports waiting for RelicModels to replicate
local spinners = {} -- [model] = { Viewport, Center, Offset, Speed, Start }
local THUMB_FOV = 40

local function getRelicModels()
	if relicModels then
		return relicModels
	end
	local module = Shared:FindFirstChild("RelicModels")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type(result.Build) == "function" then
			relicModels = result
		end
	end
	return relicModels
end

local SILHOUETTE_STRIP = { "Decal", "Texture", "SurfaceAppearance", "ParticleEmitter", "Beam", "Trail", "Light", "Fire", "Smoke", "Sparkles", "Highlight", "BillboardGui", "SurfaceGui" }

-- Relic spin: one Heartbeat loop at 30 Hz, connected only while something spins, no per-frame tables/closures.
local SPIN_STEP = 1 / 30
local spinConnection
local spinAccum = 0
local spinAngles = CFrame.Angles
local function stepSpinners(dt)
	spinAccum += dt
	if spinAccum < SPIN_STEP then
		return
	end
	spinAccum = 0
	local t = os.clock()
	for model, info in pairs(spinners) do
		if model.Parent ~= info.Viewport or not info.Viewport.Parent then
			spinners[model] = nil
		elseif info.Viewport.Visible then
			model:PivotTo(info.CenterCFrame * spinAngles(0, (t - info.Start) * info.Speed, 0) * info.Offset)
		end
	end
	if next(spinners) == nil and spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end

local function fillViewport(viewport, relicId, opts)
	local module = getRelicModels()
	if not module then
		return false
	end
	local ok, model = pcall(module.Build, relicId, CFrame.new())
	if not ok or typeof(model) ~= "Instance" then
		warn("[RelicRNG] RelicModels.Build failed for " .. tostring(relicId) .. ": " .. tostring(model))
		return true
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("Sound") then
			d:Destroy()
		elseif opts.Silhouette then
			local strip = false
			for _, class in ipairs(SILHOUETTE_STRIP) do
				if d:IsA(class) then
					strip = true
					break
				end
			end
			if strip then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Color = Color3.new(0, 0, 0)
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0
				if d:IsA("MeshPart") then
					pcall(function()
						d.TextureID = ""
					end)
				end
			end
		end
	end
	local placeholder = viewport:FindFirstChild("Placeholder")
	if placeholder then
		placeholder:Destroy()
	end
	model.Parent = viewport
	-- Frame the model from its bounding box; RelicModels.CameraCFrame gives the front-facing (-Z) angle.
	local boxCFrame, size = model:GetBoundingBox()
	local center = boxCFrame.Position
	local radius = math.max(size.Magnitude / 2, 0.5)
	local distance = radius / math.tan(math.rad(THUMB_FOV / 2)) * (opts.Zoom or 0.85)
	local camera = new("Camera", { FieldOfView = THUMB_FOV, Parent = viewport })
	if type(module.CameraCFrame) == "function" then
		camera.CFrame = module.CameraCFrame(CFrame.new(center), distance)
	else
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, distance * 0.18, -distance), center)
	end
	viewport.CurrentCamera = camera
	if opts.Spin then
		spinners[model] = {
			Viewport = viewport,
			CenterCFrame = CFrame.new(center),
			Offset = CFrame.new(center):Inverse() * model:GetPivot(),
			Speed = type(opts.Spin) == "number" and opts.Spin or 0.9,
			Start = os.clock(),
		}
		if not spinConnection then
			spinConnection = RunService.Heartbeat:Connect(stepSpinners)
		end
	end
	return true
end

local function flushPending()
	if not getRelicModels() then
		return
	end
	local list = pendingViewports
	pendingViewports = {}
	for _, entry in ipairs(list) do
		if entry.Viewport.Parent then
			fillViewport(entry.Viewport, entry.RelicId, entry.Opts)
		end
	end
end
if not getRelicModels() then
	-- RelicModels hasn't replicated yet: fill waiting thumbnails once it arrives, then drop the listener.
	local added
	added = Shared.ChildAdded:Connect(function(child)
		if child.Name == "RelicModels" then
			added:Disconnect()
			task.defer(flushPending)
		end
	end)
	task.spawn(function()
		if Shared:WaitForChild("RelicModels", 60) then
			if added.Connected then
				added:Disconnect()
			end
			flushPending()
		end
	end)
end

-- ctx.RelicViewport(parent, relicId, props) -> container Frame, ViewportFrame
-- props: Size, Position, AnchorPoint, LayoutOrder, ZIndex, Name, Spin (true or radians/sec), Silhouette,
-- Background (false for none), CornerRadius (UDim), Zoom (camera distance factor, default 1.08).
function ctx.RelicViewport(parent, relicId, props)
	props = props or {}
	local relic = Config.RelicsById[relicId]
	local rarity = relic and Config.Rarities[relic.Tier] or Config.Rarities[1]
	local z = props.ZIndex or 5
	local container = new("Frame", {
		Name = props.Name or "RelicThumb",
		Size = props.Size or UDim2.fromOffset(64, 64),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = props.Background == false and 1 or 0,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = parent,
	})
	container:SetAttribute("RelicId", relicId)
	ctx.corner(container, props.CornerRadius or UDim.new(0, 10))
	if props.Background ~= false then
		local base = props.Silhouette and Color3.fromRGB(70, 66, 84) or rarity.Color
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(darken(base, 0.35), darken(base, 0.78)),
			Parent = container,
		})
		local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromScale(0.78, 0.78), BackgroundColor3 = lighten(base, 0.3), BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = z, Parent = container })
		new("UIAspectRatioConstraint", { Parent = glow })
		ctx.corner(glow, UDim.new(1, 0))
	end
	local viewport = new("ViewportFrame", {
		Name = "Viewport",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 146, 160),
		LightColor = Color3.fromRGB(255, 246, 232),
		LightDirection = Vector3.new(-0.5, -1, -0.7),
		ImageColor3 = props.Silhouette and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
		ImageTransparency = props.Silhouette and 0.15 or 0,
		ZIndex = z + 1,
		Parent = container,
	})
	local placeholder = new("TextLabel", {
		Name = "Placeholder",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = props.Silhouette and "?" or "◆",
		TextScaled = true,
		Font = Theme.FontBlack,
		TextColor3 = props.Silhouette and Theme.Muted or lighten(rarity.Color, 0.2),
		TextTransparency = 0.2,
		ZIndex = z + 1,
		Parent = viewport,
	})
	new("UIPadding", { PaddingTop = UDim.new(0.22, 0), PaddingBottom = UDim.new(0.22, 0), Parent = placeholder })
	local opts = { Spin = props.Spin, Silhouette = props.Silhouette, Zoom = props.Zoom }
	if relic and not fillViewport(viewport, relicId, opts) then
		table.insert(pendingViewports, { Viewport = viewport, RelicId = relicId, Opts = opts })
	end
	return container, viewport
end

---------------------------------------------------------------- toasts

local toastPill = new("Frame", {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 84),
	Size = UDim2.new(0, 0, 0, 34),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Theme.Panel,
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 40,
	Parent = ctx.gui,
})
ctx.corner(toastPill, UDim.new(1, 0))
local toastStroke = ctx.stroke(toastPill, Theme.Gold, 1.5, 0.3)
new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), Parent = toastPill })
local toastLabel = new("TextLabel", {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Font = Theme.FontBold,
	TextSize = 18,
	TextColor3 = Theme.Text,
	Text = "",
	ZIndex = 41,
	Parent = toastPill,
})
new("UISizeConstraint", { MaxSize = Vector2.new(560, 34), Parent = toastLabel })
local toastToken = 0
function ctx.toast(text, kind)
	toastToken += 1
	local token = toastToken
	local color = (kind == "error" and Theme.Error) or (kind == "success" and Theme.Success) or (kind == "levelup" and Theme.GoldLight) or Theme.Text
	toastLabel.Text = tostring(text)
	toastLabel.TextColor3 = color
	toastStroke.Color = kind == nil and Theme.Gold or color
	toastPill.Visible = true
	task.delay(kind == "levelup" and 4 or 2.8, function()
		if toastToken == token then
			toastPill.Visible = false
		end
	end)
end

function ctx.act(action, arg)
	local ok, result, extra = Remotes.Action:InvokeServer(action, arg)
	if type(result) == "string" then
		ctx.toast(result, ok and "success" or "error")
	end
	return ok, result, extra
end

---------------------------------------------------------------- state and events

local state = { Inventory = {}, Discovered = {}, Displayed = {}, Pity = { 0, 0, 0, 0 }, Stats = {} }
local snapshotListeners = {}
local eventListeners = {}

function ctx.State()
	return state
end

function ctx.OnSnapshot(fn)
	table.insert(snapshotListeners, fn)
end

function ctx.OnEvent(featureName, fn)
	eventListeners[featureName] = eventListeners[featureName] or {}
	table.insert(eventListeners[featureName], fn)
end

function ctx.ApplySnapshot(snapshot)
	state = snapshot
	for _, fn in ipairs(snapshotListeners) do
		task.spawn(fn, state)
	end
	for name, frame in pairs(ctx.modals) do
		if frame.Visible and ctx.renderers[name] then
			ctx.renderers[name]()
		end
	end
end

Remotes.FeatureEvent.OnClientEvent:Connect(function(featureName, ...)
	for _, fn in ipairs(eventListeners[featureName] or {}) do
		task.spawn(fn, ...)
	end
end)

-- The dig site the local character is standing in, or nil.
function ctx.CurrentSite()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and Config.SiteAt(root.Position)
end

---------------------------------------------------------------- modals

ctx.modals = {}
ctx.renderers = {}
local modalListeners = {}

-- Modals live in this area: 16 px below the top bar, 16 px above the screen bottom, clear of the menu.
local MODAL_TOP, MODAL_BOTTOM = 90, 16
ctx.modalArea = new("Frame", {
	Name = "ModalArea",
	Position = UDim2.new(0, 0, 0, MODAL_TOP),
	Size = UDim2.new(1, 0, 1, -(MODAL_TOP + MODAL_BOTTOM)),
	BackgroundTransparency = 1,
	ZIndex = 5,
	Parent = ctx.gui,
})

-- The top bar lives here; it narrows to stay clear of the menu when the menu reaches the top of the screen.
ctx.topArea = new("Frame", {
	Name = "TopArea",
	Position = UDim2.new(0, 0, 0, 10),
	Size = UDim2.new(1, 0, 0, 64),
	BackgroundTransparency = 1,
	Parent = ctx.gui,
})

function ctx.AnyModalOpen()
	for _, frame in pairs(ctx.modals) do
		if frame.Visible then
			return true
		end
	end
	return false
end

-- fn(anyOpen) runs whenever a modal opens or closes.
function ctx.OnModalChanged(fn)
	table.insert(modalListeners, fn)
end

local function modalChanged()
	local open = ctx.AnyModalOpen()
	for _, fn in ipairs(modalListeners) do
		task.spawn(fn, open)
	end
end

local function resetModal(frame)
	local scale = frame:FindFirstChild("PopScale")
	local live = liveTweens[frame]
	if live then
		live:Cancel()
	end
	frame.GroupTransparency = 0
	if scale then
		if liveTweens[scale] then
			liveTweens[scale]:Cancel()
		end
		scale.Scale = 1
	end
end

-- Modals are CanvasGroups: one GroupTransparency tween fades the whole panel, clipped to its rounded corners.
function ctx.createModal(name, title)
	local frame = new("CanvasGroup", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = ctx.modalArea,
	})
	ctx.corner(frame, UDim.new(0, 16))
	new("UISizeConstraint", { MaxSize = Vector2.new(680, 480), Parent = frame })
	local scale = new("UIScale", { Name = "PopScale", Parent = frame })
	-- Panel art sits 2 px inside the group so its outline isn't clipped.
	ctx.panel({ Name = "Background", Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundTransparency = 0, ZIndex = 4, Parent = frame })
	local titleLabel = ctx.label({ Name = "Title", Position = UDim2.new(0, 18, 0, 10), Size = UDim2.new(1, -80, 0, 34), Font = Theme.FontBlack, TextColor3 = Theme.GoldLight, TextXAlignment = Enum.TextXAlignment.Left, Text = title, ZIndex = 6, Parent = frame }, 26)
	new("UIStroke", { Color = Color3.fromRGB(60, 36, 8), Thickness = 1.5, Transparency = 0.2, Parent = titleLabel })
	local divider = new("Frame", { Name = "Divider", Position = UDim2.new(0, 16, 0, 51), Size = UDim2.new(1, -32, 0, 2), BackgroundColor3 = Theme.Gold, BorderSizePixel = 0, ZIndex = 5, Parent = frame })
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1) }), Parent = divider })
	local close = ctx.button({ Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.new(0, 36, 0, 36), Text = "X", Font = Theme.FontBlack, BackgroundColor3 = Color3.fromRGB(205, 64, 72), ZIndex = 7, Parent = frame }, function()
		ctx.closeModal(name)
	end, 20)
	close:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(255, 160, 160)
	local content = new("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.new(0, 12, 0, 60),
		Size = UDim2.new(1, -18, 1, -70),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Gold,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 5,
		Parent = frame,
	})
	-- 12 px between list content and the (inset) scrollbar.
	new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10), Parent = content })
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			-- Every way of showing a modal gets the same 0.25 s pop + fade in.
			frame.GroupTransparency = 1
			scale.Scale = 0.92
			ctx.tween(scale, Anim.Open, { Scale = 1 })
			ctx.tween(frame, Anim.Fade, { GroupTransparency = 0 })
		else
			resetModal(frame)
		end
		modalChanged()
	end)
	ctx.modals[name] = frame
	return frame, content, titleLabel
end

-- Animated close (fade + shrink, then hide). ctx.closeModals() / Visible = false still close instantly.
function ctx.closeModal(name)
	local frame = ctx.modals[name]
	if not frame or not frame.Visible or frame:GetAttribute("Closing") then
		return
	end
	frame:SetAttribute("Closing", true)
	ctx.tween(frame:FindFirstChild("PopScale"), Anim.Close, { Scale = 0.94 })
	local tween = ctx.tween(frame, Anim.Close, { GroupTransparency = 1 })
	tween.Completed:Once(function(state)
		frame:SetAttribute("Closing", nil)
		if state == Enum.PlaybackState.Completed then
			frame.Visible = false
		end
	end)
end

function ctx.openModal(name, forceOpen)
	local target = ctx.modals[name]
	if target and target.Visible and not forceOpen then
		ctx.closeModal(name)
		return
	end
	for modalName, frame in pairs(ctx.modals) do
		if modalName ~= name then
			frame.Visible = false
		end
	end
	if target then
		if target:GetAttribute("Closing") then
			target:SetAttribute("Closing", nil)
			resetModal(target)
		end
		target.Visible = true
		if ctx.renderers[name] then
			ctx.renderers[name]()
		end
	end
end

function ctx.closeModals()
	for _, frame in pairs(ctx.modals) do
		frame.Visible = false
	end
end

---------------------------------------------------------------- side menu (icon column)

local MENU_ICONS = {
	["Dig Sites"] = { "⛏️", Color3.fromRGB(245, 170, 70) },
	["My Museum"] = { "🏛️", Color3.fromRGB(232, 188, 64) },
	["Catalog"] = { "📖", Color3.fromRGB(95, 165, 255) },
	["My Relics"] = { "🏺", Color3.fromRGB(80, 210, 190) },
	["Shop"] = { "🛒", Color3.fromRGB(110, 220, 120) },
	["Forge"] = { "🔥", Color3.fromRGB(255, 125, 70) },
	["Collections"] = { "🏆", Color3.fromRGB(190, 125, 255) },
	["Security"] = { "🛡️", Color3.fromRGB(120, 175, 235) },
	["Heists"] = { "🕵️", Color3.fromRGB(235, 80, 95) },
	["Codes"] = { "🔑", Color3.fromRGB(255, 125, 190) },
	["Daily"] = { "🎁", Color3.fromRGB(255, 205, 70) },
	["Store"] = { "💎", Color3.fromRGB(90, 230, 130) },
}

local MENU_GAP, MENU_PAD = 6, 8
ctx.menu = new("ScrollingFrame", {
	Name = "Menu",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 4, 0.5, 0),
	Size = UDim2.fromOffset(80, 80),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	ZIndex = 2,
	Parent = ctx.gui,
})
local menuGrid = new("UIGridLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	CellSize = UDim2.fromOffset(64, 64),
	CellPadding = UDim2.fromOffset(MENU_GAP, MENU_GAP),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = ctx.menu,
})
-- Padding leaves room for badges (Daily "!") and the hover pop without clipping.
new("UIPadding", { PaddingLeft = UDim.new(0, MENU_PAD), PaddingRight = UDim.new(0, MENU_PAD + 4), PaddingTop = UDim.new(0, MENU_PAD + 4), PaddingBottom = UDim.new(0, MENU_PAD), Parent = ctx.menu })
local menuCount = 0

local function layoutMenu()
	local screen = ctx.gui.AbsoluteSize
	if screen.Y < 50 then
		return
	end
	local count = math.max(menuCount, 1)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local avail = screen.Y - 16 - MENU_PAD * 2 - 4
	if touch then
		avail = math.floor(screen.Y * 0.62) -- keep the bottom-left clear for the thumbstick
	end
	local size = screen.Y < 560 and 52 or 64
	local perColumn = math.max(1, math.floor((avail + MENU_GAP) / (size + MENU_GAP)))
	local columns = math.min(math.ceil(count / perColumn), 3) -- beyond three columns the menu scrolls
	local rows = math.ceil(count / columns)
	menuGrid.CellSize = UDim2.fromOffset(size, size)
	menuGrid.FillDirectionMaxCells = rows
	local shownRows = math.min(rows, perColumn)
	local width = columns * (size + MENU_GAP) - MENU_GAP + MENU_PAD * 2 + 4
	local height = shownRows * (size + MENU_GAP) - MENU_GAP + MENU_PAD * 2 + 4
	ctx.menu.Size = UDim2.fromOffset(width, height)
	ctx.menu.ScrollingEnabled = rows > perColumn
	if touch then
		ctx.menu.AnchorPoint = Vector2.new(0, 0)
		ctx.menu.Position = UDim2.new(0, 4, 0, 4)
	else
		ctx.menu.AnchorPoint = Vector2.new(0, 0.5)
		ctx.menu.Position = UDim2.new(0, 4, 0.5, 0)
	end
	-- Keep modals centred but clear of the menu column.
	local inset = width + 12
	ctx.modalArea.Position = UDim2.new(0, inset, 0, MODAL_TOP)
	ctx.modalArea.Size = UDim2.new(1, -inset * 2, 1, -(MODAL_TOP + MODAL_BOTTOM))
	local menuTop = touch and 4 or (screen.Y - height) / 2
	local topInset = menuTop < 84 and inset or 8
	ctx.topArea.Position = UDim2.new(0, topInset, 0, 10)
	ctx.topArea.Size = UDim2.new(1, -topInset * 2, 0, 64)
end
ctx.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutMenu)

-- Adds a square icon button to the left menu. Lower order sorts first.
-- icon: optional glyph/emoji (defaults per known name); color: optional accent colour.
-- Returns the TextButton (Name = text; setting its TextColor3 recolours the caption) and the glyph label.
function ctx.AddMenuButton(text, order, onClick, icon, color)
	local preset = MENU_ICONS[text]
	local glyph = icon or (preset and preset[1]) or text:sub(1, 1):upper()
	local accent = color or (preset and preset[2]) or Theme.Gold
	local b = new("TextButton", {
		Name = text,
		Text = "",
		LayoutOrder = order or 100,
		AutoButtonColor = true,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		TextColor3 = Theme.Text,
		ZIndex = 2,
		Parent = ctx.menu,
	})
	ctx.corner(b, UDim.new(0, 14))
	ctx.stroke(b, accent, 2, 0.15)
	ctx.lipGradient(b, lighten(darken(accent, 0.55), 0.05), darken(accent, 0.8), darken(accent, 0.92), 4)
	local glyphLabel = new("TextLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 5),
		Size = UDim2.new(1, -16, 0.58, -6),
		BackgroundTransparency = 1,
		Text = glyph,
		TextScaled = true,
		Font = Theme.FontBlack,
		TextColor3 = lighten(accent, 0.2),
		ZIndex = 3,
		Parent = b,
	})
	local caption = new("TextLabel", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -4, 0, 14),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Theme.FontBold,
		TextColor3 = Theme.Text,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.45,
		ZIndex = 3,
		Parent = b,
	})
	ctx.maxText(caption, 12)
	b:GetPropertyChangedSignal("TextColor3"):Connect(function()
		caption.TextColor3 = b.TextColor3
	end)
	ctx.pressPop(b)
	if onClick then
		b.Activated:Connect(onClick)
	end
	menuCount += 1
	layoutMenu()
	return b, glyphLabel
end

return ctx
