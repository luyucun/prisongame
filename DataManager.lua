--[[
脚本名称: DataManager
脚本类型: ModuleScript (服务端核心)
脚本位置: ServerScriptService/Core/DataManager
]]

--[[
数据管理器模块
职责:
1. 管理所有玩家的游戏数据
2. 提供数据的加载、获取、修改接口
3. 为后续数据持久化(DataStore)预留接口
]]

local DataManager = {}

-- 引用配置模块
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")  -- V2.1：添加DataStore服务
local RunService = game:GetService("RunService")  -- Studio检测服务
local HttpService = game:GetService("HttpService")  -- V3.9：用于生成InstanceId
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local StageConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StageConfig"))  -- V3.7.1：章节配置
local HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))

-- DataStore实例（V2.1库存系统：添加真正的持久化）
-- Studio与线上数据隔离：根据环境和配置决定DataStore名称
local isStudio = RunService:IsStudio()
local suffix = (isStudio and GameConfig.USE_STUDIO_DATASTORE_SUFFIX) and "_Studio" or ""
local DATASTORE_NAME = "PlayerData_V2.1" .. suffix
local PlayerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

-- 打印当前使用的DataStore名称（便于确认环境）
if GameConfig.DEBUG_MODE then
	print(string.format("[DataManager] 🗄️ 使用DataStore: %s (isStudio=%s, suffix=%s)",
		DATASTORE_NAME, tostring(isStudio), suffix))
end

-- 存储所有玩家的数据 [UserId] = PlayerData
-- 注意: Roblox脚本是单线程执行,因此不存在真正的race condition问题
-- 多个玩家的事件通过Roblox的事件队列顺序处理,不会出现并发访问
local playerDataCache = {}

-- 🔥修复服务器关闭时数据保存：保存状态跟踪
local pendingSaves = {}  -- [UserId] = in-flight save count
local isShuttingDown = false  -- 服务器是否正在关闭
local LOAD_RETRY_ATTEMPTS = isStudio and 1 or 3
local LOAD_RETRY_DELAY_SECONDS = 0.5

local function AddPendingSave(userId)
    if not userId then
        return
    end
    pendingSaves[userId] = (pendingSaves[userId] or 0) + 1
end

local function RemovePendingSave(userId)
    if not userId then
        return
    end
    local current = pendingSaves[userId]
    if not current then
        return
    end
    if current <= 1 then
        pendingSaves[userId] = nil
    else
        pendingSaves[userId] = current - 1
    end
end

--[[
玩家数据结构:
PlayerData = {
    UserId = number,           -- 玩家ID
    Player = Player,           -- 玩家对象引用
    HomeSlot = number,         -- 分配的基地编号(1-6)
    Currency = {
        Coins = number,        -- 金币数量
    },
    Units = {},                -- 拥有的兵种数据(后续版本)
    PlacedUnits = {            -- 🔥修复持久化：已放置兵种数据
        [instanceId] = {
            UnitId = string,       -- 兵种ID
            Level = number,        -- 等级
            GridX = number,        -- 网格X坐标
            GridZ = number,        -- 网格Z坐标
            GridSize = number,     -- 占地大小(向后兼容)
            GridWidth = number,    -- 占地宽度(格数)
            GridDepth = number,    -- 占地深度(格数)
            IsActivated = boolean, -- 是否已激活(用于战役系统)
            Health = number,       -- 当前生命值
            MaxHealth = number,    -- 最大生命值
        }
    },
    ShopData = {               -- V2.1库存系统：商店数据持久化
        [shopId] = {
            LastRefreshTime = number,  -- 上次刷新时间戳
        }
    },
    IdleCoinData = {           -- V2.6挂机金币系统
        LastLogoutTime = number,       -- 上次登出时间戳
        PendingCoins = number,         -- 待领取的挂机金币
        GuideEligibleOnLogin = boolean,-- 是否允许本次登录触发挂机金币引导
    },
    SoundSettings = {          -- V4.6设置系统：音效开关
        MusicEnabled = boolean,        -- BGM是否开启
        SfxEnabled = boolean,          -- SFX是否开启
    },
    PowerRankData = {          -- V4.7排行榜：战斗力达成时间
        Power = number,        -- 当前战斗力
        Time = number,         -- 达成时间戳
    },
    ChapterProgress = {        -- V2.8章节进度系统
        CurrentChapter = number,   -- 当前挑战章节(从1开始)
        CompletedChapters = number, -- 已通关的章节数(0表示未通关任何章节)
        CurrentHouseModel = string, -- 当前房屋模型名称
    },
    SkillInventory = {         -- V3.0技能系统
        [skillId] = count,     -- 技能ID: 数量
    },
    TaskData = {               -- V3.3任务系统
        CurrentTaskId = number,    -- 当前任务ID
        CurrentProgress = number,  -- 当前任务进度
        CompletedTaskIds = {},     -- 已完成的任务ID列表
        AllTasksCompleted = boolean, -- 是否全部任务完成
    },
    GuideData = {              -- V3.5新手引导系统
        CompletedGuides = {},  -- 已完成的引导 {[guideId] = true}
    },
    SevenDayData = {           -- V4.8七日登录奖励
        Round = number,        -- 当前轮次
        ClaimedDays = {},      -- 已领取天数 {[day] = true}
        UnlockedDays = number, -- 当前已解锁的最高天数
        LastClaimTime = number,-- 上次领取时间戳
        LastUnlockDay = number,-- 上次解锁检查的UTC天数索引
        PendingReset = boolean,-- 是否待重置新一轮
    },
    DailyRewardData = {        -- V5.3每日免费奖励
        LastClaimDay = number, -- 上次领取UTC日索引
        LastClaimTime = number,-- 上次领取时间戳
    },
    GroupRewardData = {        -- V4.9加入群组奖励
        Claimed = boolean,     -- 是否已领取群组奖励
    },
    LastSaveTime = number,     -- 最后保存时间
}
]]

-- ==================== 私有函数 ====================

--[[
把值清洗为DataStore可接受的类型（number/boolean/string/table）
@param v any - 要清洗的值
@return any - 清洗后的值
]]
local function SanitizeForDataStore(v)
    local t = typeof(v)
    if t == "Vector3" then
        return {__type="Vector3", x=v.X, y=v.Y, z=v.Z}
    elseif t == "CFrame" then
        local cf = {v:GetComponents()}
        return {__type="CFrame", components=cf}
    elseif t == "Color3" then
        return {__type="Color3", r=v.R, g=v.G, b=v.B}
    elseif t == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[k] = SanitizeForDataStore(val)
        end
        return out
    elseif t == "Instance" then
        return nil -- 丢弃Instance，不能序列化
    else
        return v  -- number/boolean/string/nil直接返回
    end
end

--[[
清洗Units数组，处理其中的Vector3等不可序列化类型
@param units table|nil - 兵种数组
@return table - 清洗后的兵种数组
]]
local function CleanUnits(units)
    if type(units) ~= "table" then
        return {}
    end

    local out = {}
    for i, unitInstance in ipairs(units) do
        local cleaned = SanitizeForDataStore(unitInstance)
        if cleaned then  -- 过滤掉nil值
            table.insert(out, cleaned)
        end
    end
    return out
end

--[[
还原Vector3等类型（加载时使用）
@param data any - 要还原的数据
@return any - 还原后的数据
]]
local function RestoreFromDataStore(data)
    if type(data) == "table" then
        if data.__type == "Vector3" then
            return Vector3.new(data.x, data.y, data.z)
        elseif data.__type == "CFrame" then
            return CFrame.new(unpack(data.components))
        elseif data.__type == "Color3" then
            return Color3.new(data.r, data.g, data.b)
        else
            -- 普通table，递归处理
            local out = {}
            for k, v in pairs(data) do
                out[k] = RestoreFromDataStore(v)
            end
            return out
        end
    else
        return data
    end
end

--[[
从DataStore加载玩家数据（V2.1库存系统：实现真正的持久化）
@param player Player - 玩家对象
@return table|nil - 加载的数据，失败返回nil
@return string - ok | missing | error
]]
local function LoadFromDataStore(player)
	if not player then
		return nil, "error"
	end

	local lastError = nil
	for attempt = 1, LOAD_RETRY_ATTEMPTS do
		local success, data = pcall(function()
			return PlayerDataStore:GetAsync("Player_" .. player.UserId)
		end)

		if success then
			if not data then
				return nil, "missing"
			end

			-- 还原Vector3等类型（如果需要）
			if data.Units then
				data.Units = RestoreFromDataStore(data.Units)
			end
			if data.Currency then
				data.Currency = RestoreFromDataStore(data.Currency)
			end
			if data.PlacedUnits then
				data.PlacedUnits = RestoreFromDataStore(data.PlacedUnits)  -- ??修复持久化：恢复放置数据
			end
			if data.ShopData then
				data.ShopData = RestoreFromDataStore(data.ShopData)
			end
			if data.IdleCoinData then
				data.IdleCoinData = RestoreFromDataStore(data.IdleCoinData)  -- V2.6：恢复挂机金币数据
			end
			if data.ChapterProgress then
				data.ChapterProgress = RestoreFromDataStore(data.ChapterProgress)  -- V2.8：恢复章节进度数据
			end
			if data.SkillInventory then
				data.SkillInventory = RestoreFromDataStore(data.SkillInventory)  -- V3.0：恢复技能背包数据
			end
			if data.TaskData then
				data.TaskData = RestoreFromDataStore(data.TaskData)  -- V3.3：恢复任务数据
			end
			if data.GuideData then
				data.GuideData = RestoreFromDataStore(data.GuideData)  -- V3.5：恢复引导数据
			end
			if data.TalkData then
				data.TalkData = RestoreFromDataStore(data.TalkData)  -- V4.5对话数据
			end
			if data.SevenDayData then
				data.SevenDayData = RestoreFromDataStore(data.SevenDayData)  -- V4.8七日登录奖励
			end
			if data.DailyRewardData then
				data.DailyRewardData = RestoreFromDataStore(data.DailyRewardData)  -- V5.3每日免费奖励
			end
			if data.GroupRewardData then
				data.GroupRewardData = RestoreFromDataStore(data.GroupRewardData)  -- V4.9加入群组奖励
			end
			if data.SoundSettings then
				data.SoundSettings = RestoreFromDataStore(data.SoundSettings)  -- V4.6：恢复音效设置
			end
			if data.PowerRankData then
				data.PowerRankData = RestoreFromDataStore(data.PowerRankData)  -- V4.7：恢复排行榜数据
			end

			return data, "ok"
		end

		lastError = data
		if attempt < LOAD_RETRY_ATTEMPTS then
			task.wait(LOAD_RETRY_DELAY_SECONDS * attempt)
		end
	end

	if isStudio then
		warn(string.format(
			"[DataManager] Studio DataStore load failed (API Access?) - player:%s error:%s",
			player.Name,
			tostring(lastError)
		))
		return nil, "missing"
	end

	warn(string.format(
		"%s [DataManager] DataStore load failed after %d attempts - player:%s error:%s",
		GameConfig.LOG_PREFIX,
		LOAD_RETRY_ATTEMPTS,
		player.Name,
		tostring(lastError)
	))
	return nil, "error"
end

--[[
保存玩家数据到DataStore（V2.1库存系统：实现真正的持久化）
@param player Player - 玩家对象
@param playerData table - 玩家数据
@return boolean - 是否保存成功
]]
local function SaveToDataStore(player, playerData, userId)
	-- 🔥修复服务器关闭时数据保存：支持直接传入userId
	local targetUserId = userId or (player and player.UserId) or playerData.UserId
	local playerName = (player and player.Name) or ("UserId_" .. targetUserId)

	-- 构造要保存的数据（去除Player引用等不可序列化字段）
	local dataToSave = {
		UserId = playerData.UserId,
		HomeSlot = playerData.HomeSlot,
		IsNewPlayer = playerData.IsNewPlayer,
		Currency = SanitizeForDataStore(playerData.Currency),
		Units = CleanUnits(playerData.Units),  -- 关键：清洗Units中的Vector3等类型
		PlacedUnits = SanitizeForDataStore(playerData.PlacedUnits),  -- 🔥修复持久化：保存放置数据
		ShopData = SanitizeForDataStore(playerData.ShopData),  -- V2.1库存系统：保存商店数据
		IdleCoinData = SanitizeForDataStore(playerData.IdleCoinData),  -- V2.6：保存挂机金币数据
		SoundSettings = SanitizeForDataStore(playerData.SoundSettings),  -- V4.6：保存音效设置
		PowerRankData = SanitizeForDataStore(playerData.PowerRankData),  -- V4.7：保存排行榜数据
		ChapterProgress = SanitizeForDataStore(playerData.ChapterProgress),  -- V2.8：保存章节进度数据
		SkillInventory = SanitizeForDataStore(playerData.SkillInventory),  -- V3.0：保存技能背包
		TaskData = SanitizeForDataStore(playerData.TaskData),  -- V3.3：保存任务数据
		GuideData = SanitizeForDataStore(playerData.GuideData),  -- V3.5：保存引导数据
		TalkData = SanitizeForDataStore(playerData.TalkData),  -- V4.5对话数据
		SevenDayData = SanitizeForDataStore(playerData.SevenDayData),  -- V4.8七日登录奖励
		DailyRewardData = SanitizeForDataStore(playerData.DailyRewardData),  -- V5.3每日免费奖励
		GroupRewardData = SanitizeForDataStore(playerData.GroupRewardData),  -- V4.9加入群组奖励
		LastSaveTime = os.time(),
	}

	local success, errorMsg = pcall(function()
		-- 🔥V2.6.1优化：使用UpdateAsync替代SetAsync，提升保存性能
		-- UpdateAsync只在数据真正改变时才写入，避免不必要的DataStore请求
		PlayerDataStore:UpdateAsync("Player_" .. targetUserId, function(oldData)
			-- 返回新数据，Roblox会自动处理版本控制和冲突
			return dataToSave
		end)
	end)

	if success then
		return true
	else
		-- Studio环境下给出更友好的提示
		if isStudio then
			warn(string.format(
				"[DataManager] ⚠️ Studio DataStore保存失败（可能未开启API Access）- 玩家:%s 错误:%s",
				playerName,
				tostring(errorMsg)
			))
		else
			warn(string.format(
				"%s [DataManager] DataStore保存失败 - 玩家:%s 错误:%s",
				GameConfig.LOG_PREFIX,
				playerName,
				tostring(errorMsg)
			))
		end
		return false
	end
end

local function GetUtcDayIndex(timestamp)
    local ts = tonumber(timestamp) or os.time()
    return math.floor(ts / 86400)
end

local function BuildDefaultSevenDayData(now)
    local utcDay = GetUtcDayIndex(now)
    return {
        Round = 1,
        ClaimedDays = {},
        UnlockedDays = 1,
        LastClaimTime = 0,
        LastUnlockDay = utcDay,
        PendingReset = false,
    }
end

local function NormalizeSevenDayData(data)
    if type(data) ~= "table" then
        return BuildDefaultSevenDayData(os.time())
    end

    data.Round = tonumber(data.Round) or 1
    if type(data.ClaimedDays) ~= "table" then
        data.ClaimedDays = {}
    end

    local unlocked = tonumber(data.UnlockedDays)
    if unlocked == nil then
        unlocked = 1
    end
    if unlocked < 0 then
        unlocked = 0
    elseif unlocked > 7 then
        unlocked = 7
    end
    data.UnlockedDays = unlocked

    data.LastClaimTime = tonumber(data.LastClaimTime) or 0
    data.LastUnlockDay = tonumber(data.LastUnlockDay) or GetUtcDayIndex(os.time())
    data.PendingReset = data.PendingReset == true

    local claimedCount = 0
    for day, claimed in pairs(data.ClaimedDays) do
        if tonumber(day) and claimed == true then
            claimedCount = claimedCount + 1
        end
    end
    if data.UnlockedDays < claimedCount then
        data.UnlockedDays = claimedCount
    end

    return data
end

local function BuildDefaultDailyRewardData(now)
    return {
        LastClaimDay = 0,
        LastClaimTime = 0,
    }
end

local function NormalizeDailyRewardData(data)
    if type(data) ~= "table" then
        return BuildDefaultDailyRewardData(os.time())
    end

    data.LastClaimDay = tonumber(data.LastClaimDay) or 0
    data.LastClaimTime = tonumber(data.LastClaimTime) or 0

    if data.LastClaimDay < 0 then
        data.LastClaimDay = 0
    end
    if data.LastClaimTime < 0 then
        data.LastClaimTime = 0
    end

    return data
end

local function BuildDefaultGroupRewardData()
    return {
        Claimed = false,
    }
end

local function NormalizeGroupRewardData(data)
    if type(data) ~= "table" then
        return BuildDefaultGroupRewardData()
    end

    data.Claimed = data.Claimed == true
    return data
end

--[[
创建默认玩家数据
@param player Player - 玩家对象
@return table - 初始化的玩家数据
]]
local function CreateDefaultData(player)

    return {
        UserId = player.UserId,
        Player = player,
        IsNewPlayer = true,  -- 新玩家标记（首次进店流程使用）
        HomeSlot = 0,  -- 初始为0,由PlayerManager分配
        Currency = {
            Coins = GameConfig.INITIAL_COINS,  -- 初始金币100
        },
        Units = {},  -- 后续版本使用
        PlacedUnits = {},  -- 🔥修复持久化：初始化空的放置数据
        ShopData = {},  -- V2.1库存系统：初始化空商店数据
        IdleCoinData = {  -- V2.6挂机金币系统：初始化
            LastLogoutTime = 0,
            PendingCoins = 0,
            GuideEligibleOnLogin = false,
        },
        SoundSettings = {  -- V4.6设置系统：初始化
            MusicEnabled = true,
            SfxEnabled = true,
        },
        PowerRankData = {  -- V4.7排行榜：初始化
            Power = 0,
            Time = 0,
        },
        ChapterProgress = {  -- V2.8章节进度系统：初始化
            CurrentChapter = 1,       -- 默认从第1章开始
            CompletedChapters = 0,    -- 未通关任何章节
            CurrentHouseModel = "PrisonLv1",  -- 默认初始房屋
            -- 主线最大通关进度（只增不减）：用于“最多打到哪关”统计与展示
            MaxClearedChapter = 1,
            MaxClearedStage = 0,
        },
        SkillInventory = {},  -- V3.0技能系统：初始化空技能背包
        TaskData = {  -- V3.3任务系统：初始化
            CurrentTaskId = 1001,     -- 默认从第一个任务开始（需要与TaskConfig.GetFirstTaskId()同步）
            CurrentProgress = 0,
            CompletedTaskIds = {},
            AllTasksCompleted = false,
        },
        GuideData = {  -- V3.5新手引导系统：初始化
            CompletedGuides = {},
        },
        TalkData = {  -- V4.5对话系统：初始化
            CompletedTalks = {},
        },
        SevenDayData = BuildDefaultSevenDayData(os.time()), -- V4.8七日登录奖励
        DailyRewardData = BuildDefaultDailyRewardData(os.time()), -- V5.3每日免费奖励
        GroupRewardData = BuildDefaultGroupRewardData(), -- V4.9加入群组奖励
        LastSaveTime = os.time(),
    }
end

-- ==================== V5.3每日免费奖励接口 ====================

function DataManager.GetDailyRewardData(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    if not playerData.DailyRewardData then
        playerData.DailyRewardData = BuildDefaultDailyRewardData(os.time())
    else
        playerData.DailyRewardData = NormalizeDailyRewardData(playerData.DailyRewardData)
    end

    return playerData.DailyRewardData
end

function DataManager.SetDailyRewardClaim(player, claimDay, claimTime)
    local rewardData = DataManager.GetDailyRewardData(player)
    if not rewardData then
        warn(GameConfig.LOG_PREFIX, "SetDailyRewardClaim: 找不到玩家数据")
        return false
    end

    rewardData.LastClaimDay = tonumber(claimDay) or rewardData.LastClaimDay or 0
    rewardData.LastClaimTime = tonumber(claimTime) or rewardData.LastClaimTime or 0
    return true
end

function DataManager.ResetDailyReward(player)
    local rewardData = DataManager.GetDailyRewardData(player)
    if not rewardData then
        warn(GameConfig.LOG_PREFIX, "ResetDailyReward: 找不到玩家数据")
        return false
    end

    rewardData.LastClaimDay = 0
    rewardData.LastClaimTime = 0
    return true
end

-- ==================== V4.9群组奖励接口 ====================

function DataManager.GetGroupRewardData(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    if not playerData.GroupRewardData then
        playerData.GroupRewardData = BuildDefaultGroupRewardData()
    else
        playerData.GroupRewardData = NormalizeGroupRewardData(playerData.GroupRewardData)
    end

    return playerData.GroupRewardData
end

function DataManager.SetGroupRewardClaimed(player, claimed)
    local rewardData = DataManager.GetGroupRewardData(player)
    if not rewardData then
        warn(GameConfig.LOG_PREFIX, "SetGroupRewardClaimed: 找不到玩家数据")
        return false
    end

    rewardData.Claimed = claimed == true
    return true
end

-- ==================== 主线进度工具（最大通关关卡） ====================

local function GetStagesPerChapterSafe(chapterId: number): number
    local defaultStages = (GameConfig.Campaign and GameConfig.Campaign.MaxStages) or 10

    local ok, chapterConfig = pcall(function()
        return StageConfig.GetChapterConfig and StageConfig.GetChapterConfig(chapterId)
    end)

    -- If chapter exists, prefer StageConfig's unified stage-count accessor (V3.10+ reads from EnemyConfig).
    if ok and chapterConfig and StageConfig.GetStagesPerChapter then
        local ok2, stages = pcall(function()
            return StageConfig.GetStagesPerChapter(chapterId)
        end)
        local stagesNum = tonumber(stages)
        if ok2 and stagesNum and stagesNum > 0 then
            return stagesNum
        end
    end

    return defaultStages
end

local function EnsureChapterProgress(playerData)
    if not playerData.ChapterProgress then
        playerData.ChapterProgress = {
            CurrentChapter = 1,
            CompletedChapters = 0,
            CurrentHouseModel = "PrisonLv1",
            MaxClearedChapter = 1,
            MaxClearedStage = 0,
        }
        return playerData.ChapterProgress
    end

    local progress = playerData.ChapterProgress

    if progress.CurrentChapter == nil then
        progress.CurrentChapter = 1
    end
    if progress.CompletedChapters == nil then
        progress.CompletedChapters = 0
    end
    if progress.CurrentHouseModel == nil then
        progress.CurrentHouseModel = "PrisonLv1"
    end

    local maxChapter = tonumber(progress.MaxClearedChapter)
    local maxStage = tonumber(progress.MaxClearedStage)

    -- 向后兼容：旧存档没有 MaxCleared* 字段时，用 CompletedChapters 推导最低保底值
    if maxChapter == nil and maxStage == nil then
        local completed = tonumber(progress.CompletedChapters) or 0
        if completed > 0 then
            progress.MaxClearedChapter = completed
            progress.MaxClearedStage = GetStagesPerChapterSafe(completed)
        else
            progress.MaxClearedChapter = 1
            progress.MaxClearedStage = 0
        end
        return progress
    end

    if maxChapter == nil then
        maxChapter = 1
    end
    if maxStage == nil then
        maxStage = 0
    end

    if maxChapter < 1 then
        maxChapter = 1
    end
    if maxStage < 0 then
        maxStage = 0
    end

    progress.MaxClearedChapter = maxChapter
    progress.MaxClearedStage = maxStage

    return progress
end

-- ==================== 公共接口 ====================

--[[
初始化玩家数据（V2.1库存系统：从DataStore加载）
@param player Player - 玩家对象
@return table - 玩家数据
]]
function DataManager.InitializePlayerData(player)
    if not player then
        warn(GameConfig.LOG_PREFIX, "InitializePlayerData: player为空")
        return nil
    end

    -- 检查是否已存在数据
    if playerDataCache[player.UserId] then
        playerDataCache[player.UserId].Player = player
        return playerDataCache[player.UserId]
    end

    -- V2.1库存系统：尝试从DataStore加载数据
    local loadedData, loadStatus = LoadFromDataStore(player)
    local playerData

    if loadStatus == "error" then
        warn(GameConfig.LOG_PREFIX, "InitializePlayerData: DataStore load failed -", player.Name)
        return nil
    end

    if loadedData then
        -- 使用加载的数据，但重新设置Player引用
        playerData = loadedData
        playerData.Player = player
        if playerData.IsNewPlayer == nil then
            playerData.IsNewPlayer = false  -- 已有存档默认不是新玩家
        end

        -- 🔥重要：清除旧的HomeSlot，让PlayerManager重新分配
        -- HomeSlot是运行时动态分配的，不应该从存档恢复
        playerData.HomeSlot = nil

        -- 确保ShopData字段存在（向后兼容）
        if not playerData.ShopData then
            playerData.ShopData = {}
        end

        -- 🔥修复库存售罄：向后兼容 - 为所有已有商店数据添加Stock字段
        for shopId, shopData in pairs(playerData.ShopData) do
            if not shopData.Stock then
                shopData.Stock = {}
            end
        end

        -- 🔥修复持久化：确保PlacedUnits字段存在（向后兼容）
        if not playerData.PlacedUnits then
            playerData.PlacedUnits = {}
        end

        -- V2.6挂机金币：确保IdleCoinData字段存在（向后兼容）
        if not playerData.IdleCoinData then
            playerData.IdleCoinData = {
                LastLogoutTime = 0,
                PendingCoins = 0,
                GuideEligibleOnLogin = false,
            }
        end

        -- V2.8章节进度：确保ChapterProgress字段存在（向后兼容）
        EnsureChapterProgress(playerData)

        -- V3.0技能系统：确保SkillInventory字段存在（向后兼容）
        if not playerData.SkillInventory then
            playerData.SkillInventory = {}
        end

        -- V3.3任务系统：确保TaskData字段存在（向后兼容）
        if not playerData.TaskData then
            playerData.TaskData = {
                CurrentTaskId = 1001,  -- 默认从第一个任务开始
                CurrentProgress = 0,
                CompletedTaskIds = {},
                AllTasksCompleted = false,
            }
        end

        -- V3.5新手引导系统：确保GuideData字段存在（向后兼容）
        if not playerData.GuideData then
            playerData.GuideData = {
                CompletedGuides = {},
            }
        end

        -- V4.5对话系统：确保TalkData字段存在（向后兼容）
        if not playerData.TalkData then
            playerData.TalkData = {
                CompletedTalks = {},
            }
        end

        -- V4.8七日登录奖励：确保SevenDayData字段存在（向后兼容）
        if not playerData.SevenDayData then
            playerData.SevenDayData = BuildDefaultSevenDayData(os.time())
        else
            playerData.SevenDayData = NormalizeSevenDayData(playerData.SevenDayData)
        end

        -- V5.3每日免费奖励：确保DailyRewardData字段存在（向后兼容）
        if not playerData.DailyRewardData then
            playerData.DailyRewardData = BuildDefaultDailyRewardData(os.time())
        else
            playerData.DailyRewardData = NormalizeDailyRewardData(playerData.DailyRewardData)
        end

        -- V4.9加入群组奖励：确保GroupRewardData字段存在（向后兼容）
        if not playerData.GroupRewardData then
            playerData.GroupRewardData = BuildDefaultGroupRewardData()
        else
            playerData.GroupRewardData = NormalizeGroupRewardData(playerData.GroupRewardData)
        end

        -- V4.6设置系统：确保SoundSettings字段存在（向后兼容）
        if not playerData.SoundSettings then
            playerData.SoundSettings = {
                MusicEnabled = true,
                SfxEnabled = true,
            }
        else
            if playerData.SoundSettings.MusicEnabled == nil then
                playerData.SoundSettings.MusicEnabled = true
            end
            if playerData.SoundSettings.SfxEnabled == nil then
                playerData.SoundSettings.SfxEnabled = true
            end
        end

        -- V4.7排行榜：确保PowerRankData字段存在（向后兼容）
        if not playerData.PowerRankData then
            playerData.PowerRankData = {
                Power = 0,
                Time = 0,
            }
        else
            if playerData.PowerRankData.Power == nil then
                playerData.PowerRankData.Power = 0
            end
            if playerData.PowerRankData.Time == nil then
                playerData.PowerRankData.Time = 0
            end
        end

        -- 🔥V3.9数据迁移：Inventory→Units（向后兼容）
        -- 如果Units为空但Inventory有数据，则迁移到Units数组
        if (not playerData.Units or #playerData.Units == 0) and playerData.Inventory then
            local hasInventoryData = false
            for unitId, count in pairs(playerData.Inventory) do
                if count and count > 0 then
                    hasInventoryData = true
                    break
                end
            end

            if hasInventoryData then
                print(string.format("[DataManager] 检测到旧存档，开始迁移 Inventory→Units (玩家: %s)", player.Name))
                playerData.Units = playerData.Units or {}

                -- 将Inventory中的每个兵种转换为Units数组元素
                for unitId, count in pairs(playerData.Inventory) do
                    if count and count > 0 then
                        for i = 1, count do
                            table.insert(playerData.Units, {
                                UnitId = tostring(unitId),  -- 🔥修复：保持字符串类型，与UnitConfig一致
                                InstanceId = HttpService:GenerateGUID(false),
                                Level = 1,  -- 默认等级1
                            })
                        end
                    end
                end

                print(string.format("[DataManager] 迁移完成：%d 个兵种已转换为 Units 数组", #playerData.Units))

                -- 清空旧的Inventory（避免重复迁移）
                playerData.Inventory = {}

                -- 立即保存迁移后的数据
                DataManager.SavePlayerDataThrottled(player)  -- 🔥修复：添加DataManager前缀
            end
        end

        -- 确保Units字段存在（向后兼容）
        if not playerData.Units then
            playerData.Units = {}
        end

    else
        -- 创建新数据
        playerData = CreateDefaultData(player)

    end

    playerDataCache[player.UserId] = playerData

    return playerData
end

--[[
等待玩家数据加载完成（修复竞态条件）
@param player Player - 玩家对象
@param timeout number - 超时时间（秒），默认10秒
@return table|nil - 玩家数据，超时返回nil
]]
function DataManager.WaitForPlayerData(player, timeout)
    if not player then
        warn(GameConfig.LOG_PREFIX, "WaitForPlayerData: player为空")
        return nil
    end

    timeout = timeout or 10  -- 默认10秒超时
    local startTime = tick()

    -- 如果数据已存在，直接返回
    if playerDataCache[player.UserId] then
        return playerDataCache[player.UserId]
    end

    -- 等待数据加载完成
    while tick() - startTime < timeout do
        if playerDataCache[player.UserId] then
            return playerDataCache[player.UserId]
        end
        task.wait(0.1)  -- 每100ms检查一次
    end

    -- 超时
    warn(GameConfig.LOG_PREFIX, "WaitForPlayerData: 等待玩家数据超时 -", player.Name)
    return nil
end

--[[
获取玩家数据
@param player Player - 玩家对象
@return table|nil - 玩家数据,如果不存在则返回nil
]]
function DataManager.GetPlayerData(player)
    if not player then
        warn(GameConfig.LOG_PREFIX, "GetPlayerData: player为空")
        return nil
    end

    return playerDataCache[player.UserId]
end

--[[
设置玩家的基地编号
@param player Player - 玩家对象
@param homeSlot number - 基地编号(1-6)
@return boolean - 是否设置成功
]]
function DataManager.SetPlayerHomeSlot(player, homeSlot)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetPlayerHomeSlot: 找不到玩家数据")
        return false
    end

    -- 验证基地编号有效性
    if homeSlot < GameConfig.MIN_HOME_SLOT or homeSlot > GameConfig.MAX_HOME_SLOT then
        warn(GameConfig.LOG_PREFIX, "SetPlayerHomeSlot: 无效的基地编号", homeSlot)
        return false
    end

    playerData.HomeSlot = homeSlot


    return true
end

--[[
获取玩家的基地编号
@param player Player - 玩家对象
@return number|nil - 基地编号,如果不存在则返回nil
]]
function DataManager.GetPlayerHomeSlot(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    return playerData.HomeSlot
end

--[[
更新玩家货币
@param player Player - 玩家对象
@param currencyType string - 货币类型(例如"Coins")
@param amount number - 变化数量(可以是负数)
@param reason string - 变化原因(用于日志)
@return boolean, number - 是否成功, 更新后的货币数量
]]
function DataManager.UpdateCurrency(player, currencyType, amount, reason)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "UpdateCurrency: 找不到玩家数据")
        return false, 0
    end

    -- 验证货币类型
    if not playerData.Currency[currencyType] then
        warn(GameConfig.LOG_PREFIX, "UpdateCurrency: 无效的货币类型", currencyType)
        return false, 0
    end

    -- 计算新的货币数量
    local oldAmount = playerData.Currency[currencyType]
    local newAmount = oldAmount + amount

    -- 防止货币为负数
    if newAmount < 0 then
        newAmount = 0
    end

    playerData.Currency[currencyType] = newAmount


    return true, newAmount
end

--[[
获取玩家货币数量
@param player Player - 玩家对象
@param currencyType string - 货币类型
@return number|nil - 货币数量
]]
function DataManager.GetCurrency(player, currencyType)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    return playerData.Currency[currencyType]
end

--[[
获取玩家所有货币
@param player Player - 玩家对象
@return table|nil - 货币数据表
]]
function DataManager.GetAllCurrency(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    return playerData.Currency
end

--[[
V2.1库存系统：获取玩家商店数据
@param player Player - 玩家对象
@param shopId string - 商店ID
@return table|nil - 商店数据 {LastRefreshTime = number, Stock = {[unitId] = number}}
]]
function DataManager.GetShopData(player, shopId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return nil
    end

    if not playerData.ShopData[shopId] then
        playerData.ShopData[shopId] = {
            LastRefreshTime = 0,  -- 默认为0表示首次进入
            Stock = {}           -- 🔥修复库存售罄：添加Stock字段存储库存数据
        }
    end

    return playerData.ShopData[shopId]
end

--[[
V2.1库存系统：设置玩家商店刷新时间
@param player Player - 玩家对象
@param shopId string - 商店ID
@param refreshTime number - 刷新时间戳
@return boolean - 是否设置成功
]]
function DataManager.SetShopRefreshTime(player, shopId, refreshTime)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetShopRefreshTime: 找不到玩家数据")
        return false
    end

    if not playerData.ShopData[shopId] then
        playerData.ShopData[shopId] = {
            Stock = {}  -- 🔥修复库存售罄：确保Stock字段存在
        }
    end

    playerData.ShopData[shopId].LastRefreshTime = refreshTime


    return true
end

--[[
🔥修复库存售罄：保存玩家商店库存数据
@param player Player - 玩家对象
@param shopId string - 商店ID
@param stockData table - 库存数据 {[unitId] = stock}
@return boolean - 是否设置成功
]]
function DataManager.SetShopStock(player, shopId, stockData)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetShopStock: 找不到玩家数据")
        return false
    end

    if not playerData.ShopData[shopId] then
        playerData.ShopData[shopId] = {
            LastRefreshTime = 0
        }
    end

    -- 保存库存数据（清洗掉LastRefreshTime等非库存字段）
    local cleanedStock = {}
    for unitId, stock in pairs(stockData) do
        if unitId ~= "LastRefreshTime" and type(stock) == "number" then
            cleanedStock[unitId] = stock
        end
    end

    playerData.ShopData[shopId].Stock = cleanedStock

    return true
end

--[[
🔥修复库存售罄：获取玩家商店库存数据
@param player Player - 玩家对象
@param shopId string - 商店ID
@return table - 库存数据 {[unitId] = stock}
]]
function DataManager.GetShopStock(player, shopId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {}
    end

    if not playerData.ShopData[shopId] then
        return {}
    end

    return playerData.ShopData[shopId].Stock or {}
end

--[[
保存玩家数据（V2.1库存系统：保存到DataStore）
@param player Player - 玩家对象
@param waitForDataSeconds number - optional wait before saving when data is missing
@return boolean - 是否保存成功
]]
function DataManager.SavePlayerData(player, waitForDataSeconds)
    local userId = player and player.UserId
    AddPendingSave(userId)

    local playerData = DataManager.GetPlayerData(player)
    if not playerData and waitForDataSeconds and waitForDataSeconds > 0 then
        playerData = DataManager.WaitForPlayerData(player, waitForDataSeconds)
    end
    if not playerData then
        RemovePendingSave(userId)
        warn(GameConfig.LOG_PREFIX, "SavePlayerData: 找不到玩家数据")
        return false
    end

    -- 🔥修复持久化：只在保存成功后才更新LastSaveTime，避免保存失败后节流机制阻止重试
    local saveSuccess = SaveToDataStore(player, playerData)
    if saveSuccess then
        playerData.LastSaveTime = os.time()
    end

    -- 🔥修复服务器关闭时数据保存：标记保存完成
    RemovePendingSave(userId)

    return saveSuccess
end

--[[
清除玩家数据(玩家离开时调用)
@param player Player - 玩家对象
]]
function DataManager.ClearPlayerData(player)
    if not player then
        return
    end

    -- 保存数据
    local saveSuccess = DataManager.SavePlayerData(player, 3)
    if saveSuccess then
        -- 从缓存中移除
        playerDataCache[player.UserId] = nil
        return
    end

    local userId = player.UserId
    local originalPlayer = player
    if not playerDataCache[userId] then
        warn(GameConfig.LOG_PREFIX, "ClearPlayerData: cache missing, skip cleanup -", player.Name)
        return
    end

    warn(GameConfig.LOG_PREFIX, "ClearPlayerData: save failed, keep cache and retry -", player.Name)
    task.spawn(function()
        local retryDelay = 2
        local maxAttempts = 3
        for attempt = 1, maxAttempts do
            task.wait(retryDelay)
            if not playerDataCache[userId] or playerDataCache[userId].Player ~= originalPlayer then
                return
            end
            local success = DataManager.SaveCachedPlayerData(userId)
            if success then
                if playerDataCache[userId] and playerDataCache[userId].Player == originalPlayer then
                    playerDataCache[userId] = nil
                end
                return
            end
            retryDelay = retryDelay * 2
        end
    end)
end

-- ==================== 🔥修复持久化：放置单位数据管理 ====================

--[[
保存放置单位数据
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@param placedData table - 放置数据 {UnitId, Level, GridX, GridZ, GridSize, IsActivated, Health, MaxHealth}
@return boolean - 是否保存成功
]]
function DataManager.SavePlacedUnit(player, instanceId, placedData)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SavePlacedUnit: 找不到玩家数据")
        return false
    end

    -- 确保PlacedUnits字段存在
    if not playerData.PlacedUnits then
        playerData.PlacedUnits = {}
    end

    -- 保存放置数据（只保存可序列化的数据，不包含Model引用）
    playerData.PlacedUnits[instanceId] = {
        UnitId = placedData.UnitId,
        Level = placedData.Level or 1,
        GridX = placedData.GridX,
        GridZ = placedData.GridZ,
        GridSize = placedData.GridSize or 1,
        IsActivated = placedData.IsActivated or false,
        Health = placedData.Health,
        MaxHealth = placedData.MaxHealth,
    }

    return true
end

--[[
移除放置单位数据
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@return boolean - 是否移除成功
]]
function DataManager.RemovePlacedUnit(player, instanceId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "RemovePlacedUnit: 找不到玩家数据")
        return false
    end

    if playerData.PlacedUnits and playerData.PlacedUnits[instanceId] then
        playerData.PlacedUnits[instanceId] = nil
        return true
    end

    return false
end

--[[
获取玩家的所有放置单位数据
@param player Player - 玩家对象
@return table - 放置单位数据表 {[instanceId] = placedData}
]]
function DataManager.GetPlacedUnits(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {}
    end

    return playerData.PlacedUnits or {}
end

--[[
获取特定放置单位的数据
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@return table|nil - 放置单位数据，不存在返回nil
]]
function DataManager.GetPlacedUnit(player, instanceId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData or not playerData.PlacedUnits then
        return nil
    end

    return playerData.PlacedUnits[instanceId]
end

--[[
更新放置单位的位置
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@param gridX number - 新的网格X坐标
@param gridZ number - 新的网格Z坐标
@return boolean - 是否更新成功
]]
function DataManager.UpdatePlacedUnitPosition(player, instanceId, gridX, gridZ)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData or not playerData.PlacedUnits or not playerData.PlacedUnits[instanceId] then
        warn(GameConfig.LOG_PREFIX, "UpdatePlacedUnitPosition: 找不到放置单位数据")
        return false
    end

    playerData.PlacedUnits[instanceId].GridX = gridX
    playerData.PlacedUnits[instanceId].GridZ = gridZ
    return true
end

--[[
更新放置单位的生命值
@param player Player - 玩家对象
@param instanceId string - 单位实例ID
@param health number - 当前生命值
@param maxHealth number - 最大生命值（可选）
@return boolean - 是否更新成功
]]
function DataManager.UpdatePlacedUnitHealth(player, instanceId, health, maxHealth)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData or not playerData.PlacedUnits or not playerData.PlacedUnits[instanceId] then
        warn(GameConfig.LOG_PREFIX, "UpdatePlacedUnitHealth: 找不到放置单位数据")
        return false
    end

    playerData.PlacedUnits[instanceId].Health = health
    if maxHealth then
        playerData.PlacedUnits[instanceId].MaxHealth = maxHealth
    end
    return true
end

--[[
节流式保存玩家数据（避免频繁保存）
@param player Player - 玩家对象
@param forceImmediate boolean - 是否强制立即保存（可选，默认false）
@return boolean - 是否保存成功
]]
function DataManager.SavePlayerDataThrottled(player, forceImmediate)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SavePlayerDataThrottled: 找不到玩家数据")
        return false
    end

    local currentTime = os.time()
    local timeSinceLastSave = currentTime - (playerData.LastSaveTime or 0)
    local SAVE_THROTTLE_SECONDS = 30  -- 30秒内避免重复保存
    local RETRY_AFTER_FAILURE_SECONDS = 5  -- 保存失败后5秒允许重试

    -- 判断是否需要保存
    local shouldSave = false

    if forceImmediate then
        shouldSave = true
        -- print(string.format("[DataManager] 🔥 强制立即保存: 玩家 %s", player.Name))
    elseif timeSinceLastSave >= SAVE_THROTTLE_SECONDS then
        shouldSave = true
        -- print(string.format("[DataManager] 🔥 正常节流保存: 玩家 %s (距离上次 %d 秒)", player.Name, timeSinceLastSave))
    elseif playerData.LastSaveFailedTime and (currentTime - playerData.LastSaveFailedTime) >= RETRY_AFTER_FAILURE_SECONDS then
        shouldSave = true
        -- print(string.format("[DataManager] 🔥 保存失败重试: 玩家 %s (距离失败 %d 秒)", player.Name, currentTime - playerData.LastSaveFailedTime))
    end

    if shouldSave then
        local saveSuccess = DataManager.SavePlayerData(player)
        if not saveSuccess then
            -- 记录保存失败的时间，允许较快重试
            playerData.LastSaveFailedTime = currentTime
            warn(string.format(
                "%s [DataManager] 🔥 保存失败，将在 %d 秒后允许重试: 玩家 %s",
                GameConfig.LOG_PREFIX,
                RETRY_AFTER_FAILURE_SECONDS,
                player.Name
            ))
        else
            -- 保存成功，清除失败标记
            playerData.LastSaveFailedTime = nil
        end
        return saveSuccess
    else
        -- 标记需要保存，但暂不执行（节流中）
        return true
    end
end

--[[
🔥修复服务器关闭时数据保存：设置关机状态
]]
function DataManager.SetShuttingDown(value)
    isShuttingDown = value
end

--[[
🔥修复服务器关闭时数据保存：获取关机状态
@return boolean - 是否正在关机
]]
function DataManager.IsShuttingDown()
    return isShuttingDown
end

--[[
🔥修复服务器关闭时数据保存：获取所有玩家数据（从缓存）
@return table - 所有玩家数据 {[UserId] = PlayerData}
]]
function DataManager.GetAllPlayerData()
    return playerDataCache
end

--[[
🔥修复服务器关闭时数据保存：根据UserId保存缓存数据
@param userId number - 玩家UserId
@return boolean - 是否保存成功
]]
function DataManager.SaveCachedPlayerData(userId)
    local playerData = playerDataCache[userId]
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SaveCachedPlayerData: 找不到缓存数据 -", userId)
        return false
    end

    -- 标记保存开始
    AddPendingSave(userId)

    -- 创建临时Player对象用于保存（仅用于日志）
    local success = SaveToDataStore(nil, playerData, userId)

    -- 标记保存完成
    RemovePendingSave(userId)

    return success
end

--[[
🔥修复服务器关闭时数据保存：等待所有保存完成
@param timeout number - 超时时间（秒），默认10秒
@return boolean - 是否在超时前全部完成
]]
function DataManager.WaitForAllSavesToComplete(timeout)
    timeout = timeout or 10
    local startTime = tick()

    while tick() - startTime < timeout do
        local hasPendingSaves = false
        for _, count in pairs(pendingSaves) do
            if count and count > 0 then
                hasPendingSaves = true
                break
            end
        end

        if not hasPendingSaves then
            return true  -- 全部完成
        end

        -- 🔥V2.6.1优化：减少轮询间隔到0.05秒，更快响应完成状态
        task.wait(0.05)
    end

    return false  -- 超时
end

--[[
🔥修复服务器关闭时数据保存：获取待保存数量
@return number - 待保存的玩家数量
]]
function DataManager.GetPendingSaveCount()
    local count = 0
    for _, pending in pairs(pendingSaves) do
        if pending and pending > 0 then
            count = count + 1
        end
    end
    return count
end

--[[
🔥修复服务器关闭时数据保存：同步放置单位数据
@param player Player - 玩家对象
@param placedUnitsData table - 放置单位数据
]]
function DataManager.SyncPlacedUnits(player, placedUnitsData)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SyncPlacedUnits: 找不到玩家数据")
        return false
    end

    -- 清洗数据，移除不可序列化的字段（如Model引用）
    local cleanedData = {}
    for instanceId, unitData in pairs(placedUnitsData) do
        local gridWidth = unitData.GridWidth or unitData.GridSize or 1
        local gridDepth = unitData.GridDepth or unitData.GridSize or gridWidth

        cleanedData[instanceId] = {
            InstanceId = unitData.InstanceId,
            UnitId = unitData.UnitId,
            Level = unitData.Level or 1,
            GridX = unitData.GridX,
            GridZ = unitData.GridZ,
            GridSize = unitData.GridSize,
            GridWidth = gridWidth,
            GridDepth = gridDepth,
            PlacedTime = unitData.PlacedTime,
            -- 注意：不包含Position和Model，因为这些可以通过其他数据重建
        }
    end

    playerData.PlacedUnits = cleanedData
    return true
end

--[[
🔥修复服务器关闭时数据保存：添加单个放置单位
@param player Player - 玩家对象
@param instanceId string - 实例ID
@param unitData table - 单位数据
]]
function DataManager.AddPlacedUnit(player, instanceId, unitData)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "AddPlacedUnit: 找不到玩家数据")
        return false
    end

    if not playerData.PlacedUnits then
        playerData.PlacedUnits = {}
    end

    -- 清洗数据
    local gridWidth = unitData.GridWidth or unitData.GridSize or 1
    local gridDepth = unitData.GridDepth or unitData.GridSize or gridWidth

    playerData.PlacedUnits[instanceId] = {
        InstanceId = unitData.InstanceId,
        UnitId = unitData.UnitId,
        Level = unitData.Level or 1,
        GridX = unitData.GridX,
        GridZ = unitData.GridZ,
        GridSize = unitData.GridSize,
        GridWidth = gridWidth,
        GridDepth = gridDepth,
        PlacedTime = unitData.PlacedTime or os.time(),
    }

    return true
end

-- ==================== V2.6挂机金币系统接口 ====================

-- 获取玩家挂机配置（根据最高解锁房屋）
local function GetIdleConfigForPlayer(player)
    local completedChapters = DataManager.GetCompletedChapters(player) or 0
    local houseConfig = HouseConfig.GetIdleConfigByCompletedChapters(completedChapters)

    local coinsPerMinute = houseConfig and tonumber(houseConfig.CoinsPerMinute) or 0
    local maxMinutes = houseConfig and tonumber(houseConfig.MaxMinutes) or 0
    local maxHours = houseConfig and tonumber(houseConfig.MaxHours) or 0

    if coinsPerMinute <= 0 then
        coinsPerMinute = tonumber(GameConfig.IdleCoin.CoinsPerMinute) or 0
    end

    if maxMinutes <= 0 then
        maxMinutes = tonumber(GameConfig.IdleCoin.MaxOfflineMinutes) or 0
    end

    if maxHours <= 0 then
        maxHours = math.floor(maxMinutes / 60)
    end

    return {
        CoinsPerMinute = coinsPerMinute,
        MaxMinutes = maxMinutes,
        MaxHours = maxHours,
    }
end

-- 计算挂机金币上限（分钟上限 * 每分钟金币）
local function GetIdleCoinMaxCoins(player)
    local idleConfig = GetIdleConfigForPlayer(player)
    if not idleConfig then
        return nil
    end

    local maxMinutes = tonumber(idleConfig.MaxMinutes)
    local coinsPerMinute = tonumber(idleConfig.CoinsPerMinute)
    if not maxMinutes or not coinsPerMinute or maxMinutes <= 0 or coinsPerMinute <= 0 then
        return nil
    end

    return maxMinutes * coinsPerMinute
end

-- 钳制挂机金币到上限
local function ClampPendingIdleCoins(player, value)
    local amount = tonumber(value) or 0
    if amount < 0 then
        amount = 0
    end

    local maxCoins = GetIdleCoinMaxCoins(player)
    if maxCoins and amount > maxCoins then
        amount = maxCoins
    end

    return amount
end

--[[
获取玩家挂机金币数据
@param player Player - 玩家对象
@return table - {LastLogoutTime = number, PendingCoins = number}
]]
function DataManager.GetIdleCoinData(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {
            LastLogoutTime = 0,
            PendingCoins = 0,
            GuideEligibleOnLogin = false,
        }
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
            GuideEligibleOnLogin = false,
        }
    elseif playerData.IdleCoinData.GuideEligibleOnLogin == nil then
        playerData.IdleCoinData.GuideEligibleOnLogin = false
    end

    -- 钳制PendingCoins到配置上限，避免超出累积时间上限
    playerData.IdleCoinData.PendingCoins = ClampPendingIdleCoins(player, playerData.IdleCoinData.PendingCoins)

    return playerData.IdleCoinData
end

--[[
设置玩家待领取的挂机金币
@param player Player - 玩家对象
@param coins number - 待领取金币数量
@return boolean - 是否设置成功
]]
function DataManager.SetPendingIdleCoins(player, coins)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetPendingIdleCoins: 找不到玩家数据")
        return false
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
            GuideEligibleOnLogin = false,
        }
    elseif playerData.IdleCoinData.GuideEligibleOnLogin == nil then
        playerData.IdleCoinData.GuideEligibleOnLogin = false
    end

    playerData.IdleCoinData.PendingCoins = ClampPendingIdleCoins(player, coins)
    return true
end

--[[
设置玩家上次登出时间
@param player Player - 玩家对象
@param timestamp number - 登出时间戳
@return boolean - 是否设置成功
]]
function DataManager.SetLastLogoutTime(player, timestamp)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetLastLogoutTime: 找不到玩家数据")
        return false
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
            GuideEligibleOnLogin = false,
        }
    elseif playerData.IdleCoinData.GuideEligibleOnLogin == nil then
        playerData.IdleCoinData.GuideEligibleOnLogin = false
    end

    playerData.IdleCoinData.LastLogoutTime = timestamp
    return true
end

--[[
增加玩家待领取的挂机金币
@param player Player - 玩家对象
@param amount number - 增加数量
@return boolean, number - 是否成功, 新的待领取金币数量
]]
function DataManager.AddPendingIdleCoins(player, amount)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "AddPendingIdleCoins: 找不到玩家数据")
        return false, 0
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
            GuideEligibleOnLogin = false,
        }
    elseif playerData.IdleCoinData.GuideEligibleOnLogin == nil then
        playerData.IdleCoinData.GuideEligibleOnLogin = false
    end

    local newPending = (playerData.IdleCoinData.PendingCoins or 0) + (tonumber(amount) or 0)
    playerData.IdleCoinData.PendingCoins = ClampPendingIdleCoins(player, newPending)
    return true, playerData.IdleCoinData.PendingCoins
end

--[[
清空玩家待领取的挂机金币
@param player Player - 玩家对象
@return number - 清空前的金币数量
]]
function DataManager.ClearPendingIdleCoins(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "ClearPendingIdleCoins: 找不到玩家数据")
        return 0
    end

    if not playerData.IdleCoinData then
        playerData.IdleCoinData = {
            LastLogoutTime = 0,
            PendingCoins = 0,
            GuideEligibleOnLogin = false,
        }
        return 0
    elseif playerData.IdleCoinData.GuideEligibleOnLogin == nil then
        playerData.IdleCoinData.GuideEligibleOnLogin = false
    end

    local oldAmount = playerData.IdleCoinData.PendingCoins or 0
    playerData.IdleCoinData.PendingCoins = 0
    playerData.IdleCoinData.GuideEligibleOnLogin = false
    return oldAmount
end

-- ==================== V4.6音效设置接口 ====================

--[[
获取玩家音效设置
@param player Player - 玩家对象
@return table - {MusicEnabled = boolean, SfxEnabled = boolean}
]]
function DataManager.GetSoundSettings(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {
            MusicEnabled = true,
            SfxEnabled = true,
        }
    end

    if not playerData.SoundSettings then
        playerData.SoundSettings = {
            MusicEnabled = true,
            SfxEnabled = true,
        }
    else
        if playerData.SoundSettings.MusicEnabled == nil then
            playerData.SoundSettings.MusicEnabled = true
        end
        if playerData.SoundSettings.SfxEnabled == nil then
            playerData.SoundSettings.SfxEnabled = true
        end
    end

    return playerData.SoundSettings
end

--[[
设置玩家音效开关
@param player Player - 玩家对象
@param musicEnabled boolean|nil - BGM开关
@param sfxEnabled boolean|nil - SFX开关
@return boolean - 是否设置成功
]]
function DataManager.SetSoundSettings(player, musicEnabled, sfxEnabled)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetSoundSettings: 找不到玩家数据")
        return false
    end

    if not playerData.SoundSettings then
        playerData.SoundSettings = {
            MusicEnabled = true,
            SfxEnabled = true,
        }
    end

    if type(musicEnabled) == "boolean" then
        playerData.SoundSettings.MusicEnabled = musicEnabled
    end
    if type(sfxEnabled) == "boolean" then
        playerData.SoundSettings.SfxEnabled = sfxEnabled
    end

    return true
end

--[[
GM命令：重置玩家所有数据
@param player Player - 玩家对象
@return boolean - 是否重置成功
说明: 此函数会清空玩家的所有数据并保存到DataStore
]]
function DataManager.ResetAllPlayerData(player)
    if not player then
        warn(GameConfig.LOG_PREFIX, "ResetAllPlayerData: player为空")
        return false
    end

    local userId = player.UserId

    -- 创建全新的默认数据
    local newData = CreateDefaultData(player)

    -- 更新缓存
    playerDataCache[userId] = newData

    if player and player:IsA("Player") then
        local chapterProgress = newData.ChapterProgress or {}
        player:SetAttribute("CompletedChapters", chapterProgress.CompletedChapters or 0)
        player:SetAttribute("CurrentHouseModel", chapterProgress.CurrentHouseModel or "PrisonLv1")
    end

    -- 立即保存到DataStore
    local saveSuccess = SaveToDataStore(player, newData)

    if saveSuccess then
        print(string.format(
            "%s [DataManager] ✅ 玩家 %s 的所有数据已重置",
            GameConfig.LOG_PREFIX,
            player.Name
        ))
    else
        warn(string.format(
            "%s [DataManager] ⚠ 玩家 %s 数据重置后保存失败",
            GameConfig.LOG_PREFIX,
            player.Name
        ))
    end

    return saveSuccess
end

-- ==================== V2.8章节进度系统接口 ====================

--[[
获取玩家章节进度数据
@param player Player - 玩家对象
@return table - {CurrentChapter = number, CompletedChapters = number, CurrentHouseModel = string}
]]
function DataManager.GetChapterProgress(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {
            CurrentChapter = 1,
            CompletedChapters = 0,
            CurrentHouseModel = "PrisonLv1",
            MaxClearedChapter = 1,
            MaxClearedStage = 0,
        }
    end

    EnsureChapterProgress(playerData)

    return playerData.ChapterProgress
end

--[[
获取玩家当前挑战章节
@param player Player - 玩家对象
@return number - 当前章节ID
]]
function DataManager.GetCurrentChapter(player)
    local progress = DataManager.GetChapterProgress(player)
    local chapter = progress.CurrentChapter or 1
    -- V3.7.1修复：确保章节ID不超过配置的最大章节数（兼容已有的错误数据）
    local maxChapters = StageConfig.TotalChapters
    return math.min(chapter, maxChapters)
end

--[[
获取玩家已通关章节数
@param player Player - 玩家对象
@return number - 已通关章节数
]]
function DataManager.GetCompletedChapters(player)
    local progress = DataManager.GetChapterProgress(player)
    return progress.CompletedChapters or 0
end

--[[
设置玩家当前挑战章节
@param player Player - 玩家对象
@param chapterId number - 章节ID
@return boolean - 是否设置成功
]]
function DataManager.SetCurrentChapter(player, chapterId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetCurrentChapter: 找不到玩家数据")
        return false
    end

    EnsureChapterProgress(playerData)

    playerData.ChapterProgress.CurrentChapter = chapterId
    return true
end

--[[
通关章节（增加已通关章节数）
@param player Player - 玩家对象
@param chapterId number - 通关的章节ID
@return boolean, number - 是否成功, 新的已通关章节数
]]
function DataManager.CompleteChapter(player, chapterId)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "CompleteChapter: 找不到玩家数据")
        return false, 0
    end

    EnsureChapterProgress(playerData)

    -- 只有通关当前章节才更新进度（防止重复通关刷进度）
    if chapterId == playerData.ChapterProgress.CurrentChapter then
        -- 更新已通关章节数
        if chapterId > playerData.ChapterProgress.CompletedChapters then
            playerData.ChapterProgress.CompletedChapters = chapterId
        end

        if player and player:IsA("Player") then
            player:SetAttribute("CompletedChapters", playerData.ChapterProgress.CompletedChapters)
        end

        -- 同步更新“主线最大通关关卡”（只增不减）
        -- 章节通关等价于该章节最后一关已通关
        do
            local stagesPerChapter = GetStagesPerChapterSafe(chapterId)
            local maxChapter = tonumber(playerData.ChapterProgress.MaxClearedChapter) or 1
            local maxStage = tonumber(playerData.ChapterProgress.MaxClearedStage) or 0

            if chapterId > maxChapter or (chapterId == maxChapter and stagesPerChapter > maxStage) then
                playerData.ChapterProgress.MaxClearedChapter = chapterId
                playerData.ChapterProgress.MaxClearedStage = stagesPerChapter
            end
        end

        -- V3.7.1修复：自动进入下一章，但不超过最大章节数
        -- 如果已打通最后一章，则保持在最后一章继续挑战
        local maxChapters = StageConfig.TotalChapters
        playerData.ChapterProgress.CurrentChapter = math.min(chapterId + 1, maxChapters)
    end

    return true, playerData.ChapterProgress.CompletedChapters
end

--[[
获取玩家主线最大通关进度（只增不减）
@param player Player - 玩家对象
@return number, number - MaxClearedChapter, MaxClearedStage
]]
function DataManager.GetMaxClearedProgress(player)
    local progress = DataManager.GetChapterProgress(player)
    local maxChapter = tonumber(progress.MaxClearedChapter) or 1
    local maxStage = tonumber(progress.MaxClearedStage) or 0
    return maxChapter, maxStage
end

--[[
更新玩家主线最大通关进度（只增不减）
说明：用于“玩家最多通关到第几章第几关”的打点数据
@param player Player - 玩家对象
@param clearedChapter number - 本次通关的章节ID（从1开始）
@param clearedStage number - 本次通关的关卡编号（章节内，从1开始；0表示尚未通关任何关卡）
@return boolean, number, number - 是否发生更新, MaxClearedChapter, MaxClearedStage
]]
function DataManager.UpdateMaxClearedProgress(player, clearedChapter, clearedStage)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "UpdateMaxClearedProgress: 找不到玩家数据")
        return false, 0, 0
    end

    EnsureChapterProgress(playerData)
    local progress = playerData.ChapterProgress

    local chapterId = tonumber(clearedChapter)
    local stageNum = tonumber(clearedStage)
    if not chapterId or not stageNum then
        return false, tonumber(progress.MaxClearedChapter) or 1, tonumber(progress.MaxClearedStage) or 0
    end

    if chapterId < 1 then
        chapterId = 1
    end
    if stageNum < 0 then
        stageNum = 0
    end

    -- 保护：关卡编号不超过该章节的最大关卡数（避免异常数据写入）
    local stagesPerChapter = GetStagesPerChapterSafe(chapterId)
    if stageNum > stagesPerChapter then
        stageNum = stagesPerChapter
    end

    local oldMaxChapter = tonumber(progress.MaxClearedChapter) or 1
    local oldMaxStage = tonumber(progress.MaxClearedStage) or 0

    local updated = false
    if chapterId > oldMaxChapter then
        progress.MaxClearedChapter = chapterId
        progress.MaxClearedStage = stageNum
        updated = true
    elseif chapterId == oldMaxChapter and stageNum > oldMaxStage then
        progress.MaxClearedStage = stageNum
        updated = true
    end

    return updated, tonumber(progress.MaxClearedChapter) or 1, tonumber(progress.MaxClearedStage) or 0
end

--[[
获取玩家当前房屋模型名称
@param player Player - 玩家对象
@return string - 房屋模型名称
]]
function DataManager.GetCurrentHouseModel(player)
    local progress = DataManager.GetChapterProgress(player)
    return progress.CurrentHouseModel or "PrisonLv1"
end

--[[
设置玩家当前房屋模型名称
@param player Player - 玩家对象
@param modelName string - 新的房屋模型名称
@return boolean - 是否设置成功
]]
function DataManager.SetCurrentHouseModel(player, modelName)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetCurrentHouseModel: 找不到玩家数据")
        return false
    end

    EnsureChapterProgress(playerData)

    playerData.ChapterProgress.CurrentHouseModel = modelName

    if player and player:IsA("Player") then
        player:SetAttribute("CurrentHouseModel", modelName)
    end
    return true
end

-- ==================== V3.0技能系统接口 ====================

--[[
归一化技能背包，确保所有key都是number类型
@param playerData table - 玩家数据
]]
local function NormalizeSkillInventory(playerData)
    if not playerData.SkillInventory then
        playerData.SkillInventory = {}
        return
    end

    -- 收集需要转换的字符串key
    local keysToConvert = {}
    for key, count in pairs(playerData.SkillInventory) do
        if type(key) ~= "number" then
            local nid = tonumber(key)
            if nid then
                table.insert(keysToConvert, {oldKey = key, newKey = nid, count = count})
            end
        end
    end

    -- 执行转换
    for _, item in ipairs(keysToConvert) do
        playerData.SkillInventory[item.oldKey] = nil
        playerData.SkillInventory[item.newKey] = (playerData.SkillInventory[item.newKey] or 0) + item.count
    end
end

--[[
获取玩家技能背包
@param player Player - 玩家对象
@return table - 技能背包 {[skillId] = count}
]]
function DataManager.GetSkillInventory(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        return {}
    end

    if not playerData.SkillInventory then
        playerData.SkillInventory = {}
    end

    -- V3.1修复：归一化后回写到playerData，确保后续操作都是数字key
    NormalizeSkillInventory(playerData)

    -- 返回副本
    local inventory = {}
    for skillId, count in pairs(playerData.SkillInventory) do
        if count and count > 0 then
            inventory[skillId] = count
        end
    end

    return inventory
end

--[[
获取玩家指定技能的数量
@param player Player - 玩家对象
@param skillId number - 技能ID
@return number - 技能数量
]]
function DataManager.GetSkillCount(player, skillId)
    local inventory = DataManager.GetSkillInventory(player)
    -- V3.0修复：确保skillId是number类型
    local normalizedId = tonumber(skillId)
    if not normalizedId then
        return 0
    end
    return inventory[normalizedId] or 0
end

--[[
添加技能到玩家背包
@param player Player - 玩家对象
@param skillId number - 技能ID
@param count number - 添加数量
@return boolean, number - 是否成功, 新数量
]]
function DataManager.AddSkill(player, skillId, count)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "AddSkill: 找不到玩家数据")
        return false, 0
    end

    if not playerData.SkillInventory then
        playerData.SkillInventory = {}
    end

    -- V3.1修复：先归一化，确保所有key都是数字类型
    NormalizeSkillInventory(playerData)

    -- V3.0修复：确保skillId是number类型
    local normalizedId = tonumber(skillId)
    if not normalizedId then
        warn(GameConfig.LOG_PREFIX, "AddSkill: 无效的技能ID", skillId)
        return false, 0
    end

    local currentCount = playerData.SkillInventory[normalizedId] or 0
    local newCount = currentCount + count
    playerData.SkillInventory[normalizedId] = newCount

    print(string.format("[DataManager] 添加技能: skillId=%d, 添加数量=%d, 新数量=%d", normalizedId, count, newCount))

    return true, newCount
end

--[[
从玩家背包移除技能
@param player Player - 玩家对象
@param skillId number - 技能ID
@param count number - 移除数量
@return boolean, number - 是否成功, 剩余数量
]]
function DataManager.RemoveSkill(player, skillId, count)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "RemoveSkill: 找不到玩家数据")
        return false, 0
    end

    if not playerData.SkillInventory then
        playerData.SkillInventory = {}
        return false, 0
    end

    -- V3.1修复：先归一化，确保所有key都是数字类型
    NormalizeSkillInventory(playerData)

    -- V3.0修复：确保skillId是number类型
    local normalizedId = tonumber(skillId)
    if not normalizedId then
        warn(GameConfig.LOG_PREFIX, "RemoveSkill: 无效的技能ID", skillId)
        return false, 0
    end

    local currentCount = playerData.SkillInventory[normalizedId] or 0
    if currentCount < count then
        warn(string.format("[DataManager] RemoveSkill: 技能数量不足 skillId=%d, 当前=%d, 请求移除=%d", normalizedId, currentCount, count))
        return false, currentCount
    end

    local newCount = currentCount - count
    if newCount <= 0 then
        playerData.SkillInventory[normalizedId] = nil
    else
        playerData.SkillInventory[normalizedId] = newCount
    end

    print(string.format("[DataManager] 移除技能: skillId=%d, 移除数量=%d, 剩余=%d", normalizedId, count, newCount))

    return true, newCount
end

--[[
设置玩家技能数量
@param player Player - 玩家对象
@param skillId number - 技能ID
@param count number - 设置数量
@return boolean - 是否成功
]]
function DataManager.SetSkillCount(player, skillId, count)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "SetSkillCount: 找不到玩家数据")
        return false
    end

    if not playerData.SkillInventory then
        playerData.SkillInventory = {}
    end

    -- V3.0修复：确保skillId是number类型
    local normalizedId = tonumber(skillId)
    if not normalizedId then
        warn(GameConfig.LOG_PREFIX, "SetSkillCount: 无效的技能ID", skillId)
        return false
    end

    if count <= 0 then
        playerData.SkillInventory[normalizedId] = nil
    else
        playerData.SkillInventory[normalizedId] = count
    end

    return true
end

--[[
清空玩家技能背包
@param player Player - 玩家对象
@return boolean - 是否成功
]]
function DataManager.ClearSkillInventory(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        warn(GameConfig.LOG_PREFIX, "ClearSkillInventory: 找不到玩家数据")
        return false
    end

    playerData.SkillInventory = {}
    return true
end

return DataManager
