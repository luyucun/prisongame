--[[
Script Name: RobuxPriceHelper
Script Type: ModuleScript (Shared helper)
Script Location: ReplicatedStorage/Modules/RobuxPriceHelper
Purpose: Fetch and cache Marketplace prices for regional pricing UI.
]]

local MarketplaceService = game:GetService("MarketplaceService") :: any

local RobuxPriceHelper = {}

local CACHE = {
	Product = {},
	GamePass = {},
}

local PENDING = {
	Product = {},
	GamePass = {},
}

local function IsTextObject(obj)
	return obj and (obj:IsA("TextLabel") or obj:IsA("TextButton"))
end

local function NormalizeId(id)
	local num = tonumber(id)
	if not num or num <= 0 then
		return nil
	end
	return num
end

local function ResolvePrice(info)
	if type(info) ~= "table" then
		return nil
	end
	local price = info.PriceInRobux or info.Price
	price = tonumber(price)
	if price == nil then
		return nil
	end
	return price
end

local function FetchPrice(kind, id, callback)
	local numericId = NormalizeId(id)
	if not numericId then
		if callback then
			callback(nil, false, nil)
		end
		return
	end

	local cached = CACHE[kind][numericId]
	if cached ~= nil then
		if callback then
			callback(cached, true, nil)
		end
		return
	end

	local queue = PENDING[kind][numericId]
	if queue then
		if callback then
			table.insert(queue, callback)
		end
		return
	end

	queue = {}
	if callback then
		table.insert(queue, callback)
	end
	PENDING[kind][numericId] = queue

	task.spawn(function()
		local infoType = kind == "GamePass" and Enum.InfoType.GamePass or Enum.InfoType.Product
		local success, info = pcall(function()
			return MarketplaceService:GetProductInfo(numericId, infoType)
		end)
		local price = nil
		if success then
			price = ResolvePrice(info)
		end
		if price ~= nil then
			CACHE[kind][numericId] = price
		end

		local callbacks = PENDING[kind][numericId]
		PENDING[kind][numericId] = nil
		if callbacks then
			for _, cb in ipairs(callbacks) do
				cb(price, success, info)
			end
		end
	end)
end

function RobuxPriceHelper.GetProductPrice(productId, callback)
	FetchPrice("Product", productId, callback)
end

function RobuxPriceHelper.GetGamePassPrice(gamePassId, callback)
	FetchPrice("GamePass", gamePassId, callback)
end

function RobuxPriceHelper.GetCachedProductPrice(productId)
	local numericId = NormalizeId(productId)
	if not numericId then
		return nil
	end
	return CACHE.Product[numericId]
end

function RobuxPriceHelper.GetCachedGamePassPrice(gamePassId)
	local numericId = NormalizeId(gamePassId)
	if not numericId then
		return nil
	end
	return CACHE.GamePass[numericId]
end

function RobuxPriceHelper.PrimeProductPrices(productIds)
	if type(productIds) ~= "table" then
		return
	end
	for _, productId in pairs(productIds) do
		FetchPrice("Product", productId, nil)
	end
end

function RobuxPriceHelper.PrimeGamePassPrices(gamePassIds)
	if type(gamePassIds) ~= "table" then
		return
	end
	for _, gamePassId in pairs(gamePassIds) do
		FetchPrice("GamePass", gamePassId, nil)
	end
end

function RobuxPriceHelper.FormatPrice(price, format)
	local value = tonumber(price)
	if value == nil then
		return nil
	end
	local text = tostring(value)
	if format == "prefix" then
		return "R$" .. text
	end
	if format == "suffix" then
		return text .. "R$"
	end
	return text
end

local function ApplyLabelPrice(label, requestId, price, format)
	if not IsTextObject(label) then
		return
	end
	if label:GetAttribute("RobuxPriceRequestId") ~= requestId then
		return
	end
	local text = RobuxPriceHelper.FormatPrice(price, format)
	if text then
		label.Text = text
	end
end

function RobuxPriceHelper.UpdateProductLabel(label, productId, format)
	if not IsTextObject(label) then
		return
	end
	local requestId = (label:GetAttribute("RobuxPriceRequestId") or 0) + 1
	label:SetAttribute("RobuxPriceRequestId", requestId)

	local cached = RobuxPriceHelper.GetCachedProductPrice(productId)
	if cached ~= nil then
		label.Text = RobuxPriceHelper.FormatPrice(cached, format)
	end

	RobuxPriceHelper.GetProductPrice(productId, function(price)
		if not label or not label.Parent then
			return
		end
		ApplyLabelPrice(label, requestId, price, format)
	end)
end

function RobuxPriceHelper.UpdateGamePassLabel(label, gamePassId, format)
	if not IsTextObject(label) then
		return
	end
	local requestId = (label:GetAttribute("RobuxPriceRequestId") or 0) + 1
	label:SetAttribute("RobuxPriceRequestId", requestId)

	local cached = RobuxPriceHelper.GetCachedGamePassPrice(gamePassId)
	if cached ~= nil then
		label.Text = RobuxPriceHelper.FormatPrice(cached, format)
	end

	RobuxPriceHelper.GetGamePassPrice(gamePassId, function(price)
		if not label or not label.Parent then
			return
		end
		ApplyLabelPrice(label, requestId, price, format)
	end)
end

return RobuxPriceHelper
