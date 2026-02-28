--[[
=====================================================
游戏整体架构设计文档（当前代码基线）
=====================================================

项目名称: Roblox Prison Game
当前版本: V7.2
文档更新时间: 2026-02-28

说明：
1. 本文档以当前仓库脚本为准（MainServer/DataManager/CampaignManager/RebirthSystem/LikeSystem）。
2. 需求文档版本已经到 V7.2，旧版 V4.x 架构描述已不再作为维护基线。
3. 当前仓库是“导出后平铺脚本结构”，逻辑路径仍按 Studio 分层（Core/Systems/UI/Controllers）。

=====================================================
一、总体架构
=====================================================

1) 服务端权威 + 客户端表现
- 服务端：数据持久化、状态机推进、数值结算、反作弊校验。
- 客户端：UI、动效、输入交互、镜头与表现层。

2) 客户端 AI 架构（V4.0+）
- 战斗与行军由客户端驱动（ClientUnitAI + ClientMarchService）。
- 服务端保留权威判定（伤害、死亡、合法性校验）。

3) 数据驱动
- 兵种/关卡/商店/奖励/重生/养成等由 Config 模块驱动。
- 业务尽量通过配置扩展，减少硬编码。

4) 多系统并行
- 单服最多 6 名玩家，各自独立家园、独立战役进度、独立商店与成长数据。

=====================================================
二、当前模块结构（按实际代码）
=====================================================

【服务端 Core】
- DataManager.lua：玩家数据加载、缓存、持久化、兼容迁移。
- PlayerManager.lua：玩家进入/离开、家园分配、占位维护。

【服务端 Systems】
- CurrencySystem.lua：金币增减、VIP/好友/重生加成结算。
- HomeSystem.lua：家园结构初始化与管理。
- InventorySystem.lua：兵种库存、实例ID、同步。
- PlacementSystem.lua：放置/回收/换位、网格验证。
- MergeSystem.lua：同兵种同等级合成。
- PhysicsManager.lua：碰撞组与物理规则。
- CollisionSystem.lua：寻路碰撞辅助。
- BattleManager.lua：战斗实例生命周期。
- CombatSystem.lua：攻击请求校验、伤害与死亡。
- UnitAI.lua：服务端兼容AI/校验层。
- ClientAIBootstrap.lua（客户端脚本）配套 ClientAIEvents。
- ProjectileSystem.lua：远程弹道。
- HitboxService.lua：近战命中判定。
- UnitManager.lua：单位索引与检索。
- WeaponEffectSystem.lua：开火特效。
- BattleTestSystem.lua：战斗调试入口。
- CampaignManager.lua：章节推进、地图/勋章、结算流程。
- StageService.lua：关卡模板生成与清理。
- DoorControlService.lua：家园门开关表现。
- ShopSystem.lua：兵种商店、库存刷新、快速补货。
- SkillSystem.lua：技能释放与效果。
- SkillShopSystem.lua：技能商店。
- IdleCoinSystem.lua：离线挂机收益。
- HouseUpgradeSystem.lua：监狱房屋升级/替换。
- GuideSystem.lua：新手引导。
- SoundSystem.lua：BGM/SFX路由。
- PowerSystem.lua：战斗力计算与同步。
- LeaderboardSystem.lua：全局排行榜。
- BadgeSystem.lua：徽章发放。
- SevenDaysSystem.lua：七日奖励。
- DailyRewardSystem.lua：每日免费奖励。
- GroupRewardSystem.lua：群组奖励。
- StarterPackSystem.lua：新手礼包。
- VipSystem.lua：VIP权益。
- LimitPrisonerSystem.lua：限时囚犯。
- OnlineRewardSystem.lua：在线奖励。
- UpgradeSystem.lua：全局养成。
- RebirthSystem.lua：重生系统。
- LikeSystem.lua：点赞系统。
- MarketplaceHandler.lua：开发者商品/通行证收据分发。
- GMCommandSystem.lua：GM 指令调试。

【客户端（StarterPlayerScripts 逻辑分组）】
- ClientAI：ClientUnitManager / ClientPathService / ClientUnitAI / ClientMarchService / ClientAIBootstrap
- UI：ShopDisplay / SkillShopDisplay / RebirthDisplay / MapDisplay / LimitPrisonerDisplay / OnlineRewardDisplay / DailyRewardDisplay / SevenDaysDisplay / LeaderboardDisplay / StarterPackDisplay / VipDisplay / ArmyPackDisplay 等
- Controllers：PlacementController / DragSystem / RemovalController / CameraController / MainGuiController / AutoBattleController / TipsSystemController / GuideController / SoundController 等
- Utils：ButtonEffectHelper / UIEffectController / LevelDisplayHelper / CoinAnimationHelper / RobuxPriceHelper 等

【配置层（ReplicatedStorage/Config）】
- 基础：GameConfig / UnitConfig / PlacementConfig / BattleConfig / EnemyConfig / StageConfig / HouseConfig
- 商业化：ShopConfig / SkillShopConfig / VipConfig / StarterPackConfig
- 奖励：SevenDaysConfig / DailyRewardConfig / OnlineRewardConfig / GroupRewardConfig / LimitPrisonerConfig
- 成长：UpgradeConfig / RebirthConfig / PowerConfig / BadgeConfig
- 引导与表现：GuideConfig / SoundConfig / LevelColorConfig

=====================================================
三、主启动顺序（MainServer 当前顺序）
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
11. Sound -> Upgrade -> Rebirth -> Like
12. MarketplaceHandler
13. OnlineReward

备注：MainServer 初始化顺序即当前系统依赖基线，新增系统尽量追加到相关依赖之后。

=====================================================
四、核心玩法链路（V7.2）
=====================================================

1) 基础循环
- 买兵（商店） -> 放置/拖拽换位 -> 合成升阶 -> 自动战斗 -> 获取金币/勋章 -> 持续成长。

2) 战役与地图（V7.1）
- Play 打开地图面板。
- 章节依据勋章解锁；玩家可选择已解锁章节挑战。
- 通过章节后发放勋章并刷新可解锁章节。

3) 增长系统
- 挂机收益（含离线、在线奖励、每日、七日）。
- 养成系统（全局移动/攻速/攻击/生命）。
- 重生系统（清零重置 + 全局倍率/攻击加成/解锁）。

4) 付费与权益
- 新手礼包、VIP、兵种礼包、快速补货、复活、限时囚犯 Robux 购买。
- 价格显示支持动态拉取（RobuxPriceHelper）。

5) 社交与轻竞技
- 点赞系统（V7.2）
- 全局排行榜（战斗力）
- 徽章系统

=====================================================
五、核心数据结构（DataManager 当前字段）
=====================================================

PlayerData 关键字段：
- Currency.Coins
- Units / PlacedUnits
- ShopData（含库存刷新时间与快速补货结束时间）
- SkillInventory
- IdleCoinData
- ChapterProgress（CurrentChapter / CompletedChapters / UnlockedChapters / MedalCount / CurrentHouseModel）
- SevenDayData / DailyRewardData / OnlineRewardData
- StarterPackData / VipData / GroupRewardData
- HandcuffData / LimitPrisonerData
- UpgradeData
- RebirthData（Count/CoinBonusRate/AttackBonusRate）
- LikeData（Count/LastLikeTime）
- SoundSettings
- PowerRankData

=====================================================
六、当前版本增量（相对旧文档）
=====================================================

- V6.1：OnlineRewardSystem + OnlineRewardEvents
- V6.7：UpgradeSystem + UpgradeEvents
- V7.0：RebirthSystem + RebirthEvents
- V7.1：MapDisplay + CampaignEvents(RequestMapData/MapData) + 勋章章节选择
- V7.2：LikeSystem + LikeEvents

=====================================================
七、维护规范（文档约束）
=====================================================

1. RemoteEvent 以 `RemoteEvent当前列表.lua` 为单一真相源。
2. 新增系统时必须同步更新：
   - MainServer 初始化顺序
   - 本文模块结构
   - RemoteEvent 清单
3. 当前代码未包含 TaskSystem/TaskDisplay/TaskEvents 脚本，若后续恢复任务系统需重新登记。
4. 统一按钮点击反馈、统一弹框开关动效、统一 Blur 锁应继续复用现有工具模块。

=====================================================
文档结束
=====================================================
]]
