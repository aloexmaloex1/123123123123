-- Codes panel: type a code and redeem it. The server validates everything; relic rewards play the reveal.
local TweenService = game:GetService("TweenService")

local MAX_LENGTH = 32
local HINT = "Follow the game's group for new codes!"

return function(ctx)
	local Theme = ctx.Theme
	local new, label, button, corner, stroke = ctx.new, ctx.label, ctx.button, ctx.corner, ctx.stroke

	local frame, content = ctx.createModal("Codes", "Redeem Codes")
	-- Header (60) + content (hint 20, box 48, button 46, status 20 + gaps) + padding: no empty space.
	frame:FindFirstChildOfClass("UISizeConstraint").MaxSize = Vector2.new(440, 238)
	content.ScrollBarThickness = 0

	label({ Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, -10, 0, 20), Text = "Enter a code to claim free rewards!", Font = Theme.FontBold, TextColor3 = Theme.Muted, ZIndex = 5, Parent = content }, 16)

	local box = new("TextBox", {
		Name = "CodeBox",
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, -10, 0, 48),
		BackgroundColor3 = Color3.fromRGB(14, 11, 20),
		BorderSizePixel = 0,
		Font = Theme.FontBold,
		Text = "",
		PlaceholderText = "Enter code here",
		PlaceholderColor3 = Theme.Disabled,
		TextColor3 = Theme.GoldLight,
		TextScaled = true,
		ClearTextOnFocus = false,
		ZIndex = 6,
		Parent = content,
	})
	corner(box, UDim.new(0, 10))
	stroke(box, Theme.Gold, 1.5, 0.35)
	ctx.maxText(box, 22)
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = box })
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > MAX_LENGTH then
			box.Text = box.Text:sub(1, MAX_LENGTH)
		end
	end)

	-- One status line: the group hint until a result replaces it.
	local result = label({ Position = UDim2.new(0, 0, 0, 136), Size = UDim2.new(1, -10, 0, 20), Text = HINT, Font = Theme.FontBold, TextColor3 = Theme.Muted, ZIndex = 5, Parent = content }, 16)

	local busy = false
	local redeem
	local function submit()
		local text = box.Text:match("^%s*(.-)%s*$")
		if busy then
			return
		end
		if text == "" then
			result.Text = "Type a code first."
			result.TextColor3 = Theme.Error
			return
		end
		busy = true
		ctx.setEnabled(redeem, false)
		redeem.Text = "Checking..."
		local ok, message = ctx.Remotes.Action:InvokeServer("RedeemCode", text)
		result.Text = type(message) == "string" and message or (ok and "Code redeemed!" or "Couldn't redeem that code.")
		result.TextColor3 = ok and Theme.Success or Theme.Error
		if ok then
			box.Text = ""
			result.TextTransparency = 1
			TweenService:Create(result, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		end
		task.wait(0.6)
		redeem.Text = "Redeem"
		ctx.setEnabled(redeem, true)
		busy = false
	end
	redeem = button({ Position = UDim2.new(0, 0, 0, 82), Size = UDim2.new(1, -10, 0, 46), Text = "Redeem", Font = Theme.FontBlack, BackgroundColor3 = Theme.Gold, TextColor3 = Theme.Dark, ZIndex = 6, Parent = content }, function()
		if redeem.Active then
			submit()
		end
	end, 22)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)

	-- Relic rewards from codes (or anything else granted through core.GrantRewards) show the reveal card.
	ctx.OnEvent("Codes", function(kind, payload)
		if kind == "Reveal" and type(payload) == "table" and ctx.ShowReveal and ctx.Config.RelicsById[payload.RelicId] then
			ctx.closeModals()
			ctx.ShowReveal(payload)
		end
	end)

	ctx.AddMenuButton("Codes", 60, function()
		if not frame.Visible and not busy then
			result.Text = HINT
			result.TextColor3 = Theme.Muted
		end
		ctx.openModal("Codes")
	end)
end
