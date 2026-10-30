-- Runs the actual LocalScript with real shared modules and mocked Roblox services.
-- Validates wiring/state transitions; it does not render pixels or play real audio.
local fs = require("@lune/fs")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local AssetCatalog = require("../src/shared/AssetCatalog")
local baseEnvironment = getfenv()
local passed = 0

local function test(name, callback)
	local ok, failure = pcall(callback)
	assert(ok, "FAIL " .. name .. ": " .. tostring(failure))
	passed += 1
	print("PASS " .. name)
end

local function signal()
	local event = { Callbacks = {} }
	function event:Connect(callback)
		table.insert(self.Callbacks, callback)
		return { Disconnect = function() end }
	end
	function event:Fire(...)
		for _, callback in ipairs(self.Callbacks) do callback(...) end
	end
	return event
end

local function enumGroup()
	return setmetatable({}, { __index = function(target, key) rawset(target, key, key) return key end })
end
local mockEnum = setmetatable({}, {
	__index = function(target, key)
		local value = enumGroup()
		rawset(target, key, value)
		return value
	end,
})
local mockColor = {}
function mockColor.fromRGB(red, green, blue)
	local value = { R = red, G = green, B = blue }
	function value:Lerp(other, alpha)
		return mockColor.fromRGB(self.R * (1 - alpha) + other.R * alpha,
			self.G * (1 - alpha) + other.G * alpha, self.B * (1 - alpha) + other.B * alpha)
	end
	return value
end
local mockVector = { new = function(x, y) return { X = x, Y = y } end }
local mockUDim = { new = function(scale, offset) return { Scale = scale, Offset = offset } end }
local mockUDim2 = { new = function(xs, xo, ys, yo) return { X = mockUDim.new(xs, xo), Y = mockUDim.new(ys, yo) } end }
function mockUDim2.fromScale(x, y) return mockUDim2.new(x, 0, y, 0) end
function mockUDim2.fromOffset(x, y) return mockUDim2.new(0, x, 0, y) end

local mockInstance = {}
local methods = {}
function methods:SetAttribute(key, value) self.Attributes[key] = value end
function methods:GetAttribute(key) return self.Attributes[key] end
function methods:GetPropertyChangedSignal(key)
	if not self.Signals[key] then self.Signals[key] = signal() end
	return self.Signals[key]
end
function methods:FindFirstChild(name)
	for _, child in ipairs(self.Children) do if child.Name == name then return child end end
	return nil
end
function methods:FindFirstChildOfClass(name)
	for _, child in ipairs(self.Children) do if child.ClassName == name then return child end end
	return nil
end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:Play() self.PlayCount = (self.PlayCount or 0) + 1 end
function methods:Stop() self.StopCount = (self.StopCount or 0) + 1 end
function mockInstance.new(className)
	local object = {
		Properties = { ClassName = className, Name = className, AbsoluteSize = mockVector.new(1280, 720), IsLoaded = false },
		Attributes = {}, Children = {}, Signals = {},
	}
	for _, name in ipairs({ "Activated", "MouseEnter", "MouseLeave", "Loaded", "OnClientEvent" }) do
		object.Properties[name] = signal()
	end
	return setmetatable(object, {
		__index = function(target, key) return methods[key] or target.Properties[key] end,
		__newindex = function(target, key, value)
			target.Properties[key] = value
			if key == "Parent" and value then table.insert(value.Children, target) end
			if target.Signals[key] then target.Signals[key]:Fire() end
		end,
	})
end

local function descendant(root, name)
	if root.Name == name then return root end
	for _, child in ipairs(root.Children) do
		local found = descendant(child, name)
		if found then return found end
	end
	return nil
end

local clock = 1000
local queue, delayed, actions = {}, {}, {}
local function child(parent, name, className)
	local value = mockInstance.new(className or "Folder")
	value.Name = name
	value.Parent = parent
	return value
end
local player = mockInstance.new("Player")
player.Name = "TestBarista"
player.DisplayName = "Barista"
local playerGui = child(player, "PlayerGui", "PlayerGui")
local storage = mockInstance.new("ReplicatedStorage")
local shared = child(storage, "Shared")
local configToken = child(shared, "Config", "ModuleScript")
local economyToken = child(shared, "Economy", "ModuleScript")
local catalogToken = child(shared, "AssetCatalog", "ModuleScript")
local remotes = child(storage, "Remotes")
local action = child(remotes, "Action", "RemoteEvent")
action.FireServer = function(_, ...) table.insert(actions, table.pack(...)) end
local state = child(remotes, "State", "RemoteEvent")
local getter = child(remotes, "GetState", "RemoteFunction")
getter.InvokeServer = function() return { Ready = false, Error = "Test reconnect" } end
local soundService = mockInstance.new("SoundService")
local runService = { RenderStepped = signal() }
local input = { InputBegan = signal() }
local services = {
	Players = { LocalPlayer = player, GetPlayers = function() return { player } end },
	ReplicatedStorage = storage,
	TweenService = { Create = function(_, target, _, properties)
		return { Play = function() for key, value in pairs(properties) do target[key] = value end end }
	end },
	RunService = runService, UserInputService = input, SoundService = soundService,
	ContentProvider = { PreloadAsync = function(_, objects)
		for _, object in ipairs(objects) do object.IsLoaded = true object.Loaded:Fire() end
	end },
}
local environment = setmetatable({
	game = { GetService = function(_, name) assert(services[name], "Unexpected service: " .. name) return services[name] end },
	workspace = { GetServerTimeNow = function() return clock end },
	Instance = mockInstance, Enum = mockEnum, Color3 = mockColor, Vector2 = mockVector,
	UDim = mockUDim, UDim2 = mockUDim2, TweenInfo = { new = function() return {} end },
	os = { clock = function() return clock end, time = function() return 1793390400 + math.floor(clock) end },
	task = {
		spawn = function(callback, ...) table.insert(queue, { Callback = callback, Arguments = table.pack(...) }) end,
		delay = function(seconds, callback) table.insert(delayed, { Seconds = seconds, Callback = callback }) end,
		wait = function() coroutine.yield() end,
	},
	require = function(token)
		if token == configToken then return Config end
		if token == economyToken then return Economy end
		if token == catalogToken then return AssetCatalog end
		error("Unexpected UI module")
	end,
}, { __index = baseEnvironment })

local source = fs.readFile("src/client/Main.client.luau")
local entry, failure = loadstring(source, "@src/client/Main.client.luau")
assert(entry, failure)
setfenv(entry, environment)
entry()
while #queue > 0 do
	local work = table.remove(queue, 1)
	local thread = coroutine.create(work.Callback)
	local ok, problem = coroutine.resume(thread, table.unpack(work.Arguments, 1, work.Arguments.n))
	assert(ok, problem)
end
local gui = assert(descendant(playerGui, "EspressoCafeUI"))
local function find(name) return assert(descendant(gui, name), "Missing UI object: " .. name) end
local function press(name)
	clock += 0.2
	find(name).Activated:Fire()
end
local profile = Economy.newProfile(1793390400)
local snapshot = {
	Ready = true, Profile = profile, PlotIndex = 1, SelectedRecipe = "espresso",
	Order = { RecipeId = "espresso", Vip = false }, SaveStatus = "Session only", OfflineReward = 0,
	Rush = { Active = false, NextAt = 1300, EndsAt = 0 }, ServerTime = 1000,
}
local function push()
	snapshot.ServerTime = clock
	state.OnClientEvent:Fire(snapshot)
	runService.RenderStepped:Fire()
end

test("real LocalScript builds and subscribes while showing reconnect state", function()
	assert(find("Loading").Visible)
	assert(#state.OnClientEvent.Callbacks == 1)
	push()
	assert(not find("Loading").Visible)
	assert(find("Cash").Text == "$60")
	assert(find("SaleValue").Text == "$24")
end)

test("upgrade affordability and action payload use actual shared economy", function()
	local buy = descendant(find("Upgrade_machine"), "Buy")
	assert(not buy:GetAttribute("Enabled"))
	profile.Cash = 10000
	push()
	assert(buy:GetAttribute("Enabled"))
	clock += 0.2
	buy.Activated:Fire()
	assert(actions[#actions][1] == "BuyUpgrade" and actions[#actions][2] == "machine")
end)

test("all five management tabs open without rebuilding their content", function()
	press("ManageCafe")
	assert(find("ManagePanel").Visible)
	for _, name in ipairs({ "Upgrades", "Menu", "Goals", "Style", "Neighbors" }) do
		local page = find(name)
		local before = #page.Children
		press("Tab_" .. name)
		assert(page.Visible and #page.Children == before)
	end
end)

test("brew button sends Brew and respects server extraction phases", function()
	press("BrewAction")
	assert(actions[#actions][1] == "Brew")
	snapshot.Brew = { StartedAt = clock, ReadyAt = clock + 4, PerfectUntil = clock + 5.4, ExpiresAt = clock + 18 }
	push()
	assert(find("BrewAction").Text == "BREWING…")
	assert(not find("BrewAction"):GetAttribute("Enabled"))
	clock = snapshot.Brew.ReadyAt + 0.3
	runService.RenderStepped:Fire()
	assert(find("BrewAction").Text == "SERVE · PERFECT SHOT")
	press("BrewAction")
	assert(actions[#actions][1] == "Serve")
	clock = snapshot.Brew.PerfectUntil + 0.1
	runService.RenderStepped:Fire()
	assert(find("BrewAction").Text == "SERVE COFFEE")
	clock = snapshot.Brew.ExpiresAt + 0.1
	runService.RenderStepped:Fire()
	assert(find("BrewAction").Text == "BREW A FRESH SHOT")
end)

test("daily claim state and payload reflect server progression", function()
	local claim = descendant(find("Goal_daily_serve"), "Claim")
	assert(not claim:GetAttribute("Enabled"))
	profile.Daily.Served = 20
	push()
	assert(claim:GetAttribute("Enabled"))
	clock += 0.2
	claim.Activated:Fire()
	assert(actions[#actions][1] == "ClaimQuest" and actions[#actions][2] == "daily_serve")
	profile.Daily.Claimed.daily_serve = true
	push()
	assert(claim.Text == "CLAIMED" and not claim:GetAttribute("Enabled"))
end)

test("franchise requires eligibility and a separate explicit confirmation", function()
	assert(not find("FranchiseAction"):GetAttribute("Enabled"))
	press("FranchiseAction")
	assert(not find("FranchiseConfirmation").Visible)
	profile.Cash = 20000
	for _, upgrade in ipairs(Config.Upgrades) do profile.Upgrades[upgrade.Id] = upgrade.MaxLevel end
	push()
	press("FranchiseAction")
	assert(find("FranchiseConfirmation").Visible)
	assert(actions[#actions][1] ~= "Franchise")
	press("ConfirmFranchise")
	assert(not find("FranchiseConfirmation").Visible)
	assert(actions[#actions][1] == "Franchise")
end)

test("music is opt-in and mute works without creating a duplicate brew sound", function()
	local background = assert(descendant(soundService, "CafeMusic"))
	assert(not background.PlayCount)
	assert(not descendant(soundService, "Brew"))
	press("MusicToggle")
	assert(background.PlayCount == 1)
	press("MusicToggle")
	assert(background.StopCount == 1)
end)

test("stale network snapshots cannot roll the displayed wallet backward", function()
	profile.Cash = 555
	push()
	state.OnClientEvent:Fire({ Ready = true, Profile = Economy.newProfile(1793390400), ServerTime = clock - 1 })
	assert(find("Cash").Text == "$555")
end)

test("responsive layout code handles phone, landscape and desktop sizes", function()
	for _, size in ipairs({ { 320, 640 }, { 390, 844 }, { 844, 390 }, { 1280, 720 }, { 1920, 1080 } }) do
		find("Root").AbsoluteSize = mockVector.new(size[1], size[2])
	end
	assert(find("BrewAction").Size.Y.Offset >= 40)
end)

print(string.format("%d mocked UI scenarios passed; Studio rendering, device input and audio playback were not exercised.", passed))
