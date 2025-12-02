--[[
=====================================================
脚本名称: SkillShopTrigger
脚本类型: LocalScript (客户端脚本)
脚本位置: StarterPlayerScripts/Triggers/SkillShopTrigger.lua
版本: V3.1
=====================================================

功能描述:
- 检测玩家靠近技能商店NPC
- 触发技能商店UI显示
- 使用与兵种商店相同的距离判定

=====================================================
]]

local SkillShopTrigger = {}

-- 引用服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local SkillShopConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillShopConfig"))

-- 本地玩家
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 调试配置
local DEBUG_MODE = false
local LOG_PREFIX = "[SkillShopTrigger]"

-- 状态变量
local isNearShop = false
local lastCheckTime = 0
local checkConnection = nil

-- 技能商店NPC名称（从SkillShopConfig获取）
local SKILL_SHOP_NPC_NAME = "KeepShoper02"

-- UI引用
local skillShopUI = nil
local skillShopFrame = nil

-- 事件引用
local RequestSkillShopList = nil

-- ==================== 私有函数 ====================

--[[
初始化事件引用
@return boolean - 是否成功
]]
local function InitializeEvents()
	if RequestSkillShopList then
		return true
	end

	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then
		warn(LOG_PREFIX, "Events文件夹未找到")
		return false
	end

	local skillShopEvents = events:FindFirstChild("SkillShopEvents")
	if not skillShopEvents then
		warn(LOG_PREFIX, "SkillShopEvents文件夹未找到")
		return false
	end

	RequestSkillShopList = skillShopEvents:FindFirstChild("RequestSkillShopList")
	if not RequestSkillShopList then
		warn(LOG_PREFIX, "RequestSkillShopList事件未找到")
		return false
	end

	return true
end

--[[
初始化UI引用
@return boolean - 是否成功
]]
local function InitializeUI()
	if skillShopUI and skillShopFrame then
		return true
	end

	skillShopUI = playerGui:WaitForChild("SkillStore", 5)
	if not skillShopUI then
		warn(LOG_PREFIX, "找不到 SkillStore ScreenGui")
		return false
	end

	skillShopFrame = skillShopUI:WaitForChild("StoreBg", 2)
	if not skillShopFrame then
		warn(LOG_PREFIX, "找不到 StoreBg Frame")
		return false
	end

	return true
end

--[[
获取技能商店NPC
@return Instance|nil - NPC模型
]]
local function GetSkillShopNPC()
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

	-- 从SkillShopConfig获取NPC名称
	for shopId, shopData in pairs(SkillShopConfig.Shops) do
		if shopData.NPCName then
			local npc = playerHome:FindFirstChild(shopData.NPCName)
			if npc then
				return npc
			end
		end
	end

	-- 回退到默认NPC名称
	return playerHome:FindFirstChild(SKILL_SHOP_NPC_NAME)
end

--[[
计算玩家与NPC的距离
@param npc Instance - NPC模型
@return number - 距离
]]
local function GetDistanceToNPC(npc)
	local character = player.Character
	if not character then
		return math.huge
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return math.huge
	end

	local npcPart = npc:FindFirstChild("HumanoidRootPart")
	             or npc.PrimaryPart
	             or npc:FindFirstChildWhichIsA("BasePart")

	if not npcPart then
		return math.huge
	end

	return (rootPart.Position - npcPart.Position).Magnitude
end

--[[
打开技能商店
]]
local function OpenSkillShop()
	if not InitializeUI() then
		warn(LOG_PREFIX, "UI未初始化，无法打开商店")
		return
	end

	if not InitializeEvents() then
		warn(LOG_PREFIX, "事件未初始化，无法打开商店")
		return
	end

	-- 显示商店UI
	skillShopFrame.Visible = true

	-- 请求商店列表（通过事件通知SkillShopDisplay）
	RequestSkillShopList:FireServer()

	if DEBUG_MODE then
		print(LOG_PREFIX, "打开技能商店，已请求商店列表")
	end
end

--[[
关闭技能商店
]]
local function CloseSkillShop()
	if skillShopFrame then
		skillShopFrame.Visible = false
	end

	if DEBUG_MODE then
		print(LOG_PREFIX, "关闭技能商店")
	end
end

--[[
距离检测循环
]]
local function CheckProximity()
	local currentTime = tick()

	-- 检测间隔控制
	if currentTime - lastCheckTime < GameConfig.Shop.CheckInterval then
		return
	end
	lastCheckTime = currentTime

	-- 获取技能商店NPC
	local npc = GetSkillShopNPC()
	if not npc then
		-- NPC不存在时，如果之前在商店范围内则关闭
		if isNearShop then
			isNearShop = false
			CloseSkillShop()
		end
		return
	end

	-- 计算距离
	local distance = GetDistanceToNPC(npc)
	local isInRange = distance <= GameConfig.Shop.OpenDistance

	-- 状态变化处理
	if isInRange and not isNearShop then
		-- 进入范围
		isNearShop = true
		OpenSkillShop()

		if DEBUG_MODE then
			print(LOG_PREFIX, "进入技能商店范围, 距离:", string.format("%.2f", distance))
		end
	elseif not isInRange and isNearShop then
		-- 离开范围
		isNearShop = false
		CloseSkillShop()

		if DEBUG_MODE then
			print(LOG_PREFIX, "离开技能商店范围, 距离:", string.format("%.2f", distance))
		end
	end
end

-- ==================== 公共接口 ====================

--[[
初始化技能商店触发器
]]
function SkillShopTrigger.Initialize()
	if DEBUG_MODE then
		print(LOG_PREFIX, "初始化技能商店触发器...")
	end

	-- 初始化UI
	InitializeUI()

	-- 启动距离检测循环
	if checkConnection then
		checkConnection:Disconnect()
	end

	checkConnection = RunService.Heartbeat:Connect(CheckProximity)

	-- 监听角色重生
	player.CharacterAdded:Connect(function(character)
		-- 重置状态
		isNearShop = false

		-- 等待角色加载完成
		character:WaitForChild("HumanoidRootPart")

		if DEBUG_MODE then
			print(LOG_PREFIX, "角色重生，重置触发器状态")
		end
	end)

	if DEBUG_MODE then
		print(LOG_PREFIX, "技能商店触发器初始化完成")
	end

	return true
end

--[[
停止触发器
]]
function SkillShopTrigger.Stop()
	if checkConnection then
		checkConnection:Disconnect()
		checkConnection = nil
	end

	isNearShop = false
	CloseSkillShop()

	if DEBUG_MODE then
		print(LOG_PREFIX, "技能商店触发器已停止")
	end
end

--[[
手动打开商店（供其他脚本调用）
]]
function SkillShopTrigger.OpenShop()
	OpenSkillShop()
end

--[[
手动关闭商店（供其他脚本调用）
]]
function SkillShopTrigger.CloseShop()
	CloseSkillShop()
end

--[[
获取当前状态
@return boolean - 是否在商店范围内
]]
function SkillShopTrigger.IsNearShop()
	return isNearShop
end

-- ==================== 自动初始化 ====================

task.spawn(function()
	-- 等待玩家数据加载
	local maxWait = 10
	local waited = 0
	while not player:GetAttribute("HomeSlot") and waited < maxWait do
		task.wait(0.5)
		waited = waited + 0.5
	end

	-- 初始化触发器
	local success, result = pcall(SkillShopTrigger.Initialize)
	if not success then
		warn(LOG_PREFIX, "初始化失败:", result)
	end
end)

return SkillShopTrigger
