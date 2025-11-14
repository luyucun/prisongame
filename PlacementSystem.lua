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

-- 远程事件(延迟获取)
local PlacementEvents = nil

-- ==================== 数据结构 ====================
--[[
PlacedUnitData = {
    InstanceId = string,       -- 兵种实例ID
    UnitId = string,           -- 兵种配置ID
    Position = Vector3,        -- 放置位置
    GridX = number,            -- 网格X坐标
    GridZ = number,            -- 网格Z坐标
    GridSize = number,         -- 占地大小
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
检查网格是否被占用
@param player Player
@param gridX number
@param gridZ number
@param gridSize number - 兵种占地大小 (1, 4, 9)
@return boolean, string - 是否占用, 占用的instanceId
]]
local function IsGridOccupied(player, gridX, gridZ, gridSize)
    local userId = player.UserId
    if not gridOccupancy[userId] then
        gridOccupancy[userId] = {}
    end

    local gridWidth = math.sqrt(gridSize)

    -- 检查所有需要占据的格子
    for i = 0, gridWidth - 1 do
        for j = 0, gridWidth - 1 do
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
占据网格
@param player Player
@param gridX number
@param gridZ number
@param gridSize number
@param instanceId string
]]
local function OccupyGrid(player, gridX, gridZ, gridSize, instanceId)
    local userId = player.UserId
    if not gridOccupancy[userId] then
        gridOccupancy[userId] = {}
    end

    local gridWidth = math.sqrt(gridSize)

    for i = 0, gridWidth - 1 do
        for j = 0, gridWidth - 1 do
            local occupyX = gridX + i
            local occupyZ = gridZ + j
            local gridKey = GetGridKey(occupyX, occupyZ)
            gridOccupancy[userId][gridKey] = instanceId
        end
    end
end

--[[
释放网格
@param player Player
@param gridX number
@param gridZ number
@param gridSize number
]]
local function ReleaseGrid(player, gridX, gridZ, gridSize)
    local userId = player.UserId
    if not gridOccupancy[userId] then
        return
    end

    local gridWidth = math.sqrt(gridSize)

    for i = 0, gridWidth - 1 do
        for j = 0, gridWidth - 1 do
            local releaseX = gridX + i
            local releaseZ = gridZ + j
            local gridKey = GetGridKey(releaseX, releaseZ)
            gridOccupancy[userId][gridKey] = nil
        end
    end
end

--[[
更新模型等级显示 V1.4
@param model Model - 兵种模型
@param level number - 等级
]]
local function UpdateLevelDisplay(model, level)
    if not model then
        if GameConfig.DEBUG_MODE then
            warn(GameConfig.LOG_PREFIX, "UpdateLevelDisplay: 模型为空")
        end
        return
    end

    -- 查找Head下的BillboardGui
    local head = model:FindFirstChild("Head")
    if not head then
        if GameConfig.DEBUG_MODE then
            warn(GameConfig.LOG_PREFIX, "UpdateLevelDisplay: 模型没有Head部件:", model.Name)
        end
        return
    end

    local billboardGui = head:FindFirstChild("BillboardGui")
    if not billboardGui then
        if GameConfig.DEBUG_MODE then
            warn(GameConfig.LOG_PREFIX, "UpdateLevelDisplay: Head下没有BillboardGui:", model.Name)
        end
        return
    end

    local textLabel = billboardGui:FindFirstChild("TextLabel")
    if not textLabel then
        if GameConfig.DEBUG_MODE then
            warn(GameConfig.LOG_PREFIX, "UpdateLevelDisplay: BillboardGui下没有TextLabel:", model.Name)
        end
        return
    end

    -- 更新等级显示
    if level >= UnitConfig.MAX_LEVEL then
        textLabel.Text = "Lv.Max"
    else
        textLabel.Text = "Lv." .. tostring(level)
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "更新等级显示成功:", model.Name, "Level:", level, "显示:", textLabel.Text)
    end
end

--[[
播放展示动画 (V1.5.2新增)
@param model Model - 兵种模型
@param unitId string - 兵种ID
]]
local function PlayShowAnimation(model, unitId)
	if not model or not unitId then
		if GameConfig.DEBUG_MODE then
			warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: 参数无效")
		end
		return
	end

	-- 获取展示动画ID
	local showAnimId = UnitConfig.GetShowAnimationId(unitId)

	-- 如果没有配置展示动画，直接返回
	if not showAnimId or showAnimId == "" or showAnimId == "0" then
		if GameConfig.DEBUG_MODE then
			print(GameConfig.LOG_PREFIX, "PlayShowAnimation: 单位", unitId, "未配置展示动画")
		end
		return
	end

	-- V1.5.2调试：验证动画ID格式
	if not tonumber(showAnimId) then
		warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: 动画ID格式无效:", unitId, "AnimID:", showAnimId, "类型:", type(showAnimId))
		return
	end

	-- 查找Humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		if GameConfig.DEBUG_MODE then
			warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: 模型没有Humanoid:", model.Name)
		end
		return
	end

	-- 查找Animator
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: Humanoid没有Animator:", model.Name, "- 尝试创建Animator")
		-- 尝试创建Animator（Roblox会自动创建，但保险起见）
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: 无法获取Animator，动画无法播放")
			return
		end
	end

	-- 创建动画实例
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. showAnimId

	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "PlayShowAnimation: 准备加载动画 -", unitId, "完整AnimationId:", animation.AnimationId)
	end

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

	-- 设置循环播放
	animTrack.Looped = true

	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "PlayShowAnimation: 动画加载成功，准备播放 -", unitId, "动画长度:", animTrack.Length, "秒")
	end

	-- 播放动画
	local playSuccess, playError = pcall(function()
		animTrack:Play()
	end)

	if not playSuccess then
		warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: 动画播放失败:", unitId, "错误:", playError)
		animation:Destroy()
		return
	end

	-- 检查动画是否真的在播放
	task.wait(0.1)  -- 等待一小段时间
	if animTrack.IsPlaying then
		if GameConfig.DEBUG_MODE then
			print(GameConfig.LOG_PREFIX, "PlayShowAnimation: ✅ 动画确认正在播放:", unitId, "当前时间位置:", animTrack.TimePosition)
		end
	else
		warn(GameConfig.LOG_PREFIX, "PlayShowAnimation: ⚠️ 动画未播放:", unitId, "IsPlaying=false")
	end

	-- V1.5.2修复：循环动画在停止时清理Animation对象，防止内存泄漏
	-- 当单位被回收时，animTrack:Stop()会触发此事件
	animTrack.Stopped:Connect(function()
		if animation and animation.Parent then
			animation:Destroy()
		end
	end)

	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "PlayShowAnimation: 成功播放展示动画:", unitId, "AnimID:", showAnimId)
	end
end

--[[
递归搜索文件夹
@param folder Instance - 要搜索的文件夹
@param targetName string - 目标名称
@return Model|nil - 找到的模型
]]
local function SearchFolderRecursive(folder, targetName)
    -- 先在当前层级查找
    local found = folder:FindFirstChild(targetName)
    if found and found:IsA("Model") then
        return found
    end

    -- 递归搜索所有子文件夹
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Folder") then
            local result = SearchFolderRecursive(child, targetName)
            if result then
                return result
            end
        end
    end

    return nil
end

--[[
创建兵种模型到世界
@param unitId string
@param position Vector3
@param instanceId string - V1.3: 添加instanceId参数用于标记模型
@param level number - V1.4: 添加等级参数
@param gridSize number - V1.4: 添加占地大小参数
@return Model|nil
]]
local function CreateUnitModel(unitId, position, instanceId, level, gridSize)
    -- V1.4: 处理默认参数
    level = level or 1
    gridSize = gridSize or 1

    local unitConfig = UnitConfig.GetUnitById(unitId)
    if not unitConfig then
        return nil
    end

    -- V1.5.1修复: 递归搜索Role文件夹下的所有子文件夹
    -- 支持任意文件夹结构，如 Role/Basic/Noob, Role/Rifle/AK-47 等
    local roleFolder = ReplicatedStorage:FindFirstChild("Role")
    if not roleFolder then
        warn(GameConfig.LOG_PREFIX, "找不到Role文件夹")
        return nil
    end

    local modelTemplate = SearchFolderRecursive(roleFolder, unitId)

    if not modelTemplate then
        warn(GameConfig.LOG_PREFIX, "在Role文件夹下找不到模型:", unitId, "(配置路径:", unitConfig.ModelPath, ")")
        return nil
    end

    -- 克隆模型
    local model = modelTemplate:Clone()

    -- V1.3: 设置InstanceId属性，用于回收时识别
    if instanceId then
        model:SetAttribute("InstanceId", instanceId)
    end

    -- V1.4: 设置等级和UnitId属性，用于拖动合成时识别
    model:SetAttribute("Level", level)
    model:SetAttribute("UnitId", unitId)
    model:SetAttribute("GridSize", gridSize)
    -- V2.1补充：添加只读属性用于调试兵种类型（可选）
    model:SetAttribute("UnitType", UnitConfig.IsRangedUnit(unitId) and "Ranged" or "Melee")

    -- V1.4: 更新等级显示
    UpdateLevelDisplay(model, level)

    -- 设置位置
    if model.PrimaryPart then
        model:SetPrimaryPartCFrame(CFrame.new(position))
    elseif model:FindFirstChild("HumanoidRootPart") then
        model.HumanoidRootPart.CFrame = CFrame.new(position)
    end

    -- V1.5.2修复：IdleFloor上的单位需要播放动画
    -- 只锚定根部件防止移动/下沉，其他部件保持可动以支持动画
    local rootPart = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart

    if rootPart then
        -- 锚定根部件，防止模型移动和下沉
        rootPart.Anchored = true
        rootPart.CanCollide = true

        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "锚定根部件:", rootPart.Name, "模型:", model.Name)
        end
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

    model.Parent = Workspace

    return model
end

-- ==================== 公共接口 ====================

--[[
验证放置位置是否合法
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

    -- 4.1 调试信息：打印客户端传来的位置和服务端的IdleFloor信息
    if GameConfig.DEBUG_MODE then
        local floorCenter = idleFloor.Position
        print(string.format(
            "%s ValidatePlacement - 客户端位置:(%.2f, %.2f, %.2f), IdleFloor中心:(%.2f, %.2f, %.2f), 玩家:%s",
            GameConfig.LOG_PREFIX,
            position.X, position.Y, position.Z,
            floorCenter.X, floorCenter.Y, floorCenter.Z,
            player.Name
        ))
    end

    -- 5. 转换为网格坐标
    local floorCenter = idleFloor.Position
    local gridX, gridZ = PlacementConfig.WorldToGrid(position, floorCenter)

    if GameConfig.DEBUG_MODE then
        print(string.format(
            "%s 网格索引 - gridX:%d, gridZ:%d, GridSize:%d",
            GameConfig.LOG_PREFIX, gridX, gridZ, unitInstance.GridSize
        ))
    end

    -- 6. 检查边界
    if not PlacementConfig.IsGridInBounds(gridX, gridZ, unitInstance.GridSize) then
        if GameConfig.DEBUG_MODE then
            print(string.format(
                "%s 边界检查失败 - 网格:(%d, %d) 占地:%d 最大网格:(120, 120) - 玩家:%s",
                GameConfig.LOG_PREFIX, gridX, gridZ, unitInstance.GridSize, player.Name
            ))
            print(string.format(
                "%s 详细信息 - 客户端位置:(%.2f, %.2f, %.2f), IdleFloor中心:(%.2f, %.2f, %.2f)",
                GameConfig.LOG_PREFIX,
                position.X, position.Y, position.Z,
                floorCenter.X, floorCenter.Y, floorCenter.Z
            ))
        end
        return false, "超出放置范围"
    end

    -- 7. 检查碰撞
    if PlacementConfig.ENABLE_COLLISION_CHECK then
        local isOccupied, occupyingId = IsGridOccupied(player, gridX, gridZ, unitInstance.GridSize)
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
放置兵种
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
    local idleFloor = GetPlayerIdleFloor(player)
    local floorCenter = idleFloor.Position

    -- 转换为网格坐标
    local gridX, gridZ = PlacementConfig.WorldToGrid(position, floorCenter)

    -- 计算精确的放置位置 (对齐到网格中心，传入gridSize以正确计算多格兵种的中心)
    local finalPosition = PlacementConfig.GridToWorld(gridX, gridZ, floorCenter, unitInstance.GridSize)

    -- V1.3: 传递instanceId到CreateUnitModel
    -- V1.4: 传递level和gridSize到CreateUnitModel
    local model = CreateUnitModel(unitInstance.UnitId, finalPosition, instanceId, unitInstance.Level, unitInstance.GridSize)
    if not model then
        return false, "创建模型失败"
    end

    -- 更新InventorySystem中的实例状态
    unitInstance.IsPlaced = true
    unitInstance.PlacedPosition = finalPosition

    -- 占据网格
    OccupyGrid(player, gridX, gridZ, unitInstance.GridSize, instanceId)

    -- 保存放置数据
    local userId = player.UserId
    if not placedUnits[userId] then
        placedUnits[userId] = {}
    end

    placedUnits[userId][instanceId] = {
        InstanceId = instanceId,
        UnitId = unitInstance.UnitId,
        Position = finalPosition,
        GridX = gridX,
        GridZ = gridZ,
        GridSize = unitInstance.GridSize,
        Model = model,
        PlacedTime = os.time(),
    }

    -- V2.0新增: 保存GridPos到模型（用于战役系统）
    local GridPositionSystem = require(ServerScriptService.Systems.GridPositionSystem)
    local gridPos = GridPositionSystem.SaveUnitGridPosition(model, idleFloor)

    -- 同时保存到placedUnits表中
    if gridPos then
        placedUnits[userId][instanceId].GridPos = gridPos
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "兵种放置成功，GridPos:", gridPos.X, gridPos.Y)
        end
    else
        warn(GameConfig.LOG_PREFIX, "保存GridPos失败，使用默认值")
        placedUnits[userId][instanceId].GridPos = {X = gridX, Y = gridZ}
    end

    -- 配置兵种物理（禁用与玩家的碰撞）
    PhysicsManager.ConfigureUnitPhysics(model)

    -- V1.5.2新增: 播放show动画（展示动画）
    PlayShowAnimation(model, unitInstance.UnitId)

    -- 通知InventorySystem刷新客户端背包显示
    InventorySystem.RefreshClientInventory(player)

    return true, "放置成功"
end

--[[
取消放置(移除已放置的兵种)
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

    -- 释放网格
    ReleaseGrid(player, placedData.GridX, placedData.GridZ, placedData.GridSize)

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

    if GameConfig.DEBUG_MODE then
        print(string.format(
            "%s 回收兵种成功 - 玩家:%s 实例ID:%s",
            GameConfig.LOG_PREFIX, player.Name, instanceId
        ))
    end

    return true, "回收成功"
end

--[[
更新已放置兵种的位置（V1.4.1：拖动换位功能）
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

    -- 3. 转换为网格坐标
    local floorCenter = idleFloor.Position
    local newGridX, newGridZ = PlacementConfig.WorldToGrid(newPosition, floorCenter)

    -- 4. 检查边界
    if not PlacementConfig.IsGridInBounds(newGridX, newGridZ, unitInstance.GridSize) then
        if GameConfig.DEBUG_MODE then
            print(string.format(
                "%s 更新位置边界检查失败 - 网格:(%d, %d) 占地:%d",
                GameConfig.LOG_PREFIX, newGridX, newGridZ, unitInstance.GridSize
            ))
        end
        return false, "超出放置范围"
    end

    -- 5. 检查新位置是否与其他兵种冲突（排除自己）
    if PlacementConfig.ENABLE_COLLISION_CHECK then
        local isOccupied, occupyingId = IsGridOccupied(player, newGridX, newGridZ, unitInstance.GridSize)
        if isOccupied and occupyingId ~= instanceId then
            return false, "位置已被占用"
        end
    end

    -- 6. 释放旧位置的网格
    ReleaseGrid(player, placedData.GridX, placedData.GridZ, placedData.GridSize)

    -- 7. 计算新的精确位置（传入gridSize以正确计算多格兵种的中心）
    local finalPosition = PlacementConfig.GridToWorld(newGridX, newGridZ, floorCenter, unitInstance.GridSize)

    -- 8. 更新模型位置
    if placedData.Model and placedData.Model.Parent then
        if placedData.Model.PrimaryPart then
            placedData.Model:SetPrimaryPartCFrame(CFrame.new(finalPosition))
        elseif placedData.Model:FindFirstChild("HumanoidRootPart") then
            placedData.Model.HumanoidRootPart.CFrame = CFrame.new(finalPosition)
        end
    end

    -- 9. 占据新位置的网格
    OccupyGrid(player, newGridX, newGridZ, unitInstance.GridSize, instanceId)

    -- 10. 更新placedData
    placedData.Position = finalPosition
    placedData.GridX = newGridX
    placedData.GridZ = newGridZ

    -- 11. 更新InventorySystem中的位置
    unitInstance.PlacedPosition = finalPosition

    if GameConfig.DEBUG_MODE then
        print(string.format(
            "%s 更新兵种位置成功 - 玩家:%s 实例ID:%s 新网格:(%d, %d)",
            GameConfig.LOG_PREFIX, player.Name, instanceId, newGridX, newGridZ
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

    -- 清除所有已放置的兵种模型
    if placedUnits[userId] then
        for instanceId, placedData in pairs(placedUnits[userId]) do
            if placedData.Model and placedData.Model.Parent then
                placedData.Model:Destroy()
            end
        end
        placedUnits[userId] = nil
    end

    -- 清除网格占用数据
    if gridOccupancy[userId] then
        gridOccupancy[userId] = nil
    end
end

-- ==================== 远程事件处理 ====================

--[[
检查玩家是否在战役中(V2.0新增)
@param player Player
@return boolean - 是否在战役中
]]
local function IsPlayerInCampaign(player)
	-- 懒加载CampaignManager避免循环依赖
	local success, CampaignManager = pcall(function()
		return require(ServerScriptService.Systems.CampaignManager)
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
		if GameConfig.DEBUG_MODE then
			warn(GameConfig.LOG_PREFIX, "玩家", player.Name, "在战役中尝试放置兵种，已拒绝")
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
		if GameConfig.DEBUG_MODE then
			warn(GameConfig.LOG_PREFIX, "玩家", player.Name, "在战役中尝试确认放置，已拒绝")
		end
		return
	end

    local success, message = PlacementSystem.PlaceUnit(player, instanceId, position)

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
		if GameConfig.DEBUG_MODE then
			warn(GameConfig.LOG_PREFIX, "玩家", player.Name, "在战役中尝试回收兵种，已拒绝")
		end
		return
	end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "处理回收请求:", player.Name, instanceId)
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
		if GameConfig.DEBUG_MODE then
			warn(GameConfig.LOG_PREFIX, "玩家", player.Name, "在战役中尝试移动兵种，已拒绝")
		end
		return
	end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "处理位置更新请求:", player.Name, instanceId)
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
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "已连接RemoveUnit事件")
        end
    end

    -- V1.4.1: 连接位置更新事件
    local updateEvent = PlacementEvents:FindFirstChild("UpdatePosition")
    if updateEvent then
        updateEvent.OnServerEvent:Connect(OnUpdatePosition)
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "已连接UpdatePosition事件")
        end
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

return PlacementSystem
