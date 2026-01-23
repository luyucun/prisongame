--[[
脚本名称: LimitPrisonerSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/LimitPrisonerSystem
版本: V6.0
职责: 限时囚犯刷新、展示与购买/兑换逻辑
]]

local LimitPrisonerSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local LimitPrisonerConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("LimitPrisonerConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))

local DataManager = nil
local InventorySystem = nil
local CurrencySystem = nil
local PlayerManager = nil
local PlacementSystem = nil
local TaskSystem = nil

local limitPrisonerEvents = nil
local requestDataEvent = nil
local dataEvent = nil
local purchaseGoldEvent = nil
local purchaseRobuxEvent = nil
local redeemEvent = nil
local purchaseResultEvent = nil
local redeemResultEvent = nil

local refreshTimers = {}
local countdownTokens = {}
local refreshLocks = {}
local purchaseLocks = {}

-- ==================== 工具函数 ====================

local function InitializeModules()
	if not DataManager then
		local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
		if dataModule then
			DataManager = require(dataModule)
		else
			warn("[LimitPrisonerSystem] DataManager模块未找到")
			return false
		end
	end

	if not InventorySystem then
		local invModule = ServerScriptService.Systems:FindFirstChild("InventorySystem")
		if invModule then
			InventorySystem = require(invModule)
		else
			warn("[LimitPrisonerSystem] InventorySystem模块未找到")
			return false
		end
	end

	if not CurrencySystem then
		local currencyModule = ServerScriptService.Systems:FindFirstChild("CurrencySystem")
		if currencyModule then
			CurrencySystem = require(currencyModule)
		else
			warn("[LimitPrisonerSystem] CurrencySystem模块未找到")
			return false
		end
	end

	if not PlayerManager then
		local playerModule = ServerScriptService.Core:FindFirstChild("PlayerManager")
		if playerModule then
			PlayerManager = require(playerModule)
		else
			warn("[LimitPrisonerSystem] PlayerManager模块未找到")
			return false
		end
	end

	if not PlacementSystem then
		local placementModule = ServerScriptService.Systems:FindFirstChild("PlacementSystem")
		if placementModule then
			PlacementSystem = require(placementModule)
		else
			warn("[LimitPrisonerSystem] PlacementSystem模块未找到")
			return false
		end
	end

	return true
end

local function InitializeEvents()
	if limitPrisonerEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	limitPrisonerEvents = eventsFolder:FindFirstChild("LimitPrisonerEvents")
	if not limitPrisonerEvents then
		limitPrisonerEvents = Instance.new("Folder")
		limitPrisonerEvents.Name = "LimitPrisonerEvents"
		limitPrisonerEvents.Parent = eventsFolder
	end

	local function GetOrCreateEvent(name)
		local event = limitPrisonerEvents:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = limitPrisonerEvents
		end
		return event
	end

	requestDataEvent = GetOrCreateEvent("RequestLimitPrisonerData")
	dataEvent = GetOrCreateEvent("LimitPrisonerData")
	purchaseGoldEvent = GetOrCreateEvent("PurchaseLimitPrisonerGold")
	purchaseRobuxEvent = GetOrCreateEvent("PurchaseLimitPrisonerRobux")
	redeemEvent = GetOrCreateEvent("RedeemLimitPrisoner")
	purchaseResultEvent = GetOrCreateEvent("LimitPrisonerPurchaseResult")
	redeemResultEvent = GetOrCreateEvent("LimitPrisonerRedeemResult")

	return true
end

local function NotifyPurchaseTask(player, unitId)
	if not TaskSystem then
		local taskModule = ServerScriptService.Systems:FindFirstChild("TaskSystem")
		if taskModule and taskModule:IsA("ModuleScript") then
			local ok, result = pcall(require, taskModule)
			if ok then
				TaskSystem = result
			else
				warn("[LimitPrisonerSystem] TaskSystem妯″潡鍔犺浇澶辫触:", result)
			end
		end
	end

	if TaskSystem and TaskSystem.OnPurchaseUnit then
		TaskSystem.OnPurchaseUnit(player, unitId)
	end
end

local function GetPlayerHomeId(player)
	if PlayerManager and PlayerManager.GetPlayerHomeId then
		local homeId = PlayerManager.GetPlayerHomeId(player)
		if type(homeId) == "number" and homeId > 0 then
			return homeId
		end
	end

	if DataManager then
		local data = DataManager.GetPlayerData(player)
		local homeId = data and data.HomeSlot
		if type(homeId) == "number" and homeId > 0 then
			return homeId
		end
	end

	return nil
end

local function GetPrisonModel(homeId)
	local homeFolder = Workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME or "Home")
	if not homeFolder then
		return nil
	end

	local home = homeFolder:FindFirstChild((GameConfig.HOME_PREFIX or "PlayerHome") .. tostring(homeId))
	if not home then
		return nil
	end

	return home:FindFirstChild("PrisonNaoHong")
end

local function GetPrisonPrimaryPart(prisonModel)
	if not prisonModel then
		return nil
	end

	if prisonModel.PrimaryPart then
		return prisonModel.PrimaryPart
	end

	local named = prisonModel:FindFirstChild("PrimaryPart")
	if named and named:IsA("BasePart") then
		prisonModel.PrimaryPart = named
		return named
	end

	for _, descendant in ipairs(prisonModel:GetDescendants()) do
		if descendant.Name == "PrimaryPart" and descendant:IsA("BasePart") then
			prisonModel.PrimaryPart = descendant
			return descendant
		end
	end

	for _, child in ipairs(prisonModel:GetChildren()) do
		if child:IsA("BasePart") then
			prisonModel.PrimaryPart = child
			return child
		end
	end

	return nil
end

local function GetRefreshPart(prisonModel)
	if not prisonModel then
		return nil
	end

	local part = prisonModel:FindFirstChild("RefreshPart")
	if part and part:IsA("BasePart") then
		return part
	end

	for _, descendant in ipairs(prisonModel:GetDescendants()) do
		if descendant.Name == "RefreshPart" and descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function GetTimeLabel(prisonModel)
	local refreshPart = GetRefreshPart(prisonModel)
	if not refreshPart then
		return nil
	end

	local surfaceGui = refreshPart:FindFirstChild("SurfaceGui")
	if not surfaceGui then
		for _, descendant in ipairs(refreshPart:GetDescendants()) do
			if descendant.Name == "SurfaceGui" and descendant:IsA("SurfaceGui") then
				surfaceGui = descendant
				break
			end
		end
	end

	if not surfaceGui then
		return nil
	end

	local bg = surfaceGui:FindFirstChild("Bg")
	local timeLabel = bg and bg:FindFirstChild("Time")
	if timeLabel and timeLabel:IsA("TextLabel") then
		return timeLabel
	end

	return nil
end

local function GetNextRefreshTimeUtc(now)
	local ts = tonumber(now) or os.time()
	local dayIndex = math.floor(ts / 86400)
	local dayStart = dayIndex * 86400
	local refreshHours = LimitPrisonerConfig.RefreshHoursUtc or { 0, 12 }
	table.sort(refreshHours, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)

	for _, hour in ipairs(refreshHours) do
		local target = dayStart + (tonumber(hour) or 0) * 3600
		if ts < target then
			return target
		end
	end

	local firstHour = tonumber(refreshHours[1]) or 0
	return dayStart + 24 * 3600 + firstHour * 3600
end

local function FormatRefreshText(remainingSeconds)
	local remaining = math.max(0, math.floor(tonumber(remainingSeconds) or 0))
	if remaining < 60 then
		local minutes = math.floor(remaining / 60)
		local seconds = remaining % 60
		return string.format(
			"<font color=\"#FFFFFF\">Refreshes In:</font><font color=\"#00FF00\">%02d:%02d</font>",
			minutes,
			seconds
		)
	end

	local hours = math.floor(remaining / 3600)
	local minutes = math.floor((remaining % 3600) / 60)
	return string.format(
		"<font color=\"#FFFFFF\">Refreshes In:</font><font color=\"#00FF00\">%02d:%02d</font>",
		hours,
		minutes
	)
end

local function UpdateRefreshSurface(prisonModel, remaining)
	local timeLabel = GetTimeLabel(prisonModel)
	if not timeLabel then
		return
	end

	timeLabel.RichText = true
	timeLabel.Text = FormatRefreshText(remaining)
end

local function StopCountdown(player)
	countdownTokens[player] = nil
end

local function StartCountdown(player)
	StopCountdown(player)
	local token = {}
	countdownTokens[player] = token

	task.spawn(function()
		while countdownTokens[player] == token do
			if not player or not player.Parent then
				break
			end

			local data = DataManager and DataManager.GetLimitPrisonerData(player)
			local homeId = GetPlayerHomeId(player)
			if data and homeId then
				local prisonModel = GetPrisonModel(homeId)
				if prisonModel then
					local remaining = (tonumber(data.NextRefreshTime) or 0) - os.time()
					UpdateRefreshSurface(prisonModel, remaining)
				end
			end

			task.wait(1)
		end
	end)
end

local function PlayShowAnimation(model, unitId)
	if not model or not unitId then
		return
	end

	local showAnimId = UnitConfig.GetShowAnimationId(unitId)
	if not showAnimId or showAnimId == "" or showAnimId == "0" then
		return
	end

	if not tonumber(showAnimId) then
		warn(GameConfig.LOG_PREFIX, "LimitPrisoner PlayShowAnimation: 动画ID格式无效:", unitId, "AnimID:", showAnimId)
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") and descendant.Name == "Animate" then
			descendant.Enabled = false
		end
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		pcall(function()
			track:Stop(0)
		end)
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. showAnimId

	local success, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not result then
		animation:Destroy()
		return
	end

	local animTrack = result
	animTrack.Looped = true
	animTrack.Priority = Enum.AnimationPriority.Idle

	local playSuccess = pcall(function()
		animTrack:Play()
	end)

	if not playSuccess then
		animation:Destroy()
		return
	end

	animTrack.Stopped:Connect(function()
		if animation and animation.Parent then
			animation:Destroy()
		end
	end)
end

local function ClearDisplayModel(prisonModel)
	if not prisonModel then
		return
	end

	for _, child in ipairs(prisonModel:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("LimitPrisonerDisplay") == true then
			child:Destroy()
		end
	end
end

local function SpawnDisplayModel(player, unitId)
	if not unitId or unitId == "" then
		return
	end

	local homeId = GetPlayerHomeId(player)
	if not homeId then
		return
	end

	local prisonModel = GetPrisonModel(homeId)
	if not prisonModel then
		return
	end

	local refreshPart = GetRefreshPart(prisonModel)
	if not refreshPart then
		return
	end

	ClearDisplayModel(prisonModel)

	local unitData = UnitConfig.GetUnitById(unitId)
	local level = (unitData and unitData.BaseLevel) or 1
	local gridWidth = UnitConfig.GetGridWidth(unitId)
	local gridDepth = UnitConfig.GetGridDepth(unitId)
	local position = refreshPart.Position + Vector3.new(0, refreshPart.Size.Y / 2, 0)

	local model = PlacementSystem.CreateUnitModel(unitId, position, nil, level, gridWidth, gridDepth, homeId)
	if not model then
		return
	end

	model.Name = "LimitPrisoner_" .. unitId
	model:SetAttribute("LimitPrisonerDisplay", true)
	model.Parent = prisonModel

	local pivot = model:GetPivot()
	local x, _, z = pivot:ToOrientation()
	model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(x, math.rad(90), z))

	PlayShowAnimation(model, unitId)
end

local function EnsureDisplayModel(player, unitId)
	if not unitId or unitId == "" then
		return
	end

	local homeId = GetPlayerHomeId(player)
	if not homeId then
		return
	end

	local prisonModel = GetPrisonModel(homeId)
	if not prisonModel then
		return
	end

	for _, child in ipairs(prisonModel:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("LimitPrisonerDisplay") == true then
			return
		end
	end

	SpawnDisplayModel(player, unitId)
end

local function IsPlayerNearPrison(player)
	if not player then
		return false
	end

	local homeId = GetPlayerHomeId(player)
	if not homeId then
		return false
	end

	local prisonModel = GetPrisonModel(homeId)
	local primary = GetPrisonPrimaryPart(prisonModel)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (primary and hrp) then
		return false
	end

	local distance = (hrp.Position - primary.Position).Magnitude
	local maxDistance = (LimitPrisonerConfig.Proximity and LimitPrisonerConfig.Proximity.OpenDistance) or 8
	return distance <= maxDistance
end

local function BuildPayload(player, data)
	local prisoner = data and LimitPrisonerConfig.GetPrisonerByUnitId(data.CurrentUnitId)
	local payload = {
		UnitId = data and data.CurrentUnitId or "",
		GoldPrice = prisoner and tonumber(prisoner.GoldPrice) or 0,
		RobuxPrice = prisoner and tonumber(prisoner.RobuxPrice) or 0,
		HandcuffCost = prisoner and tonumber(prisoner.HandcuffCost) or 0,
		GoldPurchased = data and data.GoldPurchased == true,
		Redeemed = data and data.Redeemed == true,
		HandcuffCount = DataManager and DataManager.GetHandcuffCount(player) or 0,
		NextRefreshTime = data and tonumber(data.NextRefreshTime) or 0,
		ServerTime = os.time(),
	}
	return payload
end

local function SendData(player, data)
	if not dataEvent or not player then
		return
	end

	local payload = BuildPayload(player, data)
	dataEvent:FireClient(player, payload)
end

local function SendPurchaseResult(player, success, message, purchaseType, unitId, newCoins)
	if not purchaseResultEvent then
		return
	end

	purchaseResultEvent:FireClient(player, success, message or "", purchaseType or "", unitId or "", newCoins)
end

local function SendRedeemResult(player, success, message, rewardInfo)
	if not redeemResultEvent then
		return
	end

	redeemResultEvent:FireClient(player, success, message or "", rewardInfo)
end

local function EnsureLimitPrisonerData(player)
	if not InitializeModules() then
		return nil
	end

	local data = DataManager.GetLimitPrisonerData(player)
	if not data then
		DataManager.WaitForPlayerData(player, 10)
		data = DataManager.GetLimitPrisonerData(player)
	end

	return data
end

local function RefreshLimitPrisoner(player, forceRefresh)
	if refreshLocks[player] then
		return false
	end

	refreshLocks[player] = true

	local data = EnsureLimitPrisonerData(player)
	if not data then
		refreshLocks[player] = nil
		return false
	end

	local now = os.time()
	local nextRefresh = tonumber(data.NextRefreshTime) or 0
	local needRefresh = forceRefresh
		or data.LastRefreshTime <= 0
		or data.CurrentUnitId == ""
		or nextRefresh <= 0
		or now >= nextRefresh

	if needRefresh then
		local rolled = LimitPrisonerConfig.RollPrisoner()
		if rolled then
			data.CurrentUnitId = tostring(rolled.UnitId or "")
			data.LastRefreshTime = now
			data.NextRefreshTime = GetNextRefreshTimeUtc(now)
			data.GoldPurchased = false
			data.Redeemed = false

			if DataManager then
				DataManager.SavePlayerDataThrottled(player)
			end

			SpawnDisplayModel(player, data.CurrentUnitId)
		end
	else
		if nextRefresh <= 0 then
			data.NextRefreshTime = GetNextRefreshTimeUtc(now)
			if DataManager then
				DataManager.SavePlayerDataThrottled(player)
			end
		end
		EnsureDisplayModel(player, data.CurrentUnitId)
	end

	SendData(player, data)
	refreshLocks[player] = nil
	return true
end

local function StopRefreshTimer(player)
	if refreshTimers[player] then
		task.cancel(refreshTimers[player])
		refreshTimers[player] = nil
	end
end

local function StartRefreshTimer(player)
	StopRefreshTimer(player)

	local data = EnsureLimitPrisonerData(player)
	if not data then
		return
	end

	local now = os.time()
	local nextRefresh = tonumber(data.NextRefreshTime) or 0
	if nextRefresh <= 0 then
		nextRefresh = GetNextRefreshTimeUtc(now)
		data.NextRefreshTime = nextRefresh
		if DataManager then
			DataManager.SavePlayerDataThrottled(player)
		end
	end

	local remaining = nextRefresh - now
	if remaining <= 0 then
		RefreshLimitPrisoner(player, true)
		nextRefresh = tonumber(data.NextRefreshTime) or GetNextRefreshTimeUtc(os.time())
		remaining = math.max(1, nextRefresh - os.time())
	end

	refreshTimers[player] = task.delay(remaining, function()
		if not player or not player.Parent then
			return
		end
		RefreshLimitPrisoner(player, true)
		StartRefreshTimer(player)
	end)
end

local function CreatePromptForHome(homeId)
	local prisonModel = GetPrisonModel(homeId)
	if not prisonModel then
		return false
	end

	local primary = GetPrisonPrimaryPart(prisonModel)
	if not primary then
		return false
	end

	local existing = primary:FindFirstChild("LimitPrisonerPrompt")
	if existing and existing:IsA("ProximityPrompt") then
		existing.ActionText = "Click"
		existing.ObjectText = "Limit Prisoner"
		existing.KeyboardKeyCode = (LimitPrisonerConfig.Proximity and LimitPrisonerConfig.Proximity.KeyCode) or Enum.KeyCode.E
		existing.HoldDuration = (LimitPrisonerConfig.Proximity and LimitPrisonerConfig.Proximity.HoldDuration) or 0
		existing.MaxActivationDistance = (LimitPrisonerConfig.Proximity and LimitPrisonerConfig.Proximity.OpenDistance) or 8
		existing.RequiresLineOfSight = false
		return true
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LimitPrisonerPrompt"
	prompt.ActionText = "Click"
	prompt.ObjectText = "Limit Prisoner"
	prompt.KeyboardKeyCode = (LimitPrisonerConfig.Proximity and LimitPrisonerConfig.Proximity.KeyCode) or Enum.KeyCode.E
	prompt.HoldDuration = (LimitPrisonerConfig.Proximity and LimitPrisonerConfig.Proximity.HoldDuration) or 0
	prompt.MaxActivationDistance = (LimitPrisonerConfig.Proximity and LimitPrisonerConfig.Proximity.OpenDistance) or 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = primary

	return true
end

local function HandleRequestData(player)
	if not player or not player.Parent then
		return
	end

	local data = EnsureLimitPrisonerData(player)
	if not data then
		return
	end

	RefreshLimitPrisoner(player, false)
end

local function HandlePurchaseGold(player)
	if not player or not player.Parent then
		return
	end

	if purchaseLocks[player] then
		SendPurchaseResult(player, false, "购买处理中", "Gold")
		return
	end

	purchaseLocks[player] = true

	local data = EnsureLimitPrisonerData(player)
	if not data then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "数据加载失败", "Gold")
		return
	end

	if not IsPlayerNearPrison(player) then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "距离太远，无法购买", "Gold")
		return
	end

	if data.GoldPurchased then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "已购买", "Gold")
		return
	end

	local unitId = tostring(data.CurrentUnitId or "")
	local config = LimitPrisonerConfig.GetPrisonerByUnitId(unitId)
	local price = config and tonumber(config.GoldPrice) or 0
	if unitId == "" or price <= 0 then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "商品配置错误", "Gold")
		return
	end

	if not CurrencySystem.HasEnoughCoins(player, price) then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "金币不足", "Gold")
		return
	end

	local removeSuccess, newCoins = CurrencySystem.RemoveCoins(player, price, "LimitPrisonerGold")
	if not removeSuccess then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "扣除金币失败", "Gold")
		return
	end

	local addSuccess, instanceData = InventorySystem.AddUnit(player, unitId)
	if not addSuccess then
		CurrencySystem.AddCoins(player, price, "LimitPrisonerGoldRefund")
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "发放失败", "Gold")
		return
	end

	NotifyPurchaseTask(player, unitId)

	data.GoldPurchased = true
	if DataManager then
		DataManager.SavePlayerDataThrottled(player)
	end

	SendData(player, data)
	SendPurchaseResult(player, true, "购买成功", "Gold", unitId, newCoins)

	purchaseLocks[player] = nil
end

local function HandlePurchaseRobux(player)
	if not player or not player.Parent then
		return
	end

	if purchaseLocks[player] then
		SendPurchaseResult(player, false, "购买处理中", "Robux")
		return
	end

	purchaseLocks[player] = true

	local data = EnsureLimitPrisonerData(player)
	if not data then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "数据加载失败", "Robux")
		return
	end

	if not IsPlayerNearPrison(player) then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "距离太远，无法购买", "Robux")
		return
	end

	local unitId = tostring(data.CurrentUnitId or "")
	local config = LimitPrisonerConfig.GetPrisonerByUnitId(unitId)
	local devProductId = config and tonumber(config.DevProductId) or 0
	if unitId == "" or devProductId <= 0 then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "商品配置错误", "Robux")
		return
	end

	local success = pcall(function()
		MarketplaceService:PromptProductPurchase(player, devProductId)
	end)

	if not success then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "无法打开购买界面", "Robux")
		return
	end

	purchaseLocks[player] = nil
end

local function HandleRedeem(player)
	if not player or not player.Parent then
		return
	end

	if purchaseLocks[player] then
		SendRedeemResult(player, false, "兑换处理中")
		return
	end

	purchaseLocks[player] = true

	local data = EnsureLimitPrisonerData(player)
	if not data then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "数据加载失败")
		return
	end

	if not IsPlayerNearPrison(player) then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "距离太远，无法兑换")
		return
	end

	if data.Redeemed then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "已兑换")
		return
	end

	local unitId = tostring(data.CurrentUnitId or "")
	local config = LimitPrisonerConfig.GetPrisonerByUnitId(unitId)
	local cost = config and tonumber(config.HandcuffCost) or 0
	if unitId == "" or cost <= 0 then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "兑换配置错误")
		return
	end

	local removeSuccess = DataManager.RemoveHandcuffs(player, cost)
	if not removeSuccess then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "手铐不足")
		return
	end

	local addSuccess, instanceData = InventorySystem.AddUnit(player, unitId)
	if not addSuccess then
		DataManager.AddHandcuffs(player, cost)
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "发放失败")
		return
	end

	NotifyPurchaseTask(player, unitId)

	data.Redeemed = true
	if DataManager then
		DataManager.SavePlayerDataThrottled(player)
	end

	local rewardInfo = {
		Type = "Unit",
		UnitId = unitId,
		Count = 1,
	}

	SendData(player, data)
	SendRedeemResult(player, true, "兑换成功", rewardInfo)

	purchaseLocks[player] = nil
end

-- ==================== 公共接口 ====================

HandlePurchaseGold = function(player)
	if not player or not player.Parent then
		return
	end

	if purchaseLocks[player] then
		SendPurchaseResult(player, false, "Purchase already in progress.", "Gold")
		return
	end

	purchaseLocks[player] = true

	local data = EnsureLimitPrisonerData(player)
	if not data then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Failed to load data.", "Gold")
		return
	end

	if not IsPlayerNearPrison(player) then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Too far away to purchase.", "Gold")
		return
	end

	if data.GoldPurchased then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Already purchased with coins.", "Gold")
		return
	end

	local unitId = tostring(data.CurrentUnitId or "")
	local config = LimitPrisonerConfig.GetPrisonerByUnitId(unitId)
	local price = config and tonumber(config.GoldPrice) or 0
	if unitId == "" or price <= 0 then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Invalid product config.", "Gold")
		return
	end

	if not CurrencySystem.HasEnoughCoins(player, price) then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Not enough coins.", "Gold")
		return
	end

	local removeSuccess, newCoins = CurrencySystem.RemoveCoins(player, price, "LimitPrisonerGold")
	if not removeSuccess then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Failed to deduct coins.", "Gold")
		return
	end

	local addSuccess = InventorySystem.AddUnit(player, unitId)
	if not addSuccess then
		CurrencySystem.AddCoins(player, price, "LimitPrisonerGoldRefund")
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Failed to grant unit.", "Gold")
		return
	end

	NotifyPurchaseTask(player, unitId)

	data.GoldPurchased = true
	if DataManager then
		DataManager.SavePlayerDataThrottled(player)
	end

	SendData(player, data)
	SendPurchaseResult(player, true, "Purchase successful.", "Gold", unitId, newCoins)

	purchaseLocks[player] = nil
end

HandlePurchaseRobux = function(player)
	if not player or not player.Parent then
		return
	end

	if purchaseLocks[player] then
		SendPurchaseResult(player, false, "Purchase already in progress.", "Robux")
		return
	end

	purchaseLocks[player] = true

	local data = EnsureLimitPrisonerData(player)
	if not data then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Failed to load data.", "Robux")
		return
	end

	if not IsPlayerNearPrison(player) then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Too far away to purchase.", "Robux")
		return
	end

	local unitId = tostring(data.CurrentUnitId or "")
	local config = LimitPrisonerConfig.GetPrisonerByUnitId(unitId)
	local devProductId = config and tonumber(config.DevProductId) or 0
	if unitId == "" or devProductId <= 0 then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Invalid product config.", "Robux")
		return
	end

	local success = pcall(function()
		MarketplaceService:PromptProductPurchase(player, devProductId)
	end)

	if not success then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Unable to open purchase prompt.", "Robux")
		return
	end

	purchaseLocks[player] = nil
end

HandleRedeem = function(player)
	if not player or not player.Parent then
		return
	end

	if purchaseLocks[player] then
		SendRedeemResult(player, false, "Redeem already in progress.")
		return
	end

	purchaseLocks[player] = true

	local data = EnsureLimitPrisonerData(player)
	if not data then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "Failed to load data.")
		return
	end

	if not IsPlayerNearPrison(player) then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "Too far away to redeem.")
		return
	end

	if data.Redeemed then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "Already redeemed.")
		return
	end

	local unitId = tostring(data.CurrentUnitId or "")
	local config = LimitPrisonerConfig.GetPrisonerByUnitId(unitId)
	local cost = config and tonumber(config.HandcuffCost) or 0
	if unitId == "" or cost <= 0 then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "Invalid redemption config.")
		return
	end

	local removeSuccess = DataManager.RemoveHandcuffs(player, cost)
	if not removeSuccess then
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "Not enough handcuffs.")
		return
	end

	local addSuccess = InventorySystem.AddUnit(player, unitId)
	if not addSuccess then
		DataManager.AddHandcuffs(player, cost)
		purchaseLocks[player] = nil
		SendRedeemResult(player, false, "Failed to grant unit.")
		return
	end

	NotifyPurchaseTask(player, unitId)

	data.Redeemed = true
	if DataManager then
		DataManager.SavePlayerDataThrottled(player)
	end

	local rewardInfo = {
		Type = "Unit",
		UnitId = unitId,
		Count = 1,
	}

	SendData(player, data)
	SendRedeemResult(player, true, "Redeem successful.", rewardInfo)

	purchaseLocks[player] = nil
end

function LimitPrisonerSystem.Initialize()
	if not InitializeModules() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	if requestDataEvent then
		requestDataEvent.OnServerEvent:Connect(HandleRequestData)
	end
	if purchaseGoldEvent then
		purchaseGoldEvent.OnServerEvent:Connect(HandlePurchaseGold)
	end
	if purchaseRobuxEvent then
		purchaseRobuxEvent.OnServerEvent:Connect(HandlePurchaseRobux)
	end
	if redeemEvent then
		redeemEvent.OnServerEvent:Connect(HandleRedeem)
	end

	return true
end

function LimitPrisonerSystem.SyncPlayer(player)
	local data = EnsureLimitPrisonerData(player)
	if not data then
		return false
	end
	SendData(player, data)
	return true
end

function LimitPrisonerSystem.OnPlayerJoin(player)
	if not player or not player.Parent then
		return
	end

	local data = EnsureLimitPrisonerData(player)
	if not data then
		return
	end

	RefreshLimitPrisoner(player, false)

	local homeId = GetPlayerHomeId(player)
	if homeId then
		CreatePromptForHome(homeId)
	end

	StartRefreshTimer(player)
	StartCountdown(player)
end

function LimitPrisonerSystem.OnPlayerLeave(player)
	StopRefreshTimer(player)
	StopCountdown(player)
	refreshLocks[player] = nil
	purchaseLocks[player] = nil
end

return LimitPrisonerSystem
