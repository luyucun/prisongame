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

-- 确保背包默认关闭
backpackGui.Enabled = false
print("[BackpackDisplay] 背包UI已设置为默认关闭")

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

-- 存储背包实例数据 [unitId] = {Name, Count, Instances}
local inventoryDataCache = {}

-- ==================== 私有函数 ====================

--[[
处理兵种条目点击
@param unitId string
@param unitName string
]]
local function OnUnitItemClicked(unitId, unitName)
    print("[BackpackDisplay] 点击兵种:", unitName, unitId)

    -- 调试：打印缓存内容
    print("[BackpackDisplay] inventoryDataCache:", inventoryDataCache)
    if inventoryDataCache[unitId] then
        print("[BackpackDisplay] unitData存在")
        print("[BackpackDisplay] unitData.Instances:", inventoryDataCache[unitId].Instances)
        if inventoryDataCache[unitId].Instances then
            print("[BackpackDisplay] Instances数量:", #inventoryDataCache[unitId].Instances)
        end
    else
        print("[BackpackDisplay] unitData不存在!")
    end

    -- 关闭背包UI
    backpackGui.Enabled = false

    -- 从缓存中获取第一个未放置的实例
    local unitData = inventoryDataCache[unitId]
    if unitData and unitData.Instances then
        for _, instanceInfo in ipairs(unitData.Instances) do
            if not instanceInfo.IsPlaced then
                -- 调用PlacementController开始放置
                if _G.PlacementController then
                    print("[BackpackDisplay] 开始放置实例:", instanceInfo.InstanceId)
                    _G.PlacementController.StartPlacement(
                        instanceInfo.InstanceId,
                        unitId,
                        instanceInfo.GridSize
                    )
                else
                    warn("[BackpackDisplay] PlacementController未找到!")
                end
                return
            end
        end
    else
        -- 如果没有实例数据，重新请求背包数据并延迟重试
        print("[BackpackDisplay] 没有实例数据，请求刷新背包...")
        local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
        if eventsFolder then
            local inventoryEvents = eventsFolder:FindFirstChild("InventoryEvents")
            if inventoryEvents then
                local requestEvent = inventoryEvents:FindFirstChild("RequestInventory")
                if requestEvent then
                    requestEvent:FireServer()
                    -- 等待一小段时间让数据刷新
                    task.wait(0.1)
                    -- 重新尝试
                    local updatedUnitData = inventoryDataCache[unitId]
                    if updatedUnitData and updatedUnitData.Instances then
                        for _, instanceInfo in ipairs(updatedUnitData.Instances) do
                            if not instanceInfo.IsPlaced then
                                if _G.PlacementController then
                                    print("[BackpackDisplay] 重试：开始放置实例:", instanceInfo.InstanceId)
                                    _G.PlacementController.StartPlacement(
                                        instanceInfo.InstanceId,
                                        unitId,
                                        instanceInfo.GridSize
                                    )
                                end
                                return
                            end
                        end
                    end
                end
            end
        end
    end

    warn("[BackpackDisplay] 没有可放置的", unitName, "实例")
end

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

    -- 创建名称和数量标签（合并显示）
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, -20, 1, 0)
    nameLabel.Position = UDim2.new(0, 10, 0, 0)
    nameLabel.Text = unitName .. "*" .. count
    nameLabel.TextSize = 16
    nameLabel.TextColor3 = ITEM_TEXT_COLOR
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Font = Enum.Font.SourceSans
    nameLabel.BackgroundTransparency = 1
    nameLabel.Parent = itemFrame

    -- 创建点击按钮（透明覆盖整个Frame）
    local clickButton = Instance.new("TextButton")
    clickButton.Name = "ClickButton"
    clickButton.Size = UDim2.new(1, 0, 1, 0)
    clickButton.Position = UDim2.new(0, 0, 0, 0)
    clickButton.BackgroundTransparency = 1
    clickButton.Text = ""
    clickButton.Parent = itemFrame

    -- 存储unitId到按钮
    clickButton:SetAttribute("UnitId", unitId)

    -- 点击事件
    clickButton.MouseButton1Click:Connect(function()
        OnUnitItemClicked(unitId, unitName)
    end)

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
            local nameLabel = itemFrame:FindFirstChild("NameLabel")
            if nameLabel then
                nameLabel.Text = unitName .. "*" .. count
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
@param inventoryData table - 背包数据 {[unitId] = {Name, Count, Instances}}
]]
local function RefreshInventory(inventoryData)
    print("[BackpackDisplay] RefreshInventory 被调用")

    -- 调试：打印收到的数据
    if inventoryData then
        for unitId, data in pairs(inventoryData) do
            print(string.format("[BackpackDisplay] RefreshInventory - %s: Count=%d, HasInstances=%s",
                unitId,
                data.Count or 0,
                data.Instances and "是" or "否"
            ))
            if data.Instances then
                print(string.format("[BackpackDisplay] RefreshInventory - %s 有 %d 个实例", unitId, #data.Instances))
            end
        end
    else
        print("[BackpackDisplay] RefreshInventory - inventoryData 为 nil")
    end

    -- 清空现有UI
    for _, frame in pairs(itemFrames) do
        frame:Destroy()
    end
    itemFrames = {}

    -- 缓存背包数据
    inventoryDataCache = inventoryData or {}
    print("[BackpackDisplay] inventoryDataCache 已更新")

    -- 重新创建所有条目
    if inventoryData then
        for unitId, data in pairs(inventoryData) do
            -- 只显示未放置的兵种数量
            local availableCount = 0
            if data.Instances then
                for _, instance in ipairs(data.Instances) do
                    if not instance.IsPlaced then
                        availableCount = availableCount + 1
                    end
                end
            else
                availableCount = data.Count
            end

            if availableCount > 0 then
                local frame = CreateItemFrame(unitId, data.Name, availableCount)
                itemFrames[unitId] = frame
            end
        end
    end
end

-- ==================== 事件处理 ====================

-- 关闭按钮点击事件
closeButton.MouseButton1Click:Connect(function()
    backpackGui.Enabled = false
    print("[BackpackDisplay] 背包已关闭")
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
        backpackGui.Enabled = not backpackGui.Enabled
        print("[BackpackDisplay] 背包切换:", backpackGui.Enabled and "显示" or "隐藏")
    end
end)

-- ==================== 调试命令 ====================

-- 全局函数用于切换背包显示
_G.ToggleBackpack = function()
    backpackGui.Enabled = not backpackGui.Enabled
    print("[BackpackDisplay] 背包切换:", backpackGui.Enabled and "显示" or "隐藏")
end

print("[BackpackDisplay] 背包显示控制器已加载")
print("[BackpackDisplay] 按 B 键切换背包显示")
print("[BackpackDisplay] 或使用 _G.ToggleBackpack() 切换(客户端控制台)")
