--[[
脚本名称: VipConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/VipConfig
版本: V5.5
职责: VIP通行证配置与加成规则
]]

local VipConfig = {}

VipConfig.GAMEPASS_ID = 1661725726
VipConfig.COIN_BONUS_RATE = 0.5 -- +50%
VipConfig.TAG_TEXT = "[VIP]"
VipConfig.TAG_COLOR = Color3.fromRGB(255, 215, 0)

function VipConfig.GetBonusRate()
	return VipConfig.COIN_BONUS_RATE
end

function VipConfig.CalculateBonusAmount(baseAmount)
	local amount = tonumber(baseAmount) or 0
	if amount <= 0 then
		return 0, 0
	end

	local total = math.ceil(amount * (1 + VipConfig.COIN_BONUS_RATE))
	local bonus = math.max(0, total - amount)
	return total, bonus
end

return VipConfig
