--[[
脚本名称: PlacementHelper
脚本类型: ModuleScript (客户端工具类)
脚本位置: StarterPlayer/StarterPlayerScripts/Utils/PlacementHelper
]]

--[[
放置辅助工具模块 (V2.0重构: 支持任意矩形占地)
职责:
1. 提供网格吸附计算
2. 边界检测和碰撞处理
3. 鼠标位置转换为世界坐标
版本: V2.0

占地尺寸约定:
- GridWidth: X轴方向占用的格子数
- GridDepth: Z轴方向占用的格子数
- 支持任意矩形: 1x1, 1x2, 2x2, 2x3, 3x3, 4x7 等
]]

local PlacementHelper = {}

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

-- 常量配置
-- 说明: 1格兵种占据4x4 studs
local GRID_UNIT_SIZE = 4
local IDLE_FLOOR_SIZE = Vector3.new(56, 1, 56)  -- IdleFloor实际大小
-- 兵种脚底距离地板上表面的距离(studs)
-- V2.1修复: 轴点已统一在脚底,不需要额外偏移
local PLACEMENT_Y_OFFSET = 0
local GRID_COUNT = 14  -- 56 / 4 = 14格

-- ==================== 坐标转换函数 ====================

--[[
世界坐标转网格索引 (V2.0.4修复: 支持矩形占地，修正中心点偏移问题)
@param worldPos Vector3 - 世界坐标（模型中心点）
@param floorCenter Vector3 - 地板中心
@param gridWidth number - X轴方向占用格子数 (可选，默认1)
@param gridDepth number - Z轴方向占用格子数 (可选，默认等于gridWidth)
@return number, number - 网格X, 网格Z (左下角格子索引)
注意: 返回的网格索引可能超出边界,调用方应使用ClampGridToBounds进行边界处理
]]
function PlacementHelper.WorldToGrid(worldPos, floorCenter, gridWidth, gridDepth)
    -- 处理默认参数
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    -- V2.0.4: 计算占地的半宽/半深（studs）
    -- 模型中心点需要减去半个占地宽度才能得到左下角的格子索引
    local halfSpanX = (gridWidth * GRID_UNIT_SIZE) / 2
    local halfSpanZ = (gridDepth * GRID_UNIT_SIZE) / 2

    local offsetX = worldPos.X - floorCenter.X
    local offsetZ = worldPos.Z - floorCenter.Z

    -- 计算网格索引（以占地区域的左下角为基准）
    -- 地板范围: [-28, 28]，网格范围: [0, 13]
    -- V2.0.4修正: 从模型中心坐标减去半跨度，得到左下角坐标，再计算格子索引
    local gridX = math.floor((offsetX + IDLE_FLOOR_SIZE.X / 2 - halfSpanX + GRID_UNIT_SIZE / 2) / GRID_UNIT_SIZE)
    local gridZ = math.floor((offsetZ + IDLE_FLOOR_SIZE.Z / 2 - halfSpanZ + GRID_UNIT_SIZE / 2) / GRID_UNIT_SIZE)

    -- 只做基本的非负限制,防止负索引
    gridX = math.max(0, gridX)
    gridZ = math.max(0, gridZ)

    return gridX, gridZ
end

--[[
网格索引转世界坐标 (V2.0重构: 支持矩形占地)
@param gridX number - 网格X索引
@param gridZ number - 网格Z索引
@param floorCenter Vector3 - 地板中心
@param gridWidth number - X轴方向占用格子数 (默认1)
@param gridDepth number - Z轴方向占用格子数 (默认等于gridWidth)
@return Vector3 - 世界坐标 (兵种中心位置)
]]
function PlacementHelper.GridToWorld(gridX, gridZ, floorCenter, gridWidth, gridDepth)
    -- 处理默认参数
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    -- 计算兵种中心的偏移量
    local halfSpanX = (gridWidth * GRID_UNIT_SIZE) / 2
    local halfSpanZ = (gridDepth * GRID_UNIT_SIZE) / 2

    local worldX = floorCenter.X - IDLE_FLOOR_SIZE.X / 2 + gridX * GRID_UNIT_SIZE + halfSpanX
    local worldZ = floorCenter.Z - IDLE_FLOOR_SIZE.Z / 2 + gridZ * GRID_UNIT_SIZE + halfSpanZ

    -- 正确计算Y坐标：地板上表面 + 兵种脚底到地板的距离
    local worldY = floorCenter.Y + IDLE_FLOOR_SIZE.Y / 2 + PLACEMENT_Y_OFFSET

    return Vector3.new(worldX, worldY, worldZ)
end

--[[
获取最近的网格中心位置 (V2.0.4修复: WorldToGrid传入占地尺寸)
@param worldPos Vector3 - 原始世界坐标
@param floorCenter Vector3 - 地板中心
@param gridWidth number - X轴方向占用格子数
@param gridDepth number - Z轴方向占用格子数 (默认等于gridWidth)
@return Vector3 - 吸附后的世界坐标
]]
function PlacementHelper.GetNearestGridPosition(worldPos, floorCenter, gridWidth, gridDepth)
    -- 处理默认参数
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    -- V2.0.4修复: WorldToGrid需要传入占地尺寸
    local gridX, gridZ = PlacementHelper.WorldToGrid(worldPos, floorCenter, gridWidth, gridDepth)

    -- 处理边界限制
    gridX, gridZ = PlacementHelper.ClampGridToBounds(gridX, gridZ, gridWidth, gridDepth)

    -- 转换回世界坐标
    return PlacementHelper.GridToWorld(gridX, gridZ, floorCenter, gridWidth, gridDepth)
end

--[[
限制网格索引在边界内 (V2.0重构: 支持矩形占地)
@param gridX number
@param gridZ number
@param gridWidth number - X轴方向占用格子数
@param gridDepth number - Z轴方向占用格子数 (默认等于gridWidth)
@return number, number - 限制后的网格X, Z
]]
function PlacementHelper.ClampGridToBounds(gridX, gridZ, gridWidth, gridDepth)
    -- 处理默认参数
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    -- 边界计算
    -- 地板是14x14格(索引0-13)
    -- 例如: 2x3兵种可以放在X方向0-12, Z方向0-11
    local maxGridX = GRID_COUNT - gridWidth
    local maxGridZ = GRID_COUNT - gridDepth

    gridX = math.clamp(gridX, 0, maxGridX)
    gridZ = math.clamp(gridZ, 0, maxGridZ)

    return gridX, gridZ
end

--[[
检查网格是否在边界内 (V2.0重构: 支持矩形占地)
@param gridX number
@param gridZ number
@param gridWidth number - X轴方向占用格子数
@param gridDepth number - Z轴方向占用格子数 (默认等于gridWidth)
@return boolean - 是否在边界内
]]
function PlacementHelper.IsGridInBounds(gridX, gridZ, gridWidth, gridDepth)
    -- 处理默认参数
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    if gridX < 0 or gridZ < 0 then
        return false
    end

    if gridX + gridWidth > GRID_COUNT or gridZ + gridDepth > GRID_COUNT then
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

    -- 统一使用PivotTo，避免不同PrimaryPart导致的偏移累积
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and model.PrimaryPart ~= hrp then
        model.PrimaryPart = hrp
    end

    model:PivotTo(CFrame.new(position))
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

    -- 统一使用Pivot，避免因不同主部件导致的读写偏差
    local cf = model:GetPivot()
    return cf and cf.Position or nil
end

--[[
获取兵种模型模板
@param unitId string
@return Model|nil
]]
function PlacementHelper.GetUnitModelTemplate(unitId)
    -- 首先需要从UnitConfig获取模型路径
    local UnitConfig = ReplicatedStorage:FindFirstChild("Config")
    if UnitConfig then
        UnitConfig = UnitConfig:FindFirstChild("UnitConfig")
    end

    if not UnitConfig then
        warn("[PlacementHelper] 找不到UnitConfig")
        return nil
    end

    -- 加载UnitConfig模块
    local unitConfigModule = require(UnitConfig)
    local unitData = unitConfigModule.GetUnitById(unitId)

    if not unitData then
        warn(string.format("[PlacementHelper] 找不到兵种配置: %s", unitId))
        return nil
    end

    -- 获取模型路径,例如 "Role/Basic/Noob"
    local modelPath = unitData.ModelPath
    if not modelPath or modelPath == "" then
        warn(string.format("[PlacementHelper] 兵种%s没有配置ModelPath", unitId))
        return nil
    end

    -- 确保modelPath是字符串类型
    modelPath = tostring(modelPath)

    -- 解析路径
    local pathParts = string.split(modelPath, "/")

    -- 从ReplicatedStorage开始遍历路径
    local currentFolder = ReplicatedStorage
    for i = 1, #pathParts - 1 do
        local nextFolder = currentFolder:FindFirstChild(pathParts[i])
        if not nextFolder then
            warn(string.format("[PlacementHelper] 路径不存在: %s (在 %s)", pathParts[i], currentFolder:GetFullName()))
            return nil
        end
        currentFolder = nextFolder
    end

    -- 最后一个部分是模型名称
    local modelName = tostring(pathParts[#pathParts])
    local model = currentFolder:FindFirstChild(modelName)

    if not model then
        warn(string.format("[PlacementHelper] 找不到模型: %s (路径: %s)", modelName, modelPath))
        return nil
    end

    if not model:IsA("Model") then
        warn(string.format("[PlacementHelper] %s 不是一个Model类型", modelName))
        return nil
    end

    return model
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
