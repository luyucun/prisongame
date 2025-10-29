--[[
脚本名称: PhysicsManager
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/PhysicsManager
]]

--[[
物理管理系统
职责:
1. 管理玩家和兵种之间的碰撞关系
2. 禁用玩家与兵种之间的碰撞
3. 处理玩家和兵种的物理交互
版本: V1.2
]]

local PhysicsManager = {}

-- 引用服务
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- 引用模块
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ServerScriptService.Config.GameConfig)

-- 跟踪已创建的碰撞组
local groupsCreated = false

-- ==================== 初始化 ====================

--[[
初始化物理管理系统
]]
function PhysicsManager.Initialize()
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化PhysicsManager...")
    end

    -- 创建碰撞组
    CreateCollisionGroups()

    -- 为现有玩家设置碰撞
    for _, player in ipairs(Players:GetPlayers()) do
        OnPlayerAdded(player)
    end

    -- 监听新玩家加入
    Players.PlayerAdded:Connect(OnPlayerAdded)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "PhysicsManager初始化完成")
    end

    return true
end

-- ==================== 碰撞组创建 ====================

--[[
创建必要的碰撞组
]]
function CreateCollisionGroups()
    if groupsCreated then
        return
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "创建碰撞组...")
    end

    -- 创建玩家碰撞组
    pcall(function()
        PhysicsService:RegisterCollisionGroup("Players")
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "创建'Players'碰撞组成功")
        end
    end)

    -- 创建兵种碰撞组
    pcall(function()
        PhysicsService:RegisterCollisionGroup("Units")
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "创建'Units'碰撞组成功")
        end
    end)

    -- 禁用两组之间的碰撞
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable("Players", "Units", false)
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "禁用'Players'和'Units'之间的碰撞")
        end
    end)

    groupsCreated = true
end

-- ==================== 玩家处理 ====================

--[[
处理玩家加入事件
@param player Player
]]
function OnPlayerAdded(player)
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "玩家加入:", player.Name)
    end

    -- 等待玩家角色加载
    local character = player.Character or player.CharacterAdded:Wait()
    task.wait(0.1)

    -- 为玩家角色设置无碰撞组
    DisablePlayerCollisions(player, character)

    -- 监听角色重生
    local characterAddedConnection
    characterAddedConnection = player.CharacterAdded:Connect(function(newCharacter)
        if GameConfig.DEBUG_MODE then
            print(GameConfig.LOG_PREFIX, "玩家角色重生:", player.Name)
        end
        task.wait(0.1)
        DisablePlayerCollisions(player, newCharacter)
    end)

    -- 监听玩家离开
    local playerRemovingConnection
    playerRemovingConnection = Players.PlayerRemoving:Connect(function(removingPlayer)
        if removingPlayer == player then
            characterAddedConnection:Disconnect()
            playerRemovingConnection:Disconnect()
        end
    end)
end

--[[
为玩家禁用碰撞
@param player Player
@param character Model - 玩家角色
]]
function DisablePlayerCollisions(player, character)
    if not character then
        return
    end

    -- 获取玩家的所有Part
    local playerParts = character:GetDescendants()
    local addedCount = 0

    for _, part in ipairs(playerParts) do
        if part:IsA("BasePart") then
            local success, err = pcall(function()
                part.CollisionGroup = "Players"
                addedCount = addedCount + 1
            end)

            if not success and GameConfig.DEBUG_MODE then
                warn(GameConfig.LOG_PREFIX, "设置玩家Part碰撞组失败:", part:GetFullName(), err)
            end
        end
    end

    -- 监听后续动态添加的Part（如饰品、特效等）
    character.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") then
            pcall(function()
                descendant.CollisionGroup = "Players"
                if GameConfig.DEBUG_MODE then
                    print(GameConfig.LOG_PREFIX, "动态添加玩家Part到碰撞组:", descendant:GetFullName())
                end
            end)
        end
    end)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "为玩家添加到碰撞组:", player.Name, "Part数量:", addedCount)
    end
end

-- ==================== 兵种处理 ====================

--[[
为已放置的兵种模型设置碰撞组
@param model Model - 兵种模型
]]
function PhysicsManager.ConfigureUnitPhysics(model)
    if not model then
        return
    end

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "配置兵种物理:", model:GetFullName())
    end

    -- 获取兵种模型的所有Part
    local unitParts = model:GetDescendants()
    local addedCount = 0

    for _, part in ipairs(unitParts) do
        if part:IsA("BasePart") then
            local success, err = pcall(function()
                part.CollisionGroup = "Units"
                addedCount = addedCount + 1
            end)

            if not success and GameConfig.DEBUG_MODE then
                warn(GameConfig.LOG_PREFIX, "设置兵种Part碰撞组失败:", part:GetFullName(), err)
            end
        end
    end

    -- 监听后续动态添加的Part（如特效、装备等）
    model.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("BasePart") then
            pcall(function()
                descendant.CollisionGroup = "Units"
                if GameConfig.DEBUG_MODE then
                    print(GameConfig.LOG_PREFIX, "动态添加兵种Part到碰撞组:", descendant:GetFullName())
                end
            end)
        end
    end)

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "兵种Part添加到Units组:", addedCount, "个")
    end
end

return PhysicsManager

