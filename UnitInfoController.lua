--[[
=====================================================
脚本名称：UnitInfoController
脚本类型：本地脚本（客户端）
脚本位置：StarterPlayer/StarterPlayerScripts/Controllers/UnitInfoController.lua
=====================================================
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UpgradeConfig"))

local tipsGui = playerGui:WaitForChild("TipsRole", 10)
if not tipsGui then
	warn("[UnitInfoController] 未找到 TipsRole 界面")
	return
end

local tipsBg = tipsGui:WaitForChild("TipsBg", 5)
if not tipsBg then
	warn("[UnitInfoController] 未找到 TipsBg 节点")
	return
end

local icon = nil
local iconBg = tipsBg:FindFirstChild("IconBg")
if iconBg then
	icon = iconBg:FindFirstChild("Icon")
end

local atkLabel = tipsBg:FindFirstChild("ATK")
local hpLabel = tipsBg:FindFirstChild("HP")
local nameLabel = tipsBg:FindFirstChild("Name")
local qualityLabel = tipsBg:FindFirstChild("Quality")
local rangeLabel = tipsBg:FindFirstChild("Range")
local levelLabel = tipsBg:FindFirstChild("Level")

tipsBg.Visible = false

local CLICK_MOVE_PX_MOUSE = 8
local CLICK_MOVE_PX_TOUCH = 18

local clickState = {
	active = false,
	moved = false,
	startPos = nil,
	unitModel = nil,
	inputType = nil,
	touch = nil,
}


local upgradeMultipliers = {
	AttackMultiplier = 1,
	HealthMultiplier = 1,
	AttackSpeedMultiplier = 1,
	MoveSpeedMultiplier = 1,
}

local upgradeDataBound = false

local function ApplyUpgradeEntries(entries)
	if type(entries) ~= "table" then
		return
	end

	local ratioByType = {}
	for _, typeId in ipairs(UpgradeConfig.GetTypeIds()) do
		ratioByType[typeId] = 0
	end

	for _, entry in ipairs(entries) do
		local typeId = tonumber(entry and entry.TypeId)
		if typeId then
			ratioByType[typeId] = math.max(0, tonumber(entry.CurrentBonusRatio) or 0)
		end
	end

	upgradeMultipliers.AttackMultiplier = 1 + (ratioByType[UpgradeConfig.TYPE.ATTACK] or 0)
	upgradeMultipliers.HealthMultiplier = 1 + (ratioByType[UpgradeConfig.TYPE.HEALTH] or 0)
	upgradeMultipliers.AttackSpeedMultiplier = 1 + (ratioByType[UpgradeConfig.TYPE.ATTACK_SPEED] or 0)
	upgradeMultipliers.MoveSpeedMultiplier = 1 + (ratioByType[UpgradeConfig.TYPE.MOVE_SPEED] or 0)
end

local function BindUpgradeDataEvents()
	if upgradeDataBound then
		return true
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		return false
	end

	local upgradeEvents = eventsFolder:WaitForChild("UpgradeEvents", 10)
	if not upgradeEvents then
		return false
	end

	local upgradeDataEvent = upgradeEvents:FindFirstChild("UpgradeData")
	local requestUpgradeDataEvent = upgradeEvents:FindFirstChild("RequestUpgradeData")

	if not (upgradeDataEvent and upgradeDataEvent:IsA("RemoteEvent")) then
		return false
	end

	upgradeDataEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			ApplyUpgradeEntries(payload.Entries)
		end
	end)
	upgradeDataBound = true

	if requestUpgradeDataEvent and requestUpgradeDataEvent:IsA("RemoteEvent") then
		requestUpgradeDataEvent:FireServer()
	end

	return true
end

local function IsRemovalMode()
	local removalController = _G.RemovalController
	if removalController and removalController.IsRemovalMode then
		return removalController.IsRemovalMode()
	end
	return false
end

local function GetQualityColor(quality)
	local colors = (GameConfig.UI and GameConfig.UI.QualityColors) or {}
	return colors[quality] or colors.Common or Color3.fromRGB(225, 225, 225)
end

local function FindUnitModelFromInstance(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and current:GetAttribute("UnitId") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function GetUnitModelAtScreenPos(screenPos)
	if not camera then
		return nil
	end

	local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = player.Character and { player.Character } or {}

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if not result then
		return nil
	end

	return FindUnitModelFromInstance(result.Instance)
end

local function HideTips()
	if tipsBg.Visible then
		tipsBg.Visible = false
	end
end

local function ResetClickState()
	clickState.active = false
	clickState.moved = false
	clickState.startPos = nil
	clickState.unitModel = nil
	clickState.inputType = nil
	clickState.touch = nil
end

local function UpdateClickMoved(currentPos)
	if not clickState.active or clickState.moved or not clickState.startPos then
		return
	end

	local threshold = CLICK_MOVE_PX_MOUSE
	if clickState.inputType == Enum.UserInputType.Touch then
		threshold = CLICK_MOVE_PX_TOUCH
	end

	if (currentPos - clickState.startPos).Magnitude >= threshold then
		clickState.moved = true
		HideTips()
	end
end

local function ShowUnitInfo(unitModel)
	local unitId = unitModel:GetAttribute("UnitId")
	if not unitId then
		return
	end

	unitId = tostring(unitId)
	local level = tonumber(unitModel:GetAttribute("Level")) or 1
	local unitData = UnitConfig.GetUnitById(unitId)
	if not unitData then
		return
	end

	local rebirthAttackBonusRate = math.max(0, tonumber(player:GetAttribute("RebirthAttackBonusRate")) or 0)
	local attackMultiplier = (upgradeMultipliers.AttackMultiplier or 1) + rebirthAttackBonusRate
	local attack = UnitConfig.CalculateAttack(unitId, level) * attackMultiplier
	attack = math.max(1, math.ceil(attack - 1e-6))

	local health = UnitConfig.CalculateHealth(unitId, level) * (upgradeMultipliers.HealthMultiplier or 1)
	health = math.max(1, math.floor(health + 0.5))

	local humanoid = unitModel:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MaxHealth > 0 then
		health = math.max(health, math.floor(humanoid.MaxHealth + 0.5))
	end

	if icon and icon:IsA("ImageLabel") then
		icon.Image = unitData.Icon or "rbxassetid://0"
	end
	if atkLabel and atkLabel:IsA("TextLabel") then
		atkLabel.Text = tostring(attack)
	end
	if hpLabel and hpLabel:IsA("TextLabel") then
		hpLabel.Text = tostring(health)
	end
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = unitData.Name or unitId
	end
	if qualityLabel and qualityLabel:IsA("TextLabel") then
		local quality = unitData.Quality or "Common"
		qualityLabel.Text = quality
		qualityLabel.TextColor3 = GetQualityColor(quality)
	end
	if rangeLabel and rangeLabel:IsA("TextLabel") then
		local isRanged = UnitConfig.IsRangedUnit(unitId)
		rangeLabel.Text = isRanged and UnitConfig.UnitType.RANGED or UnitConfig.UnitType.MELEE
	end
	if levelLabel and levelLabel:IsA("TextLabel") then
		levelLabel.Text = "Lv." .. tostring(level)
	end

	tipsBg.Visible = true
end

-- Pull upgrade data once so popup stats include real-time nurture bonuses.
task.spawn(function()
	local attempts = 0
	while attempts < 6 and not BindUpgradeDataEvents() do
		attempts += 1
		task.wait(2)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch
	then
		return
	end

	if IsRemovalMode() then
		ResetClickState()
		HideTips()
		return
	end

	if clickState.active then
		return
	end

	clickState.active = true
	clickState.moved = false
	clickState.inputType = input.UserInputType
	clickState.startPos = Vector2.new(input.Position.X, input.Position.Y)
	if input.UserInputType == Enum.UserInputType.Touch then
		clickState.touch = input
	end

	if not gameProcessed then
		clickState.unitModel = GetUnitModelAtScreenPos(input.Position)
	else
		clickState.unitModel = nil
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if IsRemovalMode() then
		ResetClickState()
		HideTips()
		return
	end

	if not clickState.active then
		return
	end

	if clickState.inputType == Enum.UserInputType.MouseButton1
		and input.UserInputType == Enum.UserInputType.MouseMovement
	then
		UpdateClickMoved(Vector2.new(input.Position.X, input.Position.Y))
		return
	end

	if clickState.inputType == Enum.UserInputType.Touch
		and input.UserInputType == Enum.UserInputType.Touch
		and clickState.touch == input
	then
		UpdateClickMoved(Vector2.new(input.Position.X, input.Position.Y))
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if IsRemovalMode() then
		ResetClickState()
		HideTips()
		return
	end

	if not clickState.active then
		return
	end

	if input.UserInputType ~= clickState.inputType then
		return
	end

	if clickState.inputType == Enum.UserInputType.Touch and clickState.touch ~= input then
		return
	end

	local moved = clickState.moved
	local startPos = clickState.startPos
	if not moved and startPos then
		local threshold = CLICK_MOVE_PX_MOUSE
		if clickState.inputType == Enum.UserInputType.Touch then
			threshold = CLICK_MOVE_PX_TOUCH
		end
		local endPos = Vector2.new(input.Position.X, input.Position.Y)
		if (endPos - startPos).Magnitude >= threshold then
			moved = true
		end
	end
	local unitModel = clickState.unitModel
	ResetClickState()

	if moved then
		return
	end

	if unitModel then
		ShowUnitInfo(unitModel)
	else
		HideTips()
	end
end)
