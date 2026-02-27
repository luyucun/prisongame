--[[
脚本名称: HomeSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/HomeSystem
]]

--[[
基地系统模块
职责:
1. 管理玩家基地的初始化
2. 为后续兵种放置功能预留接口
3. 基地内容管理(后续版本扩展)
4. V2.8.2新增：基地初始化时立即替换正确等级的房屋
]]

local HomeSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local DataManager = require(ServerScriptService.Core.DataManager)
local DoorControlService = require(ServerScriptService.Systems.DoorControlService)  -- V2.0.1新增

-- V2.8.2新增：延迟加载HouseConfig和HouseUpgradeSystem避免循环依赖
local HouseConfig
local HouseUpgradeSystem
type HouseModelNameSet = {[string]: boolean}

-- 家园归属标记属性名（写在PlayerHome上）
local HOME_OWNER_ATTR = "HomeOwnerUserId"

local function EnsureHouseModulesLoaded()
	if not HouseConfig then
		HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))
	end
	if not HouseUpgradeSystem then
		local houseModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("HouseUpgradeSystem")
		if houseModule then
			HouseUpgradeSystem = require(houseModule)
		end
	end
end

local function GetHouseRank(modelName)
	EnsureHouseModulesLoaded()
	if not HouseConfig or not HouseConfig.GetHouseRank then
		return 0
	end
	return math.max(0, tonumber(HouseConfig.GetHouseRank(modelName)) or 0)
end

local function PickHigherRankModel(baseModel, candidateModel)
	if type(candidateModel) ~= "string" or candidateModel == "" then
		return baseModel
	end
	if type(baseModel) ~= "string" or baseModel == "" then
		return candidateModel
	end
	if GetHouseRank(candidateModel) > GetHouseRank(baseModel) then
		return candidateModel
	end
	return baseModel
end

-- 存储每个玩家的基地信息 [UserId] = HomeData
local playerHomes = {}

-- Cache house placement relative to SpawnLocation for fallback alignment.
local houseBottomOffsetByHome = {}
local houseYRotationByHome = {}
local defaultHouseBottomOffset = nil
local defaultHouseYRotation = nil
local GetCachedHousePlacement
local cachedValidHouseModelNames: HouseModelNameSet? = nil

--[[
基地数据结构:
HomeData = {
    Player = Player,              -- 玩家对象
    HomeSlot = number,            -- 基地编号
    HomeFolder = Instance,        -- 基地文件夹引用
    SpawnLocation = Instance,     -- 出生点引用
    Units = {},                   -- 放置的兵种列表(后续版本)
}
]]

-- ==================== 私有函数 ====================

-- Information面板的默认文本缓存（来自Studio初始值）
local informationDefaultTexts = nil -- { [SurfaceGuiName] = { NameText = string, PowerText = string } }

local function GetValidHouseModelNameSet(): HouseModelNameSet?
	if cachedValidHouseModelNames then
		return cachedValidHouseModelNames
	end

	EnsureHouseModulesLoaded()
	if not HouseConfig or not HouseConfig.GetAllHouses then
		return nil
	end

	local set: HouseModelNameSet = {}
	for _, house in ipairs(HouseConfig.GetAllHouses()) do
		if house and house.ModelName then
			set[house.ModelName] = true
		end
	end

	cachedValidHouseModelNames = set
	return set
end

local function GetPlacementAttributes(homeFolder)
	if not homeFolder then
		return nil, nil
	end

	local offset = homeFolder:GetAttribute("HouseBottomOffset")
	if typeof(offset) ~= "Vector3" then
		offset = nil
	end

	local yRotation = homeFolder:GetAttribute("HouseYRotation")
	if type(yRotation) ~= "number" then
		yRotation = nil
	end

	return offset, yRotation
end

local function HasCachedHousePlacement(homeId, homeFolder)
	if houseBottomOffsetByHome[homeId] ~= nil or houseYRotationByHome[homeId] ~= nil then
		return true
	end

	local offset, yRotation = GetPlacementAttributes(homeFolder)
	return offset ~= nil or yRotation ~= nil
end

local function GetHouseBottomCenter(houseModel)
	if not houseModel then
		return nil
	end

	local bboxCF, bboxSize = houseModel:GetBoundingBox()
	return Vector3.new(
		bboxCF.Position.X,
		bboxCF.Position.Y - bboxSize.Y / 2,
		bboxCF.Position.Z
	)
end

local function PivotHouseModelToBottomCenter(houseModel, bottomCenter, yRotation)
	if not houseModel or not bottomCenter then
		return false
	end

	local bboxCF, bboxSize = houseModel:GetBoundingBox()
	local pivot = houseModel:GetPivot()
	local bboxBottomY = bboxCF.Position.Y - bboxSize.Y / 2
	local pivotY = pivot.Position.Y
	local pivotToBottomY = pivotY - bboxBottomY
	local pivotToCenterX = pivot.Position.X - bboxCF.Position.X
	local pivotToCenterZ = pivot.Position.Z - bboxCF.Position.Z

	local targetPivotX = bottomCenter.X + pivotToCenterX
	local targetPivotY = bottomCenter.Y + pivotToBottomY
	local targetPivotZ = bottomCenter.Z + pivotToCenterZ

	local targetCFrame = CFrame.new(targetPivotX, targetPivotY, targetPivotZ) * CFrame.Angles(0, yRotation or 0, 0)
	houseModel:PivotTo(targetCFrame)
	return true
end

local function AlignHouseModelToExisting(currentHouseModel, newHouseModel)
	if not currentHouseModel or not newHouseModel then
		return false
	end

	local bottomCenter = GetHouseBottomCenter(currentHouseModel)
	if not bottomCenter then
		return false
	end

	local _, currentYRotation, _ = currentHouseModel:GetPivot():ToEulerAnglesYXZ()
	return PivotHouseModelToBottomCenter(newHouseModel, bottomCenter, currentYRotation)
end

local function AlignHouseModelToCachedPlacement(homeId, homeFolder, spawnLocation, houseModel)
	if not spawnLocation or not spawnLocation:IsA("BasePart") then
		return false
	end

	if not HasCachedHousePlacement(homeId, homeFolder) then
		return false
	end

	local offset, yRotation = GetCachedHousePlacement(homeId, homeFolder)
	if not offset then
		return false
	end

	local bottomCenter = spawnLocation.Position + offset
	return PivotHouseModelToBottomCenter(houseModel, bottomCenter, yRotation)
end

local function IsHouseModelMisaligned(homeId, homeFolder, spawnLocation, houseModel)
	if not spawnLocation or not spawnLocation:IsA("BasePart") then
		return false
	end

	if not HasCachedHousePlacement(homeId, homeFolder) then
		return false
	end

	local offset, yRotation = GetCachedHousePlacement(homeId, homeFolder)
	if not offset then
		return false
	end

	local expectedBottomCenter = spawnLocation.Position + offset
	local actualBottomCenter = GetHouseBottomCenter(houseModel)
	if not actualBottomCenter then
		return false
	end

	local distance = (actualBottomCenter - expectedBottomCenter).Magnitude
	if distance > 0.5 then
		return true
	end

	if yRotation ~= nil then
		local _, currentYRotation, _ = houseModel:GetPivot():ToEulerAnglesYXZ()
		local rotationDiff = math.abs(math.atan2(math.sin(currentYRotation - yRotation), math.cos(currentYRotation - yRotation)))
		if rotationDiff > math.rad(1) then
			return true
		end
	end

	return false
end

local function CleanupExtraHouseModels(houseFolder, keepModel, validModelNames)
	if not houseFolder or not validModelNames then
		return
	end

	for _, child in ipairs(houseFolder:GetChildren()) do
		if child:IsA("Model") and child ~= keepModel and validModelNames[child.Name] then
			child:Destroy()
		end
	end
end

local function CacheInformationDefaultTexts(informationModel)
    if informationDefaultTexts then
        return
    end

    informationDefaultTexts = {}

    local part = informationModel and informationModel:FindFirstChild("Part")
    if not part then
        return
    end

    for _, guiName in ipairs({"SurfaceGui01", "SurfaceGui02"}) do
        local defaults = { NameText = "", PowerText = "0" }

        local surfaceGui = part:FindFirstChild(guiName)
        if surfaceGui then
            local frame = surfaceGui:FindFirstChild("Frame")
            if frame then
                local playerNameContainer = frame:FindFirstChild("PlayerName")
                local nameLabel = playerNameContainer and playerNameContainer:FindFirstChild("Name")
                if nameLabel and nameLabel:IsA("TextLabel") then
                    defaults.NameText = nameLabel.Text
                end

                local playerPowerContainer = frame:FindFirstChild("PlayerPower")
                local numLabel = playerPowerContainer and playerPowerContainer:FindFirstChild("Num")
                if numLabel and numLabel:IsA("TextLabel") then
                    defaults.PowerText = numLabel.Text
                end
            end
        end

        informationDefaultTexts[guiName] = defaults
    end
end

--[[
获取基地文件夹
@param homeSlot number - 基地编号
@return Instance|nil - 基地文件夹
]]
local function GetHomeFolder(homeSlot)
    local homeFolder = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME)
    if not homeFolder then
        warn(GameConfig.LOG_PREFIX, "HomeSystem: 找不到Home文件夹!")
        return nil
    end

    local playerHomeName = GameConfig.HOME_PREFIX .. homeSlot
    local playerHome = homeFolder:FindFirstChild(playerHomeName)
    if not playerHome then
        warn(GameConfig.LOG_PREFIX, "HomeSystem: 找不到基地:", playerHomeName)
        return nil
    end

    return playerHome
end

local function IsHomeOwnedByPlayer(homeFolder, player)
	if not homeFolder or not player then
		return false
	end

	local ownerId = homeFolder:GetAttribute(HOME_OWNER_ATTR)
	if ownerId == nil then
		return true
	end

	return ownerId == player.UserId
end

-- 重置家园信息面板显示（玩家名/战斗力）
local function ResetInformationDisplay(homeFolder)
    local information = homeFolder and homeFolder:FindFirstChild("Information")
    if not information then
        return
    end

    local part = information:FindFirstChild("Part")
    if not part then
        return
    end

    -- 先缓存默认文本（来自Studio初始值），用于玩家离线后恢复“默认显示”
    CacheInformationDefaultTexts(information)

    for _, guiName in ipairs({"SurfaceGui01", "SurfaceGui02"}) do
        local surfaceGui = part:FindFirstChild(guiName)
        if surfaceGui then
            local frame = surfaceGui:FindFirstChild("Frame")
            if frame then
                local playerNameContainer = frame:FindFirstChild("PlayerName")
                local nameLabel = playerNameContainer and playerNameContainer:FindFirstChild("Name")
                if nameLabel and nameLabel:IsA("TextLabel") then
                    local defaults = informationDefaultTexts and informationDefaultTexts[guiName]
                    nameLabel.Text = (defaults and defaults.NameText) or ""
                end

                local playerPowerContainer = frame:FindFirstChild("PlayerPower")
                local numLabel = playerPowerContainer and playerPowerContainer:FindFirstChild("Num")
                if numLabel and numLabel:IsA("TextLabel") then
                    local defaults = informationDefaultTexts and informationDefaultTexts[guiName]
                    numLabel.Text = (defaults and defaults.PowerText) or "0"
                end
            end
        end
    end
end

-- 重置Mail上的待领取金币显示
local function ResetMailDisplay(homeFolder)
    local mailModel = homeFolder and homeFolder:FindFirstChild("Mail")
    if not mailModel then
        return
    end

    local idleEarnings = mailModel:FindFirstChild("IdleEarnings")
    local fightingGui = idleEarnings and idleEarnings:FindFirstChild("Fighting")
    local bg = fightingGui and fightingGui:FindFirstChild("Bg")
    local numberLabel = bg and bg:FindFirstChild("Number")

    if numberLabel and numberLabel:IsA("TextLabel") then
        numberLabel.Text = "0"
    end
end

local function FindHouseModelInFolder(
	houseFolder: Instance?,
	preferredModelName: string?,
	validModelNames: HouseModelNameSet?
): Model?
	if not houseFolder then
		return nil
	end

	local firstModel: Model? = nil
	local firstValidModel: Model? = nil

	for _, child in ipairs(houseFolder:GetChildren()) do
		if child:IsA("Model") then
			firstModel = firstModel or child

			if preferredModelName and child.Name == preferredModelName then
				return child
			end

			if validModelNames and validModelNames[child.Name] then
				firstValidModel = firstValidModel or child
			end
		end
	end

	if validModelNames then
		return firstValidModel
	end

	return firstModel
end

local function CacheHousePlacement(homeId, spawnLocation, houseModel, options)
	if not homeId or not spawnLocation or not houseModel then
		return false
	end

	if not spawnLocation:IsA("BasePart") then
		return false
	end

	options = options or {}
	local allowOverwrite = options.force == true
	local shouldWriteOffset = allowOverwrite or houseBottomOffsetByHome[homeId] == nil
	local shouldWriteRotation = allowOverwrite or houseYRotationByHome[homeId] == nil

	if not shouldWriteOffset and not shouldWriteRotation then
		return false
	end

	local bottomCenter = GetHouseBottomCenter(houseModel)
	if not bottomCenter then
		return
	end

	local pivot = houseModel:GetPivot()
	local _, yRotation, _ = pivot:ToEulerAnglesYXZ()

	local offset = bottomCenter - spawnLocation.Position

	if shouldWriteOffset then
		houseBottomOffsetByHome[homeId] = offset
		if defaultHouseBottomOffset == nil then
			defaultHouseBottomOffset = offset
		end
	end

	if shouldWriteRotation then
		houseYRotationByHome[homeId] = yRotation
		if defaultHouseYRotation == nil then
			defaultHouseYRotation = yRotation
		end
	end

	local homeFolder = options.homeFolder
	if not homeFolder then
		local houseFolder = houseModel.Parent
		if houseFolder then
			homeFolder = houseFolder.Parent
		end
	end

	if homeFolder then
		if shouldWriteOffset then
			homeFolder:SetAttribute("HouseBottomOffset", offset)
		end
		if shouldWriteRotation then
			homeFolder:SetAttribute("HouseYRotation", yRotation)
		end
	end

	return true
end

GetCachedHousePlacement = function(homeId, homeFolder)
	local offset = houseBottomOffsetByHome[homeId]
	local yRotation = houseYRotationByHome[homeId]

	if (offset == nil or yRotation == nil) and homeFolder then
		local attrOffset, attrRotation = GetPlacementAttributes(homeFolder)
		if offset == nil and attrOffset then
			offset = attrOffset
		end
		if yRotation == nil and attrRotation ~= nil then
			yRotation = attrRotation
		end
	end

	offset = offset or defaultHouseBottomOffset
	if yRotation == nil then
		yRotation = defaultHouseYRotation or 0
	end
	return offset, yRotation
end

-- 重置房屋到默认模型（不改玩家存档，仅清理场景）
local function ResetHouseModelToDefault(homeFolder, homeId, spawnLocation)
	if not homeFolder then
		return
	end

	EnsureHouseModulesLoaded()
	if not HouseConfig then
		return
	end

	local defaultModelName = (HouseConfig.GetHouseModelByRebirthCount and HouseConfig.GetHouseModelByRebirthCount(0))
		or HouseConfig.GetHouseModelByChapter(0)
	if not defaultModelName or defaultModelName == "" then
		return
	end

	local houseFolder = homeFolder:FindFirstChild("House")
	if not houseFolder then
		return
	end

	local validHouseModelNames = GetValidHouseModelNameSet()
	local currentHouseModel = FindHouseModelInFolder(houseFolder, defaultModelName, validHouseModelNames)

	if currentHouseModel and currentHouseModel.Name == defaultModelName then
		if spawnLocation and spawnLocation:IsA("BasePart") then
			if HasCachedHousePlacement(homeId, homeFolder) and IsHouseModelMisaligned(homeId, homeFolder, spawnLocation, currentHouseModel) then
				AlignHouseModelToCachedPlacement(homeId, homeFolder, spawnLocation, currentHouseModel)
			end
			CacheHousePlacement(homeId, spawnLocation, currentHouseModel, {homeFolder = homeFolder})
		end
		CleanupExtraHouseModels(houseFolder, currentHouseModel, validHouseModelNames)
		return
	end

	local templateFolder = ReplicatedStorage:FindFirstChild("House")
	if not templateFolder then
		warn(GameConfig.LOG_PREFIX, "HomeSystem.ResetHouseModelToDefault: ReplicatedStorage/House不存在")
		return
	end

	local template = templateFolder:FindFirstChild(defaultModelName)
	if not template or not template:IsA("Model") then
		warn(GameConfig.LOG_PREFIX, "HomeSystem.ResetHouseModelToDefault: 找不到模板", defaultModelName)
		return
	end

	local newHouseModel = template:Clone()
	newHouseModel.Name = defaultModelName

	local alignedToCache = false
	if spawnLocation and spawnLocation:IsA("BasePart") then
		alignedToCache = AlignHouseModelToCachedPlacement(homeId, homeFolder, spawnLocation, newHouseModel)
	end

	if not alignedToCache then
		if currentHouseModel then
			AlignHouseModelToExisting(currentHouseModel, newHouseModel)
		else
			local anchor = spawnLocation
			if not anchor then
				anchor = homeFolder:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
			end
			if not anchor or not anchor:IsA("BasePart") then
				anchor = homeFolder:FindFirstChild(GameConfig.IDLE_FLOOR_NAME)
			end

			if anchor and anchor:IsA("BasePart") then
				local offset, yRotation = GetCachedHousePlacement(homeId, homeFolder)
				local bottomCenter = anchor.Position + (offset or Vector3.new(0, 0, 0))
				PivotHouseModelToBottomCenter(newHouseModel, bottomCenter, yRotation)
			end
		end
	end

	newHouseModel.Parent = houseFolder
	if currentHouseModel then
		currentHouseModel:Destroy()
	end
	CleanupExtraHouseModels(houseFolder, newHouseModel, validHouseModelNames)

	if spawnLocation and spawnLocation:IsA("BasePart") then
		CacheHousePlacement(homeId, spawnLocation, newHouseModel, {homeFolder = homeFolder})
	end
end

-- 兜底：清掉所有标记了HomeSlot的单位模型（避免玩家离线后残留）
local function DestroyUnitModelsByHomeSlot(homeId)
    if not homeId then
        return
    end

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Model") then
            local slot = inst:GetAttribute("HomeSlot")
            if slot == homeId then
                -- 只清理单位模型，避免误删家园里的其它Model
                local unitId = inst:GetAttribute("UnitId")
                if unitId ~= nil and inst:FindFirstChildOfClass("Humanoid") then
                    inst:Destroy()
                end
            end
        end
    end
end

-- ==================== 公共接口 ====================

--[[
初始化玩家基地 (V2.8.2修改：立即替换正确等级的房屋，无延迟)
@param homeId number - 基地编号 (1~6)
@param player Player - 玩家对象
@return boolean - 是否初始化成功
]]
function HomeSystem.InitializePlayerHome(homeId, player)
    if not homeId or not player then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 参数无效")
        return false
    end

    -- 验证基地编号范围
    if homeId < GameConfig.MIN_HOME_SLOT or homeId > GameConfig.MAX_HOME_SLOT then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 基地编号超出范围", homeId)
        return false
    end

    -- 获取基地文件夹
    local homeFolder = GetHomeFolder(homeId)
    if not homeFolder then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 获取基地文件夹失败", homeId)
        return false
    end

    if not IsHomeOwnedByPlayer(homeFolder, player) then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 基地归属不匹配，跳过初始化", homeId)
        return false
    end

    -- 获取出生点
    local spawnLocation = homeFolder:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
    if not spawnLocation then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 找不到出生点", homeId)
        return false
    end

    -- 验证出生点的有效性
    if not spawnLocation:IsA("BasePart") then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: SpawnLocation不是有效的BasePart", homeId)
        return false
    end

	-- V2.8.2新增：立即替换正确等级的房屋（无延迟）
	EnsureHouseModulesLoaded()
	if HouseConfig and HouseUpgradeSystem then
        local rebirthCount = 0
        if DataManager.GetRebirthCount then
            rebirthCount = DataManager.GetRebirthCount(player) or 0
        end

        local targetModelName = nil
        if HouseConfig.GetHouseModelByRebirthCount then
            targetModelName = HouseConfig.GetHouseModelByRebirthCount(rebirthCount)
		else
			local completedChapters = DataManager.GetCompletedChapters(player)
			targetModelName = HouseConfig.GetHouseModelByChapter(completedChapters)
		end

		-- V7.0兼容：历史玩家若已有更高监狱，不应被重生维度降级
		local savedModelName = DataManager.GetCurrentHouseModel(player)
		targetModelName = PickHigherRankModel(targetModelName, savedModelName)
		if type(targetModelName) ~= "string" or targetModelName == "" then
			targetModelName = (HouseConfig.GetHouseModelByRebirthCount and HouseConfig.GetHouseModelByRebirthCount(0))
				or HouseConfig.GetHouseModelByChapter(0)
				or "PrisonLv1"
		end

		-- 获取场景中当前的房屋模型
		local houseFolder = homeFolder:FindFirstChild("House")
        local validHouseModelNames: HouseModelNameSet? = GetValidHouseModelNameSet()
        local currentHouseModel: Model? = FindHouseModelInFolder(houseFolder, targetModelName, validHouseModelNames)
        if not currentHouseModel then
            ResetHouseModelToDefault(homeFolder, homeId, spawnLocation)
            currentHouseModel = FindHouseModelInFolder(houseFolder, targetModelName, validHouseModelNames)
            if not currentHouseModel then
                warn(GameConfig.LOG_PREFIX, "HomeSystem.InitializePlayerHome: 房屋模型缺失，重置失败", homeId)
                return false
            end
        end

        if spawnLocation and spawnLocation:IsA("BasePart") then
            if HasCachedHousePlacement(homeId, homeFolder) and IsHouseModelMisaligned(homeId, homeFolder, spawnLocation, currentHouseModel) then
                AlignHouseModelToCachedPlacement(homeId, homeFolder, spawnLocation, currentHouseModel)
            end
            CacheHousePlacement(homeId, spawnLocation, currentHouseModel, {homeFolder = homeFolder})
        end
		CleanupExtraHouseModels(houseFolder, currentHouseModel, validHouseModelNames)

		-- 再次收窄类型，避免 Script Analysis 将 currentHouseModel 视为可空。
		if not currentHouseModel then
			return false
		end
		local ensuredCurrentHouseModel: Model = currentHouseModel
		local currentModelName = tostring(ensuredCurrentHouseModel.Name)
		targetModelName = PickHigherRankModel(targetModelName, currentModelName)

		-- 如果当前房屋不是目标房屋，立即替换
		if currentModelName ~= targetModelName then
			print(string.format(
				"%s [HomeSystem] V2.8.2 立即替换房屋: %s -> %s (玩家: %s, 重生次数: %d)",
				GameConfig.LOG_PREFIX,
				tostring(currentModelName),
				targetModelName,
                player.Name,
                rebirthCount
            ))

            -- 立即执行替换，不使用延迟
            local success = HouseUpgradeSystem.ReplaceHouseModel(player, targetModelName)
            if success then
                local refreshedHouseModel = FindHouseModelInFolder(houseFolder, targetModelName, validHouseModelNames)
                if refreshedHouseModel then
                    if spawnLocation and spawnLocation:IsA("BasePart") then
                        if HasCachedHousePlacement(homeId, homeFolder) and IsHouseModelMisaligned(homeId, homeFolder, spawnLocation, refreshedHouseModel) then
                            AlignHouseModelToCachedPlacement(homeId, homeFolder, spawnLocation, refreshedHouseModel)
                        end
                        CacheHousePlacement(homeId, spawnLocation, refreshedHouseModel, {homeFolder = homeFolder})
                    end
                    CleanupExtraHouseModels(houseFolder, refreshedHouseModel, validHouseModelNames)
                end
                print(string.format(
                    "%s [HomeSystem] V2.8.2 房屋替换成功: %s",
                    GameConfig.LOG_PREFIX,
                    targetModelName
                ))
            else
                warn(string.format(
                    "%s [HomeSystem] V2.8.2 房屋替换失败: %s",
                    GameConfig.LOG_PREFIX,
                    targetModelName
                ))
            end
        else
            if GameConfig.DEBUG_MODE then
                print(string.format(
                    "%s [HomeSystem] V2.8.2 房屋已是正确等级: %s",
                    GameConfig.LOG_PREFIX,
                    tostring(currentModelName)
                ))
            end
		end

		-- 更新存档中的房屋模型名称
		local latestSavedModelName = DataManager.GetCurrentHouseModel(player)
		if latestSavedModelName ~= targetModelName then
			DataManager.SetCurrentHouseModel(player, targetModelName)
		end
	end

    -- 创建基地数据
    local homeData = {
        Player = player,
        HomeSlot = homeId,
        HomeFolder = homeFolder,
        SpawnLocation = spawnLocation,
        Units = {},  -- 后续版本用于存储兵种
    }

    playerHomes[player.UserId] = homeData

    -- V2.0.1新增：初始化基地门状态（确保门关闭）
    pcall(function()
        DoorControlService.SetDoorState(homeId, "Closed")
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "初始化基地门状态: PlayerHome" .. homeId .. " -> Closed")
        end
    end)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化玩家基地:", player.Name, "基地编号:", homeId)
    end

    return true
end

--[[
获取玩家基地数据
@param player Player - 玩家对象
@return table|nil - 基地数据
]]
function HomeSystem.GetPlayerHome(player)
    if not player then
        return nil
    end

    return playerHomes[player.UserId]
end

--[[
清理玩家基地数据 (V2.0.1新增：支持基地门关闭)
@param homeId number - 基地编号 (1~6)
@param player Player - 玩家对象
]]
function HomeSystem.CleanupPlayerHome(homeId, player)
    if not homeId or not player then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.CleanupPlayerHome: 参数无效")
        return
    end

    local homeFolder = GetHomeFolder(homeId)
    if not homeFolder then
        HomeSystem.ClearPlayerHome(player)
        return
    end

    if not IsHomeOwnedByPlayer(homeFolder, player) then
        warn(GameConfig.LOG_PREFIX, "HomeSystem.CleanupPlayerHome: 基地归属不匹配，跳过清理", homeId)
        HomeSystem.ClearPlayerHome(player)
        return
    end

    -- V2.0.1新增：关闭基地门
    pcall(function()
        DoorControlService.CloseDoor(homeId)
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "清理时关闭基地门: PlayerHome" .. homeId)
        end
    end)

    -- 调用原有清理逻辑
    if homeFolder then
        ResetInformationDisplay(homeFolder)
        ResetMailDisplay(homeFolder)
		local spawnLocation = homeFolder:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
		ResetHouseModelToDefault(homeFolder, homeId, spawnLocation)
    end

    DestroyUnitModelsByHomeSlot(homeId)
    HomeSystem.ClearPlayerHome(player)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "清理玩家基地完成:", player.Name, "基地编号:", homeId)
    end
end

--[[
清除玩家基地数据 (V2.0.1保留：向下兼容)
@param player Player - 玩家对象
]]
function HomeSystem.ClearPlayerHome(player)
    if not player then
        return
    end

    local homeData = playerHomes[player.UserId]
    if homeData then
        -- TODO: 后续版本在此清理基地上的兵种等内容

        playerHomes[player.UserId] = nil

        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "清除玩家基地数据:", player.Name)
        end
    end
end

-- ==================== 后续版本预留接口 ====================

--[[
在基地上放置兵种(预留接口)
@param player Player - 玩家对象
@param unitId string - 兵种ID
@param position Vector3 - 放置位置
@return boolean - 是否成功
]]
function HomeSystem.PlaceUnit(player, unitId, position)
    -- TODO: 后续版本实现
    warn(GameConfig.LOG_PREFIX, "HomeSystem.PlaceUnit: 功能未实现,等待后续版本")
    return false
end

--[[
从基地移除兵种(预留接口)
@param player Player - 玩家对象
@param unitInstanceId string - 兵种实例ID
@return boolean - 是否成功
]]
function HomeSystem.RemoveUnit(player, unitInstanceId)
    -- TODO: 后续版本实现
    warn(GameConfig.LOG_PREFIX, "HomeSystem.RemoveUnit: 功能未实现,等待后续版本")
    return false
end

--[[
获取基地上的所有兵种(预留接口)
@param player Player - 玩家对象
@return table - 兵种列表
]]
function HomeSystem.GetHomeUnits(player)
    local homeData = HomeSystem.GetPlayerHome(player)
    if not homeData then
        return {}
    end

    return homeData.Units
end

--[[
初始化基地系统
]]
function HomeSystem.Initialize()
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化HomeSystem...")
    end

    -- 验证workspace中的基地结构
    local homeFolder = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME)
    if not homeFolder then
        warn(GameConfig.LOG_PREFIX, "警告: workspace中找不到Home文件夹!")
        warn(GameConfig.LOG_PREFIX, "请确保workspace中存在Home文件夹,包含PlayerHome1到PlayerHome6")
    else
        EnsureHouseModulesLoaded()
        local validHouseModelNames = GetValidHouseModelNameSet()
        local defaultModelName = HouseConfig and (
            (HouseConfig.GetHouseModelByRebirthCount and HouseConfig.GetHouseModelByRebirthCount(0))
            or HouseConfig.GetHouseModelByChapter(0)
        ) or nil
        -- 检查所有基地是否存在
        for i = GameConfig.MIN_HOME_SLOT, GameConfig.MAX_HOME_SLOT do
            local playerHomeName = GameConfig.HOME_PREFIX .. i
            local playerHome = homeFolder:FindFirstChild(playerHomeName)

            if not playerHome then
                warn(GameConfig.LOG_PREFIX, "警告: 找不到基地:", playerHomeName)
            else
                local spawnLocation = playerHome:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
                if not spawnLocation then
                    warn(GameConfig.LOG_PREFIX, "警告:", playerHomeName, "缺少SpawnLocation")
                end

                local houseFolder = playerHome:FindFirstChild("House")
                local currentHouseModel = FindHouseModelInFolder(houseFolder, defaultModelName, validHouseModelNames)
                if spawnLocation and spawnLocation:IsA("BasePart") and currentHouseModel then
                    CacheHousePlacement(i, spawnLocation, currentHouseModel, {homeFolder = playerHome, force = true})
                    CleanupExtraHouseModels(houseFolder, currentHouseModel, validHouseModelNames)
                end
            end
        end

        -- 🔥重要：预缓存Information面板的“Studio默认文本”
        -- 说明：战斗力系统会在服务端直接写入Information面板文本，如果我们等到玩家离线时才缓存默认值，
        --      很可能把“玩家当前名字/战斗力”误当成默认值，导致离线清理时无法恢复默认显示。
        -- 做法：在服务器启动阶段（还未写入玩家数据前）提前读取一次作为默认值。
        for i = GameConfig.MIN_HOME_SLOT, GameConfig.MAX_HOME_SLOT do
            local playerHome = homeFolder:FindFirstChild(GameConfig.HOME_PREFIX .. i)
            local information = playerHome and playerHome:FindFirstChild("Information")
            if information then
                CacheInformationDefaultTexts(information)
                break
            end
        end

        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "基地结构验证完成")
        end
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "HomeSystem初始化完成")
    end
end

return HomeSystem
