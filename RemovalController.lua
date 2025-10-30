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
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- 玩家引用
local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- 远程事件
local placementEvents = nil

-- UI引用
local playerGui = nil
local mainGui = nil

-- ==================== 回收状态 ====================
local removalState = {
    isRemovalMode = false,      -- 是否处于回收模式
    highlightedModel = nil,     -- 当前高光的模型
    createdHighlight = false,   -- 标记Highlight是否是我们创建的
    placedModels = {},          -- 客户端跟踪的已放置模型列表（用于计数）
    placedUnitCount = 0,        -- 已放置兵种计数（Bug修复：性能优化）
}

-- ==================== 初始化 ====================

--[[
初始化回收控制器
]]
function RemovalController.Initialize()
    print("[RemovalController] 正在初始化...")

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

    -- 连接服务端响应事件
    local removeResponseEvent = placementEvents:FindFirstChild("RemoveResponse")
    if removeResponseEvent then
        removeResponseEvent.OnClientEvent:Connect(OnRemoveResponse)
    end

    -- Bug修复：监听PlacementResponse来同步placedUnitCount
    local placementResponseEvent = placementEvents:FindFirstChild("PlacementResponse")
    if placementResponseEvent then
        placementResponseEvent.OnClientEvent:Connect(function(success, message, data)
            if success then
                -- 放置成功，增加计数
                removalState.placedUnitCount = removalState.placedUnitCount + 1
            end
        end)
    end

    -- 连接UI按钮
    ConnectUIButtons()

    -- 连接输入事件（点击检测）
    ConnectInputEvents()

    print("[RemovalController] 初始化完成")
    return true
end

-- ==================== UI按钮连接 ====================

--[[
连接UI按钮事件
]]
function ConnectUIButtons()
    -- 连接Remove按钮
    local removeButton = mainGui:FindFirstChild("Remove")
    if removeButton then
        removeButton.MouseButton1Click:Connect(function()
            RemovalController.EnterRemovalMode()
        end)
        print("[RemovalController] 已连接Remove按钮")
    else
        warn("[RemovalController] 找不到Remove按钮!")
    end

    -- 连接Exit按钮
    local exitButton = mainGui:FindFirstChild("Exit")
    if exitButton then
        exitButton.MouseButton1Click:Connect(function()
            RemovalController.ExitRemovalMode()
        end)
        print("[RemovalController] 已连接Exit按钮")
    else
        warn("[RemovalController] 找不到Exit按钮!")
    end
end

-- ==================== 回收模式管理 ====================

--[[
进入回收模式
]]
function RemovalController.EnterRemovalMode()
    if removalState.isRemovalMode then
        return
    end

    print("[RemovalController] 进入回收模式")
    removalState.isRemovalMode = true

    -- 更新UI显示
    UpdateUIForRemovalMode(true)

    -- 确保背包显示（Bug修复：不是toggle而是确保打开）
    local backpackGui = playerGui:FindFirstChild("BackpackGui")
    if backpackGui and not backpackGui.Enabled then
        backpackGui.Enabled = true
    end
end

--[[
退出回收模式
]]
function RemovalController.ExitRemovalMode()
    if not removalState.isRemovalMode then
        return
    end

    print("[RemovalController] 退出回收模式")
    removalState.isRemovalMode = false

    -- 清除高光
    ClearHighlight()

    -- 更新UI显示
    UpdateUIForRemovalMode(false)

    -- 确保背包隐藏（Bug修复：不是toggle而是确保关闭）
    local backpackGui = playerGui:FindFirstChild("BackpackGui")
    if backpackGui and backpackGui.Enabled then
        backpackGui.Enabled = false
    end
end

--[[
检查是否处于回收模式（供其他模块调用）
@return boolean
]]
function RemovalController.IsRemovalMode()
    return removalState.isRemovalMode
end

-- ==================== UI更新 ====================

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
        local removeTips = mainGui:FindFirstChild("RemoveTips")
        if removeTips then
            removeTips.Visible = true
        end

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

        local removeButton = mainGui:FindFirstChild("Remove")
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

        local removeButton = mainGui:FindFirstChild("Remove")
        if removeButton then
            removeButton.Visible = true
        end

        -- 隐藏：RemoveTips, Exit
        local removeTips = mainGui:FindFirstChild("RemoveTips")
        if removeTips then
            removeTips.Visible = false
        end

        local exitButton = mainGui:FindFirstChild("Exit")
        if exitButton then
            exitButton.Visible = false
        end
    end
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
        print("[RemovalController] 未点击到任何模型")
        return
    end

    -- 获取instanceId（从模型的属性中获取）
    local instanceId = targetModel:GetAttribute("InstanceId")
    if not instanceId then
        warn("[RemovalController] 模型没有InstanceId属性:", targetModel.Name)
        return
    end

    print("[RemovalController] 请求回收兵种:", instanceId)

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
        print("[RemovalController] 回收成功:", instanceId)

        -- 清除高光
        ClearHighlight()

        -- Bug修复：减少计数器
        removalState.placedUnitCount = math.max(0, removalState.placedUnitCount - 1)

        -- 检查场中是否还有兵种
        if removalState.placedUnitCount == 0 then
            print("[RemovalController] 场中无兵种，自动退出回收模式")
            RemovalController.ExitRemovalMode()
        end
    else
        warn("[RemovalController] 回收失败:", message)
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

-- ==================== 全局访问 ====================

-- 提供全局访问接口
_G.RemovalController = RemovalController

-- 自动初始化
task.spawn(function()
    task.wait(1.5)  -- 等待其他系统加载
    RemovalController.Initialize()
end)

return RemovalController
