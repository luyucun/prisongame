--[[
脚本名称: DailyRewardConfig
脚本类型: ModuleScript (配置模块)
脚本位置: ReplicatedStorage/Config/DailyRewardConfig
版本: V5.3
]]

local DailyRewardConfig = {}

DailyRewardConfig.Rewards = {
    { UnitId = "10002", Count = 1, Weight = 48 },
    { UnitId = "10004", Count = 1, Weight = 40 },
    { UnitId = "10008", Count = 1, Weight = 9 },
    { UnitId = "10013", Count = 1, Weight = 3 },
}

function DailyRewardConfig.GetRewards()
    return DailyRewardConfig.Rewards
end

function DailyRewardConfig.RollReward()
    local totalWeight = 0
    for _, reward in ipairs(DailyRewardConfig.Rewards) do
        local weight = tonumber(reward.Weight) or 0
        if weight > 0 then
            totalWeight = totalWeight + weight
        end
    end

    if totalWeight <= 0 then
        return nil
    end

    local roll = math.random(1, totalWeight)
    local current = 0
    for _, reward in ipairs(DailyRewardConfig.Rewards) do
        local weight = tonumber(reward.Weight) or 0
        if weight > 0 then
            current = current + weight
            if roll <= current then
                return reward
            end
        end
    end

    return nil
end

return DailyRewardConfig
