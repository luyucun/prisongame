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
    └──PlacementEvents（Folder）/  【V1.2新增】
        ├──StartPlacement（RemoteEvent） - 客户端请求开始放置兵种
        ├──ConfirmPlacement（RemoteEvent） - 客户端确认放置兵种
        ├──CancelPlacement（RemoteEvent） - 客户端取消放置兵种
        └──PlacementResponse（RemoteEvent） - 服务端返回放置结果



如果需要补充新的RemoteEvent或者Remotefunction，请在这里列出来，我会自己去创建

