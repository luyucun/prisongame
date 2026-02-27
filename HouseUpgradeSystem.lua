--[[
脚本名称: HouseUpgradeSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/HouseUpgradeSystem
版本: V3.9.1
]]

--[[
房屋升级系统
职责:
1. 根据通关章节替换房屋模型
2. 保持House文件夹结构不变，只替换里面的模型
3. 协调DataManager保存房屋状态
4. V3.9新增：房屋升级镜头表现控制

结构说明：
- Workspace/Home/PlayerHomeX/House (Folder) - 这是房屋文件夹，保持不变
- Workspace/Home/PlayerHomeX/House/PrisonLv1 (Model) - 这是房屋模型，需要替换
- ReplicatedStorage/House/PrisonLv1 (Model) - 房屋模板
- ReplicatedStorage/House/PrisonLv2 (Model) - 升级后的房屋模板

V3.9房屋升级表现流程：
1. 玩家通关章节后点击胜利弹窗确认
2. 玩家重生在基地
3. 服务端通知客户端开始镜头表现
4. 客户端镜头拉高看向房屋（1秒）
5. 等待1秒
6. 服务端替换房屋（旧房屋消失，新房屋出现）
8. 等待1秒
9. 客户端恢复镜头控制

]]

local HouseUpgradeSystem = {}

-- 服务引用
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- 模块引用（延迟加载避免循环依赖）
local DataManager
local HouseConfig
local GameConfig

-- 初始化标记
local isInitialized = false

-- RemoteEvent引用
local HouseUpgradeEvents = nil
local upgradeEventsConnected = false
local pendingShopGuideAfterUpgrade = {}
local GuideSystem = nil
local cachedValidHouseModelNames = nil

--[[
延迟加载GuideSystem（避免循环依赖）
]]
local function GetGuideSystem()
	if not GuideSystem then
		local systemsFolder = ServerScriptService:FindFirstChild("Systems")
		if systemsFolder then
			local guideModule = systemsFolder:FindFirstChild("GuideSystem")
			if guideModule then
				GuideSystem = require(guideModule)
			end
		end
	end
	return GuideSystem
end

--[[
初始化RemoteEvent（V3.9新增）
]]
local function InitializeEvents()
	if HouseUpgradeEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		warn("[HouseUpgradeSystem] Events文件夹不存在")
		return false
	end

	-- 查找或创建HouseUpgradeEvents文件夹
	local houseUpgradeFolder = eventsFolder:FindFirstChild("HouseUpgradeEvents")
	if not houseUpgradeFolder then
		houseUpgradeFolder = Instance.new("Folder")
		houseUpgradeFolder.Name = "HouseUpgradeEvents"
		houseUpgradeFolder.Parent = eventsFolder
		print("[HouseUpgradeSystem] Created HouseUpgradeEvents folder")
	end

	-- 创建StartUpgradeSequence事件（服务端→客户端：开始升级表现）
	local startEvent = houseUpgradeFolder:FindFirstChild("StartUpgradeSequence")
	if not startEvent then
		startEvent = Instance.new("RemoteEvent")
		startEvent.Name = "StartUpgradeSequence"
		startEvent.Parent = houseUpgradeFolder
		print("[HouseUpgradeSystem] 已创建StartUpgradeSequence事件")
	end

	-- 创建ClientCameraReady事件（客户端→服务端：镜头就位）
	local readyEvent = houseUpgradeFolder:FindFirstChild("ClientCameraReady")
	if not readyEvent then
		readyEvent = Instance.new("RemoteEvent")
		readyEvent.Name = "ClientCameraReady"
		readyEvent.Parent = houseUpgradeFolder
		print("[HouseUpgradeSystem] 已创建ClientCameraReady事件")
	end

	-- 创建UpgradeSequenceComplete事件（客户端→服务端：镜头表现完成）
	local completeEvent = houseUpgradeFolder:FindFirstChild("UpgradeSequenceComplete")
	if not completeEvent then
		completeEvent = Instance.new("RemoteEvent")
		completeEvent.Name = "UpgradeSequenceComplete"
		completeEvent.Parent = houseUpgradeFolder
		print("[HouseUpgradeSystem] 已创建UpgradeSequenceComplete事件")
	end

	local popupClosedEvent = houseUpgradeFolder:FindFirstChild("HouseUpgradePopupClosed")
	if not popupClosedEvent then
		popupClosedEvent = Instance.new("RemoteEvent")
		popupClosedEvent.Name = "HouseUpgradePopupClosed"
		popupClosedEvent.Parent = houseUpgradeFolder
		print("[HouseUpgradeSystem] Created HouseUpgradePopupClosed event")
	end

	HouseUpgradeEvents = houseUpgradeFolder
	return true
end

-- 调试日志开关
local DEBUG_LOGS = false
local EnsureInitialized


--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
	if DEBUG_LOGS then
		print("[HouseUpgradeSystem]", ...)
	end
end

local function GetValidHouseModelNameSet()
	if cachedValidHouseModelNames then
		return cachedValidHouseModelNames
	end

	EnsureInitialized()
	if not HouseConfig or not HouseConfig.GetAllHouses then
		return nil
	end

	local set = {}
	for _, house in ipairs(HouseConfig.GetAllHouses()) do
		if house and house.ModelName then
			set[house.ModelName] = true
		end
	end

	cachedValidHouseModelNames = set
	return set
end

local function GetPlacementAttributes(homeFolder)
	if not homeFolder then
		return nil, nil
	end

	local offset = homeFolder:GetAttribute("HouseBottomOffset")
	if typeof(offset) ~= "Vector3" then
		offset = nil
	end

	local yRotation = homeFolder:GetAttribute("HouseYRotation")
	if type(yRotation) ~= "number" then
		yRotation = nil
	end

	return offset, yRotation
end

local function PivotHouseModelToBottomCenter(houseModel, bottomCenter, yRotation)
	if not houseModel or not bottomCenter then
		return false
	end

	local bboxCF, bboxSize = houseModel:GetBoundingBox()
	local pivot = houseModel:GetPivot()
	local bboxBottomY = bboxCF.Position.Y - bboxSize.Y / 2
	local pivotY = pivot.Position.Y
	local pivotToBottomY = pivotY - bboxBottomY
	local pivotToCenterX = pivot.Position.X - bboxCF.Position.X
	local pivotToCenterZ = pivot.Position.Z - bboxCF.Position.Z

	local targetPivotX = bottomCenter.X + pivotToCenterX
	local targetPivotY = bottomCenter.Y + pivotToBottomY
	local targetPivotZ = bottomCenter.Z + pivotToCenterZ
	local targetCFrame = CFrame.new(targetPivotX, targetPivotY, targetPivotZ) * CFrame.Angles(0, yRotation or 0, 0)
	houseModel:PivotTo(targetCFrame)
	return true
end

local function AlignHouseModelToCachedPlacement(homeFolder, spawnLocation, houseModel, fallbackYRotation)
	if not spawnLocation or not spawnLocation:IsA("BasePart") then
		return false
	end

	local offset, yRotation = GetPlacementAttributes(homeFolder)
	if not offset then
		return false
	end

	local finalYRotation = yRotation
	if finalYRotation == nil then
		finalYRotation = fallbackYRotation or 0
	end

	local bottomCenter = spawnLocation.Position + offset
	return PivotHouseModelToBottomCenter(houseModel, bottomCenter, finalYRotation)
end

local function CleanupExtraHouseModels(houseFolder, keepModel, validModelNames)
	if not houseFolder or not validModelNames then
		return
	end

	for _, child in ipairs(houseFolder:GetChildren()) do
		if child:IsA("Model") and child ~= keepModel and validModelNames[child.Name] then
			child:Destroy()
		end
	end
end

--[[
初始化系统（延迟加载依赖模块）
]]
EnsureInitialized = function()
	if isInitialized then return end

	DataManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("DataManager"))
	HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))
	GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

	-- 初始化RemoteEvent
	InitializeEvents()

	-- 监听镜头表现完成事件（只绑定一次）
	if not upgradeEventsConnected and HouseUpgradeEvents then
		local completeEvent = HouseUpgradeEvents:FindFirstChild("UpgradeSequenceComplete")
		if completeEvent then
			completeEvent.OnServerEvent:Connect(function(player)
				if not player or not player.Parent then
					return
				end
				if pendingShopGuideAfterUpgrade[player.UserId] then
					pendingShopGuideAfterUpgrade[player.UserId] = nil
					local guideSystem = GetGuideSystem()
					if guideSystem then
						guideSystem.TriggerGuide(player, 1006)
					end
				end
			end)
		end
		upgradeEventsConnected = true
	end

	isInitialized = true
end

function HouseUpgradeSystem.WaitForPopupClosed(player, timeoutSeconds, startSignalCallback)
	EnsureInitialized()

	if not player then
		return false
	end

	if not InitializeEvents() then
		return false
	end

	local popupClosedInstance = HouseUpgradeEvents and HouseUpgradeEvents:FindFirstChild("HouseUpgradePopupClosed")
	if not popupClosedInstance or not popupClosedInstance:IsA("RemoteEvent") then
		return false
	end
	local popupClosedEvent = popupClosedInstance :: RemoteEvent

	local timeout = tonumber(timeoutSeconds) or 12
	local closed = false
	local connection = nil

	connection = popupClosedEvent.OnServerEvent:Connect(function(sender)
		if sender == player then
			closed = true
		end
	end)

	if type(startSignalCallback) == "function" then
		local ok, err = pcall(startSignalCallback)
		if not ok then
			warn("[HouseUpgradeSystem] start signal callback failed:", err)
		end
	end

	local startTime = tick()
	while not closed and (tick() - startTime) < timeout do
		task.wait(0.05)
	end

	if connection then
		connection:Disconnect()
	end

	return closed
end

--[[
获取玩家的House文件夹
@param homeSlot number - 玩家基地编号(1-6)
@return Folder|nil - House文件夹
]]
local function GetPlayerHouseFolder(homeSlot)
	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		warn("[HouseUpgradeSystem] Home文件夹不存在")
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then
		warn("[HouseUpgradeSystem] PlayerHome" .. homeSlot .. " not found")
		return nil
	end

	-- 查找House文件夹
	local houseFolder = playerHome:FindFirstChild("House")
	return houseFolder
end

--[[
获取House文件夹下的当前房屋模型
@param houseFolder Folder - House文件夹
@return Model|nil - 当前房屋模型
]]
local function GetCurrentHouseModelInFolder(houseFolder, preferredModelName, validModelNames)
	if not houseFolder then
		return nil
	end

	local firstModel = nil
	local firstValidModel = nil

	-- 遍历House文件夹下的子对象，找到Model类型的房屋
	for _, child in ipairs(houseFolder:GetChildren()) do
		if child:IsA("Model") then
			firstModel = firstModel or child

			if preferredModelName and child.Name == preferredModelName then
				return child
			end

			if validModelNames and validModelNames[child.Name] then
				firstValidModel = firstValidModel or child
			end
		end
	end

	if validModelNames then
		return firstValidModel
	end

	return firstModel
end

--[[
替换玩家房屋模型
@param player Player - 玩家对象
@param newModelName string - 新的房屋模型名称
@return boolean - 是否替换成功
]]
function HouseUpgradeSystem.ReplaceHouseModel(player, newModelName)
	EnsureInitialized()

	if not player then
		warn("[HouseUpgradeSystem] ReplaceHouseModel: player为空")
		return false
	end

	-- 获取玩家基地编号
	local homeSlot = DataManager.GetPlayerHomeSlot(player)
	if not homeSlot or homeSlot == 0 then
		warn("[HouseUpgradeSystem] Player home slot not assigned")
		return false
	end

	-- 获取House文件夹
	local houseFolder = GetPlayerHouseFolder(homeSlot)
	if not houseFolder then
		warn("[HouseUpgradeSystem] House folder not found")
		return false
	end

	-- 获取新房屋模型(ReplicatedStorage/House/模型名称)
	local houseTemplateFolder = ReplicatedStorage:FindFirstChild("House")
	if not houseTemplateFolder then
		warn("[HouseUpgradeSystem] ReplicatedStorage/House模板文件夹不存在")
		return false
	end

	local newHouseTemplate = houseTemplateFolder:FindFirstChild(newModelName)
	if not newHouseTemplate then
		warn("[HouseUpgradeSystem] 找不到房屋模型 " .. newModelName)
		return false
	end

	-- 获取当前House文件夹下的房屋模型
	local validHouseModelNames = GetValidHouseModelNameSet()
	local preferredModelName = DataManager.GetCurrentHouseModel(player)
	local currentHouseModel = GetCurrentHouseModelInFolder(houseFolder, preferredModelName, validHouseModelNames)
	if not currentHouseModel then
		warn("[HouseUpgradeSystem] Current house model not found")
		return false
	end

	local homeFolder = houseFolder.Parent
	local spawnLocation = homeFolder and homeFolder:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
	if spawnLocation and not spawnLocation:IsA("BasePart") then
		spawnLocation = nil
	end

	-- V2.8.2修复：获取当前房屋的底部中心位置
	-- 使用包围盒计算底部中心，确保新旧房屋底部对齐
	local currentBBoxCF, currentBBoxSize = currentHouseModel:GetBoundingBox()
	local currentBottomY = currentBBoxCF.Position.Y - currentBBoxSize.Y / 2  -- 底部Y坐标
	local currentCenterX = currentBBoxCF.Position.X  -- XZ中心
	local currentCenterZ = currentBBoxCF.Position.Z

	-- 获取当前房屋轴点的Y旋转（用于保持朝向一致）
	local currentPivot = currentHouseModel:GetPivot()
	local _, currentYRotation, _ = currentPivot:ToEulerAnglesYXZ()

	DebugLog(string.format(
		"Current house %s: bottomY=%.2f, center=(%.2f, %.2f), yRotation=%.2f",
		currentHouseModel.Name,
		currentBottomY,
		currentCenterX,
		currentCenterZ,
		math.deg(currentYRotation)
	))

	-- 克隆新房屋模型
	local newHouseModel = newHouseTemplate:Clone()
	newHouseModel.Name = newModelName

	-- V2.8.2修复：计算新房屋模型的包围盒（在模板原始位置）
	local newBBoxCF, newBBoxSize = newHouseModel:GetBoundingBox()
	local newPivot = newHouseModel:GetPivot()

	-- 计算新模型的底部Y和中心XZ（相对于轴点的偏移）
	local newBBoxBottomY = newBBoxCF.Position.Y - newBBoxSize.Y / 2
	local pivotY = newPivot.Position.Y
	local pivotToBottomY = pivotY - newBBoxBottomY  -- 轴点Y - 底部Y = 轴点到底部的距离

	-- 轴点到包围盒中心的XZ偏移
	local pivotToCenterX = newPivot.Position.X - newBBoxCF.Position.X
	local pivotToCenterZ = newPivot.Position.Z - newBBoxCF.Position.Z
	local alignedToCache = AlignHouseModelToCachedPlacement(homeFolder, spawnLocation, newHouseModel, currentYRotation)

	DebugLog(string.format(
		"新房屋%s 模板: 轴点到底部距离%.2f, 轴点到中心偏移(%.2f, %.2f)",
		newModelName,
		pivotToBottomY,
		pivotToCenterX,
		pivotToCenterZ
	))

	-- 计算新房屋轴点应该放置的位置
	-- 目标：让新房屋的包围盒底部中心对齐 旧房屋的包围盒底部中心
	-- 新轴点位置= 旧底部中心+ 新轴点相对于新底部中心的偏移
	if not alignedToCache then
		local targetPivotX = currentCenterX + pivotToCenterX
		local targetPivotY = currentBottomY + pivotToBottomY
		local targetPivotZ = currentCenterZ + pivotToCenterZ

	-- V2.8.2修复：只保留Y轴旋转，不旋转新房屋（除非旧房屋本身有旋转）
	-- 重要：新房屋应该保持与旧房屋相同的朝向
		local targetCFrame = CFrame.new(targetPivotX, targetPivotY, targetPivotZ) * CFrame.Angles(0, currentYRotation, 0)

	-- 放置新房屋
		newHouseModel:PivotTo(targetCFrame)
	end

	-- 验证放置后的位置
	local verifyBBoxCF, verifyBBoxSize = newHouseModel:GetBoundingBox()
	local verifyBottomY = verifyBBoxCF.Position.Y - verifyBBoxSize.Y / 2
	local verifyPivot = newHouseModel:GetPivot()

	DebugLog(string.format(
		"New house %s placed: pivot=(%.2f, %.2f, %.2f), bottomY=%.2f, yRotation=%.2f, cached=%s",
		newModelName,
		verifyPivot.Position.X,
		verifyPivot.Position.Y,
		verifyPivot.Position.Z,
		verifyBottomY,
		math.deg(currentYRotation),
		tostring(alignedToCache)
	))

	-- 先放入新模型到House文件夹
	newHouseModel.Parent = houseFolder

	-- 再销毁旧房屋模型
	currentHouseModel:Destroy()
	CleanupExtraHouseModels(houseFolder, newHouseModel, validHouseModelNames)

	-- 更新DataManager中的房屋模型名称
	DataManager.SetCurrentHouseModel(player, newModelName)

	DebugLog(string.format(
		"玩家 %s 的房屋已升级: %s -> %s",
		player.Name,
		currentHouseModel.Name,
		newModelName
	))

	return true
end

--[[
检查并执行房屋升级
@param player Player - 玩家对象
@return boolean - 是否执行了升级
]]
function HouseUpgradeSystem.CheckAndUpgradeHouse(player)
	EnsureInitialized()

	if not player then
		return false
	end

	-- 获取玩家当前通关章节数
	local completedChapters = DataManager.GetCompletedChapters(player)

	-- 获取玩家当前房屋模型
	local currentHouseModel = DataManager.GetCurrentHouseModel(player)

	-- 判断是否需要升级
	local shouldUpgrade, newModelName = HouseConfig.ShouldUpgradeHouse(currentHouseModel, completedChapters)

	if shouldUpgrade then
		DebugLog(string.format(
			"玩家 %s 满足升级条件: 当前房屋 %s -> 新房屋%s (通关章节: %d)",
			player.Name,
			currentHouseModel,
			newModelName,
			completedChapters
		))

		return HouseUpgradeSystem.ReplaceHouseModel(player, newModelName)
	end

	return false
end

--[[
带镜头表现的房屋升级（V3.9新增）
@param player Player - 玩家对象
@param newModelName string - 新的房屋模型名称
@return boolean - 是否升级成功
]]
function HouseUpgradeSystem.ReplaceHouseModelWithCinematic(player, newModelName)
	EnsureInitialized()

	if not player then
		warn("[HouseUpgradeSystem] ReplaceHouseModelWithCinematic: player为空")
		return false
	end

	-- 获取玩家基地编号
	local homeSlot = DataManager.GetPlayerHomeSlot(player)
	if not homeSlot or homeSlot == 0 then
		warn("[HouseUpgradeSystem] Player home slot not assigned")
		return false
	end

	-- 类型断言：此时homeSlot一定不为nil且不为0
	local validHomeSlot = homeSlot :: number

	DebugLog(string.format(
		"开始房屋升级镜头表现，玩家=%s, HomeSlot=%d, 新房屋%s",
		player.Name,
		validHomeSlot,
		newModelName
	))

	-- 1. 通知客户端开始镜头表现（先建立关闭监听，避免丢失快速回调）
	local startEvent = nil
	if InitializeEvents() then
		local startEventInstance = HouseUpgradeEvents:FindFirstChild("StartUpgradeSequence")
		if startEventInstance and startEventInstance:IsA("RemoteEvent") then
			startEvent = startEventInstance
		end
	end
	if startEvent then
		local popupClosed = HouseUpgradeSystem.WaitForPopupClosed(player, 12, function()
			startEvent:FireClient(player, validHomeSlot, DataManager.GetCurrentHouseModel(player), newModelName)
		end)
		if not popupClosed then
			warn(string.format("[HouseUpgradeSystem] Popup close wait timeout, player=%s", player.Name))
		end
	end

	-- 2. 执行房屋替换
	local success = HouseUpgradeSystem.ReplaceHouseModel(player, newModelName)

	if not success then
		warn("[HouseUpgradeSystem] 房屋替换失败")
	end

	return success
end

--[[
章节通关时触发的升级检查（V3.9修改：使用镜头表现）
@param player Player - 玩家对象
@param chapterId number - 通关的章节ID
@param useCinematic boolean - 是否使用镜头表现（默认true）
]]
function HouseUpgradeSystem.OnChapterCompleted(player, chapterId, useCinematic)
	EnsureInitialized()

	if useCinematic == nil then
		useCinematic = true  -- 默认使用镜头表现
	end

	DebugLog(string.format(
		"玩家 %s 通关章节 %d，检查房屋升级.. (镜头表现=%s)",
		player.Name,
		chapterId,
		tostring(useCinematic)
	))

	-- 延迟一帧执行，确保数据已更新
	task.defer(function()
		-- 获取玩家当前通关章节数
		local completedChapters = DataManager.GetCompletedChapters(player)

		-- 获取玩家当前房屋模型
		local currentHouseModel = DataManager.GetCurrentHouseModel(player)

		-- 判断是否需要升级
		local shouldUpgrade, newModelName = HouseConfig.ShouldUpgradeHouse(currentHouseModel, completedChapters)

		if shouldUpgrade then
			DebugLog(string.format(
				"玩家 %s 满足升级条件: 当前房屋 %s -> 新房屋%s (通关章节: %d)",
				player.Name,
				currentHouseModel,
				newModelName,
				completedChapters
			))

			if useCinematic then
				-- V3.9新增：使用镜头表现的升级
				if chapterId == 1 then
					pendingShopGuideAfterUpgrade[player.UserId] = true
				end
				HouseUpgradeSystem.ReplaceHouseModelWithCinematic(player, newModelName)
			else
				-- 直接升级（无镜头表现）
				HouseUpgradeSystem.ReplaceHouseModel(player, newModelName)
			end
		end
	end)
end

--[[
玩家登录时初始化房屋（V2.8.2修改：同步执行，无延迟）
注意：此函数现在主要由HomeSystem.InitializePlayerHome调用
@param player Player - 玩家对象
@param homeSlot number - 分配的基地编号
]]
function HouseUpgradeSystem.InitializePlayerHouse(player, homeSlot)
	EnsureInitialized()

	if not player or not homeSlot then
		return
	end

	-- 获取玩家应该使用的房屋模型
	local completedChapters = DataManager.GetCompletedChapters(player)
	local targetModelName = HouseConfig.GetHouseModelByChapter(completedChapters)

	-- 获取当前存档的房屋模型名称
	local savedModelName = DataManager.GetCurrentHouseModel(player)

	-- 获取场景中实际的房屋模型名称
	local houseFolder = GetPlayerHouseFolder(homeSlot)
	local validHouseModelNames = GetValidHouseModelNameSet()
	local currentHouseModel = houseFolder and GetCurrentHouseModelInFolder(houseFolder, targetModelName, validHouseModelNames)
	if currentHouseModel then
		CleanupExtraHouseModels(houseFolder, currentHouseModel, validHouseModelNames)
	end
	local actualModelName = currentHouseModel and currentHouseModel.Name or "PrisonLv1"

	DebugLog(string.format(
		"玩家 %s 登录，通关章节: %d, 目标房屋: %s, 存档房屋: %s, 场景中房屋 %s",
		player.Name,
		completedChapters,
		targetModelName,
		savedModelName,
		actualModelName
	))

	-- V2.8.2修改：如果场景中的房屋模型与目标不一致，立即替换（无延迟）
	if actualModelName ~= targetModelName then
		DebugLog(string.format(
			"玩家 %s 需要替换房屋 %s -> %s",
			player.Name,
			actualModelName,
			targetModelName
		))

		-- 立即执行替换，不使用延迟
		if player and player.Parent then
			HouseUpgradeSystem.ReplaceHouseModel(player, targetModelName)
		end
	end

	-- 如果存档的模型名称与目标不一致，更新存档
	if savedModelName ~= targetModelName then
		DataManager.SetCurrentHouseModel(player, targetModelName)
		DebugLog(string.format(
			"玩家 %s 存档房屋模型已更新 %s -> %s",
			player.Name,
			savedModelName,
			targetModelName
		))
	end
end

return HouseUpgradeSystem
