--[[
脚本名称: DragSystem
脚本类型: LocalScript (客户端系统)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/DragSystem
]]

--[[
已放置兵种拖动系统
职责:
1. 检测玩家点击已放置的兵种
2. 处理拖动逻辑，移动兵种位置
3. V1.4: 实现拖动合成功能
4. 与服务端通信，更新兵种位置/合成
版本: V1.4
]]

local DragSystem = {}

-- 引用服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用工具模块
local PlacementHelper = require(script.Parent.Parent.Utils.PlacementHelper)
local GridHelper = require(script.Parent.Parent.Utils.GridHelper)

-- 玩家引用
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

-- 拖动状态
local dragState = {
    isDragging = false,
    draggedModel = nil,
    draggedInstanceId = nil,
    draggedUnitId = nil,       -- V1.4: 兵种ID
    draggedLevel = nil,        -- V1.4: 兵种等级
    draggedGridSize = nil,     -- V1.4: 兵种占地大小
    dragStartPos = nil,
    idleFloor = nil,
    originalCanCollide = nil,
    placedUnits = {},          -- 追踪所有已放置的兵种
    targetModel = nil,         -- V1.4: 当前悬停的目标模型
    canMerge = false,          -- V1.4: 是否可以合成
    isMobile = false,          -- V1.4: 是否为移动设备
    currentTouch = nil,        -- V1.4: 当前触摸输入对象
}

-- 远程事件
local mergeEvents = nil

-- ==================== 初始化 ====================

--[[
初始化拖动系统
]]
function DragSystem.Initialize()
    print("[DragSystem] 正在初始化...")

    -- 初始化GridHelper (V1.4)
    GridHelper.Initialize()

    -- V1.4: 检测设备类型
    dragState.isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    print("[DragSystem] 设备类型:", dragState.isMobile and "移动端" or "PC端")

    -- 等待玩家角色加载
    local character = player.Character or player.CharacterAdded:Wait()
    print("[DragSystem] 玩家角色已加载")

    -- 等待基地分配完成
    task.wait(2)

    -- 查找IdleFloor
    dragState.idleFloor = FindPlayerIdleFloor()
    if dragState.idleFloor then
        print("[DragSystem] 找到IdleFloor:", dragState.idleFloor:GetFullName())
    else
        warn("[DragSystem] 找不到IdleFloor")
        return false
    end

    -- V1.4: 获取合成事件
    local maxRetries = 10
    local retryCount = 0
    while not mergeEvents and retryCount < maxRetries do
        local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
        if eventsFolder then
            mergeEvents = eventsFolder:FindFirstChild("MergeEvents")
        end
        if not mergeEvents then
            task.wait(0.5)
            retryCount = retryCount + 1
        end
    end

    if not mergeEvents then
        warn("[DragSystem] MergeEvents未找到，合成功能将不可用!")
    else
        -- 连接合成响应事件
        local responseEvent = mergeEvents:FindFirstChild("MergeResponse")
        if responseEvent then
            responseEvent.OnClientEvent:Connect(OnMergeResponse)
        end
    end

    -- 连接输入事件
    if dragState.isMobile then
        print("[DragSystem] 连接移动端触摸事件")
        ConnectMobileEvents()
    else
        print("[DragSystem] 连接PC端鼠标事件")
        ConnectMouseEvents()
    end

    print("[DragSystem] 初始化完成")
    return true
end

-- ==================== IdleFloor查找 ====================

--[[
查找玩家的IdleFloor
@return Part|nil
]]
function FindPlayerIdleFloor()
    local character = player.Character
    if not character then
        return nil
    end

    local homeFolder = Workspace:FindFirstChild("Home")
    if not homeFolder then
        return nil
    end

    -- 遍历所有基地找最近的
    local nearestFloor = nil
    local nearestDistance = math.huge

    for i = 1, 6 do
        local playerHome = homeFolder:FindFirstChild("PlayerHome" .. i)
        if playerHome then
            local idleFloor = playerHome:FindFirstChild("IdleFloor")
            if idleFloor then
                local distance = (idleFloor.Position - character.PrimaryPart.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestFloor = idleFloor
                end
            end
        end
    end

    return nearestFloor
end

-- ==================== PC端鼠标事件处理 ====================

--[[
连接PC端鼠标事件
]]
function ConnectMouseEvents()
    -- 鼠标按下 - 检测是否点击到已放置的兵种
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            -- 创建射线检测
            local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
            local rayOrigin = mouseRay.Origin
            local rayDirection = mouseRay.Direction * 1000

            local raycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.FilterDescendantsInstances = {player.Character}

            local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

            if raycastResult then
                local hitPart = raycastResult.Instance
                if hitPart then
                    -- 查找父模型
                    local model = hitPart.Parent
                    while model and model ~= Workspace do
                        if model:FindFirstChild("Humanoid") and model:GetAttribute("InstanceId") then
                            -- 这是一个已放置的NPC模型
                            print("[DragSystem] 检测到点击模型:", model.Name)
                            StartDragging(model)
                            return
                        end
                        model = model.Parent
                    end
                end
            end
        end
    end)

    -- 鼠标移动 - 拖动已选中的模型
    RunService.RenderStepped:Connect(function()
        if dragState.isDragging and dragState.draggedModel then
            UpdateDragPosition()
        end
    end)

    -- 鼠标释放 - 结束拖动
    UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if dragState.isDragging then
                StopDragging()
            end
        end
    end)
end

-- ==================== 移动端触摸事件处理 ====================

--[[
连接移动端触摸事件
]]
function ConnectMobileEvents()
    -- 触摸开始 - 检测是否触摸到已放置的兵种
    UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
        if gameProcessed then
            return
        end

        -- 如果已经在拖动，忽略新的触摸
        if dragState.isDragging then
            return
        end

        -- 创建射线检测
        local touchPos = touch.Position
        local touchRay = camera:ScreenPointToRay(touchPos.X, touchPos.Y)
        local rayOrigin = touchRay.Origin
        local rayDirection = touchRay.Direction * 1000

        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = {player.Character}

        local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

        if raycastResult then
            local hitPart = raycastResult.Instance
            if hitPart then
                -- 查找父模型
                local model = hitPart.Parent
                while model and model ~= Workspace do
                    if model:FindFirstChild("Humanoid") and model:GetAttribute("InstanceId") then
                        -- 这是一个已放置的NPC模型，开始拖动
                        print("[DragSystem] 移动端检测到触摸模型:", model.Name)
                        dragState.currentTouch = touch
                        StartDragging(model)
                        return
                    end
                    model = model.Parent
                end
            end
        end
    end)

    -- 触摸移动 - 更新拖动位置
    UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
        -- 不检查gameProcessed，允许拖动时穿过UI

        if not dragState.isDragging or not dragState.draggedModel then
            return
        end

        -- 只响应当前拖动的触摸
        if dragState.currentTouch and touch ~= dragState.currentTouch then
            return
        end

        -- 更新拖动位置
        UpdateDragPositionTouch(touch.Position)
    end)

    -- 触摸结束 - 停止拖动
    UserInputService.TouchEnded:Connect(function(touch, gameProcessed)
        if not dragState.isDragging then
            return
        end

        -- 只响应当前拖动的触摸
        if dragState.currentTouch and touch == dragState.currentTouch then
            dragState.currentTouch = nil
            StopDragging()
        end
    end)
end

-- ==================== 拖动逻辑 ====================

--[[
开始拖动模型
@param model Model - 要拖动的模型
]]
function StartDragging(model)
    if not model or dragState.isDragging then
        return
    end

    -- 检查模型是否在IdleFloor上
    if not IsModelOnIdleFloor(model) then
        return
    end

    -- V1.4: 获取兵种信息
    local instanceId = model:GetAttribute("InstanceId")
    if not instanceId then
        warn("[DragSystem] 模型没有InstanceId属性")
        return
    end

    local unitId = model:GetAttribute("UnitId")
    local level = model:GetAttribute("Level") or 1
    local gridSize = model:GetAttribute("GridSize") or 1

    print("[DragSystem] 开始拖动:", model:GetFullName(), "Level:", level)

    dragState.isDragging = true
    dragState.draggedModel = model
    dragState.draggedInstanceId = instanceId
    dragState.draggedUnitId = unitId
    dragState.draggedLevel = level
    dragState.draggedGridSize = gridSize

    -- 保存原始CanCollide状态
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp then
        dragState.originalCanCollide = hrp.CanCollide
    end

    -- 拖动时取消锚固和碰撞，允许移动和穿过其他物体
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.Anchored = false  -- 取消锚固以允许拖动
        end
    end

    dragState.dragStartPos = GetModelPosition(model)
end

--[[
更新拖动位置（PC端鼠标）
]]
function UpdateDragPosition()
    if not dragState.draggedModel or not dragState.idleFloor then
        return
    end

    -- 获取鼠标在IdleFloor上的位置
    local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local rayOrigin = mouseRay.Origin
    local rayDirection = mouseRay.Direction * 1000

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {player.Character, dragState.draggedModel}

    local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if raycastResult then
        ProcessDragUpdate(raycastResult)
    else
        -- 没有击中任何东西
        dragState.targetModel = nil
        dragState.canMerge = false
        GridHelper.HideGrid()
    end
end

--[[
更新拖动位置（移动端触摸）
@param touchPosition Vector2 - 触摸屏幕位置
]]
function UpdateDragPositionTouch(touchPosition)
    if not dragState.draggedModel or not dragState.idleFloor then
        return
    end

    -- 获取触摸点在世界中的位置
    local touchRay = camera:ScreenPointToRay(touchPosition.X, touchPosition.Y)
    local rayOrigin = touchRay.Origin
    local rayDirection = touchRay.Direction * 1000

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {player.Character, dragState.draggedModel}

    local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if raycastResult then
        ProcessDragUpdate(raycastResult)
    else
        -- 没有击中任何东西
        dragState.targetModel = nil
        dragState.canMerge = false
        GridHelper.HideGrid()
    end
end

--[[
处理拖动更新（统一处理PC和移动端）
@param raycastResult RaycastResult
]]
function ProcessDragUpdate(raycastResult)
    local hitPart = raycastResult.Instance
    local hitModel = nil

    -- 查找被射线击中的模型
    if hitPart then
        local parent = hitPart.Parent
        while parent and parent ~= Workspace do
            if parent:FindFirstChild("Humanoid") and parent:GetAttribute("InstanceId") then
                hitModel = parent
                break
            end
            parent = parent.Parent
        end
    end

    -- V1.4: 检测是否悬停在可合成的目标上
    if hitModel and hitModel ~= dragState.draggedModel then
        local targetInstanceId = hitModel:GetAttribute("InstanceId")
        local targetUnitId = hitModel:GetAttribute("UnitId")
        local targetLevel = hitModel:GetAttribute("Level") or 1
        local targetGridSize = hitModel:GetAttribute("GridSize") or 1

        -- 检查是否可以合成
        local canMerge = (targetUnitId == dragState.draggedUnitId) and
                       (targetLevel == dragState.draggedLevel) and
                       (dragState.draggedLevel < 3)  -- 最高等级3

        dragState.targetModel = hitModel
        dragState.canMerge = canMerge

        -- 显示Grid提示
        local targetPos = GetModelPosition(hitModel)
        GridHelper.ShowGrid(targetGridSize, targetPos, canMerge)

        -- 移动拖动的模型到目标位置
        local currentPos = GetModelPosition(dragState.draggedModel)
        local newPos = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
        SetModelPosition(dragState.draggedModel, newPos)
    else
        -- 没有悬停在其他模型上
        dragState.targetModel = nil
        dragState.canMerge = false
        GridHelper.HideGrid()

        -- 检查是否在IdleFloor上
        if raycastResult.Instance == dragState.idleFloor then
            local newPos = raycastResult.Position
            local model = dragState.draggedModel
            local currentPos = GetModelPosition(model)
            newPos = Vector3.new(newPos.X, currentPos.Y, newPos.Z)
            SetModelPosition(model, newPos)
        end
    end
end

--[[
停止拖动
]]
function StopDragging()
    if not dragState.isDragging or not dragState.draggedModel then
        return
    end

    print("[DragSystem] 停止拖动:", dragState.draggedModel:GetFullName())

    local model = dragState.draggedModel

    -- V1.4: 检查是否可以合成
    if dragState.canMerge and dragState.targetModel and mergeEvents then
        local targetInstanceId = dragState.targetModel:GetAttribute("InstanceId")

        print("[DragSystem] 请求合成:", dragState.draggedInstanceId, "->", targetInstanceId)

        -- 发送合成请求到服务端
        local requestEvent = mergeEvents:FindFirstChild("RequestMerge")
        if requestEvent then
            requestEvent:FireServer(dragState.draggedInstanceId, targetInstanceId)
        end

        -- 暂时不恢复，等待服务端响应
        GridHelper.HideGrid()
    else
        -- 不能合成，恢复到原位置
        if dragState.dragStartPos then
            SetModelPosition(model, dragState.dragStartPos)
        end

        -- 恢复锚固和碰撞设置
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true  -- 恢复锚固
                if descendant:FindFirstChild("HumanoidRootPart") then
                    descendant.CanCollide = dragState.originalCanCollide or false
                else
                    descendant.CanCollide = false
                end
            end
        end

        GridHelper.HideGrid()
    end

    -- 重置拖动状态
    dragState.isDragging = false
    dragState.draggedModel = nil
    dragState.draggedInstanceId = nil
    dragState.draggedUnitId = nil
    dragState.draggedLevel = nil
    dragState.draggedGridSize = nil
    dragState.dragStartPos = nil
    dragState.targetModel = nil
    dragState.canMerge = false
    dragState.currentTouch = nil  -- V1.4: 清理触摸引用
end

-- ==================== 工具函数 ====================

--[[
检查模型是否在IdleFloor上
@param model Model
@return boolean
]]
function IsModelOnIdleFloor(model)
    if not model or not dragState.idleFloor then
        return false
    end

    local modelPos = GetModelPosition(model)
    if not modelPos then
        return false
    end

    local floorPos = dragState.idleFloor.Position
    local floorSize = dragState.idleFloor.Size

    -- 检查模型是否在地板范围内
    local distX = math.abs(modelPos.X - floorPos.X)
    local distZ = math.abs(modelPos.Z - floorPos.Z)

    return distX <= floorSize.X / 2 and distZ <= floorSize.Z / 2
end

--[[
获取模型位置
@param model Model
@return Vector3|nil
]]
function GetModelPosition(model)
    if not model then
        return nil
    end

    if model.PrimaryPart then
        return model.PrimaryPart.Position
    elseif model:FindFirstChild("HumanoidRootPart") then
        return model.HumanoidRootPart.Position
    end

    return nil
end

--[[
设置模型位置
@param model Model
@param position Vector3
]]
function SetModelPosition(model, position)
    if not model or not position then
        return
    end

    if model.PrimaryPart then
        model:SetPrimaryPartCFrame(CFrame.new(position))
    elseif model:FindFirstChild("HumanoidRootPart") then
        model.HumanoidRootPart.CFrame = CFrame.new(position)
    end
end

-- ==================== V1.4: 合成响应处理 ====================

--[[
处理服务端合成响应
@param success boolean - 是否成功
@param message string - 消息
@param newUnitData table|nil - 新兵种数据
]]
function OnMergeResponse(success, message, newUnitData)
    print("[DragSystem] 收到合成响应:", success, message)

    if success then
        print("[DragSystem] 合成成功! 新等级:", newUnitData and newUnitData.Level or "?")
        -- 服务端已经处理了模型的移除和新建，客户端不需要额外操作
        -- 等待新模型自动同步
    else
        warn("[DragSystem] 合成失败:", message)
        -- 可以在这里添加UI提示
    end
end

-- ==================== 全局访问 ====================

_G.DragSystem = DragSystem

-- 自动初始化
task.spawn(function()
    task.wait(1)
    DragSystem.Initialize()
end)

return DragSystem
