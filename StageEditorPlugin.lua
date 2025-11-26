--[[
=====================================================
脚本名称: StageEditorPlugin
脚本类型: Plugin Script (Roblox Studio插件)
脚本位置: 创建为Studio Plugin
版本: V2.1 - 全新设计
=====================================================

功能描述:
- 固定编辑地板（Workspace/EnemyTemplate/Style01/Stage001/IdleFloorEnemy）
- 通过UI选择兵种、等级、排列生成敌人
- 配置持久化（保存/加载关卡）
- Delete键删除选中兵种
- 导出为EnemyConfig.lua格式

使用方法:
1. 在Studio中安装此插件
2. 点击工具栏"Stage Editor"按钮打开窗口
3. 在UI中选择兵种/等级/排列，点击"生成"
4. 选择关卡，点击"保存"保存当前配置
5. 点击"导出"复制Lua代码到剪贴板
6. 选中兵种模型，按Delete键删除

]]

-- ==================== 服务引用 ====================
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ==================== 插件基础设置 ====================
-- 工具栏
local toolbar = plugin:CreateToolbar("Stage Editor V2.1")
local mainButton = toolbar:CreateButton(
	"Stage Editor",
	"打开关卡编辑器",
	"rbxassetid://6034509993"
)

-- UI窗口
local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false,   -- 初始启用状态
	false,   -- 是否覆盖之前状态
	350,     -- 浮动窗口宽度
	600,     -- 浮动窗口高度
	300,     -- 最小宽度
	400      -- 最小高度
)

local widget = plugin:CreateDockWidgetPluginGui("StageEditorWidget_V2", widgetInfo)
widget.Title = "Stage Editor V2.1"

-- ==================== 全局变量 ====================
local EDITOR_FLOOR_PATH = "Workspace.EnemyTemplate.Style01.Stage001.IdleFloorEnemy"
local editorFloor = nil
local currentStageName = "Stage001"  -- 当前编辑的关卡名
local stageData = {}  -- 所有关卡配置 {["Stage001"] = {...}, ...}
local currentEnemies = {}  -- 当前编辑地板上的敌人列表
local selectedUnitId = "Noob"
local selectedLevel = 1
local selectedGridX = 7
local selectedGridY = 7

-- 网格可视化相关
local gridVisualizationEnabled = false
local gridParts = {}  -- 存储网格Part的表

-- ==================== 辅助函数 ====================

--[[
获取所有可用的兵种ID列表
@return table - 兵种ID数组
]]
local function GetAllUnitIds()
	local unitIds = {}

	-- 尝试从ReplicatedStorage加载UnitConfig
	local success, result = pcall(function()
		local unitConfig = require(ReplicatedStorage:FindFirstChild("Config"):FindFirstChild("UnitConfig"))

		if unitConfig and unitConfig.Units then
			for unitId, _ in pairs(unitConfig.Units) do
				table.insert(unitIds, unitId)
			end
		end

		return unitIds
	end)

	if success and #result > 0 then
		-- 按字母排序
		table.sort(result)
		print(string.format("[StageEditor] ✅ 加载了%d个兵种ID", #result))
		return result
	else
		-- 默认兵种列表
		warn("[StageEditor] ⚠️ 无法加载UnitConfig，使用默认列表")
		return {"Noob", "Rookie", "AK-47", "Mafia"}
	end
end

--[[
获取固定编辑地板
@return Part|nil - 编辑地板
]]
local function GetEditorFloor()
	if editorFloor and editorFloor.Parent then
		return editorFloor
	end

	-- 解析路径
	local success, result = pcall(function()
		local enemyTemplate = workspace:FindFirstChild("EnemyTemplate")
		if not enemyTemplate then
			warn("[StageEditor] Workspace下没有EnemyTemplate文件夹")
			return nil
		end

		local style01 = enemyTemplate:FindFirstChild("Style01")
		if not style01 then
			warn("[StageEditor] EnemyTemplate下没有Style01文件夹")
			return nil
		end

		local stage001 = style01:FindFirstChild("Stage001")
		if not stage001 then
			warn("[StageEditor] Style01下没有Stage001文件夹")
			return nil
		end

		local idleFloorEnemy = stage001:FindFirstChild("IdleFloorEnemy")
		if not idleFloorEnemy then
			warn("[StageEditor] Stage001下没有IdleFloorEnemy")
			return nil
		end

		return idleFloorEnemy
	end)

	if success and result then
		editorFloor = result
		print("[StageEditor] ✅ 找到编辑地板:", EDITOR_FLOOR_PATH)
		return editorFloor
	else
		warn("[StageEditor] ❌ 无法找到编辑地板:", result)
		return nil
	end
end

--[[
计算GridPos转世界坐标
@param floor Part - 地板
@param gridX number - 格子X (1-14，用户输入)
@param gridY number - 格子Y (1-14，用户输入)
@return CFrame - 世界坐标
注意：此算法必须与PlacementHelper.GridToWorld完全一致
]]
local function GridToWorld(floor, gridX, gridY)
	local GRID_UNIT_SIZE = 4
	local GRID_COUNT = 14
	local IDLE_FLOOR_SIZE = Vector3.new(56, 1, 56)  -- 56x56 studs地板
	local PLACEMENT_Y_OFFSET = 3  -- 兵种站在地板上方3 studs

	-- 验证输入范围（1-14）
	gridX = math.clamp(gridX, 1, GRID_COUNT)
	gridY = math.clamp(gridY, 1, GRID_COUNT)

	-- 用户输入1-14，转换为网格索引0-13
	local gridIndexX = gridX - 1
	local gridIndexZ = gridY - 1

	-- 获取地板中心和大小
	local floorCenter = floor.CFrame.Position
	local floorSize = floor.Size

	-- 计算兵种中心的世界坐标（与PlacementHelper.GridToWorld完全一致）
	local gridSize = 1  -- 1x1兵种
	local gridWidth = math.sqrt(gridSize)  -- 1
	local halfSpan = (gridWidth * GRID_UNIT_SIZE) / 2  -- 2

	-- X和Z坐标计算：从地板左下角开始，加上格子索引*格子大小，再加上半格偏移
	local worldX = floorCenter.X - IDLE_FLOOR_SIZE.X / 2 + gridIndexX * GRID_UNIT_SIZE + halfSpan
	local worldZ = floorCenter.Z - IDLE_FLOOR_SIZE.Z / 2 + gridIndexZ * GRID_UNIT_SIZE + halfSpan

	-- Y坐标计算：地板表面 + 3 studs偏移
	local worldY = floorCenter.Y + floorSize.Y / 2 + PLACEMENT_Y_OFFSET

	return CFrame.new(worldX, worldY, worldZ)
end

--[[
计算世界坐标转GridPos (V2.0.4修复: 支持占地尺寸)
@param floor Part - 地板
@param worldPos Vector3 - 世界坐标
@param gridWidth number - X轴方向占用格子数 (可选，默认1)
@param gridDepth number - Z轴方向占用格子数 (可选，默认等于gridWidth)
@return table - {X = gridX, Y = gridY} (1-14，用户可读)
注意：此算法必须与PlacementHelper.WorldToGrid完全一致
]]
local function WorldToGrid(floor, worldPos, gridWidth, gridDepth)
	local GRID_UNIT_SIZE = 4
	local GRID_COUNT = 14
	local IDLE_FLOOR_SIZE = Vector3.new(56, 1, 56)

	-- 处理默认参数
	gridWidth = gridWidth or 1
	gridDepth = gridDepth or gridWidth

	-- V2.0.4: 计算占地的半宽/半深（studs）
	local halfSpanX = (gridWidth * GRID_UNIT_SIZE) / 2
	local halfSpanZ = (gridDepth * GRID_UNIT_SIZE) / 2

	-- 获取地板中心
	local floorCenter = floor.CFrame.Position

	-- 计算相对偏移（世界坐标相对于地板中心）
	local offsetX = worldPos.X - floorCenter.X
	local offsetZ = worldPos.Z - floorCenter.Z

	-- 转换为网格索引（0-13）
	-- V2.0.4修正: 从模型中心坐标减去半跨度，得到左下角坐标，再计算格子索引
	local gridIndexX = math.floor((offsetX + IDLE_FLOOR_SIZE.X / 2 - halfSpanX + GRID_UNIT_SIZE / 2) / GRID_UNIT_SIZE)
	local gridIndexZ = math.floor((offsetZ + IDLE_FLOOR_SIZE.Z / 2 - halfSpanZ + GRID_UNIT_SIZE / 2) / GRID_UNIT_SIZE)

	-- 限制范围在0-13
	gridIndexX = math.clamp(gridIndexX, 0, GRID_COUNT - 1)
	gridIndexZ = math.clamp(gridIndexZ, 0, GRID_COUNT - 1)

	-- 转换为用户可读的1-14
	return {X = gridIndexX + 1, Y = gridIndexZ + 1}
end

--[[
查找兵种模型模板
@param unitId string - 兵种ID
@return Model|nil - 兵种模型模板
]]
local function FindUnitModel(unitId)
	-- 从ReplicatedStorage/Role递归查找
	local function SearchRecursive(folder, targetName)
		local found = folder:FindFirstChild(targetName)
		if found and found:IsA("Model") then
			return found
		end

		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Folder") then
				local result = SearchRecursive(child, targetName)
				if result then
					return result
				end
			end
		end

		return nil
	end

	local roleFolder = ReplicatedStorage:FindFirstChild("Role")
	if not roleFolder then
		warn("[StageEditor] ReplicatedStorage下没有Role文件夹")
		return nil
	end

	return SearchRecursive(roleFolder, unitId)
end

--[[
扫描当前地板上的所有敌人
@return table - 敌人列表
]]
local function ScanEnemies()
	local floor = GetEditorFloor()
	if not floor then
		return {}
	end

	local enemies = {}
	for _, child in ipairs(floor:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChild("HumanoidRootPart") then
			-- 从Attribute或名称解析
			local unitId = child:GetAttribute("UnitId") or child.Name:match("^(%w+)_")
			local level = child:GetAttribute("Level") or tonumber(child.Name:match("_Lv(%d+)_")) or 1

			-- 计算GridPos
			local rootPart = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
			local gridPos = WorldToGrid(floor, rootPart.Position)

			table.insert(enemies, {
				UnitId = unitId or "Unknown",
				Level = level,
				GridPos = gridPos,
				Instance = child
			})
		end
	end

	return enemies
end

--[[
检查格子是否有重叠
@param gridX number - 格子X
@param gridY number - 格子Y
@return boolean, string - 是否重叠，已有兵种名称
]]
local function CheckOverlap(gridX, gridY)
	local enemies = ScanEnemies()

	for _, enemy in ipairs(enemies) do
		if enemy.GridPos.X == gridX and enemy.GridPos.Y == gridY then
			return true, enemy.Instance.Name
		end
	end

	return false, nil
end

-- ==================== 核心功能 ====================

--[[
生成兵种到指定GridPos
@param unitId string - 兵种ID
@param level number - 等级
@param gridX number - 格子X
@param gridY number - 格子Y
@return Model|nil - 生成的兵种实例
]]
local function GenerateUnit(unitId, level, gridX, gridY)
	local floor = GetEditorFloor()
	if not floor then
		warn("[StageEditor] 无法获取编辑地板")
		return nil
	end

	-- 检查重叠
	local isOverlap, existingName = CheckOverlap(gridX, gridY)
	if isOverlap then
		warn(string.format("[StageEditor] ❌ 位置(%d,%d)已有兵种: %s", gridX, gridY, existingName))
		return nil
	end

	-- 查找模型模板
	local template = FindUnitModel(unitId)
	if not template then
		warn("[StageEditor] ❌ 找不到兵种模型:", unitId)
		return nil
	end

	-- 克隆模型
	local unit = template:Clone()

	-- 设置Attribute
	unit:SetAttribute("UnitId", unitId)
	unit:SetAttribute("Level", level)

	-- 计算世界坐标
	local worldCFrame = GridToWorld(floor, gridX, gridY)

	-- 设置位置
	if unit.PrimaryPart then
		unit:SetPrimaryPartCFrame(worldCFrame)
	elseif unit:FindFirstChild("HumanoidRootPart") then
		unit.HumanoidRootPart.CFrame = worldCFrame
	end

	-- 命名（格式: UnitId_LvX_Index）
	local index = #floor:GetChildren() + 1
	unit.Name = string.format("%s_Lv%d_%d", unitId, level, index)

	-- 锚定根部件
	local rootPart = unit:FindFirstChild("HumanoidRootPart") or unit.PrimaryPart
	if rootPart then
		rootPart.Anchored = true
		rootPart.CanCollide = true
	end

	-- 其他部件不锚定
	for _, descendant in ipairs(unit:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= rootPart then
			descendant.Anchored = false
			descendant.CanCollide = false
		end
	end

	-- V2.2: 更新等级显示（包含颜色配置）
	local head = unit:FindFirstChild("Head")
	if head then
		local billboardGui = head:FindFirstChild("BillboardGui")
		if billboardGui then
			local textLabel = billboardGui:FindFirstChild("TextLabel")
			if textLabel then
				-- 设置等级文本
				if level >= 3 then
					textLabel.Text = "Lv.Max"
					-- 最高等级颜色: 黑字红边
					textLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
				else
					textLabel.Text = "Lv." .. level
					-- 设置字体颜色为白色
					textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end

				-- 设置描边颜色
				local levelColors = {
					[1] = Color3.fromRGB(0, 170, 0),   -- LV.1: 绿边
					[2] = Color3.fromRGB(0, 80, 255),  -- LV.2: 蓝边
					[3] = Color3.fromRGB(170, 0, 255), -- LV.3: 紫边
					[4] = Color3.fromRGB(255, 100, 0), -- LV.4: 橙边
					[5] = Color3.fromRGB(255, 0, 0),   -- LV.5: 红边
					Max = Color3.fromRGB(255, 0, 0),   -- Max: 红边
				}

				local strokeColor = (level >= 3) and levelColors.Max or (levelColors[level] or levelColors[1])

				-- 优先使用UIStroke，兜底使用TextStroke
				local uiStroke = textLabel:FindFirstChild("UIStroke") or textLabel:FindFirstChild("Stroke")
				if uiStroke and uiStroke:IsA("UIStroke") then
					uiStroke.Color = strokeColor
					uiStroke.Enabled = true
					uiStroke.Transparency = 0
				else
					textLabel.TextStrokeColor3 = strokeColor
					textLabel.TextStrokeTransparency = 0
				end
			end
		end
	end

	-- 添加到场景
	unit.Parent = floor

	print(string.format("[StageEditor] ✅ 生成兵种: %s Lv%d at (%d,%d)", unitId, level, gridX, gridY))

	return unit
end

--[[
清空地板上的所有兵种
]]
local function ClearAllUnits()
	local floor = GetEditorFloor()
	if not floor then
		return
	end

	local count = 0
	for _, child in ipairs(floor:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
			count = count + 1
		end
	end

	print(string.format("[StageEditor] 已清空地板，移除%d个兵种", count))
	ChangeHistoryService:SetWaypoint("Clear Stage")
end

--[[
保存当前关卡配置
@param stageName string - 关卡名称
]]
local function SaveStage(stageName)
	local enemies = ScanEnemies()

	if #enemies == 0 then
		warn("[StageEditor] 当前地板没有兵种，无法保存")
		return false
	end

	-- 构建配置
	local config = {}
	for _, enemy in ipairs(enemies) do
		table.insert(config, {
			UnitId = enemy.UnitId,
			Level = enemy.Level,
			GridPos = {X = enemy.GridPos.X, Y = enemy.GridPos.Y}
		})
	end

	-- 保存到stageData
	stageData[stageName] = config

	-- 持久化到Plugin Setting
	local success, err = pcall(function()
		local json = HttpService:JSONEncode(stageData)
		plugin:SetSetting("StageEditorData_V2", json)
	end)

	if success then
		print(string.format("[StageEditor] ✅ 保存关卡成功: %s (共%d个兵种)", stageName, #enemies))
		return true
	else
		warn("[StageEditor] ❌ 保存失败:", err)
		return false
	end
end

--[[
加载关卡配置
@param stageName string - 关卡名称
]]
local function LoadStage(stageName)
	local config = stageData[stageName]

	if not config then
		warn(string.format("[StageEditor] 关卡不存在: %s", stageName))
		return false
	end

	-- 清空当前地板
	ClearAllUnits()

	-- 批量生成兵种
	local successCount = 0
	for _, enemy in ipairs(config) do
		local unit = GenerateUnit(
			enemy.UnitId,
			enemy.Level,
			enemy.GridPos.X,
			enemy.GridPos.Y
		)

		if unit then
			successCount = successCount + 1
		end
	end

	print(string.format("[StageEditor] ✅ 加载关卡: %s (成功生成%d/%d)", stageName, successCount, #config))
	ChangeHistoryService:SetWaypoint("Load Stage: " .. stageName)

	return true
end

--[[
删除关卡配置
@param stageName string - 关卡名称
]]
local function DeleteStage(stageName)
	if not stageData[stageName] then
		warn("[StageEditor] 关卡不存在:", stageName)
		return false
	end

	stageData[stageName] = nil

	-- 持久化
	local success, err = pcall(function()
		local json = HttpService:JSONEncode(stageData)
		plugin:SetSetting("StageEditorData_V2", json)
	end)

	if success then
		print("[StageEditor] ✅ 删除关卡:", stageName)
		return true
	else
		warn("[StageEditor] ❌ 删除失败:", err)
		return false
	end
end

--[[
获取所有关卡名称列表
@return table - 关卡名称数组（已排序）
]]
local function GetAllStages()
	local stages = {}
	for stageName, _ in pairs(stageData) do
		table.insert(stages, stageName)
	end

	-- 按名称排序
	table.sort(stages)

	return stages
end

--[[
导出为Lua代码
@param stageName string - 关卡名称
@return string - Lua代码
]]
local function ExportToLua(stageName)
	local enemies = ScanEnemies()

	if #enemies == 0 then
		warn("[StageEditor] 当前地板没有兵种")
		return ""
	end

	local code = string.format('-- %s配置\nEnemyConfig["%s"] = {\n', stageName, stageName)

	for _, enemy in ipairs(enemies) do
		code = code .. string.format(
			'\t{UnitId = "%s", Level = %d, GridPos = {X = %d, Y = %d}},\n',
			enemy.UnitId, enemy.Level, enemy.GridPos.X, enemy.GridPos.Y
		)
	end

	code = code .. "}\n"

	-- 复制到剪贴板
	pcall(function()
		setclipboard(code)
	end)

	print("=== 导出的Lua代码 ===")
	print(code)
	print("=== 已复制到剪贴板 ===")

	return code
end

--[[
销毁网格可视化
]]
local function DestroyGridVisualization()
	for _, part in ipairs(gridParts) do
		if part and part.Parent then
			part:Destroy()
		end
	end

	gridParts = {}
	gridVisualizationEnabled = false

	print("[StageEditor] 网格可视化已关闭")
end

--[[
创建网格可视化
]]
local function CreateGridVisualization()
	local floor = GetEditorFloor()
	if not floor then
		warn("[StageEditor] 无法创建网格：编辑地板未找到")
		return
	end

	-- 清理旧的网格
	DestroyGridVisualization()

	local GRID_UNIT_SIZE = 4
	local GRID_COUNT = 14
	local IDLE_FLOOR_SIZE = Vector3.new(56, 1, 56)  -- 56x56地板
	local LINE_THICKNESS = 0.05
	local LINE_HEIGHT = 0.2
	local LINE_COLOR = Color3.fromRGB(100, 200, 255)  -- 浅蓝色
	local LINE_TRANSPARENCY = 0.5

	local floorCenter = floor.CFrame.Position
	local floorSize = floor.Size
	-- 网格线应该在地板表面上方一点点
	local floorY = floorCenter.Y + floorSize.Y / 2 + LINE_HEIGHT / 2

	-- 创建一个容器文件夹
	local gridFolder = Instance.new("Folder")
	gridFolder.Name = "StageEditorGrid"
	gridFolder.Parent = workspace

	-- 生成垂直线（X方向）- 15条线（索引0-14）
	for x = 0, GRID_COUNT do
		-- 从地板左边缘开始，每条线间隔4 studs
		local worldX = floorCenter.X - IDLE_FLOOR_SIZE.X / 2 + x * GRID_UNIT_SIZE

		local line = Instance.new("Part")
		line.Name = "GridLineX_" .. x
		line.Size = Vector3.new(LINE_THICKNESS, LINE_HEIGHT, IDLE_FLOOR_SIZE.Z)
		line.CFrame = CFrame.new(worldX, floorY, floorCenter.Z)
		line.Anchored = true
		line.CanCollide = false
		line.Material = Enum.Material.Neon
		line.Color = LINE_COLOR
		line.Transparency = LINE_TRANSPARENCY
		line.Parent = gridFolder

		table.insert(gridParts, line)
	end

	-- 生成水平线（Z方向）- 15条线（索引0-14）
	for z = 0, GRID_COUNT do
		-- 从地板前边缘开始，每条线间隔4 studs
		local worldZ = floorCenter.Z - IDLE_FLOOR_SIZE.Z / 2 + z * GRID_UNIT_SIZE

		local line = Instance.new("Part")
		line.Name = "GridLineZ_" .. z
		line.Size = Vector3.new(IDLE_FLOOR_SIZE.X, LINE_HEIGHT, LINE_THICKNESS)
		line.CFrame = CFrame.new(floorCenter.X, floorY, worldZ)
		line.Anchored = true
		line.CanCollide = false
		line.Material = Enum.Material.Neon
		line.Color = LINE_COLOR
		line.Transparency = LINE_TRANSPARENCY
		line.Parent = gridFolder

		table.insert(gridParts, line)
	end

	-- 添加中心标记（格子7,7 = 用户输入(7,7) = 网格索引(6,6)）
	local centerGridX = 7
	local centerGridY = 7
	local centerCFrame = GridToWorld(floor, centerGridX, centerGridY)

	local centerMarker = Instance.new("Part")
	centerMarker.Name = "CenterMarker"
	centerMarker.Size = Vector3.new(0.5, LINE_HEIGHT * 2, 0.5)
	centerMarker.CFrame = CFrame.new(centerCFrame.Position.X, floorY, centerCFrame.Position.Z)
	centerMarker.Anchored = true
	centerMarker.CanCollide = false
	centerMarker.Material = Enum.Material.Neon
	centerMarker.Color = Color3.fromRGB(255, 255, 0)  -- 黄色
	centerMarker.Transparency = 0.3
	centerMarker.Parent = gridFolder

	table.insert(gridParts, centerMarker)
	table.insert(gridParts, gridFolder)

	gridVisualizationEnabled = true
	print(string.format("[StageEditor] ✅ 网格可视化已启用 (共%d条线)", #gridParts - 2))
end

--[[
切换网格可视化
]]
local function ToggleGridVisualization()
	if gridVisualizationEnabled then
		DestroyGridVisualization()
	else
		CreateGridVisualization()
	end
end

-- ==================== UI构建 ====================

-- 创建主容器
local mainFrame = Instance.new("ScrollingFrame")
mainFrame.Size = UDim2.new(1, 0, 1, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(46, 46, 46)
mainFrame.BorderSizePixel = 0
mainFrame.CanvasSize = UDim2.new(0, 0, 0, 800)
mainFrame.ScrollBarThickness = 8
mainFrame.Parent = widget

local yOffset = 10

-- 辅助函数：创建分隔线
local function CreateDivider(parent, yPos)
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -20, 0, 1)
	divider.Position = UDim2.new(0, 10, 0, yPos)
	divider.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	divider.BorderSizePixel = 0
	divider.Parent = parent
	return divider
end

-- 辅助函数：创建标题
local function CreateTitle(parent, text, yPos)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 25)
	title.Position = UDim2.new(0, 10, 0, yPos)
	title.BackgroundTransparency = 1
	title.Text = text
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = parent
	return title
end

-- 辅助函数：创建按钮
local function CreateButton(parent, text, yPos, callback)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -20, 0, 35)
	button.Position = UDim2.new(0, 10, 0, yPos)
	button.BackgroundColor3 = Color3.fromRGB(60, 150, 255)
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.SourceSansBold
	button.TextSize = 14
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Parent = parent

	if callback then
		button.MouseButton1Click:Connect(callback)
	end

	return button
end

-- 辅助函数：创建输入框
local function CreateTextBox(parent, labelText, defaultValue, yPos)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -20, 0, 20)
	label.Position = UDim2.new(0, 10, 0, yPos)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.Font = Enum.Font.SourceSans
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent

	local textBox = Instance.new("TextBox")
	textBox.Size = UDim2.new(1, -20, 0, 30)
	textBox.Position = UDim2.new(0, 10, 0, yPos + 22)
	textBox.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	textBox.Text = tostring(defaultValue)
	textBox.TextColor3 = Color3.new(1, 1, 1)
	textBox.Font = Enum.Font.SourceSans
	textBox.TextSize = 14
	textBox.BorderSizePixel = 0
	textBox.Parent = parent

	return textBox, yPos + 55
end

-- ========== 关卡管理区 ==========
CreateTitle(mainFrame, "📁 关卡管理", yOffset)
yOffset = yOffset + 30

local stageNameInput, newOffset = CreateTextBox(mainFrame, "当前关卡名称:", currentStageName, yOffset)
yOffset = newOffset

-- 新建关卡按钮
CreateButton(mainFrame, "新建关卡", yOffset, function()
	local newName = stageNameInput.Text
	if newName == "" then
		warn("[StageEditor] 请输入关卡名称")
		return
	end

	currentStageName = newName
	print("[StageEditor] 切换到关卡:", newName)
end)
yOffset = yOffset + 40

-- 保存按钮
CreateButton(mainFrame, "💾 保存当前关卡", yOffset, function()
	local success = SaveStage(stageNameInput.Text)
	if success then
		RefreshStageList()  -- 保存成功后刷新列表
	end
end)
yOffset = yOffset + 40

-- 删除关卡按钮
CreateButton(mainFrame, "🗑️ 删除当前关卡", yOffset, function()
	local success = DeleteStage(stageNameInput.Text)
	if success then
		RefreshStageList()  -- 删除成功后刷新列表
	end
end)
yOffset = yOffset + 40

CreateDivider(mainFrame, yOffset)
yOffset = yOffset + 15

-- ========== 兵种生成区 ==========
CreateTitle(mainFrame, "⚔️ 兵种生成", yOffset)
yOffset = yOffset + 30

-- 获取兵种列表
local availableUnits = GetAllUnitIds()
local currentUnitIndex = 1

-- 兵种选择（下拉按钮）
local unitLabel = Instance.new("TextLabel")
unitLabel.Size = UDim2.new(1, -20, 0, 20)
unitLabel.Position = UDim2.new(0, 10, 0, yOffset)
unitLabel.BackgroundTransparency = 1
unitLabel.Text = "兵种ID (点击切换):"
unitLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
unitLabel.Font = Enum.Font.SourceSans
unitLabel.TextSize = 13
unitLabel.TextXAlignment = Enum.TextXAlignment.Left
unitLabel.Parent = mainFrame
yOffset = yOffset + 22

local unitButton = Instance.new("TextButton")
unitButton.Size = UDim2.new(1, -20, 0, 35)
unitButton.Position = UDim2.new(0, 10, 0, yOffset)
unitButton.BackgroundColor3 = Color3.fromRGB(80, 120, 200)
unitButton.Text = availableUnits[currentUnitIndex] or "Noob"
unitButton.TextColor3 = Color3.new(1, 1, 1)
unitButton.Font = Enum.Font.SourceSansBold
unitButton.TextSize = 16
unitButton.BorderSizePixel = 0
unitButton.Parent = mainFrame

-- 点击切换兵种
unitButton.MouseButton1Click:Connect(function()
	currentUnitIndex = currentUnitIndex + 1
	if currentUnitIndex > #availableUnits then
		currentUnitIndex = 1
	end
	unitButton.Text = availableUnits[currentUnitIndex]
	selectedUnitId = availableUnits[currentUnitIndex]
	print("[StageEditor] 切换到兵种:", selectedUnitId)
end)
yOffset = yOffset + 40

-- 等级选择
local levelInput, newOffset = CreateTextBox(mainFrame, "等级 (1-3):", "1", yOffset)
yOffset = newOffset

-- 第几排
local gridXInput, newOffset = CreateTextBox(mainFrame, "第几排 (1-14):", "7", yOffset)
yOffset = newOffset

-- 第几列
local gridYInput, newOffset = CreateTextBox(mainFrame, "第几列 (1-14):", "7", yOffset)
yOffset = newOffset

-- 生成按钮
CreateButton(mainFrame, "✨ 生成兵种", yOffset, function()
	local unitId = unitButton.Text  -- 从按钮获取
	local level = tonumber(levelInput.Text) or 1
	local gridX = tonumber(gridXInput.Text) or 7
	local gridY = tonumber(gridYInput.Text) or 7

	-- 验证输入
	if unitId == "" then
		warn("[StageEditor] 请选择兵种")
		return
	end

	if gridX < 1 or gridX > 14 or gridY < 1 or gridY > 14 then
		warn("[StageEditor] 格子坐标必须在1-14之间")
		return
	end

	if level < 1 or level > 3 then
		warn("[StageEditor] 等级必须在1-3之间")
		return
	end

	-- 生成兵种
	GenerateUnit(unitId, level, gridX, gridY)
	ChangeHistoryService:SetWaypoint("Generate Unit")
end)
yOffset = yOffset + 40

CreateDivider(mainFrame, yOffset)
yOffset = yOffset + 15

-- ========== 关卡列表 ==========
CreateTitle(mainFrame, "📋 已保存的关卡", yOffset)
yOffset = yOffset + 30

local stageListFrame = Instance.new("ScrollingFrame")
stageListFrame.Size = UDim2.new(1, -20, 0, 150)
stageListFrame.Position = UDim2.new(0, 10, 0, yOffset)
stageListFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
stageListFrame.BorderSizePixel = 0
stageListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
stageListFrame.ScrollBarThickness = 6
stageListFrame.Parent = mainFrame
yOffset = yOffset + 155

-- 刷新关卡列表
local function RefreshStageList()
	-- 清空现有内容
	for _, child in ipairs(stageListFrame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local stages = GetAllStages()
	local itemHeight = 35
	local itemGap = 5

	for i, stageName in ipairs(stages) do
		local stageButton = Instance.new("TextButton")
		stageButton.Size = UDim2.new(1, -10, 0, itemHeight)
		stageButton.Position = UDim2.new(0, 5, 0, (i - 1) * (itemHeight + itemGap))
		stageButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		stageButton.Text = stageName
		stageButton.TextColor3 = Color3.new(1, 1, 1)
		stageButton.Font = Enum.Font.SourceSans
		stageButton.TextSize = 14
		stageButton.BorderSizePixel = 0
		stageButton.Parent = stageListFrame

		-- 点击加载关卡
		stageButton.MouseButton1Click:Connect(function()
			LoadStage(stageName)
			stageNameInput.Text = stageName
			currentStageName = stageName
		end)
	end

	-- 更新CanvasSize
	stageListFrame.CanvasSize = UDim2.new(0, 0, 0, #stages * (itemHeight + itemGap))
end

CreateDivider(mainFrame, yOffset)
yOffset = yOffset + 15

-- ========== 快捷操作 ==========
CreateTitle(mainFrame, "🔧 快捷操作", yOffset)
yOffset = yOffset + 30

-- 网格可视化按钮
local gridToggleButton = CreateButton(mainFrame, "🔲 显示网格辅助线", yOffset, nil)
gridToggleButton.MouseButton1Click:Connect(function()
	ToggleGridVisualization()

	-- 更新按钮文本
	if gridVisualizationEnabled then
		gridToggleButton.Text = "✅ 隐藏网格辅助线"
		gridToggleButton.BackgroundColor3 = Color3.fromRGB(50, 180, 100)
	else
		gridToggleButton.Text = "🔲 显示网格辅助线"
		gridToggleButton.BackgroundColor3 = Color3.fromRGB(60, 150, 255)
	end
end)
yOffset = yOffset + 40

-- 清空地板按钮
CreateButton(mainFrame, "🧹 清空地板", yOffset, function()
	ClearAllUnits()
end)
yOffset = yOffset + 40

-- 导出Lua代码按钮
CreateButton(mainFrame, "📤 导出Lua代码", yOffset, function()
	ExportToLua(stageNameInput.Text)
end)
yOffset = yOffset + 40

-- 刷新列表按钮
CreateButton(mainFrame, "🔄 刷新关卡列表", yOffset, function()
	RefreshStageList()
end)
yOffset = yOffset + 40

-- 更新CanvasSize
mainFrame.CanvasSize = UDim2.new(0, 0, 0, yOffset + 20)

-- ==================== 事件监听 ====================

-- 主按钮点击事件
mainButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled

	if widget.Enabled then
		-- 检查编辑地板
		local floor = GetEditorFloor()
		if floor then
			print("[StageEditor] ✅ 编辑器已打开")
		else
			warn("[StageEditor] ❌ 无法找到编辑地板，请检查路径")
		end

		-- 刷新关卡列表
		RefreshStageList()
	else
		-- 关闭时清理网格
		if gridVisualizationEnabled then
			DestroyGridVisualization()
		end
	end
end)

-- Delete键删除功能
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Delete then
		local selected = Selection:Get()

		if #selected == 0 then
			return
		end

		local floor = GetEditorFloor()
		if not floor then
			return
		end

		local deletedCount = 0
		for _, obj in ipairs(selected) do
			-- 验证是否在编辑地板内
			if obj.Parent == floor and obj:IsA("Model") then
				print("[StageEditor] 删除兵种:", obj.Name)
				obj:Destroy()
				deletedCount = deletedCount + 1
			end
		end

		if deletedCount > 0 then
			ChangeHistoryService:SetWaypoint("Delete Units")
			print(string.format("[StageEditor] ✅ 已删除%d个兵种", deletedCount))
		end
	end
end)

-- ==================== 初始化 ====================

-- 加载持久化数据
local function LoadPersistedData()
	local success, result = pcall(function()
		local json = plugin:GetSetting("StageEditorData_V2")
		if json and json ~= "" then
			return HttpService:JSONDecode(json)
		end
		return {}
	end)

	if success and result then
		stageData = result
		print("[StageEditor] ✅ 加载了", #GetAllStages(), "个关卡配置")
	else
		print("[StageEditor] ⚠️ 没有历史数据，从空开始")
		stageData = {}
	end
end

-- 初始化
LoadPersistedData()
print("====================================")
print("Stage Editor V2.1 已加载")
print("点击工具栏的'Stage Editor'按钮打开编辑器")
print("====================================")
