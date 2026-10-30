-- Executes the real world module with real Roblox datatypes and mocked services.
-- Checks lifecycle/asset boundaries, not rendering, avatar APIs or mesh permissions.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
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
	local event = { Listeners = {} }
	function event:Connect(callback)
		local listener = { Active = true, Callback = callback }
		table.insert(self.Listeners, listener)
		return { Disconnect = function() listener.Active = false end }
	end
	function event:Once(callback)
		local connection
		connection = self:Connect(function(...)
			connection.Disconnect()
			callback(...)
		end)
		return connection
	end
	function event:Fire(...)
		for _, listener in ipairs(table.clone(self.Listeners)) do
			if listener.Active then listener.Callback(...) end
		end
	end
	function event:DisconnectAll()
		for _, listener in ipairs(self.Listeners) do listener.Active = false end
	end
	return event
end

local function harness()
	local fixture = { Clock = 0, Delayed = {}, Debris = {}, Tweens = {}, Spawned = {}, AssetRequests = {}, SourceAssets = false }
	local methods, mockInstance = {}, {}
	local function descendants(root)
		local result = {}
		for _, child in ipairs(root.Children) do
			table.insert(result, child)
			for _, nested in ipairs(descendants(child)) do table.insert(result, nested) end
		end
		return result
	end
	local objectMetatable = {
		__index = function(target, key)
			if methods[key] then return methods[key] end
			if key == "Position" and target.Properties.CFrame then return target.Properties.CFrame.Position end
			if target.Properties[key] ~= nil then return target.Properties[key] end
			for _, child in ipairs(target.Children) do if child.Name == key then return child end end
			return nil
		end,
		__newindex = function(target, key, value)
			-- Lune's reflection snapshot validates actual engine property names/types.
			-- Relationship/tween bookkeeping stays in the mock service layer.
			if key ~= "Parent" and key ~= "PrimaryPart" and key ~= "Pivot" and key ~= "Scale" and key ~= "Destroyed" then
				local ok, failure = pcall(function() target.Native[key] = value end)
				assert(ok, target.Properties.ClassName .. "." .. key .. ": " .. tostring(failure))
			end
			if key == "Parent" then
				local previous = target.Properties.Parent
				if previous then
					for index, child in ipairs(previous.Children) do
						if child == target then table.remove(previous.Children, index) break end
					end
				end
				if value then table.insert(value.Children, target) end
			end
			target.Properties[key] = value
			if key == "Value" then target.Properties.Changed:Fire(value) end
		end,
	}
	function mockInstance.new(className)
		return setmetatable({
			Native = roblox.Instance.new(className),
			Properties = {
				ClassName = className, Name = className, CFrame = roblox.CFrame.identity,
				Size = roblox.Vector3.one, Triggered = signal(), Changed = signal(),
			},
			Children = {}, Attributes = {},
		}, objectMetatable)
	end
	function methods:IsA(className)
		if self.ClassName == className then return true end
		if className == "BasePart" then return self.ClassName == "Part" or self.ClassName == "SpawnLocation" end
		if className == "LuaSourceContainer" then
			return self.ClassName == "Script" or self.ClassName == "LocalScript" or self.ClassName == "ModuleScript"
		end
		return false
	end
	function methods:GetChildren() return table.clone(self.Children) end
	function methods:GetDescendants() return descendants(self) end
	function methods:FindFirstChild(name, recursive)
		for _, child in ipairs(self.Children) do if child.Name == name then return child end end
		if recursive then
			for _, child in ipairs(self.Children) do
				local found = child:FindFirstChild(name, true)
				if found then return found end
			end
		end
		return nil
	end
	function methods:FindFirstChildOfClass(className)
		for _, child in ipairs(self.Children) do if child.ClassName == className then return child end end
		return nil
	end
	function methods:WaitForChild(name) return self:FindFirstChild(name) end
	function methods:ClearAllChildren()
		for _, child in ipairs(table.clone(self.Children)) do child:Destroy() end
	end
	function methods:Destroy()
		self.Parent = nil
		self:ClearAllChildren()
		self.Triggered:DisconnectAll()
		self.Changed:DisconnectAll()
		self.Destroyed = true
	end
	function methods:SetAttribute(key, value) self.Attributes[key] = value end
	function methods:GetPivot() return self.Pivot or (self.PrimaryPart and self.PrimaryPart.CFrame) or roblox.CFrame.identity end
	function methods:PivotTo(transform)
		local delta = transform * self:GetPivot():Inverse()
		for _, item in ipairs(self:GetDescendants()) do
			if item:IsA("BasePart") then item.CFrame = delta * item.CFrame end
		end
		self.Pivot = transform
	end
	function methods:GetScale() return self.Scale or 1 end
	function methods:ScaleTo(scale)
		local ratio, pivot = scale / self:GetScale(), self:GetPivot()
		for _, item in ipairs(self:GetDescendants()) do
			if item:IsA("BasePart") then
				local relative = pivot:ToObjectSpace(item.CFrame)
				item.Size *= ratio
				item.CFrame = pivot * roblox.CFrame.new(relative.Position * ratio) * (relative - relative.Position)
			end
		end
		self.Scale = scale
	end
	function methods:GetBoundingBox()
		local pivot, minimum, maximum = self:GetPivot(), nil, nil
		for _, item in ipairs(self:GetDescendants()) do
			if item:IsA("BasePart") then
				local position = pivot:PointToObjectSpace(item.Position)
				local low, high = position - item.Size / 2, position + item.Size / 2
				minimum = if minimum then minimum:Min(low) else low
				maximum = if maximum then maximum:Max(high) else high
			end
		end
		assert(minimum and maximum, "Mock model has no geometry")
		return pivot * roblox.CFrame.new((minimum + maximum) / 2), maximum - minimum
	end
	function methods:Play() self.Playing = true end
	function methods:Stop() self.Playing = false end
	local function child(parent, name, className)
		local value = mockInstance.new(className or "Folder")
		value.Name, value.Parent = name, parent
		return value
	end
	local workspace = mockInstance.new("Workspace")
	local lighting = mockInstance.new("Lighting")
	local storage = mockInstance.new("ReplicatedStorage")
	local shared = child(storage, "Shared")
	local configToken = child(shared, "Config", "ModuleScript")
	local economyToken = child(shared, "Economy", "ModuleScript")
	local catalogToken = child(shared, "AssetCatalog", "ModuleScript")
	local server = mockInstance.new("Folder")
	local scriptToken = child(server, "World", "ModuleScript")
	local assetsToken = child(server, "Assets", "ModuleScript")
	local assets = {}
	function assets.get(key)
		table.insert(fixture.AssetRequests, key)
		if not fixture.SourceAssets then return nil end
		local model = mockInstance.new("Model")
		local geometry = child(model, "SourcedGeometry", "Part")
		-- An awkward source pivot/size exercises normalization rather than a pre-fitted dummy.
		geometry.Size = roblox.Vector3.new(12, 8, 10)
		geometry.CFrame = roblox.CFrame.new(45, 20, -35)
		return model
	end
	local services = {
		Players = { CreateHumanoidModelFromDescriptionAsync = function() error("Avatar platform unavailable in mock") end },
		Lighting = lighting, ReplicatedStorage = storage,
		TweenService = { Create = function(_, target, info, properties)
			local tween = { Completed = signal(), Target = target, Properties = properties, Duration = info.Duration, Active = false }
			function tween:Play()
				self.Active, self.EndsAt = true, fixture.Clock + self.Duration
				table.insert(fixture.Tweens, self)
			end
			function tween:Cancel()
				if self.Active then self.Active = false self.Completed:Fire(roblox.Enum.PlaybackState.Cancelled) end
			end
			return tween
		end },
		Debris = { AddItem = function(_, item, seconds)
			table.insert(fixture.Debris, { Item = item, At = fixture.Clock + seconds })
		end },
	}
	local environment = setmetatable({
		game = { GetService = function(_, name) assert(services[name], "Unexpected service " .. name) return services[name] end },
		workspace = workspace, script = scriptToken, Instance = mockInstance,
		Enum = roblox.Enum, Color3 = roblox.Color3, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame,
		UDim = roblox.UDim, UDim2 = roblox.UDim2, NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence, NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, ColorSequence = roblox.ColorSequence,
		TweenInfo = { new = function(duration) return { Duration = duration } end },
		os = { time = function() return 1793390400 + math.floor(fixture.Clock) end },
		task = {
			spawn = function(callback) table.insert(fixture.Spawned, callback) end,
			delay = function(seconds, callback) table.insert(fixture.Delayed, { Callback = callback, At = fixture.Clock + seconds }) end,
		},
		require = function(token)
			if token == configToken then return Config end
			if token == economyToken then return Economy end
			if token == catalogToken then return AssetCatalog end
			if token == assetsToken then return assets end
			error("Unexpected world module require")
		end,
	}, { __index = baseEnvironment })
	local entry, failure = loadstring(fs.readFile("src/server/World.luau"), "@src/server/World.luau")
	assert(entry, failure)
	setfenv(entry, environment)
	fixture.World = entry().build()
	function fixture:advance(seconds)
		self.Clock += seconds
		for _, tween in ipairs(self.Tweens) do
			if tween.Active and tween.EndsAt <= self.Clock then
				tween.Active = false
				for key, value in pairs(tween.Properties) do tween.Target[key] = value end
				tween.Completed:Fire(roblox.Enum.PlaybackState.Completed)
			end
		end
		for index = #self.Delayed, 1, -1 do
			local work = self.Delayed[index]
			if work.At <= self.Clock then table.remove(self.Delayed, index) work.Callback() end
		end
		for index = #self.Debris, 1, -1 do
			local work = self.Debris[index]
			if work.At <= self.Clock then table.remove(self.Debris, index) work.Item:Destroy() end
		end
	end
	function fixture:player(id)
		local player = { UserId = id, Name = "Barista" .. id, DisplayName = "Barista " .. id }
		player.Character = child(workspace, "Character" .. id, "Model")
		child(player.Character, "HumanoidRootPart", "Part")
		return player
	end
	return fixture
end

local function modelCount(root)
	local count = 0
	for _, child in ipairs(root:GetChildren()) do if child:IsA("Model") then count += 1 end end
	return count
end

test("world builds all six visitable cafes using valid Roblox datatypes and enums", function()
	local h = harness()
	assert(#h.World._plots == 6)
	for _, plot in ipairs(h.World._plots) do
		assert(plot.Structure:FindFirstChild("OakFloor"))
		assert(plot.Furniture:FindFirstChild("BrewInteraction"))
		assert(plot.Customers.Parent == plot.Root)
	end
	-- Avatar service failure is isolated; world construction already succeeded.
	for _, callback in ipairs(h.Spawned) do callback() end
	assert(h.World._personTemplate == nil)
end)

test("plot assignment is idempotent, rejects overflow and spawns safely at its cafe", function()
	local h = harness()
	for index = 1, 6 do
		local player = h:player(index)
		assert(h.World:assignPlot(player) == index)
		assert(h.World:assignPlot(player) == index)
		h.World:spawnPlayer(player)
		local expected = h.World._plots[index].Transform * roblox.CFrame.new(0, 4.5, -16)
		assert((player.Character:GetPivot().Position - expected.Position).Magnitude < 0.001)
		assert(player.Character.HumanoidRootPart.AssemblyLinearVelocity == roblox.Vector3.zero)
	end
	assert(h.World:assignPlot(h:player(99)) == nil)
end)

test("world brew and purchase prompts route only their owning player", function()
	local h = harness()
	local owner, visitor = h:player(1), h:player(2)
	h.World:assignPlot(owner)
	local brews, purchases = 0, 0
	h.World:setHandlers({
		Brew = function(player) assert(player == owner) brews += 1 end,
		BuyUpgrade = function(player, id) assert(player == owner and id == "machine") purchases += 1 end,
	})
	local furniture = h.World._plots[1].Furniture
	local brew = furniture.BrewInteraction:FindFirstChildOfClass("ProximityPrompt")
	local upgrade = furniture.Upgrade_machine:FindFirstChildOfClass("ProximityPrompt")
	brew.Triggered:Fire(visitor)
	upgrade.Triggered:Fire(visitor)
	assert(brews == 0 and purchases == 0)
	brew.Triggered:Fire(owner)
	upgrade.Triggered:Fire(owner)
	assert(brews == 1 and purchases == 1)
end)

test("available sourced props replace fallback geometry and normalize source bounds", function()
	local h = harness()
	h.SourceAssets = true
	local player, profile = h:player(1), Economy.newProfile(1793390400)
	h.World:assignPlot(player)
	profile.Upgrades.bakery = 1
	h.World:refreshPlot(player, profile)
	local furniture = h.World._plots[1].Furniture
	for _, key in ipairs({ "espresso_machine", "cafe_table", "plant", "pastry" }) do
		assert(furniture:FindFirstChild("Sourced_" .. key), "Sourced prop omitted: " .. key)
	end
	assert(not furniture:FindFirstChild("EspressoMachineBody_Fallback"))
	assert(not furniture:FindFirstChild("ChairSeat"), "Imported table set must not get duplicate fallback chairs")
	local machine = furniture.Sourced_espresso_machine
	local box, size = machine:GetBoundingBox()
	assert(size.X <= 6.501 and size.Y <= 4.201 and size.Z <= 3.801)
	assert(math.abs(box.Position.Y - size.Y / 2 - 4.92) < 0.001, "Imported machine must sit on countertop")
end)

test("upgrading or changing theme preserves the active order guest and brew", function()
	local h = harness()
	local player, profile = h:player(1), Economy.newProfile(1793390400)
	h.World:assignPlot(player)
	h.World:showOrder(player, Config.Recipes[1], true)
	h.World:setBrew(player, true)
	local plot = h.World._plots[1]
	local guest = plot.Guest
	for _, upgrade in ipairs(Config.Upgrades) do profile.Upgrades[upgrade.Id] = upgrade.MaxLevel end
	profile.Theme, profile.Franchises = "midnight", 2
	h.World:refreshPlot(player, profile)
	assert(plot.Guest == guest and guest.Parent == plot.Customers)
	assert(plot.Brewing and plot.Steam.Enabled)
	assert(plot.Furniture:FindFirstChild("TerracePergola"))
	assert(plot.Furniture:FindFirstChild("Barista3"))
end)

test("rapid order changes stay bounded and served guests depart before debris cleanup", function()
	local h = harness()
	local player = h:player(1)
	h.World:assignPlot(player)
	local plot = h.World._plots[1]
	for _ = 1, 30 do h.World:showOrder(player, Config.Recipes[1], false) end
	assert(modelCount(plot.Customers) == 1)
	for _ = 1, 12 do
		h:advance(2.3)
		h.World:setBrew(player, true)
		h.World:serveCustomer(player, Config.Recipes[1], 32, true)
		h.World:setBrew(player, false)
		h.World:showOrder(player, Config.Recipes[1], false)
		assert(modelCount(plot.Customers) <= 2, "Departing customers accumulated")
	end
	h:advance(4)
	assert(modelCount(plot.Customers) == 1)
end)

test("release cancels the active guest, clears guests and frees the plot for a new owner", function()
	local h = harness()
	local player = h:player(1)
	h.World:assignPlot(player)
	h.World:showOrder(player, Config.Recipes[1], true)
	h.World:setBrew(player, true)
	local plot, guest = h.World._plots[1], h.World._plots[1].Guest
	h.World:releasePlot(player)
	assert(h.World._byUser[player.UserId] == nil)
	assert(not plot.Owner and not plot.Guest and not plot.GuestTween and not plot.Brewing)
	assert(guest.Parent == nil and #plot.Customers:GetChildren() == 0)
	assert(h.World:assignPlot(h:player(2)) == 1)
	h:advance(5)
	assert(#plot.Customers:GetChildren() == 0)
end)

print(string.format("PASS %d world lifecycle/asset scenarios; actual visuals and Roblox platform services require Studio", passed))
