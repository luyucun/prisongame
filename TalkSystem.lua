--[[
脚本名称: TalkSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/TalkSystem
版本: V4.5
]]

local TalkSystem = {}

-- 服务
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- 配置与依赖
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local TalkConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("TalkConfig"))
local DataManager = require(ServerScriptService.Core.DataManager)
local CurrencySystem = require(ServerScriptService.Systems.CurrencySystem)

local talkEvents = nil

-- ==================== 私有方法 ====================

local function EnsureEventsExist()
	if talkEvents then
		return talkEvents
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end

	local talkFolder = eventsFolder:FindFirstChild("TalkEvents")
	if not talkFolder then
		talkFolder = Instance.new("Folder")
		talkFolder.Name = "TalkEvents"
		talkFolder.Parent = eventsFolder
	end

	local eventNames = {
		"RequestTalkList",   -- 客户端->服务端：请求对话列表
		"TalkList",          -- 服务端->客户端：下发对话列表
		"SelectTalkOption",  -- 客户端->服务端：选择对话选项
		"TalkResponse",      -- 服务端->客户端：返回对话结果
	}

	talkEvents = {}
	for _, name in ipairs(eventNames) do
		local event = talkFolder:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = talkFolder
		end
		talkEvents[name] = event
	end

	return talkEvents
end

local function GetPlayerTalkData(player)
	local playerData = DataManager.GetPlayerData(player)
	if not playerData then
		return { CompletedTalks = {} }
	end

	if not playerData.TalkData then
		playerData.TalkData = {
			CompletedTalks = {},
		}
	end

	if not playerData.TalkData.CompletedTalks then
		playerData.TalkData.CompletedTalks = {}
	end

	return playerData.TalkData
end

local function IsTalkCompleted(player, talkId)
	local talkData = GetPlayerTalkData(player)
	return talkData.CompletedTalks[talkId] == true or talkData.CompletedTalks[tostring(talkId)] == true
end

local function MarkTalkCompleted(player, talkId)
	local talkData = GetPlayerTalkData(player)
	talkData.CompletedTalks[talkId] = true
	DataManager.SavePlayerDataThrottled(player)
end

local function CheckCondition(player, option)
	local condition = option.Condition
	if not condition or condition.Type == TalkConfig.ConditionType.DEFAULT then
		return true
	end

	if condition.Type == TalkConfig.ConditionType.TALK_COMPLETED then
		local targetId = tonumber(condition.TalkId)
		if not targetId then
			return false
		end
		return IsTalkCompleted(player, targetId)
	end

	if condition.Type == TalkConfig.ConditionType.CHAPTER_COMPLETED then
		local chapter = tonumber(condition.Chapter) or 1
		local completed = DataManager.GetCompletedChapters(player) or 0
		return completed >= chapter
	end

	return true
end

local function BuildTalkList(player)
	local list = {}
	for _, option in pairs(TalkConfig.Options) do
		if option and option.Enabled ~= false then
			local talkId = tonumber(option.Id)
			if talkId then
				if option.OneTime and IsTalkCompleted(player, talkId) then
					continue
				end
				if CheckCondition(player, option) then
					table.insert(list, {
						Id = talkId,
						Text = option.OptionText or "",
						Sort = option.Sort or talkId,
					})
				end
			end
		end
	end

	table.sort(list, function(a, b)
		if a.Sort == b.Sort then
			return a.Id < b.Id
		end
		return a.Sort < b.Sort
	end)

	return list
end

local function SendTalkList(player)
	local events = EnsureEventsExist()
	if not events.TalkList then
		return
	end
	local list = BuildTalkList(player)
	events.TalkList:FireClient(player, list)
end

local function HandleRequestTalkList(player)
	if not player or not player.Parent then
		return
	end
	SendTalkList(player)
end

local function HandleSelectOption(player, talkId)
	if not player or not player.Parent then
		return
	end

	local option = TalkConfig.GetOption(talkId)
	local events = EnsureEventsExist()
	if not option then
		if events.TalkResponse then
			events.TalkResponse:FireClient(player, false, "INVALID", talkId, {})
		end
		return
	end

	if option.Enabled == false or not CheckCondition(player, option) then
		if events.TalkResponse then
			events.TalkResponse:FireClient(player, false, "CONDITION", talkId, {})
		end
		return
	end

	local completed = option.OneTime and IsTalkCompleted(player, option.Id)
	if option.RewardCoins and option.RewardCoins > 0 and not completed then
		CurrencySystem.AddCoins(player, option.RewardCoins, "对话奖励")
	end

	if option.OneTime and not completed then
		MarkTalkCompleted(player, option.Id)
	end

	if events.TalkResponse then
		local action = option.Action or TalkConfig.OptionType.DIALOG
		local dialogues = option.Dialogues or {}
		events.TalkResponse:FireClient(player, true, action, option.Id, dialogues)
	end
end

-- ==================== 公共接口 ====================

function TalkSystem.Initialize()
	print("[TalkSystem] 初始化对话系统...")

	EnsureEventsExist()

	if talkEvents.RequestTalkList then
		talkEvents.RequestTalkList.OnServerEvent:Connect(HandleRequestTalkList)
	end

	if talkEvents.SelectTalkOption then
		talkEvents.SelectTalkOption.OnServerEvent:Connect(function(player, talkId)
			HandleSelectOption(player, talkId)
		end)
	end

	print("[TalkSystem] 对话系统初始化完成")
	return true
end

return TalkSystem
