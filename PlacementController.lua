--[[
脚本名称: PlacementController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/PlacementController
]]

--[[
兵种放置控制器
职责:
1. 处理PC端和移动端的放置交互
2. 管理放置预览模型
3. 实现网格吸附和边界限制
4. 与服务端通信完成放置
版本: V1.2
]]

local PlacementController = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- 引用工具模块
local PlacementHelper = require(script.Parent.Parent.Utils.PlacementHelper)
local HighlightHelper = require(script.Parent.Parent.Utils.HighlightHelper)
local GridHelper = require(script.Parent.Parent.Utils.GridHelper)  -- V1.2.1: 新增Grid管理

-- 玩家引用
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

-- 远程事件
local placementEvents = nil

-- ==================== 放置状态 ====================
local placementState = {
    isPlacing = false,           -- 是否正在放置
    previewModel = nil,          -- 预览模型
    currentInstanceId = nil,     -- 当前放置的实例ID
    currentUnitId = nil,         -- 当前兵种ID
    currentGridSize = 1,         -- 当前兵种占地大小
    idleFloor = nil,             -- 玩家的IdleFloor
    lastGridX = nil,             -- 上次的网格X
    lastGridZ = nil,             -- 上次的网格Z
    isMobile = false,            -- 是否为移动设备
    placedModels = {},           -- V1.2.1: 客户端跟踪已放置的模型 {model = {gridX, gridZ, gridSize}}
}

-- ==================== 初始化 ====================

--[[
初始化放置控制器
]]
function PlacementController.Initialize()
    -- 初始化GridHelper (V1.2.1)
    GridHelper.Initialize()

    -- 检测设备类型
    placementState.isMobile = PlacementHelper.IsMobileDevice()

    -- 多次尝试获取远程事件（避免时序问题）
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
        warn("[PlacementController] PlacementEvents未找到，放置功能将不可用!")
        return false
    end

    -- 连接服务端响应事件
    local responseEvent = placementEvents:FindFirstChild("PlacementResponse")
    if responseEvent then
        responseEvent.OnClientEvent:Connect(OnPlacementResponse)
    end

    -- 等待IdleFloor加载
    task.spawn(function()
        -- 等待玩家角色加载
        local character = player.Character or player.CharacterAdded:Wait()

        -- 再等待一段时间确保基地分配完成
        task.wait(2)

        placementState.idleFloor = FindPlayerIdleFloor()
        if not placementState.idleFloor then
            warn("[PlacementController] 找不到IdleFloor!")
        end
    end)

    -- 连接输入事件
    if placementState.isMobile then
        ConnectMobileInput()
    else
        ConnectPCInput()
    end

    return true
end

-- ==================== 查找IdleFloor ====================

--[[
查找玩家的IdleFloor
@return Part|nil
]]
function FindPlayerIdleFloor()
    -- 等待玩家角色加载
    local character = player.Character
    if not character then
        character = player.CharacterAdded:Wait()
    end

    if not character.PrimaryPart then
        task.wait(0.5)
        if not character.PrimaryPart then
            warn("[PlacementController] PrimaryPart加载失败")
            return nil
        end
    end

    local playerPos = character.PrimaryPart.Position

    local homeFolder = Workspace:FindFirstChild("Home")
    if not homeFolder then
        warn("[PlacementController] Home文件夹不存在")
        return nil
    end

    local nearestFloor = nil
    local nearestDistance = math.huge

    -- 找到距离最近的基地的IdleFloor
    for i = 1, 6 do
        local playerHome = homeFolder:FindFirstChild("PlayerHome" .. i)
        if playerHome then
            local idleFloor = playerHome:FindFirstChild("IdleFloor")
            if idleFloor then
                local distance = (idleFloor.Position - playerPos).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestFloor = idleFloor
                end
            end
        end
    end

    return nearestFloor
end

-- ==================== 公共接口 ====================

--[[
开始放置兵种
@param instanceId string - 兵种实例ID
@param unitId string - 兵种配置ID
@param gridSize number - 占地大小
]]
function PlacementController.StartPlacement(instanceId, unitId, gridSize)
    if placementState.isPlacing then
        PlacementController.CancelPlacement()
    end

    -- 如果还没有找到IdleFloor，立即查找一次
    if not placementState.idleFloor then
        placementState.idleFloor = FindPlayerIdleFloor()
    end

    if not placementState.idleFloor then
        warn("[PlacementController] IdleFloor不存在，无法放置")
        return
    end

    -- 更新状态
    placementState.isPlacing = true
    placementState.currentInstanceId = instanceId
    placementState.currentUnitId = unitId
    placementState.currentGridSize = gridSize or 1

    -- 克隆预览模型
    local previewModel = PlacementHelper.CloneUnitModel(unitId)
    if not previewModel then
        warn("[PlacementController] 无法创建预览模型")
        PlacementController.CancelPlacement()
        return
    end

    placementState.previewModel = previewModel
    previewModel.Parent = Workspace

    -- 设置预览模式
    HighlightHelper.SetPreviewMode(previewModel)

    -- 初始位置（PC端用鼠标，移动端用角色前方）
    if placementState.isMobile then
        -- 移动端：放在角色前方，但要限制在IdleFloor范围内
        local character = player.Character
        if character and character.PrimaryPart then
            local forwardPos = character.PrimaryPart.Position + character.PrimaryPart.CFrame.LookVector * 3
            -- 将位置投影到IdleFloor的Y轴上
            local floorY = placementState.idleFloor.Position.Y
            local initialPos = Vector3.new(forwardPos.X, floorY, forwardPos.Z)
            -- 通过吸附函数确保在范围内
            local floorCenter = placementState.idleFloor.Position
            local snappedPos = PlacementHelper.GetNearestGridPosition(initialPos, floorCenter, placementState.currentGridSize)
            UpdatePreviewPosition(snappedPos)
        else
            -- 如果没有角色，放在IdleFloor中心
            UpdatePreviewPosition(placementState.idleFloor.Position)
        end

        -- 显示确认UI
        ShowMobileConfirmUI(true)
    else
        -- PC端：跟随鼠标
        -- 位置会在RenderStepped中更新
    end
end

--[[
确认放置
]]
function PlacementController.ConfirmPlacement()
    if not placementState.isPlacing or not placementState.previewModel then
        return
    end

    -- 获取最终位置
    local finalPosition = PlacementHelper.GetModelPosition(placementState.previewModel)
    if not finalPosition then
        warn("[PlacementController] 无法获取模型位置")
        PlacementController.CancelPlacement()
        return
    end

    -- 发送确认请求到服务端
    if placementEvents then
        local confirmEvent = placementEvents:FindFirstChild("ConfirmPlacement")
        if confirmEvent then
            confirmEvent:FireServer(placementState.currentInstanceId, finalPosition)
        end
    end

    -- 暂时不清理，等待服务端响应
end

--[[
取消放置
]]
function PlacementController.CancelPlacement()
    if not placementState.isPlacing then
        return
    end

    -- V1.2.1: 移除Grid提示块
    GridHelper.HideGrid()

    -- V1.2.1: 移除Highlight效果
    if placementState.previewModel then
        HighlightHelper.RemoveHighlight(placementState.previewModel)
    end

    -- 移除预览模型
    if placementState.previewModel then
        placementState.previewModel:Destroy()
        placementState.previewModel = nil
    end

    -- 隐藏移动端UI
    if placementState.isMobile then
        ShowMobileConfirmUI(false)
    end

    -- 通知服务端取消
    if placementEvents then
        local cancelEvent = placementEvents:FindFirstChild("CancelPlacement")
        if cancelEvent then
            cancelEvent:FireServer(placementState.currentInstanceId)
        end
    end

    -- 重置状态
    placementState.isPlacing = false
    placementState.currentInstanceId = nil
    placementState.currentUnitId = nil
    placementState.currentGridSize = 1
    placementState.lastGridX = nil
    placementState.lastGridZ = nil
end

-- ==================== 预览位置更新 ====================

--[[
检查当前位置是否有效（客户端预检测）
@param gridX number
@param gridZ number
@return boolean - true表示有效（绿色），false表示冲突（红色）
]]
local function IsPositionValid(gridX, gridZ)
    -- V1.2.1: 基于网格坐标的碰撞检测
    if not placementState.idleFloor then
        return true
    end

    -- 获取当前兵种占据的网格宽度
    local currentGridWidth = math.sqrt(placementState.currentGridSize)  -- 1, 2, 3

    -- 检查当前位置是否与已放置的模型重叠
    for model, data in pairs(placementState.placedModels) do
        -- 确保模型还存在
        if model and model.Parent then
            local placedGridX = data.gridX
            local placedGridZ = data.gridZ
            local placedGridWidth = math.sqrt(data.gridSize)

            -- 检查网格是否重叠
            -- 当前模型占据的网格范围: [gridX, gridX + currentGridWidth)
            -- 已放置模型占据的网格范围: [placedGridX, placedGridX + placedGridWidth)
            local overlapX = not (gridX + currentGridWidth <= placedGridX or gridX >= placedGridX + placedGridWidth)
            local overlapZ = not (gridZ + currentGridWidth <= placedGridZ or gridZ >= placedGridZ + placedGridWidth)

            if overlapX and overlapZ then
                return false  -- 位置冲突
            end
        else
            -- 模型已被移除，清理缓存
            placementState.placedModels[model] = nil
        end
    end

    return true  -- 位置有效
end

--[[
更新预览模型位置
@param worldPos Vector3 - 原始世界坐标
]]
function UpdatePreviewPosition(worldPos)
    if not placementState.previewModel or not placementState.idleFloor then
        return
    end

    local floorCenter = placementState.idleFloor.Position

    -- 转换为网格索引
    local gridX, gridZ = PlacementHelper.WorldToGrid(worldPos, floorCenter)

    -- 检查是否需要更新 (只有网格变化时才更新，实现吸附效果)
    if gridX == placementState.lastGridX and gridZ == placementState.lastGridZ then
        return
    end

    -- 限制在边界内
    gridX, gridZ = PlacementHelper.ClampGridToBounds(gridX, gridZ, placementState.currentGridSize)

    -- 转换回世界坐标
    local snappedPos = PlacementHelper.GridToWorld(gridX, gridZ, floorCenter)

    -- 更新模型位置
    PlacementHelper.SetModelPosition(placementState.previewModel, snappedPos)

    -- V1.2.1: 检测位置是否有效（用于切换Grid颜色）
    local isValid = IsPositionValid(gridX, gridZ)

    -- V1.2.1: 更新Grid提示块（绿色或红色）
    GridHelper.ShowGrid(placementState.currentGridSize, snappedPos, isValid)

    -- 记录当前网格
    placementState.lastGridX = gridX
    placementState.lastGridZ = gridZ
end

-- ==================== PC端输入处理 ====================

--[[
连接PC端输入事件
]]
function ConnectPCInput()
    -- 鼠标移动 - 使用RenderStepped实时更新
    RunService.RenderStepped:Connect(function()
        if not placementState.isPlacing or not placementState.previewModel then
            return
        end

        if not placementState.idleFloor then
            return
        end

        -- 获取鼠标在地板上的位置
        local mouseWorldPos = PlacementHelper.GetMouseWorldPosition(camera, mouse, placementState.idleFloor)
        if mouseWorldPos then
            UpdatePreviewPosition(mouseWorldPos)
        end
    end)

    -- 鼠标点击
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end

        if not placementState.isPlacing then
            return
        end

        -- 左键确认
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            PlacementController.ConfirmPlacement()
        end

        -- 右键取消
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            PlacementController.CancelPlacement()
        end
    end)
end

-- ==================== 移动端输入处理 ====================

--[[
连接移动端输入事件
]]
function ConnectMobileInput()
    -- 触摸开始 - 用于初始拖动
    UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
        if gameProcessed then
            return
        end

        if not placementState.isPlacing or not placementState.previewModel then
            return
        end

        if not placementState.idleFloor then
            return
        end

        -- 获取触摸点在地板上的位置
        local touchWorldPos = PlacementHelper.GetTouchWorldPosition(camera, touch.Position, placementState.idleFloor)
        if touchWorldPos then
            UpdatePreviewPosition(touchWorldPos)
        end
    end)

    -- 触摸拖动
    UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
        if gameProcessed then
            return
        end

        if not placementState.isPlacing or not placementState.previewModel then
            return
        end

        if not placementState.idleFloor then
            return
        end

        -- 获取触摸点在地板上的位置
        local touchWorldPos = PlacementHelper.GetTouchWorldPosition(camera, touch.Position, placementState.idleFloor)
        if touchWorldPos then
            UpdatePreviewPosition(touchWorldPos)
        end
    end)

    -- 连接移动端确认/取消按钮
    ConnectMobileUI()
end

--[[
连接移动端UI按钮
]]
function ConnectMobileUI()
    local playerGui = player:WaitForChild("PlayerGui")
    local putConfirmGui = playerGui:WaitForChild("PutConfirm", 10)

    if not putConfirmGui then
        warn("[PlacementController] 找不到PutConfirm UI")
        return
    end

    local buttonBg = putConfirmGui:WaitForChild("ButtonBg", 5)
    if not buttonBg then
        return
    end

    local confirmButton = buttonBg:FindFirstChild("Confirm")
    local cancelButton = buttonBg:FindFirstChild("Cancel")

    if confirmButton then
        confirmButton.MouseButton1Click:Connect(function()
            PlacementController.ConfirmPlacement()
        end)
    end

    if cancelButton then
        cancelButton.MouseButton1Click:Connect(function()
            PlacementController.CancelPlacement()
        end)
    end
end

--[[
显示/隐藏移动端确认UI
@param show boolean
]]
function ShowMobileConfirmUI(show)
    local playerGui = player:WaitForChild("PlayerGui")
    local putConfirmGui = playerGui:FindFirstChild("PutConfirm")

    if putConfirmGui then
        putConfirmGui.Enabled = show
    end
end

-- ==================== 服务端响应处理 ====================

--[[
处理服务端放置响应
@param success boolean
@param message string
@param data table|nil
]]
function OnPlacementResponse(success, message, data)
    if success then
        -- V1.2.1: 记录放置的位置，用于后续碰撞检测
        if placementState.lastGridX and placementState.lastGridZ and placementState.currentGridSize then
            -- 延迟一帧后查找服务端创建的模型
            task.spawn(function()
                task.wait(0.1)  -- 等待服务端模型同步到客户端

                -- 查找IdleFloor上新增的模型
                local floorCenter = placementState.idleFloor.Position
                local placedPos = PlacementHelper.GridToWorld(placementState.lastGridX, placementState.lastGridZ, floorCenter)

                -- 在该位置附近查找模型
                local nearbyModels = {}
                for _, obj in ipairs(Workspace:GetChildren()) do
                    if obj:IsA("Model") and obj.PrimaryPart then
                        local distance = (obj.PrimaryPart.Position - placedPos).Magnitude
                        if distance < 5 then  -- 5 studs范围内
                            table.insert(nearbyModels, obj)
                        end
                    end
                end

                -- 找到最近的模型
                local closestModel = nil
                local closestDistance = math.huge
                for _, model in ipairs(nearbyModels) do
                    if not placementState.placedModels[model] then  -- 排除已记录的
                        local distance = (model.PrimaryPart.Position - placedPos).Magnitude
                        if distance < closestDistance then
                            closestDistance = distance
                            closestModel = model
                        end
                    end
                end

                if closestModel then
                    placementState.placedModels[closestModel] = {
                        gridX = placementState.lastGridX,
                        gridZ = placementState.lastGridZ,
                        gridSize = placementState.currentGridSize
                    }
                else
                    warn("[PlacementController] 未找到放置的模型!")
                end
            end)
        end

        -- V1.2.1: 移除Grid提示块
        GridHelper.HideGrid()

        -- V1.2.1: 移除Highlight效果
        if placementState.previewModel then
            HighlightHelper.RemoveHighlight(placementState.previewModel)
        end

        -- 放置成功，清理预览模型
        if placementState.previewModel then
            placementState.previewModel:Destroy()
            placementState.previewModel = nil
        end

        -- 隐藏移动端UI
        if placementState.isMobile then
            ShowMobileConfirmUI(false)
        end

        -- 重置状态
        placementState.isPlacing = false
        placementState.currentInstanceId = nil
        placementState.currentUnitId = nil
    else
        -- 放置失败，显示错误信息
        warn("[PlacementController] 放置失败:", message)
        -- 可以在这里添加UI提示
    end
end

-- ==================== 全局访问 ====================

-- 提供全局访问接口（供BackpackDisplay调用）
_G.PlacementController = PlacementController

-- 自动初始化
task.spawn(function()
    task.wait(1)  -- 等待其他系统加载
    PlacementController.Initialize()
end)

return PlacementController
