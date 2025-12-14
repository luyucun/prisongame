--[[
=====================================================
脚本名称: PowerSystem.lua
脚本类型: Script
脚本位置: ServerScriptService/Systems/PowerSystem
版本: V3.9.2
功能描述: 服务端战斗力管理系统
=====================================================
--]]

local PowerSystem = {}

-- ==================== 服务引用 ====================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ==================== 模块引用 ====================
local PowerConfig = require(ReplicatedStorage.Config.PowerConfig)
local UnitConfig = require(ReplicatedStorage.Config.UnitConfig)

-- 延迟加载避免循环依赖
local DataManager
local InventorySystem

-- ==================== 数据存储 ====================
-- 玩家战斗力缓存
local playerPowerCache = {}

-- ==================== RemoteEvent ====================
local PowerEvents
local PowerUpdateEvent

-- ==================== 初始化 ====================

function PowerSystem.Initialize()
	-- 延迟加载模块
	DataManager = require(game:GetService("ServerScriptService").Core.DataManager)
	InventorySystem = require(game:GetService("ServerScriptService").Systems.InventorySystem)

	-- 在 Events 文件夹下查找/创建 PowerEvents
	local eventsFolder = ReplicatedStorage:WaitForChild("Events")

	PowerEvents = eventsFolder:FindFirstChild("PowerEvents")
	if not PowerEvents then
		PowerEvents = Instance.new("Folder")
		PowerEvents.Name = "PowerEvents"
		PowerEvents.Parent = eventsFolder
	end

	-- 创建/获取PowerUpdate事件
	PowerUpdateEvent = PowerEvents:FindFirstChild("PowerUpdate")
	if not PowerUpdateEvent then
		PowerUpdateEvent = Instance.new("RemoteEvent")
		PowerUpdateEvent.Name = "PowerUpdate"
		PowerUpdateEvent.Parent = PowerEvents
	end

	-- 创建/获取RequestPower事件
	local RequestPowerEvent = PowerEvents:FindFirstChild("RequestPower")
	if not RequestPowerEvent then
		RequestPowerEvent = Instance.new("RemoteEvent")
		RequestPowerEvent.Name = "RequestPower"
		RequestPowerEvent.Parent = PowerEvents
	end

	-- 处理客户端请求战斗力
	RequestPowerEvent.OnServerEvent:Connect(function(player)
		PowerSystem.RecalculatePlayerPower(player)
	end)

	-- 监听玩家加入
	Players.PlayerAdded:Connect(function(player)
		PowerSystem.OnPlayerJoin(player)
	end)

	-- 监听玩家离开
	Players.PlayerRemoving:Connect(function(player)
		PowerSystem.OnPlayerLeave(player)
	end)

	-- 处理已在线玩家
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			PowerSystem.OnPlayerJoin(player)
		end)
	end
end

-- ==================== 核心功能 ====================

--[[
	玩家加入时初始化战斗力
--]]
function PowerSystem.OnPlayerJoin(player)
	-- 初始化缓存
	playerPowerCache[player] = {
		TotalPower = 0,
		UnitPowers = {},
		LastUpdate = tick()
	}

	-- 延迟计算战斗力作为兜底
	task.spawn(function()
		-- 等待玩家数据加载完成（最多等待20秒）
		local maxWait = 20
		local startTime = tick()
		local playerData = nil

		while tick() - startTime < maxWait do
			if not player or not player:IsDescendantOf(Players) then
				return
			end

			local success, result = pcall(function()
				return DataManager.GetPlayerData(player)
			end)

			if success and result then
				playerData = result
				break
			end

			task.wait(0.5)
		end

		if not playerData then
			return
		end

		-- 计算战斗力并缓存
		local cache = playerPowerCache[player]
		if not cache then
			cache = {
				TotalPower = 0,
				UnitPowers = {},
				LastUpdate = tick()
			}
			playerPowerCache[player] = cache
		end

		local unitsArray = playerData.Units or {}
		local totalPower = 0

		for _, unitInfo in ipairs(unitsArray) do
			if unitInfo then
				local unitId = unitInfo.UnitId
				local level = unitInfo.Level or 1
				local instanceId = unitInfo.InstanceId or ("Unit_" .. tostring(unitId))

				local power = PowerConfig.CalculateUnitPowerByIdAndLevel(unitId, level)
				cache.UnitPowers[instanceId] = power
				totalPower = totalPower + power
			end
		end

		-- 兼容旧存档
		if #unitsArray == 0 then
			local inventory = playerData.Inventory or {}
			for unitId, count in pairs(inventory) do
				if count > 0 then
					local power = PowerConfig.CalculateUnitPowerByIdAndLevel(unitId, 1)
					totalPower = totalPower + power * count
				end
			end

			local placedUnits = playerData.PlacedUnits or {}
			for _, unitInfo in pairs(placedUnits) do
				local unitId = unitInfo.UnitId
				local level = unitInfo.Level or 1
				local power = PowerConfig.CalculateUnitPowerByIdAndLevel(unitId, level)
				totalPower = totalPower + power
			end
		end

		cache.TotalPower = totalPower
		cache.LastUpdate = tick()

		-- 延迟30秒后主动推送一次（兜底）
		task.wait(30)

		if not player or not player:IsDescendantOf(Players) then
			return
		end

		local currentCache = playerPowerCache[player]
		if currentCache and currentCache.LastUpdate > cache.LastUpdate then
			return
		end

		PowerSystem.SyncPowerToClient(player, totalPower)
	end)
end

--[[
	玩家离开时清理缓存
--]]
function PowerSystem.OnPlayerLeave(player)
	playerPowerCache[player] = nil
end

--[[
	重新计算玩家总战斗力
	@param player Player - 玩家
--]]
function PowerSystem.RecalculatePlayerPower(player)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	local success, result = pcall(function()
		local playerData = DataManager.GetPlayerData(player)
		if not playerData then
			return
		end

		local unitsArray = playerData.Units or {}

		local cache = playerPowerCache[player]
		if not cache then
			cache = {
				TotalPower = 0,
				UnitPowers = {},
				LastUpdate = tick()
			}
			playerPowerCache[player] = cache
		end

		cache.UnitPowers = {}
		local totalPower = 0

		if unitsArray and #unitsArray > 0 then
			for _, unitInfo in ipairs(unitsArray) do
				if unitInfo then
					local unitId = unitInfo.UnitId
					local level = unitInfo.Level or 1
					local instanceId = unitInfo.InstanceId or ("Unit_" .. tostring(unitId))

					local power = PowerConfig.CalculateUnitPowerByIdAndLevel(unitId, level)
					cache.UnitPowers[instanceId] = power
					totalPower = totalPower + power
				end
			end
		else
			-- 兼容旧存档
			local inventory = playerData.Inventory or {}
			for unitId, count in pairs(inventory) do
				if count > 0 then
					local power = PowerConfig.CalculateUnitPowerByIdAndLevel(unitId, 1)
					totalPower = totalPower + power * count
				end
			end

			local placedUnits = playerData.PlacedUnits or {}
			for _, unitInfo in pairs(placedUnits) do
				local unitId = unitInfo.UnitId
				local level = unitInfo.Level or 1
				local power = PowerConfig.CalculateUnitPowerByIdAndLevel(unitId, level)
				totalPower = totalPower + power
			end
		end

		cache.TotalPower = totalPower
		cache.LastUpdate = tick()

		PowerSystem.SyncPowerToClient(player, totalPower)
	end)

	if not success then
		warn("[PowerSystem] RecalculatePlayerPower 出错:", result)
	end
end

--[[
	添加兵种时更新战斗力
	@param player Player - 玩家
	@param unitId string - 兵种ID
	@param count number - 数量
--]]
function PowerSystem.OnAddUnit(player, unitId, count)
	if not player or not unitId or not count then
		return
	end

	local success, result = pcall(function()
		PowerSystem.RecalculatePlayerPower(player)
	end)

	if not success then
		warn("[PowerSystem] OnAddUnit 出错:", result)
	end
end

--[[
	移除兵种时更新战斗力
	@param player Player - 玩家
	@param unitId string - 兵种ID
	@param level number - 等级
	@param count number - 数量
--]]
function PowerSystem.OnRemoveUnit(player, unitId, level, count)
	if not player or not unitId or not count then
		return
	end

	local success, result = pcall(function()
		PowerSystem.RecalculatePlayerPower(player)
	end)

	if not success then
		warn("[PowerSystem] OnRemoveUnit 出错:", result)
	end
end

--[[
	兵种合成时更新战斗力
	@param player Player - 玩家
	@param unitId string - 兵种ID
	@param oldLevel number - 旧等级
	@param newLevel number - 新等级
--]]
function PowerSystem.OnMergeUnit(player, unitId, oldLevel, newLevel)
	if not player or not unitId or not oldLevel or not newLevel then
		return
	end

	local success, result = pcall(function()
		PowerSystem.RecalculatePlayerPower(player)
	end)

	if not success then
		warn("[PowerSystem] OnMergeUnit 出错:", result)
	end
end

--[[
	同步战斗力到客户端
	@param player Player - 玩家
	@param totalPower number - 总战斗力
--]]
function PowerSystem.SyncPowerToClient(player, totalPower)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	if not PowerUpdateEvent then
		return
	end

	local success, result = pcall(function()
		PowerUpdateEvent:FireClient(player, totalPower)
	end)

	if not success then
		warn("[PowerSystem] SyncPowerToClient 出错:", result)
	end
end

--[[
	获取玩家总战斗力
	@param player Player - 玩家
	@return number - 总战斗力
--]]
function PowerSystem.GetPlayerTotalPower(player)
	if not player then
		return 0
	end

	local cache = playerPowerCache[player]
	if cache then
		return cache.TotalPower or 0
	end

	return 0
end

-- ==================== 导出模块 ====================

return PowerSystem
