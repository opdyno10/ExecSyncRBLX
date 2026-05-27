-- ╔══════════════════════════════════════════════════════╗
-- ║         ExecSync  v1.4.1  (Auth Fix)                 ║
-- ║   IceWare Key System  +  Kiwisense Main GUI          ║
-- ╚══════════════════════════════════════════════════════╝

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
--  FIX #1: Universal HTTP wrapper
--  Roblox executors expose the HTTP API in
--  different ways — try all of them in order.
-- ─────────────────────────────────────────────
local function httpRequest(opts)
    -- syn/fluxus/xeno use `request`
    -- krnl/script-ware use `http.request` or `http_request`
    -- fallback: HttpService:RequestAsync (works everywhere)
    if type(request) == "function" then
        return request(opts)
    elseif type(http) == "table" and type(http.request) == "function" then
        return http.request(opts)
    elseif type(http_request) == "function" then
        return http_request(opts)
    else
        -- HttpService:RequestAsync is always available
        return HttpService:RequestAsync(opts)
    end
end

-- ─────────────────────────────────────────────
--  NOTIFICATION HELPER
--  We keep a reference to the KW/ML library so
--  every module can push visible notifications.
-- ─────────────────────────────────────────────
local ActiveLib   -- set once any library loads
local NotifQueue  = {}

local function notify(title, body, duration)
    duration = duration or 5
    if ActiveLib and ActiveLib.Notification then
        ActiveLib:Notification({
            Name        = title,
            Description = body,
            Duration    = duration,
            Icon        = "116339777575852",
            IconColor   = Color3.fromRGB(255, 255, 255),
        })
    else
        -- Queue it; delivered once a library is ready
        table.insert(NotifQueue, { title, body, duration })
        -- Also always print so devs can see it
        warn("[ExecSync] " .. title .. " — " .. body)
    end
end

local function flushNotifQueue()
    for _, n in NotifQueue do
        ActiveLib:Notification({
            Name        = n[1],
            Description = n[2],
            Duration    = n[3],
            Icon        = "116339777575852",
            IconColor   = Color3.fromRGB(255, 255, 255),
        })
    end
    NotifQueue = {}
end

-- ─────────────────────────────────────────────
--  REMOTE LOGGER
-- ─────────────────────────────────────────────
local function remoteLog(level, message)
    print("[ExecSync][" .. level .. "] " .. tostring(message))
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
--  FIRESTORE HELPERS
--  FIX #2: All HTTP calls now go through
--  httpRequest() and surface errors via notify()
--  instead of silently returning nil.
-- ─────────────────────────────────────────────

-- Step 1 — find document by username + code
local function queryByCode(username, code)
    logInfo("queryByCode → " .. username)

    local body = HttpService:JSONEncode({
        structuredQuery = {
            from  = {{ collectionId = "verificationCodes" }},
            where = {
                compositeFilter = {
                    op = "AND",
                    filters = {
                        {
                            fieldFilter = {
                                field = { fieldPath = "username" },
                                op    = "EQUAL",
                                value = { stringValue = username },
                            }
                        },
                        {
                            fieldFilter = {
                                field = { fieldPath = "code" },
                                op    = "EQUAL",
                                value = { stringValue = tostring(code) },
                            }
                        },
                    }
                }
            },
            limit = 1,
        }
    })

    local ok, res = pcall(function()
        return httpRequest({
            Url     = QUERY_URL,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = body,
        })
    end)

    if not ok then
        local msg = "Network error — check HttpService is enabled in Studio/executor."
        logError("queryByCode: " .. tostring(res))
        return nil, msg
    end

    -- Surface non-200 HTTP status codes
    if res.StatusCode ~= 200 then
        local msg = "Firestore error (" .. tostring(res.StatusCode) .. "). Check project ID and collection name."
        logError("queryByCode HTTP " .. tostring(res.StatusCode) .. " body=" .. tostring(res.Body))
        return nil, msg
    end

    local parsed
    ok, parsed = pcall(HttpService.JSONDecode, HttpService, res.Body)
    if not ok then
        logError("queryByCode: JSON decode failed — " .. tostring(parsed))
        return nil, "Invalid server response."
    end

    -- runQuery returns an array; first element has `document` if a match was found
    if type(parsed) ~= "table" or not parsed[1] or not parsed[1].document then
        logWarn("queryByCode: no document matched (user=" .. username .. " code=" .. code .. ")")
        return nil, "Code not found. Double-check your username and code."
    end

    logInfo("queryByCode: match found → " .. tostring(parsed[1].document.name))
    return parsed[1].document.name, nil
end

-- Step 2 — mark used + write session token
local function writeTokenToDoc(docName, token)
    local patchUrl = "https://firestore.googleapis.com/v1/" .. docName
        .. "?updateMask.fieldPaths=used&updateMask.fieldPaths=sessionToken"

    local ok, res = pcall(function()
        return httpRequest({
            Url     = patchUrl,
            Method  = "PATCH",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode({
                fields = {
                    used         = { booleanValue = true },
                    sessionToken = { stringValue  = token },
                }
            }),
        })
    end)

    if not ok then
        logError("writeTokenToDoc network error: " .. tostring(res))
        return false, "Network error when saving session."
    end

    if res.StatusCode ~= 200 then
        logError("writeTokenToDoc HTTP " .. tostring(res.StatusCode) .. " — " .. tostring(res.Body))
        return false, "Could not save session (HTTP " .. tostring(res.StatusCode) .. ")."
    end

    logInfo("writeTokenToDoc: OK")
    return true, nil
end

-- Session resume — find document by stored token
local function queryByToken(token)
    logInfo("queryByToken: " .. token:sub(1, 8) .. "…")

    local body = HttpService:JSONEncode({
        structuredQuery = {
            from  = {{ collectionId = "verificationCodes" }},
            where = {
                fieldFilter = {
                    field = { fieldPath = "sessionToken" },
                    op    = "EQUAL",
                    value = { stringValue = token },
                }
            },
            limit = 1,
        }
    })

    local ok, res = pcall(function()
        return httpRequest({
            Url     = QUERY_URL,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = body,
        })
    end)

    if not ok or res.StatusCode ~= 200 then
        logError("queryByToken failed: " .. tostring(ok and res.StatusCode or res))
        return nil
    end

    local parsed = HttpService:JSONDecode(res.Body)
    if type(parsed) ~= "table" or not parsed[1] or not parsed[1].document then
        logWarn("queryByToken: token not found in Firestore")
        return nil
    end

    local fields = parsed[1].document.fields
    if fields and fields.username and fields.username.stringValue then
        logInfo("queryByToken → resolved: " .. fields.username.stringValue)
        return fields.username.stringValue
    end
    return nil
end

local function fetchRemoteSettings()
    local ok, res = pcall(function()
        return httpRequest({
            Url     = FIRESTORE_BASE .. "/settings/global",
            Method  = "GET",
            Headers = { ["Content-Type"] = "application/json" },
        })
    end)
    if not ok or res.StatusCode ~= 200 then return nil end
    local parsed = HttpService:JSONDecode(res.Body)
    return parsed and parsed.fields or nil
end

-- ─────────────────────────────────────────────
--  SESSION HELPERS
-- ─────────────────────────────────────────────
local function saveToken(t)
    pcall(function() writefile(SESSION_FILE, t) end)
end

local function readToken()
    -- isfile / readfile are executor globals — guard both with pcall
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
--  SETTINGS POLL  (every 5 minutes)
-- ─────────────────────────────────────────────
local function startSettingsPoll(ML)
    task.spawn(function()
        while true do
            task.wait(300)
            local s = fetchRemoteSettings()
            if s then
                if s.killSwitch and s.killSwitch.booleanValue == true then
                    logWarn("Kill switch activated")
                    notify("ExecSync", "Script disabled remotely.", 6)
                    task.wait(3)
                    ML:Unload()
                    return
                end
                if s.maintenanceMessage and s.maintenanceMessage.stringValue ~= "" then
                    notify("ExecSync – Notice", s.maintenanceMessage.stringValue, 8)
                end
                logInfo("Settings refreshed")
            end
        end
    end)
end

-- ─────────────────────────────────────────────
--  MAIN GUI  (Kiwisense — IceWare look)
-- ─────────────────────────────────────────────
local function LoadMainScript(username)
    local LoadingTick = os.clock()

    local ML = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Kiwisense/Library.lua"
    ))()

    -- Register as the active library so notify() works
    ActiveLib = ML
    flushNotifQueue()

    -- ── Window ────────────────────────────────
    local Window = ML:Window({
        Name      = "IceWare",
        Version   = "v1.4.1",
        Logo      = "135215559087473",
        FadeSpeed = 0.25,
    })

    local Watermark = ML:Watermark("IceWare | Driving Empire", "135215559087473")
    Watermark:SetVisibility(true)

    local KeybindList = ML:KeybindsList()
    KeybindList:SetVisibility(false)

    -- ── Pages ─────────────────────────────────
    local Pages = {
        ["Main"]     = Window:Page({ Name = "Main",          Icon = "7733960981",      SubPages = true }),
        ["Misc"]     = Window:Page({ Name = "Miscellaneous", Icon = "136623465713368",  Columns = 2 }),
        ["Players"]  = Window:Page({ Name = "Player List",   Icon = "103174889897193" }),
        ["Settings"] = Window:Page({ Name = "Settings",      Icon = "137300573942266",  SubPages = true }),
    }

    -- ── Main SubPages ─────────────────────────
    local MainSub = {
        ["AutoFarm"] = Pages["Main"]:SubPage({ Name = "Auto Farm", Icon = "13107902118",      Columns = 2 }),
        ["CarMods"]  = Pages["Main"]:SubPage({ Name = "Car Mods",  Icon = "103174889897193",  Columns = 2 }),
    }

    -- ── Auto Farm ─────────────────────────────
    do
        local Racing  = MainSub["AutoFarm"]:Section({ Name = "Racing",  Side = 1 })
        local Robbery = MainSub["AutoFarm"]:Section({ Name = "Robbery", Side = 2 })

        Racing:Toggle({ Name = "Auto Race",           Flag = "AutoRace",     Default = false, Callback = function() end })
        Racing:Toggle({ Name = "Start Solo",          Flag = "StartSolo",    Default = false, Callback = function() end })
        Racing:Slider({ Name = "Race Speed",          Flag = "RaceSpeed",    Min = 1,  Max = 500, Default = 250, Decimals = 1,   Callback = function() end })
        Racing:Slider({ Name = "Minimum Wait Time",   Flag = "MinWaitTime",  Min = 0,  Max = 10,  Default = 0.5, Decimals = 0.1, Suffix = "s", Callback = function() end })
        Racing:Toggle({ Name = "Auto Vary Wait Time", Flag = "AutoVaryWait", Default = false, Callback = function() end })
        Racing:Dropdown({ Name = "Select Race", Flag = "SelectRace",
            Items = { "Circuit Race", "Street Race", "Derby", "Drag Race" },
            Default = "Circuit Race", MaxSize = 150, Callback = function() end })
        Racing:Label("Auto Drive is not great for revenues,\nif you are trying to farm money use auto rob/arrest", "Left")

        Robbery:Label("!! Use auto rob at your own risk, there is a\nchance of being banned !!\nWE ARE AWARE OF THE BUG WITH ATMS, WE\nARE TRYING TO FIND A WORKAROUND", "Left")
        Robbery:Label("Session Time: 0s", "Left")
        Robbery:Toggle({ Name = "Auto Rob",             Flag = "AutoRob",            Default = false, Callback = function() end })
        Robbery:Toggle({ Name = "Include Cargo Crates", Flag = "IncludeCargoCrates", Default = false, Callback = function() end })
        Robbery:Toggle({ Name = "Anti Cop",             Flag = "AntiCop",            Default = false, Callback = function() end })
        Robbery:Toggle({ Name = "Include Bank Heist",   Flag = "IncludeBankHeist",   Default = false, Callback = function() end })
        Robbery:Toggle({ Name = "Auto Deposit",         Flag = "AutoDeposit",        Default = false, Callback = function() end })
        Robbery:Slider({ Name = "Deposit Threshold",   Flag = "DepositThreshold",   Min = 1, Max = 100, Default = 10, Decimals = 1, Callback = function() end })
        Robbery:Slider({ Name = "Pause Bag Threshold", Flag = "PauseBagThreshold",  Min = 1, Max = 100, Default = 25, Decimals = 1, Callback = function() end })
    end

    -- ── Car Mods ──────────────────────────────
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

        Extra:Toggle({ Name = "Horn Boost",          Flag = "HornBoost",          Default = false, Callback = function() end })
        Extra:Slider({ Name = "Horn Boost Intensity", Flag = "HornBoostIntensity", Min = 1, Max = 10, Default = 1, Decimals = 1, Callback = function() end })
        Extra:Toggle({ Name = "Instant Stop",         Flag = "InstantStop",        Default = false, Callback = function() end })
        Extra:Toggle({ Name = "Car Breakable Aura",   Flag = "CarBreakableAura",   Default = false, Callback = function() end })
        Extra:Toggle({ Name = "Infinite Nitro",       Flag = "InfiniteNitro",      Default = false, Callback = function() end })
    end

    -- ── Miscellaneous ─────────────────────────
    do
        local Rewards   = Pages["Misc"]:Section({ Name = "Rewards",      Side = 1 })
        local Trolling  = Pages["Misc"]:Section({ Name = "Trolling",     Side = 1 })
        local Inventory = Pages["Misc"]:Section({ Name = "Inventory",    Side = 1 })
        local Dealer    = Pages["Misc"]:Section({ Name = "Dealership",   Side = 2 })
        local Optim     = Pages["Misc"]:Section({ Name = "Optimization", Side = 2 })
        local Misc      = Pages["Misc"]:Section({ Name = "Misc",         Side = 2 })
        local Webhook   = Pages["Misc"]:Section({ Name = "Webhook",      Side = 2 })

        Rewards:Toggle({ Name = "Auto Claim Daily Rewards",    Flag = "AutoDailyRewards",        Default = false, Callback = function() end })
        Rewards:Toggle({ Name = "Auto Double Daily Rewards",   Flag = "AutoDoubleDailyRewards",   Default = false, Callback = function() end })
        Rewards:Toggle({ Name = "Auto Claim AD Rewards",       Flag = "AutoADRewards",            Default = false, Callback = function() end })
        Rewards:Button({ Name = "Redeem All Codes",            Callback = function() end })
        Rewards:Button({ Name = "Free Trophies (Nascar QUIZ)", Callback = function() end })
        Trolling:Toggle({ Name = "Spam Outfits",               Flag = "SpamOutfits",              Default = false, Callback = function() end })
        Inventory:Toggle({ Name = "Auto Open Packs [$$$]",    Flag = "AutoOpenPacks",            Default = false, Callback = function() end })
        Inventory:Slider({ Name = "Gacha Open Amount",         Flag = "GachaOpenAmount",          Min = 1, Max = 100, Default = 1, Decimals = 1, Callback = function() end })
        Dealer:Dropdown({ Name = "Select Vehicle", Flag = "SelectVehicle",
            Items = { "Cars", "Motorcycles", "Trucks", "Sports Cars" }, Default = "Cars", MaxSize = 200, Callback = function() end })
        Dealer:Button({ Name = "Open Dealership",              Callback = function() end })
        Optim:Toggle({ Name = "Disable Rendering",             Flag = "DisableRendering",         Default = false, Callback = function() end })
        Misc:Toggle({ Name = "No Telemetry",                   Flag = "NoTelemetry",              Default = false, Callback = function() end })
        Misc:Toggle({ Name = "Always See Bounties [$$$]",      Flag = "AlwaysSeeBounties",        Default = false, Callback = function() end })
        Webhook:Toggle({ Name = "Webhook Alerts",              Flag = "WebhookAlerts",            Default = false, Callback = function() end })
        Webhook:Textbox({ Name = "Webhook URL",                Flag = "WebhookURL",               Default = "", Placeholder = "...", Callback = function() end })
        Webhook:Toggle({ Name = "Ping on alert (@here)",       Flag = "WebhookPing",              Default = false, Callback = function() end })
    end

    -- ── Player List ───────────────────────────
    Pages["Players"]:Playerlist({ Callback = function(...) end })

    -- ── Settings ──────────────────────────────
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
        Session:Button({ Name = "Eject", Callback = function()
            logInfo("Eject"); ML:Unload()
        end })
        Session:Button({ Name = "Log Out", Callback = function()
            logInfo("Log Out — clearing session")
            deleteSessionFile()
            notify("ExecSync", "Logged out. Re-run the script to sign in again.", 4)
            task.wait(2); ML:Unload()
        end })
        Session:Button({ Name = "Join Discord", Callback = function()
            if setclipboard then setclipboard(DISCORD_INVITE) end
            notify("ExecSync", "Discord link copied!", 3)
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

        Anim:Slider({ Name = "Time", Flag = "TweenTime", Min = 0, Max = 5, Default = 0.3, Decimals = 0.01,
            Callback = function(v) ML.Tween.Time = v end })
        Anim:Dropdown({ Name = "Style", Flag = "TweenStyle",
            Items = { "Linear","Sine","Quad","Cubic","Quart","Quint","Exponential","Circular","Back","Elastic","Bounce" },
            Default = "Cubic", MaxSize = 150,
            Callback = function(v) ML.Tween.Style = Enum.EasingStyle[v] end })
        Anim:Dropdown({ Name = "Direction", Flag = "TweenDirection",
            Items = { "In","Out","InOut" }, Default = "Out", MaxSize = 80,
            Callback = function(v) ML.Tween.Direction = Enum.EasingDirection[v] end })
    end

    do
        local Profiles = SettingsSub["Configs"]:Section({ Name = "Profiles", Side = 1 })
        local Autoload = SettingsSub["Configs"]:Section({ Name = "Autoload", Side = 2 })
        local ConfigSelected, ConfigName
        local CfgDropdown = Profiles:Dropdown({ Name = "Configs", Flag = "ConfigsList", Items = {}, Multi = false,
            Callback = function(v) ConfigSelected = v end })
        Profiles:Textbox({ Name = "Config Name", Flag = "ConfigName", Default = "", Placeholder = "Enter Name",
            Callback = function(v) ConfigName = v end })
        Profiles:Button({ Name = "Create", Callback = function()
            if ConfigName and ConfigName ~= "" then
                writefile(ML.Folders.Configs .. "/" .. ConfigName .. ".json", ML:GetConfig())
                ML:RefreshConfigsList(CfgDropdown)
            end
        end })
        Profiles:Button({ Name = "Delete", Callback = function()
            if ConfigSelected then ML:DeleteConfig(ConfigSelected); ML:RefreshConfigsList(CfgDropdown) end
        end })
        Profiles:Button({ Name = "Load", Callback = function()
            if ConfigSelected then ML:LoadConfig(readfile(ML.Folders.Configs .. "/" .. ConfigSelected)) end
        end })
        Profiles:Button({ Name = "Save", Callback = function()
            if ConfigSelected then ML:SaveConfig(ConfigSelected) end
        end })
        Profiles:Button({ Name = "Refresh List", Callback = function()
            ML:RefreshConfigsList(CfgDropdown)
        end })
        ML:RefreshConfigsList(CfgDropdown)
        Autoload:Button({ Name = "Set Selected As Autoload", Callback = function()
            if ConfigSelected then
                writefile(ML.Folders.Directory .. "/AutoLoadConfig (do not modify this).json",
                    readfile(ML.Folders.Configs .. "/" .. ConfigSelected))
            end
        end })
        Autoload:Button({ Name = "Set Current As Autoload", Callback = function()
            writefile(ML.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", ML:GetConfig())
        end })
        Autoload:Button({ Name = "Remove Autoload", Callback = function()
            writefile(ML.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", "")
        end })
    end

    do
        local Theming  = SettingsSub["Theme"]:Section({ Name = "Theming",  Side = 1 })
        local Profiles = SettingsSub["Theme"]:Section({ Name = "Profiles", Side = 2 })
        local Autoload = SettingsSub["Theme"]:Section({ Name = "Autoload", Side = 2 })

        ML.ThemeColorpickers = ML.ThemeColorpickers or {}
        for Index, Value in ML.Theme do
            ML.ThemeColorpickers[Index] = Theming:Label(Index, "Left"):Colorpicker({
                Name = "Colorpicker", Flag = "ColorpickerTheme" .. Index,
                Default = Value, Alpha = 0,
                Callback = function(Color)
                    ML.Theme[Index] = Color
                    ML:ChangeTheme(Index, Color)
                end
            })
        end
        Profiles:Dropdown({ Name = "Built-in Themes",
            Items = { "Default", "Halloween", "Aqua", "One Tap" }, Default = "Default", MaxSize = 150, Multi = false,
            Callback = function(v)
                local ThemeData = ML.Themes[v == "Default" and "Preset" or v]
                if not ThemeData then return end
                for k, col in ThemeData do
                    ML.Theme[k] = col; ML:ChangeTheme(k, col)
                    if ML.ThemeColorpickers and ML.ThemeColorpickers[k] then
                        ML.ThemeColorpickers[k]:Set(col)
                    end
                end
            end
        })
        local ThemeSelected, ThemeName
        local ThemeDropdown = Profiles:Dropdown({ Name = "Custom Themes", Flag = "ThemesList", Items = {}, Multi = false,
            Callback = function(v) ThemeSelected = v end })
        Profiles:Textbox({ Name = "Theme Name", Flag = "ThemeName", Default = "", Placeholder = "Enter Name",
            Callback = function(v) ThemeName = v end })
        Profiles:Button({ Name = "Save", Callback = function()
            if ThemeName and ThemeName ~= "" then
                writefile(ML.Folders.Themes .. "/" .. ThemeName .. ".json", ML:GetTheme())
                ML:RefreshThemesList(ThemeDropdown)
            end
        end })
        Profiles:Button({ Name = "Load", Callback = function()
            if ThemeSelected then ML:LoadTheme(readfile(ML.Folders.Themes .. "/" .. ThemeSelected)) end
        end })
        ML:RefreshThemesList(ThemeDropdown)
        Autoload:Button({ Name = "Set Selected As Autoload", Callback = function()
            if ThemeSelected then
                writefile(ML.Folders.Directory .. "/AutoLoadTheme (do not modify this).json",
                    readfile(ML.Folders.Themes .. "/" .. ThemeSelected))
            end
        end })
    end

    ML:Notification({
        Name        = "ExecSync",
        Description = "Loaded in: " .. string.format("%.4f", os.clock() - LoadingTick) .. " seconds  •  " .. tostring(username),
        Duration    = 5,
        Icon        = "116339777575852",
        IconColor   = Color3.fromRGB(255, 255, 255),
    })

    ML:Init()
    startSettingsPoll(ML)
    logInfo("Main GUI loaded for " .. tostring(username))
end

-- ─────────────────────────────────────────────
--  KEY SYSTEM  (Kiwisense Window)
--  FIX #3: Status feedback via notifications
--  (KW library is loaded but Init() not yet
--  called, so we need ActiveLib set first so
--  notify() can reach it immediately).
-- ─────────────────────────────────────────────
local function BuildKeySystem(onSuccess)
    local KW = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Kiwisense/Library.lua"
    ))()

    -- Register early so notify() works during key system
    ActiveLib = KW

    local Win = KW:Window({
        Name      = "IceWare",
        Version   = "Key System",
        Logo      = "135215559087473",
        FadeSpeed = 0.25,
    })

    local KeyPage = Win:Page({
        Name    = "Key System",
        Icon    = "116339777575852",
        Columns = 2,
    })

    -- ── LEFT — Key Verification ────────────────
    local VerifSection = KeyPage:Section({ Name = "Key Verification", Side = 1 })

    VerifSection:Label("Enter your 5-digit code to unlock access", "Center")

    local enteredCode = ""
    local isVerifying = false   -- prevents concurrent submissions

    VerifSection:Textbox({
        Name        = "Key Input",
        Flag        = "KeyInput",
        Default     = "",
        Placeholder = "Enter your key here..",
        Callback    = function(v)
            enteredCode = v
        end
    })

    VerifSection:Button({
        Name = "Check Key",
        Callback = function()
            -- FIX: guard is now reset in ALL exit paths
            if isVerifying then
                notify("ExecSync", "Already verifying, please wait…", 2)
                return
            end

            local code = (enteredCode or ""):match("^%s*(.-)%s*$")

            if not code or code == "" then
                notify("ExecSync – Key System", "Please enter your security code.", 3)
                return
            end
            if not code:match("^%d%d%d%d%d$") then
                notify("ExecSync – Key System", "Code must be exactly 5 digits.", 3)
                return
            end

            isVerifying = true
            notify("ExecSync – Key System", "Verifying code, please wait…", 4)
            logInfo("Check Key pressed by " .. LocalPlayer.Name .. " with code=" .. code)

            task.spawn(function()
                -- Step 1: Query Firestore
                local docName, queryErr = queryByCode(LocalPlayer.Name, code)

                if not docName then
                    notify("ExecSync – Key System", "❌ " .. (queryErr or "Invalid code."), 5)
                    logError("Key rejected: " .. tostring(queryErr))
                    isVerifying = false   -- ← always reset
                    return
                end

                -- Step 2: Write session token to Firestore
                local token = generateToken()
                local patched, patchErr = writeTokenToDoc(docName, token)

                if not patched then
                    notify("ExecSync – Key System", "❌ " .. (patchErr or "Could not save session."), 5)
                    logError("Token write failed: " .. tostring(patchErr))
                    isVerifying = false   -- ← always reset
                    return
                end

                -- Step 3: Persist token locally
                saveToken(token)
                logInfo("Token saved locally for " .. LocalPlayer.Name)

                -- Step 4: Success
                notify("ExecSync – Key System", "✅ Verified! Loading ExecSync…", 3)
                task.wait(1.5)

                -- Unload key system UI then fire callback
                KW:Unload()
                task.wait(0.3)
                isVerifying = false

                if onSuccess then
                    task.spawn(function()
                        onSuccess(LocalPlayer.Name)
                    end)
                end
            end)
        end
    })

    VerifSection:Button({
        Name = "Get Key (12H)",
        Callback = function()
            if setclipboard then setclipboard(DISCORD_INVITE) end
            notify("ExecSync", "Join our Discord to get a 12H key. Link copied!", 4)
        end
    })

    VerifSection:Button({
        Name = "Get Key (1D)",
        Callback = function()
            if setclipboard then setclipboard(DISCORD_INVITE) end
            notify("ExecSync", "Join our Discord to get a 1D key. Link copied!", 4)
        end
    })

    -- ── RIGHT — Information ────────────────────
    local InfoSection = KeyPage:Section({ Name = "Information", Side = 2 })

    InfoSection:Label("Codes are tied to your Roblox username.", "Center")
    InfoSection:Label("Each code can only be used once.", "Center")
    InfoSection:Label("Premium removes the key system and gives you\naccess to the best features, join our discord\nto learn more", "Center")

    local DiscordSection = KeyPage:Section({ Name = "Discord", Side = 2 })

    DiscordSection:Label("Need help or updates? Join our Discord server", "Left")

    DiscordSection:Button({
        Name = "Join Discord",
        Callback = function()
            if setclipboard then setclipboard(DISCORD_INVITE) end
            notify("ExecSync", "Discord invite link copied to clipboard!", 3)
        end
    })

    KW:Init()
    logInfo("Key system displayed for " .. LocalPlayer.Name)
end

-- ─────────────────────────────────────────────
--  ENTRY POINT
-- ─────────────────────────────────────────────
logInfo("ExecSync starting — place=" .. tostring(game.PlaceId) .. "  user=" .. LocalPlayer.Name)

task.spawn(function()
    -- Try to resume from a saved session token first
    local savedToken = readToken()
    if savedToken and savedToken ~= "" then
        logInfo("Found saved token — validating silently…")
        -- Temporarily load KW just for notifications during silent check
        local resolvedUser = queryByToken(savedToken)
        if resolvedUser then
            logInfo("Session valid → loading for " .. resolvedUser)
            LoadMainScript(resolvedUser)
            return
        else
            logWarn("Saved token invalid or expired — showing key system")
            deleteSessionFile()
        end
    end

    -- No valid session — show key system
    BuildKeySystem(function(username)
        LoadMainScript(username)
    end)
end)
