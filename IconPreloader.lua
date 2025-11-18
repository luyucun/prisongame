--[[
脚本名称: IconPreloader
脚本类型: LocalScript (客户端)
脚本位置: StarterPlayer/StarterPlayerScripts/IconPreloader
版本: V2.3
]]

--[[
图标预加载系统
职责:
1. 在游戏启动时预加载所有兵种图标
2. 使用ContentProvider批量下载图片资源
3. 避免打开商店/背包时图标加载卡顿
4. 提供加载进度日志

使用说明:
- 此脚本会在玩家进入游戏后自动运行
- 预加载会在后台异步进行,不阻塞游戏
- 预加载完成后,商店和背包的图标会立即显示
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- 配置
local DEBUG_MODE = true
local LOG_PREFIX = "[IconPreloader]"

-- 延迟启动时间(秒) - 等待其他系统初始化
local STARTUP_DELAY = 0.5

-- 日志函数
local function Log(...)
	if DEBUG_MODE then
		print(LOG_PREFIX, ...)
	end
end

--[[
收集所有需要预加载的图标资源
@return table - 资源ID数组
]]
local function CollectIconAssets()
	local assets = {}
	local assetSet = {}  -- 用于去重

	-- 等待UnitConfig加载
	local configFolder = ReplicatedStorage:WaitForChild("Config", 10)
	if not configFolder then
		warn(LOG_PREFIX, "找不到Config文件夹")
		return assets
	end

	local unitConfigModule = configFolder:WaitForChild("UnitConfig", 10)
	if not unitConfigModule then
		warn(LOG_PREFIX, "找不到UnitConfig模块")
		return assets
	end

	-- 加载UnitConfig
	local success, UnitConfig = pcall(require, unitConfigModule)
	if not success then
		warn(LOG_PREFIX, "加载UnitConfig失败:", UnitConfig)
		return assets
	end

	-- 遍历所有兵种,收集图标资源
	local unitCount = 0
	for unitId, unitData in pairs(UnitConfig.Units) do
		if unitData.Icon and unitData.Icon ~= "" then
			-- 提取资源ID
			local iconAssetId = unitData.Icon

			-- 确保格式为 rbxassetid://数字
			if string.match(iconAssetId, "rbxassetid://") then
				-- 去重检查
				if not assetSet[iconAssetId] then
					assetSet[iconAssetId] = true
					table.insert(assets, iconAssetId)
					unitCount = unitCount + 1
				end
			elseif tonumber(iconAssetId) then
				-- 如果只是数字,转换为完整格式
				local fullAssetId = "rbxassetid://" .. iconAssetId
				if not assetSet[fullAssetId] then
					assetSet[fullAssetId] = true
					table.insert(assets, fullAssetId)
					unitCount = unitCount + 1
				end
			else
				warn(LOG_PREFIX, "兵种", unitId, "的图标格式无效:", iconAssetId)
			end
		end
	end

	Log(string.format("收集到 %d 个兵种的 %d 个唯一图标", unitCount, #assets))
	return assets
end

--[[
预加载图标资源
@param assets table - 资源ID数组
]]
local function PreloadIcons(assets)
	if #assets == 0 then
		warn(LOG_PREFIX, "没有需要预加载的图标")
		return
	end

	Log("开始预加载图标...")

	local startTime = tick()
	local successCount = 0
	local failCount = 0

	-- V2.3增强: 分批预加载,避免一次性加载过多导致卡顿
	local BATCH_SIZE = 10  -- 每批处理10个图标
	local totalBatches = math.ceil(#assets / BATCH_SIZE)

	for batchIndex = 1, totalBatches do
		local startIdx = (batchIndex - 1) * BATCH_SIZE + 1
		local endIdx = math.min(batchIndex * BATCH_SIZE, #assets)
		local batch = {}

		-- 准备当前批次
		for i = startIdx, endIdx do
			table.insert(batch, assets[i])
		end

		-- 预加载当前批次
		local batchSuccess, batchErr = pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)

		if batchSuccess then
			successCount = successCount + #batch
			Log(string.format("批次 %d/%d 完成 (%d 个图标)", batchIndex, totalBatches, #batch))
		else
			failCount = failCount + #batch
			warn(LOG_PREFIX, string.format("批次 %d 失败:", batchIndex), batchErr)
		end

		-- 批次间短暂等待,避免阻塞主线程
		if batchIndex < totalBatches then
			task.wait(0.1)
		end
	end

	local endTime = tick()
	local duration = endTime - startTime

	Log(string.format("✅ 图标预加载完成! 成功: %d, 失败: %d, 耗时: %.2f 秒",
		successCount, failCount, duration))

	-- 设置全局标记,表示预加载完成
	_G.IconPreloadComplete = true
	_G.IconPreloadStats = {
		Total = #assets,
		Success = successCount,
		Failed = failCount,
		Duration = duration
	}
end

--[[
主初始化函数
]]
local function Initialize()
	-- 等待玩家加载
	if not player.Character then
		player.CharacterAdded:Wait()
	end

	-- 延迟启动,避免影响其他系统初始化
	task.wait(STARTUP_DELAY)

	Log("图标预加载系统启动中...")

	-- 收集资源
	local assets = CollectIconAssets()

	-- 预加载
	PreloadIcons(assets)
end

-- 启动预加载系统
task.spawn(function()
	local success, err = pcall(Initialize)
	if not success then
		warn(LOG_PREFIX, "初始化失败:", err)
	end
end)

Log("图标预加载脚本已加载")
