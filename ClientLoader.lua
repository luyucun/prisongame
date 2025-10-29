--[[
脚本名称: ClientLoader
脚本类型: LocalScript (客户端主启动脚本)
脚本位置: StarterPlayer/StarterPlayerScripts/ClientLoader
]]

--[[
客户端系统启动器
职责:
1. 按顺序加载所有客户端系统
2. 初始化UI和控制器
]]

print("[ClientLoader] 启动客户端系统...")

-- 等待必要的系统加载
task.wait(0.5)

-- 加载PlacementController
local PlacementController = require(script.Parent.Controllers.PlacementController)
print("[ClientLoader] PlacementController已加载")

-- 加载DragSystem
local DragSystem = require(script.Parent.Controllers.DragSystem)
print("[ClientLoader] DragSystem已加载")

print("[ClientLoader] 所有客户端系统加载完成！")
