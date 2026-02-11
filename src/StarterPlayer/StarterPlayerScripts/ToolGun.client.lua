local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local fireEvent = ReplicatedStorage:WaitForChild("ToolGunFire")

-- read settings from module if present
local TOOLCFG
if ReplicatedStorage:FindFirstChild("Toolgunsettings") then
    local mod = require(ReplicatedStorage:WaitForChild("Toolgunsettings"))
    TOOLCFG = mod.get()
end

local COOLDOWN = (TOOLCFG and TOOLCFG.cd) or 0.5
local firing = {}

local fireAck = ReplicatedStorage:WaitForChild("ToolGunFireAck")

local Debris = game:GetService("Debris")

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
                    local hitPos = (mouse and mouse.Hit and mouse.Hit.Position) or (origin + camera.CFrame.LookVector * 100)
                    local dir = (hitPos - origin)
                    if dir.Magnitude == 0 then dir = camera.CFrame.LookVector end
                    dir = dir.Unit
                    fireEvent:FireServer(origin, dir)
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

    -- listen for server ack to play sound
    fireAck.OnClientEvent:Connect(function()
        playFireSound()
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
