--[[
脚本名称: CoinDisplay
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/CoinDisplay
版本: V2.1（集成金币滚动动画）
]]

--[[
金币显示控制器
职责:
1. 监听服务端的货币变化事件
2. 实时更新UI显示玩家金币数量
3. 使用格式化工具显示金币($XXXXX格式)
4. V2.1新增：金币变化时播放滚动动画
]]

-- 等待必要的服务和对象加载
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- 调试模式和日志前缀(必须在最前面定义)
local DEBUG_MODE = false
local LOG_PREFIX = "[CoinDisplay]"

-- 等待玩家GUI加载
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- 引用共享模块
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
if not Modules then
    warn(LOG_PREFIX, "严重错误: 找不到Modules文件夹!")
    error("Modules folder not found in ReplicatedStorage")
end

local FormatHelper = require(Modules:WaitForChild("FormatHelper", 10))

-- V2.1新增：动画工具（延迟加载，避免循环依赖）
local CoinAnimationHelper = nil

-- 引用远程事件
local Events = ReplicatedStorage:WaitForChild("Events", 10)
if not Events then
    warn(LOG_PREFIX, "严重错误: 找不到Events文件夹!")
    error("Events folder not found in ReplicatedStorage")
end

local CurrencyEvents = Events:WaitForChild("CurrencyEvents", 10)
if not CurrencyEvents then
    warn(LOG_PREFIX, "严重错误: 找不到CurrencyEvents事件!")
    error("CurrencyEvents not found in Events folder")
end

-- UI元素引用(会在重生后重新获取)
local MainGui = nil
local CoinNumLabel = nil

-- 当前金币数量(用于客户端缓存)
local currentCoins = 0

-- ==================== 私有函数 ====================

--[[
延迟加载动画助手
@return boolean - 是否成功加载
]]
local function LoadAnimationHelper()
    if CoinAnimationHelper then
        return true -- 已加载
    end

    -- 尝试加载动画助手模块
    local success, result = pcall(function()
        local script = game:GetService("StarterPlayer").StarterPlayerScripts.Utils.CoinAnimationHelper
        return require(script)
    end)

    if success then
        CoinAnimationHelper = result
        if DEBUG_MODE then
            print(LOG_PREFIX, "动画助手加载成功")
        end
        return true
    else
        warn(LOG_PREFIX, "动画助手加载失败:", result)
        return false
    end
end

--[[
获取或刷新UI引用
@return boolean - 是否成功获取UI引用
]]
local function RefreshUIReferences()
    -- 尝试获取MainGui
    if not MainGui or not MainGui.Parent then
        MainGui = PlayerGui:FindFirstChild("MainGui")

        if not MainGui then
            -- 静默等待，由 ChildAdded 回调负责后续刷新
            return false
        end

        if DEBUG_MODE then
            print(LOG_PREFIX, "MainGui引用已刷新")
        end
    end

    -- 尝试获取CoinNumLabel
    if not CoinNumLabel or not CoinNumLabel.Parent then
        CoinNumLabel = MainGui:FindFirstChild("CoinNum")

        if not CoinNumLabel then
            -- 静默等待，由 ChildAdded 回调负责后续刷新
            return false
        end

        if DEBUG_MODE then
            print(LOG_PREFIX, "CoinNumLabel引用已刷新")
        end
    end

    return true
end

--[[
更新金币显示（V2.1增强：支持动画）
@param newAmount number - 新的金币数量
@param useAnimation boolean - 是否使用动画（默认true）
]]
local function UpdateCoinDisplay(newAmount, useAnimation)
    -- 验证金币数量
    if type(newAmount) ~= "number" then
        warn(LOG_PREFIX, "金币数量必须是数字:", newAmount)
        return
    end

    -- 默认使用动画
    useAnimation = useAnimation ~= false

    -- 刷新UI引用
    if not RefreshUIReferences() then
        if DEBUG_MODE then
            print(LOG_PREFIX, "UI引用无效,等待GUI...")
        end
        return
    end

    local oldAmount = currentCoins
    currentCoins = newAmount

    -- V2.1新增：动画逻辑
    if useAnimation and LoadAnimationHelper() and math.abs(newAmount - oldAmount) > 0 then
        -- 使用动画更新
        CoinAnimationHelper.AnimateCoinRoll(CoinNumLabel, oldAmount, newAmount, {
            OnComplete = function()
                if DEBUG_MODE then
                    print(LOG_PREFIX, "金币动画完成:", oldAmount, "->", newAmount)
                end
            end
        })
    else
        -- 直接更新（无动画）
        local formattedText = FormatHelper.FormatCoins(newAmount)
        CoinNumLabel.Text = formattedText
    end

    if DEBUG_MODE then
        print(LOG_PREFIX, "更新金币显示:", oldAmount, "->", newAmount, useAnimation and "(动画)" or "(直接)")
    end
end

--[[
处理货币变化事件（V2.1增强：动画支持）
@param currencyType string - 货币类型
@param newAmount number - 新的货币数量
]]
local function OnCurrencyChanged(currencyType, newAmount)
    if DEBUG_MODE then
        print(LOG_PREFIX, "收到货币变化事件:", currencyType, newAmount)
    end

    -- 目前只处理金币
    if currencyType == "Coins" then
        UpdateCoinDisplay(newAmount, true) -- V2.1：默认使用动画
    end
end

-- ==================== 初始化 ====================

--[[
初始化金币显示系统
]]
local function Initialize()
    if DEBUG_MODE then
        print(LOG_PREFIX, "初始化金币显示系统...")
    end

    -- 获取初始UI引用
    local uiReady = RefreshUIReferences()
    if not uiReady then
        if DEBUG_MODE then
            print(LOG_PREFIX, "等待MainGui/CoinNum创建后再初始化显示")
        end
    else
        -- 仅在UI就绪时设置初始显示（不使用动画）
        UpdateCoinDisplay(0, false)
    end

    if not CurrencyEvents then
        warn(LOG_PREFIX, "错误: 找不到CurrencyEvents!")
        warn(LOG_PREFIX, "请确保ReplicatedStorage/Events中存在CurrencyEvents")
        return false
    end

    -- 监听PlayerGui的ChildAdded事件,处理GUI重建
    PlayerGui.ChildAdded:Connect(function(child)
        if child.Name == "MainGui" then
            if DEBUG_MODE then
                print(LOG_PREFIX, "检测到MainGui重建,刷新引用")
            end

            -- 重置引用以便下次UpdateCoinDisplay时重新获取
            MainGui = nil
            CoinNumLabel = nil

            -- 等待一帧确保GUI完全加载
            task.wait()

            -- 刷新引用并更新显示（不使用动画）
            if RefreshUIReferences() then
                UpdateCoinDisplay(currentCoins, false)
            end
        end
    end)

    -- 监听服务端的货币变化事件
    local connectionSuccess, connectionError = pcall(function()
        CurrencyEvents.OnClientEvent:Connect(OnCurrencyChanged)
    end)

    if not connectionSuccess then
        warn(LOG_PREFIX, "连接货币变化事件失败:", connectionError)
        return false
    end

    -- 🔥修复金币显示延迟：优化请求逻辑，添加重试机制
    task.spawn(function()
        local maxRetries = 3
        local retryDelay = 2  -- 每次重试间隔2秒
        local gotResponse = false

        -- 监听服务端响应，设置响应标志
        local responseConnection
        responseConnection = CurrencyEvents.OnClientEvent:Connect(function(currencyType, amount)
            gotResponse = true
            responseConnection:Disconnect()  -- 只监听第一次响应
        end)

        for attempt = 1, maxRetries do
            -- 每次尝试前等待一定时间，让服务端有时间初始化
            local delayTime = attempt == 1 and 1 or retryDelay
            task.wait(delayTime)

            local requestSuccess, requestError = pcall(function()
                CurrencyEvents:FireServer()
            end)

            if not requestSuccess then
                warn(LOG_PREFIX, "请求货币数据失败 (尝试", attempt .. "):", requestError)
                if attempt == maxRetries then
                    responseConnection:Disconnect()
                end
                continue
            end

            if DEBUG_MODE then
                print(LOG_PREFIX, "已向服务端请求货币数据 (尝试", attempt .. ")")
            end

            -- 等待服务端响应
            task.wait(2)

            if gotResponse then
                if DEBUG_MODE then
                    print(LOG_PREFIX, "收到服务端响应，停止重试")
                end
                break
            elseif attempt < maxRetries then
                if DEBUG_MODE then
                    print(LOG_PREFIX, "未收到响应，准备重试...")
                end
            else
                warn(LOG_PREFIX, "多次请求货币数据失败，客户端可能显示不正确的金币数")
                responseConnection:Disconnect()
            end
        end
    end)

    if DEBUG_MODE then
        print(LOG_PREFIX, "初始化完成,已连接货币变化事件和GUI重建监听")
    end

    return true
end

-- ==================== 公共接口(调试用) ====================

--[[
手动更新金币显示(调试用)
@param amount number - 金币数量
@param useAnimation boolean - 是否使用动画（可选）
]]
local function DebugSetCoins(amount, useAnimation)
    if DEBUG_MODE then
        print(LOG_PREFIX, "[调试] 手动设置金币:", amount)
    end
    UpdateCoinDisplay(amount, useAnimation)
end

-- 导出调试函数到全局(仅调试模式)
if DEBUG_MODE then
    _G.DebugSetCoins = DebugSetCoins
    _G.GetCurrentCoins = function()
        return currentCoins
    end
end

-- ==================== 启动 ====================

-- 尝试初始化
local success, errorMsg = pcall(Initialize)

if not success then
    warn(LOG_PREFIX, "初始化失败:", errorMsg)
else
    if DEBUG_MODE then
        print(LOG_PREFIX, "金币显示系统运行中...")
    end
end
