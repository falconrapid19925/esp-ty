-- Executes the actual asset loader with Lune Instances and a fake AssetService.
-- This checks stripping/caching boundaries, not Roblox downloads or rendering.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Catalog = require("../src/shared/AssetCatalog")
local source = fs.readFile("src/server/Assets.luau")
local baseEnvironment = getfenv()
local passed = 0

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	return assert(self:FindFirstChild(name), "Missing child: " .. name)
end)
-- Lune has no engine geometry/physics. Keep that method explicit rather than
-- mistaking a fixed test box for an engine bounds calculation.
roblox.implementMethod("Model", "GetBoundingBox", function()
	return roblox.CFrame.new(), roblox.Vector3.new(5, 5, 5)
end)

local function child(parent, className, name)
	local value = roblox.Instance.new(className)
	value.Name = name or className
	if value:IsA("BasePart") then
		value.Position = roblox.Vector3.zero
		value.Size = roblox.Vector3.new(2, 2, 2)
	end
	value.Parent = parent
	return value
end

local function fixtureModel()
	local model = roblox.Instance.new("Model")
	model.Name = "CommunityModel"
	local tool = child(model, "Tool", "InteractiveCoffeeCup")
	child(tool, "Part", "Handle")
	child(tool, "Script", "UntrustedServerCode")
	child(model, "LocalScript", "UntrustedClientCode")
	child(model, "ModuleScript", "UntrustedModule")
	child(model, "RemoteEvent", "UnexpectedRemote")
	child(model, "Sound", "UnreviewedAudio")
	child(model, "ParticleEmitter", "UnboundedParticles")
	child(model, "Seat", "ChairCushion")
	return model
end

local function harness(options)
	options = options or {}
	local storage = roblox.Instance.new("ReplicatedStorage")
	local shared = child(storage, "Folder", "Shared")
	local catalogToken = child(shared, "ModuleScript", "AssetCatalog")
	local serverStorage = roblox.Instance.new("ServerStorage")
	if options.Override then
		local folder = child(serverStorage, "Folder", "AssetOverrides")
		local model = options.Override:Clone()
		model.Name = "espresso_machine"
		model.Parent = folder
	end
	local fixture = { Clock = 0, Calls = {}, Warnings = {}, ServerStorage = serverStorage }
	local services = {
		ReplicatedStorage = storage,
		ServerStorage = serverStorage,
		AssetService = {
			AllowInsertFreeAssets = options.Allowed ~= false,
			LoadAssetAsync = function(_, id)
				table.insert(fixture.Calls, id)
				if options.Fail then error("test asset unavailable") end
				return if options.Model then options.Model:Clone() else fixtureModel()
			end,
		},
	}
	local environment = setmetatable({
		game = { GetService = function(_, name) return assert(services[name], name) end },
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		require = function(token) assert(token == catalogToken) return Catalog end,
		os = { clock = function() return fixture.Clock end },
		task = {
			spawn = function(callback, ...) callback(...) end,
			wait = function(seconds) fixture.Clock += seconds or 0.03 end,
		},
		warn = function(message) table.insert(fixture.Warnings, tostring(message)) end,
	}, { __index = baseEnvironment })
	local entry = assert(loadstring(source, "@src/server/Assets.luau"))
	setfenv(entry, environment)
	fixture.Assets = entry()
	return fixture
end

local function test(name, callback)
	local ok, failure = pcall(callback)
	assert(ok, "FAIL " .. name .. ": " .. tostring(failure))
	passed += 1
	print("PASS " .. name)
end

test("disabled third-party setting makes no network loads and returns fallback signal", function()
	local f = harness({ Allowed = false })
	local status = f.Assets.preload()
	assert(#f.Calls == 0)
	assert(status.espresso_machine == "third-party loading disabled")
	assert(f.Assets.get("espresso_machine") == nil)
end)

test("community scripts/interactions are stripped while Tool-wrapped geometry survives", function()
	local f = harness()
	f.Assets.preload()
	local prop = assert(f.Assets.get("espresso_machine"), table.concat(f.Warnings, "\n"))
	local parts = 0
	for _, value in ipairs(prop:GetDescendants()) do
		assert(not value:IsA("LuaSourceContainer"))
		assert(not value:IsA("Tool"))
		assert(not value:IsA("RemoteEvent"))
		assert(not value:IsA("Sound"))
		assert(not value:IsA("ParticleEmitter"))
		if value:IsA("BasePart") then
			parts += 1
			assert(value.Anchored and not value.CanCollide and not value.CanTouch and not value.CanQuery)
			if value:IsA("Seat") then assert(value.Disabled) end
		end
	end
	assert(parts == 2, "Cup handle and disabled chair cushion should both survive")
	assert(prop:FindFirstChild("Handle"), "Nested Tool geometry must be flattened before Tool removal")
	assert(prop:GetAttribute("SourceAssetId") == "12520208389")
end)

test("cached models clone independently and do not reload on repeated get", function()
	local f = harness()
	f.Assets.preload()
	local calls = #f.Calls
	local first = assert(f.Assets.get("pastry"))
	first:FindFirstChild("Handle"):Destroy()
	local second = assert(f.Assets.get("pastry"))
	assert(first ~= second)
	assert(second:FindFirstChild("Handle"))
	assert(#f.Calls == calls)
end)

test("reviewed local overrides take precedence even when third-party loading is disabled", function()
	local localModel = roblox.Instance.new("Model")
	child(localModel, "Part", "ReviewedKenneyMachine")
	child(localModel, "Script", "ShouldStillBeRemoved")
	local f = harness({ Allowed = false, Override = localModel })
	local status = f.Assets.preload()
	local prop = assert(f.Assets.get("espresso_machine"))
	assert(prop:FindFirstChild("ReviewedKenneyMachine"))
	assert(not prop:FindFirstChild("ShouldStillBeRemoved"))
	assert(status.espresso_machine == "local override")
	assert(#f.Calls == 0)
	assert(f.ServerStorage.AssetOverrides.espresso_machine:FindFirstChild("ShouldStillBeRemoved"),
		"Sanitization works on a clone, leaving Studio source untouched")
end)

test("oversized geometry and excessive part counts are rejected", function()
	local enormous = roblox.Instance.new("Model")
	child(enormous, "Part").Size = roblox.Vector3.new(501, 2, 2)
	local f = harness({ Model = enormous })
	assert(f.Assets.preload().espresso_machine == "rejected geometry")
	assert(f.Assets.get("espresso_machine") == nil)
	local crowded = roblox.Instance.new("Model")
	for index = 1, Catalog.MaxParts + 1 do child(crowded, "Part", tostring(index)) end
	local crowdedFixture = harness({ Model = crowded })
	assert(crowdedFixture.Assets.preload().espresso_machine == "rejected geometry")
	assert(crowdedFixture.Assets.get("espresso_machine") == nil)
end)

test("unavailable asset returns nil without propagating network failures", function()
	local f = harness({ Fail = true })
	assert(f.Assets.preload().espresso_machine == "load failed")
	assert(f.Assets.get("espresso_machine") == nil)
	assert(f.Assets.get("unconfigured_key") == nil)
end)

print("Asset loader scenarios passed: " .. passed)
