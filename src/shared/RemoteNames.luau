--!strict
-- The one list of remotes. The server creates them at startup (Main); clients only wait for them.
-- Adding a remote = adding a line here.

export type RemoteName = "RequestRoll" | "RollResult" | "DataUpdated" | "Notify" | "Announce" | "FeatureEvent" | "Action"

local RemoteNames = {
	Events = { "RequestRoll", "RollResult", "DataUpdated", "Notify", "Announce", "FeatureEvent" } :: { RemoteName },
	Functions = { "Action" } :: { RemoteName },
}

return table.freeze(RemoteNames)
