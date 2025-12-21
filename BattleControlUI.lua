--[[
=====================================================
脚本名称: BattleControlUI
脚本类型: LocalScript (客户端)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/BattleControlUI.lua
版本: V2.0
=====================================================

功能描述:
- 处理Play/Retreat按钮点击
- 监听战役状态更新
- 锁定/解锁基地操作
- 显示战役进度提示

]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 等待UI加载
local mainGui = playerGui:WaitForChild("MainGui")
local battleControl = mainGui:WaitForChild("BattleControl")
local playButton = battleControl:WaitForChild("Play")
local retreatButton = battleControl:WaitForChild("Retreat")

-- 远程事件
local eventsFolder = ReplicatedStorage:WaitForChild("Events")
local CampaignEvents = eventsFolder:WaitForChild("CampaignEvents")

-- 引用其他控制器（用于锁定操作）
local PlacementController = nil
local DragSystem = nil
local RemovalController = nil

-- 延迟获取其他控制器（V2.0.2修复：使用_G全局对象而非require）
task.spawn(function()
	-- 等待控制器初始化
	task.wait(2)

	-- 从全局对象获取PlacementController
	if _G.PlacementController then
		PlacementController = _G.PlacementController
	else
		warn("[BattleControlUI] PlacementController未找到")
	end

	-- 从全局对象获取RemovalController
	if _G.RemovalController then
		RemovalController = _G.RemovalController
	else
		warn("[BattleControlUI] RemovalController未找到")
	end

	-- DragSystem需要require（它是ModuleScript）
	local success, result = pcall(function()
		local playerScripts = player:WaitForChild("PlayerScripts", 10)
		if playerScripts then
			local controllers = playerScripts:WaitForChild("Controllers", 10)
			if controllers then
				local dragModule = controllers:WaitForChild("DragSystem", 10)
				if dragModule and dragModule:IsA("ModuleScript") then
					return require(dragModule)
				end
			end
		end
		return nil
	end)

	if success and result then
		DragSystem = result
	else
		-- 尝试从全局对象获取
		if _G.DragSystem then
			DragSystem = _G.DragSystem
		else
			warn("[BattleControlUI] DragSystem加载失败")
		end
	end
end)

-- 状态文本UI（可选，如果有的话）
local statusTextLabel = mainGui:FindFirstChild("StatusText")

-- ==================== 背包显示控制（战斗期间强制隐藏） ====================

local function HideBackpackForBattle()
	-- 优先调用统一背包接口
	if _G.BackpackDisplay and _G.BackpackDisplay.HideBackpack then
		_G.BackpackDisplay.HideBackpack()
	else
		-- 兜底：直接关闭BackpackGui
		local backpackGui = playerGui:FindFirstChild("BackpackGui")
		if backpackGui then
			backpackGui.Enabled = false
		end
	end
end

-- ==================== UI控制函数 ====================

--[[
锁定/解锁基地操作
@param locked boolean - 是否锁定
]]
local function LockHomeOperations(locked)
	-- 锁定摆放操作
	if PlacementController and PlacementController.SetLocked then
		PlacementController.SetLocked(locked)
	end

	-- 锁定拖动合成操作
	if DragSystem and DragSystem.SetEnabled then
		DragSystem.SetEnabled(not locked)
	end

	-- 锁定回收操作
	if RemovalController and RemovalController.SetEnabled then
		RemovalController.SetEnabled(not locked)
	end
end

--[[
显示状态文本
@param text string - 状态文本
]]
local function ShowStatusText(text)
	if statusTextLabel then
		statusTextLabel.Text = text
		statusTextLabel.Visible = true
	end
end

--[[
隐藏状态文本
]]
local function HideStatusText()
	if statusTextLabel then
		statusTextLabel.Visible = false
	end
end

--[[
显示胜利UI
]]
local function ShowVictoryUI()
	ShowStatusText("🎉 战役胜利！")
	-- TODO: 可以添加更华丽的胜利UI
end

--[[
显示失败UI
]]
local function ShowDefeatUI()
	ShowStatusText("💀 战役失败")
	-- TODO: 可以添加失败UI
end

-- ==================== 按钮事件 ====================

--[[
Play按钮点击事件
]]
playButton.MouseButton1Click:Connect(function()
	-- 开战点击后立刻隐藏背包
	HideBackpackForBattle()

	-- V5.7修复：移除此处的BattleCameraController.Start()调用
	-- 原因：在点击按钮时，玩家可能在别人家溜达，此时：
	-- 1. 服务端还没有完成玩家传送（TeleportPlayerToCommandPart）
	-- 2. 单位还没有被标记为CampaignKeepInstance
	-- 3. 镜头的computeCenter()会计算出错误的目标位置
	-- 正确做法：由CameraController监听CampaignStateUpdate事件来启动镜头锁定
	-- 这样可以确保服务端完成传送和准备后，镜头才开始跟随正确的位置

	-- 触发服务器事件
	local requestStart = CampaignEvents:FindFirstChild("RequestStartCampaign")
	if requestStart then
		requestStart:FireServer()
	else
		warn("[BattleControlUI] RequestStartCampaign事件未找到")
	end
end)

--[[
Retreat按钮点击事件
]]
retreatButton.MouseButton1Click:Connect(function()
	-- 触发服务器事件
	local requestRetreat = CampaignEvents:FindFirstChild("RequestRetreat")
	if requestRetreat then
		requestRetreat:FireServer()
	else
		warn("[BattleControlUI] RequestRetreat事件未找到")
	end
end)

-- ==================== 监听战役状态 ====================

--[[
战役状态更新事件
@param state string - 战役状态
@param stageNum number - 当前关卡编号
]]
local stateUpdateEvent = CampaignEvents:FindFirstChild("CampaignStateUpdate")
if stateUpdateEvent then
	stateUpdateEvent.OnClientEvent:Connect(function(state, stageNum)
		if state == "Preparing" or state == "PrepareBattle" then
			-- 准备阶段（包括战斗准备）
			playButton.Visible = false
			retreatButton.Visible = true
			LockHomeOperations(true)
			ShowStatusText("准备中...")
			HideBackpackForBattle()

		elseif state == "Marching" then
			-- 行军阶段
			ShowStatusText("前往第 " .. stageNum .. " 关...")
			HideBackpackForBattle()

		elseif state == "Fighting" then
			-- 战斗阶段
			ShowStatusText("战斗中 - 第 " .. stageNum .. " 关")
			HideBackpackForBattle()

		elseif state == "StageClear" then
			-- 关卡完成
			ShowStatusText("第 " .. stageNum .. " 关完成！")
			HideBackpackForBattle()

		elseif state == "Victory" then
			-- 战役胜利
			-- 等待结算确认完成后再进入Idle，否则重开会被服务端拒绝
			playButton.Visible = false
			retreatButton.Visible = false
			ShowVictoryUI()
			HideBackpackForBattle()
			task.wait(3)
			HideStatusText()

		elseif state == "Defeat" then
			-- 战役失败
			-- 等待结算确认完成后再进入Idle，否则重开会被服务端拒绝
			playButton.Visible = false
			retreatButton.Visible = false
			ShowDefeatUI()
			HideBackpackForBattle()
			task.wait(3)
			HideStatusText()

	elseif state == "Idle" then
		-- 闲置状态
		playButton.Visible = true
		retreatButton.Visible = false
		LockHomeOperations(false)
		-- ensure camera unlocked
		if _G.BattleCameraController and _G.BattleCameraController.Stop then
			_G.BattleCameraController.Stop()
		end
		HideStatusText()

	else
		warn("[BattleControlUI] 未知状态:", state)
	end
	end)
else
	warn("[BattleControlUI] CampaignStateUpdate事件未找到")
end

--[[
关卡进度更新事件
@param stageNum number - 关卡编号
@param status string - 状态（"Clear"等）
]]
local progressEvent = CampaignEvents:FindFirstChild("StageProgress")
if progressEvent then
	progressEvent.OnClientEvent:Connect(function(stageNum, status)
		if status == "Clear" then
			ShowStatusText("✅ 第 " .. stageNum .. " 关完成！")
		end
	end)
end

--[[
锁定基地操作事件（备用）
@param locked boolean - 是否锁定
]]
local lockEvent = CampaignEvents:FindFirstChild("LockHomeOperations")
if lockEvent then
	lockEvent.OnClientEvent:Connect(function(locked)
		LockHomeOperations(locked)
	end)
end

-- ==================== 初始化 ====================

-- 确保初始状态正确
playButton.Visible = true
retreatButton.Visible = false
HideStatusText()

