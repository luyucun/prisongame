--[[
脚本名称: GuideSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/GuideSystem
]]

--[[
新手引导系统模块 V3.9.1
职责:
1. 管理玩家的新手引导数据
2. 处理引导触发条件判断
3. 与客户端同步引导状态
4. 提供GM命令接口
V3.9.1新增: HAS_TWO_UNITS/ARRIVED_IDLE_FLOOR/TWO_UNITS_PLACED触发条件，UI聚焦引导支持
]]

local GuideSystem = {}

-- 引用服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local GuideConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GuideConfig"))

-- 收敛调试print，避免刷屏（仅在DEBUG_MODE开启时输出）
local _print = print
local function DebugPrint(...)
	if GameConfig.DEBUG_MODE then
		_print(...)
	end
end
local print = DebugPrint

-- 延迟加载的模块（避免循环依赖）
local DataManager = nil
local IdleCoinSystem = nil

-- 事件缓存
local guideEvents = nil

-- 玩家引导状态缓存 [UserId] = {activeGuideId, isPending...}
local playerGuideStates = {}

-- ==================== 私有函数 ====================

--[[
延迟加载DataManager
]]
local function GetDataManager()
	if not DataManager then
		DataManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("DataManager"))
	end
	return DataManager
end

--[[
延迟加载IdleCoinSystem
]]
local function GetIdleCoinSystem()
	if not IdleCoinSystem then
		local systemsFolder = ServerScriptService:FindFirstChild("Systems")
		if systemsFolder then
			local idleSystem = systemsFolder:FindFirstChild("IdleCoinSystem")
			if idleSystem then
				IdleCoinSystem = require(idleSystem)
			end
		end
	end
	return IdleCoinSystem
end

--[[
确保事件存在
]]
local function EnsureEventsExist()
	if guideEvents then
		return guideEvents
	end

	-- 获取或创建Events文件夹
	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then
		events = Instance.new("Folder")
		events.Name = "Events"
		events.Parent = ReplicatedStorage
	end

	-- 获取或创建GuideEvents文件夹
	local guideEventsFolder = events:FindFirstChild("GuideEvents")
	if not guideEventsFolder then
		guideEventsFolder = Instance.new("Folder")
		guideEventsFolder.Name = "GuideEvents"
		guideEventsFolder.Parent = events
	end

	-- 创建所需的RemoteEvent
	local eventNames = {
		"StartGuide",        -- 服务器→客户端：开始引导
		"CompleteGuide",     -- 服务器→客户端：完成引导
		"GuideArrived",      -- 客户端→服务器：玩家到达目标
		"SyncGuideData",     -- 服务器→客户端：同步引导数据
		"RequestGuideSync",  -- 客户端→服务器：请求同步引导数据
		"StartUIFocusGuide", -- 服务器→客户端：开始UI聚焦引导
		"UIFocusCompleted",  -- 客户端→服务器：UI聚焦引导完成
	}

	guideEvents = {}
	for _, eventName in ipairs(eventNames) do
		local event = guideEventsFolder:FindFirstChild(eventName)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = guideEventsFolder
		end
		guideEvents[eventName] = event
	end

	return guideEvents
end

--[[
获取玩家的引导数据
@param player Player - 玩家对象
@return table - 引导数据 {CompletedGuides = {guideId = true}, ...}
]]
local function GetPlayerGuideData(player)
	local dm = GetDataManager()
	if not dm then
		return {CompletedGuides = {}}
	end

	local playerData = dm.GetPlayerData(player)
	if not playerData then
		return {CompletedGuides = {}}
	end

	-- 确保GuideData字段存在
	if not playerData.GuideData then
		playerData.GuideData = {
			CompletedGuides = {},  -- 已完成的引导 {guideId = true}
		}
	end

	return playerData.GuideData
end

local function GetUnitCount(playerData)
	if not playerData then
		return 0
	end

	local count = 0
	if playerData.Units then
		for _, unitData in ipairs(playerData.Units) do
			if unitData then
				count = count + 1
			end
		end
	end

	if count > 0 then
		return count
	end

	count = 0
	if playerData.Inventory then
		for _, unitCount in pairs(playerData.Inventory) do
			if type(unitCount) == "number" and unitCount > 0 then
				count = count + unitCount
			end
		end
	end

	return count
end

local function GetPlacedUnitCount(playerData)
	if not playerData or not playerData.PlacedUnits then
		return 0
	end

	local count = 0
	for _, unitData in pairs(playerData.PlacedUnits) do
		if unitData then
			count = count + 1
		end
	end

	return count
end

--[[
检查引导是否已完成
@param player Player - 玩家对象
@param guideId number - 引导ID
@return boolean - 是否已完成
]]
local function IsGuideCompleted(player, guideId)
	local guideData = GetPlayerGuideData(player)
	-- 🔥修复：DataStore加载后number key会变成string key，需要同时检查两种类型
	return guideData.CompletedGuides[guideId] == true
		or guideData.CompletedGuides[tostring(guideId)] == true
end

--[[
标记引导为已完成
@param player Player - 玩家对象
@param guideId number - 引导ID
]]
local function MarkGuideCompleted(player, guideId)
	local dm = GetDataManager()
	if not dm then
		return
	end

	local playerData = dm.GetPlayerData(player)
	if not playerData then
		return
	end

	if not playerData.GuideData then
		playerData.GuideData = {CompletedGuides = {}}
	end

	playerData.GuideData.CompletedGuides[guideId] = true

	-- 保存数据
	dm.SavePlayerDataThrottled(player)

	print(string.format("[GuideSystem] 玩家 %s 完成引导 %d", player.Name, guideId))
end

--[[
检查引导触发条件
@param player Player - 玩家对象
@param guideConfig table - 引导配置
@return boolean - 是否满足触发条件
]]
local function CheckTriggerCondition(player, guideConfig)
	local condition = guideConfig.TriggerCondition

	if condition == "FIRST_JOIN" then
		-- 首次进入游戏：只要该引导未完成就返回true
		return not IsGuideCompleted(player, guideConfig.GuideId)

	elseif condition == "HAS_IDLE_COINS" then
		-- 有挂机金币可领取
		if IsGuideCompleted(player, guideConfig.GuideId) then
			return false
		end

		-- 检查挂机金币数量（仅允许登录时已有的待领取金币触发）
		local dm = GetDataManager()
		if dm then
			local idleCoinData = dm.GetIdleCoinData(player)
			if idleCoinData then
				if not idleCoinData.GuideEligibleOnLogin then
					return false
				end

				if (idleCoinData.PendingCoins or 0) > 0 then
					return true
				end
			end
		end
		return false

	elseif condition == "HAS_TWO_UNITS" then
		-- 获得两个兵种
		if IsGuideCompleted(player, guideConfig.GuideId) then
			return false
		end

		-- 必须先完成引导1001（前往商店）才能触发此引导
		if not IsGuideCompleted(player, 1001) then
			return false
		end

		-- 检查背包是否有两个兵种
		local dm = GetDataManager()
		if dm then
			local playerData = dm.GetPlayerData(player)
			if playerData then
				local unitCount = GetUnitCount(playerData)
				if unitCount >= 2 then
					return true
				end

				-- 仅买了一个兵但已自行摆放，则视为已完成IdleFloor引导
				local placedCount = GetPlacedUnitCount(playerData)
				if placedCount > 0 then
					GuideSystem.GMCompleteGuide(player, guideConfig.GuideId)
				end
			end
		end
		return false

	elseif condition == "ARRIVED_IDLE_FLOOR" then
		-- 到达IdleFloor（由引导1003完成后触发）
		if IsGuideCompleted(player, guideConfig.GuideId) then
			return false
		end

		-- 检查引导1003是否已完成
		return IsGuideCompleted(player, 1003)

	elseif condition == "TWO_UNITS_PLACED" then
		-- 摆放两个兵种
		if IsGuideCompleted(player, guideConfig.GuideId) then
			return false
		end

		-- 必须先完成引导1003（前往IdleFloor）或引导1004（点击背包）才能触发此引导
		-- 注意：引导1004可能被跳过，所以检查1003即可
		if not IsGuideCompleted(player, 1003) then
			return false
		end

		-- 检查是否有两个兵种被摆放在IdleFloor上
		local dm = GetDataManager()
		if dm then
			local playerData = dm.GetPlayerData(player)
			if playerData and playerData.PlacedUnits then
				local placedCount = GetPlacedUnitCount(playerData)
				if placedCount >= 2 then
					return true
				end
			end
		end
		return false
	end

	return false
end

--[[
获取玩家家园中的目标对象
@param player Player - 玩家对象
@param targetName string - 目标对象名称
@return Instance|nil - 目标对象
]]
local function GetTargetInPlayerHome(player, targetName)
	local dm = GetDataManager()
	if not dm then
		return nil
	end

	local homeSlot = dm.GetPlayerHomeSlot(player)
	if not homeSlot then
		return nil
	end

	-- 查找玩家家园
	local homeFolder = workspace:FindFirstChild("Home")
	if not homeFolder then
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then
		return nil
	end

	-- 查找目标对象
	return playerHome:FindFirstChild(targetName)
end

--[[
发送引导开始事件到客户端
@param player Player - 玩家对象
@param guideId number - 引导ID
@param targetPosition Vector3|nil - 目标位置（nil表示UI聚焦类型）
]]
local function SendStartGuide(player, guideId, targetPosition)
	local events = EnsureEventsExist()
	local guideConfig = GuideConfig.GetGuideById(guideId)

	if not guideConfig then
		return
	end

	-- 如果是UI聚焦类型
	if guideConfig.GuideType == GuideConfig.GuideType.UI_FOCUS then
		if events.StartUIFocusGuide then
			events.StartUIFocusGuide:FireClient(player, guideId, guideConfig.TargetUIPath)
		end
	else
		-- 普通Beam引导
		if events.StartGuide then
			events.StartGuide:FireClient(player, guideId, targetPosition)
		end
	end
end

--[[
发送引导完成事件到客户端
@param player Player - 玩家对象
@param guideId number - 引导ID
]]
local function SendCompleteGuide(player, guideId)
	local events = EnsureEventsExist()
	if events.CompleteGuide then
		events.CompleteGuide:FireClient(player, guideId)
	end
end

--[[
同步引导数据到客户端
@param player Player - 玩家对象
]]
local function SyncGuideDataToClient(player)
	local guideData = GetPlayerGuideData(player)
	local events = EnsureEventsExist()
	if events.SyncGuideData then
		events.SyncGuideData:FireClient(player, guideData)
	end
end

-- ==================== 公共接口 ====================

--[[
初始化新手引导系统
]]
function GuideSystem.Initialize()
	print("[GuideSystem] 初始化新手引导系统...")

	-- 确保事件存在
	EnsureEventsExist()

	-- 监听客户端事件
	if guideEvents.GuideArrived then
		guideEvents.GuideArrived.OnServerEvent:Connect(function(player, guideId)
			GuideSystem.OnGuideArrived(player, guideId)
		end)
	end

	if guideEvents.RequestGuideSync then
		guideEvents.RequestGuideSync.OnServerEvent:Connect(function(player)
			SyncGuideDataToClient(player)
		end)
	end

	if guideEvents.UIFocusCompleted then
		guideEvents.UIFocusCompleted.OnServerEvent:Connect(function(player, guideId)
			GuideSystem.OnGuideArrived(player, guideId)
		end)
	end

	print("[GuideSystem] 新手引导系统初始化完成")
end

--[[
初始化玩家的引导
@param player Player - 玩家对象
]]
function GuideSystem.InitializePlayerGuide(player)
	print(string.format("[GuideSystem] 初始化玩家 %s 的引导...", player.Name))

	-- 等待一小段时间，确保DataManager数据已加载
	task.wait(1)

	-- 检查并触发引导
	GuideSystem.CheckAndTriggerGuides(player)
end

--[[
检查并触发引导
@param player Player - 玩家对象
]]
function GuideSystem.CheckAndTriggerGuides(player)
	local enabledGuides = GuideConfig.GetEnabledGuides()

	for _, guideConfig in ipairs(enabledGuides) do
		-- 检查是否已完成
		if IsGuideCompleted(player, guideConfig.GuideId) then
			continue
		end

		-- 检查触发条件
		if CheckTriggerCondition(player, guideConfig) then
			-- 触发引导
			GuideSystem.TriggerGuide(player, guideConfig.GuideId)
			-- 每次只触发一个引导
			break
		end
	end
end

--[[
触发引导
@param player Player - 玩家对象
@param guideId number - 引导ID
@return boolean - 是否成功触发
]]
function GuideSystem.TriggerGuide(player, guideId)
	local guideConfig = GuideConfig.GetGuideById(guideId)
	if not guideConfig then
		warn("[GuideSystem] 无效的引导ID:", guideId)
		return false
	end

	-- 检查是否已完成
	if IsGuideCompleted(player, guideId) then
		print(string.format("[GuideSystem] 引导 %d 已完成，跳过", guideId))
		return false
	end

	-- 如果是UI聚焦类型的引导
	if guideConfig.GuideType == GuideConfig.GuideType.UI_FOCUS then
		-- 特殊处理：检查是否需要跳过
		if guideConfig.SkipIfNoUnits then
			-- 检查背包是否有兵种
			local dm = GetDataManager()
			if dm then
				local playerData = dm.GetPlayerData(player)
				if playerData then
					local hasUnits = false

					-- 🔥修复：优先检查新的 Units 数组
					if playerData.Units and #playerData.Units > 0 then
						hasUnits = true
					end

					-- 兼容旧的 Inventory map
					if not hasUnits and playerData.Inventory then
						for unitId, count in pairs(playerData.Inventory) do
							if count and count > 0 then
								hasUnits = true
								break
							end
						end
					end

					if not hasUnits then
						-- 没有兵种，跳过并标记为完成
						print(string.format("[GuideSystem] 引导 %d 跳过（背包无兵种）", guideId))
						MarkGuideCompleted(player, guideId)
						-- 检查下一个引导
						task.delay(0.5, function()
							if player and player.Parent then
								GuideSystem.CheckAndTriggerGuides(player)
							end
						end)
						return false
					end
				end
			end
		end

		-- 记录当前激活的引导（UI聚焦类型）
		playerGuideStates[player.UserId] = {
			activeGuideId = guideId,
			guideType = guideConfig.GuideType,
			targetUIPath = guideConfig.TargetUIPath,
		}

		-- 发送开始引导事件到客户端（UI聚焦类型）
		SendStartGuide(player, guideId, nil)  -- targetPosition为nil表示UI聚焦类型

		print(string.format("[GuideSystem] 玩家 %s 触发UI聚焦引导 %d (%s)", player.Name, guideId, guideConfig.Name))
		return true
	end

	-- 普通引导（Beam类型）
	-- 获取目标对象
	local target = GetTargetInPlayerHome(player, guideConfig.TargetName)
	if not target then
		warn(string.format("[GuideSystem] 找不到目标对象: %s", guideConfig.TargetName))
		return false
	end

	-- 获取目标位置
	local targetPosition
	if target:IsA("Model") then
		local primaryPart = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart")
		if primaryPart then
			targetPosition = primaryPart.Position
		else
			-- 尝试找到任意Part
			local anyPart = target:FindFirstChildOfClass("Part") or target:FindFirstChildOfClass("MeshPart")
			if anyPart then
				targetPosition = anyPart.Position
			end
		end
	elseif target:IsA("BasePart") then
		targetPosition = target.Position
	end

	if not targetPosition then
		warn(string.format("[GuideSystem] 无法获取目标位置: %s", guideConfig.TargetName))
		return false
	end

	-- 记录当前激活的引导
	playerGuideStates[player.UserId] = {
		activeGuideId = guideId,
		targetPosition = targetPosition,
		targetName = guideConfig.TargetName,
	}

	-- 发送开始引导事件到客户端
	SendStartGuide(player, guideId, targetPosition)

	print(string.format("[GuideSystem] 玩家 %s 触发引导 %d (%s)", player.Name, guideId, guideConfig.Name))
	return true
end

--[[
当玩家到达引导目标时调用
@param player Player - 玩家对象
@param guideId number - 引导ID
]]
function GuideSystem.OnGuideArrived(player, guideId)
	-- 验证是否是当前激活的引导
	local state = playerGuideStates[player.UserId]
	if not state or state.activeGuideId ~= guideId then
		return
	end

	-- 标记引导完成
	MarkGuideCompleted(player, guideId)

	-- 清除激活状态
	playerGuideStates[player.UserId] = nil

	-- 发送完成事件到客户端
	SendCompleteGuide(player, guideId)

	-- 检查是否有下一个引导
	task.delay(0.5, function()
		if player and player.Parent then
			GuideSystem.CheckAndTriggerGuides(player)
		end
	end)
end

--[[
清理玩家的引导状态
@param player Player - 玩家对象
]]
function GuideSystem.CleanupPlayer(player)
	playerGuideStates[player.UserId] = nil
end

--[[
获取玩家当前激活的引导ID
@param player Player - 玩家对象
@return number|nil - 引导ID
]]
function GuideSystem.GetActiveGuideId(player)
	local state = playerGuideStates[player.UserId]
	return state and state.activeGuideId
end

--[[
检查指定引导是否已完成
@param player Player - 玩家对象
@param guideId number - 引导ID
@return boolean - 是否已完成
]]
function GuideSystem.IsGuideCompleted(player, guideId)
	return IsGuideCompleted(player, guideId)
end

--[[
获取玩家已完成的所有引导ID
@param player Player - 玩家对象
@return table - 已完成的引导ID数组
]]
function GuideSystem.GetCompletedGuides(player)
	local guideData = GetPlayerGuideData(player)
	local completed = {}
	for guideId, _ in pairs(guideData.CompletedGuides) do
		-- 🔥修复：统一转换为number类型返回
		local numId = tonumber(guideId)
		if numId then
			table.insert(completed, numId)
		end
	end
	return completed
end

-- ==================== GM命令接口 ====================

--[[
GM命令：触发指定引导
@param player Player - 玩家对象
@param guideId number - 引导ID
@return boolean - 是否成功
]]
function GuideSystem.GMTriggerGuide(player, guideId)
	return GuideSystem.TriggerGuide(player, guideId)
end

--[[
GM命令：重置指定引导
@param player Player - 玩家对象
@param guideId number - 引导ID
@return boolean - 是否成功
]]
function GuideSystem.GMResetGuide(player, guideId)
	local dm = GetDataManager()
	if not dm then
		return false
	end

	local playerData = dm.GetPlayerData(player)
	if not playerData or not playerData.GuideData then
		return false
	end

	-- 🔥修复：同时移除number和string两种key的完成标记
	playerData.GuideData.CompletedGuides[guideId] = nil
	playerData.GuideData.CompletedGuides[tostring(guideId)] = nil

	-- 保存数据
	dm.SavePlayerDataThrottled(player)

	print(string.format("[GuideSystem] GM重置玩家 %s 的引导 %d", player.Name, guideId))
	return true
end

--[[
GM命令：重置所有引导
@param player Player - 玩家对象
@return boolean - 是否成功
]]
function GuideSystem.GMResetAllGuides(player)
	local dm = GetDataManager()
	if not dm then
		return false
	end

	local playerData = dm.GetPlayerData(player)
	if not playerData then
		return false
	end

	-- 重置引导数据
	playerData.GuideData = {
		CompletedGuides = {},
	}

	-- 清除激活状态
	playerGuideStates[player.UserId] = nil

	-- 保存数据
	dm.SavePlayerDataThrottled(player)

	-- 通知客户端清除引导
	SendCompleteGuide(player, 0)  -- 0表示清除所有

	print(string.format("[GuideSystem] GM重置玩家 %s 的所有引导", player.Name))
	return true
end

--[[
GM命令：强制完成指定引导
@param player Player - 玩家对象
@param guideId number - 引导ID
@return boolean - 是否成功
]]
function GuideSystem.GMCompleteGuide(player, guideId)
	-- 标记完成
	MarkGuideCompleted(player, guideId)

	-- 如果当前激活的就是这个引导，清除状态
	local state = playerGuideStates[player.UserId]
	if state and state.activeGuideId == guideId then
		playerGuideStates[player.UserId] = nil
		SendCompleteGuide(player, guideId)
	end

	return true
end

return GuideSystem
