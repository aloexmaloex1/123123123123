--!strict
-- Minimal TestEZ-style runner for the pure-logic specs in this folder (describe / it / expect).
-- Run from Studio (Edit mode) with:
--   require(game.ServerScriptService.RelicRNG.Tests.TestRunner).run()
-- Specs cover pure logic only; live-state behaviour is tested with Services/CheatCommands in a playtest.

local TestRunner = {}

local function expect(value: any)
	return {
		to = {
			equal = function(other: any)
				if value ~= other then
					error(`expected {tostring(other)}, got {tostring(value)}`, 2)
				end
			end,
			be = {
				ok = function()
					if not value then
						error(`expected a truthy value, got {tostring(value)}`, 2)
					end
				end,
				near = function(other: number, limit: number?)
					if math.abs(value - other) > (limit or 1e-7) then
						error(`expected {value} to be within {limit or 1e-7} of {other}`, 2)
					end
				end,
			},
			throw = function()
				if pcall(value) then
					error("expected the function to throw", 2)
				end
			end,
		},
	}
end

function TestRunner.run(): string
	local passed, failed = 0, 0
	local lines: { string } = {}
	local prefix: { string } = {}

	local env = {
		expect = expect,
		describe = function(name: string, fn: () -> ())
			table.insert(prefix, name)
			fn()
			table.remove(prefix)
		end,
		it = function(name: string, fn: () -> ())
			local ok, err = pcall(fn)
			if ok then
				passed += 1
			else
				failed += 1
				table.insert(lines, `FAIL {table.concat(prefix, " > ")} > {name}: {err}`)
			end
		end,
	}

	for _, module in script.Parent:GetChildren() do
		if module:IsA("ModuleScript") and module.Name:match("%.spec$") then
			-- Clone so each run gets fresh module state.
			local copy = module:Clone()
			copy.Parent = module.Parent
			local ok, specOrErr = pcall(require, copy)
			if not ok then
				failed += 1
				table.insert(lines, `FAIL {module.Name} failed to load: {specOrErr}`)
			else
				table.insert(prefix, module.Name)
				local ranOk, runErr = pcall(specOrErr, env)
				table.remove(prefix)
				if not ranOk then
					failed += 1
					table.insert(lines, `FAIL {module.Name} crashed: {runErr}`)
				end
			end
			copy:Destroy() -- only after running: specs resolve modules via script.Parent
		end
	end
	table.insert(lines, 1, `{passed} passed, {failed} failed`)
	return table.concat(lines, "\n")
end

return TestRunner
