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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))

local ButtonEffectHelper = nil

local mainGui = nil
local targetButton = nil

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
local BindHouseEntry

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

local function GetCompletedChapters()
	local completed = player:GetAttribute("CompletedChapters")
	if type(completed) == "number" then
		return completed
	end
	return 0
end

local function GetCurrentHouseModel()
	local modelName = player:GetAttribute("CurrentHouseModel")
	if type(modelName) == "string" and modelName ~= "" then
		return modelName
	end

	local completedChapters = GetCompletedChapters()
	local house = HouseConfig.GetHouseByChapter(completedChapters)
	return house and house.ModelName or nil
end

local function GetHouseStatus(house, completedChapters, currentModel)
	if not house then
		return "LOCKED", Color3.fromRGB(255, 0, 0)
	end

	if currentModel and house.ModelName == currentModel then
		return "ACTIVE", Color3.fromRGB(0, 255, 0)
	end

	if completedChapters >= (house.RequiredChapter or 0) then
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
		local completedChapters = GetCompletedChapters()
		local currentModel = GetCurrentHouseModel()
		local statusText, statusColor = GetHouseStatus(house, completedChapters, currentModel)
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

	prisonsBg.Visible = true
	RefreshHouseEntries()

	local currentModel = GetCurrentHouseModel()
	local completedChapters = GetCompletedChapters()
	local defaultHouse = HouseConfig.GetHouseByModel(currentModel) or HouseConfig.GetHouseByChapter(completedChapters)
	if not defaultHouse and #HouseConfig.GetAllHouses() > 0 then
		defaultHouse = HouseConfig.GetAllHouses()[1]
	end

	SelectHouse(defaultHouse)
end

local function ClosePrisons()
	if prisonsBg then
		prisonsBg.Visible = false
	end
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

	prisonsBg.Visible = false
	return true
end

local function TryInitialize()
	if not InitializeUI() then
		return false
	end

	BindButtons()
	return true
end

local function Initialize()
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
		if not child or (child.Name ~= "Prisons" and child.Name ~= "MainGui") then
			return
		end
		task.spawn(function()
			task.wait()
			TryInitialize()
		end)
	end)
end

Initialize()
