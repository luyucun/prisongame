--[[
脚本名称: BattleControlVisibility
脚本类型: LocalScript
脚本位置: StarterPlayer/StarterPlayerScripts/UI/BattleControlVisibility
功能描述: 根据地板上的兵种数量控制战斗按钮的显示/隐藏
版本: V3.9.1
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 等待UI加载
local mainGui = playerGui:WaitForChild("MainGui")
local battleControl = mainGui:WaitForChild("BattleControl")

-- 等待事件
local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local inventoryEvents = eventsFolder:WaitForChild("InventoryEvents")
local inventoryRefresh = inventoryEvents:WaitForChild("InventoryRefresh")

-- 日志前缀
local LOG_PREFIX = "[BattleControlVisibility]"

-- 当前地板上的兵种数量
local placedUnitCount = 0

--[[
    更新战斗按钮的显示状态
]]
local function UpdateBattleControlVisibility()
    local shouldShow = placedUnitCount >= 1

    if battleControl.Visible ~= shouldShow then
        battleControl.Visible = shouldShow
        print(LOG_PREFIX, "战斗按钮显示状态更新:", shouldShow and "显示" or "隐藏", "| 兵种数量:", placedUnitCount)
    end
end

--[[
    计算地板上的兵种数量
    @param placedUnits table - 放置的兵种数据 {[instanceId] = unitData}
    @return number - 兵种数量
]]
local function CountPlacedUnits(placedUnits)
    if not placedUnits then
        return 0
    end

    local count = 0
    for instanceId, unitData in pairs(placedUnits) do
        if unitData and unitData.UnitId then
            count = count + 1
        end
    end

    return count
end

--[[
    处理背包刷新事件
    @param inventory table - 背包数据
    @param placedUnits table - 放置的兵种数据
]]
local function OnInventoryRefresh(inventory, placedUnits)
    -- 计算地板上的兵种数量
    local newCount = CountPlacedUnits(placedUnits)

    if newCount ~= placedUnitCount then
        placedUnitCount = newCount
        UpdateBattleControlVisibility()
    end
end

--[[
    初始化：请求当前背包数据
]]
local function Initialize()
    print(LOG_PREFIX, "初始化战斗按钮显示控制")

    -- 初始状态隐藏战斗按钮
    battleControl.Visible = false

    -- 监听背包刷新事件
    inventoryRefresh.OnClientEvent:Connect(OnInventoryRefresh)

    -- 请求初始数据
    local requestInventory = inventoryEvents:WaitForChild("RequestInventory")
    requestInventory:FireServer()

    print(LOG_PREFIX, "初始化完成，已请求背包数据")
end

-- 启动初始化
local success, err = pcall(Initialize)
if not success then
    warn(LOG_PREFIX, "初始化失败:", err)
end
