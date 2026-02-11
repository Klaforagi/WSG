local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local fireEvent = ReplicatedStorage:WaitForChild("ToolGunFire")

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local playerGui = player:WaitForChild("PlayerGui")

-- custom cursor GUI (shows a closed parenthesis)
local cursorGui = Instance.new("ScreenGui")
cursorGui.Name = "ToolGunCursor"
cursorGui.ResetOnSpawn = false
cursorGui.IgnoreGuiInset = true

local cursorLabel = Instance.new("TextLabel")
cursorLabel.Name = "Cursor"
cursorLabel.Size = UDim2.new(0, 12, 0, 12)
cursorLabel.AnchorPoint = Vector2.new(0.5, 0.5)
cursorLabel.BackgroundTransparency = 1
cursorLabel.Text = "•"
cursorLabel.Font = Enum.Font.GothamBold
cursorLabel.TextScaled = false
cursorLabel.TextSize = 14
cursorLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
cursorLabel.Parent = cursorGui
local hitLabel = Instance.new("TextLabel")
hitLabel.Name = "HitMarker"
hitLabel.Size = UDim2.new(0, 12, 0, 12)
hitLabel.AnchorPoint = Vector2.new(0.5, 0.5)
hitLabel.BackgroundTransparency = 1
hitLabel.Text = "X"
hitLabel.Font = Enum.Font.GothamBold
hitLabel.TextScaled = false
hitLabel.TextSize = 14
hitLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
hitLabel.TextTransparency = 0.5
hitLabel.Visible = false
hitLabel.Parent = cursorGui
local cursorConn = nil

-- read settings from module if present
local TOOLCFG
if ReplicatedStorage:FindFirstChild("Toolgunsettings") then
    local mod = require(ReplicatedStorage:WaitForChild("Toolgunsettings"))
    TOOLCFG = mod.get()
end

local COOLDOWN = (TOOLCFG and TOOLCFG.cd) or 0.5
local firing = {}

local fireAck = ReplicatedStorage:WaitForChild("ToolGunFireAck")
local fireHit = ReplicatedStorage:FindFirstChild("ToolGunHit")

local Debris = game:GetService("Debris")

-- debug tracer toggle: when true, client spawns a short-lived laser part showing the shot
-- Can be overridden by the Toolgunsettings module via `showTracer` boolean.
local SHOW_TRACER = true
if TOOLCFG and type(TOOLCFG.showTracer) == "boolean" then
    SHOW_TRACER = TOOLCFG.showTracer
end

local TEAM_TRACER_COLORS = {
    Blue = Color3.fromRGB(65, 105, 225), -- royal blue
    Red  = Color3.fromRGB(255, 75, 75),
}
local DEFAULT_TRACER_COLOR = Color3.fromRGB(255, 200, 100)
local function getTracerColor()
    if player and player.Team then
        return TEAM_TRACER_COLORS[player.Team.Name] or DEFAULT_TRACER_COLOR
    end
    return DEFAULT_TRACER_COLOR
end

local function spawnTracer(origin, targetPos)
    if not origin or not targetPos then return end
    local dir = targetPos - origin
    local len = dir.Magnitude
    if len <= 0.01 then return end
    local beam = Instance.new("Part")
    beam.Name = "ToolGunTracer"
    beam.Size = Vector3.new(0.06, 0.06, len)
    beam.CFrame = CFrame.new(origin + dir/2, targetPos)
    beam.Anchored = true
    beam.CanCollide = false
    beam.Material = Enum.Material.Neon
    beam.Color = getTracerColor()
    beam.Transparency = 0.25
    beam.Parent = workspace
    Debris:AddItem(beam, 0.12)
end

local function playFireSound()
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return end
    local toolgunFolder = soundsFolder:FindFirstChild("Toolgun")
    if not toolgunFolder then return end
    local template = toolgunFolder:FindFirstChild("Gun_shoot")
    if not template or not template:IsA("Sound") then return end
    local s = template:Clone()
    s.Parent = workspace.CurrentCamera or workspace
    s:Play()
    Debris:AddItem(s, 3)
end

local function playHitSound()
    local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
    if not soundsFolder then return end
    local toolgunFolder = soundsFolder:FindFirstChild("Toolgun")
    if not toolgunFolder then return end
    local template = toolgunFolder:FindFirstChild("Gun_hitmarker")
    if not template or not template:IsA("Sound") then return end
    local s = template:Clone()
    s.Parent = workspace.CurrentCamera or workspace
    s:Play()
    Debris:AddItem(s, 3)
end

print("[ToolGun.client] script running for", player and player.Name)

-- Handle firing for a single tool instance
local function attachTool(tool)
    if not tool or not tool:IsA("Tool") then return end
    if tool.Name ~= "ToolGun" then return end
    print("[ToolGun.client] attachTool called for", tool:GetFullName())

    -- continuous fire while holding left mouse
    local mouse = player:GetMouse()
    local holding = false
    local function startFiring()
        if holding then return end
        holding = true
        firing[tool] = true
        spawn(function()
            while holding and tool and tool.Parent and firing[tool] do
                -- basic client-side cooldown to avoid spam
                if tool:GetAttribute("_canFire") == false then
                    -- wait a short moment and continue
                    task.wait(0.05)
                else
                    tool:SetAttribute("_canFire", false)
                    print("[ToolGun.client] Firing (hold) from", tool:GetFullName())
                    local origin
                    if tool:FindFirstChild("Handle") and tool.Handle:IsA("BasePart") then
                        origin = tool.Handle.Position
                    else
                        origin = camera.CFrame.Position
                    end
                    -- compute screen-based ray from cursor so visual dot and firing align
                    local mx, my
                    if mouse and mouse.X and mouse.Y then
                        mx = mouse.X
                        my = mouse.Y
                    else
                        local mpos = UserInputService:GetMouseLocation()
                        mx = mpos.X
                        my = mpos.Y
                    end
                    local ray = camera:ScreenPointToRay(mx, my)
                    local camOrigin = ray.Origin
                    local camDir = ray.Direction.Unit
                    local farPos = camOrigin + camDir * 1000
                    -- optionally spawn a short tracer from the gun muzzle while waiting for server confirmation
                    local gunOrigin = origin
                    if SHOW_TRACER then
                        spawnTracer(gunOrigin, farPos)
                    end
                    -- send camera origin + direction and the gun origin so the server can hitscan and/or spawn visuals
                    fireEvent:FireServer(camOrigin, camDir, gunOrigin)
                    task.delay(COOLDOWN, function()
                        if tool and tool.Parent then
                            tool:SetAttribute("_canFire", true)
                        end
                    end)
                end
                task.wait(0.05)
            end
        end)
    end

    local function stopFiring()
        holding = false
        firing[tool] = nil
    end

    -- Bind mouse buttons when tool is equipped
    tool.Equipped:Connect(function()
        if mouse then
            mouse.Button1Down:Connect(startFiring)
            mouse.Button1Up:Connect(stopFiring)
        end
        -- show tiny custom cursor and hide system cursor
        if not cursorGui.Parent then
            cursorGui.Parent = playerGui
        end
        UserInputService.MouseIconEnabled = false
        if cursorConn then cursorConn:Disconnect() end
        cursorConn = RunService.RenderStepped:Connect(function()
            local mpos = UserInputService:GetMouseLocation()
            local mx, my = mpos.X or 0, mpos.Y or 0
            cursorLabel.Position = UDim2.new(0, mx, 0, my)
            hitLabel.Position = UDim2.new(0, mx, 0, my)
        end)
    end)

    tool.Unequipped:Connect(function()
        -- hide custom cursor and restore system cursor
        if cursorConn then cursorConn:Disconnect() end
        cursorConn = nil
        if cursorGui.Parent then
            cursorGui.Parent = nil
        end
        UserInputService.MouseIconEnabled = true
        stopFiring()
    end)

    -- initialize attribute
    if tool:GetAttribute("_canFire") == nil then
        tool:SetAttribute("_canFire", true)
    end

    -- initialize attribute
    if tool:GetAttribute("_canFire") == nil then
        tool:SetAttribute("_canFire", true)
    end

    -- mark connected (we attach via Equipped for hold behavior)
    if not tool:GetAttribute("_equippedConnected") then
        tool:SetAttribute("_equippedConnected", true)
    end

    -- listen for server ack to play sound and draw the authoritative tracer from the gun
    fireAck.OnClientEvent:Connect(function(gunOrigin, targetPos)
        playFireSound()
        if gunOrigin and targetPos and SHOW_TRACER then
            spawnTracer(gunOrigin, targetPos)
        end
    end)
    -- hit sound handled globally below
end

-- play hitmarker when server notifies a hit
if fireHit and fireHit:IsA("RemoteEvent") then
    fireHit.OnClientEvent:Connect(function()
        playHitSound()
        -- show an X at the cursor briefly
        if cursorGui.Parent then
            hitLabel.Visible = true
            task.delay(0.25, function()
                hitLabel.Visible = false
            end)
        else
            -- fallback: spawn a tiny transient GUI at current mouse position
            local mpos = UserInputService:GetMouseLocation()
            local tempGui = Instance.new("ScreenGui")
            tempGui.IgnoreGuiInset = true
            tempGui.ResetOnSpawn = false
            tempGui.Parent = playerGui
            local temp = Instance.new("TextLabel")
            temp.Size = UDim2.new(0,12,0,12)
            temp.Position = UDim2.new(0, mpos.X, 0, mpos.Y)
            temp.AnchorPoint = Vector2.new(0.5,0.5)
            temp.BackgroundTransparency = 1
            temp.Text = "X"
            temp.Font = Enum.Font.GothamBold
            temp.TextSize = 14
            temp.TextColor3 = Color3.fromRGB(0,0,0)
            temp.TextTransparency = 0.5
            temp.Parent = tempGui
            task.delay(0.25, function()
                tempGui:Destroy()
            end)
        end
    end)
end

-- Attach to existing tools in Backpack and Character
local function scanAndAttach()
    if player.Backpack then
        for _, child in ipairs(player.Backpack:GetChildren()) do
            attachTool(child)
        end
    end
    if player.Character then
        for _, child in ipairs(player.Character:GetChildren()) do
            attachTool(child)
        end
    end
end

-- Initial scan
scanAndAttach()

-- Watch for tools added to Backpack or Character
player.Backpack.ChildAdded:Connect(function(child)
    attachTool(child)
end)
player.CharacterAdded:Connect(function(char)
    -- scan character for tools and also watch for tools moved into it
    scanAndAttach()
    char.ChildAdded:Connect(function(child)
        attachTool(child)
    end)
end)

-- Also connect to tools already in StarterPack (they'll be copied to Backpack by Roblox)
for _, child in ipairs(StarterPack:GetChildren()) do
    if child:IsA("Tool") and child.Name == "ToolGun" then
        -- nothing to do; it'll be handled when placed in Backpack
    end
end
