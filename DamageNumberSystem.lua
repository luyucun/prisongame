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
	-- V2.5新增：阵营颜色
	ATTACKER_COLOR = Color3.fromRGB(255, 255, 255),  -- 我方打敌方：白字
	DEFENDER_COLOR = Color3.fromRGB(255, 0, 0),      -- 敌方打我方：红字
}

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
	billboard.Size = UDim2.new(0, 100, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)  -- 从头顶稍上方开始
	billboard.AlwaysOnTop = true
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
