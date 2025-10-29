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

-- ==================== 初始化 ====================

--[[
初始化Grid模板引用
]]
function GridHelper.Initialize()
    gridFolder = Workspace:FindFirstChild("Grid")

    if not gridFolder then
        warn("[GridHelper] 找不到Workspace/Grid文件夹!")
        return false
    end

    print("[GridHelper] 找到Grid文件夹，开始缓存模板...")

    -- 缓存所有Grid模板（绿色和红色）
    gridTemplates["GridGreen1"] = gridFolder:FindFirstChild("GridGreen1")
    gridTemplates["GridGreen2"] = gridFolder:FindFirstChild("GridGreen2")
    gridTemplates["GridGreen3"] = gridFolder:FindFirstChild("GridGreen3")
    gridTemplates["GridRed1"] = gridFolder:FindFirstChild("GridRed1")
    gridTemplates["GridRed2"] = gridFolder:FindFirstChild("GridRed2")
    gridTemplates["GridRed3"] = gridFolder:FindFirstChild("GridRed3")

    -- 验证所有模板
    local allValid = true
    local missingTemplates = {}

    for name, template in pairs(gridTemplates) do
        if not template then
            warn(string.format("[GridHelper] 找不到%s模板!", name))
            table.insert(missingTemplates, name)
            allValid = false
        else
            print(string.format("[GridHelper] 成功加载模板: %s", name))
        end
    end

    if allValid then
        print("[GridHelper] 初始化成功，所有Grid模板已加载")
    else
        warn(string.format("[GridHelper] 初始化失败，缺少模板: %s", table.concat(missingTemplates, ", ")))
    end

    return allValid
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
    -- 移除旧的Grid
    GridHelper.HideGrid()

    -- 确定要使用的模板名称
    local gridWidth = math.sqrt(gridSize)  -- 1, 2, 3
    local templateName = isValid and ("GridGreen" .. gridWidth) or ("GridRed" .. gridWidth)

    -- 从缓存中获取模板
    local template = gridTemplates[templateName]

    if not template then
        warn(string.format("[GridHelper] 找不到Grid模板: %s", templateName))
        return nil
    end

    -- 克隆Grid Part
    currentGridPart = template:Clone()
    currentGridPart.Name = "ActiveGridIndicator"

    -- 设置位置（贴在地面上）
    -- Grid应该放在IdleFloor的表面上，模型在地面上方PLACEMENT_Y_OFFSET
    -- Grid需要在模型下方，所以Y坐标为 position.Y - PLACEMENT_Y_OFFSET
    local gridY = position.Y - PLACEMENT_Y_OFFSET
    currentGridPart.Position = Vector3.new(position.X, gridY, position.Z)

    -- 设置属性
    currentGridPart.Anchored = true
    currentGridPart.CanCollide = false

    -- 放入Workspace
    currentGridPart.Parent = Workspace

    print(string.format("[GridHelper] 显示Grid - 模板:%s 大小:%d 位置:(%.1f, %.1f, %.1f)",
        templateName, gridSize, position.X, position.Y, position.Z))

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
        print("[GridHelper] 已隐藏Grid")
    end
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
