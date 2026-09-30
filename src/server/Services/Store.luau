-- Robux store: game pass ownership and effects, developer product receipts, and Auto-Dig
-- (a roll every few seconds while standing at a dig site, plus a batch of offline digs on return).
-- This service is the only owner of MarketplaceService.ProcessReceipt.
-- Items and prices live in ReplicatedStorage.RelicRNG.FeatureConfig.Store.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StoreConfig = require(ReplicatedStorage.RelicRNG.FeatureConfig.Store)

local Store = { Priority = 5 }

local PASS_CHECK_TIMEOUT = 10

local function findPass(gamePassId)
	for key, pass in pairs(StoreConfig.Passes) do
		if pass.Id ~= 0 and pass.Id == gamePassId then
			return key, pass
		end
	end
	return nil
end

local function findProduct(productId)
	for key, product in pairs(StoreConfig.Products) do
		if product.Id ~= 0 and product.Id == productId then
			return key, product
		end
	end
	return nil
end

-- Income factor from passes alone (DoubleIncome x VIP).
function Store.PassIncomeFactor(hasDouble, hasVip)
	local factor = 1
	if hasDouble then
		factor *= StoreConfig.DoubleIncomeMultiplier
	end
	if hasVip then
		factor *= StoreConfig.VIPIncomeMultiplier
	end
	return factor
end

-- How many offline Auto-Dig rolls a returning player gets.
function Store.OfflineRollCount(awaySeconds, tickets, ticketCost)
	local byTime = math.floor(math.max(0, awaySeconds) / StoreConfig.OfflineDigEvery)
	local byTickets = math.floor(math.max(0, tickets) / math.max(1, ticketCost))
	return math.max(0, math.min(StoreConfig.OfflineDigMax, byTime, byTickets))
end

-- Keeps the newest `limit` purchase ids; returns true if `id` was already there.
function Store.RememberPurchase(list, id, limit)
	if table.find(list, id) then
		return true
	end
	table.insert(list, id)
	while #list > limit do
		table.remove(list, 1)
	end
	return false
end

function Store.Init(core)
	local Config = core.Config
	core.DataService.AddDefaults({
		PurchaseIds = {}, -- recent developer product receipts, newest last
		LastDigSite = "DustyDunes", -- where offline Auto-Dig digs
	})

	local passChecks = {} -- [player] = true once ownership has been checked

	---------------------------------------------------------------- VIP title

	local function addVipTag(character)
		local head = character:WaitForChild("Head", 10)
		if not head or head:FindFirstChild("VIPTag") then
			return
		end
		local tag = Instance.new("BillboardGui")
		tag.Name = "VIPTag"
		tag.Size = UDim2.fromOffset(64, 24)
		tag.StudsOffset = Vector3.new(0, 3.1, 0)
		tag.MaxDistance = 90
		tag.LightInfluence = 0
		local frame = Instance.new("TextLabel")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
		frame.BackgroundTransparency = 0.2
		frame.Font = Enum.Font.GothamBlack
		frame.Text = "VIP"
		frame.TextColor3 = Color3.fromRGB(245, 215, 120)
		frame.TextSize = 16
		frame.Parent = tag
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(212, 175, 55)
		stroke.Thickness = 1.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		tag.Parent = head
	end

	local function refreshVipTag(player)
		if core.HasPass(player, "VIP") and player.Character then
			task.spawn(addVipTag, player.Character)
		end
	end

	---------------------------------------------------------------- pass ownership

	local function onPassesChanged(player)
		if not core.GetData(player) then
			return
		end
		core.RefreshMuseum(player)
		core.Sync(player)
		refreshVipTag(player)
	end

	-- Checks every configured pass in parallel and sets Pass_<Key> attributes.
	local function checkPasses(player)
		local pending = 0
		for key, pass in pairs(StoreConfig.Passes) do
			if pass.Id ~= 0 and player:GetAttribute("Pass_" .. key) ~= true then
				pending += 1
				task.spawn(function()
					local ok, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
					end)
					if not ok then
						warn(("[RelicRNG] Pass check %s failed for %s: %s"):format(key, player.Name, tostring(owns)))
					elseif owns and player.Parent then
						player:SetAttribute("Pass_" .. key, true)
					end
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + PASS_CHECK_TIMEOUT
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
		passChecks[player] = true
	end

	-- Starts at join so it overlaps the DataStore load; the PlayerAdded hook waits for it.
	local function startPassCheck(player)
		if passChecks[player] == nil then
			passChecks[player] = false
			task.spawn(checkPasses, player)
		end
	end
	Players.PlayerAdded:Connect(startPassCheck)
	for _, player in ipairs(Players:GetPlayers()) do
		startPassCheck(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		passChecks[player] = nil
	end)

	-- The purchase-finished signal can be spoofed by an exploiting client, so ownership is always
	-- re-checked with Roblox before the pass is granted. A few retries cover the ownership cache
	-- catching up right after a real purchase. Studio test purchases don't grant real ownership, so
	-- Studio alone trusts the signal.
	local verifying = {} -- [player] = { [gamePassId] = true } while a check is running
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased or typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		local key, pass = findPass(gamePassId)
		if not key or player:GetAttribute("Pass_" .. key) == true then
			return
		end
		local pending = verifying[player] or {}
		if pending[gamePassId] then
			return
		end
		pending[gamePassId] = true
		verifying[player] = pending
		local owns = false
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and result then
				owns = true
				break
			end
			if not player.Parent then
				break
			end
			task.wait(attempt * 2)
		end
		if verifying[player] then
			verifying[player][gamePassId] = nil
		end
		if not owns and RunService:IsStudio() then
			owns = true
		end
		if not owns or not player.Parent then
			return
		end
		player:SetAttribute("Pass_" .. key, true)
		onPassesChanged(player)
		core.Notify(player, pass.Name .. " unlocked! Thank you for the support!", "success")
	end)
	Players.PlayerRemoving:Connect(function(player)
		verifying[player] = nil
	end)

	---------------------------------------------------------------- pass effects

	core.Hook("IncomeMultiplier", function(player)
		return Store.PassIncomeFactor(core.HasPass(player, "DoubleIncome"), core.HasPass(player, "VIP"))
	end)
	core.Hook("DisplaySlots", function(player)
		return core.HasPass(player, "ExtraPedestals") and StoreConfig.ExtraPedestals or 0
	end)
	-- Lucky Scanner: the pitch was "preview whether the next roll is Rare+". An honest preview would
	-- mean pre-rolling the result and storing it before the player commits a ticket, which leaks the
	-- outcome and lets players skip bad rolls by switching sites. Instead the scanner is a flat luck
	-- bonus, which is what the preview would effectively be worth anyway.
	core.Hook("LuckMultiplier", function(player)
		return core.HasPass(player, "LuckyScanner") and StoreConfig.LuckyScannerLuck or 1
	end)
	core.Hook("Rolled", function(_, data, result)
		if result.Site and Config.DigSites[result.Site] then
			data.LastDigSite = result.Site
		end
	end)

	---------------------------------------------------------------- join: passes, offline top-up, offline Auto-Dig

	local function runOfflineAutoDig(player, profile, greeting)
		local data = profile.Data
		local away = os.time() - (data.LastOnline or os.time())
		local siteId = data.LastDigSite
		if not Config.DigSites[siteId] or not core.IsSiteUnlocked(data, siteId) then
			siteId = "DustyDunes"
		end
		local site = Config.DigSites[siteId]
		local rolls = Store.OfflineRollCount(away, data.Tickets, site.TicketCost)
		if rolls < 1 then
			return
		end
		local done, newCount, best = 0, 0, nil
		for i = 1, rolls do
			-- core.RollAt syncs the whole snapshot every roll (there is no batch flag in core), so spread
			-- a large offline batch over several frames instead of sending up to 100 snapshots at once.
			if i % 10 == 0 then
				task.wait()
				if not player.Parent then
					break
				end
			end
			local result = core.RollAt(player, siteId, true)
			if not result then
				break
			end
			done += 1
			if result.IsNew then
				newCount += 1
			end
			if not best or result.Tier > best.Tier then
				best = result
			end
		end
		if done > 0 then
			local relic = Config.RelicsById[best.RelicId]
			greeting.Extra = greeting.Extra or {}
			table.insert(greeting.Extra, ("Auto-Dig excavated %d time%s at %s while you were away. Best find: %s (%s)%s."):format(
				done, done == 1 and "" or "s", site.Name, relic.Name, Config.Rarities[best.Tier].Name,
				newCount > 0 and (", plus %d new relic%s"):format(newCount, newCount == 1 and "" or "s") or ""))
		end
	end

	core.Hook("PlayerAdded", function(player, profile, greeting)
		startPassCheck(player)
		local deadline = os.clock() + PASS_CHECK_TIMEOUT + 1
		while not passChecks[player] and os.clock() < deadline and player.Parent do
			task.wait(0.1)
		end
		player:GetAttributeChangedSignal("Pass_VIP"):Connect(function()
			refreshVipTag(player)
		end)
		player.CharacterAdded:Connect(function()
			refreshVipTag(player)
		end)
		refreshVipTag(player)
		core.RefreshMuseum(player) -- Main placed relics before pass slots were known

		-- Main paid offline income before pass attributes existed; top it up to the real rate.
		local data = profile.Data
		local incomePass = core.HasPass(player, "DoubleIncome") or core.HasPass(player, "VIP") or core.HasPass(player, "ExtraPedestals")
		if incomePass and not greeting.IsNew and (greeting.Seconds or 0) > 0 then
			local owed = math.floor(core.GetIncomePerMinute(player, data) / 60 * greeting.Seconds)
			local extra = owed - (greeting.Earned or 0)
			if extra > 0 then
				core.AddCoins(player, extra, true)
				greeting.Earned = owed
			end
		end

		if not greeting.IsNew and core.HasPass(player, "AutoDig") then
			runOfflineAutoDig(player, profile, greeting)
		end
	end)

	---------------------------------------------------------------- Auto-Dig (online)

	local function setStatus(player, text)
		if player:GetAttribute("AutoDigStatus") ~= text then
			player:SetAttribute("AutoDigStatus", text)
		end
	end

	function core.Actions.SetAutoDig(player, enabled)
		if type(enabled) ~= "boolean" then
			return false, "Invalid request."
		end
		if enabled and not core.HasPass(player, "AutoDig") then
			return false, "Auto-Dig needs the Auto-Dig pass."
		end
		local profile = core.GetProfile(player)
		profile.Session.AutoDig = enabled
		profile.Session.AutoDigNext = os.clock() + 1
		player:SetAttribute("AutoDigOn", enabled)
		setStatus(player, enabled and "Starting..." or "")
		return true, enabled and "Auto-Dig on. Stand in a dig site." or "Auto-Dig off."
	end

	core.Hook("Tick", function(player, profile)
		local session = profile.Session
		if not session.AutoDig then
			return
		end
		if not core.HasPass(player, "AutoDig") then
			session.AutoDig = false
			player:SetAttribute("AutoDigOn", false)
			return
		end
		local now = os.clock()
		if now < (session.AutoDigNext or 0) then
			return
		end
		if session.Busy then
			setStatus(player, "Paused")
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local siteId = root and Config.SiteAt(root.Position)
		if not siteId then
			setStatus(player, "Stand in a dig site")
			return
		end
		local data = profile.Data
		local site = Config.DigSites[siteId]
		if not core.IsSiteUnlocked(data, siteId) then
			setStatus(player, ("Unlocks at Lv %d"):format(site.Level))
			return
		end
		if data.Tickets < site.TicketCost then
			setStatus(player, "Out of Dig Tickets")
			return
		end
		session.AutoDigNext = now + StoreConfig.AutoDigInterval - 0.05
		local result = core.RollAt(player, siteId, true)
		if result then
			setStatus(player, "Digging at " .. site.Name)
			core.FireClient(player, "AutoDig", { RelicId = result.RelicId, Tier = result.Tier, IsNew = result.IsNew, Pity = result.Pity })
		end
	end)

	core.Hook("PlayerRemoving", function(player)
		passChecks[player] = nil
	end)

	---------------------------------------------------------------- developer products

	local function grant(player, product)
		local reward = product.Grant
		if reward.Tickets then
			core.AddTickets(player, reward.Tickets)
		end
		if reward.Boost then
			core.AddBoost(player, reward.Boost, reward.Seconds)
		end
	end

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local profile = player and core.GetProfile(player)
		if not profile or not player:GetAttribute("Loaded") then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local _, product = findProduct(receipt.ProductId)
		if not product then
			warn("[RelicRNG] Receipt for unknown product id " .. tostring(receipt.ProductId) .. "; add it to FeatureConfig.Store.")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		-- Never grant into a session that can't save (failed load), except in Studio test purchases.
		if not profile.CanSave and not RunService:IsStudio() then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local data = profile.Data
		if not table.find(data.PurchaseIds, receipt.PurchaseId) then
			grant(player, product)
			Store.RememberPurchase(data.PurchaseIds, receipt.PurchaseId, StoreConfig.RecentPurchaseIds)
			core.Sync(player)
			core.Notify(player, product.Name .. " received. Thank you!", "success")
		end
		if profile.CanSave and not core.DataService.Save(player) then
			-- The grant stays in memory with its PurchaseId, so a retry won't double it.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return Store
