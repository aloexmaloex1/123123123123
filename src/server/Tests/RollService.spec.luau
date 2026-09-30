--!strict
-- Seeded checks for rolling: pity guarantees, odds over many rolls, loot minimum tiers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local Config = require(ReplicatedStorage.RelicRNG.Config) :: any
	local RollService = require(script.Parent.Parent.RollService) :: any

	local function freshData()
		return {
			Pity = { 0, 0, 0, 0 },
			Inventory = {},
			Discovered = {},
			TotalRolls = 0,
			Stats = { TotalEarned = 0, BestTier = 1 },
		}
	end

	describe("ApplyPity", function()
		it("upgrades exactly on the Every-th roll without a qualifying tier", function()
			for index, rule in Config.Pity do
				local pity = { 0, 0, 0, 0 }
				pity[index] = rule.Every - 1
				local tier, used = RollService.ApplyPity(pity, 1, function(minTier)
					return minTier
				end)
				expect(used).to.equal(true)
				expect(tier).to.equal(rule.MinTier)
				expect(pity[index]).to.equal(0)
			end
		end)

		it("does not fire one roll early", function()
			local pity = { 23, 0, 0, 0 }
			local tier, used = RollService.ApplyPity(pity, 1, function(minTier)
				return minTier
			end)
			expect(used).to.equal(false)
			expect(tier).to.equal(1)
			expect(pity[1]).to.equal(24)
		end)

		it("prefers the highest due milestone and resets every satisfied counter", function()
			local pity = { 24, 74, 199, 0 }
			local tier, used = RollService.ApplyPity(pity, 1, function(minTier)
				return minTier
			end)
			expect(used).to.equal(true)
			expect(tier).to.equal(5)
			expect(pity[1]).to.equal(0)
			expect(pity[2]).to.equal(0)
			expect(pity[3]).to.equal(0)
			expect(pity[4]).to.equal(1)
		end)

		it("leaves a naturally lucky roll alone", function()
			local pity = { 24, 0, 0, 0 }
			local tier, used = RollService.ApplyPity(pity, 6, function()
				error("should not reroll")
			end)
			expect(used).to.equal(false)
			expect(tier).to.equal(6)
			expect(pity[1]).to.equal(0)
		end)
	end)

	describe("Roll (seeded)", function()
		it("never lets any pity counter reach its limit over 30,000 rolls", function()
			local data = freshData()
			local rng = Random.new(42)
			for _ = 1, 30000 do
				RollService.Roll(data, "DustyDunes", 1, rng)
				for index, rule in Config.Pity do
					expect(data.Pity[index] < rule.Every).to.be.ok()
				end
			end
			expect(data.TotalRolls).to.equal(30000)
		end)

		it("lands close to the published odds at luck 1", function()
			local data = freshData()
			local rng = Random.new(7)
			local counts = {}
			local n = 60000
			for _ = 1, n do
				local result = RollService.Roll(data, "DustyDunes", 1, rng)
				counts[result.Tier] = (counts[result.Tier] or 0) + 1
			end
			expect((counts[1] or 0) / n * 100).to.be.near(45, 1.5)
			expect((counts[2] or 0) / n * 100).to.be.near(25, 1.5)
			expect((counts[3] or 0) / n * 100).to.be.near(14, 1.5)
		end)

		it("records inventory, discovery and best tier", function()
			local data = freshData()
			local result = RollService.Roll(data, "DustyDunes", 1, Random.new(1))
			expect(data.Inventory[result.RelicId]).to.equal(1)
			expect(data.Discovered[result.RelicId]).to.equal(true)
			expect(result.IsNew).to.equal(true)
		end)
	end)

	describe("RollLoot", function()
		it("respects the minimum tier", function()
			local rng = Random.new(99)
			for _ = 1, 2000 do
				local relicId, tier = RollService.RollLoot("DustyDunes", 1, 4, rng)
				expect(tier >= 4).to.be.ok()
				expect(Config.RelicsById[relicId].Tier).to.equal(tier)
			end
		end)
	end)
end
