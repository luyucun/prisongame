--[[
脚本名称: PlacementConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/PlacementConfig
]]

--[[
放置系统配置模块
职责: 存储兵种放置系统的配置参数
版本: V2.0 - 重构支持任意矩形占地 (MxN格子)

占地尺寸约定:
- GridWidth: X轴方向占用的格子数 (宽度)
- GridDepth: Z轴方向占用的格子数 (深度)
- 例如: 1x1, 1x2, 2x2, 2x3, 3x3, 4x7 等任意矩形
- 兵种配置中使用 GridWidth 和 GridDepth 两个字段
- 为了向后兼容,如果只配置了 GridSize,则视为正方形 (GridWidth=GridDepth=GridSize)
]]

local PlacementConfig = {}

-- ==================== 地板相关配置 ====================

-- IdleFloor的名称
PlacementConfig.IDLE_FLOOR_NAME = "IdleFloor"

-- IdleFloor的标准大小 (X, Y, Z) - 实际尺寸
PlacementConfig.IDLE_FLOOR_SIZE = Vector3.new(56, 1, 56)

-- 单个格子的大小 (4 studs)
-- 说明: 1格兵种占据4x4 studs，2格兵种(2x2格)占据8x8 studs，3格兵种(3x3格)占据12x12 studs
PlacementConfig.GRID_UNIT_SIZE = 4

-- 网格数量 (56 / 4 = 14，所以是14x14个格子)
PlacementConfig.GRID_COUNT_X = 14
PlacementConfig.GRID_COUNT_Z = 14

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
-- 注意: 由于所有兵种模型的Pivot已经设置到脚底,所以Y偏移改为0
-- 之前腰部Pivot需要+3才能让脚落地,现在脚底Pivot直接对齐地板即可
PlacementConfig.PLACEMENT_Y_OFFSET = 0

-- ==================== 验证配置 ====================

-- 是否启用严格的边界检查
PlacementConfig.STRICT_BOUNDARY_CHECK = true

-- 是否启用碰撞检测
PlacementConfig.ENABLE_COLLISION_CHECK = true

-- ==================== 工具函数 ====================

--[[
解析占地尺寸,将各种格式统一为 {Width, Depth} 格式
支持的输入格式:
1. {GridWidth=2, GridDepth=3} -> {2, 3}
2. {GridWidth=2} -> {2, 2} (正方形)
3. {GridSize=2} -> {2, 2} (向后兼容,正方形边长)
4. 数字 2 -> {2, 2} (向后兼容,正方形边长)
5. nil -> {1, 1} (默认1x1)

@param gridSizeData table|number|nil - 占地尺寸数据
@return number, number - GridWidth, GridDepth
]]
function PlacementConfig.ParseGridSize(gridSizeData)
	-- 默认1x1
	if gridSizeData == nil then
		return 1, 1
	end

	-- 数字: 向后兼容,视为正方形边长
	if type(gridSizeData) == "number" then
		local size = math.max(1, math.floor(gridSizeData :: number))
		return size, size
	end

	-- table格式
	if type(gridSizeData) == "table" then
		local tbl = gridSizeData :: {[string]: any}
		local width = tbl.GridWidth or tbl.Width or tbl.GridSize or 1
		local depth = tbl.GridDepth or tbl.Depth or tbl.GridSize or width
		return math.max(1, math.floor(width)), math.max(1, math.floor(depth))
	end

	-- 其他情况返回默认值
	return 1, 1
end

--[[
将世界坐标转换为网格索引 (V2.0.4修复: 支持矩形占地，修正中心点偏移问题)
@param worldPos Vector3 - 世界坐标（模型中心点）
@param floorCenter Vector3 - 地板中心坐标
@param gridWidth number - X轴方向占用格子数 (可选，默认1)
@param gridDepth number - Z轴方向占用格子数 (可选，默认等于gridWidth)
@return number, number - 网格索引 (gridX, gridZ)，表示占地区域左下角的格子
注意: 返回的网格索引可能超出边界,调用方应使用ClampGridToBounds进行边界处理
]]
function PlacementConfig.WorldToGrid(worldPos, floorCenter, gridWidth, gridDepth)
    -- 处理默认参数
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    -- V2.0.4: 计算占地的半宽/半深（studs）
    -- 模型中心点需要减去半个占地宽度才能得到左下角的格子索引
    local halfSpanX = (gridWidth * PlacementConfig.GRID_UNIT_SIZE) / 2
    local halfSpanZ = (gridDepth * PlacementConfig.GRID_UNIT_SIZE) / 2

    -- 计算相对于地板中心的偏移
    local offsetX = worldPos.X - floorCenter.X
    local offsetZ = worldPos.Z - floorCenter.Z

    -- 转换为网格索引 (从地板左下角开始,0-based)
    -- 地板范围: [-28, 28] studs (相对于中心，56/2=28)
    -- 网格范围: [0, 13] (14个格子，每格4 studs)
    -- V2.0.4修正: 从模型中心坐标减去半跨度，得到左下角坐标，再计算格子索引
    local gridX = math.floor((offsetX + PlacementConfig.IDLE_FLOOR_SIZE.X / 2 - halfSpanX + PlacementConfig.GRID_UNIT_SIZE / 2) / PlacementConfig.GRID_UNIT_SIZE)
    local gridZ = math.floor((offsetZ + PlacementConfig.IDLE_FLOOR_SIZE.Z / 2 - halfSpanZ + PlacementConfig.GRID_UNIT_SIZE / 2) / PlacementConfig.GRID_UNIT_SIZE)

    -- 只做基本的非负限制,防止负索引
    gridX = math.max(0, gridX)
    gridZ = math.max(0, gridZ)

    return gridX, gridZ
end

--[[
将网格索引转换为世界坐标 (V2.0重构: 支持矩形占地)
@param gridX number - 网格X索引 (兵种左下角所在格子)
@param gridZ number - 网格Z索引 (兵种左下角所在格子)
@param floorCenter Vector3 - 地板中心坐标
@param gridWidth number - 兵种X轴方向占用格子数 (可选,默认1)
@param gridDepth number - 兵种Z轴方向占用格子数 (可选,默认gridWidth)
@return Vector3 - 世界坐标 (兵种中心位置)

注: 为向后兼容,第4个参数也可以是旧版的gridSize(总格子数如1,4,9),
    此时会自动sqrt转换为正方形边长
]]
function PlacementConfig.GridToWorld(gridX, gridZ, floorCenter, gridWidth, gridDepth)
    -- 处理默认参数和向后兼容
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    -- 向后兼容: 如果gridWidth是旧版gridSize格式(1,4,9),自动转换
    -- 检测方式: 如果只传了gridWidth且没有gridDepth,且值是完全平方数,则按旧逻辑处理
    -- 但为了安全,我们假设新代码总是传正确的gridWidth/gridDepth
    -- 旧代码传gridSize时,gridWidth和gridDepth相等,sqrt后也相等,所以逻辑一致

    -- 计算兵种中心的偏移量
    local halfSpanX = (gridWidth * PlacementConfig.GRID_UNIT_SIZE) / 2
    local halfSpanZ = (gridDepth * PlacementConfig.GRID_UNIT_SIZE) / 2

    -- 计算网格中心的世界坐标
    local worldX = floorCenter.X - PlacementConfig.IDLE_FLOOR_SIZE.X / 2 + gridX * PlacementConfig.GRID_UNIT_SIZE + halfSpanX
    local worldZ = floorCenter.Z - PlacementConfig.IDLE_FLOOR_SIZE.Z / 2 + gridZ * PlacementConfig.GRID_UNIT_SIZE + halfSpanZ
    local worldY = floorCenter.Y + PlacementConfig.IDLE_FLOOR_SIZE.Y / 2 + PlacementConfig.PLACEMENT_Y_OFFSET

    return Vector3.new(worldX, worldY, worldZ)
end

--[[
检查网格索引是否在有效范围内 (V2.0重构: 支持矩形占地)
@param gridX number - 网格X索引
@param gridZ number - 网格Z索引
@param gridWidth number - 兵种X轴方向占用格子数
@param gridDepth number - 兵种Z轴方向占用格子数 (可选,默认gridWidth)
@return boolean - 是否在有效范围内
]]
function PlacementConfig.IsGridInBounds(gridX, gridZ, gridWidth, gridDepth)
    -- 处理默认参数
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    -- 检查边界 (考虑兵种大小)
    if gridX < 0 or gridZ < 0 then
        return false
    end

    if gridX + gridWidth > PlacementConfig.GRID_COUNT_X or
       gridZ + gridDepth > PlacementConfig.GRID_COUNT_Z then
        return false
    end

    return true
end

--[[
限制网格索引在边界内 (V2.0新增)
@param gridX number - 网格X索引
@param gridZ number - 网格Z索引
@param gridWidth number - 兵种X轴方向占用格子数
@param gridDepth number - 兵种Z轴方向占用格子数 (可选,默认gridWidth)
@return number, number - 限制后的gridX, gridZ
]]
function PlacementConfig.ClampGridToBounds(gridX, gridZ, gridWidth, gridDepth)
    -- 处理默认参数
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    -- 计算最大有效索引
    local maxGridX = PlacementConfig.GRID_COUNT_X - gridWidth
    local maxGridZ = PlacementConfig.GRID_COUNT_Z - gridDepth

    gridX = math.clamp(gridX, 0, maxGridX)
    gridZ = math.clamp(gridZ, 0, maxGridZ)

    return gridX, gridZ
end

--[[
检查两个矩形区域是否重叠 (V2.0新增)
@param x1 number - 区域1左下角X
@param z1 number - 区域1左下角Z
@param w1 number - 区域1宽度
@param d1 number - 区域1深度
@param x2 number - 区域2左下角X
@param z2 number - 区域2左下角Z
@param w2 number - 区域2宽度
@param d2 number - 区域2深度
@return boolean - 是否重叠
]]
function PlacementConfig.DoRectsOverlap(x1, z1, w1, d1, x2, z2, w2, d2)
    -- 两个矩形不重叠的条件: 一个在另一个的左边、右边、上边或下边
    -- 重叠 = NOT(不重叠)
    local noOverlapX = (x1 + w1 <= x2) or (x2 + w2 <= x1)
    local noOverlapZ = (z1 + d1 <= z2) or (z2 + d2 <= z1)

    return not (noOverlapX or noOverlapZ)
end

--[[
获取矩形区域占用的所有格子键值 (V2.0新增)
用于网格占用管理
@param gridX number - 左下角网格X索引
@param gridZ number - 左下角网格Z索引
@param gridWidth number - 宽度(格子数)
@param gridDepth number - 深度(格子数)
@return table - 格子键值数组 {"x_z", ...}
]]
function PlacementConfig.GetOccupiedGridKeys(gridX, gridZ, gridWidth, gridDepth)
    local keys = {}
    for i = 0, gridWidth - 1 do
        for j = 0, gridDepth - 1 do
            local key = string.format("%d_%d", gridX + i, gridZ + j)
            table.insert(keys, key)
        end
    end
    return keys
end

return PlacementConfig
