-- Museum security: Security Level upgrades (paid in Security Credits), NPC thief attempts on the
-- player's museum and the 1-5 star museum rating that boosts income.
-- Tuning lives in ReplicatedStorage.RelicRNG.FeatureConfig.Security.
-- Adds to core: core.Security.GetRating(player, data), core.Security.TriggerThief(player) (testing).
--
-- Thief attempts: the owner gets an alert and CATCH_WINDOW seconds to reach the thief at the robbed
-- pedestal and hold E on the server-side "Catch" prompt (a guaranteed catch). If they don't, the
-- Security Level catch chance decides. The thief NPC, its run and the alarm beacons are drawn by every
-- client from "Security" "ThiefFx" events (Features.60_Museum), so nothing is tweened on the server.
-- No attempts while the player is busy / in a heist, nor for BUSY_GRACE seconds afterwards.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("RelicRNG"):WaitForChild("FeatureConfig"):WaitForChild("Security"))

local Security = {}

local random = Random.new()
local THIEF = Tuning.Thief

local CATCH_WINDOW = 18 -- seconds between the alarm and the outcome
local BUSY_GRACE = 90 -- no thief for this long after a heist / busy period ends
local CATCH_HOLD = 1 -- seconds to hold the Catch prompt
local CATCH_REACH = 16 -- server-side distance check for the Catch prompt
-- Loss cap for an escaped thief: at most this many minutes of income AND this share of coins.
local MAX_STOLEN_MINUTES = math.min(THIEF.StolenIncomeMinutes, 10)
local MAX_STOLEN_FRACTION = math.min(THIEF.MaxStolenFraction, 0.05)

local function randomIn(range)
	return random:NextInteger(range[1], range[2])
end

-- Coins an escaped thief takes.
function Security.StolenAmount(incomePerMin, coins)
	return math.max(0, math.floor(math.min(incomePerMin * MAX_STOLEN_MINUTES, coins * MAX_STOLEN_FRACTION)))
end

---------------------------------------------------------------- service

function Security.Init(core)
	local Config, MuseumService = core.Config, core.MuseumService

	core.DataService.AddDefaults({
		Security = { Level = 0, Caught = 0, Escaped = 0, Log = {} },
	})

	local lastStars = {} -- [player] = stars shown on the sign
	local attempts = {} -- [player] = { Point = catch prompt part, Connection = Triggered connection }
	local attemptId = 0

	local function getRating(player, data)
		return Tuning.ComputeRating(data.Displayed, core.GetDisplaySlots(player, data), data.Security.Level, Config)
	end

	local function hasDisplay(player, data)
		local slots = core.GetDisplaySlots(player, data)
		for slot, relicId in pairs(data.Displayed) do
			if Config.RelicsById[relicId] and tonumber(slot) <= slots then
				return true
			end
		end
		return false
	end

	local function plotFrame(plot)
		local pivot = plot:GetPivot().Position
		return CFrame.new(pivot.X, 1, pivot.Z) -- floor top, plot centre
	end

	-- Picks a displayed pedestal for the thief to go for; returns its plot-local position.
	local function targetPedestal(player, data, plot, frame)
		local slots = core.GetDisplaySlots(player, data)
		local options = {}
		for slot, relicId in pairs(data.Displayed) do
			local pedestal = plot.Pedestals:FindFirstChild("Pedestal" .. slot)
			if pedestal and Config.RelicsById[relicId] and tonumber(slot) <= slots then
				table.insert(options, pedestal)
			end
		end
		local pedestal = options[random:NextInteger(1, math.max(1, #options))]
		if not pedestal then
			return Vector3.new(0, 0, 0)
		end
		return frame:PointToObjectSpace(pedestal.Top.Position)
	end

	local function cleanupAttempt(player)
		local attempt = attempts[player]
		if attempt then
			attempts[player] = nil
			attempt.Connection:Disconnect()
			attempt.Point:Destroy()
		end
	end

	-- Invisible anchored part with the owner's Catch prompt where the thief stands.
	local function makeCatchPoint(player, plot, at)
		local point = Instance.new("Part")
		point.Name = "ThiefCatchPoint"
		point.Size = Vector3.new(2, 5, 2)
		point.CFrame = CFrame.new(at + Vector3.new(0, 2.5, 0))
		point.Transparency = 1
		point.Anchored = true
		point.CanCollide = false
		point.CanQuery = false
		point.CanTouch = false
		point:SetAttribute("OwnerUserId", player.UserId) -- other clients hide the prompt locally
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CatchPrompt"
		prompt.ActionText = "Catch"
		prompt.ObjectText = "Thief"
		prompt.HoldDuration = CATCH_HOLD
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = point
		point.Parent = plot
		return point, prompt
	end

	local function runAttempt(player, profile)
		local data = profile.Data
		local plot = MuseumService.GetPlot(player)
		if not plot then
			return
		end
		attemptId += 1
		local id = attemptId
		local frame = plotFrame(plot)
		local target = targetPedestal(player, data, plot, frame)
		local side = target.X >= 0 and 1 or -1
		local standAt = Vector3.new(target.X - side * math.min(2.8, math.abs(target.X)), 0, target.Z - (math.abs(target.X) < 1 and 2.8 or 0))
		local standWorld = (frame * CFrame.new(standAt)).Position

		local caughtByPlayer = false
		local point, prompt = makeCatchPoint(player, plot, standWorld)
		local connection = prompt.Triggered:Connect(function(who)
			if who ~= player or caughtByPlayer then
				return
			end
			local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - standWorld).Magnitude <= CATCH_REACH then
				caughtByPlayer = true
			end
		end)
		attempts[player] = { Point = point, Connection = connection }

		local startLevel = data.Security.Level
		local endsAt = workspace:GetServerTimeNow() + CATCH_WINDOW
		core.FireClient(player, "Security", "Thief", {
			Phase = "Alert",
			Seconds = CATCH_WINDOW,
			EndsAt = endsAt,
			Level = startLevel,
			Chance = Tuning.GetCatchChance(startLevel),
			Position = standWorld,
		})
		core.FireAllClients("Security", "ThiefFx", {
			Phase = "Enter",
			Id = id,
			Owner = player.UserId,
			Plot = plot.Name,
			Frame = frame,
			Target = target,
			StandAt = standAt,
			EndsAt = endsAt,
		})

		-- Wait for the window to run out or the owner to catch the thief.
		local deadline = os.clock() + CATCH_WINDOW
		while os.clock() < deadline and not caughtByPlayer and player.Parent and core.GetProfile(player) == profile do
			task.wait(0.2)
		end
		cleanupAttempt(player)
		if core.GetProfile(player) ~= profile or not player.Parent then
			core.FireAllClients("Security", "ThiefFx", { Phase = "Cancel", Id = id })
			return
		end

		local level = data.Security.Level
		local caught = caughtByPlayer or random:NextNumber() * 100 < Tuning.GetCatchChance(level)
		local entry = { T = os.time(), Caught = caught, Level = level, ByPlayer = caughtByPlayer or nil }
		if caught then
			local credits = THIEF.CaughtCredits + level * THIEF.CaughtCreditsPerLevel
			core.AddCredits(player, credits)
			data.Security.Caught += 1
			entry.Credits = credits
			local how = caughtByPlayer and "You caught the thief red-handed!" or "Your security caught the thief!"
			core.Notify(player, ("%s +%d Security Credits"):format(how, credits), "success")
		else
			local stolen = Security.StolenAmount(core.GetIncomePerMinute(player, data), data.Coins)
			core.AddCoins(player, -stolen)
			data.Security.Escaped += 1
			entry.Coins = stolen
			core.Notify(player, ("The thief escaped with %s coins! Upgrade your Security to catch the next one."):format(Config.FormatNumber(stolen)), "error")
		end
		local log = data.Security.Log
		table.insert(log, 1, entry)
		while #log > THIEF.LogSize do
			table.remove(log)
		end
		core.FireClient(player, "Security", "Thief", {
			Phase = "Result",
			Caught = caught,
			ByPlayer = caughtByPlayer,
			Credits = entry.Credits,
			Coins = entry.Coins,
			Level = level,
		})
		core.FireAllClients("Security", "ThiefFx", { Phase = caught and "Caught" or "Escaped", Id = id })
		core.Sync(player)
	end

	local function startAttempt(player, profile)
		profile.Session.ThiefActive = true
		task.spawn(function()
			local ok, err = pcall(runAttempt, player, profile)
			if not ok then
				warn("[RelicRNG] Thief attempt failed: " .. tostring(err))
			end
			cleanupAttempt(player)
			profile.Session.ThiefActive = false
		end)
	end

	core.Security = {
		GetRating = getRating,
		-- Forces a thief attempt right now (for testing).
		TriggerThief = function(player)
			local profile = core.GetProfile(player)
			if profile and not profile.Session.ThiefActive and MuseumService.GetPlot(player) then
				startAttempt(player, profile)
				return true
			end
			return false
		end,
	}

	---------------------------------------------------------------- hooks

	core.Hook("IncomeMultiplier", function(player, data)
		return 1 + Tuning.GetIncomeBonus(getRating(player, data).Stars)
	end)

	core.Hook("Stats", function(player, data)
		local stars = getRating(player, data).Stars
		player:SetAttribute("MuseumRating", stars)
		player:SetAttribute("SecurityLevel", data.Security.Level)
		if lastStars[player] ~= stars then
			lastStars[player] = stars
			MuseumService.SetRating(player, stars)
		end
	end)

	core.Hook("Snapshot", function(player, data, snapshot)
		snapshot.Security = {
			Level = data.Security.Level,
			Caught = data.Security.Caught,
			Escaped = data.Security.Escaped,
			Log = data.Security.Log,
			Rating = getRating(player, data),
		}
	end)

	core.Hook("PlayerAdded", function(player, profile)
		local data = profile.Data
		data.Security.Level = math.clamp(math.floor(tonumber(data.Security.Level) or 0), 0, Tuning.MaxLevel)
		MuseumService.SetSecurity(player, data.Security.Level)
		local stars = getRating(player, data).Stars
		lastStars[player] = stars
		MuseumService.SetRating(player, stars)
		profile.Session.NextThiefAt = os.time() + randomIn(THIEF.FirstDelay)
	end)

	core.Hook("Tick", function(player, profile, now)
		local session = profile.Session
		if session.ThiefActive then
			return
		end
		-- Busy (heist, teleporting...): push the next attempt past a grace period after it ends.
		if session.Busy or player:GetAttribute("InHeist") then
			session.NextThiefAt = math.max(session.NextThiefAt or 0, now + BUSY_GRACE)
			return
		end
		if not session.NextThiefAt then
			session.NextThiefAt = now + randomIn(THIEF.FirstDelay)
			return
		end
		if now < session.NextThiefAt then
			return
		end
		if not MuseumService.GetPlot(player) or not hasDisplay(player, profile.Data) then
			session.NextThiefAt = now + THIEF.RetryDelay
			return
		end
		session.NextThiefAt = now + randomIn(THIEF.Interval)
		startAttempt(player, profile)
	end)

	core.Hook("PlayerRemoving", function(player)
		lastStars[player] = nil
		cleanupAttempt(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastStars[player] = nil
		cleanupAttempt(player)
	end)

	---------------------------------------------------------------- actions

	function core.Actions.UpgradeSecurity(player)
		local data = core.GetData(player)
		local level = data.Security.Level
		if level >= Tuning.MaxLevel then
			return false, "Your security is already at the maximum level."
		end
		local cost = Tuning.GetUpgradeCost(level)
		if data.SecurityCredits < cost then
			return false, ("You need %d Security Credits (you have %d). Catch thieves or pull off heists to earn more."):format(cost, data.SecurityCredits)
		end
		core.AddCredits(player, -cost)
		data.Security.Level = level + 1
		MuseumService.SetSecurity(player, level + 1)
		core.Sync(player)
		return true, ("Security Level %d! %s."):format(level + 1, Tuning.LevelPerks[level + 1] or "Better protection")
	end
end

return Security
