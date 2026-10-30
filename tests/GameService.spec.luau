-- Run the current GameService + DataService sources with a small deterministic
-- Roblox boundary. These checks do not simulate physics, rendering or real APIs.
local fs = require("@lune/fs")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local gameSource = fs.readFile("src/server/GameService.luau")
local dataSource = fs.readFile("src/server/DataService.luau")
local baseEnvironment = getfenv()
local EPOCH = 1793390400
local passed = 0

local function equal(actual, expected, message)
	assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, callback)
	local success, failure = pcall(callback)
	if not success then error("FAIL " .. name .. ": " .. tostring(failure), 0) end
	passed += 1
	print("PASS " .. name)
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, entry in pairs(value) do result[key] = copy(entry) end
	return result
end

local function signal()
	local connections = {}
	return {
		Connect = function(_, callback)
			local connection = { Active = true, Callback = callback }
			table.insert(connections, connection)
			return { Disconnect = function() connection.Active = false end }
		end,
		Fire = function(_, ...)
			for _, connection in ipairs(connections) do
				if connection.Active then connection.Callback(...) end
			end
		end,
	}
end

local function fixture(options)
	options = options or {}
	local h = {
		Clock = 0, Queue = {}, Warnings = {}, Events = {}, Analytics = {},
		Records = options.Records or {}, Failures = options.Failures or {}, Writes = 0,
	}
	function h:now() return EPOCH + self.Clock end
	function h:advance(seconds) self.Clock += seconds end
	function h:step()
		-- Resume only the tasks that were already queued. All ongoing loops yield
		-- at their real task.wait calls; tests decide when the clock advances.
		local count = #self.Queue
		for index = 1, count do
			local thread = self.Queue[index]
			if coroutine.status(thread) ~= "dead" then
				local success, failure = coroutine.resume(thread)
				assert(success, failure)
			end
		end
	end

	local function object(className)
		local children = {}
		local properties = { ClassName = className, Children = children, OnServerEvent = signal() }
		local methods = {
			FindFirstChild = function(_, name) return children[name] end,
			IsA = function(_, name) return properties.ClassName == name end,
			FireClient = function(_, player, value)
				-- Copy the packet just as RemoteEvent serialization separates client state.
				table.insert(h.Events, { Player = player, Value = copy(value) })
			end,
		}
		return setmetatable({}, {
			__index = function(_, key) return methods[key] or properties[key] end,
			__newindex = function(self, key, value)
				if key == "Parent" and properties.Parent then
					properties.Parent.Children[properties.Name] = nil
				end
				properties[key] = value
				if key == "Parent" and value then value.Children[properties.Name] = self end
			end,
		})
	end

	local players = object("Players")
	players.PlayerAdded = signal()
	players.PlayerRemoving = signal()
	local player = object("Player")
	player.Name = "CoffeeTester"
	player.UserId = 42
	player.Parent = players
	player.CharacterAdded = signal()
	players.GetPlayers = function() return { player } end
	players.GetPlayerByUserId = function(_, userId) return if userId == player.UserId and player.Parent == players then player else nil end
	local replicatedStorage = object("ReplicatedStorage")
	local configToken, economyToken, dataToken = {}, {}, {}
	replicatedStorage.Shared = { Config = configToken, Economy = economyToken }
	local store = {}
	function store:UpdateAsync(key, callback)
		if #h.Failures > 0 then error(table.remove(h.Failures, 1), 0) end
		local result = callback(copy(h.Records[key]))
		if result ~= nil then
			h.Records[key] = copy(result)
			h.Writes += 1
		end
		return copy(result)
	end
	local services = {
		Players = players,
		ReplicatedStorage = replicatedStorage,
		DataStoreService = { GetDataStore = function() return store end },
		HttpService = { GenerateGUID = function() return "game-test-session" end },
		RunService = { IsStudio = function() return options.Studio == true end },
		AnalyticsService = {
			LogOnboardingFunnelStepEvent = function(_, who, step, name)
				table.insert(h.Analytics, { Player = who, Step = step, Name = name })
			end,
		},
	}
	local mockGame = {
		JobId = "mock-game-server", GameId = if options.Studio then 0 else 123,
		GetService = function(_, name)
			assert(services[name], "Unexpected service " .. name)
			return services[name]
		end,
		BindToClose = function(_, callback) h.Close = callback end,
	}
	local mockTask = {
		spawn = function(callback, ...)
			local arguments = table.pack(...)
			local thread = coroutine.create(function() callback(table.unpack(arguments, 1, arguments.n)) end)
			table.insert(h.Queue, thread)
			return thread
		end,
		wait = function(seconds) return coroutine.yield(seconds or 0.03) end,
	}
	mockTask.defer = mockTask.spawn
	local dataModule
	local environment = setmetatable({
		game = mockGame, task = mockTask,
		workspace = { GetServerTimeNow = function() return h:now() end },
		Instance = { new = object },
		os = { clock = function() return h.Clock end, time = function() return math.floor(h:now()) end },
		warn = function(message) table.insert(h.Warnings, tostring(message)) end,
		script = { Parent = { DataService = dataToken } },
		require = function(module)
			if module == configToken then return Config end
			if module == economyToken then return Economy end
			if module == dataToken then return dataModule end
			error("Unexpected module in GameService fixture", 0)
		end,
	}, { __index = baseEnvironment })
	local function load(source, name)
		local module, failure = loadstring(source, "@" .. name)
		assert(module, failure)
		setfenv(module, environment)
		return module()
	end
	dataModule = load(dataSource, "src/server/DataService.luau")
	local GameService = load(gameSource, "src/server/GameService.luau")
	local world = { ManualSales = {}, Brewing = false, Spawns = 0, Refreshes = 0, Released = 0 }
	function world:assignPlot() return if options.NoPlots then nil else 1 end
	function world:refreshPlot() self.Refreshes += 1 end
	function world:showOrder(_, recipe, vip) self.Order = { RecipeId = recipe.Id, Vip = vip } end
	function world:setBrew(_, active) self.Brewing = active end
	function world:serveCustomer(_, recipe, amount, perfect)
		assert(self.Brewing, "Customer must depart before the world brew state is cleared")
		table.insert(self.ManualSales, { RecipeId = recipe.Id, Amount = amount, Perfect = perfect })
	end
	function world:spawnPlayer() self.Spawns += 1 end
	function world:releasePlot() self.Released += 1 end
	function world:setHandlers(handlers) self.Handlers = handlers end
	h.World = world
	h.Player = player
	h.Players = players
	h.Service = GameService.start(world)
	h.State = h.Service.States[player]
	function h:send(action, argument) self.Service.Dispatch(self.Player, action, argument) end
	function h:snapshot()
		return replicatedStorage:FindFirstChild("Remotes"):FindFirstChild("GetState").OnServerInvoke(self.Player)
	end
	function h:leave()
		self.Players.PlayerRemoving:Fire(self.Player)
		self.Player.Parent = nil
	end
	h:step()
	if not options.AllowNotReady then assert(h.State.Ready, "Fixture profile should have loaded") end
	return h
end

test("joining assigns a cafe, restores state and exposes server-owned leaderstats", function()
	local h = fixture()
	local value = h:snapshot()
	assert(value.Ready)
	equal(value.Profile.Cash, Config.StartingCash)
	equal(value.PlotIndex, 1)
	equal(value.Order.RecipeId, "espresso")
	equal(h.World.Order.RecipeId, value.Order.RecipeId)
	equal(h.World.Spawns, 1)
	equal(h.Player:FindFirstChild("leaderstats"):FindFirstChild("Cash").Value, Config.StartingCash)
	assert(value.ServerTime and value.Rush.NextAt > value.ServerTime)
end)

test("early and replayed Serve cannot pay; a server-timed perfect shot pays once", function()
	local h = fixture()
	h:send("Brew")
	local brew = assert(h.State.Brew)
	local profile = h.State.Profile
	local amount = Economy.saleValue(profile, Config.Recipes[1], true, h.State.Order.Vip, false)
	local cash = profile.Cash
	h:send("Serve")
	equal(profile.Cash, cash)
	equal(h.State.Brew, brew)
	h:advance(brew.ReadyAt - h:now() + 0.2)
	h:send("Serve")
	equal(profile.Cash, cash + amount)
	equal(profile.ManualServed, 1)
	equal(profile.PerfectShots, 1)
	equal(profile.LifetimeServed, 1)
	equal(#h.World.ManualSales, 1)
	equal(h.State.Brew, nil)
	h:send("Serve")
	equal(profile.Cash, cash + amount)
	equal(#h.World.ManualSales, 1)
end)

test("a late but unexpired shot serves normally without granting a perfect bonus", function()
	local h = fixture()
	h:send("Brew")
	local brew = assert(h.State.Brew)
	local amount = Economy.saleValue(h.State.Profile, Config.Recipes[1], false, h.State.Order.Vip, false)
	h:advance(brew.PerfectUntil - h:now() + 0.1)
	h:send("Serve")
	equal(h.State.Profile.Cash, Config.StartingCash + amount)
	equal(h.State.Profile.PerfectShots, 0)
	equal(h.World.ManualSales[1].Perfect, false)
end)

test("an expired shot clears without paying and can be brewed again", function()
	local h = fixture()
	h:send("Brew")
	local brew = assert(h.State.Brew)
	local order = h.State.Order
	h:advance(brew.ExpiresAt - h:now() + 0.1)
	h:step()
	equal(h.State.Brew, nil)
	equal(h.State.Order, order)
	equal(h.State.Profile.Cash, Config.StartingCash)
	equal(h.World.Brewing, false)
	h:send("Serve")
	equal(h.State.Profile.Cash, Config.StartingCash)
	h:send("Brew")
	assert(h.State.Brew and h.State.Brew.StartedAt > brew.StartedAt)
end)

test("recipe selection respects unlocks and cannot change a shot already extracting", function()
	local h = fixture()
	h:send("SelectRecipe", "cold_brew")
	equal(h.State.SelectedRecipe, "espresso")
	h.State.Profile.Cash = 1000
	h:send("BuyUpgrade", "menu")
	equal(h.State.Profile.Cash, 1000 - Config.Upgrades[4].BaseCost)
	h:send("SelectRecipe", "americano")
	equal(h.State.SelectedRecipe, "americano")
	equal(h.World.Order.RecipeId, "americano")
	h:send("Brew")
	local order = h.State.Order
	h:send("SelectRecipe", "espresso")
	equal(h.State.SelectedRecipe, "americano")
	equal(h.State.Order, order)
end)

test("upgrade routing rejects unaffordable, forged and malformed client payloads", function()
	local h = fixture()
	local profile = h.State.Profile
	h:send("BuyUpgrade", "machine")
	equal(profile.Upgrades.machine, 0)
	equal(profile.Cash, Config.StartingCash)
	profile.Cash = 1000
	h:send("BuyUpgrade", { Id = "machine", Cost = -500 })
	h:send("BuyUpgrade", 0 / 0)
	h:send("BuyUpgrade", "forged")
	h:send({ "BuyUpgrade" }, "machine")
	equal(profile.Upgrades.machine, 0)
	equal(profile.Cash, 1000)
	h:advance(2)
	h:send("BuyUpgrade", "machine")
	equal(profile.Upgrades.machine, 1)
	equal(profile.Cash, 1000 - Config.Upgrades[1].BaseCost)
	assert(h.World.Refreshes >= 2)
end)

test("a burst of repeated action events cannot manufacture sales or endless upgrades", function()
	local h = fixture()
	h:send("Brew")
	for _ = 1, 100 do h:send("Serve") end
	equal(h.State.Profile.Cash, Config.StartingCash)
	equal(h.State.Profile.LifetimeServed, 0)
	assert(h.State.Tokens < 1, "Action burst should exhaust server token allowance")
	h.State.Profile.Cash = 100000
	h:advance(2)
	for _ = 1, 100 do h:send("BuyUpgrade", "machine") end
	assert(h.State.Profile.Upgrades.machine <= Config.Upgrades[1].MaxLevel)
	assert(h.State.Profile.Cash >= 0)
end)

test("staff earn through a separate lane without consuming a manual order or brew", function()
	local h = fixture()
	local profile = h.State.Profile
	profile.Upgrades.staff = 1
	h.State.NextStaffAt = h:now() + 1
	h:send("Brew")
	local brew, order = h.State.Brew, h.State.Order
	local amount = Economy.saleValue(profile, Config.Recipes[1], false, false, false)
	h:advance(1.1)
	h:step()
	equal(profile.Cash, Config.StartingCash + amount)
	equal(profile.LifetimeServed, 1)
	equal(profile.ManualServed, 0)
	equal(h.State.Brew, brew)
	equal(h.State.Order, order)
	equal(#h.World.ManualSales, 0)
	assert(h.World.Brewing)
end)

test("offline income is credited once per loaded session and its notice remains available", function()
	local profile = Economy.newProfile(EPOCH - 3600)
	profile.Cash = 500
	profile.Upgrades.staff = 1
	profile.Upgrades.menu = 2
	local reward = Economy.offlineEarnings(profile, 3600)
	local h = fixture({ Records = { Player_42 = { Profile = profile, SchemaVersion = Config.Version } } })
	equal(h.State.Profile.Cash, 500 + reward)
	equal(h.State.Profile.LifetimeEarned, reward)
	equal(h.State.Profile.LifetimeServed, 0)
	for _ = 1, 5 do
		local value = h:snapshot()
		equal(value.OfflineReward, reward)
		equal(value.Profile.Cash, 500 + reward)
	end
end)

test("daily and milestone claims route through server progress and cannot be replayed", function()
	local h = fixture()
	local profile = h.State.Profile
	h:send("ClaimQuest", "daily_serve")
	equal(profile.Cash, Config.StartingCash)
	profile.Daily.Served = 20
	h:send("ClaimQuest", "daily_serve")
	local dailyCash = profile.Cash
	assert(profile.Daily.Claimed.daily_serve and dailyCash > Config.StartingCash)
	h:send("ClaimQuest", "daily_serve")
	equal(profile.Cash, dailyCash)
	profile.LifetimeServed = 10
	h:send("ClaimAchievement", "first_ten")
	local milestoneCash = profile.Cash
	assert(profile.Achievements.first_ten and milestoneCash > dailyCash)
	h:send("ClaimAchievement", "first_ten")
	equal(profile.Cash, milestoneCash)
end)

test("franchise eligibility is enforced, then resets the run and unlocks its style", function()
	local h = fixture()
	local profile = h.State.Profile
	h:send("Franchise")
	h:send("SetTheme", "terracotta")
	equal(profile.Franchises, 0)
	equal(profile.Theme, "sage")
	profile.Cash = Config.FranchiseCash
	for _, upgrade in ipairs(Config.Upgrades) do profile.Upgrades[upgrade.Id] = upgrade.MaxLevel end
	profile.LifetimeServed = 123
	profile.Achievements.first_ten = true
	h:send("Brew")
	assert(h.State.Brew)
	h:send("Franchise")
	equal(profile.Franchises, 1)
	equal(profile.Cash, Config.StartingCash)
	equal(profile.LifetimeServed, 123)
	assert(profile.Achievements.first_ten)
	for _, level in pairs(profile.Upgrades) do equal(level, 0) end
	equal(h.State.Brew, nil)
	equal(h.State.SelectedRecipe, "espresso")
	equal(h.World.Brewing, false)
	h:advance(2)
	h:send("SetTheme", "terracotta")
	equal(profile.Theme, "terracotta")
	h:send("SetTheme", "midnight")
	equal(profile.Theme, "terracotta")
end)

test("lease expiry pauses new gameplay and renewal safely resumes it", function()
	local h = fixture()
	local session = h.Service.Data.Sessions[h.Player.UserId]
	h:advance(session.LeaseExpiresAt - h:now() + 1)
	h:send("Brew")
	equal(h.State.Brew, nil)
	equal(h.State.Profile.Cash, Config.StartingCash)
	equal(h.Service.Data:getStatus(h.Player.UserId), "Save delayed")
	assert(h.Service.Data:save(h.Player.UserId, false))
	h:send("Brew")
	assert(h.State.Brew)
end)

test("lost persistence ownership blocks the UI state and all further gameplay", function()
	local h = fixture()
	local saved = h.Records.Player_42
	saved.Session = { Id = "different-server", ExpiresAt = EPOCH + 1000 }
	assert(not h.Service.Data:save(h.Player.UserId, false))
	equal(h.State.Ready, false)
	assert(h.State.SessionLost)
	local value = h:snapshot()
	equal(value.Profile, nil)
	assert(string.find(value.Error, "rejoin", 1, true))
	h:send("Brew")
	equal(h.State.Brew, nil)
	equal(h.Records.Player_42.Session.Id, "different-server")
end)

test("load outages keep gameplay blocked and can recover through a later safe retry", function()
	local h = fixture({ AllowNotReady = true, Failures = { "network failure", "network failure", "network failure" } })
	h:step()
	h:step()
	equal(h.State.Ready, false)
	equal(h.Writes, 0)
	h:send("Brew")
	equal(h.State.Brew, nil)
	local value = h:snapshot()
	equal(value.Profile, nil)
	assert(value.Error)
	h:advance(13)
	h:snapshot()
	h:step()
	h:step()
	assert(h.State.Ready)
	equal(h.State.Profile.Cash, Config.StartingCash)
end)

test("respawn returns to the owned cafe; departure releases plot and persistence", function()
	local h = fixture()
	h.Player.CharacterAdded:Fire()
	h:step()
	equal(h.World.Spawns, 2)
	h.State.Profile.Cash = 321
	h:leave()
	h:step()
	equal(h.Service.States[h.Player], nil)
	equal(h.World.Released, 1)
	equal(h.Records.Player_42.Profile.Cash, 321)
	equal(h.Records.Player_42.Session, nil)
	h.Player.CharacterAdded:Fire()
	h:step()
	equal(h.World.Spawns, 2)
end)

print(string.format("%d mocked game-service scenarios passed; Roblox engine/network APIs were not exercised.", passed))
