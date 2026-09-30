-- Relic RNG client bootstrap: builds the shared UI toolkit, then starts every feature module.
-- Feature modules live in the Features folder and return function(ctx).
local ctx = require(script:WaitForChild("UIKit"))

local features = script:WaitForChild("Features"):GetChildren()
table.sort(features, function(a, b)
	return a.Name < b.Name
end)
for _, module in ipairs(features) do
	if module:IsA("ModuleScript") then
		task.spawn(function()
			local ok, err = pcall(function()
				require(module)(ctx)
			end)
			if not ok then
				warn("[RelicRNG] Client feature " .. module.Name .. " failed: " .. tostring(err))
			end
		end)
	end
end

ctx.Remotes.DataUpdated.OnClientEvent:Connect(ctx.ApplySnapshot)
ctx.Remotes.Notify.OnClientEvent:Connect(ctx.toast)
