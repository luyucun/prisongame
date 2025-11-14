--[[
脚本名称: PlayerManager
脚本类型: ModuleScript (服务端核心)
脚本位置: ServerScriptService/Core/PlayerManager
]]

--[[
玩家管理器模块
职责:
1. 处理玩家加入和离开游戏
2. 随机分配可用基地(1-6)
3. 传送玩家到对应基地的出生点
4. 管理基地占用状态
]]

local PlayerManager = {}

-- 引用服务
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local DataManager = require(ServerScriptService.Core.DataManager)

-- 基地占用状态表 [homeSlot] = player 或 nil
local homeOccupancy = {}

-- 玩家角色事件连接 [UserId] = Connection (用于清理)
local playerCharacterConnections = {}

-- 初始化基地占用表
for i = GameConfig.MIN_HOME_SLOT, GameConfig.MAX_HOME_SLOT do
    homeOccupancy[i] = nil
end

-- ==================== 私有函数 ====================

--[[
获取所有可用的基地编号
@return table - 可用基地编号列表
]]
local function GetAvailableHomes()
    local available = {}

    for homeSlot = GameConfig.MIN_HOME_SLOT, GameConfig.MAX_HOME_SLOT do
        if homeOccupancy[homeSlot] == nil then
            table.insert(available, homeSlot)
        end
    end

    return available
end

--[[
随机选择一个可用基地
@return number|nil - 基地编号,如果没有可用基地则返回nil
]]
local function SelectRandomHome()
    local availableHomes = GetAvailableHomes()

    if #availableHomes == 0 then
        warn(GameConfig.LOG_PREFIX, "没有可用的基地!")
        return nil
    end

    -- 从可用基地中随机选择一个
    local randomIndex = math.random(1, #availableHomes)
    local selectedHome = availableHomes[randomIndex]

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "可用基地列表:", table.concat(availableHomes, ", "))
        print(GameConfig.LOG_PREFIX, "随机选择基地编号:", selectedHome)
    end

    return selectedHome
end

--[[
占用指定基地
@param homeSlot number - 基地编号
@param player Player - 玩家对象
@return boolean - 是否占用成功
]]
local function OccupyHome(homeSlot, player)
    -- 检查基地是否已被占用
    if homeOccupancy[homeSlot] ~= nil then
        warn(GameConfig.LOG_PREFIX, "基地已被占用:", homeSlot)
        return false
    end

    homeOccupancy[homeSlot] = player

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "玩家", player.Name, "占用基地", homeSlot)
    end

    return true
end

--[[
释放指定基地
@param homeSlot number - 基地编号
]]
local function ReleaseHome(homeSlot)
    if homeOccupancy[homeSlot] then
        local playerName = homeOccupancy[homeSlot].Name
        homeOccupancy[homeSlot] = nil

        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "释放基地", homeSlot, "原玩家:", playerName)
        end
    end
end

--[[
获取基地的出生点
@param homeSlot number - 基地编号
@return BasePart|nil - 出生点对象
]]
local function GetHomeSpawnLocation(homeSlot)
    local homeFolder = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME)
    if not homeFolder then
        warn(GameConfig.LOG_PREFIX, "找不到Home文件夹!")
        return nil
    end

    local playerHomeName = GameConfig.HOME_PREFIX .. homeSlot
    local playerHome = homeFolder:FindFirstChild(playerHomeName)
    if not playerHome then
        warn(GameConfig.LOG_PREFIX, "找不到基地:", playerHomeName)
        return nil
    end

    local spawnLocation = playerHome:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
    if not spawnLocation then
        warn(GameConfig.LOG_PREFIX, "找不到出生点:", playerHomeName .. "/" .. GameConfig.SPAWN_LOCATION_NAME)
        return nil
    end

    return spawnLocation
end

--[[
根据位置选择最近的可用基地
用于Studio Play Here模式,确保分配的基地与玩家实际位置一致
@param position Vector3 - 玩家当前位置
@return number|nil - 最近的可用基地编号,如果没有可用基地则返回nil
]]
local function FindClosestAvailableHome(position)
    local availableHomes = GetAvailableHomes()

    if #availableHomes == 0 then
        warn(GameConfig.LOG_PREFIX, "没有可用的基地!")
        return nil
    end

    local closestHome = nil
    local closestDistance = math.huge

    -- 遍历所有可用基地,找到最近的
    for _, homeSlot in ipairs(availableHomes) do
        local spawnLocation = GetHomeSpawnLocation(homeSlot)
        if spawnLocation then
            local distance = (spawnLocation.Position - position).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closestHome = homeSlot
            end
        end
    end

    if GameConfig.DEBUG_MODE and closestHome then
        print(GameConfig.LOG_PREFIX, "根据位置选择最近基地:", closestHome, "距离:", math.floor(closestDistance))
    end

    return closestHome
end

--[[
传送玩家到指定基地
@param player Player - 玩家对象
@param homeSlot number - 基地编号
@return boolean - 是否传送成功
]]
local function TeleportPlayerToHome(player, homeSlot)
    -- 检查玩家和基地编号的有效性
    if not player or not homeSlot then
        warn(GameConfig.LOG_PREFIX, "TeleportPlayerToHome: 参数无效")
        return false
    end

    -- 检查角色是否存在
    local character = player.Character
    if not character then
        warn(GameConfig.LOG_PREFIX, "TeleportPlayerToHome: 角色不存在", player.Name)
        return false
    end

    -- 等待HumanoidRootPart加载(最多等待15秒)
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 15)
    if not humanoidRootPart then
        warn(GameConfig.LOG_PREFIX, "找不到玩家的HumanoidRootPart:", player.Name)
        return false
    end

    -- 获取出生点
    local spawnLocation = GetHomeSpawnLocation(homeSlot)
    if not spawnLocation then
        warn(GameConfig.LOG_PREFIX, "获取出生点失败:", homeSlot)
        return false
    end

    -- 验证spawnLocation的有效性
    if not spawnLocation:IsA("BasePart") then
        warn(GameConfig.LOG_PREFIX, "SpawnLocation不是有效的BasePart:", homeSlot)
        return false
    end

    -- 传送玩家
    humanoidRootPart.CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)  -- 向上偏移5避免卡地

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "传送玩家", player.Name, "到基地", homeSlot)
    end

    return true
end

--[[
判断是否应该跳过家园分配
当在Studio中使用"从此处开始游戏"功能时，跳过家园分配
@param player Player - 玩家对象
@return boolean - 是否应该跳过家园分配
]]
local function ShouldSkipHomeAssignment(player)
    -- 首先检查是否在Studio环境中
    if not RunService:IsStudio() then
        return false
    end

    -- 尝试获取玩家的 JoinData
    local success, joinData = pcall(function()
        return player:GetJoinData()
    end)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "GetJoinData success:", success)
        if success and joinData then
            print(GameConfig.LOG_PREFIX, "JoinData type:", typeof(joinData))
            for k, v in pairs(joinData) do
                print(GameConfig.LOG_PREFIX, "  JoinData." .. tostring(k) .. " =", tostring(v))
            end
        else
            print(GameConfig.LOG_PREFIX, "JoinData is nil or error")
        end
    end

    -- 在 Studio 的 PlayHere 模式下，GetJoinData 通常返回空表或 nil
    -- 正式服务器或普通 Play 模式会有 TeleportData 等字段
    if not success or not joinData or (type(joinData) == "table" and next(joinData) == nil) then
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "检测到Studio PlayHere模式（joinData为空），跳过家园分配：", player.Name)
        end
        return true
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "joinData存在且有内容，保持默认家园分配行为")
    end

    return false
end

-- ==================== 公共接口 ====================

--[[
处理玩家加入游戏
@param player Player - 玩家对象
]]
function PlayerManager.OnPlayerAdded(player)
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "玩家加入:", player.Name)
    end

    -- 1. 初始化玩家数据
    DataManager.InitializePlayerData(player)

    -- 2. 检查是否在Studio Play Here模式下
    local skipHomeAssignment = ShouldSkipHomeAssignment(player)
    if skipHomeAssignment and GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "检测到Studio Play Here模式，将根据玩家位置选择基地:", player.Name)
    end

    -- 3. 选择基地
    local homeSlot = nil

    if skipHomeAssignment then
        -- Studio Play Here模式：根据玩家当前位置选择最近的基地
        -- 需要等待角色加载完成
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)

        if humanoidRootPart then
            -- 根据玩家当前位置找到最近的可用基地
            homeSlot = FindClosestAvailableHome(humanoidRootPart.Position)
            if GameConfig.DEBUG_MODE and homeSlot then
                print(GameConfig.LOG_PREFIX, "Play Here模式 - 玩家位置:", humanoidRootPart.Position, "选择基地:", homeSlot)
            end
        else
            warn(GameConfig.LOG_PREFIX, "Play Here模式下无法获取角色位置，回退到随机分配")
        end
    end

    -- 如果没有通过位置选择到基地，则随机选择
    if not homeSlot then
        homeSlot = SelectRandomHome()
    end

    if not homeSlot then
        warn(GameConfig.LOG_PREFIX, "无法为玩家分配基地,服务器已满!", player.Name)
        -- TODO: 后续可以考虑踢出玩家或显示等待界面
        return
    end

    -- 4. 占用基地
    if not OccupyHome(homeSlot, player) then
        warn(GameConfig.LOG_PREFIX, "占用基地失败:", player.Name, homeSlot)
        return
    end

    -- 5. 设置玩家数据中的基地编号
    DataManager.SetPlayerHomeSlot(player, homeSlot)

    -- 5.1 同步HomeSlot到客户端（用于客户端确定正确的IdleFloor）
    player:SetAttribute("HomeSlot", homeSlot)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "同步HomeSlot到客户端:", player.Name, "HomeSlot:", homeSlot)
    end

    -- 6. 初始化玩家基地(HomeSystem)
    local HomeSystem = require(ServerScriptService.Systems.HomeSystem)
    HomeSystem.InitializePlayerHome(homeSlot, player)  -- V2.0.1修复：传入正确的参数 (homeId, player)

    -- 6.5 V2.0.1新增：生成Stage001（如果不存在）
    -- 注意：必须在HomeSystem初始化后执行，确保Stage文件夹存在
    task.spawn(function()
        -- 短暂延迟，确保HomeSystem初始化完成
        task.wait(0.1)

        local StageService = require(ServerScriptService.Systems.StageService)
        local stage001 = StageService.GetOrCreateStage(player.UserId, 1)
        if stage001 then
            print(GameConfig.LOG_PREFIX, "Stage001已准备完成:", player.Name, "HomeSlot:", homeSlot)
        else
            warn(GameConfig.LOG_PREFIX, "Stage001生成失败:", player.Name, "HomeSlot:", homeSlot)
        end
    end)

    -- 6.6 V2.1新增：初始化商店库存定时器
    task.spawn(function()
        -- 短暂延迟，确保其他系统初始化完成
        task.wait(0.5)

        local ShopSystem = ServerScriptService.Systems:FindFirstChild("ShopSystem")
        if ShopSystem then
            local shopModule = require(ShopSystem)
            if shopModule.InitializePlayerShopTimer then
                shopModule.InitializePlayerShopTimer(player, "UnitShop")
                if GameConfig.DEBUG_MODE then
                    print(GameConfig.LOG_PREFIX, "商店定时器初始化完成:", player.Name)
                end
            end
        else
            if GameConfig.DEBUG_MODE then
                warn(GameConfig.LOG_PREFIX, "ShopSystem未找到，跳过商店定时器初始化")
            end
        end
    end)

    -- 7. 处理角色传送 - 使用异步方式避免阻塞
    -- 标记是否应跳过首次传送（用于Studio Play Here模式）
    local shouldSkipFirstTeleport = skipHomeAssignment

    -- 标记是否已经处理过初始角色（防止重复传送）
    local hasProcessedInitialCharacter = false

    local function HandleCharacterSpawn(character)
        task.spawn(function()
            -- 检查是否应跳过首次传送（Studio Play Here模式）
            if shouldSkipFirstTeleport then
                if GameConfig.DEBUG_MODE then
                    print(GameConfig.LOG_PREFIX, "检测到Studio Play Here模式，跳过首次传送:", player.Name)
                end
                shouldSkipFirstTeleport = false  -- 只跳过第一次，后续重生正常传送
                hasProcessedInitialCharacter = true  -- 标记已处理初始角色
                return
            end

            -- 等待一小段时间确保角色完全加载
            task.wait(0.1)

            local success = TeleportPlayerToHome(player, homeSlot)
            if not success then
                warn(GameConfig.LOG_PREFIX, "传送失败,将在角色重生时重试:", player.Name)
            else
                if GameConfig.DEBUG_MODE then
                    print(GameConfig.LOG_PREFIX, "成功传送玩家到基地:", player.Name, "HomeSlot:", homeSlot)
                end
            end
        end)
    end

    -- 连接玩家重生事件（必须在检查Character之前连接，避免竞态条件）
    local characterAddedConnection = player.CharacterAdded:Connect(function(character)
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "玩家角色加载/重生:", player.Name)
        end
        HandleCharacterSpawn(character)
    end)

    -- 保存连接以便后续清理
    playerCharacterConnections[player.UserId] = characterAddedConnection

    -- 如果角色已存在，且CharacterAdded还未触发，则手动处理一次
    -- 使用task.defer确保在CharacterAdded连接后执行，避免重复
    if player.Character and not hasProcessedInitialCharacter then
        task.defer(function()
            -- 再次检查，防止CharacterAdded已经触发
            if not hasProcessedInitialCharacter then
                hasProcessedInitialCharacter = true
                HandleCharacterSpawn(player.Character)
            end
        end)
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "玩家", player.Name, "初始化完成,基地编号:", homeSlot)
    end
end

--[[
处理玩家离开游戏
@param player Player - 玩家对象
]]
function PlayerManager.OnPlayerRemoving(player)
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "玩家离开:", player.Name)
    end

    -- 1. 获取玩家的基地编号
    local homeSlot = DataManager.GetPlayerHomeSlot(player)

    -- 2. 释放基地
    if homeSlot and homeSlot > 0 then
        ReleaseHome(homeSlot)
    end

    -- 3. 断开CharacterAdded连接
    if playerCharacterConnections[player.UserId] then
        playerCharacterConnections[player.UserId]:Disconnect()
        playerCharacterConnections[player.UserId] = nil
    end

    -- 4. 清除基地系统数据
    local HomeSystem = require(ServerScriptService.Systems.HomeSystem)
    if homeSlot and homeSlot > 0 then
        HomeSystem.CleanupPlayerHome(homeSlot, player)  -- V2.0.1修复：调用正确的方法并传入homeId
    end

    -- 5. 清除玩家数据
    DataManager.ClearPlayerData(player)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "玩家", player.Name, "清理完成")
    end
end

--[[
获取基地占用状态(调试用)
@return table - 基地占用状态表
]]
function PlayerManager.GetHomeOccupancy()
    return homeOccupancy
end

--[[
获取可用基地数量
@return number - 可用基地数量
]]
function PlayerManager.GetAvailableHomeCount()
    return #GetAvailableHomes()
end

--[[
获取玩家的HomeId
@param player Player - 玩家对象
@return number - HomeId (1~6), 如果未分配则返回nil
]]
function PlayerManager.GetPlayerHomeId(player)
    if not player then
        return nil
    end
    return DataManager.GetPlayerHomeSlot(player)
end

--[[
初始化玩家管理器
连接玩家加入和离开事件
]]
function PlayerManager.Initialize()
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化PlayerManager...")
    end

    -- 连接玩家加入事件
    Players.PlayerAdded:Connect(PlayerManager.OnPlayerAdded)

    -- 连接玩家离开事件
    Players.PlayerRemoving:Connect(PlayerManager.OnPlayerRemoving)

    -- 处理已经在游戏中的玩家(用于测试)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            PlayerManager.OnPlayerAdded(player)
        end)
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "PlayerManager初始化完成")
    end
end

return PlayerManager
