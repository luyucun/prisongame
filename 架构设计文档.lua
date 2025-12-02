--[[
=====================================================
游戏整体架构设计文档
=====================================================

项目名称: Roblox 兵种塔防游戏
当前版本: V3.1
最后更新: 2025-12-01

=====================================================
一、架构设计原则
=====================================================

1. 客户端-服务端分离架构
   - 服务端: 数据管理、权威验证、游戏逻辑
   - 客户端: UI显示、用户交互、渲染表现

2. 模块化设计
   - 独立封装、事件通信、易于扩展

3. 数据驱动
   - 配置表驱动、统一管理、实时同步

4. 性能优化
   - AI节流、批量更新、资源预加载

=====================================================
二、目录结构
=====================================================

ServerScriptService/
├── Core/
│   ├── DataManager.lua          (数据管理 V2.8增强)
│   └── PlayerManager.lua        (玩家管理)
├── Systems/
│   ├── CurrencySystem.lua       (货币系统)
│   ├── HomeSystem.lua           (基地系统)
│   ├── InventorySystem.lua      (背包系统)
│   ├── PlacementSystem.lua      (放置系统)
│   ├── MergeSystem.lua          (合成系统)
│   ├── PhysicsManager.lua       (物理管理)
│   ├── BattleManager.lua        (战斗管理 V2.4增强)
│   ├── CombatSystem.lua         (战斗系统 V2.5增强)
│   ├── UnitAI.lua               (兵种AI V2.10增强)
│   ├── ProjectileSystem.lua     (弹道系统)
│   ├── HitboxService.lua        (碰撞判定)
│   ├── UnitManager.lua          (单位索引)
│   ├── WeaponEffectSystem.lua   (武器特效)
│   ├── BattleTestSystem.lua     (战斗测试)
│   ├── GMCommandSystem.lua      (GM命令)
│   ├── PathService.lua          (寻路服务 V2.7增强)
│   ├── StageService.lua         (关卡服务 V2.8章节系统)
│   ├── GridPositionSystem.lua   (网格坐标系统)
│   ├── CampaignManager.lua      (战役管理器 V2.11增强)
│   ├── CampaignUnitHelper.lua   (战役单位辅助)
│   ├── DoorControlService.lua   (门控制服务 V2.0新增)
│   ├── ShopSystem.lua           (商店系统 V2.1新增 V3.1增强)
│   ├── IdleCoinSystem.lua       (挂机金币系统 V2.6新增)
│   ├── HouseUpgradeSystem.lua   (房屋升级系统 V2.8新增)
│   ├── SkillSystem.lua          (技能系统 V3.0新增)
│   └── SkillShopSystem.lua      (技能商店系统 V3.1新增)

StarterPlayer/StarterPlayerScripts/
├── UI/
│   ├── CoinDisplay.lua          (金币显示)
│   ├── BackpackDisplay.lua      (背包显示)
│   ├── ShopDisplay.lua          (商店显示 V2.1新增)
│   ├── BattleTestUI.lua         (战斗测试UI)
│   ├── BattleControlUI.lua      (战斗控制UI V2.0新增)
│   ├── DamageNumberSystem.lua   (伤害冒字系统 V2.5增强)
│   ├── SkillBackpackDisplay.lua (技能背包显示 V3.0新增)
│   └── SkillShopDisplay.lua     (技能商店显示 V3.1新增)
├── Controllers/
│   ├── PlacementController.lua  (放置控制)
│   ├── DragSystem.lua           (拖动系统)
│   ├── RemovalController.lua    (回收控制)
│   ├── CameraController.lua     (战斗相机控制 V2.11增强)
│   ├── IdleCoinController.lua   (挂机金币控制 V2.6新增)
│   ├── MainGuiController.lua    (主界面控制 V2.11新增)
│   └── SkillController.lua      (技能控制器 V3.0新增)
├── Triggers/                        (V3.1新增)
│   └── SkillShopTrigger.lua     (技能商店触发器 V3.1新增)
├── Utils/
│   ├── PlacementHelper.lua      (放置辅助)
│   ├── HighlightHelper.lua      (高光辅助)
│   ├── GridHelper.lua           (网格辅助)
│   ├── HealthBarController.lua  (血条控制 V2.3新增)
│   ├── HealthBarEventHandler.lua(血条事件处理 V2.3新增)
│   ├── VictoryUIController.lua  (结算界面控制 V2.4新增)
│   ├── MergeEffectController.lua(合成特效控制)
│   ├── LevelDisplayHelper.lua   (等级显示辅助)
│   ├── ButtonEffectHelper.lua   (按钮特效辅助)
│   ├── CoinAnimationHelper.lua  (金币动画辅助)
│   └── UIEffectController.lua   (UI特效控制)
├── AnimationPreloader.lua       (动画预加载)
└── IconPreloader.lua            (图标预加载 V2.1新增)

ReplicatedStorage/
├── Config/
│   ├── GameConfig.lua           (游戏配置 V2.8增强)
│   ├── UnitConfig.lua           (兵种配置)
│   ├── PlacementConfig.lua      (放置配置)
│   ├── BattleConfig.lua         (战斗配置)
│   ├── ShopConfig.lua           (商店配置 V2.1新增)
│   ├── StageConfig.lua          (关卡配置 V2.8章节系统)
│   ├── EnemyConfig.lua          (敌人配置)
│   ├── HouseConfig.lua          (房屋配置 V2.8新增)
│   ├── LevelColorConfig.lua     (等级颜色配置)
│   ├── SkillConfig.lua          (技能配置 V3.0新增 V3.1增强)
│   └── SkillShopConfig.lua      (技能商店配置 V3.1新增)
├── Events/                      (RemoteEvent事件)
│   ├── CurrencyEvents/
│   ├── PlayerEvents/
│   ├── InventoryEvents/
│   ├── PlacementEvents/
│   ├── MergeEvents/
│   ├── BattleEvents/            (V2.3-V2.5增强)
│   ├── CampaignEvents/          (V2.0新增)
│   ├── ShopEvents/              (V2.1新增)
│   ├── IdleCoinEvents/          (V2.6新增)
│   ├── BattleControlEvents/     (V2.11新增)
│   ├── SkillEvents/             (V3.0新增)
│   └── SkillShopEvents/         (V3.1新增)
└── Modules/
    └── FormatHelper.lua         (格式化工具)

=====================================================
三、核心系统概览
=====================================================

【3.1 数据管理】DataManager
- 玩家数据加载/保存
- 初始金币: 100
- 支持DataStore持久化
- V2.6新增: 挂机金币数据管理
- V2.8新增: 章节进度/房屋等级数据

【3.2 玩家管理】PlayerManager
- 6个基地随机分配
- 玩家进入/离开管理
- 基地占用状态维护

【3.3 货币系统】CurrencySystem
- 金币增减、验证
- 通过RemoteEvent通知客户端
- 战斗/挂机/购买接口

【3.4 背包系统】InventorySystem
- 兵种存储管理
- 数量增减
- 客户端实时同步

【3.5 放置系统】PlacementSystem
- 服务端验证放置合法性
- 网格吸附(4x4 studs)
- 碰撞检测(GridRed/GridGreen)
- V2.8: 支持多格占地单位(GridWidth/GridDepth)

【3.6 合成系统】MergeSystem
- 相同ID+相同等级 → 升级
- 等级上限: 3级
- 等级系数: 1级=1.0, 2级=1.2, 3级=1.5

【3.7 战斗管理】BattleManager
- 管理多个战斗实例(支持6玩家并发)
- 战斗状态: Preparing/Fighting/Finished
- 战场清理机制
- V2.4: 战斗结算弹窗机制

【3.8 战斗系统】CombatSystem
- 攻击阶段状态机: Idle → Attacking → Recovery
- 动画事件驱动("Damage" Marker)
- 伤害计算: 攻击力 × 等级 × 等级系数
- 死亡流程: 停止AI → 播放死亡动画 → 冻结尸体
- V2.5: 阵营颜色伤害数字

【3.9 兵种AI】UnitAI
- AI状态机: SEEKING → MOVING → ATTACKING
- AI节流: 0.2秒批量更新
- 寻敌优化: UnitManager分组索引
- 显式动画状态管理
- V2.10: 移动动画控制/透明度重置

【3.10 碰撞判定】HitboxService
- 服务端权威的近战命中判定
- OverlapParams + 扇形角度过滤
- 同帧去重机制
- 替代不稳定的Touched事件

【3.11 单位索引】UnitManager
- 按battleId和team分组
- 高效寻敌: O(敌方单位数)而非O(所有单位数)
- 位置缓存减少实例访问

【3.12 弹道系统】ProjectileSystem
- 远程单位弹道管理
- 追踪目标(跟踪炮弹)
- 仅与目标碰撞(穿透友军)

【3.13 武器特效】WeaponEffectSystem
- 远程武器发射特效
- Beam(0.1秒) + PointLight(0.1秒) + ParticleEmitter(0.5秒)
- 快速攻击时强制重置
- 容错设计(特效缺失不影响战斗)

【3.14 动画预加载】AnimationPreloader
- 客户端启动时预加载所有战斗动画
- 使用ContentProvider:PreloadAsync
- 解决首场战斗"傻站"卡顿问题

【3.15 商店系统】ShopSystem (V2.1新增)
- 数据驱动的商店配置(ShopConfig)
- 库存系统(每种商品限购数量)
- 定时刷新机制
- 购买锁防止并发购买

【3.16 挂机金币系统】IdleCoinSystem (V2.6新增)
- 计算玩家离线期间产生的金币
- ProximityPrompt交互领取
- Mail模型金币数量显示
- 登出时记录时间戳

【3.17 房屋升级系统】HouseUpgradeSystem (V2.8新增)
- 根据通关章节替换房屋模型
- 保持House文件夹结构
- 从ReplicatedStorage/House加载模板

【3.18 血条系统】HealthBarController (V2.3新增)
- 战斗时挂载血条,隐藏等级显示
- 根据阵营显示不同颜色(我方绿/敌方红)
- 实时更新血量
- 战斗结束恢复等级显示

【3.19 战斗结算系统】VictoryUIController (V2.4新增)
- 战斗结束显示结算弹窗
- 玩家确认后完成清理流程
- 支持胜利/失败不同显示

【3.20 伤害冒字系统】DamageNumberSystem (V2.5增强)
- 受伤单位显示伤害数字
- 数字向上移动并淡出
- V2.5: 阵营颜色区分(我方白/敌方红)

【3.21 战斗相机控制】CameraController (V2.10/V2.11)
- 战斗期间相机锁定战场
- 跟随队伍质心移动
- V2.10: 战斗特写模式
- V2.11: 解锁镜头功能(UnlockToPlayer)

【3.22 主界面控制】MainGuiController (V2.11新增)
- 战斗期间显示控制按钮
- ReturnToHome: 传送回家园
- UnlockMove: 解锁镜头跟随

【3.23 门控制服务】DoorControlService (V2.0新增)
- 基地大门开关动画
- 状态机: CLOSED ↔ OPENING → OPEN ↔ CLOSING → CLOSED
- 1秒TweenService动画

【3.24 技能系统】SkillSystem (V3.0新增)
- 管理玩家技能背包数据
- 处理技能释放请求和验证
- 计算技能伤害并应用效果
- 支持即时伤害(INSTANT)和持续伤害(DOT)
- 与战斗系统(CombatSystem)集成
- 技能特效生成和同步

【3.25 技能配置】SkillConfig (V3.0新增)
- 数据驱动的技能配置表
- 技能类型: DAMAGE(伤害)/HEALING(治疗)/BUFF(增益)
- 效果类型: INSTANT(即时)/DOT(持续伤害)/HOT(持续治疗)
- 目标类型: ENEMY(敌方)/ALLY(友方)/SELF(自身)/ALL(全体)
- 可扩展设计,便于添加新技能

【3.26 技能控制器】SkillController (V3.0新增)
- 客户端技能释放输入处理
- 技能预览圆圈(SkillPreview)显示
- 支持PC端(鼠标)和移动端(触屏)
- 瞄准模式: 显示预览 → 左键确认/右键取消

【3.27 技能背包显示】SkillBackpackDisplay (V3.0新增)
- 管理技能背包UI显示
- 动态创建技能图标列表
- 战斗开始时显示,战斗结束时隐藏
- 与CampaignStateUpdate事件集成

=====================================================
四、版本历史
=====================================================

【V1.0】基础架构
- 货币系统、玩家管理、基地分配

【V1.1】兵种定义
- 兵种配置表、背包系统、GM命令获取兵种

【V1.2】兵种放置
- 网格吸附、拖放操作、边界检测、高光预览

【V1.3】兵种回收
- 回收模式、点击回收、自动退出

【V1.4】兵种属性与合成
- 属性系统(攻击/血量/速度)
- 等级系统(1-3级)
- 拖动合成、等级显示(Lv.X)
- 拖动换位

【V1.5】战斗系统核心
- BattleManager: 多战斗实例管理
- CombatSystem: 伤害计算、血量管理
- UnitAI: 寻敌、移动、攻击
- ProjectileSystem: 远程弹道
- HitboxService: 服务端权威命中判定
- UnitManager: 单位分组索引
- WeaponEffectSystem: 远程武器特效
- AnimationPreloader: 客户端动画预加载

【V2.0】战役系统
- CampaignManager: 战役流程管理
- CampaignUnitHelper: 战役单位辅助
- StageService: 动态关卡生成
- GridPositionSystem: 网格坐标系统
- PathService增强: 批量寻路+回调
- DoorControlService: 基地大门控制
- BattleControlUI: 战斗控制界面

【V2.1】商店系统
- ShopSystem: 商店核心逻辑
- ShopConfig: 商店配置表
- ShopDisplay: 商店UI显示
- ShopTrigger: 商店触发器
- 库存系统: 限购+定时刷新
- IconPreloader: 商品图标预加载

【V2.3】血条系统
- HealthBarController: 血条显示控制
- HealthBarEventHandler: 血条事件处理
- HpTemplate: 血条UI模板
- 战斗时显示血条,结束时恢复等级

【V2.4】战斗结算系统
- VictoryUIController: 结算界面控制
- Victory UI: 结算弹窗界面
- VictoryPopup/VictoryConfirm事件
- 玩家确认后完成战役清理

【V2.5】伤害显示增强
- DamageNumberSystem增强: 阵营颜色
- CombatSystem增强: 传递攻击者阵营
- 我方打敌方白字,敌方打我方红字

【V2.6】挂机金币系统
- IdleCoinSystem: 挂机金币计算
- IdleCoinController: 客户端控制
- Mail模型: 金币显示+ProximityPrompt
- DataManager: 登出时间记录

【V2.7】寻路系统增强
- PathService: 战场中心参数
- 行军到达判定优化
- 卡住检测与重新规划

【V2.8】章节系统
- StageConfig: 章节配置
- DataManager: 章节进度数据
- HouseUpgradeSystem: 房屋升级
- HouseConfig: 房屋配置
- CampaignManager: 章节奖励计算

【V2.10】相机系统增强
- CameraController: 战斗相机控制
- 战斗特写模式(SetCombatMode)
- 跟随模式(SetFollowMode)
- 角色自动跟随战场

【V2.11】战斗控制按钮
- MainGuiController: 主界面按钮控制
- ReturnToHome按钮: 传送回家园
- UnlockMove按钮: 解锁镜头跟随
- CameraController.UnlockToPlayer: 解锁镜头
- CampaignManager.ReturnToHome: 传送功能
- BattleControlEvents: 新增事件文件夹

【V3.0】技能系统
- SkillConfig: 技能配置表(数据驱动)
- SkillSystem: 服务端技能处理系统
- SkillController: 客户端技能控制器
- SkillBackpackDisplay: 技能背包UI显示
- 技能类型: 即时伤害/持续伤害(DOT)
- 技能范围: AOE圆形范围(直径=Range)
- 技能背包: 玩家技能存储与消耗
- GM命令: /addskill /removeskill /listskills /skilllist
- 初始技能: 喷水枪(1001)/毒气炸弹(1002)/大火(1003)

【V3.1】技能商店系统
- SkillShopConfig: 技能商店配置表(数据驱动)
- SkillShopSystem: 服务端技能商店系统
- SkillShopDisplay: 客户端技能商店UI显示
- SkillShopTrigger: 技能商店NPC距离触发器
- SkillConfig增强: 新增DevProductId字段(Robux购买)
- ShopSystem增强: 共享刷新周期(与兵种商店同步)
- 库存系统: 概率刷新/库存上限/售罄机制
- 支持金币购买和Robux购买(MarketplaceService)
- 技能商店NPC: KeepShoper02

=====================================================
五、核心技术要点
=====================================================

【5.1 客户端-服务器职责划分】
客户端:
- 渲染资源预加载(ContentProvider)
- UI显示和交互
- 动画/特效播放

服务器:
- 游戏逻辑和数据管理
- 权威验证和判定
- Track预缓存(加速LoadAnimation)

【5.2 动画系统设计】
- 客户端预加载: 避免首场卡顿
- 动画事件驱动: "Damage" Marker精确命中
- 回退机制: 动画失败时用延迟模拟
- 优先级管理: 死亡动画Action4最高优先级

【5.3 战斗系统优化】
- 服务端权威: HitboxService替代Touched
- AI节流: 0.2秒批量更新
- 分组索引: UnitManager按team分组
- 攻击状态机: Idle → Attacking → Recovery

【5.4 性能优化策略】
- 批量更新: RunService.Heartbeat统一驱动
- 位置缓存: 减少HumanoidRootPart访问
- 死亡清理: 立即从索引移除
- 资源预加载: 启动时完成

【5.5 碰撞判定原则】
近战:
- OverlapParams范围查询
- 扇形角度过滤(Vector3.Dot)
- 同帧去重(LastHitFrame)
- 友军碰撞忽略(PhysicsService)

远程:
- 弹道Part + Touched事件
- 仅与目标碰撞(CanCollide设置)
- 追踪目标(跟踪炮弹)

【5.6 容错设计】
- 所有操作包裹pcall
- 资源缺失降级处理
- 预加载失败不阻止游戏
- 详细的调试日志

=====================================================
六、配置表结构
=====================================================

【GameConfig】游戏常量
- 初始金币: 100
- 最大玩家数: 6
- 日志前缀
- V2.6: 挂机金币配置(每小时收益/上限)
- V2.8: 章节系统配置

【UnitConfig】兵种配置
- 基础属性: Health/Attack/AttackSpeed/AttackRange/MoveSpeed
- 动画ID: Idle/Move/Attack/Death/Show
- 战斗配置: CombatProfile(碰撞判定参数)
- 远程配置: ProjectileSpeed/ProjectileModelPath
- 武器配置: WeaponName
- V2.8: GridWidth/GridDepth(多格占地)

【PlacementConfig】放置配置
- 网格大小: 4x4 studs
- IdleFloor尺寸: 120x1x120
- 边界限制参数
- V2.8: GridToWorld坐标转换

【BattleConfig】战斗配置
- AI更新间隔: 0.2秒
- 碰撞判定参数
- 攻击超时: 5秒
- 弹道配置
- 武器特效时长

【ShopConfig】商店配置 (V2.1新增)
- 商店列表: ShopId/商品配置
- 商品属性: UnitId/Price/Stock
- 刷新时间: RefreshInterval

【StageConfig】关卡配置 (V2.8章节系统)
- 章节列表: Chapters
- 章节属性: StagesPerChapter/Style/Rewards
- 关卡奖励: Coins

【EnemyConfig】敌人配置
- 关卡敌人: [StageNum] = {敌人列表}
- 敌人属性: UnitId/Position/Level

【HouseConfig】房屋配置 (V2.8新增)
- 房屋等级: HouseLevels
- 升级条件: RequiredChapters
- 模型路径: ModelPath

【LevelColorConfig】等级颜色配置
- 等级颜色: [Level] = Color3

【SkillConfig】技能配置 (V3.0新增 V3.1增强)
- 技能列表: [SkillId] = 技能配置
- 技能属性: Name/ResourceName/Icon/SkillType/EffectType/TargetType
- 伤害属性: Range(直径)/Damage(即时)/TickDamage(DOT)/Duration/TickInterval
- 特效属性: EffectDuration
- V3.1新增: DevProductId(开发者商品ID，用于Robux购买)
- 公共接口: GetSkillById()/IsValidSkill()/GetAllSkillIds()/IsDOTSkill()
- V3.1新增: GetDevProductId()/HasRobuxPurchase()

【SkillShopConfig】技能商店配置 (V3.1新增)
- 商店列表: Shops[shopId] = 商店配置
- 商店属性: Name/NPCName/RefreshInterval/Items
- 商品属性: SkillId/Price/RobuxPrice/Sort/Enabled
- 库存配置: StockMin/StockMax/RefreshProbability
- 公共接口: GetShopItems()/GetPrice()/IsSkillOnSale()/GetStockConfig()

=====================================================
七、RemoteEvent事件列表
=====================================================

【CurrencyEvents】
- UpdateCurrency: Server → Client (金币变化)

【InventoryEvents】
- InventoryRefresh: Server → Client (背包刷新)
- RequestInventory: Client → Server (请求背包)
- UnitUpdated: Server → Client (兵种更新)
- RequestUnitInstance: Client → Server (请求可放置实例)
- UnitInstanceResponse: Server → Client (返回实例信息)

【PlacementEvents】
- StartPlacement: Client → Server (开始放置)
- ConfirmPlacement: Client → Server (确认放置)
- CancelPlacement: Client → Server (取消放置)
- PlacementResponse: Server → Client (放置结果)
- RemoveUnit: Client → Server (回收兵种)
- RemoveResponse: Server → Client (回收结果)
- UpdatePosition: Client → Server (更新位置)
- UpdateResponse: Server → Client (位置更新结果)

【MergeEvents】
- RequestMerge: Client → Server (请求合成)
- MergeResponse: Server → Client (合成结果)

【BattleEvents】
- RequestBattleTest: Client → Server (请求战斗测试)
- BattleTestResponse: Server → Client (战斗测试结果)
- BattleStateUpdate: Server → Client (战斗状态更新)
- UnitDeath: BindableEvent (服务端内部死亡通知)
- ShowDamageNumber: Server → Client (显示伤害数字)
- UnitHealthUpdate: Server → Client (单位血量更新) V2.3
- AttachHealthBars: Server → Client (挂载血条) V2.3
- DetachHealthBars: Server → Client (移除血条) V2.3
- VictoryPopup: Server → Client (结算弹窗) V2.4
- VictoryConfirm: Client → Server (确认结算) V2.4

【CampaignEvents】V2.0
- RequestStartCampaign: Client → Server (开始战役)
- RequestRetreat: Client → Server (请求撤退)
- CampaignStateUpdate: Server → Client (战役状态更新)
- StageProgress: Server → Client (关卡进度更新)
- LockHomeOperations: Server → Client (锁定/解锁基地)

【ShopEvents】V2.1
- RequestShopList: Client → Server (请求商店列表)
- ShopList: Server → Client (返回商品数据)
- PurchaseUnit: Client → Server (请求购买)
- PurchaseResult: Server → Client (购买结果)
- StockUpdate: Server → Client (库存更新)
- RefreshTimeUpdate: Server → Client (刷新倒计时)

【IdleCoinEvents】V2.6
- CollectIdleCoins: Client → Server (领取挂机金币)
- SyncIdleCoins: Server → Client (同步金币数量)

【BattleControlEvents】V2.11
- ReturnToHome: Client → Server (传送回家园)

【SkillEvents】V3.0
- RequestCastSkill: Client → Server (请求释放技能: skillId, position)
- CastSkillResponse: Server → Client (释放结果: success, message)
- SkillInventoryUpdate: Server → Client (技能背包更新: inventory)
- SpawnSkillEffect: Server → Client (生成技能特效: skillId, position, duration)

【SkillShopEvents】V3.1
- RequestSkillShopList: Client → Server (请求技能商店列表)
- SkillShopList: Server → Client (返回技能商品数据数组)
- PurchaseSkill: Client → Server (请求购买技能: skillId)
- SkillPurchaseResult: Server → Client (购买结果: success, message, skillId, newCoins)
- SkillStockUpdate: Server → Client (技能库存更新: shopId, stockData)
- SkillRefreshTimeUpdate: Server → Client (刷新倒计时: remainingTime)

=====================================================
八、最佳实践
=====================================================

1. 总是在客户端预加载渲染资源
   - 动画、音效、粒子特效
   - 使用ContentProvider:PreloadAsync
   - 在游戏启动时完成,而非战斗开始时

2. 服务器端权威验证
   - 所有游戏逻辑判定在服务器
   - 客户端仅负责显示和输入
   - 防止作弊和网络延迟问题

3. 性能优化原则
   - 批量更新而非逐个处理
   - 数据缓存减少实例访问
   - 及时清理无效对象

4. 容错与降级
   - 预加载失败不阻止游戏
   - 资源缺失提供降级方案
   - 详细日志便于调试

5. 分离关注点
   - 客户端负责表现层
   - 服务器负责逻辑层
   - 清晰划分职责边界

6. 数据驱动设计
   - 配置表驱动游戏内容
   - 便于扩展和调整
   - 减少硬编码

=====================================================
九、故障排查指南
=====================================================

【动画卡顿问题】
症状: 首场战斗"傻站"
排查:
1. 确认AnimationPreloader.lua在StarterPlayerScripts下
2. 检查客户端日志: "✅ 预加载完成"
3. 确认预加载在战斗开始前完成
4. 验证动画ID配置正确

【AI不移动/不攻击】
排查:
1. 检查UnitManager是否正确注册单位
2. 确认FindNearestEnemy返回有效目标
3. 验证攻击距离和移动速度配置
4. 检查BattleId是否匹配

【近战不造成伤害】
排查:
1. 确认HitboxService.ResolveMeleeHit被调用
2. 检查CombatProfile配置(半径/角度/高度)
3. 验证"Damage"动画事件存在
4. 检查服务器日志中的命中判定

【远程不发射子弹】
排查:
1. 确认WeaponName配置正确
2. 检查ProjectileSpeed > 0
3. 验证武器模型存在
4. 检查弹道创建日志

【特效不播放】
排查:
1. 确认武器下有Effect Part
2. 检查Beam/PointLight/ParticleEmitter存在
3. 验证WeaponEffectSystem被初始化
4. 开启DEBUG_WEAPON_EFFECTS查看日志

=====================================================
十、开发注意事项
=====================================================

1. 动画ID必须为纯数字字符串
2. UnitConfig必须在ReplicatedStorage(客户端可访问)
3. 所有RemoteEvent必须预先创建在ReplicatedStorage
4. 战斗测试时使用V键打开测试UI
5. 兵种模型必须包含Humanoid和HumanoidRootPart
6. 死亡动画优先级必须最高(Action4)
7. 客户端预加载是解决动画卡顿的唯一正确方案
8. 服务器端ContentProvider对客户端无效

=====================================================
十一、V2.0-V2.11 新增系统详解
=====================================================

【11.1 战役系统】CampaignManager (V2.0)
职责：管理玩家战役流程
状态机：IDLE → PREPARING → MARCHING → PREPARE_BATTLE → FIGHTING → VICTORY/DEFEAT → CLEANUP

核心API：
- StartCampaign(player)           启动战役
- MarchToStage(campaignData, n)   行军到关卡
- BeginBattlePrep(...)            准备战斗
- StartStageBattle(...)           开始战斗
- OnBattleEnd(...)                战斗结束处理
- OnVictory/OnDefeat(...)         胜利/失败处理
- RespawnUnits(...)               单位复生
- ReturnToHome(player)            传送回家园 (V2.11)

【11.2 关卡服务】StageService (V2.0/V2.8)
职责：动态生成和管理关卡

核心API：
- GetOrCreateStage(playerId, n)   获取或创建关卡
- GenerateStage(playerId, n)      生成新关卡
- LoadEnemyData(stage, n)         加载敌人配置
- CleanupStages(playerId)         清理关卡
- SetAirWallState(stage, enabled) 设置空气墙

【11.3 商店系统】ShopSystem (V2.1)
职责：商店购买与库存管理

核心API：
- Initialize()                    初始化商店
- GetShopList(player, shopId)     获取商品列表
- PurchaseUnit(player, unitId)    购买兵种
- GetPlayerStock(player, shopId)  获取玩家库存
- RefreshStock(player, shopId)    刷新库存

【11.4 挂机金币系统】IdleCoinSystem (V2.6)
职责：离线收益计算与领取

核心API：
- Initialize()                    初始化系统
- CalculateIdleCoins(player)      计算挂机金币
- CollectIdleCoins(player)        领取金币
- UpdateMailDisplay(homeId, coins) 更新显示

【11.5 房屋升级系统】HouseUpgradeSystem (V2.8)
职责：根据章节进度升级房屋

核心API：
- Initialize()                    初始化系统
- OnChapterCompleted(player, ch)  章节完成时检查升级
- UpgradeHouse(player, level)     升级房屋
- GetHouseLevel(player)           获取当前等级

【11.6 血条系统】HealthBarController (V2.3)
职责：战斗时显示单位血条

核心API：
- AttachHealthBar(unitModel)      挂载血条
- DetachHealthBar(unitModel)      移除血条
- UpdateHealthBar(unit, hp, max)  更新血量
- ApplyTeamColor(unit, bar)       应用阵营颜色

【11.7 战斗相机】CameraController (V2.10/V2.11)
职责：战斗期间相机控制

核心API：
- Start(allies, enemies)          开始相机锁定
- Stop()                          停止相机锁定
- SetCombatMode()                 战斗特写模式
- SetFollowMode()                 跟随模式
- UnlockToPlayer()                解锁镜头 (V2.11)

全局访问：_G.BattleCameraController

【11.8 主界面控制】MainGuiController (V2.11)
职责：战斗期间按钮显示控制

功能：
- 监听CampaignStateUpdate事件
- 战斗时显示ReturnToHome/UnlockMove按钮
- 战斗结束时隐藏按钮
- 处理按钮点击事件

【11.9 技能系统】SkillSystem (V3.0新增)
职责：服务端技能处理

核心API：
- Initialize()                    初始化技能系统
- HandleCastSkillRequest(player, skillId, position)  处理释放请求
- AddSkill(player, skillId, count)  添加技能
- GetSkillCount(player, skillId)    获取技能数量
- GetPlayerSkills(player)           获取技能背包
- SyncSkillInventory(player)        同步背包到客户端
- SendCastResponse(player, success, message)  发送释放结果

内部机制：
- DOT效果管理(ActiveDOTEffects表)
- Heartbeat驱动DOT伤害tick
- 技能冷却(0.5秒)
- 延迟加载DataManager/CombatSystem/UnitManager避免循环依赖

【11.10 技能控制器】SkillController (V3.0新增)
职责：客户端技能输入处理

核心API：
- Initialize()                    初始化控制器
- StartSkillCast(skillId)         开始释放技能(由UI调用)
- CancelAiming()                  取消瞄准
- IsAiming()                      检查是否在瞄准
- GetCurrentSkillId()             获取当前技能ID

内部机制：
- 创建SkillPreview圆柱体显示范围
- RenderStepped更新预览位置
- 射线检测地面位置
- 支持鼠标/触屏/ESC输入

全局访问：_G.SkillController

【11.11 技能背包显示】SkillBackpackDisplay (V3.0新增)
职责：技能背包UI管理

核心API：
- Initialize()                    初始化显示
- Refresh(inventory)              刷新背包
- Show()                          显示背包
- Hide()                          隐藏背包
- GetSkillCount(skillId)          获取技能数量

内部机制：
- 从SkillTemplate克隆技能图标
- 监听SkillInventoryUpdate事件
- 监听CampaignStateUpdate事件(战斗时显示)
- 点击图标调用SkillController.StartSkillCast()

全局访问：_G.SkillBackpackDisplay

【11.12 技能商店系统】SkillShopSystem (V3.1新增)
职责：服务端技能商店处理

核心API：
- Initialize()                    初始化技能商店系统
- InitializePlayerSkillShopTimer(player, shopId)  初始化玩家商店定时器
- OnPurchaseSkill(player, skillId)  处理购买请求
- RefreshSkillShopStock(player, shopId)  刷新库存
- GetPlayerStock(player, shopId, skillId)  获取库存
- DeductStock(player, shopId, skillId, amount)  扣除库存

内部机制：
- 库存数据持久化(DataManager，使用"Skill_"+shopId前缀)
- 概率刷新机制(RefreshProbability)
- 刷新定时器(与兵种商店共享周期)
- 购买锁防止并发购买
- Robux购买支持(MarketplaceService)

【11.13 技能商店显示】SkillShopDisplay (V3.1新增)
职责：客户端技能商店UI管理

核心API：
- Initialize()                    初始化显示系统
- RequestShopList()               请求商店列表
- GetShopData()                   获取当前商店数据
- Cleanup()                       清理商店显示

内部机制：
- 从SkillCardTemplate克隆技能卡片
- 监听SkillShopList/SkillPurchaseResult事件
- 监听SkillStockUpdate/SkillRefreshTimeUpdate事件
- 卡片点击展开购买按钮(BuyButtonFrame)
- 标题显示刷新倒计时

【11.14 技能商店触发器】SkillShopTrigger (V3.1新增)
职责：客户端技能商店NPC距离检测

核心API：
- Initialize()                    初始化触发器
- Stop()                          停止触发器
- OpenShop()                      手动打开商店
- CloseShop()                     手动关闭商店
- IsNearShop()                    获取当前状态

内部机制：
- Heartbeat循环检测玩家与NPC距离
- 使用GameConfig.Shop.OpenDistance判定
- 进入范围自动打开商店UI
- 离开范围自动关闭商店UI
- 技能商店NPC名称：KeepShoper02

=====================================================
十二、核心数据结构
=====================================================

【campaignData】战役数据
```lua
{
    PlayerId = number,
    Player = Player,
    HomeId = number,
    CurrentStage = number,
    TotalStages = number,
    CurrentChapter = number,        -- V2.8
    State = CampaignState,
    Units = {
        [unitModel] = {
            Instance = Model,
            InstanceId = string,    -- V2.8
            UnitId = string,
            Level = number,
            GridX = number,         -- V2.8
            GridZ = number,         -- V2.8
            GridWidth = number,     -- V2.8
            GridDepth = number,     -- V2.8
            CurrentHP = number,
            MaxHP = number,
            IsDead = boolean,
            IsActivated = boolean,
            LastKnownPosition = Vector3?,
            LastBattleId = string?,
        }
    },
    CurrentBattleId = string?,
    CurrentMoveId = string?,
    PendingBattleResult = table?,   -- V2.4
    IsWaitingForConfirm = boolean?, -- V2.4
    IsVictory = boolean?,           -- V2.4
    PlayerMoveBackup = table?,      -- 玩家移动备份
}
```

【PlayerData】玩家数据 (DataManager)
```lua
{
    Coins = number,
    Inventory = {[unitId] = count},
    PlacedUnits = {放置数据},
    LastLogoutTime = number,        -- V2.6
    PendingIdleCoins = number,      -- V2.6
    CompletedChapters = number,     -- V2.8
    CurrentChapter = number,        -- V2.8
    HouseLevel = number,            -- V2.8
    SkillInventory = {[skillId] = count},  -- V3.0
    ShopData = {                    -- V2.1/V3.1 商店库存数据
        [shopId] = {                -- 兵种商店数据 (V2.1)
            LastRefreshTime = number,
            Stock = {[unitId] = count},
        },
        ["Skill_" + shopId] = {     -- 技能商店数据 (V3.1)
            LastRefreshTime = number,
            Stock = {[skillId] = count},
        },
    },
}
```

=====================================================
十三、开发注意事项
=====================================================

1. 动画ID必须为纯数字字符串
2. UnitConfig必须在ReplicatedStorage(客户端可访问)
3. 所有RemoteEvent必须预先创建在ReplicatedStorage
4. 战斗测试时使用V键打开测试UI
5. 兵种模型必须包含Humanoid和HumanoidRootPart
6. 死亡动画优先级必须最高(Action4)
7. 客户端预加载是解决动画卡顿的唯一正确方案
8. 服务器端ContentProvider对客户端无效
9. V2.8+: 多格占地单位需配置GridWidth/GridDepth
10. V2.11+: 战斗按钮需在MainGui下创建ReturnToHome/UnlockMove
11. V3.0+: 技能背包UI需按指定结构创建(SkillBackpackGui/BackpackFrame/ItemListFrame/SkillTemplate)
12. V3.0+: 新增技能只需在SkillConfig.Skills表中添加配置，无需修改其他代码
13. V3.1+: 技能商店UI需按指定结构创建(SkillStore/StoreBg/ItemContainer/SkillCardTemplate)
14. V3.1+: 技能商店NPC为KeepShoper02，需在各玩家家园下创建
15. V3.1+: 技能商店与兵种商店共享刷新周期，由ShopSystem.InitializePlayerShopTimer同时初始化
16. V3.1+: Robux购买需在Roblox开发者后台配置DevProductId对应的开发者商品

=====================================================
架构设计文档完成
版本: V3.1
最后更新: 2025-12-02
=====================================================
]]
