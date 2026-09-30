--!strict
-- One manager per world behaviour (no scripts inside world models).
-- TeleportPad: any BasePart tagged "TeleportPad" with a Vector3 attribute "Destination" moves a
-- touching player's character there (e.g. the launch pad up to the floating Celestial Ruins).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local WorldInteractions = { Priority = 80 }

local PAD_TAG = "TeleportPad"
local PAD_COOLDOWN = 2

function WorldInteractions.Start(core: any)
	local lastUse: { [Player]: number } = {}
	local padConnections: { [Instance]: RBXScriptConnection } = {}

	local function attach(pad: Instance)
		if not pad:IsA("BasePart") or padConnections[pad] then
			return
		end
		padConnections[pad] = pad.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			local destination = pad:GetAttribute("Destination")
			if typeof(destination) ~= "Vector3" then
				return
			end
			local profile = core.GetProfile(player)
			if not profile or profile.Session.Busy then
				return
			end
			local now = os.clock()
			if lastUse[player] and now - lastUse[player] < PAD_COOLDOWN then
				return
			end
			lastUse[player] = now
			-- Pads into a dig site respect its level gate, same as menu travel.
			local siteId = core.Config.SiteAt(destination)
			if siteId and not core.IsSiteUnlocked(profile.Data, siteId) then
				local site = core.Config.DigSites[siteId]
				core.Notify(player, `{site.Name} unlocks at Curator Level {site.Level}.`, "error")
				return
			end
			core.Teleport(player, CFrame.new(destination))
		end)
	end

	local function detach(pad: Instance)
		local connection = padConnections[pad]
		if connection then
			connection:Disconnect()
			padConnections[pad] = nil
		end
	end

	for _, pad in CollectionService:GetTagged(PAD_TAG) do
		attach(pad)
	end
	CollectionService:GetInstanceAddedSignal(PAD_TAG):Connect(attach)
	CollectionService:GetInstanceRemovedSignal(PAD_TAG):Connect(detach)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)
end

return WorldInteractions
