--[[
=====================================================
脚本名称: SkillBackpackDisplay
脚本类型: LocalScript (UI控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/SkillBackpackDisplay.lua
版本: V3.0
=====================================================

功能描述:
- 管理技能背包UI显示
- 动态创建技能图标列表
- 处理技能图标点击事件
- 战斗开始时显示，战斗结束时隐藏
- 同步服务器技能数据

UI结构:
StarterGui
└── SkillBackpackGui (ScreenGui)
    └── BackpackFrame (Frame)
        └── ItemListFrame (ScrollingFrame)
            ├── UIListLayout
            └── SkillTemplate (ImageButton) [Visible=false]
                ├── Icon (ImageLabel)
                └── Number (TextLabel)

=====================================================
]]

local SkillBackpackDisplay = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- 获取本地玩家
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 引用配置
local SkillConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillConfig"))

-- UI引用
local skillBackpackGui = nil
local backpackFrame = nil
local itemListFrame = nil
local skillTemplate = nil

-- 远程事件引用
local SkillEvents = nil
local CampaignEvents = nil

-- 技能图标实例缓存: [skillId] = ImageButton
local skillIcons = {}

-- 当前技能背包数据: {[skillId] = count}
local skillInventory = {}

-- 防止重复触发的时间戳
local lastClickTime = 0
local CLICK_COOLDOWN = 0.3  -- 点击冷却时间(秒)

-- ==================== 私有函数 ====================

--[[
初始化UI引用
]]
local function InitializeUI()
	skillBackpackGui = playerGui:WaitForChild("SkillBackpackGui", 5)
	if not skillBackpackGui then
		warn("[SkillBackpackDisplay] SkillBackpackGui不存在")
		return false
	end

	-- 设置ScreenGui层级，避免被其他UI遮挡
	skillBackpackGui.DisplayOrder = 60
	skillBackpackGui.Enabled = true

	backpackFrame = skillBackpackGui:WaitForChild("BackpackFrame", 5)
	if not backpackFrame then
		warn("[SkillBackpackDisplay] BackpackFrame不存在")
		return false
	end

	-- 提升Frame层级
	backpackFrame.ZIndex = 10

	itemListFrame = backpackFrame:WaitForChild("ItemListFrame", 5)
	if not itemListFrame then
		warn("[SkillBackpackDisplay] ItemListFrame不存在")
		return false
	end

	-- 提升ItemListFrame层级
	itemListFrame.ZIndex = 11

	skillTemplate = itemListFrame:FindFirstChild("SkillTemplate")
	if not skillTemplate then
		warn("[SkillBackpackDisplay] SkillTemplate不存在")
		return false
	end

	-- 确保模板不可见
	skillTemplate.Visible = false

	return true
end

--[[
初始化远程事件
]]
local function InitializeEvents()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 5)
	if not eventsFolder then return false end

	SkillEvents = eventsFolder:FindFirstChild("SkillEvents")
	CampaignEvents = eventsFolder:FindFirstChild("CampaignEvents")

	return true
end

--[[
创建技能图标
@param skillId number - 技能ID
@param count number - 数量
@return ImageButton - 技能图标
]]
local function CreateSkillIcon(skillId, count)
	local skillData = SkillConfig.GetSkillById(skillId)
	if not skillData then return nil end

	-- 复制模板
	local icon = skillTemplate:Clone()
	icon.Name = "Skill_" .. skillId
	icon.Visible = true

	-- 设置图标
	local iconImage = icon:FindFirstChild("Icon")
	if iconImage and iconImage:IsA("ImageLabel") then
		iconImage.Image = skillData.Icon
	end

	-- 设置数量
	local numberLabel = icon:FindFirstChild("Number")
	if numberLabel and numberLabel:IsA("TextLabel") then
		numberLabel.Text = "*" .. count
	end

	-- 存储skillId到按钮属性
	icon:SetAttribute("SkillId", skillId)

	-- 关键：强制启用按钮点击
	icon.Active = true

	-- 设置LayoutOrder
	icon.LayoutOrder = skillId

	-- 先设置Parent
	icon.Parent = itemListFrame

	-- 绑定点击事件 - 多种方式确保响应
	if icon:IsA("TextButton") or icon:IsA("ImageButton") then
		icon.MouseButton1Click:Connect(function()
			OnSkillIconClick(skillId)
		end)

		icon.Activated:Connect(function()
			OnSkillIconClick(skillId)
		end)
	end

	return icon
end

--[[
更新技能图标数量
@param skillId number - 技能ID
@param count number - 新数量
]]
local function UpdateSkillIconCount(skillId, count)
	local icon = skillIcons[skillId]
	if not icon then return end

	local numberLabel = icon:FindFirstChild("Number")
	if numberLabel and numberLabel:IsA("TextLabel") then
		numberLabel.Text = "*" .. count
	end
end

--[[
移除技能图标
@param skillId number - 技能ID
]]
local function RemoveSkillIcon(skillId)
	local icon = skillIcons[skillId]
	if icon then
		icon:Destroy()
		skillIcons[skillId] = nil
	end
end

--[[
刷新技能背包显示
@param inventory table - 技能背包数据 {[skillId] = count}
]]
local function RefreshDisplay(inventory)
	skillInventory = inventory or {}

	-- 获取当前显示的技能ID集合
	local currentIds = {}
	for skillId, _ in pairs(skillIcons) do
		currentIds[skillId] = true
	end

	-- 更新或创建图标
	for skillId, count in pairs(skillInventory) do
		if count > 0 then
			if skillIcons[skillId] then
				-- 更新数量
				UpdateSkillIconCount(skillId, count)
			else
				-- 创建新图标
				skillIcons[skillId] = CreateSkillIcon(skillId, count)
			end
			currentIds[skillId] = nil  -- 标记为已处理
		end
	end

	-- 移除不再拥有的技能图标
	for skillId, _ in pairs(currentIds) do
		RemoveSkillIcon(skillId)
	end
end

--[[
技能图标点击处理
@param skillId number - 技能ID
]]
function OnSkillIconClick(skillId)
	-- 防止短时间内重复触发
	local currentTime = tick()
	if currentTime - lastClickTime < CLICK_COOLDOWN then
		return
	end
	lastClickTime = currentTime

	-- 如果已经在瞄准状态,忽略点击
	if _G.SkillController and _G.SkillController.IsAiming and _G.SkillController.IsAiming() then
		return
	end

	-- 检查是否还有该技能
	local count = skillInventory[skillId] or 0
	if count <= 0 then
		warn("[SkillBackpackDisplay] 技能数量不足:", skillId)
		return
	end

	-- 调用SkillController开始瞄准
	if _G.SkillController and _G.SkillController.StartSkillCast then
		_G.SkillController.StartSkillCast(skillId)
	else
		warn("[SkillBackpackDisplay] SkillController未初始化")
	end
end

--[[
显示技能背包
]]
local function ShowBackpack()
	if itemListFrame then
		itemListFrame.Visible = true

		-- 请求服务器同步技能数据
		if SkillEvents then
			local requestSync = SkillEvents:FindFirstChild("RequestSkillSync")
			if requestSync then
				requestSync:FireServer()
			end
		end
	end
end

--[[
隐藏技能背包
]]
local function HideBackpack()
	if itemListFrame then
		itemListFrame.Visible = false
	end

	-- 如果正在瞄准,取消瞄准
	if _G.SkillController and _G.SkillController.IsAiming and _G.SkillController.IsAiming() then
		_G.SkillController.CancelAiming()
	end
end

-- ==================== 公共接口 ====================

--[[
初始化技能背包显示
]]
function SkillBackpackDisplay.Initialize()
	-- 初始化UI
	if not InitializeUI() then
		warn("[SkillBackpackDisplay] UI初始化失败")
		return false
	end

	-- 初始化事件
	InitializeEvents()

	-- 监听技能背包更新
	if SkillEvents then
		local updateEvent = SkillEvents:FindFirstChild("SkillInventoryUpdate")
		if updateEvent then
			updateEvent.OnClientEvent:Connect(function(inventory)
				RefreshDisplay(inventory)
			end)
		end
	end

	-- 监听战役状态更新(战斗开始/结束)
	if CampaignEvents then
		local stateUpdate = CampaignEvents:FindFirstChild("CampaignStateUpdate")
		if stateUpdate then
			stateUpdate.OnClientEvent:Connect(function(state, stageNum)
				-- 战斗状态:显示技能背包
				if state == "Fighting" or state == "Preparing" or state == "Marching" then
					ShowBackpack()
				-- 非战斗状态:隐藏技能背包
				elseif state == "Idle" or state == "Victory" or state == "Defeat" then
					HideBackpack()
				end
			end)
		end
	end

	-- 全局输入监听作为兜底（处理透明覆盖层拦截输入的情况）
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not itemListFrame or not itemListFrame.Visible then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and
			input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local pos = input.Position
		local hitObjects = playerGui:GetGuiObjectsAtPosition(pos.X, pos.Y)
		for _, gui in ipairs(hitObjects) do
			local skillId = gui:GetAttribute("SkillId")
			if skillId then
				OnSkillIconClick(skillId)
				return
			end
		end
	end)

	-- 初始隐藏
	HideBackpack()

	return true
end

--[[
手动刷新背包(供其他脚本调用)
@param inventory table - 技能背包数据
]]
function SkillBackpackDisplay.Refresh(inventory)
	RefreshDisplay(inventory)
end

--[[
手动显示背包
]]
function SkillBackpackDisplay.Show()
	ShowBackpack()
end

--[[
手动隐藏背包
]]
function SkillBackpackDisplay.Hide()
	HideBackpack()
end

--[[
获取技能数量
@param skillId number - 技能ID
@return number - 数量
]]
function SkillBackpackDisplay.GetSkillCount(skillId)
	return skillInventory[skillId] or 0
end

-- 暴露到全局
_G.SkillBackpackDisplay = SkillBackpackDisplay

-- 自动初始化
SkillBackpackDisplay.Initialize()

return SkillBackpackDisplay
