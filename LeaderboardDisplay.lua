--[[
=====================================================
Script Name: LeaderboardDisplay.lua
Script Type: LocalScript (Client UI)
Script Location: StarterPlayer/StarterPlayerScripts/UI/LeaderboardDisplay
Version: V4.7
=====================================================
--]]

local LeaderboardDisplay = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local leaderboardEvents = nil
local requestLeaderboardEvent = nil
local leaderboardDataEvent = nil

local topRightGui = nil
local leaderboardGui = nil
local leaderboardBg = nil
local openButton = nil
local closeButton = nil
local scrollingFrame = nil
local rank01 = nil
local rank02 = nil
local rank03 = nil
local rankTemplate = nil
local playerFrame = nil
local playerAvatar = nil
local playerName = nil
local playerPower = nil
local playerRank = nil
local countDownLabel = nil

local cachedEntries = {}
local nextRefreshTime = 0
local serverTimeOffset = 0
local countdownConnection = nil
local countdownAccumulator = 0
local templateClones = {}
local avatarCache = {}
local BLUR_LOCK_ID = "Leaderboard"
local BLUR_LOCKS_KEY = "__PopupBlurLocks"

local ButtonEffectHelper = nil
local buttonsBound = false
local dataBound = false
local powerBound = false

-- 弹框动画配置（仅Bg）
local POPUP_OPEN_START_SCALE = 0.86
local POPUP_OPEN_OVERSHOOT_SCALE = 1.10
local POPUP_OPEN_DURATION_A = 0.18
local POPUP_OPEN_DURATION_B = 0.10
local POPUP_CLOSE_OVERSHOOT_SCALE = 1.12
local POPUP_CLOSE_END_SCALE = 0.78
local POPUP_CLOSE_DURATION_A = 0.08
local POPUP_CLOSE_DURATION_B = 0.12

local popupScale = nil
local popupOpenTweenA = nil
local popupOpenTweenB = nil
local popupCloseTweenA = nil
local popupCloseTweenB = nil
local popupAnimating = false

local function SafeWaitForChild(parent, childName, timeout)
	timeout = timeout or 3
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(childName)
	if child then
		return child
	end

	local startTime = tick()
	while tick() - startTime < timeout do
		child = parent:FindFirstChild(childName)
		if child then
			return child
		end
		task.wait(0.1)
	end

	return nil
end

local function LoadButtonEffectHelper()
	if ButtonEffectHelper then
		return true
	end

	local success, result = pcall(function()
		return require(game:GetService("StarterPlayer").StarterPlayerScripts.Utils.ButtonEffectHelper)
	end)

	if success then
		ButtonEffectHelper = result
		return true
	end

	warn("[LeaderboardDisplay] ButtonEffectHelper load failed:", result)
	return false
end

local function SetBlurLock(enabled)
	local locks = _G[BLUR_LOCKS_KEY]
	if type(locks) ~= "table" then
		locks = {}
		_G[BLUR_LOCKS_KEY] = locks
	end

	if enabled then
		locks[BLUR_LOCK_ID] = true
	else
		locks[BLUR_LOCK_ID] = nil
	end

	local blur = Lighting:FindFirstChild("Blur")
	if blur and blur:IsA("BlurEffect") then
		blur.Enabled = next(locks) ~= nil
	end
end

local function EnsurePopupScale()
	if not leaderboardBg then
		return nil
	end

	if not popupScale or popupScale.Parent ~= leaderboardBg then
		popupScale = leaderboardBg:FindFirstChild("PopupScale")
		if not popupScale then
			popupScale = Instance.new("UIScale")
			popupScale.Name = "PopupScale"
			popupScale.Scale = 1
			popupScale.Parent = leaderboardBg
		end
	end

	return popupScale
end

local function CancelPopupTweens()
	local tweens = {popupOpenTweenA, popupOpenTweenB, popupCloseTweenA, popupCloseTweenB}
	for _, tween in ipairs(tweens) do
		if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
			tween:Cancel()
		end
	end
end

local function PlayPopupOpen()
	if not leaderboardBg then
		return false
	end

	local scale = EnsurePopupScale()
	if not scale then
		leaderboardBg.Visible = true
		SetBlurLock(true)
		return true
	end

	if leaderboardBg.Visible and not popupAnimating then
		SetBlurLock(true)
		return true
	end

	CancelPopupTweens()
	popupAnimating = true

	leaderboardBg.Visible = true
	scale.Scale = POPUP_OPEN_START_SCALE

	popupOpenTweenA = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_OPEN_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = POPUP_OPEN_OVERSHOOT_SCALE}
	)
	popupOpenTweenB = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = 1}
	)

	local connA
	connA = popupOpenTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			popupOpenTweenB:Play()
		end
	end)

	local connB
	connB = popupOpenTweenB.Completed:Connect(function()
		connB:Disconnect()
		popupAnimating = false
		scale.Scale = 1
		SetBlurLock(true)
	end)

	popupOpenTweenA:Play()
	return true
end

local function PlayPopupClose()
	if not leaderboardBg then
		return false
	end

	local scale = EnsurePopupScale()
	if not scale then
		leaderboardBg.Visible = false
		SetBlurLock(false)
		return true
	end

	if not leaderboardBg.Visible and not popupAnimating then
		SetBlurLock(false)
		return true
	end

	CancelPopupTweens()
	popupAnimating = true

	popupCloseTweenA = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = POPUP_CLOSE_OVERSHOOT_SCALE}
	)
	popupCloseTweenB = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Scale = POPUP_CLOSE_END_SCALE}
	)

	local connA
	connA = popupCloseTweenA.Completed:Connect(function(state)
		connA:Disconnect()
		if state == Enum.PlaybackState.Completed then
			popupCloseTweenB:Play()
		end
	end)

	local connB
	connB = popupCloseTweenB.Completed:Connect(function()
		connB:Disconnect()
		leaderboardBg.Visible = false
		scale.Scale = 1
		popupAnimating = false
		SetBlurLock(false)
	end)

	popupCloseTweenA:Play()
	return true
end

local function InitializeEvents()
	if leaderboardEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[LeaderboardDisplay] Events folder not found")
		return false
	end

	leaderboardEvents = eventsFolder:WaitForChild("LeaderboardEvents", 10)
	if not leaderboardEvents then
		warn("[LeaderboardDisplay] LeaderboardEvents not found")
		return false
	end

	requestLeaderboardEvent = leaderboardEvents:WaitForChild("RequestLeaderboard", 5)
	leaderboardDataEvent = leaderboardEvents:WaitForChild("LeaderboardData", 5)

	if not (requestLeaderboardEvent and leaderboardDataEvent) then
		warn("[LeaderboardDisplay] Leaderboard events missing")
		return false
	end

	return true
end

local function InitializeUI()
	if leaderboardBg then
		return true
	end

	topRightGui = SafeWaitForChild(playerGui, "TopRightGui", 5)
	if topRightGui then
		local topRightBg = topRightGui:FindFirstChild("Bg")
		local leaderboardContainer = topRightBg and topRightBg:FindFirstChild("Learderboard")
		openButton = leaderboardContainer and leaderboardContainer:FindFirstChild("Button")
	end

	leaderboardGui = SafeWaitForChild(playerGui, "Leaderboard", 5)
	if not leaderboardGui then
		warn("[LeaderboardDisplay] Leaderboard GUI not found")
		return false
	end

	leaderboardBg = leaderboardGui:FindFirstChild("Bg")
	if not leaderboardBg then
		warn("[LeaderboardDisplay] Leaderboard Bg not found")
		return false
	end

	local title = leaderboardBg:FindFirstChild("Title")
	if title then
		closeButton = title:FindFirstChild("CloseButton")
	end

	scrollingFrame = leaderboardBg:FindFirstChild("ScrollingFrame")
	if scrollingFrame then
		rank01 = scrollingFrame:FindFirstChild("Rank01")
		rank02 = scrollingFrame:FindFirstChild("Rank02")
		rank03 = scrollingFrame:FindFirstChild("Rank03")
		rankTemplate = scrollingFrame:FindFirstChild("RankTemplate")
	end

	playerFrame = leaderboardBg:FindFirstChild("Player")
	if playerFrame then
		playerAvatar = playerFrame:FindFirstChild("Avatar")
		playerName = playerFrame:FindFirstChild("Name")
		playerPower = playerFrame:FindFirstChild("Power")
		playerRank = playerFrame:FindFirstChild("Rank")
	end

	countDownLabel = leaderboardBg:FindFirstChild("CountDownTime")
	leaderboardBg.Visible = false
	SetBlurLock(false)
	return true
end

local function GetLocalPower()
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return 0
	end

	local powerValue = leaderstats:FindFirstChild("Power")
	if powerValue and powerValue:IsA("ValueBase") then
		return math.floor(tonumber(powerValue.Value) or 0)
	end

	return 0
end

local function SetAvatarImage(imageLabel, userId)
	if not imageLabel or not userId then
		return
	end

	if avatarCache[userId] then
		imageLabel.Image = avatarCache[userId]
		return
	end

	task.spawn(function()
		local success, result = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if success and result and imageLabel then
			avatarCache[userId] = result
			imageLabel.Image = result
		end
	end)
end

local function ApplyEntry(frame, entry, rank)
	if not frame then
		return
	end

	if not entry then
		frame.Visible = false
		return
	end

	frame.Visible = true
	local avatar = frame:FindFirstChild("Avatar")
	local nameLabel = frame:FindFirstChild("Name")
	local powerLabel = frame:FindFirstChild("Power")
	local rankLabel = frame:FindFirstChild("Rank")

	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = tostring(entry.Name or "Unknown")
	end
	if powerLabel and powerLabel:IsA("TextLabel") then
		powerLabel.Text = tostring(math.floor(tonumber(entry.Power) or 0))
	end
	if rankLabel and rankLabel:IsA("TextLabel") then
		rankLabel.Text = tostring(rank or "")
	end

	SetAvatarImage(avatar, entry.UserId)
end

local function ClearTemplateClones()
	for _, clone in ipairs(templateClones) do
		if clone and clone.Parent then
			clone:Destroy()
		end
	end
	templateClones = {}
end

local function UpdatePlayerPanel(entries)
	if not playerFrame then
		return
	end

	local rankText = "20+"
	for _, entry in ipairs(entries or {}) do
		if entry.UserId == player.UserId then
			rankText = tostring(entry.Rank or "20+")
			break
		end
	end

	if playerAvatar and playerAvatar:IsA("ImageLabel") then
		SetAvatarImage(playerAvatar, player.UserId)
	end
	if playerName and playerName:IsA("TextLabel") then
		playerName.Text = player.Name
	end
	if playerPower and playerPower:IsA("TextLabel") then
		playerPower.Text = tostring(GetLocalPower())
	end
	if playerRank and playerRank:IsA("TextLabel") then
		playerRank.Text = rankText
	end
end

local function UpdateLeaderboardUI(entries)
	if not scrollingFrame then
		return
	end

	local list = entries or {}
	ApplyEntry(rank01, list[1], 1)
	ApplyEntry(rank02, list[2], 2)
	ApplyEntry(rank03, list[3], 3)

	ClearTemplateClones()

	if rankTemplate then
		for index = 4, math.min(#list, 20) do
			local entry = list[index]
			local clone = rankTemplate:Clone()
			clone.Name = "Rank" .. tostring(index)
			clone.Visible = true
			clone.LayoutOrder = index
			clone.Parent = scrollingFrame
			ApplyEntry(clone, entry, index)
			table.insert(templateClones, clone)
		end
	end

	UpdatePlayerPanel(list)
end

local function UpdateCountdownLabel()
	if not countDownLabel or not countDownLabel:IsA("TextLabel") then
		return
	end

	local now = os.time() + serverTimeOffset
	local remaining = math.max(0, (tonumber(nextRefreshTime) or 0) - now)
	local minutes = math.floor(remaining / 60)
	local seconds = math.floor(remaining % 60)
	countDownLabel.Text = string.format("Refreshes in: %02d:%02d", minutes, seconds)
end

local function StartCountdown()
	if countdownConnection then
		return
	end

	countdownAccumulator = 0
	UpdateCountdownLabel()
	countdownConnection = RunService.Heartbeat:Connect(function(dt)
		countdownAccumulator = countdownAccumulator + dt
		if countdownAccumulator >= 1 then
			countdownAccumulator = 0
			UpdateCountdownLabel()
		end
	end)
end

local function StopCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
end

local function OpenLeaderboard()
	if not leaderboardBg then
		return
	end

	if not PlayPopupOpen() then
		return
	end
	if requestLeaderboardEvent then
		requestLeaderboardEvent:FireServer()
	end
	StartCountdown()
	UpdateLeaderboardUI(cachedEntries)
end

local function CloseLeaderboard()
	PlayPopupClose()
	StopCountdown()
end

local function BindButtons()
	if buttonsBound then
		return
	end

	LoadButtonEffectHelper()

	if openButton and (openButton:IsA("TextButton") or openButton:IsA("ImageButton")) then
		if ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(openButton, { OnClick = OpenLeaderboard })
		else
			openButton.MouseButton1Click:Connect(OpenLeaderboard)
		end
	end

	if closeButton and (closeButton:IsA("TextButton") or closeButton:IsA("ImageButton")) then
		if ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(closeButton, { OnClick = CloseLeaderboard })
		else
			closeButton.MouseButton1Click:Connect(CloseLeaderboard)
		end
	end

	if openButton or closeButton then
		buttonsBound = true
	end
end

local function BindPowerListener()
	if powerBound then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local powerValue = leaderstats:FindFirstChild("Power")
	if powerValue and powerValue:IsA("ValueBase") then
		powerValue.Changed:Connect(function()
			if leaderboardBg and leaderboardBg.Visible then
				UpdatePlayerPanel(cachedEntries)
			end
		end)
		powerBound = true
	end
end

local function OnLeaderboardData(entries, nextTime, serverTime)
	if type(entries) == "table" then
		cachedEntries = entries
	else
		cachedEntries = {}
	end

	nextRefreshTime = tonumber(nextTime) or 0
	if type(serverTime) == "number" then
		serverTimeOffset = serverTime - os.time()
	end

	if leaderboardBg and leaderboardBg.Visible then
		UpdateLeaderboardUI(cachedEntries)
		UpdateCountdownLabel()
	end
end

local function BindLeaderboardData()
	if dataBound or not leaderboardDataEvent then
		return
	end

	leaderboardDataEvent.OnClientEvent:Connect(OnLeaderboardData)
	dataBound = true
end

local function TryInitialize()
	local eventsReady = InitializeEvents()
	local uiReady = InitializeUI()

	if eventsReady then
		BindLeaderboardData()
	end
	if uiReady then
		BindButtons()
		BindPowerListener()
	end

	return eventsReady and uiReady
end

function LeaderboardDisplay.Initialize()
	if TryInitialize() then
		return
	end

	task.spawn(function()
		local attempts = 0
		while attempts < 5 and not TryInitialize() do
			attempts += 1
			task.wait(2)
		end
	end)

	player.ChildAdded:Connect(function(child)
		if child and child.Name == "leaderstats" then
			BindPowerListener()
		end
	end)
end

LeaderboardDisplay.Initialize()

return LeaderboardDisplay
