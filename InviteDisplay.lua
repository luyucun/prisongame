--[[
=====================================================
Script Name: InviteDisplay
Script Type: LocalScript (Client UI)
Script Location: StarterPlayer/StarterPlayerScripts/UI/InviteDisplay
Version: V4.9.1
=====================================================
]]

local InviteDisplay = {}

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local topRightGui = nil
local inviteButtonContainer = nil
local inviteButton = nil

local ButtonEffectHelper = nil
local boundButtons = {}
local initialized = false

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

local function IsDescendantOfPlayerGui(instance)
	return instance ~= nil and instance:IsDescendantOf(playerGui)
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

	warn("[InviteDisplay] ButtonEffectHelper load failed:", result)
	return false
end

local function InitializeUI()
	local buttonValid = IsDescendantOfPlayerGui(inviteButton)
	if buttonValid then
		return true
	end

	topRightGui = nil
	inviteButtonContainer = nil
	inviteButton = nil

	topRightGui = SafeWaitForChild(playerGui, "TopRightGui", 5)
	if not topRightGui then
		return false
	end

	local topRightBg = topRightGui:FindFirstChild("Bg")
	inviteButtonContainer = topRightBg and topRightBg:FindFirstChild("Invite")
	inviteButton = inviteButtonContainer and inviteButtonContainer:FindFirstChild("Button")

	return inviteButton ~= nil
end

local function PromptInvite()
	local success, err = pcall(function()
		SocialService:PromptGameInvite(player)
	end)
	if success then
		return
	end

	local fallbackSuccess, fallbackErr = pcall(function()
		StarterGui:SetCore("PromptGameInvite")
	end)
	if not fallbackSuccess then
		warn("[InviteDisplay] Prompt invite failed:", err, fallbackErr)
	end
end

local function BindButtons()
	LoadButtonEffectHelper()

	if inviteButton and (inviteButton:IsA("TextButton") or inviteButton:IsA("ImageButton")) then
		if not boundButtons[inviteButton] then
			if ButtonEffectHelper then
				ButtonEffectHelper.AddClickEffect(inviteButton, { OnClick = PromptInvite })
			else
				inviteButton.MouseButton1Click:Connect(PromptInvite)
			end
			boundButtons[inviteButton] = true
		end
	end
end

local function TryInitialize()
	if not InitializeUI() then
		return false
	end

	BindButtons()
	return true
end

function InviteDisplay.Initialize()
	if initialized then
		return
	end

	if TryInitialize() then
		initialized = true
		return
	end

	task.spawn(function()
		local attempts = 0
		while attempts < 5 and not TryInitialize() do
			attempts += 1
			task.wait(2)
		end
		initialized = true
	end)

	playerGui.ChildAdded:Connect(function(child)
		if not child or child.Name ~= "TopRightGui" then
			return
		end
		task.spawn(function()
			task.wait()
			if InitializeUI() then
				BindButtons()
			end
		end)
	end)
end

InviteDisplay.Initialize()

return InviteDisplay
