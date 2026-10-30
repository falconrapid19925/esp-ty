-- These tests run DataService's real persistence logic against mocks in Lune.
-- They verify session/data boundaries, not Roblox DataStore API availability or behavior.
local fs = require("@lune/fs")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local source = fs.readFile("src/server/DataService.luau")
local baseEnvironment = getfenv()
local EPOCH = 1793390400
local passed = 0
local nextNode = 0

local function equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function contains(actual, expected)
	assert(type(actual) == "string" and string.find(actual, expected, 1, true),
		"expected '" .. tostring(actual) .. "' to contain '" .. expected .. "'")
end

local function test(name, callback)
	local ok, failure = pcall(callback)
	if not ok then error("FAIL " .. name .. ": " .. tostring(failure), 0) end
	passed += 1
	print("PASS " .. name)
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, entry in pairs(value) do result[key] = copy(entry) end
	return result
end

local function store()
	local backend = { Records = {}, Calls = 0, Writes = 0, Failures = {}, BeforeUpdate = nil }
	function backend:UpdateAsync(key, transform)
		self.Calls += 1
		if self.BeforeUpdate then self.BeforeUpdate(key, self.Calls) end
		if #self.Failures > 0 then error(table.remove(self.Failures, 1), 0) end
		-- Copies mimic the serialization boundary: local mutations cannot edit persisted data.
		local updated = transform(copy(self.Records[key]))
		if updated == nil then return nil end
		self.Records[key] = copy(updated)
		self.Writes += 1
		return copy(updated)
	end
	return backend
end

local function harness(options)
	options = options or {}
	nextNode += 1
	local fixture = {
		Clock = 0, Backend = options.Backend or store(), Queue = {}, Warnings = {}, Statuses = {}, Guid = 0,
	}
	function fixture:advance(seconds) self.Clock += seconds end
	function fixture:now() return EPOCH + math.floor(self.Clock) end
	local configToken, economyToken = {}, {}
	local services = {
		DataStoreService = {
			GetDataStore = function(_, name)
				equal(name, "EspressoCafeTycoon_Profiles_v1")
				if options.StoreError then error(options.StoreError, 0) end
				return fixture.Backend
			end,
		},
		HttpService = {
			GenerateGUID = function()
				fixture.Guid += 1
				return "guid-" .. fixture.Guid
			end,
		},
		RunService = { IsStudio = function() return options.Studio == true end },
		ReplicatedStorage = { Shared = { Config = configToken, Economy = economyToken } },
	}
	local mockGame = {
		GameId = if options.GameId ~= nil then options.GameId else 123,
		JobId = "mock-job-" .. nextNode,
		GetService = function(_, name)
			assert(services[name], "Unexpected service " .. name)
			return services[name]
		end,
	}
	local mockTask = {
		spawn = function(callback, ...)
			-- Do not execute DataService.new's infinite autosave loop.
			table.insert(fixture.Queue, { Callback = callback, Arguments = table.pack(...) })
		end,
		wait = function(seconds)
			fixture:advance(seconds or 0.03)
			return seconds or 0.03
		end,
	}
	local environment = setmetatable({
		game = mockGame,
		script = {},
		task = mockTask,
		os = { clock = function() return fixture.Clock end, time = function() return fixture:now() end },
		warn = function(message) table.insert(fixture.Warnings, tostring(message)) end,
		require = function(module)
			if module == configToken then return Config end
			if module == economyToken then return Economy end
			error("Unexpected module require in DataService", 0)
		end,
	}, { __index = baseEnvironment })
	local module, failure = loadstring(source, "@src/server/DataService.luau")
	assert(module, failure)
	setfenv(module, environment)
	local DataService = module()
	fixture.Data = DataService.new(function(userId, status)
		table.insert(fixture.Statuses, { UserId = userId, Status = status })
	end)
	equal(#fixture.Queue, 1)
	return fixture
end

local function savedRecord(cash)
	local profile = Economy.newProfile(EPOCH - 100)
	profile.Cash = cash
	profile.Upgrades.menu = 2
	return { SchemaVersion = Config.Version, Profile = profile }
end

test("first load acquires a lease and keeps unsaved mutations out of persisted data", function()
	local h = harness()
	local profile = assert(h.Data:load({ UserId = 101 }))
	local persisted = h.Backend.Records.Player_101
	equal(profile.Cash, Config.StartingCash)
	equal(persisted.Profile.Cash, Config.StartingCash)
	equal(persisted.SchemaVersion, Config.Version)
	assert(type(persisted.Session.Id) == "string" and persisted.Session.Id ~= "")
	assert(persisted.Session.ExpiresAt > h:now())
	equal(h.Data:getStatus(101), "Saved")
	assert(h.Data:isWritable(101))
	profile.Cash = 999
	equal(persisted.Profile.Cash, Config.StartingCash)
	-- A duplicate load within the same session reuses its state without a second lease write.
	equal(h.Data:load({ UserId = 101 }), profile)
	equal(h.Backend.Writes, 1)
end)

test("save and release preserve progression and LastSeen then allow the next server", function()
	local h = harness()
	local profile = assert(h.Data:load({ UserId = 102 }))
	profile.Cash = 700
	profile.Upgrades.menu = 2
	h.Data:markDirty(102)
	h:advance(45)
	assert(h.Data:save(102, false))
	equal(h.Backend.Records.Player_102.Profile.Cash, 700)
	equal(h.Backend.Records.Player_102.Profile.LastSeen, h:now())
	equal(profile.LastSeen, h:now())
	assert(h.Backend.Records.Player_102.Session ~= nil)
	profile.Cash = 850
	h:advance(19)
	assert(h.Data:release(102))
	equal(h.Backend.Records.Player_102.Profile.Cash, 850)
	equal(h.Backend.Records.Player_102.Profile.LastSeen, h:now())
	equal(h.Backend.Records.Player_102.Session, nil)
	equal(h.Data:isWritable(102), false)
	local nextServer = harness({ Backend = h.Backend })
	nextServer:advance(h.Clock)
	local loaded = assert(nextServer.Data:load({ UserId = 102 }))
	equal(loaded.Cash, 850)
	equal(loaded.Upgrades.menu, 2)
end)

test("another server cannot load or overwrite a profile with a live lease", function()
	local first = harness()
	assert(first.Data:load({ UserId = 103 }))
	local token = first.Backend.Records.Player_103.Session.Id
	local second = harness({ Backend = first.Backend })
	local profile, failure = second.Data:load({ UserId = 103 })
	equal(profile, nil)
	contains(failure, "another server")
	equal(second.Data:isWritable(103), false)
	equal(second.Data:save(103, false), false)
	equal(first.Backend.Writes, 1)
	equal(first.Backend.Records.Player_103.Session.Id, token)
	assert(first.Data:isWritable(103))
end)

test("an expired lease is recoverable while retaining the saved cafe", function()
	local h = harness()
	h.Backend.Records.Player_104 = savedRecord(3456)
	h.Backend.Records.Player_104.Session = { Id = "expired-owner", ExpiresAt = EPOCH - 1 }
	local loaded = assert(h.Data:load({ UserId = 104 }))
	equal(loaded.Cash, 3456)
	equal(loaded.Upgrades.menu, 2)
	assert(h.Backend.Records.Player_104.Session.Id ~= "expired-owner")
end)

test("both future envelope and future profile schemas are refused without a write", function()
	for _, location in ipairs({ "Envelope", "Profile" }) do
		local h = harness()
		local original = savedRecord(8765)
		if location == "Envelope" then original.SchemaVersion = Config.Version + 1
		else original.Profile.Version = Config.Version + 1 end
		h.Backend.Records.Player_105 = original
		local profile, failure = h.Data:load({ UserId = 105 })
		equal(profile, nil)
		contains(failure, "newer game version")
		equal(h.Data:isWritable(105), false)
		equal(h.Data:release(105), false)
		equal(h.Backend.Writes, 0)
		equal(h.Backend.Records.Player_105.Profile.Cash, 8765)
		equal(h.Backend.Records.Player_105, original)
	end
end)

test("load outage exhausts retries without creating fresh data or permitting a save", function()
	local h = harness()
	local original = savedRecord(5432)
	h.Backend.Records.Player_106 = original
	h.Backend.Failures = { "temporary network error", "temporary network error", "temporary network error" }
	local profile, failure = h.Data:load({ UserId = 106 })
	equal(profile, nil)
	contains(failure, "saved progress was not changed")
	equal(h.Backend.Calls, 3)
	equal(h.Backend.Writes, 0)
	equal(h.Backend.Records.Player_106, original)
	equal(h.Data:isWritable(106), false)
	equal(h.Data:save(106, false), false)
	-- Recovery must reload the real existing record, never the starting-cash fallback.
	local recovered = assert(h.Data:load({ UserId = 106 }))
	equal(recovered.Cash, 5432)
	equal(recovered.Upgrades.menu, 2)
	equal(h.Backend.Writes, 1)
end)

test("a transient first-call load failure retries and retains existing progression", function()
	local h = harness()
	h.Backend.Records.Player_107 = savedRecord(8888)
	h.Backend.Failures = { "transient service unavailable" }
	local profile = assert(h.Data:load({ UserId = 107 }))
	equal(profile.Cash, 8888)
	equal(profile.Upgrades.menu, 2)
	equal(h.Backend.Calls, 2)
	equal(h.Backend.Writes, 1)
	assert(h.Clock > 0)
end)

test("unpublished Studio explicitly uses session-only progress without contacting the store", function()
	local h = harness({ Studio = true, GameId = 0 })
	local profile = assert(h.Data:load({ UserId = 108 }))
	equal(h.Data:getStatus(108), "Session only")
	assert(h.Data:isWritable(108))
	profile.Cash = 1234
	h:advance(20)
	assert(h.Data:save(108, false))
	equal(profile.LastSeen, h:now())
	equal(h.Data:getStatus(108), "Session only")
	assert(h.Data:release(108))
	equal(h.Backend.Calls, 0)
	equal(h.Backend.Writes, 0)
	equal(h.Data:isWritable(108), false)
end)

test("Studio API-disabled error is session-only but the same live-server error refuses loading", function()
	for _, studio in ipairs({ true, false }) do
		local h = harness({ Studio = studio })
		h.Backend.Records.Player_109 = savedRecord(9000)
		h.Backend.Failures = {
			"Studio access to API services is not allowed",
			"Studio access to API services is not allowed",
			"Studio access to API services is not allowed",
		}
		local profile = h.Data:load({ UserId = 109 })
		if studio then
			assert(profile)
			equal(profile.Cash, Config.StartingCash)
			equal(h.Data:getStatus(109), "Session only")
			assert(h.Data:save(109, false))
		else
			equal(profile, nil)
			equal(h.Data:isWritable(109), false)
		end
		equal(h.Backend.Writes, 0)
		equal(h.Backend.Records.Player_109.Profile.Cash, 9000)
	end
end)

test("losing a lease blocks progression and cannot overwrite the new owner's profile", function()
	local h = harness()
	local profile = assert(h.Data:load({ UserId = 110 }))
	profile.Cash = 6000
	h.Data:markDirty(110)
	local stolen = savedRecord(7777)
	stolen.Session = { Id = "different-server-token", ExpiresAt = EPOCH + 600 }
	h.Backend.Records.Player_110 = stolen
	equal(h.Data:save(110, false), false)
	equal(h.Data:getStatus(110), "Session lost")
	equal(h.Data:isWritable(110), false)
	equal(h.Backend.Records.Player_110, stolen)
	equal(h.Backend.Records.Player_110.Profile.Cash, 7777)
	equal(h.Backend.Writes, 1)
	local reloaded, failure = h.Data:load({ UserId = 110 })
	equal(reloaded, nil)
	contains(failure, "moved to another server")
	equal(h.Data:release(110), false)
	equal(h.Backend.Records.Player_110.Session.Id, "different-server-token")
end)

test("corrupt legacy data is sanitized before a writable profile is exposed", function()
	local h = harness()
	h.Backend.Records.Player_111 = {
		Version = Config.Version, Cash = "invalid", LifetimeEarned = -500,
		LastSeen = EPOCH + 99999, Franchises = 0, Theme = "midnight",
		Upgrades = { menu = 900, staff = -12, machine = "five", forged = 100 },
		Achievements = { first_ten = "yes", forged = true },
		Daily = { Day = math.floor(EPOCH / 86400), Served = -5, Earned = "bad", Claimed = { forged = true } },
	}
	local profile = assert(h.Data:load({ UserId = 111 }))
	equal(profile.Cash, Config.StartingCash)
	equal(profile.LifetimeEarned, 0)
	equal(profile.LastSeen, EPOCH)
	equal(profile.Theme, "sage")
	equal(profile.Upgrades.menu, 5)
	equal(profile.Upgrades.staff, 0)
	equal(profile.Upgrades.machine, 0)
	equal(profile.Upgrades.forged, nil)
	equal(profile.Achievements.first_ten, nil)
	equal(profile.Achievements.forged, nil)
	equal(profile.Daily.Served, 0)
	equal(profile.Daily.Earned, 0)
	equal(profile.Daily.Claimed.forged, nil)
	assert(h.Data:isWritable(111))
	equal(h.Backend.Records.Player_111.Profile.Upgrades.menu, 5)
end)

test("departure during a pending load releases its own acquired lease", function()
	local h = harness()
	h.Backend.Records.Player_112 = savedRecord(4321)
	h.Backend.BeforeUpdate = function(_, call)
		if call == 1 then equal(h.Data:release(112), false) end
	end
	local profile, failure = h.Data:load({ UserId = 112 })
	equal(profile, nil)
	contains(failure, "left while")
	equal(h.Data:isWritable(112), false)
	equal(h.Backend.Records.Player_112.Session, nil)
	equal(h.Backend.Records.Player_112.Profile.Cash, 4321)
end)

print(string.format("%d mocked persistence scenarios passed; actual Roblox APIs were not exercised.", passed))
