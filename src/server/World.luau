-- The plaza is authored architecture; hero props use the free asset catalog first.
-- World objects never award money. All prompts call back into GameService.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Economy = require(ReplicatedStorage.Shared:WaitForChild("Economy"))
local AssetCatalog = require(ReplicatedStorage.Shared:WaitForChild("AssetCatalog"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local World = {}
World.__index = World

local CREAM = Color3.fromRGB(244, 236, 219)
local SAGE = Color3.fromRGB(100, 126, 107)
local WOOD = Color3.fromRGB(126, 84, 56)
local DARK = Color3.fromRGB(47, 43, 38)
local BRASS = Color3.fromRGB(186, 149, 86)
local STONE = Color3.fromRGB(190, 182, 164)
local WHITE = Color3.fromRGB(255, 250, 237)

local function rgb(value, fallback)
    if typeof(value) == "Color3" then
        return value
    end
    if type(value) == "table" and #value >= 3 then
        return Color3.fromRGB(value[1], value[2], value[3])
    end
    return fallback
end

local function folder(parent, name)
    local result = Instance.new("Folder")
    result.Name = name
    result.Parent = parent
    return result
end

local function part(parent, name, size, transform, color, material, transparency, collide)
    local result = Instance.new("Part")
    result.Name = name
    result.Size = size
    result.CFrame = transform
    result.Color = color or CREAM
    result.Material = material or Enum.Material.SmoothPlastic
    result.Transparency = transparency or 0
    result.Anchored = true
    result.CanCollide = collide ~= false
    result.CanTouch = false
    result.TopSurface = Enum.SurfaceType.Smooth
    result.BottomSurface = Enum.SurfaceType.Smooth
    result.CastShadow = result.Transparency < 0.6
    result.Parent = parent
    return result
end

local function cylinder(parent, name, diameter, height, transform, color, material)
    local result = part(parent, name, Vector3.new(height, diameter, diameter), transform * CFrame.Angles(0, 0, math.pi / 2), color, material)
    result.Shape = Enum.PartType.Cylinder
    return result
end

local function ball(parent, name, size, transform, color)
    local result = part(parent, name, size, transform, color, Enum.Material.SmoothPlastic, 0, false)
    result.Shape = Enum.PartType.Ball
    return result
end

local function billboard(parent, text, size, offset, textColor)
    local gui = Instance.new("BillboardGui")
    gui.Name = "Label"
    gui.Size = UDim2.fromOffset(size.X, size.Y)
    gui.StudsOffsetWorldSpace = offset or Vector3.new(0, 2, 0)
    gui.MaxDistance = 110
    gui.AlwaysOnTop = false
    gui.LightInfluence = 0
    gui.Parent = parent
    local label = Instance.new("TextLabel")
    label.Name = "Text"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundColor3 = CREAM
    label.BackgroundTransparency = 0.05
    label.TextColor3 = textColor or DARK
    label.Text = text
    label.Font = Enum.Font.GothamMedium
    label.TextScaled = true
    label.TextWrapped = true
    label.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = label
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 9)
    padding.PaddingRight = UDim.new(0, 9)
    padding.PaddingTop = UDim.new(0, 5)
    padding.PaddingBottom = UDim.new(0, 5)
    padding.Parent = label
    return gui, label
end

local function surfaceText(parent, text, color)
    local gui = Instance.new("SurfaceGui")
    gui.Name = "Sign"
    gui.Face = Enum.NormalId.Front
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = 40
    gui.LightInfluence = 0
    gui.Parent = parent
    local label = Instance.new("TextLabel")
    label.Name = "Text"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color or WHITE
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextWrapped = true
    label.Parent = gui
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.PaddingTop = UDim.new(0, 4)
    padding.PaddingBottom = UDim.new(0, 4)
    padding.Parent = label
    return label
end

local function prompt(parent, action, object, distance, callback)
    local result = Instance.new("ProximityPrompt")
    result.ActionText = action
    result.ObjectText = object
    result.MaxActivationDistance = distance or 10
    result.HoldDuration = 0.15
    result.RequiresLineOfSight = false
    result.KeyboardKeyCode = Enum.KeyCode.E
    result.GamepadKeyCode = Enum.KeyCode.ButtonX
    result.Parent = parent
    result.Triggered:Connect(callback)
    return result
end

local function accentOf(profile)
    for _, theme in ipairs(Config.Themes or {}) do
        if theme.Id == profile.Theme then
            return rgb(theme.Primary, SAGE), rgb(theme.Accent, BRASS)
        end
    end
    return SAGE, BRASS
end

local function level(profile, id)
    return math.max(0, tonumber((profile.Upgrades or {})[id]) or 0)
end

-- A sourced model's bounding box, rather than its original pivot/scale, determines placement.
local function placeAsset(parent, key, transform, footprint)
    local ok, model = pcall(Assets.get, key)
    if not ok or not model or not model:IsA("Model") then
        if model and typeof(model) == "Instance" then
            model:Destroy()
        end
        return nil
    end
    local success = pcall(function()
        local _, size = model:GetBoundingBox()
        if size.X < 0.01 or size.Y < 0.01 or size.Z < 0.01 then
            error("Empty asset")
        end
        local scale = math.min(footprint.X / size.X, footprint.Y / size.Y, footprint.Z / size.Z)
        model:ScaleTo(model:GetScale() * math.clamp(scale, 0.001, 100))
        local box, fittedSize = model:GetBoundingBox()
        local pivotOffset = model:GetPivot():ToObjectSpace(box)
        model:PivotTo(transform * CFrame.new(0, fittedSize.Y / 2, 0) * pivotOffset:Inverse())
        model.Name = "Sourced_" .. key
        model.Parent = parent
    end)
    if not success then
        model:Destroy()
        return nil
    end
    return model
end

local function fallbackPlant(parent, transform, scale)
    scale = scale or 1
    cylinder(parent, "TerracottaPot", 1.6 * scale, 1.4 * scale, transform * CFrame.new(0, 0.7 * scale, 0), Color3.fromRGB(175, 110, 81))
    part(parent, "Stem", Vector3.new(0.15, 1.8, 0.15) * scale, transform * CFrame.new(0, 1.9 * scale, 0), WOOD, Enum.Material.Wood, 0, false)
    for index = 1, 5 do
        local angle = index * math.pi * 0.4
        local cf = transform * CFrame.new(math.sin(angle) * 0.45 * scale, (2 + (index % 2) * 0.5) * scale, math.cos(angle) * 0.45 * scale) * CFrame.Angles(0.4, angle, 0.5)
        ball(parent, "Leaf", Vector3.new(0.6, 1.5, 0.28) * scale, cf, SAGE)
    end
end

local function makePlant(parent, transform, scale)
    scale = scale or 1
    if not placeAsset(parent, "plant", transform, Vector3.new(2.1, 3.5, 2.1) * scale) then
        fallbackPlant(parent, transform, scale)
    end
end

local function fallbackChair(parent, transform, color)
    part(parent, "ChairSeat", Vector3.new(2.6, 0.35, 2.5), transform * CFrame.new(0, 1.9, 0), color, Enum.Material.Wood)
    part(parent, "ChairBack", Vector3.new(2.6, 2.1, 0.32), transform * CFrame.new(0, 3, 1.05), color, Enum.Material.Wood)
    for _, x in ipairs({ -0.95, 0.95 }) do
        for _, z in ipairs({ -0.9, 0.9 }) do
            part(parent, "ChairLeg", Vector3.new(0.2, 1.9, 0.2), transform * CFrame.new(x, 0.95, z), DARK, Enum.Material.Metal)
        end
    end
end

local function makeTable(parent, transform, color)
    -- Catalog's cafe_table is a complete table-and-two-chairs set.
    local asset = placeAsset(parent, "cafe_table", transform, Vector3.new(8, 4.5, 8))
    if not asset then
        cylinder(parent, "RoundCafeTable", 4.8, 0.35, transform * CFrame.new(0, 3.05, 0), WOOD, Enum.Material.Wood)
        cylinder(parent, "TablePedestal", 0.45, 2.8, transform * CFrame.new(0, 1.5, 0), DARK, Enum.Material.Metal)
        cylinder(parent, "TableBase", 2.3, 0.2, transform * CFrame.new(0, 0.12, 0), DARK, Enum.Material.Metal)
        if not placeAsset(parent, "cafe_chair", transform * CFrame.new(0, 0, 4), Vector3.new(2.7, 4, 2.7)) then
            fallbackChair(parent, transform * CFrame.new(0, 0, 4), color)
        end
        if not placeAsset(parent, "cafe_chair", transform * CFrame.new(0, 0, -4) * CFrame.Angles(0, math.pi, 0), Vector3.new(2.7, 4, 2.7)) then
            fallbackChair(parent, transform * CFrame.new(0, 0, -4) * CFrame.Angles(0, math.pi, 0), color)
        end
        if not placeAsset(parent, "coffee_cup", transform * CFrame.new(0.7, 3.25, 0), Vector3.new(0.9, 0.9, 0.9)) then
            cylinder(parent, "TableCup", 0.5, 0.65, transform * CFrame.new(0.7, 3.5, 0), CREAM)
        end
    end
end

local function espressoFallback(parent, transform, machineLevel, accent)
    local width = 4.5 + math.min(machineLevel, 4) * 0.3
    part(parent, "EspressoMachineBody_Fallback", Vector3.new(width, 2.5, 2.2), transform * CFrame.new(0, 1.35, 0), DARK, Enum.Material.Metal)
    part(parent, "MachineFront", Vector3.new(width - 0.3, 1.6, 0.2), transform * CFrame.new(0, 1.4, -1.16), accent, Enum.Material.Metal)
    part(parent, "CupWarmingTray", Vector3.new(width + 0.25, 0.15, 2.45), transform * CFrame.new(0, 2.68, 0), STONE, Enum.Material.Metal)
    part(parent, "DripTray", Vector3.new(width + 0.2, 0.2, 1.5), transform * CFrame.new(0, 0.18, -0.6), Color3.fromRGB(140, 147, 145), Enum.Material.Metal)
    for _, x in ipairs({ -1.1, 1.1 }) do
        cylinder(parent, "ExtractionGroup", 0.6, 0.35, transform * CFrame.new(x, 1.05, -1.2), STONE, Enum.Material.Metal)
        cylinder(parent, "EspressoCup", 0.65, 0.6, transform * CFrame.new(x, 0.55, -1.15), WHITE)
        local gauge = part(parent, "PressureGauge", Vector3.new(0.55, 0.55, 0.08), transform * CFrame.new(x, 1.95, -1.28), WHITE, Enum.Material.SmoothPlastic)
        surfaceText(gauge, "•", DARK)
    end
    for index = 1, 3 do
        cylinder(parent, "WarmingCup", 0.55, 0.55, transform * CFrame.new(-1.1 + index * 0.65, 3, 0), CREAM)
    end
end

local function createFallbackPerson(parent, transform, shirt, skin)
    local model = Instance.new("Model")
    model.Name = "Guest"
    part(model, "Torso", Vector3.new(1.8, 2.2, 1), CFrame.new(0, 3.2, 0), shirt, nil, 0, false)
    ball(model, "Head", Vector3.new(1.35, 1.35, 1.35), CFrame.new(0, 5, 0), skin)
    part(model, "LeftLeg", Vector3.new(0.75, 2.1, 0.8), CFrame.new(-0.48, 1.1, 0), DARK, nil, 0, false)
    part(model, "RightLeg", Vector3.new(0.75, 2.1, 0.8), CFrame.new(0.48, 1.1, 0), DARK, nil, 0, false)
    part(model, "LeftArm", Vector3.new(0.6, 2.1, 0.8), CFrame.new(-1.25, 3.2, 0), skin, nil, 0, false)
    part(model, "RightArm", Vector3.new(0.6, 2.1, 0.8), CFrame.new(1.25, 3.2, 0), skin, nil, 0, false)
    local root = part(model, "HumanoidRootPart", Vector3.new(1, 1, 1), CFrame.new(0, 3, 0), DARK, nil, 1, false)
    model.PrimaryPart = root
    model:PivotTo(transform * CFrame.new(0, 3, 0))
    model.Parent = parent
    return model
end

local function makePerson(self, parent, transform, shirt, vip)
    local skin = vip and Color3.fromRGB(207, 158, 111) or Color3.fromRGB(222, 181, 145)
    if self._personTemplate then
        local model = self._personTemplate:Clone()
        model.Name = vip and "VIPGuest" or "Guest"
        for _, item in ipairs(model:GetDescendants()) do
            if item:IsA("BasePart") then
                item.Anchored = true
                item.CanCollide = false
                item.CanTouch = false
                if item.Name:find("Torso") then
                    item.Color = shirt
                elseif item.Name == "Head" or item.Name:find("Arm") or item.Name:find("Hand") then
                    item.Color = skin
                end
            end
        end
        local box, size = model:GetBoundingBox()
        local offset = model:GetPivot():ToObjectSpace(box)
        model:PivotTo(transform * CFrame.new(0, size.Y / 2 + 0.05, 0) * offset:Inverse())
        model.Parent = parent
        return model
    end
    return createFallbackPerson(parent, transform, shirt, skin)
end

local function tweenModel(model, destination, duration, onDone)
    local progress = Instance.new("CFrameValue")
    progress.Value = model:GetPivot()
    local connection = progress.Changed:Connect(function(value)
        if model.Parent then
            model:PivotTo(value)
        end
    end)
    local tween = TweenService:Create(progress, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Value = destination })
    tween.Completed:Once(function()
        connection:Disconnect()
        progress:Destroy()
        if onDone then
            onDone()
        end
    end)
    tween:Play()
    return tween
end

local function safeName(player)
    -- DisplayName comes from Roblox identity and contains no RichText parsing here.
    return player.DisplayName or player.Name
end

function World.build()
    local old = workspace:FindFirstChild("EspressoWorld")
    if old then
        old:Destroy()
    end
    local self = setmetatable({ _plots = {}, _byUser = {}, _handlers = {}, _personTemplate = nil }, World)
    self.Root = folder(workspace, "EspressoWorld")
    local environment = folder(self.Root, "Plaza")
    Lighting.ClockTime = 16.4
    Lighting.Brightness = 2.3
    Lighting.Ambient = Color3.fromRGB(134, 130, 119)
    Lighting.OutdoorAmbient = Color3.fromRGB(163, 159, 145)
    Lighting.EnvironmentDiffuseScale = 0.8
    Lighting.EnvironmentSpecularScale = 0.6
    Lighting.GlobalShadows = true
    local colorEffect = Lighting:FindFirstChild("EspressoColor") or Instance.new("ColorCorrectionEffect")
    colorEffect.Name = "EspressoColor"
    colorEffect.TintColor = Color3.fromRGB(255, 247, 231)
    colorEffect.Saturation = -0.05
    colorEffect.Contrast = 0.04
    colorEffect.Parent = Lighting
    local bloom = Lighting:FindFirstChild("EspressoBloom") or Instance.new("BloomEffect")
    bloom.Name = "EspressoBloom"
    bloom.Intensity = 0.12
    bloom.Size = 20
    bloom.Threshold = 1.8
    bloom.Parent = Lighting

    part(environment, "Ground", Vector3.new(230, 2, 290), CFrame.new(0, -1.2, 0), Color3.fromRGB(137, 153, 119), Enum.Material.Grass)
    part(environment, "PedestrianPromenade", Vector3.new(44, 0.4, 250), CFrame.new(0, -0.05, 0), STONE, Enum.Material.Limestone)
    for _, x in ipairs({ -22, 22 }) do
        part(environment, "StoneBorder", Vector3.new(0.5, 0.55, 250), CFrame.new(x, 0.05, 0), CREAM, Enum.Material.Marble)
    end
    -- Broad paving joints provide scale without thousands of decorative parts.
    for z = -120, 120, 12 do
        part(environment, "PavingJoint", Vector3.new(43.5, 0.015, 0.08), CFrame.new(0, 0.16, z), Color3.fromRGB(156, 151, 137), Enum.Material.SmoothPlastic, 0, false)
    end
    for _, z in ipairs({ -102, -32, 32, 102 }) do
        for _, x in ipairs({ -18, 18 }) do
            cylinder(environment, "Planter", 5.5, 1.5, CFrame.new(x, 0.75, z), CREAM, Enum.Material.Concrete)
            part(environment, "TreeTrunk", Vector3.new(0.75, 7, 0.75), CFrame.new(x, 4.6, z), WOOD, Enum.Material.Wood)
            ball(environment, "TreeCanopy", Vector3.new(7, 8, 7), CFrame.new(x, 10.5, z), Color3.fromRGB(110, 139, 98))
            ball(environment, "TreeCanopy", Vector3.new(5.4, 6, 5.5), CFrame.new(x + 1, 12.5, z), Color3.fromRGB(127, 153, 111))
        end
    end
    for _, z in ipairs({ -85, -45, 45, 85 }) do
        for _, x in ipairs({ -14, 14 }) do
            cylinder(environment, "StreetLamp", 0.25, 10, CFrame.new(x, 5, z), DARK, Enum.Material.Metal)
            local lamp = ball(environment, "LampGlobe", Vector3.new(1.8, 1.8, 1.8), CFrame.new(x, 10.4, z), Color3.fromRGB(255, 222, 164))
            lamp.Material = Enum.Material.Neon
            local light = Instance.new("PointLight")
            light.Color = lamp.Color
            light.Brightness = 1
            light.Range = 16
            light.Shadows = false
            light.Parent = lamp
        end
    end
    local welcome = part(environment, "WelcomeSign", Vector3.new(22, 7, 0.8), CFrame.new(0, 8, -121), SAGE, Enum.Material.Wood)
    surfaceText(welcome, "ESPRESSO\nTHE CAFÉ QUARTER", WHITE)
    part(environment, "SignPostLeft", Vector3.new(0.6, 5, 0.6), CFrame.new(-8, 2.5, -121), WOOD, Enum.Material.Wood)
    part(environment, "SignPostRight", Vector3.new(0.6, 5, 0.6), CFrame.new(8, 2.5, -121), WOOD, Enum.Material.Wood)
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "PlazaSpawn"
    spawn.Size = Vector3.new(8, 0.3, 8)
    spawn.CFrame = CFrame.new(0, 0.4, -110)
    spawn.Transparency = 1
    spawn.Anchored = true
    spawn.CanCollide = false
    spawn.Neutral = true
    spawn.Duration = 0
    spawn.Parent = environment

    for index = 1, math.min(Config.MaxPlots or 6, 6) do
        local side = index <= 3 and -1 or 1
        local row = (index - 1) % 3
        local cf = CFrame.new(side * 51, 0, (row - 1) * 63) * CFrame.Angles(0, side == -1 and -math.pi / 2 or math.pi / 2, 0)
        local plot = {
            Index = index,
            Transform = cf,
            Owner = nil,
            Root = folder(self.Root, "Cafe" .. tostring(index)),
            Revision = 0,
            OrderSerial = 0,
            Guest = nil,
            GuestTween = nil,
        }
        plot.Structure = folder(plot.Root, "Architecture")
        plot.Furniture = folder(plot.Root, "Furniture")
        plot.Customers = folder(plot.Root, "Guests")
        local p = plot.Structure
        part(p, "Foundation", Vector3.new(45, 0.8, 44), cf * CFrame.new(0, 0.15, 0), CREAM, Enum.Material.Concrete)
        part(p, "OakFloor", Vector3.new(42.8, 0.18, 41), cf * CFrame.new(0, 0.65, 0), Color3.fromRGB(160, 124, 88), Enum.Material.WoodPlanks)
        part(p, "BackWall", Vector3.new(44, 15, 0.8), cf * CFrame.new(0, 8.1, 21), CREAM, Enum.Material.Plaster)
        for _, x in ipairs({ -21.5, 21.5 }) do
            part(p, "SideWallBase", Vector3.new(0.7, 3.6, 42), cf * CFrame.new(x, 2.5, 0), CREAM, Enum.Material.Plaster)
            part(p, "SideWallTop", Vector3.new(0.7, 2.3, 42), cf * CFrame.new(x, 14, 0), CREAM, Enum.Material.Plaster)
            part(p, "SideGlass", Vector3.new(0.2, 8.4, 39), cf * CFrame.new(x, 8.2, 0), Color3.fromRGB(186, 211, 204), Enum.Material.Glass, 0.72, false)
            for _, z in ipairs({ -20, -7, 7, 20 }) do
                part(p, "WindowMullion", Vector3.new(0.9, 12, 0.4), cf * CFrame.new(x, 7.8, z), DARK, Enum.Material.Metal)
            end
        end
        for _, x in ipairs({ -15, 15 }) do
            part(p, "FrontWindowBase", Vector3.new(13.5, 2.6, 0.7), cf * CFrame.new(x, 2, -20.8), CREAM, Enum.Material.Plaster)
            part(p, "FrontGlass", Vector3.new(12.6, 7.8, 0.18), cf * CFrame.new(x, 7.2, -20.9), Color3.fromRGB(186, 211, 204), Enum.Material.Glass, 0.72, false)
            for _, edge in ipairs({ -6.5, 6.5 }) do
                part(p, "FrontFrame", Vector3.new(0.4, 10.6, 0.65), cf * CFrame.new(x + edge, 6.1, -20.8), DARK, Enum.Material.Metal)
            end
        end
        part(p, "RoofLeft", Vector3.new(6, 0.8, 44), cf * CFrame.new(-19.2, 15.7, 0), DARK, Enum.Material.Slate)
        part(p, "RoofRight", Vector3.new(6, 0.8, 44), cf * CFrame.new(19.2, 15.7, 0), DARK, Enum.Material.Slate)
        part(p, "RoofBack", Vector3.new(33, 0.8, 7), cf * CFrame.new(0, 15.7, 18.5), DARK, Enum.Material.Slate)
        part(p, "Skylight", Vector3.new(32.5, 0.15, 34), cf * CFrame.new(0, 15.5, -1), Color3.fromRGB(180, 209, 206), Enum.Material.Glass, 0.82, false)
        plot.Fascia = part(p, "CafeFascia", Vector3.new(45, 3.5, 1.2), cf * CFrame.new(0, 13.2, -21), SAGE, Enum.Material.Wood)
        plot.Sign = surfaceText(plot.Fascia, "ESPRESSO  /  CAFÉ " .. tostring(index), WHITE)
        part(p, "Awning", Vector3.new(44, 0.3, 5), cf * CFrame.new(0, 11.3, -23) * CFrame.Angles(math.rad(-6), 0, 0), CREAM, Enum.Material.Fabric)
        part(p, "Terrace", Vector3.new(43, 0.25, 8), cf * CFrame.new(0, 0.23, -25), STONE, Enum.Material.Limestone)
        local ownerAnchor = part(p, "OwnerSign", Vector3.new(8, 4, 0.45), cf * CFrame.new(-15, 3, -25), DARK, Enum.Material.Wood)
        plot.OwnerLabel = surfaceText(ownerAnchor, "CAFÉ AVAILABLE\nA new story starts here", WHITE)
        for _, x in ipairs({ -10, 10 }) do
            local fixture = part(p, "Pendant", Vector3.new(2, 0.65, 2), cf * CFrame.new(x, 12.8, 1), BRASS, Enum.Material.Metal)
            part(p, "PendantCable", Vector3.new(0.07, 2.2, 0.07), cf * CFrame.new(x, 14.1, 1), DARK, Enum.Material.Metal, 0, false)
            local light = Instance.new("PointLight")
            light.Color = Color3.fromRGB(255, 222, 175)
            light.Range = 20
            light.Brightness = 0.8
            light.Parent = fixture
        end
        local board = part(p, "MenuBoard", Vector3.new(18, 5.5, 0.25), cf * CFrame.new(5, 9, 20.4), DARK, Enum.Material.Wood)
        plot.MenuLabel = surfaceText(board, "FRESHLY PULLED\nESPRESSO  /  MADE WITH CARE", CREAM)
        self._plots[index] = plot
        self:_refreshFurniture(plot, Economy.newProfile(os.time()))
    end

    -- Roblox-provided avatar generation is preferred over handmade character art.
    -- It runs independently of boot and is optional if platform access is unavailable.
    task.spawn(function()
        local description = Instance.new("HumanoidDescription")
        description.HeadColor = Color3.fromRGB(222, 181, 145)
        description.LeftArmColor = description.HeadColor
        description.RightArmColor = description.HeadColor
        description.TorsoColor = SAGE
        description.LeftLegColor = DARK
        description.RightLegColor = DARK
        description.HeightScale = 0.9
        description.WidthScale = 0.9
        description.DepthScale = 0.9
        local ok, model = pcall(function()
            return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
        end)
        description:Destroy()
        if ok and model then
            for _, item in ipairs(model:GetDescendants()) do
                if item:IsA("LuaSourceContainer") then
                    item:Destroy()
                elseif item:IsA("BasePart") then
                    item.Anchored = true
                    item.CanCollide = false
                    item.CanTouch = false
                elseif item:IsA("Humanoid") then
                    item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                    item.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
                end
            end
            if self.Root.Parent then
                self._personTemplate = model
                model.Parent = nil
            else
                model:Destroy()
            end
        end
    end)
    return self
end

function World:_refreshFurniture(plot, profile)
    plot.Revision += 1
    plot.Furniture:ClearAllChildren()
    local p = plot.Furniture
    local cf = plot.Transform
    local primary, accent = accentOf(profile)
    local machineLevel = level(profile, "machine")
    local seating = level(profile, "seating")
    local staff = level(profile, "staff")
    local decor = level(profile, "decor")
    local bakery = level(profile, "bakery")
    local expansion = level(profile, "expansion")
    plot.Fascia.Color = primary

    part(p, "CounterBase", Vector3.new(34, 3.8, 4), cf * CFrame.new(-1, 2.6, 8), primary, Enum.Material.Wood)
    part(p, "StoneCountertop", Vector3.new(35, 0.4, 4.5), cf * CFrame.new(-1, 4.7, 8), CREAM, Enum.Material.Marble)
    for x = -16, 14, 2 do
        part(p, "CounterFluting", Vector3.new(0.16, 3.1, 0.18), cf * CFrame.new(x, 2.6, 5.95), accent, Enum.Material.Wood, 0, false)
    end
    part(p, "BackWorktop", Vector3.new(34, 3.6, 2.6), cf * CFrame.new(-1, 2.5, 17.5), WOOD, Enum.Material.Wood)
    part(p, "BackWorktopStone", Vector3.new(34.5, 0.35, 3), cf * CFrame.new(-1, 4.45, 17.5), CREAM, Enum.Material.Marble)
    if not placeAsset(p, "espresso_machine", cf * CFrame.new(-8, 4.92, 8), Vector3.new(6.5, 4.2, 3.8)) then
        espressoFallback(p, cf * CFrame.new(-8, 4.92, 8), machineLevel, accent)
    end
    if machineLevel > 0 then
        local plate = part(p, "MachineTier", Vector3.new(3.6, 0.8, 0.1), cf * CFrame.new(-8, 5.5, 5.65), accent, Enum.Material.Metal, 0, false)
        surfaceText(plate, "PRECISION / MK " .. tostring(machineLevel + 1), DARK)
    end
    local brewAnchor = part(p, "BrewInteraction", Vector3.new(6, 1.5, 3), cf * CFrame.new(-8, 5.5, 5.8), primary, nil, 1, false)
    plot.BrewPrompt = prompt(brewAnchor, "Pull espresso", "Your espresso station", 10, function(player)
        if plot.Owner == player and self._handlers.Brew then
            self._handlers.Brew(player)
        end
    end)
    local steamAnchor = Instance.new("Attachment")
    steamAnchor.Name = "Steam"
    steamAnchor.Position = Vector3.new(0, 1.8, 0)
    steamAnchor.Parent = brewAnchor
    local steam = Instance.new("ParticleEmitter")
    steam.Name = "BrewSteam"
    steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
    steam.Enabled = plot.Brewing == true
    steam.Rate = 7
    steam.Lifetime = NumberRange.new(0.6, 1.2)
    steam.Speed = NumberRange.new(0.6, 1)
    steam.Acceleration = Vector3.new(0, 0.6, 0)
    steam.SpreadAngle = Vector2.new(10, 10)
    steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.7) })
    steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1) })
    steam.Color = ColorSequence.new(CREAM)
    steam.LightEmission = 0.3
    steam.Parent = steamAnchor
    plot.Steam = steam
    local brewSound = AssetCatalog.Sounds and AssetCatalog.Sounds.Brew
    if brewSound and brewSound.Id then
        local sound = Instance.new("Sound")
        sound.Name = "CoffeeBrewing"
        sound.SoundId = "rbxassetid://" .. tostring(brewSound.Id)
        sound.Volume = 0.18
        sound.Looped = true
        sound.RollOffMinDistance = 4
        sound.RollOffMaxDistance = 30
        sound.Parent = brewAnchor
        plot.BrewSound = sound
        if plot.Brewing then
            sound:Play()
        end
    else
        plot.BrewSound = nil
    end
    -- Bean jars make bean-quality purchases legible without an opaque multiplier wall.
    for index = 1, math.min(1 + level(profile, "beans"), 6) do
        local x = -14 + index * 2.2
        cylinder(p, "BeanCanister", 1.25, 1.8, cf * CFrame.new(x, 5.5, 17.5), Color3.fromRGB(102, 72, 47), Enum.Material.Glass)
        cylinder(p, "CanisterLid", 1.35, 0.15, cf * CFrame.new(x, 6.45, 17.5), accent, Enum.Material.Metal)
    end
    local recipes = Economy.unlockedRecipes(profile)
    local names = {}
    for _, recipe in ipairs(recipes) do
        table.insert(names, recipe.Name:upper())
    end
    plot.MenuLabel.Text = "TODAY'S MENU\n" .. table.concat(names, "  ·  ")

    makeTable(p, cf * CFrame.new(-13, 0.75, -9), primary)
    if seating >= 1 then
        makeTable(p, cf * CFrame.new(12, 0.75, -9), primary)
    end
    if seating >= 2 then
        makeTable(p, cf * CFrame.new(13, 0.75, 0), primary)
    end
    if seating >= 3 then
        makeTable(p, cf * CFrame.new(-13, 0.75, 0), primary)
    end
    if seating >= 4 or expansion >= 1 then
        makeTable(p, cf * CFrame.new(13, 0.36, -25), primary)
    end
    if expansion >= 2 then
        makeTable(p, cf * CFrame.new(-6, 0.36, -25), primary)
    end
    if seating >= 5 and expansion < 2 then
        makeTable(p, cf * CFrame.new(-6, 0.36, -25), primary)
    end
    if expansion >= 1 then
        for _, x in ipairs({ -21, 21 }) do
            part(p, "TerraceRailing", Vector3.new(0.3, 2.8, 7), cf * CFrame.new(x, 2, -25), primary, Enum.Material.Wood)
            makePlant(p, cf * CFrame.new(x * 0.9, 0.36, -27), 0.8)
        end
        part(p, "TerraceRunner", Vector3.new(12, 0.04, 6.5), cf * CFrame.new(7.5, 0.42, -25), primary, Enum.Material.Fabric, 0, false)
    end
    if expansion >= 2 then
        local canopy = part(p, "TerracePergola", Vector3.new(43, 0.2, 7), cf * CFrame.new(0, 10.7, -25), CREAM, Enum.Material.Fabric, 0.15, false)
        for _, x in ipairs({ -20, 20 }) do
            part(p, "PergolaPost", Vector3.new(0.25, 10.3, 0.25), cf * CFrame.new(x, 5.6, -28), accent, Enum.Material.Metal)
        end
        canopy:SetAttribute("Upgrade", "expansion")
    end
    makePlant(p, cf * CFrame.new(-18.5, 0.75, -17), 1)
    makePlant(p, cf * CFrame.new(18.5, 0.75, -17), 1)
    for index = 1, decor do
        local frame = part(p, "CoffeeArtFrame", Vector3.new(3, 3.8, 0.2), cf * CFrame.new(-16 + (index - 1) * 4, 9, 20.4), accent, Enum.Material.Wood)
        surfaceText(frame, ({ "BREW\nSLOW", "GOOD\nDAYS", "COFFEE\nFIRST", "STAY\nAWHILE", "FRESH\nDAILY" })[(index - 1) % 5 + 1], CREAM)
    end
    if decor >= 2 then
        makePlant(p, cf * CFrame.new(18, 0.75, 17), 1.4)
    end
    if bakery >= 1 then
        part(p, "PastryDisplay", Vector3.new(6, 1.8, 3), cf * CFrame.new(10, 5.8, 8), Color3.fromRGB(214, 231, 220), Enum.Material.Glass, 0.65, false)
        part(p, "PastryTray", Vector3.new(5.7, 0.18, 2.8), cf * CFrame.new(10, 4.98, 8), WOOD, Enum.Material.Wood)
        for index = 1, 3 + bakery do
            local x = 8 + ((index - 1) % 3) * 1.7
            local z = 7.3 + math.floor((index - 1) / 3) * 1.3
            if not placeAsset(p, "pastry", cf * CFrame.new(x, 5.1, z), Vector3.new(1.3, 0.85, 1.05)) then
                ball(p, "FreshPastry", Vector3.new(1.2, 0.7, 0.8), cf * CFrame.new(x, 5.4, z), Color3.fromRGB(205, 151, 78))
            end
        end
    end
    for index = 1, staff do
        local worker = makePerson(self, p, cf * CFrame.new(4 + (index - 1) * 4, 0.75, 12), primary, false)
        worker.Name = "Barista" .. tostring(index)
        local head = worker:FindFirstChild("Head", true) or worker.PrimaryPart
        if head then
            billboard(head, "BARISTA", Vector2.new(95, 22), Vector3.new(0, 1.5, 0), primary)
        end
    end

    -- Upgrade interaction points are deliberately small and sit beside the register.
    -- The full catalog remains available in the management UI.
    for index, upgrade in ipairs({ "machine", "menu", "staff" }) do
        local cost = Economy.upgradeCost(profile, upgrade)
        local pad = part(p, "Upgrade_" .. upgrade, Vector3.new(2.8, 0.16, 2.1), cf * CFrame.new(-1 + (index - 1) * 4, 4.98, 8), accent, Enum.Material.Metal, 0, false)
        local label = upgrade == "machine" and "Machine" or (upgrade == "menu" and "Menu" or "Barista")
        prompt(pad, cost and ("Upgrade · " .. Economy.formatMoney(cost)) or "Fully upgraded", label, 8, function(player)
            if plot.Owner == player and self._handlers.BuyUpgrade then
                self._handlers.BuyUpgrade(player, upgrade)
            end
        end)
    end
end

function World:setHandlers(handlers)
    self._handlers = handlers or {}
end

function World:assignPlot(player)
    local existing = self._byUser[player.UserId]
    if existing then
        return existing.Index
    end
    for _, plot in ipairs(self._plots) do
        if not plot.Owner then
            plot.Owner = player
            self._byUser[player.UserId] = plot
            plot.OwnerLabel.Text = safeName(player) .. "'S CAFÉ\nFreshly brewed, always"
            plot.Sign.Text = "ESPRESSO  /  " .. safeName(player):upper()
            return plot.Index
        end
    end
    return nil
end

function World:releasePlot(player)
    local plot = self._byUser[player.UserId]
    if not plot then
        return
    end
    self._byUser[player.UserId] = nil
    plot.Owner = nil
    plot.OrderSerial += 1
    if plot.GuestTween then
        plot.GuestTween:Cancel()
        plot.GuestTween = nil
    end
    plot.Customers:ClearAllChildren()
    plot.Guest = nil
    plot.Brewing = false
    plot.Sign.Text = "ESPRESSO  /  CAFÉ " .. tostring(plot.Index)
    plot.OwnerLabel.Text = "CAFÉ AVAILABLE\nA new story starts here"
    self:_refreshFurniture(plot, Economy.newProfile(os.time()))
end

function World:refreshPlot(player, profile)
    local plot = self._byUser[player.UserId]
    if plot then
        self:_refreshFurniture(plot, profile)
    end
end

function World:spawnPlayer(player)
    local plot = self._byUser[player.UserId]
    local character = player.Character
    if not plot or not character then
        return
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then
        root = character:WaitForChild("HumanoidRootPart", 8)
    end
    if root and character.Parent and plot.Owner == player then
        character:PivotTo(plot.Transform * CFrame.new(0, 4.5, -16))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

function World:showOrder(player, recipe, vip)
    local plot = self._byUser[player.UserId]
    if not plot or not recipe then
        return
    end
    plot.OrderSerial += 1
    local serial = plot.OrderSerial
    if plot.GuestTween then
        plot.GuestTween:Cancel()
        plot.GuestTween = nil
    end
    if plot.Guest then
        plot.Guest:Destroy()
    end
    local start = plot.Transform * CFrame.new(0, 0.75, -18) * CFrame.Angles(0, math.pi, 0)
    local shirt = vip and BRASS or ({ SAGE, Color3.fromRGB(174, 116, 92), Color3.fromRGB(98, 114, 139), Color3.fromRGB(148, 120, 148) })[math.random(1, 4)]
    local guest = makePerson(self, plot.Customers, start, shirt, vip)
    plot.Guest = guest
    local head = guest:FindFirstChild("Head", true) or guest.PrimaryPart
    if head then
        billboard(head, (vip and "VIP · " or "") .. recipe.Name, Vector2.new(165, 38), Vector3.new(0, 2, 0), vip and Color3.fromRGB(131, 91, 24) or DARK)
    end
    local from = guest:GetPivot()
    local destination = from + plot.Transform:VectorToWorldSpace(Vector3.new(0, 0, 20))
    plot.GuestTween = tweenModel(guest, destination, 2.2, function()
        if plot.OrderSerial == serial then
            plot.GuestTween = nil
        end
    end)
end

function World:serveCustomer(player, recipe, amount, perfect)
    local plot = self._byUser[player.UserId]
    if not plot then
        return
    end
    local guest = plot.Guest
    -- Automated sales can arrive without replacing the manually served guest.
    -- Only animate a departure if an active manual brew has just been cleared.
    if guest and plot.Brewing then
        plot.OrderSerial += 1
        if plot.GuestTween then
            plot.GuestTween:Cancel()
            plot.GuestTween = nil
        end
        plot.Guest = nil
        for _, gui in ipairs(guest:GetDescendants()) do
            if gui:IsA("BillboardGui") then
                gui:Destroy()
            end
        end
        local from = guest:GetPivot()
        local exit = from - plot.Transform:VectorToWorldSpace(Vector3.new(0, 0, 22))
        tweenModel(guest, exit * CFrame.Angles(0, math.pi, 0), 2.1, function()
            guest:Destroy()
        end)
        Debris:AddItem(guest, 3)
    end
    local anchor = part(plot.Customers, "SaleFeedback", Vector3.new(0.2, 0.2, 0.2), plot.Transform * CFrame.new(0, 7, 6), CREAM, nil, 1, false)
    local gui, label = billboard(anchor, (perfect and "PERFECT SHOT  " or "") .. "+" .. Economy.formatMoney(amount), Vector2.new(perfect and 230 or 130, 36), Vector3.zero, SAGE)
    TweenService:Create(gui, TweenInfo.new(1.5, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = Vector3.new(0, 2, 0) }):Play()
    task.delay(0.8, function()
        if label.Parent then
            TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
        end
    end)
    Debris:AddItem(anchor, 1.6)
end

function World:setBrew(player, active)
    local plot = self._byUser[player.UserId]
    if not plot then
        return
    end
    plot.Brewing = active == true
    if plot.Steam and plot.Steam.Parent then
        plot.Steam.Enabled = plot.Brewing
    end
    if plot.BrewSound and plot.BrewSound.Parent then
        if plot.Brewing then
            plot.BrewSound:Play()
        else
            plot.BrewSound:Stop()
        end
    end
    if plot.BrewPrompt and plot.BrewPrompt.Parent then
        plot.BrewPrompt.ActionText = plot.Brewing and "Serve your shot" or "Pull espresso"
    end
end

return World
