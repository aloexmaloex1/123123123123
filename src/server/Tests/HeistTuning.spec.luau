--!strict
-- Shared heist tuning (FeatureConfig.Heist): vision cones, camera sweeps, rewards, energy and ranks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local Heist = require(ReplicatedStorage.RelicRNG.FeatureConfig.Heist) :: any
	local Sec = Heist.Security

	describe("InVision", function()
		local eye = Vector3.new(0, 5.6, 0)
		local look = Vector3.new(0, 0, -1)

		it("sees a thief straight ahead within range", function()
			expect((Heist.InVision(eye, look, Vector3.new(0, 3, -10), Sec.GuardRange, Sec.GuardMinDot))).to.equal(true)
		end)

		it("misses a thief behind, out of range or far above", function()
			expect((Heist.InVision(eye, look, Vector3.new(0, 3, 10), Sec.GuardRange, Sec.GuardMinDot))).to.equal(false)
			expect((Heist.InVision(eye, look, Vector3.new(0, 3, -(Sec.GuardRange + 1)), Sec.GuardRange, Sec.GuardMinDot))).to.equal(false)
			expect((Heist.InVision(eye, look, Vector3.new(0, 25, -10), Sec.GuardRange, Sec.GuardMinDot))).to.equal(false)
		end)

		it("shrinks the danger zone with Silent Shoes", function()
			local target = Vector3.new(0, 3, -(Sec.SilentRange + 2))
			expect((Heist.InVision(eye, look, target, Sec.GuardRange, Sec.GuardMinDot))).to.equal(true)
			expect((Heist.InVision(eye, look, target, Sec.SilentRange, Sec.GuardMinDot))).to.equal(false)
		end)
	end)

	describe("cameras", function()
		it("sweeps no further than CameraSweepDegrees either side", function()
			local limit = math.rad(Sec.CameraSweepDegrees) + 1e-9
			for elapsed = 0, 120, 0.25 do
				expect(math.abs(Heist.CameraYaw(1, 0.7, elapsed) - 1) <= limit).to.equal(true)
			end
		end)

		it("points camera heads down at the floor", function()
			local cf = Heist.CameraCFrame(Vector3.new(0, 12, 0), 0, math.rad(-Sec.CameraPitchDegrees))
			expect(cf.LookVector.Y < 0).to.equal(true)
		end)
	end)

	describe("Rewards", function()
		it("pays more for a ghost run and for time left on the clock", function()
			local base = Heist.Rewards("GildedGallery", 100, 60, 180, false, 5)
			local ghost = Heist.Rewards("GildedGallery", 100, 60, 180, true, 5)
			local fast = Heist.Rewards("GildedGallery", 100, 150, 180, false, 5)
			expect(ghost.Coins > base.Coins).to.equal(true)
			expect(ghost.Credits > base.Credits).to.equal(true)
			expect(ghost.Notoriety > base.Notoriety).to.equal(true)
			expect(fast.Coins > base.Coins).to.equal(true)
		end)

		it("never pays less than the base coins, even with negative income", function()
			for _, mapId in Heist.MapOrder do
				local reward = Heist.Rewards(mapId, -500, 0, 180, false, 1)
				expect(reward.Coins >= Heist.Maps[mapId].BaseCoins).to.equal(true)
				expect(reward.XP > 0).to.equal(true)
			end
		end)
	end)

	describe("RegenEnergy", function()
		local period = Heist.EnergyRegenSeconds

		it("adds one energy per full period and keeps the remainder", function()
			local energy, at = Heist.RegenEnergy(0, 1000, 3, 1000 + period * 2 + 30)
			expect(energy).to.equal(2)
			expect(at).to.equal(1000 + period * 2)
		end)

		it("never goes past the cap", function()
			local energy = Heist.RegenEnergy(1, 0, 3, period * 50)
			expect(energy).to.equal(3)
		end)
	end)

	describe("GetRank", function()
		it("ranks up exactly at each threshold", function()
			for i, rank in Heist.Ranks do
				local index = Heist.GetRank(rank.Min)
				expect(index).to.equal(i)
				if i > 1 then
					expect((Heist.GetRank(rank.Min - 1))).to.equal(i - 1)
				end
			end
		end)
	end)
end
