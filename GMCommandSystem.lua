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
- /unitlist : 列出所有可用的兵种ID
]]

local GMCommandSystem = {}

-- 引用服务
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- 引用模块
local GameConfig = require(ServerScriptService.Config.GameConfig)
local UnitConfig = require(ServerScriptService.Config.UnitConfig)
local DataManager = require(ServerScriptService.Core.DataManager)
local InventorySystem = require(ServerScriptService.Systems.InventorySystem)
local CurrencySystem = require(ServerScriptService.Systems.CurrencySystem)

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

    local unitId = args[1]
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
        message = message .. string.format(
            "  - %s (等级%d, %s, %d金币)\n",
            unitId,
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
命令: /help
显示帮助信息
]]
local function CMD_Help(player, args)
    local helpText = [[
=== GM命令帮助 ===
/addunit <unitId> [count] - 添加兵种(默认1个)
/listunits - 查看背包
/clearunits - 清空背包
/unitlist - 查看所有可用兵种
/addcoins <amount> - 添加金币
/help - 显示此帮助
    ]]
    SendMessage(player, helpText)
end

-- 命令映射表
local COMMAND_HANDLERS = {
    ["addunit"] = CMD_AddUnit,
    ["listunits"] = CMD_ListUnits,
    ["clearunits"] = CMD_ClearUnits,
    ["unitlist"] = CMD_UnitList,
    ["addcoins"] = CMD_AddCoins,
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
        if GameConfig.DEBUG_MODE then
            print(string.format("%s GM命令: %s 参数: %s", GameConfig.LOG_PREFIX, commandName, table.concat(args, ", ")))
        end

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
    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "初始化GMCommandSystem...")
    end

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

    if GameConfig.DEBUG_MODE then
        print(GameConfig.LOG_PREFIX, "GMCommandSystem初始化完成")
        print(GameConfig.LOG_PREFIX, "权限检查:", ENABLE_PERMISSION_CHECK and "启用" or "禁用(所有人可用)")
    end
end

return GMCommandSystem
