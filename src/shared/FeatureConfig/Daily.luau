-- Daily login rewards: 7-day streak cycle tuning, plus the pure streak maths shared by server and client.
local Daily = {
	Cooldown = 20 * 3600, -- seconds between claims
	ResetAfter = 48 * 3600, -- streak resets if the last claim was longer ago than this

	-- One entry per day of the cycle. Same reward keys as codes: Coins, Tickets, Credits, Relic, Boost = { Kind, Seconds }.
	Days = {
		{ Tickets = 10, Coins = 250 },
		{ Tickets = 15, Coins = 750 },
		{ Tickets = 25, Coins = 1500 },
		{ Tickets = 20, Boost = { Kind = "Luck", Seconds = 15 * 60 } },
		{ Tickets = 35, Coins = 4000 },
		{ Tickets = 50, Coins = 8000, Credits = 50 },
		{ Tickets = 100, Credits = 250, Boost = { Kind = "Income", Seconds = 30 * 60 } },
	},
}

-- streak: consecutive claims so far; lastClaim: unix time of the last claim (0 = never).
-- Returns { Claimable, Streak (after any reset), Day (cycle day the next claim gives), ReadyAt, ResetAt, Broken, Claimed (days done this cycle) }.
function Daily.GetStatus(streak, lastClaim, now)
	streak = math.max(0, math.floor(tonumber(streak) or 0))
	lastClaim = tonumber(lastClaim) or 0
	local claimable, broken, readyAt, resetAt = false, false, 0, 0
	if lastClaim <= 0 then
		streak, claimable = 0, true
	else
		readyAt = lastClaim + Daily.Cooldown
		resetAt = lastClaim + Daily.ResetAfter
		if now > resetAt then
			broken = streak > 0
			streak, claimable, resetAt = 0, true, 0
		else
			claimable = now >= readyAt
		end
	end
	return {
		Claimable = claimable,
		Streak = streak,
		Day = Daily.NextDay(streak),
		ReadyAt = readyAt,
		ResetAt = resetAt,
		Broken = broken,
		Claimed = Daily.ClaimedInCycle(streak, claimable),
	}
end

function Daily.NextDay(streak)
	return streak % #Daily.Days + 1
end

-- How many cards of the current cycle show as claimed. Right after claiming day 7 all 7 stay
-- ticked until the next claim starts a new cycle.
function Daily.ClaimedInCycle(streak, claimable)
	if streak <= 0 then
		return 0
	end
	if claimable then
		return streak % #Daily.Days
	end
	return (streak - 1) % #Daily.Days + 1
end

-- Short card lines for a reward table, e.g. { "10 Tickets", "250 Coins" }. `abbr` formats big numbers.
function Daily.ShortLines(rewards, abbr, relicName)
	abbr = abbr or tostring
	local lines = {}
	if rewards.Tickets then
		table.insert(lines, abbr(rewards.Tickets) .. " Tickets")
	end
	if rewards.Coins then
		table.insert(lines, abbr(rewards.Coins) .. " Coins")
	end
	if rewards.Credits then
		table.insert(lines, abbr(rewards.Credits) .. " Credits")
	end
	if rewards.Boost then
		table.insert(lines, ("2x %s %dm"):format(rewards.Boost.Kind, rewards.Boost.Seconds // 60))
	end
	if rewards.Relic then
		table.insert(lines, relicName and relicName(rewards.Relic) or "Relic")
	end
	return lines
end

return Daily
