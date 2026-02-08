--[[
脚本名称: TalkController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/TalkController.lua
版本: V4.5
]]

local TalkController = {}

-- 服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- 配置
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

-- 玩家
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- UI引用
local talkGui = nil
local talkFrame = nil
local talkList = nil
local chatTemplate = nil

local talkBottomGui = nil
local talkBottomFrame = nil
local talkBottomText = nil
local talkBottomArrow = nil

-- UI缓存
local talkFramePos = nil
local talkFrameSize = nil
local talkBottomPos = nil
local talkBottomSize = nil
local arrowBasePos = nil

-- 事件引用
local talkEvents = nil
local requestTalkList = nil
local talkListEvent = nil
local selectTalkOption = nil
local talkResponseEvent = nil
local currencyEvents = nil

-- 状态
local isNearNPC = false
local isNearNPC = false
local isListOpen = false
local isDialogOpen = false
local manualClosed = false
local listDirty = true
local pendingOpen = false
local lastRequestTime = 0
local lastCurrencyRequest = 0

local currentNPC = nil
local currentPrompt = nil
local promptConnection = nil
local SetupPrompt = nil
local CloseTalkList = nil
local CloseDialog = nil
local currentDialogues = {}
local currentDialogIndex = 0

-- PrisonerTouch触发
local prisonerTouchPart = nil
local prisonerTouchConn = nil
local prisonerTouchEndedConn = nil
local prisonerTouchingParts = {}
local prisonerTouchActive = false
local lastTouchResolve = 0
local TOUCH_RESOLVE_INTERVAL = 0.5

local listTween = nil
local bottomTween = nil
local arrowTween = nil
local listVisibilityConn = nil

-- ==================== 工具方法 ====================

local function ScaleSize(size: UDim2, scale: number): UDim2
	return UDim2.new(
		size.X.Scale * scale,
		size.X.Offset * scale,
		size.Y.Scale * scale,
		size.Y.Offset * scale
	)
end

local function PlayFrameOpen(frame: Frame, targetPos: UDim2, targetSize: UDim2)
	if not frame then
		return
	end
	if frame == talkFrame and listTween then
		listTween:Cancel()
	end
	if frame == talkBottomFrame and bottomTween then
		bottomTween:Cancel()
	end

	frame.Visible = true
	frame.Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale + 0.03, targetPos.Y.Offset)
	frame.Size = ScaleSize(targetSize, 0.95)

	local tween = TweenService:Create(
		frame,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = targetPos, Size = targetSize }
	)
	tween:Play()

	if frame == talkFrame then
		listTween = tween
	else
		bottomTween = tween
	end
end

local function PlayFrameClose(frame: Frame, targetPos: UDim2, targetSize: UDim2)
	if not frame then
		return
	end
	if frame == talkFrame and listTween then
		listTween:Cancel()
	end
	if frame == talkBottomFrame and bottomTween then
		bottomTween:Cancel()
	end

	local tween = TweenService:Create(
		frame,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale + 0.03, targetPos.Y.Offset), Size = ScaleSize(targetSize, 0.95) }
	)
	tween.Completed:Connect(function(playbackState)
		if frame and playbackState == Enum.PlaybackState.Completed then
			frame.Visible = false
		end
	end)
	tween:Play()

	if frame == talkFrame then
		listTween = tween
	else
		bottomTween = tween
	end
end

local function StartArrowFloat()
	if not talkBottomArrow then
		return
	end
	if arrowTween then
		arrowTween:Cancel()
	end
	talkBottomArrow.Position = arrowBasePos
	arrowTween = TweenService:Create(
		talkBottomArrow,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.new(arrowBasePos.X.Scale, arrowBasePos.X.Offset, arrowBasePos.Y.Scale + 0.02, arrowBasePos.Y.Offset) }
	)
	arrowTween:Play()
end

local function StopArrowFloat()
	if arrowTween then
		arrowTween:Cancel()
		arrowTween = nil
	end
	if talkBottomArrow and arrowBasePos then
		talkBottomArrow.Position = arrowBasePos
	end
end

local function IsLocalCharacterPart(part: Instance?)
	local character = player.Character
	return character and part and part:IsDescendantOf(character)
end

local function IsCharacterTouchingPart(part: BasePart)
	local character = player.Character
	if not character or not part or not part.Parent then
		return false
	end

	local ok, touching = pcall(function()
		return part:GetTouchingParts()
	end)
	if not ok or type(touching) ~= "table" then
		return false
	end

	for _, hit in ipairs(touching) do
		if hit and hit:IsDescendantOf(character) then
			return true
		end
	end

	return false
end

local function BindPrompt(prompt: ProximityPrompt?)
	if promptConnection then
		promptConnection:Disconnect()
		promptConnection = nil
	end

	currentPrompt = prompt
	if currentPrompt then
		promptConnection = currentPrompt.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer == player then
				TalkController.OpenTalkList(true)
			end
		end)
	end
end

local function SetPromptEnabled(enabled: boolean)
	if not currentPrompt or not currentPrompt.Parent then
		if currentNPC then
			SetupPrompt(currentNPC)
		end
	end
	if currentPrompt then
		currentPrompt.Enabled = enabled
	end
end

local function SetupVisibilityWatch()
	if talkFrame and not listVisibilityConn then
		listVisibilityConn = talkFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if talkFrame.Visible then
				return
			end
			if isNearNPC and not isDialogOpen then
				isListOpen = false
				manualClosed = true
				listDirty = true
				pendingOpen = false
				SetPromptEnabled(true)
			end
		end)
	end
end

local function RequestCurrencySync()
	if not currencyEvents then
		local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
		currencyEvents = eventsFolder and eventsFolder:FindFirstChild("CurrencyEvents")
	end
	if not currencyEvents then
		return
	end
	local now = tick()
	if now - lastCurrencyRequest < 0.2 then
		return
	end
	lastCurrencyRequest = now
	pcall(function()
		currencyEvents:FireServer()
	end)
end

-- ==================== UI 初始化 ====================

local function InitializeUI()
	if talkGui and talkFrame and talkList then
		return true
	end

	talkGui = playerGui:WaitForChild("Talk", 10)
	if not talkGui then
		warn("[TalkController] 找不到 Talk ScreenGui")
		return false
	end

	talkFrame = talkGui:FindFirstChild("Bg")
	if not talkFrame then
		warn("[TalkController] 找不到 Talk/Bg")
		return false
	end

	talkList = talkFrame:FindFirstChild("ScrollingFrame")
	if not talkList then
		warn("[TalkController] 找不到 Talk/Bg/ScrollingFrame")
		return false
	end

	chatTemplate = talkList:FindFirstChild("ChatTemplate")
	if not chatTemplate then
		warn("[TalkController] 找不到 ChatTemplate")
		return false
	end
	chatTemplate.Visible = false

	talkFramePos = talkFrame.Position
	talkFrameSize = talkFrame.Size

	talkBottomGui = playerGui:WaitForChild("TalkBottom", 10)
	if not talkBottomGui then
		warn("[TalkController] 找不到 TalkBottom ScreenGui")
		return false
	end

	talkBottomFrame = talkBottomGui:FindFirstChild("Bg")
	if not talkBottomFrame then
		warn("[TalkController] 找不到 TalkBottom/Bg")
		return false
	end

	talkBottomText = talkBottomFrame:FindFirstChild("TalkText")
	talkBottomArrow = talkBottomFrame:FindFirstChild("Arrow")
	if not talkBottomText then
		warn("[TalkController] 找不到 TalkBottom/Bg/TalkText")
	end
	if not talkBottomArrow then
		warn("[TalkController] 找不到 TalkBottom/Bg/Arrow")
	end

	talkBottomPos = talkBottomFrame.Position
	talkBottomSize = talkBottomFrame.Size
	if talkBottomArrow then
		arrowBasePos = talkBottomArrow.Position
	end

	talkFrame.Visible = false
	talkBottomFrame.Visible = false

	return true
end

-- ==================== 事件初始化 ====================

local function InitializeEvents()
	if talkEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[TalkController] 找不到 Events")
		return false
	end

	talkEvents = eventsFolder:WaitForChild("TalkEvents", 10)
	if not talkEvents then
		warn("[TalkController] 找不到 TalkEvents")
		return false
	end

	requestTalkList = talkEvents:WaitForChild("RequestTalkList", 5)
	talkListEvent = talkEvents:WaitForChild("TalkList", 5)
	selectTalkOption = talkEvents:WaitForChild("SelectTalkOption", 5)
	talkResponseEvent = talkEvents:WaitForChild("TalkResponse", 5)

	if not (requestTalkList and talkListEvent and selectTalkOption and talkResponseEvent) then
		warn("[TalkController] TalkEvents事件不完整")
		return false
	end

	return true
end

-- ==================== NPC 检测 ====================

local function FindNPC()
	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then
		return nil
	end

	local homeFolder = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME or "Home")
	if not homeFolder then
		return nil
	end

	local playerHome = homeFolder:FindFirstChild((GameConfig.HOME_PREFIX or "PlayerHome") .. homeSlot)
	if not playerHome then
		return nil
	end

	local npcName = (GameConfig.Shop and GameConfig.Shop.NPCName) or "KeepShoper01"
	return playerHome:FindFirstChild(npcName)
end

local function GetNPCCenterPart(npc)
	if not npc then
		return nil
	end
	return npc:FindFirstChild("HumanoidRootPart", true)
		or npc.PrimaryPart
		or npc:FindFirstChildWhichIsA("BasePart", true)
end

SetupPrompt = function(npc)
	if not npc then
		BindPrompt(nil)
		return
	end
	local part = GetNPCCenterPart(npc)
	local prompt = nil
	if part then
		prompt = part:FindFirstChildWhichIsA("ProximityPrompt")
	end
	if not prompt then
		prompt = npc:FindFirstChildWhichIsA("ProximityPrompt", true)
	end
	BindPrompt(prompt)
end

local function FindPrisonerTouchPart()
	local homeSlot = player:GetAttribute("HomeSlot")
	if not homeSlot then
		return nil
	end

	local homeFolder = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME or "Home")
	if not homeFolder then
		return nil
	end

	local playerHome = homeFolder:FindFirstChild((GameConfig.HOME_PREFIX or "PlayerHome") .. homeSlot)
	if not playerHome then
		return nil
	end

	return playerHome:FindFirstChild("PrisonerTouch")
end

local function ClearPrisonerTouchConnections()
	if prisonerTouchConn then
		prisonerTouchConn:Disconnect()
		prisonerTouchConn = nil
	end
	if prisonerTouchEndedConn then
		prisonerTouchEndedConn:Disconnect()
		prisonerTouchEndedConn = nil
	end
	prisonerTouchingParts = {}
	prisonerTouchActive = false
end

local function BindPrisonerTouch(part: BasePart?)
	if prisonerTouchPart == part then
		return
	end

	ClearPrisonerTouchConnections()
	prisonerTouchPart = part
	if not part then
		return
	end

	prisonerTouchConn = part.Touched:Connect(function(hit)
		if not IsLocalCharacterPart(hit) then
			return
		end
		prisonerTouchingParts[hit] = true
		if not prisonerTouchActive then
			prisonerTouchActive = true
			TalkController.OpenTalkList(true)
		end
	end)

	prisonerTouchEndedConn = part.TouchEnded:Connect(function(hit)
		if not prisonerTouchingParts[hit] then
			return
		end
		prisonerTouchingParts[hit] = nil
		if next(prisonerTouchingParts) == nil then
			prisonerTouchActive = false
			CloseDialog()
			CloseTalkList(true)
		end
	end)
end

local function ResolvePrisonerTouch(force: boolean)
	local now = tick()
	if not force and (now - lastTouchResolve) < TOUCH_RESOLVE_INTERVAL then
		return
	end
	lastTouchResolve = now

	local part = FindPrisonerTouchPart()
	if part and not part:IsA("BasePart") then
		part = nil
	end
	if part ~= prisonerTouchPart then
		BindPrisonerTouch(part)
	end
end

local function UpdatePrisonerTouchState()
	if not prisonerTouchPart or not prisonerTouchPart.Parent then
		if prisonerTouchActive then
			prisonerTouchActive = false
			prisonerTouchingParts = {}
		end
		return
	end

	local touching = IsCharacterTouchingPart(prisonerTouchPart)
	if touching and not prisonerTouchActive then
		prisonerTouchActive = true
		TalkController.OpenTalkList(true)
	elseif (not touching) and prisonerTouchActive and next(prisonerTouchingParts) == nil then
		prisonerTouchActive = false
		CloseDialog()
		CloseTalkList(true)
	end
end

-- ==================== 列表生成 ====================

local function ClearTalkList()
	for _, child in ipairs(talkList:GetChildren()) do
		if child:IsA("Frame") and child ~= chatTemplate then
			child:Destroy()
		end
	end
end

local function BindOptionEffect(optionFrame: Frame, talkId: number)
	local clickButton = optionFrame:FindFirstChild("ClickButton")
	if not clickButton then
		clickButton = Instance.new("TextButton")
		clickButton.Name = "ClickButton"
		clickButton.BackgroundTransparency = 1
		clickButton.Size = UDim2.new(1, 0, 1, 0)
		clickButton.Position = UDim2.new(0, 0, 0, 0)
		clickButton.Text = ""
		clickButton.ZIndex = optionFrame.ZIndex + 1
		clickButton.Parent = optionFrame
	end

	local originalSize = optionFrame.Size
	local hoverScale = 1.05
	local clickScale = GameConfig.UI and GameConfig.UI.ButtonScaleDown or 0.95

	local activeTween = nil
	local function PlayScale(scale)
		if activeTween then
			activeTween:Cancel()
		end
		activeTween = TweenService:Create(
			optionFrame,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = ScaleSize(originalSize, scale) }
		)
		activeTween:Play()
	end

	clickButton.MouseEnter:Connect(function()
		PlayScale(hoverScale)
	end)
	clickButton.MouseLeave:Connect(function()
		PlayScale(1)
	end)
	clickButton.MouseButton1Down:Connect(function()
		PlayScale(clickScale)
	end)
	clickButton.MouseButton1Up:Connect(function()
		PlayScale(hoverScale)
	end)
	clickButton.MouseButton1Click:Connect(function()
		if selectTalkOption then
			selectTalkOption:FireServer(talkId)
		end
	end)
end

local function BuildTalkList(options)
	if not chatTemplate then
		return
	end

	ClearTalkList()

	for index, option in ipairs(options) do
		local item = chatTemplate:Clone()
		item.Name = "ChatOption_" .. tostring(option.Id or index)
		item.Visible = true
		item.LayoutOrder = option.Sort or index

		local textLabel = item:FindFirstChild("TalkText")
		if textLabel and textLabel:IsA("TextLabel") then
			textLabel.Text = string.format("[%d]%s", index, option.Text or "")
		end

		BindOptionEffect(item, option.Id)
		item.Parent = talkList
	end
end

-- ==================== 对话流程 ====================

local function HideTalkListForDialog()
	if talkFrame and isListOpen then
		PlayFrameClose(talkFrame, talkFramePos, talkFrameSize)
	end
	isListOpen = false
	SetPromptEnabled(false)
end

local function ShowTalkList()
	if talkFrame then
		PlayFrameOpen(talkFrame, talkFramePos, talkFrameSize)
	end
	isListOpen = true
	SetPromptEnabled(false)
end

CloseTalkList = function(manual: boolean)
	if talkFrame and isListOpen then
		PlayFrameClose(talkFrame, talkFramePos, talkFrameSize)
	end
	isListOpen = false
	listDirty = true
	pendingOpen = false
	lastRequestTime = 0
	if manual then
		manualClosed = true
		if isNearNPC then
			SetPromptEnabled(true)
		end
	else
		manualClosed = false
		SetPromptEnabled(false)
	end
end

local function ShowDialog(dialogues: {string})
	if not talkBottomFrame or not talkBottomText then
		return
	end

	if not dialogues or #dialogues == 0 then
		ShowTalkList()
		return
	end

	currentDialogues = dialogues
	currentDialogIndex = 1
	talkBottomText.Text = currentDialogues[currentDialogIndex] or ""

	HideTalkListForDialog()
	PlayFrameOpen(talkBottomFrame, talkBottomPos, talkBottomSize)
	isDialogOpen = true
	StartArrowFloat()
end

CloseDialog = function()
	if talkBottomFrame and isDialogOpen then
		PlayFrameClose(talkBottomFrame, talkBottomPos, talkBottomSize)
	end
	isDialogOpen = false
	StopArrowFloat()
	currentDialogues = {}
	currentDialogIndex = 0
	pendingOpen = false
	lastRequestTime = 0
end

local function AdvanceDialog()
	if not isDialogOpen then
		return
	end
	if currentDialogIndex < #currentDialogues then
		currentDialogIndex = currentDialogIndex + 1
		if talkBottomText then
			talkBottomText.Text = currentDialogues[currentDialogIndex] or ""
		end
	else
		CloseDialog()
		listDirty = true
		if isNearNPC then
			ShowTalkList()
			if requestTalkList then
				pendingOpen = true
				lastRequestTime = tick()
				requestTalkList:FireServer()
			end
		end
	end
end

-- ==================== 交互逻辑 ====================

function TalkController.OpenTalkList(forceRefresh: boolean)
	if not InitializeUI() or not InitializeEvents() then
		return
	end
	if isDialogOpen then
		return
	end

	manualClosed = false

	if forceRefresh then
		listDirty = true
	end

	if listDirty and requestTalkList then
		pendingOpen = true
		lastRequestTime = tick()
		requestTalkList:FireServer()
	else
		ShowTalkList()
	end
end

function TalkController.CloseTalkList()
	CloseTalkList(true)
end

local function OpenArmyShop()
	local shopUI = playerGui:FindFirstChild("ArmyStore")
	local shopFrame = shopUI and shopUI:FindFirstChild("StoreBg")
	if shopFrame then
		if _G.ShopDisplay and _G.ShopDisplay.PlayOpen then
			_G.ShopDisplay.PlayOpen()
		else
			shopFrame.Visible = true
		end
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local shopEvents = eventsFolder and eventsFolder:FindFirstChild("ShopEvents")
	local requestShop = shopEvents and shopEvents:FindFirstChild("RequestShopList")
	if requestShop then
		requestShop:FireServer()
	end
end

-- ==================== 事件处理 ====================

local function OnTalkListReceived(options)
	BuildTalkList(options or {})
	listDirty = false

	if pendingOpen then
		pendingOpen = false
		lastRequestTime = 0
		if isNearNPC and not isDialogOpen and not manualClosed then
			ShowTalkList()
		end
	end
end

local function OnTalkResponse(success, action, talkId, dialogues)
	if not success then
		return
	end

	if action == "DIALOG" then
		listDirty = true
		ShowDialog(dialogues or {})
	elseif action == "OPEN_SHOP" then
		CloseTalkList(true)
		OpenArmyShop()
	elseif action == "CLOSE_LIST" then
		CloseTalkList(true)
	end

	RequestCurrencySync()
end

local function ConnectTalkBottomClick()
	if not talkBottomFrame then
		return
	end

	local clickButton = talkBottomFrame:FindFirstChild("ClickButton")
	if not clickButton then
		clickButton = Instance.new("TextButton")
		clickButton.Name = "ClickButton"
		clickButton.BackgroundTransparency = 1
		clickButton.Size = UDim2.new(1, 0, 1, 0)
		clickButton.Position = UDim2.new(0, 0, 0, 0)
		clickButton.Text = ""
		clickButton.ZIndex = talkBottomFrame.ZIndex + 1
		clickButton.Parent = talkBottomFrame
	end

	clickButton.MouseButton1Click:Connect(AdvanceDialog)
	clickButton.TouchTap:Connect(AdvanceDialog)
end

-- ==================== 距离检测 ====================

local function CheckDistance()
	ResolvePrisonerTouch(false)
	UpdatePrisonerTouchState()

	local npc = FindNPC()
	if not npc then
		if isNearNPC and not prisonerTouchActive then
			isNearNPC = false
			CloseDialog()
			CloseTalkList(false)
		end
		return
	end

	if npc ~= currentNPC then
		currentNPC = npc
		SetupPrompt(npc)
	end

	local npcPart = GetNPCCenterPart(npc)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not npcPart or not rootPart then
		return
	end

	local distance = (rootPart.Position - npcPart.Position).Magnitude
	local npcInRange = distance <= ((GameConfig.Shop and GameConfig.Shop.OpenDistance) or 11)
	local inRange = npcInRange or prisonerTouchActive

	if inRange and not isNearNPC then
		isNearNPC = true
		manualClosed = false
		if npcInRange and not prisonerTouchActive then
			TalkController.OpenTalkList(true)
		end
	elseif (not inRange) and isNearNPC then
		isNearNPC = false
		CloseDialog()
		CloseTalkList(false)
	end

	-- 兜底：仍在范围内但列表未打开时，自动尝试打开
	if inRange and not isListOpen and not isDialogOpen and not manualClosed then
		if pendingOpen then
			if tick() - lastRequestTime > 1.5 then
				pendingOpen = false
				TalkController.OpenTalkList(true)
			end
		else
			TalkController.OpenTalkList(true)
		end
	end

	if inRange and manualClosed then
		SetPromptEnabled(true)
	end
end

-- ==================== 初始化 ====================

function TalkController.Initialize()
	if not InitializeUI() or not InitializeEvents() then
		return false
	end

	ResolvePrisonerTouch(true)

	SetupVisibilityWatch()
	ConnectTalkBottomClick()

	if talkListEvent then
		talkListEvent.OnClientEvent:Connect(OnTalkListReceived)
	end
	if talkResponseEvent then
		talkResponseEvent.OnClientEvent:Connect(OnTalkResponse)
	end

	local lastCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = tick()
		local interval = (GameConfig.Shop and GameConfig.Shop.CheckInterval) or 0.2
		if now - lastCheck >= interval then
			lastCheck = now
			CheckDistance()
		end
	end)

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		isNearNPC = false
		currentNPC = nil
		currentPrompt = nil
		prisonerTouchActive = false
		prisonerTouchingParts = {}
		CloseDialog()
		CloseTalkList(false)
	end)

	return true
end

player:GetAttributeChangedSignal("HomeSlot"):Connect(function()
	ResolvePrisonerTouch(true)
end)

TalkController.Initialize()

_G.TalkController = TalkController

return TalkController
