-- Market: shared weapon offers, trails and emotes. Cosmetic cards are rarity-neutral.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Catalog = require(RS:WaitForChild("MarketCatalog"))
local Preview = require(RS:WaitForChild("SideUI"):WaitForChild("CosmeticPreviewController"))
local RarityStyles = require(script.Parent:WaitForChild("RarityStyles"))
local ClaimSound = require(script.Parent:WaitForChild("ClaimSound"))
local AssetCodes = require(RS:WaitForChild("AssetCodes"))
local EnchantTextStyler = require(script.Parent:WaitForChild("EnchantTextStyler"))
local ItemIconRegistry = require(RS:WaitForChild("ItemIconRegistry"))
local MarketStallUI = {}
local callbacks = setmetatable({}, { __mode = "k" })
local C = { Panel = Color3.fromRGB(18,22,35), Top = Color3.fromRGB(35,44,68),
    Card = Color3.fromRGB(27,34,51), Surface = Color3.fromRGB(12,16,27),
    Stroke = Color3.fromRGB(102,127,190), Text = Color3.fromRGB(246,248,255),
    Muted = Color3.fromRGB(177,188,214), Gold = Color3.fromRGB(255,204,90),
    PurchaseGreen = Color3.fromRGB(64,154,78) }

local function make(class, parent, properties)
    local instance = Instance.new(class)
    for k,v in pairs(properties or {}) do instance[k] = v end
    instance.Parent = parent
    return instance
end
local function round(frame, radius)
    make("UICorner", frame, { CornerRadius = UDim.new(0, radius or 12) })
end
local function label(parent, text, position, size, fontSize)
    local result = make("TextLabel", parent, { Text = text, Position = position, Size = size,
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = fontSize or 16,
        TextColor3 = C.Text, TextWrapped = true, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left })
    make("UITextSizeConstraint", result, { MinTextSize = 9, MaxTextSize = fontSize or 16 })
    return result
end
local function button(parent, text, position, size)
    local b = make("TextButton", parent, { Text = text, Position = position, Size = size,
        BackgroundColor3 = C.Card, BorderSizePixel = 0, Font = Enum.Font.GothamBold,
        TextSize = 16, TextScaled = true, TextColor3 = C.Text, AutoButtonColor = false })
    make("UITextSizeConstraint", b, { MinTextSize = 9, MaxTextSize = 16 })
    round(b, 10)
    return b
end
local function invoke(remote, ...)
    if not remote then return false end
    return pcall(remote.InvokeServer, remote, ...)
end
local function idSet(list)
    local set = {}
    for _,entry in pairs(type(list) == "table" and list or {}) do
        local id = type(entry) == "table" and entry.Id or entry
        if type(id) == "string" then set[id] = true end
    end
    return set
end
local function emoteLoadout(list)
    local slots = {}
    for _,entry in ipairs(type(list) == "table" and list or {}) do
        if type(entry) == "table" and tonumber(entry.Slot) and type(entry.Id) == "string" then
            slots[tonumber(entry.Slot)] = entry.Id
        end
    end
    return slots
end
local function number(n)
    local s = tostring(math.floor(n or 0))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

function MarketStallUI.SetCloseCallback(root, callback) callbacks[root] = callback end

local function formatCompactCount(value)
	local n = math.floor(tonumber(value) or 0)
	if n < 0 then
		return "-" .. formatCompactCount(-n)
	end
	if n < 10000 then
		return number(n)
	end

	local function tryUnit(scale, suffix)
		local scaled = n / scale
		if scaled >= 100 then
			local rounded = math.floor(scaled + 0.5)
			if rounded >= 1000 then
				return nil
			end
			return tostring(rounded) .. suffix
		end
		local rounded = math.floor(scaled * 10 + 0.5) / 10
		if rounded >= 100 then
			local asInt = math.floor(rounded + 0.5)
			if asInt >= 1000 then
				return nil
			end
			return tostring(asInt) .. suffix
		end
		return string.format("%.1f%s", rounded, suffix)
	end

	if n >= 1000000000 then
		return tryUnit(1000000000, "B") or "1.0T"
	end
	if n >= 1000000 then
		return tryUnit(1000000, "M") or tryUnit(1000000000, "B") or "1.0B"
	end
	return tryUnit(1000, "k") or tryUnit(1000000, "M") or number(n)
end

local function coinContent(parent, small)
    local content = make("Frame", parent, { Name = "CoinContent", BackgroundTransparency = 1,
        Position = UDim2.new(0,5,0,0), Size = UDim2.new(1,-10,1,0) })
    make("UIListLayout", content, { FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = small and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0,6), SortOrder = Enum.SortOrder.LayoutOrder })
    local icon = make("ImageLabel", content, { Name = "CoinIcon", BackgroundTransparency = 1,
        Size = UDim2.fromOffset(small and 18 or 28,small and 18 or 28), Image = AssetCodes.Get("Coin") or "", ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1 })
    local amount = label(content,"",UDim2.new(),UDim2.new(0,0,.75,0),15)
    amount.AutomaticSize = Enum.AutomaticSize.X
    amount.Font = Enum.Font.GothamBlack
    amount.TextScaled = false
    amount.LayoutOrder = 2
    amount.TextColor3 = Color3.new(1,1,1)
    make("UIStroke",amount,{Color=Color3.new(0,0,0),Transparency=.42,Thickness=1})
    return amount, icon
end

local function itemImage(item)
    if item.Category == "Weapon" then
        if type(AssetCodes.GetWeaponIcon) == "function" then
            return AssetCodes.GetWeaponIcon(item.WeaponName, item.EnchantName) or ""
        end
        return AssetCodes.Get(item.WeaponName) or ""
    end
    local icon = ItemIconRegistry.Get(item.IconKey) or ItemIconRegistry.Get(item.ItemId)
    if icon then
        if icon.IconAssetId and icon.IconAssetId ~= "" then return icon.IconAssetId end
        local asset = icon.AssetKey and AssetCodes.Get(icon.AssetKey)
        if asset and asset ~= "" then return asset end
    end
    return (item.IconKey and AssetCodes.Get(item.IconKey)) or ""
end

function MarketStallUI.Create(parent, options)
    local existing = parent:FindFirstChild("MarketStallRoot")
    if existing then return existing end
    local root = make("Frame", parent, { Name = "MarketStallRoot", Size = UDim2.fromScale(1,1),
        BackgroundTransparency = 1, Visible = false })
    callbacks[root] = options and options.onClose
    local panel = make("Frame", root, { Name = "Panel", AnchorPoint = Vector2.new(.5,.5),
        BackgroundColor3 = C.Panel, BorderSizePixel = 0 })
    round(panel, 22)
    -- Use the same gold outline as the primary menu windows.
    make("UIStroke", panel, { Color = Color3.fromRGB(255, 215, 80), Thickness = 2, Transparency = .1 })
    make("UIGradient", panel, { Color = ColorSequence.new(C.Top, C.Panel), Rotation = 90 })
    make("UIAspectRatioConstraint", panel, { AspectRatio = 1.4,
        AspectType = Enum.AspectType.FitWithinMaxSize, DominantAxis = Enum.DominantAxis.Width })
    local function layout()
        local camera = workspace.CurrentCamera
        local compact = camera and camera.ViewportSize.X < 760
        -- Match the potion stall's panel footprint and aspect constraint exactly.
        panel.Position = UDim2.fromScale(.5, compact and .51 or .52)
        panel.Size = UDim2.fromScale(compact and .94 or .7, compact and .86 or .8)
    end
    layout()
    label(panel, "MARKET", UDim2.fromScale(.025,.015), UDim2.fromScale(.4,.065), 28)
    local balancePill = make("Frame",panel,{Name="BalancePill",Position=UDim2.fromScale(.755,.02),
        Size=UDim2.fromScale(.15,.08),BackgroundColor3=Color3.fromRGB(18,23,37),BorderSizePixel=0})
    round(balancePill,14)
    make("UIStroke",balancePill,{Color=Color3.fromRGB(255,208,95),Thickness=1.2,Transparency=.28})
    local balanceIcon=make("ImageLabel",balancePill,{Name="CoinIcon",BackgroundTransparency=1,
        Position=UDim2.fromScale(.02,.25),Size=UDim2.fromScale(.5,.5),Image=AssetCodes.Get("Coin") or "",ScaleType=Enum.ScaleType.Fit})
    make("UIAspectRatioConstraint",balanceIcon,{AspectRatio=1})
    local balance=label(balancePill,"",UDim2.fromScale(.3,0),UDim2.fromScale(.6,1),18)
    balance.Font=Enum.Font.GothamBlack
    balance.TextColor3=Color3.fromRGB(255,208,95)
    balance:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize=50
    make("UIStroke",balance,{Color=Color3.new(0,0,0),Thickness=1,Transparency=.48})
    local close = button(panel, "X", UDim2.fromScale(.93,.02), UDim2.fromScale(.045,.055))
    close.Name = "CloseButton"
    -- Match the shared menu close-button feedback and its gold trim.
    local closeGold = Color3.fromRGB(255, 215, 80)
    local closeDefault = Color3.fromRGB(26, 30, 48)
    local closeHover = Color3.fromRGB(55, 30, 38)
    local closePress = Color3.fromRGB(18, 20, 32)
    close.BackgroundColor3 = closeDefault
    close.TextColor3 = closeGold
    close.Font = Enum.Font.GothamBlack
    local closeAspect = make("UIAspectRatioConstraint", close, { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height })
    local closeStroke = make("UIStroke", close, { Color = closeGold, Thickness = 1.2, Transparency = .4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    local closeTextConstraint = close:FindFirstChildOfClass("UITextSizeConstraint")
    if closeTextConstraint then
        closeTextConstraint.MinTextSize = 14
        closeTextConstraint.MaxTextSize = 26
    end
    close.MouseEnter:Connect(function()
        TweenService:Create(close, TweenInfo.new(.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = closeHover, TextColor3 = Color3.new(1,1,1) }):Play()
    end)
    close.MouseLeave:Connect(function()
        TweenService:Create(close, TweenInfo.new(.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = closeDefault, TextColor3 = closeGold }):Play()
    end)
    close.MouseButton1Down:Connect(function()
        TweenService:Create(close, TweenInfo.new(.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = closePress }):Play()
    end)
    close.MouseButton1Up:Connect(function()
        TweenService:Create(close, TweenInfo.new(.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = closeHover }):Play()
    end)
    close.Activated:Connect(function()
        if callbacks[root] then callbacks[root]() else root.Visible = false end
    end)
    local timers = {}
    local scroll = make("ScrollingFrame", panel, { Name = "Items", Position = UDim2.fromScale(.025,.12),
        Size = UDim2.fromScale(.63,.82), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y })
    make("UIListLayout", scroll, { Padding = UDim.new(0,14), SortOrder = Enum.SortOrder.LayoutOrder })
    local details = make("Frame", panel, { Position = UDim2.fromScale(.675,.12), Size = UDim2.fromScale(.3,.82),
        BackgroundColor3 = C.Surface, BorderSizePixel = 0 })
    round(details)
    local viewport = make("ViewportFrame", details, { Position = UDim2.fromScale(.04,.03),
        Size = UDim2.fromScale(.92,.49), BackgroundTransparency = 1,
        Ambient = Color3.fromRGB(200,200,200), LightColor = Color3.new(1,1,1) })
    local preview = Preview.new(viewport)
    local detailImage = make("ImageLabel", details, { BackgroundTransparency = 1,
        Position = viewport.Position, Size = viewport.Size, ScaleType = Enum.ScaleType.Fit, Visible = false })
    local detailRarity = label(details,"",UDim2.fromScale(.06,.67),UDim2.fromScale(.88,.045),15)
    local detailSize = label(details,"",UDim2.fromScale(.06,.72),UDim2.fromScale(.88,.045),15)
    local detailEnchant = label(details,"",UDim2.fromScale(.06,.77),UDim2.fromScale(.88,.045),15)
    local name = label(details, "Select an item", UDim2.fromScale(.06,.54), UDim2.fromScale(.88,.12), 22)
    local description = label(details, "", UDim2.fromScale(.06,.67), UDim2.fromScale(.88,.16), 15)
    description.TextColor3 = C.Muted
    local action = button(details, "", UDim2.fromScale(.06,.85), UDim2.fromScale(.88,.11))
    local actionValue, actionIcon = coinContent(action)
    local actionStroke = make("UIStroke",action,{Color=Color3.new(1,1,1),Thickness=1.2,Transparency=.35})
    local status = label(panel, "", UDim2.fromScale(.025,.955), UDim2.fromScale(.95,.035), 13)
    local statusVersion = 0
    local function showStatus(text)
        statusVersion += 1
        local version = statusVersion
        status.TextTransparency = 0
        status.Text = text
        task.delay(5, function()
            if version ~= statusVersion or not status.Parent then return end
            local fade = TweenService:Create(status, TweenInfo.new(.35), {TextTransparency = 1})
            fade.Completed:Once(function()
                if version == statusVersion and status.Parent then status.Text = "" end
            end)
            fade:Play()
        end)
    end
    local connections, cards = {}, {}
    local market, selected, selectedCycle
    local coinBalance = 0
    local ownedTrails, ownedEmotes, equippedEmotes = {}, {}, {}
    local equippedTrail = nil
    local requesting = false
    local remotes = RS:WaitForChild("Remotes")
    local marketRemotes = remotes:WaitForChild("Market")
    local effects = remotes:WaitForChild("Effects")
    local emotes = remotes:WaitForChild("Emotes")
    local getMarket = marketRemotes:WaitForChild("GetState")
    local buyWeapon = marketRemotes:WaitForChild("PurchaseWeapon")
    local buyPotion = marketRemotes:WaitForChild("PurchasePotion")

    local function potionRemaining(item)
        return market and market.PotionRemaining and market.PotionRemaining[tostring(item.Slot)] or 0
    end

    local function emoteSlot(id)
        for slot, emote in pairs(equippedEmotes) do if emote == id then return tonumber(slot) end end
    end
    local function owned(item)
        if item.Category == "Weapon" then return market and market.Purchased[tostring(item.Slot)] == true end
        return item.IsFree or (item.Category == "Trail" and ownedTrails[item.Id])
            or (item.Category == "Emote" and ownedEmotes[item.Id])
    end
    local function actionText(item)
        if item.Category == "Potion" then
            if not market or not market.Ready then return "LOADING..." end
            if potionRemaining(item)<=0 then return "SOLD OUT" end
        elseif item.Category == "Weapon" then
            if owned(item) then return "PURCHASED" end
            if not market or not market.Ready then return "LOADING..." end
        elseif owned(item) then
            if item.Category == "Trail" then return "PURCHASED" end
            return emoteSlot(item.Id) and "UNEQUIP" or "EQUIP"
        end
        return number(item.CoinPrice) .. " COINS"
    end
    local function updateLabels()
        for _,record in ipairs(cards) do
            local text = actionText(record.item)
            record.status.Text = text == number(record.item.CoinPrice) .. " COINS" and "" or text
            if record.stock then record.stock.Text = tostring(potionRemaining(record.item)) .. " in stock" end
        end
        if selected then
            local text=actionText(selected)
            local purchasing=text==number(selected.CoinPrice).." COINS"
            actionValue.Text=purchasing and number(selected.CoinPrice) or text
            actionIcon.Visible=purchasing
            local affordable=coinBalance >= (selected.CoinPrice or 0)
            action.BackgroundColor3=purchasing and (affordable and C.PurchaseGreen or Color3.fromRGB(73,96,70)) or C.Card
            action.BackgroundTransparency=purchasing and not affordable and .12 or 0
            actionValue.TextTransparency=purchasing and not affordable and .18 or 0
            actionStroke.Transparency=purchasing and .35 or .55
            if requesting and selected.Category ~= "Trail" then actionValue.Text="PROCESSING..."; actionIcon.Visible=false end
        end
    end
    local function selectItem(item)
        selected, selectedCycle = item, market and market.Cycle
        name.Text = item.DisplayName
        local isWeapon = item.Category == "Weapon"
        local isImage = isWeapon or item.Category == "Potion"
        description.Visible = not isWeapon
        description.Text = item.Category == "Potion" and (item.Description or "") or ""
        detailRarity.Visible, detailSize.Visible, detailEnchant.Visible = isWeapon, isWeapon, isWeapon
        if isWeapon then
            detailRarity.Text = item.Rarity
            detailRarity.TextColor3 = RarityStyles.GetColor(item.Rarity)
            EnchantTextStyler.ApplySize(detailSize,item.SizeTier,item.SizeTier.." "..item.SizePercent.."%")
            EnchantTextStyler.Apply(detailEnchant, item.EnchantName)
        end
        detailImage.Visible, viewport.Visible = isImage, not isImage
        if isImage then detailImage.Image = itemImage(item) end
        if root.Visible then
            if isImage then preview:Stop() else preview:ShowItem(item) end
        end
        updateLabels()
    end
    local function section(title, items, order)
        local container = make("Frame", scroll, { Size = UDim2.new(1,-8,0,0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1, LayoutOrder = order })
        make("UIListLayout", container, { Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder })
        local header = make("Frame",container,{Size=UDim2.new(1,0,0,28),BackgroundTransparency=1,LayoutOrder=0})
        label(header,title,UDim2.new(),UDim2.fromScale(.5,1),21)
        if title=="WEAPONS" or title=="POTIONS" then
            local timer=label(header,"",UDim2.fromScale(.5,0),UDim2.fromScale(.5,1),14)
            timer.TextColor3=C.Muted
            timer.TextXAlignment=Enum.TextXAlignment.Right
            table.insert(timers,timer)
        end
        for index,item in ipairs(items) do
            local card = button(container, "", UDim2.new(), UDim2.new(1,0,0,item.Category == "Weapon" and 132 or (item.Category=="Potion" and 106 or 74)))
            card.LayoutOrder = index
            local outline = make("UIStroke", card, { Color = C.Stroke, Thickness = 1, Transparency = .55 })
            local titleLabel = label(card,item.DisplayName,UDim2.fromScale(.04,.08),UDim2.fromScale(.7,.27),18)
            if item.Category == "Weapon" then
                outline.Color = RarityStyles.GetColor(item.Rarity)
                local rarity=label(card,item.Rarity,UDim2.fromScale(.04,.35),UDim2.fromScale(.68,.14),14)
                rarity.TextColor3=RarityStyles.GetColor(item.Rarity)
                local size=label(card,"",UDim2.fromScale(.04,.51),UDim2.fromScale(.68,.14),14)
                EnchantTextStyler.ApplySize(size,item.SizeTier,item.SizeTier.." "..item.SizePercent.."%")
                if item.EnchantName and item.EnchantName~="" then
                    local enchant=label(card,"",UDim2.fromScale(.04,.67),UDim2.fromScale(.68,.13),14)
                    EnchantTextStyler.Apply(enchant, item.EnchantName)
                end
            elseif item.Category == "Trail" then
                -- The swatch depicts the trail itself, never ownership or rarity.
                local swatch = make("Frame",card,{ Position=UDim2.fromScale(.86,.22),Size=UDim2.fromScale(.1,.14),
                    BackgroundColor3=(item.IsTeamTrail or item.TrailColorSequence) and Color3.new(1,1,1) or item.Color or C.Text,BorderSizePixel=0 })
                round(swatch,4)
                if item.TrailColorSequence then make("UIGradient",swatch,{Color=item.TrailColorSequence})
                elseif item.IsTeamTrail then make("UIGradient",swatch,{Color=ColorSequence.new({
                    ColorSequenceKeypoint.new(0,Color3.fromRGB(45,125,255)), ColorSequenceKeypoint.new(.499,Color3.fromRGB(45,125,255)),
                    ColorSequenceKeypoint.new(.501,Color3.fromRGB(230,60,60)), ColorSequenceKeypoint.new(1,Color3.fromRGB(230,60,60)),
                })}) end
                titleLabel.Size = UDim2.fromScale(.78,.39)
            end
            -- No emote icons, cosmetic subtitles, rarity labels, or ownership-colored backgrounds.
            if item.Category == "Weapon" or item.Category == "Potion" then
                make("ImageLabel",card,{BackgroundTransparency=1,Position=UDim2.fromScale(.76,.1),
                    Size=UDim2.fromScale(.2,.65),ScaleType=Enum.ScaleType.Fit,Image=itemImage(item)})
            end
            local priceRow=make("Frame",card,{BackgroundTransparency=1,
                Position=UDim2.fromScale(.03,item.Category=="Weapon" and .82 or .7),Size=UDim2.fromScale(.45,.18)})
            local priceValue=coinContent(priceRow,true)
            priceValue.Text=number(item.CoinPrice)
            local price=label(card,"",UDim2.fromScale(.5,item.Category=="Weapon" and .82 or .7),UDim2.fromScale(.46,.18),13)
            price.TextColor3=C.Muted
            price.TextXAlignment=Enum.TextXAlignment.Right
            local stock
            if item.Category=="Potion" then
                stock=label(card,"",UDim2.fromScale(.04,.45),UDim2.fromScale(.92,.2),14)
                stock.TextColor3=C.Muted
            end
            table.insert(cards,{item=item,status=price,stock=stock})
            card.Activated:Connect(function() selectItem(item) end)
        end
    end
    local function rebuild()
        local scrollPosition = scroll.CanvasPosition
        for _,child in ipairs(scroll:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        cards = {}
        timers = {}
        section("WEAPONS", market and market.Offers or {}, 1)
        section("POTIONS", market and market.PotionOffers or {}, 2)
        section("TRAILS", Catalog.GetItemsByCategory("Trail"), 3)
        section("EMOTES", Catalog.GetItemsByCategory("Emote"), 4)
        if selected and selected.Category == "Potion" and market and market.PotionOffers then selectItem(market.PotionOffers[selected.Slot])
        elseif selected and selected.Category ~= "Weapon" then selectItem(selected)
        elseif market and market.Offers[1] then selectItem(market.Offers[selected and selected.Slot or 1] or market.Offers[1]) end
        scroll.CanvasPosition = scrollPosition
    end
    local function applyState(data)
        if type(data) ~= "table" then return end
        if market and data.Cycle < market.Cycle then return end
        local sameCycle = market and market.Cycle == data.Cycle and #cards > 0
        market = data
        if sameCycle then updateLabels() else rebuild() end
    end
    local function syncCosmetics()
        local ok, list = invoke(effects:WaitForChild("GetOwnedEffects"))
        if ok then ownedTrails = idSet(list) end
        ok,list = invoke(emotes:WaitForChild("GetOwnedEmotes"))
        if ok then ownedEmotes = idSet(list) end
        ok,list = invoke(effects:WaitForChild("GetEquippedEffects"))
        if ok and type(list)=="table" then equippedTrail = list.DashTrail end
        ok,list = invoke(emotes:WaitForChild("GetEquippedEmotes"))
        if ok and type(list)=="table" then equippedEmotes = emoteLoadout(list) end
        updateLabels()
    end
    local function refreshMarket()
        local ok, data = invoke(getMarket)
        if ok then applyState(data) end
        local coinsOk, coins = invoke(RS:WaitForChild("GetCoins"))
        if coinsOk then coinBalance=tonumber(coins) or 0; balance.Text=formatCompactCount(coinBalance); updateLabels() end
    end
    action.Activated:Connect(function()
        if requesting or not selected then return end
        requesting = true
        updateLabels()
        local item, cycle = selected, selectedCycle
        local ok, success, response, extra
        if item.Category=="Weapon" or item.Category=="Potion" then
            ok,success,response,extra = invoke(item.Category=="Potion" and buyPotion or buyWeapon,cycle,item.Slot)
            if type(extra)=="table" then applyState(extra) end
            showStatus(ok and tostring(response or "") or "Purchase failed; please retry")
        elseif not owned(item) then
            if item.Category == "Trail" then ownedTrails[item.Id] = true; updateLabels() end
            local folder = item.Category=="Trail" and effects or emotes
            local remoteName = item.Category=="Trail" and "PurchaseEffect" or "PurchaseEmote"
            ok,success,response,extra = invoke(folder:WaitForChild(remoteName),item.Id)
            showStatus(ok and success and ("Purchased "..item.DisplayName) or tostring(extra or "Purchase failed"))
            if not (ok and success) and item.Category == "Trail" then ownedTrails[item.Id] = nil end
            if ok and success then
                if item.Category=="Trail" then ownedTrails[item.Id]=true else ownedEmotes[item.Id]=true end
            end
        else
            if item.Category=="Trail" then return
            elseif emoteSlot(item.Id) then emotes:WaitForChild("UnequipEmote"):FireServer(emoteSlot(item.Id))
            else
                local count=0
                for _ in pairs(equippedEmotes) do count+=1 end
                if count<Catalog.GetSlotCount() then emotes:WaitForChild("EquipEmote"):FireServer(item.Id)
                else showStatus("All emote slots are full") end
            end
        end
        if ok and success then ClaimSound.Play() end
        requesting=false
        updateLabels()
    end)
    table.insert(connections,marketRemotes:WaitForChild("StateChanged").OnClientEvent:Connect(function(data)
        applyState(data)
    end))
    table.insert(connections,effects:WaitForChild("EquippedEffectsChanged").OnClientEvent:Connect(function(data)
        equippedTrail=type(data)=="table" and data.DashTrail or nil; updateLabels()
    end))
    table.insert(connections,effects:WaitForChild("OwnedEffectsChanged").OnClientEvent:Connect(function(list)
        ownedTrails=idSet(list); updateLabels()
    end))
    table.insert(connections,emotes:WaitForChild("EquippedEmotesChanged").OnClientEvent:Connect(function(data)
        equippedEmotes=emoteLoadout(data); updateLabels()
    end))
    table.insert(connections,RS:WaitForChild("CoinsUpdated").OnClientEvent:Connect(function(coins)
        coinBalance=tonumber(coins) or 0
        balance.Text=formatCompactCount(coinBalance)
        updateLabels()
    end))
    root:GetPropertyChangedSignal("Visible"):Connect(function()
        if root.Visible then
            task.spawn(function() refreshMarket(); syncCosmetics() end)
            if selected then selectItem(selected) end
        else preview:Stop() end
    end)
    local elapsed=0
    local lastRefresh=0
    table.insert(connections,RunService.Heartbeat:Connect(function(dt)
        elapsed+=dt
        if elapsed<1 then return end
        elapsed=0; layout()
        if market then
            local left=math.max(0,math.ceil(market.RefreshAt-workspace:GetServerTimeNow()))
            for _,timer in ipairs(timers) do
                timer.Text=string.format("Refreshes in %02d:%02d",math.floor(left/60),left%60)
            end
        end
        if root.Visible and not requesting and os.clock()-lastRefresh>=5
            and (not market or not market.Ready or market.RefreshAt<=workspace:GetServerTimeNow()) then
            lastRefresh=os.clock()
            task.spawn(refreshMarket)
        end
    end))
    root.Destroying:Connect(function()
        preview:Stop()
        for _,connection in ipairs(connections) do connection:Disconnect() end
    end)
    task.spawn(function() refreshMarket(); syncCosmetics() end)
    return root
end

return MarketStallUI
