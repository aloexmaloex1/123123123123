-- Heist service: NPC museum heists, the game's signature mechanic.
-- Server-authoritative. Each heist gets its own museum generated from HeistMaps far from the main
-- world (Workspace.RelicRNG.ActiveHeists), guards/cameras/lasers are simulated here with detection at
-- ~10 Hz. Guards and camera heads exist only as numbers on the server: the client (Features.70_Heist)
-- builds and animates them from the "Heist" Start/State events and draws the HUD.
-- Anti-cheat: server-checked steal hold time, movement plausibility (speed budget, walls, noclip) with
-- rubber-banding, and minimum steal / escape times derived from the map's shortest walk.
-- Finished museums are reset and pooled per map (HeistMaps.PoolMaps) instead of rebuilt.
-- Actions: StartHeist(mapId), UseHeistTool(toolId), BuyHeistTool(toolId), AbandonHeist().
-- Saved: data.Heist = { Energy, EnergyAt, Notoriety, Wins, Fails, BestTimes, Tools }.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("RelicRNG")
local Tuning = require(Shared:WaitForChild("FeatureConfig"):WaitForChild("Heist"))
local HeistMaps = require(script.Parent.Parent:WaitForChild("HeistMaps"))

local Heist = { Priority = 60 }

local CELL = HeistMaps.CellSize
local WALL_HEIGHT = HeistMaps.WallHeight
local Sec = Tuning.Security
local AC = HeistMaps.AntiCheat
local SLOT_SPACING = 500
local ORIGIN_X = 4000
local RELEASE_DELAY = 3 -- seconds a finished museum stays untouched while its thief is teleported out
local LOAD_TIMEOUT = 6 -- longest the thief is held at the entry waiting for the client's HeistReady
local CEILING_LIGHT_TAG = "HeistCeilingLight" -- the client pulses these during lockdown
local STEAL_REACH = 14 -- server-side distance check for the Steal prompt (it activates at 9)
local DIRECT_CHASE_RANGE = 18 -- lockdown guards run straight at a thief they can see this close

local RED = Color3.fromRGB(255, 40, 55)
local ALARM_RED = Color3.fromRGB(255, 30, 40)
local GREEN = Color3.fromRGB(60, 255, 140)
local EMP_BLUE = Tuning.EmpBlue
local FLASH_WARM = Color3.fromRGB(255, 238, 205)
local PLATE_AMBER = Color3.fromRGB(255, 160, 40)
local CEILING_BRIGHTNESS = 3.2
local EXIT_PAD_IDLE = 0.55

local DIR_VEC = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

local core
local active = {} -- [player] = heist state
local slots = {} -- [slot] = map occupying that slot (running, cooling down or pooled)
local pool = {} -- [mapId] = { idle maps ready for reuse }
local activeFolder
local rng = Random.new()

local function serverNow()
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------- part builders

local function mk(className, parent, props)
	local inst = Instance.new(className)
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.TopSurface = Enum.SurfaceType.Smooth
		inst.BottomSurface = Enum.SurfaceType.Smooth
	end
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

-- Non-colliding decoration.
local function deco(parent, size, cframe, color, material, extra)
	local p = mk("Part", parent, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	if extra then
		for key, value in pairs(extra) do
			p[key] = value
		end
	end
	return p
end

-- Colliding part that also blocks guard/camera sight when parented to the map's Solid folder.
local function solid(parent, size, cframe, color, material)
	return mk("Part", parent, { Size = size, CFrame = cframe, Color = color, Material = material or Enum.Material.SmoothPlastic, CanTouch = false })
end

local function cellCenter(origin, c, r)
	return origin + Vector3.new((c - 0.5) * CELL, 0, (r - 0.5) * CELL)
end

local function billboard(parent, text, color, offset, size)
	local gui = mk("BillboardGui", parent, {
		Size = size or UDim2.fromOffset(150, 40),
		StudsOffsetWorldSpace = offset or Vector3.zero,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 400,
	})
	local labelText = mk("TextLabel", gui, {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = color,
		TextStrokeTransparency = 0.2,
		Text = text,
	})
	return gui, labelText
end

-- Small placeholder relics for display cases and the target.
local function buildTrinket(parent, shape, color, at, scale)
	local s = scale or 1
	local glow = Enum.Material.Neon
	local metal = Enum.Material.Foil
	local main
	local cyl = Enum.PartType.Cylinder
	local ball = Enum.PartType.Ball
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local cf = CFrame.new(at)
	if shape == "Ball" then
		main = deco(parent, Vector3.new(1.8, 1.8, 1.8) * s, cf, color, Enum.Material.Glass, { Shape = ball, Reflectance = 0.3 })
		deco(parent, Vector3.new(1.2, 1.2, 1.2) * s, cf, color:Lerp(Color3.new(1, 1, 1), 0.35), glow, { Shape = ball, Transparency = 0.15 })
		deco(parent, Vector3.new(0.15, 2.6, 2.6) * s, cf * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(20), 0, 0), color:Lerp(Color3.new(1, 1, 1), 0.5), glow, { Shape = cyl, Transparency = 0.2 })
		deco(parent, Vector3.new(0.4, 1.2, 1.2) * s, cf * CFrame.new(0, -1 * s, 0) * upright, Color3.fromRGB(40, 36, 44), metal, { Shape = cyl })
	elseif shape == "Crown" then
		main = deco(parent, Vector3.new(0.8, 2.2, 2.2) * s, cf * upright, color, metal, { Shape = cyl })
		deco(parent, Vector3.new(0.82, 1.7, 1.7) * s, cf * upright, Color3.fromRGB(30, 20, 40), Enum.Material.Fabric, { Shape = cyl })
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			deco(parent, Vector3.new(0.3, 0.9, 0.3) * s, cf * CFrame.new(math.cos(a) * 0.95 * s, 0.7 * s, math.sin(a) * 0.95 * s), color, metal)
			deco(parent, Vector3.new(0.34, 0.34, 0.34) * s, cf * CFrame.new(math.cos(a) * 0.95 * s, 1.2 * s, math.sin(a) * 0.95 * s), color:Lerp(Color3.new(1, 1, 1), 0.4), glow, { Shape = ball })
		end
	elseif shape == "Idol" then
		main = deco(parent, Vector3.new(0.9, 1.7, 0.7) * s, cf, color, metal)
		deco(parent, Vector3.new(1, 1, 1) * s, cf * CFrame.new(0, 1.3 * s, 0), color, metal, { Shape = ball })
		deco(parent, Vector3.new(0.7, 0.18, 0.1) * s, cf * CFrame.new(0, 1.35 * s, -0.46 * s), Color3.fromRGB(255, 80, 60), glow)
		deco(parent, Vector3.new(0.35, 1.5, 1.5) * s, cf * CFrame.new(0, -1.05 * s, 0) * upright, Color3.fromRGB(40, 32, 30), metal, { Shape = cyl })
		deco(parent, Vector3.new(0.12, 2.4, 2.4) * s, cf * CFrame.new(0, 1.3 * s, 0.35 * s) * CFrame.Angles(0, math.rad(90), 0), color:Lerp(Color3.new(1, 1, 1), 0.3), glow, { Shape = cyl, Transparency = 0.35 })
	elseif shape == "Vase" then
		main = deco(parent, Vector3.new(1.8, 1.5, 1.5) * s, cf * upright, color, Enum.Material.Marble, { Shape = cyl })
		deco(parent, Vector3.new(0.8, 0.8, 0.8) * s, cf * CFrame.new(0, 1.2 * s, 0) * upright, color, Enum.Material.Marble, { Shape = cyl })
		deco(parent, Vector3.new(0.15, 1.56, 1.56) * s, cf * CFrame.new(0, 0.3 * s, 0) * upright, Color3.fromRGB(255, 215, 120), glow, { Shape = cyl })
	else -- Coin
		main = deco(parent, Vector3.new(0.3, 2, 2) * s, cf, color, metal, { Shape = cyl })
		deco(parent, Vector3.new(0.34, 1.2, 1.2) * s, cf, color:Lerp(Color3.new(1, 1, 1), 0.4), glow, { Shape = cyl })
		deco(parent, Vector3.new(0.3, 0.9, 0.9) * s, cf * CFrame.new(0, -1.3 * s, 0), Color3.fromRGB(40, 36, 44), metal)
	end
	return main
end

---------------------------------------------------------------- map generation

-- Builds a whole museum for `mapId` with its north-west corner at `origin`. Returns the map table the
-- simulation drives. Public so the map can be previewed in Edit mode.
function Heist.BuildMap(mapId, origin, parent)
	local spec = HeistMaps.Maps[mapId]
	assert(spec, "unknown heist map " .. tostring(mapId))
	local layout = HeistMaps.Parse(spec)
	local pal = spec.Palette
	local seeded = Random.new(spec.Seed or 1)
	local W, H = layout.Width, layout.Height
	local function get(c, r)
		return HeistMaps.Get(layout, c, r)
	end

	local model = Instance.new("Model")
	model.Name = mapId
	local solidFolder = mk("Folder", model, { Name = "Solid" })
	local decor = mk("Folder", model, { Name = "Decor" })
	local fx = mk("Folder", model, { Name = "Effects" })
	local map = {
		Id = mapId, Spec = spec, Layout = layout, Origin = origin, Model = model, Solid = solidFolder, Effects = fx,
		Palette = pal, Lights = {}, Trims = {}, Lasers = {}, Plates = {}, Sticky = {}, Cameras = {},
	}

	-- Floor: dark grout slab with a checker of polished tiles on every open cell.
	local size = Vector3.new(W * CELL, 0, H * CELL)
	map.Floor = solid(model, Vector3.new(size.X, 2, size.Z), CFrame.new(origin + Vector3.new(size.X / 2, -1, size.Z / 2)), pal.Grout, Enum.Material.Slate)
	map.Floor.Name = "Floor"
	for _, cell in ipairs(layout.Floor) do
		local c, r = cell[1], cell[2]
		deco(decor, Vector3.new(CELL - 0.3, 0.2, CELL - 0.3), CFrame.new(cellCenter(origin, c, r)), (c + r) % 2 == 0 and pal.Floor1 or pal.Floor2, pal.FloorMaterial, { Reflectance = 0.04 })
	end
	map.Ceiling = solid(model, Vector3.new(size.X, 1, size.Z), CFrame.new(origin + Vector3.new(size.X / 2, WALL_HEIGHT + 0.5, size.Z / 2)), pal.Ceiling, Enum.Material.Plaster)
	map.Ceiling.Name = "Ceiling"

	-- Walls: merged horizontal runs with a dark wainscot, brass rail, glowing baseboard and a cornice.
	for r = 1, H do
		local c = 1
		while c <= W do
			if HeistMaps.IsWall(get(c, r)) then
				local start = c
				while c + 1 <= W and HeistMaps.IsWall(get(c + 1, r)) do
					c += 1
				end
				local len = c - start + 1
				local center = origin + Vector3.new((start - 1 + len / 2) * CELL, 0, (r - 0.5) * CELL)
				local sx, sz = len * CELL, CELL
				solid(solidFolder, Vector3.new(sx, WALL_HEIGHT, sz), CFrame.new(center + Vector3.new(0, WALL_HEIGHT / 2, 0)), pal.Wall, pal.WallMaterial)
				deco(decor, Vector3.new(sx + 0.16, 4.2, sz + 0.16), CFrame.new(center + Vector3.new(0, 3.3, 0)), pal.Wainscot, pal.WallMaterial)
				deco(decor, Vector3.new(sx + 0.3, 0.25, sz + 0.3), CFrame.new(center + Vector3.new(0, 5.45, 0)), pal.Rail, Enum.Material.Metal)
				table.insert(map.Trims, deco(decor, Vector3.new(sx + 0.3, 0.3, sz + 0.3), CFrame.new(center + Vector3.new(0, 1, 0)), pal.Trim, Enum.Material.Neon))
				deco(decor, Vector3.new(sx + 0.5, 0.9, sz + 0.5), CFrame.new(center + Vector3.new(0, WALL_HEIGHT - 0.45, 0)), pal.Cap, Enum.Material.Metal)
			end
			c += 1
		end
	end

	-- Pilasters every other cell edge give the walls rhythm.
	local placed = {}
	for _, cell in ipairs(layout.Floor) do
		local c, r = cell[1], cell[2]
		for _, dirName in ipairs(HeistMaps.DirOrder) do
			local d = HeistMaps.Dirs[dirName]
			if HeistMaps.IsWall(get(c + d[1], r + d[2])) then
				local dir = DIR_VEC[dirName]
				local side = Vector3.new(math.abs(dir.Z), 0, math.abs(dir.X))
				for _, s in ipairs({ -1, 1 }) do
					local edge = cellCenter(origin, c, r) + dir * (CELL / 2) + side * s * (CELL / 2)
					local index = dir.X ~= 0 and math.floor((edge.Z - origin.Z) / CELL + 0.5) or math.floor((edge.X - origin.X) / CELL + 0.5)
					local key = math.floor(edge.X * 10 + 0.5) .. ":" .. math.floor(edge.Z * 10 + 0.5) .. dirName
					if index % 2 == 0 and not placed[key] then
						placed[key] = true
						local at = edge - dir * 0.35
						deco(decor, Vector3.new(1.5, WALL_HEIGHT - 1, 1.5) - Vector3.new(dir.X ~= 0 and 0.8 or 0, 0, dir.Z ~= 0 and 0.8 or 0), CFrame.new(at + Vector3.new(0, (WALL_HEIGHT - 1) / 2, 0)), pal.Wall:Lerp(Color3.new(1, 1, 1), 0.05), pal.WallMaterial)
						deco(decor, Vector3.new(1.9, 0.5, 1.9) - Vector3.new(dir.X ~= 0 and 0.9 or 0, 0, dir.Z ~= 0 and 0.9 or 0), CFrame.new(at + Vector3.new(0, WALL_HEIGHT - 1.6, 0)), pal.Rail, Enum.Material.Metal)
					end
				end
			end
		end
	end

	-- Ceiling spotlights make pools of light with dark gaps between them.
	for _, cell in ipairs(layout.Floor) do
		local c, r = cell[1], cell[2]
		local ch = get(c, r)
		if c % 2 == 0 and r % 2 == 0 and ch ~= "T" and ch ~= "E" and ch ~= "L" then
			local pos = cellCenter(origin, c, r) + Vector3.new(0, WALL_HEIGHT - 0.1, 0)
			deco(decor, Vector3.new(3.6, 0.25, 3.6), CFrame.new(pos), pal.Cap, Enum.Material.Metal)
			local panel = deco(decor, Vector3.new(2.6, 0.3, 2.6), CFrame.new(pos - Vector3.new(0, 0.1, 0)), pal.Light, Enum.Material.Neon, { Name = "CeilingLight" })
			CollectionService:AddTag(panel, CEILING_LIGHT_TAG)
			-- No shadows: dozens of shadowed spotlights per museum are far too expensive.
			local light = mk("SpotLight", panel, { Face = Enum.NormalId.Bottom, Angle = 80, Range = 20, Brightness = CEILING_BRIGHTNESS, Color = pal.Light, Shadows = false })
			table.insert(map.Lights, { Panel = panel, Light = light })
		end
	end

	-- Paintings with little picture lights on some wall faces.
	for _, cell in ipairs(layout.Floor) do
		local c, r = cell[1], cell[2]
		local ch = get(c, r)
		if ch ~= "E" and ch ~= "L" and ch ~= "T" then
			for _, dirName in ipairs(HeistMaps.DirOrder) do
				local d = HeistMaps.Dirs[dirName]
				if get(c + d[1], r + d[2]) == "#" and seeded:NextNumber() < (spec.PaintingChance or 0.2) then
					local dir = DIR_VEC[dirName]
					local face = cellCenter(origin, c, r) + dir * (CELL / 2) + Vector3.new(0, 8.6, 0)
					local facing = CFrame.lookAt(face - dir * 0.2, face - dir * 2)
					deco(decor, Vector3.new(6, 4.4, 0.35), facing, pal.Rail, Enum.Material.Foil)
					local canvas = deco(decor, Vector3.new(5.2, 3.6, 0.1), facing * CFrame.new(0, 0, -0.2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
					local surface = mk("SurfaceGui", canvas, { Face = Enum.NormalId.Front, LightInfluence = 1, PixelsPerStud = 20 })
					local art = mk("Frame", surface, { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1) })
					local a = Color3.fromHSV(seeded:NextNumber(), 0.55 + seeded:NextNumber() * 0.3, 0.35 + seeded:NextNumber() * 0.35)
					local b = Color3.fromHSV(seeded:NextNumber(), 0.6, 0.12 + seeded:NextNumber() * 0.2)
					mk("UIGradient", art, { Color = ColorSequence.new(a, b), Rotation = seeded:NextInteger(0, 359) })
					local orb = mk("Frame", art, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.3 + seeded:NextNumber() * 0.4, 0.35 + seeded:NextNumber() * 0.3), Size = UDim2.fromScale(0.28, 0.4), BackgroundColor3 = b:Lerp(Color3.new(1, 1, 1), 0.5), BorderSizePixel = 0 })
					mk("UICorner", orb, { CornerRadius = UDim.new(1, 0) })
					local lamp = deco(decor, Vector3.new(2.6, 0.25, 0.6), facing * CFrame.new(0, 2.7, -0.45), pal.Rail, Enum.Material.Metal)
					mk("SpotLight", lamp, { Face = Enum.NormalId.Bottom, Angle = 80, Range = 7, Brightness = 1.6, Color = FLASH_WARM })
				end
			end
		end
	end

	-- Display cases with decoy relics (they block sight: hide behind them).
	local shapes = { "Ball", "Vase", "Crown", "Idol", "Coin" }
	for i, cell in ipairs(layout.Decor) do
		local base = cellCenter(origin, cell[1], cell[2])
		local color = spec.DecorColors[(i - 1) % #spec.DecorColors + 1]
		deco(decor, Vector3.new(4.6, 0.4, 4.6), CFrame.new(base + Vector3.new(0, 0.3, 0)), pal.Cap, Enum.Material.Metal)
		solid(solidFolder, Vector3.new(3.8, 3.6, 3.8), CFrame.new(base + Vector3.new(0, 2, 0)), pal.Pedestal, Enum.Material.Marble)
		deco(decor, Vector3.new(4.2, 0.2, 4.2), CFrame.new(base + Vector3.new(0, 3.85, 0)), color, Enum.Material.Neon, { Transparency = 0.1 })
		local case = solid(solidFolder, Vector3.new(3.5, 3.4, 3.5), CFrame.new(base + Vector3.new(0, 5.65, 0)), Color3.fromRGB(190, 210, 255), Enum.Material.Glass)
		case.Transparency = 0.82
		deco(decor, Vector3.new(3.7, 0.15, 3.7), CFrame.new(base + Vector3.new(0, 7.4, 0)), pal.Cap, Enum.Material.Metal)
		local trinket = buildTrinket(decor, shapes[(i - 1) % #shapes + 1], color, base + Vector3.new(0, 5.4, 0), 0.75)
		mk("PointLight", trinket, { Color = color, Range = 9, Brightness = 1.3 })
	end

	-- Target: stepped dais, pedestal, glass case, spotlight, velvet posts and the Steal prompt.
	do
		local tpos = cellCenter(origin, layout.Target[1], layout.Target[2])
		local relicInfo = spec.TargetRelic
		mk("Part", model, { Size = Vector3.new(9, 0.5, 9), CFrame = CFrame.new(tpos + Vector3.new(0, 0.25, 0)), Color = pal.Pedestal, Material = Enum.Material.Marble, CanTouch = false })
		mk("Part", model, { Size = Vector3.new(7, 0.5, 7), CFrame = CFrame.new(tpos + Vector3.new(0, 0.75, 0)), Color = pal.Wainscot, Material = Enum.Material.Marble, CanTouch = false })
		deco(decor, Vector3.new(0.12, 9.6, 9.6), CFrame.new(tpos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), pal.Accent, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, Transparency = 0.25 })
		local pedestal = solid(solidFolder, Vector3.new(3, 3.4, 3), CFrame.new(tpos + Vector3.new(0, 2.7, 0)), pal.Pedestal, Enum.Material.Marble)
		pedestal.Name = "TargetPedestal"
		deco(decor, Vector3.new(3.6, 0.3, 3.6), CFrame.new(tpos + Vector3.new(0, 4.5, 0)), pal.Accent, Enum.Material.Foil)
		local relicParts = mk("Folder", model, { Name = "TargetRelic" })
		local main = buildTrinket(relicParts, relicInfo.Shape, relicInfo.Color, tpos + Vector3.new(0, 6.5, 0), 1.6)
		mk("PointLight", main, { Color = pal.Accent, Range = 12, Brightness = 2 })
		mk("ParticleEmitter", main, {
			Color = ColorSequence.new(pal.Accent),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(1, 1.8),
			Rate = 10,
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180),
		})
		local case = deco(relicParts, Vector3.new(4.6, 5, 4.6), CFrame.new(tpos + Vector3.new(0, 7.1, 0)), Color3.fromRGB(200, 220, 255), Enum.Material.Glass, { Transparency = 0.8 })
		case.Name = "Case"
		local spot = deco(decor, Vector3.new(2, 0.4, 2), CFrame.new(tpos + Vector3.new(0, WALL_HEIGHT - 0.3, 0)), pal.Cap, Enum.Material.Metal)
		mk("SpotLight", spot, { Face = Enum.NormalId.Bottom, Angle = 40, Range = 22, Brightness = 7, Color = pal.Accent, Shadows = true })
		local shaftTop = mk("Attachment", spot, { Position = Vector3.new(0, -0.2, 0) })
		local shaftBottom = mk("Attachment", map.Floor, {})
		shaftBottom.WorldPosition = tpos + Vector3.new(0, 1, 0)
		mk("Beam", spot, {
			Attachment0 = shaftTop,
			Attachment1 = shaftBottom,
			FaceCamera = true,
			Width0 = 2.2,
			Width1 = 8,
			Segments = 1,
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new(pal.Accent),
			Transparency = NumberSequence.new(0.8, 0.94),
		})
		local corners = { Vector3.new(4.2, 0, 4.2), Vector3.new(-4.2, 0, 4.2), Vector3.new(-4.2, 0, -4.2), Vector3.new(4.2, 0, -4.2) }
		for i, corner in ipairs(corners) do
			deco(decor, Vector3.new(0.35, 3, 0.35), CFrame.new(tpos + corner + Vector3.new(0, 1.5, 0)), pal.Rail, Enum.Material.Metal)
			deco(decor, Vector3.new(0.6, 0.6, 0.6), CFrame.new(tpos + corner + Vector3.new(0, 3.1, 0)), pal.Accent, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
			local a, b = tpos + corner + Vector3.new(0, 2.5, 0), tpos + corners[i % 4 + 1] + Vector3.new(0, 2.5, 0)
			deco(decor, Vector3.new(0.18, 0.18, (b - a).Magnitude), CFrame.lookAt((a + b) / 2 - Vector3.new(0, 0.35, 0), b - Vector3.new(0, 0.35, 0)), Color3.fromRGB(130, 18, 40), Enum.Material.Fabric)
		end
		local attachment = mk("Attachment", pedestal, { Position = Vector3.new(0, 2.2, 0) })
		local prompt = mk("ProximityPrompt", attachment, {
			ActionText = "Steal",
			ObjectText = relicInfo.Name,
			HoldDuration = Tuning.StealSeconds,
			MaxActivationDistance = 9,
			RequiresLineOfSight = false,
			KeyboardKeyCode = Enum.KeyCode.E,
		})
		local marker = billboard(main, "TARGET", pal.Accent, Vector3.new(0, 3.2, 0), UDim2.fromOffset(110, 30))
		map.Target = { Position = tpos, Prompt = prompt, Relic = relicParts, Marker = marker, Name = relicInfo.Name }
	end

	-- Entry / exit: green pad and a lit exit door on the nearest outer wall.
	do
		local e = layout.Entry
		local epos = cellCenter(origin, e[1], e[2])
		local doorDir
		for _, dirName in ipairs(HeistMaps.DirOrder) do
			local d = HeistMaps.Dirs[dirName]
			if HeistMaps.IsWall(get(e[1] + d[1], e[2] + d[2])) then
				local nc, nr = e[1] + d[1], e[2] + d[2]
				if nc == 1 or nr == 1 or nc == W or nr == H then
					doorDir = dirName
					break
				end
				doorDir = doorDir or dirName
			end
		end
		doorDir = doorDir or "S"
		local dir = DIR_VEC[doorDir]
		local pad = deco(decor, Vector3.new(7, 0.12, 7), CFrame.new(epos + Vector3.new(0, 0.16, 0)), GREEN, Enum.Material.Neon, { Transparency = EXIT_PAD_IDLE })
		deco(decor, Vector3.new(0.1, 8.2, 8.2), CFrame.new(epos + Vector3.new(0, 0.13, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(20, 60, 40), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		local wallFace = epos + dir * (CELL / 2)
		local doorCF = CFrame.lookAt(wallFace - dir * 0.2 + Vector3.new(0, 4.6, 0), wallFace - dir * 5 + Vector3.new(0, 4.6, 0))
		deco(decor, Vector3.new(6, 9.2, 0.4), doorCF, Color3.fromRGB(16, 22, 20), Enum.Material.DiamondPlate)
		for _, x in ipairs({ -3.2, 3.2 }) do
			deco(decor, Vector3.new(0.45, 9.6, 0.5), doorCF * CFrame.new(x, 0.2, -0.1), GREEN, Enum.Material.Neon)
		end
		deco(decor, Vector3.new(6.9, 0.45, 0.5), doorCF * CFrame.new(0, 5, -0.1), GREEN, Enum.Material.Neon)
		local sign = deco(decor, Vector3.new(4, 1.2, 0.2), doorCF * CFrame.new(0, 6.3, -0.2), Color3.fromRGB(10, 30, 18), Enum.Material.SmoothPlastic)
		local signGui = mk("SurfaceGui", sign, { Face = Enum.NormalId.Front, LightInfluence = 0, PixelsPerStud = 40 })
		mk("TextLabel", signGui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextScaled = true, TextColor3 = GREEN, Text = "EXIT" })
		mk("PointLight", pad, { Color = GREEN, Range = 16, Brightness = 1.6 })
		local exitMarker = billboard(pad, "EXIT", GREEN, Vector3.new(0, 6, 0), UDim2.fromOffset(110, 34))
		exitMarker.Enabled = false
		map.ExitPos = epos
		map.ExitPad = pad
		map.ExitMarker = exitMarker
		map.EntryCF = CFrame.lookAt(epos + Vector3.new(0, 0.2, 0), epos + Vector3.new(0, 0.2, 0) - dir)
	end

	-- Lasers: emitter posts with five stacked beams across the cell.
	for i, cell in ipairs(layout.Lasers) do
		local center = cellCenter(origin, cell[1], cell[2])
		local axis = cell[3]
		local along = axis == "X" and Vector3.xAxis or Vector3.zAxis
		local rot = axis == "X" and CFrame.new() or CFrame.Angles(0, math.rad(90), 0)
		local beams = {}
		for _, y in ipairs(HeistMaps.LaserHeights) do
			table.insert(beams, deco(fx, Vector3.new(CELL, 0.16, 0.16), CFrame.new(center + Vector3.new(0, y, 0)) * rot, RED, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder }))
		end
		local tips = {}
		for _, side in ipairs({ -1, 1 }) do
			-- Neighbouring laser cells share one continuous gate, so only the outer ends get posts.
			local neighbour = get(cell[1] + math.round(along.X) * side, cell[2] + math.round(along.Z) * side)
			if neighbour == "L" then
				continue
			end
			local postPos = center + along * side * (CELL / 2 - 0.35)
			deco(decor, Vector3.new(0.7, 9.6, 0.7), CFrame.new(postPos + Vector3.new(0, 4.8, 0)), Color3.fromRGB(28, 28, 34), Enum.Material.Metal)
			table.insert(tips, deco(fx, Vector3.new(0.3, 9, 0.3), CFrame.new(postPos - along * side * 0.3 + Vector3.new(0, 4.8, 0)), RED, Enum.Material.Neon))
		end
		local light = mk("PointLight", beams[3], { Color = RED, Range = 12, Brightness = 1.6 })
		map.Lasers[i] = { Center = center, Axis = axis, Group = cell[4], Beams = beams, Tips = tips, Light = light, On = true, CooldownUntil = 0 }
	end

	-- Pressure plates: dull steel with a faint amber seam.
	for i, cell in ipairs(layout.Plates) do
		local center = cellCenter(origin, cell[1], cell[2])
		local seam = deco(fx, Vector3.new(7.4, 0.14, 7.4), CFrame.new(center + Vector3.new(0, 0.14, 0)), Color3.fromRGB(255, 160, 40), Enum.Material.Neon, { Transparency = 0.62 })
		local plate = deco(decor, Vector3.new(6.8, 0.3, 6.8), CFrame.new(center + Vector3.new(0, 0.2, 0)), Color3.fromRGB(44, 44, 50), Enum.Material.DiamondPlate)
		map.Plates[i] = { Center = center, Plate = plate, Seam = seam, Pressed = false }
	end

	-- Sticky floor: glossy violet goo with slow bubbles.
	for i, cell in ipairs(layout.Sticky) do
		local center = cellCenter(origin, cell[1], cell[2])
		deco(decor, Vector3.new(9.6, 0.18, 9.6), CFrame.new(center + Vector3.new(0, 0.14, 0)), Color3.fromRGB(45, 12, 60), Enum.Material.SmoothPlastic, { Reflectance = 0.25 })
		local goo = deco(fx, Vector3.new(9, 0.2, 9), CFrame.new(center + Vector3.new(0, 0.2, 0)), Color3.fromRGB(190, 60, 255), Enum.Material.Neon, { Transparency = 0.72 })
		mk("ParticleEmitter", goo, {
			Color = ColorSequence.new(Color3.fromRGB(210, 110, 255)),
			LightEmission = 0.6,
			Transparency = NumberSequence.new(0.3, 1),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.6) }),
			Lifetime = NumberRange.new(0.6, 1.2),
			Rate = 6,
			Speed = NumberRange.new(0.3, 1),
			EmissionDirection = Enum.NormalId.Top,
		})
		map.Sticky[i] = { Center = center }
	end

	-- Wall cameras: only the bracket is built here. The sweeping head (red cone, spotlight) is built and
	-- animated by the client from the Start payload; the server just tracks each camera's yaw.
	for i, cell in ipairs(layout.Cameras) do
		local dir = DIR_VEC[cell[3]]
		local wallFace = cellCenter(origin, cell[1], cell[2]) + dir * (CELL / 2) + Vector3.new(0, WALL_HEIGHT - 3.4, 0)
		local faceCF = CFrame.lookAt(wallFace, wallFace + dir)
		deco(decor, Vector3.new(1.8, 1.8, 0.3), faceCF * CFrame.new(0, 0, -0.15), Color3.fromRGB(30, 30, 36), Enum.Material.Metal)
		deco(decor, Vector3.new(0.35, 0.35, 1), faceCF * CFrame.new(0, 0, -0.7), Color3.fromRGB(50, 50, 58), Enum.Material.Metal)
		local pivotPos = wallFace + dir * 1.2
		local baseYaw = math.atan2(-dir.X, -dir.Z)
		map.Cameras[i] = { PivotPos = pivotPos, BaseYaw = baseYaw, Yaw = baseYaw, Pitch = math.rad(-Sec.CameraPitchDegrees), Phase = i * 1.7 }
	end

	-- Streams to the heist's thief as one persistent unit (AddPersistentPlayer in startHeist), so the
	-- floor and walls are all there before they are let go; other players never receive it.
	model.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	model:SetAttribute("SolidCount", #solidFolder:GetChildren())
	map.Model.Parent = parent
	return map
end

---------------------------------------------------------------- guards
-- Guards are pure simulation here (Pos, Yaw, Look); the client draws them from the State payload.

local LOOK = Tuning.GuardLook

local function cellOf(state, pos)
	local o = state.Map.Origin
	local layout = state.Map.Layout
	local c = math.clamp(math.floor((pos.X - o.X) / CELL) + 1, 1, layout.Width)
	local r = math.clamp(math.floor((pos.Z - o.Z) / CELL) + 1, 1, layout.Height)
	return { c, r }
end

local function setGoal(state, guard, point)
	local map = state.Map
	local goalCell = cellOf(state, point)
	local cells = HeistMaps.FindPath(map.Layout, cellOf(state, guard.Pos), goalCell)
	local path = {}
	if cells then
		for i = 1, #cells - 1 do
			table.insert(path, cellCenter(map.Origin, cells[i][1], cells[i][2]))
		end
		-- End exactly on the point when guards can stand there, otherwise at the cell centre.
		if HeistMaps.GuardWalkable(map.Layout, goalCell[1], goalCell[2]) then
			table.insert(path, Vector3.new(point.X, map.Origin.Y, point.Z))
		else
			table.insert(path, cellCenter(map.Origin, goalCell[1], goalCell[2]))
		end
	end
	guard.Path = path
	guard.PathIndex = 1
end

-- Moves along the current path. Returns true once the path is finished.
local function followPath(guard, dt, speed)
	local target = guard.Path[guard.PathIndex]
	if not target then
		guard.Moving = false
		return true
	end
	local offset = Vector3.new(target.X - guard.Pos.X, 0, target.Z - guard.Pos.Z)
	local dist = offset.Magnitude
	local step = speed * dt
	if dist > 0.05 then
		guard.TargetYaw = math.atan2(-offset.X, -offset.Z)
	end
	guard.Moving = true
	if dist <= step then
		guard.Pos = Vector3.new(target.X, guard.Pos.Y, target.Z)
		guard.PathIndex += 1
		return guard.PathIndex > #guard.Path
	end
	guard.Pos += offset.Unit * step
	return false
end

local function angleLerp(a, b, t)
	local diff = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + diff * t
end

local function yawTo(from, to)
	return math.atan2(-(to.X - from.X), -(to.Z - from.Z))
end

local function setGuardLook(guard, mode)
	guard.Look = LOOK[mode]
end

local function updateGuard(state, g, dt, t)
	local speed = state.GuardSpeed * (state.Stolen and Sec.StolenSpeedBonus or 1)
	if t < g.BlindUntil then
		setGuardLook(g, "Blind")
		g.TargetYaw = g.Yaw + dt * 2.5
		g.Moving = false
	elseif g.Mode == "Decoy" and t < g.ModeUntil then
		setGuardLook(g, state.Lockdown and "Alert" or "Suspicious")
		if followPath(g, dt, speed * 1.2) then
			g.TargetYaw = g.Yaw + dt * 1.8
		end
	elseif state.Lockdown then
		setGuardLook(g, "Alert")
		if g.Direct and state.PlayerPos then
			g.Path = { Vector3.new(state.PlayerPos.X, g.Pos.Y, state.PlayerPos.Z) }
			g.PathIndex = 1
		elseif t >= g.RepathAt and state.PlayerPos then
			setGoal(state, g, state.PlayerPos)
			g.RepathAt = t + 0.4
		end
		followPath(g, dt, Sec.LockdownSpeed)
	elseif g.Mode == "Suspicious" then
		setGuardLook(g, "Suspicious")
		g.Moving = false
		if g.LastSeen then
			g.TargetYaw = yawTo(g.Pos, g.LastSeen)
		end
		if t > g.ModeUntil then
			g.Mode = "Investigate"
			g.ModeUntil = t + Sec.InvestigateSeconds
			setGoal(state, g, g.LastSeen or g.Pos)
		end
	elseif g.Mode == "Investigate" and t < g.ModeUntil then
		setGuardLook(g, "Suspicious")
		if followPath(g, dt, speed * 1.15) then
			g.TargetYaw = g.Yaw + dt * 1.8
		end
	else
		if g.Mode ~= "Patrol" then
			g.Mode = "Patrol"
			setGoal(state, g, g.Waypoints[g.WaypointIndex])
		end
		setGuardLook(g, "Calm")
		if t < g.PauseUntil then
			g.Moving = false
			g.TargetYaw = g.ScanBase + math.sin((t - g.PauseStart) * 2.2) * 0.9
		elseif followPath(g, dt, speed) then
			g.WaypointIndex = g.WaypointIndex % #g.Waypoints + 1
			g.PauseStart = t
			g.PauseUntil = t + 1.2
			g.ScanBase = g.Yaw
			setGoal(state, g, g.Waypoints[g.WaypointIndex])
		end
	end
	g.Yaw = angleLerp(g.Yaw, g.TargetYaw, math.min(1, dt * 7))
end

local function spawnGuards(state)
	local map = state.Map
	for i, start in ipairs(map.Layout.Guards) do
		local pos = cellCenter(map.Origin, start[1], start[2])
		local waypoints = {}
		for _, wp in ipairs(map.Layout.Patrols[i]) do
			table.insert(waypoints, cellCenter(map.Origin, wp[1], wp[2]))
		end
		local guard = {
			Look = LOOK.Calm,
			Pos = pos,
			Yaw = 0,
			TargetYaw = 0,
			Waypoints = waypoints,
			WaypointIndex = 1,
			Mode = "Patrol",
			ModeUntil = 0,
			PauseUntil = 0,
			PauseStart = 0,
			ScanBase = 0,
			BlindUntil = 0,
			RepathAt = 0,
			Phase = i * 1.3,
			Path = {},
			PathIndex = 1,
		}
		setGoal(state, guard, waypoints[1])
		table.insert(state.Guards, guard)
	end
end

-- Edit-mode preview: the map plus guards and camera heads as the client would draw them (no simulation).
function Heist.BuildPreview(mapId, origin, parent)
	local map = Heist.BuildMap(mapId, origin, parent)
	for _, start in ipairs(map.Layout.Guards) do
		Tuning.BuildGuardModel(map.Model, cellCenter(origin, start[1], start[2]), map.Floor)
	end
	for _, cam in ipairs(map.Cameras) do
		Tuning.BuildCameraHead(map.Model, Tuning.CameraCFrame(cam.PivotPos, cam.BaseYaw, cam.Pitch), map.Floor)
	end
	return map
end

---------------------------------------------------------------- simulation

local function hasLineOfSight(state, from, to)
	return workspace:Raycast(from, to - from, state.RayParams) == nil
end

local function fire(state, event, payload)
	if state.Player.Parent then
		core.FireClient(state.Player, "Heist", event, payload)
	end
end

-- Everything the client needs to draw the heist this tick. G packs every guard as x, z, yaw, look;
-- CS lists the cameras that can see the player right now (their LEDs strobe).
local function statePayload(state, t)
	local guards = table.create(#state.Guards * 4)
	for _, g in ipairs(state.Guards) do
		table.insert(guards, g.Pos.X)
		table.insert(guards, g.Pos.Z)
		table.insert(guards, g.Yaw)
		table.insert(guards, g.Look)
	end
	return {
		Alarm = math.floor(state.Alarm + 0.5),
		Lockdown = state.Lockdown,
		Stolen = state.Stolen,
		EndsAt = state.EndsAt,
		EmpUntil = state.EmpUntil,
		ShoesUntil = state.ShoesUntil,
		Lockpick = state.LockpickReady,
		Seen = t - state.LastSeenAt < 0.35,
		G = guards,
		CS = state.CamsSeeing,
	}
end

-- Laser post tips turn blue during an EMP (rare, so these few property changes may replicate).
local function setEmpVisuals(state, off)
	for _, laser in ipairs(state.Map.Lasers) do
		for _, tip in ipairs(laser.Tips) do
			tip.Color = off and EMP_BLUE or RED
		end
	end
end

local function setLaser(laser, on)
	if laser.On == on then
		return
	end
	laser.On = on
	for _, beam in ipairs(laser.Beams) do
		beam.Transparency = on and 0 or 1
	end
	laser.Light.Enabled = on
end

local function addAlarm(state, amount, kind, t)
	if state.Lockdown then
		return
	end
	state.Alarm = math.min(100, state.Alarm + amount)
	state.MaxAlarm = math.max(state.MaxAlarm, state.Alarm)
	state.LastSeenAt = t
	if kind and t - (state.LastDetectEvent or 0) > 0.4 then
		state.LastDetectEvent = t
		fire(state, "Detected", { Kind = kind })
	end
end

local finish -- forward declaration

local function triggerLockdown(state, t)
	state.Lockdown = true
	state.Alarm = 100
	state.MaxAlarm = 100
	state.EndsAt = math.min(state.EndsAt, t + Tuning.LockdownTimeCap)
	for _, g in ipairs(state.Guards) do
		g.Mode = "Chase"
		g.RepathAt = 0
	end
	-- One-off recolour; the client pulses the ceiling lights' brightness locally.
	for _, trim in ipairs(state.Map.Trims) do
		trim.Color = ALARM_RED
	end
	for _, entry in ipairs(state.Map.Lights) do
		entry.Light.Color = ALARM_RED
		entry.Panel.Color = ALARM_RED
	end
	fire(state, "Lockdown", { EndsAt = state.EndsAt })
end

---------------------------------------------------------------- anti-cheat

-- Call after every server-initiated move of the character (entry teleport, rubber-band).
local function markTeleported(state, pos, t)
	state.LastPos = pos
	state.PlayerPos = pos
	state.LastPosAt = t
	state.TeleportAt = t
	state.GraceUntil = t + AC.TeleportGrace
	state.MoveBudget = HeistMaps.MoveBudgetCap(state.BaseWalkSpeed, AC)
end

-- Records an implausible action. Returns true when the player has run out of strikes.
local function addStrike(state, t, kind)
	local strikes = state.Strikes
	while strikes[1] and t - strikes[1] > AC.StrikeWindow do
		table.remove(strikes, 1)
	end
	table.insert(strikes, t)
	warn(("[RelicRNG] Heist anti-cheat: %s (%d) %s, strike %d/%d"):format(state.Player.Name, state.Player.UserId, kind, #strikes, AC.Strikes))
	return #strikes >= AC.Strikes
end

-- Is `pos` inside a wall cell, outside the grid, or above the ceiling? Never true for a legit character.
local function outOfBounds(map, pos)
	local o = map.Origin
	local c = math.floor((pos.X - o.X) / CELL) + 1
	local r = math.floor((pos.Z - o.Z) / CELL) + 1
	return HeistMaps.IsWall(HeistMaps.Get(map.Layout, c, r)) or pos.Y > o.Y + WALL_HEIGHT + 1
end

-- Checks the move from the last accepted position to `pos`. Returns a violation name or nil, plus the
-- new movement budget when the move is fine.
local function checkMove(state, humanoid, pos, t)
	local prev = state.LastPos
	local delta = pos - prev
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local speed = math.max(state.BaseWalkSpeed, humanoid.WalkSpeed)
	local budget, tooFast = HeistMaps.StepMoveBudget(state.MoveBudget, t - state.LastPosAt, speed, flat, AC)
	if tooFast then
		return "Speed"
	end
	if outOfBounds(state.Map, pos) then
		return "OutOfBounds"
	end
	local length = delta.Magnitude
	if length > AC.NoclipMinDepth then
		local hit = workspace:Raycast(prev, delta, state.RayParams)
		if hit then
			local back = workspace:Raycast(pos, -delta, state.RayParams)
			if back and length - hit.Distance - back.Distance >= AC.NoclipMinDepth then
				return "Noclip"
			end
		end
	end
	return nil, budget
end

-- Snaps the character back to the last accepted position (or fails the heist after too many strikes).
local function onViolation(state, root, t, kind)
	if addStrike(state, t, kind) then
		return finish(state, false, "Caught")
	end
	local character = state.Player.Character
	local back = state.LastPos
	if character and back then
		character:PivotTo(CFrame.new(back) * root.CFrame.Rotation)
	end
	markTeleported(state, back or root.Position, t)
end

---------------------------------------------------------------- detection

local function detect(state, dt, t)
	local character = state.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return finish(state, false, "KnockedOut")
	end
	local map = state.Map
	local pos = root.Position

	-- Right after a server teleport the character can still report its old position for a moment:
	-- skip those stale samples instead of treating them as movement.
	if t < state.GraceUntil then
		local anchor = state.LastPos
		local reach = AC.Slack + 2 + state.BaseWalkSpeed * AC.SpeedFactor * (t - state.TeleportAt)
		local o = pos - anchor
		if Vector3.new(o.X, 0, o.Z).Magnitude > reach then
			return
		end
	end

	local violation, budget = checkMove(state, humanoid, pos, t)
	if violation then
		return onViolation(state, root, t, violation)
	end
	local prev = state.LastPos
	state.MoveBudget = budget
	state.LastPos = pos
	state.LastPosAt = t
	state.PlayerPos = pos
	local floorY = map.Origin.Y
	if pos.Y < floorY - 30 or (pos - map.Center).Magnitude > map.Radius then
		return finish(state, false, "Left")
	end

	local seen = false
	local gain = 0
	local shoes = t < state.ShoesUntil
	local range = shoes and Sec.SilentRange or Sec.GuardRange

	-- Guards: catch, vision cone + line of sight.
	for _, g in ipairs(state.Guards) do
		local eye = g.Pos + Vector3.new(0, 5.6, 0)
		local look = CFrame.Angles(0, g.Yaw, 0).LookVector
		if t >= g.BlindUntil then
			local flat = Vector3.new(pos.X - g.Pos.X, 0, pos.Z - g.Pos.Z).Magnitude
			local los = nil
			if flat <= Sec.CatchRange then
				los = hasLineOfSight(state, eye, pos)
				if los then
					return finish(state, false, "Caught")
				end
			end
			local inCone, distance = Tuning.InVision(eye, look, pos, range, Sec.GuardMinDot)
			if inCone then
				if los == nil then
					los = hasLineOfSight(state, eye, pos)
				end
				if los then
					seen = true
					gain += Tuning.GuardAlarmRate(distance, range) * dt
					g.LastSeen = pos
					if not state.Lockdown and g.Mode ~= "Suspicious" then
						g.Mode = "Suspicious"
					end
					if g.Mode == "Suspicious" then
						g.ModeUntil = t + Sec.SuspiciousSeconds
					end
				end
			end
			-- Lockdown: run straight at a thief in clear view (seen, or heard close by); anything behind a
			-- wall or display case is chased along the grid path instead of through it.
			g.Direct = false
			if state.Lockdown and flat < DIRECT_CHASE_RANGE and (inCone or flat < 8) then
				if los == nil then
					los = hasLineOfSight(state, eye, pos)
				end
				g.Direct = los
			end
		elseif g.Direct then
			g.Direct = false
		end
	end

	-- Cameras (off during EMP). Yaw follows the same formula the client animates with.
	local emp = t < state.EmpUntil
	if state.EmpActive ~= emp then
		state.EmpActive = emp
		setEmpVisuals(state, emp)
	end
	local seeing = nil
	local elapsed = t - state.StartedAt
	for i, cam in ipairs(map.Cameras) do
		cam.Yaw = Tuning.CameraYaw(cam.BaseYaw, cam.Phase, elapsed)
		if not emp then
			local look = CFrame.Angles(0, cam.Yaw, 0).LookVector
			local eye = cam.PivotPos
			local inCone = Tuning.InVision(eye, look, pos, Sec.CameraRange, Sec.CameraMinDot)
			if inCone and hasLineOfSight(state, eye, pos) then
				seen = true
				gain += Sec.CameraAlarm * dt
				seeing = seeing or {}
				table.insert(seeing, i)
			end
		end
	end
	state.CamsSeeing = seeing

	-- Lasers (swept so sprinting can't skip them) and pressure plates.
	if not emp then
		for _, laser in ipairs(map.Lasers) do
			if laser.On and t >= laser.CooldownUntil and HeistMaps.CrossesLaser(laser.Center, laser.Axis, prev, pos) then
				laser.CooldownUntil = t + Sec.LaserCooldown
				addAlarm(state, Sec.LaserAlarm, "Laser", t)
				for _, beam in ipairs(laser.Beams) do
					beam.Color = Color3.new(1, 1, 1)
				end
				task.delay(0.25, function()
					for _, beam in ipairs(laser.Beams) do
						beam.Color = RED
					end
				end)
			end
		end
	end
	local grounded = pos.Y - floorY < 4.2
	for _, plate in ipairs(map.Plates) do
		local o = pos - plate.Center
		local on = grounded and math.abs(o.X) < 3.7 and math.abs(o.Z) < 3.7
		if on and not plate.Pressed then
			addAlarm(state, Sec.PlateAlarm, "Plate", t)
			plate.Seam.Color = ALARM_RED
			plate.Seam.Transparency = 0
			plate.Plate.CFrame = CFrame.new(plate.Center + Vector3.new(0, 0.1, 0))
		elseif not on and plate.Pressed then
			plate.Seam.Color = PLATE_AMBER
			plate.Seam.Transparency = 0.62
			plate.Plate.CFrame = CFrame.new(plate.Center + Vector3.new(0, 0.2, 0))
		end
		plate.Pressed = on
	end

	-- Sticky floor.
	for _, goo in ipairs(map.Sticky) do
		local o = pos - goo.Center
		if grounded and math.abs(o.X) < 4.8 and math.abs(o.Z) < 4.8 then
			if t >= state.StickyUntil then
				fire(state, "Sticky", { Seconds = Sec.StickySeconds })
			end
			state.StickyUntil = t + Sec.StickySeconds
			humanoid.WalkSpeed = Sec.StickySpeed
		end
	end
	if state.StickyUntil > 0 and t >= state.StickyUntil then
		state.StickyUntil = 0
		humanoid.WalkSpeed = state.BaseWalkSpeed
	end

	-- Alarm meter.
	if gain > 0 then
		addAlarm(state, gain, "Seen", t)
	elseif not state.Lockdown and t - state.LastSeenAt > Sec.DecayDelay then
		state.Alarm = math.max(0, state.Alarm - Sec.AlarmDecay * dt)
	end
	if state.Alarm >= 100 and not state.Lockdown then
		triggerLockdown(state, t)
	end

	-- Escape. Reaching the exit faster than anyone could walk there doesn't count (and is a strike).
	if state.Stolen then
		local o = pos - map.ExitPos
		if Vector3.new(o.X, 0, o.Z).Magnitude <= Tuning.EscapeRadius then
			if t - state.StolenAt >= state.MinEscape then
				return finish(state, true, "Escaped")
			elseif not state.EarlyExitFlagged then
				state.EarlyExitFlagged = true
				if addStrike(state, t, "EarlyEscape") then
					return finish(state, false, "Caught")
				end
			end
		end
	end

	-- Guards move every tick, so the client gets the state at the detection rate (10 Hz).
	fire(state, "State", statePayload(state, t))
end

local beginHeist -- forward declaration

local function step(state, dt, t)
	if not state.Arrived then
		-- Teleporting in, or held in place until the client reports the museum loaded (or it times out).
		if state.Teleported and t >= state.ReadyDeadline then
			beginHeist(state)
		end
		return
	end
	if t >= state.EndsAt then
		return finish(state, false, "Timeout")
	end
	local map = state.Map

	-- Lasers blink in groups.
	local period = Sec.LaserOnSeconds + Sec.LaserOffSeconds
	for _, laser in ipairs(map.Lasers) do
		local phase = (t - state.StartedAt + laser.Group * 0.9) % period
		setLaser(laser, phase < Sec.LaserOnSeconds)
	end

	for _, g in ipairs(state.Guards) do
		updateGuard(state, g, dt, t)
	end

	state.DetectAccum += dt
	if state.DetectAccum >= 1 / Sec.TickRate then
		local tickDt = math.min(state.DetectAccum, 0.3)
		state.DetectAccum = 0
		detect(state, tickDt, t)
	end
end

---------------------------------------------------------------- saved data helpers

local function heistData(data)
	local h = data.Heist
	h.Tools = h.Tools or {}
	h.BestTimes = h.BestTimes or {}
	h.Energy = tonumber(h.Energy) or Tuning.BaseEnergy
	h.Notoriety = tonumber(h.Notoriety) or 0
	h.Wins = tonumber(h.Wins) or 0
	h.Fails = tonumber(h.Fails) or 0
	return h
end

local function energyCap(player)
	return Tuning.EnergyCap(core.HasPass and core.HasPass(player, "ExtraHeistEnergy"))
end

local function regen(player, data)
	local h = heistData(data)
	h.Energy, h.EnergyAt = Tuning.RegenEnergy(h.Energy, h.EnergyAt, energyCap(player), os.time())
end

local function museumCFrame(player)
	local plot = core.MuseumService.GetPlot(player)
	local point = plot and plot:FindFirstChild("TeleportPoint")
	return point and point.CFrame
end

-- Teleports a living character back to its museum. Yields (streams the destination): always task.spawn it.
local function sendHome(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local home = museumCFrame(player)
	if home then
		core.Teleport(player, home)
	elseif character.Parent then
		character:PivotTo(CFrame.new(0, 5, 0))
	end
end

-- Undoes what startHeist changed on the player: the loading hold, camera occlusion/zoom, museum streaming.
local function restorePlayer(state)
	local player = state.Player
	local root = state.HeldRoot
	if root then
		state.HeldRoot = nil
		root.Anchored = false
	end
	if state.CameraSaved then
		state.CameraSaved = false
		player.DevCameraOcclusionMode = state.SavedOcclusion
		player.CameraMaxZoomDistance = state.SavedMaxZoom
	end
	pcall(function()
		state.Map.Model:RemovePersistentPlayer(player)
	end)
end

---------------------------------------------------------------- map pool

-- Puts a used museum back the way BuildMap made it (the relic back in its case, lights, lasers,
-- plates and exit reset, tool effects removed) so the next heist on this map can reuse it.
local function resetMap(map)
	local pal = map.Palette
	for _, trim in ipairs(map.Trims) do
		trim.Color = pal.Trim
	end
	for _, entry in ipairs(map.Lights) do
		entry.Light.Color = pal.Light
		entry.Light.Brightness = CEILING_BRIGHTNESS
		entry.Panel.Color = pal.Light
	end
	for _, laser in ipairs(map.Lasers) do
		laser.On = false
		setLaser(laser, true)
		laser.CooldownUntil = 0
		for _, beam in ipairs(laser.Beams) do
			beam.Color = RED
		end
		for _, tip in ipairs(laser.Tips) do
			tip.Color = RED
		end
	end
	for _, plate in ipairs(map.Plates) do
		plate.Pressed = false
		plate.Seam.Color = PLATE_AMBER
		plate.Seam.Transparency = 0.62
		plate.Plate.CFrame = CFrame.new(plate.Center + Vector3.new(0, 0.2, 0))
	end
	local target = map.Target
	target.Relic.Parent = map.Model
	target.Prompt.Enabled = false
	target.Prompt.HoldDuration = Tuning.StealSeconds
	map.ExitMarker.Enabled = false
	map.ExitPad.Transparency = EXIT_PAD_IDLE
	local temp = map.Model:FindFirstChild("Temp")
	if temp then
		temp:Destroy()
	end
	map.Model.Name = ("%s_idle%d"):format(map.Id, map.Slot)
end

-- An idle pooled museum for `mapId`, or a freshly built one in the first free slot. Errors if the build fails.
local function acquireMap(mapId)
	local idle = pool[mapId]
	if idle and #idle > 0 then
		return table.remove(idle)
	end
	local slot = 0
	while slots[slot] do
		slot += 1
	end
	local origin = Vector3.new(ORIGIN_X + slot * SLOT_SPACING, 0, 0)
	local map = Heist.BuildMap(mapId, origin, activeFolder)
	map.Slot = slot
	slots[slot] = map
	local layout = map.Layout
	local extent = Vector3.new(layout.Width * CELL, 0, layout.Height * CELL)
	map.Center = origin + extent / 2 + Vector3.new(0, 5, 0)
	map.Radius = extent.Magnitude / 2 + 40
	-- Shortest walks (minus the last cell: the prompt and the exit pad reach into it).
	map.StealStuds = math.max(0, (HeistMaps.PlayerPathStuds(layout, layout.Entry, layout.Target) or 0) - CELL)
	map.EscapeStuds = math.max(0, (HeistMaps.PlayerPathStuds(layout, layout.Target, layout.Entry) or 0) - CELL)
	return map
end

local function destroyMap(map)
	if slots[map.Slot] == map then
		slots[map.Slot] = nil
	end
	map.Model:Destroy()
end

-- Returns a finished museum to the pool (or destroys it when pooling is off / the pool is full).
local function releaseMap(map)
	local idle = pool[map.Id] or {}
	pool[map.Id] = idle
	if not HeistMaps.PoolMaps or #idle >= HeistMaps.PoolPerMap then
		destroyMap(map)
		return
	end
	local ok, err = pcall(resetMap, map)
	if not ok then
		warn("[RelicRNG] Heist map reset failed, rebuilding next time: " .. tostring(err))
		destroyMap(map)
		return
	end
	table.insert(idle, map)
end

---------------------------------------------------------------- start / finish

-- Never yields (it runs inside the Heartbeat loop): the teleport home is spawned.
function finish(state, success, reason)
	if state.Done then
		return
	end
	state.Done = true
	local player = state.Player
	local t = serverNow()
	if active[player] == state then
		active[player] = nil
	end
	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end
	table.clear(state.Connections)

	local info = Tuning.Maps[state.MapId]
	local elapsed = state.Arrived and t - state.StartedAt or 0
	local summary = { Success = success, Reason = reason, MapId = state.MapId, MapName = info.Name, Time = elapsed }
	local profile = core.GetProfile(player)
	if profile then
		profile.Session.Busy = false
		local data = profile.Data
		local h = heistData(data)
		if success then
			local ghost = state.MaxAlarm < Tuning.GhostAlarm
			local reward = Tuning.Rewards(state.MapId, core.GetIncomePerMinute(player, data), math.max(0, state.EndsAt - t), state.Duration, ghost, data.Level)
			core.AddCoins(player, reward.Coins, true)
			core.AddCredits(player, reward.Credits)
			h.Notoriety += reward.Notoriety
			core.AddXP(player, reward.XP)
			local site = info.LootSites[rng:NextInteger(1, #info.LootSites)]
			local relicId, tier = core.RollService.RollLoot(site, core.GetLuck(player, data) * info.LootLuck, info.MinTier)
			local isNew = not data.Discovered[relicId]
			core.GrantRelic(player, relicId, 1)
			h.Wins += 1
			local best = h.BestTimes[state.MapId]
			summary.NewBest = best == nil or elapsed < best
			if summary.NewBest then
				h.BestTimes[state.MapId] = math.floor(elapsed * 10) / 10
			end
			summary.Coins, summary.Credits, summary.NotorietyGained, summary.XP = reward.Coins, reward.Credits, reward.Notoriety, reward.XP
			summary.Ghost = ghost
			summary.RelicId, summary.Tier, summary.IsNew = relicId, tier, isNew
			if tier >= 6 then
				core.FireAllClients("Heist", "Announce", { Name = player.DisplayName, MapName = info.Name, RelicId = relicId, Tier = tier })
			end
		elseif reason == "Cancelled" then
			-- Couldn't get the thief inside (no character): refund, no penalty.
			h.Energy = math.min(h.Energy + 1, energyCap(player))
			summary.NotorietyLost = 0
		else
			local loss = math.min(h.Notoriety, info.FailNotoriety)
			h.Notoriety -= loss
			h.Fails += 1
			profile.Session.HeistCooldownUntil = os.time() + Tuning.FailCooldown
			summary.NotorietyLost = loss
			summary.CooldownUntil = profile.Session.HeistCooldownUntil
		end
		summary.Notoriety = h.Notoriety
		summary.BestTime = h.BestTimes[state.MapId]
	end

	player:SetAttribute("InHeist", false)
	restorePlayer(state)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.WalkSpeed = state.BaseWalkSpeed
		-- Only once the thief is actually inside; startHeist sends them home itself if the teleport in
		-- finishes after the heist already ended.
		if state.Teleported and reason ~= "Left" and reason ~= "KnockedOut" then
			task.spawn(sendHome, player)
		end
	end
	-- Leave the museum alone for a moment while the thief is teleported out, then pool it.
	local map = state.Map
	task.delay(RELEASE_DELAY, releaseMap, map)
	if player.Parent then
		fire(state, "End", summary)
		core.Sync(player)
	end
end

-- The thief is inside and the museum has loaded (or LOAD_TIMEOUT passed): release them and start the clock.
beginHeist = function(state)
	if state.Done or state.Arrived or not state.Teleported then
		return
	end
	local t = serverNow()
	state.StartedAt = t
	state.EndsAt = t + state.Duration
	state.ArrivedAt = t
	local root = state.HeldRoot
	state.HeldRoot = nil
	if root then
		root.Anchored = false
	end
	markTeleported(state, root and root.Position or state.Map.EntryCF.Position + Vector3.new(0, 3, 0), t)
	state.Arrived = true
	fire(state, "Go", { StartedAt = t, EndsAt = state.EndsAt })
	fire(state, "State", statePayload(state, t))
end

local function startHeist(player, mapId)
	local profile = core.GetProfile(player)
	local info = type(mapId) == "string" and Tuning.Maps[mapId]
	if not info or not HeistMaps.Maps[mapId] then
		return false, "Unknown museum."
	end
	if not profile then
		return false
	end
	if active[player] then
		return false, "You're already on a heist."
	end
	if profile.Session.Busy then
		return false, "Finish what you're doing first."
	end
	local data = profile.Data
	if data.Level < info.Level then
		return false, ("%s needs Curator Level %d."):format(info.Name, info.Level)
	end
	local cooldown = (profile.Session.HeistCooldownUntil or 0) - os.time()
	if cooldown > 0 then
		return false, ("Lie low for %ds before the next heist."):format(cooldown)
	end
	regen(player, data)
	local h = heistData(data)
	if h.Energy < 1 then
		return false, "No heist energy left. It recharges 1 every 15 minutes."
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return false, "Wait until you've respawned."
	end

	profile.Session.Busy = true
	local ok, map = pcall(acquireMap, mapId)
	if not ok then
		profile.Session.Busy = false
		warn("[RelicRNG] Heist map failed to build: " .. tostring(map))
		return false, "That museum is closed right now."
	end
	map.Model.Name = ("%s_%d"):format(mapId, player.UserId)
	map.Target.Prompt.HoldDuration = Tuning.StealSeconds
	map.Target.Prompt.Enabled = true

	local t = serverNow()
	local duration = Tuning.Duration + core.SetBonus(data, "HeistSeconds")
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { map.Solid }
	local walkSpeed = math.max(1, humanoid.WalkSpeed)
	local state = {
		Player = player, MapId = mapId, Map = map, Slot = map.Slot,
		StartedAt = t, Duration = duration, EndsAt = t + duration,
		GuardSpeed = info.GuardSpeed, Guards = {}, RayParams = rayParams,
		Alarm = 0, MaxAlarm = 0, Lockdown = false, Stolen = false, LockpickReady = false,
		EmpUntil = 0, ShoesUntil = 0, StickyUntil = 0, LastSeenAt = -100,
		DetectAccum = 0, ToolLockUntil = 0,
		BaseWalkSpeed = walkSpeed, Connections = {},
		Temp = mk("Folder", map.Model, { Name = "Temp" }), -- tool effects, cleared when the map is pooled
		-- Anti-cheat.
		Arrived = false, Strikes = {}, MoveBudget = 0, LastPosAt = 0, TeleportAt = 0, GraceUntil = 0,
		MinSteal = map.StealStuds / walkSpeed * AC.MinPathFraction,
		MinEscape = map.EscapeStuds / walkSpeed * AC.MinPathFraction,
	}
	active[player] = state
	spawnGuards(state)

	-- Steal: only the heist owner, only after the full hold (timed here, not trusted from the client),
	-- and never sooner than walking from the entry could get them there.
	local prompt = map.Target.Prompt
	local function nearTarget(who)
		local r = who.Character and who.Character:FindFirstChild("HumanoidRootPart")
		return r ~= nil and (r.Position - map.Target.Position).Magnitude <= STEAL_REACH
	end
	table.insert(state.Connections, prompt.PromptButtonHoldBegan:Connect(function(who)
		-- A hold only counts from when the thief is actually at the case (no pre-starting it on the way).
		if who == player and state.Arrived and nearTarget(who) then
			state.HoldBeganAt = os.clock()
		end
	end))
	table.insert(state.Connections, prompt.PromptButtonHoldEnded:Connect(function(who)
		if who == player then
			state.HoldEndedAt = os.clock()
		end
	end))
	table.insert(state.Connections, prompt.Triggered:Connect(function(who)
		if who ~= player or state.Done or state.Stolen or not state.Arrived or not nearTarget(who) then
			return
		end
		local began = state.HoldBeganAt
		state.HoldBeganAt = nil
		if not began then
			return
		end
		local endedAt = state.HoldEndedAt
		local heldUntil = (endedAt and endedAt > began) and endedAt or os.clock()
		local required = state.LockpickReady and Tuning.LockpickStealSeconds or Tuning.StealSeconds
		if heldUntil - began < required - AC.HoldSlack then
			return
		end
		local now = serverNow()
		if now - state.ArrivedAt < state.MinSteal then
			if addStrike(state, now, "EarlySteal") then
				finish(state, false, "Caught")
			end
			return
		end
		state.Stolen = true
		state.StolenAt = now
		state.LockpickReady = false
		map.Target.Relic.Parent = nil -- kept for the pool; resetMap puts it back
		prompt.Enabled = false
		map.ExitMarker.Enabled = true
		map.ExitPad.Transparency = 0.25
		addAlarm(state, Tuning.StealAlarm, nil, now)
		fire(state, "Stolen", { RelicName = map.Target.Name })
		fire(state, "State", statePayload(state, now))
	end))
	table.insert(state.Connections, humanoid.Died:Connect(function()
		finish(state, false, "KnockedOut")
	end))
	table.insert(state.Connections, player.CharacterRemoving:Connect(function()
		finish(state, false, "KnockedOut")
	end))

	h.Energy -= 1
	-- Stream the whole museum to this player, freeze the character so it can't fall before the floor
	-- exists on their client, and pull the camera in (Invisicam: walls fade instead of the camera
	-- snapping into the head in narrow corridors).
	pcall(function()
		map.Model:AddPersistentPlayer(player)
	end)
	root.Anchored = true
	state.HeldRoot = root
	state.SavedOcclusion = player.DevCameraOcclusionMode
	state.SavedMaxZoom = player.CameraMaxZoomDistance
	state.CameraSaved = true
	player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
	player.CameraMaxZoomDistance = math.min(state.SavedMaxZoom, 26)

	-- core.Teleport yields while the museum streams in. Nothing is simulated until Arrived is set (after
	-- the client confirms the museum loaded), so the player isn't judged on where they stood before.
	local arrived = core.Teleport(player, map.EntryCF)
	if state.Done then
		-- Abandoned / died / left while streaming: undo the teleport if it went through anyway.
		if arrived then
			task.spawn(sendHome, player)
		end
		return false
	end
	if not arrived then
		finish(state, false, "Cancelled")
		return false, "Wait until you've respawned."
	end
	player:SetAttribute("InHeist", true)
	state.Teleported = true
	state.ReadyDeadline = serverNow() + LOAD_TIMEOUT

	local cameras = table.create(#map.Cameras)
	for i, cam in ipairs(map.Cameras) do
		cameras[i] = { Pos = cam.PivotPos, BaseYaw = cam.BaseYaw, Pitch = cam.Pitch, Phase = cam.Phase }
	end
	fire(state, "Start", {
		MapId = mapId,
		MapName = info.Name,
		TargetName = map.Target.Name,
		StartedAt = t,
		EndsAt = state.EndsAt,
		Duration = duration,
		ModelName = map.Model.Name,
		FloorY = map.Origin.Y,
		Cameras = cameras,
	})
	fire(state, "State", statePayload(state, t))
	core.Sync(player)
	return true, ("Heist started: steal %s and escape!"):format(map.Target.Name)
end

---------------------------------------------------------------- tools

local function useTool(player, toolId)
	local state = active[player]
	if not state then
		return false, "Tools can only be used during a heist."
	end
	if not state.Arrived then
		return false
	end
	local tool = type(toolId) == "string" and Tuning.Tools[toolId]
	if not tool then
		return false, "Unknown tool."
	end
	local data = core.GetData(player)
	local h = heistData(data)
	if (h.Tools[toolId] or 0) < 1 then
		return false, ("You have no %s. Buy some in the Heists menu."):format(tool.Name)
	end
	local t = serverNow()
	if t < state.ToolLockUntil then
		return false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local pos = root.Position
	local message
	if toolId == "Lockpick" then
		if state.Stolen then
			return false, "The relic is already yours. Escape!"
		end
		if state.LockpickReady then
			return false, "Your lockpick is already in the lock."
		end
		state.LockpickReady = true
		state.Map.Target.Prompt.HoldDuration = Tuning.LockpickStealSeconds
		message = "Lockpick ready: your next steal is almost instant."
	elseif toolId == "EMP" then
		state.EmpUntil = t + tool.Duration
		-- The expanding burst is drawn by the client from the ToolUsed event.
		message = ("EMP! Lasers and cameras are down for %ds."):format(tool.Duration)
	elseif toolId == "Smoke" then
		local count = 0
		for _, g in ipairs(state.Guards) do
			if Vector3.new(g.Pos.X - pos.X, 0, g.Pos.Z - pos.Z).Magnitude <= tool.Radius then
				g.BlindUntil = t + tool.Duration
				count += 1
			end
		end
		local cloud = deco(state.Temp, Vector3.new(1, 1, 1), CFrame.new(pos - Vector3.new(0, 2, 0)), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, { Transparency = 1 })
		mk("ParticleEmitter", cloud, {
			Color = ColorSequence.new(Color3.fromRGB(150, 150, 165)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 12) }),
			Lifetime = NumberRange.new(2.5, 4),
			Rate = 40,
			Speed = NumberRange.new(4, 10),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 2,
		})
		task.delay(tool.Duration - 2, function()
			local emitter = cloud.Parent and cloud:FindFirstChildOfClass("ParticleEmitter")
			if emitter then
				emitter.Enabled = false
			end
		end)
		task.delay(tool.Duration + 3, function()
			cloud:Destroy()
		end)
		message = count > 0 and ("Smoke! %d guard%s blinded for %ds."):format(count, count == 1 and "" or "s", tool.Duration) or "Smoke bomb popped, but no guards were close enough."
	elseif toolId == "Decoy" then
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		flatLook = flatLook.Magnitude > 0.01 and flatLook.Unit or Vector3.zAxis
		local eye = pos + Vector3.new(0, 1, 0)
		local hit = workspace:Raycast(eye, flatLook * tool.Throw, state.RayParams)
		local distance = hit and math.max(1, (hit.Position - eye).Magnitude - 2) or tool.Throw
		local point = Vector3.new(pos.X, state.Map.Origin.Y, pos.Z) + flatLook * distance
		local count = 0
		for _, g in ipairs(state.Guards) do
			if t >= g.BlindUntil and Vector3.new(g.Pos.X - pos.X, 0, g.Pos.Z - pos.Z).Magnitude <= tool.Radius then
				g.Mode = "Decoy"
				g.ModeUntil = t + tool.Duration
				setGoal(state, g, point)
				count += 1
			end
		end
		local coin = deco(state.Temp, Vector3.new(0.3, 1.6, 1.6), CFrame.new(point + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 205, 70), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder })
		mk("PointLight", coin, { Color = Color3.fromRGB(255, 205, 70), Range = 10, Brightness = 2 })
		mk("ParticleEmitter", coin, {
			Color = ColorSequence.new(Color3.fromRGB(255, 225, 120)),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.5, 1),
			Rate = 18,
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top,
		})
		task.delay(tool.Duration, function()
			coin:Destroy()
		end)
		message = count > 0 and ("Clink! %d guard%s went to check the noise."):format(count, count == 1 and "" or "s") or "Clink! No guards were close enough to hear it."
	elseif toolId == "SilentShoes" then
		state.ShoesUntil = math.max(state.ShoesUntil, t) + tool.Duration
		message = ("Silent Shoes on: guards only notice you up close for %ds."):format(tool.Duration)
	end
	h.Tools[toolId] -= 1
	state.ToolLockUntil = t + 0.4
	fire(state, "ToolUsed", { Tool = toolId, Pos = pos })
	fire(state, "State", statePayload(state, t))
	core.SendSnapshot(player)
	return true, message
end

local function buyTool(player, toolId)
	local tool = type(toolId) == "string" and Tuning.Tools[toolId]
	if not tool then
		return false, "Unknown tool."
	end
	if active[player] then
		return false, "Buy tools before you start the heist."
	end
	local data = core.GetData(player)
	local h = heistData(data)
	local owned = h.Tools[toolId] or 0
	if owned >= Tuning.MaxToolStack then
		return false, ("You can carry at most %d."):format(Tuning.MaxToolStack)
	end
	if data.Coins < tool.Price then
		return false, ("You need %s coins."):format(core.Config.FormatNumber(tool.Price))
	end
	data.Coins -= tool.Price
	h.Tools[toolId] = owned + 1
	core.Sync(player)
	return true, ("Bought a %s (%d owned)."):format(tool.Name, owned + 1)
end

---------------------------------------------------------------- init

function Heist.Init(c)
	core = c
	core.DataService.AddDefaults({
		Heist = { Energy = Tuning.BaseEnergy, EnergyAt = 0, Notoriety = 0, Wins = 0, Fails = 0, BestTimes = {}, Tools = {} },
	})

	local root = workspace:WaitForChild("RelicRNG")
	activeFolder = root:FindFirstChild("ActiveHeists")
	if not activeFolder then
		activeFolder = Instance.new("Folder")
		activeFolder.Name = "ActiveHeists"
		activeFolder.Parent = root
	end
	for _, leftover in ipairs(activeFolder:GetChildren()) do
		leftover:Destroy()
	end

	core.Actions.StartHeist = startHeist
	core.Actions.UseHeistTool = useTool
	core.Actions.BuyHeistTool = buyTool
	core.Actions.AbandonHeist = function(player)
		local state = active[player]
		if not state then
			return false, "You're not on a heist."
		end
		finish(state, false, "Abandoned")
		return true
	end
	-- Sent by the client once the museum's floor and walls have streamed in; takes no arguments.
	core.Actions.HeistReady = function(player)
		local state = active[player]
		if state and state.Teleported and not state.Arrived then
			beginHeist(state)
		end
		return true
	end

	core.Hook("Tick", function(player, profile)
		regen(player, profile.Data)
	end)
	core.Hook("Stats", function(player, data)
		local h = heistData(data)
		local cap = energyCap(player)
		local _, rank = Tuning.GetRank(h.Notoriety)
		player:SetAttribute("Notoriety", h.Notoriety)
		player:SetAttribute("NotorietyRank", rank.Name)
		player:SetAttribute("HeistEnergy", h.Energy)
		player:SetAttribute("HeistMaxEnergy", cap)
		player:SetAttribute("HeistEnergyNextAt", h.Energy < cap and (h.EnergyAt or os.time()) + Tuning.EnergyRegenSeconds or 0)
		player:SetAttribute("InHeist", active[player] ~= nil)
		player:SetAttribute("HeistWins", h.Wins)
		local profile = core.GetProfile(player)
		player:SetAttribute("HeistCooldownUntil", profile and profile.Session.HeistCooldownUntil or 0)
	end)
	core.Hook("Snapshot", function(_, data, snapshot)
		local h = heistData(data)
		snapshot.Heist = { Tools = h.Tools, Wins = h.Wins, Fails = h.Fails, BestTimes = h.BestTimes }
	end)
	core.Hook("PlayerAdded", function(player, profile)
		regen(player, profile.Data)
	end)
	core.Hook("PlayerRemoving", function(player)
		local state = active[player]
		if state then
			finish(state, false, "Left")
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		if next(active) == nil then
			return
		end
		local t = serverNow()
		for _, state in pairs(active) do
			local ok, err = pcall(step, state, dt, t)
			if not ok then
				warn("[RelicRNG] Heist step failed: " .. tostring(err))
				pcall(finish, state, false, "Abandoned")
			end
		end
	end)
end

return Heist
