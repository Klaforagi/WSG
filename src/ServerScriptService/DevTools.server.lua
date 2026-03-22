-- DevTools.server.lua
-- Dev/testing tool: ensures ReplicatedStorage.Remotes.RequestAddCoins exists
-- and grants coins when fired.
--
-- WHY NO IsStudio() GUARD ON REMOTE CREATION:
-- In Team Test the server process can report IsStudio() = false even though
-- the game was launched from Studio.  XPService.server.lua (no guard) was
-- creating the Remotes folder, but this script was bailing before adding
-- RequestAddCoins — so the client saw Remotes but not the child RemoteEvent.
-- Creating a dormant RemoteEvent is harmless; the client-side DevToolUI
-- already guards its button with IsStudio(), so nothing fires in production.

local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ── 1. Ensure ReplicatedStorage.Remotes folder ───────────────────────────
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if remotesFolder then
	print("[DevTools] Remotes folder already exists")
else
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
	print("[DevTools] Remotes folder CREATED")
end

-- ── 2. Ensure Remotes.RequestAddCoins RemoteEvent ────────────────────────
local addCoinsRemote = remotesFolder:FindFirstChild("RequestAddCoins")
if addCoinsRemote then
	print("[DevTools] RequestAddCoins already exists")
else
	addCoinsRemote = Instance.new("RemoteEvent")
	addCoinsRemote.Name = "RequestAddCoins"
	addCoinsRemote.Parent = remotesFolder
	print("[DevTools] RequestAddCoins CREATED")
end

print("[DevTools] IsStudio =", RunService:IsStudio(),
	"| remote =", addCoinsRemote:GetFullName())

-- ── 3. Load the project's real CurrencyService module (if available) ─────
-- CurrencyService:AddCoins(player, amount) handles in-memory balance,
-- leaderstats update, and fires CoinsUpdated to the client — so the UI
-- coin display updates automatically.
local CurrencyService = nil
do
	local mod = ServerScriptService:FindFirstChild("CurrencyService")
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			CurrencyService = result
			print("[DevTools] CurrencyService module loaded")
		else
			warn("[DevTools] CurrencyService require failed:", tostring(result))
		end
	else
		warn("[DevTools] CurrencyService ModuleScript not found in ServerScriptService")
	end
end

-- ── 4. Fallback: locate a raw IntValue/NumberValue on the player ──────────
local function findCurrencyValue(player)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local coins = ls:FindFirstChild("Coins")
		if coins and (coins:IsA("IntValue") or coins:IsA("NumberValue")) then return coins end
		local gold = ls:FindFirstChild("Gold")
		if gold and (gold:IsA("IntValue") or gold:IsA("NumberValue")) then return gold end
	end
	local c = player:FindFirstChild("Coins")
	if c and (c:IsA("IntValue") or c:IsA("NumberValue")) then return c end
	local g = player:FindFirstChild("Gold")
	if g and (g:IsA("IntValue") or g:IsA("NumberValue")) then return g end
	return nil
end

-- ── 5. Handler ────────────────────────────────────────────────────────────
addCoinsRemote.OnServerEvent:Connect(function(player, amount)
	amount = tonumber(amount) or 10
	if amount <= 0 or amount > 1000 then return end
	print("[DevTools]", player.Name, "requested +" .. amount .. " coins")

	-- Path A: use the project's CurrencyService (preferred)
	if CurrencyService and type(CurrencyService.AddCoins) == "function" then
		local oldCoins = 0
		pcall(function() oldCoins = CurrencyService:GetCoins(player) end)
		local ok, err = pcall(function()
			CurrencyService:AddCoins(player, amount)
		end)
		if ok then
			local newCoins = 0
			pcall(function() newCoins = CurrencyService:GetCoins(player) end)
			print("[DevTools] CurrencyService:AddCoins OK | old:", oldCoins, "| new:", newCoins)
			return
		else
			warn("[DevTools] CurrencyService:AddCoins error:", tostring(err))
			-- fall through to Path B
		end
	end

	-- Path B: raw IntValue/NumberValue fallback
	local valueObj = findCurrencyValue(player)
	if valueObj then
		local old = valueObj.Value
		valueObj.Value = old + amount
		print("[DevTools] IntValue fallback | ", valueObj:GetFullName(), "| old:", old, "| new:", valueObj.Value)
	else
		warn("[DevTools] No currency found for", player.Name,
			"— CurrencyService unavailable and no IntValue at leaderstats.Coins/Gold or player.Coins/Gold")
	end
end)

print("[DevTools] Ready — ReplicatedStorage.Remotes.RequestAddCoins is live")

--------------------------------------------------------------------------------
-- PREMIUM CRATE / KEY SYSTEM  – Dev command: grant Keys for testing
-- RemoteEvent: ReplicatedStorage.Remotes.RequestAddKeys
-- Client fires with (amount), server grants keys. Same IsStudio guard on client.
-- TO REMOVE LATER: delete this entire section.
--------------------------------------------------------------------------------
local addKeysRemote = remotesFolder:FindFirstChild("RequestAddKeys")
if not addKeysRemote then
    addKeysRemote = Instance.new("RemoteEvent")
    addKeysRemote.Name = "RequestAddKeys"
    addKeysRemote.Parent = remotesFolder
    print("[DevTools] RequestAddKeys CREATED")
end

addKeysRemote.OnServerEvent:Connect(function(player, amount)
    amount = tonumber(amount) or 5
    if amount <= 0 or amount > 100 then return end
    print("[DevTools] PREMIUM CRATE / KEY SYSTEM:", player.Name, "requested +" .. amount .. " keys")

    if CurrencyService and type(CurrencyService.AddKeys) == "function" then
        local oldKeys = 0
        pcall(function() oldKeys = CurrencyService:GetKeys(player) end)
        local ok, err = pcall(function()
            CurrencyService:AddKeys(player, amount)
        end)
        if ok then
            local newKeys = 0
            pcall(function() newKeys = CurrencyService:GetKeys(player) end)
            print("[DevTools] CurrencyService:AddKeys OK | old:", oldKeys, "| new:", newKeys)
        else
            warn("[DevTools] CurrencyService:AddKeys error:", tostring(err))
        end
    else
        warn("[DevTools] CurrencyService:AddKeys not available")
    end
end)

print("[DevTools] PREMIUM CRATE / KEY SYSTEM — RequestAddKeys is live")
