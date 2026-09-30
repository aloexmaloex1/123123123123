--!strict
-- Heist map layouts and the anti-cheat geometry: every map parses and is winnable, lasers catch a runner
-- between detection ticks, and the movement budget allows walking but refuses teleports.
return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local HeistMaps = require(script.Parent.Parent.HeistMaps) :: any
	local AC = HeistMaps.AntiCheat

	describe("Parse", function()
		it("parses every map with a walkable route from the entry to the target and back", function()
			for _, spec in HeistMaps.Maps do
				local layout = HeistMaps.Parse(spec)
				expect(HeistMaps.PlayerPathStuds(layout, layout.Entry, layout.Target) ~= nil).to.equal(true)
				expect(HeistMaps.PlayerPathStuds(layout, layout.Target, layout.Entry) ~= nil).to.equal(true)
			end
		end)

		it("gives every guard a patrol and every laser an axis and a blink group", function()
			for _, spec in HeistMaps.Maps do
				local layout = HeistMaps.Parse(spec)
				expect(#layout.Patrols).to.equal(#layout.Guards)
				for _, laser in layout.Lasers do
					expect(laser[3] == "X" or laser[3] == "Z").to.equal(true)
					expect(laser[4] >= 1 and laser[4] <= layout.LaserGroups).to.equal(true)
				end
			end
		end)

		it("rejects a map without an entry", function()
			expect(function()
				HeistMaps.Parse({ Grid = { "###", "#T#", "###" }, Patrols = {} })
			end).to.throw()
		end)

		it("rejects a target that is walled off from the entry", function()
			expect(function()
				HeistMaps.Parse({ Grid = { "#####", "#E#T#", "#####" }, Patrols = {} })
			end).to.throw()
		end)
	end)

	describe("CrossesLaser", function()
		local center = Vector3.new(5, 0, 5)
		local function at(along: number, height: number, across: number): Vector3
			-- Axis "X": beams run along X, so crossing the gate means moving in Z.
			return center + Vector3.new(along, height, across)
		end

		it("catches a thief standing in the beams", function()
			local p = at(1, 3, 0.5)
			expect(HeistMaps.CrossesLaser(center, "X", p, p)).to.equal(true)
		end)

		it("catches a sprint that jumps the gate between two ticks", function()
			expect(HeistMaps.CrossesLaser(center, "X", at(0, 3, -3), at(0, 3, 3))).to.equal(true)
		end)

		it("ignores walking alongside the gate", function()
			expect(HeistMaps.CrossesLaser(center, "X", at(-4, 3, 3), at(4, 3, 3))).to.equal(false)
		end)

		it("ignores moves in the next cell over", function()
			expect(HeistMaps.CrossesLaser(center, "X", at(7, 3, -3), at(7, 3, 3))).to.equal(false)
		end)
	end)

	describe("StepMoveBudget", function()
		local speed = 16
		local cap = HeistMaps.MoveBudgetCap(speed, AC)

		it("lets a character walk at full speed indefinitely", function()
			local budget = cap
			for _ = 1, 100 do
				local tooFast
				budget, tooFast = HeistMaps.StepMoveBudget(budget, 0.1, speed, speed * 0.1, AC)
				expect(tooFast).to.equal(false)
			end
		end)

		it("absorbs one network burst but not a second one right after", function()
			local burst = cap - 2
			local budget, tooFast = HeistMaps.StepMoveBudget(cap, 0.1, speed, burst, AC)
			expect(tooFast).to.equal(false)
			_, tooFast = HeistMaps.StepMoveBudget(budget, 0.1, speed, burst, AC)
			expect(tooFast).to.equal(true)
		end)

		it("refuses a teleport and refills the budget for the rubber-band", function()
			local budget, tooFast = HeistMaps.StepMoveBudget(cap, 0.1, speed, 60, AC)
			expect(tooFast).to.equal(true)
			expect(budget).to.equal(cap)
		end)

		it("treats a NaN distance as a violation", function()
			local _, tooFast = HeistMaps.StepMoveBudget(cap, 0.1, speed, 0 / 0, AC)
			expect(tooFast).to.equal(true)
		end)
	end)
end
