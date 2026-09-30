-- Redeem codes (server-only, so exploiters can't read the list).
--
-- HOW TO ADD A CODE
--   Add a line to the table below. The key is the code players type; matching ignores
--   upper/lower case and spaces around it (use letters, digits, _ or - only, max 32 characters).
--   Rewards can combine any of:
--     Coins = 1000               Tickets = 50               Credits = 200 (Security Credits)
--     Relic = "golden_scarab"    (a relic id from ReplicatedStorage.RelicRNG.Config; shows a reveal)
--     Boost = { Kind = "Luck" or "Income", Seconds = 900 }
--   Optional limits:
--     MinLevel = 5               -- Curator Level needed to redeem
--     Expires = os.time({ year = 2026, month = 12, day = 31, hour = 0 })  -- UTC; after this it says "expired"
--
-- HOW TO EXPIRE A CODE
--   Give it an Expires time (players get a friendly "expired" message), or delete its line.
--   Each player can redeem each code once; that's saved with their data, so re-adding a code
--   later won't let anyone claim it twice.
--
-- Example:
--   UPDATE2 = { Rewards = { Tickets = 100, Boost = { Kind = "Income", Seconds = 1800 } }, Expires = os.time({ year = 2026, month = 11, day = 1 }) },
return {
	RELEASE = { Rewards = { Tickets = 50, Coins = 1000 } },
	MUSEUM = { Rewards = { Tickets = 25 } },
	LUCKY = { Rewards = { Boost = { Kind = "Luck", Seconds = 15 * 60 } } },
	HEIST = { Rewards = { Credits = 200 } },
	RELICS = { Rewards = { Relic = "golden_scarab" } },
}
