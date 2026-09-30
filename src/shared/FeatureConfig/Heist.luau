-- Heist tuning: NPC museums, security, tools, rewards and notoriety ranks.
-- Shared with the client for the heist menu and HUD. Map layouts live server-side in
-- ServerScriptService.RelicRNG.HeistMaps; the simulation lives in Services.Heist.
local Config = require(script.Parent.Parent:WaitForChild("Config"))

local rgb = Color3.fromRGB
local Heist = {}

---------------------------------------------------------------- energy, timing

Heist.BaseEnergy = 3
Heist.PassEnergyBonus = 2 -- "ExtraHeistEnergy" game pass
Heist.EnergyRegenSeconds = 15 * 60
Heist.Duration = 180 -- seconds per heist (+ "HeistSeconds" set bonus)
Heist.FailCooldown = 30
Heist.StealSeconds = 4
Heist.LockpickStealSeconds = 0.8
Heist.EscapeRadius = 6 -- studs from the exit pad centre
Heist.LockdownTimeCap = 45 -- at most this many seconds left once lockdown starts
Heist.StealAlarm = 10 -- the display case chirps when the relic is lifted
Heist.GhostAlarm = 50 -- finishing with the alarm never above this counts as a clean "Ghost" heist
Heist.GhostCoinBonus = 1.25
Heist.GhostNotorietyBonus = 1.5
Heist.SpeedCoinBonus = 0.25 -- up to +25% coins for time left on the clock
Heist.MaxToolStack = 99

---------------------------------------------------------------- security

Heist.Security = {
	TickRate = 10, -- detection checks per second
	GuardRange = 22,
	SilentRange = 13, -- with Silent Shoes
	GuardMinDot = 0.35, -- how far to the side guards can see (dot of facing vs direction to player)
	CatchRange = 4,
	GuardAlarmMin = 30, -- alarm per second when seen at the edge of vision...
	GuardAlarmMax = 90, -- ...and right up close
	CameraRange = 30,
	CameraMinDot = 0.8,
	CameraAlarm = 40, -- per second in a camera cone
	CameraSweepDegrees = 45,
	CameraSweepSpeed = 0.7,
	CameraPitchDegrees = 24,
	AlarmDecay = 4, -- per second once nobody has seen you for DecayDelay seconds (never during lockdown)
	DecayDelay = 1.5,
	LaserAlarm = 35,
	LaserOnSeconds = 1.8,
	LaserOffSeconds = 1.4,
	LaserCooldown = 1,
	PlateAlarm = 20,
	StickySpeed = 7,
	StickySeconds = 3,
	SuspiciousSeconds = 0.7, -- a guard stares this long after losing sight, then investigates
	InvestigateSeconds = 4,
	LockdownSpeed = 14.5, -- players walk at 16, so a clean sprint still escapes
	StolenSpeedBonus = 1.15, -- guards walk faster once the relic is gone
}

---------------------------------------------------------------- museums

Heist.MapOrder = { "GildedGallery", "ObsidianVault", "SkyPalace" }
Heist.Maps = {
	GildedGallery = {
		Name = "Gilded Gallery",
		Difficulty = "Easy",
		Level = 3,
		Color = rgb(245, 195, 80),
		Blurb = "Sleepy gallery. Two guards, one camera.",
		BaseCoins = 300,
		IncomeMinutes = 10, -- plus this many minutes of your museum income
		Credits = 3,
		Notoriety = 12,
		FailNotoriety = 3,
		XPFraction = 0.35, -- of the XP needed for your next level
		MinTier = 3,
		LootLuck = 1.5,
		LootSites = { "DustyDunes", "SunkenVault" },
		GuardSpeed = 7,
	},
	ObsidianVault = {
		Name = "Obsidian Vault",
		Difficulty = "Medium",
		Level = 12,
		Color = rgb(80, 170, 255),
		Blurb = "Laser doors, pressure plates, five guards.",
		BaseCoins = 2500,
		IncomeMinutes = 20,
		Credits = 8,
		Notoriety = 35,
		FailNotoriety = 6,
		XPFraction = 0.5,
		MinTier = 4,
		LootLuck = 2,
		LootSites = { "SunkenVault", "FrozenReliquary", "MeteorCrater" },
		GuardSpeed = 8,
	},
	SkyPalace = {
		Name = "Sky Palace Collection",
		Difficulty = "Hard",
		Level = 25,
		Color = rgb(190, 140, 255),
		Blurb = "Laser gauntlet, throne vault, six guards.",
		BaseCoins = 12000,
		IncomeMinutes = 35,
		Credits = 20,
		Notoriety = 90,
		FailNotoriety = 12,
		XPFraction = 0.6,
		MinTier = 5,
		LootLuck = 3,
		LootSites = { "MeteorCrater", "HauntedBazaar", "CelestialRuins" },
		GuardSpeed = 9,
	},
}

---------------------------------------------------------------- tools (bought with coins, saved counts)

Heist.ToolOrder = { "Lockpick", "EMP", "Smoke", "Decoy", "SilentShoes" }
Heist.Tools = {
	Lockpick = { Name = "Lockpick", Price = 120, Key = 1, Color = rgb(245, 200, 90), Description = "Your next steal takes 0.8s instead of 4s." },
	EMP = { Name = "EMP Burst", Price = 350, Key = 2, Duration = 8, Color = rgb(90, 180, 255), Description = "Lasers and cameras shut down for 8s." },
	Smoke = { Name = "Smoke Bomb", Price = 250, Key = 3, Duration = 6, Radius = 30, Color = rgb(190, 190, 210), Description = "Guards within 30 studs are blinded for 6s." },
	Decoy = { Name = "Decoy Coin", Price = 150, Key = 4, Duration = 6, Radius = 40, Throw = 20, Color = rgb(255, 215, 80), Description = "Guards within 40 studs go check a noise ahead of you for 6s." },
	SilentShoes = { Name = "Silent Shoes", Price = 400, Key = 5, Duration = 45, Color = rgb(170, 120, 255), Description = "Guards only notice you within 13 studs for 45s." },
}

---------------------------------------------------------------- notoriety

Heist.Ranks = {
	{ Name = "Pickpocket", Min = 0, Color = rgb(170, 170, 170) },
	{ Name = "Sneak", Min = 50, Color = rgb(110, 210, 120) },
	{ Name = "Burglar", Min = 150, Color = rgb(80, 160, 255) },
	{ Name = "Cat Burglar", Min = 400, Color = rgb(165, 95, 245) },
	{ Name = "Vault Breaker", Min = 900, Color = rgb(255, 150, 50) },
	{ Name = "Phantom Thief", Min = 1800, Color = rgb(235, 60, 80) },
	{ Name = "Master Thief", Min = 3500, Color = rgb(245, 205, 70) },
	{ Name = "Legendary Heirloom Hunter", Min = 6000, Color = rgb(255, 230, 150) },
	{ Name = "Shadow Curator", Min = 10000, Color = rgb(200, 60, 255) },
}

-- Returns rankIndex, rank, nextRank (nil at max).
function Heist.GetRank(notoriety)
	local index = 1
	for i, rank in ipairs(Heist.Ranks) do
		if (notoriety or 0) >= rank.Min then
			index = i
		end
	end
	return index, Heist.Ranks[index], Heist.Ranks[index + 1]
end

function Heist.EnergyCap(hasPass)
	return Heist.BaseEnergy + (hasPass and Heist.PassEnergyBonus or 0)
end

-- Regenerates heist energy from a saved timestamp (works across sessions). Returns energy, energyAt.
function Heist.RegenEnergy(energy, energyAt, cap, now)
	if energy >= cap then
		return energy, now
	end
	energyAt = energyAt or now
	local elapsed = now - energyAt
	if elapsed >= Heist.EnergyRegenSeconds then
		local gained = math.floor(elapsed / Heist.EnergyRegenSeconds)
		energy = math.min(cap, energy + gained)
		energyAt = energy >= cap and now or energyAt + gained * Heist.EnergyRegenSeconds
	end
	return energy, energyAt
end

---------------------------------------------------------------- detection math

-- Is `target` inside a vision cone at `eye` looking along `look`? Horizontal cone; returns seen, flatDistance.
function Heist.InVision(eye, look, target, range, minDot)
	local offset = target - eye
	if math.abs(offset.Y) > 14 then
		return false, math.huge
	end
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	if distance > range then
		return false, distance
	end
	if distance < 0.5 then
		return true, distance
	end
	local lookFlat = Vector3.new(look.X, 0, look.Z)
	if lookFlat.Magnitude < 1e-3 then
		return false, distance
	end
	return flat.Unit:Dot(lookFlat.Unit) > minDot, distance
end

-- Alarm per second from a guard that can see you at `distance`.
function Heist.GuardAlarmRate(distance, range)
	local sec = Heist.Security
	local closeness = 1 - math.clamp(distance / range, 0, 1)
	return sec.GuardAlarmMin + (sec.GuardAlarmMax - sec.GuardAlarmMin) * closeness
end

---------------------------------------------------------------- guard / camera visuals
-- The server only simulates guards and cameras (positions live in tables); the client builds and
-- animates these models locally from the "Heist" Start/State events so nothing moving replicates.
-- The server's Edit-mode preview (Services.Heist.BuildPreview) uses the same builders.

local GUARD_UNIFORM = rgb(26, 30, 52)
local GUARD_DARK = rgb(14, 14, 20)
local GUARD_SKIN = rgb(62, 56, 70)
local VISOR_CALM = rgb(70, 255, 150)
local FLASH_WARM = rgb(255, 238, 205)
local ALARM_RED = rgb(255, 30, 40)
local CAM_RED = rgb(255, 40, 55)
Heist.EmpBlue = rgb(90, 180, 255)
Heist.CameraRed = CAM_RED

-- Guard look codes sent in the State payload (G array, 4th value per guard).
Heist.GuardLook = { Calm = 0, Suspicious = 1, Alert = 2, Blind = 3 }

local function vpart(parent, size, cframe, color, material, extra)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if extra then
		for key, value in pairs(extra) do
			p[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function weld(root, p)
	p.Anchored = false
	p.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	return p
end

local function beamBetween(parent, a0, a1, color, width0, width1, transparency)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Width0 = width0
	beam.Width1 = width1
	beam.Segments = 1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = transparency
	beam.Parent = parent
	return beam
end

-- Builds a guard standing at floor point `at`. The flashlight beam ends on an attachment parented to
-- `endParent` (workspace.Terrain on the client). Move it by setting parts.Root.CFrame.
function Heist.BuildGuardModel(parent, at, endParent)
	local model = Instance.new("Model")
	model.Name = "Guard"
	local root = vpart(model, Vector3.new(2, 2, 1), CFrame.new(at + Vector3.new(0, 3, 0)), GUARD_DARK, nil, { Name = "Root", Transparency = 1 })
	model.PrimaryPart = root
	local function limb(sizeV, offset, color, material, extra)
		return weld(root, vpart(model, sizeV, root.CFrame * offset, color, material, extra))
	end
	local ball, cyl = Enum.PartType.Ball, Enum.PartType.Cylinder
	limb(Vector3.new(0.85, 2.9, 0.85), CFrame.new(-0.5, -1.55, 0), GUARD_DARK)
	limb(Vector3.new(0.85, 2.9, 0.85), CFrame.new(0.5, -1.55, 0), GUARD_DARK)
	limb(Vector3.new(2.1, 2.5, 1.1), CFrame.new(0, 1.15, 0), GUARD_UNIFORM, Enum.Material.Fabric)
	limb(Vector3.new(2.15, 0.3, 1.15), CFrame.new(0, 0.05, 0), GUARD_DARK, Enum.Material.Metal)
	limb(Vector3.new(0.4, 0.45, 0.1), CFrame.new(0.5, 1.7, -0.58), rgb(255, 205, 80), Enum.Material.Neon)
	limb(Vector3.new(2.3, 0.35, 1.2), CFrame.new(0, 2.3, 0), GUARD_UNIFORM, Enum.Material.Fabric)
	limb(Vector3.new(0.7, 2.4, 0.8), CFrame.new(-1.45, 1.1, 0), GUARD_UNIFORM, Enum.Material.Fabric)
	limb(Vector3.new(0.7, 2.2, 0.8), CFrame.new(1.45, 1.5, -0.7) * CFrame.Angles(math.rad(70), 0, 0), GUARD_UNIFORM, Enum.Material.Fabric)
	limb(Vector3.new(1.35, 1.35, 1.35), CFrame.new(0, 3.05, 0), GUARD_SKIN, nil, { Shape = ball })
	limb(Vector3.new(0.55, 1.5, 1.5), CFrame.new(0, 3.55, 0) * CFrame.Angles(0, 0, math.rad(90)), GUARD_DARK, Enum.Material.Fabric, { Shape = cyl })
	limb(Vector3.new(1.4, 0.14, 0.75), CFrame.new(0, 3.33, -0.75), GUARD_DARK, Enum.Material.Fabric)
	local glows = {
		limb(Vector3.new(1.15, 0.3, 0.2), CFrame.new(0, 3.05, -0.62), VISOR_CALM, Enum.Material.Neon),
		limb(Vector3.new(2.16, 0.22, 1.16), CFrame.new(0, 1.55, 0), VISOR_CALM, Enum.Material.Neon),
		limb(Vector3.new(0.74, 0.18, 0.84), CFrame.new(-1.45, 1.9, 0), VISOR_CALM, Enum.Material.Neon),
		limb(Vector3.new(0.12, 1.52, 1.52), CFrame.new(0, 3.3, 0) * CFrame.Angles(0, 0, math.rad(90)), VISOR_CALM, Enum.Material.Neon, { Shape = cyl }),
	}
	local torch = limb(Vector3.new(0.4, 0.4, 1.1), CFrame.new(1.45, 1.35, -1.95), rgb(40, 40, 46), Enum.Material.Metal)
	limb(Vector3.new(0.42, 0.42, 0.1), CFrame.new(1.45, 1.35, -2.52), FLASH_WARM, Enum.Material.Neon)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 90
	light.Range = Heist.Security.GuardRange
	light.Brightness = 2.4
	light.Color = FLASH_WARM
	light.Shadows = false
	light.Parent = torch
	local eye = Instance.new("Attachment")
	eye.Position = Vector3.new(0, 0, -0.6)
	eye.Parent = torch
	local endAtt = Instance.new("Attachment")
	endAtt.Parent = endParent
	endAtt.WorldPosition = at + Vector3.new(0, 0.2, -12)
	local beam = beamBetween(torch, eye, endAtt, FLASH_WARM, 0.5, 11, NumberSequence.new(0.7, 0.96))

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(40, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Enabled = false
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextStrokeTransparency = 0.2
	text.TextColor3 = rgb(255, 220, 90)
	text.Text = "?"
	text.Parent = gui
	gui.Parent = root
	model.Parent = parent
	return { Model = model, Root = root, Glows = glows, Light = light, Beam = beam, End = endAtt, Indicator = gui, IndicatorText = text, Look = -1 }
end

-- Recolours a guard for a look code (Heist.GuardLook). Cheap no-op when unchanged.
function Heist.SetGuardLook(parts, look)
	if parts.Look == look then
		return
	end
	parts.Look = look
	local light, beam, text, indicator = parts.Light, parts.Beam, parts.IndicatorText, parts.Indicator
	local glow = VISOR_CALM
	if look == Heist.GuardLook.Alert then
		glow = ALARM_RED
		light.Color = rgb(255, 70, 70)
		beam.Color = ColorSequence.new(rgb(255, 60, 60))
		indicator.Enabled = true
		text.Text = "!"
		text.TextColor3 = ALARM_RED
	elseif look == Heist.GuardLook.Suspicious then
		glow = rgb(255, 190, 60)
		light.Color = rgb(255, 210, 150)
		beam.Color = ColorSequence.new(rgb(255, 200, 120))
		indicator.Enabled = true
		text.Text = "?"
		text.TextColor3 = rgb(255, 210, 80)
	elseif look == Heist.GuardLook.Blind then
		glow = rgb(120, 120, 130)
		light.Color = FLASH_WARM
		beam.Color = ColorSequence.new(FLASH_WARM)
		indicator.Enabled = true
		text.Text = "x"
		text.TextColor3 = rgb(200, 200, 210)
	else
		light.Color = FLASH_WARM
		beam.Color = ColorSequence.new(FLASH_WARM)
		indicator.Enabled = false
	end
	for _, part in ipairs(parts.Glows) do
		part.Color = glow
	end
	local lit = look ~= Heist.GuardLook.Blind
	light.Enabled = lit
	beam.Enabled = lit
end

-- CFrame of a wall camera's sweeping head at yaw `yaw`.
function Heist.CameraCFrame(pivotPos, yaw, pitch)
	return CFrame.new(pivotPos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

-- Sweep yaw of camera `cam` ({BaseYaw, Phase}) `elapsed` seconds into the heist. Server and client agree.
function Heist.CameraYaw(baseYaw, phase, elapsed)
	local sec = Heist.Security
	return baseYaw + math.sin(elapsed * sec.CameraSweepSpeed + phase) * math.rad(sec.CameraSweepDegrees)
end

-- Builds the sweeping head of a wall camera (the wall bracket is part of the server-built map).
function Heist.BuildCameraHead(parent, pivotCF, endParent)
	local model = Instance.new("Model")
	model.Name = "CameraHead"
	local pivot = vpart(model, Vector3.new(0.5, 0.5, 0.5), pivotCF, CAM_RED, nil, { Name = "CameraPivot", Transparency = 1 })
	model.PrimaryPart = pivot
	local body = weld(pivot, vpart(model, Vector3.new(1.2, 1.1, 2.4), pivotCF * CFrame.new(0, 0, -1.1), rgb(215, 215, 222)))
	weld(pivot, vpart(model, Vector3.new(1.45, 0.14, 2.8), pivotCF * CFrame.new(0, 0.62, -1.2), rgb(30, 30, 36), Enum.Material.Metal))
	weld(pivot, vpart(model, Vector3.new(0.25, 0.9, 0.9), pivotCF * CFrame.new(0, 0, -2.35) * CFrame.Angles(0, math.rad(90), 0), rgb(12, 12, 16), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder }))
	local lens = weld(pivot, vpart(model, Vector3.new(0.27, 0.45, 0.45), pivotCF * CFrame.new(0, 0, -2.37) * CFrame.Angles(0, math.rad(90), 0), CAM_RED, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder }))
	local led = weld(pivot, vpart(model, Vector3.new(0.25, 0.25, 0.25), pivotCF * CFrame.new(0.4, 0.35, -2.1), CAM_RED, Enum.Material.Neon, { Shape = Enum.PartType.Ball }))
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 70
	light.Range = 30
	light.Brightness = 2.6
	light.Color = rgb(255, 70, 70)
	light.Shadows = false
	light.Parent = body
	local eye = Instance.new("Attachment")
	eye.Position = Vector3.new(0, 0, -1.3)
	eye.Parent = body
	local endAtt = Instance.new("Attachment")
	endAtt.Parent = endParent
	endAtt.WorldPosition = pivotCF.Position + pivotCF.LookVector * 18
	local beam = beamBetween(body, eye, endAtt, rgb(255, 50, 60), 0.5, 13, NumberSequence.new(0.72, 0.93))
	model.Parent = parent
	return { Model = model, Pivot = pivot, Lens = lens, Led = led, Light = light, Beam = beam, End = endAtt }
end

---------------------------------------------------------------- rewards

-- Success rewards. incomePerMin keeps coins meaningful as museums grow.
function Heist.Rewards(mapId, incomePerMin, secondsLeft, duration, ghost, level)
	local map = Heist.Maps[mapId]
	local speed = 1 + Heist.SpeedCoinBonus * math.clamp(secondsLeft / math.max(duration, 1), 0, 1)
	local coins = (map.BaseCoins + math.max(0, incomePerMin) * map.IncomeMinutes) * speed * (ghost and Heist.GhostCoinBonus or 1)
	return {
		Coins = math.floor(coins),
		Credits = map.Credits + (ghost and math.ceil(map.Credits / 3) or 0),
		Notoriety = math.floor(map.Notoriety * (ghost and Heist.GhostNotorietyBonus or 1)),
		XP = math.floor(Config.XPForLevel(math.max(level or 1, map.Level)) * map.XPFraction),
	}
end

return Heist
