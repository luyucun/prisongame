--[[
=====================================================
脚本名称: DistanceProgressController
脚本类型: LocalScript (客户端)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/DistanceProgressController.lua
版本: V3.6
=====================================================

功能描述:
- 显示战场进度UI (StarterGui - Distance - Bg)
- 根据战场中心位置实时更新玩家头像位置
- 计算从家园IdleFloor到最后一关IdleFloor的进度比例
- 战斗开始时显示，战斗结束时隐藏

UI结构:
- StarterGui - Distance - Bg - ProgressBg: 进度条背景(总长度=1)
- StarterGui - Distance - Bg - ProgressBg - PlayerIcon: 玩家头像(位置代表进度)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ==================== UI引用 ====================
local distanceGui = playerGui:WaitForChild("Distance", 10)
local bgFrame = distanceGui and distanceGui:WaitForChild("Bg", 5)
local progressBg = bgFrame and bgFrame:WaitForChild("ProgressBg", 5)
local playerIcon = progressBg and progressBg:WaitForChild("PlayerIcon", 5)

-- ==================== 配置参数 ====================
local PROGRESS_UPDATE_INTERVAL = 0.1  -- 进度更新间隔(秒)
local PROGRESS_LERP_SPEED = 0.15      -- 进度平滑过渡速度
local INITIAL_POSITION = UDim2.new(0, 0, 0.5, 0)  -- 初始位置

-- ==================== 状态变量 ====================
local isActive = false
local currentProgress = 0  -- 当前显示的进度(0-1)
local targetProgress = 0   -- 目标进度(0-1)
local renderConnection = nil

-- 战役数据
local currentChapter = 1
local totalStages = 3
local homeIdleFloorZ = 0   -- 家园IdleFloor的Z坐标(起点)
local lastStageIdleFloorZ = 0  -- 最后一关IdleFloor的Z坐标(终点)
local totalDistance = 0    -- 总距离

-- ==================== 调试函数 ====================
local function DebugLog(...)
	-- print("[DistanceProgressController]", ...)
end

-- ==================== 工具函数 ====================

--[[
获取玩家家园的IdleFloor
@return Part|nil - IdleFloor部件
]]
local function getHomeIdleFloor()
	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then
		return nil
	end

	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. tostring(homeSlot))
	if not playerHome then
		return nil
	end

	return playerHome:FindFirstChild("IdleFloor")
end

--[[
获取指定关卡的IdleFloor位置
@param stageNum number - 关卡编号
@return Part|nil - 关卡的IdleFloor部件
]]
local function getStageIdleFloor(stageNum)
	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then
		return nil
	end

	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. tostring(homeSlot))
	if not playerHome then
		return nil
	end

	local stageContainer = playerHome:FindFirstChild("Stage")
	if not stageContainer then
		return nil
	end

	-- 格式: Stage001, Stage002, ...
	local stageName = string.format("Stage%03d", stageNum)
	local stageFolder = stageContainer:FindFirstChild(stageName)
	if not stageFolder then
		return nil
	end

	return stageFolder:FindFirstChild("IdleFloor", true)
end

--[[
收集所有友军单位的位置
@return {Vector3} - 友军位置列表
]]
local function collectAllyPositions()
	local positions = {}

	-- 仅统计当前玩家自己的单位
	local myHomeSlot = player:GetAttribute("HomeSlot")
	if not myHomeSlot then
		local idleFloor = getHomeIdleFloor()
		if idleFloor then
			table.insert(positions, idleFloor.Position)
		end
		return positions
	end

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") and inst:GetAttribute("CampaignKeepInstance") then
			local unitHomeSlot = inst:GetAttribute("HomeSlot")
			if unitHomeSlot == myHomeSlot then
				local rootPart = inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
				if rootPart then
					table.insert(positions, rootPart.Position)
				end
			end
		end
	end

	if #positions == 0 then
		local idleFloor = getHomeIdleFloor()
		if idleFloor then
			table.insert(positions, idleFloor.Position)
		end
	end

	return positions
end

--[[
计算战场中心(友军质心)
@return Vector3|nil - 战场中心位置
]]
local function computeBattleCenter()
	local positions = collectAllyPositions()
	if #positions == 0 then
		return nil
	end

	local sum = Vector3.zero
	for _, pos in ipairs(positions) do
		sum = sum + pos
	end

	return sum / #positions
end

--[[
计算进度比例(0-1)
@param currentZ number - 当前战场中心的Z坐标
@return number - 进度比例
]]
local function calculateProgress(currentZ)
	if totalDistance <= 0 then
		return 0
	end

	-- 注意: 在Roblox中，前进通常是Z轴负方向
	-- homeIdleFloorZ是起点(较大的Z值)
	-- lastStageIdleFloorZ是终点(较小的Z值)
	-- 所以: 进度 = (起点Z - 当前Z) / (起点Z - 终点Z)
	local advancedDistance = homeIdleFloorZ - currentZ
	local progress = advancedDistance / totalDistance

	-- 限制在0-1范围内
	return math.clamp(progress, 0, 1)
end

--[[
设置玩家头像
]]
local function setPlayerIcon()
	if not playerIcon then
		return
	end

	-- 获取玩家头像
	local userId = player.UserId
	local success, result = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)

	if success and result then
		playerIcon.Image = result
		DebugLog("玩家头像已设置")
	end
end

--[[
初始化进度追踪数据
@param chapter number - 当前章节
@param stages number - 总关卡数
]]
local function initializeProgressData(chapter, stages)
	currentChapter = chapter or 1
	totalStages = stages or 3

	-- 获取起点(家园IdleFloor)
	local homeIdleFloor = getHomeIdleFloor()
	if homeIdleFloor then
		homeIdleFloorZ = homeIdleFloor.Position.Z
		DebugLog("起点Z坐标:", homeIdleFloorZ)
	else
		DebugLog("⚠ 未找到家园IdleFloor")
		return false
	end

	-- 计算终点(最后一关的IdleFloor)
	-- 由于关卡是动态生成的，我们需要估算终点位置
	-- 根据GameConfig.Campaign.StageGenerateOffset = 170
	-- 以及Stage001的初始位置，可以计算出最后一关的预期位置

	-- 方法1: 尝试获取已存在的最后一关IdleFloor
	local lastStageIdleFloor = getStageIdleFloor(totalStages)
	if lastStageIdleFloor then
		lastStageIdleFloorZ = lastStageIdleFloor.Position.Z
		DebugLog("终点Z坐标(实际):", lastStageIdleFloorZ)
	else
		-- 方法2: 根据配置估算
		-- Stage001位置大约在homeIdleFloorZ - 184的位置(根据GameConfig)
		-- 每关间距约169 studs(负方向)
		local stageOffset = -169  -- 每关向Z负方向偏移
		local stage001OffsetFromHome = -184  -- Stage001相对于Home的偏移

		-- 从Stage001开始，每关偏移stageOffset
		-- 最后一关的Z = homeIdleFloorZ + stage001OffsetFromHome + (totalStages - 1) * stageOffset
		lastStageIdleFloorZ = homeIdleFloorZ + stage001OffsetFromHome + (totalStages - 1) * stageOffset
		DebugLog("终点Z坐标(估算):", lastStageIdleFloorZ)
	end

	-- 计算总距离
	totalDistance = homeIdleFloorZ - lastStageIdleFloorZ
	DebugLog("总距离:", totalDistance)

	if totalDistance <= 0 then
		DebugLog("⚠ 总距离无效:", totalDistance)
		return false
	end

	return true
end

--[[
更新进度显示
]]
local function updateProgressDisplay()
	if not isActive or not playerIcon then
		return
	end

	-- 计算战场中心
	local battleCenter = computeBattleCenter()
	if battleCenter then
		-- 计算目标进度
		targetProgress = calculateProgress(battleCenter.Z)
	end

	-- 平滑过渡到目标进度
	currentProgress = currentProgress + (targetProgress - currentProgress) * PROGRESS_LERP_SPEED

	-- 更新玩家头像位置
	-- X轴: 0代表起点, 1代表终点
	-- Y轴固定为0.5
	playerIcon.Position = UDim2.new(currentProgress, 0, 0.5, 0)
end

--[[
显示进度UI
]]
local function showProgressUI()
	if not bgFrame then
		DebugLog("⚠ 进度UI不存在")
		return
	end

	-- 重置进度
	currentProgress = 0
	targetProgress = 0

	-- 重置玩家头像位置
	if playerIcon then
		playerIcon.Position = INITIAL_POSITION
	end

	-- 显示UI
	bgFrame.Visible = true
	DebugLog("进度UI已显示")
end

--[[
隐藏进度UI
]]
local function hideProgressUI()
	if not bgFrame then
		return
	end

	bgFrame.Visible = false
	DebugLog("进度UI已隐藏")
end

--[[
启动进度追踪
@param chapter number - 当前章节
@param stages number - 总关卡数
]]
local function startProgressTracking(chapter, stages)
	if isActive then
		return
	end

	-- 初始化数据
	if not initializeProgressData(chapter, stages) then
		DebugLog("⚠ 进度数据初始化失败")
		return
	end

	isActive = true

	-- 显示UI
	showProgressUI()

	-- 设置玩家头像
	setPlayerIcon()

	-- 启动渲染循环
	if not renderConnection then
		renderConnection = RunService.RenderStepped:Connect(updateProgressDisplay)
	end

	DebugLog("进度追踪已启动")
end

--[[
停止进度追踪
]]
local function stopProgressTracking()
	if not isActive then
		return
	end

	isActive = false

	-- 断开渲染连接
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	-- 隐藏UI
	hideProgressUI()

	DebugLog("进度追踪已停止")
end

-- ==================== 监听战役状态 ====================
task.spawn(function()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[DistanceProgressController] Events文件夹未找到")
		return
	end

	local campaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
	if not campaignEvents then
		warn("[DistanceProgressController] CampaignEvents未找到")
		return
	end

	local stateUpdate = campaignEvents:FindFirstChild("CampaignStateUpdate")
	if stateUpdate then
		-- V3.6: 接收额外参数 (state, stageNum, chapter, totalStagesInChapter)
		stateUpdate.OnClientEvent:Connect(function(state, stageNum, chapter, totalStagesInChapter)
			DebugLog("收到状态更新:", state, "关卡:", stageNum, "章节:", chapter, "总关卡数:", totalStagesInChapter)

			if state == "Preparing" then
				-- 准备阶段: 初始化并显示进度UI
				-- V3.6: 优先使用服务器发来的章节和关卡数
				local chapterToUse = chapter or 1
				local stagesToUse = totalStagesInChapter or 3

				-- 如果服务器没有发送，则尝试从配置获取
				if not chapter or not totalStagesInChapter then
					local StageConfig = nil
					pcall(function()
						StageConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StageConfig"))
					end)

					if StageConfig then
						local currentChapterAttr = player:GetAttribute("CurrentChapter")
						if currentChapterAttr then
							chapterToUse = currentChapterAttr
						end

						-- 使用StageConfig.GetStagesPerChapter()函数获取关卡数
						stagesToUse = StageConfig.GetStagesPerChapter(chapterToUse)
					end
				end

				startProgressTracking(chapterToUse, stagesToUse)

			elseif state == "Marching" or state == "PrepareBattle" or state == "Fighting" or state == "StageClear" then
				-- 战斗进行中: 确保进度追踪已启动
				if not isActive then
					startProgressTracking(currentChapter, totalStages)
				end

				-- 当进入新关卡时，尝试更新终点位置
				if stageNum and stageNum > 0 then
					local stageIdleFloor = getStageIdleFloor(stageNum)
					if stageIdleFloor then
						-- 更新已知的关卡位置信息
						DebugLog("关卡", stageNum, "IdleFloor Z:", stageIdleFloor.Position.Z)
					end
				end

			elseif state == "Victory" or state == "Defeat" then
				-- 胜利或失败: 停止进度追踪(隐藏UI)
				stopProgressTracking()

			elseif state == "Idle" then
				-- 闲置状态: 确保停止追踪
				stopProgressTracking()
			end
		end)
	end

	DebugLog("战役状态监听已启动")
end)

-- ==================== 初始化 ====================

-- 确保初始状态下进度UI隐藏
task.defer(function()
	if bgFrame then
		bgFrame.Visible = false
	end
end)

-- 设置玩家头像(预加载)
task.defer(setPlayerIcon)

DebugLog("DistanceProgressController已初始化")

-- 导出接口供其他脚本调用
return {
	Start = startProgressTracking,
	Stop = stopProgressTracking,
	IsActive = function() return isActive end,
}
