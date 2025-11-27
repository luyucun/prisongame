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
        └──VictoryConfirm（RemoteEvent） 【V2.4新增】 - 客户端→服务器：确认战斗结算(battleId)
    └──CampaignEvents（Folder）/  【V2.0新增】
        ├──RequestStartCampaign（RemoteEvent） - 客户端→服务器：请求开始战役
        ├──RequestRetreat（RemoteEvent） - 客户端→服务器：请求撤退
        ├──CampaignStateUpdate（RemoteEvent） - 服务器→客户端：战役状态更新(state, stageNum)
        ├──StageProgress（RemoteEvent） - 服务器→客户端：关卡进度更新(stageNum, status)
        └──LockHomeOperations（RemoteEvent） - 服务器→客户端：锁定/解锁基地操作(locked)
    └──ShopEvents（Folder）/  【V2.1新增】
        ├──RequestShopList（RemoteEvent） - 客户端→服务器：请求商店列表
        ├──ShopList（RemoteEvent） - 服务器→客户端：返回商品数据数组（含库存信息）
        ├──PurchaseUnit（RemoteEvent） - 客户端→服务器：请求购买兵种(unitId)
        ├──PurchaseResult（RemoteEvent） - 服务器→客户端：返回购买结果(success,message,unitId,newCoins)
        ├──StockUpdate（RemoteEvent） 【V2.1库存系统】✅已实现 - 服务器→客户端：库存更新通知(shopId, stockData)
        └──RefreshTimeUpdate（RemoteEvent） 【V2.1库存系统】✅已实现 - 服务器→客户端：刷新倒计时更新(remainingTime)
    └──IdleCoinEvents（Folder）/  【V2.6新增】
        ├──CollectIdleCoins（RemoteEvent） - 客户端→服务器：请求领取挂机金币
        └──SyncIdleCoins（RemoteEvent） - 服务器→客户端：同步待领取金币数量(coins)


如果需要补充新的RemoteEvent或者Remotefunction，请在这里列出来，我会自己去创建

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