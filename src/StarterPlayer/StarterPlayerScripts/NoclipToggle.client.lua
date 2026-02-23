local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local backpack = player:WaitForChild("Backpack")
local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 5)

local TOOL_NAME = "Noclip"
local ACTION_NAME = "ToggleNoclipAction"

local forceEquipRemote = ReplicatedStorage:WaitForChild("ForceEquipTool")
local requestToolCopy = ReplicatedStorage:WaitForChild("RequestToolCopy")

-- Colors for highlight similar to Hotbar
local DEFAULT_BG = Color3.fromRGB(20,20,24)
local HIGHLIGHT_BG = Color3.fromRGB(40,40,65)
local DEFAULT_STROKE = Color3.fromRGB(60,60,60)
local HIGHLIGHT_STROKE = Color3.fromRGB(140,155,255)
local requestToolCopy = ReplicatedStorage:FindFirstChild("RequestToolCopy")

local function toggleNoclip()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local tool = (char and char:FindFirstChild(TOOL_NAME)) or backpack:FindFirstChild(TOOL_NAME) or (starterGear and starterGear:FindFirstChild(TOOL_NAME))
    if not tool then return end

    if tool.Parent == char then
        hum:UnequipTools()
        if type(refreshSlotUI) == "function" then
            task.defer(refreshSlotUI)
        end
        return
    end

    -- Prefer server-side equip for reliability
    if forceEquipRemote then
        pcall(function()
            forceEquipRemote:FireServer("Dev", TOOL_NAME)
        end)
        if type(refreshSlotUI) == "function" then
            task.delay(0.12, refreshSlotUI)
        end
        return
    end

    -- Fallback to local equip
    local ok = pcall(function() hum:EquipTool(tool) end)
    if not ok and requestToolCopy then
        pcall(function() requestToolCopy:InvokeServer("Dev", TOOL_NAME) end)
    end
    if type(refreshSlotUI) == "function" then
        task.defer(refreshSlotUI)
    end
end

ContextActionService:BindAction(ACTION_NAME, function(actionName, inputState, inputObject)
    if inputState == Enum.UserInputState.Begin then
        toggleNoclip()
    end
    return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Z)

backpack.ChildAdded:Connect(function(child)
    if child:IsA("Tool") and child.Name == TOOL_NAME then
        -- no-op
    end
end)

-- Small bottom-left slot UI
local playerGui = player:WaitForChild("PlayerGui")
local slotGui = Instance.new("ScreenGui")
slotGui.Name = "NoclipSlot"
slotGui.ResetOnSpawn = false
slotGui.IgnoreGuiInset = true
slotGui.Parent = playerGui

local SLOT_SCALE = 0.08 -- 8% of screen width/height (square)
local MARGIN_SCALE = 0.02

local slotBtn = Instance.new("TextButton")
slotBtn.Name = "NoclipSlotBtn"
slotBtn.AnchorPoint = Vector2.new(0, 1)
slotBtn.Position = UDim2.fromScale(MARGIN_SCALE, 1 - MARGIN_SCALE)
slotBtn.Size = UDim2.fromScale(SLOT_SCALE, SLOT_SCALE)
slotBtn.BackgroundColor3 = Color3.fromRGB(20,20,24)
slotBtn.BackgroundTransparency = 0.05
slotBtn.AutoButtonColor = false
slotBtn.Text = ""
slotBtn.Parent = slotGui

local corner = Instance.new("UICorner", slotBtn)
corner.CornerRadius = UDim.new(0.15, 0)

local stroke = Instance.new("UIStroke", slotBtn)
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(60,60,60)

-- Ensure perfect square regardless of scaling/layout
local aspect = Instance.new("UIAspectRatioConstraint", slotBtn)
aspect.AspectRatio = 1
aspect.DominantAxis = Enum.DominantAxis.Height

-- Hotkey indicator (top-left)
local hotkey = Instance.new("TextLabel")
hotkey.Name = "Hotkey"
hotkey.AnchorPoint = Vector2.new(0, 0)
hotkey.Position = UDim2.fromScale(0.06, 0.04)
hotkey.Size = UDim2.fromScale(0.28, 0.22)
hotkey.BackgroundTransparency = 1
hotkey.Text = "Z"
hotkey.Font = Enum.Font.GothamBold
hotkey.TextScaled = true
hotkey.TextColor3 = Color3.fromRGB(200,200,200)
hotkey.TextXAlignment = Enum.TextXAlignment.Left
hotkey.Parent = slotBtn

local thumb = Instance.new("ImageLabel")
thumb.Name = "Thumb"
thumb.AnchorPoint = Vector2.new(0.5, 0.5)
thumb.Position = UDim2.fromScale(0.5, 0.45)
thumb.Size = UDim2.fromScale(0.7, 0.7)
thumb.BackgroundTransparency = 1
thumb.ScaleType = Enum.ScaleType.Fit
thumb.Parent = slotBtn

local label = Instance.new("TextLabel")
label.Name = "Name"
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.fromScale(0.5, 0.98)
label.Size = UDim2.fromScale(0.9, 0.22)
label.BackgroundTransparency = 1
label.Text = ""
label.Font = Enum.Font.Gotham
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(210,210,210)
label.Parent = slotBtn

slotBtn.MouseButton1Click:Connect(function()
    toggleNoclip()
end)

local function refreshSlotUI()
    local tool = (player.Character and player.Character:FindFirstChild(TOOL_NAME))
               or backpack:FindFirstChild(TOOL_NAME)
               or (starterGear and starterGear:FindFirstChild(TOOL_NAME))

    if tool then
        -- set thumbnail if available
        local icon = ""
        local ok, tex = pcall(function() return tool.TextureId end)
        if ok and type(tex) == "string" and #tex > 0 then icon = tex end
        local attr = tool:GetAttribute("Icon")
        if type(attr) == "string" and #attr > 0 then icon = attr end

        if #icon > 0 then
            thumb.Image = icon
            thumb.Visible = true
        else
            thumb.Image = ""
            thumb.Visible = false
        end
        label.Text = tool.Name
        if tool.Parent == player.Character then
            stroke.Color = HIGHLIGHT_STROKE
            slotBtn.BackgroundColor3 = HIGHLIGHT_BG
        else
            stroke.Color = DEFAULT_STROKE
            slotBtn.BackgroundColor3 = DEFAULT_BG
        end
    else
        -- If the tool lives in StarterGear (engine may not have copied it to Backpack yet), ask the server
        if starterGear and starterGear:FindFirstChild(TOOL_NAME) then
            if requestToolCopy and requestToolCopy.InvokeServer then
                pcall(function()
                    requestToolCopy:InvokeServer("Dev", TOOL_NAME)
                end)
            end
            -- schedule a refresh after server copies
            if type(refreshSlotUI) == "function" then
                task.delay(0.15, refreshSlotUI)
            end
            thumb.Image = ""
            thumb.Visible = false
            label.Text = ""
            stroke.Color = Color3.fromRGB(60,60,60)
            return
        end

        thumb.Image = ""
        thumb.Visible = false
        label.Text = ""
        stroke.Color = DEFAULT_STROKE
        slotBtn.BackgroundColor3 = DEFAULT_BG
    end
end

backpack.ChildAdded:Connect(function(child)
    if child:IsA("Tool") and child.Name == TOOL_NAME then
        refreshSlotUI()
    end
end)
backpack.ChildRemoved:Connect(function(child)
    if child:IsA("Tool") and child.Name == TOOL_NAME then
        refreshSlotUI()
    end
end)

if starterGear then
    starterGear.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and child.Name == TOOL_NAME then
            refreshSlotUI()
        end
    end)
    starterGear.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") and child.Name == TOOL_NAME then
            refreshSlotUI()
        end
    end)
end

player.CharacterAdded:Connect(function()
    task.wait(0.15)
    -- Re-parent UI to the (possibly new) PlayerGui and refresh
    local pg = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 5)
    if pg then
        slotGui.Parent = pg
    end
    -- refresh after a small delay to allow engine StarterGear->Backpack copy
    task.wait(0.15)
    refreshSlotUI()
end)

-- Keep UI in sync when tool is equipped/unequipped on the Character
local function connectCharacterListeners(character)
    if not character then return end
    character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and child.Name == TOOL_NAME then
            -- equipped
            refreshSlotUI()
        end
    end)
    character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") and child.Name == TOOL_NAME then
            -- unequipped
            -- small delay to allow engine updates
            task.delay(0.05, refreshSlotUI)
        end
    end)
end

if player.Character then
    connectCharacterListeners(player.Character)
end
player.CharacterAdded:Connect(function(char)
    connectCharacterListeners(char)
end)

-- initial
refreshSlotUI()
