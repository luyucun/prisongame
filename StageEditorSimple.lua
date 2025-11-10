--[[
=====================================================
脚本名称: StageEditorSimple
脚本类型: Command Bar Script (Studio快速工具)
版本: V2.0
=====================================================

使用方法:
1. 在Studio中打开游戏
2. 选择一个Stage文件夹(例如Workspace.Home.PlayerHome1.Stage.Stage001)
3. 将此脚本复制到Command Bar并运行
4. 查看Output获取当前Stage的配置代码

功能:
- 自动扫描选中Stage的IdleFloorEnemy
- 分析所有敌人模型
- 导出为EnemyConfig.lua格式的Lua代码

]]

-- 获取选中的对象
local Selection = game:GetService("Selection")
local selected = Selection:Get()

if #selected == 0 then
	warn("[StageEditor] 请先选择一个Stage文件夹")
	return
end

local stage = selected[1]

-- 验证是否为Stage
if not stage:IsA("Folder") or not string.match(stage.Name, "^Stage%d+") then
	warn("[StageEditor] 请选择一个Stage文件夹 (例如Stage001)")
	warn("[StageEditor] 当前选择的是:", stage.Name)
	return
end

print("[StageEditor] ==============================================")
print("[StageEditor] 正在分析Stage:", stage.Name)
print("[StageEditor] ==============================================")

-- 查找IdleFloorEnemy
local idleFloorEnemy = stage:FindFirstChild("IdleFloorEnemy")
if not idleFloorEnemy then
	warn("[StageEditor] 找不到IdleFloorEnemy，请确保Stage结构正确")
	return
end

-- 辅助函数：计算GridPos
local function WorldToGrid(idleFloor, worldPos)
	local floorSize = idleFloor.Size
	local floorPos = idleFloor.Position

	local gridWidth = 14
	local gridHeight = 14
	local cellSize = 4

	-- 计算相对位置
	local relX = worldPos.X - (floorPos.X - floorSize.X / 2)
	local relZ = worldPos.Z - (floorPos.Z - floorSize.Z / 2)

	-- 转换为格子坐标
	local gridX = math.floor(relX / cellSize) + 1
	local gridY = math.floor(relZ / cellSize) + 1

	-- 限制范围
	gridX = math.clamp(gridX, 1, gridWidth)
	gridY = math.clamp(gridY, 1, gridHeight)

	return {X = gridX, Y = gridY}
end

-- 扫描敌人
local enemies = {}
for _, child in ipairs(idleFloorEnemy:GetChildren()) do
	if child:IsA("Model") and child:FindFirstChild("HumanoidRootPart") then
		-- 解析名称获取UnitId和Level
		local unitId = "Unknown"
		local level = 1

		-- 尝试从名称解析 (格式: UnitId_LvX_Index)
		local nameMatch = string.match(child.Name, "^(%w+)_Lv(%d+)_")
		if nameMatch then
			unitId = string.match(child.Name, "^(%w+)_")
			level = tonumber(string.match(child.Name, "_Lv(%d+)_")) or 1
		else
			-- 尝试直接获取Attribute
			unitId = child:GetAttribute("UnitId") or child.Name
			level = child:GetAttribute("Level") or 1
		end

		-- 计算GridPos
		local rootPart = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
		local gridPos = {X = 7, Y = 7}  -- 默认中心
		if rootPart then
			gridPos = WorldToGrid(idleFloorEnemy, rootPart.Position)
		end

		table.insert(enemies, {
			UnitId = unitId,
			Level = level,
			GridPos = gridPos,
			ModelName = child.Name
		})

		print(string.format("[StageEditor] 发现敌人: %s (Lv%d) at Grid(%d,%d)",
			unitId, level, gridPos.X, gridPos.Y))
	end
end

if #enemies == 0 then
	warn("[StageEditor] 当前Stage没有敌人模型")
	return
end

-- 生成Lua配置代码
print("[StageEditor] ")
print("[StageEditor] ==============================================")
print("[StageEditor] 复制下面的代码到 EnemyConfig.lua")
print("[StageEditor] ==============================================")
print("")

local stageName = stage.Name
local output = string.format('-- %s配置\nEnemyConfig["%s"] = {', stageName, stageName)
print(output)

for i, enemy in ipairs(enemies) do
	local line = string.format('\t{UnitId = "%s", Level = %d, GridPos = {X = %d, Y = %d}},',
		enemy.UnitId, enemy.Level, enemy.GridPos.X, enemy.GridPos.Y)
	print(line)
end

print("}")
print("")
print("[StageEditor] ==============================================")
print("[StageEditor] 导出完成！共", #enemies, "个敌人")
print("[StageEditor] ==============================================")
