-- Assigns museum plots, places relic models (RelicModels) on the display pedestals with a name plate and a
-- ceiling spotlight, and drives the plot's sign + owner billboard (name + star rating), locked/empty pedestal
-- look, security props and alarm beacons.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RelicRNG.Config)
local RelicModels = require(ReplicatedStorage.RelicRNG.RelicModels)

local plotsFolder = workspace:WaitForChild("RelicRNG"):WaitForChild("Museums")

local MuseumService = {}
local plotOwners = {} -- [plot] = player
local playerPlots = {} -- [player] = plot

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
local GOLD = Color3.fromRGB(222, 172, 64)
local WARM_WHITE = Color3.fromRGB(255, 247, 232)
local STAR_SIZE = 46 -- pixels per star on the sign
local MARBLE = Color3.fromRGB(246, 242, 234)
local IDLE_GLOW = Color3.fromRGB(120, 120, 120)
local EMPTY_GLOW = Color3.fromRGB(255, 205, 110)
local LOCKED_GLOW = Color3.fromRGB(45, 45, 55)
local LOCKED_STONE = Color3.fromRGB(84, 86, 98)
local LOCKED_METAL = Color3.fromRGB(96, 92, 84)
local ALARM_OFF = Color3.fromRGB(110, 16, 16)
local ALARM_ON = Color3.fromRGB(255, 40, 40)
local PLATE_DISTANCE = 30 -- relic name plates fade out beyond this many studs
local SPOT_HEIGHT = 9.5 -- ceiling spotlight height above the pedestal top

---------------------------------------------------------------- sign + owner billboard

local function signGui(plot)
	return plot.Sign:FindFirstChildOfClass("SurfaceGui")
end

local function ownerBoard(plot)
	local anchor = plot:FindFirstChild("OwnerBoard")
	return anchor and anchor:FindFirstChild("Board")
end

-- Sets the owner text on the entrance sign and the big billboard; `owned` toggles the billboard's subtitle.
local function setSign(plot, text, owned)
	local label = plot.Sign:FindFirstChild("Text", true)
	if label then
		label.Text = text
	end
	local board = ownerBoard(plot)
	if board then
		local panel = board:FindFirstChild("Panel")
		local title = panel and panel:FindFirstChild("Title")
		if title then
			title.Text = text
			title.TextColor3 = owned and Color3.fromRGB(255, 246, 225) or Color3.fromRGB(200, 196, 188)
		end
		local subtitle = panel and panel:FindFirstChild("Subtitle")
		if subtitle then
			subtitle.Visible = not owned
		end
	end
end

-- Fills `row`'s Star1..5 for `stars` (half steps allowed). The sign uses pixel-sized Fill frames,
-- the billboard uses scale-sized Clip frames holding a Gold star.
local function fillStarRow(row, stars, starPixels)
	for i = 1, 5 do
		local star = row:FindFirstChild("Star" .. i)
		local amount = math.clamp((stars or 0) - (i - 1), 0, 1)
		if star then
			local fill = star:FindFirstChild("Fill") or star:FindFirstChild("Clip")
			if fill and starPixels then
				fill.Size = UDim2.fromOffset(starPixels * amount, starPixels)
			elseif fill then
				fill.Visible = amount > 0
				fill.Size = UDim2.fromScale(amount, 1)
				local gold = fill:FindFirstChild("Gold")
				if gold and amount > 0 then
					gold.Size = UDim2.fromScale(1 / amount, 1)
				end
			end
		end
	end
end

-- Fills the sign's and billboard's five stars; nil hides them.
local function setStars(plot, stars)
	local gui = signGui(plot)
	local row = gui and gui:FindFirstChild("Stars")
	local caption = gui and gui:FindFirstChild("Rating")
	if row then
		row.Visible = stars ~= nil
		if caption then
			caption.Visible = stars == nil
		end
		fillStarRow(row, stars, STAR_SIZE)
	end
	local board = ownerBoard(plot)
	local panel = board and board:FindFirstChild("Panel")
	local boardRow = panel and panel:FindFirstChild("Stars")
	if boardRow then
		boardRow.Visible = stars ~= nil
		fillStarRow(boardRow, stars)
		local value = boardRow:FindFirstChild("Value")
		if value then
			value.Text = stars and ("%.1f"):format(stars) or ""
		end
	end
end

---------------------------------------------------------------- relic display

local function addPart(parent, shape, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Name plate above a relic: sized in studs (scales with distance like the world), never drawn on top of walls.
local function buildNamePlate(relic, rarity, height)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NamePlate"
	billboard.Size = UDim2.fromScale(5.2, 1.35)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	billboard.MaxDistance = PLATE_DISTANCE
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(18, 15, 24)
	panel.BackgroundTransparency = 0.25
	panel.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarity.Color
	stroke.Thickness = 1.5
	stroke.Parent = panel
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "RelicName"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromScale(0.06, 0.08)
	nameLabel.Size = UDim2.fromScale(0.88, 0.5)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = rarity.Color:Lerp(Color3.new(1, 1, 1), 0.15)
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Text = relic.Name
	nameLabel.Parent = panel
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "Info"
	infoLabel.BackgroundTransparency = 1
	infoLabel.Position = UDim2.fromScale(0.08, 0.6)
	infoLabel.Size = UDim2.fromScale(0.84, 0.3)
	infoLabel.Font = Enum.Font.GothamMedium
	infoLabel.TextScaled = true
	infoLabel.TextColor3 = Color3.fromRGB(240, 236, 225)
	infoLabel.Text = ("%s  ·  +%s/min"):format(rarity.Name, Config.FormatNumber(rarity.Income))
	infoLabel.Parent = panel
	return billboard
end

-- Places the shared relic model centred on `at`, with a name plate and the spin tag.
local function buildRelicModel(relicId, at, plateHeight)
	local relic = Config.RelicsById[relicId]
	local rarity = Config.Rarities[relic.Tier]
	local model = RelicModels.Build(relicId, at)
	buildNamePlate(relic, rarity, plateHeight).Parent = model.PrimaryPart
	CollectionService:AddTag(model, "RelicSpin")
	return model
end

-- Ceiling can light pointing down at the pedestal; brightness grows with rarity.
local function buildSpotlight(holder, pedestal, tier, accent)
	local top = pedestal.Top.Position
	local fixture = Instance.new("Model")
	fixture.Name = "Spotlight"
	local can = addPart(fixture, Enum.PartType.Cylinder, Vector3.new(0.9, 0.9, 0.9), CFrame.new(top + Vector3.new(0, SPOT_HEIGHT, 0)) * UPRIGHT, GOLD, Enum.Material.Foil)
	can.CastShadow = false
	local lens = addPart(fixture, Enum.PartType.Cylinder, Vector3.new(0.08, 0.7, 0.7), CFrame.new(top + Vector3.new(0, SPOT_HEIGHT - 0.46, 0)) * UPRIGHT, WARM_WHITE:Lerp(accent, 0.3), Enum.Material.Neon)
	lens.CastShadow = false
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 38
	light.Range = SPOT_HEIGHT + 5
	light.Brightness = 0.6 + tier * 0.18
	light.Color = WARM_WHITE:Lerp(accent, math.clamp(tier / 20, 0.05, 0.4))
	light.Shadows = false
	light.Parent = can
	fixture.Parent = holder
end

-- Static showcase dressing around a relic: glass case for Mythic+, light pillar for World Wonder+.
local function buildShowcase(holder, pedestal, tier)
	local topY = pedestal.Top.Position.Y + pedestal.Top.Size.X / 2
	local x, z = pedestal.Top.Position.X, pedestal.Top.Position.Z
	local accent = Config.Rarities[tier].Color
	local case = Instance.new("Model")
	case.Name = "Showcase"
	if tier >= 6 then
		local height = tier >= 9 and 5.6 or 4.4
		local glass = addPart(case, Enum.PartType.Block, Vector3.new(3.1, height, 3.1), CFrame.new(x, topY + height / 2, z), Color3.fromRGB(210, 235, 245), Enum.Material.Glass)
		glass.Transparency = 0.82
		glass.CastShadow = false
		addPart(case, Enum.PartType.Block, Vector3.new(3.4, 0.3, 3.4), CFrame.new(x, topY + height + 0.15, z), GOLD, Enum.Material.Foil)
		addPart(case, Enum.PartType.Block, Vector3.new(3.4, 0.3, 3.4), CFrame.new(x, topY + 0.15, z), GOLD, Enum.Material.Foil)
		for _, corner in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
			local post = addPart(case, Enum.PartType.Block, Vector3.new(0.18, height, 0.18), CFrame.new(x + corner[1] * 1.56, topY + height / 2, z + corner[2] * 1.56), GOLD, Enum.Material.Foil)
			post.CastShadow = false
		end
	end
	if tier >= 8 then
		local pillar = addPart(case, Enum.PartType.Cylinder, Vector3.new(SPOT_HEIGHT - 1, 2.6, 2.6), CFrame.new(x, topY + (SPOT_HEIGHT - 1) / 2, z) * UPRIGHT, accent, Enum.Material.Neon)
		pillar.Transparency = 0.9
		pillar.CastShadow = false
	end
	if #case:GetChildren() > 0 then
		case.Parent = holder
	else
		case:Destroy()
	end
end

---------------------------------------------------------------- pedestal looks

local function setPedestalLook(pedestal, look, glowColor, tier)
	local locked = look == "Locked"
	for _, part in ipairs(pedestal:GetChildren()) do
		if part:IsA("BasePart") then
			part.Transparency = 0
			if part.Name == "Base" then
				part.Color = locked and LOCKED_STONE or MARBLE
			elseif part.Name == "Top" or part.Name == "Collar" or part.Name == "Neck" then
				part.Color = locked and LOCKED_METAL or GOLD
			end
		end
	end
	local glow = pedestal.Glow
	if look == "Filled" then
		glow.Color = glowColor
		glow.Material = (tier or 1) >= 3 and Enum.Material.Neon or Enum.Material.SmoothPlastic
		glow.Transparency = math.clamp(0.55 - (tier or 1) * 0.05, 0.05, 0.5)
	elseif look == "Empty" then
		glow.Color = EMPTY_GLOW
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.45
	elseif locked then
		glow.Color = LOCKED_GLOW
		glow.Material = Enum.Material.SmoothPlastic
		glow.Transparency = 0.7
	else
		glow.Color = IDLE_GLOW
		glow.Material = Enum.Material.SmoothPlastic
		glow.Transparency = 0.6
	end
	local top = pedestal.Top
	local lockGui, emptyGui = top:FindFirstChild("LockGui"), top:FindFirstChild("EmptyGui")
	if lockGui then
		lockGui.Enabled = locked
	end
	if emptyGui then
		emptyGui.Enabled = look == "Empty"
	end
	pedestal:SetAttribute("Locked", locked)
end

local function clearRelics(plot)
	local holder = plot:FindFirstChild("Relics")
	if holder then
		holder:Destroy()
	end
end

---------------------------------------------------------------- security props

local function minLevelOf(inst, root)
	local node = inst
	while node and node ~= root do
		local min = node:GetAttribute("MinLevel")
		if min then
			return min
		end
		node = node.Parent
	end
	return 0
end

local function applySecurity(plot, level)
	local folder = plot:FindFirstChild("Security")
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			local shown = level >= minLevelOf(d, folder)
			d.Transparency = shown and (d:GetAttribute("BaseTransparency") or 0) or 1
		end
	end
	plot:SetAttribute("SecurityLevel", level)
end

local function applyAlarm(plot, on)
	local alarm = plot:FindFirstChild("Security") and plot.Security:FindFirstChild("Alarm")
	if not alarm then
		return
	end
	for _, beacon in ipairs(alarm:GetChildren()) do
		if beacon.Name == "Beacon" then
			beacon.Material = on and Enum.Material.Neon or Enum.Material.Glass
			beacon.Color = on and ALARM_ON or ALARM_OFF
			local light = beacon:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = on
			end
		end
	end
end

local function resetPlot(plot)
	clearRelics(plot)
	for _, pedestal in ipairs(plot.Pedestals:GetChildren()) do
		setPedestalLook(pedestal, "Idle")
	end
	applySecurity(plot, 0)
	applyAlarm(plot, false)
	setSign(plot, "Available Museum", false)
	setStars(plot, nil)
	plot:SetAttribute("OwnerUserId", nil)
	plot:SetAttribute("OwnerName", nil)
	plot:SetAttribute("MuseumRating", nil)
end

---------------------------------------------------------------- public API

function MuseumService.Assign(player)
	local plots = plotsFolder:GetChildren()
	table.sort(plots, function(a, b)
		return (a:GetAttribute("PlotIndex") or 0) < (b:GetAttribute("PlotIndex") or 0)
	end)
	for _, plot in ipairs(plots) do
		if not plotOwners[plot] then
			plotOwners[plot] = player
			playerPlots[player] = plot
			plot:SetAttribute("OwnerUserId", player.UserId)
			plot:SetAttribute("OwnerName", player.DisplayName)
			setSign(plot, player.DisplayName .. "'s Museum", true)
			setStars(plot, 1)
			return plot
		end
	end
	return nil
end

function MuseumService.GetPlot(player)
	return playerPlots[player]
end

-- Rebuilds the relic models to match the player's Displayed table.
-- Pedestals numbered above `slots` are shown as locked, unlocked empty ones invite a relic.
function MuseumService.Refresh(player, displayed, slots)
	local plot = playerPlots[player]
	if not plot then
		return
	end
	clearRelics(plot)
	slots = slots or Config.Economy.DisplaySlots
	local holder = Instance.new("Folder")
	holder.Name = "Relics"
	for _, pedestal in ipairs(plot.Pedestals:GetChildren()) do
		local slot = pedestal:GetAttribute("Slot") or 0
		local relicId = displayed[tostring(slot)]
		local relic = relicId and Config.RelicsById[relicId]
		if slot > slots then
			setPedestalLook(pedestal, "Locked")
		elseif relic then
			local tier = relic.Tier
			local rarity = Config.Rarities[tier]
			setPedestalLook(pedestal, "Filled", rarity.Color, tier)
			local lift = tier >= 9 and 3.4 or 2.3
			-- keep the plate above the glass case for Mythic+ relics
			local plateHeight = tier >= 9 and 3.5 or tier >= 6 and 3.4 or 2.5
			local model = buildRelicModel(relicId, CFrame.new(pedestal.Top.Position + Vector3.new(0, lift, 0)), plateHeight)
			model:SetAttribute("Slot", slot)
			model.Parent = holder
			buildShowcase(holder, pedestal, tier)
			buildSpotlight(holder, pedestal, tier, rarity.Color)
		else
			setPedestalLook(pedestal, "Empty")
		end
	end
	holder.Parent = plot
end

-- Shows the museum's star rating (1..5, half steps) on the plot sign and owner billboard.
function MuseumService.SetRating(player, stars)
	local plot = playerPlots[player]
	if plot then
		setStars(plot, stars)
		plot:SetAttribute("MuseumRating", stars)
	end
end

-- Shows the security props for `level` (0..10) on the player's plot.
function MuseumService.SetSecurity(player, level)
	local plot = playerPlots[player]
	if plot then
		applySecurity(plot, level)
	end
end

-- Turns the plot's alarm beacons on or off (the Security service flashes them during a break-in).
function MuseumService.SetAlarm(player, on)
	local plot = playerPlots[player]
	if plot then
		applyAlarm(plot, on)
	end
end

function MuseumService.Release(player)
	local plot = playerPlots[player]
	if not plot then
		return
	end
	resetPlot(plot)
	plotOwners[plot] = nil
	playerPlots[player] = nil
end

for _, plot in ipairs(plotsFolder:GetChildren()) do
	resetPlot(plot)
end

return MuseumService
