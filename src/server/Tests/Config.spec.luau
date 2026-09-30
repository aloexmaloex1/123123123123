--!strict
-- Pure-logic checks for the shared Config: odds, luck, content integrity and the level curve.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local Config = require(ReplicatedStorage.RelicRNG.Config) :: any

	describe("GetTierChances", function()
		it("sums to 100 at every luck from 1 to 20", function()
			for luck = 1, 20, 0.5 do
				local total = 0
				for _, chance in Config.GetTierChances(luck) do
					total += chance
				end
				expect(total).to.be.near(100, 1e-6)
			end
		end)

		it("matches the design doc table at luck 1", function()
			local chances = Config.GetTierChances(1)
			local expected = { 45, 25, 14, 8, 4.5, 2, 0.9, 0.35, 0.2, 0.05 }
			for tier, value in expected do
				expect(chances[tier]).to.be.near(value, 1e-9)
			end
		end)

		it("never lowers a lucky tier's chance as luck rises", function()
			local previous = Config.GetTierChances(1)
			for luck = 1.5, 10, 0.5 do
				local current = Config.GetTierChances(luck)
				for tier = Config.LuckMinTier, #Config.Rarities do
					expect(current[tier] >= previous[tier]).to.be.ok()
				end
				previous = current
			end
		end)
	end)

	describe("content", function()
		it("has unique relic ids and every relic's site exists", function()
			local seen = {}
			for _, relic in Config.Relics do
				expect(seen[relic.Id]).to.equal(nil)
				seen[relic.Id] = true
				expect(Config.DigSites[relic.Site] ~= nil).to.be.ok()
				expect(Config.Rarities[relic.Tier] ~= nil).to.be.ok()
			end
		end)

		it("gives the starter site at least one relic in every tier", function()
			for tier in Config.Rarities do
				expect(#Config.SiteRelicsByTier.DustyDunes[tier] > 0).to.be.ok()
			end
		end)

		it("only references real relics in collection sets", function()
			for _, set in Config.Sets do
				for _, relicId in set.Relics do
					expect(Config.RelicsById[relicId] ~= nil).to.be.ok()
				end
			end
		end)

		it("puts every site centre inside its own zone", function()
			for siteId, site in Config.DigSites do
				expect(Config.SiteAt(site.Center)).to.equal(siteId)
			end
		end)

		it("gives relic chances that sum back to the tier chance", function()
			for tier in Config.Rarities do
				local pool = Config.SiteRelicsByTier.DustyDunes[tier]
				local total = 0
				for _, relicId in pool do
					total += Config.GetRelicChance(relicId, 1)
				end
				expect(total).to.be.near(Config.GetTierChances(1)[tier], 1e-9)
			end
		end)
	end)

	describe("XPForLevel", function()
		it("is positive and strictly increasing up to level 200", function()
			local previous = 0
			for level = 1, 200 do
				local xp = Config.XPForLevel(level)
				expect(xp > previous).to.be.ok()
				previous = xp
			end
		end)
	end)

	describe("FormatNumber / Abbreviate", function()
		it("formats with thousands separators", function()
			expect(Config.FormatNumber(0)).to.equal("0")
			expect(Config.FormatNumber(1234567)).to.equal("1,234,567")
			expect(Config.FormatNumber(999)).to.equal("999")
			expect(Config.FormatNumber(-1234)).to.equal("-1,234")
		end)

		it("abbreviates large numbers", function()
			expect(Config.Abbreviate(950)).to.equal("950")
			expect(Config.Abbreviate(1500)).to.equal("1.5K")
			expect(Config.Abbreviate(1234567)).to.equal("1.23M")
		end)
	end)
end
