--[[
脚本名称: LoadingInitializer
脚本类型: LocalScript (客户端)
脚本位置: StarterGui/Loading/LoadingInitializer
版本: V3.2.2

职责:
【唯一职责】在游戏启动的第一时间显示Loading界面

原理:
- 此脚本放在 StarterGui/Loading 下面
- 当GUI复制到PlayerGui时，此脚本会立即执行
- 比StarterPlayerScripts下的脚本执行更早
- 使用script.Parent直接访问，无需WaitForChild

使用说明:
1. 在Studio中创建此LocalScript
2. 放置在 StarterGui/Loading/ 下
3. Bg.Visible在Studio中可以设为false（方便编辑）
4. 此脚本会在游戏启动时立即把Bg设为Visible=true
]]

-- 【立即执行】不等待任何东西
local LoadingGui = script.Parent  -- 直接获取父级（Loading ScreenGui）

if LoadingGui and LoadingGui:IsA("ScreenGui") then
	-- 确保Loading GUI启用并在最上层
	LoadingGui.Enabled = true
	LoadingGui.DisplayOrder = 999

	-- 立即显示Bg
	local Bg = LoadingGui:FindFirstChild("Bg")
	if Bg then
		Bg.Visible = true
	end
end

-- 脚本职责完成，后续由LoadingController接管
