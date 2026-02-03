--[[
脚本名称: ShopTrigger
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayerScripts/UI/ShopTrigger
版本: V2.1
职责: 检测玩家靠近商店NPC并自动打开/关闭商店UI
]]

-- V4.5：对话系统接管KeepShoper01交互，旧的自动商店触发停用
local DISABLE_SHOP_TRIGGER = true

local ShopTrigger = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 收敛调试print，避免刷屏（仅在DEBUG_MODE开启时输出）
local DEBUG_MODE = GameConfig.DEBUG_MODE
local _print = print
local function DebugPrint(...)
	if DEBUG_MODE then
		_print(...)
	end
end
local print = DebugPrint

-- 本地玩家
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- 状态变量
local isNearShop = false          -- 是否靠近商店
local currentNPC = nil            -- 当前靠近的NPC
local isShopOpen = false          -- 商店是否已打开
local manualClosed = false        -- 是否手动关闭（通过Close按钮）
local checkConnection = nil       -- 距离检测连接

-- UI引用（延迟加载）
local shopUI = nil
local shopFrame = nil
local BACKPACK_HIDE_KEY = "Shop"

-- 事件引用
local RequestShopList = nil
local ShopListEvent = nil

-- ==================== 私有函数 ====================

--[[
初始化UI引用
@return boolean - 是否成功
]]
local function RequestBackpackHide()
	local trigger = _G.BackpackTrigger
	if trigger and trigger.IsOnIdleFloor and trigger.IsOnIdleFloor() then
		if trigger.PushHideLock then
			trigger.PushHideLock(BACKPACK_HIDE_KEY)
		elseif _G.BackpackDisplay and _G.BackpackDisplay.HideBackpack then
			_G.BackpackDisplay.HideBackpack()
		end
	end
end

local function ReleaseBackpackHide()
	local trigger = _G.BackpackTrigger
	if trigger and trigger.PopHideLock then
		trigger.PopHideLock(BACKPACK_HIDE_KEY)
	elseif trigger and trigger.RefreshVisibility then
		trigger.RefreshVisibility()
	end
end
local function InitializeUI()
	if shopUI then
		return true -- 已初始化
	end

	local playerGui = player:WaitForChild("PlayerGui")
	shopUI = playerGui:FindFirstChild("ArmyStore")

	if not shopUI then
		warn("[ShopTrigger] 找不到 ArmyStore ScreenGui")
		return false
	end

	shopFrame = shopUI:FindFirstChild("StoreBg")
	if not shopFrame then
		warn("[ShopTrigger] 找不到 StoreBg Frame")
		return false
	end

	return true
end

--[[
初始化事件引用
@return boolean - 是否成功
]]
local function InitializeEvents()
	if RequestShopList and ShopListEvent then
		return true -- 已初始化
	end

	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then
		warn("[ShopTrigger] Events文件夹未找到")
		return false
	end

	local shopEvents = events:FindFirstChild("ShopEvents")
	if not shopEvents then
		warn("[ShopTrigger] ShopEvents文件夹未找到")
		return false
	end

	RequestShopList = shopEvents:FindFirstChild("RequestShopList")
	ShopListEvent = shopEvents:FindFirstChild("ShopList")

	if not (RequestShopList and ShopListEvent) then
		warn("[ShopTrigger] 商店事件不完整")
		return false
	end

	return true
end

--[[
查找玩家家园中的商店NPC
@return Instance|nil - NPC实例
]]
local function FindShopNPC()
	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then
		return nil
	end

	local home = workspace:FindFirstChild("Home")
	if not home then
		return nil
	end

	local playerHome = home:FindFirstChild("PlayerHome" .. homeSlot)
	if not playerHome then
		return nil
	end

	-- 查找KeepShoper01
	local npc = playerHome:FindFirstChild(GameConfig.Shop.NPCName)
	return npc
end

--[[
获取NPC的中心Part
@param npc Instance - NPC模型
@return BasePart|nil - 中心Part
]]
local function GetNPCCenterPart(npc)
	if not npc then return nil end

	return npc:FindFirstChild("HumanoidRootPart")
	    or npc.PrimaryPart
	    or npc:FindFirstChildWhichIsA("BasePart")
end

--[[
检查是否靠近NPC
@return boolean - 是否靠近
@return Instance|nil - NPC实例（如果靠近）
]]
local function CheckDistanceToNPC()
	local npc = FindShopNPC()
	if not npc then
		return false, nil
	end

	local npcPart = GetNPCCenterPart(npc)
	if not npcPart then
		return false, nil
	end

	-- 重新获取HumanoidRootPart（可能角色重生了）
	if not character or not character.Parent then
		character = player.Character
		if character then
			humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		end
	end

	-- 检查HumanoidRootPart是否存在且有效（Parent存在表示仍在场景中）
	if not humanoidRootPart or not humanoidRootPart.Parent then
		return false, nil
	end

	local distance = (humanoidRootPart.Position - npcPart.Position).Magnitude
	return distance <= GameConfig.Shop.OpenDistance, npc
end

--[[
打开商店
]]
local function OpenShop()
	if isShopOpen or manualClosed then
		return
	end

	if not InitializeUI() or not InitializeEvents() then
		return
	end

	-- 显示商店UI
	if _G.ShopDisplay and _G.ShopDisplay.PlayOpen then
		_G.ShopDisplay.PlayOpen()
	else
		shopFrame.Visible = true
	end
    RequestBackpackHide()
	isShopOpen = true

	-- 请求商店列表
	if RequestShopList then
		RequestShopList:FireServer()
		print("[ShopTrigger] 请求商店列表")

		-- V2.1修复：兜底重试机制，防止竞态丢消息
		task.delay(0.5, function()
			if not shopFrame then return end

			-- 检查是否有商品卡片生成
			local scrollingFrame = shopFrame:FindFirstChild("ItemContainer") or shopFrame:FindFirstChild("ScrollingFrame")
			if not scrollingFrame then return end

			local hasCards = false
			for _, child in ipairs(scrollingFrame:GetChildren()) do
				if child:IsA("Frame") and string.find(child.Name, "ItemCard_") then
					hasCards = true
					break
				end
			end

			-- 如果没有卡片且商店仍然打开，重试请求
			if not hasCards and shopFrame.Visible then
				print("[ShopTrigger] 未检测到商品卡片，重试请求商店列表")
				RequestShopList:FireServer()
			end
		end)
	end
end

--[[
关闭商店
@param manual boolean - 是否手动关闭
]]
local function CloseShop(manual)
	if not isShopOpen then
		return
	end

	if not InitializeUI() then
		return
	end

	-- 隐藏商店UI
	if _G.ShopDisplay and _G.ShopDisplay.PlayClose then
		_G.ShopDisplay.PlayClose()
	else
		shopFrame.Visible = false
	end
    ReleaseBackpackHide()
	isShopOpen = false

	if manual then
		manualClosed = true
		print("[ShopTrigger] 手动关闭商店")
	else
		print("[ShopTrigger] 自动关闭商店（离开范围）")
	end
end

--[[
距离检测循环
]]
local function CheckDistanceLoop()
	local nearNow, npc = CheckDistanceToNPC()

	if nearNow and not isNearShop then
		-- 进入商店范围
		isNearShop = true
		currentNPC = npc
		manualClosed = false -- 重置手动关闭标记
		print("[ShopTrigger] 进入商店范围")
		OpenShop()

	elseif not nearNow and isNearShop then
		-- 离开商店范围
		isNearShop = false
		currentNPC = nil
		print("[ShopTrigger] 离开商店范围")
		CloseShop(false)
	end
end

-- ==================== 公共接口 ====================

--[[
初始化ShopTrigger
]]
function ShopTrigger.Initialize()
	if DISABLE_SHOP_TRIGGER then
		print("[ShopTrigger] 已停用（对话系统接管KeepShoper01）")
		return
	end

	print("[ShopTrigger] 初始化商店触发器...")

	-- 等待角色加载
	if not character or not character.Parent then
		player.CharacterAdded:Wait()
		character = player.Character
		humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	end

	-- 延迟启动，确保其他系统初始化完成
	task.wait(1)

	-- 初始化UI和事件
	if not InitializeUI() then
		warn("[ShopTrigger] UI初始化失败")
		return
	end

	if not InitializeEvents() then
		warn("[ShopTrigger] 事件初始化失败")
		return
	end

	-- 绑定关闭按钮
	local closeButton = shopFrame:FindFirstChild("CloseButton")
	if closeButton then
		closeButton.MouseButton1Click:Connect(function()
			CloseShop(true)
		end)
		print("[ShopTrigger] 关闭按钮已绑定")
	else
		warn("[ShopTrigger] 找不到CloseButton")
	end

	-- 启动距离检测
	checkConnection = RunService.Heartbeat:Connect(function()
		-- 按间隔检测（节省性能）
		local now = tick()
		if not ShopTrigger._lastCheckTime or (now - ShopTrigger._lastCheckTime) >= GameConfig.Shop.CheckInterval then
			ShopTrigger._lastCheckTime = now
			CheckDistanceLoop()
		end
	end)

	-- 监听角色重生
	player.CharacterAdded:Connect(function(newCharacter)
		character = newCharacter
		humanoidRootPart = character:WaitForChild("HumanoidRootPart")
		isNearShop = false
		currentNPC = nil
		if isShopOpen then
			CloseShop(false)
		end
		print("[ShopTrigger] 角色重生，重置状态")
	end)

	print("[ShopTrigger] ✅ 商店触发器已就绪")
end

--[[
清理ShopTrigger
]]
function ShopTrigger.Cleanup()
	if checkConnection then
		checkConnection:Disconnect()
		checkConnection = nil
	end
	print("[ShopTrigger] 已清理")
end

-- ==================== 自动初始化 ====================
ShopTrigger.Initialize()

return ShopTrigger
