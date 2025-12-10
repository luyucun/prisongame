--[[
脚本名称: LoadingController
脚本类型: LocalScript (客户端)
脚本位置: StarterPlayer/StarterPlayerScripts/LoadingController
版本: V3.2.4

职责:
1. 显示Loading界面
2. 管理客户端资源预加载
3. 接收服务端加载进度
4. 控制Loading界面显示/隐藏

V3.2.4更新:
- 【修复】超时时同时通知服务器ClientPreloadComplete，避免服务端加载状态永远无法结束
- 【修复】监听CharacterAdded，确保角色后生成时也能禁用移动
- 【修复】Loading结束时断开CharacterAdded连接并恢复移动

V3.2.3更新:
- 【修复】立即连接服务端事件，不再放在task.spawn中
- 【优化】减少不必要的等待时间
- 【优化】Loading背景图和事件连接并行执行
]]

-- ============================================================
-- 【最高优先级】立即显示Loading界面 - 必须在最顶部执行！
-- ============================================================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 5)

-- 立即显示Loading（不等待任何其他东西）
if PlayerGui then
	local LoadingGui = PlayerGui:FindFirstChild("Loading")
	if LoadingGui then
		LoadingGui.Enabled = true
		LoadingGui.DisplayOrder = 999
		local Bg = LoadingGui:FindFirstChild("Bg")
		if Bg then
			Bg.Visible = true
		end
	end
end
-- ============================================================

-- 引用服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

-- 配置
local DEBUG_MODE = false
local LOG_PREFIX = "[LoadingController]"

-- Loading背景图片列表
local LOADING_IMAGES = {
	"rbxassetid://98877166419333",
	"rbxassetid://111664305611167",
	"rbxassetid://136231844959584",
}

-- 加载超时时间（秒）
local LOADING_TIMEOUT = 60

-- ==================== UI引用 ====================

local LoadingGui = nil
local LoadingBg = nil
local LoadingImage = nil
local ProgressBg = nil
local Progressbar = nil
local NumberLabel = nil

-- ==================== 状态变量 ====================

local currentProgress = 0           -- 当前服务端进度
local clientPreloadProgress = 0     -- 客户端预加载进度
local totalProgress = 0             -- 总进度
local isLoadingComplete = false     -- 加载是否完成
local clientPreloadComplete = false -- 客户端预加载是否完成

-- RemoteEvent引用
local LoadingEvents = nil

-- 保存原始值（用于恢复）
local originalWalkSpeed = 16
local originalJumpPower = 50

-- V3.2.4新增：CharacterAdded连接，用于在Loading结束时断开
local characterAddedConnection = nil

-- ==================== 私有函数 ====================

local function DebugLog(...)
	if DEBUG_MODE then
		print(LOG_PREFIX, ...)
	end
end

--[[
禁用玩家操作（针对单个角色）
V3.2.4新增：独立函数，可被CharacterAdded调用
@param character Model - 角色模型
]]
local function DisableCharacterMovement(character)
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- 保存原始值（仅首次保存）
		if originalWalkSpeed == 16 and humanoid.WalkSpeed > 0 then
			originalWalkSpeed = humanoid.WalkSpeed
		end
		if originalJumpPower == 50 and humanoid.JumpPower > 0 then
			originalJumpPower = humanoid.JumpPower
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		DebugLog("角色移动已禁用:", character.Name)
	end
end

--[[
禁用玩家操作
V3.2.4修复：监听CharacterAdded，确保角色后生成时也能禁用移动
]]
local function DisablePlayerControls()
	-- 1. 禁用当前角色移动（如果存在）
	local character = LocalPlayer.Character
	if character then
		DisableCharacterMovement(character)
	end

	-- 2. V3.2.4新增：监听CharacterAdded，处理角色后生成的情况
	-- 断开之前的连接（如果存在）
	if characterAddedConnection then
		characterAddedConnection:Disconnect()
	end
	characterAddedConnection = LocalPlayer.CharacterAdded:Connect(function(newCharacter)
		-- 只有在Loading未完成时才禁用移动
		if not isLoadingComplete then
			-- 等待Humanoid加载
			local humanoid = newCharacter:WaitForChild("Humanoid", 5)
			if humanoid then
				DisableCharacterMovement(newCharacter)
			end
		end
	end)

	-- 3. 禁用部分Roblox默认UI（避免PlayerList警告）
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
	end)

	-- 4. 禁用鼠标锁定
	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end)

	DebugLog("玩家操作已禁用")
end

--[[
恢复玩家操作
V3.2.4修复：断开CharacterAdded连接
]]
local function EnablePlayerControls()
	-- 0. V3.2.4新增：断开CharacterAdded连接，不再需要监听
	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end

	-- 1. 恢复角色移动
	local character = LocalPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = originalWalkSpeed
			humanoid.JumpPower = originalJumpPower
		end
	end

	-- 2. 恢复Roblox默认UI
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, true)
	end)

	DebugLog("玩家操作已恢复")
end

--[[
更新进度条显示
@param progress number - 进度值 (0-100)
]]
local function UpdateProgressDisplay(progress)
	progress = math.clamp(progress, 0, 100)
	totalProgress = progress

	-- 更新进度条
	if Progressbar then
		local targetSize = UDim2.new(progress / 100, 0, 1, 0)
		local tween = TweenService:Create(Progressbar, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = targetSize
		})
		tween:Play()
	end

	-- 更新数字显示
	if NumberLabel then
		NumberLabel.Text = string.format("%d%%", math.floor(progress))
	end
end

--[[
计算并更新总进度
服务端进度占60%，客户端预加载占40%
]]
local function CalculateTotalProgress()
	local serverWeight = 0.6
	local clientWeight = 0.4
	local calculatedProgress = (currentProgress * serverWeight) + (clientPreloadProgress * clientWeight)
	UpdateProgressDisplay(calculatedProgress)
end

--[[
初始化Loading UI引用
@return boolean - 是否成功
]]
local function InitializeUI()
	LoadingGui = PlayerGui:FindFirstChild("Loading")
	if not LoadingGui then
		LoadingGui = PlayerGui:WaitForChild("Loading", 3)
	end
	if not LoadingGui then
		warn(LOG_PREFIX, "找不到Loading ScreenGui!")
		return false
	end

	LoadingGui.Enabled = true
	LoadingGui.DisplayOrder = 999

	LoadingBg = LoadingGui:FindFirstChild("Bg")
	if not LoadingBg then
		LoadingBg = LoadingGui:WaitForChild("Bg", 2)
	end
	if not LoadingBg then
		warn(LOG_PREFIX, "找不到Loading/Bg!")
		return false
	end

	LoadingBg.Visible = true

	-- 【关键】确保Bg可以拦截所有点击/触摸输入
	LoadingBg.Active = true

	LoadingImage = LoadingBg:FindFirstChild("LoadingImage")
	ProgressBg = LoadingBg:FindFirstChild("ProgressBg")

	if ProgressBg then
		Progressbar = ProgressBg:FindFirstChild("Progressbar")
		NumberLabel = ProgressBg:FindFirstChild("Number")
	end

	-- 初始化进度显示
	if Progressbar then
		Progressbar.Size = UDim2.new(0, 0, 1, 0)
	end
	if NumberLabel then
		NumberLabel.Text = "0%"
	end

	-- 【关键】禁用玩家操作
	DisablePlayerControls()

	DebugLog("UI初始化完成")
	return true
end

--[[
预加载并设置Loading背景图
]]
local function PreloadAndSetLoadingImage()
	if not LoadingImage then return end

	local randomIndex = math.random(1, #LOADING_IMAGES)
	local selectedImage = LOADING_IMAGES[randomIndex]

	-- 预加载背景图
	pcall(function()
		ContentProvider:PreloadAsync({selectedImage})
	end)

	LoadingImage.Image = selectedImage
	DebugLog("设置背景图片:", selectedImage)
end

--[[
隐藏Loading界面
]]
local function HideLoadingScreen()
	if not LoadingBg then return end

	UpdateProgressDisplay(100)
	task.wait(0.2)

	-- 淡出效果
	local fadeOut = TweenService:Create(LoadingBg, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})

	for _, child in ipairs(LoadingBg:GetDescendants()) do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then
			TweenService:Create(child, TweenInfo.new(0.4), {ImageTransparency = 1}):Play()
		elseif child:IsA("TextLabel") or child:IsA("TextButton") then
			TweenService:Create(child, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
		elseif child:IsA("Frame") then
			TweenService:Create(child, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
		end
	end

	fadeOut:Play()
	fadeOut.Completed:Wait()

	LoadingBg.Visible = false
	LoadingBg.Active = false

	-- 重置透明度
	LoadingBg.BackgroundTransparency = 0
	for _, child in ipairs(LoadingBg:GetDescendants()) do
		if child:IsA("ImageLabel") or child:IsA("ImageButton") then
			child.ImageTransparency = 0
		elseif child:IsA("TextLabel") or child:IsA("TextButton") then
			child.TextTransparency = 0
		elseif child:IsA("Frame") then
			child.BackgroundTransparency = 0
		end
	end

	-- 【关键】恢复玩家操作
	EnablePlayerControls()

	DebugLog("隐藏Loading界面")
end

--[[
执行客户端资源预加载
]]
local function PerformClientPreload()
	DebugLog("开始客户端资源预加载...")

	local totalAssets = 0
	local loadedAssets = 0
	local assetsToPreload = {}

	-- 收集资源
	local Config = ReplicatedStorage:FindFirstChild("Config")
	if not Config then
		Config = ReplicatedStorage:WaitForChild("Config", 5)
	end

	if Config then
		-- 收集动画和图标
		local UnitConfigModule = Config:FindFirstChild("UnitConfig")
		if UnitConfigModule then
			local success, UnitConfig = pcall(require, UnitConfigModule)
			if success and UnitConfig and UnitConfig.Units then
				for unitId, unitData in pairs(UnitConfig.Units) do
					local animIds = {
						unitData.ShowAnimationId,
						unitData.IdleAnimationId,
						unitData.MoveAnimationId,
						unitData.AttackAnimationId,
						unitData.DeathAnimationId,
					}

					for _, animId in ipairs(animIds) do
						if animId and animId ~= "" and animId ~= "0" then
							local animation = Instance.new("Animation")
							animation.AnimationId = "rbxassetid://" .. tostring(animId)
							table.insert(assetsToPreload, animation)
							totalAssets = totalAssets + 1
						end
					end

					if unitData.Icon and unitData.Icon ~= "" then
						local iconId = tostring(unitData.Icon)
						if not string.match(iconId, "rbxassetid://") then
							iconId = "rbxassetid://" .. iconId
						end
						table.insert(assetsToPreload, iconId)
						totalAssets = totalAssets + 1
					end
				end
			end
		end

		-- 收集技能图标
		local SkillConfigModule = Config:FindFirstChild("SkillConfig")
		if SkillConfigModule then
			local success, SkillConfig = pcall(require, SkillConfigModule)
			if success and SkillConfig and SkillConfig.Skills then
				for skillId, skillData in pairs(SkillConfig.Skills) do
					if skillData.Icon and skillData.Icon ~= "" then
						table.insert(assetsToPreload, skillData.Icon)
						totalAssets = totalAssets + 1
					end
				end
			end
		end
	end

	-- 预加载Victory UI相关资源
	local victoryGui = PlayerGui:FindFirstChild("Victory")
	if victoryGui then
		local informationFrame = victoryGui:FindFirstChild("Information")
		if informationFrame then
			-- 预加载棒球棍图片
			for _, child in ipairs(informationFrame:GetChildren()) do
				if child:IsA("ImageLabel") and child.Image and child.Image ~= "" then
					table.insert(assetsToPreload, child.Image)
					totalAssets = totalAssets + 1
					DebugLog("收集Victory UI图片:", child.Name, child.Image)
				end
			end

			-- 预加载Confirm按钮图片（如果有）
			local confirmButton = informationFrame:FindFirstChild("Confirm")
			if confirmButton and confirmButton:IsA("ImageButton") and confirmButton.Image and confirmButton.Image ~= "" then
				table.insert(assetsToPreload, confirmButton.Image)
				totalAssets = totalAssets + 1
				DebugLog("收集Confirm按钮图片:", confirmButton.Image)
			end
		end

		-- 预加载Effect Frame的资源（如果有）
		local effectFrame = victoryGui:FindFirstChild("Effect")
		if effectFrame then
			for _, child in ipairs(effectFrame:GetDescendants()) do
				if child:IsA("ImageLabel") and child.Image and child.Image ~= "" then
					table.insert(assetsToPreload, child.Image)
					totalAssets = totalAssets + 1
				elseif child:IsA("ImageButton") and child.Image and child.Image ~= "" then
					table.insert(assetsToPreload, child.Image)
					totalAssets = totalAssets + 1
				end
			end
		end
	end

	DebugLog("收集到", totalAssets, "个资源需要预加载")

	if totalAssets == 0 then
		clientPreloadProgress = 100
		clientPreloadComplete = true
		CalculateTotalProgress()
		return
	end

	-- 分批预加载
	local BATCH_SIZE = 15
	local totalBatches = math.ceil(#assetsToPreload / BATCH_SIZE)

	for batchIndex = 1, totalBatches do
		local startIdx = (batchIndex - 1) * BATCH_SIZE + 1
		local endIdx = math.min(batchIndex * BATCH_SIZE, #assetsToPreload)
		local batch = {}

		for i = startIdx, endIdx do
			table.insert(batch, assetsToPreload[i])
		end

		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)

		loadedAssets = loadedAssets + #batch
		clientPreloadProgress = (loadedAssets / totalAssets) * 100
		CalculateTotalProgress()

		if batchIndex < totalBatches then
			task.wait(0.03)
		end
	end

	-- 清理
	for _, asset in ipairs(assetsToPreload) do
		if typeof(asset) == "Instance" and asset:IsA("Animation") then
			asset:Destroy()
		end
	end

	clientPreloadProgress = 100
	clientPreloadComplete = true
	CalculateTotalProgress()

	DebugLog("客户端预加载完成")
end

--[[
通知服务端客户端预加载完成
]]
local function NotifyServerPreloadComplete()
	if not LoadingEvents then return end

	local completeEvent = LoadingEvents:FindFirstChild("ClientPreloadComplete")
	if completeEvent then
		completeEvent:FireServer()
		DebugLog("通知服务端客户端预加载完成")
	end
end

--[[
处理服务端进度更新
]]
local function OnServerProgressUpdate(progress, stageName)
	currentProgress = progress or 0
	CalculateTotalProgress()
	DebugLog("服务端进度:", progress, stageName)
end

--[[
处理服务端加载完成通知
]]
local function OnServerLoadingComplete()
	isLoadingComplete = true
	currentProgress = 100
	CalculateTotalProgress()

	DebugLog("服务端加载完成")

	task.spawn(function()
		HideLoadingScreen()
	end)
end

--[[
连接服务端事件（立即执行，不放在task.spawn中）
]]
local function ConnectServerEvents()
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if not Events then
		Events = ReplicatedStorage:WaitForChild("Events", 10)
	end
	if not Events then
		warn(LOG_PREFIX, "找不到Events文件夹")
		return false
	end

	LoadingEvents = Events:FindFirstChild("LoadingEvents")
	if not LoadingEvents then
		LoadingEvents = Events:WaitForChild("LoadingEvents", 10)
	end
	if not LoadingEvents then
		warn(LOG_PREFIX, "找不到LoadingEvents")
		return false
	end

	-- 连接事件
	local progressEvent = LoadingEvents:FindFirstChild("LoadingProgress")
	if progressEvent then
		progressEvent.OnClientEvent:Connect(OnServerProgressUpdate)
	end

	local stageEvent = LoadingEvents:FindFirstChild("LoadingStageUpdate")
	if stageEvent then
		stageEvent.OnClientEvent:Connect(function(stage)
			DebugLog("服务端阶段:", stage)
		end)
	end

	local completeEvent = LoadingEvents:FindFirstChild("LoadingComplete")
	if completeEvent then
		completeEvent.OnClientEvent:Connect(OnServerLoadingComplete)
	end

	DebugLog("服务端事件连接完成")
	return true
end

--[[
超时处理
V3.2.4修复：超时时同时通知服务器，避免服务端加载状态永远无法结束
]]
local function StartTimeoutWatchdog()
	task.spawn(function()
		local startTime = tick()
		while not isLoadingComplete do
			task.wait(1)
			if tick() - startTime > LOADING_TIMEOUT then
				warn(LOG_PREFIX, "加载超时，强制完成")

				-- V3.2.4修复：超时时也需要标记客户端预加载完成并通知服务器
				if not clientPreloadComplete then
					clientPreloadComplete = true
					clientPreloadProgress = 100
					-- 通知服务器客户端预加载完成（即使是超时完成）
					NotifyServerPreloadComplete()
				end

				isLoadingComplete = true
				HideLoadingScreen()
				break
			end
		end
	end)
end

-- ==================== 主初始化流程 ====================

local function Initialize()
	DebugLog("初始化LoadingController...")

	-- 1. 初始化UI
	if not InitializeUI() then
		warn(LOG_PREFIX, "UI初始化失败")
		return
	end

	-- 2. 【关键】立即连接服务端事件（不放在task.spawn中！）
	ConnectServerEvents()

	-- 3. 启动超时监控
	StartTimeoutWatchdog()

	-- 4. 并行执行：预加载背景图 + 预加载其他资源
	task.spawn(function()
		-- 先预加载背景图（优先级最高）
		PreloadAndSetLoadingImage()

		-- 然后预加载其他资源
		PerformClientPreload()

		-- 通知服务端
		NotifyServerPreloadComplete()
	end)

	DebugLog("LoadingController初始化完成")
end

-- ==================== 公共接口 ====================

local LoadingController = {}

function LoadingController.IsLoadingComplete()
	return isLoadingComplete
end

function LoadingController.GetProgress()
	return totalProgress
end

function LoadingController.ForceHide()
	isLoadingComplete = true
	HideLoadingScreen()
end

_G.LoadingController = LoadingController

-- ==================== 启动 ====================

Initialize()
