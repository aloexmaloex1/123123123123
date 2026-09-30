--!strict
-- Museum security: what an escaped thief can take, catch chances and the star rating.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local Config = require(ReplicatedStorage.RelicRNG.Config) :: any
	local Tuning = require(ReplicatedStorage.RelicRNG.FeatureConfig.Security) :: any
	local Security = require(script.Parent.Parent.Services.Security) :: any

	describe("StolenAmount", function()
		it("takes at most 5% of the player's coins", function()
			expect(Security.StolenAmount(1e9, 1000)).to.equal(50)
		end)

		it("takes at most 10 minutes of income", function()
			expect(Security.StolenAmount(20, 1e9)).to.equal(200)
		end)

		it("takes nothing from a broke or incomeless museum", function()
			expect(Security.StolenAmount(100, 0)).to.equal(0)
			expect(Security.StolenAmount(0, 5000)).to.equal(0)
		end)
	end)

	describe("GetCatchChance", function()
		it("rises with every level and clamps outside 0..MaxLevel", function()
			for level = 1, Tuning.MaxLevel do
				expect(Tuning.GetCatchChance(level) > Tuning.GetCatchChance(level - 1)).to.equal(true)
			end
			expect(Tuning.GetCatchChance(-5)).to.equal(Tuning.GetCatchChance(0))
			expect(Tuning.GetCatchChance(99)).to.equal(Tuning.GetCatchChance(Tuning.MaxLevel))
		end)

		it("has an upgrade price for every level below the max and none at the max", function()
			for level = 0, Tuning.MaxLevel - 1 do
				expect(Tuning.GetUpgradeCost(level) ~= nil).to.equal(true)
			end
			expect(Tuning.GetUpgradeCost(Tuning.MaxLevel)).to.equal(nil)
		end)
	end)

	describe("ComputeRating", function()
		it("gives an empty, unprotected museum one star", function()
			expect(Tuning.ComputeRating({}, 12, 0, Config).Stars).to.equal(1)
		end)

		it("gives a full museum of rare, varied relics at max security five stars", function()
			local displayed = {}
			local best = table.clone(Config.Relics)
			table.sort(best, function(a, b)
				return a.Tier > b.Tier
			end)
			for slot = 1, Tuning.Rating.DisplayedTarget do
				displayed[tostring(slot)] = best[slot].Id
			end
			expect(Tuning.ComputeRating(displayed, Tuning.Rating.DisplayedTarget, Tuning.MaxLevel, Config).Stars).to.equal(5)
		end)

		it("ignores relics on locked pedestals", function()
			local id = Config.Relics[1].Id
			local rating = Tuning.ComputeRating({ ["1"] = id, ["9"] = id }, 3, 0, Config)
			expect(rating.Parts[1].Value).to.equal(1)
		end)

		it("only ever reports whole or half stars between 1 and 5", function()
			for level = 0, Tuning.MaxLevel do
				local stars = Tuning.ComputeRating({}, 12, level, Config).Stars
				expect(stars >= 1 and stars <= 5 and (stars * 2) % 1 == 0).to.equal(true)
			end
		end)
	end)
end
