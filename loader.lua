-- ╔══════════════════════════════════════════════════════╗
-- ║         ExecSync  v1.4.4  (IceWare Theme)            ║
-- ║   ExecSync Key System  +  Kiwisense Main GUI         ║
-- ╚══════════════════════════════════════════════════════╝

-- ─────────────────────────────────────────────
--  EXECUTOR COMPATIBILITY SHIMS
-- ─────────────────────────────────────────────
if not cloneref        then cloneref        = function(x) return x end end
if not getgenv         then getgenv         = function()   return _G  end end
if not gethui          then gethui          = function()   return game:GetService("CoreGui") end end
if not getcustomasset  then getcustomasset  = function(p)  return "rbxasset://" .. p end end

local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────────
--  CONFIG
-- ─────────────────────────────────────────────
local FIREBASE_PROJECT = "studio-9760542617-d373c"
local SESSION_FILE     = "execsync_session.txt"
local DISCORD_INVITE   = "https://discord.gg/execsync"

local FIRESTORE_BASE = "https://firestore.googleapis.com/v1/projects/"
    .. FIREBASE_PROJECT .. "/databases/(default)/documents"
local QUERY_URL = FIRESTORE_BASE .. ":runQuery"

-- ─────────────────────────────────────────────
--  ICEWARE THEME PALETTE
-- ─────────────────────────────────────────────
local IW = {
    -- Backgrounds
    Background          = Color3.fromRGB(10,  10,  10),   -- #0a0a0a  (window bg)
    SecondaryBG         = Color3.fromRGB(15,  15,  15),   -- #0f0f0f
    ElementBG           = Color3.fromRGB(20,  20,  20),   -- #141414  (buttons / inputs)
    HoverBG             = Color3.fromRGB(28,  28,  28),   -- #1c1c1c
    SectionBG           = Color3.fromRGB(13,  13,  13),   -- #0d0d0d

    -- Borders
    Border              = Color3.fromRGB(35,  35,  35),   -- #232323
    BorderLight         = Color3.fromRGB(50,  50,  50),   -- #323232

    -- Text
    Text                = Color3.fromRGB(255, 255, 255),  -- pure white
    SubText             = Color3.fromRGB(180, 180, 180),  -- #b4b4b4
    DimText             = Color3.fromRGB(90,  90,  90),   -- #5a5a5a
    PlaceholderText     = Color3.fromRGB(65,  65,  65),   -- #414141

    -- Accent (IceWare uses white as accent — no color tint)
    Accent              = Color3.fromRGB(255, 255, 255),
    AccentDim           = Color3.fromRGB(200, 200, 200),

    -- Toggle / Slider
    ToggleOn            = Color3.fromRGB(255, 255, 255),
    ToggleOff           = Color3.fromRGB(35,  35,  35),
    Thumb               = Color3.fromRGB(255, 255, 255),
    DisabledThumb       = Color3.fromRGB(45,  45,  45),
    SliderFill          = Color3.fromRGB(255, 255, 255),
    SliderTrack         = Color3.fromRGB(30,  30,  30),

    -- Notification
    NotifBG             = Color3.fromRGB(14,  14,  14),
    NotifBorder         = Color3.fromRGB(255, 255, 255),

    -- Dropdown
    DropdownBG          = Color3.fromRGB(12,  12,  12),
    DropdownItem        = Color3.fromRGB(18,  18,  18),
    DropdownSelected    = Color3.fromRGB(28,  28,  28),

    -- Scrollbar
    ScrollBar           = Color3.fromRGB(40,  40,  40),
    ScrollBarHover      = Color3.fromRGB(70,  70,  70),

    -- Font — GothamBold matches IceWare's clean sans-serif header,
    --        GothamSemibold for body/labels
    FontTitle           = Enum.Font.GothamBold,
    FontBody            = Enum.Font.GothamSemibold,
    FontMono            = Enum.Font.Code,
}

-- ─────────────────────────────────────────────
--  UNIVERSAL HTTP WRAPPER
-- ─────────────────────────────────────────────
local function httpRequest(opts)
    if type(request) == "function" then
        return request(opts)
    elseif type(http) == "table" and type(http.request) == "function" then
        return http.request(opts)
    elseif type(http_request) == "function" then
        return http_request(opts)
    else
        return HttpService:RequestAsync(opts)
    end
end

-- ─────────────────────────────────────────────
--  NOTIFICATION HELPER
-- ─────────────────────────────────────────────
local ActiveLib  = nil
local NotifQueue = {}

local function notify(title, body, duration)
    duration = duration or 5
    if ActiveLib and ActiveLib.Notification then
        ActiveLib:Notification({
            Name        = title,
            Description = body,
            Duration    = duration,
            Icon        = "116339777575852",
            IconColor   = IW.Text,
        })
    else
        table.insert(NotifQueue, { title, body, duration })
        warn("[ExecSync] " .. title .. " — " .. body)
    end
end

local function flushNotifQueue()
    for _, n in ipairs(NotifQueue) do
        ActiveLib:Notification({
            Name        = n[1],
            Description = n[2],
            Duration    = n[3],
            Icon        = "116339777575852",
            IconColor   = IW.Text,
        })
    end
    NotifQueue = {}
end

-- ─────────────────────────────────────────────
--  REMOTE LOGGER
-- ─────────────────────────────────────────────
local function remoteLog(level, message)
    task.spawn(function()
        pcall(function()
            httpRequest({
                Url     = FIRESTORE_BASE .. "/debugLogs",
                Method  = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = HttpService:JSONEncode({
                    fields = {
                        username  = { stringValue  = LocalPlayer.Name },
                        level     = { stringValue  = level },
                        message   = { stringValue  = tostring(message) },
                        timestamp = { integerValue = tostring(os.time()) },
                        placeId   = { stringValue  = tostring(game.PlaceId) },
                        jobId     = { stringValue  = tostring(game.JobId) },
                    }
                }),
            })
        end)
    end)
end
local function logInfo(m)  remoteLog("INFO",  m) end
local function logWarn(m)  remoteLog("WARN",  m) end
local function logError(m) remoteLog("ERROR", m) end

-- ─────────────────────────────────────────────
--  TOKEN GENERATOR
-- ─────────────────────────────────────────────
local function generateToken()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local token = ""
    math.randomseed(os.time() * math.random(1000, 9999))
    for _ = 1, 32 do
        local i = math.random(1, #chars)
        token = token .. chars:sub(i, i)
    end
    return token
end

-- ─────────────────────────────────────────────
--  PRESENCE TRACKING
-- ─────────────────────────────────────────────
local presenceDocUrl = FIRESTORE_BASE .. "/userPresence/" .. LocalPlayer.Name

local function updatePresence(online)
    task.spawn(function()
        pcall(function()
            local fields = {
                username    = { stringValue  = LocalPlayer.Name },
                online      = { booleanValue = online },
                lastUpdated = { integerValue = tostring(os.time()) },
                placeId     = { stringValue  = tostring(game.PlaceId) },
                jobId       = { stringValue  = tostring(game.JobId) },
            }
            if online then
                fields.gameUrl    = { stringValue = "https://www.roblox.com/games/" .. tostring(game.PlaceId) }
                fields.serverLink = { stringValue = "roblox://experiences/start?placeId=" .. tostring(game.PlaceId) .. "&gameInstanceId=" .. tostring(game.JobId) }
            end
            httpRequest({
                Url     = presenceDocUrl
                    .. "?updateMask.fieldPaths=username"
                    .. "&updateMask.fieldPaths=online"
                    .. "&updateMask.fieldPaths=lastUpdated"
                    .. "&updateMask.fieldPaths=placeId"
                    .. "&updateMask.fieldPaths=jobId"
                    .. "&updateMask.fieldPaths=gameUrl"
                    .. "&updateMask.fieldPaths=serverLink",
                Method  = "PATCH",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = HttpService:JSONEncode({ fields = fields }),
            })
        end)
    end)
end

local function goOnline()
    logInfo("Presence → ONLINE  placeId=" .. tostring(game.PlaceId))
    updatePresence(true)
    task.spawn(function()
        while true do
            task.wait(60)
            if not LocalPlayer or not LocalPlayer:IsDescendantOf(game) then break end
            pcall(function()
                httpRequest({
                    Url     = presenceDocUrl
                        .. "?updateMask.fieldPaths=lastUpdated"
                        .. "&updateMask.fieldPaths=online",
                    Method  = "PATCH",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body    = HttpService:JSONEncode({
                        fields = {
                            online      = { booleanValue = true },
                            lastUpdated = { integerValue = tostring(os.time()) },
                        }
                    }),
                })
            end)
        end
    end)
end

local offlineSent = false
local function goOffline()
    if offlineSent then return end
    offlineSent = true
    logInfo("Presence → OFFLINE")
    pcall(function()
        httpRequest({
            Url     = presenceDocUrl
                .. "?updateMask.fieldPaths=online"
                .. "&updateMask.fieldPaths=lastUpdated",
            Method  = "PATCH",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode({
                fields = {
                    online      = { booleanValue = false },
                    lastUpdated = { integerValue = tostring(os.time()) },
                }
            }),
        })
    end)
end

pcall(function() game:BindToClose(goOffline) end)
LocalPlayer.AncestryChanged:Connect(function()
    if not LocalPlayer:IsDescendantOf(game) then goOffline() end
end)

-- ─────────────────────────────────────────────
--  FIRESTORE HELPERS
-- ─────────────────────────────────────────────
local function queryByCode(username, code)
    logInfo("queryByCode → " .. username)
    local body = HttpService:JSONEncode({
        structuredQuery = {
            from  = {{ collectionId = "verificationCodes" }},
            where = {
                compositeFilter = {
                    op = "AND",
                    filters = {
                        { fieldFilter = { field = { fieldPath = "username" }, op = "EQUAL", value = { stringValue = username } } },
                        { fieldFilter = { field = { fieldPath = "code"     }, op = "EQUAL", value = { stringValue = tostring(code) } } },
                    }
                }
            },
            limit = 1,
        }
    })
    local ok, res = pcall(function()
        return httpRequest({ Url = QUERY_URL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
    end)
    if not ok then logError("queryByCode: " .. tostring(res)); return nil, "Network error — check HttpService is enabled." end
    if res.StatusCode ~= 200 then logError("queryByCode HTTP " .. tostring(res.StatusCode)); return nil, "Firestore error (" .. tostring(res.StatusCode) .. ")." end
    local parsed; ok, parsed = pcall(HttpService.JSONDecode, HttpService, res.Body)
    if not ok then logError("queryByCode: JSON decode failed"); return nil, "Invalid server response." end
    if type(parsed) ~= "table" or not parsed[1] or not parsed[1].document then
        logWarn("queryByCode: no document matched"); return nil, "Code not found. Double-check your username and code."
    end
    logInfo("queryByCode: match → " .. tostring(parsed[1].document.name))
    return parsed[1].document.name, nil
end

local function writeTokenToDoc(docName, token)
    local patchUrl = "https://firestore.googleapis.com/v1/" .. docName
        .. "?updateMask.fieldPaths=used&updateMask.fieldPaths=sessionToken"
    local ok, res = pcall(function()
        return httpRequest({
            Url     = patchUrl, Method = "PATCH",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode({ fields = { used = { booleanValue = true }, sessionToken = { stringValue = token } } }),
        })
    end)
    if not ok then logError("writeTokenToDoc network error: " .. tostring(res)); return false, "Network error when saving session." end
    if res.StatusCode ~= 200 then logError("writeTokenToDoc HTTP " .. tostring(res.StatusCode)); return false, "Could not save session." end
    logInfo("writeTokenToDoc: OK"); return true, nil
end

local function queryByToken(token)
    logInfo("queryByToken: " .. token:sub(1, 8) .. "…")
    local body = HttpService:JSONEncode({
        structuredQuery = {
            from  = {{ collectionId = "verificationCodes" }},
            where = { fieldFilter = { field = { fieldPath = "sessionToken" }, op = "EQUAL", value = { stringValue = token } } },
            limit = 1,
        }
    })
    local ok, res = pcall(function()
        return httpRequest({ Url = QUERY_URL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
    end)
    if not ok or res.StatusCode ~= 200 then logError("queryByToken failed"); return nil end
    local parsed = HttpService:JSONDecode(res.Body)
    if type(parsed) ~= "table" or not parsed[1] or not parsed[1].document then logWarn("queryByToken: not found"); return nil end
    local fields = parsed[1].document.fields
    if fields and fields.username and fields.username.stringValue then
        logInfo("queryByToken → " .. fields.username.stringValue)
        return fields.username.stringValue
    end
    return nil
end

local function fetchRemoteSettings()
    local ok, res = pcall(function()
        return httpRequest({ Url = FIRESTORE_BASE .. "/settings/global", Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
    end)
    if not ok or res.StatusCode ~= 200 then return nil end
    local parsed = HttpService:JSONDecode(res.Body)
    return parsed and parsed.fields or nil
end

-- ─────────────────────────────────────────────
--  USER SETTINGS  (Firestore ↔ GUI sync)
-- ─────────────────────────────────────────────
local USER_FLAGS_TO_SYNC = {
    "AutoRace", "StartSolo", "RaceSpeed", "MinWaitTime", "AutoVaryWait", "SelectRace",
    "AutoRob", "IncludeCargoCrates", "AntiCop", "IncludeBankHeist",
    "AutoDeposit", "DepositThreshold", "PauseBagThreshold",
    "TopSpeedEnabled", "TopSpeed", "NitrousEnabled", "NitrousScale",
    "AccelerationEnabled", "AccelerationScale", "TractionEnabled", "TractionScale",
    "HornBoost", "HornBoostIntensity", "InstantStop", "InfiniteNitro",
    "DisableRendering", "WebhookAlerts", "WebhookURL", "WebhookPing",
}

local function fetchUserSettings(username)
    logInfo("fetchUserSettings → " .. username)
    local ok, res = pcall(function()
        return httpRequest({
            Url     = FIRESTORE_BASE .. "/userSettings/" .. username,
            Method  = "GET",
            Headers = { ["Content-Type"] = "application/json" },
        })
    end)
    if not ok then
        logWarn("fetchUserSettings: network error — " .. tostring(res))
        return nil
    end
    if res.StatusCode ~= 200 then
        logWarn("fetchUserSettings: HTTP " .. tostring(res.StatusCode))
        return nil
    end
    local parsed = HttpService:JSONDecode(res.Body)
    return parsed and parsed.fields or nil
end

local function applyUserSettings(ML, fields)
    if not fields or not ML.Flags then return 0 end
    local applied = 0
    for flagName, fieldVal in pairs(fields) do
        if flagName == "lastModified" then continue end
        local flag = ML.Flags[flagName]
        if flag then
            local val
            if     fieldVal.booleanValue ~= nil then val = fieldVal.booleanValue
            elseif fieldVal.doubleValue  ~= nil then val = fieldVal.doubleValue
            elseif fieldVal.integerValue ~= nil then val = tonumber(fieldVal.integerValue)
            elseif fieldVal.stringValue  ~= nil then val = fieldVal.stringValue
            end
            if val ~= nil then
                local ok, err = pcall(function() flag:Set(val) end)
                if ok then
                    applied = applied + 1
                else
                    logWarn("applyUserSettings: flag '" .. flagName .. "' Set() failed — " .. tostring(err))
                end
            end
        else
            if flagName ~= "lastModified" then
                logWarn("applyUserSettings: unknown flag '" .. tostring(flagName) .. "'")
            end
        end
    end
    logInfo("applyUserSettings: applied " .. applied .. " flags")
    return applied
end

local function saveUserSettings(username, ML)
    if not ML.Flags then return end
    local fields = {}
    for _, flagName in ipairs(USER_FLAGS_TO_SYNC) do
        local flag = ML.Flags[flagName]
        if flag then
            local val = flag.Value
            if type(val) == "boolean" then
                fields[flagName] = { booleanValue = val }
            elseif type(val) == "number" then
                fields[flagName] = { doubleValue = val }
            elseif type(val) == "string" and val ~= "" then
                fields[flagName] = { stringValue = val }
            end
        end
    end
    fields["lastModified"] = { integerValue = tostring(os.time()) }
    local mask = "updateMask.fieldPaths=lastModified"
    for _, flagName in ipairs(USER_FLAGS_TO_SYNC) do
        mask = mask .. "&updateMask.fieldPaths=" .. flagName
    end
    logInfo("saveUserSettings → " .. username)
    pcall(function()
        httpRequest({
            Url     = FIRESTORE_BASE .. "/userSettings/" .. username .. "?" .. mask,
            Method  = "PATCH",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode({ fields = fields }),
        })
    end)
    notify("ExecSync", "Settings synced to cloud ✓", 3)
end

-- ─────────────────────────────────────────────
--  SESSION HELPERS
-- ─────────────────────────────────────────────
local function saveToken(t)
    pcall(function() writefile(SESSION_FILE, t) end)
end

local function readToken()
    local exists = false
    pcall(function() exists = isfile(SESSION_FILE) end)
    if not exists then return nil end
    local t = nil
    pcall(function() t = readfile(SESSION_FILE) end)
    return (t and t ~= "") and t or nil
end

local function deleteSessionFile()
    if not pcall(function() delfile(SESSION_FILE) end) then
        pcall(function() writefile(SESSION_FILE, "") end)
    end
    logInfo("Session file deleted")
end

-- ─────────────────────────────────────────────
--  INSTANT SETTINGS POLL
-- ─────────────────────────────────────────────
local function startSettingsPoll(ML, username)
    local lastKnownModified = 0

    task.spawn(function()
        while true do
            task.wait(3)

            local tick = os.time()
            if tick % 300 < 3 then
                local s = fetchRemoteSettings()
                if s then
                    if s.killSwitch and s.killSwitch.booleanValue == true then
                        logWarn("Kill switch activated")
                        notify("ExecSync", "Script disabled remotely.", 6)
                        task.wait(3); goOffline(); ML:Unload(); return
                    end
                    if s.maintenanceMessage and s.maintenanceMessage.stringValue ~= "" then
                        notify("ExecSync – Notice", s.maintenanceMessage.stringValue, 8)
                    end
                end
            end

            local fields = fetchUserSettings(username)
            if not fields then continue end

            local remoteModified = 0
            if fields.lastModified then
                if fields.lastModified.integerValue then
                    remoteModified = tonumber(fields.lastModified.integerValue) or 0
                elseif fields.lastModified.doubleValue then
                    remoteModified = fields.lastModified.doubleValue or 0
                end
            end

            if remoteModified <= lastKnownModified then continue end

            local n = applyUserSettings(ML, fields)
            lastKnownModified = remoteModified
            logInfo("Instant sync: " .. (n or 0) .. " flags updated (lastModified=" .. tostring(remoteModified) .. ")")
            if n and n > 0 then
                notify("ExecSync", "⚡ " .. n .. " setting(s) updated from dashboard", 3)
            end
        end
    end)
end

-- ─────────────────────────────────────────────
--  ICEWARE-STYLE THEME APPLICATION
-- ─────────────────────────────────────────────
local function applyExecSyncTheme(ML)
    pcall(function()
        if not ML.Theme then return end

        -- ── Core colour overrides matching IceWare's monochromatic dark palette ──
        local overrides = {
            -- Window & containers
            Background              = IW.Background,
            SecondaryBackground     = IW.SecondaryBG,
            TertiaryBackground      = IW.SectionBG,
            ElementBackground       = IW.ElementBG,
            HoveredElementBackground= IW.HoverBG,
            SectionBackground       = IW.SectionBG,
            DropdownBackground      = IW.DropdownBG,
            DropdownItemBackground  = IW.DropdownItem,
            DropdownSelectedBackground = IW.DropdownSelected,

            -- Borders
            Border                  = IW.Border,
            LightBorder             = IW.BorderLight,
            ElementBorder           = IW.Border,
            SectionBorder           = IW.Border,
            SelectedElementBorder   = IW.Text,       -- white highlight on selected
            NotificationBorder      = IW.Text,       -- white notification border

            -- Text
            Text                    = IW.Text,
            SubText                 = IW.SubText,
            DimText                 = IW.DimText,
            PlaceholderText         = IW.PlaceholderText,
            HeaderText              = IW.Text,
            LabelText               = IW.SubText,

            -- Accent (IceWare uses white as its sole accent)
            Accent                  = IW.Accent,
            AccentDark              = IW.ElementBG,

            -- Toggles & sliders
            ToggleBackground        = IW.ToggleOff,
            ToggleEnabledBackground = IW.ToggleOn,
            Thumb                   = IW.Thumb,
            DisabledThumb           = IW.DisabledThumb,
            SliderBackground        = IW.SliderTrack,
            SliderFill              = IW.SliderFill,

            -- Scrollbar
            ScrollBar               = IW.ScrollBar,
            ScrollBarHover          = IW.ScrollBarHover,

            -- Notifications
            NotificationBackground  = IW.NotifBG,
            NotificationIcon        = IW.Text,

            -- Font — GothamBold for titles, GothamSemibold for body
            Font                    = IW.FontBody,
            TitleFont               = IW.FontTitle,
        }

        for key, value in pairs(overrides) do
            if ML.Theme[key] ~= nil then
                ML.Theme[key] = value
                pcall(function() ML:ChangeTheme(key, value) end)
            else
                -- attempt blind set even if not pre-declared in the theme table
                pcall(function() ML:ChangeTheme(key, value) end)
            end
        end

        -- ── Additional raw GuiObject styling pass ──
        -- Walk the CoreGui/PlayerGui tree and re-style any ExecSync frames directly,
        -- ensuring the background/border colours are exactly right even if the
        -- library doesn't expose every key through ChangeTheme.
        task.defer(function()
            pcall(function()
                local roots = { gethui(), PlayerGui }
                for _, root in ipairs(roots) do
                    for _, desc in ipairs(root:GetDescendants()) do
                        -- Re-colour frames that look like window/section backgrounds
                        if desc:IsA("Frame") or desc:IsA("ScrollingFrame") then
                            local bg = desc.BackgroundColor3
                            -- If the element was a mid-grey placeholder, push it to IceWare dark
                            local r, g, b = bg.R * 255, bg.G * 255, bg.B * 255
                            if r > 25 and r < 60 and math.abs(r - g) < 8 and math.abs(g - b) < 8 then
                                desc.BackgroundColor3 = IW.ElementBG
                            elseif r <= 25 and math.abs(r - g) < 5 and math.abs(g - b) < 5 then
                                desc.BackgroundColor3 = IW.Background
                            end
                            -- Enforce border transparency / thinness
                            if desc.BorderSizePixel and desc.BorderSizePixel > 0 then
                                desc.BorderColor3 = IW.Border
                            end
                        end

                        -- Enforce text colours on labels
                        if desc:IsA("TextLabel") then
                            if desc.TextColor3 ~= IW.Text and desc.TextColor3 ~= IW.SubText then
                                local tr = desc.TextColor3.R * 255
                                if tr > 150 then
                                    desc.TextColor3 = IW.Text
                                elseif tr > 80 then
                                    desc.TextColor3 = IW.SubText
                                else
                                    desc.TextColor3 = IW.DimText
                                end
                            end
                            -- Apply Gotham font family
                            pcall(function()
                                if desc.TextSize and desc.TextSize >= 16 then
                                    desc.Font = IW.FontTitle
                                else
                                    desc.Font = IW.FontBody
                                end
                            end)
                        end

                        if desc:IsA("TextButton") or desc:IsA("TextBox") then
                            pcall(function() desc.Font = IW.FontBody end)
                            if desc:IsA("TextButton") then
                                desc.BackgroundColor3 = IW.ElementBG
                                desc.TextColor3 = IW.Text
                                desc.BorderColor3 = IW.Border
                            end
                        end

                        -- UICorner — IceWare uses very subtle corners (2–4 px)
                        if desc:IsA("UICorner") then
                            if desc.CornerRadius.Offset > 6 then
                                desc.CornerRadius = UDim.new(0, 4)
                            end
                        end

                        -- UIStroke — use border colour
                        if desc:IsA("UIStroke") then
                            desc.Color = IW.Border
                            if desc.Thickness > 1.5 then
                                desc.Thickness = 1
                            end
                        end
                    end
                end
            end)
        end)

        logInfo("IceWare theme applied — GothamBold/SemiBold, monochromatic dark palette")
    end)
end

-- ─────────────────────────────────────────────
--  MAIN GUI
-- ─────────────────────────────────────────────
local function LoadMainScript(username)
    local LoadingTick = os.clock()

    local ML = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Kiwisense/Library.lua"
    ))()

    ActiveLib = ML
    flushNotifQueue()

    local Window = ML:Window({
        Name      = "ExecSync",
        Version   = "v1.4.4",
        Logo      = "135215559087473",
        FadeSpeed = 0.20,   -- slightly snappier to feel more like IceWare
    })

    local Watermark = ML:Watermark("ExecSync | Driving Empire", "135215559087473")
    Watermark:SetVisibility(true)

    local KeybindList = ML:KeybindsList()
    KeybindList:SetVisibility(false)

    local Pages = {
        ["Main"]     = Window:Page({ Name = "Main",          Icon = "7733960981",      SubPages = true }),
        ["Misc"]     = Window:Page({ Name = "Miscellaneous", Icon = "136623465713368",  Columns = 2 }),
        ["Players"]  = Window:Page({ Name = "Player List",   Icon = "103174889897193" }),
        ["Settings"] = Window:Page({ Name = "Settings",      Icon = "137300573942266",  SubPages = true }),
    }

    local MainSub = {
        ["AutoFarm"] = Pages["Main"]:SubPage({ Name = "Auto Farm", Icon = "13107902118",     Columns = 2 }),
        ["CarMods"]  = Pages["Main"]:SubPage({ Name = "Car Mods",  Icon = "103174889897193", Columns = 2 }),
    }

    -- ── Auto Farm ──
    do
        local Racing  = MainSub["AutoFarm"]:Section({ Name = "Racing",  Side = 1 })
        local Robbery = MainSub["AutoFarm"]:Section({ Name = "Robbery", Side = 2 })

        Racing:Toggle({ Name = "Auto Race",           Flag = "AutoRace",     Default = false, Callback = function() end })
        Racing:Toggle({ Name = "Start Solo",          Flag = "StartSolo",    Default = false, Callback = function() end })
        Racing:Slider({ Name = "Race Speed",          Flag = "RaceSpeed",    Min = 1,  Max = 500, Default = 250, Decimals = 1,   Callback = function() end })
        Racing:Slider({ Name = "Minimum Wait Time",   Flag = "MinWaitTime",  Min = 0,  Max = 10,  Default = 0.5, Decimals = 0.1, Suffix = "s", Callback = function() end })
        Racing:Toggle({ Name = "Auto Vary Wait Time", Flag = "AutoVaryWait", Default = false, Callback = function() end })
        Racing:Dropdown({ Name = "Select Race", Flag = "SelectRace",
            Items   = { "Circuit Race", "Street Race", "Derby", "Drag Race" },
            Default = "Circuit Race", MaxSize = 150, Callback = function() end })
        Racing:Label("Auto Drive is not great for revenues,\nif you are trying to farm money use auto rob/arrest", "Left")

        Robbery:Label("!! Use auto rob at your own risk, there is a\nchance of being banned !!\nWE ARE AWARE OF THE BUG WITH ATMS, WE\nARE TRYING TO FIND A WORKAROUND", "Left")
        Robbery:Label("Session Time: 0s", "Left")
        Robbery:Toggle({ Name = "Auto Rob",             Flag = "AutoRob",            Default = false, Callback = function() end })
        Robbery:Toggle({ Name = "Include Cargo Crates", Flag = "IncludeCargoCrates", Default = false, Callback = function() end })
        Robbery:Toggle({ Name = "Anti Cop",             Flag = "AntiCop",            Default = false, Callback = function() end })
        Robbery:Toggle({ Name = "Include Bank Heist",   Flag = "IncludeBankHeist",   Default = false, Callback = function() end })
        Robbery:Toggle({ Name = "Auto Deposit",         Flag = "AutoDeposit",        Default = false, Callback = function() end })
        Robbery:Slider({ Name = "Deposit Threshold",    Flag = "DepositThreshold",   Min = 1, Max = 100, Default = 10, Decimals = 1, Callback = function() end })
        Robbery:Slider({ Name = "Pause Bag Threshold",  Flag = "PauseBagThreshold",  Min = 1, Max = 100, Default = 25, Decimals = 1, Callback = function() end })
    end

    -- ── Car Mods ──
    do
        local Perf  = MainSub["CarMods"]:Section({ Name = "Performance",    Side = 1 })
        local Extra = MainSub["CarMods"]:Section({ Name = "Extra Features", Side = 2 })

        Perf:Toggle({ Name = "Top Speed",    Flag = "TopSpeedEnabled",     Default = false, Callback = function() end })
        Perf:Slider({ Name = "Speed",         Flag = "TopSpeed",            Min = 1,   Max = 600, Default = 300, Decimals = 1,   Callback = function() end })
        Perf:Toggle({ Name = "Nitrous",       Flag = "NitrousEnabled",      Default = false, Callback = function() end })
        Perf:Slider({ Name = "Scale",         Flag = "NitrousScale",        Min = 0.1, Max = 10,  Default = 2,   Decimals = 0.1, Callback = function() end })
        Perf:Toggle({ Name = "Acceleration",  Flag = "AccelerationEnabled", Default = false, Callback = function() end })
        Perf:Slider({ Name = "Scale",         Flag = "AccelerationScale",   Min = 0.1, Max = 10,  Default = 2,   Decimals = 0.1, Callback = function() end })
        Perf:Toggle({ Name = "Traction",      Flag = "TractionEnabled",     Default = false, Callback = function() end })
        Perf:Slider({ Name = "Scale",         Flag = "TractionScale",       Min = 0.1, Max = 10,  Default = 2,   Decimals = 0.1, Callback = function() end })

        Extra:Toggle({ Name = "Horn Boost",            Flag = "HornBoost",          Default = false, Callback = function() end })
        Extra:Slider({ Name = "Horn Boost Intensity",  Flag = "HornBoostIntensity", Min = 1, Max = 10, Default = 1, Decimals = 1, Callback = function() end })
        Extra:Toggle({ Name = "Instant Stop",          Flag = "InstantStop",        Default = false, Callback = function() end })
        Extra:Toggle({ Name = "Car Breakable Aura",    Flag = "CarBreakableAura",   Default = false, Callback = function() end })
        Extra:Toggle({ Name = "Infinite Nitro",        Flag = "InfiniteNitro",      Default = false, Callback = function() end })
    end

    -- ── Miscellaneous ──
    do
        local Rewards   = Pages["Misc"]:Section({ Name = "Rewards",      Side = 1 })
        local Trolling  = Pages["Misc"]:Section({ Name = "Trolling",     Side = 1 })
        local Inventory = Pages["Misc"]:Section({ Name = "Inventory",    Side = 1 })
        local Dealer    = Pages["Misc"]:Section({ Name = "Dealership",   Side = 2 })
        local Optim     = Pages["Misc"]:Section({ Name = "Optimization", Side = 2 })
        local Misc      = Pages["Misc"]:Section({ Name = "Misc",         Side = 2 })
        local Webhook   = Pages["Misc"]:Section({ Name = "Webhook",      Side = 2 })

        Rewards:Toggle({ Name = "Auto Claim Daily Rewards",    Flag = "AutoDailyRewards",       Default = false, Callback = function() end })
        Rewards:Toggle({ Name = "Auto Double Daily Rewards",   Flag = "AutoDoubleDailyRewards",  Default = false, Callback = function() end })
        Rewards:Toggle({ Name = "Auto Claim AD Rewards",       Flag = "AutoADRewards",           Default = false, Callback = function() end })
        Rewards:Button({ Name = "Redeem All Codes",            Callback = function() end })
        Rewards:Button({ Name = "Free Trophies (Nascar QUIZ)", Callback = function() end })
        Trolling:Toggle({ Name = "Spam Outfits",               Flag = "SpamOutfits",             Default = false, Callback = function() end })
        Inventory:Toggle({ Name = "Auto Open Packs [$$$]",    Flag = "AutoOpenPacks",           Default = false, Callback = function() end })
        Inventory:Slider({ Name = "Gacha Open Amount",         Flag = "GachaOpenAmount",         Min = 1, Max = 100, Default = 1, Decimals = 1, Callback = function() end })
        Dealer:Dropdown({ Name = "Select Vehicle", Flag = "SelectVehicle",
            Items = { "Cars", "Motorcycles", "Trucks", "Sports Cars" }, Default = "Cars", MaxSize = 200, Callback = function() end })
        Dealer:Button({ Name = "Open Dealership", Callback = function() end })
        Optim:Toggle({ Name = "Disable Rendering",            Flag = "DisableRendering",  Default = false, Callback = function() end })
        Misc:Toggle({ Name = "No Telemetry",                   Flag = "NoTelemetry",       Default = false, Callback = function() end })
        Misc:Toggle({ Name = "Always See Bounties [$$$]",     Flag = "AlwaysSeeBounties", Default = false, Callback = function() end })
        Webhook:Toggle({ Name = "Webhook Alerts",              Flag = "WebhookAlerts",     Default = false, Callback = function() end })
        Webhook:Textbox({ Name = "Webhook URL",                Flag = "WebhookURL",        Default = "", Placeholder = "...", Callback = function() end })
        Webhook:Toggle({ Name = "Ping on alert (@here)",       Flag = "WebhookPing",       Default = false, Callback = function() end })
    end

    Pages["Players"]:Playerlist({ Callback = function(...) end })

    -- ── Settings ──
    local SettingsSub = {
        ["Config"]  = Pages["Settings"]:SubPage({ Name = "Configuration", Icon = "137300573942266", Columns = 2 }),
        ["Configs"] = Pages["Settings"]:SubPage({ Name = "Configs",       Icon = "96491224522405",  Columns = 2 }),
        ["Theme"]   = Pages["Settings"]:SubPage({ Name = "Theming",       Icon = "103863157706913", Columns = 2 }),
    }

    do
        local Session = SettingsSub["Config"]:Section({ Name = "Session",        Side = 1 })
        local UI      = SettingsSub["Config"]:Section({ Name = "User Interface", Side = 2 })
        local Anim    = SettingsSub["Config"]:Section({ Name = "Animations",     Side = 2 })

        Session:Label("Driving Empire", "Center")
        Session:Label(tostring(username or LocalPlayer.Name), "Center")
        Session:Label("Place ID: " .. tostring(game.PlaceId), "Center")

        Session:Button({ Name = "Rejoin", Callback = function()
            game:GetService("TeleportService"):Teleport(game.PlaceId)
        end })

        Session:Button({ Name = "Server Hop", Callback = function()
            local TS = game:GetService("TeleportService")
            local servers = HttpService:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            ))
            for _, sv in ipairs(servers.data) do
                if sv.id ~= game.JobId and sv.playing < sv.maxPlayers then
                    TS:TeleportToPlaceInstance(game.PlaceId, sv.id); return
                end
            end
        end })

        Session:Button({ Name = "Pull Settings from Cloud", Callback = function()
            notify("ExecSync", "Fetching settings…", 2)
            task.spawn(function()
                local fields = fetchUserSettings(username)
                if fields then
                    local n = applyUserSettings(ML, fields)
                    notify("ExecSync", "Loaded " .. (n or 0) .. " settings from cloud ✓", 4)
                else
                    notify("ExecSync", "No cloud settings found — check Firestore rules.", 4)
                end
            end)
        end })

        Session:Button({ Name = "Push Settings to Cloud", Callback = function()
            task.spawn(function() saveUserSettings(username, ML) end)
        end })

        Session:Button({ Name = "Eject", Callback = function()
            logInfo("Eject"); goOffline(); ML:Unload()
        end })

        Session:Button({ Name = "Log Out", Callback = function()
            logInfo("Log Out — clearing session")
            deleteSessionFile(); goOffline()
            notify("ExecSync", "Logged out. Re-run the script to sign in again.", 4)
            task.wait(2); ML:Unload()
        end })

        Session:Button({ Name = "Join Discord", Callback = function()
            if setclipboard then setclipboard(DISCORD_INVITE) end
            notify("ExecSync", "Discord link copied!", 3)
        end })

        Session:Button({ Name = "Copy Game URL", Callback = function()
            local url = "https://www.roblox.com/games/" .. tostring(game.PlaceId)
            if setclipboard then setclipboard(url) end
            notify("ExecSync", "Game URL copied: " .. url, 4)
        end })

        UI:Label("Menu Keybind", "Left"):Keybind({
            Name = "MenuKeybind", Flag = "MenuKeybind", Mode = "toggle",
            Default = Enum.KeyCode.RightControl,
            Callback = function() ML.MenuKeybind = ML.Flags["MenuKeybind"].Key end
        })
        UI:Toggle({ Name = "Keybind List", Flag = "KeybindList", Default = false,
            Callback = function(v) KeybindList:SetVisibility(v) end })
        UI:Toggle({ Name = "Watermark", Flag = "Watermark", Default = true,
            Callback = function(v) Watermark:SetVisibility(v) end })

        Anim:Slider({ Name = "Time",    Flag = "TweenTime",      Min = 0, Max = 5,  Default = 0.2, Decimals = 0.01, Callback = function() end })
        Anim:Dropdown({ Name = "Style", Flag = "TweenStyle",
            Items   = { "Linear","Sine","Quad","Cubic","Quart","Quint","Exponential","Circular","Back","Elastic","Bounce" },
            Default = "Cubic", MaxSize = 150, Callback = function() end })
        Anim:Dropdown({ Name = "Direction", Flag = "TweenDirection",
            Items = { "In","Out","InOut" }, Default = "Out", MaxSize = 80, Callback = function() end })
    end

    -- ── Configs subpage ──
    do
        local SaveLoad = SettingsSub["Configs"]:Section({ Name = "Save / Load", Side = 1 })
        local Auto     = SettingsSub["Configs"]:Section({ Name = "Autoload",    Side = 2 })

        SaveLoad:Textbox({ Name = "Config Name", Flag = "ConfigName", Default = "", Placeholder = "Enter Name", Callback = function() end })
        SaveLoad:Button({ Name = "Create",       Callback = function() end })
        SaveLoad:Button({ Name = "Delete",       Callback = function() end })
        SaveLoad:Button({ Name = "Load",         Callback = function() end })
        SaveLoad:Button({ Name = "Save",         Callback = function() end })
        SaveLoad:Button({ Name = "Refresh List", Callback = function() end })

        Auto:Button({ Name = "Set Selected Config As Autoload", Callback = function() end })
        Auto:Button({ Name = "Set Current Config As Autoload",  Callback = function() end })
        Auto:Button({ Name = "Remove Autoload Config",          Callback = function() end })
    end

    -- ── Theme subpage ──
    do
        local ThemeSec = SettingsSub["Theme"]:Section({ Name = "Colour Overrides", Side = 1 })
        local FontSec  = SettingsSub["Theme"]:Section({ Name = "Typography",       Side = 2 })

        ThemeSec:Label("IceWare theme active by default.", "Center")
        ThemeSec:Button({ Name = "Re-apply IceWare Theme", Callback = function()
            task.defer(function() applyExecSyncTheme(ML) end)
            notify("ExecSync", "IceWare theme re-applied ✓", 3)
        end })

        FontSec:Label("Font: GothamBold (titles)", "Left")
        FontSec:Label("Font: GothamSemibold (body)", "Left")
    end

    ML:Init()

    -- Apply IceWare theme immediately after init, then again after a short delay
    -- to catch any elements the library creates asynchronously.
    task.defer(function() applyExecSyncTheme(ML) end)
    task.delay(0.5, function() applyExecSyncTheme(ML) end)
    task.delay(1.5, function() applyExecSyncTheme(ML) end)

    goOnline()

    task.spawn(function()
        local fields = fetchUserSettings(username)
        if fields then
            task.wait(0.5)
            local n = applyUserSettings(ML, fields)
            logInfo("Cloud settings applied on load: " .. (n or 0) .. " flags")
        end
    end)

    ML:Notification({
        Name        = "ExecSync",
        Description = "Loaded in: " .. string.format("%.4f", os.clock() - LoadingTick) .. "s",
        Duration    = 5,
        Icon        = "116339777575852",
        IconColor   = IW.Text,
    })

    startSettingsPoll(ML, username)
    logInfo("Main GUI loaded for " .. tostring(username))
end

-- ─────────────────────────────────────────────
--  KEY SYSTEM  (same IceWare theme)
-- ─────────────────────────────────────────────
local function BuildKeySystem(onSuccess)
    local KW = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Kiwisense/Library.lua"
    ))()

    ActiveLib = KW

    local Win = KW:Window({
        Name      = "ExecSync",
        Version   = "Key System",
        Logo      = "135215559087473",
        FadeSpeed = 0.20,
    })

    local KeyPage = Win:Page({ Name = "Key System", Icon = "116339777575852", Columns = 2 })

    local VerifSection = KeyPage:Section({ Name = "Key Verification", Side = 1 })
    VerifSection:Label("Enter your 5-digit code to unlock access", "Center")

    local enteredCode = ""
    local isVerifying = false

    VerifSection:Textbox({
        Name = "Key Input", Flag = "KeyInput", Default = "", Placeholder = "Enter your key here..",
        Callback = function(v) enteredCode = v end
    })

    VerifSection:Button({
        Name = "Check Key",
        Callback = function()
            if isVerifying then notify("ExecSync", "Already verifying, please wait…", 2); return end
            local code = (enteredCode or ""):match("^%s*(.-)%s*$")
            if not code or code == "" then notify("ExecSync – Key System", "Please enter your security code.", 3); return end
            if not code:match("^%d%d%d%d%d$") then notify("ExecSync – Key System", "Code must be exactly 5 digits.", 3); return end
            isVerifying = true
            notify("ExecSync – Key System", "Verifying code, please wait…", 4)
            logInfo("Check Key pressed by " .. LocalPlayer.Name)
            task.spawn(function()
                local docName, queryErr = queryByCode(LocalPlayer.Name, code)
                if not docName then
                    notify("ExecSync – Key System", "❌ " .. (queryErr or "Invalid code."), 5)
                    logError("Key rejected: " .. tostring(queryErr)); isVerifying = false; return
                end
                local token = generateToken()
                local patched, patchErr = writeTokenToDoc(docName, token)
                if not patched then
                    notify("ExecSync – Key System", "❌ " .. (patchErr or "Could not save session."), 5)
                    logError("Token write failed: " .. tostring(patchErr)); isVerifying = false; return
                end
                saveToken(token)
                logInfo("Token saved for " .. LocalPlayer.Name)
                notify("ExecSync – Key System", "✅ Verified! Loading ExecSync…", 3)
                task.wait(1.5)
                isVerifying = false

                if onSuccess then
                    task.spawn(function()
                        onSuccess(LocalPlayer.Name)
                        task.wait(2)
                        pcall(function() KW:Unload() end)
                    end)
                end
            end)
        end
    })

    VerifSection:Button({ Name = "Get Key (12H)", Callback = function()
        if setclipboard then setclipboard(DISCORD_INVITE) end
        notify("ExecSync", "Join Discord to get a 12H key. Link copied!", 4)
    end })
    VerifSection:Button({ Name = "Get Key (1D)", Callback = function()
        if setclipboard then setclipboard(DISCORD_INVITE) end
        notify("ExecSync", "Join Discord to get a 1D key. Link copied!", 4)
    end })

    local InfoSection = KeyPage:Section({ Name = "Information", Side = 2 })
    InfoSection:Label("Codes are tied to your Roblox username.", "Center")
    InfoSection:Label("Each code can only be used once.", "Center")
    InfoSection:Label("Premium removes the key system and gives you\naccess to the best features, join our discord\nto learn more", "Center")

    local DiscordSection = KeyPage:Section({ Name = "Discord", Side = 2 })
    DiscordSection:Label("Need help or updates? Join our Discord server", "Left")
    DiscordSection:Button({ Name = "Join Discord", Callback = function()
        if setclipboard then setclipboard(DISCORD_INVITE) end
        notify("ExecSync", "Discord invite link copied!", 3)
    end })

    KW:Init()

    task.defer(function() applyExecSyncTheme(KW) end)
    task.delay(0.5, function() applyExecSyncTheme(KW) end)
    task.delay(1.5, function() applyExecSyncTheme(KW) end)

    logInfo("Key system displayed for " .. LocalPlayer.Name)
end

-- ─────────────────────────────────────────────
--  ENTRY POINT
-- ─────────────────────────────────────────────
logInfo("ExecSync starting — place=" .. tostring(game.PlaceId) .. "  user=" .. LocalPlayer.Name)

task.spawn(function()
    local savedToken = readToken()
    if savedToken and savedToken ~= "" then
        logInfo("Found saved token — validating silently…")
        local resolvedUser = queryByToken(savedToken)
        if resolvedUser then
            logInfo("Session valid → loading for " .. resolvedUser)
            LoadMainScript(resolvedUser); return
        else
            logWarn("Saved token invalid — showing key system")
            deleteSessionFile()
        end
    end
    BuildKeySystem(function(username) LoadMainScript(username) end)
end)
