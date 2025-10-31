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
        └──UnitDeath（BindableEvent） - 服务端内部兵种死亡通知



如果需要补充新的RemoteEvent或者Remotefunction，请在这里列出来，我会自己去创建

