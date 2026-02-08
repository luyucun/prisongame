当前已经有的RemoteEvent

ReplicatedStorage
└──Events（Folder）/
    ├──CurrencyEvents（RemoteEvent）/
    ├──PlayerEvents（RemoteEvent）/
    ├──InventoryEvents（Folder）/
    │   ├──InventoryRefresh（RemoteEvent）
    │   ├──RequestInventory（RemoteEvent）
    │   ├──UnitUpdated（RemoteEvent）
    │   ├──RequestUnitInstance（RemoteEvent） 【V1.2新增】 - 客户端请求可放置的兵种实例
    │   └──UnitInstanceResponse（RemoteEvent） 【V1.2新增】 - 服务端返回实例信息（备用）
    ├──PlacementEvents（Folder）/  【V1.2新增】
    │   ├──StartPlacement（RemoteEvent） - 客户端请求开始放置兵种
    │   ├──ConfirmPlacement（RemoteEvent） - 客户端确认放置兵种
    │   ├──CancelPlacement（RemoteEvent） - 客户端取消放置兵种
    │   ├──PlacementResponse（RemoteEvent） - 服务端返回放置结果
    │   ├──RemoveUnit（RemoteEvent） 【V1.3新增】 - 客户端请求回收兵种
    │   ├──RemoveAllUnits（RemoteEvent） 【V5.2新增】 - 客户端请求一键回收所有已放置兵种
    │   ├──RemoveResponse（RemoteEvent） 【V1.3新增】 - 服务端返回回收结果
    │   ├──UpdatePosition（RemoteEvent） 【V1.4.1新增】 - 客户端请求更新兵种位置（拖动换位）
    │   └──UpdateResponse（RemoteEvent） 【V1.4.1新增】 - 服务端返回位置更新结果
    ├──MergeEvents（Folder）/  【V1.4新增】
    │   ├──RequestMerge（RemoteEvent） - 客户端请求合成兵种
    │   └──MergeResponse（RemoteEvent） - 服务端返回合成结果
    └──BattleEvents（Folder）/  【V1.5新增】
        ├──RequestBattleTest（RemoteEvent） - 客户端请求开始战斗测试
        ├──BattleTestResponse（RemoteEvent） - 服务端返回战斗测试结果
        ├──BattleStateUpdate（RemoteEvent） - 服务端通知客户端战斗状态更新
        ├──UnitDeath（BindableEvent） - 服务端内部兵种死亡通知
        ├──ShowDamageNumber（RemoteEvent） 【V1.5.1新增】 - 服务端通知客户端显示伤害数字
        ├──UnitHealthUpdate（RemoteEvent） 【V2.3新增】 - 服务器→客户端：单位血量更新(unitModel, currentHP, maxHP)
        ├──AttachHealthBars（RemoteEvent） 【V2.3新增】 - 服务器→客户端：挂载血条(unitModels)
        ├──DetachHealthBars（RemoteEvent） 【V2.3新增】 - 服务器→客户端：移除血条(unitModels)
        ├──VictoryPopup（RemoteEvent） 【V2.4新增】 - 服务器→客户端：显示战斗结算弹窗(battleId, result, stageNum, extraRewards)
        ├──VictoryConfirm（RemoteEvent） 【V2.4新增】 - 客户端→服务器：确认战斗结算(battleId)
        ├──ReviveResult（RemoteEvent） 【V5.9新增】 - 服务器→客户端：复活结果(success, message)
        └──CoinEarnedEffect（RemoteEvent） 【V3.4.1新增】 - 服务器→客户端：战斗金币获取表现通知(amount, vipBonus)
    └──CampaignEvents（Folder）/  【V2.0新增】
        ├──RequestStartCampaign（RemoteEvent） - 客户端→服务器：请求开始战役
        ├──RequestRetreat（RemoteEvent） - 客户端→服务器：请求撤退
        ├──CampaignStateUpdate（RemoteEvent） - 服务器→客户端：战役状态更新(state, stageNum, chapter?, totalStagesInChapter?) 【V3.6修改：新增chapter和totalStagesInChapter参数用于进度条显示】
        ├──StageProgress（RemoteEvent） - 服务器→客户端：关卡进度更新(stageNum, status)
        └──LockHomeOperations（RemoteEvent） - 服务器→客户端：锁定/解锁基地操作(locked)
    └──ShopEvents（Folder）/  【V2.1新增】
        ├──RequestShopList（RemoteEvent） - 客户端→服务器：请求商店列表
        ├──ShopList（RemoteEvent） - 服务器→客户端：返回商品数据数组（含库存信息）
        ├──PurchaseUnit（RemoteEvent） - 客户端→服务器：请求购买兵种(unitId)
        ├──PurchaseResult（RemoteEvent） - 服务器→客户端：返回购买结果(success,message,unitId,newCoins)
        ├──StockUpdate（RemoteEvent） 【V2.1库存系统】✅已实现 - 服务器→客户端：库存更新通知(shopId, stockData)
        └──RefreshTimeUpdate（RemoteEvent） 【V2.1库存系统】✅已实现 - 服务器→客户端：刷新倒计时更新(remainingTime)
    └──TalkEvents（Folder）/  【V4.5新增】
        ├──RequestTalkList（RemoteEvent） - 客户端→服务器：请求对话列表
        ├──TalkList（RemoteEvent） - 服务器→客户端：返回对话列表
        ├──SelectTalkOption（RemoteEvent） - 客户端→服务器：选择对话选项(talkId)
        └──TalkResponse（RemoteEvent） - 服务器→客户端：返回对话结果(success, action, talkId, dialogues)
    └──IdleCoinEvents（Folder）/  【V2.6新增】
        ├──CollectIdleCoins（RemoteEvent） - 客户端→服务器：请求领取挂机金币
        └──SyncIdleCoins（RemoteEvent） - 服务器→客户端：同步待领取金币数量(coins)
    └──BattleControlEvents（Folder）/  【V2.11新增】
        └──ReturnToHome（RemoteEvent） - 客户端→服务器：请求传送回家园出生点
    └──SkillEvents（Folder）/  【V3.0新增】
        ├──RequestCastSkill（RemoteEvent） - 客户端→服务器：请求释放技能(skillId, position)
        ├──CastSkillResponse（RemoteEvent） - 服务器→客户端：技能释放结果(success, message)
        ├──SkillInventoryUpdate（RemoteEvent） - 服务器→客户端：技能背包更新(inventory)
        ├──SpawnSkillEffect（RemoteEvent） - 服务器→客户端：生成技能特效(skillId, position, duration)
        └──RequestSkillSync（RemoteEvent） - 客户端→服务器：请求同步技能背包
    └──SkillShopEvents（Folder）/  【V3.1新增】
        ├──RequestSkillShopList（RemoteEvent） - 客户端→服务器：请求技能商店列表
        ├──SkillShopList（RemoteEvent） - 服务器→客户端：返回技能商品数据数组（含库存信息）
        ├──PurchaseSkill（RemoteEvent） - 客户端→服务器：请求购买技能(skillId)
        ├──SkillPurchaseResult（RemoteEvent） - 服务器→客户端：返回购买结果(success,message,skillId,newCoins)
        ├──SkillStockUpdate（RemoteEvent） - 服务器→客户端：技能库存更新通知(shopId, stockData)
        └──SkillRefreshTimeUpdate（RemoteEvent） - 服务器→客户端：技能刷新倒计时更新(remainingTime)
    └──LoadingEvents（Folder）/  【V3.2新增】
        ├──LoadingProgress（RemoteEvent） - 服务器→客户端：加载进度更新(progress, stageName)
        ├──LoadingStageUpdate（RemoteEvent） - 服务器→客户端：加载阶段更新(stage)
        ├──LoadingComplete（RemoteEvent） - 服务器→客户端：加载完成通知
        └──ClientPreloadComplete（RemoteEvent） - 客户端→服务器：客户端预加载完成通知
    └──TaskEvents（Folder）/  【V3.3新增】
        ├──TaskProgress（RemoteEvent） - 服务器→客户端：任务进度更新(taskData)
        ├──TaskComplete（RemoteEvent） - 服务器→客户端：任务完成通知(taskInfo)
        ├──ClaimTaskReward（RemoteEvent） - 客户端→服务器：领取任务奖励
        └──ClaimRewardResult（RemoteEvent） - 服务器→客户端：领取结果(success, message, rewardCoins)
    └──GuideEvents（Folder）/  【V3.5新增 / V3.9.1增强】
        ├──StartGuide（RemoteEvent） - 服务器→客户端：开始引导(guideId, targetPosition)
        ├──CompleteGuide（RemoteEvent） - 服务器→客户端：完成引导(guideId)
        ├──GuideArrived（RemoteEvent） - 客户端→服务器：到达目标(guideId)
        ├──SyncGuideData（RemoteEvent） - 服务器→客户端：同步引导数据(guideData)
        ├──RequestGuideSync（RemoteEvent） - 客户端→服务器：请求同步引导数据
        ├──StartUIFocusGuide（RemoteEvent） - 服务器→客户端：开始UI聚焦引导(guideId, uiPath) 【V3.9.1新增】
        └──UIFocusCompleted（RemoteEvent） - 客户端→服务器：UI聚焦引导完成(guideId) 【V3.9.1新增】
    └──SoundEvents（Folder）/  【V3.8新增】
        ├──PlayBGM（RemoteEvent） - 服务器→客户端：播放BGM(bgmKey)
        ├──StopBGM（RemoteEvent） - 服务器→客户端：停止BGM
        ├──PlaySFX（RemoteEvent） - 服务器→客户端：播放一次性音效(sfxKey)
        └──StopSFX（RemoteEvent） - 服务器→客户端：停止一次性音效(sfxKey)
    └──HouseUpgradeEvents（Folder）/  【V3.9新增】
        ├──StartUpgradeSequence（RemoteEvent） - 服务器→客户端：开始房屋升级镜头表现(homeSlot, oldModelName, newModelName)
        ├──ClientCameraReady（RemoteEvent） - 客户端→服务器：镜头就位通知
        ├──HouseUpgradePopupClosed（RemoteEvent）- 客户端→服务器：房屋升级弹框关闭
        └──UpgradeSequenceComplete（RemoteEvent） - 客户端→服务器：镜头表现完成
    └──ClientAIEvents（Folder）/  【V4.0新增 - 客户端AI迁移】
        ├──InitializeBattle（RemoteEvent） - 服务器→客户端：初始化战斗(battleId, attackUnits, defenseUnits, battleField)
        ├──SyncUnitPosition（RemoteEvent） - 服务器→客户端：同步单位位置(battleId, unitModel, position)
        ├──TerminateBattle（RemoteEvent） - 服务器→客户端：终止战斗(battleId, result)
        ├──ServerUnitDeath（RemoteEvent） - 服务器→客户端：单位死亡通知(battleId, unitModel, killerModel)
        ├──RequestAttack（RemoteEvent） - 客户端→服务器：请求攻击(battleId, attackerModel, targetModel, attackType)
        ├──ReportUnitPosition（RemoteEvent） - 客户端→服务器：上报位置(battleId, unitModel, position, state)
        ├──ClientBattleReady（RemoteEvent） - 客户端→服务器：客户端准备完成(battleId)
        ├──StartMarch（RemoteEvent） 【V4.1新增 - 客户端行军系统】 - 服务器→客户端：通知开始行军(battleId, moveTargets, stageNum, marchToken)
        └──MarchComplete（RemoteEvent） 【V4.1新增 - 客户端行军系统】 - 客户端→服务器：报告行军完成(battleId, stageNum, marchToken, arrivedList, failedList)
    └──PowerEvents（Folder）/  【V3.9.2新增 - 战斗力系统】
        ├──PowerUpdate（RemoteEvent） - 服务器→客户端：同步战斗力数值(totalPower)
        └──RequestPower（RemoteEvent） - 客户端→服务器：请求当前战斗力
    └──LeaderboardEvents（Folder）/  【V4.7新增 - 全局排行榜】
        ├──RequestLeaderboard（RemoteEvent） - 客户端→服务器：请求排行榜数据
        └──LeaderboardData（RemoteEvent） - 服务器→客户端：返回排行榜数据(entries, nextRefreshTime, serverTime)
    └──SevenDaysEvents（Folder）/  【V4.8新增 - 七日登录奖励】
        ├──RequestSevenDaysData（RemoteEvent） - 客户端→服务器：请求七日奖励数据(allowReset)
        ├──SevenDaysData（RemoteEvent） - 服务器→客户端：七日奖励数据(unlockedDays, claimedDays, pendingReset, nextRefreshTime, serverTime, round)
        ├──ClaimSevenDayReward（RemoteEvent） - 客户端→服务器：领取奖励(dayIndex)
        └──ClaimSevenDayResult（RemoteEvent） - 服务器→客户端：领取结果(success, message, dayIndex)
    └──GroupRewardEvents（Folder）/  【V4.9新增 - 加入群组奖励】
        ├──RequestGroupRewardData（RemoteEvent） - 客户端→服务器：请求群组奖励数据
        ├──GroupRewardData（RemoteEvent） - 服务器→客户端：群组奖励数据(claimed)
        ├──ClaimGroupReward（RemoteEvent） - 客户端→服务器：领取群组奖励
        └──ClaimGroupRewardResult（RemoteEvent） - 服务器→客户端：领取结果(success, message, claimed)
    └──DailyRewardEvents（Folder）/  【V5.3新增 - 每日免费奖励】
        ├──RequestDailyRewardData（RemoteEvent） - 客户端→服务器：请求每日奖励数据
        ├──DailyRewardData（RemoteEvent） - 服务器→客户端：每日奖励数据(canClaim, nextRefreshTime, serverTime, lastClaimDay)
        ├──ClaimDailyReward（RemoteEvent） - 客户端→服务器：领取每日奖励
        └──ClaimDailyRewardResult（RemoteEvent） - 服务器→客户端：领取结果(success, message, rewardInfo)
    └──StarterPackEvents（Folder）/  【V5.4新增 - 新手礼包】
        ├──RequestStarterPackData（RemoteEvent） - 客户端→服务器：请求新手礼包数据
        ├──StarterPackData（RemoteEvent） - 服务器→客户端：新手礼包数据(purchased)
        ├──PurchaseStarterPack（RemoteEvent） - 客户端→服务器：请求购买新手礼包
        └──PurchaseStarterPackResult（RemoteEvent） - 服务器→客户端：购买结果(success, message, rewards)
    └──VipEvents（Folder）/  【V5.5新增 - VIP礼包】
        ├──RequestVipData（RemoteEvent） - 客户端→服务器：请求VIP数据
        ├──VipData（RemoteEvent） - 服务器→客户端：VIP数据(purchased)
        ├──PurchaseVip（RemoteEvent） - 客户端→服务器：请求购买VIP
        └──VipPurchaseResult（RemoteEvent） - 服务器→客户端：购买结果(success, message)
    └──ArmyPackEvents（Folder）/  【V5.6新增 - 兵种礼包开发者商品】
        └──ArmyPackPurchaseResult（RemoteEvent） - 服务器→客户端：购买结果(success, message, productId, rewards)
    └──LimitPrisonerEvents（Folder）/  【V6.0新增 - 限时囚犯】
        ├──RequestLimitPrisonerData（RemoteEvent） - 客户端→服务器：请求限时囚犯数据
        ├──LimitPrisonerData（RemoteEvent） - 服务器→客户端：限时囚犯数据(unitId, prices, handcuffs, refreshTime)
        ├──PurchaseLimitPrisonerGold（RemoteEvent） - 客户端→服务器：金币购买限时囚犯
        ├──PurchaseLimitPrisonerRobux（RemoteEvent） - 客户端→服务器：Robux购买限时囚犯
        ├──RedeemLimitPrisoner（RemoteEvent） - 客户端→服务器：手铐兑换限时囚犯
        ├──LimitPrisonerPurchaseResult（RemoteEvent） - 服务器→客户端：购买结果(success, message, purchaseType, unitId, newCoins)
        └──LimitPrisonerRedeemResult（RemoteEvent） - 服务器→客户端：兑换结果(success, message, rewardInfo)
    └──UpgradeEvents（Folder）/  【V6.7新增 - 养成系统】
        ├──RequestUpgradeData（RemoteEvent） - 客户端→服务器：请求养成数据
        ├──UpgradeData（RemoteEvent） - 服务器→客户端：养成数据同步(entries, levels, serverTime)
        ├──PurchaseUpgradeByCoin（RemoteEvent） - 客户端→服务器：金币升级(typeId)
        ├──PurchaseUpgradeByRobux（RemoteEvent） - 客户端→服务器：Robux升级(typeId)
        └──UpgradePurchaseResult（RemoteEvent） - 服务器→客户端：升级结果(payload)



如果需要补充新的RemoteEvent或者Remotefunction，请在这里列出来，我会自己去创建

【V4.5对话系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/TalkEvents/ （新建文件夹）
🆕 RequestTalkList (RemoteEvent) - 需在Studio中手动创建
🆕 TalkList (RemoteEvent) - 需在Studio中手动创建
🆕 SelectTalkOption (RemoteEvent) - 需在Studio中手动创建
🆕 TalkResponse (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "TalkEvents"
6. 右键点击 TalkEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "RequestTalkList"
9. 重复步骤7-8，创建 "TalkList"
10. 重复步骤7-8，创建 "SelectTalkOption"
11. 重复步骤7-8，创建 "TalkResponse"
12. 保存游戏

注意：TalkSystem.lua 初始化时会自动创建这些事件（如果不存在），但建议手动创建以确保事件在系统初始化前就存在。

【V4.8七日登录奖励RemoteEvent创建说明】
位置：ReplicatedStorage/Events/SevenDaysEvents/ （新建文件夹）
🆕 RequestSevenDaysData (RemoteEvent) - 需在Studio中手动创建
🆕 SevenDaysData (RemoteEvent) - 需在Studio中手动创建
🆕 ClaimSevenDayReward (RemoteEvent) - 需在Studio中手动创建
🆕 ClaimSevenDayResult (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "SevenDaysEvents"
6. 右键点击 SevenDaysEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "RequestSevenDaysData"
9. 重复步骤7-8，创建 "SevenDaysData"
10. 重复步骤7-8，创建 "ClaimSevenDayReward"
11. 重复步骤7-8，创建 "ClaimSevenDayResult"
12. 保存游戏

注意：SevenDaysSystem.lua 初始化时会自动创建这些事件（如果不存在），但建议手动创建以确保事件在系统初始化前就存在。

【V4.9群组奖励RemoteEvent创建说明】
位置：ReplicatedStorage/Events/GroupRewardEvents/ （新建文件夹）
🆕 RequestGroupRewardData (RemoteEvent) - 需在Studio中手动创建
🆕 GroupRewardData (RemoteEvent) - 需在Studio中手动创建
🆕 ClaimGroupReward (RemoteEvent) - 需在Studio中手动创建
🆕 ClaimGroupRewardResult (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "GroupRewardEvents"
6. 右键点击 GroupRewardEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "RequestGroupRewardData"
9. 重复步骤7-8，创建 "GroupRewardData"
10. 重复步骤7-8，创建 "ClaimGroupReward"
11. 重复步骤7-8，创建 "ClaimGroupRewardResult"
12. 保存游戏

注意：GroupRewardSystem.lua 初始化时会自动创建这些事件（如果不存在），但建议手动创建以确保事件在系统初始化前就存在。

【V5.3每日免费奖励RemoteEvent创建说明】
位置：ReplicatedStorage/Events/DailyRewardEvents/ （新建文件夹）
?? RequestDailyRewardData (RemoteEvent) - 需在Studio中手动创建
?? DailyRewardData (RemoteEvent) - 需在Studio中手动创建
?? ClaimDailyReward (RemoteEvent) - 需在Studio中手动创建
?? ClaimDailyRewardResult (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "DailyRewardEvents"
6. 右键点击 DailyRewardEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "RequestDailyRewardData"
9. 重复步骤7-8，创建 "DailyRewardData"
10. 重复步骤7-8，创建 "ClaimDailyReward"
11. 重复步骤7-8，创建 "ClaimDailyRewardResult"
12. 保存游戏

注意：DailyRewardSystem.lua 初始化时会自动创建这些事件（如果不存在），但建议手动创建以确保事件在系统初始化前就存在。

【V5.4新手礼包RemoteEvent创建说明】
位置：ReplicatedStorage/Events/StarterPackEvents/ （新建文件夹）
?? RequestStarterPackData (RemoteEvent) - 需在Studio中手动创建
?? StarterPackData (RemoteEvent) - 需在Studio中手动创建
?? PurchaseStarterPack (RemoteEvent) - 需在Studio中手动创建
?? PurchaseStarterPackResult (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "StarterPackEvents"
6. 右键点击 StarterPackEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "RequestStarterPackData"
9. 重复步骤7-8，创建 "StarterPackData"
10. 重复步骤7-8，创建 "PurchaseStarterPack"
11. 重复步骤7-8，创建 "PurchaseStarterPackResult"
12. 保存游戏

注意：StarterPackSystem.lua 初始化时会自动创建这些事件（如果不存在），但建议手动创建以确保事件在系统初始化前就存在。

【V5.5 VIP礼包RemoteEvent创建说明】
位置：ReplicatedStorage/Events/VipEvents/ （新建文件夹）
?? RequestVipData (RemoteEvent) - 需在Studio中手动创建
?? VipData (RemoteEvent) - 需在Studio中手动创建
?? PurchaseVip (RemoteEvent) - 需在Studio中手动创建
?? VipPurchaseResult (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "VipEvents"
6. 右键点击 VipEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "RequestVipData"
9. 重复步骤7-8，创建 "VipData"
10. 重复步骤7-8，创建 "PurchaseVip"
11. 重复步骤7-8，创建 "VipPurchaseResult"
12. 保存游戏

注意：VipSystem.lua 初始化时会自动创建这些事件（如果不存在），但建议手动创建以确保事件在系统初始化前就存在。

【V5.6 兵种礼包开发者商品RemoteEvent创建说明】
位置：ReplicatedStorage/Events/ArmyPackEvents/ （新建文件夹）
?? ArmyPackPurchaseResult (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "ArmyPackEvents"
6. 右键点击 ArmyPackEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "ArmyPackPurchaseResult"
9. 保存游戏

注意：MarketplaceHandler.lua 初始化时会自动创建这些事件（如果不存在），但建议手动创建以确保事件在系统初始化前就存在。

【V2.1库存系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/ShopEvents/
✅ StockUpdate (RemoteEvent) - 已在代码中实现，需在Studio中手动创建
✅ RefreshTimeUpdate (RemoteEvent) - 已在代码中实现，需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events > ShopEvents
3. 右键点击 ShopEvents 文件夹
4. 选择 "Insert Object" > "RemoteEvent"
5. 将新建的 RemoteEvent 重命名为 "StockUpdate"
6. 重复步骤3-5，创建 "RefreshTimeUpdate"
7. 保存游戏


【V2.3血条系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/BattleEvents/
🔄 UnitHealthUpdate (RemoteEvent) - 需在Studio中手动创建
🔄 AttachHealthBars (RemoteEvent) - 需在Studio中手动创建
🔄 DetachHealthBars (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events > BattleEvents
3. 右键点击 BattleEvents 文件夹
4. 选择 "Insert Object" > "RemoteEvent"
5. 将新建的 RemoteEvent 重命名为 "UnitHealthUpdate"
6. 重复步骤3-5，创建 "AttachHealthBars"
7. 重复步骤3-5，创建 "DetachHealthBars"
8. 保存游戏


【V2.4战斗结算系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/BattleEvents/
🆕 VictoryPopup (RemoteEvent) - 需在Studio中手动创建
🆕 VictoryConfirm (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events > BattleEvents
3. 右键点击 BattleEvents 文件夹
4. 选择 "Insert Object" > "RemoteEvent"
5. 将新建的 RemoteEvent 重命名为 "VictoryPopup"
6. 重复步骤3-5，创建 "VictoryConfirm"
7. 保存游戏

功能说明：
- VictoryPopup：服务器在战斗结束时发送给客户端，触发结算界面显示
  参数：(battleId, result, stageNum, extraRewards)
- VictoryConfirm：客户端玩家点击确认按钮后发送给服务器，完成战斗结算
  参数：(battleId)


【V2.6挂机金币系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/IdleCoinEvents/ （新建文件夹）
🆕 CollectIdleCoins (RemoteEvent) - 需在Studio中手动创建
🆕 SyncIdleCoins (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "IdleCoinEvents"
6. 右键点击 IdleCoinEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "CollectIdleCoins"
9. 重复步骤7-8，创建 "SyncIdleCoins"
10. 保存游戏

功能说明：
- CollectIdleCoins：客户端→服务器：请求领取挂机金币
  参数：无（服务器根据玩家身份处理）
- SyncIdleCoins：服务器→客户端：同步待领取金币数量
  参数：(coins: number) 待领取的金币数量

注意：服务端IdleCoinSystem.lua也会在初始化时自动创建这些事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。


【V2.11战斗控制RemoteEvent创建说明】
位置：ReplicatedStorage/Events/BattleControlEvents/ （新建文件夹）
🆕 ReturnToHome (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "BattleControlEvents"
6. 右键点击 BattleControlEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "ReturnToHome"
9. 保存游戏

功能说明：
- ReturnToHome：客户端→服务器：请求传送回家园出生点
  参数：无（服务器根据玩家身份获取家园位置）

UI配置说明（MainGui）：
1. 在StarterGui中的MainGui下创建两个按钮：
   - ReturnToHome (TextButton/ImageButton) - 返回家园按钮
   - UnlockMove (TextButton/ImageButton) - 解锁镜头按钮
2. 两个按钮的初始Visible属性设为false
3. 按钮会在战斗开始时自动显示，战斗结束时自动隐藏

客户端脚本说明：
- MainGuiController.lua 需放置在 StarterPlayer/StarterPlayerScripts/Controllers/
- 负责管理MainGui下的战斗控制按钮显示/隐藏和点击事件


【V3.0技能系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/SkillEvents/ （新建文件夹）
🆕 RequestCastSkill (RemoteEvent) - 需在Studio中手动创建
🆕 CastSkillResponse (RemoteEvent) - 需在Studio中手动创建
🆕 SkillInventoryUpdate (RemoteEvent) - 需在Studio中手动创建
🆕 SpawnSkillEffect (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "SkillEvents"
6. 右键点击 SkillEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "RequestCastSkill"
9. 重复步骤7-8，创建 "CastSkillResponse"
10. 重复步骤7-8，创建 "SkillInventoryUpdate"
11. 重复步骤7-8，创建 "SpawnSkillEffect"
12. 保存游戏

功能说明：
- RequestCastSkill：客户端→服务器：请求释放技能
  参数：(skillId: number, position: Vector3) 技能ID和释放位置
- CastSkillResponse：服务器→客户端：技能释放结果
  参数：(success: boolean, message: string) 是否成功和消息
- SkillInventoryUpdate：服务器→客户端：技能背包更新
  参数：(inventory: table) 技能背包数据 {[skillId] = count}
- SpawnSkillEffect：服务器→客户端：生成技能特效
  参数：(skillId: number, position: Vector3, duration: number) 技能ID、位置和持续时间

注意：服务端SkillSystem.lua会在初始化时自动创建这些事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。

【V3.0技能系统其他资源创建说明】

1. 技能特效资源位置：ReplicatedStorage/Skills/
   需要创建以下特效资源（Model或Part）：
   - WaterGun (喷水枪特效)
   - PoisonGas (毒气炸弹特效)
   - Molotov (大火特效)

2. 技能预览圆圈（可选）：ReplicatedStorage/SkillPreview
   如果不存在，SkillController会自动创建一个绿色发光圆柱体作为默认预览

3. 技能背包UI结构：StarterGui/SkillBackpackGui/
   └── BackpackFrame (Frame)
       └── ItemListFrame (ScrollingFrame)
           ├── UIListLayout
           └── SkillTemplate (ImageButton) [Visible=false]
               ├── Icon (ImageLabel) - 技能图标
               └── Number (TextLabel) - 数量显示

4. 技能配置模块位置：ReplicatedStorage/Config/SkillConfig

5. 服务端系统位置：ServerScriptService/Systems/SkillSystem

6. 客户端控制器位置：
   - StarterPlayer/StarterPlayerScripts/Controllers/SkillController
   - StarterPlayer/StarterPlayerScripts/UI/SkillBackpackDisplay


【V3.1技能商店系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/SkillShopEvents/ （新建文件夹）
🆕 RequestSkillShopList (RemoteEvent) - 需在Studio中手动创建
🆕 SkillShopList (RemoteEvent) - 需在Studio中手动创建
🆕 PurchaseSkill (RemoteEvent) - 需在Studio中手动创建
🆕 SkillPurchaseResult (RemoteEvent) - 需在Studio中手动创建
🆕 SkillStockUpdate (RemoteEvent) - 需在Studio中手动创建
🆕 SkillRefreshTimeUpdate (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "SkillShopEvents"
6. 右键点击 SkillShopEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "RequestSkillShopList"
9. 重复步骤7-8，创建 "SkillShopList"
10. 重复步骤7-8，创建 "PurchaseSkill"
11. 重复步骤7-8，创建 "SkillPurchaseResult"
12. 重复步骤7-8，创建 "SkillStockUpdate"
13. 重复步骤7-8，创建 "SkillRefreshTimeUpdate"
14. 保存游戏

功能说明：
- RequestSkillShopList：客户端→服务器：请求技能商店列表
  参数：无（服务器根据玩家位置判断商店）
- SkillShopList：服务器→客户端：返回技能商品数据数组
  参数：(shopItems: table) 商品列表 [{SkillId, Name, Price, Icon, Stock, ...}]
- PurchaseSkill：客户端→服务器：请求购买技能
  参数：(skillId: number) 技能ID
- SkillPurchaseResult：服务器→客户端：返回购买结果
  参数：(success: boolean, message: string, skillId: number, newCoins: number)
- SkillStockUpdate：服务器→客户端：技能库存更新通知
  参数：(shopId: string, stockData: table) 商店ID和库存数据 {[skillId] = stock}
- SkillRefreshTimeUpdate：服务器→客户端：技能刷新倒计时更新
  参数：(remainingTime: number) 剩余秒数

注意：服务端SkillShopSystem.lua会在初始化时自动创建这些事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。


【V3.1技能商店系统其他资源创建说明】

1. 技能商店配置模块位置：ReplicatedStorage/Config/SkillShopConfig

2. 服务端系统位置：ServerScriptService/Systems/SkillShopSystem

3. 客户端控制器位置：
   - StarterPlayer/StarterPlayerScripts/UI/SkillShopDisplay
   - StarterPlayer/StarterPlayerScripts/Triggers/SkillShopTrigger

4. 技能商店UI结构：StarterGui/SkillStore/
   └── StoreBg (Frame)
       ├── TitleLabel (TextLabel) - 标题（显示刷新倒计时）
       ├── CloseButton (TextButton) - 关闭按钮
       └── ItemContainer (ScrollingFrame)
           ├── UIGridLayout
           ├── SkillCardTemplate (Frame) [Visible=false] - 技能卡片模板
           │   ├── IconBg (Frame)
           │   │   └── Icon (ImageLabel) - 技能图标
           │   ├── Name (TextLabel) - 技能名称
           │   ├── Type (TextLabel) - 技能类型
           │   ├── Effect (TextLabel) - 效果类型
           │   ├── Range (TextLabel) - 技能范围
           │   ├── Description (TextLabel) - 描述
           │   ├── Number (TextLabel) - 库存数量
           │   └── Price (TextLabel) - 价格
           └── BuyButtonFrame (Frame) [Visible=false] - 购买按钮面板
               ├── GoldBuy (TextButton) - 金币购买按钮
               │   └── Price (TextLabel)
               └── RobuxBuy (TextButton) - Robux购买按钮
                   └── Price (TextLabel)

5. 技能商店NPC：
   - NPC名称：KeepShoper02
   - 位置：Home/PlayerHomeX/KeepShoper02
   - 需要有HumanoidRootPart或PrimaryPart用于距离检测

6. 技能商店与兵种商店共享刷新周期：
   - 两个商店使用相同的刷新间隔（默认300秒/5分钟）
   - ShopSystem.InitializePlayerShopTimer() 会同时初始化两个商店的定时器
   - 库存数据分别存储：兵种商店在 ShopData[shopId]，技能商店在 ShopData["Skill_" + shopId]


【V3.2 Loading系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/LoadingEvents/ （新建文件夹）
🆕 LoadingProgress (RemoteEvent) - 需在Studio中手动创建
🆕 LoadingStageUpdate (RemoteEvent) - 需在Studio中手动创建
🆕 LoadingComplete (RemoteEvent) - 需在Studio中手动创建
🆕 ClientPreloadComplete (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "LoadingEvents"
6. 右键点击 LoadingEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "LoadingProgress"
9. 重复步骤7-8，创建 "LoadingStageUpdate"
10. 重复步骤7-8，创建 "LoadingComplete"
11. 重复步骤7-8，创建 "ClientPreloadComplete"
12. 保存游戏

功能说明：
- LoadingProgress：服务器→客户端：加载进度更新
  参数：(progress: number, stageName: string) 进度值(0-100)和当前阶段名称
- LoadingStageUpdate：服务器→客户端：加载阶段更新
  参数：(stage: string) 加载阶段名称(INIT/DATA_LOADING/HOME_SETUP/SCENE_SETUP/SYNC_DATA/COMPLETE)
- LoadingComplete：服务器→客户端：加载完成通知
  参数：无
- ClientPreloadComplete：客户端→服务器：客户端预加载完成通知
  参数：无（服务器根据玩家身份处理）

注意：服务端LoadingSystem.lua会在初始化时自动创建这些事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。


【V3.2 Loading系统其他资源创建说明】

1. 服务端系统位置：ServerScriptService/Systems/LoadingSystem

2. 客户端控制器位置：StarterPlayer/StarterPlayerScripts/LoadingController

3. Loading UI结构：StarterGui/Loading/
   └── Bg (Frame) - 全屏黑色背景
       ├── LoadingImage (ImageLabel) - 随机显示的背景图片
       ├── ProgressBg (Frame) - 进度条背景
       │   ├── Progressbar (Frame) - 进度条填充（Size.X.Scale从0到1）
       │   └── Number (TextLabel) - 进度百分比显示（XX%格式）
       └── [其他装饰元素]

4. Loading背景图片资源（3张随机选择）：
   - rbxassetid://98877166419333
   - rbxassetid://111664305611167
   - rbxassetid://136231844959584

5. 加载阶段权重（用于进度计算）：
   - 服务端进度占60%权重
   - 客户端预加载占40%权重
   - 总进度 = 服务端进度 × 0.6 + 客户端进度 × 0.4

6. 加载流程说明：
   阶段1 - INIT (0%): 初始化开始
   阶段2 - DATA_LOADING (0-20%): 玩家数据加载
   阶段3 - HOME_SETUP (20-40%): 基地设置（等待HomeSlot分配）
   阶段4 - SCENE_SETUP (40-60%): 场景设置（商店/挂机金币等系统初始化）
   阶段5 - SYNC_DATA (60-80%): 数据同步（技能背包等同步到客户端）
   阶段6 - COMPLETE (100%): 加载完成

7. 客户端预加载内容：
   - 动画资源（所有兵种的Show/Idle/Move/Attack/Death动画）
   - 图标资源（所有兵种图标）
   - 技能图标（SkillConfig中的技能图标）
   - Loading背景图片

8. 超时保护：
   - 客户端60秒超时自动完成Loading
   - 防止因网络问题导致无限等待

9. 与现有预加载脚本的集成：
   - AnimationPreloader.lua: 检测到LoadingController后跳过独立预加载
   - IconPreloader.lua: 检测到LoadingController后跳过独立预加载
   - 保留原有脚本作为备份，当LoadingController未正常加载时自动启用


【V3.3任务系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/TaskEvents/ （新建文件夹）
🆕 TaskProgress (RemoteEvent) - 服务器→客户端：任务进度更新
🆕 TaskComplete (RemoteEvent) - 服务器→客户端：任务完成通知
🆕 ClaimTaskReward (RemoteEvent) - 客户端→服务器：领取任务奖励
🆕 ClaimRewardResult (RemoteEvent) - 服务器→客户端：领取结果

注意：服务端TaskSystem.lua会在初始化时自动创建这些事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "TaskEvents"
6. 右键点击 TaskEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "TaskProgress"
9. 重复步骤7-8，创建 "TaskComplete"
10. 重复步骤7-8，创建 "ClaimTaskReward"
11. 重复步骤7-8，创建 "ClaimRewardResult"
12. 保存游戏

功能说明：
- TaskProgress：服务器→客户端：任务进度更新
  参数：(taskData: table) 任务数据 {CurrentTaskId, CurrentProgress, RequiredCount, Description, RewardCoins, IsCompleted, AllTasksCompleted}
- TaskComplete：服务器→客户端：任务完成通知
  参数：(taskInfo: table) 完成的任务信息 {TaskId, Description, RewardCoins}
- ClaimTaskReward：客户端→服务器：领取任务奖励
  参数：无（服务器根据玩家当前任务处理）
- ClaimRewardResult：服务器→客户端：领取结果
  参数：(success: boolean, message: string, rewardCoins: number) 是否成功、消息和奖励金币数


【V3.3任务系统其他资源创建说明】

1. 任务配置模块位置：ReplicatedStorage/Config/TaskConfig

2. 服务端系统位置：ServerScriptService/Systems/TaskSystem

3. 客户端控制器位置：StarterPlayer/StarterPlayerScripts/UI/TaskDisplay

4. 任务UI结构：StarterGui/MainGui/TaskPanel/
   └── TaskPanel (Frame) - 任务面板
       ├── TaskDescription (TextLabel) - 任务描述文本
       ├── ProgressText (TextLabel) - 进度文本（如 "2/3"）
       ├── ProgressBar (Frame) - 进度条背景
       │   └── Fill (Frame) - 进度条填充
       ├── RewardText (TextLabel) - 奖励显示（如 "奖励: 100金币"）
       ├── ClaimButton (TextButton) - 领取按钮
       └── CompletedLabel (TextLabel) - 全部完成标签（可选）

5. 任务类型说明：
   - 类型1 PURCHASE_UNIT: 购买N次兵种
   - 类型2 PLACE_UNIT: 将N个兵布置到战场
   - 类型3 PURCHASE_SKILL: 购买N次技能
   - 类型4 COMPLETE_BATTLE: 完成一场战斗（点击attack后到弹出结算界面）
   - 类型5 COLLECT_IDLE_COIN: 领取一次挂机金币奖励

6. 任务进度触发点：
   - 购买兵种: ShopSystem.OnPurchaseUnit()
   - 布置兵种: PlacementSystem.OnConfirmPlacement()
   - 购买技能: SkillShopSystem.OnPurchaseSkill()
   - 完成战斗: CampaignManager.OnCampaignEnd()
   - 领取挂机金币: IdleCoinSystem.OnCollectRequest()


【V3.4.1战斗金币表现系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/BattleEvents/
🆕 CoinEarnedEffect (RemoteEvent) - 需在Studio中手动创建（或由服务端自动创建）

功能说明：
- CoinEarnedEffect：服务器→客户端：战斗金币获取表现通知
  参数：(amount: number, vipBonus: number) 获得的金币数量 / VIP额外加成
  触发时机：玩家在战斗中获得金币时（击杀敌人/前进奖励）

客户端效果：
- 在屏幕中央区域显示金币数值
- 金币数字做抛物线运动（烟花效果）
- 每次获得金币都会触发一次表现

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events > BattleEvents
3. 右键点击 BattleEvents 文件夹
4. 选择 "Insert Object" > "RemoteEvent"
5. 将新建的 RemoteEvent 重命名为 "CoinEarnedEffect"
6. 保存游戏

注意：服务端CurrencySystem.lua会在初始化时自动创建这个事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。


【V3.4.1战斗金币表现系统其他资源创建说明】

1. 客户端控制器位置：StarterPlayer/StarterPlayerScripts/UI/CoinNumShowController

2. 金币显示模板位置：ReplicatedStorage/CoinNumShow/
   └── CoinNumShow (TextLabel) - 金币数字模板
       - Visible: false
       - BackgroundTransparency: 1
       - Font: GothamBold
       - TextColor3: (255, 215, 0) 金色
       - TextStrokeColor3: (139, 69, 19) 棕色
       - TextStrokeTransparency: 0

3. 如果模板不存在，客户端会自动创建默认模板

4. 表现效果配置（在CoinNumShowController.lua中可调整）：
   - 抛洒区域：屏幕中央偏上
   - 初始速度：随机X方向，向上Y方向
   - 重力加速度：400像素/秒²
   - 动画时长：1.2秒
   - 淡出时间：0.8秒开始淡出


【V3.5新手引导系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/GuideEvents/ （新建文件夹）
🆕 StartGuide (RemoteEvent) - 服务器→客户端：开始引导
🆕 CompleteGuide (RemoteEvent) - 服务器→客户端：完成引导
🆕 GuideArrived (RemoteEvent) - 客户端→服务器：到达目标
🆕 SyncGuideData (RemoteEvent) - 服务器→客户端：同步引导数据
🆕 RequestGuideSync (RemoteEvent) - 客户端→服务器：请求同步

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "GuideEvents"
6. 右键点击 GuideEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "StartGuide"
9. 重复步骤7-8，创建 "CompleteGuide"
10. 重复步骤7-8，创建 "GuideArrived"
11. 重复步骤7-8，创建 "SyncGuideData"
12. 重复步骤7-8，创建 "RequestGuideSync"
13. 保存游戏

功能说明：
- StartGuide：服务器→客户端：开始引导
  参数：(guideId: number, targetPosition: Vector3) 引导ID和目标位置
- CompleteGuide：服务器→客户端：完成引导
  参数：(guideId: number) 引导ID (0表示清除所有引导)
- GuideArrived：客户端→服务器：到达目标
  参数：(guideId: number) 引导ID
- SyncGuideData：服务器→客户端：同步引导数据
  参数：(guideData: table) 引导数据 {CompletedGuides = {[guideId] = true}}
- RequestGuideSync：客户端→服务器：请求同步引导数据
  参数：无（服务器根据玩家身份处理）

注意：服务端GuideSystem.lua会在初始化时自动创建这些事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。


【V3.5新手引导系统其他资源创建说明】

1. 引导配置模块位置：ReplicatedStorage/Config/GuideConfig

2. 服务端系统位置：ServerScriptService/Systems/GuideSystem

3. 客户端控制器位置：StarterPlayer/StarterPlayerScripts/Controllers/GuideController

4. 引导资源位置：Workspace/Effect/
   - Guide01 (Part/Model) - 起始点，绑定到玩家躯干
   - Guide02 (Part/Model) - 终点，放在目标位置
   - 两个Part之间可以设置Beam连线形成引导箭头效果

5. 引导目标位置（每个玩家家园下需要存在）：
   - Home/PlayerHomeX/KeepShoper01 - 兵种商店NPC
   - Home/PlayerHomeX/Mail - 挂机金币邮箱

6. 引导配置说明（GuideConfig.lua）：
   - GuideId: 引导唯一ID (1001, 1002...)
   - GuideType: 引导类型 (SHOP/MAIL)
   - TargetName: 目标对象名称
   - TriggerCondition: 触发条件 (FIRST_JOIN/HAS_IDLE_COINS)
   - ArrivalDistance: 到达判定距离(studs)

7. GM命令：
   - /triggerguide <guideId> - 触发指定引导
   - /resetguide <guideId> - 重置指定引导
   - /resetallguides - 重置所有引导
   - /listguides - 查看所有引导状态

8. 数据存储：
   - DataManager.GuideData.CompletedGuides 记录已完成的引导
   - 完成的引导ID存储为 {[guideId] = true} 格式


【V3.6战场进度系统说明】

功能描述：
- 在挑战过程中实时显示玩家的关卡进度
- 以玩家家里的IdleFloor为起点，最后一关的IdleFloor为终点
- 进度条上的玩家头像位置随战场中心移动而实时更新

UI结构（需要在Studio中创建）：
1. StarterGui/Distance/Bg (Frame) - 进度条背景容器
   - 初始Visible: false
   - 战斗开始时显示，战斗结束时隐藏

2. StarterGui/Distance/Bg/ProgressBg (Frame) - 进度条背景
   - 代表整个关卡的总长度(Size.X.Scale = 1)

3. StarterGui/Distance/Bg/ProgressBg/PlayerIcon (ImageLabel) - 玩家头像
   - 初始Position: {0, 0}, {0.5, 0}
   - X坐标使用Scale: 0代表起点，1代表终点
   - Y坐标固定为0.5
   - 图片会自动设置为玩家的头像

客户端控制器位置：
- StarterPlayer/StarterPlayerScripts/Controllers/DistanceProgressController

CampaignStateUpdate事件变更（V3.6）：
- 原参数：(state, stageNum)
- 新参数：(state, stageNum, chapter?, totalStagesInChapter?)
- 新增参数仅在state="Preparing"时发送
- chapter: 当前章节ID
- totalStagesInChapter: 该章节的总关卡数

进度计算逻辑：
1. 起点：玩家家园的IdleFloor位置(Z坐标)
2. 终点：最后一关的IdleFloor位置(Z坐标，根据配置估算)
3. 当前位置：所有友军单位的质心位置
4. 进度 = (起点Z - 当前Z) / (起点Z - 终点Z)
5. 进度范围：0到1，对应X轴Position.Scale

注意事项：
- 本功能不需要新增RemoteEvent
- 复用现有的CampaignStateUpdate事件，仅新增可选参数
- 客户端通过监听战役状态变化来控制UI显示/隐藏
- 进度更新使用RenderStepped实现平滑过渡


【V3.8音效系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/SoundEvents/ （新建文件夹）
🆕 PlayBGM (RemoteEvent) - 服务器→客户端：播放BGM
🆕 StopBGM (RemoteEvent) - 服务器→客户端：停止BGM
🆕 PlaySFX (RemoteEvent) - 服务器→客户端：播放一次性音效
🆕 StopSFX (RemoteEvent) - 服务器→客户端：停止一次性音效

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "SoundEvents"
6. 右键点击 SoundEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "PlayBGM"
9. 重复步骤7-8，创建 "StopBGM"
10. 重复步骤7-8，创建 "PlaySFX"
11. 重复步骤7-8，创建 "StopSFX"
12. 保存游戏

功能说明：
- PlayBGM：服务器→客户端：播放BGM
  参数：(bgmKey: string) BGM键名 ("Home" 或 "Battle")
- StopBGM：服务器→客户端：停止BGM
  参数：无
- PlaySFX：服务器→客户端：播放一次性音效
  参数：(sfxKey: string) SFX键名 ("CoinsTrigger"/"Victory"/"Merge"/"Error")
- StopSFX：服务器→客户端：停止一次性音效
  参数：(sfxKey: string) SFX键名

注意：服务端SoundSystem.lua会在初始化时自动创建这些事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。


【V3.8音效系统其他资源创建说明】

1. 音效配置模块位置：ReplicatedStorage/Config/SoundConfig

2. 服务端系统位置：ServerScriptService/Systems/SoundSystem

3. 客户端控制器位置：StarterPlayer/StarterPlayerScripts/SoundController

4. 音效资源结构（由客户端自动创建）：
   SoundService/
   ├── BGM/
   │   ├── Home/
   │   │   └── Road To War (Underscore Version) (Sound)
   │   └── Battle/
   │       └── Urban Racer (Alt Vs) (Sound)
   └── Audio/
       └── Common/
           ├── CoinsTrigger (Sound)
           ├── Victory royale (Sound)
           ├── Merge (Sound)
           └── Error Sound 1 (Sound)

5. 音效资源ID：
   - 通用BGM: rbxassetid://1842908030
   - 战斗BGM: rbxassetid://1838627590
   - 领取金币音效: rbxassetid://99023919906775
   - 胜利音效: rbxassetid://5205229311
   - 合成音效: rbxassetid://7393525156
   - 错误音效: rbxassetid://8400918001

6. 音效触发点：
   - 玩家加入游戏：MainServer → SoundSystem.OnPlayerJoin() → 播放Home BGM
   - 战斗开始：CampaignManager.StartCampaign() → SoundSystem.OnBattleStart() → 切换到Battle BGM
   - 战斗结束：CampaignManager.CompleteCampaignEnd() → SoundSystem.OnBattleEnd() → 切换回Home BGM
   - 结算界面弹出：CampaignManager.OnCampaignEnd() → SoundSystem.OnVictoryShow() → 播放Victory音效
   - 确认结算：CampaignManager.CompleteCampaignEnd() → SoundSystem.OnVictoryConfirm() → 停止Victory音效
   - 领取挂机金币：IdleCoinSystem.OnCollectRequest() → SoundSystem.OnCollectIdleCoins() → 播放CoinsTrigger音效
   - 兵种合成：MergeSystem.MergeUnits() → SoundSystem.OnMerge() → 播放Merge音效
   - 购买失败（金币不足）：ShopSystem/SkillShopSystem → SoundSystem.OnPurchaseError() → 播放Error音效

7. BGM切换特性：
   - BGM切换带有淡入淡出效果（默认0.5秒）
   - 如果已在播放相同BGM，不会重复播放
   - 使用TweenService实现平滑音量过渡

8. 客户端公共接口（通过_G.SoundController访问）：
   - SoundController.PlayBGM(bgmKey) - 手动播放BGM
   - SoundController.StopBGM() - 手动停止BGM
   - SoundController.PlaySFX(sfxKey) - 手动播放SFX
   - SoundController.StopSFX(sfxKey) - 手动停止SFX
   - SoundController.IsInitialized() - 检查是否已初始化
   - SoundController.GetCurrentBGMKey() - 获取当前BGM键名


【V4.0客户端AI迁移系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/ClientAIEvents/ （新建文件夹）
🆕 InitializeBattle (RemoteEvent) - 需在Studio中手动创建
🆕 SyncUnitPosition (RemoteEvent) - 需在Studio中手动创建
🆕 TerminateBattle (RemoteEvent) - 需在Studio中手动创建
🆕 ServerUnitDeath (RemoteEvent) - 需在Studio中手动创建
🆕 RequestAttack (RemoteEvent) - 需在Studio中手动创建
🆕 ReportUnitPosition (RemoteEvent) - 需在Studio中手动创建
🆕 ClientBattleReady (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "ClientAIEvents"
6. 右键点击 ClientAIEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "InitializeBattle"
9. 重复步骤7-8，创建 "SyncUnitPosition"
10. 重复步骤7-8，创建 "TerminateBattle"
11. 重复步骤7-8，创建 "ServerUnitDeath"
12. 重复步骤7-8，创建 "RequestAttack"
13. 重复步骤7-8，创建 "ReportUnitPosition"
14. 重复步骤7-8，创建 "ClientBattleReady"
15. 保存游戏

功能说明：
- InitializeBattle：服务器→客户端：初始化战斗
  参数：(battleId: number, attackUnits: table, defenseUnits: table, battleField: Folder)
  说明：战斗开始时服务端通知客户端，下发所有单位信息和战场引用

- SyncUnitPosition：服务器→客户端：同步单位位置
  参数：(battleId: number, unitModel: Model, position: Vector3)
  说明：服务端定期向客户端同步位置，客户端进行矫正（防作弊）

- TerminateBattle：服务器→客户端：终止战斗
  参数：(battleId: number, result: string)
  说明：战斗结束时服务端通知客户端，清理所有AI

- ServerUnitDeath：服务器→客户端：单位死亡通知
  参数：(battleId: number, unitModel: Model, killerModel: Model|nil)
  说明：服务端确认单位死亡后通知客户端，客户端播放死亡动画并清理AI

- RequestAttack：客户端→服务器：请求攻击
  参数：(battleId: number, attackerModel: Model, targetModel: Model, attackType: string)
  说明：客户端AI判定发起攻击时请求服务端校验并执行伤害计算
  attackType: "Melee" 或 "Ranged"

- ReportUnitPosition：客户端→服务器：上报位置
  参数：(battleId: number, unitModel: Model, position: Vector3, state: string)
  说明：客户端定期向服务端报告单位位置和状态（每0.5秒），用于防作弊校验
  state: "Idle"/"Seeking"/"Moving"/"Attacking"/"Dead"

- ClientBattleReady：客户端→服务器：客户端准备完成
  参数：(battleId: number)
  说明：客户端AI系统初始化完成后通知服务端，可以开始战斗

注意：服务端BattleManager.lua和CombatSystem.lua会在初始化时自动创建这些事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。


【V4.1客户端行军系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/ClientAIEvents/ （已存在文件夹）
🆕 StartMarch (RemoteEvent) - 需在Studio中手动创建
🆕 MarchComplete (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events > ClientAIEvents
3. 右键点击 ClientAIEvents 文件夹
4. 选择 "Insert Object" > "RemoteEvent"
5. 将新建的 RemoteEvent 重命名为 "StartMarch"
6. 重复步骤4-5，创建 "MarchComplete"
7. 保存游戏

功能说明：
- StartMarch：服务器→客户端：通知客户端开始行军
  参数：(battleId: number, moveTargets: table, stageNum: number, marchToken: string)
  说明：服务端在CampaignManager.MarchToStage时通知客户端开始行军
  moveTargets格式：数组格式 {{unitName=string, targetCFrame=CFrame}, ...}
  注意：由于RemoteEvent无法序列化Instance作为table的key，使用unitName标识单位
  marchToken说明：本次行军的唯一Token，用于服务端校验MarchComplete的延迟/乱序包

- MarchComplete：客户端→服务器：客户端报告行军完成
  参数：(battleId: number, stageNum: number, marchToken: string, arrivedList: table, failedList: table)
  说明：客户端行军完成后通知服务端，报告到达和失败的单位列表
  arrivedList格式：{unitModel1, unitModel2, ...}
  failedList格式：{unitModel1, unitModel2, ...}

注意：
1. 行军系统由客户端完全控制，服务端仅发送指令并接收结果
2. 客户端使用ClientMarchService处理行军逻辑（寻路、移动、到达检测）
3. 行军兜底：客户端可在卡住/超时/走错路时将单位瞬移到目标点，服务端对结果做距离/时间合理性校验
4. 服务端可根据需要对行军结果进行校验（距离、时间合理性）


【V4.0客户端AI迁移系统其他资源创建说明】

1. 客户端AI模块位置：StarterPlayer/StarterPlayerScripts/ClientAI/
   需要创建以下文件：
   - ClientUnitManager.lua (ModuleScript) - 客户端单位管理器
   - ClientPathService.lua (ModuleScript) - 客户端寻路服务
   - ClientUnitAI.lua (ModuleScript) - 客户端AI核心逻辑
   - ClientAIBootstrap.lua (LocalScript) - 客户端AI启动脚本

2. 服务端系统修改：
   - ServerScriptService/Systems/CombatSystem.lua - 新增客户端攻击请求处理
   - ServerScriptService/Systems/BattleManager.lua - 新增客户端AI初始化/停止
   - ServerScriptService/Systems/CampaignManager.lua - 传递BattleField引用
   - ServerScriptService/Systems/UnitAI.lua - 添加客户端AI检查

3. 配置文件修改：ReplicatedStorage/Config/BattleConfig.lua
   需要新增以下配置：
   ```lua
   -- ==================== V4.0 客户端AI配置 ====================
   -- 是否启用客户端AI（渐进式迁移开关）
   BattleConfig.ENABLE_CLIENT_AI = true

   -- 客户端上报位置间隔（秒）
   BattleConfig.CLIENT_POSITION_REPORT_INTERVAL = 0.5

   -- 服务端位置同步间隔（秒）
   BattleConfig.SERVER_POSITION_SYNC_INTERVAL = 1.0

   -- 位置校验容差（studs）- 超过此值服务端强制同步
   BattleConfig.POSITION_VALIDATION_TOLERANCE = 10

   -- 攻击请求超时时间（秒）
   BattleConfig.ATTACK_REQUEST_TIMEOUT = 0.2
   ```

4. 性能优化效果（理论值）：
   - 服务端AI计算：200次/帧 → 0次/帧（100%降低）
   - 服务端寻路请求：~50次/秒 → 0次/秒（100%降低）
   - 客户端帧率(100v100)：~20 FPS → ~45 FPS（125%提升）
   - 网络流量：位置同步为主 → 攻击请求为主（减少）

5. 防作弊机制：
   - 服务端权威伤害计算（客户端只能请求攻击）
   - 攻击距离校验（1.5倍容差）
   - 攻击阶段验证（必须Idle才能攻击）
   - 队伍验证（不能攻击友军）
   - 位置偏差检测（10 studs容差）

6. 回滚方案：
   如果客户端AI出现问题，可以通过设置 BattleConfig.ENABLE_CLIENT_AI = false 快速回退到服务端AI模式


【V3.9房屋升级镜头表现系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/HouseUpgradeEvents/ （新建文件夹）
🆕 StartUpgradeSequence (RemoteEvent) - 需在Studio中手动创建（或由服务端自动创建）
🆕 ClientCameraReady (RemoteEvent) - 需在Studio中手动创建（或由服务端自动创建）
🆕 HouseUpgradePopupClosed (RemoteEvent) - 需在Studio中手动创建（或由服务端自动创建）
🆕 UpgradeSequenceComplete (RemoteEvent) - 需在Studio中手动创建（或由服务端自动创建）

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "HouseUpgradeEvents"
6. 右键点击 HouseUpgradeEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "StartUpgradeSequence"
9. 重复步骤7-8，创建 "ClientCameraReady"
10. 重复步骤7-8，创建 "HouseUpgradePopupClosed"
11. 重复步骤7-8，创建 "UpgradeSequenceComplete"
12. 保存游戏

功能说明：
- StartUpgradeSequence：服务器→客户端：开始房屋升级镜头表现
  参数：(homeSlot: number, oldModelName: string, newModelName: string) 玩家基地编号(1-6)
  触发时机：玩家通关章节后点击胜利弹窗确认，重生在基地时

- ClientCameraReady：客户端→服务器：镜头就位通知
  参数：无（服务器根据玩家身份处理）
  触发时机：客户端镜头移动到位后通知服务端可以替换房屋

- HouseUpgradePopupClosed：客户端→服务器：房屋升级弹框关闭通知
  参数：无（服务端根据玩家身份处理）
  触发时机：玩家点击任意区域关闭升级弹框后

- UpgradeSequenceComplete：客户端→服务器：镜头表现完成
  参数：无（服务器根据玩家身份处理）
  触发时机：镜头表现结束并恢复玩家视角后

注意：服务端HouseUpgradeSystem.lua会在初始化时自动创建这些事件（如果不存在），
但建议手动创建以确保事件在系统初始化前就存在。


【V3.9房屋升级镜头表现系统其他资源创建说明】

1. 服务端系统位置：ServerScriptService/Systems/HouseUpgradeSystem
   - V3.9新增：ReplaceHouseModelWithCinematic() 带镜头表现的房屋升级
   - V3.9修改：OnChapterCompleted() 支持useCinematic参数

2. 客户端控制器位置：StarterPlayer/StarterPlayerScripts/Controllers/HouseUpgradeCameraController
   - 负责接收服务端通知并控制镜头表现
   - 自动初始化，无需手动调用

3. 房屋升级表现流程：
   阶段1：玩家通关章节后点击胜利弹窗确认
   阶段2：玩家重生在基地（传送到SpawnLocation）
   阶段3：服务端通知客户端开始镜头表现（StartUpgradeSequence）
   阶段4：客户端镜头拉高看向房屋（1秒Tween动画）
   阶段5：等待1秒（让玩家看清楚旧房屋）
   阶段6：服务端替换房屋（旧房屋消失，新房屋出现）
   阶段7：等待1秒（让玩家看清楚新房屋）
   阶段8：客户端恢复镜头控制

4. 镜头参数配置（在HouseUpgradeCameraController.lua中可调整）：
   - CAMERA_HEIGHT = 30 studs（镜头高度）
   - CAMERA_DISTANCE = 40 studs（镜头距离房屋的距离）
   - CAMERA_ANGLE = 30度（镜头俯视角度）
   - TWEEN_DURATION = 1.0秒（镜头移动时长）
   - WAIT_BEFORE_REPLACE = 1.0秒（房屋替换前等待时间）
   - WAIT_AFTER_REPLACE = 1.0秒（房屋替换后等待时间）

5. 与现有系统的集成：
   - CampaignManager.OnVictory()：通关章节时标记PendingHouseUpgrade
   - CampaignManager.CompleteCampaignEnd()：玩家确认后触发房屋升级表现
   - HouseUpgradeSystem.OnChapterCompleted()：执行房屋升级逻辑
   - 房屋模板路径：ReplicatedStorage/House/PrisonLv1, PrisonLv2...

6. 注意事项：
   - 房屋升级只在通关章节且满足升级条件时触发
   - 镜头表现期间玩家无法控制镜头
   - 房屋替换保持底部中心位置对齐
   - 支持关闭镜头表现（useCinematic=false）用于调试


【V3.9.1房屋升级特效说明】

功能描述：
- 房屋替换时播放HouseChange特效
- 特效在新房屋出现的瞬间播放
- 特效持续1秒后自动移除

特效资源位置：
- ReplicatedStorage/Effect/HouseChange (Part)
- 该Part下绑定着特效内容（粒子/光效等）

特效播放逻辑：
1. 房屋替换时，从ReplicatedStorage/Effect复制HouseChange
2. 将特效的轴点与新房屋的轴点位置对齐
3. 特效出现1.5秒后自动移除

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Effect
3. 如果Effect文件夹不存在，先创建Effect文件夹
4. 在Effect文件夹下创建一个Part，命名为"HouseChange"
5. 在HouseChange Part下添加所需的特效（ParticleEmitter/PointLight/Beam等）
6. 将HouseChange Part的Anchored属性设为true
7. 将HouseChange Part的CanCollide属性设为false
8. 将HouseChange Part的Transparency属性设为1（透明，只显示特效）
9. 保存游戏

配置参数：
- HouseUpgradeSystem.lua:
  - HOUSE_CHANGE_EFFECT_DURATION = 1.5秒（特效持续时间）
- HouseUpgradeCameraController.lua:

V6.1 Online Reward RemoteEvents
Location: ReplicatedStorage/Events/OnlineRewardEvents
- RequestOnlineRewardData (RemoteEvent) - Client -> Server: request online reward data
- OnlineRewardData (RemoteEvent) - Server -> Client: online reward data(totalOnlineSeconds, claimedRewards, serverTime, lastRefreshDay)
- ClaimOnlineReward (RemoteEvent) - Client -> Server: claim online reward(rewardId)
- ClaimOnlineRewardResult (RemoteEvent) - Server -> Client: claim result(success, message, rewardInfo, rewardId)
  - WAIT_AFTER_REPLACE = 3.0秒（房屋替换后等待时间，即镜头解锁前的等待）


【V3.9.2战斗力系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/PowerEvents/ （新建文件夹）
✅ PowerUpdate (RemoteEvent) - 服务端自动创建

注意：PowerSystem.lua会在初始化时自动创建这些事件（如果不存在），
**无需手动创建**，系统会自动处理。

创建步骤（可选，如果系统未自动创建）：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "PowerEvents"
6. 右键点击 PowerEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "PowerUpdate"
9. 保存游戏

功能说明：
- PowerUpdate：服务器→客户端：同步战斗力数值
  参数：(totalPower: number) 玩家总战斗力
  触发时机：
    - 玩家加入游戏时（初始化）
    - 添加兵种时
    - 删除兵种时
    - 兵种合成升级时
    - 兵种放置/回收时（通过重算触发）


【V3.9.2战斗力系统其他资源创建说明】

1. 战斗力配置模块位置：ReplicatedStorage/Config/PowerConfig
   需要创建PowerConfig.lua配置文件，定义战斗力计算规则

2. 服务端系统位置：ServerScriptService/Systems/PowerSystem
   已存在，自动初始化

3. 客户端控制器位置：StarterPlayer/StarterPlayerScripts/Controllers/PowerController（需要创建）
   负责接收战斗力更新并显示UI

4. 战斗力UI结构（需要在Studio中创建）：
   StarterGui/MainGui/PowerPanel/ （建议添加到MainGui中）
   └── PowerPanel (Frame) - 战斗力显示面板
       ├── PowerIcon (ImageLabel) - 战斗力图标
       ├── PowerValue (TextLabel) - 战斗力数值显示
       └── PowerLabel (TextLabel) - "战斗力"文字标签（可选）

5. 战斗力计算触发点：
   - InventorySystem.AddUnit() → PowerSystem.OnAddUnit()
   - InventorySystem.RemoveUnit() → PowerSystem.OnRemoveUnit()
   - MergeSystem.MergeUnits() → PowerSystem.OnMergeUnit()（需集成）
   - PlacementSystem放置/回收 → 通过Units数组变化自动重算

6. 数据持久化：
   - 战斗力实时计算，不直接存储
   - 基于玩家Units数组（包含背包和已放置兵种）
   - 兼容旧存档（Inventory + PlacedUnits）

7. 性能优化：
   - 使用playerPowerCache缓存计算结果
   - 避免频繁重复计算
   - 操作触发时直接重算确保准确性

8. 调试模式：
   在PowerSystem.lua中设置 DEBUG = true 可以查看详细日志


【V4.7排行榜系统RemoteEvent创建说明】
位置：ReplicatedStorage/Events/LeaderboardEvents/ （新建文件夹）
?? RequestLeaderboard (RemoteEvent) - 需在Studio中手动创建
?? LeaderboardData (RemoteEvent) - 需在Studio中手动创建

创建步骤：
1. 打开Roblox Studio
2. 导航到 ReplicatedStorage > Events
3. 右键点击 Events 文件夹
4. 选择 "Insert Object" > "Folder"
5. 将新建的 Folder 重命名为 "LeaderboardEvents"
6. 右键点击 LeaderboardEvents 文件夹
7. 选择 "Insert Object" > "RemoteEvent"
8. 将新建的 RemoteEvent 重命名为 "RequestLeaderboard"
9. 重复步骤7-8，创建 "LeaderboardData"
10. 保存游戏

功能说明：
- RequestLeaderboard：客户端→服务器：请求排行榜数据
  参数：无
- LeaderboardData：服务器→客户端：返回排行榜数据
  参数：(entries, nextRefreshTime, serverTime)
