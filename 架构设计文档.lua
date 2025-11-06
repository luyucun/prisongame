--[[
=====================================================
游戏整体架构设计文档
=====================================================

项目名称: Roblox 兵种塔防游戏
当前版本: V1.5.5
最后更新: 2025-01-XX

=====================================================
一、架构设计原则
=====================================================

1. 客户端-服务端分离架构
   - 服务端: 数据管理、权威验证、游戏逻辑
   - 客户端: UI显示、用户交互、渲染表现

2. 模块化设计
   - 独立封装、事件通信、易于扩展

3. 数据驱动
   - 配置表驱动、统一管理、实时同步

4. 性能优化
   - AI节流、批量更新、资源预加载

=====================================================
二、目录结构
=====================================================

ServerScriptService/
├── Core/
│   ├── DataManager.lua          (数据管理)
│   └── PlayerManager.lua        (玩家管理)
├── Systems/
│   ├── CurrencySystem.lua       (货币系统)
│   ├── HomeSystem.lua           (基地系统)
│   ├── InventorySystem.lua      (背包系统)
│   ├── PlacementSystem.lua      (放置系统)
│   ├── MergeSystem.lua          (合成系统)
│   ├── PhysicsManager.lua       (物理管理)
│   ├── BattleManager.lua        (战斗管理)
│   ├── CombatSystem.lua         (战斗系统)
│   ├── UnitAI.lua               (兵种AI)
│   ├── ProjectileSystem.lua     (弹道系统)
│   ├── HitboxService.lua        (碰撞判定)
│   ├── UnitManager.lua          (单位索引)
│   ├── WeaponEffectSystem.lua   (武器特效 V1.5.4)
│   ├── BattleTestSystem.lua     (战斗测试)
│   └── GMCommandSystem.lua      (GM命令)

StarterPlayer/StarterPlayerScripts/
├── UI/
│   ├── CoinDisplay.lua          (金币显示)
│   ├── BackpackDisplay.lua      (背包显示)
│   └── BattleTestUI.lua         (战斗测试UI)
├── Controllers/
│   ├── PlacementController.lua  (放置控制)
│   ├── DragSystem.lua           (拖动系统)
│   └── RemovalController.lua    (回收控制)
├── Utils/
│   ├── PlacementHelper.lua      (放置辅助)
│   ├── HighlightHelper.lua      (高光辅助)
│   └── GridHelper.lua           (网格辅助)
└── AnimationPreloader.lua       (动画预加载 V1.5.5)

ReplicatedStorage/
├── Config/
│   ├── GameConfig               (游戏配置)
│   ├── UnitConfig               (兵种配置)
│   ├── PlacementConfig          (放置配置)
│   └── BattleConfig             (战斗配置)
├── Events/                      (RemoteEvent事件)
│   ├── CurrencyEvents
│   ├── PlayerEvents
│   ├── InventoryEvents/
│   ├── PlacementEvents/
│   ├── MergeEvents/
│   └── BattleEvents/
└── Modules/
    └── FormatHelper.lua         (格式化工具)

=====================================================
三、核心系统概览
=====================================================

【3.1 数据管理】DataManager
- 玩家数据加载/保存
- 初始金币: 100
- 支持扩展DataStore持久化

【3.2 玩家管理】PlayerManager
- 6个基地随机分配
- 玩家进入/离开管理
- 基地占用状态维护

【3.3 货币系统】CurrencySystem
- 金币增减、验证
- 通过RemoteEvent通知客户端
- 预留战斗/挂机/购买接口

【3.4 背包系统】InventorySystem
- 兵种存储管理
- 数量增减
- 客户端实时同步

【3.5 放置系统】PlacementSystem
- 服务端验证放置合法性
- 网格吸附(4x4 studs)
- 碰撞检测(GridRed/GridGreen)

【3.6 合成系统】MergeSystem
- 相同ID+相同等级 → 升级
- 等级上限: 3级
- 等级系数: 1级=1.0, 2级=1.2, 3级=1.5

【3.7 战斗管理】BattleManager
- 管理多个战斗实例(支持6玩家并发)
- 战斗状态: Preparing/Fighting/Finished
- 战场清理机制

【3.8 战斗系统】CombatSystem (V1.5.1重构)
- 攻击阶段状态机: Idle → Attacking → Recovery
- 动画事件驱动("Damage" Marker)
- 伤害计算: 攻击力 × 等级 × 等级系数
- 死亡流程: 停止AI → 播放死亡动画 → 冻结尸体

【3.9 兵种AI】UnitAI (V1.5.1优化)
- AI状态机: SEEKING → MOVING → ATTACKING
- AI节流: 0.2秒批量更新
- 寻敌优化: UnitManager分组索引
- 显式动画状态管理

【3.10 碰撞判定】HitboxService (V1.5.1)
- 服务端权威的近战命中判定
- OverlapParams + 扇形角度过滤
- 同帧去重机制
- 替代不稳定的Touched事件

【3.11 单位索引】UnitManager (V1.5.1)
- 按battleId和team分组
- 高效寻敌: O(敌方单位数)而非O(所有单位数)
- 位置缓存减少实例访问

【3.12 弹道系统】ProjectileSystem
- 远程单位弹道管理
- 追踪目标(跟踪炮弹)
- 仅与目标碰撞(穿透友军)

【3.13 武器特效】WeaponEffectSystem (V1.5.4)
- 远程武器发射特效
- Beam(0.1秒) + PointLight(0.1秒) + ParticleEmitter(0.5秒)
- 快速攻击时强制重置
- 容错设计(特效缺失不影响战斗)

【3.14 动画预加载】AnimationPreloader (V1.5.5)
- 客户端启动时预加载所有战斗动画
- 使用ContentProvider:PreloadAsync
- 解决首场战斗"傻站"卡顿问题
- 关键: 动画渲染在客户端,必须客户端预加载

=====================================================
四、版本历史
=====================================================

【V1.0】基础架构
- 货币系统、玩家管理、基地分配

【V1.1】兵种定义
- 兵种配置表、背包系统、GM命令获取兵种

【V1.2】兵种放置
- 网格吸附、拖放操作、边界检测、高光预览

【V1.3】兵种回收
- 回收模式、点击回收、自动退出

【V1.4】兵种属性与合成
- 属性系统(攻击/血量/速度)
- 等级系统(1-3级)
- 拖动合成、等级显示(Lv.X)
- 拖动换位

【V1.5】战斗系统核心
核心功能:
- BattleManager: 多战斗实例管理
- CombatSystem: 伤害计算、血量管理
- UnitAI: 寻敌、移动、攻击
- ProjectileSystem: 远程弹道
- BattleTestSystem: 测试UI

关键设计:
- 近战: 武器Touched触发伤害(V1.5.1优化)
- 远程: 弹道追踪 + Touched
- 死亡: 播放动画 → 冻结尸体
- 碰撞: PhysicsService碰撞组

【V1.5.1】战斗系统架构优化
核心改进:
- HitboxService: 服务端权威命中判定(OverlapParams)
  取代不稳定的Touched事件

- UnitManager: 单位分组索引
  按battleId+team分组,寻敌性能提升2-10倍

- CombatSystem重构: 攻击阶段状态机
  Idle → Attacking(监听"Damage"事件) → Recovery
  动画事件驱动,精确命中时机

- UnitAI性能优化: AI节流
  从每帧更新改为0.2秒批量更新,性能提升12倍

技术要点:
- 动画Marker系统: GetMarkerReachedSignal("Damage")
- 回退机制: 动画失败时用task.delay模拟
- 服务端权威: 所有判定在服务器完成

【V1.5.2】动画系统
- 5种动画: show/idle/run/attack/death
- 动画配置化: UnitConfig中配置动画ID

【V1.5.3】合成特效
- 根据单位大小(1x1/2x2/3x3)播放对应特效
- Merge01/Merge02/Merge03
- 0.3秒自动清理

【V1.5.4】远程武器特效系统
核心功能:
- WeaponEffectSystem管理远程武器发射特效
- 武器结构: Weapon/Effect/Beam+PointLight+ParticleEmitters
- 特效时序: Beam/Light(0.1秒), Particle(0.5秒)

关键设计:
- 快速攻击处理: 强制重置粒子(攻速<0.5秒时)
- 容错机制: 特效缺失不影响战斗
- 定时器管理: 避免累积和内存泄漏

集成点:
- CombatSystem.OnRangedDamageEvent调用
- 在发射子弹之前播放特效

【V1.5.5】客户端动画预加载系统 ⭐核心优化
问题根源:
- 服务器端预加载无效(ContentProvider只缓存到服务器)
- 动画渲染在客户端,首场战斗时客户端从CDN下载
- 导致"移动→傻站→攻击"、"攻击→傻站→死亡"卡顿

正确方案:
- AnimationPreloader.lua (客户端脚本)
  位置: StarterPlayerScripts/AnimationPreloader.lua

- 工作流程:
  1. 玩家进入游戏 → 等待角色加载
  2. 延迟0.5秒(确保其他系统初始化)
  3. 遍历UnitConfig.Units收集所有动画ID
  4. ContentProvider:PreloadAsync批量下载(1-3秒)
  5. 清理临时Animation实例

- 服务器端简化:
  UnitAI.PreloadAllAnimations仅预缓存Track
  不再使用ContentProvider(无效)

效果:
- 首场战斗动画流畅,无"傻站"卡顿
- 死亡动画无缝衔接
- 适用于所有动画类型

技术要点:
- 客户端预加载渲染资源(动画/音效/特效)
- 服务器预加载逻辑资源(数据/AI)
- BeginDeathAnimation: 先停旧动画,再播死亡动画

性能影响:
- 启动时间: +1-3秒(异步,不阻塞游戏)
- 内存: +400KB-2MB(可忽略)
- 网络: 1-5MB(仅首次)

=====================================================
五、核心技术要点
=====================================================

【5.1 客户端-服务器职责划分】
客户端:
- 渲染资源预加载(ContentProvider)
- UI显示和交互
- 动画/特效播放

服务器:
- 游戏逻辑和数据管理
- 权威验证和判定
- Track预缓存(加速LoadAnimation)

【5.2 动画系统设计】
- 客户端预加载: 避免首场卡顿
- 动画事件驱动: "Damage" Marker精确命中
- 回退机制: 动画失败时用延迟模拟
- 优先级管理: 死亡动画Action4最高优先级

【5.3 战斗系统优化】
- 服务端权威: HitboxService替代Touched
- AI节流: 0.2秒批量更新
- 分组索引: UnitManager按team分组
- 攻击状态机: Idle → Attacking → Recovery

【5.4 性能优化策略】
- 批量更新: RunService.Heartbeat统一驱动
- 位置缓存: 减少HumanoidRootPart访问
- 死亡清理: 立即从索引移除
- 资源预加载: 启动时完成

【5.5 碰撞判定原则】
近战:
- OverlapParams范围查询
- 扇形角度过滤(Vector3.Dot)
- 同帧去重(LastHitFrame)
- 友军碰撞忽略(PhysicsService)

远程:
- 弹道Part + Touched事件
- 仅与目标碰撞(CanCollide设置)
- 追踪目标(跟踪炮弹)

【5.6 容错设计】
- 所有操作包裹pcall
- 资源缺失降级处理
- 预加载失败不阻止游戏
- 详细的调试日志

=====================================================
六、配置表结构
=====================================================

【GameConfig】游戏常量
- 初始金币: 100
- 最大玩家数: 6
- 日志前缀

【UnitConfig】兵种配置
- 基础属性: Health/Attack/AttackSpeed/AttackRange/MoveSpeed
- 动画ID: Idle/Move/Attack/Death/Show
- 战斗配置: CombatProfile(碰撞判定参数)
- 远程配置: ProjectileSpeed/ProjectileModelPath
- 武器配置: WeaponName

【PlacementConfig】放置配置
- 网格大小: 4x4 studs
- IdleFloor尺寸: 120x1x120
- 边界限制参数

【BattleConfig】战斗配置
- AI更新间隔: 0.2秒
- 碰撞判定参数
- 攻击超时: 5秒
- 弹道配置
- 武器特效时长

=====================================================
七、RemoteEvent事件列表
=====================================================

【CurrencyEvents】
- UpdateCurrency: Server → Client (金币变化)

【InventoryEvents】
- InventoryRefresh: Server → Client (背包刷新)
- RequestInventory: Client → Server (请求背包)
- UnitUpdated: Server → Client (兵种更新)

【PlacementEvents】
- StartPlacement: Client → Server (开始放置)
- ConfirmPlacement: Client → Server (确认放置)
- CancelPlacement: Client → Server (取消放置)
- PlacementResponse: Server → Client (放置结果)
- RemoveUnit: Client → Server (回收兵种)
- UpdatePosition: Client → Server (更新位置)

【MergeEvents】
- RequestMerge: Client → Server (请求合成)
- MergeResponse: Server → Client (合成结果)

【BattleEvents】
- RequestBattleTest: Client → Server (请求战斗测试)
- BattleTestResponse: Server → Client (战斗测试结果)
- BattleStateUpdate: Server → Client (战斗状态更新)
- UnitDeath: BindableEvent (服务端内部死亡通知)
- ShowDamageNumber: Server → Client (显示伤害数字)

=====================================================
八、最佳实践
=====================================================

1. 总是在客户端预加载渲染资源
   - 动画、音效、粒子特效
   - 使用ContentProvider:PreloadAsync
   - 在游戏启动时完成,而非战斗开始时

2. 服务器端权威验证
   - 所有游戏逻辑判定在服务器
   - 客户端仅负责显示和输入
   - 防止作弊和网络延迟问题

3. 性能优化原则
   - 批量更新而非逐个处理
   - 数据缓存减少实例访问
   - 及时清理无效对象

4. 容错与降级
   - 预加载失败不阻止游戏
   - 资源缺失提供降级方案
   - 详细日志便于调试

5. 分离关注点
   - 客户端负责表现层
   - 服务器负责逻辑层
   - 清晰划分职责边界

6. 数据驱动设计
   - 配置表驱动游戏内容
   - 便于扩展和调整
   - 减少硬编码

=====================================================
九、故障排查指南
=====================================================

【动画卡顿问题】
症状: 首场战斗"傻站"
排查:
1. 确认AnimationPreloader.lua在StarterPlayerScripts下
2. 检查客户端日志: "✅ 预加载完成"
3. 确认预加载在战斗开始前完成
4. 验证动画ID配置正确

【AI不移动/不攻击】
排查:
1. 检查UnitManager是否正确注册单位
2. 确认FindNearestEnemy返回有效目标
3. 验证攻击距离和移动速度配置
4. 检查BattleId是否匹配

【近战不造成伤害】
排查:
1. 确认HitboxService.ResolveMeleeHit被调用
2. 检查CombatProfile配置(半径/角度/高度)
3. 验证"Damage"动画事件存在
4. 检查服务器日志中的命中判定

【远程不发射子弹】
排查:
1. 确认WeaponName配置正确
2. 检查ProjectileSpeed > 0
3. 验证武器模型存在
4. 检查弹道创建日志

【特效不播放】
排查:
1. 确认武器下有Effect Part
2. 检查Beam/PointLight/ParticleEmitter存在
3. 验证WeaponEffectSystem被初始化
4. 开启DEBUG_WEAPON_EFFECTS查看日志

=====================================================
十、开发注意事项
=====================================================

1. 动画ID必须为纯数字字符串
2. UnitConfig必须在ReplicatedStorage(客户端可访问)
3. 所有RemoteEvent必须预先创建在ReplicatedStorage
4. 战斗测试时使用V键打开测试UI
5. 兵种模型必须包含Humanoid和HumanoidRootPart
6. 死亡动画优先级必须最高(Action4)
7. 客户端预加载是解决动画卡顿的唯一正确方案
8. 服务器端ContentProvider对客户端无效

=====================================================
架构设计文档完成
版本: V1.5.5
总行数: 精简至 ~600 行
=====================================================
]]
