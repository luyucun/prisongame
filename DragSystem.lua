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
3. 与服务端通信，更新兵种位置
版本: V1.2
]]

local DragSystem = {}

-- 引用服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- 玩家引用
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

-- 拖动状态
local dragState = {
    isDragging = false,
    draggedModel = nil,
    draggedInstanceId = nil,
    dragStartPos = nil,
    idleFloor = nil,
    originalCanCollide = nil,
    placedUnits = {},  -- 追踪所有已放置的兵种
}

-- ==================== 初始化 ====================

--[[
初始化拖动系统
]]
function DragSystem.Initialize()
    print("[DragSystem] 正在初始化...")

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

    -- 连接鼠标事件
    ConnectMouseEvents()

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

-- ==================== 鼠标事件处理 ====================

--[[
连接鼠标事件
]]
function ConnectMouseEvents()
    print("[DragSystem] 连接鼠标事件")

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
                    while model and model.Parent ~= Workspace do
                        if model:FindFirstChild("Humanoid") then
                            -- 这是一个NPC模型
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

    print("[DragSystem] 开始拖动:", model:GetFullName())

    dragState.isDragging = true
    dragState.draggedModel = model

    -- 保存原始CanCollide状态
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp then
        dragState.originalCanCollide = hrp.CanCollide
    end

    -- 拖动时禁用碰撞，允许穿过其他物体
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
        end
    end

    dragState.dragStartPos = GetModelPosition(model)
end

--[[
更新拖动位置
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
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = {dragState.idleFloor}

    local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if raycastResult then
        local newPos = raycastResult.Position
        -- 保持模型的Y位置
        local model = dragState.draggedModel
        local currentPos = GetModelPosition(model)
        newPos = Vector3.new(newPos.X, currentPos.Y, newPos.Z)

        -- 设置模型位置
        SetModelPosition(model, newPos)
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

    -- 恢复碰撞设置
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if descendant:FindFirstChild("HumanoidRootPart") then
                descendant.CanCollide = dragState.originalCanCollide or false
            else
                descendant.CanCollide = false
            end
        end
    end

    -- 重置拖动状态
    dragState.isDragging = false
    dragState.draggedModel = nil
    dragState.dragStartPos = nil
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

-- ==================== 全局访问 ====================

_G.DragSystem = DragSystem

-- 自动初始化
task.spawn(function()
    task.wait(1)
    DragSystem.Initialize()
end)

return DragSystem
