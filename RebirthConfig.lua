--[[
脚本名称: RebirthConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/RebirthConfig
版本: V7.0
]]

local RebirthConfig = {}

RebirthConfig.Levels = {
	{
		RebirthCount = 1,
		RequiredCoins = 1000,
		RequiredUnitId = "10001",
		RequiredUnitCount = 5,
		RewardCoins = 500,
		RewardUnitId = "10002",
		RewardUnitCount = 3,
		CoinBonusRate = 0.2,
		AttackBonusRate = 0.2,
		UnlockUnitId = "10005",
		UnlockHouseModel = "PrisonLv2",
	},
	{
		RebirthCount = 2,
		RequiredCoins = 2000,
		RequiredUnitId = "10002",
		RequiredUnitCount = 5,
		RewardCoins = 1000,
		RewardUnitId = "10003",
		RewardUnitCount = 3,
		CoinBonusRate = 0.4,
		AttackBonusRate = 0.4,
		UnlockUnitId = "10006",
		UnlockHouseModel = "PrisonLv2",
	},
	{
		RebirthCount = 3,
		RequiredCoins = 3000,
		RequiredUnitId = "10003",
		RequiredUnitCount = 5,
		RewardCoins = 2000,
		RewardUnitId = "10004",
		RewardUnitCount = 3,
		CoinBonusRate = 0.6,
		AttackBonusRate = 0.6,
		UnlockUnitId = "10007",
		UnlockHouseModel = "PrisonLv2",
	},
	{
		RebirthCount = 4,
		RequiredCoins = 4000,
		RequiredUnitId = "10004",
		RequiredUnitCount = 5,
		RewardCoins = 3000,
		RewardUnitId = "10005",
		RewardUnitCount = 3,
		CoinBonusRate = 0.8,
		AttackBonusRate = 0.8,
		UnlockUnitId = "10008",
		UnlockHouseModel = "PrisonLv2",
	},
	{
		RebirthCount = 5,
		RequiredCoins = 5000,
		RequiredUnitId = "10005",
		RequiredUnitCount = 5,
		RewardCoins = 5000,
		RewardUnitId = "10006",
		RewardUnitCount = 3,
		CoinBonusRate = 1.0,
		AttackBonusRate = 1.0,
		UnlockUnitId = "10009",
		UnlockHouseModel = "PrisonLv3",
	},
	{
		RebirthCount = 6,
		RequiredCoins = 6000,
		RequiredUnitId = "10006",
		RequiredUnitCount = 8,
		RewardCoins = 8000,
		RewardUnitId = "10007",
		RewardUnitCount = 3,
		CoinBonusRate = 1.2,
		AttackBonusRate = 1.2,
		UnlockUnitId = "10010",
		UnlockHouseModel = "PrisonLv3",
	},
	{
		RebirthCount = 7,
		RequiredCoins = 7000,
		RequiredUnitId = "10007",
		RequiredUnitCount = 8,
		RewardCoins = 12000,
		RewardUnitId = "10008",
		RewardUnitCount = 3,
		CoinBonusRate = 1.4,
		AttackBonusRate = 1.4,
		UnlockUnitId = "10011",
		UnlockHouseModel = "PrisonLv3",
	},
	{
		RebirthCount = 8,
		RequiredCoins = 8000,
		RequiredUnitId = "10008",
		RequiredUnitCount = 8,
		RewardCoins = 15000,
		RewardUnitId = "10009",
		RewardUnitCount = 3,
		CoinBonusRate = 1.6,
		AttackBonusRate = 1.6,
		UnlockUnitId = "10012",
		UnlockHouseModel = "PrisonLv3",
	},
	{
		RebirthCount = 9,
		RequiredCoins = 9000,
		RequiredUnitId = "10009",
		RequiredUnitCount = 8,
		RewardCoins = 20000,
		RewardUnitId = "10010",
		RewardUnitCount = 3,
		CoinBonusRate = 1.8,
		AttackBonusRate = 1.8,
		UnlockUnitId = "10013",
		UnlockHouseModel = "PrisonLv3",
	},
	{
		RebirthCount = 10,
		RequiredCoins = 10000,
		RequiredUnitId = "10010",
		RequiredUnitCount = 8,
		RewardCoins = 25000,
		RewardUnitId = "10011",
		RewardUnitCount = 3,
		CoinBonusRate = 2.0,
		AttackBonusRate = 2.0,
		UnlockUnitId = "10014",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 11,
		RequiredCoins = 11000,
		RequiredUnitId = "10011",
		RequiredUnitCount = 12,
		RewardCoins = 30000,
		RewardUnitId = "10012",
		RewardUnitCount = 3,
		CoinBonusRate = 2.2,
		AttackBonusRate = 2.2,
		UnlockUnitId = "10015",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 12,
		RequiredCoins = 12000,
		RequiredUnitId = "10012",
		RequiredUnitCount = 12,
		RewardCoins = 40000,
		RewardUnitId = "10013",
		RewardUnitCount = 3,
		CoinBonusRate = 2.4,
		AttackBonusRate = 2.4,
		UnlockUnitId = "10016",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 13,
		RequiredCoins = 13000,
		RequiredUnitId = "10013",
		RequiredUnitCount = 12,
		RewardCoins = 50000,
		RewardUnitId = "10014",
		RewardUnitCount = 3,
		CoinBonusRate = 2.6,
		AttackBonusRate = 2.6,
		UnlockUnitId = "10017",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 14,
		RequiredCoins = 14000,
		RequiredUnitId = "10014",
		RequiredUnitCount = 12,
		RewardCoins = 60000,
		RewardUnitId = "10015",
		RewardUnitCount = 3,
		CoinBonusRate = 2.8,
		AttackBonusRate = 2.8,
		UnlockUnitId = "10018",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 15,
		RequiredCoins = 15000,
		RequiredUnitId = "10015",
		RequiredUnitCount = 12,
		RewardCoins = 70000,
		RewardUnitId = "10016",
		RewardUnitCount = 3,
		CoinBonusRate = 3.0,
		AttackBonusRate = 3.0,
		UnlockUnitId = "10019",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 16,
		RequiredCoins = 16000,
		RequiredUnitId = "10016",
		RequiredUnitCount = 15,
		RewardCoins = 80000,
		RewardUnitId = "10017",
		RewardUnitCount = 3,
		CoinBonusRate = 3.2,
		AttackBonusRate = 3.2,
		UnlockUnitId = "10020",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 17,
		RequiredCoins = 17000,
		RequiredUnitId = "10017",
		RequiredUnitCount = 15,
		RewardCoins = 90000,
		RewardUnitId = "10018",
		RewardUnitCount = 3,
		CoinBonusRate = 3.4,
		AttackBonusRate = 3.4,
		UnlockUnitId = "10021",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 18,
		RequiredCoins = 18000,
		RequiredUnitId = "10018",
		RequiredUnitCount = 15,
		RewardCoins = 100000,
		RewardUnitId = "10019",
		RewardUnitCount = 3,
		CoinBonusRate = 3.6,
		AttackBonusRate = 3.6,
		UnlockUnitId = "10022",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 19,
		RequiredCoins = 19000,
		RequiredUnitId = "10019",
		RequiredUnitCount = 15,
		RewardCoins = 110000,
		RewardUnitId = "10020",
		RewardUnitCount = 3,
		CoinBonusRate = 3.8,
		AttackBonusRate = 3.8,
		UnlockUnitId = "10023",
		UnlockHouseModel = "PrisonLv4",
	},
	{
		RebirthCount = 20,
		RequiredCoins = 20000,
		RequiredUnitId = "10020",
		RequiredUnitCount = 15,
		RewardCoins = 120000,
		RewardUnitId = "10021",
		RewardUnitCount = 3,
		CoinBonusRate = 4.0,
		AttackBonusRate = 4.0,
		UnlockUnitId = "10024",
		UnlockHouseModel = "PrisonLv4",
	},
}

local unlockUnitToRebirth = nil
local unlockHouseToRebirth = nil

local function BuildUnlockIndex()
	if unlockUnitToRebirth and unlockHouseToRebirth then
		return
	end

	unlockUnitToRebirth = {}
	unlockHouseToRebirth = {}

	for _, config in ipairs(RebirthConfig.Levels) do
		local rebirthCount = tonumber(config.RebirthCount) or 0
		local unlockUnitId = tostring(config.UnlockUnitId or "")
		local unlockHouseModel = tostring(config.UnlockHouseModel or "")

		if unlockUnitId ~= "" and unlockUnitToRebirth[unlockUnitId] == nil then
			unlockUnitToRebirth[unlockUnitId] = rebirthCount
		end

		if unlockHouseModel ~= "" and unlockHouseToRebirth[unlockHouseModel] == nil then
			unlockHouseToRebirth[unlockHouseModel] = rebirthCount
		end
	end
end

function RebirthConfig.GetAllLevels()
	return RebirthConfig.Levels
end

function RebirthConfig.GetMaxRebirthCount()
	return #RebirthConfig.Levels
end

function RebirthConfig.GetConfigByCount(rebirthCount)
	local index = math.floor(tonumber(rebirthCount) or 0)
	if index < 1 then
		return nil
	end
	return RebirthConfig.Levels[index]
end

function RebirthConfig.GetNextConfig(currentRebirthCount)
	local current = math.floor(tonumber(currentRebirthCount) or 0)
	return RebirthConfig.GetConfigByCount(current + 1)
end

function RebirthConfig.GetEffectiveBonusRates(rebirthCount)
	local count = math.floor(tonumber(rebirthCount) or 0)
	if count <= 0 then
		return 0, 0
	end

	local maxCount = RebirthConfig.GetMaxRebirthCount()
	if count > maxCount then
		count = maxCount
	end

	local config = RebirthConfig.GetConfigByCount(count)
	if not config then
		return 0, 0
	end

	return tonumber(config.CoinBonusRate) or 0, tonumber(config.AttackBonusRate) or 0
end

function RebirthConfig.GetRequiredRebirthForUnit(unitId)
	BuildUnlockIndex()
	local key = tostring(unitId or "")
	if key == "" then
		return 0
	end
	return tonumber(unlockUnitToRebirth[key]) or 0
end

function RebirthConfig.GetRequiredRebirthForHouse(modelName)
	BuildUnlockIndex()
	local key = tostring(modelName or "")
	if key == "" then
		return 0
	end
	return tonumber(unlockHouseToRebirth[key]) or 0
end

return RebirthConfig
