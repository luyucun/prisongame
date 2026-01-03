--[[
脚本名称: PlacementSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/PlacementSystem
]]

--[[
兵种放置系统模块
职责:
1. 管理玩家已放置的兵种实例
2. 验证放置位置的合法性
3. 处理放置/取消放置请求
4. 同步放置状态到客户端
版本: V1.2
]]

local PlacementSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local PlacementConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PlacementConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local DataManager = require(ServerScriptService.Core.DataManager)
local InventorySystem = require(ServerScriptService.Systems.InventorySystem)
local PhysicsManager = require(ServerScriptService.Systems.PhysicsManager)
-- V2.2新增：等级显示辅助工具
local LevelDisplayHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("LevelDisplayHelper"))

-- 远程事件(延迟获取)
local PlacementEvents = nil

-- ==================== 数据结构 ====================
--[[
PlacedUnitData = {
    InstanceId = string,       -- 兵种实例ID
    UnitId = string,           -- 兵种配置ID
    Position = Vector3,        -- 放置位置
    GridX = number,            -- 网格X坐标 (左下角)
    GridZ = number,            -- 网格Z坐标 (左下角)
    -- V2.0重构: 支持矩形占地
    GridWidth = number,        -- X轴方向占用格子数
    GridDepth = number,        -- Z轴方向占用格子数
    Model = Model,             -- 放置的模型引用
    PlacedTime = number,       -- 放置时间戳
}
]]

-- 存储所有已放置的兵种 [player.UserId] = {[instanceId] = PlacedUnitData}
local placedUnits = {}

-- 存储网格占用状态 [player.UserId] = {[gridKey] = instanceId}
local gridOccupancy = {}

-- ==================== 私有函数 ====================

--[[
初始化远程事件
@return boolean - 是否成功
]]
local function InitializeEvents()
	if not PlacementEvents then
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			PlacementEvents = eventsFolder:FindFirstChild("PlacementEvents")
		end

		if not PlacementEvents and GameConfig.DEBUG_MODE then
			warn(GameConfig.LOG_PREFIX, "PlacementEvents未找到!")
		end
	end
	return PlacementEvents ~= nil
end

--[[
生成网格键值
@param gridX number
@param gridZ number
@return string - 格式: "x_z"
]]
local function GetGridKey(gridX, gridZ)
	return string.format("%d_%d", gridX, gridZ)
end

--[[
计算字典表的大小（用于替代table.maxn）
@param tbl table - 要计算大小的表
@return number - 表中的元素数量
]]
local function GetTableCount(tbl)
	if not tbl then return 0 end
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

--[[
获取玩家的基地IdleFloor
@param player Player
@return Part|nil - IdleFloor对象
]]
local function GetPlayerIdleFloor(player)
	local playerData = DataManager.GetPlayerData(player)
	if not playerData then
		return nil
	end

	local homeSlot = playerData.HomeSlot
	local homeFolder = Workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME)
	if not homeFolder then
		return nil
	end

	local playerHome = homeFolder:FindFirstChild(GameConfig.HOME_PREFIX .. homeSlot)
	if not playerHome then
		return nil
	end

	return playerHome:FindFirstChild(GameConfig.IDLE_FLOOR_NAME)
end

--[[
检查网格是否被占用 (V2.0重构: 支持矩形占地)
@param player Player
@param gridX number - 左下角网格X坐标
@param gridZ number - 左下角网格Z坐标
@param gridWidth number - X轴方向占用格子数
@param gridDepth number - Z轴方向占用格子数 (可选,默认等于gridWidth)
@return boolean, string - 是否占用, 占用的instanceId
]]
local function IsGridOccupied(player, gridX, gridZ, gridWidth, gridDepth)
	local userId = player.UserId
	if not gridOccupancy[userId] then
		gridOccupancy[userId] = {}
	end

	-- 处理默认参数
	gridWidth = gridWidth or 1
	gridDepth = gridDepth or gridWidth

	-- 检查所有需要占据的格子
	for i = 0, gridWidth - 1 do
		for j = 0, gridDepth - 1 do
			local checkX = gridX + i
			local checkZ = gridZ + j
			local gridKey = GetGridKey(checkX, checkZ)

			if gridOccupancy[userId][gridKey] then
				return true, gridOccupancy[userId][gridKey]
			end
		end
	end

	return false, nil
end

--[[
占据网格 (V2.0重构: 支持矩形占地)
@param player Player
@param gridX number - 左下角网格X坐标
@param gridZ number - 左下角网格Z坐标
@param gridWidth number - X轴方向占用格子数
@param gridDepth number - Z轴方向占用格子数 (可选,默认等于gridWidth)
@param instanceId string
]]
local function OccupyGrid(player, gridX, gridZ, gridWidth, gridDepth, instanceId)
	local userId = player.UserId
	if not gridOccupancy[userId] then
		gridOccupancy[userId] = {}
	end

	-- 处理默认参数
	gridWidth = gridWidth or 1
	gridDepth = gridDepth or gridWidth

	for i = 0, gridWidth - 1 do
		for j = 0, gridDepth - 1 do
			local occupyX = gridX + i
			local occupyZ = gridZ + j
			local gridKey = GetGridKey(occupyX, occupyZ)
			gridOccupancy[userId][gridKey] = instanceId
		end
	end
end

--[[
释放网格 (V2.0重构: 支持矩形占地)
@param player Player
@param gridX number - 左下角网格X坐标
@param gridZ number - 左下角网格Z坐标
@param gridWidth number - X轴方向占用格子数
@param gridDepth number - Z轴方向占用格子数 (可选,默认等于gridWidth)
]]
local function ReleaseGrid(player, gridX, gridZ, gridWidth, gridDepth)
	local userId = player.UserId
	if not gridOccupancy[userId] then
		return
	end

	-- 处理默认参数
	gridWidth = gridWidth or 1
	gridDepth = gridDepth or gridWidth

	for i = 0, gridWidth - 1 do
		for j = 0, gridDepth - 1 do
			local releaseX = gridX + i
			local releaseZ = gridZ + j
			local gridKey = GetGridKey(releaseX, releaseZ)
			gridOccupancy[userId][gridKey] = nil
		end
	end
end

--[[
更新模型等级显示 V2.2 (重构为使用LevelDisplayHelper)
@param model Model - 兵种模型
@param level number - 等级
]]
local function UpdateLevelDisplay(model, level)
	if not model or not level then
		return
	end

	-- V2.2: 使用统一的LevelDisplayHelper处理等级显示
	local success = LevelDisplayHelper.UpdateLevelDisplay(model, level)
	if not success then
		warn("[PlacementSystem] UpdateLevelDisplay: 更新等级显示失败，model=" .. tostring(model.Name) .. ", level=" .. tostring(level))
	end
end

local function NormalizeUnitHealth(unitInstance, unitId, level)
	if not unitInstance or not unitId or not level then
		return nil, nil
	end

	local expectedMax = UnitConfig.CalculateHealth(unitId, level)
	if expectedMax <= 0 then
		return unitInstance.Health, unitInstance.MaxHealth
	end

	local currentMax = tonumber(unitInstance.MaxHealth) or 0
	local currentHealth = tonumber(unitInstance.Health)

	if currentMax <= 0 or math.abs(currentMax - expectedMax) > 0.01 then
		local ratio = 1
		if currentMax > 0 and currentHealth ~= nil then
			ratio = math.clamp(currentHealth / currentMax, 0, 1)
		end
		currentMax = expectedMax
		if currentHealth ~= nil then
			currentHealth = math.clamp(currentMax * ratio, 0, currentMax)
		else
			currentHealth = currentMax
		end
		unitInstance.MaxHealth = currentMax
		unitInstance.Health = currentHealth
	elseif currentHealth == nil or currentHealth > currentMax then
		currentHealth = currentMax
		unitInstance.Health = currentHealth
	end

	return currentHealth, currentMax
end

--[[
播放展示动画 (V1.5.2新增, V2.8修复: 支持重复调用, V2.9修复: 禁用默认Animate脚本)
@param model Model - 兵种模型
@param unitId string - 兵种ID
]]
local function PlayShowAnimation(model, unitId)
	if not model or not unitId then
		warn(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 参数无效: model=", model, "unitId=", unitId)
		return
	end

	-- print(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 开始播放展示动画:", model.Name, "UnitId:", unitId)

	-- 获取展示动画ID
	local showAnimId = UnitConfig.GetShowAnimationId(unitId)

	-- 如果没有配置展示动画，直接返回
	if not showAnimId or showAnimId == "" or showAnimId == "0" then
		-- warn(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 没有配置ShowAnimationId:", unitId)
		return
	end

	-- print(GameConfig.LOG_PREFIX, "[PlayShowAnimation] ShowAnimationId:", showAnimId)

	-- V1.5.2调试：验证动画ID格式
	if not tonumber(showAnimId) then
		warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: 动画ID格式无效:", unitId, "AnimID:", showAnimId, "类型:", type(showAnimId))
		return
	end

	-- 查找Humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 找不到Humanoid:", model.Name)
		return
	end

	-- V2.9关键修复：禁用默认Animate脚本，防止与展示动画冲突
	-- 默认Animate脚本会不断播放Idle动画，会覆盖我们的ShowAnimation
	local animateScriptDisabled = false
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") and descendant.Name == "Animate" then
			descendant.Enabled = false
			animateScriptDisabled = true
			-- print(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 已禁用Animate脚本:", model.Name)
		end
	end
	if not animateScriptDisabled then
		-- print(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 未找到Animate脚本:", model.Name)
	end

	-- 查找Animator
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		-- 尝试创建Animator（Roblox会自动创建，但保险起见）
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			-- 手动创建Animator
			animator = Instance.new("Animator")
			animator.Parent = humanoid
			-- print(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 手动创建Animator:", model.Name)
		end
	end

	-- V2.8修复：停止所有正在播放的动画，避免动画混播
	-- 这在单位被移动位置后重新播放展示动画时很重要
	local playingTracks = animator:GetPlayingAnimationTracks()
	if #playingTracks > 0 then
		-- print(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 停止", #playingTracks, "个正在播放的动画:", model.Name)
	end
	for _, track in ipairs(playingTracks) do
		pcall(function()
			track:Stop(0)  -- 立即停止，不做淡出
		end)
	end

	-- 创建动画实例
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. showAnimId

	-- 加载动画
	local success, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success then
		warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: 动画加载失败:", unitId, "错误:", result)
		animation:Destroy()
		return
	end

	local animTrack = result
	if not animTrack then
		warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: 动画轨道为空:", unitId)
		animation:Destroy()
		return
	end

	-- print(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 动画加载成功:", model.Name, "AnimTrack:", animTrack)

	-- 设置循环播放
	animTrack.Looped = true

	-- V2.9修复：设置Idle优先级，便于战斗/行军动画覆盖
	animTrack.Priority = Enum.AnimationPriority.Idle

	-- 播放动画
	local playSuccess, playError = pcall(function()
		animTrack:Play()
	end)

	if not playSuccess then
		warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: 动画播放失败:", unitId, "错误:", playError)
		animation:Destroy()
		return
	end

	-- print(GameConfig.LOG_PREFIX, "[PlayShowAnimation] ✅ 动画播放成功:", model.Name, "Looped:", animTrack.Looped, "Priority:", tostring(animTrack.Priority), "IsPlaying:", animTrack.IsPlaying)

	-- V2.9修复：将动画轨道保存到模型属性，方便后续管理
	-- 这样在移动单位时可以先停止旧动画
	model:SetAttribute("_ShowAnimTrackId", animTrack.Name or "ShowAnim")

	-- V1.5.2修复：循环动画在停止时清理Animation对象，防止内存泄漏
	-- 当单位被回收时，animTrack:Stop()会触发此事件
	animTrack.Stopped:Connect(function()
		-- print(GameConfig.LOG_PREFIX, "[PlayShowAnimation] 动画已停止:", model.Name)
		if animation and animation.Parent then
			animation:Destroy()
		end
	end)
end

--[[
创建兵种模型到世界 (V2.0重构: 支持矩形占地)
@param unitId string
@param position Vector3
@param instanceId string - V1.3: 添加instanceId参数用于标记模型
@param level number - V1.4: 添加等级参数
@param gridWidth number - V2.0: X轴方向占用格子数
@param gridDepth number - V2.0: Z轴方向占用格子数 (可选,默认等于gridWidth)
@return Model|nil
]]
local function CreateUnitModel(unitId, position, instanceId, level, gridWidth, gridDepth, homeSlot)
	-- V2.0: 处理默认参数
	level = level or 1
	gridWidth = gridWidth or 1
	gridDepth = gridDepth or gridWidth

	local unitConfig = UnitConfig.GetUnitById(unitId)
	if not unitConfig then
		return nil
	end

	-- V2.3.3修复：使用ModelPath配置查找模型（与PlacementHelper保持一致）
	local modelTemplate = nil

	-- 获取模型路径,例如 "Role/Basic/Noob"
	local modelPath = unitConfig.ModelPath
	if not modelPath or modelPath == "" then
		warn(GameConfig.LOG_PREFIX, "兵种没有配置ModelPath:", unitId)
		return nil
	end

	-- 解析路径（修复：确保modelPath是字符串）
	local pathParts = string.split(tostring(modelPath), "/")

	-- 从ReplicatedStorage开始遍历路径
	local currentFolder = ReplicatedStorage
	for i = 1, #pathParts - 1 do
		local nextFolder = currentFolder:FindFirstChild(pathParts[i])
		if not nextFolder then
			warn(GameConfig.LOG_PREFIX, "路径不存在:", pathParts[i], "在", currentFolder:GetFullName())
			return nil
		end
		currentFolder = nextFolder
	end

	-- 最后一个部分是模型名称
	local modelName = pathParts[#pathParts]
	modelTemplate = currentFolder:FindFirstChild(modelName)

	if not modelTemplate then
		warn(GameConfig.LOG_PREFIX, "找不到模型:", modelName, "路径:", modelPath)
		return nil
	end

	if not modelTemplate:IsA("Model") then
		warn(GameConfig.LOG_PREFIX, modelName, "不是一个Model类型")
		return nil
	end


	-- 第三步：验证模型包含Humanoid（防止使用错误的展示模型）
	if not modelTemplate:FindFirstChildOfClass("Humanoid") then
		warn(GameConfig.LOG_PREFIX, "模板缺少Humanoid:", unitId, modelTemplate:GetFullName())
		return nil
	end

	-- 克隆模型
	local model = modelTemplate:Clone()

	-- V3.9新增：在模型克隆后立即保存所有部件的原始透明度
	-- 这是保存透明度的最佳时机，因为此时模型的状态是最原始的
	-- 用于后续复生时恢复到正确的透明度（避免隐藏的武器部件被错误显示）
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part:SetAttribute("_OriginalTransparency", part.Transparency)
			end)
		elseif part:IsA("Decal") or part:IsA("Texture") then
			pcall(function()
				part:SetAttribute("_OriginalTransparency", part.Transparency)
			end)
		end
	end
	model:SetAttribute("_TransparencySaved", true)

	-- V1.3: 设置InstanceId属性，用于回收时识别
	if instanceId then
		model:SetAttribute("InstanceId", instanceId)
	end

	-- 统一主部件，后续移动/拖动以HRP为基准
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then
		model.PrimaryPart = hrp
	end

	-- V2.0重构: 设置等级、UnitId和占地尺寸属性
	model:SetAttribute("Level", level)
	model:SetAttribute("UnitId", unitId)
	model:SetAttribute("GridWidth", gridWidth)
	model:SetAttribute("GridDepth", gridDepth)
	-- V2.1补充：添加只读属性用于调试兵种类型（可选）
	model:SetAttribute("UnitType", UnitConfig.IsRangedUnit(unitId) and "Ranged" or "Melee")

	-- V6.0新增：标记HomeSlot（用于玩家离线时兜底清理残留单位）
	if type(homeSlot) == "number" and homeSlot > 0 then
		model:SetAttribute("HomeSlot", homeSlot)
	end

	-- V1.4: 更新等级显示
	UpdateLevelDisplay(model, level)

	-- V2.7修复：先将模型放置到workspace，使用初始位置（后续会校准Y）
	model.Parent = Workspace

	-- V2.7修复：第一次放置到目标XZ位置（使用传入的position作为初值）
	if model.PrimaryPart then
		model:PivotTo(CFrame.new(position))
	elseif model:FindFirstChild("HumanoidRootPart") then
		model.HumanoidRootPart.CFrame = CFrame.new(position)
	end

	-- V2.12修复：计算角色底部位置时，排除武器等附件的影响
	-- 问题：GetBoundingBox会包括武器，如果武器尖端低于脚底会导致角色浮空
	-- 解决：只考虑角色身体部件的包围盒，排除Tool/Accessory/武器等
	do
		local floorTopY = position.Y - PlacementConfig.PLACEMENT_Y_OFFSET  -- 地板顶面Y坐标
		local padding = 0.05

		-- 收集角色身体部件（排除武器、工具、饰品等）
		local bodyParts = {}
		local excludeNames = {"Handle", "Sword", "Spear", "Weapon", "Gun", "Bow", "Staff", "Axe", "Knife", "Shield"}

		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				-- 排除工具和饰品
				local parent = part.Parent
				local isAccessoryOrTool = false

				while parent and parent ~= model do
					if parent:IsA("Tool") or parent:IsA("Accoutrement") or parent:IsA("Accessory") then
						isAccessoryOrTool = true
						break
					end
					parent = parent.Parent
				end

				-- 排除武器相关名称的部件
				local isWeaponPart = false
				for _, excludeName in ipairs(excludeNames) do
					if string.find(string.lower(part.Name), string.lower(excludeName)) then
						isWeaponPart = true
						break
					end
				end

				if not isAccessoryOrTool and not isWeaponPart then
					table.insert(bodyParts, part)
				end
			end
		end

		-- 计算身体部件的最低点
		local lowestY = math.huge
		if #bodyParts > 0 then
			for _, part in ipairs(bodyParts) do
				local partBottomY = part.Position.Y - part.Size.Y / 2
				if partBottomY < lowestY then
					lowestY = partBottomY
				end
			end
		else
			-- 回退方案：如果没有找到身体部件，使用HumanoidRootPart减去标准高度
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hrp then
				-- 标准R15/R6角色的HRP到脚底约为3 studs
				lowestY = hrp.Position.Y - 3
			else
				-- 最后回退：使用原来的包围盒方法
				local bboxCf, bboxSize = model:GetBoundingBox()
				lowestY = bboxCf.Position.Y - bboxSize.Y / 2
			end
		end

		-- 计算需要调整的Y偏移
		local deltaY = (floorTopY + padding) - lowestY

		-- 二次PivotTo，将模型底部对齐地板顶面
		model:PivotTo(model:GetPivot() * CFrame.new(0, deltaY, 0))
	end

	-- V1.5.2修复：IdleFloor上的单位需要播放动画
	-- 只锚定根部件防止移动/下沉，其他部件保持可动以支持动画
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart

	if rootPart then
		-- 锚定根部件，防止模型移动和下沉
		rootPart.Anchored = true
		rootPart.CanCollide = true

	else
		warn(GameConfig.LOG_PREFIX, "CreateUnitModel: 找不到根部件，模型可能会下沉:", model.Name)
	end

	-- 其他部件不锚定，允许动画播放，但禁用碰撞避免干扰
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= rootPart then
			descendant.Anchored = false      -- 不锚定，允许动画移动
			descendant.CanCollide = false    -- 禁用碰撞，避免肢体碰撞干扰
		end
	end

	-- V3.11新增：确保Humanoid的AutoRotate启用，防止行军时掉头bug
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
	end

	-- V2.5寻路优化：设置兵种碰撞组，关闭兵种间碰撞
	local CollisionSystem = ServerScriptService.Systems:FindFirstChild("CollisionSystem")
	if CollisionSystem then
		local CollisionModule = require(CollisionSystem)
		pcall(function()
			CollisionModule.SetUnitCollision(model)
			-- 同时优化Humanoid性能
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				CollisionModule.OptimizeHumanoid(humanoid)
			end
		end)
	end

	-- V2.9修复：确保Animator存在，这是播放动画的前提条件
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChild("Animator")
		if not animator then
			-- 等待一小段时间让Roblox自动创建Animator
			task.wait(0.1)
			animator = humanoid:FindFirstChild("Animator")
			if not animator then
				-- 如果还没有，手动创建
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
		end
	end

	return model
end

-- ==================== 公共接口 ====================

--[[
验证放置位置是否合法 (V2.0重构: 支持矩形占地)
@param player Player
@param instanceId string - 兵种实例ID
@param position Vector3 - 世界坐标
@return boolean, string - 是否合法, 错误信息
]]
function PlacementSystem.ValidatePlacement(player, instanceId, position)
	-- 1. 检查玩家数据
	local playerData = DataManager.GetPlayerData(player)
	if not playerData then
		return false, "玩家数据不存在"
	end

	-- 2. 检查兵种实例是否存在
	local unitInstance = InventorySystem.GetUnitByInstanceId(player, instanceId)
	if not unitInstance then
		return false, "兵种实例不存在"
	end

	-- 3. 检查兵种是否已经放置
	if unitInstance.IsPlaced then
		return false, "兵种已经被放置"
	end

	-- 4. 获取玩家的IdleFloor
	local idleFloor = GetPlayerIdleFloor(player)
	if not idleFloor then
		return false, "找不到放置地板"
	end

	-- V2.0: 获取兵种占地尺寸 (必须在WorldToGrid之前获取)
	local gridWidth = UnitConfig.GetGridWidth(unitInstance.UnitId)
	local gridDepth = UnitConfig.GetGridDepth(unitInstance.UnitId)
	-- 回写实例占地，向后兼容老数据
	unitInstance.GridWidth = gridWidth
	unitInstance.GridDepth = gridDepth

	-- 5. 转换为网格坐标 (V2.0.4修复: 传入占地尺寸)
	local floorCenter = idleFloor.Position
	local gridX, gridZ = PlacementConfig.WorldToGrid(position, floorCenter, gridWidth, gridDepth)

	-- 6. 检查边界
	if not PlacementConfig.IsGridInBounds(gridX, gridZ, gridWidth, gridDepth) then
		return false, "超出放置范围"
	end

	-- 7. 检查碰撞
	if PlacementConfig.ENABLE_COLLISION_CHECK then
		local isOccupied, occupyingId = IsGridOccupied(player, gridX, gridZ, gridWidth, gridDepth)
		if isOccupied then
			return false, "位置已被占用"
		end
	end

	-- 8. 检查放置数量限制
	local userId = player.UserId
	if placedUnits[userId] and #placedUnits[userId] >= PlacementConfig.MAX_PLACED_UNITS then
		return false, "已达到最大放置数量"
	end

	return true, "验证通过"
end

--[[
放置兵种 (V2.0重构: 支持矩形占地)
@param player Player
@param instanceId string
@param position Vector3
@return boolean, string - 是否成功, 错误/成功信息
]]
function PlacementSystem.PlaceUnit(player, instanceId, position)
	-- 验证放置
	local valid, message = PlacementSystem.ValidatePlacement(player, instanceId, position)
	if not valid then
		return false, message
	end

	-- 获取兵种实例
	local unitInstance = InventorySystem.GetUnitByInstanceId(player, instanceId)
	local playerData = DataManager.GetPlayerData(player)
	local homeSlot = playerData and playerData.HomeSlot
	local idleFloor = GetPlayerIdleFloor(player)
	local floorCenter = idleFloor.Position

	-- V2.0: 获取兵种占地尺寸 (必须在WorldToGrid之前获取)
	local gridWidth = UnitConfig.GetGridWidth(unitInstance.UnitId)
	local gridDepth = UnitConfig.GetGridDepth(unitInstance.UnitId)
	-- 回写实例占地，向后兼容老数据
	unitInstance.GridWidth = gridWidth
	unitInstance.GridDepth = gridDepth

	-- 转换为网格坐标 (V2.0.4修复: 传入占地尺寸)
	local gridX, gridZ = PlacementConfig.WorldToGrid(position, floorCenter, gridWidth, gridDepth)

	-- 计算精确的放置位置 (对齐到网格中心)
	local finalPosition = PlacementConfig.GridToWorld(gridX, gridZ, floorCenter, gridWidth, gridDepth)

	-- V2.0: 传递gridWidth和gridDepth到CreateUnitModel
	local model = CreateUnitModel(unitInstance.UnitId, finalPosition, instanceId, unitInstance.Level, gridWidth, gridDepth, homeSlot)
	if not model then
		return false, "创建模型失败"
	end

	-- V2.7修复：获取模型实际放置后的位置（Y已被CreateUnitModel校准）
	local actualPosition = finalPosition
	if model.PrimaryPart then
		actualPosition = model:GetPivot().Position
	elseif model:FindFirstChild("HumanoidRootPart") then
		actualPosition = model.HumanoidRootPart.Position
	end

	-- 更新InventorySystem中的实例状态
	unitInstance.IsPlaced = true
	unitInstance.PlacedPosition = actualPosition

	-- 🔧 修复：将血量同步到模型的Humanoid
	-- 确保model.Humanoid的血量与unitInstance一致（防止首战时读取错误血量）
	local humanoid = model:FindFirstChild("Humanoid")
	if humanoid then
		local health, maxHealth = NormalizeUnitHealth(unitInstance, unitInstance.UnitId, unitInstance.Level)
		if not health or not maxHealth then
			-- 使用unitInstance的血量，如果没有则使用配置表的默认值
			health = unitInstance.Health or UnitConfig.CalculateHealth(unitInstance.UnitId, unitInstance.Level)
			maxHealth = unitInstance.MaxHealth or UnitConfig.CalculateHealth(unitInstance.UnitId, unitInstance.Level)
		end
		humanoid.MaxHealth = maxHealth
		humanoid.Health = math.clamp(health, 0, maxHealth)
		-- print(GameConfig.LOG_PREFIX, "[PlacementSystem.PlaceUnit] 同步血量到Humanoid:", unitInstance.UnitId, "HP:", humanoid.Health, "/", humanoid.MaxHealth)
	end

	-- V2.0: 占据网格 (使用gridWidth和gridDepth)
	OccupyGrid(player, gridX, gridZ, gridWidth, gridDepth, instanceId)

	-- 保存放置数据
	local userId = player.UserId
	if not placedUnits[userId] then
		placedUnits[userId] = {}
	end

	-- V2.0重构: 使用GridWidth和GridDepth替代GridSize
	placedUnits[userId][instanceId] = {
		InstanceId = instanceId,
		UnitId = unitInstance.UnitId,
		Level = unitInstance.Level,
		Position = actualPosition,
		GridX = gridX,
		GridZ = gridZ,
		GridWidth = gridWidth,
		GridDepth = gridDepth,
		Model = model,
		PlacedTime = os.time(),
	}

	-- 🔥修复服务器关闭时数据保存：同步到DataManager
	DataManager.AddPlacedUnit(player, instanceId, placedUnits[userId][instanceId])

	-- V2.0新增: 保存GridPos到模型（用于战役系统）
	local gridModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("GridPositionSystem")
	if gridModule then
		local GridPositionSystem = require(gridModule :: ModuleScript)
		local gridPos = GridPositionSystem.SaveUnitGridPosition(model, idleFloor)

		-- 同时保存到placedUnits表中
		if gridPos then
			placedUnits[userId][instanceId].GridPos = gridPos
		else
			warn(GameConfig.LOG_PREFIX, "保存GridPos失败，使用默认值")
			placedUnits[userId][instanceId].GridPos = {X = gridX, Y = gridZ}
		end
	end

	-- 配置兵种物理（禁用与玩家的碰撞）
	PhysicsManager.ConfigureUnitPhysics(model, "ally")  -- 玩家的兵种为友军

	-- V1.5.2新增: 播放show动画（展示动画）
	PlayShowAnimation(model, unitInstance.UnitId)

	-- 通知InventorySystem刷新客户端背包显示
	InventorySystem.RefreshClientInventory(player)

	-- 🔥修复持久化：保存放置数据到DataManager
	-- V2.0重构: 使用GridWidth和GridDepth替代GridSize
	local placedData = {
		UnitId = unitInstance.UnitId,
		Level = unitInstance.Level,
		GridX = gridX,
		GridZ = gridZ,
		GridWidth = gridWidth,
		GridDepth = gridDepth,
		IsActivated = false,  -- 新放置的单位未激活
		Health = unitInstance.Health or UnitConfig.CalculateHealth(unitInstance.UnitId, unitInstance.Level),
		MaxHealth = unitInstance.MaxHealth or UnitConfig.CalculateHealth(unitInstance.UnitId, unitInstance.Level),
	}

	local saveSuccess = DataManager.SavePlacedUnit(player, instanceId, placedData)
	if saveSuccess then
		-- 节流式保存整个玩家数据
		DataManager.SavePlayerDataThrottled(player)
		-- print(string.format(
		-- 	"%s [PlacementSystem] 🔥 已保存放置数据: 玩家 %s, 兵种 %s, 位置 (%d,%d)",
		-- 	GameConfig.LOG_PREFIX,
		-- 	player.Name,
		-- 	unitInstance.UnitId,
		-- 	gridX,
		-- 	gridZ
		-- 	))
	else
		warn(string.format(
			"%s [PlacementSystem] 🔥 保存放置数据失败: 玩家 %s, 兵种 %s",
			GameConfig.LOG_PREFIX,
			player.Name,
			instanceId
			))
	end

	return true, "放置成功"
end

--[[
取消放置(移除已放置的兵种) (V2.0重构: 支持矩形占地)
@param player Player
@param instanceId string
@return boolean, string
]]
function PlacementSystem.RemovePlacedUnit(player, instanceId)
	local userId = player.UserId
	if not placedUnits[userId] or not placedUnits[userId][instanceId] then
		return false, "兵种未放置"
	end

	local placedData = placedUnits[userId][instanceId]

	-- V2.0: 释放网格 (使用GridWidth和GridDepth,向后兼容GridSize)
	local gridWidth = placedData.GridWidth or placedData.GridSize or 1
	local gridDepth = placedData.GridDepth or placedData.GridSize or gridWidth
	ReleaseGrid(player, placedData.GridX, placedData.GridZ, gridWidth, gridDepth)

	-- 移除模型
	if placedData.Model and placedData.Model.Parent then
		placedData.Model:Destroy()
	end

	-- 更新InventorySystem状态
	local unitInstance = InventorySystem.GetUnitByInstanceId(player, instanceId)
	if unitInstance then
		unitInstance.IsPlaced = false
		unitInstance.PlacedPosition = nil
	end

	-- 移除放置数据
	placedUnits[userId][instanceId] = nil

	-- 🔥修复持久化：从DataManager移除放置数据
	local removeSuccess = DataManager.RemovePlacedUnit(player, instanceId)
	if removeSuccess then
		-- 节流式保存整个玩家数据
		DataManager.SavePlayerDataThrottled(player)
		-- print(string.format(
		-- 	"%s [PlacementSystem] 🔥 已移除放置数据: 玩家 %s, 兵种 %s",
		-- 	GameConfig.LOG_PREFIX,
		-- 	player.Name,
		-- 	instanceId
		-- 	))
	else
		warn(string.format(
			"%s [PlacementSystem] 🔥 移除放置数据失败: 玩家 %s, 兵种 %s",
			GameConfig.LOG_PREFIX,
			player.Name,
			instanceId
			))
	end

	return true, "移除成功"
end

--[[
回收兵种（V1.3：移除已放置的兵种并返回背包）
@param player Player
@param instanceId string
@return boolean, string
]]
function PlacementSystem.RemoveUnit(player, instanceId)
	-- 1. 移除放置的兵种
	local success, message = PlacementSystem.RemovePlacedUnit(player, instanceId)
	if not success then
		return false, message
	end

	-- 2. 刷新客户端背包显示（兵种已经存在于InventorySystem中，只是IsPlaced变为false）
	InventorySystem.RefreshClientInventory(player)


	return true, "回收成功"
end

--[[
更新已放置兵种的位置 (V2.0重构: 支持矩形占地)
@param player Player
@param instanceId string - 兵种实例ID
@param newPosition Vector3 - 新的世界坐标
@return boolean, string - 是否成功, 消息
]]
function PlacementSystem.UpdateUnitPosition(player, instanceId, newPosition)
	local userId = player.UserId

	-- 1. 检查兵种是否已放置
	if not placedUnits[userId] or not placedUnits[userId][instanceId] then
		return false, "兵种未放置"
	end

	local placedData = placedUnits[userId][instanceId]
	local unitInstance = InventorySystem.GetUnitByInstanceId(player, instanceId)
	if not unitInstance then
		return false, "兵种实例不存在"
	end

	-- 2. 获取IdleFloor
	local idleFloor = GetPlayerIdleFloor(player)
	if not idleFloor then
		return false, "找不到放置地板"
	end

	-- V2.0: 获取占地尺寸 (必须在WorldToGrid之前获取)
	local gridWidth = UnitConfig.GetGridWidth(unitInstance.UnitId)
	local gridDepth = UnitConfig.GetGridDepth(unitInstance.UnitId)
	placedData.GridWidth = gridWidth
	placedData.GridDepth = gridDepth

	-- 3. 转换为网格坐标 (V2.0.4修复: 传入占地尺寸)
	local floorCenter = idleFloor.Position
	local newGridX, newGridZ = PlacementConfig.WorldToGrid(newPosition, floorCenter, gridWidth, gridDepth)

	-- 4. 检查边界
	if not PlacementConfig.IsGridInBounds(newGridX, newGridZ, gridWidth, gridDepth) then
		return false, "超出放置范围"
	end

	-- 5. 检查新位置是否与其他兵种冲突（排除自己）
	if PlacementConfig.ENABLE_COLLISION_CHECK then
		-- 先释放自己占据的网格,再检查冲突
		local oldGridWidth = placedData.GridWidth or placedData.GridSize or 1
		local oldGridDepth = placedData.GridDepth or placedData.GridSize or oldGridWidth
		ReleaseGrid(player, placedData.GridX, placedData.GridZ, oldGridWidth, oldGridDepth)

		local isOccupied, occupyingId = IsGridOccupied(player, newGridX, newGridZ, gridWidth, gridDepth)
		if isOccupied then
			-- 恢复原来的网格占用
			OccupyGrid(player, placedData.GridX, placedData.GridZ, oldGridWidth, oldGridDepth, instanceId)
			return false, "位置已被占用"
		end
	else
		-- 不检查碰撞时也需要释放旧网格
		local oldGridWidth = placedData.GridWidth or placedData.GridSize or 1
		local oldGridDepth = placedData.GridDepth or placedData.GridSize or oldGridWidth
		ReleaseGrid(player, placedData.GridX, placedData.GridZ, oldGridWidth, oldGridDepth)
	end

	-- 7. 计算新的精确位置
	local finalPosition = PlacementConfig.GridToWorld(newGridX, newGridZ, floorCenter, gridWidth, gridDepth)

	-- 8. 更新模型位置（V2.12修复：排除武器影响，使用角色身体计算底部）
	if placedData.Model and placedData.Model.Parent then
		-- V2.7修复：第一次PivotTo到新的XZ位置（使用finalPosition作为初值）
		if placedData.Model.PrimaryPart then
			placedData.Model:PivotTo(CFrame.new(finalPosition))
		elseif placedData.Model:FindFirstChild("HumanoidRootPart") then
			placedData.Model.HumanoidRootPart.CFrame = CFrame.new(finalPosition)
		end

		-- V2.12修复：计算角色底部位置时，排除武器等附件的影响
		local floorTopY = finalPosition.Y - PlacementConfig.PLACEMENT_Y_OFFSET  -- 地板顶面Y坐标
		local padding = 0.05

		-- 收集角色身体部件（排除武器、工具、饰品等）
		local bodyParts = {}
		local excludeNames = {"Handle", "Sword", "Spear", "Weapon", "Gun", "Bow", "Staff", "Axe", "Knife", "Shield"}

		for _, part in ipairs(placedData.Model:GetDescendants()) do
			if part:IsA("BasePart") then
				-- 排除工具和饰品
				local parent = part.Parent
				local isAccessoryOrTool = false

				while parent and parent ~= placedData.Model do
					if parent:IsA("Tool") or parent:IsA("Accoutrement") or parent:IsA("Accessory") then
						isAccessoryOrTool = true
						break
					end
					parent = parent.Parent
				end

				-- 排除武器相关名称的部件
				local isWeaponPart = false
				for _, excludeName in ipairs(excludeNames) do
					if string.find(string.lower(part.Name), string.lower(excludeName)) then
						isWeaponPart = true
						break
					end
				end

				if not isAccessoryOrTool and not isWeaponPart then
					table.insert(bodyParts, part)
				end
			end
		end

		-- 计算身体部件的最低点
		local lowestY = math.huge
		if #bodyParts > 0 then
			for _, part in ipairs(bodyParts) do
				local partBottomY = part.Position.Y - part.Size.Y / 2
				if partBottomY < lowestY then
					lowestY = partBottomY
				end
			end
		else
			-- 回退方案：如果没有找到身体部件，使用HumanoidRootPart减去标准高度
			local hrp = placedData.Model:FindFirstChild("HumanoidRootPart")
			if hrp then
				lowestY = hrp.Position.Y - 3
			else
				-- 最后回退：使用原来的包围盒方法
				local bboxCf, bboxSize = placedData.Model:GetBoundingBox()
				lowestY = bboxCf.Position.Y - bboxSize.Y / 2
			end
		end

		-- 计算需要调整的Y偏移
		local deltaY = (floorTopY + padding) - lowestY

		-- 二次PivotTo，将模型底部对齐地板顶面
		placedData.Model:PivotTo(placedData.Model:GetPivot() * CFrame.new(0, deltaY, 0))

		-- V2.7修复：更新finalPosition为校准后的实际Y坐标
		finalPosition = Vector3.new(finalPosition.X, finalPosition.Y + deltaY, finalPosition.Z)
	end

	-- 9. 占据新位置的网格
	OccupyGrid(player, newGridX, newGridZ, gridWidth, gridDepth, instanceId)

	-- 10. 更新placedData (V2.0: 使用GridWidth和GridDepth)
	placedData.Position = finalPosition
	placedData.GridX = newGridX
	placedData.GridZ = newGridZ
	placedData.GridWidth = gridWidth
	placedData.GridDepth = gridDepth

	-- 11. 更新InventorySystem中的位置
	unitInstance.PlacedPosition = finalPosition

	-- V2.8修复：移动位置后重新播放展示动画
	-- 因为PivotTo操作可能打断正在播放的动画
	PlayShowAnimation(placedData.Model, placedData.UnitId)

	-- V2.8修复：更新GridPositionSystem中的格子坐标
	-- 战役系统会读取模型上的GridPosX/GridPosY属性来计算行军目标
	-- 如果不更新这些属性，被移动的兵种在战斗中会前往错误的位置
	local gridModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("GridPositionSystem")
	if gridModule then
		local GridPositionSystem = require(gridModule :: ModuleScript)
		local gridPos = GridPositionSystem.SaveUnitGridPosition(placedData.Model, idleFloor)

		-- 同时更新placedUnits表中的GridPos
		if gridPos then
			placedData.GridPos = gridPos
		else
			placedData.GridPos = {X = newGridX, Y = newGridZ}
		end
	end

	-- 🔥修复持久化：更新DataManager中的位置数据
	local updateSuccess = DataManager.UpdatePlacedUnitPosition(player, instanceId, newGridX, newGridZ)
	if updateSuccess then
		-- 节流式保存整个玩家数据
		DataManager.SavePlayerDataThrottled(player)
		-- print(string.format(
		-- 	"%s [PlacementSystem] 🔥 已更新位置数据: 玩家 %s, 兵种 %s, 新位置 (%d,%d)",
		-- 	GameConfig.LOG_PREFIX,
		-- 	player.Name,
		-- 	instanceId,
		-- 	newGridX,
		-- 	newGridZ
		-- 	))
	else
		warn(string.format(
			"%s [PlacementSystem] 🔥 更新位置数据失败: 玩家 %s, 兵种 %s",
			GameConfig.LOG_PREFIX,
			player.Name,
			instanceId
			))
	end

	return true, "位置更新成功"
end

--[[
获取玩家所有已放置的兵种
@param player Player
@return table - 已放置兵种数据数组
]]
function PlacementSystem.GetPlacedUnits(player)
	local userId = player.UserId
	if not placedUnits[userId] then
		return {}
	end

	local result = {}
	for _, placedData in pairs(placedUnits[userId]) do
		table.insert(result, placedData)
	end

	return result
end

function PlacementSystem.CleanupOrphanPlacedUnits(player)
	local userId = player.UserId
	if not placedUnits[userId] then
		return 0
	end

	local toRemove = {}
	for instanceId in pairs(placedUnits[userId]) do
		local unitInstance = InventorySystem.GetUnitByInstanceId(player, instanceId)
		if not unitInstance then
			table.insert(toRemove, instanceId)
		end
	end

	local removed = 0
	for _, instanceId in ipairs(toRemove) do
		local success = PlacementSystem.RemovePlacedUnit(player, instanceId)
		if success then
			removed = removed + 1
		end
	end

	return removed
end

--[[
清除玩家所有已放置的兵种
@param player Player
@return number - 清除的数量
]]
function PlacementSystem.ClearAllPlacedUnits(player)
	local userId = player.UserId
	if not placedUnits[userId] then
		return 0
	end

	local count = 0
	for instanceId, _ in pairs(placedUnits[userId]) do
		PlacementSystem.RemovePlacedUnit(player, instanceId)
		count = count + 1
	end

	return count
end

--[[
玩家离开时清理数据
@param player Player
]]
function PlacementSystem.OnPlayerLeaving(player)
	local userId = player.UserId

	-- 🔥修复持久化：在清理模型前先同步所有数据到DataManager
	if placedUnits[userId] then
		-- print(string.format(
		-- 	"%s [PlacementSystem] 🔥 玩家 %s 离开，同步 %d 个放置单位的数据",
		-- 	GameConfig.LOG_PREFIX,
		-- 	player.Name,
		-- 	GetTableCount(placedUnits[userId])
		-- 	))

		-- 🔥关键修复：同步内存中的放置数据到DataManager
		local syncSuccess = DataManager.SyncPlacedUnits(player, placedUnits[userId])
		if syncSuccess then
			-- print(string.format(
			-- 	"%s [PlacementSystem] ✅ 玩家 %s 的放置数据已同步到DataManager",
			-- 	GameConfig.LOG_PREFIX,
			-- 	player.Name
			-- 	))
		else
			warn(string.format(
				"%s [PlacementSystem] ❌ 玩家 %s 的放置数据同步失败",
				GameConfig.LOG_PREFIX,
				player.Name
				))
		end

		-- 强制保存一次玩家数据（包含所有已放置的单位）
		local isShuttingDown = DataManager.IsShuttingDown and DataManager.IsShuttingDown() or false
		if not isShuttingDown then
			local saveSuccess, saveError = pcall(function()
				DataManager.SavePlayerData(player, 3)
			end)

			if not saveSuccess then
				warn(string.format(
					"%s [PlacementSystem] 🔥 玩家 %s 离开时保存数据失败: %s",
					GameConfig.LOG_PREFIX,
					player.Name,
					tostring(saveError)
					))
			end
		end
	end

	-- 清除所有已放置的兵种模型（注意：不再清除DataManager中的数据）
	if placedUnits[userId] then
		for instanceId, placedData in pairs(placedUnits[userId]) do
			if placedData.Model and placedData.Model.Parent then
				placedData.Model:Destroy()
			end
		end
		placedUnits[userId] = nil  -- 只清除内存中的引用
	end

	-- 清除网格占用数据
	if gridOccupancy[userId] then
		gridOccupancy[userId] = nil
	end

	-- print(string.format(
	-- 	"%s [PlacementSystem] 🔥 玩家 %s 的放置数据已清理（保留持久化数据）",
	-- 	GameConfig.LOG_PREFIX,
	-- 	player.Name
	-- 	))
end

-- ==================== 🔥修复持久化：放置单位恢复功能 ====================

--[[
恢复玩家的所有放置单位（玩家重新进入游戏时调用）
@param player Player - 玩家对象
@return boolean, string - 是否成功, 恢复的单位数量或错误信息
]]
function PlacementSystem.RestorePlacedUnits(player)
	local userId = player.UserId
	local playerData = DataManager.GetPlayerData(player)
	local homeSlot = playerData and playerData.HomeSlot

	-- 1. 获取玩家的IdleFloor
	local idleFloor = GetPlayerIdleFloor(player)
	if not idleFloor then
		return false, "找不到玩家基地的IdleFloor"
	end

	-- 2. 从DataManager获取已保存的放置单位数据
	local savedPlacedUnits = DataManager.GetPlacedUnits(player)
	if not savedPlacedUnits or next(savedPlacedUnits) == nil then
		-- print(string.format(
		-- 	"%s [PlacementSystem] 🔥 玩家 %s 没有需要恢复的放置单位",
		-- 	GameConfig.LOG_PREFIX,
		-- 	player.Name
		-- 	))
		return true, "0"
	end

	-- print(string.format(
	-- 	"%s [PlacementSystem] 🔥 开始恢复玩家 %s 的 %d 个放置单位...",
	-- 	GameConfig.LOG_PREFIX,
	-- 	player.Name,
	-- 	GetTableCount(savedPlacedUnits)
	-- 	))

	local floorCenter = idleFloor.Position
	local restoredCount = 0
	local errorCount = 0

	-- 3. 初始化玩家的数据结构
	if not placedUnits[userId] then
		placedUnits[userId] = {}
	end
	if not gridOccupancy[userId] then
		gridOccupancy[userId] = {}
	end

	-- 4. 遍历保存的放置单位数据，逐一恢复
	for instanceIdRaw, savedData in pairs(savedPlacedUnits) do
		-- 修复：确保instanceId是字符串类型
		local instanceId = tostring(instanceIdRaw)

		local success, error = pcall(function()
			-- 4.1 验证InventorySystem中是否仍有对应的兵种实例
			local unitInstance = InventorySystem.GetUnitByInstanceId(player, instanceId)
			if not unitInstance then
				warn(string.format(
					"%s [PlacementSystem] 🔥 恢复失败：背包中找不到实例 %s，从放置数据中移除",
					GameConfig.LOG_PREFIX,
					instanceId
					))
				-- 从DataManager中删除无效的放置数据
				DataManager.RemovePlacedUnit(player, instanceId)
				return false
			end

			-- 4.2 验证UnitId是否匹配
			if unitInstance.UnitId ~= savedData.UnitId then
				warn(string.format(
					"%s [PlacementSystem] 🔥 恢复失败：实例 %s UnitId不匹配 (%s != %s)",
					GameConfig.LOG_PREFIX,
					instanceId,
					unitInstance.UnitId,
					savedData.UnitId
					))
				return false
			end

			-- 占地尺寸：优先使用保存的宽/深，向后兼容GridSize/配置表
			-- Prefer inventory level to avoid stale placed data overriding upgrades.
			local level = unitInstance.Level or savedData.Level or 1
			if unitInstance.Level == nil then
				unitInstance.Level = level
			end
			local gridWidth = UnitConfig.GetGridWidth(unitInstance.UnitId)
			local gridDepth = UnitConfig.GetGridDepth(unitInstance.UnitId)
			-- 回写实例占地，保持与当前配置一致
			unitInstance.GridWidth = gridWidth
			unitInstance.GridDepth = gridDepth

			-- 4.3 验证网格位置是否在边界内
			if not PlacementConfig.IsGridInBounds(savedData.GridX, savedData.GridZ, gridWidth, gridDepth) then
				warn(string.format(
					"%s [PlacementSystem] 🔥 恢复失败：实例 %s 网格位置 (%d,%d) 超出边界",
					GameConfig.LOG_PREFIX,
					instanceId,
					savedData.GridX,
					savedData.GridZ
					))
				return false
			end

			-- 4.4 检查网格位置是否被占用（跳过自己占用的情况）
			local gridOccupied = false
			for x = savedData.GridX, savedData.GridX + gridWidth - 1 do
				for z = savedData.GridZ, savedData.GridZ + gridDepth - 1 do
					local gridKey = GetGridKey(x, z)
					local occupiedBy = gridOccupancy[userId][gridKey]
					if occupiedBy and occupiedBy ~= instanceId then
						gridOccupied = true
						break
					end
				end
				if gridOccupied then
					break
				end
			end

			if gridOccupied then
				warn(string.format(
					"%s [PlacementSystem] 🔥 恢复失败：实例 %s 网格位置 (%d,%d) 已被占用",
					GameConfig.LOG_PREFIX,
					instanceId,
					savedData.GridX,
					savedData.GridZ
					))
				return false
			end

			-- 4.5 计算世界坐标位置
			local worldPosition = PlacementConfig.GridToWorld(
				savedData.GridX,
				savedData.GridZ,
				floorCenter,
				gridWidth,
				gridDepth
			)

			-- 4.6 创建兵种模型
			local model = CreateUnitModel(
				savedData.UnitId,
				worldPosition,
				instanceId,
				level,
				gridWidth,
				gridDepth,
				homeSlot
			)

			if not model then
				warn(string.format(
					"%s [PlacementSystem] 🔥 恢复失败：实例 %s 创建模型失败",
					GameConfig.LOG_PREFIX,
					instanceId
					))
				return false
			end

			-- V2.7修复：获取模型实际放置后的位置（Y已被CreateUnitModel校准）
			local actualPosition = worldPosition
			if model.PrimaryPart then
				actualPosition = model:GetPivot().Position
			elseif model:FindFirstChild("HumanoidRootPart") then
				actualPosition = model.HumanoidRootPart.Position
			end

			-- 4.7 更新InventorySystem中的兵种状态
			unitInstance.IsPlaced = true
			unitInstance.PlacedPosition = actualPosition
			-- 如果有保存的生命值，恢复它
			if savedData.Health then
				unitInstance.Health = savedData.Health
			end
			if savedData.MaxHealth then
				unitInstance.MaxHealth = savedData.MaxHealth
			end

			-- 🔧 修复：将血量同步到模型的Humanoid
			-- 问题：如果不同步，model.Humanoid会保持模板默认值（通常100）
			-- 导致首战开战时BattleManager读取错误的血量，造成"瞬间半血"
			local humanoid = model:FindFirstChild("Humanoid")
			if humanoid then
				local health, maxHealth = NormalizeUnitHealth(unitInstance, unitInstance.UnitId, level)
				if not health or not maxHealth then
					-- 使用存档的血量，如果没有则使用配置表的默认值
					health = savedData.Health or UnitConfig.CalculateHealth(savedData.UnitId, level)
					maxHealth = savedData.MaxHealth or UnitConfig.CalculateHealth(savedData.UnitId, level)
				end
				humanoid.MaxHealth = maxHealth
				humanoid.Health = math.clamp(health, 0, maxHealth)  -- 确保血量不超过最大值
				-- print(GameConfig.LOG_PREFIX, "[PlacementSystem] 同步血量到Humanoid:", savedData.UnitId, "HP:", humanoid.Health, "/", humanoid.MaxHealth)
			end

			-- 4.8 占据网格
			OccupyGrid(player, savedData.GridX, savedData.GridZ, gridWidth, gridDepth, instanceId)

			-- 4.9 保存放置数据到内存
			placedUnits[userId][instanceId] = {
				InstanceId = instanceId,
				UnitId = savedData.UnitId,
				Level = level,
				Position = actualPosition,  -- V2.7修复：使用校准后的实际位置
				GridX = savedData.GridX,
				GridZ = savedData.GridZ,
				GridSize = savedData.GridSize,
				GridWidth = gridWidth,
				GridDepth = gridDepth,
				Model = model,
				PlacedTime = os.time(),
			}

			-- 4.9.5 保存GridPos到模型（用于战役系统）
			local gridModule2 = ServerScriptService:WaitForChild("Systems"):FindFirstChild("GridPositionSystem")
			if gridModule2 then
				local GridPositionSystem = require(gridModule2 :: ModuleScript)
				local gridPos = GridPositionSystem.SaveUnitGridPosition(model, idleFloor)
				if gridPos then
					placedUnits[userId][instanceId].GridPos = gridPos
				else
					placedUnits[userId][instanceId].GridPos = {X = savedData.GridX, Y = savedData.GridZ}
				end
			end

			-- 4.10 配置兵种物理
			PhysicsManager.ConfigureUnitPhysics(model, "ally")

			-- 4.11 播放展示动画
			PlayShowAnimation(model, savedData.UnitId)
			-- 4.11.1 确保等级显示立即刷新
			UpdateLevelDisplay(model, level)

			-- print(string.format(
			-- 	"%s [PlacementSystem] 🔥 已恢复单位: %s (%s) 位置 (%d,%d)",
			-- 	GameConfig.LOG_PREFIX,
			-- 	instanceId,
			-- 	savedData.UnitId,
			-- 	savedData.GridX,
			-- 	savedData.GridZ
			-- 	))

			return true
		end)

		if success and error ~= false then
			restoredCount = restoredCount + 1
		else
			errorCount = errorCount + 1
		end
	end

	-- 5. 刷新客户端背包显示
	InventorySystem.RefreshClientInventory(player)

	-- 6. 返回恢复结果
	local message = string.format("成功恢复 %d 个，失败 %d 个", restoredCount, errorCount)
	-- print(string.format(
	-- 	"%s [PlacementSystem] 🔥 玩家 %s 放置单位恢复完成：%s",
	-- 	GameConfig.LOG_PREFIX,
	-- 	player.Name,
	-- 	message
	-- 	))

	-- 如果有失败的恢复，保存一次数据以清理无效数据
	if errorCount > 0 then
		DataManager.SavePlayerDataThrottled(player, true)  -- 强制立即保存
	end

	return true, message
end

-- ==================== 远程事件处理 ====================

--[[
检查玩家是否在战役中(V2.0新增)
@param player Player
@return boolean - 是否在战役中
]]
local function IsPlayerInCampaign(player)
	-- 懒加载CampaignManager避免循环依赖（修复：添加类型断言）
	local success, CampaignManager = pcall(function()
		local campaignModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("CampaignManager")
		if campaignModule then
			return require(campaignModule :: ModuleScript)
		end
		return nil
	end)

	if success and CampaignManager and CampaignManager.ActiveCampaigns then
		local playerId = player.UserId
		return CampaignManager.ActiveCampaigns[playerId] ~= nil
	end

	return false
end

--[[
处理开始放置请求
@param player Player
@param instanceId string
]]
local function OnStartPlacement(player, instanceId)
	-- V2.0: 战役期间禁止基地操作
	if IsPlayerInCampaign(player) then
		if InitializeEvents() then
			local responseEvent = PlacementEvents:FindFirstChild("PlacementResponse")
			if responseEvent then
				responseEvent:FireClient(player, false, "战役进行中，无法操作基地")
			end
		end
		return
	end

	-- 验证兵种实例
	local unitInstance = InventorySystem.GetUnitByInstanceId(player, instanceId)
	if not unitInstance then
		-- 通知客户端失败
		if InitializeEvents() then
			local responseEvent = PlacementEvents:FindFirstChild("PlacementResponse")
			if responseEvent then
				responseEvent:FireClient(player, false, "兵种实例不存在")
			end
		end
		return
	end

	-- 返回兵种配置信息给客户端
	local unitConfig = UnitConfig.GetUnitById(unitInstance.UnitId)
	if InitializeEvents() then
		local responseEvent = PlacementEvents:FindFirstChild("PlacementResponse")
		if responseEvent then
			responseEvent:FireClient(player, true, "可以开始放置", {
				UnitId = unitInstance.UnitId,
				InstanceId = instanceId,
				GridSize = unitInstance.GridSize,
				ModelPath = unitConfig.ModelPath,
			})
		end
	end
end

--[[
处理确认放置请求
@param player Player
@param instanceId string
@param position Vector3
]]
local function OnConfirmPlacement(player, instanceId, position)
	-- V2.0: 战役期间禁止基地操作
	if IsPlayerInCampaign(player) then
		if InitializeEvents() then
			local responseEvent = PlacementEvents:FindFirstChild("PlacementResponse")
			if responseEvent then
				responseEvent:FireClient(player, false, "战役进行中，无法操作基地")
			end
		end
		return
	end

	local success, message = PlacementSystem.PlaceUnit(player, instanceId, position)

	-- V3.3任务系统：放置成功时通知任务系统
	if success then
		local TaskSystem = nil
		local taskModule = ServerScriptService.Systems:FindFirstChild("TaskSystem")
		if taskModule then
			TaskSystem = require(taskModule)
			TaskSystem.OnPlaceUnit(player, instanceId)
		end

		-- V3.9.1引导系统：首次摆放兵种后触发引导检查
		task.delay(0.5, function()
			if player and player.Parent then
				local guideModule = ServerScriptService.Systems:FindFirstChild("GuideSystem")
				if guideModule and guideModule:IsA("ModuleScript") then
					local GuideSystem = require(guideModule :: ModuleScript)
					GuideSystem.CheckAndTriggerGuides(player)
				end
			end
		end)
	end

	-- 通知客户端结果
	if InitializeEvents() then
		local responseEvent = PlacementEvents:FindFirstChild("PlacementResponse")
		if responseEvent then
			responseEvent:FireClient(player, success, message)
		end
	end
end

--[[
处理取消放置请求
@param player Player
@param instanceId string
]]
local function OnCancelPlacement(player, instanceId)
	-- 客户端取消，不需要特殊处理
end

--[[
处理回收兵种请求 (V1.3 / V2.0扩展：战役期间禁止)
@param player Player
@param instanceId string
]]
local function OnRemoveUnit(player, instanceId)
	-- V2.0: 战役期间禁止基地操作
	if IsPlayerInCampaign(player) then
		if InitializeEvents() then
			local responseEvent = PlacementEvents:FindFirstChild("RemoveResponse")
			if responseEvent then
				responseEvent:FireClient(player, false, "战役进行中，无法操作基地", instanceId)
			end
		end
		return
	end


	-- 调用RemoveUnit移除兵种
	local success, message = PlacementSystem.RemoveUnit(player, instanceId)

	-- 通知客户端结果
	if InitializeEvents() then
		local responseEvent = PlacementEvents:FindFirstChild("RemoveResponse")
		if responseEvent then
			responseEvent:FireClient(player, success, message, instanceId)
		end
	end
end

--[[
处理更新兵种位置请求 (V1.4.1 / V2.0扩展：战役期间禁止)
@param player Player
@param instanceId string
@param newPosition Vector3
]]
local function OnUpdatePosition(player, instanceId, newPosition)
	-- V2.0: 战役期间禁止基地操作
	if IsPlayerInCampaign(player) then
		if InitializeEvents() then
			local responseEvent = PlacementEvents:FindFirstChild("UpdateResponse")
			if responseEvent then
				responseEvent:FireClient(player, false, "战役进行中，无法操作基地", instanceId)
			end
		end
		return
	end


	-- 调用UpdateUnitPosition更新位置
	local success, message = PlacementSystem.UpdateUnitPosition(player, instanceId, newPosition)

	-- 通知客户端结果
	if InitializeEvents() then
		local responseEvent = PlacementEvents:FindFirstChild("UpdateResponse")
		if responseEvent then
			responseEvent:FireClient(player, success, message, instanceId)
		end
	end
end

--[[
初始化放置系统
]]
function PlacementSystem.Initialize()
	-- 初始化事件
	if not InitializeEvents() then
		warn(GameConfig.LOG_PREFIX, "PlacementEvents未找到，放置系统将不可用!")
		return false
	end

	-- 连接远程事件
	local startEvent = PlacementEvents:FindFirstChild("StartPlacement")
	if startEvent then
		startEvent.OnServerEvent:Connect(OnStartPlacement)
	end

	local confirmEvent = PlacementEvents:FindFirstChild("ConfirmPlacement")
	if confirmEvent then
		confirmEvent.OnServerEvent:Connect(OnConfirmPlacement)
	end

	local cancelEvent = PlacementEvents:FindFirstChild("CancelPlacement")
	if cancelEvent then
		cancelEvent.OnServerEvent:Connect(OnCancelPlacement)
	end

	-- V1.3: 连接回收事件
	local removeEvent = PlacementEvents:FindFirstChild("RemoveUnit")
	if removeEvent then
		removeEvent.OnServerEvent:Connect(OnRemoveUnit)
	end

	-- V1.4.1: 连接位置更新事件
	local updateEvent = PlacementEvents:FindFirstChild("UpdatePosition")
	if updateEvent then
		updateEvent.OnServerEvent:Connect(OnUpdatePosition)
	end

	-- 连接玩家离开事件
	game.Players.PlayerRemoving:Connect(PlacementSystem.OnPlayerLeaving)

	return true
end

--[[
获取玩家已放置的所有兵种模型（V2.0新增，用于战役系统）
@param player Player
@return table - 兵种Model实例列表
]]
function PlacementSystem.GetPlacedUnitModels(player)
	local userId = player.UserId
	local units = {}

	if placedUnits[userId] then
		for instanceId, placedData in pairs(placedUnits[userId]) do
			if placedData.Model and placedData.Model.Parent then
				table.insert(units, placedData.Model)
			end
		end
	end

	return units
end

--[[
V4.0新增：暴露CreateUnitModel供CampaignManager使用
用于战役结束后重新创建丢失的单位
@param unitId string - 兵种ID
@param position Vector3 - 生成位置
@param instanceId string - 实例ID
@param level number - 等级
@param gridWidth number - 占地宽度
@param gridDepth number - 占地深度
@return Model|nil - 创建的单位模型
]]
function PlacementSystem.CreateUnitModel(unitId, position, instanceId, level, gridWidth, gridDepth, homeSlot)
	return CreateUnitModel(unitId, position, instanceId, level, gridWidth, gridDepth, homeSlot)
end

return PlacementSystem
