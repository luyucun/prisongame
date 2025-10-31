--[[
脚本名称: PlacementHelper
脚本类型: ModuleScript (客户端工具类)
脚本位置: StarterPlayer/StarterPlayerScripts/Utils/PlacementHelper
]]

--[[
放置辅助工具模块
职责:
1. 提供网格吸附计算
2. 边界检测和碰撞处理
3. 鼠标位置转换为世界坐标
版本: V1.2
]]

local PlacementHelper = {}

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

-- 常量配置
-- 说明: 1格兵种占据4x4 studs，2格兵种(2x2格)占据8x8 studs，3格兵种(3x3格)占据12x12 studs
local GRID_UNIT_SIZE = 4
local IDLE_FLOOR_SIZE = Vector3.new(120, 1, 120)
local PLACEMENT_Y_OFFSET = 2.5
local GRID_COUNT = 30  -- 120 / 4 = 30格

-- ==================== 坐标转换函数 ====================

--[[
世界坐标转网格索引
@param worldPos Vector3 - 世界坐标
@param floorCenter Vector3 - 地板中心
@return number, number - 网格X, 网格Z
]]
function PlacementHelper.WorldToGrid(worldPos, floorCenter)
    local offsetX = worldPos.X - floorCenter.X
    local offsetZ = worldPos.Z - floorCenter.Z

    -- V1.5.1修复: 计算网格索引前先限制在地板范围内
    -- 地板范围: [-60, 60]
    local halfSize = IDLE_FLOOR_SIZE.X / 2
    offsetX = math.clamp(offsetX, -halfSize, halfSize - 0.01)  -- 减去0.01避免刚好在边界
    offsetZ = math.clamp(offsetZ, -halfSize, halfSize - 0.01)

    local gridX = math.floor((offsetX + IDLE_FLOOR_SIZE.X / 2) / GRID_UNIT_SIZE)
    local gridZ = math.floor((offsetZ + IDLE_FLOOR_SIZE.Z / 2) / GRID_UNIT_SIZE)

    -- V1.5.1修复: 再次确保索引在有效范围内 (0 到 GRID_COUNT-1)
    gridX = math.clamp(gridX, 0, GRID_COUNT - 1)
    gridZ = math.clamp(gridZ, 0, GRID_COUNT - 1)

    return gridX, gridZ
end

--[[
网格索引转世界坐标
@param gridX number - 网格X索引
@param gridZ number - 网格Z索引
@param floorCenter Vector3 - 地板中心
@return Vector3 - 世界坐标
]]
function PlacementHelper.GridToWorld(gridX, gridZ, floorCenter)
    local worldX = floorCenter.X - IDLE_FLOOR_SIZE.X / 2 + gridX * GRID_UNIT_SIZE + GRID_UNIT_SIZE / 2
    local worldZ = floorCenter.Z - IDLE_FLOOR_SIZE.Z / 2 + gridZ * GRID_UNIT_SIZE + GRID_UNIT_SIZE / 2
    local worldY = floorCenter.Y + IDLE_FLOOR_SIZE.Y / 2 + PLACEMENT_Y_OFFSET

    return Vector3.new(worldX, worldY, worldZ)
end

--[[
获取最近的网格中心位置
@param worldPos Vector3 - 原始世界坐标
@param floorCenter Vector3 - 地板中心
@param gridSize number - 兵种占地大小 (1, 4, 9)
@return Vector3 - 吸附后的世界坐标
]]
function PlacementHelper.GetNearestGridPosition(worldPos, floorCenter, gridSize)
    -- 转换为网格索引
    local gridX, gridZ = PlacementHelper.WorldToGrid(worldPos, floorCenter)

    -- 处理边界限制
    gridX, gridZ = PlacementHelper.ClampGridToBounds(gridX, gridZ, gridSize)

    -- 转换回世界坐标
    return PlacementHelper.GridToWorld(gridX, gridZ, floorCenter)
end

--[[
限制网格索引在边界内
@param gridX number
@param gridZ number
@param gridSize number - 兵种占地大小 (1, 4, 9)
@return number, number - 限制后的网格X, Z
]]
function PlacementHelper.ClampGridToBounds(gridX, gridZ, gridSize)
    local gridWidth = math.sqrt(gridSize)  -- 1格=1, 4格=2, 9格=3

    -- V1.5.1修复: 边界计算
    -- 地板是30x30格(索引0-29)
    -- 1x1兵种: 可以放在0-29格(占据1格)
    -- 2x2兵种: 可以放在0-28格(占据2格,范围0-29)
    -- 3x3兵种: 可以放在0-27格(占据3格,范围0-29)
    -- 所以最大索引 = GRID_COUNT - gridWidth
    local maxGridIndex = GRID_COUNT - gridWidth

    gridX = math.clamp(gridX, 0, maxGridIndex)
    gridZ = math.clamp(gridZ, 0, maxGridIndex)

    return gridX, gridZ
end

--[[
检查网格是否在边界内
@param gridX number
@param gridZ number
@param gridSize number - 兵种占地大小 (1, 4, 9)
@return boolean - 是否在边界内
]]
function PlacementHelper.IsGridInBounds(gridX, gridZ, gridSize)
    if gridX < 0 or gridZ < 0 then
        return false
    end

    local gridWidth = math.sqrt(gridSize)  -- 1格=1, 4格=2, 9格=3

    -- V1.5.1修复: 边界检查
    -- 兵种占据 gridWidth 个格子
    -- 起始索引是 gridX, 结束索引是 gridX + gridWidth - 1
    -- 所以 gridX + gridWidth - 1 < GRID_COUNT
    -- 即 gridX + gridWidth <= GRID_COUNT
    -- 即 gridX < GRID_COUNT - gridWidth + 1
    -- 但为了统一，我们用 gridX + gridWidth > GRID_COUNT 作为越界条件
    if gridX + gridWidth > GRID_COUNT or gridZ + gridWidth > GRID_COUNT then
        return false
    end

    return true
end

-- ==================== 鼠标/触摸位置处理 ====================

--[[
获取鼠标在地板上的世界坐标
@param camera Camera
@param mouse Mouse
@param idleFloor Part - IdleFloor对象
@return Vector3|nil - 世界坐标，如果没有命中地板返回nil
]]
function PlacementHelper.GetMouseWorldPosition(camera, mouse, idleFloor)
    local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local rayOrigin = mouseRay.Origin
    local rayDirection = mouseRay.Direction * 1000

    -- 射线检测
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = {idleFloor}

    local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if raycastResult and raycastResult.Instance == idleFloor then
        return raycastResult.Position
    end

    return nil
end

--[[
获取触摸点在地板上的世界坐标
@param camera Camera
@param touchPosition Vector2 - 触摸位置
@param idleFloor Part
@return Vector3|nil
]]
function PlacementHelper.GetTouchWorldPosition(camera, touchPosition, idleFloor)
    local touchRay = camera:ScreenPointToRay(touchPosition.X, touchPosition.Y)
    local rayOrigin = touchRay.Origin
    local rayDirection = touchRay.Direction * 1000

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = {idleFloor}

    local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if raycastResult and raycastResult.Instance == idleFloor then
        return raycastResult.Position
    end

    return nil
end

-- ==================== 设备检测 ====================

--[[
检测是否为移动设备
@return boolean - true表示移动设备
]]
function PlacementHelper.IsMobileDevice()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

--[[
检测是否为PC设备
@return boolean - true表示PC设备
]]
function PlacementHelper.IsPCDevice()
    return UserInputService.KeyboardEnabled and UserInputService.MouseEnabled
end

-- ==================== 模型操作 ====================

--[[
设置模型位置
@param model Model
@param position Vector3
]]
function PlacementHelper.SetModelPosition(model, position)
    if not model then
        return
    end

    if model.PrimaryPart then
        model:SetPrimaryPartCFrame(CFrame.new(position))
    elseif model:FindFirstChild("HumanoidRootPart") then
        model.HumanoidRootPart.CFrame = CFrame.new(position)
    end
end

--[[
获取模型位置
@param model Model
@return Vector3|nil
]]
function PlacementHelper.GetModelPosition(model)
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
获取兵种模型模板
@param unitId string
@return Model|nil
]]
function PlacementHelper.GetUnitModelTemplate(unitId)
    local roleFolder = ReplicatedStorage:FindFirstChild("Role")
    if not roleFolder then
        return nil
    end

    local basicFolder = roleFolder:FindFirstChild("Basic")
    if not basicFolder then
        return nil
    end

    return basicFolder:FindFirstChild(unitId)
end

--[[
克隆兵种模型用于预览
@param unitId string
@return Model|nil
]]
function PlacementHelper.CloneUnitModel(unitId)
    local template = PlacementHelper.GetUnitModelTemplate(unitId)
    if not template then
        warn("[PlacementHelper] 找不到兵种模型:", unitId)
        return nil
    end

    local clone = template:Clone()

    -- 确保克隆的模型有PrimaryPart
    if not clone.PrimaryPart then
        -- 尝试设置HumanoidRootPart为PrimaryPart
        local hrp = clone:FindFirstChild("HumanoidRootPart")
        if hrp then
            clone.PrimaryPart = hrp
        else
            -- 如果没有HumanoidRootPart，找第一个Part
            for _, child in ipairs(clone:GetChildren()) do
                if child:IsA("BasePart") then
                    clone.PrimaryPart = child
                    break
                end
            end
        end
    end

    return clone
end

-- ==================== 调试函数 ====================

--[[
打印网格信息
@param gridX number
@param gridZ number
]]
function PlacementHelper.DebugPrintGrid(gridX, gridZ)
    print(string.format("[PlacementHelper] 网格: (%d, %d)", gridX, gridZ))
end

--[[
打印世界坐标信息
@param position Vector3
]]
function PlacementHelper.DebugPrintPosition(position)
    print(string.format("[PlacementHelper] 坐标: (%.2f, %.2f, %.2f)", position.X, position.Y, position.Z))
end

return PlacementHelper
