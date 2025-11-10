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

-- 延迟获取其他控制器（V2.0修复：添加安全检查）
task.spawn(function()
	local success, err = pcall(function()
		local playerScripts = player:WaitForChild("PlayerScripts", 10)
		if not playerScripts then
			warn("[BattleControlUI] PlayerScripts未找到")
			return
		end

		local controllers = playerScripts:WaitForChild("Controllers", 10)
		if not controllers then
			warn("[BattleControlUI] Controllers文件夹未找到")
			return
		end

		-- 安全加载PlacementController
		local placementModule = controllers:WaitForChild("PlacementController", 10)
		if placementModule and placementModule:IsA("ModuleScript") then
			PlacementController = require(placementModule)
		else
			warn("[BattleControlUI] PlacementController加载失败")
		end

		-- 安全加载DragSystem
		local dragModule = controllers:WaitForChild("DragSystem", 10)
		if dragModule and dragModule:IsA("ModuleScript") then
			DragSystem = require(dragModule)
		else
			warn("[BattleControlUI] DragSystem加载失败")
		end

		-- 安全加载RemovalController
		local removalModule = controllers:WaitForChild("RemovalController", 10)
		if removalModule and removalModule:IsA("ModuleScript") then
			RemovalController = require(removalModule)
		else
			warn("[BattleControlUI] RemovalController加载失败")
		end

		print("[BattleControlUI] 控制器加载完成")
	end)

	if not success then
		warn("[BattleControlUI] 控制器加载错误:", err)
	end
end)

-- 状态文本UI（可选，如果有的话）
local statusTextLabel = mainGui:FindFirstChild("StatusText")

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

	print("[BattleControlUI] 基地操作", locked and "已锁定" or "已解锁")
end

--[[
显示状态文本
@param text string - 状态文本
]]
local function ShowStatusText(text)
	if statusTextLabel then
		statusTextLabel.Text = text
		statusTextLabel.Visible = true
	else
		-- 如果没有StatusText UI，在控制台输出
		print("[战役状态]", text)
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
	print("[BattleControlUI] 请求开始战役")

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
	print("[BattleControlUI] 请求撤退")

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
		print("[BattleControlUI] 战役状态更新:", state, "关卡:", stageNum)

		if state == "Preparing" then
			-- 准备阶段
			playButton.Visible = false
			retreatButton.Visible = true
			LockHomeOperations(true)
			ShowStatusText("准备中...")

		elseif state == "Marching" then
			-- 行军阶段
			ShowStatusText("前往第 " .. stageNum .. " 关...")

		elseif state == "Fighting" then
			-- 战斗阶段
			ShowStatusText("战斗中 - 第 " .. stageNum .. " 关")

		elseif state == "StageClear" then
			-- 关卡完成
			ShowStatusText("第 " .. stageNum .. " 关完成！")

		elseif state == "Victory" then
			-- 战役胜利
			playButton.Visible = true
			retreatButton.Visible = false
			ShowVictoryUI()
			task.wait(3)
			HideStatusText()

		elseif state == "Defeat" then
			-- 战役失败
			playButton.Visible = true
			retreatButton.Visible = false
			ShowDefeatUI()
			task.wait(3)
			HideStatusText()

		elseif state == "Idle" then
			-- 闲置状态
			playButton.Visible = true
			retreatButton.Visible = false
			LockHomeOperations(false)
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
		print("[BattleControlUI] 关卡进度:", stageNum, status)

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

print("[BattleControlUI] 初始化完成")

-- 确保初始状态正确
playButton.Visible = true
retreatButton.Visible = false
HideStatusText()
