local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local DataService = require(script.Parent.DataService)

local GameService = {}
local started = false

local function instance(className, name, parent)
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA(className), name .. " has an unexpected class")
		return existing
	end
	local object = Instance.new(className)
	object.Name = name
	object.Parent = parent
	return object
end

function GameService.start(world)
	assert(not started, "Espresso GameService was already started")
	started = true
	local remotes = instance("Folder", "Remotes", ReplicatedStorage)
	local actionEvent = instance("RemoteEvent", "Action", remotes)
	local stateEvent = instance("RemoteEvent", "State", remotes)
	local getState = instance("RemoteFunction", "GetState", remotes)
	local states = {}
	local stopping = false
	local rushDuration = Config.RushDuration or 40
	local rushInterval = Config.RushInterval or 240
	local rush = {Active = false, EndsAt = 0, NextAt = workspace:GetServerTimeNow() + rushInterval}
	local data
	local attemptLoad

	local function worldCall(method, ...)
		if type(world[method]) == "function" then
			local success, failure = pcall(world[method], world, ...)
			if not success then
				warn("[Espresso] World " .. method .. " failed: " .. tostring(failure))
			end
			return success
		end
		return false
	end

	local function snapshot(state)
		return {
			Ready = state.Ready == true,
			Error = state.Error,
			Profile = if state.Ready then state.Profile else nil,
			PlotIndex = state.PlotIndex,
			SelectedRecipe = state.SelectedRecipe or "espresso",
			Order = state.Order,
			Brew = state.Brew,
			ServerTime = workspace:GetServerTimeNow(),
			Rush = {Active = rush.Active, EndsAt = rush.EndsAt, NextAt = rush.NextAt},
			SaveStatus = data:getStatus(state.Player.UserId),
			OfflineReward = state.OfflineReward or 0,
			Message = state.Message,
		}
	end

	local function push(state, message)
		if state.Dead or state.Player.Parent ~= Players then
			return
		end
		if message then
			state.Message = message
		end
		state.LastPush = workspace:GetServerTimeNow()
		stateEvent:FireClient(state.Player, snapshot(state))
	end

	local function leaderstats(state)
		local folder = instance("Folder", "leaderstats", state.Player)
		instance("IntValue", "Cash", folder).Value = math.floor(state.Profile.Cash)
		instance("IntValue", "Served", folder).Value = math.floor(state.Profile.LifetimeServed)
		instance("IntValue", "Franchises", folder).Value = math.floor(state.Profile.Franchises)
	end

	local function funnel(state, step, name)
		if not state.NewPlayer or state.Funnel[step] or RunService:IsStudio() or game.GameId == 0 then
			return
		end
		state.Funnel[step] = true
		task.spawn(function()
			local success, failure = pcall(function()
				AnalyticsService:LogOnboardingFunnelStepEvent(state.Player, step, name)
			end)
			if not success then
				warn("[Espresso] Onboarding analytics unavailable: " .. tostring(failure))
			end
		end)
	end

	data = DataService.new(function(userId, status)
		local player = Players:GetPlayerByUserId(userId)
		local state = if player then states[player] else nil
		if state then
			if status == "Session lost" then
				state.Ready = false
				state.SessionLost = true
				state.Error = "Your save session moved to another server. Please rejoin to protect your progress."
				state.Brew = nil
				worldCall("setBrew", player, false)
			end
			push(state)
		end
	end)

	local function nextOrder(state)
		local recipe = Economy.recipe(state.Profile, state.SelectedRecipe)
		if not recipe then
			recipe = Economy.unlockedRecipes(state.Profile)[1]
			state.SelectedRecipe = recipe.Id
		end
		local vipChance = 0.08 + (state.Profile.Upgrades.decor or 0) * 0.015
		state.Order = {RecipeId = recipe.Id, Vip = math.random() < vipChance}
		worldCall("showOrder", state.Player, recipe, state.Order.Vip)
	end

	local function changed(state, refreshWorld)
		data:markDirty(state.Player.UserId)
		leaderstats(state)
		if refreshWorld then
			worldCall("refreshPlot", state.Player, state.Profile)
		end
	end

	local function checkpoint(state)
		local now = os.clock()
		if now - state.LastCheckpoint >= 15 then
			state.LastCheckpoint = now
			task.spawn(function()
				data:save(state.Player.UserId, false)
			end)
		end
	end

	local function expireBrew(state, now)
		if state.Brew and now > state.Brew.ExpiresAt then
			state.Brew = nil
			worldCall("setBrew", state.Player, false)
			return true
		end
		return false
	end

	local function allowed(state)
		local now = os.clock()
		state.Tokens = math.min(8, state.Tokens + (now - state.TokenTime) * 4)
		state.TokenTime = now
		if state.Tokens < 1 then
			return false
		end
		state.Tokens -= 1
		return true
	end

	local function dispatch(player, action, argument)
		local state = states[player]
		if not state or state.Dead or type(action) ~= "string" or #action > 32 or not allowed(state) then
			return
		end
		if not state.Ready then
			push(state, "Please wait for your café to finish loading.")
			return
		end
		if not data:isWritable(player.UserId) then
			push(state, "Café actions are paused while the save connection recovers. Your progress is protected.")
			return
		end
		if argument ~= nil and (type(argument) ~= "string" or #argument > 40) then
			return
		end
		local now = workspace:GetServerTimeNow()
		local epoch = os.time()
		Economy.rollDaily(state.Profile, epoch)
		expireBrew(state, now)

		if action == "Brew" then
			if state.Brew then
				push(state, "Your espresso is extracting. Serve it when the meter reaches the green zone.")
				return
			end
			local recipe = Economy.recipe(state.Profile, state.Order.RecipeId)
			if not recipe then
				nextOrder(state)
				recipe = Economy.recipe(state.Profile, state.Order.RecipeId)
			end
			local ready = now + Economy.brewDuration(state.Profile, recipe)
			state.Brew = {
				StartedAt = now,
				ReadyAt = ready,
				PerfectUntil = ready + (Config.PerfectWindow or 1.15),
				ExpiresAt = ready + (Config.ServeWindow or 14),
			}
			worldCall("setBrew", player, true)
			funnel(state, 2, "First shot started")
			push(state, "Pulling your shot. Serve in the green zone for a perfect bonus!")
		elseif action == "Serve" then
			local brew = state.Brew
			if not brew then
				push(state, "Start brewing a drink first.")
				return
			end
			if now < brew.ReadyAt then
				push(state, "Give the espresso a moment to finish extracting.")
				return
			end
			local perfect = now <= brew.PerfectUntil
			local recipe = Economy.recipe(state.Profile, state.Order.RecipeId)
			local vip = state.Order.Vip
			-- Clear before any world callbacks. A repeated remote cannot sell the same shot twice.
			state.Brew = nil
			local amount = Economy.recordSale(state.Profile, recipe.Id, perfect, vip, rush.Active, epoch)
			state.Profile.ManualServed += 1
			changed(state, false)
			worldCall("serveCustomer", player, recipe, amount, perfect)
			worldCall("setBrew", player, false)
			nextOrder(state)
			funnel(state, 3, "First drink served")
			push(state, (if perfect then "Perfect extraction! +" else "Drink served! +") .. Economy.formatMoney(amount))
		elseif action == "BuyUpgrade" then
			local success, message = Economy.buyUpgrade(state.Profile, argument, epoch)
			if success then
				changed(state, true)
				state.NextStaffAt = now + Economy.staffInterval(state.Profile)
				funnel(state, 4, "First upgrade bought")
				checkpoint(state)
			end
			push(state, message)
		elseif action == "SelectRecipe" then
			if state.Brew then
				push(state, "Serve your current drink before changing the menu.")
				return
			end
			local recipe = Economy.recipe(state.Profile, argument)
			if not recipe then
				push(state, "Upgrade your menu to unlock that recipe.")
				return
			end
			state.SelectedRecipe = recipe.Id
			nextOrder(state)
			push(state, recipe.Name .. " is now your featured drink.")
		elseif action == "ClaimQuest" then
			local success, message = Economy.claimQuest(state.Profile, argument, epoch)
			if success then
				changed(state, false)
				checkpoint(state)
			end
			push(state, message)
		elseif action == "ClaimAchievement" then
			local success, message = Economy.claimAchievement(state.Profile, argument)
			if success then
				changed(state, false)
				checkpoint(state)
			end
			push(state, message)
		elseif action == "SetTheme" then
			local success, message = Economy.setTheme(state.Profile, argument)
			if success then
				changed(state, true)
				checkpoint(state)
			end
			push(state, message)
		elseif action == "Franchise" then
			local success, message = Economy.franchise(state.Profile, epoch)
			if success then
				state.Brew = nil
				state.SelectedRecipe = "espresso"
				state.NextStaffAt = now + Economy.staffInterval(state.Profile)
				worldCall("setBrew", player, false)
				changed(state, true)
				nextOrder(state)
				state.LastCheckpoint = os.clock()
				task.spawn(function()
					data:save(player.UserId, false)
				end)
			end
			push(state, message)
		end
	end

	attemptLoad = function(state)
		if state.Loading or state.Dead or state.Ready or state.SessionLost or stopping then
			return
		end
		state.Loading = true
		state.LastLoadAttempt = os.clock()
		state.Error = nil
		push(state)
		local profile, failure = data:load(state.Player)
		state.Loading = false
		if state.Dead or state.Player.Parent ~= Players or stopping then
			data:release(state.Player.UserId)
			return
		end
		if not profile then
			state.Error = failure
			push(state)
			return
		end
		local success, plotIndex = pcall(world.assignPlot, world, state.Player)
		if not success or not plotIndex then
			state.Error = "All cafés are occupied. A plot will be assigned when one opens."
			data:release(state.Player.UserId)
			push(state)
			return
		end
		state.Profile = profile
		state.PlotIndex = plotIndex
		state.NewPlayer = profile.ManualServed == 0
		Economy.rollDaily(profile, os.time())
		local elapsed = math.max(0, os.time() - profile.LastSeen)
		local offline = Economy.offlineEarnings(profile, elapsed)
		state.OfflineReward = offline
		if offline > 0 then
			profile.Cash += offline
			profile.LifetimeEarned += offline
		end
		state.Ready = true
		state.Error = nil
		state.NextStaffAt = workspace:GetServerTimeNow() + Economy.staffInterval(profile)
		changed(state, true)
		nextOrder(state)
		worldCall("spawnPlayer", state.Player)
		funnel(state, 1, "Cafe ready")
		push(state, if offline > 0 then "Welcome back! Your baristas earned " .. Economy.formatMoney(offline) .. " while you were away."
			else "Welcome to your café! Pull a shot, serve a customer, and buy your first upgrade.")
		if offline > 0 then
			checkpoint(state)
		end
	end

	local function joined(player)
		if states[player] or stopping then
			return
		end
		local now = workspace:GetServerTimeNow()
		local state = {
			Player = player,
			Ready = false,
			Loading = false,
			Dead = false,
			SessionLost = false,
			Profile = nil,
			SelectedRecipe = "espresso",
			Brew = nil,
			Order = nil,
			OfflineReward = 0,
			Message = nil,
			Funnel = {},
			Tokens = 8,
			TokenTime = os.clock(),
			LastPush = now,
			LastLoadAttempt = -100,
			LastCheckpoint = -100,
			NextStaffAt = now + 15,
		}
		states[player] = state
		state.CharacterConnection = player.CharacterAdded:Connect(function()
			if state.Ready and not state.Dead then
				task.defer(function()
					if state.Ready and not state.Dead then
						worldCall("spawnPlayer", player)
					end
				end)
			end
		end)
		task.spawn(attemptLoad, state)
	end

	local function leaving(player)
		local state = states[player]
		if not state then
			return
		end
		state.Dead = true
		state.Ready = false
		if state.CharacterConnection then
			state.CharacterConnection:Disconnect()
		end
		states[player] = nil
		worldCall("releasePlot", player)
		task.spawn(function()
			data:release(player.UserId)
		end)
	end

	actionEvent.OnServerEvent:Connect(dispatch)
	getState.OnServerInvoke = function(player)
		local state = states[player]
		if not state then
			joined(player)
			state = states[player]
		end
		if not state then
			return {Ready = false, Error = "Server is closing. Please rejoin.", ServerTime = workspace:GetServerTimeNow()}
		end
		if not state.Ready and not state.Loading and not state.SessionLost and os.clock() - state.LastLoadAttempt >= 12 then
			task.spawn(attemptLoad, state)
		end
		return snapshot(state)
	end
	worldCall("setHandlers", {
		Brew = function(player)
			local state = states[player]
			local action = if state and state.Brew and workspace:GetServerTimeNow() >= state.Brew.ReadyAt then "Serve" else "Brew"
			dispatch(player, action)
		end,
		BuyUpgrade = function(player, id)
			dispatch(player, "BuyUpgrade", id)
		end,
	})
	Players.PlayerAdded:Connect(joined)
	Players.PlayerRemoving:Connect(leaving)
	for _, player in ipairs(Players:GetPlayers()) do
		joined(player)
	end

	task.spawn(function()
		while not stopping do
			task.wait(0.2)
			local now = workspace:GetServerTimeNow()
			if rush.Active and now >= rush.EndsAt then
				rush.Active = false
				rush.NextAt = now + rushInterval
			elseif not rush.Active and now >= rush.NextAt then
				rush.Active = true
				rush.EndsAt = now + rushDuration
				for _, state in pairs(states) do
					if state.Ready then
						push(state, "Coffee rush! Every sale earns a rush bonus for a little while.")
					end
				end
			end
			for _, state in pairs(states) do
				if state.Ready and not state.Dead and data:isWritable(state.Player.UserId) then
					local previousDay = state.Profile.Daily.Day
					Economy.rollDaily(state.Profile, os.time())
					if previousDay ~= state.Profile.Daily.Day then
						changed(state, false)
					end
					if expireBrew(state, now) then
						push(state, "That shot cooled down. Pull another shot to serve this customer.")
					end
					if (state.Profile.Upgrades.staff or 0) > 0 and now >= state.NextStaffAt then
						local unlocked = Economy.unlockedRecipes(state.Profile)
						local recipe = unlocked[#unlocked]
						-- Staff run a separate service lane and never consume the manual order or shot.
						Economy.recordSale(state.Profile, recipe.Id, false, false, rush.Active, os.time())
						state.NextStaffAt = now + Economy.staffInterval(state.Profile)
						changed(state, false)
					elseif (state.Profile.Upgrades.staff or 0) == 0 then
						state.NextStaffAt = now + Economy.staffInterval(state.Profile)
					end
					if now - state.LastPush >= 2 then
						push(state)
					end
				elseif not state.Ready and not state.Loading and not state.SessionLost and not state.Dead
					and os.clock() - state.LastLoadAttempt >= 12 then
					task.spawn(attemptLoad, state)
				end
			end
		end
	end)

	game:BindToClose(function()
		stopping = true
		for _, state in pairs(states) do
			state.Ready = false
		end
		data:shutdown()
	end)
	return {Data = data, States = states, Dispatch = dispatch}
end

return GameService
