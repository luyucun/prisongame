--[[
Script Name: StarterPackSystem
Script Type: ModuleScript (Server System)
Script Location: ServerScriptService/Systems/StarterPackSystem
Version: V5.4
Responsibility: Handle newbie starter pack game pass purchase and rewards
]]

local StarterPackSystem = {}

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GAMEPASS_ID = 1658798778
local COIN_REWARD_ICON = "rbxassetid://92295649647469"

local REWARD_ITEMS = {
	{ Type = "Unit", UnitId = "10006", Count = 5 },
	{ Type = "Unit", UnitId = "10009", Count = 5 },
	{ Type = "Skill", SkillId = 1003, Count = 5 },
	{ Type = "Coins", Count = 5000, Icon = COIN_REWARD_ICON },
}

local DataManager = nil
local InventorySystem = nil
local SkillSystem = nil
local CurrencySystem = nil

local starterPackEvents = nil
local requestDataEvent = nil
local starterPackDataEvent = nil
local purchaseEvent = nil
local purchaseResultEvent = nil

local purchaseLocks = {}

-- ==================== Helpers ====================

local function InitializeModules()
	if not DataManager then
		local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
		if dataModule then
			DataManager = require(dataModule)
		else
			warn("[StarterPackSystem] DataManager not found")
			return false
		end
	end

	if not InventorySystem then
		local invModule = ServerScriptService.Systems:FindFirstChild("InventorySystem")
		if invModule then
			InventorySystem = require(invModule)
		else
			warn("[StarterPackSystem] InventorySystem not found")
			return false
		end
	end

	if not SkillSystem then
		local skillModule = ServerScriptService.Systems:FindFirstChild("SkillSystem")
		if skillModule then
			SkillSystem = require(skillModule)
		else
			warn("[StarterPackSystem] SkillSystem not found")
			return false
		end
	end

	if not CurrencySystem then
		local currencyModule = ServerScriptService.Systems:FindFirstChild("CurrencySystem")
		if currencyModule then
			CurrencySystem = require(currencyModule)
		else
			warn("[StarterPackSystem] CurrencySystem not found")
			return false
		end
	end

	return true
end

local function InitializeEvents()
	if starterPackEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	starterPackEvents = eventsFolder:FindFirstChild("StarterPackEvents")
	if not starterPackEvents then
		starterPackEvents = Instance.new("Folder")
		starterPackEvents.Name = "StarterPackEvents"
		starterPackEvents.Parent = eventsFolder
	end

	local function GetOrCreateEvent(name)
		local event = starterPackEvents:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = starterPackEvents
		end
		return event
	end

	requestDataEvent = GetOrCreateEvent("RequestStarterPackData")
	starterPackDataEvent = GetOrCreateEvent("StarterPackData")
	purchaseEvent = GetOrCreateEvent("PurchaseStarterPack")
	purchaseResultEvent = GetOrCreateEvent("PurchaseStarterPackResult")

	return true
end

local function EnsureStarterPackData(player)
	if not InitializeModules() then
		return nil
	end

	local packData = DataManager.GetStarterPackData(player)
	if not packData then
		DataManager.WaitForPlayerData(player, 10)
		packData = DataManager.GetStarterPackData(player)
	end

	return packData
end

local function SendData(player, packData)
	local purchased = packData and packData.Purchased == true
	player:SetAttribute("StarterPackPurchased", purchased)

	if starterPackDataEvent then
		starterPackDataEvent:FireClient(player, { Purchased = purchased })
	end
end

local function SendPurchaseResult(player, success, message, rewards)
	if purchaseResultEvent then
		purchaseResultEvent:FireClient(player, success, message or "", rewards)
	end
end

local function RollbackRewards(player, grantedUnits, grantedSkills, grantedCoins)
	if InventorySystem then
		for _, instance in ipairs(grantedUnits) do
			if instance and instance.InstanceId then
				InventorySystem.RemoveUnit(player, instance.InstanceId)
			end
		end
	end

	if DataManager and next(grantedSkills) ~= nil then
		for skillId, count in pairs(grantedSkills) do
			DataManager.RemoveSkill(player, skillId, count)
		end
		if SkillSystem then
			SkillSystem.SyncSkillInventory(player)
		end
	end

	if CurrencySystem and grantedCoins > 0 then
		CurrencySystem.RemoveCoins(player, grantedCoins, "StarterPackRollback")
	end
end

local function GrantRewards(player)
	local grantedUnits = {}
	local grantedSkills = {}
	local grantedCoins = 0
	local rewardPayload = {}

	for _, reward in ipairs(REWARD_ITEMS) do
		local count = tonumber(reward.Count) or 0
		if count <= 0 then
			RollbackRewards(player, grantedUnits, grantedSkills, grantedCoins)
			return false, "Invalid reward config"
		end

		if reward.Type == "Unit" then
			local unitId = tostring(reward.UnitId or "")
			if unitId == "" then
				RollbackRewards(player, grantedUnits, grantedSkills, grantedCoins)
				return false, "Invalid reward config"
			end

			for i = 1, count do
				local success, result = InventorySystem.AddUnit(player, unitId)
				if not success then
					RollbackRewards(player, grantedUnits, grantedSkills, grantedCoins)
					return false, tostring(result or "Unit grant failed")
				end
				if type(result) == "table" and result.InstanceId then
					table.insert(grantedUnits, result)
				end
			end

			table.insert(rewardPayload, {
				Type = "Unit",
				UnitId = unitId,
				Count = count,
			})
		elseif reward.Type == "Skill" then
			local skillId = tonumber(reward.SkillId)
			if not skillId then
				RollbackRewards(player, grantedUnits, grantedSkills, grantedCoins)
				return false, "Invalid reward config"
			end

			local success = SkillSystem.AddSkill(player, skillId, count)
			if not success then
				RollbackRewards(player, grantedUnits, grantedSkills, grantedCoins)
				return false, "Skill grant failed"
			end
			grantedSkills[skillId] = (grantedSkills[skillId] or 0) + count

			table.insert(rewardPayload, {
				Type = "Skill",
				SkillId = skillId,
				Count = count,
			})
		elseif reward.Type == "Coins" then
			local success = CurrencySystem.AddCoins(player, count, "StarterPack")
			if not success then
				RollbackRewards(player, grantedUnits, grantedSkills, grantedCoins)
				return false, "Coin grant failed"
			end
			grantedCoins = grantedCoins + count

			table.insert(rewardPayload, {
				Type = "Coins",
				Count = count,
				Icon = reward.Icon or COIN_REWARD_ICON,
			})
		else
			RollbackRewards(player, grantedUnits, grantedSkills, grantedCoins)
			return false, "Invalid reward config"
		end
	end

	return true, "Purchase Successful!", rewardPayload
end

local function HandlePurchaseSuccess(player)
	local packData = EnsureStarterPackData(player)
	if not packData then
		SendPurchaseResult(player, false, "Data load failed")
		return
	end

	if packData.Purchased == true then
		return
	end

	local success, message, rewards = GrantRewards(player)
	if success then
		DataManager.SetStarterPackPurchased(player, true)
		DataManager.SavePlayerDataThrottled(player)
		SendData(player, packData)
	end

	SendPurchaseResult(player, success, message, rewards)
end

local function HandlePurchaseRequest(player)
	if not player or not player.Parent then
		return
	end

	if purchaseLocks[player] then
		return
	end
	purchaseLocks[player] = true

	local packData = EnsureStarterPackData(player)
	if not packData then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Data load failed")
		return
	end

	if packData.Purchased == true then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Already purchased")
		return
	end

	local ownsPass = false
	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GAMEPASS_ID)
	end)
	if success then
		ownsPass = result == true
	else
		warn("[StarterPackSystem] UserOwnsGamePassAsync failed:", result)
	end

	if ownsPass then
		purchaseLocks[player] = nil
		HandlePurchaseSuccess(player)
		return
	end

	local promptOk, promptErr = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, GAMEPASS_ID)
	end)
	if not promptOk then
		purchaseLocks[player] = nil
		warn("[StarterPackSystem] PromptGamePassPurchase failed:", promptErr)
		SendPurchaseResult(player, false, "Purchase failed")
	end
end

local function HandleRequestData(player)
	if not player or not player.Parent then
		return
	end

	StarterPackSystem.SyncPlayer(player)
end

-- ==================== Public API ====================

function StarterPackSystem.SyncPlayer(player)
	local packData = EnsureStarterPackData(player)
	if not packData then
		return false
	end

	SendData(player, packData)
	return true
end

function StarterPackSystem.GMResetStarterPack(player)
	local packData = EnsureStarterPackData(player)
	if not packData then
		return false, "Data load failed"
	end

	packData.Purchased = false
	DataManager.SavePlayerDataThrottled(player)
	purchaseLocks[player] = nil

	SendData(player, packData)
	return true, "Starter pack reset"
end

function StarterPackSystem.Initialize()
	if not InitializeModules() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	if requestDataEvent then
		requestDataEvent.OnServerEvent:Connect(HandleRequestData)
	end
	if purchaseEvent then
		purchaseEvent.OnServerEvent:Connect(HandlePurchaseRequest)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if tonumber(gamePassId) ~= GAMEPASS_ID then
			return
		end

		if purchaseLocks[player] then
			purchaseLocks[player] = nil
		end

		if not player or not player.Parent then
			return
		end

		if not wasPurchased then
			SendPurchaseResult(player, false, "Purchase canceled")
			return
		end

		HandlePurchaseSuccess(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			StarterPackSystem.SyncPlayer(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		purchaseLocks[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			StarterPackSystem.SyncPlayer(player)
		end)
	end

	return true
end

return StarterPackSystem
