-- Branded, device-adaptive café UI. Progress and all rewards remain server-owned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local Economy = require(shared:WaitForChild("Economy"))

local C = {
	Cream = Color3.fromRGB(249, 245, 235),
	Paper = Color3.fromRGB(255, 253, 247),
	Ink = Color3.fromRGB(53, 37, 29),
	Muted = Color3.fromRGB(128, 116, 99),
	Line = Color3.fromRGB(225, 216, 198),
	Sage = Color3.fromRGB(83, 113, 91),
	SageLight = Color3.fromRGB(225, 235, 220),
	Gold = Color3.fromRGB(190, 132, 53),
	GoldLight = Color3.fromRGB(250, 235, 202),
	Red = Color3.fromRGB(166, 70, 54),
	Disabled = Color3.fromRGB(235, 229, 216),
}

local function make(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function corner(instance, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 14) }, instance)
end

local function outline(instance, color)
	return make("UIStroke", { Color = color or C.Line, Thickness = 1, Transparency = 0.15 }, instance)
end

local function label(parent, value, size, position, dimensions, color, bold)
	return make("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextColor3 = color or C.Ink,
		TextSize = size,
		Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = position,
		Size = dimensions,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

local selectionOrder = 0
local playUiClick = function() end
local function button(parent, title, position, dimensions, callback, color)
	selectionOrder += 1
	local baseColor = color or C.Sage
	local object = make("TextButton", {
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = C.Paper,
		BackgroundColor3 = baseColor,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Position = position,
		Size = dimensions,
		Selectable = true,
		SelectionOrder = selectionOrder,
	}, parent)
	corner(object, 10)
	object:SetAttribute("BaseColor", baseColor)
	object:SetAttribute("Enabled", true)
	object.Activated:Connect(function()
		if object:GetAttribute("Enabled") then
			playUiClick()
			callback()
		end
	end)
	object.MouseEnter:Connect(function()
		if object:GetAttribute("Enabled") then
			local current = object:GetAttribute("BaseColor")
			TweenService:Create(object, TweenInfo.new(0.12), { BackgroundColor3 = current:Lerp(C.Ink, 0.09) }):Play()
		end
	end)
	object.MouseLeave:Connect(function()
		if object:GetAttribute("Enabled") then
			TweenService:Create(object, TweenInfo.new(0.12), { BackgroundColor3 = object:GetAttribute("BaseColor") }):Play()
		end
	end)
	return object
end

local function enableButton(object, enabled, title, color)
	local baseColor = color or C.Sage
	object:SetAttribute("Enabled", enabled)
	object:SetAttribute("BaseColor", baseColor)
	object.BackgroundColor3 = enabled and baseColor or C.Disabled
	object.TextColor3 = enabled and C.Paper or C.Muted
	object.Selectable = enabled
	if title then
		object.Text = title
	end
end

local function text(object, value)
	if object.Text ~= value then
		object.Text = value
	end
end

local function money(amount)
	return Economy.formatMoney(amount or 0)
end

local function count(amount)
	return (string.gsub(Economy.formatMoney(amount or 0), "^%$", ""))
end

local function duration(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
end

local function recipeById(id)
	for _, recipe in ipairs(Config.Recipes) do
		if recipe.Id == id then
			return recipe
		end
	end
	return Config.Recipes[1]
end

local screen = make("ScreenGui", {
	Name = "EspressoCafeUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

local root = make("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, screen)
local snapshot = nil
local actionRemote = nil
local manageOpen = false
local currentTab = "Upgrades"
local lastAction = 0
local previousMessage = ""
local offlineShown = false
local toastGeneration = 0
local lastCash = nil
local sessionOnlyShown = false

local toast = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108),
	Size = UDim2.new(1, -40, 0, 52), BackgroundColor3 = C.Ink,
	BackgroundTransparency = 0.03, BorderSizePixel = 0, Visible = false, ZIndex = 55,
}, root)
make("UISizeConstraint", { MaxSize = Vector2.new(480, 70) }, toast)
corner(toast, 12)
local toastText = label(toast, "", 12, UDim2.fromOffset(16, 4), UDim2.new(1, -32, 1, -8), C.Paper, true)
toastText.TextWrapped = true
toastText.TextTruncate = Enum.TextTruncate.None
toastText.ZIndex = 56

local function notify(message, seconds)
	toastGeneration += 1
	local generation = toastGeneration
	toastText.Text = tostring(message)
	toast.Visible = true
	toast.BackgroundTransparency = 0.03
	toastText.TextTransparency = 0
	task.delay(seconds or 4, function()
		if generation ~= toastGeneration then return end
		TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(toastText, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		task.delay(0.3, function()
			if generation == toastGeneration then toast.Visible = false end
		end)
	end)
end

local function send(action, argument)
	if not snapshot or not snapshot.Ready or not actionRemote then
		notify("Your café is still loading. Please wait.")
		return
	end
	if os.clock() - lastAction < 0.12 then return end
	lastAction = os.clock()
	actionRemote:FireServer(action, argument)
end

-- Compact bank / navigation bar leaves the café itself visible.
local header = make("Frame", {
	Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 78),
	BackgroundColor3 = C.Cream, BackgroundTransparency = 0.03, BorderSizePixel = 0,
}, root)
corner(header, 16)
outline(header)
local brand = label(header, "ESPRESSO", 24, UDim2.fromOffset(18, 9), UDim2.fromOffset(190, 28), C.Ink, true)
local brandSub = label(header, "YOUR LITTLE COFFEE EMPIRE", 9, UDim2.fromOffset(19, 36), UDim2.fromOffset(225, 15), C.Muted, true)
local saveStatus = label(header, "Connecting to your café…", 10, UDim2.fromOffset(19, 55), UDim2.new(1, -40, 0, 14), C.Muted)
local bank = label(header, "$—", 25, UDim2.new(1, -336, 0, 10), UDim2.fromOffset(168, 30), C.Sage, true)
bank.Name = "Cash"
bank.TextXAlignment = Enum.TextXAlignment.Right
local statsLine = label(header, "0 customers served", 10, UDim2.new(1, -336, 0, 43), UDim2.fromOffset(168, 16), C.Muted)
statsLine.TextXAlignment = Enum.TextXAlignment.Right
local openManage
local manageButton = button(header, "MANAGE CAFÉ", UDim2.new(1, -150, 0, 18), UDim2.fromOffset(132, 42), function()
	if openManage then openManage("Upgrades") end
end)
manageButton.Name = "ManageCafe"

local tutorial = make("Frame", {
	Position = UDim2.fromOffset(16, 104), Size = UDim2.fromOffset(254, 116),
	BackgroundColor3 = C.Cream, BorderSizePixel = 0,
}, root)
corner(tutorial, 14)
outline(tutorial)
label(tutorial, "A SMALL START. A BIG DREAM.", 9, UDim2.fromOffset(15, 10), UDim2.new(1, -30, 0, 16), C.Sage, true)
local tutorialTitle = label(tutorial, "Make your first espresso", 15, UDim2.fromOffset(15, 30), UDim2.new(1, -30, 0, 22), C.Ink, true)
local tutorialDescription = label(tutorial, "Press BREW. Serve when the meter turns green for a perfect shot.", 11,
	UDim2.fromOffset(15, 56), UDim2.new(1, -30, 0, 45), C.Muted)
tutorialDescription.TextWrapped = true
tutorialDescription.TextTruncate = Enum.TextTruncate.None
tutorialDescription.TextYAlignment = Enum.TextYAlignment.Top

local rushPill = make("Frame", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 104),
	Size = UDim2.fromOffset(210, 38), BackgroundColor3 = C.GoldLight, BorderSizePixel = 0,
}, root)
corner(rushPill, 11)
local rushLabel = label(rushPill, "Next rush · —", 11, UDim2.fromOffset(12, 0), UDim2.new(1, -24, 1, 0), C.Ink, true)
rushLabel.TextXAlignment = Enum.TextXAlignment.Center

-- One clear active task: pull and serve the current customer's drink.
local orderCard = make("Frame", {
	Name = "CurrentOrder", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20),
	Size = UDim2.new(1, -32, 0, 210), BackgroundColor3 = C.Cream, BorderSizePixel = 0,
}, root)
make("UISizeConstraint", { MaxSize = Vector2.new(460, 230) }, orderCard)
corner(orderCard, 18)
outline(orderCard)
local orderEyebrow = label(orderCard, "AT YOUR COUNTER", 9, UDim2.fromOffset(20, 14), UDim2.new(1, -40, 0, 16), C.Muted, true)
local orderName = label(orderCard, "Espresso", 28, UDim2.fromOffset(20, 34), UDim2.new(1, -155, 0, 36), C.Ink, true)
orderName.Name = "DrinkName"
local orderValue = label(orderCard, "$—", 22, UDim2.new(1, -130, 0, 36), UDim2.fromOffset(110, 30), C.Sage, true)
orderValue.Name = "SaleValue"
orderValue.TextXAlignment = Enum.TextXAlignment.Right
local orderHint = label(orderCard, "Your customer is ready. Pull a fresh shot.", 11, UDim2.fromOffset(20, 74), UDim2.new(1, -40, 0, 26), C.Muted)
orderHint.TextWrapped = true
orderHint.TextTruncate = Enum.TextTruncate.None
local meterTrack = make("Frame", {
	Position = UDim2.fromOffset(20, 110), Size = UDim2.new(1, -40, 0, 10),
	BackgroundColor3 = C.Disabled, BorderSizePixel = 0, ClipsDescendants = true,
}, orderCard)
corner(meterTrack, 5)
local meterFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Sage, BorderSizePixel = 0 }, meterTrack)
corner(meterFill, 5)
local meterCaption = label(orderCard, "A perfect extraction earns a bigger tip", 10, UDim2.fromOffset(20, 124), UDim2.new(1, -40, 0, 18), C.Muted)
local brewButton = button(orderCard, "BREW ESPRESSO", UDim2.fromOffset(20, 154), UDim2.new(1, -40, 0, 40), function()
	if snapshot and snapshot.Brew then
		local now = workspace:GetServerTimeNow()
		if now >= snapshot.Brew.ReadyAt and now <= snapshot.Brew.ExpiresAt then
			send("Serve")
		elseif now > snapshot.Brew.ExpiresAt then
			send("Brew")
		end
	else
		send("Brew")
	end
end)
brewButton.Name = "BrewAction"

-- The shop uses stable rows. State updates never reset a player's scroll position.
local backdrop = make("TextButton", {
	Name = "ManageBackdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink,
	BackgroundTransparency = 0.4, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
	Visible = false, ZIndex = 30, Selectable = false,
}, root)
local panel = make("Frame", {
	Name = "ManagePanel",
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -32, 1, -40), BackgroundColor3 = C.Cream, BorderSizePixel = 0, ZIndex = 31,
	Active = true,
}, root)
panel.Visible = false
make("UISizeConstraint", { MaxSize = Vector2.new(730, 640) }, panel)
corner(panel, 18)
outline(panel)
label(panel, "YOUR COFFEE HOUSE", 10, UDim2.fromOffset(22, 17), UDim2.new(1, -90, 0, 16), C.Sage, true).ZIndex = 32
local panelTitle = label(panel, "A little better, every cup.", 23, UDim2.fromOffset(22, 35), UDim2.new(1, -90, 0, 34), C.Ink, true)
panelTitle.ZIndex = 32
local closeManage
local closeButton = button(panel, "X", UDim2.new(1, -58, 0, 20), UDim2.fromOffset(38, 38), function()
	if closeManage then closeManage() end
end, C.Ink)
closeButton.ZIndex = 33

local tabStrip = make("ScrollingFrame", {
	Position = UDim2.fromOffset(20, 82), Size = UDim2.new(1, -40, 0, 44),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.fromOffset(620, 0), ZIndex = 32,
}, panel)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, tabStrip)
local pages = {}
local tabButtons = {}
local tabNames = { "Upgrades", "Menu", "Goals", "Style", "Neighbors" }
local tabWidths = { Upgrades = 109, Menu = 86, Goals = 86, Style = 86, Neighbors = 118 }
for index, name in ipairs(tabNames) do
	local tabButton = button(tabStrip, string.upper(name), UDim2.new(), UDim2.fromOffset(tabWidths[name], 38), function()
		if openManage then openManage(name) end
	end, C.Ink)
	tabButton.LayoutOrder = index
	tabButton.Name = "Tab_" .. name
	tabButton.ZIndex = 33
	tabButtons[name] = tabButton
	local page = make("ScrollingFrame", {
		Name = name, Position = UDim2.fromOffset(20, 140), Size = UDim2.new(1, -40, 1, -158),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.Muted, ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		Visible = false, ZIndex = 32,
	}, panel)
	make("UIPadding", { PaddingRight = UDim.new(0, 7), PaddingBottom = UDim.new(0, 12) }, page)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	pages[name] = page
end

local function paintTabs()
	for name, page in pairs(pages) do
		page.Visible = name == currentTab
		local selected = name == currentTab
		enableButton(tabButtons[name], true, nil, selected and C.Sage or C.Disabled)
		tabButtons[name].TextColor3 = selected and C.Paper or C.Ink
	end
end

openManage = function(tab)
	currentTab = tab or currentTab
	manageOpen = true
	panel.Visible = true
	backdrop.Visible = true
	orderCard.Visible = root.AbsoluteSize.Y >= 450
	paintTabs()
end
closeManage = function()
	manageOpen = false
	panel.Visible = false
	backdrop.Visible = false
	orderCard.Visible = true
end
backdrop.Activated:Connect(closeManage)

local rowNumber = 0
local function row(parent, height)
	rowNumber += 1
	local object = make("Frame", {
		Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = C.Paper,
		BorderSizePixel = 0, LayoutOrder = rowNumber, ZIndex = 33,
	}, parent)
	corner(object, 12)
	outline(object)
	return object
end

local function rowLabel(parent, value, size, position, dimensions, color, bold)
	local object = label(parent, value, size, position, dimensions, color, bold)
	object.ZIndex = 34
	return object
end

local function section(parent, title, detail)
	local object = row(parent, detail and 64 or 36)
	object.BackgroundTransparency = 1
	object:FindFirstChildOfClass("UIStroke").Transparency = 1
	rowLabel(object, title, 16, UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 24), C.Ink, true)
	if detail then
		local sub = rowLabel(object, detail, 11, UDim2.fromOffset(0, 28), UDim2.new(1, -8, 0, 32), C.Muted)
		sub.TextWrapped = true
		sub.TextTruncate = Enum.TextTruncate.None
		sub.TextYAlignment = Enum.TextYAlignment.Top
	end
	return object
end

local upgradeRows = {}
section(pages.Upgrades, "Grow at your own pace.", "Every upgrade is bought with café cash. Furniture and equipment grow with your café.")
for _, upgrade in ipairs(Config.Upgrades) do
	local object = row(pages.Upgrades, 126)
	object.Name = "Upgrade_" .. upgrade.Id
	rowLabel(object, upgrade.Name, 15, UDim2.fromOffset(14, 11), UDim2.new(1, -95, 0, 24), C.Ink, true)
	local level = rowLabel(object, "0 / " .. upgrade.MaxLevel, 11, UDim2.new(1, -82, 0, 13), UDim2.fromOffset(66, 20), C.Sage, true)
	level.TextXAlignment = Enum.TextXAlignment.Right
	local description = rowLabel(object, upgrade.Description, 11, UDim2.fromOffset(14, 40), UDim2.new(1, -28, 0, 34), C.Muted)
	description.TextWrapped = true
	description.TextTruncate = Enum.TextTruncate.None
	description.TextYAlignment = Enum.TextYAlignment.Top
	local buy = button(object, "BUY", UDim2.new(1, -140, 0, 79), UDim2.fromOffset(126, 34), function()
		send("BuyUpgrade", upgrade.Id)
	end)
	buy.ZIndex = 34
	buy.Name = "Buy"
	local benefit = rowLabel(object, "Café cash upgrade", 10, UDim2.fromOffset(14, 84), UDim2.new(1, -165, 0, 24), C.Muted)
	upgradeRows[upgrade.Id] = { Level = level, Buy = buy, Benefit = benefit, Config = upgrade }
end

local recipeRows = {}
section(pages.Menu, "What are you brewing?", "Choose your next order. Unlock new drinks with the menu upgrade; finish your current shot before switching.")
for _, recipe in ipairs(Config.Recipes) do
	local object = row(pages.Menu, 108)
	local color = recipe.Color or { 126, 88, 61 }
	local swatch = make("Frame", { Position = UDim2.fromOffset(14, 15), Size = UDim2.fromOffset(9, 32), BackgroundColor3 = Color3.fromRGB(color[1], color[2], color[3]), BorderSizePixel = 0, ZIndex = 34 }, object)
	corner(swatch, 4)
	rowLabel(object, recipe.Name, 15, UDim2.fromOffset(34, 12), UDim2.new(1, -50, 0, 24), C.Ink, true)
	local info = rowLabel(object, "", 11, UDim2.fromOffset(34, 40), UDim2.new(1, -50, 0, 20), C.Muted)
	local choose = button(object, "SELECT", UDim2.new(1, -140, 0, 66), UDim2.fromOffset(126, 30), function()
		send("SelectRecipe", recipe.Id)
	end)
	choose.ZIndex = 34
	local status = rowLabel(object, "", 10, UDim2.fromOffset(14, 69), UDim2.new(1, -165, 0, 20), C.Muted)
	recipeRows[recipe.Id] = { Config = recipe, Info = info, Choose = choose, Status = status }
end

local resetLabel
section(pages.Goals, "A fresh reason to brew.", "Daily goals reset at 00:00 UTC. Missing a day never removes your café progress.")
local resetRow = row(pages.Goals, 32)
resetRow.BackgroundColor3 = C.SageLight
resetLabel = rowLabel(resetRow, "Daily reset in —", 10, UDim2.fromOffset(12, 0), UDim2.new(1, -24, 1, 0), C.Sage, true)
local questRows = {}
local achievementRows = {}

local function progressRow(parent, item, action)
	local object = row(parent, 112)
	object.Name = "Goal_" .. item.Id
	rowLabel(object, item.Name, 14, UDim2.fromOffset(14, 10), UDim2.new(1, -28, 0, 25), C.Ink, true)
	local progress = rowLabel(object, "0 / " .. item.Target, 11, UDim2.fromOffset(14, 39), UDim2.new(1, -155, 0, 21), C.Muted)
	local reward = rowLabel(object, "+" .. money(item.Reward), 11, UDim2.new(1, -140, 0, 39), UDim2.fromOffset(126, 21), C.Sage, true)
	reward.TextXAlignment = Enum.TextXAlignment.Right
	local track = make("Frame", { Position = UDim2.fromOffset(14, 82), Size = UDim2.new(1, -169, 0, 7), BackgroundColor3 = C.Disabled, BorderSizePixel = 0, ZIndex = 34 }, object)
	corner(track, 4)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Sage, BorderSizePixel = 0, ZIndex = 35 }, track)
	corner(fill, 4)
	local claim = button(object, "CLAIM", UDim2.new(1, -140, 0, 70), UDim2.fromOffset(126, 30), function()
		send(action, item.Id)
	end)
	claim.ZIndex = 34
	claim.Name = "Claim"
	return { Config = item, Progress = progress, Fill = fill, Claim = claim }
end

for _, quest in ipairs(Config.Quests) do
	questRows[quest.Id] = progressRow(pages.Goals, quest, "ClaimQuest")
end
section(pages.Goals, "Lifetime milestones", "These rewards never reset when you open a new franchise.")
for _, achievement in ipairs(Config.Achievements) do
	achievementRows[achievement.Id] = progressRow(pages.Goals, achievement, "ClaimAchievement")
end

section(pages.Style, "Make the place your own.", "Switch café palettes for free. Franchise milestones unlock more styles.")
local themeRows = {}
for _, theme in ipairs(Config.Themes) do
	local object = row(pages.Style, 96)
	local palette = theme.Primary or { 83, 113, 91 }
	local swatch = make("Frame", { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromRGB(palette[1], palette[2], palette[3]), BorderSizePixel = 0, ZIndex = 34 }, object)
	corner(swatch, 9)
	rowLabel(object, theme.Name, 15, UDim2.fromOffset(60, 14), UDim2.new(1, -75, 0, 26), C.Ink, true)
	local requirement = rowLabel(object, "", 10, UDim2.fromOffset(14, 58), UDim2.new(1, -165, 0, 22), C.Muted)
	local choose = button(object, "APPLY", UDim2.new(1, -140, 0, 54), UDim2.fromOffset(126, 30), function()
		send("SetTheme", theme.Id)
	end)
	choose.ZIndex = 34
	themeRows[theme.Id] = { Config = theme, Choose = choose, Requirement = requirement }
end

section(pages.Style, "The next chapter", "An optional franchise starts a new café run and adds +20% permanent service income. Lifetime milestones stay.")
local franchiseCard = row(pages.Style, 164)
local franchiseHeading = rowLabel(franchiseCard, "FRANCHISE 01", 14, UDim2.fromOffset(14, 12), UDim2.new(1, -28, 0, 26), C.Ink, true)
local franchiseDescription = rowLabel(franchiseCard, "", 11, UDim2.fromOffset(14, 46), UDim2.new(1, -28, 0, 58), C.Muted)
franchiseDescription.TextWrapped = true
franchiseDescription.TextYAlignment = Enum.TextYAlignment.Top
franchiseDescription.TextTruncate = Enum.TextTruncate.None
local confirmFranchise
local franchiseButton = button(franchiseCard, "OPEN FRANCHISE", UDim2.fromOffset(14, 116), UDim2.new(1, -28, 0, 34), function()
	if confirmFranchise then confirmFranchise() end
end, C.Ink)
franchiseButton.ZIndex = 34
franchiseButton.Name = "FranchiseAction"

section(pages.Style, "Set the mood.", "Background music is optional and starts only when you choose to play.")
local audioCard = row(pages.Style, 112)
local musicName = rowLabel(audioCard, "Café soundtrack", 14, UDim2.fromOffset(14, 10), UDim2.new(1, -28, 0, 25), C.Ink, true)
local musicStatus = rowLabel(audioCard, "Finding your soundtrack…", 10, UDim2.fromOffset(14, 40), UDim2.new(1, -28, 0, 20), C.Muted)
local toggleMusic = function() end
local musicButton = button(audioCard, "MUSIC OFF", UDim2.new(1, -150, 0, 70), UDim2.fromOffset(136, 30), function()
	toggleMusic()
end, C.Ink)
musicButton.ZIndex = 34
musicButton.Name = "MusicToggle"
enableButton(musicButton, false, "MUSIC OFF", C.Ink)

section(pages.Neighbors, "Good coffee brings people together.", "Visit the other cafés around the plaza. These are the players and lifetime customers in this server.")
local neighborsContainer = row(pages.Neighbors, 360)
neighborsContainer.BackgroundTransparency = 1
neighborsContainer:FindFirstChildOfClass("UIStroke").Transparency = 1
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, neighborsContainer)
local neighborRows = {}
for index = 1, math.max(6, Config.MaxPlots or 6) do
	local object = make("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = C.Paper, BorderSizePixel = 0, LayoutOrder = index, ZIndex = 34, Visible = false }, neighborsContainer)
	corner(object, 12)
	local name = rowLabel(object, "", 12, UDim2.fromOffset(14, 6), UDim2.new(1, -115, 0, 22), C.Ink, true)
	local detail = rowLabel(object, "", 9, UDim2.fromOffset(14, 29), UDim2.new(1, -115, 0, 14), C.Muted)
	local served = rowLabel(object, "", 13, UDim2.new(1, -98, 0, 0), UDim2.fromOffset(82, 50), C.Sage, true)
	served.TextXAlignment = Enum.TextXAlignment.Right
	neighborRows[index] = { Root = object, Name = name, Detail = detail, Served = served }
end

-- Explicit reset confirmation; accidental taps never erase an active café.
local confirmOverlay = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink, BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false, Active = true, ZIndex = 50 }, root)
confirmOverlay.Name = "FranchiseConfirmation"
local confirmCard = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -40, 0, 292), BackgroundColor3 = C.Cream, BorderSizePixel = 0, ZIndex = 51 }, confirmOverlay)
make("UISizeConstraint", { MaxSize = Vector2.new(430, 310) }, confirmCard)
corner(confirmCard, 18)
local confirmTitle = label(confirmCard, "A new café. A new chapter.", 20, UDim2.fromOffset(20, 18), UDim2.new(1, -40, 0, 42), C.Ink, true)
confirmTitle.ZIndex = 52
local confirmBody = label(confirmCard, "Your cash and café upgrades will reset. Your franchises, lifetime statistics and claimed milestones stay. This cannot be undone.", 12, UDim2.fromOffset(20, 70), UDim2.new(1, -40, 0, 104), C.Muted)
confirmBody.ZIndex = 52
confirmBody.TextWrapped = true
confirmBody.TextTruncate = Enum.TextTruncate.None
confirmBody.TextYAlignment = Enum.TextYAlignment.Top
local cancelFranchise = button(confirmCard, "KEEP MY CAFÉ", UDim2.fromOffset(20, 184), UDim2.new(1, -40, 0, 38), function()
	confirmOverlay.Visible = false
end)
cancelFranchise.ZIndex = 52
cancelFranchise.Name = "CancelFranchise"
local acceptFranchise = button(confirmCard, "CONFIRM NEW FRANCHISE", UDim2.fromOffset(20, 232), UDim2.new(1, -40, 0, 38), function()
	confirmOverlay.Visible = false
	send("Franchise")
end, C.Ink)
acceptFranchise.ZIndex = 52
acceptFranchise.Name = "ConfirmFranchise"
confirmFranchise = function()
	if not snapshot or not snapshot.Ready then return end
	local allowed, reason = Economy.canFranchise(snapshot.Profile)
	if not allowed then notify(reason or "Your café is not ready to franchise yet.") return end
	confirmOverlay.Visible = true
end

local loading = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Cream, BorderSizePixel = 0, ZIndex = 60 }, root)
loading.Name = "Loading"
local loadingBrand = label(loading, "ESPRESSO", 34, UDim2.new(0, 24, 0.5, -100), UDim2.new(1, -48, 0, 46), C.Ink, true)
loadingBrand.TextXAlignment = Enum.TextXAlignment.Center
loadingBrand.ZIndex = 61
local loadingTitle = label(loading, "Warming up your coffee house…", 14, UDim2.new(0, 24, 0.5, -30), UDim2.new(1, -48, 0, 34), C.Sage, true)
loadingTitle.TextXAlignment = Enum.TextXAlignment.Center
loadingTitle.ZIndex = 61
local loadingDetail = label(loading, "Loading your saved café safely.", 11, UDim2.new(0, 32, 0.5, 22), UDim2.new(1, -64, 0, 90), C.Muted)
loadingDetail.TextXAlignment = Enum.TextXAlignment.Center
loadingDetail.TextYAlignment = Enum.TextYAlignment.Top
loadingDetail.TextWrapped = true
loadingDetail.TextTruncate = Enum.TextTruncate.None
loadingDetail.ZIndex = 61

local function updateNeighbors()
	local others = Players:GetPlayers()
	local function servedBy(other)
		local stats = other:FindFirstChild("leaderstats")
		if not stats then return 0 end
		local served = stats:FindFirstChild("Customers") or stats:FindFirstChild("Served")
		return served and served.Value or 0
	end
	table.sort(others, function(a, b)
		return servedBy(a) > servedBy(b)
	end)
	for index, view in ipairs(neighborRows) do
		local other = others[index]
		view.Root.Visible = other ~= nil
		if other then
			text(view.Name, other.DisplayName .. (other == player and "  · YOU" or ""))
			text(view.Detail, "@" .. other.Name)
			text(view.Served, count(servedBy(other)))
		end
	end
end

local function updateGoal(view, amount, claimed)
	local target = view.Config.Target
	amount = math.max(0, amount or 0)
	text(view.Progress, count(math.min(amount, target)) .. " / " .. count(target))
	view.Fill.Size = UDim2.fromScale(math.clamp(amount / math.max(1, target), 0, 1), 1)
	enableButton(view.Claim, not claimed and amount >= target, claimed and "CLAIMED" or (amount >= target and "CLAIM REWARD" or "IN PROGRESS"))
end

local function updateState(value)
	if type(value) ~= "table" then return end
	if snapshot and type(snapshot.ServerTime) == "number" and type(value.ServerTime) == "number" and value.ServerTime < snapshot.ServerTime then
		return
	end
	snapshot = value
	if not value.Ready or type(value.Profile) ~= "table" then
		loading.Visible = true
		text(loadingTitle, value.Error and "Reconnecting to your coffee house…" or "Warming up your coffee house…")
		text(loadingDetail, value.Error or "Loading your saved café safely.")
		return
	end
	loading.Visible = false
	local profile = value.Profile
	text(bank, money(profile.Cash))
	text(statsLine, count(profile.LifetimeServed) .. " served  ·  " .. tostring(profile.Franchises or 0) .. " franchises")
	local status = value.SaveStatus or "Connected"
	text(saveStatus, "CAFÉ " .. tostring(value.PlotIndex or "—") .. "  ·  " .. status)
	saveStatus.TextColor3 = (string.find(string.lower(status), "fail") or string.find(string.lower(status), "lost")) and C.Red or C.Muted
	if not sessionOnlyShown and string.find(string.lower(status), "session only") then
		sessionOnlyShown = true
		notify("Studio preview mode: progress in this session will not be saved.", 8)
	end
	if lastCash and profile.Cash > lastCash then
		bank.TextColor3 = C.Gold
		TweenService:Create(bank, TweenInfo.new(0.45), { TextColor3 = C.Sage }):Play()
	end
	lastCash = profile.Cash
	if value.Message and value.Message ~= "" and value.Message ~= previousMessage then
		previousMessage = value.Message
		notify(value.Message)
	end
	if not offlineShown and (value.OfflineReward or 0) > 0 then
		offlineShown = true
		notify("Welcome back! Your staff earned " .. money(value.OfflineReward) .. " while you were away.", 7)
	end

	for id, view in pairs(upgradeRows) do
		local level = profile.Upgrades[id] or 0
		local cost = Economy.upgradeCost(profile, id)
		text(view.Level, tostring(level) .. " / " .. tostring(view.Config.MaxLevel))
		local canAfford = cost ~= nil and profile.Cash >= cost
		enableButton(view.Buy, canAfford, cost and ("BUY · " .. money(cost)) or "MAX LEVEL")
		text(view.Benefit, cost == nil and "Fully upgraded" or (canAfford and "Ready to upgrade" or (money(cost - profile.Cash) .. " to go")))
	end
	for id, view in pairs(recipeRows) do
		local unlocked = Economy.recipe(profile, id) ~= nil
		local selected = value.SelectedRecipe == id
		local price = Economy.saleValue(profile, view.Config, false, false, false)
		text(view.Info, money(price) .. " base sale  ·  " .. string.format("%.1fs", Economy.brewDuration(profile, view.Config)) .. " brew")
		text(view.Status, unlocked and (selected and "On your menu now" or "Ready for your counter") or ("Requires menu level " .. tostring(view.Config.MenuLevel)))
		enableButton(view.Choose, unlocked and not selected and not value.Brew, selected and "SELECTED" or (unlocked and (value.Brew and "FINISH SHOT" or "SELECT") or "LOCKED"))
	end
	for id, view in pairs(questRows) do
		local daily = profile.Daily or {}
		updateGoal(view, daily[view.Config.Metric] or 0, (daily.Claimed or {})[id])
	end
	for id, view in pairs(achievementRows) do
		updateGoal(view, profile[view.Config.Metric] or 0, (profile.Achievements or {})[id])
	end
	for id, view in pairs(themeRows) do
		local required = view.Config.RequiredFranchises or 0
		local unlocked = (profile.Franchises or 0) >= required
		local selected = profile.Theme == id
		text(view.Requirement, unlocked and (selected and "Your café palette" or "Unlocked · free to apply") or (tostring(required) .. " franchises to unlock"))
		enableButton(view.Choose, unlocked and not selected, selected and "APPLIED" or (unlocked and "APPLY" or "LOCKED"))
	end
	local allowed, reason = Economy.canFranchise(profile)
	text(franchiseHeading, "FRANCHISE " .. string.format("%02d", (profile.Franchises or 0) + 1))
	text(franchiseDescription, allowed and "Your next chapter is ready. Cash and upgrades reset; your permanent franchise bonus and lifetime progress remain." or (reason or "Keep growing your café to unlock a new franchise."))
	enableButton(franchiseButton, allowed, allowed and "OPEN FRANCHISE" or "KEEP GROWING", C.Ink)
	if confirmOverlay.Visible and not allowed then confirmOverlay.Visible = false end

	local served = profile.ManualServed or 0
	local bought = profile.TotalUpgrades or 0
	local claimedGoal = next((profile.Daily or {}).Claimed or {}) ~= nil
	if served == 0 then
		text(tutorialTitle, "1 / 3 · Pull your first shot")
		text(tutorialDescription, "Press BREW below. When the meter turns green, serve a perfect espresso.")
	elseif bought == 0 then
		text(tutorialTitle, "2 / 3 · Make it a little better")
		text(tutorialDescription, "Open MANAGE CAFÉ and buy your first upgrade. Better equipment means a better coffee house.")
	elseif not claimedGoal then
		text(tutorialTitle, "3 / 3 · Your next small goal")
		text(tutorialDescription, "Keep serving, then claim a daily goal in MANAGE CAFÉ → GOALS.")
	else
		text(tutorialTitle, "Your café. Your pace.")
		text(tutorialDescription, "Try a new drink, hire staff, or visit your neighbors around the plaza.")
	end
	updateNeighbors()
end

local function updateExtraction()
	if not snapshot or not snapshot.Ready then
		enableButton(brewButton, false, "PREPARING CAFÉ")
		return
	end
	local now = workspace:GetServerTimeNow()
	local order = snapshot.Order or {}
	local recipe = recipeById(order.RecipeId or snapshot.SelectedRecipe)
	local vip = order.Vip == true
	text(orderName, recipe.Name)
	text(orderEyebrow, vip and "A VIP AT YOUR COUNTER" or "AT YOUR COUNTER")
	orderEyebrow.TextColor3 = vip and C.Gold or C.Muted
	local rush = snapshot.Rush
	local rushActive = rush and rush.Active and now < rush.EndsAt
	local price = Economy.saleValue(snapshot.Profile, recipe, false, vip, rushActive == true)
	text(orderValue, money(price))
	local brew = snapshot.Brew
	if not brew then
		meterFill.Size = UDim2.fromScale(0, 1)
		meterFill.BackgroundColor3 = C.Sage
		text(orderHint, "Your customer is ready. Pull a fresh shot.")
		text(meterCaption, "Serve in the green window for a perfect-shot bonus")
		enableButton(brewButton, true, "BREW " .. string.upper(recipe.Name))
	elseif now < brew.ReadyAt then
		local progress = math.clamp((now - brew.StartedAt) / math.max(0.1, brew.ReadyAt - brew.StartedAt), 0, 1)
		meterFill.Size = UDim2.fromScale(progress, 1)
		meterFill.BackgroundColor3 = C.Gold
		text(orderHint, "Extracting… get ready to serve.")
		text(meterCaption, string.format("%.1fs to the perfect window", math.max(0, brew.ReadyAt - now)))
		enableButton(brewButton, false, "BREWING…")
	elseif now <= brew.PerfectUntil then
		meterFill.Size = UDim2.fromScale(1, 1)
		meterFill.BackgroundColor3 = C.Sage
		text(orderHint, "Balanced, rich, and ready. Serve it now!")
		text(meterCaption, "PERFECT WINDOW · " .. string.format("%.1fs", math.max(0, brew.PerfectUntil - now)))
		enableButton(brewButton, true, "SERVE · PERFECT SHOT", C.Sage)
	elseif now <= brew.ExpiresAt then
		meterFill.Size = UDim2.fromScale(math.clamp((brew.ExpiresAt - now) / math.max(0.1, brew.ExpiresAt - brew.PerfectUntil), 0, 1), 1)
		meterFill.BackgroundColor3 = C.Gold
		text(orderHint, "Still warm. Your customer is waiting.")
		text(meterCaption, string.format("Serve within %.1fs", math.max(0, brew.ExpiresAt - now)))
		enableButton(brewButton, true, "SERVE COFFEE", C.Gold)
	else
		meterFill.Size = UDim2.fromScale(0, 1)
		text(orderHint, "This shot cooled down. A fresh one will be better.")
		text(meterCaption, "No cash lost. Brew again when you are ready.")
		enableButton(brewButton, true, "BREW A FRESH SHOT")
	end
	if rushActive then
		text(rushLabel, "COFFEE RUSH · " .. duration(rush.EndsAt - now))
		rushPill.BackgroundColor3 = C.GoldLight
	elseif rush and rush.NextAt then
		text(rushLabel, "Next rush · " .. duration(rush.NextAt - now))
		rushPill.BackgroundColor3 = C.Cream
	end
	text(resetLabel, "Daily reset in " .. duration(86400 - (os.time() % 86400)) .. " · UTC")
end

local function responsive()
	local size = root.AbsoluteSize
	local compact = size.X < 650
	local veryShort = size.Y < 450
	header.Size = UDim2.new(1, -32, 0, compact and 116 or 78)
	brand.TextSize = compact and 21 or 24
	brand.Size = UDim2.fromOffset(compact and 150 or 190, 28)
	brandSub.Visible = not compact
	saveStatus.Position = UDim2.fromOffset(19, compact and 43 or 55)
	saveStatus.Size = UDim2.new(1, compact and -38 or -40, 0, 14)
	bank.Position = UDim2.new(1, compact and -150 or -336, 0, 10)
	bank.Size = UDim2.fromOffset(compact and 132 or 168, 30)
	bank.TextSize = compact and 22 or 25
	statsLine.Position = compact and UDim2.fromOffset(19, 78) or UDim2.new(1, -336, 0, 43)
	statsLine.Size = UDim2.fromOffset(compact and math.max(80, size.X - 215) or 168, 20)
	statsLine.TextXAlignment = compact and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
	manageButton.Position = UDim2.new(1, -150, 0, compact and 67 or 18)
	manageButton.Size = UDim2.fromOffset(132, compact and 34 or 42)
	tutorial.Visible = not veryShort and size.Y >= (compact and 640 or 520)
	tutorial.Position = UDim2.fromOffset(16, compact and 140 or 104)
	tutorial.Size = compact and UDim2.new(1, -32, 0, 92) or UDim2.fromOffset(254, 116)
	tutorialTitle.TextSize = compact and 13 or 15
	tutorialDescription.Position = UDim2.fromOffset(15, compact and 53 or 56)
	tutorialDescription.Size = UDim2.new(1, -30, 0, compact and 32 or 45)
	tutorialDescription.TextSize = compact and 10 or 11
	rushPill.Visible = not veryShort
	rushPill.Position = UDim2.new(1, -16, 0, compact and (tutorial.Visible and 242 or 140) or 104)
	rushPill.Size = UDim2.fromOffset(compact and 185 or 210, 34)
	rushLabel.TextSize = compact and 10 or 11
	toast.Position = UDim2.new(0.5, 0, 0, compact and 140 or 102)
	orderCard.Position = UDim2.new(0.5, 0, 1, -16)
	orderCard.Visible = not (veryShort and manageOpen)
	orderName.TextSize = size.X < 380 and 23 or 28
	panelTitle.TextSize = size.X < 450 and 17 or 23
	panel.Size = UDim2.new(1, -32, 1, -28)
	confirmTitle.TextSize = size.X < 380 and 17 or 20
end

root:GetPropertyChangedSignal("AbsoluteSize"):Connect(responsive)
responsive()
RunService.RenderStepped:Connect(updateExtraction)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.ButtonB then
		if confirmOverlay.Visible then confirmOverlay.Visible = false elseif manageOpen then closeManage() end
	elseif input.KeyCode == Enum.KeyCode.ButtonY and not loading.Visible then
		if manageOpen then closeManage() else openManage("Upgrades") end
	end
end)

-- Audio is sourced in AssetCatalog. Loading/permission failures never block play.
task.spawn(function()
	local catalogRef = shared:WaitForChild("AssetCatalog", 30)
	if not catalogRef then
		text(musicStatus, "No café soundtrack is available.")
		return
	end
	local ok, catalog = pcall(require, catalogRef)
	if not ok or type(catalog) ~= "table" then
		text(musicStatus, "No café soundtrack is available.")
		return
	end
	local folder = make("Folder", { Name = "EspressoCafeLocalAudio" }, SoundService)
	local function audioSound(name, settings, defaultVolume, looped)
		if type(settings) ~= "table" or not settings.Id then return nil end
		return make("Sound", {
			Name = name, SoundId = "rbxassetid://" .. tostring(settings.Id),
			Volume = math.clamp(settings.Volume or defaultVolume, 0, 0.35), Looped = looped == true,
		}, folder)
	end
	local sounds = catalog.Sounds or {}
	local clickSound = audioSound("UIClick", sounds.UiClick, 0.12, false)
	local function oneShot(sound)
		if not sound or not sound.IsLoaded then return end
		pcall(function()
			sound.TimePosition = 0
			sound:Play()
		end)
	end
	playUiClick = function() oneShot(clickSound) end
	local effectsToLoad = {}
	if clickSound then table.insert(effectsToLoad, clickSound) end
	if #effectsToLoad > 0 then
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync(effectsToLoad) end)
		end)
	end
	local music = catalog.Music or {}
	local tracks = music.Tracks or {}
	local track = tracks[1]
	if not track then
		text(musicStatus, "No café soundtrack is available.")
		return
	end
	local background = audioSound("CafeMusic", { Id = track.Id, Volume = music.Volume or 0.16 }, 0.16, true)
	if not background then return end
	local playing = false
	local loadAttempt = 0
	local failed = false
	text(musicName, track.Name or "Café soundtrack")
	text(musicStatus, "Off · choose PLAY MUSIC when you feel like it.")
	enableButton(musicButton, true, "PLAY MUSIC", C.Ink)
	background.Loaded:Connect(function()
		if playing then text(musicStatus, "Now playing · " .. (track.Name or "Café soundtrack")) end
	end)
	toggleMusic = function()
		if failed then return end
		playing = not playing
		loadAttempt += 1
		local thisAttempt = loadAttempt
		if not playing then
			background:Stop()
			text(musicStatus, "Off · enjoy the sounds of your coffee house.")
			enableButton(musicButton, true, "PLAY MUSIC", C.Ink)
			return
		end
		local played = pcall(function() background:Play() end)
		text(musicStatus, background.IsLoaded and ("Now playing · " .. (track.Name or "Café soundtrack")) or "Loading your café soundtrack…")
		enableButton(musicButton, true, "MUTE MUSIC", C.Sage)
		task.delay(15, function()
			if thisAttempt ~= loadAttempt or not playing then return end
			if not played or not background.IsLoaded then
				failed = true
				playing = false
				background:Stop()
				text(musicStatus, "This soundtrack is unavailable. Your café can keep going.")
				enableButton(musicButton, false, "UNAVAILABLE", C.Ink)
			end
		end)
	end
	if music.EnabledByDefault == true then toggleMusic() end
end)

-- Subscribe first, then request a snapshot. Slow loads retry without duplicate calls.
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 40)
	if not remotes then
		text(loadingTitle, "The café server is still starting.")
		text(loadingDetail, "Please rejoin if this screen stays here. Your saved café has not been changed.")
		return
	end
	actionRemote = remotes:WaitForChild("Action", 20)
	local stateRemote = remotes:WaitForChild("State", 20)
	local getter = remotes:WaitForChild("GetState", 20)
	if not actionRemote or not stateRemote or not getter then
		text(loadingTitle, "The café connection is unavailable.")
		text(loadingDetail, "Please rejoin to reconnect to the server.")
		return
	end
	stateRemote.OnClientEvent:Connect(updateState)
	while screen.Parent do
		if not snapshot or not snapshot.Ready then
			local ok, result = pcall(function() return getter:InvokeServer() end)
			if ok and result then
				updateState(result)
			elseif not snapshot then
				text(loadingDetail, "Waiting for the café server. Reconnecting automatically…")
			end
		end
		task.wait(3)
	end
end)
