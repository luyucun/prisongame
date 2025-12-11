--[[
脚本名称: GuideController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/GuideController
]]

--[[
新手引导控制器 V3.5
职责:
1. 接收服务端引导事件
2. 显示引导箭头（Guide01 + Guide02 + Beam）
3. 检测玩家是否到达目标位置
4. 通知服务端引导完成
]]

local GuideController = {}

-- 调试配置
local DEBUG_MODE = false
local function DebugLog(...)
	if DEBUG_MODE then
		print("[GuideController]", ...)
	end
end

-- 引用服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 本地玩家
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- 引用配置
local GuideConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GuideConfig"))

-- 事件缓存
local guideEvents = nil

-- 当前引导状态
local currentGuideId = nil
local currentTargetPosition = nil
local guideStartPart = nil   -- 绑定到玩家的Guide01副本
local guideEndPart = nil     -- 放在目标位置的Guide02副本
local updateConnection = nil -- RenderStepped连接

-- ==================== 私有函数（前向声明） ====================

-- 前向声明，解决函数互相调用的问题
local CheckArrival
local OnArriveAtTarget
local ClearGuideDisplay

--[[
获取事件引用
]]
local function GetGuideEvents()
	if guideEvents then
		return guideEvents
	end

	local events = ReplicatedStorage:WaitForChild("Events", 10)
	if not events then
		return nil
	end

	local guideEventsFolder = events:WaitForChild("GuideEvents", 10)
	if not guideEventsFolder then
		return nil
	end

	guideEvents = {
		StartGuide = guideEventsFolder:WaitForChild("StartGuide", 5),
		CompleteGuide = guideEventsFolder:WaitForChild("CompleteGuide", 5),
		GuideArrived = guideEventsFolder:WaitForChild("GuideArrived", 5),
		SyncGuideData = guideEventsFolder:WaitForChild("SyncGuideData", 5),
		RequestGuideSync = guideEventsFolder:WaitForChild("RequestGuideSync", 5),
	}

	return guideEvents
end

--[[
从ReplicatedStorage获取引导模板
@param templateName string - 模板名称
@return Instance|nil - 模板对象
]]
local function GetGuideTemplate(templateName)
	-- 从ReplicatedStorage/Effect获取模板
	local effectFolder = ReplicatedStorage:FindFirstChild("Effect")
	if not effectFolder then
		warn("[GuideController] 找不到ReplicatedStorage/Effect文件夹")
		return nil
	end

	local template = effectFolder:FindFirstChild(templateName)
	if not template then
		warn("[GuideController] 找不到引导模板:", templateName)
		return nil
	end

	return template
end

--[[
获取玩家的躯干Part
]]
local function GetPlayerTorso()
	local char = player.Character
	if not char then
		return nil
	end

	-- 优先查找UpperTorso（R15）或Torso（R6）
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	return torso
end

--[[
清除当前引导显示
]]
ClearGuideDisplay = function()
	-- 断开更新连接
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	-- 移除引导部件
	if guideStartPart then
		guideStartPart:Destroy()
		guideStartPart = nil
	end

	if guideEndPart then
		guideEndPart:Destroy()
		guideEndPart = nil
	end

	currentGuideId = nil
	currentTargetPosition = nil
end

--[[
到达目标时调用
]]
OnArriveAtTarget = function()
	if not currentGuideId then
		return
	end

	local guideId = currentGuideId

	-- 通知服务端
	local events = GetGuideEvents()
	if events and events.GuideArrived then
		events.GuideArrived:FireServer(guideId)
	end

	-- 清除引导显示
	ClearGuideDisplay()
end

--[[
检查玩家是否到达目标位置
]]
CheckArrival = function()
	if not currentGuideId or not currentTargetPosition then
		return
	end

	local char = player.Character
	if not char then
		return
	end

	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- 获取引导配置
	local guideConfig = GuideConfig.GetGuideById(currentGuideId)
	local arrivalDistance = guideConfig and guideConfig.ArrivalDistance or 10

	-- 计算距离
	local distance = (rootPart.Position - currentTargetPosition).Magnitude

	if distance <= arrivalDistance then
		-- 到达目标
		OnArriveAtTarget()
	end
end

--[[
更新引导显示（每帧调用）
]]
local function UpdateGuideDisplay()
	if not currentGuideId or not guideStartPart then
		return
	end

	-- 获取玩家躯干
	local torso = GetPlayerTorso()
	if not torso then
		return
	end

	-- 更新起始点位置（绑定到玩家躯干）
	if guideStartPart:IsA("BasePart") then
		local offset = GuideConfig.Display.AttachmentOffset or Vector3.new(0, 1, 0)
		guideStartPart.Position = torso.Position + offset
		guideStartPart.Anchored = true
		guideStartPart.CanCollide = false
	end

	-- 检查是否到达目标
	CheckArrival()
end

--[[
创建引导显示
@param guideId number - 引导ID
@param targetPosition Vector3 - 目标位置
]]
local function CreateGuideDisplay(guideId, targetPosition)
	-- 清除旧的引导
	ClearGuideDisplay()

	-- 获取引导模板
	local guide01Template = GetGuideTemplate(GuideConfig.Display.GuideStartPartName)
	local guide02Template = GetGuideTemplate(GuideConfig.Display.GuideEndPartName)

	if not guide01Template or not guide02Template then
		warn("[GuideController] 无法获取引导模板")
		return false
	end

	-- 复制Guide01（起始点，绑定到玩家）
	guideStartPart = guide01Template:Clone()
	guideStartPart.Name = "GuideStart_" .. guideId
	guideStartPart.Parent = Workspace

	-- 复制Guide02（终点，放在目标位置）
	guideEndPart = guide02Template:Clone()
	guideEndPart.Name = "GuideEnd_" .. guideId
	guideEndPart.Parent = Workspace

	-- 设置终点位置
	if guideEndPart:IsA("BasePart") then
		guideEndPart.Position = targetPosition + Vector3.new(0, 2, 0)  -- 稍微抬高一点
		guideEndPart.Anchored = true
		guideEndPart.CanCollide = false
	end

	-- 连接Beam的Attachment
	-- Beam在GuideStart下，Attachment0连接GuideEnd的Attachment0，Attachment1连接GuideStart的Attachment1
	local beam = guideStartPart:FindFirstChild("Beam", true)
	if beam then
		local endAttachment = guideEndPart:FindFirstChild("Attachment0", true)
		local startAttachment = guideStartPart:FindFirstChild("Attachment1", true)
		if endAttachment then
			beam.Attachment0 = endAttachment
		end
		if startAttachment then
			beam.Attachment1 = startAttachment
		end
	end

	-- 保存状态
	currentGuideId = guideId
	currentTargetPosition = targetPosition

	-- 启动更新循环
	updateConnection = RunService.RenderStepped:Connect(function()
		UpdateGuideDisplay()
	end)

	return true
end

--[[
处理开始引导事件
@param guideId number - 引导ID
@param targetPosition Vector3 - 目标位置
]]
local function OnStartGuide(guideId, targetPosition)
	CreateGuideDisplay(guideId, targetPosition)
end

--[[
处理完成引导事件
@param guideId number - 引导ID (0表示清除所有)
]]
local function OnCompleteGuide(guideId)
	if guideId == 0 or guideId == currentGuideId then
		ClearGuideDisplay()
	end
end

--[[
处理同步引导数据事件
@param guideData table - 引导数据
]]
local function OnSyncGuideData(guideData)
	-- 可以在这里处理引导数据的客户端缓存
end

-- ==================== 公共接口 ====================

--[[
初始化引导控制器
]]
function GuideController.Initialize()
	-- 等待事件就绪
	local events = GetGuideEvents()
	if not events then
		warn("[GuideController] 无法获取引导事件，引导功能禁用")
		return
	end

	-- 监听服务端事件
	if events.StartGuide then
		events.StartGuide.OnClientEvent:Connect(OnStartGuide)
	end

	if events.CompleteGuide then
		events.CompleteGuide.OnClientEvent:Connect(OnCompleteGuide)
	end

	if events.SyncGuideData then
		events.SyncGuideData.OnClientEvent:Connect(OnSyncGuideData)
	end

	-- 监听角色重生
	player.CharacterAdded:Connect(function(newCharacter)
		character = newCharacter
		-- 角色重生后重新请求引导数据
		task.wait(1)
		if events.RequestGuideSync then
			events.RequestGuideSync:FireServer()
		end
	end)

	-- 请求同步引导数据
	task.delay(2, function()
		if events.RequestGuideSync then
			events.RequestGuideSync:FireServer()
		end
	end)
end

--[[
获取当前激活的引导ID
@return number|nil - 引导ID
]]
function GuideController.GetCurrentGuideId()
	return currentGuideId
end

--[[
检查是否有激活的引导
@return boolean - 是否有激活的引导
]]
function GuideController.HasActiveGuide()
	return currentGuideId ~= nil
end

--[[
手动清除引导（用于调试）
]]
function GuideController.ClearGuide()
	ClearGuideDisplay()
end

-- 初始化
GuideController.Initialize()

-- 暴露到全局（可选，用于调试）
_G.GuideController = GuideController

return GuideController
