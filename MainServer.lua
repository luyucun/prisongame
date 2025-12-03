--[[
脚本名称: MainServer
脚本类型: Script (服务端主脚本)
脚本位置: ServerScriptService/MainServer
]]

--[[
服务端主启动脚本
职责:
1. 初始化所有服务端系统
2. 按正确的顺序加载各个模块
3. 处理系统启动错误
]]

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 引用核心模块
local DataManager = require(ServerScriptService.Core.DataManager)
local PlayerManager = require(ServerScriptService.Core.PlayerManager)

-- 引用系统模块
local CurrencySystem = require(ServerScriptService.Systems.CurrencySystem)
local HomeSystem = require(ServerScriptService.Systems.HomeSystem)
local InventorySystem = require(ServerScriptService.Systems.InventorySystem)
local PlacementSystem = require(ServerScriptService.Systems.PlacementSystem)
local MergeSystem = require(ServerScriptService.Systems.MergeSystem)  -- V1.4新增
local PhysicsManager = require(ServerScriptService.Systems.PhysicsManager)
local GMCommandSystem = require(ServerScriptService.Systems.GMCommandSystem)
-- V1.5新增 - 战斗系统
local CombatSystem = require(ServerScriptService.Systems.CombatSystem)
local ProjectileSystem = require(ServerScriptService.Systems.ProjectileSystem)
local UnitAI = require(ServerScriptService.Systems.UnitAI)
local BattleManager = require(ServerScriptService.Systems.BattleManager)
local BattleTestSystem = require(ServerScriptService.Systems.BattleTestSystem)
-- V1.5.1新增 - 战斗基础服务
local HitboxService = require(ServerScriptService.Systems.HitboxService)
local UnitManager = require(ServerScriptService.Systems.UnitManager)
-- V1.5.4新增 - 武器特效系统
local WeaponEffectSystem = require(ServerScriptService.Systems.WeaponEffectSystem)
-- V2.0新增 - 战役系统
local CampaignManager = require(ServerScriptService.Systems.CampaignManager)
-- V2.0.1新增 - 门控系统
local DoorControlService = require(ServerScriptService.Systems.DoorControlService)
-- V2.1新增 - 商店系统
local ShopSystem = require(ServerScriptService.Systems.ShopSystem)
-- V3.1新增 - 技能商店系统
local SkillShopSystem = require(ServerScriptService.Systems.SkillShopSystem)
-- V2.5新增 - 碰撞系统（寻路性能优化）
local CollisionSystem = require(ServerScriptService.Systems.CollisionSystem)
-- V2.6新增 - 挂机金币系统
local IdleCoinSystem = require(ServerScriptService.Systems.IdleCoinSystem)
-- V3.0新增 - 技能系统
local SkillSystem = require(ServerScriptService.Systems.SkillSystem)
-- V3.2新增 - Loading系统
local LoadingSystem = require(ServerScriptService.Systems.LoadingSystem)
-- V3.3新增 - 任务系统
local TaskSystem = require(ServerScriptService.Systems.TaskSystem)

-- ==================== 系统初始化顺序 ====================

local function InitializeServer()
    local initializationFailed = false

    -- 0. 初始化物理管理系统(必须首先初始化)
    local success, result = pcall(function()
        return PhysicsManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "物理管理系统初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "物理管理系统初始化失败(返回false)")
        initializationFailed = true
    end

    -- 0.1 初始化碰撞系统 (V2.5寻路性能优化 - 必须在物理系统之后)
    success, result = pcall(function()
        return CollisionSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "碰撞系统初始化失败(异常):", result)
        -- 碰撞系统失败不阻止游戏运行，但会影响寻路性能
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "碰撞系统初始化失败(返回false)")
    end

    -- 1. 初始化基地系统(验证地图结构)
    success, result = pcall(function()
        return HomeSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "基地系统初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "基地系统初始化失败(返回false)")
        initializationFailed = true
    end

    -- 1.1 初始化门控系统 (V2.0.1新增)
    success, result = pcall(function()
        return DoorControlService.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "门控系统初始化失败(异常):", result)
        -- 门控不是关键系统，失败不阻止游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "门控系统初始化失败(返回false)")
    end

    -- 2. 初始化货币系统(连接远程事件)
    success, result = pcall(function()
        return CurrencySystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "货币系统初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "货币系统初始化失败(返回false),无法处理货币操作!")
        warn(GameConfig.LOG_PREFIX, "请检查ReplicatedStorage/Events/CurrencyEvents是否存在")
        initializationFailed = true
    end

    -- 3. 初始化玩家管理器(连接玩家事件)
    success, result = pcall(function()
        return PlayerManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "玩家管理器初始化失败(异常):", result)
        initializationFailed = true
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "玩家管理器初始化失败(返回false)")
        initializationFailed = true
    end

    -- 4. 初始化背包系统(连接背包事件)
    success, result = pcall(function()
        InventorySystem.Initialize()
        return true
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "背包系统初始化失败(异常):", result)
        -- 背包系统不是关键系统,失败不影响游戏运行
    end

    -- 5. 初始化放置系统(连接放置事件) V1.2新增
    success, result = pcall(function()
        return PlacementSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "放置系统初始化失败(异常):", result)
        -- 放置系统不是关键系统,失败不影响游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "放置系统初始化失败(返回false),放置功能将不可用")
    end

    -- 5.5. 初始化合成系统(连接合成事件) V1.4新增
    success, result = pcall(function()
        return MergeSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "合成系统初始化失败(异常):", result)
        -- 合成系统不是关键系统,失败不影响游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "合成系统初始化失败(返回false),合成功能将不可用")
    end

    -- 5.6. 初始化商店系统(V2.1新增 - 数据驱动版)
    success, result = pcall(function()
        return ShopSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "⚠️ 商店系统初始化失败(异常):", result)
        warn(GameConfig.LOG_PREFIX, "请检查：")
        warn("  1. ReplicatedStorage/Events/ShopEvents 是否已创建")
        warn("  2. ShopEvents 下是否有 RequestShopList、ShopList、PurchaseUnit、PurchaseResult")
        warn("  3. ReplicatedStorage/Config/ShopConfig 是否已创建")
        warn("  4. ShopConfig 是否正确配置")
        -- 商店系统不是关键系统,失败不影响游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "商店系统初始化失败(返回false),购买功能将不可用")
    end

    -- 5.7. 初始化技能商店系统(V3.1新增)
    success, result = pcall(function()
        return SkillShopSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "⚠️ 技能商店系统初始化失败(异常):", result)
        warn(GameConfig.LOG_PREFIX, "请检查：")
        warn("  1. ReplicatedStorage/Events/SkillShopEvents 是否已创建")
        warn("  2. SkillShopEvents 下是否有 RequestSkillShopList、SkillShopList、PurchaseSkill、SkillPurchaseResult")
        warn("  3. ReplicatedStorage/Config/SkillShopConfig 是否已创建")
        -- 技能商店系统不是关键系统,失败不影响游戏运行
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "技能商店系统初始化失败(返回false),技能购买功能将不可用")
    end

    -- 6. 初始化GM命令系统(连接聊天事件)
    success, result = pcall(function()
        GMCommandSystem.Initialize()
        return true
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "GM命令系统初始化失败(异常):", result)
        -- GM系统不是关键系统,失败不影响游戏运行
    end

    -- 7. 初始化战斗系统(V1.5新增, V1.5.1优化)

    -- 7.0 初始化HitboxService (V1.5.1新增 - 碰撞判定服务)
    success, result = pcall(function()
        return HitboxService.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "碰撞判定服务初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "碰撞判定服务初始化失败(返回false)")
    end

    -- 7.0b 初始化UnitManager (V1.5.1新增 - 单位索引管理)
    success, result = pcall(function()
        return UnitManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "单位索引管理初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "单位索引管理初始化失败(返回false)")
    end

    -- 7.1 初始化CombatSystem
    success, result = pcall(function()
        return CombatSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战斗系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战斗系统初始化失败(返回false)")
    end

    -- 7.2 初始化ProjectileSystem
    success, result = pcall(function()
        return ProjectileSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "弹道系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "弹道系统初始化失败(返回false)")
    end

    -- 7.2.5 初始化WeaponEffectSystem (V1.5.4新增)
    success, result = pcall(function()
        return WeaponEffectSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "武器特效系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "武器特效系统初始化失败(返回false)")
    end

    -- 7.3 初始化UnitAI
    success, result = pcall(function()
        return UnitAI.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "兵种AI系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "兵种AI系统初始化失败(返回false)")
    end

    -- 7.4 初始化BattleManager
    success, result = pcall(function()
        return BattleManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战斗管理器初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战斗管理器初始化失败(返回false)")
    end

    -- 7.5 初始化BattleTestSystem
    success, result = pcall(function()
        return BattleTestSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战斗测试系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战斗测试系统初始化失败(返回false)")
    end

    -- 8. 初始化战役系统 (V2.0新增)
    success, result = pcall(function()
        return CampaignManager.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "战役系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "战役系统初始化失败(返回false)")
    end

    -- 9. 初始化挂机金币系统 (V2.6新增)
    success, result = pcall(function()
        return IdleCoinSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "挂机金币系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "挂机金币系统初始化失败(返回false)")
    end

    -- 10. 初始化技能系统 (V3.0新增)
    success, result = pcall(function()
        return SkillSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "技能系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "技能系统初始化失败(返回false)")
    end

    -- 11. 初始化Loading系统 (V3.2新增)
    success, result = pcall(function()
        return LoadingSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "Loading系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "Loading系统初始化失败(返回false)")
    end

    -- 12. 初始化任务系统 (V3.3新增)
    success, result = pcall(function()
        return TaskSystem.Initialize()
    end)
    if not success then
        warn(GameConfig.LOG_PREFIX, "任务系统初始化失败(异常):", result)
    elseif result == false then
        warn(GameConfig.LOG_PREFIX, "任务系统初始化失败(返回false)")
    end

    -- 检查是否有关键系统初始化失败
    if initializationFailed then
        warn("==========================================")
        warn(GameConfig.LOG_PREFIX, "警告: 一个或多个系统初始化失败!")
        warn(GameConfig.LOG_PREFIX, "服务端可能无法正常工作,请检查上述错误信息")
        warn("==========================================")
        return false
    end

    return true
end

-- ==================== 启动服务端 ====================

-- 使用pcall包裹初始化过程,防止崩溃
local success, result = pcall(InitializeServer)

if not success then
    warn("==========================================")
    warn(GameConfig.LOG_PREFIX, "严重错误: 服务端初始化过程崩溃!")
    warn(GameConfig.LOG_PREFIX, "错误信息:", result)
    warn("==========================================")
elseif result == false then
    warn("==========================================")
    warn(GameConfig.LOG_PREFIX, "服务端初始化未完全成功,某些功能可能不可用")
    warn("==========================================")
end

-- ==================== 调试命令(仅调试模式) ====================

if GameConfig.DEBUG_MODE then
    -- 提供一些调试函数
    _G.DebugAddCoins = function(playerName, amount)
        local Players = game:GetService("Players")
        local player = Players:FindFirstChild(playerName)
        if player then
            CurrencySystem.AddCoins(player, amount, "调试添加")
        else
            warn(GameConfig.LOG_PREFIX, "找不到玩家:", playerName)
        end
    end

    _G.DebugGetPlayerData = function(playerName)
        local Players = game:GetService("Players")
        local player = Players:FindFirstChild(playerName)
        if player then
            local data = DataManager.GetPlayerData(player)
            if not data then
                warn(GameConfig.LOG_PREFIX, "玩家数据不存在:", playerName)
            end
        else
            warn(GameConfig.LOG_PREFIX, "找不到玩家:", playerName)
        end
    end

    _G.DebugGetHomeOccupancy = function()
        local occupancy = PlayerManager.GetHomeOccupancy()
        for slot = 1, GameConfig.HOME_COUNT do
            local player = occupancy[slot]
        end
    end
end

-- ==================== 玩家事件处理 (V2.0.1新增) ====================

local Players = game:GetService("Players")

-- 玩家加入时初始化基地
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()  -- 使用task.spawn避免阻塞其他玩家加入
		-- V3.2新增：开始玩家加载流程
		LoadingSystem.StartPlayerLoading(player)

		-- 🔥修复竞态条件：等待玩家数据加载完成
		-- V3.2: 通知数据加载阶段开始
		LoadingSystem.NotifyDataLoading(player, 0)
		local playerData = DataManager.WaitForPlayerData(player, 10)
		if not playerData then
			warn(GameConfig.LOG_PREFIX, "玩家数据加载失败，跳过初始化 -", player.Name)
			-- V3.2: 即使数据加载失败也要完成Loading流程
			LoadingSystem.ForceCompleteLoading(player)
			return
		end
		-- V3.2: 通知数据加载完成
		LoadingSystem.NotifyDataLoadComplete(player)

		-- 🔥等待HomeSlot被设置（最多等待15秒）
		-- V3.2: 通知基地设置阶段开始
		LoadingSystem.NotifyHomeSetup(player, 0)
		local homeId = nil
		local maxWaitTime = 15
		local startTime = tick()
		while tick() - startTime < maxWaitTime do
			homeId = PlayerManager.GetPlayerHomeId(player)
			if homeId and homeId > 0 then
				break
			end
			-- V3.2: 更新基地设置进度
			LoadingSystem.NotifyHomeSetup(player, (tick() - startTime) / maxWaitTime * 0.5)
			task.wait(0.2)
		end

		if not homeId or homeId <= 0 then
			warn(GameConfig.LOG_PREFIX, "等待HomeId超时，跳过部分初始化 -", player.Name)
		end

		if homeId and homeId > 0 then
			-- 初始化玩家基地（确保门关闭）
			pcall(function()
				HomeSystem.InitializePlayerHome(homeId, player)
			end)
		end
		-- V3.2: 通知基地设置完成
		LoadingSystem.NotifyHomeSetupComplete(player)

		-- V3.2: 通知场景设置阶段开始
		LoadingSystem.NotifySceneSetup(player, 0)

		-- V2.1修复：初始化玩家商店库存系统
		pcall(function()
			ShopSystem.InitializePlayerShopTimer(player, "UnitShop")
			print(string.format(
				"%s [MainServer] 玩家 %s 商店库存系统已初始化",
				GameConfig.LOG_PREFIX,
				player.Name
			))
		end)
		LoadingSystem.NotifySceneSetup(player, 0.25)

		-- V3.1新增：初始化玩家技能商店库存系统
		pcall(function()
			SkillShopSystem.InitializePlayerSkillShopTimer(player, "SkillShop")
			print(string.format(
				"%s [MainServer] 玩家 %s 技能商店库存系统已初始化",
				GameConfig.LOG_PREFIX,
				player.Name
			))
		end)
		LoadingSystem.NotifySceneSetup(player, 0.5)

		-- V2.6新增：初始化挂机金币系统（HomeSlot已确认存在）
		pcall(function()
			IdleCoinSystem.OnPlayerJoin(player)
			print(string.format(
				"%s [MainServer] 玩家 %s 挂机金币系统已初始化",
				GameConfig.LOG_PREFIX,
				player.Name
			))
		end)
		LoadingSystem.NotifySceneSetup(player, 0.75)

		-- V3.2: 通知场景设置完成
		LoadingSystem.NotifySceneSetupComplete(player)

		-- V3.2: 通知数据同步阶段开始
		LoadingSystem.NotifyDataSync(player, 0)

		-- V3.0新增：同步技能背包数据到客户端
		pcall(function()
			SkillSystem.SyncSkillInventory(player)
			print(string.format(
				"%s [MainServer] 玩家 %s 技能背包已同步",
				GameConfig.LOG_PREFIX,
				player.Name
			))
		end)
		LoadingSystem.NotifyDataSync(player, 0.5)

		-- V3.3新增：初始化玩家任务数据并同步到客户端
		pcall(function()
			TaskSystem.InitializePlayerTask(player)
			print(string.format(
				"%s [MainServer] 玩家 %s 任务系统已初始化",
				GameConfig.LOG_PREFIX,
				player.Name
			))
		end)
		LoadingSystem.NotifyDataSync(player, 0.75)

		-- V3.2: 通知数据同步完成（这会尝试完成加载流程）
		LoadingSystem.NotifyDataSyncComplete(player)
	end)
end)

-- 玩家离开时清理
Players.PlayerRemoving:Connect(function(player)
	local playerId = player.UserId
	local homeId = PlayerManager.GetPlayerHomeId(player)

	-- V3.2新增：清理玩家加载状态
	pcall(function()
		LoadingSystem.CleanupPlayer(player)
	end)

	-- 1. 如果玩家在战役中，强制结束战役并关门
	local campaignData = CampaignManager.ActiveCampaigns[playerId]
	if campaignData then
		pcall(function()
			CampaignManager.OnCampaignEnd(campaignData, false)
		end)
	end

	-- 2. 清理基地（关闭门）
	if homeId then
		pcall(function()
			HomeSystem.CleanupPlayerHome(homeId, player)
		end)
	end

	-- 3. V2.6新增：记录玩家登出时间（用于挂机金币计算）
	pcall(function()
		IdleCoinSystem.OnPlayerLeave(player)
	end)
end)

-- ==================== 🔥修复持久化：服务器关闭数据保存 ====================

-- 服务器关闭时保存所有玩家数据（🔥修复数据丢失问题）
game:BindToClose(function()
	print(GameConfig.LOG_PREFIX .. " [MainServer] 🔥服务器关闭中，正在保存所有玩家数据...")

	local startTime = tick()
	local savedCount = 0
	local errorCount = 0

	-- 🔥修复：标记服务器正在关闭
	DataManager.SetShuttingDown(true)

	-- 🔥修复：先保存当前在线玩家的快照（避免Roblox清理玩家后无法遍历）
	local Players = game:GetService("Players")
	local activePlayersSnapshot = Players:GetPlayers()

	print(string.format(
		"%s [MainServer] 检测到 %d 个在线玩家，开始保存...",
		GameConfig.LOG_PREFIX,
		#activePlayersSnapshot
	))

	-- 第一步：保存在线玩家数据（包含地面兵种数据）
	for _, player in pairs(activePlayersSnapshot) do
		task.spawn(function()  -- 并行保存提高效率
			local success, error = pcall(function()
				-- 🔥关键：先保存地面兵种数据到DataManager
				if PlacementSystem and PlacementSystem.OnPlayerLeaving then
					PlacementSystem.OnPlayerLeaving(player)
				end

				-- 然后保存所有数据到DataStore
				local saved = DataManager.SavePlayerData(player)
				if saved then
					savedCount = savedCount + 1
					print(string.format(
						"%s [MainServer] ✅ 在线玩家 %s 数据已保存",
						GameConfig.LOG_PREFIX,
						player.Name
					))
				else
					errorCount = errorCount + 1
					warn(string.format(
						"%s [MainServer] ❌ 在线玩家 %s 数据保存失败",
						GameConfig.LOG_PREFIX,
						player.Name
					))
				end
			end)

			if not success then
				errorCount = errorCount + 1
				warn(string.format(
					"%s [MainServer] ❌ 在线玩家 %s 数据保存异常: %s",
					GameConfig.LOG_PREFIX,
					player.Name,
					tostring(error)
				))
			end
		end)
	end

	-- 第二步：等待并行保存完成
	task.wait(2)  -- 给并行任务一些时间

	-- 第三步：兜底保存缓存中的数据（防止Roblox已删除Player对象）
	local allPlayerData = DataManager.GetAllPlayerData()
	for userIdRaw, playerData in pairs(allPlayerData) do
		-- 修复：确保userId是数字类型
		local userId = tonumber(userIdRaw)
		if userId then
			local isAlreadySaved = false
			-- 检查这个用户是否在在线玩家快照中
			for _, activePlayer in pairs(activePlayersSnapshot) do
				if activePlayer.UserId == userId then
					isAlreadySaved = true
					break
				end
			end

			-- 如果不在在线快照中，需要兜底保存
			if not isAlreadySaved then
				task.spawn(function()
					local success = DataManager.SaveCachedPlayerData(userId)
					if success then
						savedCount = savedCount + 1
						print(string.format(
							"%s [MainServer] ✅ 缓存玩家 UserId_%d 数据已保存",
							GameConfig.LOG_PREFIX,
							userId
						))
					else
						errorCount = errorCount + 1
						warn(string.format(
							"%s [MainServer] ❌ 缓存玩家 UserId_%d 数据保存失败",
							GameConfig.LOG_PREFIX,
							userId
						))
					end
				end)
			end
		else
			warn(string.format("%s [MainServer] ⚠️ 无效的UserId: %s", GameConfig.LOG_PREFIX, tostring(userIdRaw)))
		end
	end

	-- 第四步：等待所有保存操作完成
	local maxWaitTime = 15  -- 最多等待15秒
	local waitSuccess = DataManager.WaitForAllSavesToComplete(maxWaitTime)

	local endTime = tick()
	local duration = endTime - startTime

	if waitSuccess then
		print(string.format(
			"%s [MainServer] 🔥数据保存完成：成功 %d 个，失败 %d 个，耗时 %.2f 秒",
			GameConfig.LOG_PREFIX,
			savedCount,
			errorCount,
			duration
		))
	else
		local pendingCount = DataManager.GetPendingSaveCount()
		warn(string.format(
			"%s [MainServer] ⚠️ 保存超时：成功 %d 个，失败 %d 个，仍有 %d 个待保存，耗时 %.2f 秒",
			GameConfig.LOG_PREFIX,
			savedCount,
			errorCount,
			pendingCount,
			duration
		))
	end

	print(GameConfig.LOG_PREFIX .. " [MainServer] 🔥服务器关闭流程完成")
end)

