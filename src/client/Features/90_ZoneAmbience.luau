-- Zone ambience: while the local character stands inside a dig site, tweens a client-only colour grade,
-- the Atmosphere and a few Lighting values towards that site's mood; restores the originals on leaving.
-- Only this client is affected. The place's own Lighting children are never destroyed.
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local FADE = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local CHECK_INTERVAL = 0.3

-- Per-site mood. Grade = our own ColorCorrectionEffect; Atmosphere/Lighting are tweened then restored.
local MOODS = {
	DustyDunes = {
		Grade = { TintColor = Color3.fromRGB(255, 243, 222), Brightness = 0.02, Contrast = 0.04, Saturation = 0.08 },
		Atmosphere = { Density = 0.34, Haze = 1.6, Color = Color3.fromRGB(236, 212, 168), Decay = Color3.fromRGB(196, 160, 110) },
	},
	SunkenVault = {
		Grade = { TintColor = Color3.fromRGB(212, 246, 242), Brightness = -0.02, Contrast = 0.06, Saturation = 0.05 },
		Atmosphere = { Density = 0.38, Haze = 1.2, Color = Color3.fromRGB(150, 205, 210), Decay = Color3.fromRGB(60, 120, 140) },
	},
	FrozenReliquary = {
		Grade = { TintColor = Color3.fromRGB(218, 232, 255), Brightness = -0.04, Contrast = 0.08, Saturation = -0.08 },
		Atmosphere = { Density = 0.4, Haze = 1.4, Color = Color3.fromRGB(190, 212, 240), Decay = Color3.fromRGB(110, 140, 190) },
		Lighting = { ExposureCompensation = -0.35 },
	},
	MeteorCrater = {
		Grade = { TintColor = Color3.fromRGB(228, 208, 255), Brightness = -0.03, Contrast = 0.1, Saturation = 0.08 },
		Atmosphere = { Density = 0.42, Haze = 1.8, Color = Color3.fromRGB(150, 120, 200), Decay = Color3.fromRGB(80, 50, 130) },
		Lighting = { ExposureCompensation = -0.15 },
	},
	HauntedBazaar = {
		Grade = { TintColor = Color3.fromRGB(200, 180, 235), Brightness = -0.06, Contrast = 0.14, Saturation = -0.35 },
		Atmosphere = { Density = 0.55, Offset = 0.1, Haze = 2.4, Glare = 0, Color = Color3.fromRGB(90, 70, 120), Decay = Color3.fromRGB(40, 28, 60) },
		Lighting = {
			ClockTime = 20.2,
			ExposureCompensation = -0.2,
			Ambient = Color3.fromRGB(60, 48, 82),
			OutdoorAmbient = Color3.fromRGB(78, 62, 108),
		},
	},
	CelestialRuins = {
		Grade = { TintColor = Color3.fromRGB(255, 244, 222), Brightness = 0.05, Contrast = 0.05, Saturation = 0.12 },
		Atmosphere = { Density = 0.26, Haze = 1, Glare = 0.5, Color = Color3.fromRGB(255, 236, 205), Decay = Color3.fromRGB(255, 205, 150) },
		Lighting = { ExposureCompensation = 0.1 },
	},
}
local MOOD_LIST = { MOODS.DustyDunes, MOODS.SunkenVault, MOODS.FrozenReliquary, MOODS.MeteorCrater, MOODS.HauntedBazaar, MOODS.CelestialRuins }

local NEUTRAL_GRADE = { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0, Saturation = 0 }

return function(ctx)
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "ZoneAmbienceGrade"
	for key, value in pairs(NEUTRAL_GRADE) do
		grade[key] = value
	end
	grade.Parent = Lighting

	local saved = nil -- originals of every Atmosphere/Lighting property touched while a mood is active
	local tweens = {}
	local restoreToken = nil

	local function play(instance, goal)
		if next(goal) == nil then
			return
		end
		local tween = TweenService:Create(instance, FADE, goal)
		table.insert(tweens, tween)
		tween:Play()
	end

	local function stopTweens()
		for _, tween in ipairs(tweens) do
			tween:Cancel()
		end
		table.clear(tweens)
	end

	local function apply(siteId)
		stopTweens()
		local mood = siteId and MOODS[siteId]
		local atmos = Lighting:FindFirstChildOfClass("Atmosphere")

		-- Leaving (or a site with no mood): fade back to what the place had before.
		if not mood then
			play(grade, NEUTRAL_GRADE)
			if saved then
				if atmos then
					play(atmos, saved.Atmosphere)
				end
				play(Lighting, saved.Lighting)
				-- Forget the originals once the fade-back finishes (re-entering mid-fade reuses them).
				local token = {}
				restoreToken = token
				task.delay(FADE.Time + 0.1, function()
					if restoreToken == token then
						saved = nil
					end
				end)
			end
			return
		end
		restoreToken = nil

		-- Entering from outside: remember the originals once.
		if not saved then
			saved = { Atmosphere = {}, Lighting = {} }
			for _, def in ipairs(MOOD_LIST) do
				if atmos and def.Atmosphere then
					for key in pairs(def.Atmosphere) do
						saved.Atmosphere[key] = atmos[key]
					end
				end
				for key in pairs(def.Lighting or {}) do
					saved.Lighting[key] = Lighting[key]
				end
			end
		end
		-- Every touched property gets a goal (the mood's value or the original) so switching sites never leaks.
		local goalAtmos, goalLighting = {}, {}
		if atmos then
			for key, original in pairs(saved.Atmosphere) do
				local value = mood.Atmosphere and mood.Atmosphere[key]
				goalAtmos[key] = if value ~= nil then value else original
			end
			play(atmos, goalAtmos)
		end
		for key, original in pairs(saved.Lighting) do
			local value = mood.Lighting and mood.Lighting[key]
			goalLighting[key] = if value ~= nil then value else original
		end
		play(Lighting, goalLighting)
		play(grade, mood.Grade)
	end

	-- Cleanup: stop polling, cancel tweens, snap the place's Lighting/Atmosphere back and drop our grade.
	local alive = true
	local function cleanup()
		if not alive then
			return
		end
		alive = false
		restoreToken = nil
		stopTweens()
		if saved then
			local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
			if atmos then
				for key, value in pairs(saved.Atmosphere) do
					atmos[key] = value
				end
			end
			for key, value in pairs(saved.Lighting) do
				Lighting[key] = value
			end
			saved = nil
		end
		if grade.Parent then
			grade:Destroy()
		end
	end
	grade.Destroying:Once(cleanup)
	script.Destroying:Once(cleanup)

	-- Low-rate poll (no per-frame work, no allocation unless the site changes).
	local current = nil
	task.spawn(function()
		while alive do
			local ok, siteId = pcall(ctx.CurrentSite)
			if not ok then
				siteId = nil
			end
			if siteId ~= current then
				current = siteId
				apply(siteId)
			end
			task.wait(CHECK_INTERVAL)
		end
	end)
end
