--[[
脚本名称: PlacementConfig
脚本类型: ModuleScript (服务端配置)
脚本位置: ServerScriptService/Config/PlacementConfig
]]

--[[
放置系统配置模块
职责: 存储兵种放置系统的配置参数
版本: V1.2
]]

local PlacementConfig = {}

-- ==================== 地板相关配置 ====================

-- IdleFloor的名称
PlacementConfig.IDLE_FLOOR_NAME = "IdleFloor"

-- IdleFloor的标准大小 (X, Y, Z)
PlacementConfig.IDLE_FLOOR_SIZE = Vector3.new(120, 1, 120)

-- 单个格子的大小 (4 studs)
-- 说明: 1格兵种占据4x4 studs，2格兵种(2x2格)占据8x8 studs，3格兵种(3x3格)占据12x12 studs
PlacementConfig.GRID_UNIT_SIZE = 4

-- 网格数量 (120 / 4 = 30，所以是30x30个格子)
PlacementConfig.GRID_COUNT_X = 30
PlacementConfig.GRID_COUNT_Z = 30

-- ==================== 放置限制配置 ====================

-- 最大放置数量限制(每个玩家)
PlacementConfig.MAX_PLACED_UNITS = 100

-- 是否允许重叠放置
PlacementConfig.ALLOW_OVERLAP = false

-- 放置时的最小间距 (studs)
PlacementConfig.MIN_SPACING = 0

-- ==================== 高光效果配置 ====================

-- 放置预览时的高光颜色 (绿色)
PlacementConfig.HIGHLIGHT_COLOR_VALID = Color3.fromRGB(0, 255, 0)

-- 无效位置的高光颜色 (红色)
PlacementConfig.HIGHLIGHT_COLOR_INVALID = Color3.fromRGB(255, 0, 0)

-- 高光填充透明度
PlacementConfig.HIGHLIGHT_FILL_TRANSPARENCY = 0.4

-- 高光边框透明度
PlacementConfig.HIGHLIGHT_OUTLINE_TRANSPARENCY = 0

-- ==================== 放置动画配置 ====================

-- 放置时的缩放动画时长 (秒)
PlacementConfig.PLACEMENT_SCALE_DURATION = 0.2

-- 放置时的初始缩放
PlacementConfig.PLACEMENT_INITIAL_SCALE = 0.5

-- ==================== 位置计算配置 ====================

-- 模型放置时的Y轴偏移 (相对于IdleFloor表面)
PlacementConfig.PLACEMENT_Y_OFFSET = 2.5

-- ==================== 验证配置 ====================

-- 是否启用严格的边界检查
PlacementConfig.STRICT_BOUNDARY_CHECK = true

-- 是否启用碰撞检测
PlacementConfig.ENABLE_COLLISION_CHECK = true

-- ==================== 工具函数 ====================

--[[
将世界坐标转换为网格索引
@param worldPos Vector3 - 世界坐标
@param floorCenter Vector3 - 地板中心坐标
@return number, number - 网格索引 (gridX, gridZ)
]]
function PlacementConfig.WorldToGrid(worldPos, floorCenter)
    -- 计算相对于地板中心的偏移
    local offsetX = worldPos.X - floorCenter.X
    local offsetZ = worldPos.Z - floorCenter.Z

    -- 转换为网格索引 (从地板左下角开始,0-based)
    -- 地板范围: [-60, 60] studs (相对于中心)
    -- 网格范围: [0, 30) (30个格子，每格4 studs)
    local gridX = math.floor((offsetX + PlacementConfig.IDLE_FLOOR_SIZE.X / 2) / PlacementConfig.GRID_UNIT_SIZE)
    local gridZ = math.floor((offsetZ + PlacementConfig.IDLE_FLOOR_SIZE.Z / 2) / PlacementConfig.GRID_UNIT_SIZE)

    return gridX, gridZ
end

--[[
将网格索引转换为世界坐标
@param gridX number - 网格X索引
@param gridZ number - 网格Z索引
@param floorCenter Vector3 - 地板中心坐标
@return Vector3 - 世界坐标
]]
function PlacementConfig.GridToWorld(gridX, gridZ, floorCenter)
    -- 计算网格中心的世界坐标
    local worldX = floorCenter.X - PlacementConfig.IDLE_FLOOR_SIZE.X / 2 + gridX * PlacementConfig.GRID_UNIT_SIZE + PlacementConfig.GRID_UNIT_SIZE / 2
    local worldZ = floorCenter.Z - PlacementConfig.IDLE_FLOOR_SIZE.Z / 2 + gridZ * PlacementConfig.GRID_UNIT_SIZE + PlacementConfig.GRID_UNIT_SIZE / 2
    local worldY = floorCenter.Y + PlacementConfig.IDLE_FLOOR_SIZE.Y / 2 + PlacementConfig.PLACEMENT_Y_OFFSET

    return Vector3.new(worldX, worldY, worldZ)
end

--[[
检查网格索引是否在有效范围内
@param gridX number - 网格X索引
@param gridZ number - 网格Z索引
@param unitGridSize number - 兵种占地大小 (1, 4, 9)
@return boolean - 是否在有效范围内
]]
function PlacementConfig.IsGridInBounds(gridX, gridZ, unitGridSize)
    -- 计算兵种占据的网格尺寸 (1格=1x1, 4格=2x2, 9格=3x3)
    local gridWidth = math.sqrt(unitGridSize)

    -- 检查边界 (考虑兵种大小)
    if gridX < 0 or gridZ < 0 then
        return false
    end

    if gridX + gridWidth > PlacementConfig.GRID_COUNT_X or
       gridZ + gridWidth > PlacementConfig.GRID_COUNT_Z then
        return false
    end

    return true
end

return PlacementConfig
