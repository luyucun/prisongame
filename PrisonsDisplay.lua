--[[
=====================================================
Script Name: PrisonsDisplay
Script Type: LocalScript (Client UI Controller)
Script Location: StarterPlayer/StarterPlayerScripts/Controllers/PrisonsDisplay.lua
Version: V5.0
=====================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))

local ButtonEffectHelper = nil

local mainGui = nil
local targetButton = nil
local BACKPACK_HIDE_KEY = "Prisons"
local BLUR_LOCK_ID = "Prisons"
local BLUR_LOCKS_KEY = "__PopupBlurLocks"

local prisonsGui = nil
local prisonsBg = nil
local prisonsCloseButton = nil
local prisonsScroll = nil
local houseInfo = nil
local houseDes = nil
local houseIcon = nil
local houseName = nil
local houseIdleSpeed = nil
local houseIdleTime = nil
local houseStatus = nil

local houseEntries = {}
local initialized = false
local boundButtons = {}
local attributeSignalsBound = false
local BindHouseEntry

-- 弹框动画配置（仅Bg）
local POPUP_OPEN_START_SCALE = 0.86
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

local function RequestBackpackHide()
	local trigger = _G.BackpackTrigger
	if trigger and trigger.IsOnIdleFloor and trigger.IsOnIdleFloor() then
		if trigger.PushHideLock then
			trigger.PushHideLock(BACKPACK_HIDE_KEY)
		elseif _G.BackpackDisplay and _G.BackpackDisplay.HideBackpack then
			_G.BackpackDisplay.HideBackpack()
		end
	end
end

local function ReleaseBackpackHide()
	local trigger = _G.BackpackTrigger
	if trigger and trigger.PopHideLock then
		trigger.PopHideLock(BACKPACK_HIDE_KEY)
	elseif trigger and trigger.RefreshVisibility then
		trigger.RefreshVisibility()
	end
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

	warn("[PrisonsDisplay] ButtonEffectHelper load failed:", result)
	return false
end

local function EnsurePopupScale()
	if not prisonsBg then
		return nil
	end

	if not popupScale or popupScale.Parent ~= prisonsBg then
		popupScale = prisonsBg:FindFirstChild("PopupScale")
		if not popupScale then
			popupScale = Instance.new("UIScale")
			popupScale.Name = "PopupScale"
			popupScale.Scale = 1
			popupScale.Parent = prisonsBg
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
	if not prisonsBg then
		return false
	end

	local scale = EnsurePopupScale()
	if not scale then
		prisonsBg.Visible = true
		SetBlurLock(true)
		return true
	end

	if prisonsBg.Visible and not popupAnimating then
		SetBlurLock(true)
		return true
	end

	CancelPopupTweens()
	popupAnimating = true

	prisonsBg.Visible = true
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
	if not prisonsBg then
		return false
	end

	local scale = EnsurePopupScale()
	if not scale then
		prisonsBg.Visible = false
		SetBlurLock(false)
		return true
	end

	if not prisonsBg.Visible and not popupAnimating then
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
		prisonsBg.Visible = false
		scale.Scale = 1
		popupAnimating = false
		SetBlurLock(false)
	end)

	popupCloseTweenA:Play()
	return true
end

local function GetCompletedChapters()
	local completed = player:GetAttribute("CompletedChapters")
	if type(completed) == "number" then
		return completed
	end
	return 0
end

local function GetRebirthCount()
	local rebirthCount = player:GetAttribute("RebirthCount")
	if type(rebirthCount) == "number" then
		return math.max(0, math.floor(rebirthCount))
	end
	return 0
end

local function GetHouseRank(modelName)
	if type(modelName) ~= "string" or modelName == "" then
		return 0
	end
	if HouseConfig.GetHouseRank then
		return math.max(0, tonumber(HouseConfig.GetHouseRank(modelName)) or 0)
	end
	return 0
end

local function GetCurrentHouseModel()
	local modelName = player:GetAttribute("CurrentHouseModel")
	if type(modelName) == "string" and modelName ~= "" then
		return modelName
	end

	local house = nil
	if HouseConfig.GetHouseByRebirthCount then
		house = HouseConfig.GetHouseByRebirthCount(GetRebirthCount())
	else
		local completedChapters = GetCompletedChapters()
		house = HouseConfig.GetHouseByChapter(completedChapters)
	end

	return house and house.ModelName or nil
end

local function GetEffectiveUnlockedHouseRank(rebirthCount, currentModel)
	local bestRank = 0
	if HouseConfig.GetHouseByRebirthCount then
		local rebirthHouse = HouseConfig.GetHouseByRebirthCount(rebirthCount)
		if rebirthHouse and rebirthHouse.ModelName then
			bestRank = GetHouseRank(rebirthHouse.ModelName)
		end
	else
		local chapterHouse = HouseConfig.GetHouseByChapter(GetCompletedChapters())
		if chapterHouse and chapterHouse.ModelName then
			bestRank = GetHouseRank(chapterHouse.ModelName)
		end
	end

	local currentRank = GetHouseRank(currentModel)
	if currentRank > bestRank then
		bestRank = currentRank
	end

	return bestRank
end

local function GetHouseStatus(house, rebirthCount, currentModel)
	if not house then
		return "LOCKED", Color3.fromRGB(255, 0, 0)
	end

	if currentModel and house.ModelName == currentModel then
		return "ACTIVE", Color3.fromRGB(0, 255, 0)
	end

	local houseRank = GetHouseRank(house.ModelName)
	local unlockedRank = GetEffectiveUnlockedHouseRank(rebirthCount, currentModel)
	if houseRank > 0 and unlockedRank >= houseRank then
		return "UNLOCKED", Color3.fromRGB(255, 255, 255)
	end

	local requiredRebirth = tonumber(house.RequiredRebirth)
	if requiredRebirth == nil then
		requiredRebirth = tonumber(house.RequiredChapter) or 0
	end
	if rebirthCount >= requiredRebirth then
		return "UNLOCKED", Color3.fromRGB(255, 255, 255)
	end

	return "LOCKED", Color3.fromRGB(255, 0, 0)
end

local function ApplyHouseInfo(house)
	if not house then
		return
	end

	if houseDes and houseDes:IsA("TextLabel") then
		houseDes.Text = tostring(house.Description or "")
	end
	if houseIcon and houseIcon:IsA("ImageLabel") then
		houseIcon.Image = tostring(house.Icon or "")
	end
	if houseName and houseName:IsA("TextLabel") then
		houseName.Text = tostring(house.Name or "")
	end
	if houseIdleSpeed and houseIdleSpeed:IsA("TextLabel") then
		local speed = tonumber(house.IdleCoinsPerMinute) or 0
		houseIdleSpeed.Text = string.format("$%d/min", speed)
	end
	if houseIdleTime and houseIdleTime:IsA("TextLabel") then
		local maxHours = tonumber(house.IdleMaxHours) or 0
		houseIdleTime.Text = string.format("%dH", maxHours)
	end
	if houseStatus and houseStatus:IsA("TextLabel") then
		local rebirthCount = GetRebirthCount()
		local currentModel = GetCurrentHouseModel()
		local statusText, statusColor = GetHouseStatus(house, rebirthCount, currentModel)
		houseStatus.Text = statusText
		houseStatus.TextColor3 = statusColor
	end
end

local function SelectHouse(house)
	ApplyHouseInfo(house)
end

local function BuildHouseEntries()
	houseEntries = {}

	if not prisonsScroll then
		return
	end

	for index, house in ipairs(HouseConfig.GetAllHouses()) do
		local entryName = "House" .. index
		local frame = prisonsScroll:FindFirstChild(entryName)
		if frame then
			local button = nil
			if frame:IsA("TextButton") or frame:IsA("ImageButton") then
				button = frame
			else
				button = frame:FindFirstChildWhichIsA("TextButton", true) or frame:FindFirstChildWhichIsA("ImageButton", true)
			end

			table.insert(houseEntries, {
				House = house,
				Frame = frame,
				Button = button,
			})
		end
	end
end

local function RefreshHouseEntries()
	BuildHouseEntries()
	for _, entry in ipairs(houseEntries) do
		BindHouseEntry(entry)
	end
end

local function OpenPrisons()
	if not prisonsBg then
		return
	end

	if not PlayPopupOpen() then
		return
	end
    RequestBackpackHide()
	RefreshHouseEntries()

	local currentModel = GetCurrentHouseModel()
	local rebirthCount = GetRebirthCount()
	local defaultHouse = HouseConfig.GetHouseByModel(currentModel)
		or (HouseConfig.GetHouseByRebirthCount and HouseConfig.GetHouseByRebirthCount(rebirthCount))
		or HouseConfig.GetHouseByChapter(GetCompletedChapters())
	if not defaultHouse and #HouseConfig.GetAllHouses() > 0 then
		defaultHouse = HouseConfig.GetAllHouses()[1]
	end

	SelectHouse(defaultHouse)
end

local function ClosePrisons()
	PlayPopupClose()
    ReleaseBackpackHide()
end

BindHouseEntry = function(entry)
	if not entry then
		return
	end

	local house = entry.House
	local button = entry.Button

	if button and (button:IsA("TextButton") or button:IsA("ImageButton")) then
		if boundButtons[button] then
			return
		end
		if ButtonEffectHelper then
			ButtonEffectHelper.AddClickEffect(button, {
				OnClick = function()
					SelectHouse(house)
				end,
			})
		else
			button.MouseButton1Click:Connect(function()
				SelectHouse(house)
			end)
		end
		boundButtons[button] = true
	elseif entry.Frame and entry.Frame:IsA("GuiObject") then
		if boundButtons[entry.Frame] then
			return
		end
		entry.Frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				SelectHouse(house)
			end
		end)
		boundButtons[entry.Frame] = true
	end
end

local function BindButtons()
	LoadButtonEffectHelper()

	if targetButton and (targetButton:IsA("TextButton") or targetButton:IsA("ImageButton")) then
		if not boundButtons[targetButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(targetButton, { OnClick = OpenPrisons })
			else
				targetButton.MouseButton1Click:Connect(OpenPrisons)
			end
			boundButtons[targetButton] = true
		end
	end

	if prisonsCloseButton and (prisonsCloseButton:IsA("TextButton") or prisonsCloseButton:IsA("ImageButton")) then
		if not boundButtons[prisonsCloseButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(prisonsCloseButton, { OnClick = ClosePrisons })
			else
				prisonsCloseButton.MouseButton1Click:Connect(ClosePrisons)
			end
			boundButtons[prisonsCloseButton] = true
		end
	end

	RefreshHouseEntries()
end

local function InitializeUI()
	mainGui = SafeWaitForChild(playerGui, "MainGui", 5)
	if mainGui then
		targetButton = mainGui:FindFirstChild("Target", true)
	end

	prisonsGui = SafeWaitForChild(playerGui, "Prisons", 5)
	if not prisonsGui then
		return false
	end

	prisonsBg = prisonsGui:FindFirstChild("Bg")
	if not prisonsBg then
		return false
	end

	local title = prisonsBg:FindFirstChild("Title")
	if title then
		prisonsCloseButton = title:FindFirstChild("CloseButton")
	end

	prisonsScroll = prisonsBg:FindFirstChild("ScrollingFrame")
	houseInfo = prisonsBg:FindFirstChild("HouseInfomation")
	if houseInfo then
		local describeBg = houseInfo:FindFirstChild("DescribeBg")
		if describeBg then
			houseDes = describeBg:FindFirstChild("HouseDes")
		end
		houseIcon = houseInfo:FindFirstChild("HouseIcon")
		if houseIcon then
			houseName = houseIcon:FindFirstChild("HouseName")
		end
		houseIdleSpeed = houseInfo:FindFirstChild("HouseIdleSpeed")
		houseIdleTime = houseInfo:FindFirstChild("HouseIdleTime")
		houseStatus = houseInfo:FindFirstChild("HouseStatus")
	end

	BuildHouseEntries()

	local scale = EnsurePopupScale()
	if scale then
		scale.Scale = 1
	end
	prisonsBg.Visible = false
	SetBlurLock(false)
	return true
end

local function TryInitialize()
	if not InitializeUI() then
		return false
	end

	BindButtons()
	return true
end

local function BindAttributeSignals()
	if attributeSignalsBound then
		return
	end
	attributeSignalsBound = true

	local function RefreshVisibleSelection()
		if not (prisonsBg and prisonsBg.Visible) then
			return
		end

		RefreshHouseEntries()
		local currentModel = GetCurrentHouseModel()
		local rebirthCount = GetRebirthCount()
		local selectedHouse = HouseConfig.GetHouseByModel(currentModel)
			or (HouseConfig.GetHouseByRebirthCount and HouseConfig.GetHouseByRebirthCount(rebirthCount))
			or HouseConfig.GetHouseByChapter(GetCompletedChapters())
		SelectHouse(selectedHouse)
	end

	player:GetAttributeChangedSignal("RebirthCount"):Connect(function()
		RefreshVisibleSelection()
	end)

	player:GetAttributeChangedSignal("CurrentHouseModel"):Connect(function()
		RefreshVisibleSelection()
	end)
end

local function Initialize()
	if initialized then
		return
	end

	if TryInitialize() then
		initialized = true
		BindAttributeSignals()
		return
	end

	task.spawn(function()
		local attempts = 0
		local ready = TryInitialize()
		while attempts < 5 and not ready do
			attempts += 1
			task.wait(2)
			ready = TryInitialize()
		end
		if ready then
			BindAttributeSignals()
		end
		initialized = true
	end)

	playerGui.ChildAdded:Connect(function(child)
		if not child or (child.Name ~= "Prisons" and child.Name ~= "MainGui") then
			return
		end
		task.spawn(function()
			task.wait()
			if TryInitialize() then
				BindAttributeSignals()
			end
		end)
	end)
end

Initialize()
