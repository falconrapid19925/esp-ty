--!nonstrict
-- An allowlisted, geometry-only Creator Store loader. Third-party code never
-- enters Workspace. Models stay unparented until sanitized; LoadAssetAsync's
-- default sandbox remains intact. No require(assetId), HTTP execution, or
-- capabilities are granted to downloaded content.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetCatalog"))

local Assets = {}
local cache = {}
local statuses = {}
local started = false
local remaining = 0

local allowedClasses = {
	Model = true,
	Folder = true,
	Part = true,
	WedgePart = true,
	CornerWedgePart = true,
	MeshPart = true,
	UnionOperation = true,
	NegateOperation = true,
	TrussPart = true,
	Seat = true,
	VehicleSeat = true,
	SpecialMesh = true,
	BlockMesh = true,
	CylinderMesh = true,
	Decal = true,
	Texture = true,
	SurfaceAppearance = true,
}

local function finite(value)
	return value == value and value > -math.huge and value < math.huge
end

local function sanitize(candidate, key)
	if typeof(candidate) ~= "Instance" then
		return nil, "asset did not contain an Instance"
	end
	local model
	if candidate:IsA("Model") then
		model = candidate
	else
		model = Instance.new("Model")
		candidate.Parent = model
	end
	model.Parent = nil
	model.Name = key
	local descendants = model:GetDescendants()
	if #descendants > Catalog.MaxDescendants then
		model:Destroy()
		return nil, "asset exceeded descendant budget"
	end
	-- Some otherwise useful cup/furniture models wrap their mesh parts in a
	-- Tool or another interactive container. Preserve the visual geometry
	-- before removing that container; no interactions or scripts are retained.
	for _, descendant in ipairs(descendants) do
		if descendant:IsA("BasePart") and allowedClasses[descendant.ClassName] then
			descendant.Parent = model
		end
	end
	local parts = 0
	for _, descendant in ipairs(descendants) do
		-- Removing an interactive ancestor may already have destroyed this
		-- entry from the original traversal. Some runtimes reject all access
		-- to destroyed Instances, so skip such entries without aborting load.
		local exists, belongs = pcall(function()
			return descendant:IsDescendantOf(model)
		end)
		if exists and belongs then
			if not allowedClasses[descendant.ClassName] then
				-- This removes every LuaSourceContainer, PackageLink, remote,
				-- prompt, tool, humanoid, constraint, sound, and particle emitter.
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				parts += 1
				local size = descendant.Size
				local position = descendant.Position
				if parts > Catalog.MaxParts
					or not finite(size.X + size.Y + size.Z)
					or not finite(position.X + position.Y + position.Z)
					or math.max(size.X, size.Y, size.Z) > 500 then
					model:Destroy()
					return nil, "asset exceeded geometry budget"
				end
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.Massless = true
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
				if descendant:IsA("Seat") or descendant:IsA("VehicleSeat") then
					descendant.Disabled = true
				end
			end
		end
	end
	if parts == 0 then
		model:Destroy()
		return nil, "asset contained no allowed geometry"
	end
	local _, bounds = model:GetBoundingBox()
	if not finite(bounds.X + bounds.Y + bounds.Z)
		or math.max(bounds.X, bounds.Y, bounds.Z) > 1000 then
		model:Destroy()
		return nil, "asset bounds were invalid"
	end
	model:SetAttribute("AssetKey", key)
	return model
end

local function override(key)
	local folder = ServerStorage:FindFirstChild("AssetOverrides")
	local instance = folder and folder:FindFirstChild(key)
	if not instance then
		return nil
	end
	return sanitize(instance:Clone(), key)
end

local function load(key, entry)
	local localModel, localError = override(key)
	if localModel then
		cache[key] = localModel
		statuses[key] = "local override"
		return
	elseif localError then
		warn("[Assets] Ignored invalid local override " .. key .. ": " .. localError)
	end
	local permissionOk, allowed = pcall(function()
		return AssetService.AllowInsertFreeAssets
	end)
	if permissionOk and not allowed then
		statuses[key] = "third-party loading disabled"
		return
	end
	local ok, loaded = pcall(function()
		return AssetService:LoadAssetAsync(entry.Id)
	end)
	if not ok then
		statuses[key] = "load failed"
		warn("[Assets] " .. key .. " could not load; using fallback. " .. tostring(loaded))
		return
	end
	local sanitized, reason = sanitize(loaded, key)
	if not sanitized then
		statuses[key] = "rejected geometry"
		warn("[Assets] " .. key .. " rejected: " .. tostring(reason))
		return
	end
	-- Keep large modern asset IDs exact in serialized attribute formats too.
	sanitized:SetAttribute("SourceAssetId", tostring(entry.Id))
	cache[key] = sanitized
	statuses[key] = "creator store"
end

function Assets.preload(timeout)
	if not started then
		started = true
		for key, entry in pairs(Catalog.Models) do
			if entry.Preload then
				remaining += 1
				statuses[key] = "loading"
				task.spawn(function()
					local ok, failure = pcall(load, key, entry)
					if not ok then
						statuses[key] = "load failed"
						warn("[Assets] " .. key .. ": " .. tostring(failure))
					end
					remaining -= 1
				end)
			end
		end
	end
	local deadline = os.clock() + (timeout or Catalog.PreloadTimeout)
	while remaining > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
	local unavailable = {}
	for key, entry in pairs(Catalog.Models) do
		if entry.Preload and not cache[key] then
			table.insert(unavailable, key)
		end
	end
	if #unavailable > 0 then
		warn("[Assets] Using geometry fallbacks for " .. table.concat(unavailable, ", ")
			.. ". To use the selected free models, enable Allow Loading Third Party Assets in Studio Experience Settings"
			.. " or import models into ServerStorage.AssetOverrides. See docs/ASSET_RESEARCH.md.")
	end
	return Assets.getStatus()
end

function Assets.get(key)
	if type(key) ~= "string" then
		return nil
	end
	-- Local artist imports work even for optional keys such as cafe_chair.
	if not cache[key] then
		local model = override(key)
		if model then
			cache[key] = model
			statuses[key] = "local override"
		end
	end
	local model = cache[key]
	if not model then
		return nil
	end
	return model:Clone()
end

function Assets.getStatus()
	return table.clone(statuses)
end

function Assets.sounds()
	return Catalog.Sounds
end

return Assets
