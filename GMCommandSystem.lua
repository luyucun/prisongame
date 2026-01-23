--[[
脚本名称: GMCommandSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/GMCommandSystem
]]

--[[
GM命令系统模块
职责:
1. 解析和执行GM命令
2. 提供开发测试用的命令接口
3. 支持权限验证(可选)

支持的命令:
- /addunit <unitId> [count] : 添加兵种到背包
- /removeunit <instanceId> : 删除指定实例的兵种
- /clearunits : 清空背包
- /listunits : 列出背包中的所有兵种
- /addcoins <amount> : 添加金币
- /clearcoins : 清空金币
- /unitlist : 列出所有可用的兵种ID
- /mainprogress : 查看主线通关打点(第几章第几关)
- /addskill <skillId> [count] : 添加技能到背包 (V3.0)
- /removeskill <skillId> [count] : 移除技能 (V3.0)
- /clearskills : 清空技能背包 (V3.0)
- /listskills : 列出技能背包 (V3.0)
- /skilllist : 列出所有可用技能 (V3.0)
- /triggerguide <guideId> : 触发指定引导 (V3.5)
- /resetguide <guideId> : 重置指定引导 (V3.5)
- /resetallguides : 重置所有引导 (V3.5)
- /listguides : 列出所有引导状态 (V3.5)
- /resetdailyreward : 重置今日免费奖励领取状态 (V5.3)
- /resetstarterpack : 重置新手礼包购买状态 (V5.4)
- /resetvip : 重置VIP礼包购买状态 (V5.5)
- /addhandcuff <count> : 添加手铐道具 (V6.0)
- /resetonlinereward : Reset online reward data (V6.1)
]]

local GMCommandSystem = {}

-- 引用服务
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local BattleConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("BattleConfig"))
local SkillConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SkillConfig"))  -- V3.0新增
local GuideConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GuideConfig"))  -- V3.5新增
local DataManager = require(ServerScriptService.Core.DataManager)
local InventorySystem = require(ServerScriptService.Systems.InventorySystem)
local CurrencySystem = require(ServerScriptService.Systems.CurrencySystem)
local PlacementSystem = nil  -- 延迟加载，避免循环依赖
local BattleTestSystem = nil  -- 延迟加载，避免循环依赖
local BattleManager = nil     -- 延迟加载，避免循环依赖
local IdleCoinSystem = nil    -- V2.6新增：延迟加载，避免循环依赖
local SkillSystem = nil       -- V3.0新增：延迟加载，避免循环依赖
local GuideSystem = nil       -- V3.5新增：延迟加载，避免循环依赖
local SevenDaysSystem = nil   -- V4.8新增：延迟加载，避免循环依赖
local DailyRewardSystem = nil -- V5.3新增：延迟加载，避免循环依赖
local StarterPackSystem = nil -- V5.4新增：延迟加载，避免循环依赖
local VipSystem = nil         -- V5.5新增：延迟加载，避免循环依赖
local LimitPrisonerSystem = nil -- V6.0新增：延迟加载，避免循环依赖

-- ==================== 配置 ====================

-- GM命令前缀
local COMMAND_PREFIX = "/"

-- 是否启用权限检查(测试期间可以设为false让所有人都能用)
local ENABLE_PERMISSION_CHECK = false

-- GM管理员用户ID列表(如果启用权限检查)
local GM_ADMIN_USER_IDS = {
    -- 在这里添加管理员的UserId
    -- 例如: 123456789,
}

-- ==================== 私有函数 ====================

--[[
检查玩家是否有GM权限
@param player Player - 玩家对象
@return boolean - 是否有权限
]]
local function HasGMPermission(player)
    -- 如果禁用权限检查,所有人都可以使用
    if not ENABLE_PERMISSION_CHECK then
        return true
    end

    -- 检查是否在管理员列表中
    for _, adminId in ipairs(GM_ADMIN_USER_IDS) do
        if player.UserId == adminId then
            return true
        end
    end

    return false
end

--[[
向玩家发送消息
@param player Player - 玩家对象
@param message string - 消息内容
]]
local function SendMessage(player, message)
    -- 使用聊天系统发送消息(需要TextChatService或旧的Chat服务)
    -- 这里使用SystemMessage方式
    local success, err = pcall(function()
        -- 尝试使用新的TextChatService
        local TextChatService = game:GetService("TextChatService")
        local textChannel = TextChatService:FindFirstChild("TextChannels"):FindFirstChild("RBXGeneral")
        if textChannel then
            textChannel:DisplaySystemMessage("[GM] " .. message)
        end
    end)

    -- 如果失败,打印到控制台
    if not success then
        print(string.format("[GM] %s: %s", player.Name, message))
    end
end

--[[
分割字符串
@param str string - 要分割的字符串
@param delimiter string - 分隔符
@return table - 分割后的数组
]]
local function SplitString(str, delimiter)
    local result = {}
    local pattern = string.format("([^%s]+)", delimiter)
    for match in string.gmatch(str, pattern) do
        table.insert(result, match)
    end
    return result
end

-- ==================== 命令处理函数 ====================

--[[
命令: /addunit <unitId> [count]
添加兵种到背包
]]
local function CMD_AddUnit(player, args)
    if #args < 1 then
        SendMessage(player, "用法: /addunit <unitId> [count]")
        SendMessage(player, "例如: /addunit Noob 3")
        return
    end

    local unitId = tostring(args[1])
    local count = tonumber(args[2]) or 1

    -- 验证兵种ID
    if not UnitConfig.IsValidUnit(unitId) then
        SendMessage(player, "错误: 无效的兵种ID: " .. unitId)
        SendMessage(player, "使用 /unitlist 查看所有可用的兵种")
        return
    end

    -- 验证数量
    if count < 1 or count > 100 then
        SendMessage(player, "错误: 数量必须在1-100之间")
        return
    end

    -- 添加兵种
    local successCount = 0
    for i = 1, count do
        local success, result = InventorySystem.AddUnit(player, unitId)
        if success then
            successCount = successCount + 1
        end
    end

    if successCount > 0 then
        SendMessage(player, string.format("成功添加 %d 个 %s", successCount, unitId))
        -- 显示背包信息
        local inventoryInfo = InventorySystem.PrintInventory(player)
        SendMessage(player, inventoryInfo)
    else
        SendMessage(player, "添加失败")
    end
end

--[[
命令: /listunits
列出背包中的所有兵种
]]
local function CMD_ListUnits(player, args)
    local inventoryInfo = InventorySystem.PrintInventory(player)
    SendMessage(player, inventoryInfo)
end

--[[
命令: /clearunits
清空背包
]]
local function CMD_ClearUnits(player, args)
    local success = InventorySystem.ClearInventory(player)
    if success then
        SendMessage(player, "背包已清空")
    else
        SendMessage(player, "清空失败")
    end
end

--[[
命令: /unitlist
列出所有可用的兵种ID
]]
local function CMD_UnitList(player, args)
    local allUnits = UnitConfig.GetAllUnits()
    local message = "可用的兵种列表:\n"

    for unitId, unitData in pairs(allUnits) do
        -- 修复：确保unitId是字符串类型
        local unitIdStr = tostring(unitId)
        message = message .. string.format(
            "  - %s (等级%d, %s, %d金币)\n",
            unitIdStr,
            unitData.BaseLevel,
            unitData.Type,
            unitData.Price
        )
    end

    SendMessage(player, message)
end

--[[
命令: /addcoins <amount>
添加金币
]]
local function CMD_AddCoins(player, args)
    if #args < 1 then
        SendMessage(player, "用法: /addcoins <amount>")
        return
    end

    local amount = tonumber(args[1])
    if not amount then
        SendMessage(player, "错误: 金额必须是数字")
        return
    end

    local success = CurrencySystem.AddCoinsFromGM(player, amount)
    if success then
        local currentCoins = DataManager.GetCurrency(player, GameConfig.CurrencyType.COINS)
        SendMessage(player, string.format("成功添加 %d 金币,当前金币: %d", amount, currentCoins))
    else
        SendMessage(player, "添加金币失败")
    end
end

--[[
命令: /clearcoins
清空金币
]]
local function CMD_ClearCoins(player, args)
    local currentCoins = DataManager.GetCurrency(player, GameConfig.CurrencyType.COINS)

    if currentCoins <= 0 then
        SendMessage(player, "当前金币已经是0了")
        return
    end

    -- 使用负数添加来清空金币
    local success = CurrencySystem.AddCoinsFromGM(player, -currentCoins)
    if success then
        SendMessage(player, string.format("成功清空金币(原金币: %d)", currentCoins))
    else
        SendMessage(player, "清空金币失败")
    end
end

--[[
命令: /iconpreload
检查图标预加载状态
]]
local function CMD_IconPreload(player, args)
    if _G.IconPreloadComplete then
        local stats = _G.IconPreloadStats
        if stats then
            SendMessage(player, string.format("✅ 图标预加载已完成\n总数: %d, 成功: %d, 失败: %d\n耗时: %.2f 秒",
                stats.Total, stats.Success, stats.Failed, stats.Duration))
        else
            SendMessage(player, "✅ 图标预加载已完成(无详细统计)")
        end
    else
        SendMessage(player, "⏳ 图标预加载尚未完成或失败")
    end
end

--[[
命令: /help
显示帮助信息
]]
local function CMD_Help(player, args)
    local helpText = [[
=== GM命令帮助 ===
兵种管理:
/addunit <unitId> [count] - 添加兵种(默认1个)
/listunits - 查看背包
/clearunits - 清空背包
/unitlist - 查看所有可用兵种

放置管理:
/listplaced - 查看已放置的兵种
/clearplaced - 清除所有已放置的兵种

战斗测试:
/battletest - 快速开始测试战斗(自动生成兵种)
/spawnunit <team> <unitId> <level> <pos> - 生成测试兵种
  team: attack/defense, level: 1-3, pos: 1-5
/startbattle - 开始战斗
/stopbattle - 强制结束战斗
/clearbattle - 清理战场

货币管理:
/addcoins <amount> - 添加金币
/clearcoins - 清空金币

挂机金币(V2.6):
/addidlecoins [minutes] - 添加挂机金币(默认60分钟)
/idlecoins - 查看挂机金币状态

技能管理(V3.0):
/addskill <skillId> [count] - 添加技能(默认1个)
/removeskill <skillId> [count] - 移除技能
/listskills - 查看技能背包
/clearskills - 清空技能背包
/skilllist - 查看所有可用技能

新手引导(V3.5):
/triggerguide <guideId> - 触发指定引导
/resetguide <guideId> - 重置指定引导
/resetallguides - 重置所有引导
/listguides - 查看所有引导状态

数据管理(V2.9):
/resetdata - 重置当前玩家数据(需二次确认)
/mainprogress - 查看主线通关打点(第几章第几关)

系统调试:
/iconpreload - 检查图标预加载状态

七日登录(V4.8):
/unlocknextday - 解锁下一天奖励

每日免费奖励(V5.3):
/resetdailyreward - 重置今日免费奖励领取状态

新手礼包(V5.4):
/resetstarterpack - 重置新手礼包购买状态

VIP礼包(V5.5):
/resetvip - 重置VIP礼包购买状态

其他:
/help - 显示此帮助

提示: 按V键打开战斗测试UI
/addonlinetime <minutes> - add online reward time (V6.1)
/resetonlinereward - reset online reward data (V6.1)
    ]]
    SendMessage(player, helpText)
end

--[[
命令: /mainprogress
查看主线通关打点（第几章第几关）
]]
local function CMD_MainProgress(player, args)
    local progress = DataManager.GetChapterProgress(player)

    local currentChapter = tonumber(progress.CurrentChapter) or 1
    local completedChapters = tonumber(progress.CompletedChapters) or 0
    local maxClearedChapter = tonumber(progress.MaxClearedChapter) or 1
    local maxClearedStage = tonumber(progress.MaxClearedStage) or 0

    SendMessage(player, "=== 主线通关打点 ===")
    SendMessage(player, string.format("当前挑战章节: %d", currentChapter))
    SendMessage(player, string.format("已通关章节数: %d", completedChapters))
    SendMessage(player, string.format("最大通关进度: 第%d章第%d关", maxClearedChapter, maxClearedStage))
end

--[[
命令: /unlocknextday
解锁七日登录奖励的下一天 (V4.8)
]]
local function CMD_UnlockNextDay(player, args)
    if not SevenDaysSystem then
        local systemsFolder = ServerScriptService:FindFirstChild("Systems")
        if systemsFolder then
            local module = systemsFolder:FindFirstChild("SevenDaysSystem")
            if module then
                SevenDaysSystem = require(module)
            end
        end
    end

    if not SevenDaysSystem or not SevenDaysSystem.GMUnlockNextDay then
        SendMessage(player, "错误: SevenDaysSystem未加载")
        return
    end

    local success, message = SevenDaysSystem.GMUnlockNextDay(player)
    if success then
        SendMessage(player, message or "解锁成功")
    else
        SendMessage(player, message or "解锁失败")
    end
end

--[[
命令: /resetdailyreward
重置今日每日免费奖励领取状态 (V5.3)
]]
local function CMD_ResetDailyReward(player, args)
    if not DailyRewardSystem then
        local systemsFolder = ServerScriptService:FindFirstChild("Systems")
        if systemsFolder then
            local module = systemsFolder:FindFirstChild("DailyRewardSystem")
            if module then
                DailyRewardSystem = require(module)
            end
        end
    end

    if not DailyRewardSystem or not DailyRewardSystem.GMResetDailyReward then
        SendMessage(player, "错误: DailyRewardSystem未加载")
        return
    end

    local success, message = DailyRewardSystem.GMResetDailyReward(player)
    if success then
        SendMessage(player, message or "重置成功")
    else
        SendMessage(player, message or "重置失败")
    end
end

--[[
命令: /resetstarterpack
重置新手礼包购买状态 (V5.4)
]]
local function CMD_ResetStarterPack(player, args)
    if not StarterPackSystem then
        local systemsFolder = ServerScriptService:FindFirstChild("Systems")
        if systemsFolder then
            local module = systemsFolder:FindFirstChild("StarterPackSystem")
            if module then
                StarterPackSystem = require(module)
            end
        end
    end

    if not StarterPackSystem or not StarterPackSystem.GMResetStarterPack then
        SendMessage(player, "错误: StarterPackSystem未加载")
        return
    end

    local success, message = StarterPackSystem.GMResetStarterPack(player)
    if success then
        SendMessage(player, message or "重置成功")
    else
        SendMessage(player, message or "重置失败")
    end
end

--[[
命令: /resetvip
重置VIP礼包购买状态 (V5.5)
]]
local function CMD_ResetVip(player, args)
    if not VipSystem then
        local systemsFolder = ServerScriptService:FindFirstChild("Systems")
        if systemsFolder then
            local module = systemsFolder:FindFirstChild("VipSystem")
            if module then
                VipSystem = require(module)
            end
        end
    end

    if not VipSystem or not VipSystem.GMResetVip then
        SendMessage(player, "错误: VipSystem未加载")
        return
    end

    local success, message = VipSystem.GMResetVip(player)
    if success then
        SendMessage(player, message or "重置成功")
    else
        SendMessage(player, message or "重置失败")
    end
end

--[[
命令: /listplaced
查看已放置的兵种 V1.2
]]
local function CMD_ListPlaced(player, args)
    -- 延迟加载PlacementSystem
    if not PlacementSystem then
        PlacementSystem = require(ServerScriptService.Systems.PlacementSystem)
    end

    local placedUnits = PlacementSystem.GetPlacedUnits(player)

    if #placedUnits == 0 then
        SendMessage(player, "当前没有已放置的兵种")
        return
    end

    local message = string.format("已放置的兵种 (共%d个):\n", #placedUnits)
    for _, placedData in ipairs(placedUnits) do
        local unitConfig = UnitConfig.GetUnitById(placedData.UnitId)
        local unitName = unitConfig and unitConfig.Name or placedData.UnitId
        message = message .. string.format("  - %s (位置: %.1f, %.1f, %.1f)\n",
            unitName,
            placedData.Position.X,
            placedData.Position.Y,
            placedData.Position.Z
        )
    end

    SendMessage(player, message)
end

--[[
命令: /clearplaced
清除所有已放置的兵种 V1.2
]]
local function CMD_ClearPlaced(player, args)
    -- 延迟加载PlacementSystem
    if not PlacementSystem then
        PlacementSystem = require(ServerScriptService.Systems.PlacementSystem)
    end

    local count = PlacementSystem.ClearAllPlacedUnits(player)
    SendMessage(player, string.format("已清除 %d 个已放置的兵种", count))
end

--[[
命令: /battletest
快速开始一场测试战斗 V1.5
]]
local function CMD_BattleTest(player, args)
    -- 延迟加载BattleTestSystem和BattleManager
    if not BattleTestSystem then
        BattleTestSystem = require(ServerScriptService.Systems.BattleTestSystem)
    end
    if not BattleManager then
        BattleManager = require(ServerScriptService.Systems.BattleManager)
    end

    -- 创建简单的测试数据：双方各1个1级Noob在位置1
    local attackUnitsData = {
        {UnitId = "Noob", Level = 1, Position = 1}
    }
    local defenseUnitsData = {
        {UnitId = "Noob", Level = 1, Position = 1}
    }

    -- 调用战斗测试系统
    BattleTestSystem.HandleBattleTestRequest(player, attackUnitsData, defenseUnitsData)
    SendMessage(player, "战斗测试已启动！观察Attack位置1和Defense位置1")
end

--[[
命令: /spawnunit <team> <unitId> <level> <position>
在战斗测试区域生成兵种 V1.5
]]
local function CMD_SpawnUnit(player, args)
    if #args < 4 then
        SendMessage(player, "用法: /spawnunit <team> <unitId> <level> <position>")
        SendMessage(player, "例如: /spawnunit attack Noob 1 1")
        SendMessage(player, "team可选: attack, defense")
        SendMessage(player, "level范围: 1-3")
        SendMessage(player, "position范围: 1-5")
        return
    end

    -- 延迟加载BattleTestSystem（使用类型断言）
    if not BattleTestSystem then
        local battleTestModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("BattleTestSystem")
        if battleTestModule then
            BattleTestSystem = require(battleTestModule :: ModuleScript)
        else
            SendMessage(player, "错误: 无法加载BattleTestSystem模块")
            return
        end
    end

    local teamStr = string.lower(tostring(args[1]))
    local unitId = tostring(args[2])
    local level = tonumber(args[3])
    local positionIndex = tonumber(args[4])

    -- 验证参数
    local team = nil
    if teamStr == "attack" then
        team = BattleConfig.Team.ATTACK
    elseif teamStr == "defense" then
        team = BattleConfig.Team.DEFENSE
    else
        SendMessage(player, "错误: team必须是attack或defense")
        return
    end

    if not UnitConfig.IsValidUnit(unitId) then
        SendMessage(player, "错误: 无效的兵种ID: " .. unitId)
        return
    end

    if not level or level < 1 or level > 3 then
        SendMessage(player, "错误: level必须在1-3之间")
        return
    end

    if not positionIndex or positionIndex < 1 or positionIndex > 5 then
        SendMessage(player, "错误: position必须在1-5之间")
        return
    end

    -- 生成兵种
    local success = BattleTestSystem.SpawnSingleTestUnit(player, unitId, level, team, positionIndex)

    if success then
        SendMessage(player, string.format("已在%s位置%d生成 Lv.%d %s", team, positionIndex, level, unitId))
    else
        SendMessage(player, "生成失败，请检查参数或战斗实例状态")
    end
end

--[[
命令: /startbattle
开始当前玩家的战斗测试 V1.5
]]
local function CMD_StartBattle(player, args)
    -- 延迟加载BattleManager
    if not BattleManager then
        BattleManager = require(ServerScriptService.Systems.BattleManager)
    end

    -- 获取玩家当前的战斗实例
    local battle = BattleManager.GetPlayerBattle(player.UserId)

    if not battle then
        SendMessage(player, "错误: 你还没有创建战斗实例")
        SendMessage(player, "请先使用 /spawnunit 生成兵种，或使用 /battletest 快速测试")
        return
    end

    if battle.State ~= BattleConfig.BattleState.PREPARING then
        SendMessage(player, "错误: 战斗已经开始或已结束")
        return
    end

    -- 检查是否至少有一方有兵种
    if #battle.AttackUnits == 0 and #battle.DefenseUnits == 0 then
        SendMessage(player, "错误: 至少需要生成一个兵种才能开始战斗")
        return
    end

    -- 开始战斗
    local success = BattleManager.StartBattle(battle.BattleId)

    if success then
        SendMessage(player, string.format("战斗开始! 战斗ID: %d", battle.BattleId))
    else
        SendMessage(player, "战斗启动失败")
    end
end

--[[
命令: /stopbattle
立即结束当前玩家的战斗 V1.5
]]
local function CMD_StopBattle(player, args)
    -- 延迟加载BattleManager
    if not BattleManager then
        BattleManager = require(ServerScriptService.Systems.BattleManager)
    end

    -- 获取玩家当前的战斗实例
    local battle = BattleManager.GetPlayerBattle(player.UserId)

    if not battle then
        SendMessage(player, "错误: 你没有正在进行的战斗")
        return
    end

    -- 强制结束战斗
    local success = BattleManager.EndBattle(battle.BattleId, nil)

    if success then
        SendMessage(player, "战斗已强制结束")
    else
        SendMessage(player, "结束战斗失败")
    end
end

--[[
命令: /clearbattle
清理战斗测试区域的所有兵种 V1.5
]]
local function CMD_ClearBattle(player, args)
    -- 延迟加载BattleManager
    if not BattleManager then
        BattleManager = require(ServerScriptService.Systems.BattleManager)
    end

    -- 获取玩家当前的战斗实例
    local battle = BattleManager.GetPlayerBattle(player.UserId)

    if not battle then
        SendMessage(player, "你没有战斗实例需要清理")
        return
    end

    -- 清理战场
    BattleManager.CleanupBattle(battle.BattleId)
    SendMessage(player, "已清理战斗测试区域")
end

--[[
命令: /addidlecoins [minutes]
添加挂机金币（测试用）V2.6
默认添加60分钟（1小时）的挂机金币
]]
local function CMD_AddIdleCoins(player, args)
    -- 延迟加载IdleCoinSystem
    if not IdleCoinSystem then
        IdleCoinSystem = require(ServerScriptService.Systems.IdleCoinSystem)
    end

    local minutes = tonumber(args[1]) or 60  -- 默认60分钟

    if minutes <= 0 then
        SendMessage(player, "错误: 分钟数必须大于0")
        return
    end

    -- 添加挂机金币
    local success, coins = IdleCoinSystem.GMAddIdleCoins(player, minutes)

    if success then
        local idleCoinData = DataManager.GetIdleCoinData(player)
        SendMessage(player, string.format("成功添加 %d 挂机金币（模拟 %d 分钟）", coins, minutes))
        SendMessage(player, string.format("当前待领取金币: %d", idleCoinData.PendingCoins or 0))
        SendMessage(player, "请靠近Mail模型长按E键领取")
    else
        SendMessage(player, "添加挂机金币失败")
    end
end

--[[
命令: /addhandcuff [count]
添加手铐道具 V6.0
默认添加1个
]]
local function CMD_AddHandcuff(player, args)
    if not LimitPrisonerSystem then
        LimitPrisonerSystem = require(ServerScriptService.Systems.LimitPrisonerSystem)
    end

    local count = tonumber(args[1]) or 1
    if count <= 0 then
        SendMessage(player, "错误: 数量必须大于0")
        return
    end

    local success, newCount = DataManager.AddHandcuffs(player, count)
    if success then
        SendMessage(player, string.format("成功添加 %d 个手铐", count))
        SendMessage(player, string.format("当前手铐数量: %d", newCount or 0))
        DataManager.SavePlayerDataThrottled(player)
        if LimitPrisonerSystem and LimitPrisonerSystem.SyncPlayer then
            LimitPrisonerSystem.SyncPlayer(player)
        end
    else
        SendMessage(player, "添加手铐失败")
    end
end

--[[
命令: /idlecoins
查看当前待领取的挂机金币 V2.6
]]
local function CMD_IdleCoins(player, args)
    local idleCoinData = DataManager.GetIdleCoinData(player)
    local pendingCoins = idleCoinData.PendingCoins or 0
    local lastLogoutTime = idleCoinData.LastLogoutTime or 0

    SendMessage(player, string.format("=== 挂机金币信息 ==="))
    SendMessage(player, string.format("待领取金币: %d", pendingCoins))

    if lastLogoutTime > 0 then
        local offlineSeconds = os.time() - lastLogoutTime
        local offlineMinutes = math.floor(offlineSeconds / 60)
        SendMessage(player, string.format("上次登出时间: %d (距今 %d 分钟)", lastLogoutTime, offlineMinutes))
    else
        SendMessage(player, "上次登出时间: 无记录")
    end

    local completedChapters = DataManager.GetCompletedChapters(player) or 0
    local idleConfig = HouseConfig.GetIdleConfigByCompletedChapters(completedChapters)
    local coinsPerMinute = idleConfig and tonumber(idleConfig.CoinsPerMinute) or tonumber(GameConfig.IdleCoin.CoinsPerMinute) or 0
    local maxHours = idleConfig and tonumber(idleConfig.MaxHours) or tonumber(GameConfig.IdleCoin.MaxOfflineHours) or 0

    SendMessage(player, string.format("金币产出速度: %d/分钟", coinsPerMinute))
    SendMessage(player, string.format("最大离线时长: %d 小时", maxHours))
end

--[[
命令: /resetdata
重置玩家所有数据（危险操作）V2.9
]]
local function CMD_ResetData(player, args)
    -- 二次确认机制：需要输入 /resetdata confirm 才会执行
    if #args < 1 or args[1] ~= "confirm" then
        SendMessage(player, "⚠️ 警告：此操作将清除你的所有游戏数据！")
        SendMessage(player, "包括：金币、背包、已放置兵种、商店数据、挂机金币等")
        SendMessage(player, "此操作不可撤销！")
        SendMessage(player, "")
        SendMessage(player, "如确认重置，请输入: /resetdata confirm")
        return
    end

    -- 延迟加载PlacementSystem，用于清除已放置的兵种模型
    if not PlacementSystem then
        PlacementSystem = require(ServerScriptService.Systems.PlacementSystem)
    end

    -- 清除场景中已放置的兵种模型
    local clearedCount = PlacementSystem.ClearAllPlacedUnits(player)
    SendMessage(player, string.format("已清除 %d 个已放置的兵种模型", clearedCount))

    -- 重置DataStore中的所有数据
    local success = DataManager.ResetAllPlayerData(player)

    if success then
        SendMessage(player, "✅ 数据重置成功！")
        SendMessage(player, "你的所有数据已恢复为初始状态：")
        SendMessage(player, string.format("  - 金币: %d", GameConfig.INITIAL_COINS))
        SendMessage(player, "  - 背包: 已清空")
        SendMessage(player, "  - 已放置兵种: 已清空")
        SendMessage(player, "  - 商店数据: 已重置")
        SendMessage(player, "  - 挂机金币: 已清空")
        SendMessage(player, "")
        SendMessage(player, "建议重新进入游戏以确保所有系统正确初始化")
    else
        SendMessage(player, "❌ 数据重置失败，请重试或联系管理员")
    end
end

-- ==================== V3.0 技能系统命令 ====================

--[[
命令: /addskill <skillId> [count]
添加技能到背包 V3.0
]]
local function CMD_AddSkill(player, args)
    if #args < 1 then
        SendMessage(player, "用法: /addskill <skillId> [count]")
        SendMessage(player, "例如: /addskill 1001 3")
        return
    end

    -- 延迟加载SkillSystem
    if not SkillSystem then
        local systemsFolder = ServerScriptService:FindFirstChild("Systems")
        if systemsFolder then
            local ss = systemsFolder:FindFirstChild("SkillSystem")
            if ss then
                SkillSystem = require(ss)
            end
        end
    end

    local skillId = tonumber(args[1])
    local count = tonumber(args[2]) or 1

    -- 验证技能ID
    if not skillId or not SkillConfig.IsValidSkill(skillId) then
        SendMessage(player, "错误: 无效的技能ID: " .. tostring(args[1]))
        SendMessage(player, "使用 /skilllist 查看所有可用的技能")
        return
    end

    -- 验证数量
    if count < 1 or count > 100 then
        SendMessage(player, "错误: 数量必须在1-100之间")
        return
    end

    -- 添加技能
    local success = false
    if SkillSystem then
        success = SkillSystem.AddSkill(player, skillId, count)
    else
        -- SkillSystem未加载时，直接使用DataManager
        local addSuccess, newCount = DataManager.AddSkill(player, skillId, count)
        success = addSuccess
    end

    if success then
        local skillName = SkillConfig.GetSkillName(skillId)
        SendMessage(player, string.format("成功添加 %d 个 %s (ID:%d)", count, skillName, skillId))
        SendMessage(player, "使用 /listskills 查看当前技能背包")
        -- V3.0修复：保存数据到DataStore
        DataManager.SavePlayerDataThrottled(player)
        -- V3.0修复：确保同步到客户端（重新加载SkillSystem以确保同步）
        if not SkillSystem then
            local systemsFolder = ServerScriptService:FindFirstChild("Systems")
            if systemsFolder then
                local ss = systemsFolder:FindFirstChild("SkillSystem")
                if ss then
                    SkillSystem = require(ss)
                end
            end
        end
        if SkillSystem and SkillSystem.SyncSkillInventory then
            SkillSystem.SyncSkillInventory(player)
        end
    else
        SendMessage(player, "添加技能失败")
    end
end

--[[
命令: /removeskill <skillId> [count]
从背包移除技能 V3.0
]]
local function CMD_RemoveSkill(player, args)
    if #args < 1 then
        SendMessage(player, "用法: /removeskill <skillId> [count]")
        SendMessage(player, "例如: /removeskill 1001 1")
        return
    end

    local skillId = tonumber(args[1])
    local count = tonumber(args[2]) or 1

    -- 验证技能ID
    if not skillId or not SkillConfig.IsValidSkill(skillId) then
        SendMessage(player, "错误: 无效的技能ID: " .. tostring(args[1]))
        return
    end

    -- 移除技能
    local success = false
    local remaining = 0
    if DataManager and DataManager.RemoveSkill then
        success, remaining = DataManager.RemoveSkill(player, skillId, count)
    end

    if success then
        local skillName = SkillConfig.GetSkillName(skillId)
        SendMessage(player, string.format("成功移除 %d 个 %s (ID:%d), 剩余: %d", count, skillName, skillId, remaining))
        -- 同步到客户端
        if SkillSystem then
            SkillSystem.SyncSkillInventory(player)
        end
        -- V3.0修复：保存数据到DataStore
        DataManager.SavePlayerDataThrottled(player)
    else
        SendMessage(player, "移除技能失败(数量不足或技能不存在)")
    end
end

--[[
命令: /clearskills
清空技能背包 V3.0
]]
local function CMD_ClearSkills(player, args)
    local success = false
    if DataManager and DataManager.ClearSkillInventory then
        success = DataManager.ClearSkillInventory(player)
    end

    if success then
        SendMessage(player, "技能背包已清空")
        -- 同步到客户端
        if SkillSystem then
            SkillSystem.SyncSkillInventory(player)
        end
        -- V3.0修复：保存数据到DataStore
        DataManager.SavePlayerDataThrottled(player)
    else
        SendMessage(player, "清空失败")
    end
end

--[[
命令: /listskills
列出技能背包中的所有技能 V3.0
]]
local function CMD_ListSkills(player, args)
    local inventory = {}
    if DataManager and DataManager.GetSkillInventory then
        inventory = DataManager.GetSkillInventory(player)
    end

    -- 检查是否为空
    local isEmpty = true
    for _, _ in pairs(inventory) do
        isEmpty = false
        break
    end

    if isEmpty then
        SendMessage(player, "技能背包为空")
        return
    end

    local message = "=== 技能背包 ===\n"
    local totalSkills = 0
    for skillIdKey, count in pairs(inventory) do
        local skillId = tonumber(skillIdKey) or 0
        local skillData = SkillConfig.GetSkillById(skillId)
        local skillName = skillData and skillData.Name or "Unknown"
        message = message .. string.format("  - %s (ID:%d) x%d\n", skillName, skillId, count)
        totalSkills = totalSkills + count
    end
    message = message .. string.format("总计: %d 个技能", totalSkills)

    SendMessage(player, message)
end

--[[
命令: /skilllist
列出所有可用的技能ID V3.0
]]
local function CMD_SkillList(player, args)
    local allSkillIds = SkillConfig.GetAllSkillIds()
    local message = "=== 可用技能列表 ===\n"

    for _, skillId in ipairs(allSkillIds) do
        local skillData = SkillConfig.GetSkillById(skillId)
        if skillData then
            local effectInfo = ""
            if skillData.EffectType == SkillConfig.EffectType.INSTANT then
                effectInfo = string.format("即时伤害%d", skillData.Damage or 0)
            elseif skillData.EffectType == SkillConfig.EffectType.DOT then
                local totalDamage = SkillConfig.CalculateDOTTotalDamage(skillId)
                effectInfo = string.format("DOT %d/%.1fs 共%d伤害",
                    skillData.TickDamage, skillData.TickInterval, totalDamage)
            end

            message = message .. string.format(
                "  - ID:%d %s (%s, 范围%d)\n    %s\n",
                skillId,
                skillData.Name,
                skillData.SkillType,
                skillData.Range,
                effectInfo
            )
        end
    end

    SendMessage(player, message)
end

-- ==================== V3.5 新手引导系统命令 ====================

--[[
命令: /triggerguide <guideId>
触发指定引导 V3.5
]]
local function CMD_TriggerGuide(player, args)
    if #args < 1 then
        SendMessage(player, "用法: /triggerguide <guideId>")
        SendMessage(player, "例如: /triggerguide 1001")
        return
    end

    -- 延迟加载GuideSystem
    if not GuideSystem then
        local systemsFolder = ServerScriptService:FindFirstChild("Systems")
        if systemsFolder then
            local gs = systemsFolder:FindFirstChild("GuideSystem")
            if gs then
                GuideSystem = require(gs)
            end
        end
    end

    local guideId = tonumber(args[1])
    if not guideId then
        SendMessage(player, "错误: 引导ID必须是数字")
        return
    end

    -- 验证引导ID
    if not GuideConfig.IsValidGuide(guideId) then
        SendMessage(player, "错误: 无效的引导ID: " .. tostring(args[1]))
        SendMessage(player, "使用 /listguides 查看所有引导")
        return
    end

    -- 触发引导
    local success = false
    if GuideSystem then
        success = GuideSystem.GMTriggerGuide(player, guideId)
    end

    if success then
        local guideData = GuideConfig.GetGuideById(guideId)
        SendMessage(player, string.format("成功触发引导: %d (%s)", guideId, guideData.Name))
    else
        SendMessage(player, "触发引导失败(可能已完成或找不到目标)")
    end
end

--[[
命令: /resetguide <guideId>
重置指定引导 V3.5
]]
local function CMD_ResetGuide(player, args)
    if #args < 1 then
        SendMessage(player, "用法: /resetguide <guideId>")
        SendMessage(player, "例如: /resetguide 1001")
        return
    end

    -- 延迟加载GuideSystem
    if not GuideSystem then
        local systemsFolder = ServerScriptService:FindFirstChild("Systems")
        if systemsFolder then
            local gs = systemsFolder:FindFirstChild("GuideSystem")
            if gs then
                GuideSystem = require(gs)
            end
        end
    end

    local guideId = tonumber(args[1])
    if not guideId then
        SendMessage(player, "错误: 引导ID必须是数字")
        return
    end

    -- 验证引导ID
    if not GuideConfig.IsValidGuide(guideId) then
        SendMessage(player, "错误: 无效的引导ID: " .. tostring(args[1]))
        return
    end

    -- 重置引导
    local success = false
    if GuideSystem then
        success = GuideSystem.GMResetGuide(player, guideId)
    end

    if success then
        local guideData = GuideConfig.GetGuideById(guideId)
        SendMessage(player, string.format("成功重置引导: %d (%s)", guideId, guideData.Name))
        SendMessage(player, "使用 /triggerguide " .. guideId .. " 可以重新触发")
    else
        SendMessage(player, "重置引导失败")
    end
end

--[[
命令: /resetallguides
重置所有引导 V3.5
]]
local function CMD_ResetAllGuides(player, args)
    -- 延迟加载GuideSystem
    if not GuideSystem then
        local systemsFolder = ServerScriptService:FindFirstChild("Systems")
        if systemsFolder then
            local gs = systemsFolder:FindFirstChild("GuideSystem")
            if gs then
                GuideSystem = require(gs)
            end
        end
    end

    -- 重置所有引导
    local success = false
    if GuideSystem then
        success = GuideSystem.GMResetAllGuides(player)
    end

    if success then
        SendMessage(player, "成功重置所有引导")
        SendMessage(player, "重新进入游戏或使用 /triggerguide 可触发引导")
    else
        SendMessage(player, "重置引导失败")
    end
end

--[[
命令: /listguides
列出所有引导及其状态 V3.5
]]
local function CMD_ListGuides(player, args)
    -- 延迟加载GuideSystem
    if not GuideSystem then
        local systemsFolder = ServerScriptService:FindFirstChild("Systems")
        if systemsFolder then
            local gs = systemsFolder:FindFirstChild("GuideSystem")
            if gs then
                GuideSystem = require(gs)
            end
        end
    end

    local message = "=== 引导列表 ===\n"

    -- 获取所有引导配置
    local allGuideIds = GuideConfig.GetAllGuideIds()
    local completedGuides = {}

    if GuideSystem then
        completedGuides = GuideSystem.GetCompletedGuides(player)
    end

    -- 构建已完成的引导ID集合
    local completedSet = {}
    for _, guideId in ipairs(completedGuides) do
        completedSet[guideId] = true
    end

    -- 获取当前激活的引导
    local activeGuideId = nil
    if GuideSystem then
        activeGuideId = GuideSystem.GetActiveGuideId(player)
    end

    for _, guideId in ipairs(allGuideIds) do
        local guideData = GuideConfig.GetGuideById(guideId)
        if guideData then
            local status = "❌ 未完成"
            if completedSet[guideId] then
                status = "✅ 已完成"
            elseif activeGuideId == guideId then
                status = "🔄 进行中"
            end

            message = message .. string.format(
                "  - ID:%d %s (%s)\n    目标: %s | %s\n",
                guideId,
                guideData.Name,
                guideData.GuideType,
                guideData.TargetName,
                status
            )
        end
    end

    message = message .. string.format("\n总计: %d 个引导", #allGuideIds)
    SendMessage(player, message)
end

-- 命令映射表
CMD_AddHandcuff = function(player, args)
    if not LimitPrisonerSystem then
        LimitPrisonerSystem = require(ServerScriptService.Systems.LimitPrisonerSystem)
    end

    local count = tonumber(args[1]) or 1
    if count <= 0 then
        SendMessage(player, "Error: count must be greater than 0.")
        return
    end

    local success, newCount = DataManager.AddHandcuffs(player, count)
    if success then
        SendMessage(player, string.format("Added %d handcuff(s).", count))
        SendMessage(player, string.format("Current handcuff count: %d", newCount or 0))
        DataManager.SavePlayerDataThrottled(player)
        if LimitPrisonerSystem and LimitPrisonerSystem.SyncPlayer then
            LimitPrisonerSystem.SyncPlayer(player)
        end
    else
        SendMessage(player, "Failed to add handcuffs.")
    end
end

--[[
Command: /addonlinetime [minutes]
Add online reward time in minutes (V6.1)
Default: 10 minutes
]]
local function CMD_AddOnlineTime(player, args)
    local minutes = tonumber(args[1]) or 10
    if minutes <= 0 then
        SendMessage(player, "Error: minutes must be greater than 0.")
        return
    end

    local onlineRewardSystem = require(ServerScriptService.Systems.OnlineRewardSystem)
    if onlineRewardSystem and onlineRewardSystem.SyncPlayer then
        onlineRewardSystem.SyncPlayer(player)
    end

    local rewardData = DataManager.GetOnlineRewardData(player)
    if not rewardData then
        SendMessage(player, "Online reward data not ready.")
        return
    end

    local secondsToAdd = math.floor(minutes * 60)
    local currentSeconds = tonumber(rewardData.TotalOnlineSeconds) or 0
    rewardData.TotalOnlineSeconds = currentSeconds + secondsToAdd

    DataManager.SavePlayerDataThrottled(player)

    if onlineRewardSystem and onlineRewardSystem.SyncPlayer then
        onlineRewardSystem.SyncPlayer(player)
    end

    SendMessage(player, string.format("Added %d minute(s) of online time.", minutes))
    SendMessage(player, string.format("Total online seconds today: %d", rewardData.TotalOnlineSeconds or 0))
end

--[[
Command: /resetonlinereward
Reset online reward data (V6.1)
]]
local function CMD_ResetOnlineReward(player, args)
    local success = DataManager.ResetOnlineRewardData(player, os.time())
    if not success then
        SendMessage(player, "Online reward reset failed.")
        return
    end

    DataManager.SavePlayerDataThrottled(player)

    local onlineRewardSystem = require(ServerScriptService.Systems.OnlineRewardSystem)
    if onlineRewardSystem and onlineRewardSystem.SyncPlayer then
        onlineRewardSystem.SyncPlayer(player)
    end

    SendMessage(player, "Online reward reset complete.")
end

local COMMAND_HANDLERS = {
    ["addunit"] = CMD_AddUnit,
    ["listunits"] = CMD_ListUnits,
    ["clearunits"] = CMD_ClearUnits,
    ["unitlist"] = CMD_UnitList,
    ["addcoins"] = CMD_AddCoins,
    ["clearcoins"] = CMD_ClearCoins,         -- V2.3新增
    ["iconpreload"] = CMD_IconPreload,       -- V2.3新增
    ["listplaced"] = CMD_ListPlaced,      -- V1.2新增
    ["clearplaced"] = CMD_ClearPlaced,    -- V1.2新增
    ["battletest"] = CMD_BattleTest,      -- V1.5新增
    ["spawnunit"] = CMD_SpawnUnit,        -- V1.5新增
    ["startbattle"] = CMD_StartBattle,    -- V1.5新增
    ["stopbattle"] = CMD_StopBattle,      -- V1.5新增
    ["clearbattle"] = CMD_ClearBattle,    -- V1.5新增
    ["addidlecoins"] = CMD_AddIdleCoins,  -- V2.6新增
    ["addhandcuff"] = CMD_AddHandcuff,    -- V6.0新增
    ["idlecoins"] = CMD_IdleCoins,        -- V2.6新增
    ["resetdata"] = CMD_ResetData,        -- V2.9新增
    ["mainprogress"] = CMD_MainProgress,  -- 主线通关打点
    ["unlocknextday"] = CMD_UnlockNextDay, -- V4.8新增：解锁七日登录下一天
    ["resetdailyreward"] = CMD_ResetDailyReward, -- V5.3新增：重置每日免费奖励
    ["resetstarterpack"] = CMD_ResetStarterPack, -- V5.4新增：重置新手礼包
    ["resetvip"] = CMD_ResetVip, -- V5.5新增：重置VIP礼包
    ["addskill"] = CMD_AddSkill,          -- V3.0新增
    ["removeskill"] = CMD_RemoveSkill,    -- V3.0新增
    ["clearskills"] = CMD_ClearSkills,    -- V3.0新增
    ["listskills"] = CMD_ListSkills,      -- V3.0新增
    ["skilllist"] = CMD_SkillList,        -- V3.0新增
    ["triggerguide"] = CMD_TriggerGuide,  -- V3.5新增
    ["resetguide"] = CMD_ResetGuide,      -- V3.5新增
    ["resetallguides"] = CMD_ResetAllGuides,  -- V3.5新增
    ["listguides"] = CMD_ListGuides,      -- V3.5新增
    ["addonlinetime"] = CMD_AddOnlineTime, -- V6.1
    ["resetonlinereward"] = CMD_ResetOnlineReward, -- V6.1
    ["help"] = CMD_Help,
}

-- ==================== 公共接口 ====================

--[[
处理玩家发送的命令
@param player Player - 玩家对象
@param message string - 聊天消息
@return boolean - 是否是GM命令
]]
function GMCommandSystem.HandleCommand(player, message)
    -- 检查是否是命令
    if string.sub(message, 1, 1) ~= COMMAND_PREFIX then
        return false
    end

    -- 检查权限
    if not HasGMPermission(player) then
        SendMessage(player, "错误: 你没有使用GM命令的权限")
        return true
    end

    -- 解析命令
    local parts = SplitString(message, " ")
    local commandName = string.sub(parts[1], 2):lower()  -- 移除前缀并转小写
    local args = {}

    -- 提取参数
    for i = 2, #parts do
        table.insert(args, parts[i])
    end

    -- 查找并执行命令
    local handler = COMMAND_HANDLERS[commandName]
    if handler then

        local success, err = pcall(handler, player, args)
        if not success then
            warn(GameConfig.LOG_PREFIX, "GM命令执行错误:", err)
            SendMessage(player, "命令执行出错: " .. tostring(err))
        end
    else
        SendMessage(player, "未知命令: " .. commandName)
        SendMessage(player, "使用 /help 查看可用命令")
    end

    return true
end

--[[
初始化GM命令系统
连接到聊天事件
]]
function GMCommandSystem.Initialize()

    -- 连接玩家聊天事件
    Players.PlayerAdded:Connect(function(player)
        player.Chatted:Connect(function(message)
            GMCommandSystem.HandleCommand(player, message)
        end)
    end)

    -- 处理已经在游戏中的玩家
    for _, player in ipairs(Players:GetPlayers()) do
        player.Chatted:Connect(function(message)
            GMCommandSystem.HandleCommand(player, message)
        end)
    end

end

return GMCommandSystem
