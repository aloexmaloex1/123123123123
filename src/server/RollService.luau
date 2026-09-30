--!strict
-- Server-side relic rolling: rarity table, luck, dig-site pools and pity milestones from Config.
-- Randomness is injectable (`rng`) so the specs can run with a seeded generator.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("RelicRNG")
local Config = require(Shared:WaitForChild("Config")) :: any
local Types = require(Shared:WaitForChild("Types"))

type PlayerData = Types.PlayerData
type RollResult = Types.RollResult

local Rarities = Config.Rarities
local Pity = Config.Pity

local RollService = {}
local defaultRng = Random.new()

-- Weighted pick among tiers minTier..rarest using luck-adjusted chances.
local function pickTier(rng: Random, chances: { number }, minTier: number): number
	local total = 0
	for tier = minTier, #Rarities do
		total += chances[tier]
	end
	local roll = rng:NextNumber() * total
	for tier = minTier, #Rarities do
		roll -= chances[tier]
		if roll < 0 then
			return tier
		end
	end
	return #Rarities
end

local function pickRelic(rng: Random, siteId: string, tier: number): (string, number)
	local byTier = Config.SiteRelicsByTier[siteId] or Config.SiteRelicsByTier.DustyDunes
	local pool = byTier[tier]
	while #pool == 0 and tier > 1 do
		tier -= 1
		pool = byTier[tier]
	end
	return pool[rng:NextInteger(1, #pool)], tier
end

-- Pure pity step: advances counters, applies the highest due guarantee, resets satisfied counters.
-- Returns the final tier and whether pity upgraded it.
function RollService.ApplyPity(pity: { number }, rolledTier: number, reroll: (minTier: number) -> number): (number, boolean)
	for i = 1, #Pity do
		pity[i] += 1
	end
	local tier = rolledTier
	local used = false
	-- Highest milestone wins, so hitting 200 and 25 together guarantees Legendary+.
	for i = #Pity, 1, -1 do
		local rule = Pity[i]
		if pity[i] >= rule.Every and tier < rule.MinTier then
			tier = reroll(rule.MinTier)
			used = true
			break
		end
	end
	for i, rule in Pity do
		if tier >= rule.MinTier then
			pity[i] = 0
		end
	end
	return tier, used
end

-- Rolls one relic into the player's data. The caller has already spent the tickets.
function RollService.Roll(data: PlayerData, siteId: string, luck: number?, rng: Random?): RollResult
	local random = rng or defaultRng
	local chances = Config.GetTierChances(luck or 1)
	local tier, pityUsed = RollService.ApplyPity(data.Pity, pickTier(random, chances, 1), function(minTier)
		return pickTier(random, chances, minTier)
	end)

	local relicId
	relicId, tier = pickRelic(random, siteId, tier)
	local isNew = not data.Discovered[relicId]
	data.TotalRolls += 1
	data.Inventory[relicId] = (data.Inventory[relicId] or 0) + 1
	data.Discovered[relicId] = true
	if tier > (data.Stats.BestTier or 1) then
		data.Stats.BestTier = tier
	end

	return { RelicId = relicId, Tier = tier, Pity = pityUsed, IsNew = isNew, Site = siteId }
end

-- A roll that touches no pity or stats, for rewards like heist loot. Returns relicId, tier.
function RollService.RollLoot(siteId: string, luck: number?, minTier: number?, rng: Random?): (string, number)
	local random = rng or defaultRng
	local chances = Config.GetTierChances(luck or 1)
	return pickRelic(random, siteId, pickTier(random, chances, minTier or 1))
end

return RollService
