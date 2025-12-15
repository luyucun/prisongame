--[[
脚本名称: DamageNumberSystem
脚本类型: LocalScript (客户端UI系统)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/DamageNumberSystem
版本: V1.5.1
]]

--[[
伤害冒字系统
职责:
1. 监听服务端的伤害通知
2. 在受伤单位身上显示伤害数字
3. 数字向上移动并淡出消失
4. 添加随机偏移让效果更自然
]]

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- 获取本地玩家
local player = Players.LocalPlayer

-- 等待共享配置加载
local ServerScriptService = game:GetService("ServerScriptService")
local BattleConfig = nil

-- 由于客户端无法直接访问ServerScriptService，我们使用硬编码配置
-- 或者从ReplicatedStorage读取共享配置
local DamageNumberConfig = {
	ENABLE_DAMAGE_NUMBERS = true,
	RISE_DISTANCE = 3,
	DURATION = 1.5,
	TEXT_SIZE = 24,
	COLOR = Color3.fromRGB(255, 50, 50),
	STROKE_COLOR = Color3.fromRGB(0, 0, 0),
	STROKE_THICKNESS = 2,
	RANDOM_OFFSET_X = 1,
	RANDOM_OFFSET_Z = 1,
	-- 距离缩放：近大远小（相机越远，字体越小）
	ENABLE_DISTANCE_SCALE = true,
	SCALE_BASE_DISTANCE = 70, -- 距离<=该值时保持默认大小
	SCALE_MIN = 0.3, -- 最小缩放倍率（越小越“远小”）
	SCALE_UPDATE_INTERVAL = 0.05, -- 缩放刷新频率（秒）
	BILLBOARD_WIDTH = 100,
	BILLBOARD_HEIGHT = 50,
	-- V2.5新增：阵营颜色
	ATTACKER_COLOR = Color3.fromRGB(255, 255, 255),  -- 我方打敌方：白字
	DEFENDER_COLOR = Color3.fromRGB(255, 0, 0),      -- 敌方打我方：红字
}

-- 统一刷新：避免每个伤害字都绑一个RenderStepped连接
local activeDamageNumbers = {} -- [BillboardGui] = {adorneePart, textLabel, uiStroke}
local distanceScaleAccum = 0

local function CalculateScaleByDistance(distance)
	if not DamageNumberConfig.ENABLE_DISTANCE_SCALE then
		return 1
	end

	local baseDistance = DamageNumberConfig.SCALE_BASE_DISTANCE or 70
	local minScale = DamageNumberConfig.SCALE_MIN or 0.3

	if baseDistance <= 0 then
		return 1
	end

	local scale = baseDistance / math.max(distance, 1)
	return math.clamp(scale, minScale, 1)
end

local function UpdateDamageNumberScales()
	if not DamageNumberConfig.ENABLE_DISTANCE_SCALE then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	for billboard, info in pairs(activeDamageNumbers) do
		if not billboard or not billboard.Parent then
			activeDamageNumbers[billboard] = nil
		else
			local adorneePart = info.adorneePart
			local textLabel = info.textLabel
			local uiStroke = info.uiStroke

			if not adorneePart or not adorneePart.Parent or not textLabel or not textLabel.Parent then
				activeDamageNumbers[billboard] = nil
			else
				local distance = (camera.CFrame.Position - adorneePart.Position).Magnitude
				local scale = CalculateScaleByDistance(distance)

				billboard.Size = UDim2.new(
					0,
					math.floor((DamageNumberConfig.BILLBOARD_WIDTH or 100) * scale + 0.5),
					0,
					math.floor((DamageNumberConfig.BILLBOARD_HEIGHT or 50) * scale + 0.5)
				)

				local baseTextSize = DamageNumberConfig.TEXT_SIZE or 24
				textLabel.TextSize = math.max(8, math.floor(baseTextSize * scale + 0.5))

				if uiStroke and uiStroke.Parent then
					local baseThickness = DamageNumberConfig.STROKE_THICKNESS or 2
					uiStroke.Thickness = math.max(1, baseThickness * scale)
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	if not DamageNumberConfig.ENABLE_DISTANCE_SCALE then
		return
	end

	distanceScaleAccum += dt
	if distanceScaleAccum >= (DamageNumberConfig.SCALE_UPDATE_INTERVAL or 0.05) then
		distanceScaleAccum = 0
		UpdateDamageNumberScales()
	end
end)

--[[
创建伤害数字显示
@param unitModel Model - 受伤的单位模型
@param damage number - 伤害值
@param attackerTeam string|nil - 攻击者阵营 (V2.5新增)
@param targetTeam string|nil - 被击中者阵营 (V2.5新增)
]]
local function ShowDamageNumber(unitModel, damage, attackerTeam, targetTeam)
	if not DamageNumberConfig.ENABLE_DAMAGE_NUMBERS then
		return
	end

	-- 检查单位是否有效
	if not unitModel or not unitModel:IsA("Model") then
		return
	end

	local rootPart = unitModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	-- V2.5新增：根据阵营关系确定伤害冒字颜色
	local damageColor = DamageNumberConfig.COLOR
	if attackerTeam and targetTeam then
		-- 如果目标被击中（被动接收伤害）
		if targetTeam == "Attack" and attackerTeam == "Defense" then
			-- 敌方(Defense)打我方(Attack)：红字
			damageColor = DamageNumberConfig.DEFENDER_COLOR
		elseif targetTeam == "Defense" and attackerTeam == "Attack" then
			-- 我方(Attack)打敌方(Defense)：白字
			damageColor = DamageNumberConfig.ATTACKER_COLOR
		else
			-- 其他情况使用默认色
			damageColor = DamageNumberConfig.COLOR
		end
	end

	-- 创建BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Size = UDim2.new(0, DamageNumberConfig.BILLBOARD_WIDTH, 0, DamageNumberConfig.BILLBOARD_HEIGHT)
	billboard.StudsOffset = Vector3.new(0, 3, 0)  -- 从头顶稍上方开始
	-- 不要透视/盖在模型上：让它参与深度测试，被场景模型遮挡
	billboard.AlwaysOnTop = false
	billboard.Parent = rootPart

	-- 添加随机水平偏移
	local randomOffsetX = (math.random() - 0.5) * 2 * DamageNumberConfig.RANDOM_OFFSET_X
	local randomOffsetZ = (math.random() - 0.5) * 2 * DamageNumberConfig.RANDOM_OFFSET_Z
	billboard.StudsOffsetWorldSpace = Vector3.new(randomOffsetX, 0, randomOffsetZ)

	-- 创建TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "DamageText"
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = "-" .. tostring(math.floor(damage))
	textLabel.TextColor3 = damageColor  -- 使用根据阵营确定的颜色
	textLabel.TextSize = DamageNumberConfig.TEXT_SIZE
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextStrokeTransparency = 0
	textLabel.TextStrokeColor3 = DamageNumberConfig.STROKE_COLOR
	textLabel.TextTransparency = 0
	textLabel.Parent = billboard

	-- 创建UIStroke增强描边效果
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = DamageNumberConfig.STROKE_COLOR
	uiStroke.Thickness = DamageNumberConfig.STROKE_THICKNESS
	uiStroke.Parent = textLabel

	-- 近大远小：注册到统一刷新列表
	activeDamageNumbers[billboard] = {
		adorneePart = rootPart,
		textLabel = textLabel,
		uiStroke = uiStroke,
	}
	UpdateDamageNumberScales()

	-- 创建动画：向上移动
	local startOffset = billboard.StudsOffset
	local endOffset = startOffset + Vector3.new(0, DamageNumberConfig.RISE_DISTANCE, 0)

	local tweenInfo = TweenInfo.new(
		DamageNumberConfig.DURATION,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.Out
	)

	local tween = TweenService:Create(billboard, tweenInfo, {
		StudsOffset = endOffset
	})

	-- 创建淡出动画
	local fadeInfo = TweenInfo.new(
		DamageNumberConfig.DURATION * 0.5,  -- 后半段开始淡出
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.Out
	)

	local fadeTween = TweenService:Create(textLabel, fadeInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1
	})

	-- 播放动画
	tween:Play()

	-- 延迟后开始淡出
	task.delay(DamageNumberConfig.DURATION * 0.5, function()
		fadeTween:Play()
	end)

	-- 动画结束后清理
	task.delay(DamageNumberConfig.DURATION, function()
		if billboard and billboard.Parent then
			activeDamageNumbers[billboard] = nil
			billboard:Destroy()
		end
	end)
end

--[[
初始化伤害冒字系统
]]
local function Initialize()
	-- 等待Events文件夹加载
	local eventsFolder = ReplicatedStorage:WaitForChild("Events")
	local battleEventsFolder = eventsFolder:WaitForChild("BattleEvents")
	local showDamageNumberEvent = battleEventsFolder:WaitForChild("ShowDamageNumber")

	-- 监听伤害事件
	-- V2.5新增：支持新的事件参数(attackerTeam, targetTeam)
	showDamageNumberEvent.OnClientEvent:Connect(function(unitModel, damage, attackerTeam, targetTeam)
		ShowDamageNumber(unitModel, damage, attackerTeam, targetTeam)
	end)
end

-- 启动系统
Initialize()
