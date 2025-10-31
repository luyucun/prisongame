--[[
脚本名称: ProjectileSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/ProjectileSystem
]]

--[[
弹道系统
职责:
1. 创建和管理弹道
2. 弹道追踪目标
3. 碰撞检测
4. 命中判定
版本: V1.5
]]

local ProjectileSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

-- 引用配置
local GameConfig = require(ServerScriptService.Config.GameConfig)
local BattleConfig = require(ServerScriptService.Config.BattleConfig)

-- 引用系统
local CombatSystem = require(ServerScriptService.Systems.CombatSystem)

-- ==================== 私有变量 ====================

-- 存储所有活跃的弹道
local activeProjectiles = {}

-- 弹道更新连接
local updateConnection = nil

-- 是否已初始化
local isInitialized = false

-- ==================== 数据结构 ====================

--[[
Projectile = {
    ProjectileModel = Part,      -- 弹道模型(一个Part)
    Attacker = Model,            -- 攻击者
    Target = Model,              -- 目标
    Damage = number,             -- 伤害值
    Speed = number,              -- 飞行速度
    StartTime = number,          -- 发射时间
    IsActive = boolean,          -- 是否有效
}
]]

-- ==================== 私有函数 ====================

--[[
输出调试日志
@param ... - 日志内容
]]
local function DebugLog(...)
    if BattleConfig.DEBUG_COMBAT_LOGS then
        print(GameConfig.LOG_PREFIX, "[ProjectileSystem]", ...)
    end
end

--[[
输出警告日志
@param ... - 日志内容
]]
local function WarnLog(...)
    warn(GameConfig.LOG_PREFIX, "[ProjectileSystem]", ...)
end

--[[
更新所有弹道
@param dt number - 帧间隔时间(秒)
]]
local function UpdateProjectiles(dt)
    local currentTime = tick()

    for i = #activeProjectiles, 1, -1 do
        local projectile = activeProjectiles[i]

        -- 检查弹道是否超时
        if currentTime - projectile.StartTime > BattleConfig.PROJECTILE_LIFETIME then
            ProjectileSystem.DestroyProjectile(projectile)
            table.remove(activeProjectiles, i)
            continue
        end

        -- 检查目标是否还存活
        if not projectile.Target or not projectile.Target.Parent or not CombatSystem.IsUnitAlive(projectile.Target) then
            ProjectileSystem.DestroyProjectile(projectile)
            table.remove(activeProjectiles, i)
            continue
        end

        -- 检查弹道模型是否还存在
        if not projectile.ProjectileModel or not projectile.ProjectileModel.Parent then
            table.remove(activeProjectiles, i)
            continue
        end

        -- 获取目标位置(HumanoidRootPart或PrimaryPart)
        local targetPart = projectile.Target:FindFirstChild("HumanoidRootPart") or projectile.Target.PrimaryPart
        if not targetPart then
            ProjectileSystem.DestroyProjectile(projectile)
            table.remove(activeProjectiles, i)
            continue
        end

        local targetPos = targetPart.Position

        -- 计算方向和距离
        local projectilePos = projectile.ProjectileModel.Position
        local direction = (targetPos - projectilePos).Unit
        local distance = (targetPos - projectilePos).Magnitude

        -- 检查是否命中(距离小于阈值)
        if distance <= BattleConfig.PROJECTILE_HIT_DISTANCE then
            ProjectileSystem.OnProjectileHit(projectile, projectile.Target)
            table.remove(activeProjectiles, i)
            continue
        end

        -- 移动弹道(追踪目标) - 使用实际的dt而不是固定的间隔
        local moveDistance = projectile.Speed * dt
        local newPos = projectilePos + direction * moveDistance

        projectile.ProjectileModel.CFrame = CFrame.new(newPos, targetPos)
    end
end

-- ==================== 公共接口 ====================

--[[
初始化弹道系统
@return boolean - 是否初始化成功
]]
function ProjectileSystem.Initialize()
    if isInitialized then
        WarnLog("弹道系统已经初始化过了")
        return true
    end

    DebugLog("正在初始化弹道系统...")

    -- 连接更新循环，接收dt参数
    updateConnection = RunService.Heartbeat:Connect(function(dt)
        UpdateProjectiles(dt)
    end)

    isInitialized = true

    DebugLog("弹道系统初始化完成")
    return true
end

--[[
关闭弹道系统
]]
function ProjectileSystem.Shutdown()
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end

    -- 清理所有弹道
    for _, projectile in ipairs(activeProjectiles) do
        ProjectileSystem.DestroyProjectile(projectile)
    end

    activeProjectiles = {}
    isInitialized = false

    DebugLog("弹道系统已关闭")
end

--[[
创建弹道
@param attacker Model - 攻击者
@param target Model - 目标
@param damage number - 伤害值
@param speed number - 飞行速度
@return Projectile|nil - 弹道对象,失败返回nil
]]
function ProjectileSystem.CreateProjectile(attacker, target, damage, speed)
    if not attacker or not attacker.Parent then
        WarnLog("CreateProjectile失败: attacker无效")
        return nil
    end

    if not target or not target.Parent then
        WarnLog("CreateProjectile失败: target无效")
        return nil
    end

    -- 获取攻击者的武器位置或HumanoidRootPart
    local attackerState = CombatSystem.GetUnitState(attacker)
    local weaponName = attackerState and attackerState.UnitId and require(ServerScriptService.Config.UnitConfig).GetWeaponName(attackerState.UnitId) or "Sword"

    local startPart = attacker:FindFirstChild(weaponName) or attacker:FindFirstChild("HumanoidRootPart") or attacker.PrimaryPart

    if not startPart then
        WarnLog("CreateProjectile失败: 找不到发射起点")
        return nil
    end

    -- 获取目标位置
    local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart

    if not targetPart then
        WarnLog("CreateProjectile失败: 找不到目标位置")
        return nil
    end

    -- 创建弹道Part
    local projectilePart = Instance.new("Part")
    projectilePart.Size = BattleConfig.PROJECTILE_SIZE
    projectilePart.Shape = Enum.PartType.Ball
    projectilePart.Material = Enum.Material.Neon
    projectilePart.Color = BattleConfig.PROJECTILE_COLOR
    projectilePart.CanCollide = false
    projectilePart.Anchored = true
    projectilePart.Position = startPart.Position
    projectilePart.CFrame = CFrame.new(startPart.Position, targetPart.Position)
    projectilePart.Parent = Workspace

    -- 设置弹道碰撞组
    pcall(function()
        PhysicsService:SetPartCollisionGroup(projectilePart, BattleConfig.PROJECTILE_COLLISION_GROUP)
    end)

    -- 创建弹道数据
    local projectile = {
        ProjectileModel = projectilePart,
        Attacker = attacker,
        Target = target,
        Damage = damage,
        Speed = speed,
        StartTime = tick(),
        IsActive = true,
    }

    -- 添加到活跃弹道列表
    table.insert(activeProjectiles, projectile)

    DebugLog(string.format("创建弹道: 速度%d studs/s, 伤害%d", speed, damage))

    return projectile
end

--[[
弹道命中目标
@param projectile Projectile - 弹道对象
@param target Model - 目标
]]
function ProjectileSystem.OnProjectileHit(projectile, target)
    if not projectile.IsActive then
        return
    end

    projectile.IsActive = false

    DebugLog(string.format("弹道命中目标,造成%d伤害", projectile.Damage))

    -- 对目标造成伤害
    CombatSystem.TakeDamage(target, projectile.Damage, projectile.Attacker)

    -- 销毁弹道
    ProjectileSystem.DestroyProjectile(projectile)
end

--[[
销毁弹道
@param projectile Projectile - 弹道对象
]]
function ProjectileSystem.DestroyProjectile(projectile)
    if projectile.ProjectileModel and projectile.ProjectileModel.Parent then
        projectile.ProjectileModel:Destroy()
    end

    projectile.IsActive = false
end

--[[
清理所有弹道
]]
function ProjectileSystem.ClearAllProjectiles()
    for _, projectile in ipairs(activeProjectiles) do
        ProjectileSystem.DestroyProjectile(projectile)
    end

    activeProjectiles = {}

    DebugLog("已清理所有弹道")
end

--[[
获取活跃弹道数量
@return number - 活跃弹道数量
]]
function ProjectileSystem.GetActiveProjectileCount()
    return #activeProjectiles
end

return ProjectileSystem
