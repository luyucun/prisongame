--[[
Script Name: VipSystem
Script Type: ModuleScript (Server System)
Script Location: ServerScriptService/Systems/VipSystem
Version: V5.5
Responsibility: VIP game pass purchase, status sync, tag/ICON handling
]]

local VipSystem = {}

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local VipConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("VipConfig"))

local DataManager = nil

local vipEvents = nil
local requestDataEvent = nil
local vipDataEvent = nil
local purchaseEvent = nil
local purchaseResultEvent = nil

local purchaseLocks = {}
local chatService = nil
local textChatWrapped = false

-- ==================== Helpers ====================

local function InitializeModules()
	if DataManager then
		return true
	end

	local dataModule = ServerScriptService.Core:FindFirstChild("DataManager")
	if dataModule then
		DataManager = require(dataModule)
		return true
	end

	warn("[VipSystem] DataManager not found")
	return false
end

local function InitializeEvents()
	if vipEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	vipEvents = eventsFolder:FindFirstChild("VipEvents")
	if not vipEvents then
		vipEvents = Instance.new("Folder")
		vipEvents.Name = "VipEvents"
		vipEvents.Parent = eventsFolder
	end

	local function GetOrCreateEvent(name)
		local event = vipEvents:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = vipEvents
		end
		return event
	end

	requestDataEvent = GetOrCreateEvent("RequestVipData")
	vipDataEvent = GetOrCreateEvent("VipData")
	purchaseEvent = GetOrCreateEvent("PurchaseVip")
	purchaseResultEvent = GetOrCreateEvent("VipPurchaseResult")

	return true
end

local function EnsureVipData(player)
	if not InitializeModules() then
		return nil
	end

	local vipData = DataManager.GetVipData(player)
	if not vipData then
		DataManager.WaitForPlayerData(player, 10)
		vipData = DataManager.GetVipData(player)
	end

	return vipData
end

local function SendData(player, vipData)
	local purchased = vipData and vipData.Purchased == true and vipData.ForceDisabled ~= true
	player:SetAttribute("VipPurchased", purchased)

	if vipDataEvent then
		vipDataEvent:FireClient(player, {
			Purchased = purchased,
			ForceDisabled = vipData and vipData.ForceDisabled == true or false
		})
	end
end

local function SendPurchaseResult(player, success, message)
	if purchaseResultEvent then
		purchaseResultEvent:FireClient(player, success, message or "")
	end
end

local function GetVipIconTemplate()
	return ReplicatedStorage:FindFirstChild("VipIcon")
end

local function RemoveVipIcon(character)
	if not character then
		return
	end

	local existing = character:FindFirstChild("VipIcon")
	if existing then
		existing:Destroy()
	end
end

local function AttachVipIcon(character)
	if not character then
		return
	end

	if character:FindFirstChild("VipIcon") then
		return
	end

	local template = GetVipIconTemplate()
	if not template then
		warn("[VipSystem] VipIcon not found in ReplicatedStorage")
		return
	end

	local clone = template:Clone()
	clone.Name = "VipIcon"

	if clone:IsA("BillboardGui") then
		local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
		if head and clone.Adornee == nil then
			clone.Adornee = head
		end
		if head then
			clone.Parent = head
		else
			clone.Parent = character
		end
		return
	end

	clone.Parent = character
	local target = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if clone:IsA("BasePart") and target then
		clone.CFrame = target.CFrame * CFrame.new(0, 2.5, 0)
		clone.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = target
		weld.Part1 = clone
		weld.Parent = clone
	end
end

local function ApplyVipIcon(player, purchased)
	local character = player.Character
	if purchased then
		AttachVipIcon(character)
	else
		RemoveVipIcon(character)
	end
end

local ApplyLegacyChatTag

local function InitializeLegacyChat()
	if chatService then
		return true
	end

	local runner = ServerScriptService:FindFirstChild("ChatServiceRunner")
	if not runner then
		return false
	end

	local success, result = pcall(function()
		return require(runner:WaitForChild("ChatService"))
	end)

	if success and result then
		chatService = result
		chatService.SpeakerAdded:Connect(function(speakerName)
			local speaker = chatService:GetSpeaker(speakerName)
			if not speaker then
				return
			end
			local player = Players:FindFirstChild(speakerName)
			if player then
				ApplyLegacyChatTag(player, VipSystem.IsVipCached(player))
			end
		end)
		return true
	end

	warn("[VipSystem] ChatService init failed:", result)
	return false
end

local function BuildLegacyTags(existingTags, purchased)
	local tags = {}
	local hasVip = false

	if type(existingTags) == "table" then
		for _, tag in ipairs(existingTags) do
			if type(tag) == "table" then
				local tagText = tag.TagText
				if tagText == "VIP" then
					hasVip = true
					if purchased then
						table.insert(tags, { TagText = "VIP", TagColor = VipConfig.TAG_COLOR })
					end
				else
					table.insert(tags, tag)
				end
			end
		end
	end

	if purchased and not hasVip then
		table.insert(tags, 1, { TagText = "VIP", TagColor = VipConfig.TAG_COLOR })
	end

	return tags
end

ApplyLegacyChatTag = function(player, purchased)
	if not chatService then
		return
	end

	local speaker = chatService:GetSpeaker(player.Name)
	if not speaker then
		return
	end

	local existingTags = nil
	pcall(function()
		existingTags = speaker:GetExtraData("Tags")
	end)
	local tags = BuildLegacyTags(existingTags, purchased)
	speaker:SetExtraData("Tags", tags)
end

local function InitializeTextChat()
	if RunService:IsServer() then
		return false
	end
	if textChatWrapped then
		return true
	end

	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return false
	end

	pcall(function()
		local windowConfig = TextChatService.ChatWindowConfiguration
		if windowConfig then
			windowConfig.RichText = true
		end
	end)

	local original = nil
	pcall(function()
		original = TextChatService.OnIncomingMessage
	end)
	TextChatService.OnIncomingMessage = function(message)
		local properties = nil
		if original then
			properties = original(message)
		end
		if not properties then
			properties = Instance.new("TextChatMessageProperties")
		end

		local textSource = message and message.TextSource
		if textSource then
			local player = Players:GetPlayerByUserId(textSource.UserId)
			if player and VipSystem.IsVipCached(player) then
				local prefix = message.PrefixText or ""
				if prefix ~= "" and not string.find(prefix, VipConfig.TAG_TEXT, 1, true) then
					properties.PrefixText = string.format(
						"<font color=\"#FFD700\">%s</font> %s",
						VipConfig.TAG_TEXT,
						prefix
					)
				end
			end
		end

		return properties
	end

	textChatWrapped = true
	return true
end

local function CheckVipOwnership(player)
	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, VipConfig.GAMEPASS_ID)
	end)

	if success then
		return result == true
	end

	warn("[VipSystem] UserOwnsGamePassAsync failed:", result)
	return false
end

local function ApplyVipStatus(player, purchased, saveData)
	local vipData = EnsureVipData(player)
	if not vipData then
		return false
	end

	local effectivePurchased = purchased == true and vipData.ForceDisabled ~= true

	if vipData.Purchased == effectivePurchased then
		player:SetAttribute("VipPurchased", effectivePurchased)
		ApplyVipIcon(player, effectivePurchased)
		ApplyLegacyChatTag(player, effectivePurchased)
		return true
	end

	vipData.Purchased = effectivePurchased
	player:SetAttribute("VipPurchased", vipData.Purchased)

	if saveData then
		DataManager.SavePlayerDataThrottled(player)
	end

	ApplyVipIcon(player, vipData.Purchased)
	ApplyLegacyChatTag(player, vipData.Purchased)
	return true
end

local function HandlePurchaseSuccess(player)
	local vipData = EnsureVipData(player)
	if not vipData then
		SendPurchaseResult(player, false, "Data load failed")
		return
	end

	if vipData.Purchased == true and vipData.ForceDisabled ~= true then
		SendPurchaseResult(player, false, "Already purchased")
		return
	end

	if DataManager.SetVipForceDisabled then
		DataManager.SetVipForceDisabled(player, false)
	end
	DataManager.SetVipPurchased(player, true)
	DataManager.SavePlayerDataThrottled(player)

	ApplyVipStatus(player, true, false)
	SendData(player, vipData)
	SendPurchaseResult(player, true, "Purchase Successful!")
end

local function HandlePurchaseRequest(player)
	if not player or not player.Parent then
		return
	end

	if purchaseLocks[player] then
		return
	end
	purchaseLocks[player] = true

	local vipData = EnsureVipData(player)
	if not vipData then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Data load failed")
		return
	end

	if vipData.Purchased == true then
		purchaseLocks[player] = nil
		SendPurchaseResult(player, false, "Already purchased")
		return
	end

	local ownsPass = CheckVipOwnership(player)
	if ownsPass then
		purchaseLocks[player] = nil
		HandlePurchaseSuccess(player)
		return
	end

	local promptOk, promptErr = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, VipConfig.GAMEPASS_ID)
	end)
	if not promptOk then
		purchaseLocks[player] = nil
		warn("[VipSystem] PromptGamePassPurchase failed:", promptErr)
		SendPurchaseResult(player, false, "Purchase failed")
	end
end

local function HandleRequestData(player)
	if not player or not player.Parent then
		return
	end

	VipSystem.SyncPlayer(player)
end

-- ==================== Public API ====================

function VipSystem.IsVipCached(player)
	if not player then
		return false
	end

	if DataManager and DataManager.GetVipData then
		local vipData = DataManager.GetVipData(player)
		if vipData and vipData.ForceDisabled == true then
			return false
		end
		if vipData and vipData.Purchased == true then
			return true
		end
	end

	return player:GetAttribute("VipPurchased") == true
end

function VipSystem.IsVip(player)
	if not player then
		return false
	end

	local vipData = EnsureVipData(player)
	if vipData and vipData.ForceDisabled == true then
		return false
	end

	if vipData and vipData.Purchased == true then
		return true
	end

	return player:GetAttribute("VipPurchased") == true
end

function VipSystem.ApplyCoinBonus(player, amount, options)
	local baseAmount = tonumber(amount) or 0
	if baseAmount <= 0 then
		return baseAmount, 0
	end

	if options and (options.ApplyVipBonus == false or options.NoVipBonus == true) then
		return baseAmount, 0
	end

	if not VipSystem.IsVip(player) then
		return baseAmount, 0
	end

	return VipConfig.CalculateBonusAmount(baseAmount)
end

function VipSystem.SyncPlayer(player)
	local vipData = EnsureVipData(player)
	if not vipData then
		return false
	end

	if vipData.ForceDisabled == true then
		if vipData.Purchased == true then
			DataManager.SetVipPurchased(player, false)
			vipData.Purchased = false
			DataManager.SavePlayerDataThrottled(player)
		end
	else
		if vipData.Purchased ~= true then
			if CheckVipOwnership(player) then
				DataManager.SetVipPurchased(player, true)
				DataManager.SavePlayerDataThrottled(player)
				vipData.Purchased = true
			end
		end
	end

	ApplyVipStatus(player, vipData.Purchased == true, false)
	SendData(player, vipData)
	return true
end

function VipSystem.GMResetVip(player)
	if not player or not player.Parent then
		return false, "Invalid player"
	end

	local vipData = EnsureVipData(player)
	if not vipData then
		return false, "Data load failed"
	end

	if DataManager.SetVipForceDisabled then
		DataManager.SetVipForceDisabled(player, true)
	else
		vipData.ForceDisabled = true
	end
	vipData.Purchased = false
	player:SetAttribute("VipPurchased", false)
	purchaseLocks[player] = nil

	DataManager.SavePlayerDataThrottled(player)
	ApplyVipStatus(player, false, false)
	SendData(player, vipData)

	return true, "VIP reset and disabled"
end

function VipSystem.Initialize()
	if not InitializeModules() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	InitializeLegacyChat()
	InitializeTextChat()

	if requestDataEvent then
		requestDataEvent.OnServerEvent:Connect(HandleRequestData)
	end
	if purchaseEvent then
		purchaseEvent.OnServerEvent:Connect(HandlePurchaseRequest)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if tonumber(gamePassId) ~= VipConfig.GAMEPASS_ID then
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
			VipSystem.SyncPlayer(player)
		end)

		player.CharacterAdded:Connect(function()
			if VipSystem.IsVip(player) then
				AttachVipIcon(player.Character)
			end
		end)

		player:GetAttributeChangedSignal("VipPurchased"):Connect(function()
			local purchased = player:GetAttribute("VipPurchased") == true
			ApplyVipIcon(player, purchased)
			ApplyLegacyChatTag(player, purchased)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		purchaseLocks[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			VipSystem.SyncPlayer(player)
		end)
	end

	return true
end

return VipSystem
