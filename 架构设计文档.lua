--[[
=====================================================
游戏整体架构设计文档
=====================================================

项目名称: Roblox 兵种塔防游戏
版本: V1.5
设计日期: 2025-10-31

=====================================================
一、架构设计原则
=====================================================

1. 客户端-服务端分离架构
   - 服务端负责数据管理、权威验证、玩家分配
   - 客户端负责UI显示、用户交互、视觉效果

2. 模块化设计
   - 每个功能模块独立封装
   - 模块间通过事件/接口通信
   - 便于后续功能扩展

3. 数据驱动
   - 玩家数据统一管理
   - 数据变更通过事件通知
   - 客户端监听数据变化实时更新UI

4. 可扩展性
   - 预留接口支持多种货币获取方式
   - 支持后续添加兵种系统、战斗系统等

=====================================================
二、目录结构设计
=====================================================

ServerScriptService/          (服务端脚本目录)
├── Core/                      (核心系统)
│   ├── DataManager.lua        (数据管理器 - 负责玩家数据的加载/保存/管理)
│   └── PlayerManager.lua      (玩家管理器 - 负责玩家进入/离开/基地分配)
│
├── Systems/                   (游戏系统)
│   ├── CurrencySystem.lua     (货币系统 - 负责金币的增减/验证)
│   ├── HomeSystem.lua         (基地系统 - 负责基地管理和初始化)
│   ├── InventorySystem.lua    (背包系统 - 负责兵种背包管理)
│   ├── PlacementSystem.lua    (放置系统 - 负责兵种放置验证 V1.2)
│   ├── MergeSystem.lua        (合成系统 - 负责兵种合成逻辑 V1.4)
│   ├── PhysicsManager.lua     (物理管理 - 负责碰撞组管理 V1.4)
│   ├── BattleManager.lua      (战斗管理器 - 管理战斗实例 V1.5新增)
│   ├── CombatSystem.lua       (战斗系统 - 伤害计算/血量管理 V1.5新增)
│   ├── UnitAI.lua             (兵种AI - 目标寻找/移动/攻击 V1.5新增)
│   ├── ProjectileSystem.lua   (弹道系统 - 远程弹道管理 V1.5新增)
│   ├── BattleTestSystem.lua   (战斗测试系统 - 测试工具 V1.5新增)
│   └── GMCommandSystem.lua    (GM命令系统 - 负责调试命令处理)
│
└── Config/                    (配置文件)
    ├── GameConfig.lua         (游戏配置 - 存储游戏常量和配置)
    ├── UnitConfig.lua         (兵种配置 - 存储兵种属性 V1.5更新)
    ├── PlacementConfig.lua    (放置配置 - 存储放置系统配置 V1.2)
    └── BattleConfig.lua       (战斗配置 - 存储战斗系统配置 V1.5新增)

StarterPlayer/
└── StarterPlayerScripts/      (客户端脚本目录)
    ├── UI/                    (UI相关脚本)
    │   ├── CoinDisplay.lua    (金币显示控制器)
    │   ├── BackpackDisplay.lua (背包显示控制器)
    │   └── BattleTestUI.lua   (战斗测试UI控制器 V1.5新增)
    │
    ├── Controllers/           (客户端控制器)
    │   ├── PlayerController.lua (玩家控制器 - 客户端玩家逻辑)
    │   ├── PlacementController.lua (放置控制器 - 兵种放置交互 V1.2)
    │   ├── DragSystem.lua     (拖动系统 - 兵种拖动与合成 V1.4)
    │   └── RemovalController.lua (回收控制器 - 兵种回收 V1.3)
    │
    └── Utils/                 (工具类)
        ├── UIHelper.lua       (UI辅助工具)
        ├── PlacementHelper.lua (放置辅助工具 - 网格吸附/边界检测 V1.2)
        ├── HighlightHelper.lua (高光辅助工具 - 模型高光效果 V1.2)
        └── GridHelper.lua     (网格辅助工具 - 网格显示 V1.2.1)

ReplicatedStorage/             (共享资源目录)
├── Events/                    (远程事件)
│   ├── CurrencyEvents         (货币相关事件 RemoteEvent)
│   ├── PlayerEvents           (玩家相关事件 RemoteEvent)
│   ├── InventoryEvents/       (背包相关事件 Folder)
│   │   ├── InventoryRefresh   (背包刷新 RemoteEvent)
│   │   ├── RequestInventory   (请求背包 RemoteEvent)
│   │   ├── UnitUpdated        (兵种更新 RemoteEvent)
│   │   ├── RequestUnitInstance (请求兵种实例 RemoteEvent V1.2)
│   │   └── UnitInstanceResponse (兵种实例响应 RemoteEvent V1.2)
│   ├── PlacementEvents/       (放置相关事件 Folder V1.2)
│   │   ├── StartPlacement     (开始放置 RemoteEvent)
│   │   ├── ConfirmPlacement   (确认放置 RemoteEvent)
│   │   ├── CancelPlacement    (取消放置 RemoteEvent)
│   │   ├── PlacementResponse  (放置响应 RemoteEvent)
│   │   ├── RemoveUnit         (回收兵种 RemoteEvent V1.3)
│   │   └── RemoveResponse     (回收响应 RemoteEvent V1.3)
│   ├── MergeEvents/           (合成相关事件 Folder V1.4)
│   │   ├── RequestMerge       (请求合成 RemoteEvent)
│   │   └── MergeResponse      (合成响应 RemoteEvent)
│   └── BattleEvents/          (战斗相关事件 Folder V1.5新增)
│       ├── RequestBattleTest  (请求战斗测试 RemoteEvent)
│       ├── BattleTestResponse (战斗测试响应 RemoteEvent)
│       ├── BattleStateUpdate  (战斗状态更新 RemoteEvent - 可选)
│       └── UnitDeath          (兵种死亡通知 BindableEvent - 服务端内部)
│
└── Modules/                   (共享模块)
    └── FormatHelper.lua       (格式化辅助工具 - 如金币显示格式化)

Workspace/
└── Home/                      (基地区域)
    ├── PlayerHome1/           (1号玩家基地)
    │   └── SpawnLocation      (出生点)
    ├── PlayerHome2/           (2号玩家基地)
    ├── PlayerHome3/
    ├── PlayerHome4/
    ├── PlayerHome5/
    └── PlayerHome6/

StarterGui/
└── MainGui/                   (主界面)
    └── CoinNum                (金币显示TextLabel)

=====================================================
三、核心系统设计
=====================================================

【3.1 数据管理系统 - DataManager】
----------------------------------
职责:
- 管理玩家数据的加载和保存
- 提供数据获取和修改接口
- 处理数据持久化(后续版本对接DataStore)

数据结构:
PlayerData = {
    UserId = 玩家ID,
    Currency = {
        Coins = 100,  -- 金币数量,初始100
    },
    HomeSlot = 1,     -- 分配的基地编号(1-6)
    Units = {},       -- 拥有的兵种数据(后续版本)
}

主要接口:
- GetPlayerData(player) : 获取玩家数据
- UpdateCurrency(player, amount, reason) : 更新货币
- SavePlayerData(player) : 保存玩家数据


【3.2 玩家管理系统 - PlayerManager】
----------------------------------
职责:
- 处理玩家进入游戏
- 随机分配可用基地(1-6)
- 传送玩家到对应基地
- 处理玩家离开释放基地

主要功能:
- 维护6个基地的占用状态
- 随机分配空闲基地
- 玩家离开时释放基地供新玩家使用

基地分配逻辑:
1. 玩家进入时检查所有基地占用状态
2. 从空闲基地(1-6)中随机选择一个
3. 标记基地为已占用
4. 传送玩家到对应SpawnLocation
5. 玩家离开时释放基地


【3.3 货币系统 - CurrencySystem】
----------------------------------
职责:
- 提供货币增减接口
- 验证货币操作合法性
- 通知客户端货币变化

货币获取渠道(预留接口):
1. AddCoinsFromBattle(player, amount) : 战斗获得金币
2. AddCoinsFromIdle(player, amount) : 挂机获得金币
3. AddCoinsFromPurchase(player, productId) : 购买获得金币

事件通知:
- 货币变化时通过RemoteEvent通知客户端更新UI


【3.4 基地系统 - HomeSystem】
----------------------------------
职责:
- 管理玩家基地的初始化
- 后续支持基地内容加载(兵种放置等)

主要功能:
- 根据玩家分配的基地编号初始化基地
- 为后续兵种放置预留扩展接口

=====================================================
四、客户端系统设计
=====================================================

【4.1 金币显示控制器 - CoinDisplay】
----------------------------------
职责:
- 监听服务端货币变化事件
- 实时更新UI显示金币数量
- 格式化显示: $XXXXX

工作流程:
1. 玩家进入时获取初始金币数量
2. 监听CurrencyChanged事件
3. 收到事件后更新TextLabel文本
4. 使用FormatHelper格式化显示


【4.2 玩家控制器 - PlayerController】
----------------------------------
职责:
- 管理客户端玩家状态
- 处理玩家输入
- 协调各个客户端模块

=====================================================
五、通信机制设计
=====================================================

【5.1 RemoteEvent 事件列表】
----------------------------------
ReplicatedStorage.Events.CurrencyEvents/
├── UpdateCurrency : Server -> Client
│   参数: newAmount (number)
│   说明: 通知客户端金币数量变化
│
└── RequestCurrency : Client -> Server
    参数: 无
    说明: 客户端请求当前金币数量


【5.2 数据流向】
----------------------------------
玩家进入游戏:
1. PlayerManager分配基地 -> 传送玩家
2. DataManager加载数据 -> 初始化玩家数据
3. Server触发UpdateCurrency -> Client更新UI

货币变化:
1. 服务端CurrencySystem处理货币变更
2. DataManager更新玩家数据
3. 触发RemoteEvent通知客户端
4. 客户端CoinDisplay更新UI显示

=====================================================
六、V1.0版本开发任务清单
=====================================================

【服务端开发】
1. Config/GameConfig.lua
   - 定义初始金币数量(100)
   - 定义最大玩家数(6)
   - 定义基地编号范围(1-6)

2. Core/DataManager.lua
   - 实现玩家数据结构
   - 实现数据初始化(初始金币100)
   - 实现数据获取接口
   - 实现货币更新接口

3. Core/PlayerManager.lua
   - 实现基地占用状态管理
   - 实现随机基地分配逻辑
   - 实现玩家传送到基地
   - 实现玩家离开释放基地

4. Systems/CurrencySystem.lua
   - 实现货币增减接口
   - 预留三种货币获取渠道接口
   - 实现客户端通知机制

5. Systems/HomeSystem.lua
   - 实现基地初始化
   - 为后续功能预留接口


【客户端开发】
6. ReplicatedStorage/Modules/FormatHelper.lua
   - 实现金币格式化函数: FormatCoins(amount) -> "$XXXXX"

7. ReplicatedStorage/Events/
   - 创建CurrencyEvents (RemoteEvent)
   - 创建PlayerEvents (RemoteEvent)

8. StarterPlayerScripts/UI/CoinDisplay.lua
   - 获取StarterGui.MainGui.CoinNum引用
   - 监听货币变化事件
   - 实时更新UI显示
   - 使用格式化工具显示金币


【测试验证】
9. 测试多玩家进入时基地随机分配
10. 测试金币UI实时显示
11. 测试玩家离开后基地释放

=====================================================
七、后续版本扩展预留
=====================================================

【V1.2 已完成功能】
- 兵种放置系统: 拖放兵种到基地
- 网格吸附系统: 自动对齐到格子
- 边界限制系统: 防止放置超出范围
- 高光预览系统: 放置前预览效果

【V1.3 已完成功能】
- 兵种回收系统: 从场地收回兵种到背包
- 回收模式UI: 专门的回收操作界面

【V1.4 已完成功能】
- 兵种属性系统: 生命值、攻击力、攻击速度
- 兵种等级系统: 1-3级，等级系数计算
- 兵种合成系统: 拖动相同兵种合成升级
- 等级显示系统: 模型头顶显示Lv.X

【V1.5 正在开发 - 战斗系统】
- 战斗管理系统: 管理多个战斗实例(支持6玩家同时战斗)
- 兵种AI系统: 目标寻找、移动寻路、攻击判定
- 战斗系统: 伤害计算、血量管理、死亡流程
- 弹道系统: 远程单位弹道追踪
- 战斗测试工具: 简易UI测试战斗功能

【V2.0 预期功能】
- 商店系统: 购买兵种
- 兵种合成系统

【V3.0 预期功能】
- 关卡系统: 主线关卡挑战
- 战斗系统: 兵种自动战斗
- 奖励系统: 战斗获得金币

【V4.0 预期功能】
- 挂机系统: 离线收益
- 开发者产品: 付费购买金币
- 数据持久化: DataStoreService

【扩展性设计】
- 货币系统已预留三种获取渠道接口
- 基地系统预留兵种放置扩展
- 数据管理器支持扩展新的数据字段
- 模块化设计便于添加新系统

=====================================================
八、技术要点总结
=====================================================

1. 服务端权威
   - 所有数据修改在服务端完成
   - 客户端只负责显示和请求

2. 随机分配算法
   - 维护基地占用表
   - 从空闲基地中随机选择
   - 确保不重复分配

3. 事件驱动UI更新
   - 数据变化通过RemoteEvent通知
   - 客户端监听事件自动更新
   - 解耦数据逻辑和显示逻辑

4. 可扩展架构
   - 模块化设计便于后续添加功能
   - 预留接口支持新的货币获取方式
   - 数据结构支持扩展新字段

=====================================================
架构设计完成
=====================================================
]]


--[[
=====================================================
九、V1.5 战斗系统详细设计
=====================================================

【9.1 战斗系统概述】
----------------------------------
战斗系统是游戏的核心玩法,玩家放置的兵种将自动与关卡中的敌方兵种战斗。
系统需要支持多个玩家同时进行战斗(最多6个玩家),每个战斗实例独立运行。

战斗流程:
1. 玩家发起战斗(测试阶段通过测试UI)
2. 在指定位置生成攻击方和防守方兵种
3. 兵种自动寻找目标、移动、攻击
4. 直至一方全部死亡,战斗结束
5. 等待3秒后清理战场


【9.2 核心模块设计】
----------------------------------

█ BattleManager (战斗管理器)
职责:
- 管理所有战斗实例(支持多个玩家同时战斗)
- 创建和销毁战斗实例
- 分配战斗ID
- 监控战斗状态

数据结构:
BattleInstance = {
    BattleId = number,           -- 战斗实例ID
    PlayerId = number,           -- 发起战斗的玩家UserId
    AttackUnits = {},            -- 攻击方兵种列表 {unitInstance1, unitInstance2...}
    DefenseUnits = {},           -- 防守方兵种列表
    State = string,              -- 战斗状态: "Preparing", "Fighting", "Finished"
    StartTime = number,          -- 战斗开始时间
    Winner = string,             -- 胜利方: "Attack", "Defense", nil
}

主要接口:
- CreateBattle(playerId, attackUnits, defenseUnits) : 创建战斗实例
- StartBattle(battleId) : 开始战斗
- EndBattle(battleId, winner) : 结束战斗
- CleanupBattle(battleId) : 清理战场(移除所有兵种模型)
- GetBattle(battleId) : 获取战斗实例数据
- GetPlayerBattle(playerId) : 获取玩家当前的战斗实例


█ CombatSystem (战斗系统)
职责:
- 管理兵种的战斗状态(血量、是否存活)
- 处理伤害计算
- 处理死亡流程
- 发送死亡通知给攻击者

数据结构:
UnitCombatState = {
    UnitInstance = Model,        -- 兵种模型实例
    UnitId = string,             -- 兵种ID (如"Noob")
    Level = number,              -- 等级 (1-3)
    Team = string,               -- 阵营: "Attack" 或 "Defense"
    BattleId = number,           -- 所属战斗ID

    -- 战斗属性
    MaxHealth = number,          -- 最大生命值
    CurrentHealth = number,      -- 当前生命值
    Attack = number,             -- 攻击力
    AttackSpeed = number,        -- 攻击速度(秒/次)
    AttackRange = number,        -- 攻击距离
    MoveSpeed = number,          -- 移动速度

    -- 战斗状态
    IsAlive = boolean,           -- 是否存活
    CurrentTarget = Model,       -- 当前攻击目标
    LastAttackTime = number,     -- 上次攻击时间
    State = string,              -- 状态: "Idle", "Moving", "Attacking", "Dead"
}

主要接口:
- InitializeUnit(unitModel, unitId, level, team, battleId) : 初始化兵种战斗状态
- TakeDamage(unitModel, damage, attacker) : 兵种受到伤害
- Heal(unitModel, amount) : 治疗(预留接口)
- GetUnitState(unitModel) : 获取兵种战斗状态
- IsUnitAlive(unitModel) : 检查兵种是否存活
- KillUnit(unitModel) : 杀死兵种(播放死亡动画,从战场移除)


█ UnitAI (兵种AI系统)
职责:
- 目标寻找与锁定
- 移动与寻路
- 攻击判定与执行
- 状态机管理

AI状态机:
State = {
    Idle,        -- 待机(无目标)
    Seeking,     -- 寻找目标
    Moving,      -- 移动到目标
    Attacking,   -- 攻击中
    Dead,        -- 死亡
}

主要接口:
- StartAI(unitModel) : 启动兵种AI
- StopAI(unitModel) : 停止兵种AI
- FindNearestEnemy(unitModel) : 寻找最近的敌方单位
- MoveToTarget(unitModel, target) : 移动到目标
- AttackTarget(unitModel, target) : 攻击目标
- OnTargetDeath(unitModel) : 当前目标死亡时的回调

AI核心流程:
1. 寻找目标 -> 锁定距离最近的敌方单位
2. 移动到目标 -> 使用Humanoid.MoveTo或寻路服务
3. 判定距离 -> 检查是否进入攻击范围
4. 如果在范围内 -> 执行攻击
5. 如果不在范围内 -> 继续移动
6. 攻击后 -> 等待攻击冷却
7. 冷却结束 -> 重新判定距离,重复3-6
8. 目标死亡 -> 回到步骤1寻找新目标
9. 无目标 -> 进入Idle状态


█ ProjectileSystem (弹道系统 - 远程单位)
职责:
- 创建和管理弹道
- 弹道追踪目标
- 碰撞检测
- 命中判定

数据结构:
Projectile = {
    ProjectileModel = Part,      -- 弹道模型(一个Part)
    Attacker = Model,            -- 攻击者
    Target = Model,              -- 目标
    Damage = number,             -- 伤害值
    Speed = number,              -- 飞行速度
    StartTime = number,          -- 发射时间
    IsActive = boolean,          -- 是否有效
}

主要接口:
- CreateProjectile(attacker, target, damage, speed) : 创建弹道
- UpdateProjectiles() : 更新所有弹道(每帧调用)
- OnProjectileHit(projectile, target) : 弹道命中目标
- DestroyProjectile(projectile) : 销毁弹道

弹道行为:
1. 从攻击者武器位置发射
2. 始终追踪目标(跟踪炮弹效果)
3. 不与非目标单位碰撞(可穿透其他兵种)
4. 命中目标后触发伤害,销毁弹道
5. 目标死亡后,弹道自动销毁


█ BattleTestSystem (战斗测试系统)
职责:
- 处理测试UI的请求
- 在指定位置生成测试兵种
- 管理测试战斗流程

数据结构:
TestSpawnRequest = {
    PlayerId = number,           -- 请求的玩家ID
    Team = string,               -- "Attack" 或 "Defense"
    UnitId = string,             -- 兵种ID
    Level = number,              -- 等级 (1-3)
    Position = number,           -- 位置编号 (1-5)
}

测试流程:
1. 玩家在UI上选择参数(队伍/兵种/位置/等级)
2. 点击"生成"按钮,发送请求到服务端
3. 服务端在对应Position生成兵种
4. 玩家点击"开始战斗"按钮
5. 服务端创建战斗实例,启动所有兵种AI
6. 战斗进行,直至一方全灭
7. 等待3秒后,清理所有测试兵种


【9.3 兵种配置扩展 (UnitConfig.lua)】
----------------------------------
需要在UnitConfig中新增以下属性:

BaseAttackRange = number,      -- 基础攻击距离(studs)
BaseMoveSpeed = number,        -- 基础移动速度(studs/秒)
ProjectileSpeed = number,      -- 弹道速度(studs/秒) 近战填0
AttackAnimationId = string,    -- 普通攻击动画ID
WeaponName = string,           -- 武器名称(模型中的Tool或Part名称)

示例配置:
["Noob"] = {
    -- ... 现有配置 ...
    BaseAttackRange = 5,       -- 近战攻击距离5 studs
    BaseMoveSpeed = 16,        -- 移动速度16 studs/秒
    ProjectileSpeed = 0,       -- 近战无弹道
    AttackAnimationId = "",    -- 攻击动画ID(暂时留空)
    WeaponName = "Sword",      -- 武器名称
}


【9.4 战斗配置 (BattleConfig.lua - 新增)】
----------------------------------
BattleConfig = {
    -- 测试区域配置
    BATTLE_TEST_FOLDER = "BattleTest",
    ATTACK_FOLDER = "Attack",
    DEFENSE_FOLDER = "Defense",
    SPAWN_POSITION_COUNT = 5,          -- 每方5个生成点

    -- 战斗设置
    MAX_CONCURRENT_BATTLES = 8,        -- 最大同时战斗数(对应8个玩家)
    CLEANUP_DELAY = 3,                 -- 战斗结束后清理延迟(秒)

    -- AI设置
    AI_UPDATE_INTERVAL = 0.1,          -- AI更新间隔(秒) 每0.1秒更新一次
    TARGET_SEARCH_RANGE = 200,         -- 目标搜索范围(studs)
    PATHFINDING_TIMEOUT = 5,           -- 寻路超时时间(秒)

    -- 弹道设置
    PROJECTILE_UPDATE_INTERVAL = 0.05, -- 弹道更新间隔(秒) 每0.05秒更新一次
    PROJECTILE_LIFETIME = 10,          -- 弹道最大存活时间(秒)
    PROJECTILE_SIZE = Vector3.new(0.5, 0.5, 0.5),  -- 弹道大小

    -- 碰撞设置
    UNIT_COLLISION_GROUP = "Units",    -- 兵种碰撞组
    PROJECTILE_COLLISION_GROUP = "Projectiles",  -- 弹道碰撞组

    -- 调试设置
    DEBUG_SHOW_TARGET_LINE = true,     -- 是否显示目标连线(调试用)
    DEBUG_SHOW_ATTACK_RANGE = false,   -- 是否显示攻击范围(调试用)
}


【9.5 通信机制设计】
----------------------------------

█ 客户端 -> 服务端 (RemoteEvent)

1. RequestBattleTest
   触发: 玩家点击测试UI的"开始战斗"按钮
   参数:
     - attackUnits: {{unitId, level, position}...}
     - defenseUnits: {{unitId, level, position}...}
   说明: 请求创建并开始一场测试战斗

█ 服务端 -> 客户端 (RemoteEvent)

1. BattleTestResponse
   触发: 服务端响应战斗测试请求
   参数:
     - success: boolean
     - battleId: number (如果成功)
     - message: string (提示信息)

2. BattleStateUpdate (可选)
   触发: 战斗状态变化时
   参数:
     - battleId: number
     - state: string ("Fighting", "Finished")
     - winner: string ("Attack", "Defense", nil)
   说明: 通知客户端战斗状态更新,用于UI显示

█ 服务端内部 (BindableEvent)

1. UnitDeath
   触发: 兵种死亡时
   参数:
     - unitModel: Model
     - killer: Model (可选)
     - battleId: number
   说明: 通知其他系统兵种死亡,攻击者收到信号后重新寻找目标


【9.6 伤害计算公式】
----------------------------------
造成的伤害值 = 攻击方的攻击力

示例:
- 2级Noob的攻击力 = 10 * 2 * 1.2 = 24
- 每次攻击造成24点伤害
- 敌方血量扣除24点

扣血时机:
- 近战: 武器Part与敌方身体Touched事件触发时
- 远程: 弹道Part与目标身体Touched事件触发时


【9.7 死亡流程】
----------------------------------
1. 检测血量 <= 0
2. 标记IsAlive = false
3. 停止兵种AI
4. 触发UnitDeath事件(通知攻击者)
5. 播放死亡动画(可选,暂时跳过)
6. 从战场移除兵种模型:Destroy()
7. 从战斗实例的兵种列表中移除
8. 检查战斗是否结束(一方全灭)


【9.8 战斗结束判定】
----------------------------------
每当有兵种死亡时,检查:
1. 攻击方是否全部死亡? -> 防守方胜利
2. 防守方是否全部死亡? -> 攻击方胜利
3. 都未全灭 -> 战斗继续

战斗结束后:
1. 停止所有兵种AI
2. 标记战斗状态为"Finished"
3. 记录胜利方
4. 触发BattleStateUpdate事件(通知客户端)
5. 等待3秒
6. 清理战场:移除所有兵种模型
7. 销毁战斗实例


【9.9 测试UI设计 (客户端)】
----------------------------------
UI路径: StarterGui/BattleTestGui (需要创建)

UI组件:
1. 主面板(Frame) - 默认隐藏,按V键打开/关闭
2. 兵种生成区:
   - 下拉列表: 选择队伍(Attack/Defense)
   - 下拉列表: 选择兵种ID
   - 下拉列表: 选择位置(Position1-5)
   - 下拉列表: 选择等级(1-3)
   - 按钮: "生成兵种"
3. 战斗控制区:
   - 按钮: "开始战斗"
   - 按钮: "清理战场"
4. 信息显示区:
   - TextLabel: 显示当前生成的兵种数量
   - TextLabel: 显示战斗状态

UI逻辑 (BattleTestUI.lua):
- 监听V键打开/关闭UI
- 收集UI参数
- 发送RemoteEvent请求到服务端
- 接收服务端响应,显示提示信息


【9.10 兵种碰撞设置】
----------------------------------
兵种之间需要有碰撞:
- 我方兵种 vs 我方兵种: 有碰撞
- 我方兵种 vs 敌方兵种: 有碰撞
- 兵种 vs 地形: 有碰撞

弹道碰撞:
- 弹道 vs 目标: 有碰撞(触发伤害)
- 弹道 vs 非目标: 无碰撞(穿透)
- 弹道 vs 地形: 无碰撞

实现方式:
使用PhysicsService的碰撞组:
- 兵种设置为"Units"组
- 弹道设置为"Projectiles"组
- 配置碰撞组关系


【9.11 开发任务清单 (V1.5)】
----------------------------------

【服务端开发】
1. Config/UnitConfig.lua
   - 新增战斗相关属性字段
   - 为Noob和Rookie配置战斗属性

2. Config/BattleConfig.lua (新建)
   - 创建战斗配置模块
   - 定义所有战斗相关常量

3. Systems/BattleManager.lua (新建)
   - 实现战斗实例管理
   - 实现战斗创建/开始/结束流程
   - 实现战斗清理机制

4. Systems/CombatSystem.lua (新建)
   - 实现兵种战斗状态管理
   - 实现伤害计算
   - 实现死亡流程
   - 实现血量管理

5. Systems/UnitAI.lua (新建)
   - 实现AI状态机
   - 实现目标寻找算法
   - 实现移动与寻路
   - 实现攻击判定与执行
   - 实现目标死亡响应

6. Systems/ProjectileSystem.lua (新建)
   - 实现弹道创建与管理
   - 实现弹道追踪算法
   - 实现碰撞检测
   - 实现命中伤害

7. Systems/BattleTestSystem.lua (新建)
   - 实现测试兵种生成
   - 实现测试战斗流程
   - 连接RemoteEvent
   - 处理客户端请求

8. ReplicatedStorage/Events/BattleEvents/ (新建Folder)
   - 创建RequestBattleTest (RemoteEvent)
   - 创建BattleTestResponse (RemoteEvent)
   - 创建BattleStateUpdate (RemoteEvent)
   - 创建UnitDeath (BindableEvent)

9. MainServer.lua
   - 添加战斗系统初始化
   - 添加弹道系统初始化
   - 添加测试系统初始化

【客户端开发】
10. StarterGui/BattleTestGui (新建ScreenGui)
    - 创建测试UI界面
    - 配置UI组件布局

11. StarterPlayerScripts/UI/BattleTestUI.lua (新建)
    - 实现UI控制逻辑
    - 实现V键打开/关闭
    - 实现参数收集
    - 实现RemoteEvent通信
    - 实现响应处理

【测试验证】
12. 测试近战单位战斗(Noob vs Noob)
13. 测试不同等级战斗(1级 vs 2级)
14. 测试多兵种混战
15. 测试战斗结束判定
16. 测试战场清理
17. 测试多玩家同时战斗(如果可能)

【后续优化】
18. 添加远程单位及弹道系统测试
19. 优化AI性能(批量更新而非每个兵种独立)
20. 添加攻击动画播放
21. 添加死亡动画播放
22. 添加战斗音效
23. 添加血条显示


【9.12 技术要点】
----------------------------------

1. 性能优化
   - 使用对象池管理弹道
   - AI批量更新而非每个兵种独立循环
   - 使用RunService.Heartbeat统一更新
   - 定期清理无效数据

2. 多战斗支持
   - 使用BattleId隔离不同战斗
   - 每个战斗实例独立管理兵种列表
   - 通过PlayerId关联玩家和战斗

3. 死亡通知机制
   - 使用BindableEvent在服务端内部通知
   - 攻击者监听UnitDeath事件
   - 收到通知后立即重新寻找目标

4. 寻路与移动
   - 优先使用Humanoid:MoveTo简单移动
   - 遇到障碍物时使用PathfindingService
   - 超时后重新寻路或切换目标

5. 碰撞检测
   - 使用PhysicsService管理碰撞组
   - 弹道通过Touched事件检测碰撞
   - 只与目标碰撞,忽略其他单位

6. 状态同步
   - 战斗逻辑完全在服务端
   - 客户端只负责UI和观察
   - 可选的状态更新事件用于UI显示

=====================================================
V1.5 战斗系统设计完成
=====================================================
]]