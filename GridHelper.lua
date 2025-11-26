--[[
脚本名称: GridHelper
脚本类型: ModuleScript (客户端工具类)
脚本位置: StarterPlayer/StarterPlayerScripts/Utils/GridHelper
]]

--[[
Grid脚底提示块辅助工具模块 (V2.0重构: 支持任意矩形占地)
职责:
1. 管理放置过程中的Grid脚底提示块
2. 根据占地尺寸(GridWidth x GridDepth)动态调整Grid大小
3. 实时跟随模型位置
4. 根据位置冲突切换绿色/红色Grid
版本: V2.0

占地尺寸约定:
- GridWidth: X轴方向占用的格子数
- GridDepth: Z轴方向占用的格子数
- 支持任意矩形: 1x1, 1x2, 2x2, 2x3, 3x3, 4x7 等
]]

local GridHelper = {}

-- 引用服务
local Workspace = game:GetService("Workspace")

-- 配置常量
local PLACEMENT_Y_OFFSET = 3  -- 兵种脚底距离地板上表面的距离
local GRID_Y_OFFSET = 0.01     -- Grid距离地板上表面的微小偏移
local GRID_UNIT_SIZE = 4       -- 每个格子的studs大小
local GRID_THICKNESS = 0.1     -- Grid厚度

-- Grid颜色配置
local GRID_COLOR_VALID = Color3.fromRGB(0, 255, 0)      -- 绿色
local GRID_COLOR_INVALID = Color3.fromRGB(255, 0, 0)    -- 红色
local GRID_TRANSPARENCY = 0.3                            -- 透明度

-- Grid引用
local gridFolder = nil
local gridTemplates = {}

-- 当前显示的Grid Part
local currentGridPart = nil

-- V2.0.4新增: IdleFloor引用（用于精确计算Grid的Y坐标）
local cachedIdleFloor = nil

-- V2.0: Grid状态缓存（使用GridWidth和GridDepth）
local gridStateCache = {
    gridWidth = nil,
    gridDepth = nil,
    isValid = nil,
    position = nil
}

-- ==================== 初始化 ====================

--[[
初始化Grid模板引用
]]
function GridHelper.Initialize()
    -- 尝试多次查找Grid文件夹
    local maxRetries = 5
    local retryCount = 0

    while not gridFolder and retryCount < maxRetries do
        gridFolder = Workspace:FindFirstChild("Grid")
        if not gridFolder then
            warn(string.format("[GridHelper] 第%d次尝试：找不到Workspace/Grid文件夹，等待0.5秒后重试...", retryCount + 1))
            task.wait(0.5)
            retryCount = retryCount + 1
        end
    end

    if not gridFolder then
        warn("[GridHelper] 最终未找到Workspace/Grid文件夹！Grid提示功能将被禁用。")
        return false
    end

    -- V2.0: 预定义正方形模板（用于常见尺寸，非正方形会动态创建）
    local requiredTemplates = {"GridGreen1", "GridGreen2", "GridGreen3", "GridRed1", "GridRed2", "GridRed3"}

    -- 初始化所有键
    for _, name in ipairs(requiredTemplates) do
        gridTemplates[name] = nil
    end

    -- 尝试从Grid文件夹中查找所有模板
    for _, name in ipairs(requiredTemplates) do
        local template = gridFolder:FindFirstChild(name)
        if template then
            gridTemplates[name] = template
        else
            -- 异步等待模板出现
            task.spawn(function()
                local found = gridFolder:WaitForChild(name, 10)
                if found then
                    gridTemplates[name] = found
                end
            end)
        end
    end

    -- 监听Grid文件夹的新增子对象（动态等待加载）
    gridFolder.ChildAdded:Connect(function(child)
        if gridTemplates[child.Name] == nil and table.find(requiredTemplates, child.Name) then
            gridTemplates[child.Name] = child
        end
    end)

    return true
end

--[[
V2.0.4新增: 设置IdleFloor引用（用于精确计算Grid的Y坐标）
@param idleFloor Part - IdleFloor对象
]]
function GridHelper.SetIdleFloor(idleFloor)
    cachedIdleFloor = idleFloor
end

--[[
V2.0.4新增: 获取当前缓存的IdleFloor
@return Part|nil
]]
function GridHelper.GetIdleFloor()
    return cachedIdleFloor
end

-- ==================== Grid管理 ====================

--[[
创建动态Grid Part (V2.0新增: 支持任意矩形)
@param gridWidth number - X轴方向格子数
@param gridDepth number - Z轴方向格子数
@param isValid boolean - 是否为有效位置
@return Part - 创建的Grid Part
]]
local function CreateDynamicGrid(gridWidth, gridDepth, isValid)
    local grid = Instance.new("Part")
    grid.Name = "ActiveGridIndicator"
    grid.Anchored = true
    grid.CanCollide = false
    grid.CanQuery = false
    grid.CanTouch = false
    grid.Material = Enum.Material.Neon
    grid.Color = isValid and GRID_COLOR_VALID or GRID_COLOR_INVALID
    grid.Transparency = GRID_TRANSPARENCY

    -- 计算实际大小 (studs)
    local sizeX = gridWidth * GRID_UNIT_SIZE
    local sizeZ = gridDepth * GRID_UNIT_SIZE
    grid.Size = Vector3.new(sizeX, GRID_THICKNESS, sizeZ)

    return grid
end

--[[
显示Grid提示块 (V2.0重构: 支持矩形占地)
@param gridWidth number - X轴方向格子数 (或旧版gridSize用于向后兼容)
@param position Vector3 - 世界坐标
@param isValid boolean - 是否为有效位置 (true=绿色, false=红色)
@param gridDepth number - Z轴方向格子数 (可选,默认等于gridWidth)
@return Part|nil - 创建的Grid Part

注: 为了向后兼容,如果只传gridWidth(原gridSize),则视为正方形
]]
function GridHelper.ShowGrid(gridWidth, position, isValid, gridDepth)
    -- 如果Grid文件夹不存在，静默失败
    if not gridFolder then
        return nil
    end

    -- 处理默认参数
    gridWidth = gridWidth or 1
    gridDepth = gridDepth or gridWidth

    -- V2.0: 检查是否需要切换模板（尺寸或颜色改变）
    local needChangeTemplate = false
    if gridStateCache.gridWidth ~= gridWidth or
       gridStateCache.gridDepth ~= gridDepth or
       gridStateCache.isValid ~= isValid then
        needChangeTemplate = true
    end

    -- V2.0: 如果需要切换模板，销毁旧的重建新的
    if needChangeTemplate then
        GridHelper.HideGrid()

        -- 检查是否为正方形且有预设模板
        if gridWidth == gridDepth and gridWidth <= 3 then
            -- 使用预设的正方形模板
            local templateName = isValid and ("GridGreen" .. gridWidth) or ("GridRed" .. gridWidth)
            local template = gridTemplates[templateName]

            if template == nil then
                template = gridFolder:WaitForChild(templateName, 2)
                if template then
                    gridTemplates[templateName] = template
                end
            end

            if template then
                currentGridPart = template:Clone()
                currentGridPart.Name = "ActiveGridIndicator"
                currentGridPart.Anchored = true
                currentGridPart.CanCollide = false
                currentGridPart.CanQuery = false
                currentGridPart.CanTouch = false
            else
                -- 预设模板不存在，动态创建
                currentGridPart = CreateDynamicGrid(gridWidth, gridDepth, isValid)
            end
        else
            -- 非正方形或大尺寸，动态创建Grid
            currentGridPart = CreateDynamicGrid(gridWidth, gridDepth, isValid)
        end

        currentGridPart.Parent = Workspace

        -- 更新状态缓存
        gridStateCache.gridWidth = gridWidth
        gridStateCache.gridDepth = gridDepth
        gridStateCache.isValid = isValid
    end

    -- V2.0.4修复: 无论是否切换模板，都更新位置（如果位置改变）
    if currentGridPart and currentGridPart.Parent then
        -- V2.0.4修复: Grid的Y坐标直接使用IdleFloor顶面，不依赖模型位置
        local gridY
        if cachedIdleFloor and cachedIdleFloor.Parent then
            -- 使用IdleFloor顶面 + 微小偏移
            gridY = cachedIdleFloor.Position.Y + cachedIdleFloor.Size.Y / 2 + GRID_Y_OFFSET
        else
            -- 回退到旧逻辑（兼容性）
            gridY = position.Y - PLACEMENT_Y_OFFSET + GRID_Y_OFFSET
        end
        local newPos = Vector3.new(position.X, gridY, position.Z)

        -- 只在位置真正改变时才更新
        if not gridStateCache.position or (position - gridStateCache.position).Magnitude > 0.01 then
            currentGridPart.Position = newPos
            gridStateCache.position = position
        end
    end

    return currentGridPart
end

--[[
更新Grid位置
@param position Vector3 - 新的世界坐标
]]
function GridHelper.UpdateGridPosition(position)
    if currentGridPart and currentGridPart.Parent then
        local gridY = position.Y - PLACEMENT_Y_OFFSET + GRID_Y_OFFSET
        currentGridPart.Position = Vector3.new(position.X, gridY, position.Z)
    end
end

--[[
更新Grid颜色（切换绿色/红色）(V2.0重构)
@param gridWidth number - X轴方向格子数
@param isValid boolean - 是否为有效位置
@param position Vector3 - 当前位置
@param gridDepth number - Z轴方向格子数 (可选)
]]
function GridHelper.UpdateGridColor(gridWidth, isValid, position, gridDepth)
    GridHelper.ShowGrid(gridWidth, position, isValid, gridDepth)
end

--[[
隐藏并移除Grid提示块
]]
function GridHelper.HideGrid()
    if currentGridPart and currentGridPart.Parent then
        currentGridPart:Destroy()
        currentGridPart = nil
    end

    -- V2.0: 清空状态缓存
    gridStateCache.gridWidth = nil
    gridStateCache.gridDepth = nil
    gridStateCache.isValid = nil
    gridStateCache.position = nil
end

--[[
检查是否正在显示Grid
@return boolean
]]
function GridHelper.IsGridVisible()
    return currentGridPart ~= nil and currentGridPart.Parent ~= nil
end

--[[
获取当前Grid Part
@return Part|nil
]]
function GridHelper.GetCurrentGrid()
    return currentGridPart
end

-- ==================== 工具函数 ====================

--[[
获取Grid的显示名称 (V2.0重构)
@param gridWidth number - X轴方向格子数
@param isValid boolean
@param gridDepth number - Z轴方向格子数 (可选)
@return string
]]
function GridHelper.GetGridName(gridWidth, isValid, gridDepth)
    gridDepth = gridDepth or gridWidth
    local color = isValid and "Green" or "Red"
    if gridWidth == gridDepth then
        return string.format("Grid%s%d", color, gridWidth)
    else
        return string.format("Grid%s%dx%d", color, gridWidth, gridDepth)
    end
end

return GridHelper
