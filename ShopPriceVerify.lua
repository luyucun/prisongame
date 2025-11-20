--[[
脚本名称: ShopPriceVerify
脚本类型: 测试脚本
脚本位置: 临时测试脚本
版本: V2.1
职责: 验证商店价格配置一致性
]]

-- 这是一个临时测试脚本，用于验证修复效果
-- 在服务器控制台中运行此脚本来检查价格一致性

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ShopConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("UnitConfig"))

print("==== 商店价格一致性验证 ====")

local shopItems = ShopConfig.GetShopItems("UnitShop", nil)
local totalItems = #shopItems
local priceConfigured = 0
local errors = {}

for _, item in ipairs(shopItems) do
    local unitId = item.UnitId
    local shopPrice = item.Price
    local configPrice = ShopConfig.GetPrice("UnitShop", unitId)
    local unitData = UnitConfig.GetUnitById(unitId)

    if shopPrice and shopPrice > 0 then
        priceConfigured = priceConfigured + 1

        -- 验证价格一致性
        if shopPrice ~= configPrice then
            table.insert(errors, string.format(
                "❌ %s: UI显示价格(%d) ≠ ShopConfig价格(%d)",
                unitId, shopPrice, configPrice or 0
            ))
        else
            print(string.format(
                "✅ %s: 价格一致 (%d金币)",
                unitId, shopPrice
            ))
        end

        -- 检查与UnitConfig的差异（仅作参考）
        if unitData and unitData.Price and unitData.Price ~= shopPrice then
            print(string.format(
                "ℹ️  %s: ShopConfig(%d) vs UnitConfig(%d) - 以ShopConfig为准",
                unitId, shopPrice, unitData.Price
            ))
        end
    else
        table.insert(errors, string.format("❌ %s: 没有配置价格", unitId))
    end
end

print(string.format("\n==== 验证结果 ===="))
print(string.format("总商品数: %d", totalItems))
print(string.format("已配置价格: %d", priceConfigured))
print(string.format("错误数量: %d", #errors))

if #errors > 0 then
    print("\n❌ 发现的问题:")
    for _, error in ipairs(errors) do
        print("  " .. error)
    end
else
    print("\n🎉 所有价格配置正确！")
end

print("\n==== 价格范围统计 ====")
local priceRanges = {
    ["200-500"] = 0,
    ["501-1000"] = 0,
    ["1001-3000"] = 0,
    ["3001-6000"] = 0,
    ["6001+"] = 0
}

for _, item in ipairs(shopItems) do
    local price = item.Price or 0
    if price >= 200 and price <= 500 then
        priceRanges["200-500"] = priceRanges["200-500"] + 1
    elseif price >= 501 and price <= 1000 then
        priceRanges["501-1000"] = priceRanges["501-1000"] + 1
    elseif price >= 1001 and price <= 3000 then
        priceRanges["1001-3000"] = priceRanges["1001-3000"] + 1
    elseif price >= 3001 and price <= 6000 then
        priceRanges["3001-6000"] = priceRanges["3001-6000"] + 1
    elseif price > 6000 then
        priceRanges["6001+"] = priceRanges["6001+"] + 1
    end
end

for range, count in pairs(priceRanges) do
    if count > 0 then
        print(string.format("%s: %d个兵种", range, count))
    end
end