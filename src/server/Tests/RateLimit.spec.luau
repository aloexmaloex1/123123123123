--!strict
-- Token bucket behaviour with an explicit clock.
return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local RateLimit = require(script.Parent.Parent.RateLimit) :: any
	local fakePlayer = newproxy(false) :: any -- only used as a table key

	describe("Allow", function()
		it("allows the burst, then refuses", function()
			for _ = 1, 5 do
				expect(RateLimit.Allow(fakePlayer, "burst", 1, 5, 100)).to.equal(true)
			end
			expect(RateLimit.Allow(fakePlayer, "burst", 1, 5, 100)).to.equal(false)
		end)

		it("refills at the given rate", function()
			for _ = 1, 3 do
				RateLimit.Allow(fakePlayer, "refill", 2, 3, 0)
			end
			expect(RateLimit.Allow(fakePlayer, "refill", 2, 3, 0)).to.equal(false)
			expect(RateLimit.Allow(fakePlayer, "refill", 2, 3, 0.5)).to.equal(true)
			expect(RateLimit.Allow(fakePlayer, "refill", 2, 3, 0.5)).to.equal(false)
		end)

		it("keeps separate budgets per key", function()
			expect(RateLimit.Allow(fakePlayer, "a", 1, 1, 0)).to.equal(true)
			expect(RateLimit.Allow(fakePlayer, "b", 1, 1, 0)).to.equal(true)
			expect(RateLimit.Allow(fakePlayer, "a", 1, 1, 0)).to.equal(false)
		end)

		it("forgets a player on Clear", function()
			RateLimit.Allow(fakePlayer, "c", 1, 1, 0)
			RateLimit.Clear(fakePlayer)
			expect(RateLimit.Allow(fakePlayer, "c", 1, 1, 0)).to.equal(true)
		end)
	end)
end
