--[[
脚本名称: IdleCoinSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/IdleCoinSystem
版本: V2.6
]]

--[[
挂机金币系统模块
职责:
1. 计算玩家离线期间产生的挂机金币
2. 处理玩家领取挂机金币的请求
3. 更新玩家基地Mail模型上的金币显示
4. 玩家登出时记录登出时间
5. 为每个基地创建ProximityPrompt交互
]]

local IdleCoinSystem = {}

-- 引用服务
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- 引用模块（延迟加载避免循环依赖）
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local HouseConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("HouseConfig"))
local DataManager = nil
local CurrencySystem = nil
local PlayerManager = nil
local SoundSystem = nil  -- V3.8新增

-- 收敛调试print，避免刷屏（仅在DEBUG_MODE开启时输出）
local _print = print
local function DebugPrint(...)
	if GameConfig.DEBUG_MODE then
		_print(...)
	end
end
local print = DebugPrint

-- 远程事件
local IdleCoinEvents = nil

-- 存储每个基地的ProximityPrompt连接
local promptConnections = {}

-- 🔥V3.9.3新增：存储每个玩家的在线累计定时器
local onlineTimers = {}

-- ==================== 私有函数 ====================

--[[
延迟加载模块（避免循环依赖）
]]
local function LoadModules()
	if not DataManager then
		DataManager = require(ServerScriptService.Core.DataManager)
	end
	if not CurrencySystem then
		CurrencySystem = require(ServerScriptService.Systems.CurrencySystem)
	end
	if not PlayerManager then
		PlayerManager = require(ServerScriptService.Core.PlayerManager)
	end
	-- V3.8新增：音效系统
	if not SoundSystem then
		SoundSystem = require(ServerScriptService.Systems.SoundSystem)
	end
end

local function GetIdleConfigForPlayer(player)
	LoadModules()

	local completedChapters = DataManager.GetCompletedChapters(player) or 0
	local houseConfig = HouseConfig.GetIdleConfigByCompletedChapters(completedChapters)

	local coinsPerMinute = houseConfig and tonumber(houseConfig.CoinsPerMinute) or 0
	local maxMinutes = houseConfig and tonumber(houseConfig.MaxMinutes) or 0
	local maxHours = houseConfig and tonumber(houseConfig.MaxHours) or 0

	if coinsPerMinute <= 0 then
		coinsPerMinute = tonumber(GameConfig.IdleCoin.CoinsPerMinute) or 0
	end

	if maxMinutes <= 0 then
		maxMinutes = tonumber(GameConfig.IdleCoin.MaxOfflineMinutes) or 0
	end

	if maxHours <= 0 then
		maxHours = math.floor(maxMinutes / 60)
	end

	return {
		CoinsPerMinute = coinsPerMinute,
		MaxMinutes = maxMinutes,
		MaxHours = maxHours,
	}
end

--[[
初始化事件
@return boolean - 是否成功
]]
local function InitializeEvents()
	if IdleCoinEvents then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] Events文件夹未找到")
		return false
	end

	IdleCoinEvents = eventsFolder:FindFirstChild("IdleCoinEvents")
	if not IdleCoinEvents then
		-- 创建事件文件夹
		IdleCoinEvents = Instance.new("Folder")
		IdleCoinEvents.Name = "IdleCoinEvents"
		IdleCoinEvents.Parent = eventsFolder

		-- 创建领取金币事件
		local collectEvent = Instance.new("RemoteEvent")
		collectEvent.Name = "CollectIdleCoins"
		collectEvent.Parent = IdleCoinEvents

		-- 创建同步金币数量事件（服务端→客户端）
		local syncEvent = Instance.new("RemoteEvent")
		syncEvent.Name = "SyncIdleCoins"
		syncEvent.Parent = IdleCoinEvents

		print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 已创建IdleCoinEvents事件")
	end

	return true
end

--[[
获取玩家基地的Mail模型
@param homeId number - 基地ID
@return Model|nil - Mail模型
]]
local function GetMailModel(homeId)
	local homeFolder = Workspace:FindFirstChild("Home")
	if not homeFolder then
		return nil
	end

	local playerHome = homeFolder:FindFirstChild("PlayerHome" .. homeId)
	if not playerHome then
		return nil
	end

	return playerHome:FindFirstChild("Mail")
end

--[[
获取Mail模型的有效PrimaryPart（带多级回退机制）
@param mailModel Model - Mail模型
@return BasePart|nil - PrimaryPart
]]
local function GetMailPrimaryPart(mailModel)
	-- 首选：使用Model的PrimaryPart属性
	local primaryPart = mailModel.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	-- 回退1：查找名为"PrimaryPart"的子Part（解决克隆时PrimaryPart引用丢失的问题）
	local namedPart = mailModel:FindFirstChild("PrimaryPart")
	if namedPart and namedPart:IsA("BasePart") then
		mailModel.PrimaryPart = namedPart
		print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 已通过名称'PrimaryPart'找到并设置Mail的PrimaryPart")
		return namedPart
	end

	-- 回退2：递归查找名为"PrimaryPart"的Part（可能在更深层级）
	for _, child in ipairs(mailModel:GetDescendants()) do
		if child.Name == "PrimaryPart" and child:IsA("BasePart") then
			mailModel.PrimaryPart = child
			print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 已在子层级找到并设置Mail的PrimaryPart: " .. child:GetFullName())
			return child
		end
	end

	-- 回退3：使用Mail下的第一个BasePart（如IdleEarnings）
	for _, child in ipairs(mailModel:GetChildren()) do
		if child:IsA("BasePart") then
			mailModel.PrimaryPart = child
			print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 使用备用Part作为Mail的PrimaryPart: " .. child.Name)
			return child
		end
	end

	return nil
end

--[[
更新Mail模型上的金币显示
@param homeId number - 基地ID
@param coins number - 待领取金币数量
@return boolean - 是否更新成功
]]
local function UpdateMailDisplay(homeId, coins)
	local mailModel = GetMailModel(homeId)
	if not mailModel then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] UpdateMailDisplay: 未找到Mail模型, homeId=" .. tostring(homeId))
		return false
	end

	-- 优先按策划结构查找: Mail/IdleEarnings/Fighting/Bg/Number
	local idleEarnings = mailModel:FindFirstChild("IdleEarnings")
	if not idleEarnings then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] UpdateMailDisplay: 未找到IdleEarnings, homeId=" .. tostring(homeId))
		print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] Mail子节点列表:")
		for _, child in ipairs(mailModel:GetChildren()) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return false
	end

	local fightingGui = idleEarnings:FindFirstChild("Fighting")
	if not fightingGui then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] UpdateMailDisplay: 未找到Fighting, homeId=" .. tostring(homeId))
		print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] IdleEarnings子节点列表:")
		for _, child in ipairs(idleEarnings:GetChildren()) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return false
	end

	if not fightingGui:IsA("BillboardGui") then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] UpdateMailDisplay: Fighting不是BillboardGui, 而是 " .. fightingGui.ClassName)
		return false
	end

	-- 确保显示开启
	fightingGui.Enabled = true

	local bg = fightingGui:FindFirstChild("Bg")
	if not bg then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] UpdateMailDisplay: 未找到Bg, homeId=" .. tostring(homeId))
		-- 列出Fighting下的所有子节点
		print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] Fighting子节点:")
		for _, child in ipairs(fightingGui:GetChildren()) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return false
	end

	local numberLabel = bg:FindFirstChild("Number")
	if not (numberLabel and numberLabel:IsA("TextLabel")) then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] UpdateMailDisplay: 未找到Number TextLabel, homeId=" .. tostring(homeId) .. "，请按策划结构创建 Mail/IdleEarnings/Fighting/Bg/Number")
		-- 列出Bg下的所有子节点
		print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] Bg子节点:")
		for _, child in ipairs(bg:GetChildren()) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return false
	end

	local textValue = string.format("%d$", coins)
	numberLabel.Text = textValue

	print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 更新金币显示成功: homeId=" .. homeId .. ", coins=" .. coins)
	return true
end

--[[
计算离线产生的金币
@param lastLogoutTime number - 上次登出时间戳
@return number - 产生的金币数量
]]
local function CalculateOfflineCoins(player, lastLogoutTime)
	if lastLogoutTime <= 0 then
		return 0
	end

	local currentTime = os.time()
	local offlineSeconds = currentTime - lastLogoutTime

	-- 转换为分钟
	local offlineMinutes = math.floor(offlineSeconds / 60)

	-- 限制最大离线时间
	local idleConfig = GetIdleConfigForPlayer(player)
	local maxMinutes = idleConfig.MaxMinutes or 0
	if offlineMinutes > maxMinutes then
		offlineMinutes = maxMinutes
	end

	-- 计算金币
	local coinsPerMinute = idleConfig.CoinsPerMinute or 0
	local coins = offlineMinutes * coinsPerMinute

	return coins
end

--[[
播放领取粒子特效
@param homeId number - 基地ID
]]
local function PlayCollectEffect(homeId)
	local mailModel = GetMailModel(homeId)
	if not mailModel then
		return
	end
	-- 粒子挂在CoinsTrigger
	local coinsTrigger = mailModel:FindFirstChild("CoinsTrigger")
	if not coinsTrigger then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] PlayCollectEffect: 未找到CoinsTrigger, homeId=" .. tostring(homeId) .. "，请按策划结构创建 Mail/CoinsTrigger")
		return
	end

	-- 启用所有粒子发射器
	local particles = {}
	for _, child in ipairs(coinsTrigger:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			child.Enabled = true
			table.insert(particles, child)
		end
	end

	-- 延迟后关闭粒子
	if #particles > 0 then
		task.delay(GameConfig.IdleCoin.ParticleEffectDuration, function()
			for _, particle in ipairs(particles) do
				if particle and particle.Parent then
					particle.Enabled = false
				end
			end
		end)
	end
end

--[[
为指定基地创建ProximityPrompt
@param homeId number - 基地ID
@return boolean, string - 是否创建成功, 错误信息（如果失败）
]]
local function CreateProximityPromptForHome(homeId)
	local mailModel = GetMailModel(homeId)
	if not mailModel then
		local errMsg = "未找到Mail模型, homeId=" .. tostring(homeId)
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] CreateProximityPrompt: " .. errMsg)
		return false, errMsg
	end

	-- 使用Mail模型的PrimaryPart作为交互点（带回退机制）
	local primaryPart = GetMailPrimaryPart(mailModel)
	if not primaryPart then
		local errMsg = "Mail模型未设置PrimaryPart且未找到名为'PrimaryPart'的子Part, homeId=" .. tostring(homeId)
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] CreateProximityPrompt: " .. errMsg)
		print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] Mail模型子节点:")
		for _, child in ipairs(mailModel:GetChildren()) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return false, errMsg
	end

	-- 检查是否已存在
	local existingPrompt = primaryPart:FindFirstChild("IdleCoinPrompt")
	if existingPrompt then
		existingPrompt.ActionText = "Click"
		existingPrompt.HoldDuration = GameConfig.IdleCoin.ProximityHoldDuration
		print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] ProximityPrompt已存在, homeId=" .. homeId)
		return true, "已存在"
	end

	-- 创建ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IdleCoinPrompt"
	prompt.ActionText = "Click"
	prompt.ObjectText = "Idle Coins"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = GameConfig.IdleCoin.ProximityHoldDuration
	prompt.MaxActivationDistance = GameConfig.IdleCoin.ProximityTriggerDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = primaryPart

	-- 交互触发由客户端处理（弹框/领取）

	print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] ✅ 已为基地 " .. homeId .. " 在PrimaryPart: " .. primaryPart.Name .. " 上创建ProximityPrompt")
	return true, "创建成功"
end

--[[
为所有基地创建ProximityPrompt（带重试机制）
🔥V2.6.1增强：增加更详细的错误日志和更长的重试时间
]]
local function SetupAllProximityPrompts()
	local maxRetries = 5
	local retryDelay = 2  -- 秒

	local successCount = 0
	local failedHomes = {}

	for homeId = 1, 6 do
		local success = false
		for attempt = 1, maxRetries do
			success = CreateProximityPromptForHome(homeId)
			if success then
				successCount = successCount + 1
				break
			else
				if attempt < maxRetries then
					print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 基地 " .. homeId .. " ProximityPrompt创建失败, 将在 " .. retryDelay .. " 秒后重试 (尝试 " .. attempt .. "/" .. maxRetries .. ")")
					task.wait(retryDelay)
				else
					warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] ❌ 基地 " .. homeId .. " ProximityPrompt创建失败, 已达到最大重试次数")
					table.insert(failedHomes, homeId)
				end
			end
		end
	end

	-- 输出统计信息
	print(GameConfig.LOG_PREFIX, string.format("[IdleCoinSystem] ProximityPrompt创建完成: 成功 %d/6", successCount))
	if #failedHomes > 0 then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] ❌ 失败的基地: " .. table.concat(failedHomes, ", "))
	end
end

--[[
统一处理挂机金币领取逻辑（支持倍率）
@param player Player - 玩家对象
@param multiplier number - 奖励倍率（默认1）
@param source string - 来源标记（"Idle"/"Purchase"）
@param productId number|nil - 购买产品ID（仅Purchase使用）
@return boolean, number - 是否成功, 发放金币数量
]]
local function ProcessIdleCoinCollect(player, multiplier, source, productId)
	LoadModules()

	-- 获取待领取金币
	local idleCoinData = DataManager.GetIdleCoinData(player)
	local pendingCoins = idleCoinData.PendingCoins or 0

	if pendingCoins <= 0 then
		print(string.format(
			"%s [IdleCoinSystem] 玩家 %s 没有待领取的金币",
			GameConfig.LOG_PREFIX,
			player.Name
		))
		return false, 0
	end

	multiplier = tonumber(multiplier) or 1
	if multiplier <= 0 then
		multiplier = 1
	end

	local awardCoins = math.floor(pendingCoins * multiplier)
	if awardCoins <= 0 then
		return false, 0
	end

	-- 立即播放领取特效
	local homeId = PlayerManager.GetPlayerHomeId(player)
	if homeId and homeId > 0 then
		PlayCollectEffect(homeId)
	end

	-- 播放领取金币音效
	pcall(function()
		SoundSystem.OnCollectIdleCoins(player)
	end)

	-- 发放金币
	local success, newAmount
	if source == "Purchase" then
		success, newAmount = CurrencySystem.AddCoinsFromPurchase(player, awardCoins, productId)
	else
		local idleConfig = GetIdleConfigForPlayer(player)
		local coinsPerMinute = idleConfig.CoinsPerMinute or 0
		local durationSeconds = 0
		if coinsPerMinute and coinsPerMinute > 0 then
			durationSeconds = pendingCoins * 60 / coinsPerMinute
		end
		success, newAmount = CurrencySystem.AddCoinsFromIdle(player, awardCoins, durationSeconds)
	end

	if success then
		-- 清空待领取金币
		DataManager.ClearPendingIdleCoins(player)

		-- 更新显示
		if homeId and homeId > 0 then
			UpdateMailDisplay(homeId, 0)
		end

		-- 通知客户端
		IdleCoinSystem.SyncIdleCoinsToClient(player, 0)

		-- 保存数据
		DataManager.SavePlayerDataThrottled(player)

		-- V3.3任务系统：通知领取挂机金币
		local TaskSystem = nil
		local taskModule = ServerScriptService.Systems:FindFirstChild("TaskSystem")
		if taskModule then
			TaskSystem = require(taskModule)
			TaskSystem.OnCollectIdleCoin(player)
		end

		print(string.format(
			"%s [IdleCoinSystem] 玩家 %s 领取了 %d 挂机金币，当前金币 %d",
			GameConfig.LOG_PREFIX,
			player.Name,
			awardCoins,
			newAmount
		))
	else
		warn(string.format(
			"%s [IdleCoinSystem] 玩家 %s 领取挂机金币失败",
			GameConfig.LOG_PREFIX,
			player.Name
		))
	end

	return success, awardCoins
end

-- ==================== 公共接口 ====================

--[[
🔥V2.6.1新增：为单个玩家的基地创建ProximityPrompt（用于Loading流程）
在玩家加载流程中调用，确保ProximityPrompt在玩家进入游戏前已创建
@param player Player - 玩家对象
@return boolean, string - 是否成功, 消息
]]
function IdleCoinSystem.SetupPlayerMailPrompt(player)
	LoadModules()

	-- 获取玩家的基地ID
	local homeId = PlayerManager.GetPlayerHomeId(player)
	if not homeId or homeId <= 0 then
		local errMsg = "玩家 " .. player.Name .. " 未分配基地"
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] SetupPlayerMailPrompt: " .. errMsg)
		return false, errMsg
	end

	-- 🔥类型断言：此时homeId必定是有效的number（已通过上面的检查）
	local validHomeId = homeId :: number

	-- 为该基地创建ProximityPrompt（带重试机制）
	local maxRetries = 3
	local retryDelay = 0.5

	for attempt = 1, maxRetries do
		local success, message = CreateProximityPromptForHome(validHomeId)
		if success then
			print(GameConfig.LOG_PREFIX, string.format(
				"[IdleCoinSystem] ✅ 玩家 %s 的Mail ProximityPrompt已创建 (基地%d)",
				player.Name,
				validHomeId
			))
			return true, "创建成功"
		else
			if attempt < maxRetries then
				print(GameConfig.LOG_PREFIX, string.format(
					"[IdleCoinSystem] 玩家 %s 的ProximityPrompt创建失败，重试 %d/%d: %s",
					player.Name,
					attempt,
					maxRetries,
					message
				))
				task.wait(retryDelay)
			else
				local errMsg = string.format(
					"玩家 %s 的ProximityPrompt创建失败，已达最大重试次数: %s",
					player.Name,
					message
				)
				warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] " .. errMsg)
				return false, errMsg
			end
		end
	end

	return false, "未知错误"
end

--[[
初始化挂机金币系统
@return boolean - 是否初始化成功
]]
function IdleCoinSystem.Initialize()
	print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 开始初始化挂机金币系统...")

	LoadModules()

	-- 初始化事件
	if not InitializeEvents() then
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 事件初始化失败")
		return false
	end

	-- 连接领取金币事件（客户端通过RemoteEvent触发）
	local collectEvent = IdleCoinEvents:FindFirstChild("CollectIdleCoins")
	if collectEvent then
		collectEvent.OnServerEvent:Connect(function(player)
			-- 验证玩家只能领取自己基地的金币
			local playerHomeId = PlayerManager.GetPlayerHomeId(player)
			if not playerHomeId or playerHomeId <= 0 then
				warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 玩家 " .. player.Name .. " 没有分配基地，拒绝领取请求")
				return
			end
			IdleCoinSystem.OnCollectRequest(player)
		end)
	end

	-- 🔥V2.6.1修复：ProximityPrompt的创建已移至Loading流程
	-- 每个玩家在加载时通过MainServer调用SetupPlayerMailPrompt创建
	-- 不再使用全局延迟创建，确保初始化顺序可控

	print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] 挂机金币系统初始化完成")
	return true
end

--[[
玩家登录时初始化挂机金币
@param player Player - 玩家对象
]]
function IdleCoinSystem.OnPlayerJoin(player)
	LoadModules()

	-- 获取玩家数据
	local idleCoinData = DataManager.GetIdleCoinData(player)
	local lastLogoutTime = idleCoinData.LastLogoutTime or 0
	local existingPendingCoins = idleCoinData.PendingCoins or 0

	-- 计算离线产生的金币
	local offlineCoins = CalculateOfflineCoins(player, lastLogoutTime)

	-- 累加到待领取金币
	local totalPendingCoins = existingPendingCoins + offlineCoins
	DataManager.SetPendingIdleCoins(player, totalPendingCoins)
	local finalPendingCoins = (DataManager.GetIdleCoinData(player).PendingCoins or 0)
	idleCoinData.GuideEligibleOnLogin = (finalPendingCoins > 0)

	-- 获取玩家基地ID（MainServer已等待HomeSlot设置完成，这里应该能直接获取到）
	local homeId = PlayerManager.GetPlayerHomeId(player)

	print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] OnPlayerJoin: 玩家=" .. player.Name .. ", homeId=" .. tostring(homeId) .. ", 待领取金币=" .. finalPendingCoins)

	if homeId and homeId > 0 then
		UpdateMailDisplay(homeId, finalPendingCoins)
	else
		warn(GameConfig.LOG_PREFIX, "[IdleCoinSystem] OnPlayerJoin: HomeId无效，玩家=" .. player.Name)
	end

	-- 通知客户端当前待领取金币数量
	IdleCoinSystem.SyncIdleCoinsToClient(player, finalPendingCoins)

	if offlineCoins > 0 then
		print(string.format(
			"%s [IdleCoinSystem] 玩家 %s 离线产生 %d 金币，总待领取 %d 金币",
			GameConfig.LOG_PREFIX,
			player.Name,
			offlineCoins,
			finalPendingCoins
		))
	end

	-- 🔥V3.9.3新增：启动在线累计金币定时器
	IdleCoinSystem.StartOnlineAccumulation(player)
end

--[[
玩家登出时记录时间
@param player Player - 玩家对象
]]
function IdleCoinSystem.OnPlayerLeave(player)
	LoadModules()

	-- 🔥V3.9.3新增：停止在线累计金币定时器
	IdleCoinSystem.StopOnlineAccumulation(player)

	-- 记录登出时间
	local currentTime = os.time()
	DataManager.SetLastLogoutTime(player, currentTime)

	print(string.format(
		"%s [IdleCoinSystem] 玩家 %s 登出，记录时间 %d",
		GameConfig.LOG_PREFIX,
		player.Name,
		currentTime
	))
end

--[[
🔥V3.9.3新增：启动在线累计金币定时器
@param player Player - 玩家对象
]]
function IdleCoinSystem.StartOnlineAccumulation(player)
	-- 如果已有定时器，先停止
	if onlineTimers[player] then
		IdleCoinSystem.StopOnlineAccumulation(player)
	end

	local interval = GameConfig.IdleCoin.OnlineAccumulateInterval or 60  -- 默认60秒

	-- 创建定时器协程
	onlineTimers[player] = true  -- 标记定时器已启动

	task.spawn(function()
		while onlineTimers[player] and player and player:IsDescendantOf(Players) do
			task.wait(interval)

			-- 再次检查定时器是否仍然有效
			if not onlineTimers[player] or not player or not player:IsDescendantOf(Players) then
				break
			end

			local idleConfig = GetIdleConfigForPlayer(player)
			local coinsPerMinute = idleConfig.CoinsPerMinute or 0
			-- 计算这个间隔产生的金币
			local coinsToAdd = math.floor(coinsPerMinute * (interval / 60))
			if coinsToAdd > 0 then
				-- 添加到待领取金币
				local success, newTotal = DataManager.AddPendingIdleCoins(player, coinsToAdd)
				if success then
					-- 更新显示
					local homeId = PlayerManager.GetPlayerHomeId(player)
					if homeId and homeId > 0 then
						UpdateMailDisplay(homeId, newTotal)
					end

					-- 通知客户端
					IdleCoinSystem.SyncIdleCoinsToClient(player, newTotal)

					print(string.format(
						"%s [IdleCoinSystem] 玩家 %s 在线累计 %d 金币，总待领取 %d 金币",
						GameConfig.LOG_PREFIX,
						player.Name,
						coinsToAdd,
						newTotal
					))
				end
			end
		end

		-- 清理标记
		if onlineTimers[player] then
			onlineTimers[player] = nil
		end
	end)

	local initialConfig = GetIdleConfigForPlayer(player)
	local initialCoinsPerMinute = initialConfig.CoinsPerMinute or 0
	print(string.format(
		"%s [IdleCoinSystem] 玩家 %s 在线累计定时器已启动 (间隔: %d秒, 每分钟: %d金币)",
		GameConfig.LOG_PREFIX,
		player.Name,
		interval,
		initialCoinsPerMinute
	))
end

--[[
🔥V3.9.3新增：停止在线累计金币定时器
@param player Player - 玩家对象
]]
function IdleCoinSystem.StopOnlineAccumulation(player)
	if onlineTimers[player] then
		onlineTimers[player] = nil
		print(string.format(
			"%s [IdleCoinSystem] 玩家 %s 在线累计定时器已停止",
			GameConfig.LOG_PREFIX,
			player.Name
		))
	end
end

--[[
处理玩家领取金币请求
@param player Player - 玩家对象
]]
function IdleCoinSystem.OnCollectRequest(player)
	ProcessIdleCoinCollect(player, 1, "Idle")
end

--[[
处理挂机金币10倍购买发放
@param player Player - 玩家对象
@param productId number - 开发者商品ID
@param multiplier number - 奖励倍率（默认10）
@return boolean, number - 是否成功, 发放金币数量
]]
function IdleCoinSystem.ProcessIdleCoinPurchase(player, productId, multiplier)
	local rewardMultiplier = tonumber(multiplier) or 10
	return ProcessIdleCoinCollect(player, rewardMultiplier, "Purchase", productId)
end

--[[
同步待领取金币到客户端
@param player Player - 玩家对象
@param coins number - 待领取金币数量
]]
function IdleCoinSystem.SyncIdleCoinsToClient(player, coins)
	if not InitializeEvents() then
		return
	end

	local syncEvent = IdleCoinEvents:FindFirstChild("SyncIdleCoins")
	if syncEvent then
		syncEvent:FireClient(player, coins)
	end
end

--[[
GM命令：添加挂机金币（测试用）
@param player Player - 玩家对象
@param minutes number - 模拟离线分钟数
@return boolean, number - 是否成功, 添加的金币数量
]]
function IdleCoinSystem.GMAddIdleCoins(player, minutes)
	LoadModules()

	local idleConfig = GetIdleConfigForPlayer(player)
	local coinsPerMinute = idleConfig.CoinsPerMinute or 0
	local coins = minutes * coinsPerMinute

	-- 添加到待领取金币
	local success, newTotal = DataManager.AddPendingIdleCoins(player, coins)

	if success then
		-- 获取玩家基地ID并更新显示
		local homeId = PlayerManager.GetPlayerHomeId(player)
		print(GameConfig.LOG_PREFIX, "[IdleCoinSystem] GMAddIdleCoins: homeId=" .. tostring(homeId) .. ", newTotal=" .. newTotal)

		if homeId and homeId > 0 then
			UpdateMailDisplay(homeId, newTotal)
		end

		-- 通知客户端
		IdleCoinSystem.SyncIdleCoinsToClient(player, newTotal)

		print(string.format(
			"%s [IdleCoinSystem] GM命令：为玩家 %s 添加 %d 挂机金币（模拟 %d 分钟），总待领取 %d",
			GameConfig.LOG_PREFIX,
			player.Name,
			coins,
			minutes,
			newTotal
		))
	end

	return success, coins
end

--[[
刷新玩家的Mail显示（用于玩家数据加载完成后）
@param player Player - 玩家对象
]]
function IdleCoinSystem.RefreshMailDisplay(player)
	LoadModules()

	local idleCoinData = DataManager.GetIdleCoinData(player)
	local pendingCoins = idleCoinData.PendingCoins or 0

	local homeId = PlayerManager.GetPlayerHomeId(player)
	if homeId and homeId > 0 then
		UpdateMailDisplay(homeId, pendingCoins)
	end
end

return IdleCoinSystem
