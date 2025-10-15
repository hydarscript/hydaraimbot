-- =========================
-- Fluent UI (clean + fixed)
-- =========================

-- Libraries
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Window
local Window = Fluent:CreateWindow({
    Title = "DADDY HYDAR",
    SubTitle = "by discord.gg/nUjVcV8R9j",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.LeftControl
})

-- Tabs
local Tabs = {
    Main = Window:AddTab({ Title = "PvP", Icon = "swords" }),
    Main2 = Window:AddTab({ Title = "Others", Icon = "globe" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

-- speed starts --------------------------------------------------------------------------------------

-- MUST be a LocalScript (StarterPlayerScripts or StarterGui)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer
if not LP then return end -- safety

-- config/state
local DEFAULT_WALKSPEED = 16
local SPEED_MIN, SPEED_MAX = 0, 500
local SpeedEnabled = true
local TargetSpeed = 500
local CurrentSpeed = DEFAULT_WALKSPEED
local SPEED_EASE = 10               -- higher = snappier smoothing
local BOB_FREQ = 1.6                -- camera bob frequency (visual only)
local BOB_MIN, BOB_MAX = 0.12, 0.30 -- studs

-- compat helpers
local function clamp(v, a, b) return (v < a and a) or (v > b and b) or v end

-- humanoid helper (no Luau types; survives respawn)
local HumanoidRef = nil
local function GetHumanoid()
	if HumanoidRef and HumanoidRef.Parent and HumanoidRef.Health > 0 then
		return HumanoidRef
	end
	local char = LP.Character or LP.CharacterAdded:Wait()
	HumanoidRef = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
	return HumanoidRef
end

LP.CharacterAdded:Connect(function(char)
	HumanoidRef = char:WaitForChild("Humanoid")
	HumanoidRef.WalkSpeed = SpeedEnabled and TargetSpeed or DEFAULT_WALKSPEED
	HumanoidRef.CameraOffset = Vector3.new(0,0,0)
end)

-- === PvP (Main) tab controls ===
-- Use Dawid’s Fluent pattern: first arg is the control ID.
Tabs.Main:AddToggle("PvP_Speed_Toggle", {
	Title = "Speed",
	Default = true,
	Callback = function(on)
		SpeedEnabled = on
		local hum = GetHumanoid()
		if not hum then return end
		if on then
			hum.WalkSpeed = TargetSpeed     -- immediate apply on enable
		else
			hum.WalkSpeed = DEFAULT_WALKSPEED
			hum.CameraOffset = Vector3.new(0,0,0)
		end
	end
})

Tabs.Main:AddSlider("PvP_Speed_Slider", {
	Title = "Speed",
	Min = SPEED_MIN,
	Max = SPEED_MAX,
	Default = 100,
	Rounding = 0,
	Callback = function(value)
		local num = tonumber(value) or 0
		TargetSpeed = clamp(math.floor(num), SPEED_MIN, SPEED_MAX)
		local hum = GetHumanoid()
		if hum and SpeedEnabled then
			hum.WalkSpeed = TargetSpeed     -- immediate response when sliding
		end
	end
})

-- hover-smooth loop (grounded physics; camera-only bob)
local last = tick()
RunService.RenderStepped:Connect(function()
	local hum = GetHumanoid()
	if not hum then return end

	local now = tick()
	local dt = math.max(1/240, now - last)
	last = now

	-- ease WalkSpeed
	local desired = SpeedEnabled and TargetSpeed or DEFAULT_WALKSPEED
	CurrentSpeed = CurrentSpeed + (desired - CurrentSpeed) * clamp(SPEED_EASE * dt, 0, 1)
	hum.WalkSpeed = CurrentSpeed

	-- subtle visual bob only while moving & grounded
	if SpeedEnabled and hum.MoveDirection.Magnitude > 0.05 and hum.FloorMaterial ~= Enum.Material.Air then
		local t = (SPEED_MAX > 0) and (CurrentSpeed / SPEED_MAX) or 0
		local amp = BOB_MIN + (BOB_MAX - BOB_MIN) * t
		local y = math.sin(now * math.pi * 2 * BOB_FREQ) * amp
		hum.CameraOffset = Vector3.new(0, y, 0)
	else
		hum.CameraOffset = Vector3.new(0,0,0)
	end

	hum.PlatformStand = false -- keep normal physics
end)

-- speed end ---------------------------------------------------------------------------------------------

-- aimbot skill starts ----------------------------------------------------------------------------------

--// Global Options Table
getgenv().Options = getgenv().Options or {}
local Options = getgenv().Options

--// Aimbot Skill Toggle (in PvP tab)
Options.AimbotSkill = Tabs.Main:AddToggle("aimbot_skill", {
    Title = "Aimbot Skill",
    Default = false
})

--// Aimbot Skill State
local funAimEnabled = false
Options.AimbotSkill:OnChanged(function()
    funAimEnabled = Options.AimbotSkill.Value
    print("Aimbot Skill Enabled:", funAimEnabled)
end)

Options.AimbotSkill:SetValue(false)

--// Services & Variables
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local CurrentCamera = workspace.CurrentCamera

local PlayersAimbot = nil
local PlayersPosition = nil

--// Settings
getgenv().setting = {
    LockPlayers = false,
    LockPlayersBind = Enum.KeyCode.L,
    resetPlayersBind = Enum.KeyCode.P,
}

--// Get Closest Valid Player
local function getClosestPlayer()
    local closest = nil
    local shortest = math.huge

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Humanoid") then
            if player.Character.Humanoid.Health > 0 then
                -- Optional team check (e.g., don't target teammates if Marines)
                if LocalPlayer.Team and player.Team then
                    if LocalPlayer.Team.Name == "Marines" and player.Team.Name == "Marines" then
                        continue
                    end
                end

                local distance = (LocalPlayer.Character.HumanoidRootPart.Position - player.Character.HumanoidRootPart.Position).Magnitude
                if distance < shortest then
                    shortest = distance
                    closest = player
                end
            end
        end
    end

    return closest
end

--// Target Updating Loop
task.spawn(function()
    while task.wait(0.2) do
        if funAimEnabled and not getgenv().setting.LockPlayers then
            local target = getClosestPlayer()
            if target then
                PlayersAimbot = target.Name
                PlayersPosition = target.Character.HumanoidRootPart.Position
            end
        elseif not funAimEnabled then
            PlayersAimbot = nil
            PlayersPosition = nil
        end
    end
end)

--// Keybinds: Lock + Reset
game:GetService("UserInputService").InputBegan:Connect(function(io, processed)
    if processed then return end

    if io.KeyCode == getgenv().setting.LockPlayersBind then
        if funAimEnabled then
            getgenv().setting.LockPlayers = not getgenv().setting.LockPlayers
            print("Lock Players:", getgenv().setting.LockPlayers)
        end
    elseif io.KeyCode == getgenv().setting.resetPlayersBind then
        PlayersAimbot = nil
        PlayersPosition = nil
        print("Aimbot Target Reset")
    end
end)

--// Metatable Hook (Intercept FireServer for Silent Aimbot)
task.spawn(function()
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(...)
        local method = getnamecallmethod()
        local args = { ... }

        if funAimEnabled and tostring(method) == "FireServer" then
            if tostring(args[1]) == "RemoteEvent" then
                if tostring(args[2]) ~= "true" and tostring(args[2]) ~= "false" then
                    if PlayersAimbot and PlayersPosition then
                        args[2] = PlayersPosition
                        return old(unpack(args))
                    end
                end
            end
        end

        return old(...)
    end)
end)

--// Mouse Click Shoot Override
Mouse.Button1Down:Connect(function()
    if funAimEnabled then
        pcall(function()
            if PlayersAimbot and PlayersPosition then
                local target = Players:FindFirstChild(PlayersAimbot)
                if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                    local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
                    if tool and tool:FindFirstChild("RemoteFunctionShoot") then
                        local args = {
                            [1] = PlayersPosition,
                            [2] = target.Character.HumanoidRootPart
                        }
                        tool.RemoteFunctionShoot:InvokeServer(unpack(args))
                    end
                end
            end
        end)
    end
end)

-- aimbot skill end ---------------------------------------------------------------------------------

-- camlock starts ----------------------------------------------------------------------------------------

-- SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Ensure a shared Options table exists (used by your UI lib)
getgenv().Options = getgenv().Options or {}
local Options = getgenv().Options

-- VARIABLES
local camlockUIVisible = false
local camlockActive = false
local camlockConnection = nil
local camlockedTarget = nil
local savedPosition = UDim2.new(0.5, -100, 0.3, 0)

-- === GET NEAREST PLAYER (in view) ===
local function getPlayerInView()
    local closestPlayer, closestDot = nil, -1
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = plr.Character.HumanoidRootPart
            local dirToPlayer = (hrp.Position - Camera.CFrame.Position).Unit
            local dot = Camera.CFrame.LookVector:Dot(dirToPlayer)
            if dot > closestDot then
                closestDot = dot
                closestPlayer = plr
            end
        end
    end
    return closestPlayer
end

-- === START / STOP CAMLOCK ===
local function startCamlock()
    camlockedTarget = getPlayerInView()
    if not camlockedTarget then return end
    if camlockConnection then camlockConnection:Disconnect() end
    camlockConnection = RunService.RenderStepped:Connect(function()
        if camlockedTarget and camlockedTarget.Character and camlockedTarget.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = camlockedTarget.Character.HumanoidRootPart
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, hrp.Position)
        end
    end)
end

local function stopCamlock()
    if camlockConnection then
        camlockConnection:Disconnect()
        camlockConnection = nil
    end
    camlockedTarget = nil
end

-- === CREATE THE RAINBOW CAMLOCK BUTTON ===
local function createCamlockUI()
    if game.CoreGui:FindFirstChild("CamlockStatusUI") then return end

    local gui = Instance.new("ScreenGui")
    gui.Name = "CamlockStatusUI"
    gui.Parent = game:GetService("CoreGui")
    gui.ResetOnSpawn = false

    local button = Instance.new("TextButton")
    button.Name = "CamlockStatus"
    button.Size = UDim2.new(0, 200, 0, 50)
    button.Position = savedPosition
    button.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    button.BackgroundTransparency = 0.25
    button.Font = Enum.Font.GothamBold
    button.TextScaled = true
    button.Text = "Camlock OFF"
    button.TextColor3 = Color3.new(1, 1, 1)
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Parent = gui

    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 12)

    -- Draggable
    local dragging = false
    local dragInput, mousePos, framePos

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            mousePos = input.Position
            framePos = button.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    savedPosition = button.Position
                end
            end)
        end
    end)

    button.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - mousePos
            button.Position = UDim2.new(
                framePos.X.Scale,
                framePos.X.Offset + delta.X,
                framePos.Y.Scale,
                framePos.Y.Offset + delta.Y
            )
        end
    end)

    -- Rainbow text color
    local hue = 0
    RunService.RenderStepped:Connect(function()
        hue = (hue + 0.005) % 1
        if button then
            button.TextColor3 = Color3.fromHSV(hue, 1, 1)
        end
    end)

    -- Toggle camlock when clicked
    button.MouseButton1Click:Connect(function()
        camlockActive = not camlockActive
        button.Text = camlockActive and "Camlock ON" or "Camlock OFF"
        if camlockActive then
            startCamlock()
        else
            stopCamlock()
        end
    end)
end

-- === SHOW/HIDE THE CAMLOCK UI ===
local function toggleCamlockUI(show)
    local ui = game.CoreGui:FindFirstChild("CamlockStatusUI")
    if show then
        if not ui then
            createCamlockUI()
        end
    else
        if ui then
            ui:Destroy()
            stopCamlock()
            camlockActive = false
        end
    end
end

-- === ON CHARACTER RESPAWN ===
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if camlockActive then
        startCamlock()
    end
end)

-- === UI TOGGLE TO SHOW/HIDE CAMLOCK BUTTON (PvP tab) ===
task.spawn(function()
    -- wait until Tabs and method exist
    while not Tabs or not Tabs.Main or not Tabs.Main.AddToggle do
        task.wait(0.1)
    end

    -- store toggle in Options.camlock so .Value is valid
    Options.camlock = Tabs.Main:AddToggle("camlock", {
        Title = "Camlock",
        Default = false
    })

    Options.camlock:OnChanged(function()
        camlockUIVisible = Options.camlock.Value
        toggleCamlockUI(camlockUIVisible)
    end)

    -- initialize to OFF
    Options.camlock:SetValue(false)
end)

-- camlock end ----------------------------------------------------------------------------------------

-- jump start------------------------------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

-- Ensure shared Options table exists (used by your UI lib)
getgenv().Options = getgenv().Options or {}
local Options = getgenv().Options

-- VARS
local savedJumpPos = UDim2.new(0.5, -100, 0.4, 0)
local JUMP_POWER = 250

-- === PERFORM SINGLE JUMP ===
local function performJump()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local originalPower = humanoid.JumpPower
    humanoid.UseJumpPower = true
    humanoid.JumpPower = JUMP_POWER
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

    task.delay(0.4, function()
        if humanoid then
            humanoid.JumpPower = originalPower
        end
    end)
end

-- === CREATE RAINBOW "JUMP" BUTTON ===
local function createJumpUI()
    if CoreGui:FindFirstChild("JumpUI") then return end

    local gui = Instance.new("ScreenGui")
    gui.Name = "JumpUI"
    gui.Parent = CoreGui
    gui.ResetOnSpawn = false

    local button = Instance.new("TextButton")
    button.Name = "JumpButton"
    button.Size = UDim2.new(0, 160, 0, 48)
    button.Position = savedJumpPos
    button.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    button.BackgroundTransparency = 0.3
    button.Font = Enum.Font.GothamBold
    button.TextScaled = true
    button.Text = "Jump"
    button.TextColor3 = Color3.new(1, 1, 1)
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Parent = gui

    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 12)

    -- Draggable
    local dragging = false
    local dragInput, mousePos, framePos

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            mousePos = input.Position
            framePos = button.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    savedJumpPos = button.Position
                end
            end)
        end
    end)

    button.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - mousePos
            button.Position = UDim2.new(
                framePos.X.Scale,
                framePos.X.Offset + delta.X,
                framePos.Y.Scale,
                framePos.Y.Offset + delta.Y
            )
        end
    end)

    -- Rainbow Text Effect
    local hue = 0
    RunService.RenderStepped:Connect(function()
        hue = (hue + 0.005) % 1
        if button then
            button.TextColor3 = Color3.fromHSV(hue, 1, 1)
        end
    end)

    -- Click to jump
    button.MouseButton1Click:Connect(performJump)
end

-- === TOGGLE JUMP UI VISIBILITY ===
local function toggleJumpUI(show)
    local ui = CoreGui:FindFirstChild("JumpUI")
    if show then
        if not ui then
            createJumpUI()
        end
    else
        if ui then
            ui:Destroy()
        end
    end
end

-- === SAFE TOGGLE CREATION IN PvP TAB ===
task.spawn(function()
    -- Wait until Tabs & method exist
    while not Tabs or not Tabs.Main or not Tabs.Main.AddToggle do
        task.wait(0.1)
    end

    -- Store toggle into Options.hackerjump so .Value is valid
    Options.hackerjump = Tabs.Main:AddToggle("hackerjump", {
        Title = "Hacker Jump",
        Default = false
    })

    Options.hackerjump:OnChanged(function()
        local visible = Options.hackerjump.Value
        toggleJumpUI(visible)
    end)

    -- Initialize OFF
    Options.hackerjump:SetValue(false)
end)

-- jump start------------------------------------------------------------------------------------------

-- infinite energy start --------------------------------------------------------------------------

-- SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Ensure shared Options table exists for your UI lib
getgenv().Options = getgenv().Options or {}
local Options = getgenv().Options

-- STATE
_G.InfEnergy = false
local EnergyValue = 100000 -- fallback if we can't read initial

-- Helper: find Energy/Stamina value object (recursive)
local function findEnergyObj(char)
    if not char then return nil end
    local energy = char:FindFirstChild("Energy") 
        or char:FindFirstChild("Energy", true)
        or char:FindFirstChild("Stamina")
        or char:FindFirstChild("Stamina", true)
    return energy
end

-- Loop to keep energy topped up
local function LoopEnergy()
    while task.wait(0.2) do
        if _G.InfEnergy then
            local char = LocalPlayer.Character
            if char then
                local energy = findEnergyObj(char)
                if energy and energy.Value ~= nil then
                    if not EnergyValue or EnergyValue <= 0 then
                        EnergyValue = energy.Value > 0 and energy.Value or 100000
                    end
                    -- Keep it replenished
                    energy.Value = EnergyValue
                end
            end
        end
    end
end

task.spawn(LoopEnergy)

-- Refresh cached value on respawn
Players.LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1)
    local energy = findEnergyObj(char)
    if energy and energy.Value ~= nil then
        EnergyValue = (energy.Value > 0 and energy.Value) or EnergyValue
    end
end)

-- === UI TOGGLE (PvP tab) ===
task.spawn(function()
    -- Wait for Tabs to be ready (same pattern as your Hacker Jump)
    while not Tabs or not Tabs.Main or not Tabs.Main.AddToggle do
        task.wait(0.1)
    end

    -- Store in Options.infenergy so .Value works
    Options.infenergy = Tabs.Main:AddToggle("infenergy", {
        Title = "Infinite Energy",
        Default = false
    })

    Options.infenergy:OnChanged(function()
        _G.InfEnergy = Options.infenergy.Value
        print("Infinite Energy:", _G.InfEnergy)
    end)

    Options.infenergy:SetValue(false)
end)

-- infinite energy end ---------------------------------------------------------------------------

-- anti stun starts ---------------------------------------------------------------------------

-- SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Ensure shared Options for your UI lib
getgenv().Options = getgenv().Options or {}
local Options = getgenv().Options

-- VARS
local AntiStunActive = false
local AntiStunConnection = nil
local lastSafeCFrame = nil
local ESCAPE_DISTANCE = 20 -- how far to dash away
local DASH_SPEED = 100     -- BodyVelocity impulse

-- === ESCAPE FUNCTION ===
local function escapeStun()
    local character = LocalPlayer.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp then return end

    -- Unanchor if needed
    if hrp.Anchored then
        hrp.Anchored = false
    end

    -- Cancel seated/ragdoll-ish states
    humanoid.Sit = false
    if humanoid:GetState() == Enum.HumanoidStateType.PlatformStanding then
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    end

    -- Jump
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

    -- Dash impulse opposite to camera
    local backDir = -Camera.CFrame.LookVector
    local vel = Instance.new("BodyVelocity")
    vel.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    vel.Velocity = backDir * DASH_SPEED + Vector3.new(0, 25, 0) -- add a little lift
    vel.Parent = hrp
    Debris:AddItem(vel, 0.2)

    -- Small reposition (optional)
    local newCFrame = hrp.CFrame + (backDir * ESCAPE_DISTANCE) + Vector3.new(0, 5, 0)
    hrp.CFrame = newCFrame
end

-- === START ANTI-STUN MONITOR ===
local function startAntiStun()
    if AntiStunConnection then return end
    AntiStunConnection = RunService.Heartbeat:Connect(function()
        local character = LocalPlayer.Character
        if not character then return end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not hrp then return end

        -- Save safe position
        local state = humanoid:GetState()
        if state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Freefall then
            lastSafeCFrame = hrp.CFrame
        end

        -- STUN DETECTION
        local stunned =
            hrp.Anchored or
            state == Enum.HumanoidStateType.PlatformStanding or
            state == Enum.HumanoidStateType.Seated or
            state == Enum.HumanoidStateType.Ragdoll or
            state == Enum.HumanoidStateType.Physics

        if stunned then
            escapeStun()
        end
    end)
end

-- === STOP ANTI-STUN ===
local function stopAntiStun()
    if AntiStunConnection then
        AntiStunConnection:Disconnect()
        AntiStunConnection = nil
    end
end

-- Reapply on respawn if still enabled
LocalPlayer.CharacterAdded:Connect(function()
    if AntiStunActive then
        task.wait(0.5)
        startAntiStun()
    end
end)

-- === UI TOGGLE (PvP tab) ===
task.spawn(function()
    while not Tabs or not Tabs.Main or not Tabs.Main.AddToggle do
        task.wait(0.1)
    end

    -- Store toggle in Options.antistun so .Value is valid
    Options.antistun = Tabs.Main:AddToggle("antistun", {
        Title = "Anti Stun",
        Default = false
    })

    Options.antistun:OnChanged(function()
        AntiStunActive = Options.antistun.Value
        if AntiStunActive then
            startAntiStun()
        else
            stopAntiStun()
        end
    end)

    -- Initialize OFF
    Options.antistun:SetValue(false)
end)

-- anti stun ends ---------------------------------------------------------------------------

-- esp starts --------------------------------------------------------------------------------

--// Merged ESP (Players + Fruits) - Single Toggle
--// Drop into StarterPlayerScripts as a LocalScript

---------------------------------------------------------------------
-- Services
---------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

---------------------------------------------------------------------
-- Shared UI / Toggle plumbing (works with your Tabs lib if present)
---------------------------------------------------------------------
getgenv().Options = getgenv().Options or {}
local Options = getgenv().Options

-- Master toggle state (both Player + Fruit ESP)
_G.BF_MASTER_ESP = _G.BF_MASTER_ESP or false

-- Try to hook into your existing Tabs lib (graceful fallback)
task.spawn(function()
    -- Wait for a Tabs lib if your hub provides it; else skip
    local waited = 0
    while waited < 10 and (not _G.Tabs) and (not Tabs) do
        waited += 0.1
        task.wait(0.1)
    end
    local HubTabs = (_G.Tabs or Tabs)
    if HubTabs and HubTabs.Main and HubTabs.Main.AddToggle then
        Options.masteresp = HubTabs.Main:AddToggle("masteresp", {
            Title = "ESP (Players + Fruits)",
            Default = false
        })

        Options.masteresp:OnChanged(function()
            _G.BF_MASTER_ESP = Options.masteresp.Value
            if _G.BF_MASTER_ESP then
                _G.__ESP_EnableAll()
            else
                _G.__ESP_DisableAll()
            end
        end)

        Options.masteresp:SetValue(false)
    else
        -- No UI lib detected; default OFF. You can flip at runtime by:
        -- _G.BF_MASTER_ESP = true; _G.__ESP_EnableAll()
    end
end)

---------------------------------------------------------------------
-- ===================== Player ESP Section =======================
---------------------------------------------------------------------
local ESP_ID = "BF_NameESP_" .. tostring(math.random(1, 1e9))

local function round(n) return math.floor((tonumber(n) or 0) + 0.5) end

local function getLevel(plr: Player)
    local d = plr:FindFirstChild("Data")
    local lv = d and d:FindFirstChild("Level")
    local ok, val = pcall(function() return lv and lv.Value end)
    return (ok and val) or "?"
end

local function teamColor(plr: Player)
    local team = plr.Team and plr.Team.Name or ""
    if team == "Pirates" then
        return Color3.fromRGB(255, 60, 60) -- red
    elseif team == "Marines" then
        return Color3.fromRGB(0, 120, 255) -- blue
    else
        return Color3.fromRGB(230, 230, 230) -- neutral
    end
end

local function player_ClearOne(plr: Player)
    local c = plr.Character
    if c and c:FindFirstChild("Head") then
        local tag = c.Head:FindFirstChild(ESP_ID)
        if tag then tag:Destroy() end
    end
end

local function player_ClearAll()
    for _, p in ipairs(Players:GetPlayers()) do
        player_ClearOne(p)
    end
end

local function player_EnsureOne(plr: Player)
    if plr == LocalPlayer then return end
    local myChar, char = LocalPlayer.Character, plr.Character
    if not (myChar and char) then return end

    local myHead = myChar:FindFirstChild("Head")
    local head   = char:FindFirstChild("Head")
    if not (myHead and head) then return end

    local bill = head:FindFirstChild(ESP_ID)
    if not bill then
        bill = Instance.new("BillboardGui")
        bill.Name = ESP_ID
        bill.AlwaysOnTop = true
        bill.Adornee = head
        bill.Size = UDim2.new(0, 170, 0, 18)
        bill.ExtentsOffset = Vector3.new(0, 2, 0)
        bill.ResetOnSpawn = false
        bill.Parent = head

        local label = Instance.new("TextLabel")
        label.Name = "Text"
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Font = Enum.Font.GothamSemibold
        label.TextScaled = false
        label.TextSize = 14
        label.TextStrokeTransparency = 0.6
        label.Parent = bill
    end

    local label = bill:FindFirstChild("Text")
    if not label then return end

    local distM = round((myHead.Position - head.Position).Magnitude / 3)
    local lvl = getLevel(plr)

    label.Text = ("%s [%s] • %dm"):format(plr.Name, tostring(lvl), distM)
    label.TextColor3 = teamColor(plr)
end

local function player_UpdateAll()
    if not _G.BF_MASTER_ESP then
        player_ClearAll()
        return
    end
    for _, p in ipairs(Players:GetPlayers()) do
        player_EnsureOne(p)
    end
end

-- periodic refresh for players
task.spawn(function()
    while true do
        task.wait(0.5)
        player_UpdateAll()
    end
end)

-- cleanup on player removal
Players.PlayerRemoving:Connect(function(p)
    player_ClearOne(p)
end)

-- refresh after your respawn
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if _G.BF_MASTER_ESP then player_UpdateAll() end
end)

---------------------------------------------------------------------
-- ====================== Fruit ESP Section =======================
---------------------------------------------------------------------
-- Settings (fruit nametag)
local FR_SIZE = Vector2.new(120, 22)             -- min size (px)
local BORDER_RAINBOW_SPEED = 2                   -- hue cycle speed
local PREFERRED_PART_NAME = "BillboardBase"      -- preferred adornee part
local FONT_ASSET_ID = "rbxassetid://11702779409" -- Poppins (fixed constant)

---------------------------------------------------------------------
-- Helpers (fruit detection + boat filter)
---------------------------------------------------------------------
local function lower(s) return (typeof(s) == "string" and s:lower()) or "" end

-- Case-insensitive substring match helper
local function containsFruitName(s: string?): boolean
    if not s then return false end
    s = s:lower()
    -- Extend here if your game uses other tokens like "devil"
    return s:find("fruit", 1, true) ~= nil
end

-- Walk up to a stable "root" (Tool or Model) if possible
local function getFruitRoot(inst: Instance): Instance
    local cur = inst
    local best = inst
    while cur and cur ~= Workspace do
        if cur:IsA("Tool") or cur:IsA("Model") then
            best = cur
        end
        cur = cur.Parent
    end
    return best
end

-- BOAT/VEHICLE guard: names, seats, size, and common folders
local BOAT_KEYWORDS = {
    "boat","ship","sloop","brig","galleon","submarine","raft","dinghy",
    "canoe","vessel","galley","caravel","kayak","sail","yacht","ferry",
    "skiff","barge","dhow","cutter","junk","frigate","man o' war","pirate ship"
}

local FOLDER_EXCLUDES = { "boats","boat","ships","vehicles","vehicle","transport","docks","harbor","harbour","port" }

local function nameHasAny(s: string, list: {string}): boolean
    s = lower(s)
    for _, k in ipairs(list) do
        if s:find(k, 1, true) then return true end
    end
    return false
end

local function isBoatLike(root: Instance): boolean
    -- check root & ancestors names
    local a = root
    while a and a ~= Workspace do
        local nm = lower(a.Name)
        if nameHasAny(nm, BOAT_KEYWORDS) or nameHasAny(nm, FOLDER_EXCLUDES) then
            return true
        end
        a = a.Parent
    end
    -- seats typically on vehicles/boats
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("VehicleSeat") or d:IsA("Seat") then
            return true
        end
    end
    -- size gate (fruits are small)
    local function tooBigFromSize(size: Vector3)
        return (size.X > 20) or (size.Y > 20) or (size.Z > 20)
    end
    if root:IsA("Model") then
        local ok, size = pcall(function() return root:GetExtentsSize() end)
        if ok and size and tooBigFromSize(size) then return true end
    elseif root:IsA("BasePart") then
        if tooBigFromSize(root.Size) then return true end
    end
    return false
end

-- Is this ANY candidate that could be a fruit root or part of it?
local function isFruitCandidate(inst: Instance): boolean
    -- 1) quick name match on itself
    if containsFruitName(inst.Name) and inst:IsDescendantOf(Workspace) then
        local root = getFruitRoot(inst)
        if isBoatLike(root) then return false end
        return true
    end
    -- 2) if it's a BasePart, check a few ancestors for the name token
    if inst:IsA("BasePart") then
        local a = inst.Parent
        for _ = 1, 3 do
            if not a then break end
            if containsFruitName(a.Name) and a:IsDescendantOf(Workspace) then
                if not isBoatLike(getFruitRoot(a)) then
                    return true
                end
            end
            a = a.Parent
        end
    end
    return false
end

-- Pick a base part from any fruit root (Tool/Model/BasePart), with preference
local function pickFruitBase(inst: Instance): BasePart?
    -- If Tool, try preferred / Handle / largest BasePart
    if inst:IsA("Tool") then
        local preferred = inst:FindFirstChild(PREFERRED_PART_NAME)
        if preferred and preferred:IsA("BasePart") then return preferred end
        local handle = inst:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then return handle end
        local largest: BasePart? = nil
        local largestMag = -1
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then
                local s = d.Size
                local mag = s.X * s.Y * s.Z
                if mag > largestMag then
                    largestMag = mag
                    largest = d
                end
            end
        end
        return largest
    end

    -- If Model, prefer a child named preferred/Handle, else largest BasePart
    if inst:IsA("Model") then
        local preferred = inst:FindFirstChild(PREFERRED_PART_NAME)
        if preferred and preferred:IsA("BasePart") then return preferred end
        local handle = inst:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then return handle end
        local largest: BasePart? = nil
        local largestMag = -1
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then
                local s = d.Size
                local mag = s.X * s.Y * s.Z
                if mag > largestMag then
                    largestMag = mag
                    largest = d
                end
            end
        end
        return largest
    end

    -- If already a BasePart, use it
    if inst:IsA("BasePart") then
        return inst
    end

    -- Fallback: search descendants for any BasePart
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then
            return d
        end
    end
    return nil
end

-- Pretty label from any root
local function extractFruitLabel(root: Instance): string
    local name = root.Name
    local before = name:match("^(.*)%s+[Ff]ruit$")
    if before and before ~= "" then
        return (before:gsub("^%s*(.-)%s*$", "%1"))
    end
    local stripped = name:gsub("[Ff]ruit", "")
    return (stripped:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1"))
end

-- white name/number; green brackets
local function buildFruitText(fruitLabel: string, distanceStuds: number): string
    local distStr = string.format("%dm", math.floor(distanceStuds + 0.5))
    return string.format(
        '<font color="#FFFFFF">%s Fruit </font><font color="#59ff85">[</font><font color="#FFFFFF">%s</font><font color="#59ff85">]</font>',
        fruitLabel, distStr
    )
end

local function fitToText(gui: BillboardGui, container: Frame, label: TextLabel)
    local bounds = label.TextBounds
    local padX, padY = 10, 4
    local w = math.clamp(bounds.X + padX * 2, FR_SIZE.X, 500)
    local h = math.max(bounds.Y + padY * 2, FR_SIZE.Y)
    container.Size = UDim2.fromOffset(w, h)
    gui.Size = container.Size
end

local function addArrow(parentGui: BillboardGui)
    local arrow = Instance.new("TextLabel")
    arrow.Name = "DownArrow"
    arrow.BackgroundTransparency = 1
    arrow.Size = UDim2.fromOffset(16, 10)
    arrow.AnchorPoint = Vector2.new(0.5, 0)
    arrow.Position = UDim2.new(0.5, 0, 1, 2)
    arrow.Text = "▼"
    arrow.TextSize = 12
    arrow.TextColor3 = Color3.new(1, 1, 1)
    arrow.TextStrokeTransparency = 0.5
    arrow.Parent = parentGui
    return arrow
end

local function startRainbow(stroke: UIStroke, speed: number)
    local t = 0
    return RunService.Heartbeat:Connect(function(dt)
        t += dt * speed
        local hue = (t % 1)
        stroke.Color = Color3.fromHSV(hue, 1, 1)
    end)
end

-- Fruit bookkeeping (keyed by the fruit "root" instance)
local FruitActive: {[Instance]: {base: BasePart?, gui: BillboardGui?, conn: RBXScriptConnection?, strokeConn: RBXScriptConnection?}} = {}

local function fruit_ClearOne(root: Instance)
    local rec = FruitActive[root]
    if rec then
        if rec.conn then rec.conn:Disconnect() end
        if rec.strokeConn then rec.strokeConn:Disconnect() end
        if rec.gui then rec.gui:Destroy() end
        FruitActive[root] = nil
    end
end

local function fruit_ClearAll()
    for root, _ in pairs(FruitActive) do
        fruit_ClearOne(root)
    end
end

local function fruit_MakeOneFromRoot(root: Instance)
    if FruitActive[root] then return end
    -- boat/vehicle guard one more time for safety
    if isBoatLike(root) then return end

    local base = pickFruitBase(root)
    if not base then return end

    local gui = Instance.new("BillboardGui")
    gui.Name = "FruitNametag"
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.Adornee = base
    gui.StudsOffset = Vector3.new(0, 3, 0)
    gui.MaxDistance = 0                 -- show from anywhere
    gui.Size = UDim2.fromOffset(FR_SIZE.X, FR_SIZE.Y)
    gui.ResetOnSpawn = false
    gui.Parent = (root:IsA("Tool") or root:IsA("Model")) and root or base

    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.Size = gui.Size
    container.Parent = gui

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.6
    stroke.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = container

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.PaddingTop = UDim.new(0, 4)
    padding.PaddingBottom = UDim.new(0, 4)
    padding.Parent = container

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.RichText = true
    label.TextScaled = false
    label.TextSize = 14
    label.TextWrapped = false
    label.TextStrokeTransparency = 0.6
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.FontFace = Font.new(FONT_ASSET_ID, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
    label.Parent = container

    addArrow(gui)

    local fruitName = extractFruitLabel(root)

    label:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitToText(gui, container, label)
    end)

    local conn = RunService.Heartbeat:Connect(function()
        if not _G.BF_MASTER_ESP then
            if gui.Enabled then gui.Enabled = false end
            return
        else
            if not gui.Enabled then gui.Enabled = true end
        end

        -- validate base still exists
        if not base or not base.Parent then
            fruit_ClearOne(root)
            return
        end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local dist = (hrp.Position - base.Position).Magnitude
        label.Text = buildFruitText(fruitName, dist)
    end)

    local rainbowConn = startRainbow(stroke, BORDER_RAINBOW_SPEED)

    -- initial layout
    label.Text = buildFruitText(fruitName, 0)
    fitToText(gui, container, label)

    FruitActive[root] = { base = base, gui = gui, conn = conn, strokeConn = rainbowConn }

    -- cleanup if root leaves Workspace
    root.AncestryChanged:Connect(function(_, parent)
        if not parent or not root:IsDescendantOf(Workspace) then
            fruit_ClearOne(root)
        end
    end)
end

-- bootstrap & listeners (fruits) - handles Tools / Models / Parts with "fruit" in the name
local function fruit_BootstrapExisting()
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if isFruitCandidate(inst) then
            local root = getFruitRoot(inst)
            if root and not FruitActive[root] then
                fruit_MakeOneFromRoot(root)
            end
        end
    end
end

Workspace.DescendantAdded:Connect(function(inst)
    if not _G.BF_MASTER_ESP then return end
    if isFruitCandidate(inst) then
        local root = getFruitRoot(inst)
        if root and not FruitActive[root] then
            task.defer(function()
                fruit_MakeOneFromRoot(root)
            end)
        end
    end
end)

Workspace.DescendantRemoving:Connect(function(inst)
    -- If any tracked root is going away, clear it
    if FruitActive[inst] then
        fruit_ClearOne(inst)
        return
    end
    -- If a tracked base goes away, clear that root
    for root, rec in pairs(FruitActive) do
        if rec.base == inst then
            fruit_ClearOne(root)
            break
        end
    end
end)

---------------------------------------------------------------------
-- ========== Master enable/disable that drives BOTH ESPs ==========
---------------------------------------------------------------------
function _G.__ESP_EnableAll()
    -- Players: force an update immediately
    player_UpdateAll()
    -- Fruits: build all current (now includes map-spawn; ignores boats)
    fruit_BootstrapExisting()
    -- Ensure all fruit GUIs visible
    for _, rec in pairs(FruitActive) do
        if rec.gui then rec.gui.Enabled = true end
    end
end

function _G.__ESP_DisableAll()
    -- Players: remove all
    player_ClearAll()
    -- Fruits: destroy all
    fruit_ClearAll()
end

-- If someone sets _G.BF_MASTER_ESP manually before UI appears, respect it
if _G.BF_MASTER_ESP then
    _G.__ESP_EnableAll()
end


-- esp ends --------------------------------------------------------------------------------------------

-- server hop starts --------------------------------------------------------------------------------------------------

    Tabs.Main2:AddButton({
        Title = "Server Hop",
        Description = "click to hop",
        Callback = function()
            Window:Dialog({
                Title = "Hop to another server",
                Content = "",
                Buttons = {
                    {
                        Title = "Confirm",
                        Callback = function()
                            print("Confirmed the dialog.")
                            local TeleportService = game:GetService("TeleportService")
                            local HttpService = game:GetService("HttpService")

                            local Servers = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
                            local Server, Next = nil, nil
                            local function ListServers(cursor)
                                local Raw = game:HttpGet(Servers .. ((cursor and "&cursor=" .. cursor) or ""))
                                return HttpService:JSONDecode(Raw)
                            end

                            repeat
                                local Servers = ListServers(Next)
                                Server = Servers.data[math.random(1, (#Servers.data / 3))]
                                Next = Servers.nextPageCursor
                            until Server

                            if Server.playing < Server.maxPlayers and Server.id ~= game.JobId then
                                TeleportService:TeleportToPlaceInstance(game.PlaceId, Server.id, game.Players.LocalPlayer)
                            end
                        end
                    },
                    {
                        Title = "Cancel",
                        Callback = function()
                            print("Cancelled the dialog.")
                        end
                    }
                }
            })
        end
    })

-- server hop end ---------------------------------------------------------------------------------------------








-- photo starts ------------------------------------------------------------------------------------------------------

local function createDraggableButton()
    local Players = game:GetService("Players")
    local TweenService = game:GetService("TweenService")
    local UIS = game:GetService("UserInputService")
    local CoreGui = game:GetService("CoreGui")
    local RunService = game:GetService("RunService")

    local player = Players.LocalPlayer
    local gui = Instance.new("ScreenGui")
    gui.Name = "DraggableRippleButtonGui"
    gui.ResetOnSpawn = false
    gui.Parent = player:WaitForChild("PlayerGui")

    -- 🟦 Button
    local btn = Instance.new("ImageButton")
    btn.Name = "SquareButton"
    btn.Size = UDim2.fromOffset(72, 72)
    btn.Position = UDim2.fromScale(0, 0.5)
    btn.AnchorPoint = Vector2.new(0, 0.5)
    btn.BackgroundColor3 = Color3.fromRGB(8, 4, 28)
    btn.BackgroundTransparency = 1
    btn.AutoButtonColor = false
    btn.Image = "rbxassetid://71574893626704" -- Replace with your own image if needed
    btn.ImageTransparency = 0
    btn.ImageColor3 = Color3.new(1, 1, 1)
    btn.ScaleType = Enum.ScaleType.Fit
    btn.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = btn

    -- 🌈 Rainbow Border
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = btn

    local aspect = Instance.new("UIAspectRatioConstraint")
    aspect.AspectRatio = 1
    aspect.Parent = btn

    -- 🌈 Animate Rainbow Color
    task.spawn(function()
        while btn and btn.Parent do
            local hue = tick() % 5 / 5
            local color = Color3.fromHSV(hue, 1, 1)
            stroke.Color = color
            RunService.RenderStepped:Wait()
        end
    end)

    -- 🟧 Dragging
    local dragging = false
    local dragStart
    local startPos

    local function updateDrag(input)
        if not dragging then return end
        local delta = input.Position - dragStart
        btn.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end

    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = btn.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            updateDrag(input)
        end
    end)

    -- 🌀 Ripple Effect
    local function rippleAt(screenPos)
        if typeof(screenPos) ~= "Vector2" then
            screenPos = Vector2.new(screenPos.X, screenPos.Y)
        end

        local localPos = screenPos - btn.AbsolutePosition

        local ring = Instance.new("Frame")
        ring.Name = "RippleRing"
        ring.BackgroundTransparency = 1
        ring.Size = UDim2.fromOffset(0, 0)
        ring.AnchorPoint = Vector2.new(0.5, 0.5)
        ring.Position = UDim2.fromOffset(localPos.X, localPos.Y)
        ring.ZIndex = btn.ZIndex + 10
        ring.Parent = btn

        local ringCorner = Instance.new("UICorner")
        ringCorner.CornerRadius = UDim.new(1, 0)
        ringCorner.Parent = ring

        local ringStroke = Instance.new("UIStroke")
        ringStroke.Thickness = 2
        ringStroke.Transparency = 0.1
        ringStroke.Parent = ring

        -- 🌈 Rainbow ripple color
        task.spawn(function()
            local offset = math.random()
            while ringStroke and ringStroke.Parent do
                local hue = (tick() * 0.4 + offset) % 1
                ringStroke.Color = Color3.fromHSV(hue, 1, 1)
                RunService.RenderStepped:Wait()
            end
        end)

        local maxSide = math.max(btn.AbsoluteSize.X, btn.AbsoluteSize.Y)
        local targetSize = maxSide * 1.6

        local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        local grow = TweenService:Create(ring, tweenInfo, { Size = UDim2.fromOffset(targetSize, targetSize) })
        local fade = TweenService:Create(ringStroke, tweenInfo, { Transparency = 1 })

        grow:Play()
        fade:Play()
        grow.Completed:Connect(function()
            ring:Destroy()
        end)
    end

    -- 🔘 Button Click to toggle UI (CanvasGroup-based detection)
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            rippleAt(input.Position)

            local screenGui = CoreGui:FindFirstChild("ScreenGui")
            local foundCanvasGroup = false

            if screenGui then
                for _, child in pairs(screenGui:GetChildren()) do
                    local canvasGroup = child:FindFirstChildOfClass("CanvasGroup")
                    if canvasGroup then
                        local frameParent = canvasGroup.Parent
                        if frameParent and frameParent:IsA("Frame") then
                            frameParent.Visible = not frameParent.Visible
                        end
                        foundCanvasGroup = true
                        break
                    end
                end
            end

            if not foundCanvasGroup then
                warn("[DraggableButton] No CanvasGroup found, removing GUI.")
                gui:Destroy()
            end
        end
    end)

    -- ⏬ Press + Release Animation
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), { Size = UDim2.fromOffset(68, 68) }):Play()
    end)

    btn.MouseButton1Up:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08), { Size = UDim2.fromOffset(72, 72) }):Play()
    end)
end

createDraggableButton()

-- photo end -------------------------------------------------------------------------------------------------------------

-- ==============================
-- Cleanup: Settings integrations
-- ==============================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})

InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/specific-game")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

Fluent:Notify({
    Title = "Fluent",
    Content = "The UI has been loaded.",
    Duration = 8
})

SaveManager:LoadAutoloadConfig()
