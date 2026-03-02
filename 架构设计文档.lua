--[[
=====================================================
游戏整体架构设计文档（当前代码基线）
=====================================================

项目名称: Roblox Prison Game
当前版本: V7.3
文档更新时间: 2026-02-28

说明:
1. 本文档以当前仓库脚本为准（MainServer/DataManager/Systems/UI）。
2. 该仓库是导出后的平铺脚本结构，逻辑分层仍按 Studio 的 Core/Systems/UI/Controllers。
3. 本文档同步到 V7.3（已包含 DailyTaskSystem / DailyTaskDisplay / DailyTaskEvents）。

=====================================================
一、总体架构
=====================================================

1) 服务端权威 + 客户端表现
- 服务端负责：数据持久化、数值结算、状态推进、反作弊校验。
- 客户端负责：UI、动效、输入交互、镜头与表现层。

2) 数据驱动
- 战斗、关卡、奖励、商店、重生、养成等均通过 Config 模块驱动。
- 新玩法优先“加配置 + 加系统”，减少硬编码。

3) 多系统并行
- 玩家拥有独立家园与成长数据，系统通过事件与属性同步协作。

=====================================================
二、模块结构（按当前代码）
=====================================================

【服务端 Core】
- DataManager.lua：玩家数据加载/缓存/保存、向后兼容迁移、数值接口。
- PlayerManager.lua：玩家进出、家园分配、基础状态维护。

【服务端 Systems（核心业务）】
- 战斗链路：BattleManager / CombatSystem / UnitAI / ProjectileSystem / HitboxService / UnitManager / WeaponEffectSystem / BattleTestSystem
- 家园与单位：HomeSystem / DoorControlService / InventorySystem / PlacementSystem / MergeSystem / CollisionSystem / PhysicsManager
- 关卡与成长：CampaignManager / StageService / IdleCoinSystem / UpgradeSystem / RebirthSystem / PowerSystem / LeaderboardSystem / BadgeSystem
- 商业化与奖励：ShopSystem / SkillShopSystem / DailyRewardSystem / SevenDaysSystem / GroupRewardSystem / StarterPackSystem / VipSystem / LimitPrisonerSystem / OnlineRewardSystem
- 社交系统：LikeSystem（点赞）
- V7.3 新增：DailyTaskSystem（每日任务：在线/勋章/击败累计与奖励发放）
- 其他：GuideSystem / SoundSystem / MarketplaceHandler / GMCommandSystem / LoadingSystem

【客户端（StarterPlayerScripts 逻辑分层）】
- UI：ShopDisplay / SkillShopDisplay / RebirthDisplay / MapDisplay / SevenDaysDisplay / OnlineRewardDisplay / DailyRewardDisplay / DailyTaskDisplay（V7.3）等
- Controllers：MainGuiController / PlacementController / CameraController / TipsSystemController / SoundController 等
- Utils：ButtonEffectHelper / UIEffectController / CoinAnimationHelper / RobuxPriceHelper / LevelDisplayHelper 等

【配置层（ReplicatedStorage/Config）】
- 基础：GameConfig / UnitConfig / BattleConfig / StageConfig / EnemyConfig / PlacementConfig / HouseConfig
- 商业化：ShopConfig / SkillShopConfig / VipConfig / StarterPackConfig
- 奖励与成长：SevenDaysConfig / DailyRewardConfig / OnlineRewardConfig / GroupRewardConfig / LimitPrisonerConfig / UpgradeConfig / RebirthConfig / PowerConfig / BadgeConfig
- 表现与引导：GuideConfig / SoundConfig / LevelColorConfig

=====================================================
三、MainServer 初始化顺序（当前）
=====================================================

1. PhysicsManager -> CollisionSystem
2. HomeSystem -> DoorControlService
3. CurrencySystem -> PlayerManager -> Inventory/Placement/Merge
4. Power/Leaderboard/Badge
5. Shop -> SkillShop
6. 战斗链路（Hitbox/UnitManager/Combat/Projectile/WeaponEffect/UnitAI/BattleManager/BattleTest）
7. CampaignManager
8. IdleCoin -> LimitPrisoner
9. Skill -> Loading -> Guide
10. SevenDays -> DailyReward -> StarterPack -> Vip -> GroupReward
11. Sound -> Upgrade -> Rebirth -> Like -> DailyTask（V7.3）
12. MarketplaceHandler
13. OnlineReward

备注：新增系统应接在依赖系统之后，并同步更新本文件与 RemoteEvent 清单。

=====================================================
四、核心玩法链路（V7.3）
=====================================================

1) 基础循环
- 买兵 -> 放置/拖拽 -> 合成 -> 自动战斗 -> 获取金币/勋章 -> 持续成长。

2) 关卡推进
- 地图界面选择章节，按勋章解锁与推进，通关后发放勋章并刷新解锁状态。

3) 成长系统
- 挂机收益（含在线奖励）、养成升级、重生成长、点赞社交。

4) V7.3 每日任务
- UTC0 重置每日任务进度。
- 三条任务：连续在线 15 分钟（离线重置）、当日勋章累计 20、当日击败敌人累计 100。
- 奖励统一为手铐；支持未领取红点提示与通用领取成功弹框流程。

=====================================================
五、核心数据结构（DataManager）
=====================================================

PlayerData 关键字段（节选）：
- Currency.Coins
- Units / PlacedUnits
- ChapterProgress（CurrentChapter / CompletedChapters / MedalCount / UnlockedChapters...）
- SevenDayData / DailyRewardData / OnlineRewardData
- DailyTaskData（V7.3）：
  - LastRefreshDay
  - MedalProgress
  - EnemyDefeatProgress
  - ClaimedTaskIds
- HandcuffData / LimitPrisonerData
- UpgradeData / RebirthData
- LikeData（Count / GivenLikes）
- PowerRankData / SoundSettings

=====================================================
六、版本增量（相对旧文档）
=====================================================

- V6.1：OnlineRewardSystem + OnlineRewardEvents
- V6.7：UpgradeSystem + UpgradeEvents
- V7.0：RebirthSystem + RebirthEvents
- V7.1：MapDisplay + CampaignEvents(RequestMapData/MapData)
- V7.2：LikeSystem + LikeEvents(LikeToast/LikeStateSync)
- V7.3：DailyTaskSystem + DailyTaskDisplay + DailyTaskEvents + DataManager.DailyTaskData

=====================================================
七、维护约束
=====================================================

1. RemoteEvent 以 `RemoteEvent当前列表.lua` 为单一事实源。
2. 新增系统时必须同步更新：
   - MainServer 初始化顺序
   - 本架构文档
   - RemoteEvent 清单
3. 当前代码已包含 DailyTaskSystem / DailyTaskDisplay / DailyTaskEvents，不再是“缺失项”。
4. UI 行为保持统一：按钮反馈、弹框开关动效、Blur Lock 复用既有规范。

=====================================================
文档结束
=====================================================
]]
