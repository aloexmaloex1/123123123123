-- Global leaderboards: writes each player's stats to OrderedDataStores on a throttle (and on leave)
-- and draws the top 10 on the standing boards in Workspace.RelicRNG.Leaderboards.
-- If DataStores are unavailable (e.g. Studio without API access) it warns once and shows this server's players.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Leaderboards = {}

local WRITE_INTERVAL = 180 -- seconds between a player's leaderboard writes
local REFRESH_INTERVAL = 180 -- seconds between board refreshes
local FIRST_REFRESH = 8
local TOP = 10
local EMPTY_COLOR = Color3.fromRGB(110, 108, 104)
local NAME_COLOR = Color3.fromRGB(240, 236, 225)
local MEDALS = { Color3.fromRGB(245, 200, 60), Color3.fromRGB(200, 205, 215), Color3.fromRGB(205, 127, 50) }

-- The heist feature saves notoriety at data.Heist.Notoriety.
local function notoriety(data)
	local heist = data.Heist
	return type(heist) == "table" and tonumber(heist.Notoriety) or 0
end

-- Board definitions; Id matches the model name in Workspace.RelicRNG.Leaderboards.
function Leaderboards.Boards(Config)
	return {
		{ Id = "Richest", Store = "RelicRNG_LB_Richest_v1", Get = function(data)
			return data.Stats.TotalEarned
		end, Format = function(v)
			return Config.Abbreviate(v)
		end },
		{ Id = "Level", Store = "RelicRNG_LB_Level_v1", Get = function(data)
			return data.Level
		end, Format = function(v)
			return "Lv " .. Config.FormatNumber(v)
		end },
		{ Id = "Rarest", Store = "RelicRNG_LB_Rarest_v1", Get = function(data)
			return data.Stats.BestTier
		end, Format = function(v)
			local rarity = Config.Rarities[v]
			return rarity and rarity.Name or "-", rarity and rarity.Color
		end },
		{ Id = "Heist", Store = "RelicRNG_LB_Heist_v1", Get = notoriety, Format = function(v)
			return Config.Abbreviate(v)
		end },
	}
end

-- OrderedDataStores only take non-negative whole numbers.
function Leaderboards.Clean(value)
	value = tonumber(value) or 0
	if value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, 2 ^ 53)
end

function Leaderboards.Init(core)
	local Config = core.Config
	local boards = Leaderboards.Boards(Config)
	local folder = workspace:WaitForChild("RelicRNG"):FindFirstChild("Leaderboards")

	local warned = false
	local function warnOnce(message)
		if not warned then
			warned = true
			warn("[RelicRNG] Leaderboards: " .. message .. " (showing this server's players instead)")
		end
	end

	for _, board in ipairs(boards) do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.Store)
		end)
		if ok then
			board.OrderedStore = store
		else
			warnOnce(tostring(store))
		end
	end

	---------------------------------------------------------------- names

	local nameCache = {}
	local function nameFor(userId)
		if nameCache[userId] then
			return nameCache[userId]
		end
		local player = Players:GetPlayerByUserId(userId)
		if player then
			nameCache[userId] = player.Name
			return player.Name
		end
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if ok and name then
			nameCache[userId] = name
			return name
		end
		return "Player"
	end

	---------------------------------------------------------------- writing

	local function writePlayer(userId, values, written)
		for _, board in ipairs(boards) do
			local value = values[board.Id]
			if board.OrderedStore and value and written[board.Id] ~= value then
				local ok, err = pcall(function()
					board.OrderedStore:SetAsync(tostring(userId), value)
				end)
				if ok then
					written[board.Id] = value
				else
					warnOnce(tostring(err))
				end
			end
		end
	end

	local function collect(data)
		local values = {}
		for _, board in ipairs(boards) do
			local ok, value = pcall(board.Get, data)
			values[board.Id] = ok and Leaderboards.Clean(value) or nil
		end
		return values
	end

	core.Hook("Tick", function(player, profile)
		local session = profile.Session
		local now = os.clock()
		if not session.LeaderboardNextWrite then
			session.LeaderboardNextWrite = now + math.random(30, 90)
			session.LeaderboardWritten = {}
			return
		end
		if now >= session.LeaderboardNextWrite and not session.LeaderboardWriting then
			session.LeaderboardNextWrite = now + WRITE_INTERVAL
			session.LeaderboardWriting = true
			local values = collect(profile.Data)
			task.spawn(function()
				writePlayer(player.UserId, values, session.LeaderboardWritten)
				session.LeaderboardWriting = false
			end)
		end
	end)

	core.Hook("PlayerRemoving", function(player, profile)
		local values = collect(profile.Data)
		local written = profile.Session.LeaderboardWritten or {}
		task.spawn(writePlayer, player.UserId, values, written)
	end)

	---------------------------------------------------------------- drawing

	local function draw(board, entries, isLocal)
		local model = folder and folder:FindFirstChild(board.Id)
		local gui = model and model:FindFirstChild("Board", true)
		local rows = gui and gui:FindFirstChild("Rows")
		if not rows then
			return
		end
		for rank = 1, TOP do
			local row = rows:FindFirstChild("Row" .. rank)
			if row then
				local entry = entries[rank]
				-- Empty ranks are hidden rather than drawn as placeholders.
				row.Visible = entry ~= nil
				if entry then
					local text, color = board.Format(entry.Value)
					row.PlayerName.Text = entry.Name
					row.PlayerName.TextColor3 = NAME_COLOR
					row.Value.Text = text
					row.Value.TextColor3 = color or MEDALS[rank] or NAME_COLOR
				else
					row.PlayerName.Text = ""
					row.PlayerName.TextColor3 = EMPTY_COLOR
					row.Value.Text = ""
				end
			end
		end
		local hint = gui:FindFirstChild("EmptyHint")
		if hint then
			hint.Visible = entries[1] == nil
		end
		local footer = gui:FindFirstChild("Footer")
		if footer then
			footer.Text = isLocal and "This server  ·  global board needs a published place" or "Global  ·  updates every 3 minutes"
		end
	end

	local function localEntries(board)
		local entries = {}
		for player, profile in pairs(core.DataService.All()) do
			if player.Parent then
				local ok, value = pcall(board.Get, profile.Data)
				table.insert(entries, { Name = player.Name, Value = ok and Leaderboards.Clean(value) or 0 })
			end
		end
		table.sort(entries, function(a, b)
			return a.Value > b.Value
		end)
		return entries
	end

	local function refreshBoard(board)
		if board.OrderedStore then
			local ok, page = pcall(function()
				return board.OrderedStore:GetSortedAsync(false, TOP):GetCurrentPage()
			end)
			if ok then
				local entries = {}
				for _, item in ipairs(page) do
					local userId = tonumber(item.key)
					table.insert(entries, { Name = userId and nameFor(userId) or "Player", Value = item.value })
				end
				draw(board, entries, false)
				return
			end
			warnOnce(tostring(page))
		end
		draw(board, localEntries(board), true)
	end

	task.spawn(function()
		task.wait(FIRST_REFRESH)
		while true do
			for _, board in ipairs(boards) do
				refreshBoard(board)
			end
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

return Leaderboards
