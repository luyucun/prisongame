--[[
脚本名称: CurrencySystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/CurrencySystem
版本: V3.4.1 - 新增战斗金币表现通知
]]

--[[
货币系统模块
职责:
1. 提供货币增减的统一接口
2. 验证货币操作的合法性
3. 通知客户端货币变化
4. 为不同的货币获取渠道提供接口
5. V3.4.1新增：战斗金币获取时触发客户端表现效果
]]

local CurrencySystem = {}

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local DataManager = require(ServerScriptService.Core.DataManager)

-- 远程事件(延迟获取,避免循环依赖)
local CurrencyEvents = nil

-- V3.4.1新增：战斗金币表现事件
local CoinEarnedEffectEvent = nil

-- ==================== 私有函数 ====================

--[[
初始化事件(延迟加载,支持重试)
@param useWait boolean - 是否使用WaitForChild(默认false,在Initialize中使用true)
@return boolean - 是否成功
]]
local function InitializeEvents(useWait)
    if not CurrencyEvents then
        local eventsFolder = nil

        if useWait then
            -- 初始化时使用WaitForChild,最多等待10秒
            eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
        else
            -- 运行时使用FindFirstChild,避免阻塞
            eventsFolder = ReplicatedStorage:FindFirstChild("Events")
        end

        if not eventsFolder then
            warn(GameConfig.LOG_PREFIX, "InitializeEvents: Events文件夹未找到")
            return false
        end

        if useWait then
            -- 初始化时使用WaitForChild
            CurrencyEvents = eventsFolder:WaitForChild("CurrencyEvents", 10)
        else
            -- 运行时使用FindFirstChild
            CurrencyEvents = eventsFolder:FindFirstChild("CurrencyEvents")
        end

        if not CurrencyEvents then
            warn(GameConfig.LOG_PREFIX, "InitializeEvents: 找不到CurrencyEvents!")
            return false
        end

    end

    return true
end

--[[
通知客户端货币变化
@param player Player - 玩家对象
@param currencyType string - 货币类型
@param newAmount number - 新的货币数量
@return boolean - 是否通知成功
]]
local function NotifyClient(player, currencyType, newAmount)
    local initialized = InitializeEvents(false)  -- 运行时不等待

    if not initialized then
        warn(GameConfig.LOG_PREFIX, "通知失败: 事件未初始化")
        return false
    end

    if not CurrencyEvents then
        warn(GameConfig.LOG_PREFIX, "无法通知客户端,CurrencyEvents未找到")
        return false
    end

    -- 安全地发送事件
    local success, errorMsg = pcall(function()
        CurrencyEvents:FireClient(player, currencyType, newAmount)
    end)

    if success then
        return true
    else
        warn(GameConfig.LOG_PREFIX, "通知客户端失败:", player.Name, "错误:", errorMsg)
        return false
    end
end

--[[
验证货币操作
@param player Player - 玩家对象
@param amount number - 变化数量
@return boolean, string - 是否有效,错误信息
]]
local function ValidateOperation(player, amount)
    if not player then
        return false, "玩家对象为空"
    end

    if type(amount) ~= "number" then
        return false, "数量必须是数字"
    end

    if amount == 0 then
        return false, "数量不能为0"
    end

    return true, ""
end

-- ==================== 公共接口 ====================

--[[
添加货币(通用方法)
@param player Player - 玩家对象
@param currencyType string - 货币类型
@param amount number - 添加数量(必须为正数)
@param reason string - 原因
@return boolean, number - 是否成功, 新的货币数量
]]
function CurrencySystem.AddCurrency(player, currencyType, amount, reason)
    -- 验证参数
    local valid, errorMsg = ValidateOperation(player, amount)
    if not valid then
        warn(GameConfig.LOG_PREFIX, "AddCurrency验证失败:", errorMsg)
        return false, 0
    end

    if amount < 0 then
        warn(GameConfig.LOG_PREFIX, "AddCurrency: 数量必须为正数")
        return false, 0
    end

    -- 更新数据
    local success, newAmount = DataManager.UpdateCurrency(player, currencyType, amount, reason)

    if success then
        -- 通知客户端
        NotifyClient(player, currencyType, newAmount)

        -- 🔥修复持久化：金币变化后保存数据
        DataManager.SavePlayerDataThrottled(player)
    end

    return success, newAmount
end

--[[
扣除货币(通用方法)
@param player Player - 玩家对象
@param currencyType string - 货币类型
@param amount number - 扣除数量(必须为正数)
@param reason string - 原因
@return boolean, number - 是否成功, 新的货币数量
]]
function CurrencySystem.RemoveCurrency(player, currencyType, amount, reason)
    -- 验证参数
    local valid, errorMsg = ValidateOperation(player, amount)
    if not valid then
        warn(GameConfig.LOG_PREFIX, "RemoveCurrency验证失败:", errorMsg)
        return false, 0
    end

    if amount < 0 then
        warn(GameConfig.LOG_PREFIX, "RemoveCurrency: 数量必须为正数")
        return false, 0
    end

    -- 检查是否有足够的货币
    local currentAmount = DataManager.GetCurrency(player, currencyType)
    if not currentAmount then
        warn(GameConfig.LOG_PREFIX, "RemoveCurrency: 获取货币失败")
        return false, 0
    end

    if currentAmount < amount then
        warn(GameConfig.LOG_PREFIX, "RemoveCurrency: 货币不足", player.Name, currencyType, "需要:", amount, "当前:", currentAmount)
        return false, currentAmount
    end

    -- 更新数据(传入负数)
    local success, newAmount = DataManager.UpdateCurrency(player, currencyType, -amount, reason)

    if success then
        -- 通知客户端
        NotifyClient(player, currencyType, newAmount)

        -- 🔥修复持久化：金币变化后保存数据
        DataManager.SavePlayerDataThrottled(player)
    end

    return success, newAmount
end

--[[
设置货币数量(通用方法,谨慎使用)
@param player Player - 玩家对象
@param currencyType string - 货币类型
@param amount number - 新的数量
@param reason string - 原因
@return boolean, number - 是否成功, 新的货币数量
]]
function CurrencySystem.SetCurrency(player, currencyType, amount, reason)
    if not player or type(amount) ~= "number" or amount < 0 then
        warn(GameConfig.LOG_PREFIX, "SetCurrency: 参数无效")
        return false, 0
    end

    local currentAmount = DataManager.GetCurrency(player, currencyType)
    if not currentAmount then
        warn(GameConfig.LOG_PREFIX, "SetCurrency: 获取货币失败")
        return false, 0
    end

    local delta = amount - currentAmount
    local success, newAmount = DataManager.UpdateCurrency(player, currencyType, delta, reason)

    if success then
        NotifyClient(player, currencyType, newAmount)
    end

    return success, newAmount
end

-- ==================== 金币专用接口 ====================

--[[
添加金币
@param player Player - 玩家对象
@param amount number - 金币数量
@param reason string - 原因
@return boolean, number - 是否成功, 新的金币数量
]]
function CurrencySystem.AddCoins(player, amount, reason)
    return CurrencySystem.AddCurrency(player, GameConfig.CurrencyType.COINS, amount, reason)
end

--[[
扣除金币
@param player Player - 玩家对象
@param amount number - 金币数量
@param reason string - 原因
@return boolean, number - 是否成功, 新的金币数量
]]
function CurrencySystem.RemoveCoins(player, amount, reason)
    return CurrencySystem.RemoveCurrency(player, GameConfig.CurrencyType.COINS, amount, reason)
end

--[[
获取玩家金币数量
@param player Player - 玩家对象
@return number|nil - 金币数量
]]
function CurrencySystem.GetCoins(player)
    return DataManager.GetCurrency(player, GameConfig.CurrencyType.COINS)
end

--[[
检查玩家是否有足够的金币
@param player Player - 玩家对象
@param amount number - 需要的金币数量
@return boolean - 是否足够
]]
function CurrencySystem.HasEnoughCoins(player, amount)
    local currentCoins = CurrencySystem.GetCoins(player)
    return currentCoins and currentCoins >= amount
end

-- ==================== 货币获取渠道接口(预留) ====================

--[[
通过GM命令获得金币(测试用)
@param player Player - 玩家对象
@param amount number - 金币数量
@return boolean, number - 是否成功, 新的金币数量
]]
function CurrencySystem.AddCoinsFromGM(player, amount)
    local reason = "GM命令"
    return CurrencySystem.AddCoins(player, amount, reason)
end

--[[
通过战斗获得金币
@param player Player - 玩家对象
@param amount number - 金币数量
@param stageId number - 关卡ID(可选)
@return boolean, number - 是否成功, 新的金币数量

V3.4.1更新：添加战斗金币获取表现效果
]]
function CurrencySystem.AddCoinsFromBattle(player, amount, stageId)
    local reason = string.format("战斗获得(关卡:%s)", tostring(stageId or "未知"))
    local success, newAmount = CurrencySystem.AddCoins(player, amount, reason)

    -- V3.4.1新增：战斗中获得金币时触发客户端表现效果
    if success and amount > 0 then
        CurrencySystem.NotifyBattleCoinEffect(player, amount)
    end

    return success, newAmount
end

--[[
通过挂机获得金币
@param player Player - 玩家对象
@param amount number - 金币数量
@param duration number - 挂机时长(秒,可选)
@return boolean, number - 是否成功, 新的金币数量
]]
function CurrencySystem.AddCoinsFromIdle(player, amount, duration)
    local reason = string.format("挂机获得(时长:%s秒)", tostring(duration or "未知"))
    return CurrencySystem.AddCoins(player, amount, reason)
end

--[[
通过购买开发者产品获得金币
@param player Player - 玩家对象
@param amount number - 金币数量
@param productId number - 产品ID
@return boolean, number - 是否成功, 新的金币数量
]]
function CurrencySystem.AddCoinsFromPurchase(player, amount, productId)
    local reason = string.format("购买获得(产品ID:%s)", tostring(productId or "未知"))
    return CurrencySystem.AddCoins(player, amount, reason)
end

-- ==================== 客户端请求处理 ====================

--[[
处理客户端请求货币信息
@param player Player - 请求的玩家
]]
local function OnClientRequestCurrency(player)
    task.spawn(function()  -- 使用task.spawn避免阻塞其他请求
        -- 🔥修复竞态条件：等待玩家数据加载完成
        local playerData = DataManager.WaitForPlayerData(player, 10)
        if not playerData then
            warn(GameConfig.LOG_PREFIX, "OnClientRequestCurrency: 玩家数据加载超时 -", player.Name)
            -- 即使超时也要尝试获取数据，可能数据已经部分加载
        end

        -- 获取玩家所有货币
        local allCurrency = DataManager.GetAllCurrency(player)

        if allCurrency then
            -- 发送金币信息给客户端
            NotifyClient(player, GameConfig.CurrencyType.COINS, allCurrency.Coins)
            if GameConfig.DEBUG_MODE then
                print(string.format(
                    "%s [CurrencySystem] ✅ 响应客户端请求：玩家 %s 金币 %d",
                    GameConfig.LOG_PREFIX,
                    player.Name,
                    allCurrency.Coins
                ))
            end
        else
            -- 🔥修复：如果数据仍未加载，使用默认值并记录
            warn(string.format(
                "%s [CurrencySystem] ⚠️ 玩家 %s 货币数据未就绪，使用默认值 %d",
                GameConfig.LOG_PREFIX,
                player.Name,
                GameConfig.InitialCoins
            ))

            -- 发送默认金币值，避免客户端界面显示为0
            NotifyClient(player, GameConfig.CurrencyType.COINS, GameConfig.InitialCoins)
        end
    end)
end

--[[
初始化货币系统
连接远程事件
@return boolean - 是否初始化成功
]]
function CurrencySystem.Initialize()

    -- 初始化事件(使用WaitForChild等待事件创建)
    local eventsInitialized = InitializeEvents(true)
    if not eventsInitialized then
        warn(GameConfig.LOG_PREFIX, "CurrencySystem初始化失败: 事件加载失败")
        warn(GameConfig.LOG_PREFIX, "请确保ReplicatedStorage/Events/CurrencyEvents存在")
        return false
    end

    -- 连接客户端请求事件
    if CurrencyEvents then
        local success, error = pcall(function()
            CurrencyEvents.OnServerEvent:Connect(OnClientRequestCurrency)
        end)

        if not success then
            warn(GameConfig.LOG_PREFIX, "连接CurrencyEvents.OnServerEvent失败:", error)
            return false
        end

    else
        warn(GameConfig.LOG_PREFIX, "CurrencyEvents未找到,无法连接事件")
        return false
    end


    return true
end

--[[
🔥修复金币显示延迟：主动推送玩家初始金币
在玩家数据加载完成后立即调用，确保客户端及时收到金币数据
@param player Player - 玩家对象
]]
function CurrencySystem.PushInitialCurrency(player)
    if not player or not player.Parent then
        return false
    end

    task.spawn(function()
        -- 获取玩家货币数据
        local allCurrency = DataManager.GetAllCurrency(player)
        if allCurrency then
            -- 主动推送金币信息给客户端
            NotifyClient(player, GameConfig.CurrencyType.COINS, allCurrency.Coins)
            if GameConfig.DEBUG_MODE then
                print(string.format(
                    "%s [CurrencySystem] 📤 主动推送初始金币：玩家 %s 金币 %d",
                    GameConfig.LOG_PREFIX,
                    player.Name,
                    allCurrency.Coins
                ))
            end
        else
            -- 如果数据加载失败，推送默认值
            NotifyClient(player, GameConfig.CurrencyType.COINS, GameConfig.InitialCoins)
            warn(string.format(
                "%s [CurrencySystem] 📤 推送默认金币：玩家 %s 金币 %d (数据未就绪)",
                GameConfig.LOG_PREFIX,
                player.Name,
                GameConfig.InitialCoins
            ))
        end
    end)

    return true
end

-- ==================== V3.4.1新增：战斗金币表现系统 ====================

--[[
初始化战斗金币表现事件
@return boolean - 是否成功
]]
local function InitializeBattleCoinEffectEvent()
    if CoinEarnedEffectEvent then
        return true
    end

    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if not eventsFolder then
        return false
    end

    local battleEventsFolder = eventsFolder:FindFirstChild("BattleEvents")
    if not battleEventsFolder then
        return false
    end

    CoinEarnedEffectEvent = battleEventsFolder:FindFirstChild("CoinEarnedEffect")
    if not CoinEarnedEffectEvent then
        -- 如果事件不存在，尝试创建（仅在服务端）
        if game:GetService("RunService"):IsServer() then
            CoinEarnedEffectEvent = Instance.new("RemoteEvent")
            CoinEarnedEffectEvent.Name = "CoinEarnedEffect"
            CoinEarnedEffectEvent.Parent = battleEventsFolder
            if GameConfig.DEBUG_MODE then
                print(GameConfig.LOG_PREFIX, "[CurrencySystem] ✅ 自动创建CoinEarnedEffect事件")
            end
        end
    end

    return CoinEarnedEffectEvent ~= nil
end

--[[
V3.4.1新增：通知客户端战斗金币获取表现效果
在战斗中获得金币时调用，触发客户端的抛洒烟花效果
@param player Player - 玩家对象
@param amount number - 获得的金币数量
@return boolean - 是否成功发送通知
]]
function CurrencySystem.NotifyBattleCoinEffect(player: Player, amount: number): boolean
    if not player or not player.Parent then
        return false
    end

    if not amount or amount <= 0 then
        return false
    end

    -- 确保事件已初始化
    if not CoinEarnedEffectEvent then
        InitializeBattleCoinEffectEvent()
    end

    if not CoinEarnedEffectEvent then
        -- 事件不存在，静默失败（不影响主流程）
        return false
    end

    -- 发送金币获取表现事件给客户端
    local success, errorMsg = pcall(function()
        CoinEarnedEffectEvent:FireClient(player, amount)
    end)

    if success then
        -- 调试日志（可选）
        if GameConfig.DEBUG_MODE then
            print(string.format(
                "%s [CurrencySystem] 🎉 发送金币表现事件：玩家 %s 获得 %d 金币",
                GameConfig.LOG_PREFIX,
                player.Name,
                amount
            ))
        end
        return true
    else
        warn(GameConfig.LOG_PREFIX, "[CurrencySystem] 发送金币表现事件失败:", errorMsg)
        return false
    end
end

return CurrencySystem
