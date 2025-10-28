--[[
脚本名称: CoinDisplay
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/CoinDisplay
]]

--[[
金币显示控制器
职责:
1. 监听服务端的货币变化事件
2. 实时更新UI显示玩家金币数量
3. 使用格式化工具显示金币($XXXXX格式)
]]

-- 等待必要的服务和对象加载
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- 调试模式和日志前缀(必须在最前面定义)
local DEBUG_MODE = true
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
获取或刷新UI引用
@return boolean - 是否成功获取UI引用
]]
local function RefreshUIReferences()
    -- 尝试获取MainGui
    if not MainGui or not MainGui.Parent then
        MainGui = PlayerGui:FindFirstChild("MainGui")

        if not MainGui then
            if DEBUG_MODE then
                warn(LOG_PREFIX, "MainGui未找到,等待重建...")
            end
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
            if DEBUG_MODE then
                warn(LOG_PREFIX, "CoinNum未找到,等待重建...")
            end
            return false
        end

        if DEBUG_MODE then
            print(LOG_PREFIX, "CoinNumLabel引用已刷新")
        end
    end

    return true
end

--[[
更新金币显示
@param amount number - 新的金币数量
]]
local function UpdateCoinDisplay(amount)
    -- 验证金币数量
    if type(amount) ~= "number" then
        warn(LOG_PREFIX, "金币数量必须是数字:", amount)
        return
    end

    -- 更新缓存
    currentCoins = amount

    -- 刷新UI引用
    if not RefreshUIReferences() then
        warn(LOG_PREFIX, "UI引用无效,无法更新显示")
        return
    end

    -- 格式化并更新显示
    local formattedText = FormatHelper.FormatCoins(amount)
    CoinNumLabel.Text = formattedText

    if DEBUG_MODE then
        print(LOG_PREFIX, "更新金币显示:", amount, "->", formattedText)
    end
end

--[[
处理货币变化事件
@param currencyType string - 货币类型
@param newAmount number - 新的货币数量
]]
local function OnCurrencyChanged(currencyType, newAmount)
    if DEBUG_MODE then
        print(LOG_PREFIX, "收到货币变化事件:", currencyType, newAmount)
    end

    -- 目前只处理金币
    if currencyType == "Coins" then
        UpdateCoinDisplay(newAmount)
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
    if not RefreshUIReferences() then
        warn(LOG_PREFIX, "初始UI引用获取失败,将在后续尝试")
    end

    if not CurrencyEvents then
        warn(LOG_PREFIX, "错误: 找不到CurrencyEvents!")
        warn(LOG_PREFIX, "请确保ReplicatedStorage/Events中存在CurrencyEvents")
        return false
    end

    -- 设置初始显示
    UpdateCoinDisplay(0)

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

            -- 刷新引用并更新显示
            if RefreshUIReferences() then
                UpdateCoinDisplay(currentCoins)
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

    -- 向服务端请求当前金币数量(延迟请求以确保服务端已初始化)
    task.delay(1, function()
        local requestSuccess, requestError = pcall(function()
            CurrencyEvents:FireServer()
        end)

        if not requestSuccess then
            warn(LOG_PREFIX, "请求货币数据失败:", requestError)
        elseif DEBUG_MODE then
            print(LOG_PREFIX, "已向服务端请求货币数据")
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
]]
local function DebugSetCoins(amount)
    if DEBUG_MODE then
        print(LOG_PREFIX, "[调试] 手动设置金币:", amount)
    end
    UpdateCoinDisplay(amount)
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
