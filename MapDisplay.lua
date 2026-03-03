--[[
脚本名称: MapDisplay
脚本类型: LocalScript (客户端)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/MapDisplay.lua
版本: V7.1
职责: 地图选择界面展示、章节选择、Attack开战
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local MapDisplay = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ButtonEffectHelper = nil

local BLUR_LOCKS_KEY = "__PopupBlurLocks"
local BLUR_LOCK_ID = "MapDisplay"
local BACKPACK_HIDE_KEY = "MapDisplay"

local POPUP_OPEN_START_SCALE = 0.86
local POPUP_OPEN_OVERSHOOT_SCALE = 1.10
local POPUP_OPEN_DURATION_A = 0.18
local POPUP_OPEN_DURATION_B = 0.10
local POPUP_CLOSE_OVERSHOOT_SCALE = 1.12
local POPUP_CLOSE_END_SCALE = 0.78
local POPUP_CLOSE_DURATION_A = 0.08
local POPUP_CLOSE_DURATION_B = 0.12

local mainGui = nil
local battleControl = nil
local playButton = nil

local mapGui = nil
local mapBg = nil
local dimBg = nil
local closeButton = nil
local attackButton = nil
local scrollingFrame = nil
local mapTemplate = nil
local mainMedalNumLabel = nil
local mapMedalNumLabel = nil
local mapScale = nil
local mapTemplateBaseSize = nil
local mapTemplateBaseAutomaticSize = nil
local mainGuiVisibilitySnapshot = {}
local mainGuiHiddenByMap = false

local campaignEvents = nil
local requestMapDataEvent = nil
local mapDataEvent = nil
local requestStartCampaignEvent = nil
local campaignStateUpdateEvent = nil

local popupAnimating = false
local popupOpenTweenA = nil
local popupOpenTweenB = nil
local popupCloseTweenA = nil
local popupCloseTweenB = nil
local popupAnimationMode = nil
local closeCompletionCallbacks = {}

local latestPayload = nil
local chapterCardData = {}
local selectedChapterId = nil
local autoAttackPending = false
local pendingAttackChapterId = nil
local initialized = false
local Initialize = nil
local CloseMapAndStartPendingAttack = nil
local HideBackpackForBattle = nil
local medalAttrConnection = nil
local mainGuiChildAddedConnection = nil

local function RequestBackpackHide()
	local trigger = _G.BackpackTrigger
	if trigger and trigger.PushHideLock then
		trigger.PushHideLock(BACKPACK_HIDE_KEY)
	elseif HideBackpackForBattle then
		HideBackpackForBattle()
	end
end

local function ReleaseBackpackHide()
	local trigger = _G.BackpackTrigger
	if trigger and trigger.PopHideLock then
		trigger.PopHideLock(BACKPACK_HIDE_KEY)
	elseif trigger and trigger.RefreshVisibility then
		trigger.RefreshVisibility()
	elseif _G.BackpackDisplay and _G.BackpackDisplay.ShowBackpack then
		_G.BackpackDisplay.ShowBackpack()
	else
		local backpackGui = playerGui:FindFirstChild("BackpackGui")
		if backpackGui then
			backpackGui.Enabled = true
		end
	end
end

local function SafeWaitForChild(parent, childName, timeout)
	timeout = timeout or 5
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(childName)
	if child then
		return child
	end

	local ok, result = pcall(function()
		return parent:WaitForChild(childName, timeout)
	end)
	if ok then
		return result
	end

	return nil
end

local function ResolveMainGui()
	if mainGui and mainGui.Parent then
		return mainGui
	end
	mainGui = playerGui:FindFirstChild("MainGui")
	return mainGui
end

local function HideMainGuiForMap()
	local currentMainGui = ResolveMainGui()
	if not currentMainGui or mainGuiHiddenByMap then
		return
	end

	table.clear(mainGuiVisibilitySnapshot)
	for _, child in ipairs(currentMainGui:GetChildren()) do
		if child:IsA("GuiObject") then
			mainGuiVisibilitySnapshot[child] = child.Visible
			child.Visible = false
		end
	end

	mainGuiHiddenByMap = true
end

local function RestoreMainGuiAfterMap()
	if not mainGuiHiddenByMap then
		return
	end

	for guiObject, visible in pairs(mainGuiVisibilitySnapshot) do
		if guiObject and guiObject.Parent and guiObject:IsA("GuiObject") then
			guiObject.Visible = visible
		end
	end
	table.clear(mainGuiVisibilitySnapshot)
	mainGuiHiddenByMap = false
end

local function BindMainGuiChildListener()
	if mainGuiChildAddedConnection then
		mainGuiChildAddedConnection:Disconnect()
		mainGuiChildAddedConnection = nil
	end

	local currentMainGui = ResolveMainGui()
	if not currentMainGui then
		return
	end

	mainGuiChildAddedConnection = currentMainGui.ChildAdded:Connect(function(child)
		if not child or not child:IsA("GuiObject") then
			return
		end
		if mainGuiHiddenByMap and mapBg and mapBg.Visible then
			mainGuiVisibilitySnapshot[child] = child.Visible
			child.Visible = false
		end
	end)
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

	warn("[MapDisplay] ButtonEffectHelper加载失败:", result)
	return false
end

local function ParseBlurLocks()
	local lockStr = Lighting:GetAttribute(BLUR_LOCKS_KEY)
	local lockMap = {}
	if type(lockStr) == "string" and lockStr ~= "" then
		for token in string.gmatch(lockStr, "[^|]+") do
			lockMap[token] = true
		end
	end
	return lockMap
end

local function SetBlurLock(enabled)
	local lockMap = ParseBlurLocks()
	if enabled then
		lockMap[BLUR_LOCK_ID] = true
	else
		lockMap[BLUR_LOCK_ID] = nil
	end

	local tokens = {}
	for token in pairs(lockMap) do
		table.insert(tokens, token)
	end
	table.sort(tokens)

	if #tokens > 0 then
		Lighting:SetAttribute(BLUR_LOCKS_KEY, table.concat(tokens, "|"))
	else
		Lighting:SetAttribute(BLUR_LOCKS_KEY, nil)
	end

	local blur = Lighting:FindFirstChild("Blur")
	if blur and blur:IsA("BlurEffect") then
		blur.Enabled = #tokens > 0
	end
end

local function EnsureScale()
	if not mapBg then
		return nil
	end

	if mapScale and mapScale.Parent == mapBg then
		return mapScale
	end

	local existing = mapBg:FindFirstChild("PopupScale")
	if existing and existing:IsA("UIScale") then
		mapScale = existing
		return mapScale
	end

	mapScale = Instance.new("UIScale")
	mapScale.Name = "PopupScale"
	mapScale.Scale = 1
	mapScale.Parent = mapBg
	return mapScale
end

local function CancelTweens()
	for _, tween in ipairs({popupOpenTweenA, popupOpenTweenB, popupCloseTweenA, popupCloseTweenB}) do
		if tween then
			pcall(function()
				tween:Cancel()
			end)
		end
	end
	popupOpenTweenA = nil
	popupOpenTweenB = nil
	popupCloseTweenA = nil
	popupCloseTweenB = nil
	popupAnimationMode = nil
end

local function QueueCloseCallback(callback)
	if type(callback) ~= "function" then
		return
	end
	table.insert(closeCompletionCallbacks, callback)
end

local function FlushCloseCallbacks()
	if #closeCompletionCallbacks == 0 then
		return
	end

	local callbacks = closeCompletionCallbacks
	closeCompletionCallbacks = {}
	for _, callback in ipairs(callbacks) do
		task.spawn(function()
			local ok, err = pcall(callback)
			if not ok then
				warn("[MapDisplay] 关闭回调执行失败:", err)
			end
		end)
	end
end

local function PlayOpen()
	if not mapBg then
		return false
	end

	if popupAnimationMode == "opening" then
		return true
	end

	local scale = EnsureScale()
	if not scale then
		HideMainGuiForMap()
		mapBg.Visible = true
		if dimBg then
			dimBg.Visible = true
		end
		SetBlurLock(true)
		RequestBackpackHide()
		return true
	end

	if mapBg.Visible and not popupAnimating then
		HideMainGuiForMap()
		if dimBg then
			dimBg.Visible = true
		end
		SetBlurLock(true)
		RequestBackpackHide()
		return true
	end

	CancelTweens()
	popupAnimating = true
	popupAnimationMode = "opening"
	HideMainGuiForMap()
	mapBg.Visible = true
	if dimBg then
		dimBg.Visible = true
	end
	SetBlurLock(true)
	RequestBackpackHide()

	scale.Scale = POPUP_OPEN_START_SCALE

	popupOpenTweenA = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_OPEN_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = POPUP_OPEN_OVERSHOOT_SCALE }
	)
	popupOpenTweenB = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_OPEN_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)

	local connA
	local connB
	connA = popupOpenTweenA.Completed:Connect(function(state)
		if connA then
			connA:Disconnect()
			connA = nil
		end
		if state == Enum.PlaybackState.Completed and popupOpenTweenB then
			popupOpenTweenB:Play()
		end
	end)

	connB = popupOpenTweenB.Completed:Connect(function()
		if connB then
			connB:Disconnect()
			connB = nil
		end
		popupAnimating = false
		popupAnimationMode = nil
		scale.Scale = 1
		SetBlurLock(true)
	end)

	popupOpenTweenA:Play()
	return true
end

local function PlayClose(onClosed)
	if not mapBg then
		return false
	end

	QueueCloseCallback(onClosed)

	if popupAnimationMode == "closing" then
		return true
	end

	local scale = EnsureScale()
	if not scale then
		mapBg.Visible = false
		if dimBg then
			dimBg.Visible = false
		end
		SetBlurLock(false)
		ReleaseBackpackHide()
		RestoreMainGuiAfterMap()
		FlushCloseCallbacks()
		return true
	end

	if not mapBg.Visible and not popupAnimating then
		if dimBg then
			dimBg.Visible = false
		end
		SetBlurLock(false)
		ReleaseBackpackHide()
		RestoreMainGuiAfterMap()
		FlushCloseCallbacks()
		return true
	end

	CancelTweens()
	popupAnimating = true
	popupAnimationMode = "closing"

	popupCloseTweenA = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_A, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = POPUP_CLOSE_OVERSHOOT_SCALE }
	)
	popupCloseTweenB = TweenService:Create(
		scale,
		TweenInfo.new(POPUP_CLOSE_DURATION_B, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = POPUP_CLOSE_END_SCALE }
	)

	local connA
	local connB
	connA = popupCloseTweenA.Completed:Connect(function(state)
		if connA then
			connA:Disconnect()
			connA = nil
		end
		if state == Enum.PlaybackState.Completed and popupCloseTweenB then
			popupCloseTweenB:Play()
		end
	end)

	connB = popupCloseTweenB.Completed:Connect(function()
		if connB then
			connB:Disconnect()
			connB = nil
		end
		popupAnimating = false
		popupAnimationMode = nil
		mapBg.Visible = false
		if dimBg then
			dimBg.Visible = false
		end
		scale.Scale = 1
		SetBlurLock(false)
		ReleaseBackpackHide()
		RestoreMainGuiAfterMap()
		FlushCloseCallbacks()
	end)

	popupCloseTweenA:Play()
	return true
end

HideBackpackForBattle = function()
	if _G.BackpackDisplay and _G.BackpackDisplay.HideBackpack then
		_G.BackpackDisplay.HideBackpack(BACKPACK_HIDE_KEY)
		return
	end

	local backpackGui = playerGui:FindFirstChild("BackpackGui")
	if backpackGui then
		backpackGui.Enabled = false
	end
end

local function IsChapterUnlocked(chapterId)
	local data = chapterCardData[chapterId]
	if not data then
		return false
	end
	return data.Unlocked == true
end

local function ResolveMedalLabelRefs()
	local currentMainGui = playerGui:FindFirstChild("MainGui")
	local medalRoot = currentMainGui and (currentMainGui:FindFirstChild("Medal") or currentMainGui:FindFirstChild("Medal", true))
	local medalLabel = medalRoot and (medalRoot:FindFirstChild("MedalHaveNum") or medalRoot:FindFirstChild("MedalHaveNum", true))
	if medalLabel and (medalLabel:IsA("TextLabel") or medalLabel:IsA("TextButton")) then
		mainMedalNumLabel = medalLabel
	else
		mainMedalNumLabel = nil
	end

	local currentMapGui = playerGui:FindFirstChild("Map")
	local currentMapBg = currentMapGui and currentMapGui:FindFirstChild("MapBg")
	local mapLabel = currentMapBg and (currentMapBg:FindFirstChild("MedalHaveNum") or currentMapBg:FindFirstChild("MedalHaveNum", true))
	if mapLabel and (mapLabel:IsA("TextLabel") or mapLabel:IsA("TextButton")) then
		mapMedalNumLabel = mapLabel
	else
		mapMedalNumLabel = nil
	end
end

local function UpdateMedalCountDisplay(medalCount)
	ResolveMedalLabelRefs()

	local value = tonumber(medalCount)
	if value == nil then
		value = tonumber(player:GetAttribute("MedalCount")) or 0
	end
	value = math.max(0, math.floor(value))
	local text = tostring(value)

	if mainMedalNumLabel then
		mainMedalNumLabel.Text = text
	end
	if mapMedalNumLabel then
		mapMedalNumLabel.Text = text
	end
end

local function RefreshSelectState()
	for chapterId, data in pairs(chapterCardData) do
		if data.ChooseBg then
			data.ChooseBg.Visible = (chapterId == selectedChapterId and data.Unlocked == true)
		end
	end
end

local function SelectChapter(chapterId)
	if not IsChapterUnlocked(chapterId) then
		return
	end
	selectedChapterId = chapterId
	RefreshSelectState()
end

local function PickDefaultChapter(payload)
	local chapterId = tonumber(payload and payload.CurrentChapter)
	if chapterId and IsChapterUnlocked(chapterId) then
		return chapterId
	end

	for _, chapter in ipairs(payload and payload.Chapters or {}) do
		local id = tonumber(chapter.ChapterId)
		if id and IsChapterUnlocked(id) then
			return id
		end
	end

	return 1
end

local function UpdateCanvasSize()
	if not scrollingFrame then
		return
	end

	local layout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if layout then
		local contentHeight = layout.AbsoluteContentSize.Y
		local padding = 12
		scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, contentHeight + padding)
	end
end

local function BindCardClick(card, onClick)
	if not card or type(onClick) ~= "function" then
		return
	end

	if card:IsA("GuiButton") then
		card.MouseButton1Click:Connect(onClick)
		return
	end

	local clickButton = card:FindFirstChild("ClickButton")
	if clickButton and clickButton:IsA("GuiButton") then
		clickButton.MouseButton1Click:Connect(onClick)
		return
	end

	if card:IsA("GuiObject") then
		card.Active = true
		card.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				onClick()
			end
		end)
	end
end

local function ClearCards()
	if not scrollingFrame then
		return
	end

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		local generated = child:GetAttribute("GeneratedByMapDisplay") == true
		local namedCard = string.sub(child.Name, 1, 8) == "MapCard_"
		if child ~= mapTemplate and (generated or namedCard) then
			child:Destroy()
		end
	end

	chapterCardData = {}
end

local function RebuildCards(payload)
	if not scrollingFrame or not mapTemplate then
		return
	end

	ClearCards()

	for _, chapter in ipairs(payload and payload.Chapters or {}) do
		local chapterId = tonumber(chapter.ChapterId)
		if chapterId then
			local card = mapTemplate:Clone()
			card:SetAttribute("GeneratedByMapDisplay", true)
			card.Name = "MapCard_" .. tostring(chapterId)
			card.Visible = true
			card.LayoutOrder = chapterId
			if mapTemplateBaseSize then
				card.Size = mapTemplateBaseSize
			end
			if mapTemplateBaseAutomaticSize then
				card.AutomaticSize = mapTemplateBaseAutomaticSize
			end
			local cardScale = card:FindFirstChildOfClass("UIScale")
			if cardScale then
				cardScale.Scale = 1
			end
			card.Parent = scrollingFrame

			local unlocked = chapter.Unlocked == true

			local mapIcon = card:FindFirstChild("MapIcon")
			if mapIcon and mapIcon:IsA("ImageLabel") then
				mapIcon.Image = tostring(chapter.MapIcon or "")
			end

			local mapName = card:FindFirstChild("MapName")
			if mapName and mapName:IsA("TextLabel") then
				mapName.Text = tostring(chapter.ChapterName or ("Chapter " .. tostring(chapterId)))
			end

			local medalNum = card:FindFirstChild("MedalNum")
			if medalNum and medalNum:IsA("TextLabel") then
				medalNum.Text = "*" .. tostring(math.max(0, math.floor(tonumber(chapter.RewardMedals) or 0)))
			end

			local lockBg = card:FindFirstChild("LockBg")
			if lockBg and lockBg:IsA("GuiObject") then
				lockBg.Visible = not unlocked
				local unlockDes = lockBg:FindFirstChild("UnlockDes")
				if unlockDes and unlockDes:IsA("TextLabel") then
					local unlockNeed = math.max(0, math.floor(tonumber(chapter.UnlockMedals) or 0))
					unlockDes.Text = string.format("%d Medals To Unlock", unlockNeed)
				end
			end

			local chooseBg = card:FindFirstChild("ChooseBg")
			if chooseBg and chooseBg:IsA("GuiObject") then
				chooseBg.Visible = false
			end

			chapterCardData[chapterId] = {
				Card = card,
				ChooseBg = chooseBg,
				Unlocked = unlocked,
			}

			BindCardClick(card, function()
				if unlocked then
					SelectChapter(chapterId)
				end
			end)
		end
	end

	UpdateCanvasSize()

	selectedChapterId = PickDefaultChapter(payload)
	RefreshSelectState()
end

local function OnMapData(payload)
	if type(payload) ~= "table" then
		return
	end

	latestPayload = payload
	UpdateMedalCountDisplay(payload.MedalCount)
	RebuildCards(payload)

	if autoAttackPending and selectedChapterId and IsChapterUnlocked(selectedChapterId) then
		task.defer(function()
			if autoAttackPending and mapBg and mapBg.Visible then
				local chapterIdToStart = selectedChapterId
				pendingAttackChapterId = chapterIdToStart
				CloseMapAndStartPendingAttack()
				autoAttackPending = false
			end
		end)
	end
end

local function RequestMapData()
	if requestMapDataEvent then
		requestMapDataEvent:FireServer()
	elseif latestPayload then
		OnMapData(latestPayload)
	end
end

local function FireStartCampaignForPendingAttack()
	local pendingChapter = pendingAttackChapterId
	pendingAttackChapterId = nil
	if pendingChapter and requestStartCampaignEvent then
		task.defer(function()
			requestStartCampaignEvent:FireServer(pendingChapter)
		end)
	end
end

CloseMapAndStartPendingAttack = function()
	HideBackpackForBattle()
	local closeStarted = PlayClose(FireStartCampaignForPendingAttack)
	if not closeStarted then
		FireStartCampaignForPendingAttack()
	end
end

local function StartAttack()
	if pendingAttackChapterId then
		return
	end

	if not selectedChapterId or not IsChapterUnlocked(selectedChapterId) then
		return
	end

	local chapterIdToStart = selectedChapterId
	pendingAttackChapterId = chapterIdToStart
	CloseMapAndStartPendingAttack()

	autoAttackPending = false
end

local function OpenMapInternal(isAutoAttack)
	if not initialized then
		if not Initialize() then
			return false
		end
	end

	pendingAttackChapterId = nil
	autoAttackPending = isAutoAttack == true
	PlayOpen()
	RequestMapData()
	return true
end

local function CloseMapInternal(cancelAutoAttack)
	if cancelAutoAttack ~= false then
		autoAttackPending = false
	end
	PlayClose()
end

local function BindButton(button, callback)
	if not button or type(callback) ~= "function" then
		return
	end
	if not button:IsA("GuiButton") then
		return
	end
	if button:GetAttribute("MapDisplayBound") == true then
		return
	end
	button:SetAttribute("MapDisplayBound", true)

	if ButtonEffectHelper then
		ButtonEffectHelper.AddClickEffect(button, { OnClick = callback })
	else
		button.MouseButton1Click:Connect(callback)
	end
end

local function InitializeUI()
	mainGui = SafeWaitForChild(playerGui, "MainGui", 5)
	if not mainGui then
		return false
	end
	BindMainGuiChildListener()

	battleControl = mainGui:FindFirstChild("BattleControl")
	playButton = battleControl and battleControl:FindFirstChild("Play")

	mapGui = playerGui:FindFirstChild("Map") or SafeWaitForChild(playerGui, "Map", 5)
	if not mapGui then
		warn("[MapDisplay] 未找到Map界面")
		return false
	end

	mapBg = mapGui:FindFirstChild("MapBg")
	dimBg = mapGui:FindFirstChild("Bg")
	if not mapBg then
		warn("[MapDisplay] 未找到MapBg")
		return false
	end

	closeButton = mapBg:FindFirstChild("CloseButton")
	attackButton = mapBg:FindFirstChild("AttackButton")
	scrollingFrame = mapBg:FindFirstChild("ScrollingFrame")
	mapTemplate = scrollingFrame and scrollingFrame:FindFirstChild("MapTemplate")

	if not scrollingFrame or not mapTemplate then
		warn("[MapDisplay] 缺少ScrollingFrame或MapTemplate")
		return false
	end

	mapTemplate.Visible = false
	mapTemplateBaseSize = mapTemplate.Size
	mapTemplateBaseAutomaticSize = mapTemplate.AutomaticSize
	mapBg.Visible = false
	if dimBg then
		dimBg.Visible = false
	end

	EnsureScale()
	UpdateMedalCountDisplay()
	return true
end

local function InitializeEvents()
	local eventsFolder = SafeWaitForChild(ReplicatedStorage, "Events", 5)
	if not eventsFolder then
		return false
	end

	campaignEvents = eventsFolder:FindFirstChild("CampaignEvents")
	if not campaignEvents then
		return false
	end

	requestMapDataEvent = campaignEvents:FindFirstChild("RequestMapData") or SafeWaitForChild(campaignEvents, "RequestMapData", 5)
	mapDataEvent = campaignEvents:FindFirstChild("MapData") or SafeWaitForChild(campaignEvents, "MapData", 5)
	requestStartCampaignEvent = campaignEvents:FindFirstChild("RequestStartCampaign") or SafeWaitForChild(campaignEvents, "RequestStartCampaign", 5)
	campaignStateUpdateEvent = campaignEvents:FindFirstChild("CampaignStateUpdate") or SafeWaitForChild(campaignEvents, "CampaignStateUpdate", 5)

	return requestStartCampaignEvent ~= nil
end

local function BindEvents()
	if mapDataEvent then
		mapDataEvent.OnClientEvent:Connect(OnMapData)
	end

	if medalAttrConnection then
		medalAttrConnection:Disconnect()
		medalAttrConnection = nil
	end
	medalAttrConnection = player:GetAttributeChangedSignal("MedalCount"):Connect(function()
		UpdateMedalCountDisplay(player:GetAttribute("MedalCount"))
	end)

	if campaignStateUpdateEvent then
		campaignStateUpdateEvent.OnClientEvent:Connect(function(state)
			if state ~= "Idle" then
				CloseMapInternal(false)
			end
		end)
	end
end

local function BindButtons()
	LoadButtonEffectHelper()

	BindButton(closeButton, function()
		CloseMapInternal(true)
	end)

	BindButton(attackButton, function()
		StartAttack()
	end)
end

Initialize = function()
	if initialized then
		return true
	end

	if not InitializeUI() then
		return false
	end
	if not InitializeEvents() then
		return false
	end

	BindEvents()
	BindButtons()
	RequestMapData()

	initialized = true
	return true
end

MapDisplay.OpenMap = function()
	return OpenMapInternal(false)
end

MapDisplay.CloseMap = function()
	CloseMapInternal(true)
end

MapDisplay.AutoStartAttack = function()
	return OpenMapInternal(true)
end

MapDisplay.IsOpen = function()
	return mapBg and mapBg.Visible or false
end

_G.MapDisplay = MapDisplay

task.spawn(function()
	local ok, err = pcall(Initialize)
	if not ok then
		warn("[MapDisplay] 初始化失败:", err)
	end
end)

playerGui.ChildAdded:Connect(function(child)
	if not child then
		return
	end
	if child.Name == "MainGui" or child.Name == "Map" then
		task.defer(function()
			if child.Name == "MainGui" then
				mainGui = child
				BindMainGuiChildListener()
				if mapBg and mapBg.Visible then
					mainGuiHiddenByMap = false
					table.clear(mainGuiVisibilitySnapshot)
					HideMainGuiForMap()
				end
			end
			UpdateMedalCountDisplay()
		end)
	end
end)

return MapDisplay
