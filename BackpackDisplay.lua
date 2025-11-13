--[[
脚本名称: BackpackDisplay
脚本类型: LocalScript (客户端)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/BackpackDisplay
版本: V2.0.2 重构版
]]

--[[
背包显示控制器
职责:
1. 显示玩家背包中的兵种列表
2. 监听服务端背包更新事件
3. 动态创建和更新兵种条目UI（使用模板克隆）
4. 显示兵种图标（Icon）
5. 提供公共接口供BackpackTrigger调用
]]

-- 等待玩家和GUI加载
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 等待背包UI加载
local backpackGui = playerGui:WaitForChild("BackpackGui", 10)
if not backpackGui then
	warn("[BackpackDisplay] 错误: 找不到BackpackGui!")
	return
end

local backpackFrame = backpackGui:WaitForChild("BackpackFrame", 5)
if not backpackFrame then
	warn("[BackpackDisplay] 错误: 找不到BackpackFrame!")
	return
end

-- V2.0.2: 使用新的UI结构，增加等待时间
local itemListFrame = backpackFrame:WaitForChild("ItemListFrame", 10)
if not itemListFrame then
	warn("[BackpackDisplay] 错误: 找不到ItemListFrame!")
	return
end

-- 使用WaitForChild而不是FindFirstChild，确保等待模板加载
local armyItemTemplate = itemListFrame:WaitForChild("ArmyTemplate", 10)
if not armyItemTemplate then
	warn("[BackpackDisplay] 错误: 找不到ArmyTemplate!")
	warn("[BackpackDisplay] 请确认StarterGui中存在：BackpackGui → BackpackFrame → ItemListFrame → ArmyTemplate")
	return
end

-- 确保模板默认隐藏
armyItemTemplate.Visible = false

-- ✅ V2.0.2修复：禁用滚动条显示
if itemListFrame:IsA("ScrollingFrame") then
	-- 禁用滚动功能，避免显示滚动条
	itemListFrame.ScrollingEnabled = false
	-- 不修改CanvasSize，保持与AbsoluteSize一致，这样不会触发滚动条
	-- 移除原有的强制设置CanvasSize逻辑
end

-- ⚠️ V2.0.2重大修复：不使用Enabled控制显示，改用Visible
-- 原因：Enabled=false会导致所有子元素无法响应点击事件
backpackGui.Enabled = true  -- ScreenGui始终保持启用状态
backpackGui.DisplayOrder = 50  -- ⚠️ 关键修复：提升到最高层，避免被MainGui遮挡
backpackFrame.Visible = false  -- 使用Visible控制显示/隐藏
backpackFrame.ZIndex = 10  -- 提升Frame层级

-- 提升按钮和子元素ZIndex
if itemListFrame then
	itemListFrame.ZIndex = 11
end

-- 获取远程事件
local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
local inventoryEvents = eventsFolder and eventsFolder:WaitForChild("InventoryEvents", 10)

-- 引用UnitConfig
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))

-- ==================== 私有变量 ====================

-- 存储已创建的UI条目 [unitId] = TextButton
local itemButtons = {}

-- 存储背包实例数据 [unitId] = {Name, Count, Instances}
local inventoryDataCache = {}

-- ✅ V2.0.2新增：缓存BackpackFrame的初始背景透明度
local originalBackgroundTransparency = backpackFrame.BackgroundTransparency

-- ✅ V2.0.2新增：请求刷新的防抖计时器和标记
local requestRefreshDebounce = false
local REFRESH_DEBOUNCE_TIME = 0.3  -- 防抖时间（秒）

-- 调试模式
local DEBUG_MODE = false

-- ==================== 背包可用状态 ====================
local hasAvailableUnitsCache = false

local function ComputeHasAvailableUnits()
	for _, button in pairs(itemButtons) do
		if button and button.Parent and button.Visible then
			return true
		end
	end
	return false
end

local function RefreshHasUnitsCache()
	local hasUnits = ComputeHasAvailableUnits()
	local changed = hasUnits ~= hasAvailableUnitsCache
	hasAvailableUnitsCache = hasUnits
	if changed and _G.BackpackTrigger and _G.BackpackTrigger.RefreshVisibility then
		_G.BackpackTrigger.RefreshVisibility()
	end
end

-- ==================== 私有函数 ====================

--[[
请求服务器刷新背包数据（带防抖）
]]
local function RequestInventoryRefresh()
	if requestRefreshDebounce then
		return  -- 正在防抖中，跳过
	end

	requestRefreshDebounce = true

	-- 延迟发送请求
	task.spawn(function()
		task.wait(REFRESH_DEBOUNCE_TIME)

		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			local inventoryEvents = eventsFolder:FindFirstChild("InventoryEvents")
			if inventoryEvents then
				local requestEvent = inventoryEvents:FindFirstChild("RequestInventory")
				if requestEvent then
					requestEvent:FireServer()
					if DEBUG_MODE then
						print("[BackpackDisplay] 检测到数据不一致，已请求刷新")
					end
				end
			end
		end

		requestRefreshDebounce = false
	end)
end

--[[
处理兵种条目点击
@param unitId string
@param unitName string
]]
local function OnUnitItemClicked(unitId, unitName)
	-- V1.3: 检查是否处于回收模式
	if _G.RemovalController and _G.RemovalController.IsRemovalMode() then
		warn("[BackpackDisplay] 回收模式下无法点击背包放置兵种")
		return
	end

	-- V2.0.2: 不再关闭背包，保持显示
	-- backpackGui.Enabled = false  -- 移除此行

	-- 从缓存中获取第一个未放置的实例
	local unitData = inventoryDataCache[unitId]
	if unitData and unitData.Instances then
		for _, instanceInfo in ipairs(unitData.Instances) do
			if not instanceInfo.IsPlaced then
				-- 调用PlacementController开始放置
				if _G.PlacementController then
					_G.PlacementController.StartPlacement(
						instanceInfo.InstanceId,
						unitId,
						instanceInfo.GridSize
					)
				else
					warn("[BackpackDisplay] PlacementController未找到!")
				end
				return
			end
		end
	else
		-- 如果没有实例数据，重新请求背包数据并延迟重试
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		if eventsFolder then
			local inventoryEvents = eventsFolder:FindFirstChild("InventoryEvents")
			if inventoryEvents then
				local requestEvent = inventoryEvents:FindFirstChild("RequestInventory")
				if requestEvent then
					requestEvent:FireServer()
					-- 等待一小段时间让数据刷新
					task.wait(0.1)
					-- 重新尝试
					local updatedUnitData = inventoryDataCache[unitId]
					if updatedUnitData and updatedUnitData.Instances then
						for _, instanceInfo in ipairs(updatedUnitData.Instances) do
							if not instanceInfo.IsPlaced then
								if _G.PlacementController then
									_G.PlacementController.StartPlacement(
										instanceInfo.InstanceId,
										unitId,
										instanceInfo.GridSize
									)
								end
								return
							end
						end
					end
				end
			end
		end
	end

	warn("[BackpackDisplay] 没有可放置的", unitName, "实例")
end

--[[
创建一个兵种条目UI（从模板克隆）
@param unitId string - 兵种ID
@param unitName string - 兵种名称
@param count number - 数量
@param iconId string - 图标资源ID
@return TextButton - 创建的条目按钮
]]
local function CreateItemButton(unitId, unitName, count, iconId)
	-- 克隆模板
	local itemButton = armyItemTemplate:Clone()
	itemButton.Name = "Item_" .. unitId
	itemButton.Visible = true

	-- 设置图标
	local iconLabel = itemButton:FindFirstChild("Icon")
	if iconLabel and iconLabel:IsA("ImageLabel") then
		iconLabel.Image = iconId or "rbxassetid://0"
	else
		warn("[BackpackDisplay] 找不到Icon或类型不对:", iconLabel and iconLabel.ClassName or "nil")
	end

	-- 设置数量文本
	local numberLabel = itemButton:FindFirstChild("Number")
	if numberLabel and numberLabel:IsA("TextLabel") then
		numberLabel.Text = "x" .. count
	else
		warn("[BackpackDisplay] 找不到Number或类型不对:", numberLabel and numberLabel.ClassName or "nil")
	end

	-- 存储unitId到按钮属性
	itemButton:SetAttribute("UnitId", unitId)

	-- ⚠️ V2.0.2关键修复：强制启用按钮点击
	itemButton.Active = true  -- 必须设置为true才能响应点击

	-- 先设置Parent，再绑定事件（确保在层级树中）
	itemButton.Parent = itemListFrame

	-- 点击事件 - 根据按钮类型选择事件
	if itemButton:IsA("TextButton") or itemButton:IsA("ImageButton") then
		-- 主要事件
		itemButton.MouseButton1Click:Connect(function()
			OnUnitItemClicked(unitId, unitName)
		end)

		-- 兜底事件1：MouseButton1Down
		itemButton.MouseButton1Down:Connect(function()
		end)

		-- 兜底事件2：Activated（通用激活事件）
		itemButton.Activated:Connect(function()
			OnUnitItemClicked(unitId, unitName)
		end)

	elseif itemButton:IsA("GuiButton") then
		itemButton.Activated:Connect(function()
			OnUnitItemClicked(unitId, unitName)
		end)
	else
		-- 如果不是按钮类型，手动添加点击检测
		warn("[BackpackDisplay] ⚠️ 模板不是按钮类型，使用InputBegan事件")
		itemButton.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or
				input.UserInputType == Enum.UserInputType.Touch then
				OnUnitItemClicked(unitId, unitName)
			end
		end)
	end

	-- ⚠️ 终极兜底：在ItemListFrame上监听所有输入
	if not itemListFrame:GetAttribute("InputListenerAdded") then
		itemListFrame:SetAttribute("InputListenerAdded", true)
		itemListFrame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or
				input.UserInputType == Enum.UserInputType.Touch then
				-- 查找被点击的按钮
				local mousePos = input.Position
				for _, child in ipairs(itemListFrame:GetChildren()) do
					if child:IsA("GuiButton") and child.Visible then
						local absPos = child.AbsolutePosition
						local absSize = child.AbsoluteSize
						if mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X and
							mousePos.Y >= absPos.Y and mousePos.Y <= absPos.Y + absSize.Y then
							local clickedUnitId = child:GetAttribute("UnitId")
							if clickedUnitId then
								-- 找到unitName
								for id, data in pairs(inventoryDataCache) do
									if id == clickedUnitId then
										OnUnitItemClicked(clickedUnitId, data.Name)
										break
									end
								end
							end
						end
					end
				end
			end
		end)
	end

	-- ⚠️ V2.0.2终极兜底方案：PlayerGui全局输入监听
	-- 用于处理透明覆盖层拦截输入的情况
	if not _G.BackpackDisplayGlobalInputAdded then
		_G.BackpackDisplayGlobalInputAdded = true

		local function HandleGlobalInput(input, gameProcessed)
			-- ⚠️ 关键修复：即使gameProcessed=true也要继续执行
			-- 因为透明UI可能已经标记为processed，但我们仍需检查背包按钮
			if not backpackFrame.Visible then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and
				input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end

			local pos = input.Position
			-- 修复：使用playerGui而非GuiService
			local hitObjects = playerGui:GetGuiObjectsAtPosition(pos.X, pos.Y)
			for _, gui in ipairs(hitObjects) do
				local unitId = gui:GetAttribute("UnitId")
				if unitId then
					local unitName = (inventoryDataCache[unitId] and inventoryDataCache[unitId].Name) or unitId
					OnUnitItemClicked(unitId, unitName)
					return
				end
			end
		end

		UserInputService.InputBegan:Connect(HandleGlobalInput)
	end

	return itemButton
end

--[[
更新指定兵种的UI显示
@param unitId string - 兵种ID
@param unitName string - 兵种名称
@param count number - 数量（服务端发来的总数）
]]
local function UpdateItemDisplay(unitId, unitName, count)
	-- ✅ V2.0.2兜底检查：检测数据不一致并主动刷新
	-- 如果收到的count与缓存不一致，说明可能是旧的UnitUpdated事件，需要刷新完整数据
	local cachedData = inventoryDataCache[unitId]
	if cachedData then
		local cachedTotalCount = cachedData.Count or 0

		-- 如果服务端发来的count与缓存中的总数不一致，触发刷新
		if count ~= cachedTotalCount then
			if DEBUG_MODE then
				warn(string.format(
					"[BackpackDisplay] 数据不一致 - UnitId:%s 服务端count:%d 缓存count:%d，请求刷新",
					unitId, count, cachedTotalCount
				))
			end

			-- 请求完整刷新（带防抖）
			RequestInventoryRefresh()

			-- 暂时不更新UI，等待InventoryRefresh事件
			return
		end
	end

	local itemButton = itemButtons[unitId]

	if count > 0 then
		-- 获取图标
		local iconId = UnitConfig.GetIcon(unitId)

		-- 如果数量大于0，更新或创建UI
		if itemButton then
			-- 更新现有条目的数量
			local numberLabel = itemButton:FindFirstChild("Number")
			if numberLabel then
				numberLabel.Text = "x" .. count
			end
		else
			-- 创建新条目
			itemButton = CreateItemButton(unitId, unitName, count, iconId)
			itemButtons[unitId] = itemButton
		end
	else
		-- 如果数量为0，删除UI
		if itemButton then
			itemButton:Destroy()
			itemButtons[unitId] = nil
		end
	end

	RefreshHasUnitsCache()
end

--[[
刷新整个背包显示
@param inventoryData table - 背包数据 {[unitId] = {Name, Count, Instances}}
]]
local function RefreshInventory(inventoryData)
	-- 清空现有UI
	for _, button in pairs(itemButtons) do
		button:Destroy()
	end
	itemButtons = {}

	-- 缓存背包数据
	inventoryDataCache = inventoryData or {}

	-- 重新创建所有条目
	if inventoryData then
		for unitId, data in pairs(inventoryData) do
			-- 只显示未放置的兵种数量
			local availableCount = 0
			if data.Instances then
				for _, instance in ipairs(data.Instances) do
					if not instance.IsPlaced then
						availableCount = availableCount + 1
					end
				end
			else
				availableCount = data.Count
			end

			if availableCount > 0 then
				local iconId = UnitConfig.GetIcon(unitId)
				local button = CreateItemButton(unitId, data.Name, availableCount, iconId)
				itemButtons[unitId] = button
			end
		end
	end

	RefreshHasUnitsCache()
end

-- ==================== 事件处理 ====================

-- 监听背包更新事件
if inventoryEvents then
	-- 监听单个兵种更新
	local unitUpdatedEvent = inventoryEvents:FindFirstChild("UnitUpdated")
	if unitUpdatedEvent then
		unitUpdatedEvent.OnClientEvent:Connect(function(unitId, unitName, count)
			UpdateItemDisplay(unitId, unitName, count)
		end)
	else
		warn("[BackpackDisplay] 找不到UnitUpdated事件!")
	end

	-- 监听完整背包刷新
	local inventoryRefreshEvent = inventoryEvents:FindFirstChild("InventoryRefresh")
	if inventoryRefreshEvent then
		inventoryRefreshEvent.OnClientEvent:Connect(function(inventoryData)
			RefreshInventory(inventoryData)
		end)
	else
		warn("[BackpackDisplay] 找不到InventoryRefresh事件!")
	end

	-- 请求初始背包数据
	task.wait(0.5)
	local requestEvent = inventoryEvents:FindFirstChild("RequestInventory")
	if requestEvent then
		requestEvent:FireServer()
	else
		warn("[BackpackDisplay] 找不到RequestInventory事件!")
	end
else
	warn("[BackpackDisplay] 找不到InventoryEvents!")
end

-- ==================== 公共接口 (V2.0.2新增) ====================

local BackpackDisplay = {}

--[[
显示背包
]]
function BackpackDisplay.ShowBackpack()
	-- ⚠️ V2.0.2修复：确保ScreenGui始终启用
	backpackGui.Enabled = true
	backpackFrame.Visible = true
end

--[[
隐藏背包
]]
function BackpackDisplay.HideBackpack()
	-- ⚠️ V2.0.2修复：只隐藏Frame，不禁用ScreenGui
	backpackFrame.Visible = false
end

--[[
切换背包显示
]]
function BackpackDisplay.ToggleBackpack()
	backpackFrame.Visible = not backpackFrame.Visible  -- V2.0.2修复：使用Visible而不是Enabled
end

--[[
获取背包缓存数据
@return table - inventoryDataCache
]]
function BackpackDisplay.GetInventoryCache()
	return inventoryDataCache
end

--[[
返回是否存在可放置的兵种
@return boolean
]]
function BackpackDisplay.HasAvailableUnits()
	return hasAvailableUnitsCache
end

--[[
设置放置模式时的UI行为（V2.0.2新增）
@param isPlacing boolean - 是否正在放置兵种
]]
function BackpackDisplay.SetPlacingMode(isPlacing)
	if not backpackFrame then return end

	if isPlacing then
		-- ✅ 放置模式：让BackpackFrame的空白区域不拦截输入
		-- 方案1：提高透明度，让玩家看到下面的地面
		backpackFrame.BackgroundTransparency = 0.95

		-- 方案2：或者缩小到屏幕边缘（可选，根据需要启用）
		-- backpackFrame.Position = UDim2.new(1, -250, 0, 50)
		-- backpackFrame.Size = UDim2.new(0, 200, 0, 400)
	else
		-- ✅ V2.0.2修复：恢复原始透明度，而不是硬写为0
		-- 原因：硬写0会导致黑色背景出现
		backpackFrame.BackgroundTransparency = originalBackgroundTransparency

		-- 如果启用了位置移动，这里恢复原始位置
		-- backpackFrame.Position = UDim2.new(0, 50, 0, 50)
		-- backpackFrame.Size = UDim2.new(0, 300, 0, 500)
	end
end

-- 提供全局访问接口
_G.BackpackDisplay = BackpackDisplay

-- ✅ V2.0.2新增：初始化完成后通知BackpackTrigger刷新显示状态
-- 延迟执行，确保BackpackTrigger也已加载
task.spawn(function()
	task.wait(1)  -- 等待BackpackTrigger加载
	if _G.BackpackTrigger and _G.BackpackTrigger.RefreshVisibility then
		_G.BackpackTrigger.RefreshVisibility()
		if DEBUG_MODE then
			print("[BackpackDisplay] 初始化完成，已通知BackpackTrigger刷新")
		end
	end
end)

-- ==================== V2.0.2: 移除B键切换逻辑 ====================
-- 背包显示/隐藏现在由BackpackTrigger控制
