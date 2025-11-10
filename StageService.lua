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

local StageService = {}

-- 缓存: [playerId] = {[stageNum] = stageFolderRef}
StageService.StageCache = {}

-- 配置
local STAGE_OFFSET_Z = 169  -- 关卡Z轴间距
local TEMPLATE_STYLE = "Style01"  -- 默认模板风格

--[[
    获取或创建关卡
    @param playerId number - 玩家ID
    @param stageNum number - 关卡编号
    @return Folder - 关卡文件夹引用
]]
function StageService.GetOrCreateStage(playerId, stageNum)
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
                        return cached
                    end
                end
            else
                return cached
            end
        end
    end

    -- Stage001固定存在，不需要生成
    if stageNum == 1 then
        local homeId = StageService.GetPlayerHomeId(playerId)
        if homeId then
            local stage001 = Workspace.Home:FindFirstChild("PlayerHome" .. homeId):FindFirstChild("Stage"):FindFirstChild("Stage001")
            if stage001 then
                -- 初始化缓存
                if not StageService.StageCache[playerId] then
                    StageService.StageCache[playerId] = {}
                end
                StageService.StageCache[playerId][1] = stage001
                return stage001
            end
        end
        warn("[StageService] Stage001未找到，playerId:", playerId)
        return nil
    end

    -- 生成新关卡
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
    生成关卡
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
        local templatePath = ReplicatedStorage.StageTemplate:FindFirstChild(TEMPLATE_STYLE)
        if not templatePath then
            warn("[StageService] 模板风格未找到:", TEMPLATE_STYLE)
            return nil
        end

        local template = templatePath:FindFirstChild(templateName)
        if not template then
            warn("[StageService] 模板未找到:", templateName)
            return nil
        end

        -- 获取前一关的位置
        local previousStage = StageService.GetOrCreateStage(playerId, stageNum - 1)
        if not previousStage then
            warn("[StageService] 前一关未找到，stageNum:", stageNum - 1)
            return nil
        end

        local previousBase = previousStage:FindFirstChild("Base")
        if not previousBase then
            warn("[StageService] 前一关Base未找到")
            return nil
        end

        -- 计算新关卡位置（Z轴偏移）
        local newBaseCFrame = previousBase.CFrame * CFrame.new(0, 0, STAGE_OFFSET_Z)

        -- 克隆模板
        local newStage = template:Clone()
        local newBase = newStage:FindFirstChild("Base")

        if not newBase then
            warn("[StageService] 模板中Base未找到")
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

        print("[StageService] 关卡生成成功:", newStage.Name, "位置:", newBaseCFrame.Position)

        -- 加载敌人数据
        StageService.LoadEnemyData(newStage, stageNum)

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

	local idleFloorEnemy = stageFolder:FindFirstChild("IdleFloorEnemy")
	if not idleFloorEnemy then
		warn("[StageService] IdleFloorEnemy未找到:", stageName)
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

			-- 从ReplicatedStorage查找模型（支持递归搜索）
			local function SearchFolderRecursive(folder, targetName)
				local found = folder:FindFirstChild(targetName)
				if found and found:IsA("Model") then
					return found
				end

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

			local roleFolder = ReplicatedStorage:FindFirstChild("Role")
			if not roleFolder then
				warn("[StageService] Role文件夹未找到")
				return nil
			end

			local modelTemplate = SearchFolderRecursive(roleFolder, enemyData.UnitId)
			if not modelTemplate then
				warn("[StageService] 兵种模型未找到:", enemyData.UnitId)
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

			-- 设置位置
			if unitModel.PrimaryPart then
				unitModel:SetPrimaryPartCFrame(targetCFrame)
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

			-- 更新等级显示
			local head = unitModel:FindFirstChild("Head")
			if head then
				local billboardGui = head:FindFirstChild("BillboardGui")
				if billboardGui then
					local textLabel = billboardGui:FindFirstChild("TextLabel")
					if textLabel then
						local level = enemyData.Level or 1
						textLabel.Text = (level >= 3) and "Lv.Max" or ("Lv." .. level)
					end
				end
			end

			-- V2.0修复：敌人在战斗时不需要锚定，否则无法移动
			-- 初始状态下全部解除锚定，允许敌人移动和播放动画
			for _, descendant in ipairs(unitModel:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = false
					-- 只有HumanoidRootPart有碰撞
					if descendant.Name == "HumanoidRootPart" then
						descendant.CanCollide = true
					else
						descendant.CanCollide = false
					end
				end
			end

			-- 添加到场景
			unitModel.Parent = idleFloorEnemy

			print("[StageService] 生成敌人:", unitModel.Name, "位置:", enemyData.GridPos.X, enemyData.GridPos.Y)

			return unitModel
		end)

		if success and result then
			table.insert(enemies, result)
		else
			warn("[StageService] 生成敌人失败:", enemyData.UnitId, result)
		end
	end

	print("[StageService] 敌人加载完成，总数:", #enemies)
	return enemies
end

--[[
    清理玩家的所有动态关卡（保留Stage001）
    @param playerId number - 玩家ID
]]
function StageService.CleanupStages(playerId)
    local success, err = pcall(function()
        local cache = StageService.StageCache[playerId]
        if not cache then
            return
        end

        print("[StageService] 开始清理关卡，playerId:", playerId)

        -- 遍历并销毁Stage002及以后的关卡
        for stageNum, stageFolder in pairs(cache) do
            if stageNum > 1 and stageFolder and stageFolder.Parent then
                print("[StageService] 清理关卡:", stageFolder.Name)
                stageFolder:Destroy()
            end
        end

        -- 完全清除该玩家的缓存（包括Stage001）
        StageService.StageCache[playerId] = nil

        print("[StageService] 关卡清理完成")
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
    -- 临时实现：遍历查找
    local PlayerManager = require(game.ServerScriptService.Core.PlayerManager)
    return PlayerManager.GetPlayerHomeId(game.Players:GetPlayerByUserId(playerId))
end

-- 导出
return StageService
