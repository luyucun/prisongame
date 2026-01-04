--[[
脚本名称: RemovalController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/RemovalController
]]

--[[
兵种回收控制器 (V1.3)
职责:
1. 管理回收模式状态
2. 处理Remove/Exit按钮点击
3. 处理点击已放置兵种进行回收
4. 控制UI显示/隐藏切换
5. 检测场中兵种数量，自动退出回收模式
]]

local RemovalController = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local DEBUG_MODE = GameConfig.DEBUG_MODE
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- 玩家引用
local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- 远程事件
local placementEvents = nil
local inventoryEvents = nil

-- UI引用
local playerGui = nil
local mainGui = nil
local removeButton = nil
local removeAllButton = nil
local removeTips = nil
local removeTipsBreathTween = nil
local removeTipsDefaults = nil
local ButtonEffectHelper = nil

-- ==================== 回收状态 ====================
local removalState = {
    isRemovalMode = false,      -- 是否处于回收模式
    isEnabled = true,           -- 是否允许回收（战斗中会被锁定）
    isOnIdleFloor = false,      -- 玩家是否站在IdleFloor上
    highlightedModel = nil,     -- 当前高光的模型
    createdHighlight = false,   -- 标记Highlight是否是我们创建的
    placedModels = {},          -- 客户端跟踪的已放置模型列表（用于计数）
    placedUnitCount = 0,        -- 已放置兵种计数（Bug修复：性能优化）
}

-- ==================== UI显示辅助（提前定义，供初始化阶段调用） ====================

local function ShouldShowRemoveButton()
    if not removeButton then
        return false
    end

    if removalState.isRemovalMode then
        return false
    end

    if not removalState.isEnabled then
        return false
    end

    if removalState.placedUnitCount <= 0 then
        return false
    end

    return removalState.isOnIdleFloor
end

local function IsTextObject(obj)
    return obj and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox"))
end

local function GetRemoveTips()
    if removeTips and removeTips.Parent then
        return removeTips
    end
    if not mainGui then
        return nil
    end
    removeTips = mainGui:FindFirstChild("RemoveTips")
    if removeTips and IsTextObject(removeTips) and not removeTipsDefaults then
        removeTipsDefaults = {
            TextTransparency = removeTips.TextTransparency,
            TextStrokeTransparency = removeTips.TextStrokeTransparency,
        }
    end
    return removeTips
end

local function StopRemoveTipsBreath()
    if removeTipsBreathTween then
        removeTipsBreathTween:Cancel()
        removeTipsBreathTween = nil
    end

    local tip = GetRemoveTips()
    if tip and removeTipsDefaults and IsTextObject(tip) then
        tip.TextTransparency = removeTipsDefaults.TextTransparency or 0
        tip.TextStrokeTransparency = removeTipsDefaults.TextStrokeTransparency or 0
    end
end

local function StartRemoveTipsBreath()
    local tip = GetRemoveTips()
    if not tip or not IsTextObject(tip) then
        return
    end

    if not removeTipsDefaults then
        removeTipsDefaults = {
            TextTransparency = tip.TextTransparency,
            TextStrokeTransparency = tip.TextStrokeTransparency,
        }
    end

    if removeTipsBreathTween then
        return
    end

    local baseText = removeTipsDefaults.TextTransparency or 0
    local baseStroke = removeTipsDefaults.TextStrokeTransparency or 0
    local targetText = math.clamp(baseText + 0.35, 0, 1)
    local targetStroke = math.clamp(baseStroke + 0.35, 0, 1)

    removeTipsBreathTween = TweenService:Create(
        tip,
        TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {
            TextTransparency = targetText,
            TextStrokeTransparency = targetStroke,
        }
    )
    removeTipsBreathTween:Play()
end

local function RefreshRemoveTipsVisibility()
    local tip = GetRemoveTips()
    if not tip then
        return
    end

    if removalState.isRemovalMode then
        tip.Visible = true
        StartRemoveTipsBreath()
        return
    end

    tip.Visible = false
    StopRemoveTipsBreath()
end

local function RefreshRemoveAllVisibility()
    if removeAllButton then
        removeAllButton.Visible = removalState.isRemovalMode
    end
end

local function RefreshRemoveButtonVisibility()
    if removeButton then
        removeButton.Visible = ShouldShowRemoveButton()
    end
    RefreshRemoveAllVisibility()
    RefreshRemoveTipsVisibility()
end

local function CountPlacedUnits(placedUnits)
    if not placedUnits then
        return 0
    end

    local count = 0
    for _, unitData in pairs(placedUnits) do
        if unitData and unitData.UnitId then
            count += 1
        end
    end

    return count
end

local function OnInventoryRefresh(inventory, placedUnits)
    local newCount = CountPlacedUnits(placedUnits)
    if newCount ~= removalState.placedUnitCount then
        removalState.placedUnitCount = newCount
    end

    if newCount <= 0 and removalState.isRemovalMode then
        RemovalController.ExitRemovalMode()
        return
    end

    RefreshRemoveButtonVisibility()
end

-- ==================== 初始化 ====================

--[[
初始化回收控制器
]]
function RemovalController.Initialize()
    -- 获取PlayerGui
    playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then
        warn("[RemovalController] 找不到PlayerGui!")
        return false
    end

    -- 获取MainGui
    mainGui = playerGui:WaitForChild("MainGui", 10)
    if not mainGui then
        warn("[RemovalController] 找不到MainGui!")
        return false
    end

    -- 获取远程事件
    local maxRetries = 10
    local retryCount = 0
    while not placementEvents and retryCount < maxRetries do
        local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
        if eventsFolder then
            placementEvents = eventsFolder:FindFirstChild("PlacementEvents")
        end
        if not placementEvents then
            task.wait(0.5)
            retryCount = retryCount + 1
        end
    end

    if not placementEvents then
        warn("[RemovalController] PlacementEvents未找到!")
        return false
    end

    -- 连接Inventory刷新事件（用于获取已放置兵种数量）
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if eventsFolder then
        inventoryEvents = eventsFolder:FindFirstChild("InventoryEvents")
    end

    if inventoryEvents then
        local inventoryRefreshEvent = inventoryEvents:FindFirstChild("InventoryRefresh")
        if inventoryRefreshEvent then
            inventoryRefreshEvent.OnClientEvent:Connect(OnInventoryRefresh)
        else
            warn("[RemovalController] InventoryRefresh未找到!")
        end

        local requestInventoryEvent = inventoryEvents:FindFirstChild("RequestInventory")
        if requestInventoryEvent then
            requestInventoryEvent:FireServer()
        end
    else
        warn("[RemovalController] InventoryEvents未找到!")
    end

    -- 连接服务端响应事件
    local removeResponseEvent = placementEvents:FindFirstChild("RemoveResponse")
    if removeResponseEvent then
        removeResponseEvent.OnClientEvent:Connect(OnRemoveResponse)
    end

    -- Bug修复：监听PlacementResponse来同步placedUnitCount
    local placementResponseEvent = placementEvents:FindFirstChild("PlacementResponse")
    if placementResponseEvent then
        placementResponseEvent.OnClientEvent:Connect(function(success, message, data)
            if success and data == nil then
                -- 确认放置成功时增加计数（开始放置会带data）
                removalState.placedUnitCount = removalState.placedUnitCount + 1
                RefreshRemoveButtonVisibility()
            end
        end)
    end

    -- 连接UI按钮
    ConnectUIButtons()

    -- 连接输入事件（点击检测）
    ConnectInputEvents()

    -- 初始化时刷新Remove显隐（受IdleFloor/战斗状态影响）
    RefreshRemoveButtonVisibility()

    return true
end

local function LoadButtonEffectHelper()
    if ButtonEffectHelper then
        return true
    end

    local success, result = pcall(function()
        return require(game:GetService("StarterPlayer").StarterPlayerScripts.Utils.ButtonEffectHelper)
    end)

    if success then
        ButtonEffectHelper = result
        return true
    end

    warn("[RemovalController] ButtonEffectHelper加载失败:", result)
    return false
end

local function BindButtonClick(button, onClick)
    if not button then
        return
    end

    if LoadButtonEffectHelper() and ButtonEffectHelper then
        ButtonEffectHelper.AddClickEffect(button, { OnClick = onClick })
    else
        button.MouseButton1Click:Connect(onClick)
    end
end

-- ==================== UI按钮连接 ====================

--[[
连接UI按钮事件
]]
function ConnectUIButtons()
    -- 连接Remove按钮
    removeButton = mainGui:FindFirstChild("Remove")
    if removeButton then
        BindButtonClick(removeButton, function()
            RemovalController.EnterRemovalMode()
        end)
    else
        warn("[RemovalController] 找不到Remove按钮!")
    end

    -- 连接Exit按钮
    local exitButton = mainGui:FindFirstChild("Exit")
    if exitButton then
        BindButtonClick(exitButton, function()
            RemovalController.ExitRemovalMode()
        end)
    else
        warn("[RemovalController] 找不到Exit按钮!")
    end

    -- 连接RemoveAll按钮
    removeAllButton = mainGui:FindFirstChild("RemoveAll")
    if removeAllButton then
        BindButtonClick(removeAllButton, function()
            if not removalState.isRemovalMode or not removalState.isEnabled then
                return
            end

            if placementEvents then
                local removeAllEvent = placementEvents:FindFirstChild("RemoveAllUnits")
                if removeAllEvent then
                    removeAllEvent:FireServer()
                else
                    warn("[RemovalController] 找不到RemoveAllUnits事件!")
                end
            end

            RemovalController.ExitRemovalMode()
        end)
    else
        warn("[RemovalController] 找不到RemoveAll按钮!")
    end

    RefreshRemoveAllVisibility()
end

-- ==================== 回收模式管理 ====================

--[[
进入回收模式
]]
function RemovalController.EnterRemovalMode()
    if removalState.isRemovalMode then
        return
    end

    -- 战斗锁定或不在IdleFloor时禁止进入回收模式
    if not removalState.isEnabled or not removalState.isOnIdleFloor then
        return
    end

    removalState.isRemovalMode = true

    -- 更新UI显示
    UpdateUIForRemovalMode(true)

    -- V2.0.2修复：调用BackpackDisplay接口而非直接修改Enabled
    if _G.BackpackDisplay and _G.BackpackDisplay.ShowBackpack then
        _G.BackpackDisplay.ShowBackpack()
    else
        -- 兜底方案：直接控制BackpackFrame.Visible
        local backpackGui = playerGui:FindFirstChild("BackpackGui")
        if backpackGui then
            backpackGui.Enabled = true
            local backpackFrame = backpackGui:FindFirstChild("BackpackFrame")
            if backpackFrame then
                backpackFrame.Visible = true
            end
        end
    end
end

--[[
退出回收模式
]]
function RemovalController.ExitRemovalMode()
    if not removalState.isRemovalMode then
        return
    end

    removalState.isRemovalMode = false

    -- 清除高光
    ClearHighlight()

    -- 更新UI显示
    UpdateUIForRemovalMode(false)

    -- V2.1修复：退出回收模式时不再隐藏背包
    -- 让背包的显示控制交给原有的 IdleFloor 触发逻辑
    -- 原来的逻辑：调用 _G.BackpackDisplay.HideBackpack() 或直接设置 Visible = false
    -- 现在：移除这部分逻辑，只退出移除流程，不触碰背包显示
end

--[[
检查是否处于回收模式（供其他模块调用）
@return boolean
]]
function RemovalController.IsRemovalMode()
    return removalState.isRemovalMode
end

--[[
更新UI显示状态
@param isRemovalMode boolean - 是否为回收模式
]]
function UpdateUIForRemovalMode(isRemovalMode)
    if not mainGui then
        return
    end

    if isRemovalMode then
        -- 进入回收模式
        -- 显示：RemoveTips, Exit
        local exitButton = mainGui:FindFirstChild("Exit")
        if exitButton then
            exitButton.Visible = true
        end

        -- 隐藏：Start, CoinNum, Remove
        local startButton = mainGui:FindFirstChild("Start")
        if startButton then
            startButton.Visible = false
        end

        local coinNum = mainGui:FindFirstChild("CoinNum")
        if coinNum then
            coinNum.Visible = false
        end

        if removeButton then
            removeButton.Visible = false
        end
    else
        -- 退出回收模式
        -- 显示：Start, CoinNum, Remove
        local startButton = mainGui:FindFirstChild("Start")
        if startButton then
            startButton.Visible = true
        end

        local coinNum = mainGui:FindFirstChild("CoinNum")
        if coinNum then
            coinNum.Visible = true
        end

        -- Remove按钮显隐由状态控制
        RefreshRemoveButtonVisibility()

        -- 隐藏：RemoveTips, Exit
        local exitButton = mainGui:FindFirstChild("Exit")
        if exitButton then
            exitButton.Visible = false
        end
    end

    RefreshRemoveAllVisibility()
    RefreshRemoveTipsVisibility()
end

-- ==================== 点击检测 ====================

--[[
连接输入事件
]]
function ConnectInputEvents()
    -- PC端：鼠标点击
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end

        if not removalState.isRemovalMode then
            return
        end

        -- 左键点击
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            OnClickInRemovalMode()
        end
    end)

    -- 移动端：触摸点击
    UserInputService.TouchTap:Connect(function(touchPositions, gameProcessed)
        if gameProcessed then
            return
        end

        if not removalState.isRemovalMode then
            return
        end

        -- Bug修复：使用实际触摸位置进行点击检测
        OnClickInRemovalMode(touchPositions[1])
    end)

    -- 实时检测鼠标悬停（用于高光预览）
    RunService.RenderStepped:Connect(function()
        if not removalState.isRemovalMode then
            return
        end

        UpdateMouseHover()
    end)
end

--[[
处理回收模式下的点击
@param touchPosition Vector2|nil - 移动端触摸位置（可选）
]]
function OnClickInRemovalMode(touchPosition)
    local targetModel = GetTargetModel(touchPosition)
    if not targetModel then
        return
    end

    -- 获取instanceId（从模型的属性中获取）
    local instanceId = targetModel:GetAttribute("InstanceId")
    if not instanceId then
        warn("[RemovalController] 模型没有InstanceId属性:", targetModel.Name)
        return
    end

    -- 发送回收请求到服务端
    if placementEvents then
        local removeEvent = placementEvents:FindFirstChild("RemoveUnit")
        if removeEvent then
            removeEvent:FireServer(instanceId)
        else
            warn("[RemovalController] 找不到RemoveUnit事件!")
        end
    end
end

--[[
更新鼠标悬停高光
]]
function UpdateMouseHover()
    local targetModel = GetTargetModel()

    if targetModel ~= removalState.highlightedModel then
        -- 清除旧高光
        ClearHighlight()

        -- 应用新高光
        if targetModel then
            ApplyHighlight(targetModel)
            removalState.highlightedModel = targetModel
        end
    end
end

--[[
获取鼠标/触摸指向的模型
@param touchPosition Vector2|nil - 移动端触摸位置（可选）
@return Model|nil
]]
function GetTargetModel(touchPosition)
    -- 创建射线
    local ray = nil

    -- Bug修复：移动端使用实际触摸位置而不是屏幕中心
    if touchPosition then
        -- 移动端：使用触摸位置
        ray = workspace.CurrentCamera:ViewportPointToRay(touchPosition.X, touchPosition.Y)
    else
        -- PC端：使用鼠标位置
        ray = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
    end

    -- 执行射线检测
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude  -- Bug修复：Blacklist已弃用，使用Exclude
    raycastParams.FilterDescendantsInstances = {player.Character}

    local raycastResult = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)

    if raycastResult then
        local hitPart = raycastResult.Instance
        -- 找到模型
        local model = hitPart:FindFirstAncestorOfClass("Model")

        -- 验证是否是已放置的兵种模型
        if model and IsPlacedUnit(model) then
            return model
        end
    end

    return nil
end

--[[
检查模型是否是已放置的兵种
@param model Model
@return boolean
]]
function IsPlacedUnit(model)
    -- Bug修复：只依赖InstanceId属性判断，避免误判
    return model:GetAttribute("InstanceId") ~= nil
end

--[[
应用红色高光到模型
@param model Model
]]
function ApplyHighlight(model)
    local highlight = model:FindFirstChild("Highlight")
    if highlight then
        -- 模型已有Highlight，直接修改颜色
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
        highlight.Enabled = true
        removalState.createdHighlight = false  -- 标记不是我们创建的
    else
        -- Bug修复：如果没有Highlight，创建一个并标记
        highlight = Instance.new("Highlight")
        highlight.Name = "Highlight"
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
        highlight.FillTransparency = 1
        highlight.OutlineTransparency = 0
        highlight.Parent = model
        removalState.createdHighlight = true  -- 标记是我们创建的
    end
end

--[[
清除当前高光
]]
function ClearHighlight()
    if removalState.highlightedModel then
        local highlight = removalState.highlightedModel:FindFirstChild("Highlight")
        if highlight then
            -- Bug修复：如果是我们创建的Highlight，删除它；否则只是disable
            if removalState.createdHighlight then
                highlight:Destroy()
            else
                highlight.Enabled = false
            end
        end
        removalState.highlightedModel = nil
        removalState.createdHighlight = false
    end
end

-- ==================== 服务端响应处理 ====================

--[[
处理服务端回收响应
@param success boolean
@param message string
@param instanceId string
]]
function OnRemoveResponse(success, message, instanceId)
    if success then
        -- 清除高光
        ClearHighlight()

        -- Bug修复：减少计数器
        removalState.placedUnitCount = math.max(0, removalState.placedUnitCount - 1)

        if removalState.placedUnitCount <= 0 and removalState.isRemovalMode then
            RemovalController.ExitRemovalMode()
            return
        end

        RefreshRemoveButtonVisibility()

        -- V4.9优化：场上无兵时自动退出回收模式
    else
        if DEBUG_MODE then
            warn("[RemovalController] 回收失败:", message)
        end
    end
end

--[[
检查场中是否还有已放置的兵种
@return boolean
]]
function HasAnyPlacedUnits()
    -- 遍历Workspace查找带有InstanceId属性的模型
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj:GetAttribute("InstanceId") then
            return true
        end
    end
    return false
end

-- ==================== 状态控制（战斗锁定 / IdleFloor监听）====================

-- 战斗期间锁定或解锁回收功能
function RemovalController.SetEnabled(enabled)
    removalState.isEnabled = enabled and true or false

    -- 禁用时退出回收模式并清理高光
    if not removalState.isEnabled then
        if removalState.isRemovalMode then
            RemovalController.ExitRemovalMode()
        else
            ClearHighlight()
        end
    end

    RefreshRemoveButtonVisibility()
end

-- IdleFloor站位变化回调
local function OnIdleFloorStateChanged(onFloor)
    removalState.isOnIdleFloor = onFloor and true or false

    if not removalState.isRemovalMode then
        RefreshRemoveButtonVisibility()
    end
end

local function BindBackpackTriggerIdleFloorListener()
    local timeoutSeconds = 10
    local startTime = os.clock()

    while os.clock() - startTime < timeoutSeconds do
        local backpackTrigger = _G.BackpackTrigger
        if backpackTrigger and backpackTrigger.SubscribeIdleFloorChanged then
            backpackTrigger.SubscribeIdleFloorChanged(OnIdleFloorStateChanged)
            if backpackTrigger.IsOnIdleFloor then
                OnIdleFloorStateChanged(backpackTrigger.IsOnIdleFloor())
            end
            return true
        end
        task.wait(0.2)
    end

    warn(string.format(
        "[RemovalController] 未找到BackpackTrigger的IdleFloor监听接口（等待%.1fs后仍未就绪），Remove按钮显隐可能不会随站位更新",
        timeoutSeconds
    ))
    return false
end

-- ==================== 全局访问 ====================

-- 提供全局访问接口
_G.RemovalController = RemovalController

-- 自动初始化
task.spawn(function()
    task.wait(1.5)  -- 等待其他系统加载
    RemovalController.Initialize()

    -- 订阅IdleFloor站位变化（依赖BackpackTrigger提供的接口）
    BindBackpackTriggerIdleFloorListener()
end)

return RemovalController
