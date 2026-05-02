--------------------------------------------------------------------------------
-- EventAtmosphereController.lua
--
-- Client-side event atmosphere controller. It owns temporary Lighting/Sky/
-- Atmosphere changes for timed events and restores the player's previous
-- client Lighting state when the event ends.
--------------------------------------------------------------------------------

local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")
local Debris            = game:GetService("Debris")

local EventAtmosphereController = {}

local TWEEN_IN_SECONDS = 2.8
local TWEEN_OUT_SECONDS = 2.4

local LIGHTING_CACHE_PROPS = {
    "ClockTime",
    "TimeOfDay",
    "Brightness",
    "Ambient",
    "OutdoorAmbient",
    "ColorShift_Top",
    "ColorShift_Bottom",
    "FogColor",
    "FogStart",
    "FogEnd",
    "ExposureCompensation",
    "EnvironmentDiffuseScale",
    "EnvironmentSpecularScale",
}

local SKY_CACHE_PROPS = {
    "SkyboxBk",
    "SkyboxDn",
    "SkyboxFt",
    "SkyboxLf",
    "SkyboxRt",
    "SkyboxUp",
    "CelestialBodiesShown",
    "StarCount",
    "SunAngularSize",
    "MoonAngularSize",
    "SunTextureId",
    "MoonTextureId",
}

local ATMOSPHERE_CACHE_PROPS = {
    "Density",
    "Offset",
    "Color",
    "Decay",
    "Glare",
    "Haze",
}

local METEOR_LIGHTING_TARGET = {
    ClockTime = 22.75,
    Brightness = 1.25,
    Ambient = Color3.fromRGB(50, 58, 78),
    OutdoorAmbient = Color3.fromRGB(66, 76, 100),
    ColorShift_Top = Color3.fromRGB(34, 54, 92),
    ColorShift_Bottom = Color3.fromRGB(0, 0, 14),
    FogColor = Color3.fromRGB(18, 24, 42),
    FogStart = 170,
    FogEnd = 950,
    ExposureCompensation = -0.18,
    EnvironmentDiffuseScale = 0.42,
    EnvironmentSpecularScale = 0.35,
}

local METEOR_SKY_TARGET = {
    CelestialBodiesShown = true,
    StarCount = 3000,
    SunAngularSize = 0,
    MoonAngularSize = 14,
}

local METEOR_ATMOSPHERE_TARGET = {
    Density = 0.22,
    Offset = 0.18,
    Color = Color3.fromRGB(86, 102, 132),
    Decay = Color3.fromRGB(28, 34, 58),
    Glare = 0.04,
    Haze = 1.15,
}

local GOLD_RUSH_LIGHTING_TARGET = {
    ClockTime = 17.25,
    Brightness = 2.15,
    Ambient = Color3.fromRGB(112, 82, 44),
    OutdoorAmbient = Color3.fromRGB(136, 100, 56),
    ColorShift_Top = Color3.fromRGB(255, 196, 92),
    ColorShift_Bottom = Color3.fromRGB(84, 42, 10),
    FogColor = Color3.fromRGB(150, 104, 54),
    FogStart = 210,
    FogEnd = 1150,
    ExposureCompensation = 0.12,
    EnvironmentDiffuseScale = 0.62,
    EnvironmentSpecularScale = 0.56,
}

local GOLD_RUSH_SKY_TARGET = {
    CelestialBodiesShown = true,
    StarCount = 0,
    SunAngularSize = 16,
    MoonAngularSize = 0,
}

local GOLD_RUSH_ATMOSPHERE_TARGET = {
    Density = 0.16,
    Offset = 0.12,
    Color = Color3.fromRGB(188, 136, 70),
    Decay = Color3.fromRGB(105, 62, 24),
    Glare = 0.08,
    Haze = 0.82,
}

local activeState = nil
local restoreSerial = 0
local activeTweens = {}

local function safeGet(instance, propertyName)
    local success, value = pcall(function()
        return instance[propertyName]
    end)
    if success then return value end
    return nil
end

local function safeSet(instance, propertyName, value)
    pcall(function()
        instance[propertyName] = value
    end)
end

local function cacheProperties(instance, propertyNames)
    if not instance then return nil end
    local result = {}
    for _, propertyName in ipairs(propertyNames) do
        local value = safeGet(instance, propertyName)
        if value ~= nil then
            result[propertyName] = value
        end
    end
    return result
end

local function applyProperties(instance, propertyValues)
    if not instance or type(propertyValues) ~= "table" then return end
    for propertyName, value in pairs(propertyValues) do
        safeSet(instance, propertyName, value)
    end
end

local function stopActiveTweens()
    for _, tween in ipairs(activeTweens) do
        pcall(function() tween:Cancel() end)
    end
    table.clear(activeTweens)
end

local function tweenProperties(instance, targetProperties, duration)
    if not instance or type(targetProperties) ~= "table" then return nil end

    local filtered = {}
    for propertyName, value in pairs(targetProperties) do
        if safeGet(instance, propertyName) ~= nil then
            filtered[propertyName] = value
        end
    end

    if not next(filtered) then return nil end

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
    local tween = TweenService:Create(instance, tweenInfo, filtered)
    table.insert(activeTweens, tween)
    tween:Play()
    return tween
end

local function findEventAsset(eventIdOrClassName, maybeClassName)
    local eventId = maybeClassName and eventIdOrClassName or "MeteorShower"
    local className = maybeClassName or eventIdOrClassName
    local eventAssets = ReplicatedStorage:FindFirstChild("EventAssets")
    local eventFolder = eventAssets and eventAssets:FindFirstChild(eventId)
    local asset = eventFolder and eventFolder:FindFirstChild(className)
    if asset and asset:IsA(className) then
        return asset
    end
    return nil
end

local function captureState()
    local originalSky = Lighting:FindFirstChildOfClass("Sky")
    local originalAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

    return {
        lightingProps = cacheProperties(Lighting, LIGHTING_CACHE_PROPS),
        originalSky = originalSky,
        originalSkyParent = originalSky and originalSky.Parent or nil,
        originalSkyProps = cacheProperties(originalSky, SKY_CACHE_PROPS),
        originalAtmosphere = originalAtmosphere,
        originalAtmosphereParent = originalAtmosphere and originalAtmosphere.Parent or nil,
        originalAtmosphereProps = cacheProperties(originalAtmosphere, ATMOSPHERE_CACHE_PROPS),
    }
end

local function applyMeteorSky(state)
    local customSky = findEventAsset("Sky")
    if customSky then
        if state.cache.originalSky and state.cache.originalSky.Parent == Lighting then
            state.originalSkyHidden = true
            state.cache.originalSky.Parent = nil
        end

        local skyClone = customSky:Clone()
        skyClone.Name = "MeteorShowerSky_Client"
        skyClone.Parent = Lighting
        state.tempSky = skyClone
        return
    end

    local existingSky = state.cache.originalSky
    if existingSky then
        state.modifiedSky = existingSky
        applyProperties(existingSky, METEOR_SKY_TARGET)
        return
    end

    local tempSky = Instance.new("Sky")
    tempSky.Name = "MeteorShowerSky_Client"
    applyProperties(tempSky, METEOR_SKY_TARGET)
    tempSky.Parent = Lighting
    state.tempSky = tempSky
end

local function applyMeteorAtmosphere(state)
    local customAtmosphere = findEventAsset("Atmosphere")
    if customAtmosphere then
        if state.cache.originalAtmosphere and state.cache.originalAtmosphere.Parent == Lighting then
            state.originalAtmosphereHidden = true
            state.cache.originalAtmosphere.Parent = nil
        end

        local atmosphereClone = customAtmosphere:Clone()
        atmosphereClone.Name = "MeteorShowerAtmosphere_Client"
        local targetProps = cacheProperties(atmosphereClone, ATMOSPHERE_CACHE_PROPS)
        applyProperties(atmosphereClone, {
            Density = 0,
            Glare = 0,
            Haze = 0,
        })
        atmosphereClone.Parent = Lighting
        state.tempAtmosphere = atmosphereClone
        tweenProperties(atmosphereClone, targetProps, TWEEN_IN_SECONDS)
        return
    end

    local existingAtmosphere = state.cache.originalAtmosphere
    if existingAtmosphere then
        state.modifiedAtmosphere = existingAtmosphere
        tweenProperties(existingAtmosphere, METEOR_ATMOSPHERE_TARGET, TWEEN_IN_SECONDS)
        return
    end

    local tempAtmosphere = Instance.new("Atmosphere")
    tempAtmosphere.Name = "MeteorShowerAtmosphere_Client"
    applyProperties(tempAtmosphere, {
        Density = 0,
        Offset = METEOR_ATMOSPHERE_TARGET.Offset,
        Color = METEOR_ATMOSPHERE_TARGET.Color,
        Decay = METEOR_ATMOSPHERE_TARGET.Decay,
        Glare = 0,
        Haze = 0,
    })
    tempAtmosphere.Parent = Lighting
    state.tempAtmosphere = tempAtmosphere
    tweenProperties(tempAtmosphere, METEOR_ATMOSPHERE_TARGET, TWEEN_IN_SECONDS)
end

local function applyGoldRushSky(state)
    local customSky = findEventAsset("GoldRush", "Sky")
    if customSky then
        if state.cache.originalSky and state.cache.originalSky.Parent == Lighting then
            state.originalSkyHidden = true
            state.cache.originalSky.Parent = nil
        end

        local skyClone = customSky:Clone()
        skyClone.Name = "GoldRushSky_Client"
        skyClone.Parent = Lighting
        state.tempSky = skyClone
        return
    end

    local existingSky = state.cache.originalSky
    if existingSky then
        state.modifiedSky = existingSky
        applyProperties(existingSky, GOLD_RUSH_SKY_TARGET)
        return
    end

    local tempSky = Instance.new("Sky")
    tempSky.Name = "GoldRushSky_Client"
    applyProperties(tempSky, GOLD_RUSH_SKY_TARGET)
    tempSky.Parent = Lighting
    state.tempSky = tempSky
end

local function applyGoldRushAtmosphere(state)
    local customAtmosphere = findEventAsset("GoldRush", "Atmosphere")
    if customAtmosphere then
        if state.cache.originalAtmosphere and state.cache.originalAtmosphere.Parent == Lighting then
            state.originalAtmosphereHidden = true
            state.cache.originalAtmosphere.Parent = nil
        end

        local atmosphereClone = customAtmosphere:Clone()
        atmosphereClone.Name = "GoldRushAtmosphere_Client"
        local targetProps = cacheProperties(atmosphereClone, ATMOSPHERE_CACHE_PROPS)
        applyProperties(atmosphereClone, {
            Density = 0,
            Glare = 0,
            Haze = 0,
        })
        atmosphereClone.Parent = Lighting
        state.tempAtmosphere = atmosphereClone
        tweenProperties(atmosphereClone, targetProps, TWEEN_IN_SECONDS)
        return
    end

    local existingAtmosphere = state.cache.originalAtmosphere
    if existingAtmosphere then
        state.modifiedAtmosphere = existingAtmosphere
        tweenProperties(existingAtmosphere, GOLD_RUSH_ATMOSPHERE_TARGET, TWEEN_IN_SECONDS)
        return
    end

    local tempAtmosphere = Instance.new("Atmosphere")
    tempAtmosphere.Name = "GoldRushAtmosphere_Client"
    applyProperties(tempAtmosphere, {
        Density = 0,
        Offset = GOLD_RUSH_ATMOSPHERE_TARGET.Offset,
        Color = GOLD_RUSH_ATMOSPHERE_TARGET.Color,
        Decay = GOLD_RUSH_ATMOSPHERE_TARGET.Decay,
        Glare = 0,
        Haze = 0,
    })
    tempAtmosphere.Parent = Lighting
    state.tempAtmosphere = tempAtmosphere
    tweenProperties(tempAtmosphere, GOLD_RUSH_ATMOSPHERE_TARGET, TWEEN_IN_SECONDS)
end

local function spawnMeteorStreak(parent)
    local camera = workspace.CurrentCamera
    if not camera or not parent or not parent.Parent then return end

    local cameraCFrame = camera.CFrame
    local localOffset = Vector3.new(
        math.random(-180, 180),
        math.random(95, 165),
        -math.random(220, 420)
    )
    local startPosition = cameraCFrame:PointToWorldSpace(localOffset)
    local direction = (
        cameraCFrame.RightVector * math.random(-25, 25)
        + Vector3.new(math.random(-18, 18), -math.random(70, 110), math.random(-35, 20))
    ).Unit

    local streak = Instance.new("Part")
    streak.Name = "MeteorAtmosphereStreak"
    streak.Anchored = true
    streak.CanCollide = false
    streak.CanQuery = false
    streak.CanTouch = false
    streak.CastShadow = false
    streak.Material = Enum.Material.Neon
    streak.Color = Color3.fromRGB(160, 205, 255)
    streak.Transparency = 0.48
    streak.Size = Vector3.new(0.12, 0.12, math.random(42, 70))
    streak.CFrame = CFrame.lookAt(startPosition, startPosition + direction)
    streak.Parent = parent

    local endPosition = startPosition + direction * math.random(95, 145)
    local tween = TweenService:Create(
        streak,
        TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            CFrame = CFrame.lookAt(endPosition, endPosition + direction),
            Transparency = 1,
        }
    )
    tween:Play()
    Debris:AddItem(streak, 1.1)
end

local function spawnDistantFlash(parent)
    local camera = workspace.CurrentCamera
    if not camera or not parent or not parent.Parent then return end

    local startPosition = camera.CFrame:PointToWorldSpace(Vector3.new(
        math.random(-220, 220),
        math.random(120, 190),
        -math.random(260, 480)
    ))

    local flash = Instance.new("Part")
    flash.Name = "MeteorAtmosphereFlash"
    flash.Shape = Enum.PartType.Ball
    flash.Anchored = true
    flash.CanCollide = false
    flash.CanQuery = false
    flash.CanTouch = false
    flash.CastShadow = false
    flash.Material = Enum.Material.Neon
    flash.Color = Color3.fromRGB(170, 215, 255)
    flash.Transparency = 0.72
    flash.Size = Vector3.new(6, 6, 6)
    flash.CFrame = CFrame.new(startPosition)
    flash.Parent = parent

    local tween = TweenService:Create(
        flash,
        TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Size = Vector3.new(22, 22, 22),
            Transparency = 1,
        }
    )
    tween:Play()
    Debris:AddItem(flash, 0.8)
end

local function spawnGoldRushMote(parent)
    local camera = workspace.CurrentCamera
    if not camera or not parent or not parent.Parent then return end

    local startPosition = camera.CFrame:PointToWorldSpace(Vector3.new(
        math.random(-180, 180),
        math.random(38, 125),
        -math.random(80, 260)
    ))
    local drift = Vector3.new(math.random(-18, 18), math.random(10, 34), math.random(-12, 12))

    local mote = Instance.new("Part")
    mote.Name = "GoldRushAtmosphereMote"
    mote.Shape = Enum.PartType.Ball
    mote.Anchored = true
    mote.CanCollide = false
    mote.CanQuery = false
    mote.CanTouch = false
    mote.CastShadow = false
    mote.Material = Enum.Material.Neon
    mote.Color = Color3.fromRGB(255, 214, 95)
    mote.Transparency = 0.5
    local size = math.random(5, 11) / 10
    mote.Size = Vector3.new(size, size, size)
    mote.CFrame = CFrame.new(startPosition)
    mote.Parent = parent

    local tween = TweenService:Create(
        mote,
        TweenInfo.new(math.random(16, 26) / 10, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
        {
            CFrame = CFrame.new(startPosition + drift),
            Transparency = 1,
        }
    )
    tween:Play()
    Debris:AddItem(mote, 3)
end

local function spawnGoldRushGlint(parent)
    local camera = workspace.CurrentCamera
    if not camera or not parent or not parent.Parent then return end

    local startPosition = camera.CFrame:PointToWorldSpace(Vector3.new(
        math.random(-220, 220),
        math.random(75, 150),
        -math.random(160, 360)
    ))

    local glint = Instance.new("Part")
    glint.Name = "GoldRushAtmosphereGlint"
    glint.Anchored = true
    glint.CanCollide = false
    glint.CanQuery = false
    glint.CanTouch = false
    glint.CastShadow = false
    glint.Material = Enum.Material.Neon
    glint.Color = Color3.fromRGB(255, 235, 145)
    glint.Transparency = 0.38
    glint.Size = Vector3.new(0.16, 0.16, math.random(12, 24))
    glint.CFrame = CFrame.lookAt(startPosition, startPosition + camera.CFrame.RightVector)
    glint.Parent = parent

    local endPosition = startPosition + camera.CFrame.RightVector * math.random(20, 42)
    local tween = TweenService:Create(
        glint,
        TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            CFrame = CFrame.lookAt(endPosition, endPosition + camera.CFrame.RightVector),
            Transparency = 1,
        }
    )
    tween:Play()
    Debris:AddItem(glint, 0.8)
end

local function startLocalWeatherEffects(state)
    local parent = workspace.CurrentCamera or workspace
    local folder = Instance.new("Folder")
    folder.Name = tostring(state.eventId or "Event") .. "AtmosphereClient"
    folder.Parent = parent
    state.effectsFolder = folder

    state.effectsThread = task.spawn(function()
        task.wait(1.2)
        while activeState == state and folder.Parent do
            if state.eventId == "GoldRush" then
                for _ = 1, math.random(2, 4) do
                    spawnGoldRushMote(folder)
                end
                if math.random() < 0.28 then
                    spawnGoldRushGlint(folder)
                end
                task.wait(math.random(12, 24) / 10)
            else
                spawnMeteorStreak(folder)
                if math.random() < 0.18 then
                    spawnDistantFlash(folder)
                end
                task.wait(math.random(26, 58) / 10)
            end
        end
    end)
end

local function stopLocalWeatherEffects(state)
    if not state then return end
    if state.effectsThread then
        pcall(task.cancel, state.effectsThread)
        state.effectsThread = nil
    end
    if state.effectsFolder then
        pcall(function() state.effectsFolder:Destroy() end)
        state.effectsFolder = nil
    end
end

local function finishRestore(state)
    if not state then return end

    if state.tempSky then
        pcall(function() state.tempSky:Destroy() end)
        state.tempSky = nil
    end
    if state.originalSkyHidden and state.cache.originalSky then
        state.cache.originalSky.Parent = state.cache.originalSkyParent or Lighting
    elseif state.modifiedSky and state.cache.originalSkyProps then
        applyProperties(state.modifiedSky, state.cache.originalSkyProps)
    end

    if state.tempAtmosphere then
        pcall(function() state.tempAtmosphere:Destroy() end)
        state.tempAtmosphere = nil
    end
    if state.originalAtmosphereHidden and state.cache.originalAtmosphere then
        state.cache.originalAtmosphere.Parent = state.cache.originalAtmosphereParent or Lighting
    end

    if state.cache.lightingProps and state.cache.lightingProps.TimeOfDay then
        safeSet(Lighting, "TimeOfDay", state.cache.lightingProps.TimeOfDay)
    end
end

function EventAtmosphereController.Start(eventId)
    if eventId ~= "MeteorShower" and eventId ~= "GoldRush" then
        EventAtmosphereController.Stop()
        return
    end

    if activeState and activeState.eventId == eventId then
        return
    end

    if activeState then
        EventAtmosphereController.Stop(nil, 0)
    end

    restoreSerial += 1
    stopActiveTweens()

    local state = {
        eventId = eventId,
        cache = captureState(),
    }
    activeState = state

    if eventId == "GoldRush" then
        tweenProperties(Lighting, GOLD_RUSH_LIGHTING_TARGET, TWEEN_IN_SECONDS)
        applyGoldRushSky(state)
        applyGoldRushAtmosphere(state)
    else
        tweenProperties(Lighting, METEOR_LIGHTING_TARGET, TWEEN_IN_SECONDS)
        applyMeteorSky(state)
        applyMeteorAtmosphere(state)
    end
    startLocalWeatherEffects(state)
end

function EventAtmosphereController.Stop(_eventId, duration)
    local state = activeState
    if not state then return end

    activeState = nil
    restoreSerial += 1
    local currentRestoreSerial = restoreSerial
    stopActiveTweens()
    stopLocalWeatherEffects(state)

    local restoreDuration = duration
    if restoreDuration == nil then restoreDuration = TWEEN_OUT_SECONDS end

    local lightingProps = state.cache.lightingProps or {}
    local lightingTarget = {}
    for propertyName, value in pairs(lightingProps) do
        if propertyName ~= "TimeOfDay" then
            lightingTarget[propertyName] = value
        end
    end

    if state.modifiedAtmosphere and state.cache.originalAtmosphereProps then
        tweenProperties(state.modifiedAtmosphere, state.cache.originalAtmosphereProps, restoreDuration)
    elseif state.tempAtmosphere then
        tweenProperties(state.tempAtmosphere, { Density = 0, Glare = 0, Haze = 0 }, restoreDuration)
    end

    if restoreDuration <= 0 then
        if state.modifiedAtmosphere and state.cache.originalAtmosphereProps then
            applyProperties(state.modifiedAtmosphere, state.cache.originalAtmosphereProps)
        end
        applyProperties(Lighting, lightingTarget)
        finishRestore(state)
        return
    end

    local lightingTween = tweenProperties(Lighting, lightingTarget, restoreDuration)
    if lightingTween then
        lightingTween.Completed:Once(function()
            if currentRestoreSerial ~= restoreSerial then return end
            finishRestore(state)
        end)
    else
        task.delay(restoreDuration, function()
            if currentRestoreSerial ~= restoreSerial then return end
            finishRestore(state)
        end)
    end
end

function EventAtmosphereController.IsActive()
    return activeState ~= nil
end

return EventAtmosphereController
