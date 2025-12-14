--[[
=====================================================
脚本名称: SkillController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/SkillController.lua
版本: V3.0
=====================================================

功能描述:
- 处理技能释放的客户端输入
- 显示技能预览圆圈(SkillPreview)
- 管理技能瞄准和确认
- 支持PC端(鼠标)和移动端(触屏)

操作流程:
1. 点击技能背包中的技能图标
2. 显示技能预览圆圈跟随鼠标/手指
3. 左键/点击确认释放，右键/取消按钮取消
4. 发送释放请求到服务器

=====================================================
]]

local SkillController = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- 获取本地玩家
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local SkillConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillConfig"))

-- 收敛调试print，避免刷屏（仅在DEBUG_MODE开启时输出）
local DEBUG_MODE = GameConfig.DEBUG_MODE
local _print = print
local function DebugPrint(...)
	if DEBUG_MODE then
		_print(...)
	end
end
local print = DebugPrint

-- 远程事件
local SkillEvents = nil

-- 状态变量
local isAiming = false           -- 是否正在瞄准
local currentSkillId = nil       -- 当前选中的技能ID
local previewPart = nil          -- 预览圆圈实例
local previewConnection = nil    -- RenderStepped连接
local aimStartTime = 0           -- 瞄准开始时间(防止立即确认)

-- ==================== 私有函数 ====================

--[[
初始化远程事件引用
]]
local function InitializeEvents()
	if SkillEvents then return true end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 5)
	if eventsFolder then
		SkillEvents = eventsFolder:WaitForChild("SkillEvents", 5)
	end

	return SkillEvents ~= nil
end

--[[
获取鼠标射线击中点(贴地)
@return Vector3|nil - 击中位置
]]
local function GetMouseHitPosition()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	-- 创建射线参数
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {player.Character, previewPart}

	-- 从鼠标位置发射射线
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local rayResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)

	if rayResult then
		return rayResult.Position
	end

	-- 如果没有击中,返回nil
	return nil
end

--[[
创建技能预览圆圈
@param skillId number - 技能ID
@return BasePart - 预览Part
]]
local function CreatePreviewPart(skillId)
	local skillData = SkillConfig.GetSkillById(skillId)
	if not skillData then return nil end

	-- 尝试从ReplicatedStorage获取模板
	local previewTemplate = ReplicatedStorage:FindFirstChild("SkillPreview")

	local preview
	if previewTemplate and previewTemplate:IsA("BasePart") then
		preview = previewTemplate:Clone()
	else
		-- 创建默认预览Part
		preview = Instance.new("Part")
		preview.Shape = Enum.PartType.Cylinder
		preview.Material = Enum.Material.Neon
		preview.Color = Color3.fromRGB(0, 255, 100)
		preview.Transparency = 0.5
	end

	-- 设置大小(Range是直径)
	local diameter = skillData.Range
	preview.Size = Vector3.new(0.5, diameter, diameter)  -- Cylinder: (高度, 直径X, 直径Z)
	preview.CFrame = CFrame.new(0, -100, 0) * CFrame.Angles(0, 0, math.rad(90))  -- 躺平

	-- 设置物理属性
	preview.Anchored = true
	preview.CanCollide = false
	preview.CastShadow = false

	preview.Name = "SkillPreview_" .. skillId
	preview.Parent = workspace

	return preview
end

--[[
更新预览位置
]]
local function UpdatePreviewPosition()
	if not previewPart then return end

	local hitPosition = GetMouseHitPosition()
	if hitPosition then
		-- 预览圆圈贴地显示(稍微抬高避免z-fighting)
		previewPart.CFrame = CFrame.new(hitPosition.X, hitPosition.Y + 0.3, hitPosition.Z) * CFrame.Angles(0, 0, math.rad(90))
	end
end

--[[
开始瞄准模式
@param skillId number - 技能ID
]]
local function StartAiming(skillId)
	if isAiming then
		-- 如果已经在瞄准,先停止
		SkillController.CancelAiming()
	end

	local skillData = SkillConfig.GetSkillById(skillId)
	if not skillData then
		warn("[SkillController] 无效的技能ID:", skillId)
		return
	end

	isAiming = true
	currentSkillId = skillId
	aimStartTime = tick()  -- 记录瞄准开始时间

	-- 创建预览Part
	previewPart = CreatePreviewPart(skillId)

	-- 连接RenderStepped更新位置
	if previewConnection then
		previewConnection:Disconnect()
	end

	previewConnection = RunService.RenderStepped:Connect(function()
		if isAiming then
			UpdatePreviewPosition()
		end
	end)

	print("[SkillController] 开始瞄准技能:", skillData.Name)
end

--[[
确认释放技能
]]
local function ConfirmCast()
	if not isAiming or not currentSkillId then return end

	-- 防止点击按钮后立即触发确认(需要至少0.15秒的瞄准时间)
	local aimDuration = tick() - aimStartTime
	if aimDuration < 0.15 then
		print("[SkillController] 瞄准时间过短,忽略此次确认:", aimDuration)
		return
	end

	local hitPosition = GetMouseHitPosition()
	if not hitPosition then
		warn("[SkillController] 无法获取释放位置")
		return
	end

	-- 发送释放请求到服务器
	if InitializeEvents() and SkillEvents then
		local requestEvent = SkillEvents:FindFirstChild("RequestCastSkill")
		if requestEvent then
			requestEvent:FireServer(currentSkillId, hitPosition)
			print("[SkillController] 发送技能释放请求:", currentSkillId, hitPosition)
		end
	end

	-- 停止瞄准
	SkillController.CancelAiming()
end

-- ==================== 公共接口 ====================

--[[
取消瞄准模式
]]
function SkillController.CancelAiming()
	isAiming = false
	currentSkillId = nil

	-- 断开RenderStepped连接
	if previewConnection then
		previewConnection:Disconnect()
		previewConnection = nil
	end

	-- 销毁预览Part
	if previewPart then
		previewPart:Destroy()
		previewPart = nil
	end

	print("[SkillController] 取消瞄准")
end

--[[
开始释放技能(由SkillBackpackDisplay调用)
@param skillId number - 技能ID
]]
function SkillController.StartSkillCast(skillId)
	StartAiming(skillId)
end

--[[
检查是否正在瞄准
@return boolean
]]
function SkillController.IsAiming()
	return isAiming
end

--[[
获取当前瞄准的技能ID
@return number|nil
]]
function SkillController.GetCurrentSkillId()
	return currentSkillId
end

--[[
初始化控制器
]]
function SkillController.Initialize()
	InitializeEvents()

	-- 监听鼠标输入
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if isAiming then
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				-- 左键确认
				ConfirmCast()
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				-- 右键取消
				SkillController.CancelAiming()
			end
		end
	end)

	-- 监听触屏输入(移动端)
	UserInputService.TouchTap:Connect(function(touchPositions, gameProcessed)
		if gameProcessed then return end

		if isAiming and #touchPositions > 0 then
			-- 触屏点击确认
			ConfirmCast()
		end
	end)

	-- 监听键盘取消(ESC键)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.Escape and isAiming then
			SkillController.CancelAiming()
		end
	end)

	-- 监听服务器响应
	if SkillEvents then
		local responseEvent = SkillEvents:FindFirstChild("CastSkillResponse")
		if responseEvent then
			responseEvent.OnClientEvent:Connect(function(success, message)
				if not success then
					warn("[SkillController] 技能释放失败:", message)
				end
			end)
		end
	end

	print("[SkillController] 技能控制器初始化完成")
	return true
end

-- 暴露到全局供其他脚本调用
_G.SkillController = SkillController

-- 自动初始化
SkillController.Initialize()

return SkillController
