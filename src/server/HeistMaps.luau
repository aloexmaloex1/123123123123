-- Heist map layouts (ASCII grids) plus the pure helpers that read them: parsing, guard pathfinding
-- and laser geometry. Services.Heist builds the 3D museum from a parsed layout at runtime.
--
-- Legend (one cell = CellSize studs):
--   #  wall                 .  floor               E  entry / exit (one per map)
--   T  target pedestal      L  blinking laser      P  pressure plate
--   S  sticky floor         C  wall camera (a wall cell; faces its longest open side unless overridden)
--   G  guard start          o  display case with a decoy relic (blocks sight)
-- Patrols list waypoint cells {column, row} for each G in reading order (left to right, top to bottom).
local rgb = Color3.fromRGB

local HeistMaps = {
	CellSize = 10,
	WallHeight = 16,
	LaserHeights = { 1.2, 3, 4.8, 6.6, 8.4 },
	LaserHalfThickness = 1.3,
}

HeistMaps.Legend = {
	["#"] = "Wall", ["."] = "Floor", E = "Entry", T = "Target", L = "Laser", P = "Plate",
	S = "Sticky", C = "Camera", G = "Guard", o = "Decor",
}

HeistMaps.Maps = {
	GildedGallery = {
		Seed = 11,
		Grid = {
			"###################",
			"#o.....o#o...T...o#",
			"#.......#.........#",
			"#...G...L.........#",
			"#.......#....P....#",
			"#o..P..o#o...G...o#",
			"####.###C###S######",
			"#.................#",
			"#.o.............o.#",
			"#.................#",
			"########.##########",
			"########L##########",
			"########.##########",
			"########E##########",
			"###################",
		},
		Patrols = {
			{ { 3, 3 }, { 7, 3 }, { 7, 5 }, { 3, 5 } },
			{ { 11, 3 }, { 17, 3 }, { 17, 5 }, { 11, 5 } },
		},
		PaintingChance = 0.3,
		Palette = {
			-- Warm wood floor, deep burgundy walls and gold trim so it reads as "gilded".
			Floor1 = rgb(112, 76, 46), Floor2 = rgb(88, 58, 36), FloorMaterial = Enum.Material.WoodPlanks, Grout = rgb(34, 22, 14),
			Wall = rgb(118, 52, 50), Wainscot = rgb(62, 34, 26), WallMaterial = Enum.Material.Plaster,
			Cap = rgb(176, 134, 58), Rail = rgb(236, 190, 92), Trim = rgb(255, 196, 84),
			Ceiling = rgb(52, 36, 28), Light = rgb(255, 224, 176), Accent = rgb(255, 200, 80), Pedestal = rgb(92, 62, 46),
		},
		TargetRelic = { Name = "The Gilded Sun Idol", Shape = "Idol", Color = rgb(255, 196, 60) },
		DecorColors = { rgb(90, 200, 255), rgb(255, 120, 80), rgb(120, 255, 170), rgb(220, 120, 255), rgb(255, 220, 120) },
	},
	ObsidianVault = {
		Seed = 23,
		Grid = {
			"#######################",
			"#o...o#o....T....o#o..#",
			"#.....#...........#...#",
			"#..G..#o..P...P..o#.G.#",
			"#.....###L##C##L###...#",
			"#.....................#",
			"#o...S....o.o....S...o#",
			"#..........G..........#",
			"####L####.....####L####",
			"#o.....##.....##.....o#",
			"#.......C..P..C.......#",
			"#...G...#.....#...G...#",
			"#o......L..E..L......o#",
			"#######################",
		},
		CameraFacing = { ["13,5"] = "N" },
		Patrols = {
			{ { 4, 3 }, { 4, 7 }, { 9, 7 }, { 4, 7 } },
			{ { 21, 3 }, { 21, 7 }, { 15, 7 }, { 21, 7 } },
			{ { 3, 8 }, { 21, 8 }, { 21, 6 }, { 3, 6 } },
			{ { 3, 11 }, { 7, 11 }, { 7, 13 }, { 3, 13 } },
			{ { 17, 11 }, { 21, 11 }, { 21, 13 }, { 17, 13 } },
		},
		PaintingChance = 0.22,
		Palette = {
			Floor1 = rgb(16, 17, 26), Floor2 = rgb(24, 26, 38), FloorMaterial = Enum.Material.Slate, Grout = rgb(6, 7, 10),
			Wall = rgb(20, 20, 30), Wainscot = rgb(10, 11, 16), WallMaterial = Enum.Material.Slate,
			Cap = rgb(40, 45, 60), Rail = rgb(80, 150, 230), Trim = rgb(40, 150, 255),
			Ceiling = rgb(8, 8, 12), Light = rgb(160, 195, 255), Accent = rgb(90, 200, 255), Pedestal = rgb(26, 28, 40),
		},
		TargetRelic = { Name = "The Obsidian Heart", Shape = "Ball", Color = rgb(40, 16, 70) },
		DecorColors = { rgb(90, 200, 255), rgb(170, 90, 255), rgb(60, 255, 190), rgb(255, 80, 120) },
	},
	SkyPalace = {
		Seed = 37,
		Grid = {
			"#############################",
			"#o...o#o......T......o#o...o#",
			"#.....#.G.............#.....#",
			"#..G..#....P.....P....#..G..#",
			"#.....##L####C#C####L##.....#",
			"#...S.........S.........S...#",
			"#o.......G.........G.......o#",
			"######.#####L###L#####.######",
			"#o.........................o#",
			"#...o.....o.......o.....o...#",
			"#.......P....G.....P........#",
			"#o.........................o#",
			"############C...C############",
			"#############LLL#############",
			"#############.P.#############",
			"#############S.S#############",
			"#############LLL#############",
			"##############E##############",
			"#############################",
		},
		CameraFacing = { ["14,5"] = "N", ["16,5"] = "S" },
		Patrols = {
			{ { 9, 3 }, { 21, 3 }, { 21, 4 }, { 9, 4 } },
			{ { 3, 3 }, { 3, 6 }, { 6, 6 }, { 6, 3 } },
			{ { 24, 3 }, { 27, 3 }, { 27, 6 }, { 24, 6 } },
			{ { 3, 7 }, { 14, 7 } },
			{ { 16, 7 }, { 27, 7 } },
			{ { 3, 9 }, { 27, 9 }, { 27, 12 }, { 3, 12 } },
		},
		PaintingChance = 0.2,
		Palette = {
			Floor1 = rgb(30, 28, 50), Floor2 = rgb(42, 40, 68), FloorMaterial = Enum.Material.Marble, Grout = rgb(10, 9, 18),
			Wall = rgb(38, 32, 62), Wainscot = rgb(20, 17, 36), WallMaterial = Enum.Material.Plaster,
			Cap = rgb(150, 150, 185), Rail = rgb(200, 210, 255), Trim = rgb(110, 235, 255),
			Ceiling = rgb(14, 12, 26), Light = rgb(205, 220, 255), Accent = rgb(190, 150, 255), Pedestal = rgb(52, 48, 80),
		},
		TargetRelic = { Name = "The Crown of the Sky Palace", Shape = "Crown", Color = rgb(200, 240, 255) },
		DecorColors = { rgb(140, 230, 255), rgb(255, 225, 140), rgb(200, 140, 255), rgb(255, 150, 200), rgb(140, 255, 200) },
	},
}

---------------------------------------------------------------- grid helpers

HeistMaps.Dirs = { N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }
HeistMaps.DirOrder = { "S", "N", "E", "W" }

local WALL = { ["#"] = true, C = true }
local GUARD_BLOCKED = { ["#"] = true, C = true, o = true, T = true }

function HeistMaps.Get(layout, c, r)
	local row = layout.Cells[r]
	return row and row[c] or "#"
end

function HeistMaps.IsWall(ch)
	return WALL[ch] == true
end

function HeistMaps.GuardWalkable(layout, c, r)
	return not GUARD_BLOCKED[HeistMaps.Get(layout, c, r)]
end

-- Number of open (non-wall) cells in a straight line from (c, r) in direction dir.
local function openRun(layout, c, r, dir)
	local d = HeistMaps.Dirs[dir]
	local n = 0
	c, r = c + d[1], r + d[2]
	while not WALL[HeistMaps.Get(layout, c, r)] do
		n += 1
		c, r = c + d[1], r + d[2]
	end
	return n
end

function HeistMaps.BestFacing(layout, c, r)
	local best, bestRun = nil, 0
	for _, dir in ipairs(HeistMaps.DirOrder) do
		local run = openRun(layout, c, r, dir)
		if run > bestRun then
			best, bestRun = dir, run
		end
	end
	return best
end

-- Breadth-first path over guard-walkable cells. Returns a list of {c, r} from the step after `from`
-- up to and including `to` (the goal cell is always enterable), or nil if unreachable.
function HeistMaps.FindPath(layout, from, to, walkable)
	walkable = walkable or HeistMaps.GuardWalkable
	local w = layout.Width
	local function key(c, r)
		return (r - 1) * w + c
	end
	local startKey, goalKey = key(from[1], from[2]), key(to[1], to[2])
	if startKey == goalKey then
		return { { to[1], to[2] } }
	end
	local cameFrom = { [startKey] = 0 }
	local queue, head = { { from[1], from[2] } }, 1
	while head <= #queue do
		local cell = queue[head]
		head += 1
		for _, dir in ipairs(HeistMaps.DirOrder) do
			local d = HeistMaps.Dirs[dir]
			local nc, nr = cell[1] + d[1], cell[2] + d[2]
			if nc >= 1 and nr >= 1 and nc <= w and nr <= layout.Height then
				local k = key(nc, nr)
				if cameFrom[k] == nil and (k == goalKey or walkable(layout, nc, nr)) then
					cameFrom[k] = key(cell[1], cell[2])
					if k == goalKey then
						local path, at = {}, k
						while at ~= startKey do
							table.insert(path, 1, { (at - 1) % w + 1, (at - 1) // w + 1 })
							at = cameFrom[at]
						end
						return path
					end
					table.insert(queue, { nc, nr })
				end
			end
		end
	end
	return nil
end

local function playerWalkable(layout, c, r)
	return not WALL[HeistMaps.Get(layout, c, r)]
end

---------------------------------------------------------------- parsing

-- Turns a map spec into a layout table and validates it (widths, symbols, entry/target, reachability, patrols).
function HeistMaps.Parse(spec)
	local grid = spec.Grid
	local width = #grid[1]
	local layout = {
		Width = width, Height = #grid, Cells = {},
		Guards = {}, Cameras = {}, Lasers = {}, Plates = {}, Sticky = {}, Decor = {}, Floor = {},
	}
	for r, row in ipairs(grid) do
		assert(#row == width, ("row %d is %d wide, expected %d"):format(r, #row, width))
		layout.Cells[r] = {}
		for c = 1, width do
			local ch = row:sub(c, c)
			assert(HeistMaps.Legend[ch], ("unknown symbol '%s' at %d,%d"):format(ch, c, r))
			layout.Cells[r][c] = ch
			local cell = { c, r }
			if ch == "E" then
				assert(not layout.Entry, "more than one entry")
				layout.Entry = cell
			elseif ch == "T" then
				assert(not layout.Target, "more than one target")
				layout.Target = cell
			elseif ch == "G" then
				table.insert(layout.Guards, cell)
			elseif ch == "C" then
				table.insert(layout.Cameras, cell)
			elseif ch == "L" then
				table.insert(layout.Lasers, cell)
			elseif ch == "P" then
				table.insert(layout.Plates, cell)
			elseif ch == "S" then
				table.insert(layout.Sticky, cell)
			elseif ch == "o" then
				table.insert(layout.Decor, cell)
			end
			if not WALL[ch] then
				table.insert(layout.Floor, cell)
			end
		end
	end
	assert(layout.Entry, "map has no entry (E)")
	assert(layout.Target, "map has no target (T)")
	assert(HeistMaps.FindPath(layout, layout.Entry, layout.Target, playerWalkable), "target is unreachable from the entry")

	-- Cameras face their longest open side unless the spec overrides it.
	for _, cam in ipairs(layout.Cameras) do
		local override = spec.CameraFacing and spec.CameraFacing[cam[1] .. "," .. cam[2]]
		cam[3] = override or HeistMaps.BestFacing(layout, cam[1], cam[2])
		assert(cam[3] and HeistMaps.Dirs[cam[3]], ("camera at %d,%d has no open side"):format(cam[1], cam[2]))
		local d = HeistMaps.Dirs[cam[3]]
		assert(not WALL[HeistMaps.Get(layout, cam[1] + d[1], cam[2] + d[2])], ("camera at %d,%d faces a wall"):format(cam[1], cam[2]))
	end

	-- Lasers span their cell across the corridor they block. Touching laser cells blink together.
	local function spans(ch)
		return WALL[ch] or ch == "L"
	end
	local groupOf = {}
	local groups = 0
	for _, laser in ipairs(layout.Lasers) do
		local c, r = laser[1], laser[2]
		local get = function(dc, dr)
			return HeistMaps.Get(layout, c + dc, r + dr)
		end
		if spans(get(-1, 0)) and spans(get(1, 0)) then
			laser[3] = "X"
		elseif spans(get(0, -1)) and spans(get(0, 1)) then
			laser[3] = "Z"
		else
			laser[3] = "X"
		end
		local k = c .. "," .. r
		if not groupOf[k] then
			groups += 1
			local stack = { { c, r } }
			groupOf[k] = groups
			while #stack > 0 do
				local cell = table.remove(stack)
				for _, dir in ipairs(HeistMaps.DirOrder) do
					local d = HeistMaps.Dirs[dir]
					local nc, nr = cell[1] + d[1], cell[2] + d[2]
					local nk = nc .. "," .. nr
					if HeistMaps.Get(layout, nc, nr) == "L" and not groupOf[nk] then
						groupOf[nk] = groups
						table.insert(stack, { nc, nr })
					end
				end
			end
		end
		laser[4] = groupOf[k]
	end
	layout.LaserGroups = groups

	local patrols = spec.Patrols or {}
	assert(#patrols == #layout.Guards, ("%d guards but %d patrols"):format(#layout.Guards, #patrols))
	for i, patrol in ipairs(patrols) do
		assert(#patrol >= 1, "empty patrol " .. i)
		local prev = layout.Guards[i]
		for _, wp in ipairs(patrol) do
			assert(HeistMaps.GuardWalkable(layout, wp[1], wp[2]), ("patrol %d waypoint %d,%d is not walkable"):format(i, wp[1], wp[2]))
			assert(HeistMaps.FindPath(layout, prev, wp), ("patrol %d can't reach %d,%d"):format(i, wp[1], wp[2]))
			prev = wp
		end
	end
	layout.Patrols = patrols
	return layout
end

---------------------------------------------------------------- geometry

-- Did a player moving from `prev` to `cur` touch a laser centred at `center` whose beams run along `axis`?
-- Sweeps the move so fast runners can't skip through between detection ticks.
function HeistMaps.CrossesLaser(center, axis, prev, cur)
	local half = HeistMaps.CellSize / 2
	local function split(p)
		local o = p - center
		if axis == "X" then
			return o.X, o.Z
		end
		return o.Z, o.X
	end
	local latC, sC = split(cur)
	local latP, sP = split(prev)
	if math.abs(latC) > half and math.abs(latP) > half then
		return false
	end
	local dy = cur.Y - center.Y
	if dy < -1 or dy > 13 then
		return false
	end
	if math.abs(sC) <= HeistMaps.LaserHalfThickness then
		return true
	end
	return (sP < 0) ~= (sC < 0) and math.abs(sP - sC) < HeistMaps.CellSize
end

-- Shortest player-walkable route between two cells in studs (cell-centre steps), or nil.
function HeistMaps.PlayerPathStuds(layout, from, to)
	local path = HeistMaps.FindPath(layout, from, to, playerWalkable)
	return path and #path * HeistMaps.CellSize or nil
end

---------------------------------------------------------------- anti-cheat (server only)

-- Movement plausibility for heists. The client owns its character's physics, so the server samples the
-- root position every detection tick and checks it against how far the character could have walked.
HeistMaps.AntiCheat = {
	SpeedFactor = 1.5, -- allowed horizontal speed = WalkSpeed x this
	BankSeconds = 1.2, -- unused movement allowance that may be saved up (absorbs network bursts)
	Slack = 4, -- studs of extra allowance on top of the bank
	NoclipMinDepth = 1.5, -- a move must pass this deep through map.Solid to count as noclip
	TeleportGrace = 0.8, -- seconds after a server teleport where stale far-away samples are ignored
	Strikes = 4, -- implausible moves within StrikeWindow before the heist fails as "Caught"
	StrikeWindow = 12,
	MinPathFraction = 0.6, -- steal / escape can't happen faster than this share of the shortest walk
	HoldSlack = 0.25, -- seconds of network slack on the server-checked steal hold
}

-- Map reuse: finished museums are reset and kept for the next heist on the same map.
HeistMaps.PoolMaps = true
HeistMaps.PoolPerMap = 2

-- Largest movement allowance (studs) a character walking at `speed` may bank.
function HeistMaps.MoveBudgetCap(speed, cfg)
	return speed * cfg.SpeedFactor * cfg.BankSeconds + cfg.Slack
end

-- Token bucket for horizontal movement. Refills at speed x SpeedFactor per second up to the cap and
-- spends the distance moved. Returns newBudget, tooFast. On tooFast the budget is refilled to the cap
-- (the caller rubber-bands the character back).
function HeistMaps.StepMoveBudget(budget, elapsed, speed, distance, cfg)
	local cap = HeistMaps.MoveBudgetCap(speed, cfg)
	if distance ~= distance or elapsed ~= elapsed then
		return cap, true
	end
	budget = math.min(cap, budget + speed * cfg.SpeedFactor * math.max(0, elapsed)) - distance
	if budget < 0 then
		return cap, true
	end
	return budget, false
end

return HeistMaps
