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
local HighlightHelper = require(script.Parent.Parent.Utils.HighlightHelper)  -- V1.4.1

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
    isRelocating = false,      -- V1.4.1: 是否为换位模式
    isMobile = false,          -- V1.4: 是否为移动设备
    currentTouch = nil,        -- V1.4: 当前触摸输入对象
}

-- 远程事件
local mergeEvents = nil
local placementEvents = nil  -- V1.4.1

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

    -- V1.4.1: 获取放置事件（用于换位功能）
    retryCount = 0
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
        warn("[DragSystem] PlacementEvents未找到，换位功能将不可用!")
    else
        -- 连接位置更新响应事件
        local updateResponseEvent = placementEvents:FindFirstChild("UpdateResponse")
        if updateResponseEvent then
            updateResponseEvent.OnClientEvent:Connect(OnUpdateResponse)
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

    -- 保存原始位置
    local originalPos = GetModelPosition(model)
    dragState.dragStartPos = originalPos

    -- 保存原始CanCollide状态
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp then
        dragState.originalCanCollide = hrp.CanCollide
    end

    -- V1.4.1: 彻底禁用Humanoid的自动行为（防止自动切回Running状态导致下沉）
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        -- 使用PlatformStand完全禁用Humanoid的移动和物理行为
        humanoid.PlatformStand = true
        -- 切换到Physics状态并保持
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        -- 禁用所有动画
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            local tracks = animator:GetPlayingAnimationTracks()
            for _, track in ipairs(tracks) do
                track:Stop()
            end
        end
    end

    -- 拖动时取消碰撞，保持锚定，防止物理影响
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.Anchored = true  -- V1.4.1: 保持锚定状态，配合PlatformStand防止下沉
        end
    end

    -- V1.4.1: 设置绿色描边（默认拖动状态）
    HighlightHelper.SetDraggingHighlight(model, true)

    -- 显示绿色Grid（默认状态，保持原高度）
    GridHelper.ShowGrid(gridSize, originalPos, true)
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
处理拖动更新（统一处理PC和移动端）V1.4.1重写
@param raycastResult RaycastResult
]]
function ProcessDragUpdate(raycastResult)
    local hitPart = raycastResult.Instance
    local hitModel = nil

    -- V1.4.1: 优先查找被射线击中的兵种模型（避免先判断地板导致闪烁）
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

    -- V1.4.1: 判断拖动模式 - 优先判断合成模式
    if hitModel and hitModel ~= dragState.draggedModel then
        -- ==================== 合成模式（优先） ====================
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
        dragState.isRelocating = false  -- 不是换位模式

        -- 显示Grid提示（在目标脚底）
        local targetPos = GetModelPosition(hitModel)
        GridHelper.ShowGrid(targetGridSize, targetPos, canMerge)

        -- V1.4.1: 设置拖动模型的描边颜色
        HighlightHelper.SetDraggingHighlight(dragState.draggedModel, canMerge)

        -- 移动拖动的模型到目标位置（保持原高度）
        local currentPos = GetModelPosition(dragState.draggedModel)
        local newPos = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
        SetModelPosition(dragState.draggedModel, newPos)

    elseif raycastResult.Instance == dragState.idleFloor then
        -- ==================== 换位模式（在IdleFloor上且没有击中其他兵种）====================
        dragState.targetModel = nil
        dragState.canMerge = false
        dragState.isRelocating = true  -- 换位模式

        local model = dragState.draggedModel
        local floorCenter = dragState.idleFloor.Position

        -- 使用PlacementHelper进行网格吸附
        local snappedPos = PlacementHelper.GetNearestGridPosition(
            raycastResult.Position,
            floorCenter,
            dragState.draggedGridSize
        )

        -- 检测该位置是否有冲突（排除自己）
        local isValid = IsPositionValidForRelocate(snappedPos)

        -- 显示Grid提示（在拖动模型脚底）
        GridHelper.ShowGrid(dragState.draggedGridSize, snappedPos, isValid)

        -- V1.4.1: 设置拖动模型的描边颜色
        HighlightHelper.SetDraggingHighlight(model, isValid)

        -- 移动模型（保持原高度）
        SetModelPosition(model, snappedPos)

    else
        -- ==================== 其他情况（不在IdleFloor上或其他未识别情况）====================
        dragState.targetModel = nil
        dragState.canMerge = false
        dragState.isRelocating = false
        GridHelper.HideGrid()
        HighlightHelper.SetDraggingHighlight(dragState.draggedModel, false)
    end
end

--[[
停止拖动 V1.4.1重写
]]
function StopDragging()
    if not dragState.isDragging or not dragState.draggedModel then
        return
    end

    print("[DragSystem] 停止拖动:", dragState.draggedModel:GetFullName())

    local model = dragState.draggedModel

    -- V1.4.1: 判断拖动模式并处理
    if dragState.canMerge and dragState.targetModel and mergeEvents then
        -- ==================== 合成模式 ====================
        local targetInstanceId = dragState.targetModel:GetAttribute("InstanceId")

        print("[DragSystem] 请求合成:", dragState.draggedInstanceId, "->", targetInstanceId)

        -- 发送合成请求到服务端
        local requestEvent = mergeEvents:FindFirstChild("RequestMerge")
        if requestEvent then
            requestEvent:FireServer(dragState.draggedInstanceId, targetInstanceId)
        end

        -- 隐藏Grid，等待服务端响应
        GridHelper.HideGrid()
        -- 注意：不在这里恢复模型状态，等待服务端合成响应

    elseif dragState.isRelocating and placementEvents then
        -- ==================== 换位模式 ====================
        local currentPos = GetModelPosition(model)
        if currentPos then
            -- 检查该位置是否有效
            if IsPositionValidForRelocate(currentPos) then
                print("[DragSystem] 请求换位:", dragState.draggedInstanceId, "新位置:", currentPos)

                -- 发送位置更新请求到服务端
                local updateEvent = placementEvents:FindFirstChild("UpdatePosition")
                if updateEvent then
                    updateEvent:FireServer(dragState.draggedInstanceId, currentPos)
                end

                -- 恢复模型状态（在服务端确认前）
                RestoreModelAfterDrag(model)
                GridHelper.HideGrid()
            else
                -- 位置无效，回到原位
                print("[DragSystem] 换位位置无效，回到原位")
                ReturnToOriginalPosition(model)
            end
        else
            ReturnToOriginalPosition(model)
        end

    else
        -- ==================== 取消拖动（回到原位） ====================
        print("[DragSystem] 取消拖动，回到原位")
        ReturnToOriginalPosition(model)
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
    dragState.isRelocating = false  -- V1.4.1
    dragState.currentTouch = nil
end

-- ==================== 工具函数 ====================

--[[
恢复模型拖动后的状态（V1.4.1）
@param model Model
]]
function RestoreModelAfterDrag(model)
    if not model then
        return
    end

    -- V1.4.1: 恢复Humanoid的正常行为
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.PlatformStand = false  -- 恢复Humanoid控制
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)  -- 切换回正常状态
    end

    -- 恢复锚固和碰撞
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true  -- 恢复锚固
            if descendant.Name == "HumanoidRootPart" then
                descendant.CanCollide = dragState.originalCanCollide or false
            else
                descendant.CanCollide = false
            end
        end
    end

    -- V1.4.1: 设置默认描边（透明）
    HighlightHelper.SetDefaultHighlight(model)
end

--[[
返回到原始位置（V1.4.1）
@param model Model
]]
function ReturnToOriginalPosition(model)
    if not model or not dragState.dragStartPos then
        return
    end

    -- 移动回原位
    SetModelPosition(model, dragState.dragStartPos)

    -- 恢复模型状态
    RestoreModelAfterDrag(model)

    -- 隐藏Grid
    GridHelper.HideGrid()
end

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
检查换位时的位置是否有效（V1.4.1）
@param worldPos Vector3 - 世界坐标
@return boolean - true表示有效，false表示有冲突
]]
function IsPositionValidForRelocate(worldPos)
    if not dragState.idleFloor then
        return false
    end

    local floorCenter = dragState.idleFloor.Position

    -- 转换为网格坐标
    local gridX, gridZ = PlacementHelper.WorldToGrid(worldPos, floorCenter)

    -- 获取当前兵种占据的网格宽度
    local currentGridWidth = math.sqrt(dragState.draggedGridSize)  -- 1, 2, 3

    -- 检查与已放置的模型是否重叠（需要排除自己）
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= dragState.draggedModel then
            local objInstanceId = obj:GetAttribute("InstanceId")
            if objInstanceId and objInstanceId ~= dragState.draggedInstanceId then
                -- 这是另一个已放置的兵种
                local objPos = GetModelPosition(obj)
                if objPos then
                    local objGridX, objGridZ = PlacementHelper.WorldToGrid(objPos, floorCenter)
                    local objGridSize = obj:GetAttribute("GridSize") or 1
                    local objGridWidth = math.sqrt(objGridSize)

                    -- 检查网格是否重叠
                    local overlapX = not (gridX + currentGridWidth <= objGridX or gridX >= objGridX + objGridWidth)
                    local overlapZ = not (gridZ + currentGridWidth <= objGridZ or gridZ >= objGridZ + objGridWidth)

                    if overlapX and overlapZ then
                        return false  -- 位置冲突
                    end
                end
            end
        end
    end

    return true  -- 位置有效
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

-- ==================== V1.4.1: 换位响应处理 ====================

--[[
处理服务端位置更新响应
@param success boolean - 是否成功
@param message string - 消息
@param instanceId string - 兵种实例ID
]]
function OnUpdateResponse(success, message, instanceId)
    print("[DragSystem] 收到位置更新响应:", success, message, instanceId)

    if success then
        print("[DragSystem] 换位成功!")
        -- 服务端已经更新了位置，客户端已经在StopDragging中做了处理
    else
        warn("[DragSystem] 换位失败:", message)
        -- 可以在这里添加UI提示
        -- 如果失败，可能需要将模型恢复到原位（但通常服务端会拒绝前客户端已经检查了）
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
