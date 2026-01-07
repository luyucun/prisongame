--[[
脚本名称: VipChatController
脚本类型: LocalScript (客户端控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/Controllers/VipChatController
版本: V5.5
职责: TextChatService模式下的VIP聊天前缀显示
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
	return
end

local VipConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("VipConfig"))

pcall(function()
	local windowConfig = TextChatService.ChatWindowConfiguration
	if windowConfig then
		windowConfig.RichText = true
	end
end)

local original = nil
pcall(function()
	original = TextChatService.OnIncomingMessage
end)

TextChatService.OnIncomingMessage = function(message)
	local properties = nil
	if original then
		properties = original(message)
	end
	if not properties then
		properties = Instance.new("TextChatMessageProperties")
	end

	local textSource = message and message.TextSource
	if textSource then
		local player = Players:GetPlayerByUserId(textSource.UserId)
		if player and player:GetAttribute("VipPurchased") == true then
			local prefix = message.PrefixText or ""
			if prefix ~= "" and not string.find(prefix, VipConfig.TAG_TEXT, 1, true) then
				properties.PrefixText = string.format(
					"<font color=\"#FFD700\">%s</font> %s",
					VipConfig.TAG_TEXT,
					prefix
				)
			end
		end
	end

	return properties
end
