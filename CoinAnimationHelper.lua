--[[
脚本名称: CoinAnimationHelper
脚本类型: ModuleScript (客户端工具)
脚本位置: StarterPlayerScripts/Utils/CoinAnimationHelper
版本: V2.1
职责: 提供金币数值滚动动画效果
]]

local CoinAnimationHelper = {}

-- 引用服务
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 引用格式化工具
local FormatHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FormatHelper"))

-- 默认配置
local DEFAULT_DURATION = GameConfig.UI.CoinRollDuration or 0.8

-- 活跃动画追踪
local activeAnimations = {}

-- ==================== 私有函数 ====================

--[[
清理指定TextLabel的活跃动画
@param textLabel TextLabel - 文本标签
]]
local function CleanupAnimation(textLabel)
	if activeAnimations[textLabel] then
		local animData = activeAnimations[textLabel]
		if animData.tween and animData.tween.PlaybackState ~= Enum.PlaybackState.Completed then
			animData.tween:Cancel()
		end
		if animData.connection then
			animData.connection:Disconnect()
		end
		activeAnimations[textLabel] = nil
	end
end

--[[
格式化金币显示文本（使用大数值缩写）
@param amount number - 金币数量
@return string - 格式化后的文本
]]
local function FormatCoinText(amount)
	return FormatHelper.FormatCoinsShort(amount, true)  -- 带$符号
end

--[[
数字插值函数
@param start number - 起始值
@param finish number - 结束值
@param alpha number - 插值因子 (0-1)
@return number - 插值结果
]]
local function LerpNumber(start, finish, alpha)
	return start + (finish - start) * alpha
end

-- ==================== 公共接口 ====================

--[[
执行金币滚动动画
@param textLabel TextLabel - 要更新的文本标签
@param fromAmount number - 起始金币数量
@param toAmount number - 目标金币数量
@param options table - 动画选项 {
    Duration: number - 动画时长(秒)，默认使用GameConfig配置
    EasingStyle: Enum.EasingStyle - 缓动样式，默认Quad
    EasingDirection: Enum.EasingDirection - 缓动方向，默认Out
    OnComplete: function - 完成回调函数
    OnUpdate: function - 更新回调函数 (currentAmount)
}
]]
function CoinAnimationHelper.AnimateCoinRoll(textLabel, fromAmount, toAmount, options)
	if not textLabel or not textLabel:IsA("TextLabel") then
		warn("[CoinAnimationHelper] 无效的TextLabel")
		return
	end

	-- 参数处理
	fromAmount = fromAmount or 0
	toAmount = toAmount or 0
	options = options or {}

	local duration = options.Duration or DEFAULT_DURATION
	local easingStyle = options.EasingStyle or Enum.EasingStyle.Quad
	local easingDirection = options.EasingDirection or Enum.EasingDirection.Out
	local onComplete = options.OnComplete
	local onUpdate = options.OnUpdate

	-- 如果数值相同，直接设置文本
	if math.abs(toAmount - fromAmount) < 0.01 then
		textLabel.Text = FormatCoinText(toAmount)
		if onComplete then
			onComplete()
		end
		return
	end

	-- 清理之前的动画
	CleanupAnimation(textLabel)

	-- 创建动画数据
	local animData = {
		startAmount = fromAmount,
		targetAmount = toAmount,
		currentAmount = fromAmount,
	}

	-- 创建Tween（使用一个虚拟值进行插值）
	local tweenInfo = TweenInfo.new(
		duration,
		easingStyle,
		easingDirection,
		0,
		false,
		0
	)

	-- 创建一个虚拟对象用于Tween
	local virtualObject = Instance.new("NumberValue")
	virtualObject.Value = 0

	local tween = TweenService:Create(virtualObject, tweenInfo, {Value = 1})

	-- 连接更新事件
	local connection = virtualObject.Changed:Connect(function(alpha)
		-- 插值计算当前金币数量
		animData.currentAmount = LerpNumber(animData.startAmount, animData.targetAmount, alpha)

		-- 更新文本显示
		textLabel.Text = FormatCoinText(animData.currentAmount)

		-- 调用更新回调
		if onUpdate then
			onUpdate(animData.currentAmount)
		end
	end)

	-- 动画完成处理
	tween.Completed:Connect(function()
		-- 确保最终值正确
		textLabel.Text = FormatCoinText(toAmount)

		-- 清理
		CleanupAnimation(textLabel)
		virtualObject:Destroy()

		-- 调用完成回调
		if onComplete then
			onComplete()
		end

		print(string.format(
			"[CoinAnimationHelper] 金币动画完成: %d → %d",
			fromAmount, toAmount
		))
	end)

	-- 存储动画数据
	animData.tween = tween
	animData.connection = connection
	animData.virtualObject = virtualObject
	activeAnimations[textLabel] = animData

	-- 开始动画
	tween:Play()

	print(string.format(
		"[CoinAnimationHelper] 开始金币动画: %d → %d (时长: %.1fs)",
		fromAmount, toAmount, duration
	))
end

--[[
快速更新金币显示（无动画）
@param textLabel TextLabel - 文本标签
@param amount number - 金币数量
]]
function CoinAnimationHelper.SetCoinInstant(textLabel, amount)
	if not textLabel or not textLabel:IsA("TextLabel") then
		warn("[CoinAnimationHelper] 无效的TextLabel")
		return
	end

	-- 清理可能的活跃动画
	CleanupAnimation(textLabel)

	-- 直接设置文本
	textLabel.Text = FormatCoinText(amount)
end

--[[
检查是否有活跃的金币动画
@param textLabel TextLabel - 文本标签
@return boolean - 是否有活跃动画
]]
function CoinAnimationHelper.IsAnimating(textLabel)
	return activeAnimations[textLabel] ~= nil
end

--[[
停止金币动画
@param textLabel TextLabel - 文本标签
@param snapToTarget boolean - 是否立即跳到目标值（默认true）
]]
function CoinAnimationHelper.StopAnimation(textLabel, snapToTarget)
	if not activeAnimations[textLabel] then
		return
	end

	local animData = activeAnimations[textLabel]
	snapToTarget = snapToTarget ~= false -- 默认为true

	if snapToTarget then
		textLabel.Text = FormatCoinText(animData.targetAmount)
	end

	CleanupAnimation(textLabel)
	print(string.format("[CoinAnimationHelper] 停止金币动画: %s", textLabel.Name))
end

--[[
创建金币变化提示动画（飞入效果）
@param parentGui GuiObject - 父容器
@param amount number - 变化的金币数量（正数为增加，负数为减少）
@param startPosition UDim2 - 起始位置
@param options table - 选项 {
    Duration: number - 动画时长
    TextColor: Color3 - 文字颜色（默认根据正负自动）
    TextSize: number - 文字大小（默认24）
    Font: Enum.Font - 字体（默认Gotham）
}
]]
function CoinAnimationHelper.CreateCoinChangeEffect(parentGui, amount, startPosition, options)
	if not parentGui then
		warn("[CoinAnimationHelper] 无效的父容器")
		return
	end

	options = options or {}

	-- 创建文本标签
	local effectLabel = Instance.new("TextLabel")
	effectLabel.Name = "CoinChangeEffect"
	effectLabel.Size = UDim2.new(0, 200, 0, 50)
	effectLabel.Position = startPosition
	effectLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	effectLabel.BackgroundTransparency = 1
	effectLabel.TextScaled = true
	effectLabel.TextSize = options.TextSize or 24
	effectLabel.Font = options.Font or Enum.Font.GothamBold
	effectLabel.TextStrokeTransparency = 0
	effectLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	effectLabel.ZIndex = 100

	-- 设置文本和颜色
	local prefix = amount > 0 and "+" or ""
	effectLabel.Text = prefix .. FormatCoinText(math.abs(amount))

	if options.TextColor then
		effectLabel.TextColor3 = options.TextColor
	else
		-- 自动颜色：绿色为增加，红色为减少
		effectLabel.TextColor3 = amount > 0 and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
	end

	effectLabel.Parent = parentGui

	-- 动画：上移 + 淡出
	local duration = options.Duration or 1.5
	local moveDistance = 100

	local moveTween = TweenService:Create(effectLabel,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = startPosition + UDim2.new(0, 0, 0, -moveDistance),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)

	-- 动画完成后销毁
	moveTween.Completed:Connect(function()
		effectLabel:Destroy()
	end)

	moveTween:Play()

	print(string.format(
		"[CoinAnimationHelper] 创建金币变化特效: %s%d",
		prefix, math.abs(amount)
	))
end

--[[
清理所有活跃动画
]]
function CoinAnimationHelper.CleanupAll()
	for textLabel, _ in pairs(activeAnimations) do
		CleanupAnimation(textLabel)
	end
	print("[CoinAnimationHelper] 清理所有活跃动画")
end

return CoinAnimationHelper