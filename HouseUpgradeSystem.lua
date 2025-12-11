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
7. 播放HouseChange特效（1秒后移除）
8. 等待1秒
9. 客户端恢复镜头控制

V3.9.1新增：
- 房屋替换时播放HouseChange特效
- 特效从ReplicatedStorage/Effect/HouseChange复制
- 特效放置在新房屋位置，1秒后自动移除
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
		print("[HouseUpgradeSystem] 已创建HouseUpgradeEvents文件夹")
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

	HouseUpgradeEvents = houseUpgradeFolder
	return true
end

-- 调试日志开关
local DEBUG_LOGS = false

-- 特效配置
local HOUSE_CHANGE_EFFECT_DURATION = 1.5  -- 房屋替换特效持续时间（秒）

--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
	if DEBUG_LOGS then
		print("[HouseUpgradeSystem]", ...)
	end
end

--[[
播放房屋替换特效（V3.9.1新增）
@param position Vector3 - 特效播放位置
]]
local function PlayHouseChangeEffect(position)
	-- 获取特效模板
	local effectFolder = ReplicatedStorage:FindFirstChild("Effect")
	if not effectFolder then
		warn("[HouseUpgradeSystem] ReplicatedStorage/Effect文件夹不存在")
		return
	end

	local effectTemplate = effectFolder:FindFirstChild("HouseChange")
	if not effectTemplate then
		warn("[HouseUpgradeSystem] HouseChange特效模板不存在")
		return
	end

	-- 1. 克隆特效（子节点通过Weld自动跟随）
	local effect = effectTemplate:Clone()

	-- 2. 先挂载到Workspace
	effect.Parent = Workspace

	-- 3. 立即锚定，防止物理引擎干扰（子节点保持不锚定，通过Weld跟随）
	if effect:IsA("Model") then
		if effect.PrimaryPart then
			effect.PrimaryPart.Anchored = true
		end
	elseif effect:IsA("BasePart") then
		effect.Anchored = true
	end

	-- 4. 移动到目标位置
	if effect:IsA("Model") then
		effect:PivotTo(CFrame.new(position))
	elseif effect:IsA("BasePart") then
		effect.CFrame = CFrame.new(position)
	end

	DebugLog(string.format(
		"播放房屋替换特效，位置=(%.2f, %.2f, %.2f)",
		position.X,
		position.Y,
		position.Z
	))

	-- 1.5秒后移除特效
	task.delay(HOUSE_CHANGE_EFFECT_DURATION, function()
		if effect and effect.Parent then
			effect:Destroy()
			DebugLog("房屋替换特效已移除")
		end
	end)
end

--[[
初始化系统（延迟加载依赖模块）
]]
local function EnsureInitialized()
	if isInitialized then return end

	DataManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("DataManager"))
	HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))
	GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

	-- 初始化RemoteEvent
	InitializeEvents()

	isInitialized = true
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
		warn("[HouseUpgradeSystem] PlayerHome" .. homeSlot .. " 不存在")
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
local function GetCurrentHouseModelInFolder(houseFolder)
	if not houseFolder then return nil end

	-- 遍历House文件夹下的子对象，找到Model类型的房屋
	for _, child in ipairs(houseFolder:GetChildren()) do
		if child:IsA("Model") then
			return child
		end
	end

	return nil
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
		warn("[HouseUpgradeSystem] 玩家未分配基地")
		return false
	end

	-- 获取House文件夹
	local houseFolder = GetPlayerHouseFolder(homeSlot)
	if not houseFolder then
		warn("[HouseUpgradeSystem] 找不到House文件夹")
		return false
	end

	-- 获取新房屋模板 (ReplicatedStorage/House/模型名称)
	local houseTemplateFolder = ReplicatedStorage:FindFirstChild("House")
	if not houseTemplateFolder then
		warn("[HouseUpgradeSystem] ReplicatedStorage/House模板文件夹不存在")
		return false
	end

	local newHouseTemplate = houseTemplateFolder:FindFirstChild(newModelName)
	if not newHouseTemplate then
		warn("[HouseUpgradeSystem] 找不到房屋模板: " .. newModelName)
		return false
	end

	-- 获取当前House文件夹下的房屋模型
	local currentHouseModel = GetCurrentHouseModelInFolder(houseFolder)
	if not currentHouseModel then
		warn("[HouseUpgradeSystem] House文件夹下找不到房屋模型")
		return false
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
		"当前房屋 %s: 底部Y=%.2f, 中心=(%.2f, %.2f), Y旋转=%.2f度",
		currentHouseModel.Name,
		currentBottomY,
		currentCenterX,
		currentCenterZ,
		math.deg(currentYRotation)
	))

	-- 克隆新房屋模板
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

	DebugLog(string.format(
		"新房屋 %s 模板: 轴点到底部距离=%.2f, 轴点到中心偏移=(%.2f, %.2f)",
		newModelName,
		pivotToBottomY,
		pivotToCenterX,
		pivotToCenterZ
	))

	-- 计算新房屋轴点应该放置的位置
	-- 目标：让新房屋的包围盒底部中心 对齐 旧房屋的包围盒底部中心
	-- 新轴点位置 = 旧底部中心 + 新轴点相对于新底部中心的偏移
	local targetPivotX = currentCenterX + pivotToCenterX
	local targetPivotY = currentBottomY + pivotToBottomY
	local targetPivotZ = currentCenterZ + pivotToCenterZ

	-- V2.8.2修复：只保留Y轴旋转，不旋转新房屋（除非旧房屋本身有旋转）
	-- 重要：新房屋应该保持与旧房屋相同的朝向
	local targetCFrame = CFrame.new(targetPivotX, targetPivotY, targetPivotZ) * CFrame.Angles(0, currentYRotation, 0)

	-- 放置新房屋
	newHouseModel:PivotTo(targetCFrame)

	-- 验证放置后的位置
	local verifyBBoxCF, verifyBBoxSize = newHouseModel:GetBoundingBox()
	local verifyBottomY = verifyBBoxCF.Position.Y - verifyBBoxSize.Y / 2

	DebugLog(string.format(
		"新房屋 %s 已放置: 轴点=(%.2f, %.2f, %.2f), 实际底部Y=%.2f, Y旋转=%.2f度",
		newModelName,
		targetPivotX,
		targetPivotY,
		targetPivotZ,
		verifyBottomY,
		math.deg(currentYRotation)
	))

	-- 先放入新模型到House文件夹
	newHouseModel.Parent = houseFolder

	-- 再销毁旧房屋模型
	currentHouseModel:Destroy()

	-- V3.9.1新增：播放房屋替换特效
	-- 特效位置使用新房屋的轴点位置（与房屋轴点对齐）
	local effectPosition = targetCFrame.Position
	PlayHouseChangeEffect(effectPosition)

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
			"玩家 %s 满足升级条件: 当前房屋 %s -> 新房屋 %s (通关章节: %d)",
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
		warn("[HouseUpgradeSystem] 玩家未分配基地")
		return false
	end

	-- 类型断言：此时homeSlot一定不为nil且不为0
	local validHomeSlot = homeSlot :: number

	DebugLog(string.format(
		"开始房屋升级镜头表现，玩家=%s, HomeSlot=%d, 新房屋=%s",
		player.Name,
		validHomeSlot,
		newModelName
	))

	-- 1. 通知客户端开始镜头表现
	if InitializeEvents() then
		local startEvent = HouseUpgradeEvents:FindFirstChild("StartUpgradeSequence")
		if startEvent then
			startEvent:FireClient(player, validHomeSlot)
		end
	end

	-- 2. 等待镜头移动到位（1秒移动 + 1秒等待）
	task.wait(2.0)

	-- 3. 执行房屋替换
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
		"玩家 %s 通关章节 %d，检查房屋升级... (镜头表现=%s)",
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
				"玩家 %s 满足升级条件: 当前房屋 %s -> 新房屋 %s (通关章节: %d)",
				player.Name,
				currentHouseModel,
				newModelName,
				completedChapters
			))

			if useCinematic then
				-- V3.9新增：使用镜头表现的升级
				HouseUpgradeSystem.ReplaceHouseModelWithCinematic(player, newModelName)
			else
				-- 直接升级（无镜头表现）
				HouseUpgradeSystem.ReplaceHouseModel(player, newModelName)
			end
		end
	end)
end

--[[
玩家登录时初始化房屋 (V2.8.2修改：同步执行，无延迟)
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
	local currentHouseModel = houseFolder and GetCurrentHouseModelInFolder(houseFolder)
	local actualModelName = currentHouseModel and currentHouseModel.Name or "PrisonLv1"

	DebugLog(string.format(
		"玩家 %s 登录，通关章节: %d, 目标房屋: %s, 存档房屋: %s, 场景中房屋: %s",
		player.Name,
		completedChapters,
		targetModelName,
		savedModelName,
		actualModelName
	))

	-- V2.8.2修改：如果场景中的房屋模型与目标不一致，立即替换（无延迟）
	if actualModelName ~= targetModelName then
		DebugLog(string.format(
			"玩家 %s 需要替换房屋: %s -> %s",
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
			"玩家 %s 存档房屋模型已更新: %s -> %s",
			player.Name,
			savedModelName,
			targetModelName
		))
	end
end

return HouseUpgradeSystem
