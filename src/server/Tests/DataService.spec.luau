--!strict
-- Schema migration checks against fixture records (no DataStore calls are made).
return function(t: any)
	local describe, it, expect = t.describe, t.it, t.expect
	local DataService = require(script.Parent.Parent.DataService) :: any
	local normalise = DataService._normalise

	describe("normalise / migrations", function()
		it("treats an empty key as a new player", function()
			expect(normalise(nil)).to.equal(nil)
		end)

		it("wraps a schema-1 bare data table without losing fields", function()
			local legacy = { Coins = 123, Level = 7, Inventory = { rusty_coin = 2 } }
			local record = normalise(legacy)
			expect(record.Schema).to.equal(2)
			expect(record.Data.Coins).to.equal(123)
			expect(record.Data.Level).to.equal(7)
			expect(record.Data.Inventory.rusty_coin).to.equal(2)
			expect(record.Lock).to.equal(nil)
		end)

		it("passes a current record through unchanged", function()
			local current = { Schema = 2, Data = { Coins = 5 }, Lock = { JobId = "x", Time = 1 } }
			local record = normalise(current)
			expect(record.Data.Coins).to.equal(5)
			expect(record.Lock.JobId).to.equal("x")
		end)

		it("refuses data written by a newer server", function()
			expect(function()
				normalise({ Schema = 999, Data = {} })
			end).to.throw()
		end)

		it("refuses a corrupt non-table value", function()
			expect(function()
				normalise("garbage")
			end).to.throw()
		end)
	end)
end
