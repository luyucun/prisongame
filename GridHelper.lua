--[[
脚本名称: GridHelper
脚本类型: ModuleScript (客户端工具类)
脚本位置: StarterPlayer/StarterPlayerScripts/Utils/GridHelper
]]

--[[
Grid脚底提示块辅助工具模块
职责:
1. 管理放置过程中的Grid脚底提示块
2. 根据占地大小复制对应的Grid Part
3. 实时跟随模型位置
4. 根据位置冲突切换绿色/红色Grid
版本: V1.2.1
]]

local GridHelper = {}

-- 引用服务
local Workspace = game:GetService("Workspace")

-- 配置常量
local PLACEMENT_Y_OFFSET = 2.5  -- 模型在地面上方的偏移量（与PlacementConfig保持一致）

-- Grid引用
local gridFolder = nil
local gridTemplates = {}

-- 当前显示的Grid Part
local currentGridPart = nil

-- V1.4.1: Grid状态缓存（防止不必要的重建）
local gridStateCache = {
	gridSize = nil,
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

    -- 预定义需要的模板列表
    local requiredTemplates = {"GridGreen1", "GridGreen2", "GridGreen3", "GridRed1", "GridRed2", "GridRed3"}

    -- 初始化所有键
    for _, name in ipairs(requiredTemplates) do
        gridTemplates[name] = nil
    end

    -- 尝试从Grid文件夹中查找所有模板
    local foundCount = 0
    for _, name in ipairs(requiredTemplates) do
        local template = gridFolder:FindFirstChild(name)
        if template then
            gridTemplates[name] = template
            foundCount = foundCount + 1
        else
            -- 异步等待模板出现
            task.spawn(function()
                local found = gridFolder:WaitForChild(name, 10)
                if found then
                    gridTemplates[name] = found
                else
                    warn(string.format("[GridHelper] 10秒内未找到模板: %s", name))
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

-- ==================== Grid管理 ====================

--[[
显示Grid提示块
@param gridSize number - 占地大小 (1, 4, 9)
@param position Vector3 - 世界坐标
@param isValid boolean - 是否为有效位置 (true=绿色, false=红色)
@return Part|nil - 创建的Grid Part
]]
function GridHelper.ShowGrid(gridSize, position, isValid)
    -- 如果Grid文件夹不存在，静默失败
    if not gridFolder then
        return nil
    end

    -- 确定要使用的模板名称
    local gridWidth = math.sqrt(gridSize)  -- 1, 2, 3
    local templateName = isValid and ("GridGreen" .. gridWidth) or ("GridRed" .. gridWidth)

    -- V1.4.1: 检查是否需要切换模板（尺寸或颜色改变）
    local needChangeTemplate = false
    if gridStateCache.gridSize ~= gridSize or gridStateCache.isValid ~= isValid then
        needChangeTemplate = true
    end

    -- V1.4.1: 如果需要切换模板，销毁旧的重建新的
    if needChangeTemplate then
        GridHelper.HideGrid()

        -- 从缓存中获取模板
        local template = gridTemplates[templateName]
        if template == nil then
            template = gridFolder:WaitForChild(templateName, 5)
            if template then
                gridTemplates[templateName] = template
            end
        end

        if not template then
            if not gridTemplates["_warned_" .. templateName] then
                warn(string.format("[GridHelper] 模板%s暂未加载", templateName))
                gridTemplates["_warned_" .. templateName] = true
            end
            return nil
        end

        -- 克隆Grid Part
        currentGridPart = template:Clone()
        currentGridPart.Name = "ActiveGridIndicator"
        currentGridPart.Anchored = true
        currentGridPart.CanCollide = false
        currentGridPart.CanQuery = false  -- V1.4.1: 防止射线检测命中指示块导致闪烁
        currentGridPart.CanTouch = false  -- V1.4.1: 同时禁用触摸检测
        currentGridPart.Parent = Workspace

        -- 更新状态缓存
        gridStateCache.gridSize = gridSize
        gridStateCache.isValid = isValid
    end

    -- V1.4.1: 无论是否切换模板，都更新位置（如果位置改变）
    if currentGridPart and currentGridPart.Parent then
        local gridY = position.Y - PLACEMENT_Y_OFFSET
        local newPos = Vector3.new(position.X, gridY, position.Z)

        -- 只在位置真正改变时才更新（避免不必要的CFrame操作）
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
        local gridY = position.Y - PLACEMENT_Y_OFFSET
        currentGridPart.Position = Vector3.new(position.X, gridY, position.Z)
    end
end

--[[
更新Grid颜色（切换绿色/红色）
@param gridSize number - 占地大小
@param isValid boolean - 是否为有效位置
@param position Vector3 - 当前位置
]]
function GridHelper.UpdateGridColor(gridSize, isValid, position)
    -- 简单方法：移除旧的，创建新的
    GridHelper.ShowGrid(gridSize, position, isValid)
end

--[[
隐藏并移除Grid提示块
]]
function GridHelper.HideGrid()
    if currentGridPart and currentGridPart.Parent then
        currentGridPart:Destroy()
        currentGridPart = nil
    end

    -- V1.4.1: 清空状态缓存
    gridStateCache.gridSize = nil
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
获取Grid的显示名称
@param gridSize number
@param isValid boolean
@return string
]]
function GridHelper.GetGridName(gridSize, isValid)
    local gridWidth = math.sqrt(gridSize)
    local color = isValid and "Green" or "Red"
    return string.format("Grid%s%d", color, gridWidth)
end

return GridHelper
