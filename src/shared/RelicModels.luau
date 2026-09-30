-- Shared relic model builder: composite placeholder models for every relic Shape, used by the museum
-- pedestals (server) and by ViewportFrame thumbnails / reveal cards (client).
-- RelicModels.Build(relicId, cframe) -> Model centred on `cframe` (about 3 studs tall), PrimaryPart = invisible Root
-- at `cframe`, every part Anchored with CanCollide/CanQuery/CanTouch off. No billboard or tags are added here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RelicRNG.Config)

local RelicModels = {}

local M = Enum.Material
local BLOCK, BALL, CYL = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y
local FACING = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z (disc facing the front)
local GOLD = Color3.fromRGB(226, 178, 70)
local DARK = Color3.fromRGB(22, 20, 26)
local VELVET = Color3.fromRGB(120, 20, 36)

local function tint(color, amount)
	-- amount > 0 lightens towards white, < 0 darkens towards black
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

-- Material palette for a tier: `metal`, `stone`, `gem` (+ gem transparency) and whether accents glow.
local function palette(tier)
	local p = {}
	if tier <= 1 then
		p.metal, p.stone, p.gem = M.CorrodedMetal, M.Slate, M.SmoothPlastic
	elseif tier == 2 then
		p.metal, p.stone, p.gem = M.Metal, M.Limestone, M.SmoothPlastic
	elseif tier <= 5 then
		p.metal, p.stone, p.gem = M.Metal, M.Marble, M.Glass
	elseif tier <= 8 then
		p.metal, p.stone, p.gem = M.Foil, M.Marble, M.Glass
	else
		p.metal, p.stone, p.gem = M.Foil, M.Marble, M.Neon
	end
	p.glow = tier >= 3
	p.accentMat = tier >= 3 and M.Neon or M.Metal
	p.gemTransparency = (tier >= 3 and tier <= 8) and 0.25 or 0
	p.bodyTransparency = 0
	return p
end

local function newPart(model, kind, size, cframe, color, material)
	local p
	if kind == "Wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		p.Shape = kind
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- Ellipsoid (sphere mesh stretched to the part size).
local function ellipsoid(model, size, cframe, color, material)
	local p = newPart(model, BLOCK, size, cframe, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

---------------------------------------------------------------- shapes
-- Each builder gets (model, at, color, accent, pal, tier). `at` is the model centre; +Y up, -Z is the front.

local builders = {}

function builders.Coin(model, at, color, accent, pal, tier)
	local face = at * FACING
	newPart(model, CYL, Vector3.new(0.3, 2.3, 2.3), face, tint(color, -0.15), pal.metal) -- rim
	newPart(model, CYL, Vector3.new(0.36, 1.95, 1.95), face, color, pal.metal) -- face
	newPart(model, CYL, Vector3.new(0.4, 1.35, 1.35), face, tint(color, -0.3), pal.metal) -- inner ring
	newPart(model, CYL, Vector3.new(0.44, 1.15, 1.15), face, color, pal.metal)
	-- eight-point star emblem on both faces
	for _, angle in ipairs({ 0, 45 }) do
		local star = newPart(model, BLOCK, Vector3.new(0.62, 0.62, 0.5), at * CFrame.Angles(0, 0, math.rad(angle)), accent, pal.accentMat)
		if not pal.glow then
			star.Color = tint(color, 0.25)
		end
	end
	newPart(model, CYL, Vector3.new(0.56, 0.3, 0.3), face, pal.glow and tint(accent, 0.4) or tint(color, -0.4), pal.glow and M.Neon or pal.metal)
	-- rim studs
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		newPart(model, BALL, Vector3.new(0.2, 0.2, 0.2), at * CFrame.new(math.cos(a) * 1.13, math.sin(a) * 1.13, 0), tier >= 6 and GOLD or tint(color, 0.2), pal.metal)
	end
end

function builders.Pot(model, at, color, accent, pal, tier)
	local mat = tier <= 2 and M.Sandstone or pal.stone
	local body = ellipsoid(model, Vector3.new(1.7, 1.75, 1.7), at * CFrame.new(0, -0.25, 0), color, mat)
	body.Transparency = pal.bodyTransparency
	newPart(model, CYL, Vector3.new(0.3, 0.95, 0.95), at * CFrame.new(0, -1.15, 0) * UPRIGHT, tint(color, -0.2), mat) -- foot
	newPart(model, CYL, Vector3.new(0.12, 1.72, 1.72), at * CFrame.new(0, -0.25, 0) * UPRIGHT, accent, pal.accentMat) -- band
	newPart(model, CYL, Vector3.new(0.06, 1.55, 1.55), at * CFrame.new(0, 0.18, 0) * UPRIGHT, tint(color, -0.35), mat) -- shoulder line
	newPart(model, CYL, Vector3.new(0.75, 0.62, 0.62), at * CFrame.new(0, 0.85, 0) * UPRIGHT, color, mat) -- neck
	newPart(model, CYL, Vector3.new(0.16, 0.95, 0.95), at * CFrame.new(0, 1.25, 0) * UPRIGHT, tint(color, -0.2), mat) -- lip
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, BLOCK, Vector3.new(0.13, 0.62, 0.16), at * CFrame.new(side * 0.98, 0.52, 0), tint(color, -0.15), mat)
		newPart(model, BLOCK, Vector3.new(0.5, 0.13, 0.16), at * CFrame.new(side * 0.76, 0.86, 0), tint(color, -0.15), mat)
		newPart(model, BLOCK, Vector3.new(0.3, 0.13, 0.16), at * CFrame.new(side * 0.86, 0.22, 0) * CFrame.Angles(0, 0, side * 0.5), tint(color, -0.15), mat)
	end
	if tier >= 4 then
		newPart(model, BALL, Vector3.new(0.45, 0.45, 0.45), at * CFrame.new(0, 1.45, 0), accent, M.Neon) -- glowing contents
	end
end

function builders.Mask(model, at, color, accent, pal, tier)
	local face = ellipsoid(model, Vector3.new(1.7, 2.2, 0.55), at, color, pal.metal)
	face.Transparency = pal.bodyTransparency
	local hole, holeMat = DARK, M.SmoothPlastic
	for _, side in ipairs({ -1, 1 }) do
		ellipsoid(model, Vector3.new(0.5, 0.3, 0.2), at * CFrame.new(side * 0.36, 0.28, -0.2) * CFrame.Angles(0, 0, side * -0.15), hole, holeMat)
		if tier >= 4 then
			newPart(model, BALL, Vector3.new(0.14, 0.14, 0.14), at * CFrame.new(side * 0.36, 0.28, -0.29), tint(accent, 0.3), M.Neon) -- glowing pupil
		end
		newPart(model, BLOCK, Vector3.new(0.08, 0.55, 0.1), at * CFrame.new(side * 0.36, -0.12, -0.23), accent, pal.accentMat) -- tear stripe
		newPart(model, BLOCK, Vector3.new(0.6, 0.12, 0.2), at * CFrame.new(side * 0.36, 0.52, -0.18) * CFrame.Angles(0, 0, side * -0.2), tint(color, -0.35), pal.metal) -- brow
	end
	newPart(model, "Wedge", Vector3.new(0.22, 0.5, 0.2), at * CFrame.new(0, 0.02, -0.3), tint(color, -0.1), pal.metal) -- nose
	ellipsoid(model, Vector3.new(0.6, 0.14, 0.15), at * CFrame.new(0, -0.5, -0.2), hole, holeMat) -- mouth
	-- headdress fan
	for i = -2, 2 do
		local plume = newPart(model, BLOCK, Vector3.new(0.2, 0.95, 0.12), at * CFrame.new(0, 0.55, 0.12) * CFrame.Angles(0, 0, math.rad(i * 22)) * CFrame.new(0, 0.85, 0), i % 2 == 0 and accent or GOLD, i % 2 == 0 and pal.accentMat or M.Foil)
		plume.CastShadow = false
	end
end

function builders.Crown(model, at, color, accent, pal, tier)
	local base = at * CFrame.new(0, -0.35, 0)
	newPart(model, CYL, Vector3.new(0.75, 2, 2), base * UPRIGHT, color, pal.metal) -- band
	newPart(model, CYL, Vector3.new(0.12, 2.1, 2.1), base * CFrame.new(0, -0.35, 0) * UPRIGHT, tint(color, -0.25), pal.metal)
	newPart(model, CYL, Vector3.new(0.12, 2.08, 2.08), base * CFrame.new(0, 0.33, 0) * UPRIGHT, tint(color, -0.25), pal.metal)
	ellipsoid(model, Vector3.new(1.8, 1.1, 1.8), base * CFrame.new(0, 0.35, 0), VELVET, M.Fabric) -- cushion
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local out = CFrame.Angles(0, a, 0)
		newPart(model, BLOCK, Vector3.new(0.52, 0.52, 0.12), base * out * CFrame.new(0, 0.42, -0.95) * CFrame.Angles(0, 0, math.rad(45)), color, pal.metal) -- point
		newPart(model, BALL, Vector3.new(0.22, 0.22, 0.22), base * out * CFrame.new(0, 0.86, -0.95), i % 2 == 0 and accent or GOLD, i % 2 == 0 and M.Neon or M.Foil) -- tip gem
		if i % 2 == 0 then
			newPart(model, BALL, Vector3.new(0.3, 0.3, 0.3), base * out * CFrame.new(0, -0.02, -1.0), accent, pal.gem).Transparency = pal.gemTransparency -- band gem
		end
	end
	newPart(model, BALL, Vector3.new(0.4, 0.4, 0.4), base * CFrame.new(0, 1.0, 0), GOLD, M.Foil) -- orb finial
	newPart(model, BLOCK, Vector3.new(0.1, 0.45, 0.1), base * CFrame.new(0, 1.35, 0), GOLD, M.Foil)
end

function builders.Idol(model, at, color, accent, pal, tier)
	local mat = pal.stone
	newPart(model, BLOCK, Vector3.new(1.35, 0.3, 1.1), at * CFrame.new(0, -1.25, 0), tint(color, -0.35), mat) -- base
	newPart(model, BLOCK, Vector3.new(1.15, 0.12, 0.95), at * CFrame.new(0, -1.05, 0), accent, pal.accentMat) -- base trim
	newPart(model, BLOCK, Vector3.new(0.9, 1.2, 0.62), at * CFrame.new(0, -0.38, 0), color, mat).Transparency = pal.bodyTransparency -- body
	newPart(model, BLOCK, Vector3.new(0.95, 0.14, 0.66), at * CFrame.new(0, -0.2, 0), accent, pal.accentMat) -- belt
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, BLOCK, Vector3.new(0.22, 0.75, 0.3), at * CFrame.new(side * 0.55, -0.3, -0.05) * CFrame.Angles(0, 0, side * 0.2), tint(color, -0.1), mat) -- arm
		newPart(model, BALL, Vector3.new(0.13, 0.13, 0.13), at * CFrame.new(side * 0.16, 0.6, -0.38), accent, M.Neon) -- eye
	end
	ellipsoid(model, Vector3.new(0.85, 0.9, 0.75), at * CFrame.new(0, 0.58, 0), color, mat).Transparency = pal.bodyTransparency -- head
	newPart(model, BLOCK, Vector3.new(1.1, 0.16, 0.8), at * CFrame.new(0, 0.98, 0), GOLD, M.Foil) -- headdress
	newPart(model, "Wedge", Vector3.new(0.18, 0.6, 0.5), at * CFrame.new(0, 1.35, 0.05), accent, pal.accentMat) -- crest
end

function builders.Tower(model, at, color, accent, pal, tier)
	local tiers = { { -1.05, 0.5, 1.9 }, { -0.5, 0.6, 1.45 }, { 0.1, 0.6, 1.1 }, { 0.65, 0.5, 0.78 } }
	for i, t in ipairs(tiers) do
		local y, h, d = t[1], t[2], t[3]
		newPart(model, CYL, Vector3.new(h, d, d), at * CFrame.new(0, y, 0) * UPRIGHT, i % 2 == 1 and color or tint(color, 0.15), pal.stone).Transparency = pal.bodyTransparency
		newPart(model, CYL, Vector3.new(0.08, d + 0.12, d + 0.12), at * CFrame.new(0, y + h / 2, 0) * UPRIGHT, accent, pal.accentMat) -- ledge
	end
	for i = 0, 3 do
		newPart(model, BLOCK, Vector3.new(0.18, 0.3, 0.1), at * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, -0.5, -0.73), tier >= 3 and tint(accent, 0.3) or DARK, tier >= 3 and M.Neon or M.SmoothPlastic) -- windows
	end
	newPart(model, CYL, Vector3.new(0.45, 0.4, 0.4), at * CFrame.new(0, 1.12, 0) * UPRIGHT, GOLD, M.Foil) -- spire
	newPart(model, BALL, Vector3.new(0.38, 0.38, 0.38), at * CFrame.new(0, 1.48, 0), accent, M.Neon)
end

function builders.Ring(model, at, color, accent, pal, tier)
	local segments = 12
	local radius = 0.95
	for i = 0, segments - 1 do
		local a = i / segments * math.pi * 2
		newPart(model, BLOCK, Vector3.new(0.3, 0.54, 0.3), at * CFrame.new(0, -0.15, 0) * CFrame.Angles(0, 0, a) * CFrame.new(radius, 0, 0), color, pal.metal).Transparency = pal.bodyTransparency
	end
	-- gem setting on top
	newPart(model, BLOCK, Vector3.new(0.5, 0.2, 0.42), at * CFrame.new(0, 0.9, 0), GOLD, M.Foil)
	local gem = newPart(model, BALL, Vector3.new(0.58, 0.58, 0.58), at * CFrame.new(0, 1.2, 0), accent, tier >= 3 and pal.gem or M.Glass)
	gem.Transparency = pal.gemTransparency
	if tier >= 3 then
		newPart(model, BALL, Vector3.new(0.3, 0.3, 0.3), at * CFrame.new(0, 1.2, 0), tint(accent, 0.4), M.Neon)
	end
end

function builders.Ball(model, at, color, accent, pal, tier)
	newPart(model, CYL, Vector3.new(0.18, 1.2, 1.2), at * CFrame.new(0, -1.25, 0) * UPRIGHT, GOLD, tier >= 3 and M.Foil or pal.metal) -- foot
	newPart(model, CYL, Vector3.new(0.55, 0.32, 0.32), at * CFrame.new(0, -0.92, 0) * UPRIGHT, tint(GOLD, -0.2), tier >= 3 and M.Foil or pal.metal) -- stem
	newPart(model, CYL, Vector3.new(0.14, 0.9, 0.9), at * CFrame.new(0, -0.62, 0) * UPRIGHT, GOLD, tier >= 3 and M.Foil or pal.metal) -- cup
	for i = 0, 2 do
		newPart(model, BLOCK, Vector3.new(0.1, 0.55, 0.1), at * CFrame.Angles(0, i * math.pi * 2 / 3, 0) * CFrame.new(0, -0.38, -0.42) * CFrame.Angles(-0.45, 0, 0), GOLD, M.Foil) -- prong
	end
	local orbMat = tier <= 2 and M.Marble or pal.gem
	local orb = newPart(model, BALL, Vector3.new(1.45, 1.45, 1.45), at * CFrame.new(0, 0.2, 0), color, orbMat)
	if tier >= 3 then
		orb.Transparency = tier >= 9 and 0.45 or 0.3
		newPart(model, BALL, Vector3.new(0.7, 0.7, 0.7), at * CFrame.new(0, 0.2, 0), tint(accent, 0.3), M.Neon) -- core
	end
	if tier >= 5 then
		newPart(model, CYL, Vector3.new(0.05, 2.1, 2.1), at * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(70)), accent, M.Neon).Transparency = 0.35 -- orbit band
	end
end

function builders.Slab(model, at, color, accent, pal, tier)
	local frameColor = tier >= 5 and GOLD or tint(color, -0.4)
	local frameMat = tier >= 5 and M.Foil or pal.metal
	newPart(model, BLOCK, Vector3.new(1.45, 1.95, 0.16), at * CFrame.new(0, 0.05, 0), color, tier <= 2 and M.Sandstone or pal.stone).Transparency = pal.bodyTransparency
	newPart(model, CYL, Vector3.new(0.24, 1.75, 1.75), at * CFrame.new(0, 1.0, 0) * FACING, frameColor, frameMat) -- arched top
	newPart(model, BLOCK, Vector3.new(1.75, 0.16, 0.26), at * CFrame.new(0, -0.95, 0), frameColor, frameMat)
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, BLOCK, Vector3.new(0.16, 1.95, 0.26), at * CFrame.new(side * 0.8, 0.05, 0), frameColor, frameMat)
	end
	newPart(model, CYL, Vector3.new(0.26, 1.3, 1.3), at * CFrame.new(0, 1.0, 0) * FACING, color, pal.stone) -- arch panel
	for i = 0, 3 do
		newPart(model, BLOCK, Vector3.new(i % 2 == 0 and 1.0 or 0.75, 0.07, 0.2), at * CFrame.new(0, 0.5 - i * 0.35, 0), accent, pal.accentMat) -- inscription
	end
	newPart(model, BALL, Vector3.new(0.34, 0.34, 0.34), at * CFrame.new(0, 1.15, 0), accent, pal.glow and M.Neon or pal.metal) -- emblem
	newPart(model, BLOCK, Vector3.new(2.0, 0.3, 0.7), at * CFrame.new(0, -1.15, 0), tint(color, -0.45), pal.stone) -- stand
end

function builders.Wedge(model, at, color, accent, pal, tier)
	local bladeMat = tier >= 6 and M.Foil or tier >= 3 and M.Metal or M.Slate
	local blade = at * CFrame.new(0, 0.25, 0)
	newPart(model, BLOCK, Vector3.new(0.56, 1.3, 0.1), blade, color, bladeMat).Transparency = pal.bodyTransparency
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, "Wedge", Vector3.new(0.1, 0.8, 0.28), blade * CFrame.new(side * 0.14, 1.05, 0) * CFrame.Angles(0, side * -math.pi / 2, 0), color, bladeMat).Transparency = pal.bodyTransparency
	end
	newPart(model, BLOCK, Vector3.new(0.08, 1.45, 0.14), blade * CFrame.new(0, 0.1, 0), accent, pal.accentMat) -- fuller
	newPart(model, BLOCK, Vector3.new(1.3, 0.18, 0.28), at * CFrame.new(0, -0.48, 0), GOLD, tier >= 3 and M.Foil or pal.metal) -- guard
	for _, side in ipairs({ -1, 1 }) do
		newPart(model, BALL, Vector3.new(0.26, 0.26, 0.26), at * CFrame.new(side * 0.68, -0.48, 0), accent, pal.glow and M.Neon or pal.metal)
	end
	newPart(model, CYL, Vector3.new(0.6, 0.2, 0.2), at * CFrame.new(0, -0.88, 0) * UPRIGHT, Color3.fromRGB(70, 42, 28), M.Fabric) -- grip
	newPart(model, BALL, Vector3.new(0.3, 0.3, 0.3), at * CFrame.new(0, -1.25, 0), accent, pal.glow and M.Neon or pal.metal) -- pommel
end

function builders.Block(model, at, color, accent, pal, tier)
	local wood = tier >= 6 and pal.metal or M.WoodPlanks
	newPart(model, BLOCK, Vector3.new(1.7, 0.9, 1.1), at * CFrame.new(0, -0.55, 0), color, wood) -- chest body
	ellipsoid(model, Vector3.new(1.7, 0.75, 1.1), at * CFrame.new(0, -0.1, 0), tint(color, 0.1), wood) -- domed lid
	for _, x in ipairs({ -0.55, 0.55 }) do
		newPart(model, BLOCK, Vector3.new(0.14, 1.0, 1.14), at * CFrame.new(x, -0.5, 0), GOLD, tier >= 3 and M.Foil or pal.metal) -- strap
		ellipsoid(model, Vector3.new(0.14, 0.79, 1.14), at * CFrame.new(x, -0.1, 0), GOLD, tier >= 3 and M.Foil or pal.metal)
	end
	newPart(model, BLOCK, Vector3.new(0.34, 0.4, 0.08), at * CFrame.new(0, -0.35, -0.57), GOLD, M.Foil) -- lock plate
	newPart(model, BALL, Vector3.new(0.16, 0.16, 0.16), at * CFrame.new(0, -0.35, -0.62), accent, M.Neon)
	for _, c in ipairs({ { -0.75, -0.45 }, { 0.75, -0.45 }, { -0.75, 0.45 }, { 0.75, 0.45 } }) do
		newPart(model, BLOCK, Vector3.new(0.22, 0.2, 0.22), at * CFrame.new(c[1], -1.07, c[2]), GOLD, M.Foil) -- feet
	end
	if tier >= 5 then
		-- treasure spilling out of the lid
		newPart(model, BALL, Vector3.new(0.5, 0.5, 0.5), at * CFrame.new(0, 0.35, 0), accent, M.Neon)
	end
end

---------------------------------------------------------------- public

-- Returns the Model for `relicId` centred on `cframe` (not parented). Unknown ids build a grey orb.
function RelicModels.Build(relicId, cframe)
	cframe = cframe or CFrame.new()
	local relic = Config.RelicsById[relicId]
	local tier = relic and relic.Tier or 1
	local rarity = Config.Rarities[tier]
	local accent = rarity.Color
	local color = relic and relic.Color or accent
	local pal = palette(tier)

	local model = Instance.new("Model")
	model.Name = relic and relic.Name or tostring(relicId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("RelicId", relicId)
	model:SetAttribute("Tier", tier)

	local root = newPart(model, BLOCK, Vector3.new(0.2, 0.2, 0.2), cframe, accent, M.SmoothPlastic)
	root.Name = "Root"
	root.Transparency = 1
	model.PrimaryPart = root

	local builder = builders[relic and relic.Shape or "Ball"] or builders.Ball
	builder(model, cframe, color, accent, pal, tier)

	-- rarity glow: a light from uncommon upwards, sparkles from legendary, a shimmering aura from celestial
	if tier >= 2 then
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = accent
		light.Range = 5 + tier * 0.9
		light.Brightness = 0.2 + (tier - 2) * 0.2
		light.Shadows = false
		light.Parent = root
	end
	if tier >= 5 then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "Sparkle"
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(tint(accent, 0.3))
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Transparency = NumberSequence.new(0.2)
		sparkle.Lifetime = NumberRange.new(0.8, 1.6)
		sparkle.Rate = 3 + (tier - 5) * 5
		sparkle.Speed = NumberRange.new(0.3, 1.2)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Shape = Enum.ParticleEmitterShape.Sphere
		sparkle.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		sparkle.Parent = root
		root.Size = Vector3.new(2.4, 2.4, 2.4) -- emitter volume
	end
	if tier >= 9 then
		local aura = newPart(model, BALL, Vector3.new(3.4, 3.4, 3.4), cframe, accent, M.ForceField)
		aura.Name = "Aura"
		aura.Transparency = 0.2
	end
	return model
end

-- Approximate height of built models (for camera framing in ViewportFrames).
RelicModels.Height = 3

-- Models face -Z (the coin face, mask, eyes and chest lock point that way). Camera CFrame that frames a model
-- built at `cframe` from the front, slightly above; `distance` defaults to 6.5 studs (good for FieldOfView 40).
function RelicModels.CameraCFrame(cframe, distance)
	cframe = cframe or CFrame.new()
	distance = distance or 6.5
	local eye = cframe * Vector3.new(0, distance * 0.18, -distance)
	return CFrame.lookAt(eye, cframe.Position)
end

return RelicModels
