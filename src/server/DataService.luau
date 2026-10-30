-- Persistence stays server-side. A failed load never becomes a writable new save.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)

local DataService = {}
DataService.__index = DataService

local SAVE_INTERVAL = Config.SaveInterval or 60
local LEASE_SECONDS = math.max(180, SAVE_INTERVAL * 4)
local MAX_ATTEMPTS = 3
local SCHEMA_VERSION = Config.Version or 1

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, entry in pairs(value) do
		result[key] = copy(entry)
	end
	return result
end

local function studioApiUnavailable(message)
	if not RunService:IsStudio() then
		return false
	end
	if game.GameId == 0 then
		return true
	end
	local text = string.lower(tostring(message))
	return string.find(text, "studioaccesstoapisnotallowed", 1, true) ~= nil
		or (string.find(text, "studio", 1, true) ~= nil
		and string.find(text, "api", 1, true) ~= nil
		and (string.find(text, "not allowed", 1, true) ~= nil
			or string.find(text, "not enabled", 1, true) ~= nil
			or string.find(text, "disabled", 1, true) ~= nil
			or string.find(text, "403", 1, true) ~= nil))
		or string.find(text, "must be published", 1, true) ~= nil
		or string.find(text, "placenotpublished", 1, true) ~= nil
end

function DataService.new(onStatus)
	local self = setmetatable({
		Sessions = {},
		OnStatus = onStatus,
		Stopping = false,
		Store = nil,
		StoreError = nil,
	}, DataService)
	local success, result = pcall(function()
		return DataStoreService:GetDataStore("EspressoCafeTycoon_Profiles_v1")
	end)
	if success then
		self.Store = result
	else
		self.StoreError = tostring(result)
	end
	task.spawn(function()
		while not self.Stopping do
			task.wait(2)
			local now = os.clock()
			for userId, session in pairs(self.Sessions) do
				if session.Profile and not session.Loading and not session.Closing and not session.Lost
					and not session.Saving and now - session.LastAttempt >= SAVE_INTERVAL then
					task.spawn(function()
						self:save(userId, false)
					end)
				end
			end
		end
	end)
	return self
end

function DataService:_status(session, status)
	session.Status = status
	if self.OnStatus then
		local success, failure = pcall(self.OnStatus, session.UserId, status)
		if not success then
			warn("[Espresso] Save-status callback failed: " .. tostring(failure))
		end
	end
end

function DataService:getStatus(userId)
	local session = self.Sessions[userId]
	return if session then session.Status else "Loading"
end

function DataService:isWritable(userId)
	local session = self.Sessions[userId]
	if not session or not session.Profile or session.Loading or session.Closing or session.Lost then
		return false
	end
	if session.Persistent and os.time() >= session.LeaseExpiresAt then
		if session.Status ~= "Save delayed" then
			self:_status(session, "Save delayed")
		end
		return false
	end
	return true
end

function DataService:markDirty(userId)
	local session = self.Sessions[userId]
	if session then
		session.Revision += 1
	end
end

function DataService:load(player)
	local userId = player.UserId
	if self.Stopping then
		return nil, "Server is closing. Please join another server."
	end
	local current = self.Sessions[userId]
	if current then
		if current.Loading then
			return nil, "Your café is still loading."
		end
		if current.Lost then
			return nil, "Your save session moved to another server. Please rejoin."
		end
		if current.Profile and not current.Closing then
			return current.Profile
		end
		if current.Closing then
			return nil, "Your previous café session is still closing. Please retry shortly."
		end
	end
	local session = {
		UserId = userId,
		Token = game.JobId .. ":" .. HttpService:GenerateGUID(false),
		Profile = nil,
		Loading = true,
		Closing = false,
		Saving = false,
		Persistent = false,
		Lost = false,
		Status = "Loading",
		Revision = 0,
		LastAttempt = os.clock(),
		LastSaved = os.clock(),
		LeaseExpiresAt = 0,
	}
	self.Sessions[userId] = session
	self:_status(session, "Loading")
	local failure = self.StoreError or "Data service is unavailable."
	local blockedReason = nil
	local result = nil
	-- Unpublished Studio files cannot use DataStores. Their progress is explicitly temporary.
	local sessionOnly = RunService:IsStudio() and game.GameId == 0
	if not sessionOnly and self.Store then
		for attempt = 1, MAX_ATTEMPTS do
			if session.Closing then
				break
			end
			blockedReason = nil
			local success, value = pcall(function()
				return self.Store:UpdateAsync("Player_" .. userId, function(old)
					blockedReason = nil
					local oldProfile = if type(old) == "table" and type(old.Profile) == "table" then old.Profile else old
					if type(old) == "table" and type(old.SchemaVersion) == "number" and old.SchemaVersion > SCHEMA_VERSION then
						blockedReason = "This save uses a newer game version. Please rejoin a newer server."
						return nil
					end
					if type(oldProfile) == "table" and type(oldProfile.Version) == "number"
						and oldProfile.Version > SCHEMA_VERSION then
						blockedReason = "This save uses a newer game version. Please rejoin a newer server."
						return nil
					end
					local lease = if type(old) == "table" then old.Session else nil
					if type(lease) == "table" and lease.Id ~= session.Token
						and type(lease.ExpiresAt) == "number" and lease.ExpiresAt > os.time() then
						blockedReason = "Your café is open in another server. Close that session and retry shortly."
						return nil
					end
					local profile = Economy.sanitize(oldProfile, os.time())
					return {
						SchemaVersion = SCHEMA_VERSION,
						Profile = profile,
						Session = {Id = session.Token, ExpiresAt = os.time() + LEASE_SECONDS},
					}
				end)
			end)
			if success and type(value) == "table" and type(value.Session) == "table"
				and value.Session.Id == session.Token and type(value.Profile) == "table" then
				result = value.Profile
				session.Persistent = true
				session.LeaseExpiresAt = value.Session.ExpiresAt
				break
			elseif blockedReason then
				failure = blockedReason
				break
			elseif not success then
				failure = tostring(value)
				if studioApiUnavailable(failure) then
					sessionOnly = true
					break
				end
			else
				failure = "Data service returned no profile. Please retry shortly."
			end
			if attempt < MAX_ATTEMPTS then
				task.wait(0.5 * (2 ^ (attempt - 1)) + math.random() * 0.2)
			end
		end
	elseif not sessionOnly and studioApiUnavailable(failure) then
		sessionOnly = true
	end
	if sessionOnly then
		result = Economy.newProfile(os.time())
		session.Persistent = false
	end
	session.Loading = false
	if not result then
		if self.Sessions[userId] == session then
			self.Sessions[userId] = nil
		end
		if not session.Closing then
			warn("[Espresso] Profile load refused for user " .. userId .. ": " .. tostring(failure))
		end
		-- Details stay in server logs; user-facing error never suggests a reset or overwrites data.
		return nil, blockedReason or "We couldn't safely load your café. Your saved progress was not changed. Retrying shortly."
	end
	session.Profile = result
	session.LastSaved = os.clock()
	session.LastAttempt = os.clock()
	self:_status(session, if session.Persistent then "Saved" else "Session only")
	if session.Closing or self.Stopping then
		self:save(userId, true)
		return nil, "Player left while the café was loading."
	end
	return result
end

function DataService:save(userId, release)
	local session = self.Sessions[userId]
	if not session then
		return false
	end
	if release then
		session.Closing = true
	end
	if session.Loading then
		-- load() checks Closing after the lease request returns and releases that exact token.
		return false
	end
	if session.Saving then
		if not release then
			return false
		end
		local deadline = os.clock() + 8
		while session.Saving and os.clock() < deadline do
			task.wait(0.05)
		end
		if session.Saving or self.Sessions[userId] ~= session then
			return false
		end
	end
	if not session.Profile or session.Lost then
		if release and self.Sessions[userId] == session then
			self.Sessions[userId] = nil
		end
		return false
	end
	session.Saving = true
	session.LastAttempt = os.clock()
	local snapshot = copy(session.Profile)
	snapshot.LastSeen = os.time()
	local revision = session.Revision
	if not session.Persistent then
		session.Profile.LastSeen = snapshot.LastSeen
		session.Saving = false
		self:_status(session, "Session only")
		if release and self.Sessions[userId] == session then
			self.Sessions[userId] = nil
		end
		return true
	end
	self:_status(session, "Saving")
	local saved = false
	local lost = false
	local failure = "Unknown save error"
	for attempt = 1, MAX_ATTEMPTS do
		lost = false
		local success, value = pcall(function()
			return self.Store:UpdateAsync("Player_" .. userId, function(old)
				local lease = if type(old) == "table" then old.Session else nil
				if type(lease) ~= "table" or lease.Id ~= session.Token then
					lost = true
					return nil
				end
				return {
					SchemaVersion = SCHEMA_VERSION,
					Profile = snapshot,
					Session = if release then nil else {Id = session.Token, ExpiresAt = os.time() + LEASE_SECONDS},
				}
			end)
		end)
		if success and not lost and type(value) == "table" and type(value.Profile) == "table" then
			saved = true
			if not release and type(value.Session) == "table" then
				session.LeaseExpiresAt = value.Session.ExpiresAt
			end
			break
		elseif lost then
			break
		else
			failure = tostring(value)
		end
		if attempt < MAX_ATTEMPTS then
			task.wait(0.5 * (2 ^ (attempt - 1)) + math.random() * 0.2)
		end
	end
	session.Saving = false
	if saved then
		session.Profile.LastSeen = snapshot.LastSeen
		session.LastSaved = os.clock()
		session.SavedRevision = revision
		self:_status(session, "Saved")
	elseif lost then
		session.Lost = true
		self:_status(session, "Session lost")
		warn("[Espresso] Profile lease lost for user " .. userId .. "; further progression has been blocked.")
	else
		self:_status(session, "Save failed")
		warn("[Espresso] Profile save failed for user " .. userId .. ": " .. failure)
		-- Retry failed saves sooner, without creating a hot request loop.
		session.LastAttempt = os.clock() - math.max(0, SAVE_INTERVAL - 12)
	end
	if release and self.Sessions[userId] == session then
		self.Sessions[userId] = nil
	end
	return saved
end

function DataService:release(userId)
	return self:save(userId, true)
end

function DataService:shutdown()
	if self.Stopping then
		return
	end
	self.Stopping = true
	local pending = 0
	for userId, session in pairs(self.Sessions) do
		session.Closing = true
		pending += 1
		task.spawn(function()
			self:release(userId)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while os.clock() < deadline do
		local loading = false
		for _, session in pairs(self.Sessions) do
			if session.Loading or session.Saving then
				loading = true
				break
			end
		end
		if pending == 0 and not loading then
			break
		end
		task.wait(0.1)
	end
end

return DataService
