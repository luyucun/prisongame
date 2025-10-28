--[[
脚本名称: EventsSetup (说明文档)
脚本类型: 说明文档
脚本位置: 本文件仅作说明,实际事件需要在Roblox Studio中创建
]]

--[[
=====================================================
远程事件创建说明
=====================================================

在Roblox Studio中,您需要手动创建以下远程事件:

【创建步骤】

1. 在ReplicatedStorage中创建一个Folder,命名为 "Events"

2. 在Events文件夹中创建以下RemoteEvent:

   a) CurrencyEvents (RemoteEvent)
      - 用途: 服务端通知客户端货币变化,客户端请求货币信息
      - 触发方向: Server -> Client (通知货币变化)
                  Client -> Server (请求货币信息)

   b) PlayerEvents (RemoteEvent) [当前版本暂未使用,为后续版本预留]
      - 用途: 玩家相关事件通信
      - 触发方向: 双向

【详细说明】

1. CurrencyEvents 事件说明:

   Server -> Client 参数:
   - currencyType (string): 货币类型,如 "Coins"
   - newAmount (number): 新的货币数量

   使用示例:
   服务端: CurrencyEvents:FireClient(player, "Coins", 150)
   客户端: CurrencyEvents.OnClientEvent:Connect(function(currencyType, newAmount) ... end)

   Client -> Server 参数:
   - 无参数,仅请求当前货币信息

   使用示例:
   客户端: CurrencyEvents:FireServer()
   服务端: CurrencyEvents.OnServerEvent:Connect(function(player) ... end)

2. PlayerEvents 事件说明:
   [当前版本暂未使用,为后续版本预留]

【创建后的目录结构】

ReplicatedStorage
└── Events (Folder)
    ├── CurrencyEvents (RemoteEvent)
    └── PlayerEvents (RemoteEvent)

【验证方法】

创建完成后,可以在服务端脚本中使用以下代码验证:

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local currencyEvents = eventsFolder:WaitForChild("CurrencyEvents")

if currencyEvents and currencyEvents:IsA("RemoteEvent") then
    print("CurrencyEvents创建成功!")
end

【重要提示】

1. RemoteEvent必须放在ReplicatedStorage中才能被客户端和服务端同时访问
2. Events文件夹和RemoteEvent的名称必须与配置文件中的定义完全一致
3. 确保RemoteEvent的类型正确(RemoteEvent,不是RemoteFunction)
4. 创建完成后,代码才能正常运行

=====================================================
]]

return nil
