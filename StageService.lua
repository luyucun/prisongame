--[[
=====================================================
脚本名称: StageService
脚本类型: ModuleScript (服务端)
脚本位置: ServerScriptService/Systems/StageService.lua
版本: V3.11
=====================================================

功能描述:
- 动态生成关卡场景
- 从EnemyConfig配置表加载敌人数据
- 关卡缓存管理
- 关卡清理
- V3.7新增: 支持根据章节ID获取不同的关卡模板风格
- V3.11新增: 敌人生成后自动播放展示动画

]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- 引用配置和系统
local EnemyConfig = require(ReplicatedStorage.Config.EnemyConfig)
local UnitConfig = require(ReplicatedStorage.Config.UnitConfig)
local StageConfig = require(ReplicatedStorage.Config.StageConfig)  -- V3.7新增
local GridPositionSystem = require(ServerScriptService.Systems.GridPositionSystem)
local CollisionSystem = require(ServerScriptService.Systems.CollisionSystem) -- V2.5: 碰撞/状态优化（用于敌人生成稳定化）
-- V2.2新增：等级显示辅助工具
local LevelDisplayHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("LevelDisplayHelper"))

local StageService = {}

-- V2.3.2新增：简单调试日志函数（默认关闭）
local DEBUG_MODE = false
local function DebugLog(msg)
	if DEBUG_MODE then
		print("[StageService] " .. tostring(msg))
	end
end

-- 副本隔离：关卡所属玩家可通过，其它玩家永远阻挡（Vx.x新增）
local STAGE_OWNER_ATTR = "OwnerUserId"
local AIR_WALL_OPEN_ATTR = "AirWallOpen"
local PLAYER_AIR_WALL_NAME = "PlayerAirWall"
local OWNER_NOCOLLIDE_PREFIX = "OwnerNoCollide_"

--[[
V3.11新增：播放展示动画（敌人生成后自动播放）
@param model Model - 兵种模型
@param unitId string - 兵种ID
说明: 参考PlacementSystem.PlayShowAnimation实现
]]
local function PlayShowAnimation(model, unitId)
	if not model or not unitId then
		return
	end

	-- 获取展示动画ID
	local showAnimId = UnitConfig.GetShowAnimationId(unitId)

	-- 如果没有配置展示动画，直接返回
	if not showAnimId or showAnimId == "" or showAnimId == "0" then
		return
	end

	-- 验证动画ID格式
	if not tonumber(showAnimId) then
		warn("[StageService] PlayShowAnimation: 动画ID格式无效:", unitId, "AnimID:", showAnimId)
		return
	end

	-- 查找Humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- 禁用默认Animate脚本，防止与展示动画冲突
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") and descendant.Name == "Animate" then
			descendant.Enabled = false
		end
	end

	-- 查找或创建Animator
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
	end

	-- 停止所有正在播放的动画
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		pcall(function()
			track:Stop(0)
		end)
	end

	-- 创建动画实例
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. showAnimId

	-- 加载动画
	local loadSuccess, animTrack = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not loadSuccess or not animTrack then
		animation:Destroy()
		return
	end

	-- 设置循环播放和优先级
	animTrack.Looped = true
	animTrack.Priority = Enum.AnimationPriority.Idle

	-- 播放动画
	local playSuccess = pcall(function()
		animTrack:Play()
	end)

	if not playSuccess then
		animation:Destroy()
		return
	end

	-- 动画停止时清理Animation对象，防止内存泄漏
	animTrack.Stopped:Connect(function()
		if animation and animation.Parent then
			animation:Destroy()
		end
	end)
end

-- 缓存: [playerId] = {[stageNum] = stageFolderRef}
StageService.StageCache = {}

-- V2.7修复：统一从GameConfig读取配置，避免硬编码
local GameConfigModule = require(ReplicatedStorage.Config.GameConfig)

-- V3.7重构：玩家当前章节缓存，用于获取正确的模板风格
-- [playerId] = chapterId
StageService.PlayerChapterCache = {}

--[[
V3.7新增：设置玩家当前章节
@param playerId number - 玩家ID
@param chapterId number - 章节ID
说明: 由CampaignManager在StartCampaign时调用
]]
function StageService.SetPlayerChapter(playerId, chapterId)
	StageService.PlayerChapterCache[playerId] = chapterId
end

--[[
V3.7新增：清除玩家章节缓存
@param playerId number - 玩家ID
说明: 在CleanupStages时调用
]]
function StageService.ClearPlayerChapter(playerId)
	StageService.PlayerChapterCache[playerId] = nil
end

--[[
V3.10新增：获取玩家当前章节ID
@param playerId number - 玩家ID
@return number|nil - 章节ID
]]
function StageService.GetPlayerChapter(playerId)
	return StageService.PlayerChapterCache[playerId]
end

--[[
获取模板风格（V3.7增强：支持根据玩家章节获取）
@param playerId number|nil - 玩家ID（可选）
@return string - 模板风格名称
说明:
- 如果提供playerId且有章节缓存，从StageConfig获取该章节的StageTemplateStyle
- 否则使用GameConfig.Campaign.StageTemplateStyle作为默认值
]]
local function GetTemplateStyle(playerId)
	-- V3.7: 优先从玩家章节缓存获取
	if playerId and StageService.PlayerChapterCache[playerId] then
		local chapterId = StageService.PlayerChapterCache[playerId]
		local chapterStyle = StageConfig.GetChapterStyle(chapterId)
		if chapterStyle then
			return chapterStyle
		end
	end

	-- 回退到GameConfig默认值
	return GameConfigModule.Campaign.StageTemplateStyle or "Style01"
end

-- V2.7新增：获取关卡Z轴间距（从GameConfig读取）
local function GetStageOffsetZ()
	return GameConfigModule.Campaign.StageGenerateOffset or 170  -- 默认170
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
	确保“玩家隔离墙”存在：始终阻挡其它玩家，但不影响寻路/兵种
	说明：
	- 原AirWall继续用于关卡推进/触发NavMesh更新
	- PlayerAirWall用于隔离其它玩家（Owner通过NoCollisionConstraint放行）
]]
local function EnsurePlayerAirWall(stageFolder, airWall)
	if not stageFolder then
		return nil
	end

	airWall = airWall or FindAirWall(stageFolder)
	if not airWall or not airWall:IsA("BasePart") then
		return nil
	end

	local existing = FindStagePart(stageFolder, PLAYER_AIR_WALL_NAME)
	if existing and existing:IsA("BasePart") then
		pcall(function()
			existing.CFrame = airWall.CFrame
		end)
		pcall(function()
			existing.Size = airWall.Size
		end)
		pcall(function()
			existing.Anchored = true
			existing.CanCollide = true
			existing.CanTouch = false
			existing.CanQuery = false
			existing.Transparency = 1
			existing.CastShadow = false
			existing.CollisionGroup = "Players" -- 只阻挡玩家，不阻挡Allies/Enemies
		end)

		local modifier = existing:FindFirstChildOfClass("PathfindingModifier")
		if not modifier then
			modifier = Instance.new("PathfindingModifier")
			modifier.Parent = existing
		end
		modifier.Label = "PlayerAirWall"
		modifier.PassThrough = true

		return existing
	end

	local newWall = airWall:Clone()
	newWall.Name = PLAYER_AIR_WALL_NAME
	pcall(function()
		newWall.Anchored = true
		newWall.CanCollide = true
		newWall.CanTouch = false
		newWall.CanQuery = false
		newWall.Transparency = 1
		newWall.CastShadow = false
		newWall.CollisionGroup = "Players" -- 只阻挡玩家，不阻挡Allies/Enemies
	end)

	-- 防止模板里意外带脚本/特效
	for _, descendant in ipairs(newWall:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") then
			descendant:Destroy()
		end
	end

	local modifier = newWall:FindFirstChildOfClass("PathfindingModifier")
	if not modifier then
		modifier = Instance.new("PathfindingModifier")
		modifier.Parent = newWall
	end
	modifier.Label = "PlayerAirWall"
	modifier.PassThrough = true

	newWall.Parent = airWall.Parent or stageFolder
	return newWall
end

local function ClearOwnerNoCollideConstraints(playerAirWall)
	if not playerAirWall then
		return
	end

	for _, child in ipairs(playerAirWall:GetChildren()) do
		if child:IsA("NoCollisionConstraint") and string.sub(child.Name, 1, #OWNER_NOCOLLIDE_PREFIX) == OWNER_NOCOLLIDE_PREFIX then
			child:Destroy()
		end
	end
end

local function ApplyOwnerNoCollideConstraints(playerAirWall, ownerPlayer)
	if not playerAirWall or not ownerPlayer then
		return false
	end

	local character = ownerPlayer.Character
	if not character then
		-- V5.5修复：如果角色不存在，尝试等待一小段时间
		-- 这在角色刚重生或正在加载时可能发生
		character = ownerPlayer.Character or ownerPlayer.CharacterAdded:Wait()
		if not character then
			warn(string.format("[StageService] ApplyOwnerNoCollideConstraints: 等待后仍无角色，玩家=%s", ownerPlayer.Name))
			return false
		end
		-- 等待角色完全加载
		task.wait(0.1)
	end

	ClearOwnerNoCollideConstraints(playerAirWall)

	local created = 0
	local prefix = OWNER_NOCOLLIDE_PREFIX .. tostring(ownerPlayer.UserId) .. "_"

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local nc = Instance.new("NoCollisionConstraint")
			nc.Name = prefix .. part.Name
			nc.Part0 = playerAirWall
			nc.Part1 = part
			nc.Parent = playerAirWall
			created = created + 1
		end
	end

	return created > 0
end

--[[
    设置空气墙状态（V2.0.3新增）
    @param stageFolder Folder - 关卡文件夹
    @param isOpen boolean - true=开启（玩家可通过，CanCollide=false），false=关闭（阻挡玩家，CanCollide=true）
    @return boolean - 是否设置成功
]]
function StageService.SetAirWallState(stageFolder, isOpen)
	local stageName = stageFolder and stageFolder.Name or "nil"

    local airWall = FindAirWall(stageFolder)

    if not airWall or not airWall:IsA("BasePart") then
        -- 空气墙缺失，返回false但不中断流程
		warn(string.format("[StageService] SetAirWallState 失败: Stage=%s 的 AirWall 未找到", stageName))
        return false
    end

	-- 记录开关状态（用于玩家重生后重新绑定隔离墙放行）
	pcall(function()
		stageFolder:SetAttribute(AIR_WALL_OPEN_ATTR, isOpen and true or false)
	end)

	-- 确保隔离墙存在：其它玩家永远阻挡
	local playerAirWall = EnsurePlayerAirWall(stageFolder, airWall)
	if playerAirWall then
		-- 默认阻挡Owner；仅当本关解封时放行Owner
		ClearOwnerNoCollideConstraints(playerAirWall)

		if isOpen then
			local ownerUserId = stageFolder:GetAttribute(STAGE_OWNER_ATTR)

			if ownerUserId then
				local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)

				if ownerPlayer then
					-- 如果此时角色未加载，CharacterAdded监听会补一次
					local success = ApplyOwnerNoCollideConstraints(playerAirWall, ownerPlayer)
				else
					warn(string.format("[StageService] PlayerAirWall失败: Stage=%s 找不到玩家(UserId=%s)", stageName, tostring(ownerUserId)))
				end
			else
				warn(string.format("[StageService] PlayerAirWall失败: Stage=%s 没有OwnerUserId属性", stageName))
			end
		end
	else
		warn(string.format("[StageService] PlayerAirWall失败: Stage=%s 无法创建PlayerAirWall", stageName))
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
	玩家重生/换角色后：重新绑定当前已解封关卡的隔离墙放行
	@param playerId number - 玩家ID
]]
function StageService.RefreshPlayerAirWallConstraintsForPlayer(playerId)
	local player = Players:GetPlayerByUserId(playerId)
	if not player or not player.Character then
		return
	end

	local cache = StageService.StageCache[playerId]
	if not cache then
		return
	end

	for _, stageFolder in pairs(cache) do
		if stageFolder and stageFolder.Parent then
			local ownerUserId = stageFolder:GetAttribute(STAGE_OWNER_ATTR)
			if ownerUserId == playerId and stageFolder:GetAttribute(AIR_WALL_OPEN_ATTR) == true then
				local airWall = FindAirWall(stageFolder)
				if airWall and airWall:IsA("BasePart") then
					local playerAirWall = EnsurePlayerAirWall(stageFolder, airWall)
					if playerAirWall then
						ApplyOwnerNoCollideConstraints(playerAirWall, player)
					end
				end
			end
		end
	end
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
                                -- V3.10: 传递章节ID
                                local chapterId = StageService.GetPlayerChapter(playerId)
                                StageService.LoadEnemyData(cached, stageNum, chapterId)
                            end
                        end

                        -- V2.0.4修复：只有显式要求时才重置空气墙状态
                        if resetAirWall then
                            StageService.SetAirWallState(cached, false)
                        end
						pcall(function()
							cached:SetAttribute(STAGE_OWNER_ATTR, playerId)
						end)
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
                        -- V3.10: 传递章节ID
                        local chapterId = StageService.GetPlayerChapter(playerId)
                        StageService.LoadEnemyData(cached, stageNum, chapterId)
                    end
                end

                -- V2.0.4修复：只有显式要求时才重置空气墙状态
                if resetAirWall then
                    StageService.SetAirWallState(cached, false)
                end
				pcall(function()
					cached:SetAttribute(STAGE_OWNER_ATTR, playerId)
				end)
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
            -- V5.7修复：检查敌人是否存在，如果被销毁则重新加载（修复Restart后关卡瞬间消失的问题）
            local idleFloorEnemy = existing:FindFirstChild("IdleFloorEnemy", true)
            if idleFloorEnemy then
                local hasEnemies = false
                for _, child in ipairs(idleFloorEnemy:GetChildren()) do
                    if child:IsA("Model") and child:FindFirstChild("Humanoid") then
                        hasEnemies = true
                        break
                    end
                end
                if not hasEnemies then
                    DebugLog("Stage001 敌人已被销毁，重新加载敌人数据")
                    local chapterId = StageService.GetPlayerChapter(playerId)
                    StageService.LoadEnemyData(existing, 1, chapterId)
                end
            end

            -- V2.0.4修复：只有显式要求时才重置空气墙状态
            if resetAirWall then
                StageService.SetAirWallState(existing, false)
            end
			pcall(function()
				existing:SetAttribute(STAGE_OWNER_ATTR, playerId)
			end)
            -- 缓存并返回
            if not StageService.StageCache[playerId] then
                StageService.StageCache[playerId] = {}
            end
            StageService.StageCache[playerId][1] = existing
            return existing
        end

        -- 2. 场景中不存在，动态生成Stage001
        local stage001 = StageService.GenerateStage001(homeId, playerId)  -- V3.7: 传递playerId
        if stage001 then
			pcall(function()
				stage001:SetAttribute(STAGE_OWNER_ATTR, playerId)
			end)
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
		pcall(function()
			stageFolder:SetAttribute(STAGE_OWNER_ATTR, playerId)
		end)
        if not StageService.StageCache[playerId] then
            StageService.StageCache[playerId] = {}
        end
        StageService.StageCache[playerId][stageNum] = stageFolder
    end

    return stageFolder
end

--[[
    生成Stage001（V2.0.1新增, V3.7增强）
    @param homeId number - 基地ID (1-6)
    @param playerId number|nil - 玩家ID（V3.7新增，用于获取章节模板风格）
    @return Folder - 生成的Stage001文件夹
]]
function StageService.GenerateStage001(homeId, playerId)
    local success, result = pcall(function()
        -- 1. V3.7: 先获取模板风格，用于读取对应的坐标
        local stageTemplateRoot = ReplicatedStorage:FindFirstChild("StageTemplate")
        if not stageTemplateRoot then
            warn("[StageService] StageTemplate文件夹不存在")
            return nil
        end

        -- V3.7: 传递playerId以获取章节对应的模板风格
        local templateStyle = GetTemplateStyle(playerId)
        local templatePath = stageTemplateRoot:FindFirstChild(templateStyle)
        if not templatePath then
            warn("[StageService] 模板风格未找到:", templateStyle)
            return nil
        end

        -- 2. V3.7扩展：根据Style风格获取对应的Stage001坐标
        local GameConfig = require(ReplicatedStorage.Config.GameConfig)
        local targetPosition = nil

        -- 优先从Style专属配置中读取
        if GameConfig.Campaign.Stage001PositionsByStyle and GameConfig.Campaign.Stage001PositionsByStyle[templateStyle] then
            targetPosition = GameConfig.Campaign.Stage001PositionsByStyle[templateStyle][homeId]
        end

        -- 如果Style专属配置不存在，回退到默认配置
        if not targetPosition then
            targetPosition = GameConfig.Campaign.Stage001Positions[homeId]
        end

        if not targetPosition then
            warn("[StageService] Stage001坐标配置未找到，homeId:", homeId, "style:", templateStyle)
            return nil
        end

        -- 3. 获取StageMiddle模板
        local template = templatePath:FindFirstChild("StageMiddle")
        if not template then
            warn("[StageService] StageMiddle模板未找到")
            return nil
        end

        -- 4. 克隆模板
        local newStage = template:Clone()

        -- 5. 找到模板中的Base
        local templateBase = FindStagePart(newStage, "Base")
        if not templateBase then
            warn("[StageService] 模板中Base未找到（已递归搜索）")
            newStage:Destroy()
            return nil
        end

        -- 6. 计算偏移量并移动整个关卡
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

        -- 7. 命名
        newStage.Name = "Stage001"
		pcall(function()
			newStage:SetAttribute(STAGE_OWNER_ATTR, playerId)
		end)

        -- 8. 放入场景
        local stageContainer = Workspace.Home:FindFirstChild("PlayerHome" .. homeId):FindFirstChild("Stage")
        if not stageContainer then
            warn("[StageService] Stage容器未找到，homeId:", homeId)
            newStage:Destroy()
            return nil
        end

        newStage.Parent = stageContainer

        -- 9. 加载敌人数据 (V3.10: 传递章节ID)
        local chapterId = StageService.GetPlayerChapter(playerId)
        StageService.LoadEnemyData(newStage, 1, chapterId)

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
    生成关卡（Stage002及以后，V3.7增强）
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

        -- V3.11 fix: decide StageEnd by the chapter's real stage count (not global MaxStages)
        local chapterId = StageService.GetPlayerChapter(playerId)
        if chapterId then
            local stagesInChapter = StageConfig.GetStagesPerChapter(chapterId)
            if stagesInChapter and stagesInChapter > 0 then
                totalStages = stagesInChapter
            end
        end

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

        -- V3.7增强：传递playerId以获取章节对应的模板风格
        local templateStyle = GetTemplateStyle(playerId)
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
		pcall(function()
			newStage:SetAttribute(STAGE_OWNER_ATTR, playerId)
		end)

        -- 放入场景
        local stageContainer = Workspace.Home:FindFirstChild("PlayerHome" .. homeId):FindFirstChild("Stage")
        if not stageContainer then
            warn("[StageService] Stage容器未找到，homeId:", homeId)
            newStage:Destroy()
            return nil
        end

        newStage.Parent = stageContainer

        -- 加载敌人数据 (V3.10: 传递章节ID)
        local chapterId = StageService.GetPlayerChapter(playerId)
        StageService.LoadEnemyData(newStage, stageNum, chapterId)

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
	@param stageNum number - 章节内关卡编号
	@param chapterId number|nil - 章节ID（V3.10新增，可选）
	@return table - 敌人实例列表
]]
function StageService.LoadEnemyData(stageFolder, stageNum, chapterId)
	local config = nil
	local stageName = string.format("Stage%03d", stageNum)  -- 提前定义，避免作用域问题

	-- V3.10: 优先使用章节化配置
	if chapterId then
		local stageConfig = StageConfig.GetChapterConfig(chapterId)
		if stageConfig and stageConfig.EnemyChapterRef then
			config = EnemyConfig.GetStageConfig(stageConfig.EnemyChapterRef, stageNum)
			if DEBUG_MODE and config then
				DebugLog(string.format("✅ 使用章节化配置: Chapter%d Stage%d", chapterId, stageNum))
			end
		end
	end

	-- V3.10: 如果章节化配置不存在，回退到旧的全局编号方式（向后兼容）
	if not config then
		config = EnemyConfig[stageName]
		if DEBUG_MODE and config then
			DebugLog(string.format("⚠️ 使用旧配置方式: %s", stageName))
		end
	end

	if not config then
		warn(string.format("[StageService] 关卡敌人配置未找到: Chapter%s Stage%d", tostring(chapterId or "?"), stageNum))
		return {}
	end

	-- V2.0修复：使用递归搜索，支持IdleFloorEnemy在子文件夹中（如Stage001/StageNodes/IdleFloorEnemy）
	local idleFloorEnemy = stageFolder:FindFirstChild("IdleFloorEnemy", true)
	if not idleFloorEnemy then
		warn(string.format("[StageService] IdleFloorEnemy未找到（已递归搜索）: %s 关卡路径: %s", stageName, stageFolder:GetFullName()))
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

			-- 添加到场景
			unitModel.Parent = idleFloorEnemy

			-- V3.10修复：敌人生成时不再让模型自由掉落（会触发Humanoid摔倒/起身）
			-- 直接对齐IdleFloorEnemy顶面，并进入展示态（锚定根部件+关闭碰撞，避免阻挡我方行军）
			do
				local floorTopY = idleFloorEnemy.Position.Y + idleFloorEnemy.Size.Y / 2
				local padding = 0.05

				-- 排除武器/饰品，避免包围盒被武器尖端拉低导致角色浮空
				local bodyParts = {}
				local excludeNames = {"Handle", "Sword", "Spear", "Weapon", "Gun", "Bow", "Staff", "Axe", "Knife", "Shield"}

				for _, part in ipairs(unitModel:GetDescendants()) do
					if part:IsA("BasePart") then
						-- 排除工具和饰品
						local parent = part.Parent
						local isAccessoryOrTool = false

						while parent and parent ~= unitModel do
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

				-- 计算身体部件的最低点（脚底），并对齐到地板顶面
				local lowestY = math.huge
				if #bodyParts > 0 then
					for _, part in ipairs(bodyParts) do
						local partBottomY = part.Position.Y - part.Size.Y / 2
						if partBottomY < lowestY then
							lowestY = partBottomY
						end
					end
				else
					-- 回退：无有效部件时使用整体包围盒
					local bboxCf, bboxSize = unitModel:GetBoundingBox()
					lowestY = bboxCf.Position.Y - bboxSize.Y / 2
				end

				local deltaY = (floorTopY + padding) - lowestY
				unitModel:PivotTo(unitModel:GetPivot() * CFrame.new(0, deltaY, 0))
			end

			-- 展示态：只锚定根部件，其他部件不锚定但关闭碰撞（允许动画播放且不阻挡行军）
			local rootPart = unitModel:FindFirstChild("HumanoidRootPart") or unitModel.PrimaryPart
			if rootPart then
				rootPart.Anchored = true
				rootPart.CanCollide = false
			end

			for _, descendant in ipairs(unitModel:GetDescendants()) do
				if descendant:IsA("BasePart") then
					if descendant ~= rootPart then
						descendant.Anchored = false
						descendant.CanCollide = false
					end
				end
			end

			-- V2.5/V3.x：对敌人也应用Humanoid优化，避免开战瞬间"摔倒→起身"
			local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				-- V3.11新增：确保Humanoid的AutoRotate启用，防止行军时掉头bug
				humanoid.AutoRotate = true
				pcall(function()
					CollisionSystem.OptimizeHumanoid(humanoid)
				end)
			end

			-- 设置碰撞组/无质量（与放置单位一致）
			pcall(function()
				CollisionSystem.SetUnitCollision(unitModel)
			end)

			-- 标记为未激活状态（需要在战斗开始时激活）
			unitModel:SetAttribute("IsActivated", false)

			-- V3.11新增：播放展示动画，让敌人生成后不再傻站着
			PlayShowAnimation(unitModel, enemyData.UnitId)

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
    清理玩家的所有动态关卡（V2.0.1修改：清理所有关卡包括Stage001, V3.7增强：清除章节缓存）
    @param playerId number - 玩家ID
]]
function StageService.CleanupStages(playerId)
    local success, err = pcall(function()
        local cache = StageService.StageCache[playerId]
        if not cache then
            -- V3.7: 即使没有关卡缓存，也要清除章节缓存
            StageService.ClearPlayerChapter(playerId)
            return
        end

        -- V2.0.1修改：遍历并销毁所有关卡（包括Stage001）
        for stageNum, stageFolder in pairs(cache) do
            if stageFolder and stageFolder.Parent then
                -- 保险：如果关卡已被复用给其它玩家（OwnerUserId变化），不要误删
                local ownerUserId = stageFolder:GetAttribute(STAGE_OWNER_ATTR)
                if not ownerUserId or ownerUserId == playerId then
                    stageFolder:Destroy()
                end
            end
        end

        -- 完全清除该玩家的缓存
        StageService.StageCache[playerId] = nil

        -- V3.7新增：清除玩家章节缓存
        StageService.ClearPlayerChapter(playerId)
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

-- ==================== 玩家重生：隔离墙放行补丁 ====================

local function SetupPlayerAirWallRefresh(player)
	local function RefreshLater()
		task.defer(function()
			-- 等角色部件加载完成一点点，避免漏绑定
			task.wait(0.2)
			StageService.RefreshPlayerAirWallConstraintsForPlayer(player.UserId)
		end)
	end

	player.CharacterAdded:Connect(function()
		RefreshLater()
	end)

	if player.Character then
		RefreshLater()
	end
end

Players.PlayerAdded:Connect(SetupPlayerAirWallRefresh)
for _, player in ipairs(Players:GetPlayers()) do
	SetupPlayerAirWallRefresh(player)
end

-- 导出
return StageService
