--[[
    FPS BOOSTER + MENU
    - RightShift = show/hide menu
    - Drag the title bar to move it
    - Every toggle is reversible (originals are saved and restored)
    - "Potato Mode" = turns on everything (except AFK 3D-off)
    - "Reset All"   = turns everything off / restores
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

-- re-execute safe: clean up the old copy first
if env.__FPSBooster then
    pcall(env.__FPSBooster)
end

local Connections = {}
local function track(c)
    table.insert(Connections, c)
    return c
end

--------------------------------------------------------------------
-- FEATURE ENGINE
--------------------------------------------------------------------
local Features = {}
local FeatureMT = {}
FeatureMT.__index = FeatureMT

-- set a property and remember the original so it can be restored
function FeatureMT:Set(inst, prop, val)
    pcall(function()
        local current = inst[prop]
        if current == val then return end
        local s = self.Saved[inst]
        if not s then
            s = {}
            self.Saved[inst] = s
        end
        if s[prop] == nil then
            s[prop] = current
        end
        inst[prop] = val
    end)
end

function FeatureMT:Restore()
    for inst, props in pairs(self.Saved) do
        for prop, val in pairs(props) do
            pcall(function()
                inst[prop] = val
            end)
        end
    end
    self.Saved = setmetatable({}, { __mode = "k" })
end

-- returns a scan job (if the feature needs to scan the map)
function FeatureMT:SetState(on)
    if self.On == on then return nil end
    self.On = on
    self.Token = self.Token + 1

    if on then
        if self.Global then pcall(self.Global, self, true) end
        if self.Changed then self.Changed() end
        if self.Apply then
            return { f = self, token = self.Token }
        end
    else
        self:Restore()
        if self.Global then pcall(self.Global, self, false) end
        if self.Changed then self.Changed() end
    end
    return nil
end

-- scans the whole map ONCE for a list of jobs (chunked so it doesn't freeze)
local function scan(jobs)
    if #jobs == 0 then return end
    task.spawn(function()
        for _, root in ipairs({ Workspace, Lighting }) do
            local list = root:GetDescendants()
            for i = 1, #list do
                local inst = list[i]
                for _, job in ipairs(jobs) do
                    if job.f.Token == job.token then
                        pcall(job.f.Apply, job.f, inst)
                    end
                end
                if i % 300 == 0 then task.wait() end
            end
        end
    end)
end

function FeatureMT:Toggle(on)
    local job = self:SetState(on)
    if job then scan({ job }) end
end

local function Feature(name, desc, def)
    local f = def or {}
    f.Name = name
    f.Desc = desc
    f.On = false
    f.Token = 0
    f.Saved = setmetatable({}, { __mode = "k" })
    setmetatable(f, FeatureMT)
    table.insert(Features, f)
    return f
end

--------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------
local function isPart(i)
    return i:IsA("BasePart") and not i:IsA("Terrain")
end

local EFFECT_CLASSES = {
    ParticleEmitter = true,
    Trail = true,
    Beam = true,
    Fire = true,
    Smoke = true,
    Sparkles = true,
    Highlight = true,
}

--------------------------------------------------------------------
-- THE TOGGLES
--------------------------------------------------------------------
Feature("Lowest Quality Level", "Roblox graphics level -> 1", {
    Global = function(self, on)
        local r = settings().Rendering
        if on then
            self.old = r.QualityLevel
            r.QualityLevel = Enum.QualityLevel.Level01
        elseif self.old then
            r.QualityLevel = self.old
        end
    end,
})

Feature("Disable Shadows", "No shadows anywhere", {
    Global = function(self, on)
        if on then
            self:Set(Lighting, "GlobalShadows", false)
        end
    end,
    Apply = function(self, i)
        if isPart(i) then
            self:Set(i, "CastShadow", false)
        end
    end,
})

Feature("Smooth Plastic Everything", "All materials -> flat plastic", {
    Apply = function(self, i)
        if isPart(i) then
            self:Set(i, "Material", Enum.Material.SmoothPlastic)
            self:Set(i, "Reflectance", 0)
        end
    end,
})

Feature("Remove Textures & Decals", "Hides decals, textures, skins", {
    Apply = function(self, i)
        if i:IsA("Decal") then -- includes Texture
            self:Set(i, "Transparency", 1)
        elseif i:IsA("MeshPart") then
            self:Set(i, "TextureID", "")
        elseif i:IsA("SpecialMesh") then
            self:Set(i, "TextureId", "")
        elseif i:IsA("SurfaceAppearance") then
            self:Set(i, "ColorMap", "")
            self:Set(i, "NormalMap", "")
            self:Set(i, "MetalnessMap", "")
            self:Set(i, "RoughnessMap", "")
        end
    end,
})

Feature("Low Mesh Detail", "Meshes render at lowest fidelity", {
    Apply = function(self, i)
        if i:IsA("MeshPart") then
            self:Set(i, "RenderFidelity", Enum.RenderFidelity.Performance)
        end
    end,
})

Feature("Disable Particles & Effects", "Fire, smoke, trails, beams...", {
    Apply = function(self, i)
        if EFFECT_CLASSES[i.ClassName] then
            self:Set(i, "Enabled", false)
        elseif i:IsA("Explosion") then
            self:Set(i, "Visible", false)
        end
    end,
})

Feature("Disable Post-Processing", "Bloom, blur, sunrays, DoF...", {
    Apply = function(self, i)
        if i:IsA("PostEffect") then
            self:Set(i, "Enabled", false)
        end
    end,
})

Feature("Disable Atmosphere & Clouds", "Removes haze and clouds", {
    Apply = function(self, i)
        if i:IsA("Atmosphere") then
            self:Set(i, "Density", 0)
            self:Set(i, "Offset", 0)
            self:Set(i, "Glare", 0)
            self:Set(i, "Haze", 0)
        elseif i:IsA("Clouds") then
            self:Set(i, "Enabled", false)
        end
    end,
})

Feature("Disable Dynamic Lights", "Point/Spot/Surface lights off", {
    Apply = function(self, i)
        if i:IsA("Light") then
            self:Set(i, "Enabled", false)
        end
    end,
})

Feature("Flat Water & Terrain", "No waves/reflections, no grass", {
    Global = function(self, on)
        if not on then return end
        local t = Workspace:FindFirstChildOfClass("Terrain")
        if t then
            self:Set(t, "WaterWaveSize", 0)
            self:Set(t, "WaterWaveSpeed", 0)
            self:Set(t, "WaterReflectance", 0)
            self:Set(t, "Decoration", false)
        end
    end,
})

Feature("Unlock FPS Cap", "Uncaps FPS (needs executor support)", {
    Global = function(self, on)
        if setfpscap then
            setfpscap(on and 999 or 60)
        else
            warn("[FPS Booster] Your executor has no setfpscap")
        end
    end,
})

Feature("AFK Mode (3D Off)", "Stops 3D rendering = max FPS", {
    NoPotato = true,
    Global = function(self, on)
        RunService:Set3dRenderingEnabled(not on)
    end,
})

-- apply to stuff that spawns in while a toggle is on
local function onAdded(inst)
    for _, f in ipairs(Features) do
        if f.On and f.Apply then
            pcall(f.Apply, f, inst)
        end
    end
end
track(Workspace.DescendantAdded:Connect(onAdded))
track(Lighting.DescendantAdded:Connect(onAdded))

--------------------------------------------------------------------
-- UI
--------------------------------------------------------------------
local THEME = {
    bg = Color3.fromRGB(18, 18, 24),
    header = Color3.fromRGB(26, 26, 36),
    row = Color3.fromRGB(30, 30, 42),
    accent = Color3.fromRGB(120, 90, 255),
    off = Color3.fromRGB(70, 70, 88),
    text = Color3.fromRGB(240, 240, 250),
    sub = Color3.fromRGB(150, 150, 170),
    danger = Color3.fromRGB(200, 60, 70),
}

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do
        o[k] = v
    end
    o.Parent = parent
    return o
end

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = o
end

local gui = new("ScreenGui", {
    Name = "FPSBoosterMenu",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
}, nil)

local main = new("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(300, 420),
    Position = UDim2.new(0, 20, 0.5, -210),
    BackgroundColor3 = THEME.bg,
    BorderSizePixel = 0,
    Active = true,
}, gui)
corner(main, 12)
new("UIStroke", { Color = THEME.accent, Thickness = 1.2, Transparency = 0.4 }, main)

-- header
local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = THEME.header,
    BorderSizePixel = 0,
}, main)
corner(header, 12)

new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 0),
    Size = UDim2.new(0, 110, 1, 0),
    Text = "FPS BOOSTER",
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = THEME.text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local fpsLabel = new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 125, 0, 0),
    Size = UDim2.new(0, 80, 1, 0),
    Text = "-- FPS",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = THEME.accent,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local minBtn = new("TextButton", {
    Position = UDim2.new(1, -68, 0.5, -12),
    Size = UDim2.fromOffset(24, 24),
    BackgroundColor3 = THEME.off,
    Text = "-",
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = THEME.text,
    BorderSizePixel = 0,
}, header)
corner(minBtn, 6)

local closeBtn = new("TextButton", {
    Position = UDim2.new(1, -36, 0.5, -12),
    Size = UDim2.fromOffset(24, 24),
    BackgroundColor3 = THEME.danger,
    Text = "X",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = THEME.text,
    BorderSizePixel = 0,
}, header)
corner(closeBtn, 6)

-- body
local body = new("Frame", {
    Position = UDim2.new(0, 0, 0, 40),
    Size = UDim2.new(1, 0, 1, -40),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, main)

local list = new("ScrollingFrame", {
    Position = UDim2.new(0, 8, 0, 8),
    Size = UDim2.new(1, -16, 1, -58),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = THEME.accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, body)
new("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, list)
new("UIPadding", { PaddingRight = UDim.new(0, 6) }, list)

local function buildRow(f, order)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundColor3 = THEME.row,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, list)
    corner(row, 8)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 6),
        Size = UDim2.new(1, -70, 0, 18),
        Text = f.Name,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextColor3 = THEME.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 25),
        Size = UDim2.new(1, -70, 0, 16),
        Text = f.Desc,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextColor3 = THEME.sub,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)

    local pill = new("Frame", {
        Size = UDim2.fromOffset(40, 20),
        Position = UDim2.new(1, -50, 0.5, -10),
        BackgroundColor3 = THEME.off,
        BorderSizePixel = 0,
    }, row)
    corner(pill, 10)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromOffset(2, 2),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, pill)
    corner(knob, 8)

    local click = new("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = "",
        ZIndex = 2,
    }, row)

    f.Changed = function()
        local info = TweenInfo.new(0.15)
        TweenService:Create(pill, info, {
            BackgroundColor3 = f.On and THEME.accent or THEME.off,
        }):Play()
        TweenService:Create(knob, info, {
            Position = f.On and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2),
        }):Play()
    end

    click.MouseButton1Click:Connect(function()
        f:Toggle(not f.On)
    end)
end

for i, f in ipairs(Features) do
    buildRow(f, i)
end

-- footer buttons
local function footerButton(text, xScale, xOff, color, callback)
    local b = new("TextButton", {
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Color3.new(1, 1, 1),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Size = UDim2.new(0.5, -12, 0, 34),
        Position = UDim2.new(xScale, xOff, 1, -42),
    }, body)
    corner(b, 8)
    b.MouseButton1Click:Connect(callback)
end

footerButton("POTATO MODE", 0, 8, THEME.accent, function()
    local jobs = {}
    for _, f in ipairs(Features) do
        if not f.NoPotato then
            local job = f:SetState(true)
            if job then table.insert(jobs, job) end
        end
    end
    scan(jobs)
end)

footerButton("RESET ALL", 0.5, 4, THEME.off, function()
    for _, f in ipairs(Features) do
        f:SetState(false)
    end
end)

--------------------------------------------------------------------
-- DRAGGING / MINIMIZE / KEYBIND
--------------------------------------------------------------------
local dragging, dragStart, startPos
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

track(UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y
        )
    end
end))

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    main.Size = minimized and UDim2.fromOffset(300, 40) or UDim2.fromOffset(300, 420)
end)

track(UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
    end
end))

--------------------------------------------------------------------
-- FPS COUNTER
--------------------------------------------------------------------
local frames, last = 0, os.clock()
track(RunService.Heartbeat:Connect(function()
    frames = frames + 1
    local now = os.clock()
    if now - last >= 0.5 then
        fpsLabel.Text = math.floor(frames / (now - last) + 0.5) .. " FPS"
        frames = 0
        last = now
    end
end))

--------------------------------------------------------------------
-- CLEANUP + PARENTING
--------------------------------------------------------------------
local function Cleanup()
    for _, f in ipairs(Features) do
        pcall(f.SetState, f, false)
    end
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function() gui:Destroy() end)
    env.__FPSBooster = nil
end
env.__FPSBooster = Cleanup
closeBtn.MouseButton1Click:Connect(Cleanup)

local parented = false
if gethui then
    parented = pcall(function() gui.Parent = gethui() end) and gui.Parent ~= nil
end
if not parented then
    parented = pcall(function() gui.Parent = CoreGui end) and gui.Parent ~= nil
end
if not parented then
    gui.Parent = LP:WaitForChild("PlayerGui")
end

print("[FPS Booster] Loaded. RightShift = toggle menu.")
