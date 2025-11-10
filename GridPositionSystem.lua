--[[
=====================================================
脚本名称: GridPositionSystem
脚本类型: ModuleScript (服务端)
脚本位置: ServerScriptService/Systems/GridPositionSystem.lua
=====================================================

功能描述:
- 格子坐标与世界坐标的转换
- IdleFloor间的位置映射
- 支持兵种位置保存和恢复

坐标系统:
- 格子大小: 动态计算（基于IdleFloor实际尺寸）
- 范围: 1~14 (X和Y)
- 原点: IdleFloor中心
- Y轴: 地板上方0.5 studs

V2.0修复: 移除硬编码尺寸，支持任意大小的IdleFloor
- 基地IdleFloor: 120x120 studs
- 关卡IdleFloorEnemy: 56x56 studs

]]

local GridPositionSystem = {}

-- 配置
local GRID_SIZE = 4  -- 每格4x4 studs
local GRID_ROWS = 14
local GRID_COLUMNS = 14
local Y_OFFSET = 3  -- V2.0修复：地板上方偏移（从0.5改为3，确保兵种模型站在地板上而不是插入地板）

--[[
    将世界坐标转换为格子坐标
    @param idleFloor Part - IdleFloor引用
    @param worldCFrame CFrame - 世界坐标
    @return table {X=number, Y=number} - 格子坐标(1~14)
]]
function GridPositionSystem.WorldToGrid(idleFloor, worldCFrame)
    if not idleFloor or not worldCFrame then
        warn("[GridPositionSystem] WorldToGrid: 参数无效")
        return {X = 0, Y = 0}
    end

    -- V2.0修复：使用CFrame本地坐标变换，正确处理旋转的IdleFloor
    local floorCFrame = idleFloor.CFrame
    local floorSize = idleFloor.Size

    -- 将世界坐标转换到IdleFloor的本地坐标系
    local localPos = floorCFrame:PointToObjectSpace(worldCFrame.Position)

    -- 根据实际尺寸动态计算格子大小和半宽
    local halfX = floorSize.X * 0.5
    local halfZ = floorSize.Z * 0.5
    local cellX = floorSize.X / GRID_COLUMNS
    local cellZ = floorSize.Z / GRID_ROWS

    -- 在本地坐标系中计算格子索引
    -- 本地坐标系：X轴向右，Z轴向前（负Z是前方）
    local gridX = math.floor((localPos.X + halfX) / cellX) + 1
    local gridY = math.floor((localPos.Z + halfZ) / cellZ) + 1

    -- 限制范围
    gridX = math.clamp(gridX, 1, GRID_COLUMNS)
    gridY = math.clamp(gridY, 1, GRID_ROWS)

    return {X = gridX, Y = gridY}
end

--[[
    将格子坐标转换为世界坐标
    @param idleFloor Part - IdleFloor引用
    @param gridPos table {X=number, Y=number} - 格子坐标
    @return CFrame - 世界坐标
]]
function GridPositionSystem.GridToWorld(idleFloor, gridPos)
    if not idleFloor or not gridPos then
        warn("[GridPositionSystem] GridToWorld: 参数无效")
        return CFrame.new()
    end

    -- 验证格子坐标范围
    local x = math.clamp(gridPos.X, 1, GRID_COLUMNS)
    local y = math.clamp(gridPos.Y, 1, GRID_ROWS)

    -- V2.0修复：使用CFrame本地坐标变换，正确处理旋转的IdleFloor
    local floorCFrame = idleFloor.CFrame
    local floorSize = idleFloor.Size

    -- 根据实际尺寸动态计算格子大小和半宽
    local halfX = floorSize.X * 0.5
    local halfZ = floorSize.Z * 0.5
    local cellX = floorSize.X / GRID_COLUMNS
    local cellZ = floorSize.Z / GRID_ROWS

    -- 在本地坐标系中计算格子中心的偏移
    -- 公式：本地偏移 = -半宽 + (格子索引 - 0.5) * 格子大小
    local offsetX = -halfX + (x - 0.5) * cellX
    local offsetZ = -halfZ + (y - 0.5) * cellZ
    local offsetY = floorSize.Y / 2 + Y_OFFSET  -- 地板表面之上

    -- 创建本地坐标的CFrame
    local localPos = Vector3.new(offsetX, offsetY, offsetZ)

    -- 将本地坐标转换到世界坐标
    local worldCFrame = floorCFrame * CFrame.new(localPos)

    return worldCFrame
end

--[[
    保存兵种的格子坐标
    @param unitInstance Model - 兵种实例
    @param homeIdleFloor Part - 基地IdleFloor
    @return table {X=number, Y=number} - 格子坐标
]]
function GridPositionSystem.SaveUnitGridPosition(unitInstance, homeIdleFloor)
    if not unitInstance or not homeIdleFloor then
        warn("[GridPositionSystem] SaveUnitGridPosition: 参数无效")
        return {X = 0, Y = 0}
    end

    -- 获取兵种的世界坐标
    local unitCFrame
    if unitInstance.PrimaryPart then
        unitCFrame = unitInstance.PrimaryPart.CFrame
    elseif unitInstance:FindFirstChild("HumanoidRootPart") then
        unitCFrame = unitInstance.HumanoidRootPart.CFrame
    else
        warn("[GridPositionSystem] SaveUnitGridPosition: 找不到兵种根部件")
        return {X = 0, Y = 0}
    end

    -- 转换为格子坐标
    local gridPos = GridPositionSystem.WorldToGrid(homeIdleFloor, unitCFrame)

    -- 保存到Attribute（可选，用于持久化）
    unitInstance:SetAttribute("GridPosX", gridPos.X)
    unitInstance:SetAttribute("GridPosY", gridPos.Y)

    return gridPos
end

--[[
    将格子坐标映射到目标IdleFloor
    @param gridPos table {X=number, Y=number} - 格子坐标
    @param targetIdleFloor Part - 目标IdleFloor
    @return CFrame - 目标IdleFloor上的世界坐标
]]
function GridPositionSystem.MapToTargetFloor(gridPos, targetIdleFloor)
    if not gridPos or not targetIdleFloor then
        warn("[GridPositionSystem] MapToTargetFloor: 参数无效")
        return CFrame.new()
    end

    -- 直接使用GridToWorld转换
    return GridPositionSystem.GridToWorld(targetIdleFloor, gridPos)
end

--[[
    从兵种实例读取保存的格子坐标
    @param unitInstance Model - 兵种实例
    @param idleFloor Part - IdleFloor引用（可选，用于兼容历史数据）
    @return table {X=number, Y=number} - 格子坐标
]]
function GridPositionSystem.LoadUnitGridPosition(unitInstance, idleFloor)
    if not unitInstance then
        warn("[GridPositionSystem] LoadUnitGridPosition: 参数无效")
        return {X = 0, Y = 0}
    end

    local gridX = unitInstance:GetAttribute("GridPosX")
    local gridY = unitInstance:GetAttribute("GridPosY")

    -- 兼容历史数据：如果属性不存在或为0，则从当前位置重新计算
    if (not gridX or gridX == 0) and idleFloor then
        warn("[GridPositionSystem] 检测到历史数据，重新计算GridPos:", unitInstance.Name)

        -- 从当前世界坐标重新计算
        local unitCFrame
        if unitInstance.PrimaryPart then
            unitCFrame = unitInstance.PrimaryPart.CFrame
        elseif unitInstance:FindFirstChild("HumanoidRootPart") then
            unitCFrame = unitInstance.HumanoidRootPart.CFrame
        end

        if unitCFrame then
            local gridPos = GridPositionSystem.WorldToGrid(idleFloor, unitCFrame)

            -- 立即保存到Attribute
            unitInstance:SetAttribute("GridPosX", gridPos.X)
            unitInstance:SetAttribute("GridPosY", gridPos.Y)

            print("[GridPositionSystem] 历史数据已修复，GridPos:", gridPos.X, gridPos.Y)

            return gridPos
        end
    end

    return {X = gridX or 0, Y = gridY or 0}
end

--[[
    验证格子坐标是否有效
    @param gridPos table {X=number, Y=number} - 格子坐标
    @return boolean - 是否有效
]]
function GridPositionSystem.IsValidGridPos(gridPos)
    if not gridPos or type(gridPos) ~= "table" then
        return false
    end

    if type(gridPos.X) ~= "number" or type(gridPos.Y) ~= "number" then
        return false
    end

    if gridPos.X < 1 or gridPos.X > GRID_COLUMNS then
        return false
    end

    if gridPos.Y < 1 or gridPos.Y > GRID_ROWS then
        return false
    end

    return true
end

--[[
    获取格子信息（用于调试）
    @param idleFloor Part - IdleFloor引用
    @return table - 格子信息
]]
function GridPositionSystem.GetGridInfo(idleFloor)
    if not idleFloor then
        return nil
    end

    local floorSize = idleFloor.Size
    local cellX = floorSize.X / GRID_COLUMNS
    local cellZ = floorSize.Z / GRID_ROWS

    return {
        CellSizeX = cellX,
        CellSizeZ = cellZ,
        Rows = GRID_ROWS,
        Columns = GRID_COLUMNS,
        YOffset = Y_OFFSET,
        CenterPosition = idleFloor.CFrame.Position,
        FloorSize = floorSize
    }
end

-- 导出
return GridPositionSystem
