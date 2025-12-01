--[[
脚本名称: HouseUpgradeSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/HouseUpgradeSystem
版本: V2.8.1
]]

--[[
房屋升级系统
职责:
1. 根据通关章节替换房屋模型
2. 保持House文件夹结构不变，只替换里面的模型
3. 协调DataManager保存房屋状态

结构说明：
- Workspace/Home/PlayerHomeX/House (Folder) - 这是房屋文件夹，保持不变
- Workspace/Home/PlayerHomeX/House/PrisonLv1 (Model) - 这是房屋模型，需要替换
- ReplicatedStorage/House/PrisonLv1 (Model) - 房屋模板
- ReplicatedStorage/House/PrisonLv2 (Model) - 升级后的房屋模板
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

--[[
初始化系统（延迟加载依赖模块）
]]
local function EnsureInitialized()
	if isInitialized then return end

	DataManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("DataManager"))
	HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))
	GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

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

	print(string.format(
		"[HouseUpgradeSystem] 当前房屋 %s: 底部Y=%.2f, 中心=(%.2f, %.2f), Y旋转=%.2f度",
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

	print(string.format(
		"[HouseUpgradeSystem] 新房屋 %s 模板: 轴点到底部距离=%.2f, 轴点到中心偏移=(%.2f, %.2f)",
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

	print(string.format(
		"[HouseUpgradeSystem] 新房屋 %s 已放置: 轴点=(%.2f, %.2f, %.2f), 实际底部Y=%.2f, Y旋转=%.2f度",
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

	-- 更新DataManager中的房屋模型名称
	DataManager.SetCurrentHouseModel(player, newModelName)

	print(string.format(
		"[HouseUpgradeSystem] 玩家 %s 的房屋已升级: %s -> %s",
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
		print(string.format(
			"[HouseUpgradeSystem] 玩家 %s 满足升级条件: 当前房屋 %s -> 新房屋 %s (通关章节: %d)",
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
章节通关时触发的升级检查
@param player Player - 玩家对象
@param chapterId number - 通关的章节ID
]]
function HouseUpgradeSystem.OnChapterCompleted(player, chapterId)
	EnsureInitialized()

	print(string.format(
		"[HouseUpgradeSystem] 玩家 %s 通关章节 %d，检查房屋升级...",
		player.Name,
		chapterId
	))

	-- 延迟一帧执行，确保数据已更新
	task.defer(function()
		local upgraded = HouseUpgradeSystem.CheckAndUpgradeHouse(player)

		if upgraded then
			-- 可以在这里触发客户端特效或通知
			print(string.format(
				"[HouseUpgradeSystem] 玩家 %s 房屋升级成功！",
				player.Name
			))
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

	print(string.format(
		"[HouseUpgradeSystem] 玩家 %s 登录，通关章节: %d, 目标房屋: %s, 存档房屋: %s, 场景中房屋: %s",
		player.Name,
		completedChapters,
		targetModelName,
		savedModelName,
		actualModelName
	))

	-- V2.8.2修改：如果场景中的房屋模型与目标不一致，立即替换（无延迟）
	if actualModelName ~= targetModelName then
		print(string.format(
			"[HouseUpgradeSystem] 玩家 %s 需要替换房屋: %s -> %s",
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
		print(string.format(
			"[HouseUpgradeSystem] 玩家 %s 存档房屋模型已更新: %s -> %s",
			player.Name,
			savedModelName,
			targetModelName
		))
	end
end

return HouseUpgradeSystem
