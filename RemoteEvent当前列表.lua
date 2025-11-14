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
        └──ShowDamageNumber（RemoteEvent） 【V1.5.1新增】 - 服务端通知客户端显示伤害数字
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


