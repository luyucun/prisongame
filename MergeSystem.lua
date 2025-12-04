--[[
脚本名称: MergeSystem
脚本类型: ModuleScript (服务端系统)
脚本位置: ServerScriptService/Systems/MergeSystem
]]

--[[
兵种合成系统模块
职责:
1. 处理两个相同兵种的合成
2. 验证合成条件（等级、UnitId）
3. 生成更高等级的兵种
4. 同步合成结果到客户端
5. 播放合成特效 (V1.5.3新增)
版本: V1.5.3
]]

local MergeSystem = {}

-- 引用服务
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 引用模块
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))
local PlacementConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PlacementConfig"))
local DataManager = require(ServerScriptService.Core.DataManager)  -- 🔥修复持久化：添加DataManager引用
local InventorySystem = require(ServerScriptService.Systems.InventorySystem)
local PlacementSystem = require(ServerScriptService.Systems.PlacementSystem)

-- 延迟加载系统模块（避免循环依赖）
local TaskSystem = nil

-- 远程事件(延迟获取)
local MergeEvents = nil

-- ==================== 私有函数 ====================

--[[
播放合成特效 (V1.5.3新增)
@param position Vector3 - 特效播放位置
@param gridSize number - 兵种占地大小(1/4/9)
]]
local function PlayMergeEffect(position, gridSize)
	local effectFolder = ReplicatedStorage:FindFirstChild("Effect")
	if not effectFolder then
		return
	end

	-- 根据GridSize选择特效
	local effectName = nil
	if gridSize == 1 then
		effectName = "Merge01"
	elseif gridSize == 4 then
		effectName = "Merge02"
	elseif gridSize == 9 then
		effectName = "Merge03"
	else
		return
	end

	local effectTemplate = effectFolder:FindFirstChild(effectName)
	if not effectTemplate then
		return
	end

	-- 1. 克隆特效父节点（子节点通过Weld自动跟随）
	local effect = effectTemplate:Clone()

	-- 2. 先挂载到Workspace
	effect.Parent = Workspace

	-- 3. 立即锚定父节点，防止物理引擎干扰（子节点保持不锚定）
	if effect:IsA("Model") then
		-- Model类型：锚定PrimaryPart
		if effect.PrimaryPart then
			effect.PrimaryPart.Anchored = true
		end
	elseif effect:IsA("BasePart") then
		-- BasePart类型：直接锚定父节点
		effect.Anchored = true
	end

	-- 4. 移动到目标位置（父节点已锚定，子节点通过Weld跟随）
	if effect:IsA("Model") then
		effect:PivotTo(CFrame.new(position))
	elseif effect:IsA("BasePart") then
		effect.CFrame = CFrame.new(position)
	end


	-- 4. 3秒后移除特效父节点
	task.delay(3, function()
		if effect and effect.Parent then
			effect:Destroy()
		end
	end)
end

--[[
初始化远程事件
@return boolean - 是否成功
]]
local function InitializeEvents()
    if not MergeEvents then
        local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
        if eventsFolder then
            MergeEvents = eventsFolder:FindFirstChild("MergeEvents")
        end

        if not MergeEvents and GameConfig.DEBUG_MODE then
            warn(GameConfig.LOG_PREFIX, "MergeEvents未找到!")
        end
    end
    return MergeEvents ~= nil
end

-- ==================== 公共接口 ====================

--[[
验证两个兵种是否可以合成
@param player Player
@param instanceIdA string - 兵种A的实例ID
@param instanceIdB string - 兵种B的实例ID
@return boolean, string - 是否可以合成, 失败原因
]]
function MergeSystem.CanMerge(player, instanceIdA, instanceIdB)
    -- 1. 检查两个实例ID不能相同
    if instanceIdA == instanceIdB then
        return false, "不能合成相同的兵种"
    end

    -- 2. 获取两个兵种实例
    local unitA = InventorySystem.GetUnitByInstanceId(player, instanceIdA)
    local unitB = InventorySystem.GetUnitByInstanceId(player, instanceIdB)

    if not unitA then
        return false, "兵种A不存在"
    end

    if not unitB then
        return false, "兵种B不存在"
    end

    -- 3. 检查两个兵种是否都已放置
    if not unitA.IsPlaced then
        return false, "兵种A未放置"
    end

    if not unitB.IsPlaced then
        return false, "兵种B未放置"
    end

    -- 4. 检查UnitId是否相同
    if unitA.UnitId ~= unitB.UnitId then
        return false, "兵种类型不同，无法合成"
    end

    -- 5. 检查等级是否相同
    if unitA.Level ~= unitB.Level then
        return false, "兵种等级不同，无法合成"
    end

    -- 6. 检查是否已经达到最高等级
    if unitA.Level >= UnitConfig.MAX_LEVEL then
        return false, "已达到最高等级，无法合成"
    end

    return true, "可以合成"
end

--[[
合成两个兵种
@param player Player
@param instanceIdA string - 要拖动的兵种实例ID
@param instanceIdB string - 目标兵种实例ID
@return boolean, string, table|nil - 是否成功, 消息, 新兵种实例数据
]]
function MergeSystem.MergeUnits(player, instanceIdA, instanceIdB)
    -- 1. 验证是否可以合成
    local canMerge, message = MergeSystem.CanMerge(player, instanceIdA, instanceIdB)
    if not canMerge then
        return false, message, nil
    end

    -- 2. 获取兵种实例
    local unitA = InventorySystem.GetUnitByInstanceId(player, instanceIdA)
    local unitB = InventorySystem.GetUnitByInstanceId(player, instanceIdB)

    -- 3. 记录位置（使用B的位置）和GridSize，并获取兵种脚底位置
    local mergePosition = unitB.PlacedPosition
    local newLevel = unitA.Level + 1

    -- 获取兵种配置以获取GridSize
    local unitConfig = UnitConfig.GetUnitById(unitA.UnitId)
    local gridSize = unitConfig and unitConfig.GridSize or 1

    -- 获取场上兵种B的模型，用于计算脚底位置
    local unitModelB = nil

    -- 计算IdleFloor顶面高度作为默认特效位置（去除PLACEMENT_Y_OFFSET偏移）
    local baseY = mergePosition.Y - PlacementConfig.PLACEMENT_Y_OFFSET
    local effectPosition = Vector3.new(mergePosition.X, baseY, mergePosition.Z)

    -- 尝试在Workspace中找到兵种B的模型
    for _, model in ipairs(Workspace:GetChildren()) do
        if model:IsA("Model") and model.Name == unitB.UnitId then
            -- 检查是否有InstanceId属性或UnitInstanceId子节点（兼容两种方式）
            local instanceAttr = model:GetAttribute("InstanceId")
            local instanceTag = model:FindFirstChild("UnitInstanceId")
            local matchedId = instanceAttr or (instanceTag and instanceTag.Value)

            if matchedId == instanceIdB then
                unitModelB = model
                break
            end
        end
    end

    -- 如果找到模型，计算脚底位置
    if unitModelB then
        local hrp = unitModelB:FindFirstChild("HumanoidRootPart")
        local humanoid = unitModelB:FindFirstChildOfClass("Humanoid")

        if hrp then
            -- 计算脚底位置：优先使用HipHeight，如果为0或nil则使用HRP Size
            local bottomY = hrp.Position.Y
            if humanoid and humanoid.HipHeight and humanoid.HipHeight > 0 then
                -- 使用HipHeight计算脚底
                bottomY = hrp.Position.Y - humanoid.HipHeight
            else
                -- 使用HumanoidRootPart的Size计算脚底
                bottomY = hrp.Position.Y - (hrp.Size.Y / 2)
            end

            -- 使用更低的Y值：取IdleFloor顶面高度和计算出的脚底高度中更低的值
            local finalY = math.min(baseY, bottomY)
            effectPosition = Vector3.new(hrp.Position.X, finalY, hrp.Position.Z)

        else
        end
    else
    end


    -- 4. 先创建新兵种（确保创建成功后再移除旧兵种，避免数据丢失）
    local success, newInstance = InventorySystem.AddUnit(player, unitA.UnitId)

    if not success then
        warn(GameConfig.LOG_PREFIX, "创建合成兵种失败:", newInstance)
        return false, "创建新兵种失败", nil
    end

    -- 5. 更新新兵种的等级
    newInstance.Level = newLevel
    -- V2.8.2修复: 同步更新GridSize（确保数据一致性）
    newInstance.GridSize = gridSize

    -- 6. 移除两个旧兵种（从背包和场地移除）
    PlacementSystem.RemovePlacedUnit(player, instanceIdA)
    PlacementSystem.RemovePlacedUnit(player, instanceIdB)
    InventorySystem.RemoveUnit(player, instanceIdA)
    InventorySystem.RemoveUnit(player, instanceIdB)

    -- 6.5. 播放合成特效 (V1.5.3新增，使用计算好的脚底位置)
    PlayMergeEffect(effectPosition, gridSize)

    -- 7. 立即放置新兵种到原来的位置
    local placeSuccess, placeMessage = PlacementSystem.PlaceUnit(player, newInstance.InstanceId, mergePosition)

    if not placeSuccess then
        warn(GameConfig.LOG_PREFIX, "放置合成兵种失败:", placeMessage)
        -- 如果放置失败，兵种会留在背包中
    end

    -- V2.8.2修复: 合成后强制刷新客户端背包数据，确保等级信息同步
    InventorySystem.RefreshClientInventory(player)

    -- 🔥修复持久化：合成后保存数据
    DataManager.SavePlayerDataThrottled(player)
    print(string.format(
        "%s [MergeSystem] 🔥 已保存数据: 玩家 %s 合成兵种 %s (%s -> Lv.%d)",
        GameConfig.LOG_PREFIX,
        player.Name,
        newInstance.UnitId,
        newInstance.InstanceId,
        newLevel
    ))

    -- V3.3新增：通知任务系统（合成2级兵种任务）
    if not TaskSystem then
        local taskModule = ServerScriptService.Systems:FindFirstChild("TaskSystem")
        if taskModule then
            TaskSystem = require(taskModule)
        end
    end
    if TaskSystem and TaskSystem.OnMergeLevel2Unit then
        TaskSystem.OnMergeLevel2Unit(player, newInstance.UnitId, newLevel)
    end

    return true, "合成成功", {
        InstanceId = newInstance.InstanceId,
        UnitId = newInstance.UnitId,
        Level = newLevel,
        Position = mergePosition,
    }
end

-- ==================== 远程事件处理 ====================

--[[
处理客户端请求合成
@param player Player
@param instanceIdA string - 拖动的兵种
@param instanceIdB string - 目标兵种
]]
local function OnRequestMerge(player, instanceIdA, instanceIdB)

    -- 执行合成
    local success, message, newUnitData = MergeSystem.MergeUnits(player, instanceIdA, instanceIdB)

    -- 通知客户端结果
    if InitializeEvents() then
        local responseEvent = MergeEvents:FindFirstChild("MergeResponse")
        if responseEvent then
            responseEvent:FireClient(player, success, message, newUnitData)
        end
    end
end

--[[
初始化合成系统
]]
function MergeSystem.Initialize()

    -- 初始化事件
    if not InitializeEvents() then
        warn(GameConfig.LOG_PREFIX, "MergeEvents未找到，合成系统将不可用!")
        return false
    end

    -- 连接远程事件
    local requestEvent = MergeEvents:FindFirstChild("RequestMerge")
    if requestEvent then
        requestEvent.OnServerEvent:Connect(OnRequestMerge)
    end


    return true
end

return MergeSystem
