--!strict
-- QA panel. Only shown when the server marks this player IsDev; the server re-checks every command,
-- so hiding this UI is a convenience, not the security boundary (see Services/CheatCommands).
return function(ctx: any)
	local player: Player = ctx.player
	local Theme = ctx.Theme

	local function build()
		local _, content = ctx.createModal("DevPanel", "Developer Tools")
		ctx.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 40),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = content,
		})

		local buttons: { { any } } = {
			{ "+100K coins", "Coins", 100000 },
			{ "+10M coins", "Coins", 10000000 },
			{ "+500 tickets", "Tickets", 500 },
			{ "+200 credits", "Credits", 200 },
			{ "Level 12", "Level", 12 },
			{ "Level 55 (all sites)", "Level", 55 },
			{ "Next roll: Rare+ pity", "PityNext", 1 },
			{ "Next roll: Mythic+ pity", "PityNext", 4 },
			{ "Grant every relic", "AllRelics", true },
			{ "Luck boost 15 min", "Boost", "Luck" },
			{ "Income boost 15 min", "Boost", "Income" },
			{ "Send a thief now", "Thief", true },
			{ "Refill heist energy", "HeistEnergy", true },
			{ "RESET PROFILE", "Reset", true },
		}
		for i, spec in buttons do
			local label, command, value = spec[1], spec[2], spec[3]
			local danger = command == "Reset"
			ctx.button({
				Text = label,
				LayoutOrder = i,
				ZIndex = 6,
				BackgroundColor3 = if danger then Color3.fromRGB(120, 30, 35) else Theme.Button,
				Parent = content,
			}, function()
				ctx.act("Dev", { Command = command, Value = value })
			end, 16)
		end
		ctx.AddMenuButton("Dev", 999, function()
			ctx.openModal("DevPanel")
		end)
	end

	if player:GetAttribute("IsDev") == true then
		build()
		return
	end
	local connection: RBXScriptConnection
	connection = player:GetAttributeChangedSignal("IsDev"):Connect(function()
		if player:GetAttribute("IsDev") == true then
			connection:Disconnect()
			build()
		end
	end)
end
