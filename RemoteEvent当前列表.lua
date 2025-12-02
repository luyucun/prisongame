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