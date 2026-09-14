--[[
	MVPLabelSmooth.client.lua
	TextScaled on a BillboardGui refits every time AbsoluteSize jitters (camera bob
	when close). Join pads hide that because they are large; MVP names still pop.
	Keep the stud-sized billboard, but drive TextSize locally with a deadzone.
]]

local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local LABEL_NAME = "MVPLabel"
local PLAYER_NAME = "PlayerName"
local SMOOTH_RATE = 16
local DEADZONE_PX = 2.5

local tracked = {} -- [TextLabel] = { shown = number }

local function computeTarget(label)
	local abs = label.AbsoluteSize
	if abs.X < 2 or abs.Y < 2 then
		return nil
	end

	local text = label.Text
	if type(text) ~= "string" or text == "" then
		return abs.Y
	end

	local heightFit = abs.Y
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(text, heightFit, label.Font, Vector2.new(10000, heightFit))
	end)
	if ok and typeof(bounds) == "Vector2" and bounds.X > abs.X and bounds.X > 1 then
		heightFit = heightFit * (abs.X / bounds.X)
	end
	return math.max(1, heightFit)
end

local function bind(label)
	if tracked[label] then
		return
	end
	tracked[label] = { shown = 0 }
	label.Destroying:Connect(function()
		tracked[label] = nil
	end)
end

local function tryBindFrom(inst)
	if inst.Name == LABEL_NAME and inst:IsA("BillboardGui") then
		local nameLabel = inst:FindFirstChild(PLAYER_NAME)
		if nameLabel and nameLabel:IsA("TextLabel") then
			bind(nameLabel)
		end
		return
	end
	if inst.Name == PLAYER_NAME and inst:IsA("TextLabel") then
		local parent = inst.Parent
		if parent and parent.Name == LABEL_NAME and parent:IsA("BillboardGui") then
			bind(inst)
		end
	end
end

for _, inst in ipairs(workspace:GetDescendants()) do
	tryBindFrom(inst)
end

workspace.DescendantAdded:Connect(function(inst)
	task.defer(tryBindFrom, inst)
end)

RunService.RenderStepped:Connect(function(dt)
	for label, state in pairs(tracked) do
		if not label.Parent then
			tracked[label] = nil
		else
			label.TextScaled = false
			local target = computeTarget(label)
			if target then
				if state.shown <= 0 then
					state.shown = target
				elseif math.abs(target - state.shown) > DEADZONE_PX then
					local alpha = 1 - math.exp(-SMOOTH_RATE * math.max(dt, 0))
					state.shown += (target - state.shown) * alpha
				end
				label.TextSize = state.shown
			end
		end
	end
end)
