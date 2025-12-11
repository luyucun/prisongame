--[[
=====================================================
游戏整体架构设计文档
=====================================================

项目名称: Roblox 兵种塔防游戏
当前版本: V3.9.1
最后更新: 2025-12-11

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
│   ├── StageService.lua         (关卡服务 V3.7章节地图替换)
│   ├── GridPositionSystem.lua   (网格坐标系统)
│   ├── CampaignManager.lua      (战役管理器 V2.11增强)
│   ├── CampaignUnitHelper.lua   (战役单位辅助)
│   ├── DoorControlService.lua   (门控制服务 V2.0新增)
│   ├── ShopSystem.lua           (商店系统 V2.1新增 V3.1增强)
│   ├── IdleCoinSystem.lua       (挂机金币系统 V2.6新增)
│   ├── HouseUpgradeSystem.lua   (房屋升级系统 V2.8新增)
│   ├── SkillSystem.lua          (技能系统 V3.0新增)
│   ├── SkillShopSystem.lua      (技能商店系统 V3.1新增)
│   ├── LoadingSystem.lua        (加载系统 V3.2新增)
│   ├── TaskSystem.lua           (任务系统 V3.3新增)
│   ├── GuideSystem.lua          (新手引导系统 V3.5新增)
│   └── SoundSystem.lua          (音效系统 V3.8新增)

StarterPlayer/StarterPlayerScripts/
├── UI/
│   ├── CoinDisplay.lua          (金币显示)
│   ├── BackpackDisplay.lua      (背包显示)
│   ├── ShopDisplay.lua          (商店显示 V2.1新增)
│   ├── BattleTestUI.lua         (战斗测试UI)
│   ├── BattleControlUI.lua      (战斗控制UI V2.0新增)
│   ├── DamageNumberSystem.lua   (伤害冒字系统 V2.5增强)
│   ├── SkillBackpackDisplay.lua (技能背包显示 V3.0新增)
│   ├── SkillShopDisplay.lua     (技能商店显示 V3.1新增)
│   └── TaskDisplay.lua          (任务显示 V3.3新增)
├── Controllers/
│   ├── PlacementController.lua  (放置控制)
│   ├── DragSystem.lua           (拖动系统)
│   ├── RemovalController.lua    (回收控制)
│   ├── CameraController.lua     (战斗相机控制 V2.11增强)
│   ├── IdleCoinController.lua   (挂机金币控制 V2.6新增)
│   ├── MainGuiController.lua    (主界面控制 V2.11新增)
│   ├── SkillController.lua      (技能控制器 V3.0新增)
│   └── GuideController.lua      (引导控制器 V3.5新增)
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
├── LoadingController.lua        (加载控制器 V3.2新增)
├── SoundController.lua          (音效控制器 V3.8新增)
├── AnimationPreloader.lua       (动画预加载 V3.2集成)
└── IconPreloader.lua            (图标预加载 V2.1新增 V3.2集成)

ReplicatedStorage/
├── Config/
│   ├── GameConfig.lua           (游戏配置 V2.8增强)
│   ├── UnitConfig.lua           (兵种配置)
│   ├── PlacementConfig.lua      (放置配置)
│   ├── BattleConfig.lua         (战斗配置)
│   ├── ShopConfig.lua           (商店配置 V2.1新增)
│   ├── StageConfig.lua          (关卡配置 V3.7章节地图替换)
│   ├── EnemyConfig.lua          (敌人配置)
│   ├── HouseConfig.lua          (房屋配置 V2.8新增)
│   ├── LevelColorConfig.lua     (等级颜色配置)
│   ├── SkillConfig.lua          (技能配置 V3.0新增 V3.1增强)
│   ├── SkillShopConfig.lua      (技能商店配置 V3.1新增)
│   ├── TaskConfig.lua           (任务配置 V3.3新增)
│   ├── GuideConfig.lua          (引导配置 V3.5新增)
│   └── SoundConfig.lua          (音效配置 V3.8新增)
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
│   ├── SkillShopEvents/         (V3.1新增)
│   ├── LoadingEvents/           (V3.2新增)
│   ├── TaskEvents/              (V3.3新增)
│   ├── GuideEvents/             (V3.5新增)
│   └── SoundEvents/             (V3.8新增)
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

【3.28 Loading系统】LoadingSystem/LoadingController (V3.2新增)
- 服务端LoadingSystem管理玩家加载状态和进度
- 客户端LoadingController显示Loading界面和预加载资源
- 加载阶段: INIT → DATA_LOADING → HOME_SETUP → SCENE_SETUP → SYNC_DATA → COMPLETE
- 服务端进度权重60%,客户端预加载权重40%
- 客户端预加载内容: 动画/图标/技能图标/Loading背景图
- 随机显示3张Loading背景图之一
- 进度条平滑动画(TweenService)
- 60秒超时保护机制
- 与AnimationPreloader/IconPreloader集成(备份机制)

【3.29 任务系统】TaskSystem/TaskDisplay (V3.3新增)
- 服务端TaskSystem管理任务进度和奖励发放
- 客户端TaskDisplay显示任务UI和处理领取交互
- 任务类型: 购买兵种/布置兵种/购买技能/完成战斗/领取挂机金币
- 线性任务流程: 按顺序完成任务
- 任务进度实时同步到客户端
- 完成任务可领取金币奖励
- 数据持久化(DataManager.TaskData)
- 支持运营更新新任务(自动检测未完成任务)

【3.30 新手引导系统】GuideSystem/GuideController (V3.5新增)
- 服务端GuideSystem管理玩家引导数据和触发逻辑
- 客户端GuideController显示引导箭头和检测到达
- 引导类型: 前往兵种商店(KeepShoper01)/前往挂机邮箱(Mail)
- 触发条件: 首次进入游戏/有挂机金币可领取
- 引导表现: Guide01绑定玩家+Guide02放目标位置+Beam连线
- 数据持久化(DataManager.GuideData)
- GM命令: /triggerguide /resetguide /resetallguides /listguides
- 可扩展设计,便于添加新引导

【3.31 音效系统】SoundSystem/SoundController (V3.8新增)
- 服务端SoundSystem管理音效事件触发
- 客户端SoundController处理音效播放
- BGM类型: Home(通用BGM)/Battle(战斗BGM)
- SFX类型: CoinsTrigger(领取金币)/Victory(胜利)/Merge(合成)/Error(错误)
- BGM切换带有淡入淡出效果(0.5秒TweenService)
- 支持循环BGM和一次性SFX
- 音效资源自动创建到SoundService

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

【V3.2】Loading系统
- LoadingSystem: 服务端加载状态管理
- LoadingController: 客户端Loading界面与预加载
- 加载阶段: INIT/DATA_LOADING/HOME_SETUP/SCENE_SETUP/SYNC_DATA/COMPLETE
- 加载进度: 服务端60%权重 + 客户端40%权重
- Loading UI: 随机背景图/进度条/百分比显示
- 客户端预加载: 动画/图标/技能图标资源
- 超时保护: 60秒客户端超时自动完成
- AnimationPreloader/IconPreloader集成: 备份机制
- LoadingEvents: 新增事件文件夹

【V3.3】任务系统
- TaskConfig: 任务配置表(数据驱动)
- TaskSystem: 服务端任务处理系统
- TaskDisplay: 客户端任务UI显示
- 任务类型: 购买兵种/布置兵种/购买技能/完成战斗/领取挂机金币
- 任务流程: 线性任务，按顺序完成
- 奖励系统: 完成任务领取金币奖励
- 数据持久化: DataManager.TaskData
- 自动检测: 运营更新新任务后自动激活
- TaskEvents: 新增事件文件夹

【V3.4】战斗金币系统
- UnitConfig.KillReward: 每个兵种的基础击杀金币配置
- GetKillReward()/GetKillRewardByLevel(): 击杀金币计算接口
- GameConfig.BattleCoin: 战斗金币配置(AdvanceDistance/AdvanceReward)
- CombatSystem.KillUnit: 杀死敌方单位(Defense)发放击杀金币
- CampaignManager: 前进金币追踪(StartZPosition/MaxAdvancedZ/LastRewardedDistance)
- CalculateBattleCenter(): 计算战场中心(友军质心)
- CheckAndRewardAdvanceCoins(): 检查并发放前进金币

【V3.5】基于速度的卡住检测(行军阶段)
- PathService_v3.lua: MoveUnitsToPositions行军卡住检测重构为基于WalkSpeed
- 检测逻辑: 实际移动距离 < 预期移动距离(WalkSpeed * 0.5s * 50%)
- 时间窗口: 0.5秒检测一次(与单位速度匹配)
- 快速响应: 卡住1次就立即重寻路(无需等待多次确认)
- 优势: 高速单位和低速单位都能准确检测卡住状态
- 关键变量: data.LastStuckCheckPos记录上次位置用于计算实际移动距离

【V3.5】新手引导系统
- GuideConfig: 引导配置表(数据驱动)
- GuideSystem: 服务端引导处理系统
- GuideController: 客户端引导控制器
- 引导类型: 前往兵种商店(SHOP)/前往挂机邮箱(MAIL)
- 触发条件: 首次进入游戏(FIRST_JOIN)/有挂机金币(HAS_IDLE_COINS)
- 引导表现: Guide01绑定玩家躯干+Guide02放目标位置
- 到达检测: 客户端每帧检测距离,到达后通知服务端
- 数据持久化: DataManager.GuideData.CompletedGuides
- GM命令: /triggerguide /resetguide /resetallguides /listguides
- GuideEvents: 新增事件文件夹

【V3.7】章节关卡地图替换
- StageConfig增强: 章节配置新增StageTemplateStyle字段
- StageService增强: SetPlayerChapter()/ClearPlayerChapter()接口
- StageService增强: GetTemplateStyle()根据玩家章节获取模板风格
- CampaignManager增强: StartCampaign时调用StageService.SetPlayerChapter()
- 支持不同章节使用不同风格的关卡模板(如Style01/Style02)
- 关卡模板路径: ReplicatedStorage/StageTemplate/[Style]/StageMiddle|StageEnd

【V3.8】音效系统
- SoundConfig: 音效配置表(数据驱动)
- SoundSystem: 服务端音效事件管理
- SoundController: 客户端音效播放控制
- BGM类型: Home(通用)/Battle(战斗)
- SFX类型: CoinsTrigger/Victory/Merge/Error
- BGM切换: TweenService淡入淡出效果(0.5秒)
- 音效触发点: 玩家加入/战斗开始/战斗结束/结算弹窗/领取金币/合成/购买失败
- SoundEvents: 新增事件文件夹

【V3.9.1】新手引导系统增强
- GuideConfig增强: 新增IDLE_FLOOR/UI_FOCUS引导类型
- GuideSystem增强: 新增HAS_FIRST_UNIT/ARRIVED_IDLE_FLOOR/FIRST_UNIT_PLACED触发条件
- GuideController增强: 新增UI聚焦引导功能(半透明Frame包围目标UI)
- 新增引导1003: 获得第一个兵种后引导到IdleFloor中心(Beam引导线)
- 新增引导1004: 到达IdleFloor后聚焦背包UI(半透明Frame)
- 新增引导1005: 首次摆放兵种后聚焦Attack按钮(半透明Frame)
- UI聚焦引导: 4个方向Frame滑入动画(0.5秒TweenService)
- ShopSystem集成: 购买兵种后触发引导检查
- PlacementSystem集成: 摆放兵种后触发引导检查
- GuideEvents增强: 新增StartUIFocusGuide/UIFocusCompleted事件

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

【StageConfig】关卡配置 (V3.7章节地图替换)
- 章节列表: Chapters
- 章节属性: StagesPerChapter/StageTemplateStyle/Rewards
- StageTemplateStyle: 章节使用的关卡模板风格 (如 "Style01", "Style02")
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

【TaskConfig】任务配置 (V3.3新增)
- 任务类型枚举: TaskType (PURCHASE_UNIT/PLACE_UNIT/PURCHASE_SKILL/COMPLETE_BATTLE/COLLECT_IDLE_COIN)
- 任务列表: Tasks[index] = 任务配置
- 任务属性: TaskId/TaskType/RequiredCount/Description/RewardCoins/Sort
- 公共接口: GetTaskById()/GetFirstTaskId()/GetNextTaskId()/IsValidTask()/GetAllTaskIds()/GetTaskCount()/IsLastTask()/GetTaskTypeName()

【GuideConfig】引导配置 (V3.5新增)
- 引导类型枚举: GuideType (SHOP/MAIL)
- 引导列表: Guides[guideId] = 引导配置
- 引导属性: GuideId/GuideType/Name/TargetName/TriggerCondition/ArrivalDistance/Sort/Enabled
- 触发条件: FIRST_JOIN(首次进入)/HAS_IDLE_COINS(有挂机金币)
- 显示配置: GuideStartPartName/GuideEndPartName/CheckInterval/EffectFolderPath
- 公共接口: GetGuideById()/IsValidGuide()/GetAllGuideIds()/GetGuideByType()/GetEnabledGuides()/GetGuideCount()

【SoundConfig】音效配置 (V3.8新增)
- BGM配置: BGM[key] = {Id, Name, Folder, Volume, Looped}
- SFX配置: SFX[key] = {Id, Name, Folder, Volume, Looped}
- 淡入淡出配置: BGMFadeIn/BGMFadeOut(默认0.5秒)
- 默认音量: DefaultBGMVolume(0.5)/DefaultSFXVolume(0.8)
- 公共接口: GetBGM(key)/GetSFX(key)/IsValidBGM(key)/IsValidSFX(key)

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

【LoadingEvents】V3.2
- LoadingProgress: Server → Client (加载进度更新: progress, stageName)
- LoadingStageUpdate: Server → Client (加载阶段更新: stage)
- LoadingComplete: Server → Client (加载完成通知)
- ClientPreloadComplete: Client → Server (客户端预加载完成通知)

【TaskEvents】V3.3
- TaskProgress: Server → Client (任务进度更新: taskData)
- TaskComplete: Server → Client (任务完成通知: taskInfo)
- ClaimTaskReward: Client → Server (领取任务奖励)
- ClaimRewardResult: Server → Client (领取结果: success, message, rewardCoins)

【GuideEvents】V3.5
- StartGuide: Server → Client (开始引导: guideId, targetPosition)
- CompleteGuide: Server → Client (完成引导: guideId)
- GuideArrived: Client → Server (到达目标: guideId)
- SyncGuideData: Server → Client (同步引导数据: guideData)
- RequestGuideSync: Client → Server (请求同步引导数据)

【SoundEvents】V3.8
- PlayBGM: Server → Client (播放BGM: bgmKey)
- StopBGM: Server → Client (停止BGM)
- PlaySFX: Server → Client (播放一次性音效: sfxKey)
- StopSFX: Server → Client (停止一次性音效: sfxKey)

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

【11.2 关卡服务】StageService (V2.0/V3.7)
职责：动态生成和管理关卡

核心API：
- GetOrCreateStage(playerId, n)   获取或创建关卡
- GenerateStage(playerId, n)      生成新关卡
- GenerateStage001(homeId, playerId) 生成第一关 (V3.7: 增加playerId参数)
- LoadEnemyData(stage, n)         加载敌人配置
- CleanupStages(playerId)         清理关卡
- SetAirWallState(stage, enabled) 设置空气墙
- SetPlayerChapter(playerId, chapterId)  设置玩家章节 (V3.7新增)
- ClearPlayerChapter(playerId)    清除玩家章节缓存 (V3.7新增)

V3.7章节地图替换机制：
- CampaignManager.StartCampaign调用SetPlayerChapter缓存玩家章节
- GetTemplateStyle(playerId)根据章节ID获取StageTemplateStyle
- 从StageConfig.GetChapterStyle(chapterId)读取配置
- CleanupStages时自动清除章节缓存

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

【11.15 Loading系统】LoadingSystem (V3.2新增)
职责：服务端玩家加载状态管理

核心API：
- Initialize()                    初始化Loading系统
- StartPlayerLoading(player)      开始玩家加载流程
- NotifyDataLoading(player, sub)  通知数据加载阶段
- NotifyDataLoadComplete(player)  通知数据加载完成
- NotifyHomeSetup(player, sub)    通知基地设置阶段
- NotifyHomeSetupComplete(player) 通知基地设置完成
- NotifySceneSetup(player, sub)   通知场景设置阶段
- NotifySceneSetupComplete(player)通知场景设置完成
- NotifyDataSync(player, sub)     通知数据同步阶段
- NotifyDataSyncComplete(player)  通知数据同步完成
- TryCompleteLoading(player)      尝试完成加载
- ForceCompleteLoading(player)    强制完成加载(超时)
- IsPlayerLoaded(player)          检查是否加载完成
- CleanupPlayer(player)           清理玩家加载状态

内部机制：
- playerLoadingStates存储每个玩家的加载状态
- 加载阶段权重: INIT(0%)/DATA_LOADING(20%)/HOME_SETUP(40%)/SCENE_SETUP(60%)/SYNC_DATA(80%)/COMPLETE(100%)
- 需要服务端和客户端同时完成才触发LoadingComplete
- 自动创建LoadingEvents文件夹和RemoteEvent

【11.16 Loading控制器】LoadingController (V3.2新增)
职责：客户端Loading界面与资源预加载

核心API：
- LoadingController.IsLoadingComplete()  检查是否加载完成
- LoadingController.GetProgress()        获取当前进度
- LoadingController.ForceHide()          强制隐藏Loading(紧急)

内部机制：
- 初始化时立即显示Loading界面
- 随机选择3张背景图之一显示
- 服务端进度60%权重 + 客户端预加载40%权重
- 客户端预加载内容:
  - 动画资源(Show/Idle/Move/Attack/Death)
  - 兵种图标
  - 技能图标
  - Loading背景图片
- 分批预加载(每批10个资源)避免卡顿
- 60秒超时看门狗自动完成
- 进度条TweenService平滑动画
- 完成后0.5秒淡出效果

全局访问：_G.LoadingController

【11.17 任务系统】TaskSystem (V3.3新增)
职责：服务端任务进度管理与奖励发放

核心API：
- Initialize()                    初始化任务系统
- InitializePlayerTask(player)    初始化玩家任务数据
- OnPurchaseUnit(player, unitId)  购买兵种时触发（任务类型1）
- OnPlaceUnit(player, unitId)     放置兵种时触发（任务类型2）
- OnPurchaseSkill(player, skillId)购买技能时触发（任务类型3）
- OnCompleteBattle(player)        完成战斗时触发（任务类型4）
- OnCollectIdleCoin(player)       领取挂机金币时触发（任务类型5）
- SyncTaskToClient(player)        同步任务数据到客户端
- GetPlayerTaskInfo(player)       获取玩家任务信息
- HasPendingTask(player)          检查是否有未完成任务

内部机制：
- 获取玩家TaskData(从DataManager)
- 检查任务类型是否匹配当前任务
- 增加进度并判断是否完成
- 完成时发送TaskComplete事件
- 玩家领取奖励后切换到下一个任务
- 自动检测新增任务(运营更新后)

【11.18 任务显示】TaskDisplay (V3.3新增)
职责：客户端任务UI管理

核心API：
- Initialize()                    初始化任务显示模块

内部机制：
- 监听TaskProgress事件更新UI
- 监听TaskComplete事件显示完成提示
- 监听ClaimRewardResult事件处理领取结果
- 进度条TweenService动画
- 任务完成时闪烁领取按钮
- 全部任务完成时显示"已全部完成"

UI结构：
- TaskPanel (Frame)
  - TaskDescription (TextLabel): 任务描述
  - ProgressText (TextLabel): 进度文本
  - ProgressBar (Frame): 进度条背景
    - Fill (Frame): 进度条填充
  - RewardText (TextLabel): 奖励显示
  - ClaimButton (TextButton): 领取按钮
  - CompletedLabel (TextLabel): 完成标签(可选)

【11.19 战斗金币系统】BattleCoin (V3.4新增)
职责：战斗中获取金币(击杀金币+前进金币)

击杀金币(CombatSystem.KillUnit):
- 只有Defense队被击杀时触发
- 金币数 = 兵种KillReward * 等级
- 通过BattleManager.GetBattle获取PlayerId
- 调用CurrencySystem.AddCoins发放

前进金币(CampaignManager):
- 每0.5秒计算一次战场中心位置(所有存活友军质心)
- 计算从起点(CommandPart)到当前位置的Z轴前进距离
- 每前进AdvanceDistance studs获得AdvanceReward金币
- 只计算前进不计算后退，防止往返刷金币

相关配置：
- UnitConfig.Units[id].KillReward: 基础击杀金币(默认5)
- GameConfig.BattleCoin.AdvanceDistance: 前进触发距离(默认30)
- GameConfig.BattleCoin.AdvanceReward: 每次前进金币(默认5)

【11.20 新手引导系统】GuideSystem (V3.5新增)
职责：服务端引导状态管理

核心API：
- Initialize()                    初始化引导系统
- InitializePlayerGuide(player)   初始化玩家引导
- CheckAndTriggerGuides(player)   检查并触发引导
- TriggerGuide(player, guideId)   触发指定引导
- OnGuideArrived(player, guideId) 玩家到达目标时调用
- CleanupPlayer(player)           清理玩家引导状态
- GetActiveGuideId(player)        获取当前激活的引导ID
- IsGuideCompleted(player, guideId) 检查引导是否已完成
- GetCompletedGuides(player)      获取所有已完成的引导
- GMTriggerGuide(player, guideId) GM命令：触发引导
- GMResetGuide(player, guideId)   GM命令：重置引导
- GMResetAllGuides(player)        GM命令：重置所有引导
- GMCompleteGuide(player, guideId) GM命令：完成引导

内部机制：
- playerGuideStates存储每个玩家的激活引导状态
- 延迟加载DataManager/IdleCoinSystem避免循环依赖
- 自动创建GuideEvents文件夹和RemoteEvent
- 触发条件检查: FIRST_JOIN(未完成即触发)/HAS_IDLE_COINS(有待领取金币)
- 完成引导后自动检查并触发下一个引导

【11.21 引导控制器】GuideController (V3.5新增)
职责：客户端引导显示与到达检测

核心API：
- Initialize()                    初始化引导控制器
- GetCurrentGuideId()             获取当前引导ID
- HasActiveGuide()                检查是否有激活的引导
- ClearGuide()                    手动清除引导(调试用)

内部机制：
- 从Workspace/Effect克隆Guide01(起点)/Guide02(终点)
- Guide01绑定到玩家躯干(UpperTorso/Torso/HumanoidRootPart)
- Guide02放在目标位置并Anchored
- RenderStepped每帧更新Guide01位置
- 检测玩家与目标距离,到达后发送GuideArrived事件
- 监听StartGuide/CompleteGuide事件
- 角色重生时自动请求同步引导数据

全局访问：_G.GuideController

【11.22 音效系统】SoundSystem (V3.8新增)
职责：服务端音效事件管理

核心API：
- Initialize()                    初始化音效系统
- OnPlayerJoin(player)            玩家加入时播放Home BGM
- OnBattleStart(player)           战斗开始时切换到Battle BGM
- OnBattleEnd(player)             战斗结束时切换回Home BGM
- OnVictoryShow(player)           显示结算弹窗时播放Victory音效
- OnVictoryConfirm(player)        确认结算时停止Victory音效
- OnCollectIdleCoins(player)      领取挂机金币时播放CoinsTrigger音效
- OnMerge(player)                 合成兵种时播放Merge音效
- OnPurchaseError(player)         购买失败时播放Error音效
- PlayBGM(player, bgmKey)         播放BGM(手动调用)
- StopBGM(player)                 停止BGM(手动调用)
- PlaySFX(player, sfxKey)         播放SFX(手动调用)
- StopSFX(player, sfxKey)         停止SFX(手动调用)

内部机制：
- 自动创建SoundEvents文件夹和RemoteEvent
- 通过RemoteEvent通知客户端播放音效
- 每个API都包裹pcall防止异常

【11.23 音效控制器】SoundController (V3.8新增)
职责：客户端音效播放控制

核心API：
- SoundController.PlayBGM(bgmKey)     播放BGM
- SoundController.StopBGM()           停止BGM
- SoundController.PlaySFX(sfxKey)     播放SFX
- SoundController.StopSFX(sfxKey)     停止SFX
- SoundController.IsInitialized()     检查是否初始化完成
- SoundController.GetCurrentBGMKey()  获取当前BGM键名

内部机制：
- 根据SoundConfig配置自动创建Sound对象到SoundService
- BGM存储路径: SoundService/BGM/[Folder]/[Name]
- SFX存储路径: SoundService/Audio/[Folder]/[Name]
- BGM切换使用TweenService实现淡入淡出效果(0.5秒)
- 如果已在播放相同BGM，不会重复播放
- 监听SoundEvents下的PlayBGM/StopBGM/PlaySFX/StopSFX事件

全局访问：_G.SoundController

音效资源ID：
- Home BGM: rbxassetid://1842908030
- Battle BGM: rbxassetid://1838627590
- CoinsTrigger SFX: rbxassetid://99023919906775
- Victory SFX: rbxassetid://5205229311
- Merge SFX: rbxassetid://7393525156
- Error SFX: rbxassetid://8400918001

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
    -- V3.4新增: 前进金币追踪
    StartZPosition = number,        -- 战斗起始Z坐标(CommandPart位置)
    MaxAdvancedZ = number,          -- 最远前进Z坐标
    LastRewardedDistance = number,  -- 上次获得奖励时的累计前进距离
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
    TaskData = {                    -- V3.3 任务数据
        CurrentTaskId = number,         -- 当前任务ID
        CurrentProgress = number,       -- 当前任务进度
        CompletedTaskIds = {taskId, ...}, -- 已完成的任务ID列表
        AllTasksCompleted = boolean,    -- 是否全部任务完成
    },
    GuideData = {                   -- V3.5 引导数据
        CompletedGuides = {[guideId] = true}, -- 已完成的引导ID
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
17. V3.2+: Loading UI需按指定结构创建(Loading/Bg/LoadingImage/ProgressBg/Progressbar/Number)
18. V3.2+: LoadingController会自动检测并使用AnimationPreloader/IconPreloader作为备份
19. V3.2+: 服务端需在PlayerAdded中调用LoadingSystem各阶段通知方法
20. V3.3+: 任务UI需按指定结构创建(TaskPanel/TaskDescription/ProgressText/ProgressBar/Fill/RewardText/ClaimButton)
21. V3.3+: 新增任务只需在TaskConfig.Tasks表中添加配置，无需修改其他代码
22. V3.3+: 任务系统会在玩家加入时自动初始化和同步任务数据
23. V3.3+: 各系统购买/放置/战斗完成时需调用TaskSystem对应方法通知进度
24. V3.4+: 兵种配置需包含KillReward字段(基础击杀金币)
25. V3.4+: 战斗金币配置在GameConfig.BattleCoin中(前进距离/奖励)
26. V3.4+: 击杀金币=基础值*等级，只有杀死敌方单位(Defense队)才获得
27. V3.5+: 引导资源(Guide01/Guide02)需在Workspace/Effect下创建
28. V3.5+: 引导目标(KeepShoper01/Mail)需在各玩家家园下创建
29. V3.5+: 新增引导只需在GuideConfig.Guides表中添加配置
30. V3.7+: 章节关卡地图替换需在StageConfig.Chapters中配置StageTemplateStyle字段
31. V3.7+: 关卡模板需按ReplicatedStorage/StageTemplate/[StyleName]/StageMiddle|StageEnd结构创建
32. V3.7+: 新增关卡风格只需创建对应的模板文件夹并在StageConfig中配置
33. V3.8+: 音效配置在SoundConfig中，支持BGM和SFX两种类型
34. V3.8+: 音效触发需在对应系统中调用SoundSystem的方法
35. V3.8+: SoundController会自动创建Sound对象，无需手动在SoundService中创建

=====================================================
架构设计文档完成
版本: V3.9.1
最后更新: 2025-12-11
=====================================================
]]
