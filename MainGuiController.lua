--[[
=====================================================
脚本名称: MainGuiController
脚本类型: LocalScript (客户端UI控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/MainGuiController.lua
版本: V2.11
=====================================================

功能描述:
- 管理MainGui下的战斗相关按钮（ReturnToHome, UnlockMove）
- 监听战役状态变化，控制按钮显示/隐藏
- 处理按钮点击事件：
  - UnlockMove: 解锁镜头跟随战场，恢复玩家视角
  - ReturnToHome: 传送玩家回家园出生点

V2.11新功能:
- 战斗开始时显示ReturnToHome和UnlockMove按钮
- 战斗结束时隐藏按钮
- UnlockMove解除镜头锁定
- ReturnToHome传送玩家回家园

]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- UI元素引用
local mainGui = nil
local returnToHomeButton = nil
local unlockMoveButton = nil

-- 远程事件
local campaignEvents = nil
local battleControlEvents = nil
local returnToHomeEvent = nil

-- 状态标记
local isBattleActive = false
local isInitialized = false

-- ==================== 日志函数 ====================

local function DebugLog(...)
	print("[MainGuiController]", ...)
end

-- ==================== UI初始化 ====================

--[[
安全获取UI元素
@param parent Instance - 父对象
@param childName string - 子对象名称
@param timeout number - 超时时间（秒）
@return Instance|nil
]]
local function SafeWaitForChild(parent, childName, timeout)
	timeout = timeout or 3

	local child = parent:FindFirstChild(childName)
	if child then
		return child
	end

	local startTime = tick()
	while tick() - startTime < timeout do
		child = parent:FindFirstChild(childName)
		if child then
			return child
		end
		task.wait(0.1)
	end

	return nil
end

--[[
初始化UI元素
@return boolean - 是否初始化成功
]]
local function InitializeUI()
	DebugLog("开始初始化UI元素...")

	-- 获取MainGui
	mainGui = SafeWaitForChild(playerGui, "MainGui", 5)
	if not mainGui then
		DebugLog("❌ 未找到MainGui")
		return false
	end

	-- 获取ReturnToHome按钮
	returnToHomeButton = mainGui:FindFirstChild("ReturnToHome", true)
	if not returnToHomeButton then
		DebugLog("⚠ 未找到ReturnToHome按钮")
	else
		DebugLog("✅ 找到ReturnToHome按钮")
	end

	-- 获取UnlockMove按钮
	unlockMoveButton = mainGui:FindFirstChild("UnlockMove", true)
	if not unlockMoveButton then
		DebugLog("⚠ 未找到UnlockMove按钮")
	else
		DebugLog("✅ 找到UnlockMove按钮")
	end

	-- 初始状态：隐藏按钮
	SetButtonsVisibility(false)

	return true
end

-- ==================== 按钮控制 ====================

--[[
设置战斗按钮的可见性
@param visible boolean - 是否可见
]]
function SetButtonsVisibility(visible)
	if returnToHomeButton then
		returnToHomeButton.Visible = visible
	end

	if unlockMoveButton then
		unlockMoveButton.Visible = visible
	end

	DebugLog(string.format("按钮可见性设置为: %s", tostring(visible)))
end

-- ==================== 按钮点击处理 ====================

--[[
处理UnlockMove按钮点击
解锁镜头跟随战场，恢复玩家视角
]]
local function OnUnlockMoveClick()
	DebugLog("🔓 UnlockMove按钮被点击")

	-- 调用CameraController解锁镜头
	if _G.BattleCameraController and _G.BattleCameraController.UnlockToPlayer then
		local success = _G.BattleCameraController.UnlockToPlayer()
		if success then
			DebugLog("✅ 镜头已解锁，恢复玩家视角")
		else
			DebugLog("⚠ 镜头解锁失败")
		end
	else
		DebugLog("❌ BattleCameraController.UnlockToPlayer不可用")
	end
end

--[[
处理ReturnToHome按钮点击
传送玩家回家园出生点，并解除镜头锁定
]]
local function OnReturnToHomeClick()
	DebugLog("🏠 ReturnToHome按钮被点击")

	-- 发送传送请求到服务器
	if returnToHomeEvent then
		returnToHomeEvent:FireServer()
		DebugLog("✅ 已发送传送请求到服务器")
	else
		DebugLog("❌ ReturnToHome事件不可用")
	end

	-- 解除镜头锁定，恢复玩家视角
	if _G.BattleCameraController and _G.BattleCameraController.UnlockToPlayer then
		local success = _G.BattleCameraController.UnlockToPlayer()
		if success then
			DebugLog("✅ 镜头已解锁，恢复玩家视角")
		end
	end
end

-- ==================== 事件处理 ====================

--[[
处理战役状态更新
@param state string - 战役状态
@param stageNum number - 关卡编号
]]
local function OnCampaignStateUpdate(state, stageNum)
	DebugLog(string.format("收到战役状态更新: %s, 关卡: %s", tostring(state), tostring(stageNum)))

	-- 战斗相关状态时显示按钮
	if state == "Fighting" or state == "PrepareBattle" or state == "Marching" then
		isBattleActive = true
		SetButtonsVisibility(true)
	-- 战斗结束相关状态时隐藏按钮
	elseif state == "Idle" or state == "Victory" or state == "Defeat" or state == "Cleanup" then
		isBattleActive = false
		SetButtonsVisibility(false)
	-- StageClear时保持按钮可见（准备进入下一关）
	elseif state == "StageClear" then
		-- 保持当前状态
	end
end

-- ==================== 初始化 ====================

--[[
初始化远程事件连接
]]
local function InitializeEvents()
	DebugLog("初始化远程事件...")

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		DebugLog("❌ 未找到Events文件夹")
		return false
	end

	-- 获取CampaignEvents
	campaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
	if campaignEvents then
		local stateUpdate = campaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate.OnClientEvent:Connect(OnCampaignStateUpdate)
			DebugLog("✅ 已连接CampaignStateUpdate事件")
		end
	end

	-- 获取BattleControlEvents文件夹
	battleControlEvents = eventsFolder:FindFirstChild("BattleControlEvents")
	if battleControlEvents then
		returnToHomeEvent = battleControlEvents:FindFirstChild("ReturnToHome")
		if returnToHomeEvent then
			DebugLog("✅ 找到ReturnToHome远程事件")
		end
	else
		DebugLog("⚠ BattleControlEvents文件夹不存在，需要在Studio中创建")
	end

	return true
end

--[[
连接按钮点击事件
]]
local function ConnectButtonEvents()
	-- 连接UnlockMove按钮
	if unlockMoveButton then
		if unlockMoveButton:IsA("TextButton") or unlockMoveButton:IsA("ImageButton") then
			unlockMoveButton.MouseButton1Click:Connect(function()
				pcall(OnUnlockMoveClick)
			end)
			DebugLog("✅ UnlockMove按钮事件已连接")
		end
	end

	-- 连接ReturnToHome按钮
	if returnToHomeButton then
		if returnToHomeButton:IsA("TextButton") or returnToHomeButton:IsA("ImageButton") then
			returnToHomeButton.MouseButton1Click:Connect(function()
				pcall(OnReturnToHomeClick)
			end)
			DebugLog("✅ ReturnToHome按钮事件已连接")
		end
	end
end

--[[
主初始化函数
]]
local function Initialize()
	DebugLog("开始初始化MainGuiController...")

	-- 初始化UI
	if not InitializeUI() then
		DebugLog("⚠ UI初始化失败，部分功能可能不可用")
	end

	-- 初始化事件
	if not InitializeEvents() then
		DebugLog("⚠ 事件初始化失败")
	end

	-- 连接按钮事件
	ConnectButtonEvents()

	isInitialized = true
	DebugLog("✅ MainGuiController初始化完成")

	return true
end

-- ==================== 启动 ====================

task.spawn(function()
	local success, err = pcall(Initialize)
	if not success then
		warn("[MainGuiController] 初始化出错:", err)
	end
end)

DebugLog("MainGuiController脚本加载完成")
