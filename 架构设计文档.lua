--[[
=====================================================
游戏整体架构设计文档
=====================================================

项目名称: Roblox 兵种塔防游戏
版本: V1.0
设计日期: 2025-10-28

=====================================================
一、架构设计原则
=====================================================

1. 客户端-服务端分离架构
   - 服务端负责数据管理、权威验证、玩家分配
   - 客户端负责UI显示、用户交互、视觉效果

2. 模块化设计
   - 每个功能模块独立封装
   - 模块间通过事件/接口通信
   - 便于后续功能扩展

3. 数据驱动
   - 玩家数据统一管理
   - 数据变更通过事件通知
   - 客户端监听数据变化实时更新UI

4. 可扩展性
   - 预留接口支持多种货币获取方式
   - 支持后续添加兵种系统、战斗系统等

=====================================================
二、目录结构设计
=====================================================

ServerScriptService/          (服务端脚本目录)
├── Core/                      (核心系统)
│   ├── DataManager.lua        (数据管理器 - 负责玩家数据的加载/保存/管理)
│   └── PlayerManager.lua      (玩家管理器 - 负责玩家进入/离开/基地分配)
│
├── Systems/                   (游戏系统)
│   ├── CurrencySystem.lua     (货币系统 - 负责金币的增减/验证)
│   ├── HomeSystem.lua         (基地系统 - 负责基地管理和初始化)
│   ├── InventorySystem.lua    (背包系统 - 负责兵种背包管理)
│   ├── PlacementSystem.lua    (放置系统 - 负责兵种放置验证 V1.2)
│   └── GMCommandSystem.lua    (GM命令系统 - 负责调试命令处理)
│
└── Config/                    (配置文件)
    ├── GameConfig.lua         (游戏配置 - 存储游戏常量和配置)
    ├── UnitConfig.lua         (兵种配置 - 存储兵种属性)
    └── PlacementConfig.lua    (放置配置 - 存储放置系统配置 V1.2)

StarterPlayer/
└── StarterPlayerScripts/      (客户端脚本目录)
    ├── UI/                    (UI相关脚本)
    │   ├── CoinDisplay.lua    (金币显示控制器)
    │   └── BackpackDisplay.lua (背包显示控制器)
    │
    ├── Controllers/           (客户端控制器)
    │   ├── PlayerController.lua (玩家控制器 - 客户端玩家逻辑)
    │   └── PlacementController.lua (放置控制器 - 兵种放置交互 V1.2)
    │
    └── Utils/                 (工具类)
        ├── UIHelper.lua       (UI辅助工具)
        ├── PlacementHelper.lua (放置辅助工具 - 网格吸附/边界检测 V1.2)
        └── HighlightHelper.lua (高光辅助工具 - 模型高光效果 V1.2)

ReplicatedStorage/             (共享资源目录)
├── Events/                    (远程事件)
│   ├── CurrencyEvents         (货币相关事件 RemoteEvent)
│   ├── PlayerEvents           (玩家相关事件 RemoteEvent)
│   ├── InventoryEvents/       (背包相关事件 Folder)
│   │   ├── InventoryRefresh   (背包刷新 RemoteEvent)
│   │   ├── RequestInventory   (请求背包 RemoteEvent)
│   │   └── UnitUpdated        (兵种更新 RemoteEvent)
│   └── PlacementEvents/       (放置相关事件 Folder V1.2)
│       ├── StartPlacement     (开始放置 RemoteEvent)
│       ├── ConfirmPlacement   (确认放置 RemoteEvent)
│       ├── CancelPlacement    (取消放置 RemoteEvent)
│       └── PlacementResponse  (放置响应 RemoteEvent)
│
└── Modules/                   (共享模块)
    └── FormatHelper.lua       (格式化辅助工具 - 如金币显示格式化)

Workspace/
└── Home/                      (基地区域)
    ├── PlayerHome1/           (1号玩家基地)
    │   └── SpawnLocation      (出生点)
    ├── PlayerHome2/           (2号玩家基地)
    ├── PlayerHome3/
    ├── PlayerHome4/
    ├── PlayerHome5/
    └── PlayerHome6/

StarterGui/
└── MainGui/                   (主界面)
    └── CoinNum                (金币显示TextLabel)

=====================================================
三、核心系统设计
=====================================================

【3.1 数据管理系统 - DataManager】
----------------------------------
职责:
- 管理玩家数据的加载和保存
- 提供数据获取和修改接口
- 处理数据持久化(后续版本对接DataStore)

数据结构:
PlayerData = {
    UserId = 玩家ID,
    Currency = {
        Coins = 100,  -- 金币数量,初始100
    },
    HomeSlot = 1,     -- 分配的基地编号(1-6)
    Units = {},       -- 拥有的兵种数据(后续版本)
}

主要接口:
- GetPlayerData(player) : 获取玩家数据
- UpdateCurrency(player, amount, reason) : 更新货币
- SavePlayerData(player) : 保存玩家数据


【3.2 玩家管理系统 - PlayerManager】
----------------------------------
职责:
- 处理玩家进入游戏
- 随机分配可用基地(1-6)
- 传送玩家到对应基地
- 处理玩家离开释放基地

主要功能:
- 维护6个基地的占用状态
- 随机分配空闲基地
- 玩家离开时释放基地供新玩家使用

基地分配逻辑:
1. 玩家进入时检查所有基地占用状态
2. 从空闲基地(1-6)中随机选择一个
3. 标记基地为已占用
4. 传送玩家到对应SpawnLocation
5. 玩家离开时释放基地


【3.3 货币系统 - CurrencySystem】
----------------------------------
职责:
- 提供货币增减接口
- 验证货币操作合法性
- 通知客户端货币变化

货币获取渠道(预留接口):
1. AddCoinsFromBattle(player, amount) : 战斗获得金币
2. AddCoinsFromIdle(player, amount) : 挂机获得金币
3. AddCoinsFromPurchase(player, productId) : 购买获得金币

事件通知:
- 货币变化时通过RemoteEvent通知客户端更新UI


【3.4 基地系统 - HomeSystem】
----------------------------------
职责:
- 管理玩家基地的初始化
- 后续支持基地内容加载(兵种放置等)

主要功能:
- 根据玩家分配的基地编号初始化基地
- 为后续兵种放置预留扩展接口

=====================================================
四、客户端系统设计
=====================================================

【4.1 金币显示控制器 - CoinDisplay】
----------------------------------
职责:
- 监听服务端货币变化事件
- 实时更新UI显示金币数量
- 格式化显示: $XXXXX

工作流程:
1. 玩家进入时获取初始金币数量
2. 监听CurrencyChanged事件
3. 收到事件后更新TextLabel文本
4. 使用FormatHelper格式化显示


【4.2 玩家控制器 - PlayerController】
----------------------------------
职责:
- 管理客户端玩家状态
- 处理玩家输入
- 协调各个客户端模块

=====================================================
五、通信机制设计
=====================================================

【5.1 RemoteEvent 事件列表】
----------------------------------
ReplicatedStorage.Events.CurrencyEvents/
├── UpdateCurrency : Server -> Client
│   参数: newAmount (number)
│   说明: 通知客户端金币数量变化
│
└── RequestCurrency : Client -> Server
    参数: 无
    说明: 客户端请求当前金币数量


【5.2 数据流向】
----------------------------------
玩家进入游戏:
1. PlayerManager分配基地 -> 传送玩家
2. DataManager加载数据 -> 初始化玩家数据
3. Server触发UpdateCurrency -> Client更新UI

货币变化:
1. 服务端CurrencySystem处理货币变更
2. DataManager更新玩家数据
3. 触发RemoteEvent通知客户端
4. 客户端CoinDisplay更新UI显示

=====================================================
六、V1.0版本开发任务清单
=====================================================

【服务端开发】
1. Config/GameConfig.lua
   - 定义初始金币数量(100)
   - 定义最大玩家数(6)
   - 定义基地编号范围(1-6)

2. Core/DataManager.lua
   - 实现玩家数据结构
   - 实现数据初始化(初始金币100)
   - 实现数据获取接口
   - 实现货币更新接口

3. Core/PlayerManager.lua
   - 实现基地占用状态管理
   - 实现随机基地分配逻辑
   - 实现玩家传送到基地
   - 实现玩家离开释放基地

4. Systems/CurrencySystem.lua
   - 实现货币增减接口
   - 预留三种货币获取渠道接口
   - 实现客户端通知机制

5. Systems/HomeSystem.lua
   - 实现基地初始化
   - 为后续功能预留接口


【客户端开发】
6. ReplicatedStorage/Modules/FormatHelper.lua
   - 实现金币格式化函数: FormatCoins(amount) -> "$XXXXX"

7. ReplicatedStorage/Events/
   - 创建CurrencyEvents (RemoteEvent)
   - 创建PlayerEvents (RemoteEvent)

8. StarterPlayerScripts/UI/CoinDisplay.lua
   - 获取StarterGui.MainGui.CoinNum引用
   - 监听货币变化事件
   - 实时更新UI显示
   - 使用格式化工具显示金币


【测试验证】
9. 测试多玩家进入时基地随机分配
10. 测试金币UI实时显示
11. 测试玩家离开后基地释放

=====================================================
七、后续版本扩展预留
=====================================================

【V1.2 已完成功能】
- 兵种放置系统: 拖放兵种到基地
- 网格吸附系统: 自动对齐到格子
- 边界限制系统: 防止放置超出范围
- 高光预览系统: 放置前预览效果

【V2.0 预期功能】
- 商店系统: 购买兵种
- 兵种合成系统

【V3.0 预期功能】
- 关卡系统: 主线关卡挑战
- 战斗系统: 兵种自动战斗
- 奖励系统: 战斗获得金币

【V4.0 预期功能】
- 挂机系统: 离线收益
- 开发者产品: 付费购买金币
- 数据持久化: DataStoreService

【扩展性设计】
- 货币系统已预留三种获取渠道接口
- 基地系统预留兵种放置扩展
- 数据管理器支持扩展新的数据字段
- 模块化设计便于添加新系统

=====================================================
八、技术要点总结
=====================================================

1. 服务端权威
   - 所有数据修改在服务端完成
   - 客户端只负责显示和请求

2. 随机分配算法
   - 维护基地占用表
   - 从空闲基地中随机选择
   - 确保不重复分配

3. 事件驱动UI更新
   - 数据变化通过RemoteEvent通知
   - 客户端监听事件自动更新
   - 解耦数据逻辑和显示逻辑

4. 可扩展架构
   - 模块化设计便于后续添加功能
   - 预留接口支持新的货币获取方式
   - 数据结构支持扩展新字段

=====================================================
架构设计完成
=====================================================
]]