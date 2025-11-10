--[[
=====================================================
脚本名称: CampaignUnitHelper
脚本类型: ModuleScript (服务端辅助)
脚本位置: ServerScriptService/Systems/CampaignUnitHelper.lua
版本: V2.0
=====================================================

功能描述:
- 统一管理战役系统中的单位激活/复位/属性重置
- 确保行军-战斗切换时的状态一致性
- 提供防御性编程接口

核心原则:
- 单一职责：只负责单位状态管理
- 防御式编程：所有操作包裹pcall
- 详细日志：便于问题定位
]]

local CampaignUnitHelper = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local UnitConfig = require(ReplicatedStorage.Config.UnitConfig)

-- 引用系统
local PathService = require(ServerScriptService.Systems.PathService)
local UnitAI = require(ServerScriptService.Systems.UnitAI)

-- ==================== 调试日志 ====================

local function DebugLog(...)
	print(GameConfig.LOG_PREFIX, "[CampaignUnitHelper]", ...)
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[CampaignUnitHelper]", ...)
end

-- ==================== 私有函数 ====================

--[[
设置兵种的锚定状态
@param unitModel Model - 兵种模型
@param anchored boolean - 是否锚定
]]
local function SetUnitAnchored(unitModel, anchored)
	if not unitModel then
		return false
	end

	local success, err = pcall(function()
		-- 遍历所有 BasePart 设置锚定和碰撞
		for _, descendant in ipairs(unitModel:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = anchored
				-- HumanoidRootPart始终保持碰撞
				if descendant.Name == "HumanoidRootPart" then
					descendant.CanCollide = true
				else
					descendant.CanCollide = false
				end
			end
		end

		-- 设置 Humanoid 状态
		local humanoid = unitModel:FindFirstChild("Humanoid")
		if humanoid then
			if not anchored then
				-- 解除锚定：准备移动
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			else
				-- 锚定：站立不动
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end)

	if not success then
		WarnLog("SetUnitAnchored失败:", err)
		return false
	end

	return true
end

-- ==================== 公共接口 ====================

--[[
激活单位（从基地展示态变为可战斗态）
@param unitModel Model - 兵种模型
@return boolean - 是否成功
]]
function CampaignUnitHelper.ActivateUnit(unitModel)
	if not unitModel or not unitModel:IsA("Model") then
		WarnLog("ActivateUnit失败：无效的模型")
		return false
	end

	-- 检查是否已激活
	if unitModel:GetAttribute("IsActivated") then
		DebugLog("单位", unitModel.Name, "已激活，跳过")
		return true
	end

	DebugLog("正在激活单位:", unitModel.Name)

	local success, err = pcall(function()
		-- 解除所有BasePart的锚定，恢复碰撞
		local partCount = 0
		for _, part in ipairs(unitModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false  -- 解除锚定，允许物理引擎控制
				-- 只有HumanoidRootPart需要碰撞
				if part.Name == "HumanoidRootPart" then
					part.CanCollide = true
				else
					part.CanCollide = false
				end
				partCount = partCount + 1
			end
		end

		-- 重置Humanoid状态
		local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		else
			WarnLog("警告：未找到Humanoid")
		end

		-- 标记为已激活
		unitModel:SetAttribute("IsActivated", true)

		DebugLog("✅激活完成:", unitModel.Name, "共处理", partCount, "个Part")
	end)

	if not success then
		WarnLog("ActivateUnit失败:", err)
		return false
	end

	return true
end

--[[
复位单位属性（恢复满血等）
@param unitModel Model - 兵种模型
@param maxHP number - 最大生命值
@return boolean - 是否成功
]]
function CampaignUnitHelper.ResetUnitAttributes(unitModel, maxHP)
	if not unitModel or not unitModel:IsA("Model") then
		WarnLog("ResetUnitAttributes失败：无效的模型")
		return false
	end

	local success, err = pcall(function()
		local humanoid = unitModel:FindFirstChild("Humanoid")
		if humanoid and maxHP then
			humanoid.Health = maxHP
			DebugLog("重置生命值:", unitModel.Name, "HP:", maxHP)
		end
	end)

	if not success then
		WarnLog("ResetUnitAttributes失败:", err)
		return false
	end

	return true
end

--[[
恢复已保存的生命值
@param unitModel Model - 兵种模型
@param savedHP number - 已保存的生命值
@return boolean - 是否成功
]]
function CampaignUnitHelper.RestoreSavedHP(unitModel, savedHP)
	if not unitModel or not unitModel:IsA("Model") then
		WarnLog("RestoreSavedHP失败：无效的模型")
		return false
	end

	local success, err = pcall(function()
		local humanoid = unitModel:FindFirstChild("Humanoid")
		if humanoid and savedHP then
			-- 确保不超过最大生命值
			humanoid.Health = math.min(savedHP, humanoid.MaxHealth)
			DebugLog("恢复生命值:", unitModel.Name, "HP:", humanoid.Health)
		end
	end)

	if not success then
		WarnLog("RestoreSavedHP失败:", err)
		return false
	end

	return true
end

--[[
准备单位进入战斗（清理残留状态+重置AI）
@param unitModel Model - 兵种模型
@return boolean - 是否成功
]]
function CampaignUnitHelper.PrepareForBattle(unitModel)
	if not unitModel or not unitModel:IsA("Model") then
		WarnLog("PrepareForBattle失败：无效的模型")
		return false
	end

	DebugLog("准备单位进入战斗:", unitModel.Name)

	local success, err = pcall(function()
		-- 1. 停止旧的AI（如有）
		UnitAI.StopAI(unitModel)

		-- 2. 清理PathService残留
		PathService.ClearPath(unitModel)

		-- 3. 确保解除锚定
		SetUnitAnchored(unitModel, false)

		-- 4. 重置Humanoid状态
		local humanoid = unitModel:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end

		DebugLog("✅单位准备完成:", unitModel.Name)
	end)

	if not success then
		WarnLog("PrepareForBattle失败:", err)
		return false
	end

	return true
end

--[[
重新锚定单位（返回基地展示态）
@param unitModel Model - 兵种模型
@return boolean - 是否成功
]]
function CampaignUnitHelper.DeactivateUnit(unitModel)
	if not unitModel or not unitModel:IsA("Model") then
		WarnLog("DeactivateUnit失败：无效的模型")
		return false
	end

	DebugLog("重新锚定单位:", unitModel.Name)

	local success, err = pcall(function()
		-- 重新锚定所有部件
		SetUnitAnchored(unitModel, true)

		-- 清除激活标记
		unitModel:SetAttribute("IsActivated", false)

		DebugLog("✅单位已锚定:", unitModel.Name)
	end)

	if not success then
		WarnLog("DeactivateUnit失败:", err)
		return false
	end

	return true
end

--[[
批量激活单位
@param units table - 单位列表 {unitModel1, unitModel2, ...}
@return table - 成功激活的单位列表
]]
function CampaignUnitHelper.ActivateUnits(units)
	local activated = {}

	for _, unitModel in ipairs(units) do
		if CampaignUnitHelper.ActivateUnit(unitModel) then
			table.insert(activated, unitModel)
		end
	end

	DebugLog("批量激活完成:", #activated, "/", #units)
	return activated
end

--[[
批量准备单位进入战斗
@param units table - 单位列表
@return table - 成功准备的单位列表
]]
function CampaignUnitHelper.PrepareUnitsForBattle(units)
	local prepared = {}

	for _, unitModel in ipairs(units) do
		if CampaignUnitHelper.PrepareForBattle(unitModel) then
			table.insert(prepared, unitModel)
		end
	end

	DebugLog("批量准备完成:", #prepared, "/", #units)
	return prepared
end

return CampaignUnitHelper
