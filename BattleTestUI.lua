--[[
脚本名称: BattleTestUI
脚本类型: LocalScript (客户端UI控制器)
脚本位置: StarterPlayer/StarterPlayerScripts/UI/BattleTestUI
]]

--[[
战斗测试UI控制器 - 完整版
职责:
1. 管理战斗测试UI的显示和隐藏
2. 收集用户输入的测试参数
3. 发送测试请求到服务端
4. 显示战斗状态和结果
版本: V1.5
]]

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ==================== 配置 ====================

local TOGGLE_KEY = Enum.KeyCode.V  -- 按V键打开/关闭UI

-- ==================== 私有变量 ====================

-- UI引用
local battleTestGui = nil
local mainFrame = nil
local isUIVisible = false

-- UI组件引用
local teamDropdown = nil
local unitDropdown = nil
local levelDropdown = nil
local positionDropdown = nil
local spawnButton = nil
local startButton = nil
local clearButton = nil
local cleanupButton = nil
local closeButton = nil
local attackLabel = nil
local defenseLabel = nil
local statusLabel = nil
local test1v1Button = nil
local testLevelButton = nil
local test3v3Button = nil

-- RemoteEvent引用
local requestBattleTestEvent = nil
local battleTestResponseEvent = nil
local cleanupBattleTestEvent = nil

-- 暂存的生成数据
local attackUnitsData = {}
local defenseUnitsData = {}

-- 当前选择
local currentSelections = {
    Team = "Attack",
    Unit = "Noob",
    Level = 1,
    Position = 1
}

-- ==================== 私有函数 ====================

--[[
输出调试日志
]]
local function DebugLog(...)
    print("[BattleTestUI]", ...)
end

--[[
输出警告日志
]]
local function WarnLog(...)
    warn("[BattleTestUI]", ...)
end

--[[
切换UI显示状态
]]
local function ToggleUI()
    if not battleTestGui then
        DebugLog("⚠️ UI未加载，使用GM命令测试:")
        DebugLog("  /battletest")
        DebugLog("  /spawnunit attack Noob 1 1")
        DebugLog("  /startbattle")
        return
    end

    isUIVisible = not isUIVisible
    battleTestGui.Enabled = isUIVisible

    DebugLog("UI状态:", isUIVisible and "显示" or "隐藏")
end

--[[
更新状态显示
]]
local function UpdateStatusDisplay()
    if attackLabel then
        attackLabel.Text = string.format("⚔️ 攻击方: %d 单位", #attackUnitsData)
    end

    if defenseLabel then
        defenseLabel.Text = string.format("🛡️ 防守方: %d 单位", #defenseUnitsData)
    end
end

--[[
显示状态信息
]]
local function ShowStatus(message, isError)
    DebugLog("状态:", message)

    if statusLabel then
        if isError then
            statusLabel.Text = "❌ " .. message
            statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        else
            statusLabel.Text = "💡 " .. message
            statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        end

        -- 3秒后恢复默认状态
        task.delay(3, function()
            if statusLabel then
                statusLabel.Text = "💡 状态: 就绪"
                statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
            end
        end)
    end
end

--[[
切换下拉选项
]]
local function CycleDropdown(dropdown, options, currentKey)
    local optionsArray = string.split(options, ",")
    local currentIndex = dropdown:GetAttribute("CurrentIndex") or 1

    -- 循环到下一个选项
    currentIndex = currentIndex + 1
    if currentIndex > #optionsArray then
        currentIndex = 1
    end

    dropdown:SetAttribute("CurrentIndex", currentIndex)
    dropdown.Text = optionsArray[currentIndex]

    -- 更新当前选择
    if currentKey then
        currentSelections[currentKey] = optionsArray[currentIndex]

        -- 如果是等级或位置，转换为数字
        if currentKey == "Level" or currentKey == "Position" then
            currentSelections[currentKey] = tonumber(optionsArray[currentIndex])
        end
    end

    DebugLog(currentKey, "选择:", currentSelections[currentKey])
end

--[[
添加兵种到列表
]]
local function AddUnitToList(team, unitId, level, position)
    local unitData = {
        UnitId = unitId,
        Level = level,
        Position = position,
    }

    if team == "Attack" then
        table.insert(attackUnitsData, unitData)
        DebugLog(string.format("添加攻击方兵种: %s Lv.%d 位置%d", unitId, level, position))
    elseif team == "Defense" then
        table.insert(defenseUnitsData, unitData)
        DebugLog(string.format("添加防守方兵种: %s Lv.%d 位置%d", unitId, level, position))
    end

    UpdateStatusDisplay()
end

--[[
清空兵种列表
]]
local function ClearUnitLists()
    attackUnitsData = {}
    defenseUnitsData = {}

    UpdateStatusDisplay()
    ShowStatus("已清空兵种列表", false)
    DebugLog("清空兵种列表")
end

--[[
发送战斗测试请求
]]
local function SendBattleTestRequest()
    if not requestBattleTestEvent then
        WarnLog("RequestBattleTest事件不存在")
        ShowStatus("错误: 事件未初始化", true)
        return
    end

    -- 检查是否有兵种
    if #attackUnitsData == 0 and #defenseUnitsData == 0 then
        ShowStatus("错误: 至少需要添加一个兵种", true)
        return
    end

    DebugLog(string.format("发送战斗测试请求: 攻击方%d单位, 防守方%d单位",
        #attackUnitsData, #defenseUnitsData))

    -- 发送请求
    requestBattleTestEvent:FireServer(attackUnitsData, defenseUnitsData)

    ShowStatus("战斗请求已发送...", false)
end

--[[
处理战斗测试响应
]]
local function OnBattleTestResponse(success, battleId, message)
    DebugLog("收到战斗测试响应:", success, battleId, message)

    if success then
        ShowStatus(string.format("战斗开始! BattleId=%d", battleId), false)

        -- 清空列表
        ClearUnitLists()
    else
        ShowStatus("错误: " .. message, true)
    end
end

--[[
生成兵种按钮点击
]]
local function OnSpawnButtonClick()
    local team = currentSelections.Team
    local unitId = currentSelections.Unit
    local level = currentSelections.Level
    local position = currentSelections.Position

    AddUnitToList(team, unitId, level, position)
    ShowStatus(string.format("添加: %s %s Lv.%d 位置%d", team, unitId, level, position), false)
end

--[[
开始战斗按钮点击
]]
local function OnStartButtonClick()
    SendBattleTestRequest()
end

--[[
清空列表按钮点击
]]
local function OnClearButtonClick()
    ClearUnitLists()
end

--[[
清理战场按钮点击
]]
local function OnCleanupButtonClick()
    if not cleanupBattleTestEvent then
        WarnLog("CleanupBattleTest事件不存在")
        ShowStatus("错误: 清理事件未初始化", true)
        return
    end

    DebugLog("发送清理请求...")
    cleanupBattleTestEvent:FireServer()
    ShowStatus("清理战场命令已发送", false)
end

--[[
关闭按钮点击
]]
local function OnCloseButtonClick()
    ToggleUI()
end

-- ==================== 快速测试函数 ====================

--[[
简易测试: 1v1 Noob战斗
]]
local function QuickTest_1v1_Noob()
    ClearUnitLists()

    AddUnitToList("Attack", "Noob", 1, 1)
    AddUnitToList("Defense", "Noob", 1, 1)

    SendBattleTestRequest()
    ShowStatus("快速测试: 1v1 Noob", false)
end

--[[
简易测试: 不同等级战斗
]]
local function QuickTest_LevelDifference()
    ClearUnitLists()

    AddUnitToList("Attack", "Noob", 1, 1)
    AddUnitToList("Defense", "Noob", 2, 1)

    SendBattleTestRequest()
    ShowStatus("快速测试: 等级差异", false)
end

--[[
简易测试: 3v3混战
]]
local function QuickTest_3v3_Battle()
    ClearUnitLists()

    AddUnitToList("Attack", "Noob", 1, 1)
    AddUnitToList("Attack", "Noob", 2, 2)
    AddUnitToList("Attack", "Rookie", 1, 3)

    AddUnitToList("Defense", "Noob", 1, 1)
    AddUnitToList("Defense", "Rookie", 1, 2)
    AddUnitToList("Defense", "Noob", 3, 3)

    SendBattleTestRequest()
    ShowStatus("快速测试: 3v3混战", false)
end

-- ==================== UI事件连接 ====================

--[[
连接UI组件事件
]]
local function ConnectUIEvents()
    -- 下拉菜单点击事件
    if teamDropdown then
        teamDropdown.MouseButton1Click:Connect(function()
            CycleDropdown(teamDropdown, teamDropdown:GetAttribute("Options"), "Team")
        end)
    end

    if unitDropdown then
        unitDropdown.MouseButton1Click:Connect(function()
            CycleDropdown(unitDropdown, unitDropdown:GetAttribute("Options"), "Unit")
        end)
    end

    if levelDropdown then
        levelDropdown.MouseButton1Click:Connect(function()
            CycleDropdown(levelDropdown, levelDropdown:GetAttribute("Options"), "Level")
        end)
    end

    if positionDropdown then
        positionDropdown.MouseButton1Click:Connect(function()
            CycleDropdown(positionDropdown, positionDropdown:GetAttribute("Options"), "Position")
        end)
    end

    -- 按钮点击事件
    if spawnButton then
        spawnButton.MouseButton1Click:Connect(OnSpawnButtonClick)
    end

    if startButton then
        startButton.MouseButton1Click:Connect(OnStartButtonClick)
    end

    if clearButton then
        clearButton.MouseButton1Click:Connect(OnClearButtonClick)
    end

    if cleanupButton then
        cleanupButton.MouseButton1Click:Connect(OnCleanupButtonClick)
    end

    if closeButton then
        closeButton.MouseButton1Click:Connect(OnCloseButtonClick)
    end

    -- 快速测试按钮
    if test1v1Button then
        test1v1Button.MouseButton1Click:Connect(QuickTest_1v1_Noob)
    end

    if testLevelButton then
        testLevelButton.MouseButton1Click:Connect(QuickTest_LevelDifference)
    end

    if test3v3Button then
        test3v3Button.MouseButton1Click:Connect(QuickTest_3v3_Battle)
    end

    DebugLog("✅ UI事件已连接")
end

-- ==================== 初始化 ====================

--[[
初始化UI系统
]]
local function Initialize()
    DebugLog("正在初始化战斗测试UI...")

    -- 等待UI从StarterGui复制到PlayerGui（使用WaitForChild，最多等待10秒）
    local success, result = pcall(function()
        return playerGui:WaitForChild("BattleTestGui", 10)
    end)

    if success and result then
        battleTestGui = result
        mainFrame = battleTestGui:FindFirstChild("MainFrame")

        -- 获取UI组件
        if mainFrame then
            local spawnSection = mainFrame:FindFirstChild("SpawnSection")
            if spawnSection then
                teamDropdown = spawnSection:FindFirstChild("TeamDropdown")
                unitDropdown = spawnSection:FindFirstChild("UnitDropdown")
                levelDropdown = spawnSection:FindFirstChild("LevelDropdown")
                positionDropdown = spawnSection:FindFirstChild("PositionDropdown")
                spawnButton = spawnSection:FindFirstChild("SpawnButton")
            end

            local controlSection = mainFrame:FindFirstChild("ControlSection")
            if controlSection then
                startButton = controlSection:FindFirstChild("StartButton")
                clearButton = controlSection:FindFirstChild("ClearButton")
                cleanupButton = controlSection:FindFirstChild("CleanupButton")
            end

            local statusSection = mainFrame:FindFirstChild("StatusSection")
            if statusSection then
                attackLabel = statusSection:FindFirstChild("AttackLabel")
                defenseLabel = statusSection:FindFirstChild("DefenseLabel")
                statusLabel = statusSection:FindFirstChild("StatusLabel")
            end

            local quickSection = mainFrame:FindFirstChild("QuickTestSection")
            if quickSection then
                test1v1Button = quickSection:FindFirstChild("Test1v1Button")
                testLevelButton = quickSection:FindFirstChild("TestLevelButton")
                test3v3Button = quickSection:FindFirstChild("Test3v3Button")
            end

            closeButton = mainFrame:FindFirstChild("CloseButton")
        end

        -- 默认隐藏UI
        battleTestGui.Enabled = false
        isUIVisible = false

        -- 连接UI事件
        ConnectUIEvents()

        DebugLog("✅ 战斗测试UI已加载")
        DebugLog("📍 路径: PlayerGui > BattleTestGui")
    else
        WarnLog("⚠️ 未找到BattleTestGui")
        WarnLog("请确保: StarterGui > BattleTestGui 已创建")
        WarnLog("将使用命令行测试模式")
        battleTestGui = nil
    end

    -- 获取RemoteEvent
    local eventsFolder = ReplicatedStorage:WaitForChild("Events")
    local battleEventsFolder = eventsFolder:WaitForChild("BattleEvents")

    requestBattleTestEvent = battleEventsFolder:WaitForChild("RequestBattleTest")
    battleTestResponseEvent = battleEventsFolder:WaitForChild("BattleTestResponse")
    cleanupBattleTestEvent = battleEventsFolder:FindFirstChild("CleanupBattleTest")

    -- 如果清理事件不存在，等待它创建（服务端会自动创建）
    if not cleanupBattleTestEvent then
        cleanupBattleTestEvent = battleEventsFolder:WaitForChild("CleanupBattleTest", 10)
    end

    -- 连接响应事件
    battleTestResponseEvent.OnClientEvent:Connect(OnBattleTestResponse)

    -- 监听V键切换UI
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end

        if input.KeyCode == TOGGLE_KEY then
            ToggleUI()
        end
    end)

    -- 暴露全局测试函数(用于控制台测试)
    _G.BattleTest_1v1 = QuickTest_1v1_Noob
    _G.BattleTest_LevelDiff = QuickTest_LevelDifference
    _G.BattleTest_3v3 = QuickTest_3v3_Battle
    _G.BattleTest_Toggle = ToggleUI

    DebugLog("============================================")
    DebugLog("📖 战斗测试UI初始化完成")
    DebugLog("   🎮 按 V 键打开/关闭UI")
    DebugLog("   💻 GM命令: /battletest")
    DebugLog("   🔧 控制台: _G.BattleTest_1v1()")
    DebugLog("============================================")
end

-- 启动初始化
Initialize()
