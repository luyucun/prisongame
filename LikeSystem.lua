--[[
脚本名称: LikeSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/LikeSystem
职责:
1. 处理家园 Information/InfoPart/ProximityPrompt 点赞交互
2. 校验点赞目标（非自己、非空家园）
3. 累加并持久化点赞数据
4. 通知被点赞玩家显示提示
]]

local LikeSystem = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

local DataManager = nil

local HOME_OWNER_ATTR = "HomeOwnerUserId"
local HOME_FOLDER_NAME = GameConfig.HOME_FOLDER_NAME or "Home"
local HOME_PREFIX = GameConfig.HOME_PREFIX or "PlayerHome"
local MIN_HOME_SLOT = tonumber(GameConfig.MIN_HOME_SLOT) or 1
local MAX_HOME_SLOT = tonumber(GameConfig.MAX_HOME_SLOT) or 6

local INFORMATION_NAME = "Information"
local INFO_PART_NAME = "InfoPart"
local PROMPT_NAME = "ProximityPrompt"

local LIKE_PROMPT_ATTR = "LikePrompt"
local LIKE_HOME_ID_ATTR = "LikeHomeId"
local LIKE_OWNER_ATTR = "LikeOwnerUserId"
local LIKE_SURFACE_GUIS = { "SurfaceGui01", "SurfaceGui02" }

local likeToastEvent = nil
local likeStateSyncEvent = nil
local promptsByHomeId = {}
local promptConnections = {}
local ownerConnections = {}
local homeAddedConnection = nil
local workspaceAddedConnection = nil
local playerAddedConnection = nil
local initialized = false
local maintenanceToken = nil

local function IsValidOwnerUserId(userId)
	return type(userId) == "number" and userId ~= 0 and userId == math.floor(userId)
end

local function DisconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function InitializeDependencies()
	if DataManager then
		return true
	end

	local dataModule = ServerScriptService:WaitForChild("Core"):FindFirstChild("DataManager")
	if not dataModule then
		warn("[LikeSystem] DataManager module missing")
		return false
	end

	DataManager = require(dataModule)
	return true
end

local function InitializeEvents()
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	local likeEvents = eventsFolder:FindFirstChild("LikeEvents")
	if not likeEvents then
		likeEvents = Instance.new("Folder")
		likeEvents.Name = "LikeEvents"
		likeEvents.Parent = eventsFolder
	end

	local event = likeEvents:FindFirstChild("LikeToast")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "LikeToast"
		event.Parent = likeEvents
	end
	local stateSyncEvent = likeEvents:FindFirstChild("LikeStateSync")
	if not stateSyncEvent then
		stateSyncEvent = Instance.new("RemoteEvent")
		stateSyncEvent.Name = "LikeStateSync"
		stateSyncEvent.Parent = likeEvents
	end

	likeToastEvent = event
	likeStateSyncEvent = stateSyncEvent
	return true
end

local function GetGivenLikeTargetList(player)
	if not player or not player:IsDescendantOf(Players) then
		return {}
	end
	if not DataManager or not DataManager.GetGivenLikeTargetList then
		return {}
	end

	local ok, result = pcall(function()
		return DataManager.GetGivenLikeTargetList(player)
	end)
	if not ok or type(result) ~= "table" then
		return {}
	end

	return result
end

local function SyncLikeStateForPlayer(player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	if DataManager and DataManager.WaitForPlayerData then
		pcall(function()
			DataManager.WaitForPlayerData(player, 8)
		end)
	end

	if not player or not player:IsDescendantOf(Players) then
		return
	end
	if not likeStateSyncEvent then
		return
	end

	likeStateSyncEvent:FireClient(player, "full", GetGivenLikeTargetList(player))
end

local function PushLikeStateAdd(player, targetUserId)
	if not likeStateSyncEvent then
		return
	end
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	likeStateSyncEvent:FireClient(player, "add", targetUserId)
end

local function StartLikeStateSync()
	DisconnectConnection(playerAddedConnection)
	playerAddedConnection = Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			SyncLikeStateForPlayer(player)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			SyncLikeStateForPlayer(player)
		end)
	end
end

local function GetHomeRoot()
	return Workspace:FindFirstChild(HOME_FOLDER_NAME)
end

local function GetHomeModel(homeId)
	local homeRoot = GetHomeRoot()
	if not homeRoot then
		return nil
	end

	return homeRoot:FindFirstChild(HOME_PREFIX .. tostring(homeId))
end

local function GetInfoPart(homeModel)
	if not homeModel then
		return nil
	end

	local information = homeModel:FindFirstChild(INFORMATION_NAME)
	if not information then
		return nil
	end

	local function ResolvePromptHost(node)
		if not node then
			return nil
		end
		if node:IsA("BasePart") then
			return node
		end
		if node:IsA("Attachment") and node.Parent and node.Parent:IsA("BasePart") then
			return node.Parent
		end

		if node:IsA("Model") or node:IsA("Folder") then
			for _, descendant in ipairs(node:GetDescendants()) do
				if descendant:IsA("BasePart") then
					return descendant
				end
			end
		end

		return nil
	end

	local infoPart = information:FindFirstChild(INFO_PART_NAME)
	local resolved = ResolvePromptHost(infoPart)
	if resolved then
		return resolved
	end

	local infoPartDesc = information:FindFirstChild(INFO_PART_NAME, true)
	resolved = ResolvePromptHost(infoPartDesc)
	if resolved then
		return resolved
	end

	local fallbackPart = information:FindFirstChild("Part")
	resolved = ResolvePromptHost(fallbackPart)
	if resolved then
		return resolved
	end

	return nil
end

local function ResolveOwnerLikeCount(ownerUserId, fallbackLikeCount)
	if type(fallbackLikeCount) == "number" then
		local forcedCount = math.floor(fallbackLikeCount)
		if forcedCount < 0 then
			forcedCount = 0
		end
		return forcedCount
	end

	if not IsValidOwnerUserId(ownerUserId) then
		return 0
	end

	local ownerPlayer = nil
	local ok, result = pcall(function()
		return Players:GetPlayerByUserId(ownerUserId)
	end)
	if ok then
		ownerPlayer = result
	end
	if not ownerPlayer then
		return 0
	end

	local attrCount = math.floor(tonumber(ownerPlayer:GetAttribute("LikeCount")) or 0)
	if attrCount > 0 then
		return attrCount
	end

	if DataManager and DataManager.GetLikeCount then
		local okCount, count = pcall(function()
			return DataManager.GetLikeCount(ownerPlayer)
		end)
		if okCount then
			local safeCount = math.floor(tonumber(count) or 0)
			if safeCount > 0 then
				return safeCount
			end
		end
	end

	return 0
end

local function UpdateLikeDisplayForHome(homeId, fallbackLikeCount)
	local homeModel = GetHomeModel(homeId)
	if not homeModel then
		return false
	end

	local infoPart = GetInfoPart(homeModel)
	if not infoPart then
		return false
	end

	local ownerUserId = homeModel:GetAttribute(HOME_OWNER_ATTR)
	local likeCount = ResolveOwnerLikeCount(ownerUserId, fallbackLikeCount)
	local likeText = tostring(likeCount)

	for _, guiName in ipairs(LIKE_SURFACE_GUIS) do
		local surfaceGui = infoPart:FindFirstChild(guiName) or infoPart:FindFirstChild(guiName, true)
		if surfaceGui and surfaceGui:IsA("SurfaceGui") then
			local frame = surfaceGui:FindFirstChild("Frame")
			local playerLike = frame and frame:FindFirstChild("PlayerLike")
			local numLabel = playerLike and playerLike:FindFirstChild("Num")
			if numLabel and numLabel:IsA("TextLabel") then
				numLabel.Text = likeText
			end
		end
	end

	return true
end

local function GetOrCreatePrompt(homeId, homeModel)
	local information = homeModel and homeModel:FindFirstChild(INFORMATION_NAME)
	local prompt = nil

	if information then
		prompt = information:FindFirstChild(PROMPT_NAME, true)
		if prompt and not prompt:IsA("ProximityPrompt") then
			prompt = nil
		end

		if not prompt then
			for _, descendant in ipairs(information:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") then
					prompt = descendant
					break
				end
			end
		end
	end

	if prompt then
		prompt:SetAttribute(LIKE_PROMPT_ATTR, true)
		prompt:SetAttribute(LIKE_HOME_ID_ATTR, homeId)
		return prompt
	end

	local infoPart = GetInfoPart(homeModel)
	if not infoPart then
		return nil
	end

	prompt = infoPart:FindFirstChild(PROMPT_NAME)
	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt = nil
	end

	if not prompt then
		prompt = infoPart:FindFirstChild(PROMPT_NAME, true)
		if prompt and not prompt:IsA("ProximityPrompt") then
			prompt = nil
		end
	end

	if not prompt then
		for _, descendant in ipairs(infoPart:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") then
				prompt = descendant
				break
			end
		end
	end

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.ActionText = "Like"
		prompt.ObjectText = "Player"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0.1
		prompt.RequiresLineOfSight = false
		prompt.Parent = infoPart
	end

	prompt:SetAttribute(LIKE_PROMPT_ATTR, true)
	prompt:SetAttribute(LIKE_HOME_ID_ATTR, homeId)
	return prompt
end

local function UpdatePromptState(homeId)
	local homeModel = GetHomeModel(homeId)
	if not homeModel then
		return
	end

	UpdateLikeDisplayForHome(homeId)

	local prompt = promptsByHomeId[homeId]
	if not prompt or not prompt.Parent then
		return
	end

	local ownerUserId = homeModel:GetAttribute(HOME_OWNER_ATTR)
	local hasOwner = IsValidOwnerUserId(ownerUserId)

	prompt.Enabled = hasOwner

	if hasOwner then
		prompt:SetAttribute(LIKE_OWNER_ATTR, ownerUserId)
	else
		prompt:SetAttribute(LIKE_OWNER_ATTR, nil)
	end
end

local function ResolveTargetByHome(homeId)
	local homeModel = GetHomeModel(homeId)
	if not homeModel then
		return nil, nil
	end

	local ownerUserId = homeModel:GetAttribute(HOME_OWNER_ATTR)
	if not IsValidOwnerUserId(ownerUserId) then
		return nil, nil
	end

	local ownerPlayer = nil
	local getByUserIdOk, getByUserIdResult = pcall(function()
		return Players:GetPlayerByUserId(ownerUserId)
	end)
	if getByUserIdOk then
		ownerPlayer = getByUserIdResult
	end
	if not ownerPlayer then
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer.UserId == ownerUserId then
				ownerPlayer = otherPlayer
				break
			end
		end
	end
	return ownerPlayer, ownerUserId
end

local function HandlePromptTriggered(homeId, likerPlayer)
	if not likerPlayer or not likerPlayer.Parent then
		return
	end

	local targetPlayer, targetUserId = ResolveTargetByHome(homeId)
	if not targetPlayer or not targetUserId then
		return
	end

	if likerPlayer.UserId == targetUserId then
		return
	end

	if not DataManager or not DataManager.AddLike or not DataManager.MarkLikedTarget then
		return
	end

	if DataManager.HasLikedTarget and DataManager.HasLikedTarget(likerPlayer, targetUserId) then
		PushLikeStateAdd(likerPlayer, targetUserId)
		return
	end

	if not DataManager.MarkLikedTarget(likerPlayer, targetUserId) then
		PushLikeStateAdd(likerPlayer, targetUserId)
		return
	end

	local newLikeCount = DataManager.AddLike(targetPlayer, 1)
	UpdateLikeDisplayForHome(homeId, newLikeCount)

	if DataManager.SavePlayerDataThrottled then
		DataManager.SavePlayerDataThrottled(targetPlayer)
		DataManager.SavePlayerDataThrottled(likerPlayer)
	end

	PushLikeStateAdd(likerPlayer, targetUserId)

	if likeToastEvent then
		likeToastEvent:FireClient(targetPlayer, likerPlayer.Name, newLikeCount)
	end
end

local function BindPromptForHome(homeId)
	local homeModel = GetHomeModel(homeId)
	if not homeModel then
		return false
	end

	DisconnectConnection(promptConnections[homeId])
	promptConnections[homeId] = nil

	DisconnectConnection(ownerConnections[homeId])
	ownerConnections[homeId] = nil

	local prompt = GetOrCreatePrompt(homeId, homeModel)
	if not prompt then
		return false
	end

	promptsByHomeId[homeId] = prompt
	promptConnections[homeId] = prompt.Triggered:Connect(function(player)
		HandlePromptTriggered(homeId, player)
	end)
	ownerConnections[homeId] = homeModel:GetAttributeChangedSignal(HOME_OWNER_ATTR):Connect(function()
		UpdatePromptState(homeId)
	end)

	UpdatePromptState(homeId)
	return true
end

local function TryBindPromptWithRetry(homeId)
	local maxRetries = 8
	local retryDelay = 1

	for attempt = 1, maxRetries do
		if BindPromptForHome(homeId) then
			return true
		end
		if attempt < maxRetries then
			task.wait(retryDelay)
		end
	end

	warn(string.format("[LikeSystem] Failed to bind like prompt for home %d", homeId))
	return false
end

local function ParseHomeId(name)
	if type(name) ~= "string" then
		return nil
	end
	if string.sub(name, 1, #HOME_PREFIX) ~= HOME_PREFIX then
		return nil
	end

	local suffix = string.sub(name, #HOME_PREFIX + 1)
	local homeId = math.floor(tonumber(suffix) or -1)
	if homeId < MIN_HOME_SLOT or homeId > MAX_HOME_SLOT then
		return nil
	end
	return homeId
end

local function BindAllPrompts()
	for homeId = MIN_HOME_SLOT, MAX_HOME_SLOT do
		task.spawn(function()
			TryBindPromptWithRetry(homeId)
		end)
	end
end

local function ObserveHomeRoot()
	DisconnectConnection(homeAddedConnection)
	homeAddedConnection = nil

	local homeRoot = GetHomeRoot()
	if not homeRoot then
		return false
	end

	homeAddedConnection = homeRoot.ChildAdded:Connect(function(child)
		local homeId = ParseHomeId(child.Name)
		if not homeId then
			return
		end
		task.spawn(function()
			TryBindPromptWithRetry(homeId)
		end)
	end)

	return true
end

local function ObserveHomeRootCreation()
	DisconnectConnection(workspaceAddedConnection)
	workspaceAddedConnection = Workspace.ChildAdded:Connect(function(child)
		if child and child.Name == HOME_FOLDER_NAME then
			DisconnectConnection(workspaceAddedConnection)
			workspaceAddedConnection = nil
			ObserveHomeRoot()
			BindAllPrompts()
		end
	end)
end

local function StartPromptMaintenance()
	local token = {}
	maintenanceToken = token

	task.spawn(function()
		while maintenanceToken == token do
			for homeId = MIN_HOME_SLOT, MAX_HOME_SLOT do
				UpdateLikeDisplayForHome(homeId)
				local prompt = promptsByHomeId[homeId]
				if not prompt or not prompt.Parent then
					BindPromptForHome(homeId)
				else
					UpdatePromptState(homeId)
				end
			end
			task.wait(2)
		end
	end)
end

function LikeSystem.Initialize()
	if initialized then
		return true
	end

	if not InitializeDependencies() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	StartLikeStateSync()
	BindAllPrompts()
	local hasHomeRoot = ObserveHomeRoot()
	if not hasHomeRoot then
		ObserveHomeRootCreation()
	end
	StartPromptMaintenance()

	initialized = true
	return true
end

return LikeSystem
