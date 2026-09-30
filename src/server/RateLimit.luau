--!strict
-- Per-player, per-key token buckets. Every remote handler goes through RateLimit.Allow first,
-- so a client firing remotes thousands of times a second only burns its own budget.
local Players = game:GetService("Players")

type Bucket = { tokens: number, last: number }

local RateLimit = {}

local buckets: { [Player]: { [string]: Bucket } } = {}
local strikes: { [Player]: number } = {}

-- Refills `ratePerSec` tokens per second up to `burst`; each call spends one token.
function RateLimit.Allow(player: Player, key: string, ratePerSec: number, burst: number, now: number?): boolean
	local t = now or os.clock()
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local bucket = playerBuckets[key]
	if not bucket then
		bucket = { tokens = burst, last = t }
		playerBuckets[key] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + (t - bucket.last) * ratePerSec)
	bucket.last = t
	if bucket.tokens < 1 then
		local count = (strikes[player] or 0) + 1
		strikes[player] = count
		if count % 200 == 0 then
			-- Telemetry only. Never auto-ban on this alone (lag and retry loops cause false positives).
			warn(`[RelicRNG] {player.Name} has hit rate limits {count} times ({key}).`)
		end
		return false
	end
	bucket.tokens -= 1
	return true
end

function RateLimit.Clear(player: Player)
	buckets[player] = nil
	strikes[player] = nil
end

Players.PlayerRemoving:Connect(RateLimit.Clear)

return RateLimit
