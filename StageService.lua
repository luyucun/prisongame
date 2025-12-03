--[[
=====================================================
脚本名称: StageService
脚本类型: ModuleScript (服务端)
脚本位置: ServerScriptService/Systems/StageService.lua
=====================================================

功能描述:
- 动态生成关卡场景
- 从EnemyConfig配置表加载敌人数据
- 关卡缓存管理
- 关卡清理

]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- 引用配置和系统
local EnemyConfig = require(ReplicatedStorage.Config.EnemyConfig)
local UnitConfig = require(ReplicatedStorage.Config.UnitConfig)
local GridPositionSystem = require(ServerScriptService.Systems.GridPositionSystem)
-- V2.2新增：等级显示辅助工具
local LevelDisplayHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("LevelDisplayHelper"))

local StageService = {}

-- V2.3.2新增：简单调试日志函数
local function DebugLog(msg)
	print("[StageService] " .. tostring(msg))
end

-- 缓存: [playerId] = {[stageNum] = stageFolderRef}
StageService.StageCache = {}

-- V2.7修复：统一从GameConfig读取配置，避免硬编码
local GameConfigModule = require(ReplicatedStorage.Config.GameConfig)

-- 获取模板风格（支持配置）
local function GetTemplateStyle()
	return GameConfigModule.Campaign.StageTemplateStyle or "Style01"  -- 默认Style01
end

-- V2.7新增：获取关卡Z轴间距（从GameConfig读取）
local function GetStageOffsetZ()
	return GameConfigModule.Campaign.StageGenerateOffset or 169  -- 默认169
end

--[[
    递归查找关卡组件（支持嵌套文件夹结构）
    @param stageFolder Folder - 关卡文件夹
    @param partName string - 组件名称（如"Base", "IdleFloor"）
    @return Instance - 找到的组件，未找到返回nil
]]
local function FindStagePart(stageFolder, partName)
    if not stageFolder then
        return nil
    end

    -- 先尝试直接查找（性能优化）
    local part = stageFolder:FindFirstChild(partName)
    if part then
        return part
    end

    -- 递归查找
    return stageFolder:FindFirstChild(partName, true)
end

--[[
    查找关卡的空气墙（V2.0.3新增）
    @param stageFolder Folder - 关卡文件夹
    @return Part|nil - AirWall Part，未找到返回nil
]]
local function FindAirWall(stageFolder)
    if not stageFolder then
        warn("[StageService] FindAirWall: stageFolder为nil")
        return nil
    end

    local airWall = FindStagePart(stageFolder, "AirWall")

    if not airWall then
        warn("[StageService] 未找到AirWall，关卡:", stageFolder.Name, "请检查模板配置")
    end

    return airWall
end

--[[
    设置空气墙状态（V2.0.3新增）
    @param stageFolder Folder - 关卡文件夹
    @param isOpen boolean - true=开启（玩家可通过，CanCollide=false），false=关闭（阻挡玩家，CanCollide=true）
    @return boolean - 是否设置成功
]]
function StageService.SetAirWallState(stageFolder, isOpen)
    local airWall = FindAirWall(stageFolder)

    if not airWall then
        -- 空气墙缺失，返回false但不中断流程
        return false
    end

    -- 设置碰撞属性（isOpen=true时，CanCollide=false，允许通过）
    airWall.CanCollide = not isOpen

    -- 可选：调试时可以修改透明度
    -- 开启时更透明（0.8），关闭时更可见（0.3）
    if airWall:IsA("BasePart") then
        airWall.Transparency = isOpen and 0.9 or 0.5
    end

    return true
end

--[[
    获取或创建关卡
    @param playerId number - 玩家ID
    @param stageNum number - 关卡编号
    @param resetAirWall boolean - 是否重置空气墙状态(可选,默认false不重置)
    @return Folder - 关卡文件夹引用
]]
function StageService.GetOrCreateStage(playerId, stageNum, resetAirWall)
    -- 检查缓存
    if StageService.StageCache[playerId] and StageService.StageCache[playerId][stageNum] then
        local cached = StageService.StageCache[playerId][stageNum]

        -- 验证缓存的Stage是否仍然有效且属于正确的Home
        if cached and cached.Parent then
            -- 如果是Stage001，需要额外验证是否属于当前玩家的Home
            if stageNum == 1 then
                local homeId = StageService.GetPlayerHomeId(playerId)
                if homeId then
                    local expectedParent = Workspace.Home:FindFirstChild("PlayerHome" .. homeId):FindFirstChild("Stage")
                    if cached.Parent ~= expectedParent then
                        warn("[StageService] Stage001缓存失效，HomeId已变化")
                        StageService.StageCache[playerId][stageNum] = nil
                    else
                        -- V2.9修复：检查敌人是否存在，如果被销毁则重新加载
                        local idleFloorEnemy = cached:FindFirstChild("IdleFloorEnemy", true)
                        if idleFloorEnemy then
                            local hasEnemies = false
                            for _, child in ipairs(idleFloorEnemy:GetChildren()) do
                                if child:IsA("Model") and child:FindFirstChild("Humanoid") then
                                    hasEnemies = true
                                    break
                                end
                            end
                            if not hasEnemies then
                                DebugLog("Stage" .. stageNum .. " 敌人已被销毁，重新加载敌人数据")
                                StageService.LoadEnemyData(cached, stageNum)
                            end
                        end

                        -- V2.0.4修复：只有显式要求时才重置空气墙状态
                        if resetAirWall then
                            StageService.SetAirWallState(cached, false)
                        end
                        return cached
                    end
                end
            else
                -- V2.9修复：非Stage001也检查敌人是否存在
                local idleFloorEnemy = cached:FindFirstChild("IdleFloorEnemy", true)
                if idleFloorEnemy then
                    local hasEnemies = false
                    for _, child in ipairs(idleFloorEnemy:GetChildren()) do
                        if child:IsA("Model") and child:FindFirstChild("Humanoid") then
                            hasEnemies = true
                            break
                        end
                    end
                    if not hasEnemies then
                        DebugLog("Stage" .. stageNum .. " 敌人已被销毁，重新加载敌人数据")
                        StageService.LoadEnemyData(cached, stageNum)
                    end
                end

                -- V2.0.4修复：只有显式要求时才重置空气墙状态
                if resetAirWall then
                    StageService.SetAirWallState(cached, false)
                end
                return cached
            end
        end
    end

    -- V2.0.1修改：Stage001也动态生成
    if stageNum == 1 then
        local homeId = StageService.GetPlayerHomeId(playerId)
        if not homeId then
            warn("[StageService] 玩家未分配基地，playerId:", playerId)
            return nil
        end

        -- 1. 检查场景中是否已存在Stage001（兼容旧场景）
        local stageContainer = Workspace.Home:FindFirstChild("PlayerHome" .. homeId)
        if not stageContainer then
            warn("[StageService] PlayerHome未找到，homeId:", homeId)
            return nil
        end

        local stageFolder = stageContainer:FindFirstChild("Stage")
        if not stageFolder then
            warn("[StageService] Stage文件夹未找到，homeId:", homeId)
            return nil
        end

        local existing = stageFolder:FindFirstChild("Stage001")
        if existing then
            -- V2.0.4修复：只有显式要求时才重置空气墙状态
            if resetAirWall then
                StageService.SetAirWallState(existing, false)
            end
            -- 缓存并返回
            if not StageService.StageCache[playerId] then
                StageService.StageCache[playerId] = {}
            end
            StageService.StageCache[playerId][1] = existing
            return existing
        end

        -- 2. 场景中不存在，动态生成Stage001
        local stage001 = StageService.GenerateStage001(homeId)
        if stage001 then
            -- 缓存
            if not StageService.StageCache[playerId] then
                StageService.StageCache[playerId] = {}
            end
            StageService.StageCache[playerId][1] = stage001
        end
        return stage001
    end

    -- Stage002及以后：生成新关卡
    local stageFolder = StageService.GenerateStage(playerId, stageNum)

    -- 缓存
    if stageFolder then
        if not StageService.StageCache[playerId] then
            StageService.StageCache[playerId] = {}
        end
        StageService.StageCache[playerId][stageNum] = stageFolder
    end

    return stageFolder
end

--[[
    生成Stage001（V2.0.1新增）
    @param homeId number - 基地ID (1-6)
    @return Folder - 生成的Stage001文件夹
]]
function StageService.GenerateStage001(homeId)
    local success, result = pcall(function()
        -- 1. 获取目标坐标
        local GameConfig = require(ReplicatedStorage.Config.GameConfig)
        local targetPosition = GameConfig.Campaign.Stage001Positions[homeId]

        if not targetPosition then
            warn("[StageService] Stage001坐标配置未找到，homeId:", homeId)
            return nil
        end

        -- 2. 获取模板（Stage001使用StageMiddle模板）
        local stageTemplateRoot = ReplicatedStorage:FindFirstChild("StageTemplate")
        if not stageTemplateRoot then
            warn("[StageService] StageTemplate文件夹不存在")
            return nil
        end

        local templateStyle = GetTemplateStyle()
        local templatePath = stageTemplateRoot:FindFirstChild(templateStyle)
        if not templatePath then
            warn("[StageService] 模板风格未找到:", templateStyle)
            return nil
        end

        local template = templatePath:FindFirstChild("StageMiddle")
        if not template then
            warn("[StageService] StageMiddle模板未找到")
            return nil
        end

        -- 3. 克隆模板
        local newStage = template:Clone()

        -- 4. 找到模板中的Base
        local templateBase = FindStagePart(newStage, "Base")
        if not templateBase then
            warn("[StageService] 模板中Base未找到（已递归搜索）")
            newStage:Destroy()
            return nil
        end

        -- 5. 计算偏移量并移动整个关卡
        -- V2.0.1修复：正确的坐标变换逻辑
        -- 原理：让Base的Position移动到targetPosition，保持旋转不变
        local originalBaseCFrame = templateBase.CFrame
        local targetBaseCFrame = CFrame.new(targetPosition) * (originalBaseCFrame - originalBaseCFrame.Position)

        -- 计算整体偏移变换
        local offsetTransform = targetBaseCFrame * originalBaseCFrame:Inverse()

        for _, child in ipairs(newStage:GetDescendants()) do
            if child:IsA("BasePart") then
                child.CFrame = offsetTransform * child.CFrame
            end
        end

        -- 6. 命名
        newStage.Name = "Stage001"

        -- 7. 放入场景
        local stageContainer = Workspace.Home:FindFirstChild("PlayerHome" .. homeId):FindFirstChild("Stage")
        if not stageContainer then
            warn("[StageService] Stage容器未找到，homeId:", homeId)
            newStage:Destroy()
            return nil
        end

        newStage.Parent = stageContainer

        -- 8. 加载敌人数据
        StageService.LoadEnemyData(newStage, 1)

        -- V2.0.3：生成后默认锁定空气墙
        StageService.SetAirWallState(newStage, false)

        return newStage
    end)

    if success then
        return result
    else
        warn("[StageService] 生成Stage001失败:", result)
        return nil
    end
end

--[[
    生成关卡（Stage002及以后）
    @param playerId number - 玩家ID
    @param stageNum number - 关卡编号
    @return Folder - 生成的关卡文件夹
]]
function StageService.GenerateStage(playerId, stageNum)
    local success, result = pcall(function()
        -- 获取玩家HomeId
        local homeId = StageService.GetPlayerHomeId(playerId)
        if not homeId then
            warn("[StageService] 玩家未分配基地，playerId:", playerId)
            return nil
        end

        -- 获取配置
        local GameConfig = require(ReplicatedStorage.Config.GameConfig)
        local totalStages = GameConfig.Campaign.MaxStages

        -- 确定模板类型
        local templateName
        if stageNum >= totalStages then
            templateName = "StageEnd"
        else
            templateName = "StageMiddle"
        end

        -- 获取模板
        local stageTemplateRoot = ReplicatedStorage:FindFirstChild("StageTemplate")
        if not stageTemplateRoot then
            warn("[StageService] StageTemplate文件夹不存在，请在ReplicatedStorage中创建")
            return nil
        end

        -- V2.0修复：从配置读取模板风格，支持策划动态配置
        local templateStyle = GetTemplateStyle()
        local templatePath = stageTemplateRoot:FindFirstChild(templateStyle)
        if not templatePath then
            warn("[StageService] 模板风格未找到:", templateStyle, "请检查ReplicatedStorage/StageTemplate路径")
            return nil
        end

        local template = templatePath:FindFirstChild(templateName)
        if not template then
            warn("[StageService] 模板未找到:", templateName, "路径:", templatePath:GetFullName())
            return nil
        end

        -- 获取前一关的位置
        local previousStage = StageService.GetOrCreateStage(playerId, stageNum - 1)
        if not previousStage then
            warn("[StageService] 前一关未找到，stageNum:", stageNum - 1)
            return nil
        end

        -- V2.0修复：使用递归查找，支持Base在子文件夹中（如StageNodes/Base）
        local previousBase = FindStagePart(previousStage, "Base")
        if not previousBase then
            warn("[StageService] 前一关Base未找到（已递归搜索），关卡:", previousStage:GetFullName())
            return nil
        end

        -- V2.0修复：计算新关卡位置（沿世界Z轴负方向偏移，不受Base旋转影响）
        -- V2.7修复：使用GetStageOffsetZ()从GameConfig动态读取间距
        local stageOffsetZ = GetStageOffsetZ()
        local newBaseCFrame = CFrame.new(previousBase.Position - Vector3.new(0, 0, stageOffsetZ)) * (previousBase.CFrame - previousBase.Position)

        -- 克隆模板
        local newStage = template:Clone()

        -- V2.0修复：使用递归查找，支持Base在子文件夹中（如StageNodes/Base）
        local newBase = FindStagePart(newStage, "Base")
        if not newBase then
            warn("[StageService] 模板中Base未找到（已递归搜索），模板:", templateName)
            newStage:Destroy()
            return nil
        end

        -- 计算偏移量并移动整个关卡
        local offsetCFrame = newBaseCFrame * newBase.CFrame:Inverse()
        for _, child in ipairs(newStage:GetDescendants()) do
            if child:IsA("BasePart") then
                child.CFrame = offsetCFrame * child.CFrame
            end
        end

        -- 命名
        newStage.Name = string.format("Stage%03d", stageNum)

        -- 放入场景
        local stageContainer = Workspace.Home:FindFirstChild("PlayerHome" .. homeId):FindFirstChild("Stage")
        if not stageContainer then
            warn("[StageService] Stage容器未找到，homeId:", homeId)
            newStage:Destroy()
            return nil
        end

        newStage.Parent = stageContainer

        -- 加载敌人数据
        StageService.LoadEnemyData(newStage, stageNum)

        -- V2.0.3：生成后默认锁定空气墙
        StageService.SetAirWallState(newStage, false)

        return newStage
    end)

    if success then
        return result
    else
        warn("[StageService] 生成关卡失败:", result)
        return nil
    end
end

--[[
	加载关卡敌人数据（从EnemyConfig配置表）
	@param stageFolder Folder - 关卡文件夹
	@param stageNum number - 关卡编号
	@return table - 敌人实例列表
]]
function StageService.LoadEnemyData(stageFolder, stageNum)
	local stageName = string.format("Stage%03d", stageNum)
	local config = EnemyConfig[stageName]

	if not config then
		warn("[StageService] 关卡敌人配置未找到:", stageName)
		return {}
	end

	-- V2.0修复：使用递归搜索，支持IdleFloorEnemy在子文件夹中（如Stage001/StageNodes/IdleFloorEnemy）
	local idleFloorEnemy = stageFolder:FindFirstChild("IdleFloorEnemy", true)
	if not idleFloorEnemy then
		warn("[StageService] IdleFloorEnemy未找到（已递归搜索）:", stageName, "关卡路径:", stageFolder:GetFullName())
		return {}
	end

	local enemies = {}

	-- 清空IdleFloorEnemy下的现有内容
	for _, child in ipairs(idleFloorEnemy:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end

	-- 根据配置生成敌人
	for index, enemyData in ipairs(config) do
		local success, result = pcall(function()
			-- 查找兵种配置
			local unitInfo = UnitConfig.Units[enemyData.UnitId]
			if not unitInfo then
				warn("[StageService] 兵种配置未找到:", enemyData.UnitId)
				return nil
			end

			-- V2.3.3修复：使用ModelPath配置查找模型（与PlacementHelper保持一致）
			local modelTemplate = nil

			-- 获取模型路径,例如 "Role/Basic/Noob"
			local modelPath = unitInfo.ModelPath
			if not modelPath or modelPath == "" then
				warn(string.format("[StageService] 兵种%s没有配置ModelPath", enemyData.UnitId))
				return nil
			end

			-- 解析路径（修复：确保modelPath是字符串）
			local pathParts = string.split(tostring(modelPath), "/")

			-- 从ReplicatedStorage开始遍历路径
			local currentFolder = ReplicatedStorage
			for i = 1, #pathParts - 1 do
				local nextFolder = currentFolder:FindFirstChild(pathParts[i])
				if not nextFolder then
					warn(string.format("[StageService] 路径不存在: %s (在 %s)", pathParts[i], currentFolder:GetFullName()))
					return nil
				end
				currentFolder = nextFolder
			end

			-- 最后一个部分是模型名称
			local modelName = pathParts[#pathParts]
			modelTemplate = currentFolder:FindFirstChild(modelName)

			if not modelTemplate then
				-- 修复：确保参数都是字符串类型
				warn(string.format("[StageService] 找不到模型: %s (路径: %s)", tostring(modelName), tostring(modelPath)))
				return nil
			end

			if not modelTemplate:IsA("Model") then
				warn(string.format("[StageService] %s 不是一个Model类型", modelName))
				return nil
			end


			-- 克隆模型
			local unitModel = modelTemplate:Clone()

			-- 设置等级和属性
			unitModel:SetAttribute("Level", enemyData.Level or 1)
			unitModel:SetAttribute("UnitId", enemyData.UnitId)

			-- 计算位置
			local targetCFrame = GridPositionSystem.GridToWorld(
				idleFloorEnemy,
				enemyData.GridPos
			)

			-- 设置位置（修复：使用PivotTo替代已弃用的SetPrimaryPartCFrame）
			if unitModel.PrimaryPart then
				unitModel:PivotTo(targetCFrame)
			elseif unitModel:FindFirstChild("HumanoidRootPart") then
				unitModel.HumanoidRootPart.CFrame = targetCFrame
			end

			-- 设置名称（用于调试）
			unitModel.Name = enemyData.UnitId .. "_Lv" .. (enemyData.Level or 1) .. "_" .. index

			-- 应用等级加成
			if unitModel:FindFirstChild("Humanoid") then
				local baseHP = unitInfo.Health or 100
				local baseAttack = unitInfo.Attack or 10
				local levelMultiplier = 1 + (enemyData.Level - 1) * 0.2

				unitModel.Humanoid.MaxHealth = baseHP * levelMultiplier
				unitModel.Humanoid.Health = baseHP * levelMultiplier
			end

			-- V2.2: 使用统一的LevelDisplayHelper更新等级显示
			local level = enemyData.Level or 1
			local success = LevelDisplayHelper.UpdateLevelDisplay(unitModel, level)
			if not success then
				warn("[StageService] 更新等级显示失败，unitId=" .. tostring(enemyData.UnitId) .. ", level=" .. tostring(level))
			end

			-- V2.0修复：提前生成敌人但关闭碰撞，避免阻挡我方行军
			-- 初始状态：锚定+关闭碰撞（仅用于展示）
			-- 在StartStageBattle时会恢复碰撞并启动AI
			for _, descendant in ipairs(unitModel:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true  -- 锚定，防止掉落
					descendant.CanCollide = false  -- 关闭碰撞，不阻挡行军
				end
			end

			-- 标记为未激活状态（需要在战斗开始时激活）
			unitModel:SetAttribute("IsActivated", false)

			-- 添加到场景
			unitModel.Parent = idleFloorEnemy

			return unitModel
		end)

		if success and result then
			table.insert(enemies, result)
		else
			warn("[StageService] 生成敌人失败:", enemyData.UnitId, result)
		end
	end

	return enemies
end

--[[
    清理玩家的所有动态关卡（V2.0.1修改：清理所有关卡包括Stage001）
    @param playerId number - 玩家ID
]]
function StageService.CleanupStages(playerId)
    local success, err = pcall(function()
        local cache = StageService.StageCache[playerId]
        if not cache then
            return
        end

        -- V2.0.1修改：遍历并销毁所有关卡（包括Stage001）
        for stageNum, stageFolder in pairs(cache) do
            if stageFolder and stageFolder.Parent then
                stageFolder:Destroy()
            end
        end

        -- 完全清除该玩家的缓存
        StageService.StageCache[playerId] = nil
    end)

    if not success then
        warn("[StageService] 清理关卡失败:", err)
    end
end

--[[
    获取玩家的HomeId
    @param playerId number - 玩家ID
    @return number - HomeId (1~6)
]]
function StageService.GetPlayerHomeId(playerId)
    -- 这里需要从PlayerManager获取
    -- 临时实现：遍历查找（修复：添加类型断言）
    local ServerScriptService = game:GetService("ServerScriptService")
    local playerManagerModule = ServerScriptService:WaitForChild("Core"):FindFirstChild("PlayerManager")
    if playerManagerModule then
        local PlayerManager = require(playerManagerModule :: ModuleScript)
        return PlayerManager.GetPlayerHomeId(game.Players:GetPlayerByUserId(playerId))
    end
    return nil
end

--[[
    解锁关卡的空气墙（V2.0.3新增）
    便捷接口：获取关卡并解锁空气墙
    @param playerId number - 玩家ID
    @param stageNum number - 关卡编号
    @return boolean - 是否成功解锁
]]
function StageService.UnlockStage(playerId, stageNum)
    local stageFolder = StageService.GetOrCreateStage(playerId, stageNum)
    if not stageFolder then
        warn("[StageService] UnlockStage失败：关卡未找到，stageNum:", stageNum)
        return false
    end

    return StageService.SetAirWallState(stageFolder, true)
end

--[[
    锁定关卡的空气墙（V2.0.3新增）
    便捷接口：获取关卡并锁定空气墙
    @param playerId number - 玩家ID
    @param stageNum number - 关卡编号
    @return boolean - 是否成功锁定
]]
function StageService.LockStage(playerId, stageNum)
    local stageFolder = StageService.GetOrCreateStage(playerId, stageNum)
    if not stageFolder then
        warn("[StageService] LockStage失败：关卡未找到，stageNum:", stageNum)
        return false
    end

    return StageService.SetAirWallState(stageFolder, false)
end

-- 导出
return StageService
