--[[
脚本名称: BackpackDisplay
脚本类型: LocalScript (客户端)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/BackpackDisplay
]]

--[[
背包显示控制器
职责:
1. 显示玩家背包中的兵种列表
2. 监听服务端背包更新事件
3. 动态创建和更新兵种条目UI
4. 处理关闭按钮点击
]]

-- 等待玩家和GUI加载
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("[BackpackDisplay] 正在加载...")

-- 等待背包UI加载
local backpackGui = playerGui:WaitForChild("BackpackGui", 10)
if not backpackGui then
    warn("[BackpackDisplay] 错误: 找不到BackpackGui! 请确保StarterGui中存在BackpackGui")
    warn("[BackpackDisplay] 请参考BackpackUI创建指南.lua创建UI")
    return
end

print("[BackpackDisplay] 找到BackpackGui")

local backpackFrame = backpackGui:WaitForChild("BackpackFrame", 5)
if not backpackFrame then
    warn("[BackpackDisplay] 错误: 找不到BackpackFrame!")
    return
end

print("[BackpackDisplay] 找到BackpackFrame")

local closeButton = backpackFrame:WaitForChild("CloseButton", 5)
local itemListFrame = backpackFrame:WaitForChild("ItemListFrame", 5)

if not closeButton or not itemListFrame then
    warn("[BackpackDisplay] 错误: UI组件缺失!")
    return
end

print("[BackpackDisplay] UI组件加载完成")

-- 确保背包默认可见
backpackFrame.Visible = true
print("[BackpackDisplay] 背包UI已设置为可见")

-- 获取远程事件
local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
local inventoryEvents = eventsFolder and eventsFolder:WaitForChild("InventoryEvents", 10)

-- ==================== 配置 ====================

-- 兵种条目高度
local ITEM_HEIGHT = 50
-- 兵种条目样式
local ITEM_BG_COLOR = Color3.fromRGB(50, 50, 50)
local ITEM_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local COUNT_TEXT_COLOR = Color3.fromRGB(100, 200, 255)

-- ==================== 私有变量 ====================

-- 存储已创建的UI条目 [unitId] = Frame
local itemFrames = {}

-- ==================== 私有函数 ====================

--[[
创建一个兵种条目UI
@param unitId string - 兵种ID
@param unitName string - 兵种名称
@param count number - 数量
@return Frame - 创建的条目Frame
]]
local function CreateItemFrame(unitId, unitName, count)
    -- 创建主框架
    local itemFrame = Instance.new("Frame")
    itemFrame.Name = "Item_" .. unitId
    itemFrame.Size = UDim2.new(1, -10, 0, ITEM_HEIGHT)
    itemFrame.BackgroundColor3 = ITEM_BG_COLOR
    itemFrame.BorderSizePixel = 0
    itemFrame.Parent = itemListFrame

    -- 添加圆角
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = itemFrame

    -- 创建名称标签
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(0.7, 0, 1, 0)
    nameLabel.Position = UDim2.new(0, 10, 0, 0)
    nameLabel.Text = unitName
    nameLabel.TextSize = 16
    nameLabel.TextColor3 = ITEM_TEXT_COLOR
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Font = Enum.Font.SourceSans
    nameLabel.BackgroundTransparency = 1
    nameLabel.Parent = itemFrame

    -- 创建数量标签
    local countLabel = Instance.new("TextLabel")
    countLabel.Name = "CountLabel"
    countLabel.Size = UDim2.new(0.25, 0, 1, 0)
    countLabel.Position = UDim2.new(0.75, 0, 0, 0)
    countLabel.Text = "x" .. count
    countLabel.TextSize = 16
    countLabel.TextColor3 = COUNT_TEXT_COLOR
    countLabel.TextXAlignment = Enum.TextXAlignment.Right
    countLabel.Font = Enum.Font.SourceSansBold
    countLabel.BackgroundTransparency = 1
    countLabel.Parent = itemFrame

    return itemFrame
end

--[[
更新指定兵种的UI显示
@param unitId string - 兵种ID
@param unitName string - 兵种名称
@param count number - 数量
]]
local function UpdateItemDisplay(unitId, unitName, count)
    local itemFrame = itemFrames[unitId]

    if count > 0 then
        -- 如果数量大于0，更新或创建UI
        if itemFrame then
            -- 更新现有条目
            local countLabel = itemFrame:FindFirstChild("CountLabel")
            if countLabel then
                countLabel.Text = "x" .. count
            end
        else
            -- 创建新条目
            itemFrame = CreateItemFrame(unitId, unitName, count)
            itemFrames[unitId] = itemFrame
        end
    else
        -- 如果数量为0，删除UI
        if itemFrame then
            itemFrame:Destroy()
            itemFrames[unitId] = nil
        end
    end
end

--[[
刷新整个背包显示
@param inventoryData table - 背包数据 {[unitId] = {Name, Count}}
]]
local function RefreshInventory(inventoryData)
    -- 清空现有UI
    for _, frame in pairs(itemFrames) do
        frame:Destroy()
    end
    itemFrames = {}

    -- 重新创建所有条目
    if inventoryData then
        for unitId, data in pairs(inventoryData) do
            if data.Count > 0 then
                local frame = CreateItemFrame(unitId, data.Name, data.Count)
                itemFrames[unitId] = frame
            end
        end
    end
end

-- ==================== 事件处理 ====================

-- 关闭按钮点击事件
closeButton.MouseButton1Click:Connect(function()
    backpackFrame.Visible = false
end)

-- 监听背包更新事件
if inventoryEvents then
    print("[BackpackDisplay] 找到InventoryEvents，正在连接事件...")

    -- 监听单个兵种更新
    local unitUpdatedEvent = inventoryEvents:FindFirstChild("UnitUpdated")
    if unitUpdatedEvent then
        print("[BackpackDisplay] 找到UnitUpdated事件，正在连接...")
        unitUpdatedEvent.OnClientEvent:Connect(function(unitId, unitName, count)
            print(string.format("[BackpackDisplay] 收到兵种更新: %s (%s) 数量: %d", unitName, unitId, count))
            UpdateItemDisplay(unitId, unitName, count)
        end)
        print("[BackpackDisplay] UnitUpdated事件已连接")
    else
        warn("[BackpackDisplay] 找不到UnitUpdated事件!")
    end

    -- 监听完整背包刷新
    local inventoryRefreshEvent = inventoryEvents:FindFirstChild("InventoryRefresh")
    if inventoryRefreshEvent then
        print("[BackpackDisplay] 找到InventoryRefresh事件，正在连接...")
        inventoryRefreshEvent.OnClientEvent:Connect(function(inventoryData)
            print("[BackpackDisplay] 收到背包刷新数据")
            for unitId, data in pairs(inventoryData or {}) do
                print(string.format("[BackpackDisplay]   - %s: %s x%d", unitId, data.Name, data.Count))
            end
            RefreshInventory(inventoryData)
        end)
        print("[BackpackDisplay] InventoryRefresh事件已连接")
    else
        warn("[BackpackDisplay] 找不到InventoryRefresh事件!")
    end

    -- 请求初始背包数据
    print("[BackpackDisplay] 等待0.5秒后请求背包数据...")
    task.wait(0.5)
    local requestEvent = inventoryEvents:FindFirstChild("RequestInventory")
    if requestEvent then
        print("[BackpackDisplay] 发送背包数据请求...")
        requestEvent:FireServer()
        print("[BackpackDisplay] 背包数据请求已发送")
    else
        warn("[BackpackDisplay] 找不到RequestInventory事件!")
    end
else
    warn("[BackpackDisplay] 找不到InventoryEvents!")
end

-- ==================== 快捷键设置 ====================

-- 监听键盘输入 - 按B键切换背包显示
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    -- 如果正在输入文字(聊天/文本框),忽略
    if gameProcessed then
        return
    end

    -- 按B键切换背包
    if input.KeyCode == Enum.KeyCode.B then
        backpackFrame.Visible = not backpackFrame.Visible
        print("[BackpackDisplay] 背包切换:", backpackFrame.Visible and "显示" or "隐藏")
    end
end)

-- ==================== 调试命令 ====================

-- 全局函数用于切换背包显示
_G.ToggleBackpack = function()
    backpackFrame.Visible = not backpackFrame.Visible
end

print("[BackpackDisplay] 背包显示控制器已加载")
print("[BackpackDisplay] 按 B 键切换背包显示")
print("[BackpackDisplay] 或使用 _G.ToggleBackpack() 切换(客户端控制台)")
