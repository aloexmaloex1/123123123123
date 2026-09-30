-- Tuning for museum security: security levels, NPC thief attempts and the museum star rating.
-- Shared by the Security service (server) and the 60_Museum feature (client).
local Security = {}

Security.MaxLevel = 10

-- Security Credits needed to reach each level (index = the level being bought).
Security.UpgradeCost = { 5, 8, 12, 18, 26, 38, 55, 80, 115, 160 }

-- Percent chance a thief is caught at each security level (index = level + 1, levels 0..10).
Security.CatchChance = { 35, 42, 49, 55, 61, 67, 73, 79, 84, 90, 95 }

-- What each level adds to the museum (shown in the Security menu and built on the plot).
Security.LevelPerks = {
	[1] = "Alarm keypad at the door",
	[2] = "Laser tripwires across the entrance",
	[3] = "A third laser beam",
	[4] = "Security cameras by the entrance",
	[5] = "Crossed lasers and rear cameras",
	[6] = "A security guard on patrol",
	[7] = "Motion sensors",
	[8] = "Reinforced vault door frame",
	[9] = "A second security guard",
	[10] = "Gold-plated vault: maximum security",
}

Security.Thief = {
	FirstDelay = { 6 * 60, 10 * 60 }, -- seconds after joining before the first attempt
	Interval = { 8 * 60, 15 * 60 }, -- seconds between later attempts
	RetryDelay = 60, -- recheck this often when there is nothing on display (or the player is busy)
	AlertSeconds = 5, -- time between the alarm and the outcome
	CaughtCredits = 4, -- Security Credits for catching a thief...
	CaughtCreditsPerLevel = 1, -- ...plus this per security level
	StolenIncomeMinutes = 10, -- an escaped thief takes this many minutes of income...
	MaxStolenFraction = 0.2, -- ...but never more than this share of the player's coins
	LogSize = 5, -- attempts kept in the Security menu log
}

-- Museum rating: each part scores 0..weight points, 100 points total -> 1..5 stars (half steps).
Security.Rating = {
	Weights = { Displayed = 25, Variety = 20, Rarity = 30, Security = 25 },
	DisplayedTarget = 12, -- relics on display for full points
	VarietyTarget = 12, -- distinct relics on display for full points
	RarityTarget = 80, -- sum of displayed relic tiers for full points (Common = 1 ... Forgotten = 10)
	IncomeBonusPerStar = 0.10, -- +10% income per star above 1 (5 stars = +40%)
}

function Security.GetCatchChance(level)
	level = math.clamp(math.floor(level or 0), 0, Security.MaxLevel)
	return Security.CatchChance[level + 1]
end

-- Cost to go from `level` to `level + 1`, or nil when maxed.
function Security.GetUpgradeCost(level)
	return Security.UpgradeCost[(level or 0) + 1]
end

function Security.GetIncomeBonus(stars)
	return math.max(0, (stars or 1) - 1) * Security.Rating.IncomeBonusPerStar
end

-- displayed: { [slotString] = relicId }; only slots <= `slots` count. `config` is ReplicatedStorage.RelicRNG.Config.
-- Returns { Stars, Score, Parts = { {Key, Name, Value, Target, Points, Max}, ... } }.
function Security.ComputeRating(displayed, slots, level, config)
	local rating = Security.Rating
	local count, tierSum, distinct, seen = 0, 0, 0, {}
	for slot, relicId in pairs(displayed or {}) do
		local relic = config.RelicsById[relicId]
		if relic and (tonumber(slot) or math.huge) <= slots then
			count += 1
			tierSum += relic.Tier
			if not seen[relicId] then
				seen[relicId] = true
				distinct += 1
			end
		end
	end
	level = math.clamp(level or 0, 0, Security.MaxLevel)
	local w = rating.Weights
	local parts = {
		{ Key = "Displayed", Name = "Relics on display", Value = count, Target = rating.DisplayedTarget, Max = w.Displayed },
		{ Key = "Variety", Name = "Variety", Value = distinct, Target = rating.VarietyTarget, Max = w.Variety },
		{ Key = "Rarity", Name = "Rarity", Value = tierSum, Target = rating.RarityTarget, Max = w.Rarity },
		{ Key = "Security", Name = "Security", Value = level, Target = Security.MaxLevel, Max = w.Security },
	}
	local score = 0
	for _, p in ipairs(parts) do
		p.Points = math.floor(math.clamp(p.Value / p.Target, 0, 1) * p.Max * 10 + 0.5) / 10
		score += p.Points
	end
	local stars = math.clamp(math.floor((1 + 4 * score / 100) * 2 + 1e-6) / 2, 1, 5)
	return { Stars = stars, Score = score, Parts = parts }
end

return Security
