--[[
脚本名称: CreateBattleTestUI
脚本类型: Script (一次性运行脚本)
脚本位置: 在Roblox Studio的Command Bar中运行
使用方法:
  1. 复制整个脚本
  2. 在Roblox Studio中按Ctrl+Shift+X打开Command Bar
  3. 粘贴并运行
  4. UI会自动创建在StarterGui中
版本: V1.5.1 - 使用Scale布局适配不同分辨率
]]

-- 创建战斗测试UI
local function CreateBattleTestUI()
    local StarterGui = game:GetService("StarterGui")

    -- 删除旧的UI（如果存在）
    local oldGui = StarterGui:FindFirstChild("BattleTestGui")
    if oldGui then
        oldGui:Destroy()
        print("已删除旧的BattleTestGui")
    end

    -- 创建主ScreenGui
    local gui = Instance.new("ScreenGui")
    gui.Name = "BattleTestGui"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Enabled = false  -- 默认隐藏
    gui.Parent = StarterGui

    -- 创建主Frame (使用Scale，居中显示)
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0.3, 0, 0.75, 0)  -- 宽度30%，高度75%
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)  -- 屏幕中心
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)  -- 锚点在中心
    mainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    mainFrame.BorderSizePixel = 3
    mainFrame.BorderColor3 = Color3.fromRGB(200, 200, 200)
    mainFrame.Parent = gui

    -- 添加圆角
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = mainFrame

    -- 标题
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.new(0.85, 0, 0.06, 0)
    titleLabel.Position = UDim2.new(0.025, 0, 0.01, 0)
    titleLabel.Text = "⚔️ 战斗测试工具"
    titleLabel.Font = Enum.Font.SourceSansBold
    titleLabel.TextSize = 26
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextScaled = true
    titleLabel.Parent = mainFrame

    -- 关闭按钮
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0.08, 0, 0.05, 0)
    closeButton.Position = UDim2.new(0.9, 0, 0.015, 0)
    closeButton.Text = "✕"
    closeButton.Font = Enum.Font.SourceSansBold
    closeButton.TextSize = 24
    closeButton.TextScaled = true
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    closeButton.BorderSizePixel = 0
    closeButton.Parent = mainFrame

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0.2, 0)
    closeCorner.Parent = closeButton

    -- ===== 生成兵种区域 =====
    local spawnSection = Instance.new("Frame")
    spawnSection.Name = "SpawnSection"
    spawnSection.Size = UDim2.new(0.95, 0, 0.32, 0)
    spawnSection.Position = UDim2.new(0.025, 0, 0.08, 0)
    spawnSection.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    spawnSection.BorderSizePixel = 1
    spawnSection.BorderColor3 = Color3.fromRGB(100, 100, 100)
    spawnSection.Parent = mainFrame

    local spawnCorner = Instance.new("UICorner")
    spawnCorner.CornerRadius = UDim.new(0.03, 0)
    spawnCorner.Parent = spawnSection

    -- 区域标题
    local spawnTitle = Instance.new("TextLabel")
    spawnTitle.Name = "SectionTitle"
    spawnTitle.Size = UDim2.new(0.9, 0, 0.12, 0)
    spawnTitle.Position = UDim2.new(0.025, 0, 0.02, 0)
    spawnTitle.Text = "📦 生成兵种"
    spawnTitle.Font = Enum.Font.SourceSansBold
    spawnTitle.TextSize = 20
    spawnTitle.TextScaled = true
    spawnTitle.TextColor3 = Color3.fromRGB(150, 220, 255)
    spawnTitle.BackgroundTransparency = 1
    spawnTitle.TextXAlignment = Enum.TextXAlignment.Left
    spawnTitle.Parent = spawnSection

    -- 创建下拉选项的辅助函数
    local function CreateDropdown(parent, name, labelText, yScale, options, defaultValue)
        local label = Instance.new("TextLabel")
        label.Name = name .. "Label"
        label.Size = UDim2.new(0.2, 0, 0.12, 0)
        label.Position = UDim2.new(0.04, 0, yScale, 0)
        label.Text = labelText
        label.Font = Enum.Font.SourceSans
        label.TextSize = 16
        label.TextScaled = true
        label.TextColor3 = Color3.fromRGB(220, 220, 220)
        label.BackgroundTransparency = 1
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = parent

        local dropdown = Instance.new("TextButton")
        dropdown.Name = name .. "Dropdown"
        dropdown.Size = UDim2.new(0.7, 0, 0.12, 0)
        dropdown.Position = UDim2.new(0.26, 0, yScale, 0)
        dropdown.Text = defaultValue
        dropdown.Font = Enum.Font.SourceSans
        dropdown.TextSize = 16
        dropdown.TextScaled = true
        dropdown.TextColor3 = Color3.fromRGB(255, 255, 255)
        dropdown.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        dropdown.BorderSizePixel = 1
        dropdown.BorderColor3 = Color3.fromRGB(120, 120, 120)
        dropdown.Parent = parent

        local dropCorner = Instance.new("UICorner")
        dropCorner.CornerRadius = UDim.new(0.15, 0)
        dropCorner.Parent = dropdown

        -- 存储选项（实际脚本中会用到）
        dropdown:SetAttribute("Options", table.concat(options, ","))
        dropdown:SetAttribute("CurrentIndex", 1)

        return dropdown
    end

    -- 队伍选择
    CreateDropdown(spawnSection, "Team", "队伍:", 0.18, {"Attack", "Defense"}, "Attack")

    -- 兵种选择 (会在运行时从UnitConfig动态加载所有兵种)
    CreateDropdown(spawnSection, "Unit", "兵种:", 0.35, {"加载中..."}, "加载中...")

    -- 等级选择
    CreateDropdown(spawnSection, "Level", "等级:", 0.52, {"1", "2", "3"}, "1")

    -- 位置选择
    CreateDropdown(spawnSection, "Position", "位置:", 0.69, {"1", "2", "3", "4", "5"}, "1")

    -- 生成按钮
    local spawnButton = Instance.new("TextButton")
    spawnButton.Name = "SpawnButton"
    spawnButton.Size = UDim2.new(0.9, 0, 0.15, 0)
    spawnButton.Position = UDim2.new(0.05, 0, 0.83, 0)
    spawnButton.Text = "✨ 生成兵种"
    spawnButton.Font = Enum.Font.SourceSansBold
    spawnButton.TextSize = 18
    spawnButton.TextScaled = true
    spawnButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    spawnButton.BackgroundColor3 = Color3.fromRGB(50, 150, 250)
    spawnButton.BorderSizePixel = 0
    spawnButton.Parent = spawnSection

    local spawnBtnCorner = Instance.new("UICorner")
    spawnBtnCorner.CornerRadius = UDim.new(0.15, 0)
    spawnBtnCorner.Parent = spawnButton

    -- ===== 战斗控制区域 =====
    local controlSection = Instance.new("Frame")
    controlSection.Name = "ControlSection"
    controlSection.Size = UDim2.new(0.95, 0, 0.16, 0)
    controlSection.Position = UDim2.new(0.025, 0, 0.42, 0)
    controlSection.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    controlSection.BorderSizePixel = 1
    controlSection.BorderColor3 = Color3.fromRGB(100, 100, 100)
    controlSection.Parent = mainFrame

    local controlCorner = Instance.new("UICorner")
    controlCorner.CornerRadius = UDim.new(0.05, 0)
    controlCorner.Parent = controlSection

    -- 控制区标题
    local controlTitle = Instance.new("TextLabel")
    controlTitle.Name = "SectionTitle"
    controlTitle.Size = UDim2.new(0.9, 0, 0.2, 0)
    controlTitle.Position = UDim2.new(0.025, 0, 0.05, 0)
    controlTitle.Text = "🎮 战斗控制"
    controlTitle.Font = Enum.Font.SourceSansBold
    controlTitle.TextSize = 20
    controlTitle.TextScaled = true
    controlTitle.TextColor3 = Color3.fromRGB(150, 255, 150)
    controlTitle.BackgroundTransparency = 1
    controlTitle.TextXAlignment = Enum.TextXAlignment.Left
    controlTitle.Parent = controlSection

    -- 创建按钮的辅助函数
    local function CreateButton(parent, name, text, xScale, yScale, widthScale, color)
        local button = Instance.new("TextButton")
        button.Name = name
        button.Size = UDim2.new(widthScale, 0, 0.28, 0)
        button.Position = UDim2.new(xScale, 0, yScale, 0)
        button.Text = text
        button.Font = Enum.Font.SourceSansBold
        button.TextSize = 16
        button.TextScaled = true
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.BackgroundColor3 = color
        button.BorderSizePixel = 0
        button.Parent = parent

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0.15, 0)
        btnCorner.Parent = button

        return button
    end

    -- 开始战斗按钮
    CreateButton(controlSection, "StartButton", "▶️ 开始战斗", 0.04, 0.35, 0.44, Color3.fromRGB(50, 180, 50))

    -- 清空列表按钮
    CreateButton(controlSection, "ClearButton", "🗑️ 清空列表", 0.52, 0.35, 0.44, Color3.fromRGB(200, 150, 50))

    -- 清理战场按钮
    CreateButton(controlSection, "CleanupButton", "🧹 清理战场", 0.04, 0.68, 0.92, Color3.fromRGB(180, 80, 80))

    -- ===== 状态信息区域 =====
    local statusSection = Instance.new("Frame")
    statusSection.Name = "StatusSection"
    statusSection.Size = UDim2.new(0.95, 0, 0.13, 0)
    statusSection.Position = UDim2.new(0.025, 0, 0.60, 0)
    statusSection.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    statusSection.BorderSizePixel = 1
    statusSection.BorderColor3 = Color3.fromRGB(100, 100, 100)
    statusSection.Parent = mainFrame

    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0.06, 0)
    statusCorner.Parent = statusSection

    -- 状态标题
    local statusTitle = Instance.new("TextLabel")
    statusTitle.Name = "SectionTitle"
    statusTitle.Size = UDim2.new(0.9, 0, 0.22, 0)
    statusTitle.Position = UDim2.new(0.025, 0, 0.05, 0)
    statusTitle.Text = "📊 状态信息"
    statusTitle.Font = Enum.Font.SourceSansBold
    statusTitle.TextSize = 18
    statusTitle.TextScaled = true
    statusTitle.TextColor3 = Color3.fromRGB(255, 200, 100)
    statusTitle.BackgroundTransparency = 1
    statusTitle.TextXAlignment = Enum.TextXAlignment.Left
    statusTitle.Parent = statusSection

    -- 攻击方状态
    local attackLabel = Instance.new("TextLabel")
    attackLabel.Name = "AttackLabel"
    attackLabel.Size = UDim2.new(0.9, 0, 0.2, 0)
    attackLabel.Position = UDim2.new(0.04, 0, 0.32, 0)
    attackLabel.Text = "⚔️ 攻击方: 0 单位"
    attackLabel.Font = Enum.Font.SourceSans
    attackLabel.TextSize = 16
    attackLabel.TextScaled = true
    attackLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    attackLabel.BackgroundTransparency = 1
    attackLabel.TextXAlignment = Enum.TextXAlignment.Left
    attackLabel.Parent = statusSection

    -- 防守方状态
    local defenseLabel = Instance.new("TextLabel")
    defenseLabel.Name = "DefenseLabel"
    defenseLabel.Size = UDim2.new(0.9, 0, 0.2, 0)
    defenseLabel.Position = UDim2.new(0.04, 0, 0.54, 0)
    defenseLabel.Text = "🛡️ 防守方: 0 单位"
    defenseLabel.Font = Enum.Font.SourceSans
    defenseLabel.TextSize = 16
    defenseLabel.TextScaled = true
    defenseLabel.TextColor3 = Color3.fromRGB(100, 150, 255)
    defenseLabel.BackgroundTransparency = 1
    defenseLabel.TextXAlignment = Enum.TextXAlignment.Left
    defenseLabel.Parent = statusSection

    -- 系统状态
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(0.9, 0, 0.2, 0)
    statusLabel.Position = UDim2.new(0.04, 0, 0.76, 0)
    statusLabel.Text = "💡 状态: 就绪"
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextSize = 16
    statusLabel.TextScaled = true
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = statusSection

    -- ===== 快速测试区域 =====
    local quickSection = Instance.new("Frame")
    quickSection.Name = "QuickTestSection"
    quickSection.Size = UDim2.new(0.95, 0, 0.14, 0)
    quickSection.Position = UDim2.new(0.025, 0, 0.75, 0)
    quickSection.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    quickSection.BorderSizePixel = 1
    quickSection.BorderColor3 = Color3.fromRGB(100, 100, 100)
    quickSection.Parent = mainFrame

    local quickCorner = Instance.new("UICorner")
    quickCorner.CornerRadius = UDim.new(0.06, 0)
    quickCorner.Parent = quickSection

    -- 快速测试标题
    local quickTitle = Instance.new("TextLabel")
    quickTitle.Name = "SectionTitle"
    quickTitle.Size = UDim2.new(0.9, 0, 0.22, 0)
    quickTitle.Position = UDim2.new(0.025, 0, 0.05, 0)
    quickTitle.Text = "⚡ 快速测试"
    quickTitle.Font = Enum.Font.SourceSansBold
    quickTitle.TextSize = 18
    quickTitle.TextScaled = true
    quickTitle.TextColor3 = Color3.fromRGB(255, 150, 255)
    quickTitle.BackgroundTransparency = 1
    quickTitle.TextXAlignment = Enum.TextXAlignment.Left
    quickTitle.Parent = quickSection

    -- 快速测试按钮
    CreateButton(quickSection, "Test1v1Button", "1v1 测试", 0.04, 0.38, 0.29, Color3.fromRGB(120, 80, 180))
    CreateButton(quickSection, "TestLevelButton", "等级测试", 0.355, 0.38, 0.29, Color3.fromRGB(180, 120, 80))
    CreateButton(quickSection, "Test3v3Button", "3v3 测试", 0.67, 0.38, 0.29, Color3.fromRGB(80, 180, 120))

    -- 使用说明标签
    local hintLabel = Instance.new("TextLabel")
    hintLabel.Name = "HintLabel"
    hintLabel.Size = UDim2.new(0.9, 0, 0.18, 0)
    hintLabel.Position = UDim2.new(0.05, 0, 0.78, 0)
    hintLabel.Text = "💡 提示: 按 V 键打开/关闭此窗口"
    hintLabel.Font = Enum.Font.SourceSansItalic
    hintLabel.TextSize = 14
    hintLabel.TextScaled = true
    hintLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    hintLabel.BackgroundTransparency = 1
    hintLabel.TextXAlignment = Enum.TextXAlignment.Center
    hintLabel.Parent = quickSection

    print("✅ 战斗测试UI创建成功! (使用Scale布局)")
    print("📍 位置: StarterGui > BattleTestGui")
    print("🎮 使用方法: 游戏中按 V 键打开/关闭")
    print("📱 适配: 支持不同分辨率自动适配")

    return gui
end

-- 执行创建
CreateBattleTestUI()
