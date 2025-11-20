--[[
脚本名称: CampaignUnitHelper
版本: V2.7 简化版 - 移除复杂逻辑,防止Parent报错
]]

local CampaignUnitHelper = {}

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Config.GameConfig)
local PhysicsManager = require(ServerScriptService.Systems.PhysicsManager)
local UnitAI = require(ServerScriptService.Systems.UnitAI)
local PathService = require(ServerScriptService.Systems.PathService)

local function DebugLog(...)
	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "[CampaignUnitHelper]", ...)
	end
end

local function WarnLog(...)
	warn(GameConfig.LOG_PREFIX, "[CampaignUnitHelper]", ...)
end

--[[
激活单位：从展示状态切换到战斗状态
@param unitModel Model - 兵种模型
@param team string - 阵营("ally"或"enemy")，默认"ally"
@return boolean - 是否成功
]]
function CampaignUnitHelper.ActivateUnit(unitModel, team)
	-- V2.7关键修复：静默失败，不要报错刷屏
	if not unitModel or not unitModel.Parent then
		return false
	end

	local humanoid = unitModel:FindFirstChild("Humanoid")
	if not humanoid then
		return false
	end

	-- 检查是否已激活
	if unitModel:GetAttribute("IsActivated") then
		return true
	end

	-- 默认队伍
	team = team or "ally"

	local success = pcall(function()
		-- 1. 解除锚定
		for _, part in ipairs(unitModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
				-- HumanoidRootPart保持碰撞
				if part.Name == "HumanoidRootPart" then
					part.CanCollide = true
				else
					part.CanCollide = false
				end
			end
		end

		-- 2. 激活Humanoid
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Running)

		-- 3. 设置碰撞组 (Allies/Enemies)
		PhysicsManager.ConfigureUnitPhysics(unitModel, team)

		unitModel:SetAttribute("IsActivated", true)
	end)

	return success
end

--[[
准备战斗：重置状态，清理AI
@param unitModel Model - 兵种模型
@return boolean - 是否成功
]]
function CampaignUnitHelper.PrepareForBattle(unitModel)
	-- V2.7关键修复：静默失败
	if not unitModel or not unitModel.Parent then
		return false
	end

	local humanoid = unitModel:FindFirstChild("Humanoid")
	if not humanoid then
		return false
	end

	local success = pcall(function()
		-- 1. 停止旧AI
		pcall(function()
			UnitAI.StopAI(unitModel)
		end)

		-- 2. 清理路径
		pcall(function()
			PathService.ClearPath(unitModel)
		end)

		-- 3. 确保物理状态正确
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Running)

		-- 4. 再次确认碰撞组 (防止复活时遗漏)
		-- 友军统一用"ally"
		PhysicsManager.ConfigureUnitPhysics(unitModel, "ally")
	end)

	return success
end

--[[
重新锚定单位（返回基地展示态）
@param unitModel Model - 兵种模型
@return boolean - 是否成功
]]
function CampaignUnitHelper.DeactivateUnit(unitModel)
	if not unitModel or not unitModel.Parent then
		return false
	end

	local success = pcall(function()
		-- 重新锚定所有部件
		for _, part in ipairs(unitModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end

		-- 清除激活标记
		unitModel:SetAttribute("IsActivated", false)
	end)

	return success
end

--[[
批量激活单位
@param units table - 单位列表
@param team string - 阵营
@return table - 成功激活的单位列表
]]
function CampaignUnitHelper.ActivateUnits(units, team)
	local activated = {}

	for _, unitModel in ipairs(units) do
		if CampaignUnitHelper.ActivateUnit(unitModel, team) then
			table.insert(activated, unitModel)
		end
	end

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

	return prepared
end

--[[
复位单位属性（恢复满血等）
@param unitModel Model - 兵种模型
@param maxHP number - 最大生命值
@return boolean - 是否成功
]]
function CampaignUnitHelper.ResetUnitAttributes(unitModel, maxHP)
	if not unitModel or not unitModel.Parent then
		return false
	end

	local success = pcall(function()
		local humanoid = unitModel:FindFirstChild("Humanoid")
		if humanoid and maxHP then
			humanoid.Health = maxHP
		end
	end)

	return success
end

--[[
恢复已保存的生命值
@param unitModel Model - 兵种模型
@param savedHP number - 已保存的生命值
@return boolean - 是否成功
]]
function CampaignUnitHelper.RestoreSavedHP(unitModel, savedHP)
	if not unitModel or not unitModel.Parent then
		return false
	end

	local success = pcall(function()
		local humanoid = unitModel:FindFirstChild("Humanoid")
		if humanoid and savedHP then
			humanoid.Health = math.min(savedHP, humanoid.MaxHealth)
		end
	end)

	return success
end

return CampaignUnitHelper
