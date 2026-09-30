--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (remote payloads, the saved profile schema, config shapes) live here so both sides agree.

export type TierIndex = number -- 1 (Common) .. 10 (Forgotten)

export type RarityDef = {
	Name: string,
	Chance: number, -- percent at luck 1
	Income: number, -- coins per minute on display
	Color: Color3,
}

export type RelicDef = {
	Id: string,
	Name: string,
	Tier: TierIndex,
	Shape: string,
	Color: Color3?,
	Site: string, -- filled in by Config
}

export type DigSiteDef = {
	Name: string,
	Level: number,
	TicketCost: number,
	Luck: number,
	Center: Vector3,
	Radius: number,
	Color: Color3,
	Blurb: string,
}

export type PityRule = { Every: number, MinTier: TierIndex }

export type SetBonus = {
	Income: number?,
	Luck: number?,
	OfflineHours: number?,
	HeistSeconds: number?,
}

export type SetDef = {
	Id: string,
	Name: string,
	Relics: { string },
	Bonus: SetBonus,
	Reward: { [string]: any },
}

-- Saved player data. Feature services add their own fields via DataService.AddDefaults,
-- so the table is open-ended; the core fields are listed here.
export type PlayerData = {
	Coins: number,
	CoinRemainder: number,
	Tickets: number,
	TotalRolls: number,
	Level: number,
	XP: number,
	Inventory: { [string]: number }, -- relicId -> copies owned
	Discovered: { [string]: boolean },
	Displayed: { [string]: string }, -- tostring(slot) -> relicId
	Pity: { number },
	Stats: { TotalEarned: number, BestTier: number },
	LastOnline: number,
	[string]: any,
}

-- What is actually written to the DataStore key.
export type SavedRecord = {
	Schema: number,
	Data: PlayerData,
	Lock: { JobId: string, Time: number }?,
}

export type Profile = {
	Data: PlayerData,
	CanSave: boolean,
	IsNew: boolean,
	Released: boolean,
	NextAutosave: number,
	Session: { [string]: any }, -- unsaved per-session scratch space for features
}

export type RollResult = {
	RelicId: string,
	Tier: TierIndex,
	Pity: boolean,
	IsNew: boolean,
	Site: string,
	XP: number?,
	Title: string?,
}

export type Snapshot = {
	Inventory: { [string]: number },
	Discovered: { [string]: boolean },
	Displayed: { [string]: string },
	Pity: { number },
	Stats: { TotalEarned: number, BestTier: number },
	[string]: any,
}

export type Greeting = {
	IsNew: boolean?,
	Saving: boolean?,
	Seconds: number?,
	Earned: number?,
	Capped: boolean?,
	CapSeconds: number?,
	Extra: { string }?,
}

-- Server action handlers: Actions[name](player, arg) -> ok, message?, extra?
export type ActionHandler = (player: Player, arg: unknown) -> (boolean, any?, any?)

return nil
