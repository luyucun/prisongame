--[[
脚本名称: PlayerManager
脚本类型: ModuleScript (服务端核心)
脚本位置: ServerScriptService/Core/PlayerManager
]]

--[[
玩家管理器模块
职责:
1. 处理玩家加入和离开游戏
2. 随机分配可用基地(1-6)
3. 传送玩家到对应基地的出生点
4. 管理基地占用状态
]]

local PlayerManager = {}

-- 引用服务
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig") :: ModuleScript)
local DataManager = require(ServerScriptService:WaitForChild("Core"):WaitForChild("DataManager") :: ModuleScript)

-- 基地占用状态表 [homeSlot] = player 或 nil
local homeOccupancy = {}

-- 家园归属标记属性名（写在PlayerHome上）
local HOME_OWNER_ATTR = "HomeOwnerUserId"

-- 玩家角色事件连接 [UserId] = Connection (用于清理)
local playerCharacterConnections = {}

local FAST_RESTOCK_SHOP_ID = "UnitShop"
local FAST_RESTOCK_ATTR = "UnitShopFastRestockEndTime"

-- 初始化基地占用表
for i = GameConfig.MIN_HOME_SLOT, GameConfig.MAX_HOME_SLOT do
	homeOccupancy[i] = nil
end

-- ==================== 私有函数 ====================

-- 检查某个HomeSlot是否已被其他在线玩家占用（兜底防止重复分配）
local function IsHomeSlotUsedByActivePlayer(homeSlot, excludePlayer)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= excludePlayer then
			local slot = DataManager.GetPlayerHomeSlot(other)
			if slot == homeSlot then
				return true
			end
		end
	end
	return false
end

--[[
获取所有可用的基地编号
@return table - 可用基地编号列表
]]
local function GetAvailableHomes()
	local available = {}

	for homeSlot = GameConfig.MIN_HOME_SLOT, GameConfig.MAX_HOME_SLOT do
		if homeOccupancy[homeSlot] == nil and not IsHomeSlotUsedByActivePlayer(homeSlot) then
			table.insert(available, homeSlot)
		end
	end

	return available
end

--[[
随机选择一个可用基地
@return number|nil - 基地编号,如果没有可用基地则返回nil
]]
local function SelectRandomHome()
	local availableHomes = GetAvailableHomes()

	if #availableHomes == 0 then
		warn(GameConfig.LOG_PREFIX, "没有可用的基地!")
		return nil
	end

	-- 从可用基地中随机选择一个
	local randomIndex = math.random(1, #availableHomes)
	local selectedHome = availableHomes[randomIndex]

	return selectedHome
end

--[[
随机选择一个可用基地并立即占用（原子操作）
解决竞态条件：选择和占用在同一个操作中完成，避免被其他协程打断
@param player Player - 玩家对象
@return number|nil - 基地编号,如果没有可用基地则返回nil
]]
local function SelectAndOccupyRandomHome(player)
	-- 获取当前可用基地列表的快照
	local availableHomes = GetAvailableHomes()

	if #availableHomes == 0 then
		warn(GameConfig.LOG_PREFIX, "没有可用的基地!")
		return nil
	end

	-- 打乱顺序以实现随机选择（Fisher-Yates洗牌算法）
	for i = #availableHomes, 2, -1 do
		local j = math.random(1, i)
		availableHomes[i], availableHomes[j] = availableHomes[j], availableHomes[i]
	end

	-- 遍历尝试占用，直到成功或全部失败
	for _, homeSlot in ipairs(availableHomes) do
		-- 原子检查并占用（在单线程Lua中，这个检查和赋值之间不会被打断）
		if homeOccupancy[homeSlot] == nil and not IsHomeSlotUsedByActivePlayer(homeSlot, player) then
			homeOccupancy[homeSlot] = player
			return homeSlot
		end
	end

	warn(GameConfig.LOG_PREFIX, "所有基地都已被占用!")
	return nil
end

--[[
占用指定基地
@param homeSlot number - 基地编号
@param player Player - 玩家对象
@return boolean - 是否占用成功
]]
local function OccupyHome(homeSlot, player)
	-- 检查基地是否已被占用
	if homeOccupancy[homeSlot] ~= nil then
		warn(GameConfig.LOG_PREFIX, "基地已被占用:", homeSlot)
		return false
	end

	homeOccupancy[homeSlot] = player

	return true
end

--[[
释放指定基地
@param homeSlot number - 基地编号
]]
local function ReleaseHome(homeSlot)
	if homeOccupancy[homeSlot] then
		homeOccupancy[homeSlot] = nil
	end
end

local function CleanupStaleHomeAssignments()
	-- 清理离线玩家占用（避免幽灵占用导致无可用基地）
	for homeSlot, occupant in pairs(homeOccupancy) do
		if occupant and not occupant:IsDescendantOf(Players) then
			homeOccupancy[homeSlot] = nil
		end
	end

	local homeFolder = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME)
	if not homeFolder then
		return
	end

	local activeUserIds = {}
	for _, player in ipairs(Players:GetPlayers()) do
		activeUserIds[player.UserId] = true
	end

	for homeSlot = GameConfig.MIN_HOME_SLOT, GameConfig.MAX_HOME_SLOT do
		local playerHome = homeFolder:FindFirstChild(GameConfig.HOME_PREFIX .. homeSlot)
		if playerHome then
			local ownerId = playerHome:GetAttribute(HOME_OWNER_ATTR)
			if ownerId ~= nil and not activeUserIds[ownerId] then
				playerHome:SetAttribute(HOME_OWNER_ATTR, nil)
			end
		end
	end
end

--[[
获取基地文件夹
@param homeSlot number - 基地编号
@return Instance|nil - 基地文件夹
]]
local function GetHomeFolder(homeSlot)
	local homeFolder = workspace:FindFirstChild(GameConfig.HOME_FOLDER_NAME)
	if not homeFolder then
		warn(GameConfig.LOG_PREFIX, "找不到Home文件夹!")
		return nil
	end

	local playerHomeName = GameConfig.HOME_PREFIX .. homeSlot
	local playerHome = homeFolder:FindFirstChild(playerHomeName)
	if not playerHome then
		warn(GameConfig.LOG_PREFIX, "找不到基地:", playerHomeName)
		return nil
	end

	return playerHome
end

local function SetHomeOwner(homeSlot, player)
	if not homeSlot or not player then
		return
	end

	local playerHome = GetHomeFolder(homeSlot)
	if playerHome then
		playerHome:SetAttribute(HOME_OWNER_ATTR, player.UserId)
	end
end

local function ClearHomeOwner(homeSlot, player)
	if not homeSlot or not player then
		return
	end

	local playerHome = GetHomeFolder(homeSlot)
	if not playerHome then
		return
	end

	local ownerId = playerHome:GetAttribute(HOME_OWNER_ATTR)
	if ownerId == player.UserId then
		playerHome:SetAttribute(HOME_OWNER_ATTR, nil)
	end
end

local function IsHomeOwnedByPlayer(homeSlot, player)
	if not homeSlot or not player then
		return false
	end

	local playerHome = GetHomeFolder(homeSlot)
	if not playerHome then
		return false
	end

	local ownerId = playerHome:GetAttribute(HOME_OWNER_ATTR)
	return ownerId == player.UserId
end

-- Repair missing/stale HomeOwner markers to keep respawns stable.
local function EnsureHomeOwner(homeSlot, player, context)
	if not homeSlot or not player then
		return false
	end

	local playerHome = GetHomeFolder(homeSlot)
	if not playerHome then
		return false
	end

	local ownerId = playerHome:GetAttribute(HOME_OWNER_ATTR)
	if ownerId == player.UserId then
		return true
	end

	if ownerId ~= nil and ownerId ~= player.UserId then
		warn(GameConfig.LOG_PREFIX, string.format(
			"HomeOwner conflict (%s): PlayerHome%s owner=%s player=%s",
			context or "unknown",
			tostring(homeSlot),
			tostring(ownerId),
			tostring(player.UserId)
		))
		return false
	end

	local occupant = homeOccupancy[homeSlot]
	if occupant and occupant ~= player then
		warn(GameConfig.LOG_PREFIX, string.format(
			"HomeOwner mismatch (%s): PlayerHome%s occupant=%s player=%s",
			context or "unknown",
			tostring(homeSlot),
			occupant and occupant.UserId or "nil",
			tostring(player.UserId)
		))
		return false
	end

	if IsHomeSlotUsedByActivePlayer(homeSlot, player) then
		warn(GameConfig.LOG_PREFIX, string.format(
			"HomeOwner occupied (%s): PlayerHome%s already used by another player",
			context or "unknown",
			tostring(homeSlot)
		))
		return false
	end

	playerHome:SetAttribute(HOME_OWNER_ATTR, player.UserId)
	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "Repaired HomeOwner:", player.Name, "HomeSlot", homeSlot, context or "unknown")
	end

	return true
end

local function IsPlayerActiveInHome(player, homeSlot)
	if not player or not player:IsDescendantOf(Players) then
		return false
	end

	if not homeSlot then
		return false
	end

	local currentHomeSlot = DataManager.GetPlayerHomeSlot(player)
	if currentHomeSlot ~= homeSlot then
		return false
	end

	return IsHomeOwnedByPlayer(homeSlot, player)
end

--[[
获取基地的出生点
@param homeSlot number - 基地编号
@return BasePart|nil - 出生点对象
]]
local function GetHomeSpawnLocation(homeSlot)
	local playerHome = GetHomeFolder(homeSlot)
	if not playerHome then
		return nil
	end

	local spawnLocation = playerHome:FindFirstChild(GameConfig.SPAWN_LOCATION_NAME)
	if not spawnLocation then
		warn(GameConfig.LOG_PREFIX, "找不到出生点:", playerHome.Name .. "/" .. GameConfig.SPAWN_LOCATION_NAME)
		return nil
	end

	return spawnLocation
end

local function IsCharacterNearHomeSpawn(character, homeSlot, maxDistance)
	if not character or not homeSlot then
		return false
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false
	end

	local spawnLocation = GetHomeSpawnLocation(homeSlot)
	if not spawnLocation then
		return false
	end

	local distance = (humanoidRootPart.Position - spawnLocation.Position).Magnitude
	return distance <= (maxDistance or 20)
end

-- Bind player's RespawnLocation to the assigned home spawn when possible.
local function BindPlayerRespawnLocation(player, homeSlot)
	if not player or not homeSlot then
		return false
	end

	local spawnLocation = GetHomeSpawnLocation(homeSlot)
	if not spawnLocation then
		return false
	end

	if not spawnLocation:IsA("SpawnLocation") then
		if GameConfig.DEBUG_MODE then
			warn(GameConfig.LOG_PREFIX, "RespawnLocation expects SpawnLocation:", homeSlot)
		end
		return false
	end

	player.RespawnLocation = spawnLocation
	return true
end

--[[
根据位置选择最近的可用基地
用于Studio Play Here模式,确保分配的基地与玩家实际位置一致
@param position Vector3 - 玩家当前位置
@return number|nil - 最近的可用基地编号,如果没有可用基地则返回nil
]]
local function FindClosestAvailableHome(position)
	local availableHomes = GetAvailableHomes()

	if #availableHomes == 0 then
		warn(GameConfig.LOG_PREFIX, "没有可用的基地!")
		return nil
	end

	local closestHome = nil
	local closestDistance = math.huge

	-- 遍历所有可用基地,找到最近的
	for _, homeSlot in ipairs(availableHomes) do
		local spawnLocation = GetHomeSpawnLocation(homeSlot)
		if spawnLocation then
			local distance = (spawnLocation.Position - position).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestHome = homeSlot
			end
		end
	end

	return closestHome
end

--[[
根据位置选择最近的可用基地并立即占用（原子操作）
用于Studio Play Here模式,确保分配的基地与玩家实际位置一致
解决竞态条件：选择和占用在同一个操作中完成，避免被其他协程打断
@param position Vector3 - 玩家当前位置
@param player Player - 玩家对象
@return number|nil - 最近的可用基地编号,如果没有可用基地则返回nil
]]
local function FindClosestAvailableHomeAndOccupy(position, player)
	local availableHomes = GetAvailableHomes()

	if #availableHomes == 0 then
		warn(GameConfig.LOG_PREFIX, "没有可用的基地!")
		return nil
	end

	-- 计算每个基地的距离并排序
	local homesWithDistance = {}
	for _, homeSlot in ipairs(availableHomes) do
		local spawnLocation = GetHomeSpawnLocation(homeSlot)
		if spawnLocation then
			local distance = (spawnLocation.Position - position).Magnitude
			table.insert(homesWithDistance, {homeSlot = homeSlot, distance = distance})
		end
	end

	-- 按距离从近到远排序
	table.sort(homesWithDistance, function(a, b)
		return a.distance < b.distance
	end)

	-- 按距离从近到远尝试占用，直到成功或全部失败
	for _, data in ipairs(homesWithDistance) do
		local homeSlot = data.homeSlot
		-- 原子检查并占用（在单线程Lua中，这个检查和赋值之间不会被打断）
		if homeOccupancy[homeSlot] == nil and not IsHomeSlotUsedByActivePlayer(homeSlot, player) then
			homeOccupancy[homeSlot] = player
			return homeSlot
		end
	end

	warn(GameConfig.LOG_PREFIX, "所有基地都已被占用!")
	return nil
end

--[[
传送玩家到指定基地
@param player Player - 玩家对象
@param homeSlot number - 基地编号
@return boolean - 是否传送成功
]]
local function TeleportPlayerToHome(player, homeSlot, characterOverride)
	-- 检查玩家和基地编号的有效性
	if not player or not homeSlot then
		warn(GameConfig.LOG_PREFIX, "TeleportPlayerToHome: 参数无效")
		return false
	end

	-- 检查角色是否存在
	local character = characterOverride or player.Character
	if not character then
		warn(GameConfig.LOG_PREFIX, "TeleportPlayerToHome: 角色不存在", player.Name)
		return false
	end

	if characterOverride and player.Character ~= characterOverride then
		return false
	end

	-- 等待HumanoidRootPart加载(最多等待15秒)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 15)
	if not humanoidRootPart then
		warn(GameConfig.LOG_PREFIX, "找不到玩家的HumanoidRootPart:", player.Name)
		return false
	end

	-- 获取出生点
	local spawnLocation = GetHomeSpawnLocation(homeSlot)
	if not spawnLocation then
		warn(GameConfig.LOG_PREFIX, "获取出生点失败:", homeSlot)
		return false
	end

	-- 验证spawnLocation的有效性
	if not spawnLocation:IsA("BasePart") then
		warn(GameConfig.LOG_PREFIX, "SpawnLocation不是有效的BasePart:", homeSlot)
		return false
	end

	-- 传送玩家
	humanoidRootPart.CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)  -- 向上偏移5避免卡地

	return true
end

--[[
判断是否应该跳过家园分配
当在Studio中使用"从此处开始游戏"功能时，跳过家园分配
@param player Player - 玩家对象
@return boolean - 是否应该跳过家园分配
]]
local function ShouldSkipHomeAssignment(player)
	-- 首先检查是否在Studio环境中
	if not RunService:IsStudio() then
		return false
	end

	-- 尝试获取玩家的 JoinData
	local success, joinData = pcall(function()
		return player:GetJoinData()
	end)

	-- 在 Studio 的 PlayHere 模式下，GetJoinData 通常返回空表或 nil
	-- 正式服务器或普通 Play 模式会有 TeleportData 等字段
	if not success or not joinData or (type(joinData) == "table" and next(joinData) == nil) then
		return true
	end

	return false
end

-- ==================== 公共接口 ====================

--[[
处理玩家加入游戏
@param player Player - 玩家对象
]]
local function GetServerNow()
	local ok, serverNow = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(serverNow) == "number" and serverNow > 0 then
		return serverNow
	end
	return os.time()
end

function PlayerManager.OnPlayerAdded(player)
	-- 修复：首先检查player对象是否有效
	if not player or not player:IsA("Player") or not player:IsDescendantOf(Players) then
		warn(GameConfig.LOG_PREFIX, "OnPlayerAdded收到无效的player对象")
		return
	end

	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "玩家加入:", player.Name)
	end

	CleanupStaleHomeAssignments()

	-- 1. 初始化玩家数据
	local playerData = DataManager.InitializePlayerData(player)
	if not playerData then
		warn(GameConfig.LOG_PREFIX, "Player data load failed, kicking -", player.Name)
		player:Kick("Data load failed. Please rejoin.")
		return
	end

	if not player or not player:IsDescendantOf(Players) then
		return
	end

	-- V6.8 sync fast restock absolute end time (offline countdown)
	do
		local endTime = tonumber(DataManager.GetShopFastRestockEndTime(player, FAST_RESTOCK_SHOP_ID)) or 0
		if endTime < 0 then
			endTime = 0
		end
		local now = GetServerNow()
		if endTime > 0 and endTime <= now then
			DataManager.SetShopFastRestockEndTime(player, FAST_RESTOCK_SHOP_ID, 0)
			endTime = 0
		end
		player:SetAttribute(FAST_RESTOCK_ATTR, endTime)
	end

	-- V4.8七日登录奖励：同步功能解锁状态（通关第一章后解锁）
	local completedChapters = DataManager.GetCompletedChapters(player) or 0
	player:SetAttribute("SevenDaysUnlocked", completedChapters >= 1)
	player:SetAttribute("CompletedChapters", completedChapters)

	local currentHouseModel = DataManager.GetCurrentHouseModel(player)
	player:SetAttribute("CurrentHouseModel", currentHouseModel)

	-- V4.9加入群组奖励：同步领取状态
	local groupRewardData = DataManager.GetGroupRewardData(player)
	player:SetAttribute("GroupRewardClaimed", groupRewardData and groupRewardData.Claimed == true)

	-- 2. 检查是否在Studio Play Here模式下
	local skipHomeAssignment = ShouldSkipHomeAssignment(player)

	if not player or not player:IsDescendantOf(Players) then
		return
	end

	-- 3. 选择并占用基地（使用原子操作，解决竞态条件）
	local homeSlot = nil

	if skipHomeAssignment then
		-- Studio Play Here模式：根据玩家当前位置选择最近的基地
		-- 需要等待角色加载完成
		-- 修复：在访问CharacterAdded前再次检查player有效性
		if not player or not player:IsDescendantOf(Players) then
			warn(GameConfig.LOG_PREFIX, "玩家对象在Play Here模式下已失效")
			return
		end

		local character = player.Character or player.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)

		if humanoidRootPart then
			-- 根据玩家当前位置找到最近的可用基地并立即占用（原子操作）
			homeSlot = FindClosestAvailableHomeAndOccupy(humanoidRootPart.Position, player)
		else
			warn(GameConfig.LOG_PREFIX, "Play Here模式下无法获取角色位置，回退到随机分配")
		end
	end

	-- 如果没有通过位置选择到基地，则随机选择并占用（原子操作）
	if not homeSlot then
		homeSlot = SelectAndOccupyRandomHome(player)
	end

	if not homeSlot then
		warn(GameConfig.LOG_PREFIX, "无法为玩家分配基地,服务器已满!", player.Name)
		player:Kick("服务器已满，请稍后重试")
		return
	end

	-- 注意：基地已在上面的原子操作中被占用，无需再调用OccupyHome

	if not player or not player:IsDescendantOf(Players) then
		ReleaseHome(homeSlot)
		return
	end

	-- 5. 设置玩家数据中的基地编号
	DataManager.SetPlayerHomeSlot(player, homeSlot)

	-- 5.1 同步HomeSlot到客户端（用于客户端确定正确的IdleFloor）
	player:SetAttribute("HomeSlot", homeSlot)
	BindPlayerRespawnLocation(player, homeSlot)

	-- 5.2 标记家园归属（用于防止旧玩家异步流程误操作）
	SetHomeOwner(homeSlot, player)

	-- 6. 初始化玩家基地(HomeSystem)
	local homeModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("HomeSystem")
	if homeModule then
		local HomeSystem = require(homeModule :: ModuleScript)
		local initSuccess = HomeSystem.InitializePlayerHome(homeSlot, player)  -- V2.0.1修复：传入正确的参数 (homeId, player)
		if not initSuccess then
			warn(GameConfig.LOG_PREFIX, "基地初始化失败，释放资源:", player.Name, "HomeSlot:", homeSlot)
			ClearHomeOwner(homeSlot, player)
			ReleaseHome(homeSlot)
			if player and player:IsDescendantOf(Players) then
				player:Kick("基地初始化失败，请重新加入")
			end
			return
		end
	end

	-- 6.5 V2.0.1新增：生成Stage001（如果不存在）
	-- 注意：必须在HomeSystem初始化后执行，确保Stage文件夹存在
	task.spawn(function()
		-- 短暂延迟，确保HomeSystem初始化完成
		task.wait(0.1)

		-- 修复：使用安全的require方式避免类型警告
		if not IsPlayerActiveInHome(player, homeSlot) then
			return
		end

		local stageModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("StageService")
		if stageModule then
			local StageService = require(stageModule :: ModuleScript)
			local stage001 = StageService.GetOrCreateStage(player.UserId, 1)
			if not stage001 and GameConfig.DEBUG_MODE then
				warn(GameConfig.LOG_PREFIX, "Stage001生成失败:", player.Name, "HomeSlot:", homeSlot)
			end
		end
	end)

	-- 6.6 V2.1新增：初始化商店库存定时器
	task.spawn(function()
		-- 短暂延迟，确保其他系统初始化完成
		task.wait(0.5)

		-- 修复：使用安全的require方式避免类型警告
		local ShopSystem = ServerScriptService:WaitForChild("Systems"):FindFirstChild("ShopSystem")
		if ShopSystem then
			local shopModule = require(ShopSystem :: ModuleScript)
			if shopModule.InitializePlayerShopTimer then
				shopModule.InitializePlayerShopTimer(player, "UnitShop")
			end
		end
	end)

	-- 🔥修复金币显示延迟：6.7 主动推送初始金币
	task.spawn(function()
		-- 等待数据加载完成
		task.wait(0.3)

		local CurrencySystem = ServerScriptService.Systems:FindFirstChild("CurrencySystem")
		if CurrencySystem then
			local currencyModule = require(CurrencySystem)
			if currencyModule.PushInitialCurrency then
				currencyModule.PushInitialCurrency(player)
			end
		end
	end)

	-- 🔥修复持久化：6.8 恢复玩家的放置单位（在背包系统初始化后执行）
	task.spawn(function()
		-- 等待基地和背包系统完全初始化
		task.wait(1.0)

		if not IsPlayerActiveInHome(player, homeSlot) then
			return
		end

		local PlacementSystem = ServerScriptService.Systems:FindFirstChild("PlacementSystem")
		if PlacementSystem then
			local placementModule = require(PlacementSystem)
			if placementModule.RestorePlacedUnits then
				local success, message = placementModule.RestorePlacedUnits(player)
				if success then
					-- print(string.format(
					--     "%s [PlayerManager] 🔥 玩家 %s 放置单位恢复成功: %s",
					--     GameConfig.LOG_PREFIX,
					--     player.Name,
					--     message
					-- ))
				else
					warn(string.format(
						"%s [PlayerManager] 🔥 玩家 %s 放置单位恢复失败: %s",
						GameConfig.LOG_PREFIX,
						player.Name,
						message
						))
				end
			end
		end
	end)

	-- V2.8.2修改：房屋初始化已移至HomeSystem.InitializePlayerHome中同步执行
	-- 不再需要延迟初始化，删除原有的task.spawn延迟代码

	-- 7. 处理角色传送 - 使用异步方式避免阻塞
	-- 标记是否应跳过首次传送（用于Studio Play Here模式）
	local shouldSkipFirstTeleport = skipHomeAssignment

	-- 标记是否已经处理过初始角色（防止重复传送）
	local hasProcessedInitialCharacter = false

	local function HandleCharacterSpawn(character)
		task.spawn(function()
			-- 检查是否应跳过首次传送（Studio Play Here模式）
			if shouldSkipFirstTeleport then
				shouldSkipFirstTeleport = false  -- 只跳过第一次，后续重生正常传送
				if IsCharacterNearHomeSpawn(character, homeSlot) then
					hasProcessedInitialCharacter = true  -- 标记已处理初始角色
					return
				end
			end

			-- 等待一小段时间确保角色完全加载
			task.wait(0.1)

			-- 兜底：确保HomeSlot在服务端与客户端一致
			local currentHomeSlot = DataManager.GetPlayerHomeSlot(player)
			if currentHomeSlot ~= homeSlot then
				DataManager.SetPlayerHomeSlot(player, homeSlot)
				if GameConfig.DEBUG_MODE then
					print(GameConfig.LOG_PREFIX, "Resynced HomeSlot:", player.Name, currentHomeSlot, "->", homeSlot)
				end
			end
			player:SetAttribute("HomeSlot", homeSlot)

			if not IsPlayerActiveInHome(player, homeSlot) then
				-- Repair missing/stale owner markers to avoid skipping teleport on respawn.
				local repaired = EnsureHomeOwner(homeSlot, player, "CharacterSpawn")
				if not repaired then
					return
				end
			end

			local success = TeleportPlayerToHome(player, homeSlot, character)
			if not success then
				warn(GameConfig.LOG_PREFIX, "传送失败,将在角色重生时重试:", player.Name)
			end
		end)
	end

	-- 连接玩家重生事件（必须在检查Character之前连接，避免竞态条件）
	-- 修复：在访问CharacterAdded前再次检查player有效性
	if not player or not player:IsDescendantOf(Players) then
		warn(GameConfig.LOG_PREFIX, "玩家对象在CharacterAdded连接时已失效:", player and player.Name or "nil")
		return
	end

	local characterAddedConnection = player.CharacterAdded:Connect(function(character)
		HandleCharacterSpawn(character)
	end)

	-- 保存连接以便后续清理
	playerCharacterConnections[player.UserId] = characterAddedConnection

	-- 如果角色已存在，且CharacterAdded还未触发，则手动处理一次
	-- 使用task.defer确保在CharacterAdded连接后执行，避免重复
	if player.Character and not hasProcessedInitialCharacter then
		task.defer(function()
			-- 再次检查，防止CharacterAdded已经触发
			if not hasProcessedInitialCharacter then
				hasProcessedInitialCharacter = true
				HandleCharacterSpawn(player.Character)
			end
		end)
	end

	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "玩家", player.Name, "初始化完成,基地编号:", homeSlot)
	end
end

--[[
处理玩家离开游戏
@param player Player - 玩家对象
]]
function PlayerManager.OnPlayerRemoving(player)
	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "玩家离开:", player.Name)
	end

	-- 1. 获取玩家的基地编号
	local homeSlot = DataManager.GetPlayerHomeSlot(player)

	-- 2. 断开CharacterAdded连接
	if playerCharacterConnections[player.UserId] then
		playerCharacterConnections[player.UserId]:Disconnect()
		playerCharacterConnections[player.UserId] = nil
	end

	-- 3. 清除基地系统数据
	local homeModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("HomeSystem")
	if homeModule then
		local HomeSystem = require(homeModule :: ModuleScript)
		if homeSlot and homeSlot > 0 then
			HomeSystem.CleanupPlayerHome(homeSlot, player)  -- V2.0.1修复：调用正确的方法并传入homeId
		end
	end

	-- 4. 清除家园归属标记并释放基地（避免复用时旧流程误操作）
	if homeSlot and homeSlot > 0 then
		ClearHomeOwner(homeSlot, player)
		ReleaseHome(homeSlot)
	end

	-- 🔥修复服务器关闭时数据保存：检查是否正在关机
	local isShuttingDown = DataManager.IsShuttingDown and DataManager.IsShuttingDown() or false

	-- 延迟加载PlacementSystem避免重复require
	local placementModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("PlacementSystem")
	local PlacementSystem = nil
	if placementModule then
		PlacementSystem = require(placementModule :: ModuleScript)
	end

	if not isShuttingDown then
		-- 正常离开：执行完整清理流程
		-- 🔥修复持久化：4.5 清理放置系统数据（在数据保存之前）
		if PlacementSystem then
			PlacementSystem.OnPlayerLeaving(player)
		end

		-- 🔥修复：清理关卡缓存/关卡场景（防止玩家离线后关卡仍残留在家园中）
		local stageModule = ServerScriptService:WaitForChild("Systems"):FindFirstChild("StageService")
		if stageModule then
			local StageService = require(stageModule :: ModuleScript)
			if StageService and StageService.CleanupStages then
				pcall(function()
					StageService.CleanupStages(player.UserId)
				end)
			end
		end

		-- 5. 清除玩家数据
		DataManager.ClearPlayerData(player)
	else
		-- 服务器关闭：只清理放置系统数据，保留缓存供BindToClose使用
		if PlacementSystem then
			PlacementSystem.OnPlayerLeaving(player)
		end

		-- 注意：不调用 DataManager.ClearPlayerData，让BindToClose能够访问缓存
		print(string.format(
			"%s [PlayerManager] 服务器关闭中，跳过玩家 %s 的缓存清理",
			GameConfig.LOG_PREFIX,
			player.Name
			))
	end
end

--[[
获取基地占用状态(调试用)
@return table - 基地占用状态表
]]
function PlayerManager.GetHomeOccupancy()
	return homeOccupancy
end

--[[
获取可用基地数量
@return number - 可用基地数量
]]
function PlayerManager.GetAvailableHomeCount()
	return #GetAvailableHomes()
end

--[[
获取玩家的HomeId
@param player Player - 玩家对象
@return number - HomeId (1~6), 如果未分配则返回nil
]]
function PlayerManager.GetPlayerHomeId(player)
	if not player then
		return nil
	end
	return DataManager.GetPlayerHomeSlot(player)
end

--[[
初始化玩家管理器
连接玩家加入和离开事件
]]
function PlayerManager.Initialize()
	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "初始化PlayerManager...")
	end

	-- 连接玩家加入事件
	Players.PlayerAdded:Connect(PlayerManager.OnPlayerAdded)

	-- 连接玩家离开事件
	Players.PlayerRemoving:Connect(PlayerManager.OnPlayerRemoving)

	-- 处理已经在游戏中的玩家(用于测试)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			PlayerManager.OnPlayerAdded(player)
		end)
	end

	if GameConfig.DEBUG_MODE then
		print(GameConfig.LOG_PREFIX, "PlayerManager初始化完成")
	end
end

return PlayerManager
