--[[
=====================================================
RemoteEvent 当前清单（V7.2 基线）
=====================================================

更新时间: 2026-02-28
基线来源: 当前仓库代码（MainServer + 各 System/Display/Controller）

目录结构：
ReplicatedStorage
└── Events (Folder)

=====================================================
一、事件目录总览
=====================================================

1) CurrencyEvents (RemoteEvent)
2) PlayerEvents (RemoteEvent)
3) InventoryEvents (Folder)
4) PlacementEvents (Folder)
5) MergeEvents (Folder)
6) BattleEvents (Folder)
7) CampaignEvents (Folder)
8) ShopEvents (Folder)
9) IdleCoinEvents (Folder)
10) BattleControlEvents (Folder)
11) SkillEvents (Folder)
12) SkillShopEvents (Folder)
13) LoadingEvents (Folder)
14) GuideEvents (Folder)
15) SoundEvents (Folder)
16) HouseUpgradeEvents (Folder)
17) ClientAIEvents (Folder)
18) PowerEvents (Folder)
19) LeaderboardEvents (Folder)
20) SevenDaysEvents (Folder)
21) GroupRewardEvents (Folder)
22) DailyRewardEvents (Folder)
23) StarterPackEvents (Folder)
24) VipEvents (Folder)
25) ArmyPackEvents (Folder)
26) LimitPrisonerEvents (Folder)
27) OnlineRewardEvents (Folder)
28) UpgradeEvents (Folder)
29) RebirthEvents (Folder)
30) LikeEvents (Folder)

=====================================================
二、分组明细
=====================================================

【CurrencyEvents】(RemoteEvent)
- Server -> Client: (currencyType, newAmount)
- Client -> Server: 请求货币同步

【PlayerEvents】(RemoteEvent)
- 预留（当前版本无稳定业务绑定）

【InventoryEvents】
- InventoryRefresh (S->C)
- RequestInventory (C->S)
- UnitUpdated (S->C)
- RequestUnitInstance (C->S)
- UnitInstanceResponse (S->C)

【PlacementEvents】
- StartPlacement (C->S)
- ConfirmPlacement (C->S)
- CancelPlacement (C->S)
- PlacementResponse (S->C)
- RemoveUnit (C->S)
- RemoveAllUnits (C->S)
- RemoveResponse (S->C)
- UpdatePosition (C->S)
- UpdateResponse (S->C)

【MergeEvents】
- RequestMerge (C->S)
- MergeResponse (S->C)

【BattleEvents】
- RequestBattleTest (C->S)
- BattleTestResponse (S->C)
- BattleStateUpdate (S->C)
- UnitDeath (BindableEvent, server internal)
- ShowDamageNumber (S->C)
- UnitHealthUpdate (S->C)
- AttachHealthBars (S->C)
- DetachHealthBars (S->C)
- VictoryPopup (S->C)
- VictoryConfirm (C->S)
- ReviveResult (S->C)
- CoinEarnedEffect (S->C)

【CampaignEvents】
- RequestStartCampaign (C->S, chapterId?)
- RequestRetreat (C->S)
- CampaignStateUpdate (S->C)
- StageProgress (S->C)
- LockHomeOperations (S->C)
- RequestMapData (C->S)   [V7.1]
- MapData (S->C)          [V7.1]

【ShopEvents】
- RequestShopList (C->S)
- ShopList (S->C)
- PurchaseUnit (C->S)
- PurchaseUnitRobux (C->S)
- PurchaseResult (S->C)
- StockUpdate (S->C)
- RefreshTimeUpdate (S->C)
- ShopRefreshTip (S->C)

【IdleCoinEvents】
- CollectIdleCoins (C->S)
- SyncIdleCoins (S->C)

【BattleControlEvents】
- ReturnToHome (C->S)
- UnlockMove (C->S)

【SkillEvents】
- RequestCastSkill (C->S)
- CastSkillResponse (S->C)
- SkillInventoryUpdate (S->C)
- SpawnSkillEffect (S->C)
- RequestSkillSync (C->S)

【SkillShopEvents】
- RequestSkillShopList (C->S)
- SkillShopList (S->C)
- PurchaseSkill (C->S)
- PurchaseSkillRobux (C->S)
- SkillPurchaseResult (S->C)
- SkillStockUpdate (S->C)
- SkillRefreshTimeUpdate (S->C)

【LoadingEvents】
- LoadingProgress (S->C)
- LoadingStageUpdate (S->C)
- LoadingComplete (S->C)
- ClientPreloadComplete (C->S)

【GuideEvents】
- StartGuide (S->C)
- CompleteGuide (S->C)
- GuideArrived (C->S)
- SyncGuideData (S->C)
- RequestGuideSync (C->S)
- StartUIFocusGuide (S->C)
- UIFocusCompleted (C->S)

【SoundEvents】
- PlayBGM (S->C)
- StopBGM (S->C)
- PlaySFX (S->C)
- StopSFX (S->C)

【HouseUpgradeEvents】
- StartUpgradeSequence (S->C)
- ClientCameraReady (C->S)
- HouseUpgradePopupClosed (C->S)
- UpgradeSequenceComplete (C->S)

【ClientAIEvents】
- InitializeBattle (S->C)
- SyncUnitPosition (S->C)
- TerminateBattle (S->C)
- ServerUnitDeath (S->C)
- RequestAttack (C->S)
- ReportUnitPosition (C->S)
- ClientBattleReady (C->S)
- StartMarch (S->C)
- MarchComplete (C->S)

【PowerEvents】
- PowerUpdate (S->C)
- RequestPower (C->S)

【LeaderboardEvents】
- RequestLeaderboard (C->S)
- LeaderboardData (S->C)

【SevenDaysEvents】
- RequestSevenDaysData (C->S)
- SevenDaysData (S->C)
- ClaimSevenDayReward (C->S)
- ClaimSevenDayResult (S->C)

【GroupRewardEvents】
- RequestGroupRewardData (C->S)
- GroupRewardData (S->C)
- ClaimGroupReward (C->S)
- ClaimGroupRewardResult (S->C)

【DailyRewardEvents】
- RequestDailyRewardData (C->S)
- DailyRewardData (S->C)
- ClaimDailyReward (C->S)
- ClaimDailyRewardResult (S->C)

【StarterPackEvents】
- RequestStarterPackData (C->S)
- StarterPackData (S->C)
- PurchaseStarterPack (C->S)
- PurchaseStarterPackResult (S->C)

【VipEvents】
- RequestVipData (C->S)
- VipData (S->C)
- PurchaseVip (C->S)
- VipPurchaseResult (S->C)

【ArmyPackEvents】
- ArmyPackPurchaseResult (S->C)

【LimitPrisonerEvents】
- RequestLimitPrisonerData (C->S)
- LimitPrisonerData (S->C)
- PurchaseLimitPrisonerGold (C->S)
- PurchaseLimitPrisonerRobux (C->S)
- RedeemLimitPrisoner (C->S)
- LimitPrisonerPurchaseResult (S->C)
- LimitPrisonerRedeemResult (S->C)

【OnlineRewardEvents】
- RequestOnlineRewardData (C->S)
- OnlineRewardData (S->C)
- ClaimOnlineReward (C->S)
- ClaimOnlineRewardResult (S->C)

【UpgradeEvents】
- RequestUpgradeData (C->S)
- UpgradeData (S->C)
- PurchaseUpgradeByCoin (C->S)
- PurchaseUpgradeByRobux (C->S)
- UpgradePurchaseResult (S->C)

【RebirthEvents】
- RequestRebirthData (C->S)
- RebirthData (S->C)
- AttemptRebirth (C->S)
- RebirthResult (S->C)
- RebirthPanelClosed (C->S)
- RebirthStateChanged (S->C)

【LikeEvents】
- LikeToast (S->C, likerName, newLikeCount)
- LikeStateSync (S->C, mode, payload)

=====================================================
三、维护约定
=====================================================

1. 新增业务事件时，必须同步更新：
   - 本文件
   - 架构设计文档.lua
   - 对应 System/Display 的初始化逻辑

2. 当前版本无 TaskEvents（旧文档残留已移除）。

3. 说明中 C->S / S->C 仅表示常规方向；部分 RemoteEvent 可能双向复用。

=====================================================
清单结束
=====================================================
]]
