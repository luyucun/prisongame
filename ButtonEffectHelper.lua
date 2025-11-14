--[[
脚本名称: ButtonEffectHelper
脚本类型: ModuleScript (客户端工具)
脚本位置: StarterPlayerScripts/Utils/ButtonEffectHelper
版本: V2.1
职责: 提供通用的按钮点击特效（缩放动画）
]]

local ButtonEffectHelper = {}

-- 引用服务
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 默认配置
local DEFAULT_SCALE_DOWN = GameConfig.UI.ButtonScaleDown or 0.9
local DEFAULT_DURATION = GameConfig.UI.ButtonScaleDuration or 0.1

-- 活跃的Tween缓存
local activeTweens = {}

-- ==================== 私有函数 ====================

--[[
清理按钮的活跃Tween
@param button GuiObject - 按钮对象
]]
local function CleanupTweens(button)
	if activeTweens[button] then
		for _, tween in ipairs(activeTweens[button]) do
			if tween.PlaybackState ~= Enum.PlaybackState.Completed then
				tween:Cancel()
			end
		end
		activeTweens[button] = nil
	end
end

--[[
创建缩放Tween
@param button GuiObject - 按钮对象
@param targetScale number - 目标缩放比例
@param duration number - 动画时长
@param easingStyle Enum.EasingStyle - 缓动样式
@param originalSize UDim2 - 原始大小（可选，用于计算正确的缩放）
@return Tween - 创建的Tween对象
]]
local function CreateScaleTween(button, targetScale, duration, easingStyle, originalSize)
	-- 获取原始大小（如果未提供）
	local baseSize = originalSize or button.Size

	local tweenInfo = TweenInfo.new(
		duration,
		easingStyle or Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		0,
		false,
		0
	)

	-- 正确的缩放计算：将整个原始大小乘以缩放因子
	local tween = TweenService:Create(button, tweenInfo, {
		Size = UDim2.new(
			baseSize.X.Scale * targetScale,
			baseSize.X.Offset * targetScale,
			baseSize.Y.Scale * targetScale,
			baseSize.Y.Offset * targetScale
		)
	})

	return tween
end

-- ==================== 公共接口 ====================

--[[
为按钮添加点击特效
@param button GuiObject - 按钮对象
@param options table - 配置选项 {
    ScaleDown: number - 按下时的缩放比例 (默认0.9)
    Duration: number - 动画时长 (默认0.1)
    EasingStyle: Enum.EasingStyle - 缓动样式 (默认Quad)
    OnClick: function - 点击回调函数 (可选)
}
]]
function ButtonEffectHelper.AddClickEffect(button, options)
	if not button or not button:IsA("GuiObject") then
		warn("[ButtonEffectHelper] 无效的按钮对象")
		return
	end

	options = options or {}

	local scaleDown = options.ScaleDown or DEFAULT_SCALE_DOWN
	local duration = options.Duration or DEFAULT_DURATION
	local easingStyle = options.EasingStyle or Enum.EasingStyle.Quad
	local onClick = options.OnClick

	-- 存储原始大小
	local originalSize = button.Size

	-- 清理可能存在的旧Tween
	CleanupTweens(button)
	activeTweens[button] = {}

	-- 鼠标按下事件
	button.MouseButton1Down:Connect(function()
		CleanupTweens(button)
		activeTweens[button] = {}

		-- 缩小动画（传递原始大小）
		local scaleDownTween = CreateScaleTween(button, scaleDown, duration, easingStyle, originalSize)
		table.insert(activeTweens[button], scaleDownTween)
		scaleDownTween:Play()
	end)

	-- 鼠标释放事件
	button.MouseButton1Up:Connect(function()
		CleanupTweens(button)
		activeTweens[button] = {}

		-- 恢复大小动画
		local scaleUpTween = TweenService:Create(button,
			TweenInfo.new(duration, easingStyle, Enum.EasingDirection.Out),
			{Size = originalSize}
		)
		table.insert(activeTweens[button], scaleUpTween)
		scaleUpTween:Play()
	end)

	-- 点击事件（如果提供了回调）
	if onClick then
		button.MouseButton1Click:Connect(onClick)
	end

	print(string.format("[ButtonEffectHelper] 为按钮 %s 添加了点击特效", button.Name))
end

--[[
为按钮添加悬停特效
@param button GuiObject - 按钮对象
@param options table - 配置选项 {
    HoverScale: number - 悬停时的缩放比例 (默认1.05)
    Duration: number - 动画时长 (默认0.15)
    EasingStyle: Enum.EasingStyle - 缓动样式 (默认Quad)
}
]]
function ButtonEffectHelper.AddHoverEffect(button, options)
	if not button or not button:IsA("GuiObject") then
		warn("[ButtonEffectHelper] 无效的按钮对象")
		return
	end

	options = options or {}

	local hoverScale = options.HoverScale or 1.05
	local duration = options.Duration or 0.15
	local easingStyle = options.EasingStyle or Enum.EasingStyle.Quad

	-- 存储原始大小
	local originalSize = button.Size

	-- 鼠标进入事件
	button.MouseEnter:Connect(function()
		CleanupTweens(button)
		activeTweens[button] = {}

		-- 放大动画（正确的缩放计算：基于原始大小）
		local hoverTween = TweenService:Create(button,
			TweenInfo.new(duration, easingStyle, Enum.EasingDirection.Out),
			{Size = UDim2.new(
				originalSize.X.Scale * hoverScale,
				originalSize.X.Offset * hoverScale,
				originalSize.Y.Scale * hoverScale,
				originalSize.Y.Offset * hoverScale
			)}
		)
		table.insert(activeTweens[button], hoverTween)
		hoverTween:Play()
	end)

	-- 鼠标离开事件
	button.MouseLeave:Connect(function()
		CleanupTweens(button)
		activeTweens[button] = {}

		-- 恢复大小动画
		local restoreTween = TweenService:Create(button,
			TweenInfo.new(duration, easingStyle, Enum.EasingDirection.Out),
			{Size = originalSize}
		)
		table.insert(activeTweens[button], restoreTween)
		restoreTween:Play()
	end)

	print(string.format("[ButtonEffectHelper] 为按钮 %s 添加了悬停特效", button.Name))
end

--[[
为按钮添加完整特效（点击 + 悬停）
@param button GuiObject - 按钮对象
@param options table - 配置选项，合并点击和悬停选项
]]
function ButtonEffectHelper.AddFullEffect(button, options)
	options = options or {}

	-- 添加悬停特效
	ButtonEffectHelper.AddHoverEffect(button, {
		HoverScale = options.HoverScale,
		Duration = options.HoverDuration or options.Duration,
		EasingStyle = options.HoverEasingStyle or options.EasingStyle,
	})

	-- 添加点击特效
	ButtonEffectHelper.AddClickEffect(button, {
		ScaleDown = options.ScaleDown,
		Duration = options.ClickDuration or options.Duration,
		EasingStyle = options.ClickEasingStyle or options.EasingStyle,
		OnClick = options.OnClick,
	})
end

--[[
移除按钮特效
@param button GuiObject - 按钮对象
]]
function ButtonEffectHelper.RemoveEffects(button)
	CleanupTweens(button)
	print(string.format("[ButtonEffectHelper] 移除了按钮 %s 的特效", button.Name))
end

--[[
批量为按钮添加特效
@param buttons table - 按钮对象数组
@param options table - 配置选项
]]
function ButtonEffectHelper.AddEffectsToButtons(buttons, options)
	for i, button in ipairs(buttons) do
		ButtonEffectHelper.AddFullEffect(button, options)
	end
	print(string.format("[ButtonEffectHelper] 为 %d 个按钮添加了特效", #buttons))
end

--[[
为容器内所有按钮添加特效
@param container GuiObject - 容器对象
@param options table - 配置选项
@param filterFunction function - 过滤函数 (可选)
]]
function ButtonEffectHelper.AddEffectsToContainer(container, options, filterFunction)
	local buttons = {}

	for _, child in ipairs(container:GetDescendants()) do
		if (child:IsA("TextButton") or child:IsA("ImageButton")) then
			if not filterFunction or filterFunction(child) then
				table.insert(buttons, child)
			end
		end
	end

	ButtonEffectHelper.AddEffectsToButtons(buttons, options)
end

return ButtonEffectHelper