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

==================== 武器模型结构规范 ====================
为了让子弹从正确的位置发射，远程武器模型应包含发射点Part：

推荐模型结构:
Rifle (Model)
├── Handle (Part) - 武器主体
└── MuzzlePoint (Part) - 发射点，位于枪口位置
    属性: Transparency = 1, CanCollide = false, Anchored = false

支持的发射点命名（按优先级）:
1. MuzzlePoint      (推荐)
2. ProjectileSpawn  (备选)
3. FirePoint        (备选)
4. Muzzle          (备选)
5. SpawnPoint      (备选)

查找逻辑:
1. 优先查找武器模型下的发射点Part
2. 如果没有发射点，使用武器Part中心
3. 如果没有武器，回退到HumanoidRootPart

示例配置:
UnitConfig中设置 WeaponName = "Rifle"
模型中创建名为 Rifle 的Model，其下有 MuzzlePoint 的Part
子弹将从 Rifle.MuzzlePoint 的位置发射
]]

local ProjectileSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

-- 引用配置（从ReplicatedStorage获取共享配置）
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig") :: ModuleScript)
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig") :: ModuleScript)

-- 引用系统（使用类型断言）
local CombatSystem = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("CombatSystem") :: ModuleScript)

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
创建子弹模型 - 支持三种方式
优先级: 自定义模型 > 配置生成 > 默认球体
@param unitId string - 兵种ID
@param startPosition Vector3 - 起始位置
@param targetPosition Vector3 - 目标位置
@return BasePart|Model - 子弹模型
]]
local function CreateProjectileModel(unitId, startPosition, targetPosition)
    local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))

    -- ==================== 方式1: 自定义模型路径 ====================
    local modelPath = UnitConfig.GetProjectileModelPath(unitId)
    if modelPath and modelPath ~= "" then
        -- 从ReplicatedStorage克隆模型
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local pathParts = string.split(modelPath, "/")

        local currentFolder = ReplicatedStorage
        for _, partName in ipairs(pathParts) do
            local child = currentFolder:FindFirstChild(partName)
            if not child then
                WarnLog(string.format("子弹模型路径无效: %s (找不到: %s)", modelPath, partName))
                break
            end
            currentFolder = child
        end

        -- 如果找到了模型，克隆它
        if currentFolder and currentFolder ~= ReplicatedStorage then
            local projectileModel = currentFolder:Clone()

            -- 设置位置和朝向
            if projectileModel:IsA("Model") then
                -- 修复：使用PivotTo替代已弃用的SetPrimaryPartCFrame
                projectileModel:PivotTo(CFrame.new(startPosition, targetPosition))
            else
                projectileModel.CFrame = CFrame.new(startPosition, targetPosition)
            end

            -- 设置属性
            for _, descendant in ipairs(projectileModel:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    descendant.CanCollide = false
                    descendant.Anchored = true
                end
            end

            DebugLog(string.format("使用自定义子弹模型: %s", modelPath))
            return projectileModel
        end
    end

    -- ==================== 方式2: 根据配置生成 ====================
    local projectileConfig = UnitConfig.GetProjectileConfig(unitId)

    local projectilePart = Instance.new("Part")

    -- 设置形状
    if projectileConfig.Shape == "Ball" then
        projectilePart.Shape = Enum.PartType.Ball
    elseif projectileConfig.Shape == "Cylinder" then
        projectilePart.Shape = Enum.PartType.Cylinder
    else
        projectilePart.Shape = Enum.PartType.Block
    end

    -- 设置大小
    projectilePart.Size = projectileConfig.Size or Vector3.new(0.5, 0.5, 0.5)

    -- 设置颜色
    projectilePart.Color = projectileConfig.Color or Color3.fromRGB(255, 255, 0)

    -- 设置材质
    local material = projectileConfig.Material or "Neon"
    local success = pcall(function()
        projectilePart.Material = Enum.Material[material]
    end)
    if not success then
        projectilePart.Material = Enum.Material.Neon
        WarnLog(string.format("材质 '%s' 无效，使用默认Neon", material))
    end

    -- 基础属性
    projectilePart.CanCollide = false
    projectilePart.Anchored = true
    projectilePart.CFrame = CFrame.new(startPosition, targetPosition)

    -- 添加拖尾特效（可选）
    if projectileConfig.EnableTrail then
        local trail = Instance.new("Trail")
        trail.Color = ColorSequence.new(projectileConfig.TrailColor or Color3.new(1, 1, 1))
        trail.Lifetime = projectileConfig.TrailLifetime or 0.5
        trail.FaceCamera = true

        -- 创建两个附件用于Trail
        local attachment0 = Instance.new("Attachment")
        attachment0.Name = "TrailAttachment0"
        attachment0.Parent = projectilePart

        local attachment1 = Instance.new("Attachment")
        attachment1.Name = "TrailAttachment1"
        attachment1.Position = Vector3.new(0, 0, 0.5)
        attachment1.Parent = projectilePart

        trail.Attachment0 = attachment0
        trail.Attachment1 = attachment1
        trail.Parent = projectilePart

        DebugLog(string.format("为子弹添加拖尾特效"))
    end

    DebugLog(string.format("使用配置生成子弹: Shape=%s, Size=%s, Material=%s",
        projectileConfig.Shape, tostring(projectilePart.Size), material))

    return projectilePart
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

        -- 获取弹道位置（支持Model和Part）
        local projectilePos
        if projectile.ProjectileModel:IsA("Model") then
            projectilePos = projectile.ProjectileModel:GetPrimaryPartCFrame().Position
        else
            projectilePos = projectile.ProjectileModel.Position
        end

        -- 计算方向和距离
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

        -- 更新弹道位置（支持Model和Part）
        if projectile.ProjectileModel:IsA("Model") then
            -- 修复：使用PivotTo替代已弃用的SetPrimaryPartCFrame
            projectile.ProjectileModel:PivotTo(CFrame.new(newPos, targetPos))
        else
            projectile.ProjectileModel.CFrame = CFrame.new(newPos, targetPos)
        end
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
    local weaponName = attackerState and attackerState.UnitId and require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig")).GetWeaponName(attackerState.UnitId) or "Sword"

    -- ==================== 智能查找发射起点 ====================
    -- 优先级: 武器下的发射点 > 武器Part > HumanoidRootPart
    local startPart = nil

    -- 1. 查找武器Part
    local weaponPart = attacker:FindFirstChild(weaponName)

    if weaponPart then
        -- 2. 在武器下查找发射点Part（支持多种命名规范）
        local muzzlePointNames = {
            "MuzzlePoint",      -- 推荐命名
            "ProjectileSpawn",  -- 备选命名1
            "FirePoint",        -- 备选命名2
            "Muzzle",           -- 备选命名3
            "SpawnPoint"        -- 备选命名4
        }

        for _, pointName in ipairs(muzzlePointNames) do
            local muzzlePoint = weaponPart:FindFirstChild(pointName)
            if muzzlePoint and muzzlePoint:IsA("BasePart") then
                startPart = muzzlePoint
                DebugLog(string.format("找到武器发射点: %s.%s", weaponName, pointName))
                break
            end
        end

        -- 3. 如果没找到发射点，使用武器Part本身
        if not startPart then
            startPart = weaponPart
            DebugLog(string.format("使用武器中心作为发射点: %s", weaponName))
        end
    else
        -- 4. 如果没找到武器，回退到HumanoidRootPart
        startPart = attacker:FindFirstChild("HumanoidRootPart") or attacker.PrimaryPart
        if startPart then
            DebugLog("武器未找到，使用HumanoidRootPart作为发射点")
        end
    end

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

    -- ==================== 创建子弹模型 ====================
    -- 使用新的CreateProjectileModel函数，支持自定义模型、配置生成、默认球体
    local unitId = attackerState and attackerState.UnitId or "Unknown"
    local projectileModel = CreateProjectileModel(unitId, startPart.Position, targetPart.Position)

    if not projectileModel then
        WarnLog("CreateProjectile失败: 无法创建子弹模型")
        return nil
    end

    -- 将模型添加到Workspace
    projectileModel.Parent = Workspace

    -- 设置弹道碰撞组
    if projectileModel:IsA("Model") then
        for _, part in ipairs(projectileModel:GetDescendants()) do
            if part:IsA("BasePart") then
                pcall(function()
                    part.CollisionGroup = BattleConfig.PROJECTILE_COLLISION_GROUP
                end)
            end
        end
    else
        pcall(function()
            projectileModel.CollisionGroup = BattleConfig.PROJECTILE_COLLISION_GROUP
        end)
    end

    -- 创建弹道数据
    local projectile = {
        ProjectileModel = projectileModel,
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

    -- 获取攻击者和目标的单位ID（用于日志）
    local attackerState = CombatSystem.GetUnitState(projectile.Attacker)
    local targetState = CombatSystem.GetUnitState(target)

    local attackerName = attackerState and attackerState.UnitId or "Unknown"
    local targetName = targetState and targetState.UnitId or "Unknown"

    DebugLog(string.format("弹道命中: %s -> %s, 造成%d伤害",
        attackerName, targetName, projectile.Damage))

    -- ⭐⭐⭐ 对目标造成伤害 ⭐⭐⭐
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
