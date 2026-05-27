-- ╔══════════════════════════════════════════════════════╗
-- ║         ExecSync  v1.4.1                             ║
-- ║   IceWare-style UI  +  Firestore Token Auth          ║
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
--  Kiwisense (used only for main GUI after auth)
-- ─────────────────────────────────────────────
local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Kiwisense/Library.lua"
))()

-- ─────────────────────────────────────────────
--  COLOUR PALETTE  (IceWare dark theme)
-- ─────────────────────────────────────────────
local C = {
    BG        = Color3.fromRGB(18,  18,  18),
    Panel     = Color3.fromRGB(26,  26,  26),
    Border    = Color3.fromRGB(45,  45,  45),
    TitleBar  = Color3.fromRGB(22,  22,  22),
    TextPrim  = Color3.fromRGB(230, 230, 230),
    TextSub   = Color3.fromRGB(150, 150, 150),
    TextDim   = Color3.fromRGB(100, 100, 100),
    Btn       = Color3.fromRGB(38,  38,  38),
    BtnHov    = Color3.fromRGB(52,  52,  52),
    BtnBorder = Color3.fromRGB(60,  60,  60),
    Input     = Color3.fromRGB(22,  22,  22),
    InputBord = Color3.fromRGB(55,  55,  55),
    Success   = Color3.fromRGB(80,  200, 120),
    Error     = Color3.fromRGB(220, 80,  80),
    Divider   = Color3.fromRGB(40,  40,  40),
    Logo      = Color3.fromRGB(140, 200, 255),
}

-- ─────────────────────────────────────────────
--  UI HELPERS
-- ─────────────────────────────────────────────
local function New(class, props, children)
    local inst = Instance.new(class)
    for k, v in props do inst[k] = v end
    for _, child in (children or {}) do child.Parent = inst end
    return inst
end
local function Corner(r) return New("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function Stroke(color, thickness) return New("UIStroke", { Color = color, Thickness = thickness or 1 }) end
local function Padding(t, b, l, r)
    return New("UIPadding", {
        PaddingTop    = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
        PaddingLeft   = UDim.new(0, l or 0), PaddingRight  = UDim.new(0, r or 0),
    })
end
local function ListLayout(dir, align, pad)
    return New("UIListLayout", {
        FillDirection       = dir   or Enum.FillDirection.Vertical,
        HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
        SortOrder           = Enum.SortOrder.LayoutOrder,
        Padding             = UDim.new(0, pad or 0),
    })
end
local function Tween(inst, props, t)
    TweenService:Create(inst, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad), props):Play()
end

-- ─────────────────────────────────────────────
--  REMOTE LOGGER
-- ─────────────────────────────────────────────
local function remoteLog(level, message)
    print("[ExecSync][" .. level .. "] " .. tostring(message))
    task.spawn(function()
        pcall(function()
            request({
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
                        { fieldFilter = { field = { fieldPath = "code" },     op = "EQUAL", value = { stringValue = tostring(code) } } },
                    }
                }
            },
            limit = 1,
        }
    })
    local ok, response = pcall(function()
        return request({ Url = QUERY_URL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
    end)
    if not ok then logError("queryByCode failed: " .. tostring(response)); return nil, "Network error." end
    if response.StatusCode ~= 200 then logError("queryByCode HTTP " .. response.StatusCode); return nil, "Server error (" .. response.StatusCode .. ")." end
    local parsed = HttpService:JSONDecode(response.Body)
    if type(parsed) ~= "table" or not parsed[1] or not parsed[1].document then
        logWarn("queryByCode: no match"); return nil, "Invalid code."
    end
    return parsed[1].document.name, nil
end

local function writeTokenToDoc(docName, token)
    local patchUrl = "https://firestore.googleapis.com/v1/" .. docName
        .. "?updateMask.fieldPaths=used&updateMask.fieldPaths=sessionToken"
    local ok, response = pcall(function()
        return request({
            Url = patchUrl, Method = "PATCH",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({ fields = {
                used         = { booleanValue = true },
                sessionToken = { stringValue  = token },
            }}),
        })
    end)
    if not ok or response.StatusCode ~= 200 then logError("writeTokenToDoc failed"); return false end
    logInfo("writeTokenToDoc: OK")
    return true
end

local function queryByToken(token)
    logInfo("queryByToken: " .. token:sub(1, 8) .. "…")
    local body = HttpService:JSONEncode({
        structuredQuery = {
            from  = {{ collectionId = "verificationCodes" }},
            where = { fieldFilter = {
                field = { fieldPath = "sessionToken" }, op = "EQUAL", value = { stringValue = token }
            }},
            limit = 1,
        }
    })
    local ok, response = pcall(function()
        return request({ Url = QUERY_URL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
    end)
    if not ok or response.StatusCode ~= 200 then logError("queryByToken failed"); return nil end
    local parsed = HttpService:JSONDecode(response.Body)
    if type(parsed) ~= "table" or not parsed[1] or not parsed[1].document then logWarn("queryByToken: not found"); return nil end
    local fields = parsed[1].document.fields
    if fields and fields.username and fields.username.stringValue then
        logInfo("queryByToken → " .. fields.username.stringValue)
        return fields.username.stringValue
    end
    return nil
end

local function fetchRemoteSettings()
    local ok, response = pcall(function()
        return request({ Url = FIRESTORE_BASE .. "/settings/global", Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
    end)
    if not ok or response.StatusCode ~= 200 then return nil end
    local parsed = HttpService:JSONDecode(response.Body)
    return parsed and parsed.fields or nil
end

-- ─────────────────────────────────────────────
--  SESSION HELPERS
-- ─────────────────────────────────────────────
local function saveToken(token)   pcall(function() writefile(SESSION_FILE, token) end) end
local function readToken()
    local ok = pcall(function() return isfile(SESSION_FILE) end)
    if not ok or not isfile(SESSION_FILE) then return nil end
    local t = readfile(SESSION_FILE)
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
local function startSettingsPoll(mainLib)
    task.spawn(function()
        while true do
            task.wait(300)
            local s = fetchRemoteSettings()
            if s then
                if s.killSwitch and s.killSwitch.booleanValue == true then
                    logWarn("Kill switch activated")
                    mainLib:Notification({ Name = "ExecSync", Description = "Script disabled remotely.", Duration = 6 })
                    task.wait(3); mainLib:Unload(); return
                end
                if s.maintenanceMessage and s.maintenanceMessage.stringValue ~= "" then
                    mainLib:Notification({ Name = "ExecSync – Notice", Description = s.maintenanceMessage.stringValue, Duration = 8, Icon = "116339777575852" })
                end
                logInfo("Settings refreshed")
            end
        end
    end)
end

-- ─────────────────────────────────────────────
--  MAIN EXECSYNC GUI  (Kiwisense — IceWare look)
-- ─────────────────────────────────────────────
local function LoadMainScript(username)
    pcall(function() Library:Unload() end)
    task.wait(0.3)

    local LoadingTick = os.clock()
    local ML = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Kiwisense/Library.lua"
    ))()

    local Window = ML:Window({
        Name      = "ExecSync",
        Version   = "v1.4.1",
        Logo      = "135215559087473",
        FadeSpeed = 0.25,
    })

    local Watermark = ML:Watermark("ExecSync | Driving Empire", "135215559087473")
    Watermark:SetVisibility(true)

    local KeybindList = ML:KeybindsList()
    KeybindList:SetVisibility(false)

    local Pages = {
        ["Main"]          = Window:Page({ Name = "Main",          Icon = "7733960981",     SubPages = true }),
        ["Miscellaneous"] = Window:Page({ Name = "Miscellaneous", Icon = "136623465713368", Columns = 2 }),
        ["PlayerList"]    = Window:Page({ Name = "Player List",   Icon = "103174889897193" }),
        ["Settings"]      = Window:Page({ Name = "Settings",      Icon = "137300573942266", SubPages = true }),
    }

    local MainSubpages = {
        ["AutoFarm"] = Pages["Main"]:SubPage({ Name = "Auto Farm", Icon = "13107902118",     Columns = 2 }),
        ["CarMods"]  = Pages["Main"]:SubPage({ Name = "Car Mods",  Icon = "103174889897193", Columns = 2 }),
    }

    -- ── Auto Farm ────────────────────────────
    do
        local RacingSection  = MainSubpages["AutoFarm"]:Section({ Name = "Racing",  Side = 1 })
        local RobberySection = MainSubpages["AutoFarm"]:Section({ Name = "Robbery", Side = 2 })

        RacingSection:Toggle({ Name = "Auto Race",           Flag = "AutoRace",     Default = false, Callback = function(v) end })
        RacingSection:Toggle({ Name = "Start Solo",          Flag = "StartSolo",    Default = false, Callback = function(v) end })
        RacingSection:Slider({ Name = "Race Speed",          Flag = "RaceSpeed",    Min = 1,  Max = 500, Default = 250, Decimals = 1,   Callback = function(v) end })
        RacingSection:Slider({ Name = "Minimum Wait Time",   Flag = "MinWaitTime",  Min = 0,  Max = 10,  Default = 0.5, Decimals = 0.1, Suffix = "s", Callback = function(v) end })
        RacingSection:Toggle({ Name = "Auto Vary Wait Time", Flag = "AutoVaryWait", Default = false, Callback = function(v) end })
        RacingSection:Dropdown({ Name = "Select Race", Flag = "SelectRace",
            Items = { "Circuit Race", "Street Race", "Derby", "Drag Race" }, Default = "Circuit Race", MaxSize = 150,
            Callback = function(v) end })
        RacingSection:Label("Auto Drive is not great for revenues,\nif you are trying to farm money use auto rob/arrest", "Left")

        RobberySection:Label("!! Use auto rob at your own risk, there is a\nchance of being banned !!\nWE ARE AWARE OF THE BUG WITH ATMS, WE\nARE TRYING TO FIND A WORKAROUND", "Left")
        RobberySection:Label("Session Time: 0s", "Left")
        RobberySection:Toggle({ Name = "Auto Rob",             Flag = "AutoRob",            Default = false, Callback = function(v) end })
        RobberySection:Toggle({ Name = "Include Cargo Crates", Flag = "IncludeCargoCrates", Default = false, Callback = function(v) end })
        RobberySection:Toggle({ Name = "Anti Cop",             Flag = "AntiCop",            Default = false, Callback = function(v) end })
        RobberySection:Toggle({ Name = "Include Bank Heist",   Flag = "IncludeBankHeist",   Default = false, Callback = function(v) end })
        RobberySection:Toggle({ Name = "Auto Deposit",         Flag = "AutoDeposit",        Default = false, Callback = function(v) end })
        RobberySection:Slider({ Name = "Deposit Threshold",   Flag = "DepositThreshold",   Min = 1, Max = 100, Default = 10, Decimals = 1, Callback = function(v) end })
        RobberySection:Slider({ Name = "Pause Bag Threshold", Flag = "PauseBagThreshold",  Min = 1, Max = 100, Default = 25, Decimals = 1, Callback = function(v) end })
    end

    -- ── Car Mods ──────────────────────────────
    do
        local PerfSection  = MainSubpages["CarMods"]:Section({ Name = "Performance",    Side = 1 })
        local ExtraSection = MainSubpages["CarMods"]:Section({ Name = "Extra Features", Side = 2 })

        PerfSection:Toggle({ Name = "Top Speed",   Flag = "TopSpeedEnabled",     Default = false, Callback = function(v) end })
        PerfSection:Slider({ Name = "Speed",        Flag = "TopSpeed",            Min = 1,   Max = 600, Default = 300, Decimals = 1,   Callback = function(v) end })
        PerfSection:Toggle({ Name = "Nitrous",      Flag = "NitrousEnabled",      Default = false, Callback = function(v) end })
        PerfSection:Slider({ Name = "Scale",        Flag = "NitrousScale",        Min = 0.1, Max = 10,  Default = 2,   Decimals = 0.1, Callback = function(v) end })
        PerfSection:Toggle({ Name = "Acceleration", Flag = "AccelerationEnabled", Default = false, Callback = function(v) end })
        PerfSection:Slider({ Name = "Scale",        Flag = "AccelerationScale",   Min = 0.1, Max = 10,  Default = 2,   Decimals = 0.1, Callback = function(v) end })
        PerfSection:Toggle({ Name = "Traction",     Flag = "TractionEnabled",     Default = false, Callback = function(v) end })
        PerfSection:Slider({ Name = "Scale",        Flag = "TractionScale",       Min = 0.1, Max = 10,  Default = 2,   Decimals = 0.1, Callback = function(v) end })

        ExtraSection:Toggle({ Name = "Horn Boost",           Flag = "HornBoost",          Default = false, Callback = function(v) end })
        ExtraSection:Slider({ Name = "Horn Boost Intensity", Flag = "HornBoostIntensity", Min = 1, Max = 10, Default = 1, Decimals = 1, Callback = function(v) end })
        ExtraSection:Toggle({ Name = "Instant Stop",         Flag = "InstantStop",        Default = false, Callback = function(v) end })
        ExtraSection:Toggle({ Name = "Car Breakable Aura",   Flag = "CarBreakableAura",   Default = false, Callback = function(v) end })
        ExtraSection:Toggle({ Name = "Infinite Nitro",       Flag = "InfiniteNitro",      Default = false, Callback = function(v) end })
    end

    -- ── Miscellaneous ─────────────────────────
    do
        local RewardsSection   = Pages["Miscellaneous"]:Section({ Name = "Rewards",      Side = 1 })
        local TrollingSection  = Pages["Miscellaneous"]:Section({ Name = "Trolling",     Side = 1 })
        local InventorySection = Pages["Miscellaneous"]:Section({ Name = "Inventory",    Side = 1 })
        local DealerSection    = Pages["Miscellaneous"]:Section({ Name = "Dealership",   Side = 2 })
        local OptimSection     = Pages["Miscellaneous"]:Section({ Name = "Optimization", Side = 2 })
        local MiscSection      = Pages["Miscellaneous"]:Section({ Name = "Misc",         Side = 2 })
        local WebhookSection   = Pages["Miscellaneous"]:Section({ Name = "Webhook",      Side = 2 })

        RewardsSection:Toggle({ Name = "Auto Claim Daily Rewards",    Flag = "AutoDailyRewards",      Default = false, Callback = function(v) end })
        RewardsSection:Toggle({ Name = "Auto Double Daily Rewards",   Flag = "AutoDoubleDailyRewards", Default = false, Callback = function(v) end })
        RewardsSection:Toggle({ Name = "Auto Claim AD Rewards",       Flag = "AutoADRewards",          Default = false, Callback = function(v) end })
        RewardsSection:Button({ Name = "Redeem All Codes",            Callback = function() end })
        RewardsSection:Button({ Name = "Free Trophies (Nascar QUIZ)", Callback = function() end })

        TrollingSection:Toggle({ Name = "Spam Outfits", Flag = "SpamOutfits", Default = false, Callback = function(v) end })

        InventorySection:Toggle({ Name = "Auto Open Packs [$$$]", Flag = "AutoOpenPacks",   Default = false, Callback = function(v) end })
        InventorySection:Slider({ Name = "Gacha Open Amount",     Flag = "GachaOpenAmount", Min = 1, Max = 100, Default = 1, Decimals = 1, Callback = function(v) end })

        DealerSection:Dropdown({ Name = "Select Vehicle", Flag = "SelectVehicle",
            Items = { "Cars", "Motorcycles", "Trucks", "Sports Cars" }, Default = "Cars", MaxSize = 200,
            Callback = function(v) end })
        DealerSection:Button({ Name = "Open Dealership", Callback = function() end })

        OptimSection:Toggle({ Name = "Disable Rendering",        Flag = "DisableRendering",  Default = false, Callback = function(v) end })
        MiscSection:Toggle({ Name = "No Telemetry",               Flag = "NoTelemetry",       Default = false, Callback = function(v) end })
        MiscSection:Toggle({ Name = "Always See Bounties [$$$]",  Flag = "AlwaysSeeBounties", Default = false, Callback = function(v) end })

        WebhookSection:Toggle({ Name = "Webhook Alerts",         Flag = "WebhookAlerts", Default = false, Callback = function(v) end })
        WebhookSection:Textbox({ Name = "Webhook URL",           Flag = "WebhookURL",    Default = "", Placeholder = "...", Callback = function(v) end })
        WebhookSection:Toggle({ Name = "Ping on alert (@here)",  Flag = "WebhookPing",   Default = false, Callback = function(v) end })
    end

    -- ── Player List ───────────────────────────
    Pages["PlayerList"]:Playerlist({ Callback = function(...) end })

    -- ── Settings ─────────────────────────────
    local SettingsSubpages = {
        ["Configuration"] = Pages["Settings"]:SubPage({ Name = "Configuration", Icon = "137300573942266", Columns = 2 }),
        ["Configs"]       = Pages["Settings"]:SubPage({ Name = "Configs",       Icon = "96491224522405",  Columns = 2 }),
        ["Theming"]       = Pages["Settings"]:SubPage({ Name = "Theming",       Icon = "103863157706913", Columns = 2 }),
    }

    do
        local SessionSection = SettingsSubpages["Configuration"]:Section({ Name = "Session",        Side = 1 })
        local UISection      = SettingsSubpages["Configuration"]:Section({ Name = "User Interface", Side = 2 })
        local AnimSection    = SettingsSubpages["Configuration"]:Section({ Name = "Animations",     Side = 2 })

        SessionSection:Label("Driving Empire", "Center")
        SessionSection:Label("Logged in as: " .. (username or LocalPlayer.Name), "Center")

        SessionSection:Button({ Name = "Rejoin", Callback = function()
            game:GetService("TeleportService"):Teleport(game.PlaceId)
        end })
        SessionSection:Button({ Name = "Server Hop", Callback = function()
            local TS = game:GetService("TeleportService")
            local HS = game:GetService("HttpService")
            local servers = HS:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            ))
            for _, server in ipairs(servers.data) do
                if server.id ~= game.JobId and server.playing < server.maxPlayers then
                    TS:TeleportToPlaceInstance(game.PlaceId, server.id); return
                end
            end
        end })
        SessionSection:Button({ Name = "Eject",   Callback = function() logInfo("Eject"); ML:Unload() end })
        SessionSection:Button({ Name = "Log Out", Callback = function()
            logInfo("Log Out — clearing session")
            deleteSessionFile()
            ML:Notification({ Name = "ExecSync", Description = "Logged out. Re-run the script to sign in again.", Duration = 4, Icon = "116339777575852" })
            task.wait(2); ML:Unload()
        end })
        SessionSection:Button({ Name = "Join Discord", Callback = function()
            if setclipboard then setclipboard(DISCORD_INVITE) end
        end })

        UISection:Label("Menu Keybind", "Left"):Keybind({
            Name = "MenuKeybind", Flag = "MenuKeybind", Mode = "toggle", Default = Enum.KeyCode.RightControl,
            Callback = function() ML.MenuKeybind = ML.Flags["MenuKeybind"].Key end
        })
        UISection:Toggle({ Name = "Keybind List", Flag = "KeybindList", Default = false, Callback = function(v) KeybindList:SetVisibility(v) end })
        UISection:Toggle({ Name = "Watermark",    Flag = "Watermark",   Default = true,  Callback = function(v) Watermark:SetVisibility(v) end })

        AnimSection:Slider({ Name = "Time", Flag = "TweenTime", Min = 0, Max = 5, Default = 0.3, Decimals = 0.01, Callback = function(v) ML.Tween.Time = v end })
        AnimSection:Dropdown({ Name = "Style", Flag = "TweenStyle",
            Items = { "Linear","Sine","Quad","Cubic","Quart","Quint","Exponential","Circular","Back","Elastic","Bounce" },
            Default = "Cubic", MaxSize = 150, Callback = function(v) ML.Tween.Style = Enum.EasingStyle[v] end })
        AnimSection:Dropdown({ Name = "Direction", Flag = "TweenDirection",
            Items = { "In","Out","InOut" }, Default = "Out", MaxSize = 80, Callback = function(v) ML.Tween.Direction = Enum.EasingDirection[v] end })
    end

    do
        local ProfilesSection = SettingsSubpages["Configs"]:Section({ Name = "Profiles", Side = 1 })
        local AutoloadSection = SettingsSubpages["Configs"]:Section({ Name = "Autoload", Side = 2 })
        local ConfigSelected, ConfigName

        local ConfigsDropdown = ProfilesSection:Dropdown({
            Name = "Configs", Flag = "ConfigsList", Items = {}, Multi = false,
            Callback = function(v) ConfigSelected = v end
        })
        ProfilesSection:Textbox({ Name = "Config Name", Flag = "ConfigName", Default = "", Placeholder = "Enter Name", Callback = function(v) ConfigName = v end })
        ProfilesSection:Button({ Name = "Create", Callback = function()
            if ConfigName and ConfigName ~= "" then
                writefile(ML.Folders.Configs .. "/" .. ConfigName .. ".json", ML:GetConfig())
                ML:RefreshConfigsList(ConfigsDropdown)
            end
        end })
        ProfilesSection:Button({ Name = "Delete",       Callback = function() if ConfigSelected then ML:DeleteConfig(ConfigSelected); ML:RefreshConfigsList(ConfigsDropdown) end end })
        ProfilesSection:Button({ Name = "Load",         Callback = function() if ConfigSelected then ML:LoadConfig(readfile(ML.Folders.Configs .. "/" .. ConfigSelected)) end end })
        ProfilesSection:Button({ Name = "Save",         Callback = function() if ConfigSelected then ML:SaveConfig(ConfigSelected) end end })
        ProfilesSection:Button({ Name = "Refresh List", Callback = function() ML:RefreshConfigsList(ConfigsDropdown) end })
        ML:RefreshConfigsList(ConfigsDropdown)

        AutoloadSection:Button({ Name = "Set Selected As Autoload", Callback = function()
            if ConfigSelected then
                writefile(ML.Folders.Directory .. "/AutoLoadConfig (do not modify this).json",
                    readfile(ML.Folders.Configs .. "/" .. ConfigSelected))
            end
        end })
        AutoloadSection:Button({ Name = "Set Current As Autoload", Callback = function()
            writefile(ML.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", ML:GetConfig())
        end })
        AutoloadSection:Button({ Name = "Remove Autoload", Callback = function()
            writefile(ML.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", "")
        end })
    end

    do
        local ThemingSection  = SettingsSubpages["Theming"]:Section({ Name = "Theming",  Side = 1 })
        local ProfilesSection = SettingsSubpages["Theming"]:Section({ Name = "Profiles", Side = 2 })
        local AutoloadSection = SettingsSubpages["Theming"]:Section({ Name = "Autoload", Side = 2 })

        for Index, Value in ML.Theme do
            ML.ThemeColorpickers = ML.ThemeColorpickers or {}
            ML.ThemeColorpickers[Index] = ThemingSection:Label(Index, "Left"):Colorpicker({
                Name = "Colorpicker", Flag = "ColorpickerTheme" .. Index, Default = Value, Alpha = 0,
                Callback = function(Color) ML.Theme[Index] = Color; ML:ChangeTheme(Index, Color) end
            })
        end

        ProfilesSection:Dropdown({ Name = "Built-in Themes",
            Items = { "Default","Halloween","Aqua","One Tap" }, Default = "Default", MaxSize = 150, Multi = false,
            Callback = function(v)
                local Name = v == "Default" and "Preset" or v
                local ThemeData = ML.Themes[Name]; if not ThemeData then return end
                for k, col in ThemeData do
                    ML.Theme[k] = col; ML:ChangeTheme(k, col)
                    if ML.ThemeColorpickers and ML.ThemeColorpickers[k] then ML.ThemeColorpickers[k]:Set(col) end
                end
            end
        })

        local ThemeSelected, ThemeName
        local ThemesDropdown = ProfilesSection:Dropdown({ Name = "Custom Themes", Flag = "ThemesList", Items = {}, Multi = false, Callback = function(v) ThemeSelected = v end })
        ProfilesSection:Textbox({ Name = "Theme Name", Flag = "ThemeName", Default = "", Placeholder = "Enter Name", Callback = function(v) ThemeName = v end })
        ProfilesSection:Button({ Name = "Save", Callback = function()
            if ThemeName and ThemeName ~= "" then
                writefile(ML.Folders.Themes .. "/" .. ThemeName .. ".json", ML:GetTheme())
                ML:RefreshThemesList(ThemesDropdown)
            end
        end })
        ProfilesSection:Button({ Name = "Load", Callback = function()
            if ThemeSelected then ML:LoadTheme(readfile(ML.Folders.Themes .. "/" .. ThemeSelected)) end
        end })
        ML:RefreshThemesList(ThemesDropdown)

        AutoloadSection:Button({ Name = "Set Selected As Autoload", Callback = function()
            if ThemeSelected then
                writefile(ML.Folders.Directory .. "/AutoLoadTheme (do not modify this).json",
                    readfile(ML.Folders.Themes .. "/" .. ThemeSelected))
            end
        end })
    end

    ML:Notification({
        Name        = "ExecSync",
        Description = "Loaded in: " .. string.format("%.4f", os.clock() - LoadingTick) .. " seconds",
        Duration    = 5, Icon = "116339777575852",
        IconColor   = Color3.fromRGB(140, 200, 255),
    })

    ML:Init()
    startSettingsPoll(ML)
    logInfo("Main GUI loaded for " .. (username or "unknown"))
end

-- ─────────────────────────────────────────────
--  KEY SYSTEM UI  (pixel-perfect IceWare style)
-- ─────────────────────────────────────────────
local function BuildKeySystem(onSuccess)

    local Gui = New("ScreenGui", {
        Name = "ExecSyncKeySystem", ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 999, Parent = PlayerGui,
    })

    local Overlay = New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.45, ZIndex = 1, Parent = Gui,
    })

    local Win = New("Frame", {
        Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(740, 400),
        BackgroundColor3 = C.BG, ZIndex = 2, Parent = Gui,
    }, { Corner(8), Stroke(C.Border, 1) })

    -- ── Title Bar ────────────────────────────
    local TitleBar = New("Frame", {
        Name = "TitleBar", Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = C.TitleBar, ZIndex = 3, Parent = Win,
    }, { Corner(8) })

    New("Frame", { -- square off bottom corners
        Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 1, -8),
        BackgroundColor3 = C.TitleBar, BorderSizePixel = 0, ZIndex = 3, Parent = TitleBar,
    })
    New("UIStroke", { Color = C.Border, Thickness = 1, Parent = TitleBar })

    New("TextLabel", { -- "es" badge
        Text = "es", Size = UDim2.fromOffset(28, 20), Position = UDim2.fromOffset(10, 8),
        BackgroundColor3 = C.Logo, TextColor3 = C.BG,
        Font = Enum.Font.GothamBold, TextSize = 11, ZIndex = 4, Parent = TitleBar,
    }, { Corner(4) })

    New("TextLabel", { -- title text
        Text = "ExecSync    Key System",
        Size = UDim2.new(1, -120, 1, 0), Position = UDim2.fromOffset(46, 0),
        BackgroundTransparency = 1, TextColor3 = C.TextPrim,
        Font = Enum.Font.Gotham, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = TitleBar,
    })

    New("Frame", { -- vertical separator after "ExecSync"
        Size = UDim2.fromOffset(1, 18), Position = UDim2.new(0, 110, 0.5, -9),
        BackgroundColor3 = C.Border, BorderSizePixel = 0, ZIndex = 4, Parent = TitleBar,
    })

    local CloseBtn = New("TextButton", {
        Text = "×", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -32, 0.5, -14),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.GothamBold, TextSize = 18, ZIndex = 4, Parent = TitleBar,
    })
    New("TextButton", {
        Text = "−", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -60, 0.5, -14),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.GothamBold, TextSize = 18, ZIndex = 4, Parent = TitleBar,
    })
    CloseBtn.MouseButton1Click:Connect(function() Gui:Destroy() end)

    -- Drag
    do
        local dragging, dragStart, startPos
        TitleBar.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true; dragStart = i.Position; startPos = Win.Position
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
                local d = i.Position - dragStart
                Win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
    end

    -- ── Content ──────────────────────────────
    local Content = New("Frame", {
        Size = UDim2.new(1, 0, 1, -36), Position = UDim2.fromOffset(0, 36),
        BackgroundTransparency = 1, ZIndex = 3, Parent = Win,
    })

    New("Frame", { -- centre divider line
        Size = UDim2.new(0, 1, 1, -24), Position = UDim2.new(0.5, 0, 0, 12),
        BackgroundColor3 = C.Divider, BorderSizePixel = 0, ZIndex = 3, Parent = Content,
    })

    -- ── LEFT PANEL ───────────────────────────
    local Left = New("Frame", {
        Size = UDim2.new(0.5, -1, 1, 0), BackgroundTransparency = 1,
        ZIndex = 3, Parent = Content,
    }, { Padding(20, 20, 20, 20) })
    ListLayout(Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left, 8).Parent = Left

    New("TextLabel", {
        Text = "Identity Verification", Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1, TextColor3 = C.TextPrim,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 1, Parent = Left,
    })

    New("TextLabel", {
        Text = "Enter your 5-digit code to unlock access",
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(30, 30, 30),
        TextColor3 = C.TextSub, Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 4, LayoutOrder = 2, Parent = Left,
    }, { Corner(6) })

    New("TextLabel", {
        Text = "Security Code", Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 3, Parent = Left,
    })

    local CodeBox = New("TextBox", {
        PlaceholderText = "Enter your 5-digit code..",
        Text = "", Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = C.Input, TextColor3 = C.TextPrim,
        PlaceholderColor3 = C.TextDim, Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
        ZIndex = 4, LayoutOrder = 4, Parent = Left,
    }, { Corner(6), Stroke(C.InputBord), Padding(0, 0, 10, 10) })

    local StatusLabel = New("TextLabel", {
        Text = "", Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1, TextColor3 = C.Error,
        Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 4, LayoutOrder = 5, Parent = Left,
    })

    -- Check Key button (accent — matches IceWare's primary action button)
    local VerifyBtn = New("TextButton", {
        Text = "Verify Identity", Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = C.Logo, TextColor3 = C.BG,
        Font = Enum.Font.Gotham, TextSize = 12,
        ZIndex = 4, LayoutOrder = 6, Parent = Left, AutoButtonColor = false,
    }, { Corner(6), Stroke(C.BtnBorder) })
    VerifyBtn.MouseEnter:Connect(function() Tween(VerifyBtn, { BackgroundColor3 = Color3.fromRGB(160, 210, 255) }) end)
    VerifyBtn.MouseLeave:Connect(function() Tween(VerifyBtn, { BackgroundColor3 = C.Logo }) end)

    New("TextLabel", { -- divider label
        Text = "── restore a previous session ──",
        Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1,
        TextColor3 = C.TextDim, Font = Enum.Font.Gotham, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 4, LayoutOrder = 7, Parent = Left,
    })

    New("TextLabel", {
        Text = "Session Token", Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 8, Parent = Left,
    })

    local TokenBox = New("TextBox", {
        PlaceholderText = "Paste your session token..",
        Text = "", Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = C.Input, TextColor3 = C.TextPrim,
        PlaceholderColor3 = C.TextDim, Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
        ZIndex = 4, LayoutOrder = 9, Parent = Left,
    }, { Corner(6), Stroke(C.InputBord), Padding(0, 0, 10, 10) })

    local RestoreBtn = New("TextButton", {
        Text = "Restore Session", Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = C.Btn, TextColor3 = C.TextPrim,
        Font = Enum.Font.Gotham, TextSize = 12,
        ZIndex = 4, LayoutOrder = 10, Parent = Left, AutoButtonColor = false,
    }, { Corner(6), Stroke(C.BtnBorder) })
    RestoreBtn.MouseEnter:Connect(function() Tween(RestoreBtn, { BackgroundColor3 = C.BtnHov }) end)
    RestoreBtn.MouseLeave:Connect(function() Tween(RestoreBtn, { BackgroundColor3 = C.Btn }) end)

    -- ── RIGHT PANEL ──────────────────────────
    local Right = New("Frame", {
        Size = UDim2.new(0.5, -1, 1, 0), Position = UDim2.new(0.5, 1, 0, 0),
        BackgroundTransparency = 1, ZIndex = 3, Parent = Content,
    }, { Padding(20, 20, 20, 20) })
    ListLayout(Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left, 10).Parent = Right

    New("TextLabel", {
        Text = "Information", Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1, TextColor3 = C.TextPrim,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 1, Parent = Right,
    })

    local IB1 = New("Frame", {
        Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = C.Panel,
        ZIndex = 4, LayoutOrder = 2, Parent = Right,
    }, { Corner(6) })
    New("TextLabel", {
        Text = "Codes are tied to your Roblox username.\nEach code can only be used once.",
        Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5, Parent = IB1,
    })

    local IB2 = New("Frame", {
        Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = C.Panel,
        ZIndex = 4, LayoutOrder = 3, Parent = Right,
    }, { Corner(6) })
    New("TextLabel", {
        Text = "Sessions are saved locally and validated\nagainst the database each run.\nUse the token box to restore a previous session.",
        Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5, Parent = IB2,
    })

    New("TextLabel", {
        Text = "Discord", Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1, TextColor3 = C.TextPrim,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 4, Parent = Right,
    })

    New("TextLabel", {
        Text = "Need help or updates? Join our Discord server",
        Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1,
        TextColor3 = C.TextSub, Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 5, Parent = Right,
    })

    local DiscordBtn = New("TextButton", {
        Text = "Join Discord", Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = C.Btn, TextColor3 = C.TextPrim,
        Font = Enum.Font.Gotham, TextSize = 12,
        ZIndex = 4, LayoutOrder = 6, Parent = Right, AutoButtonColor = false,
    }, { Corner(6), Stroke(C.BtnBorder) })
    DiscordBtn.MouseEnter:Connect(function() Tween(DiscordBtn, { BackgroundColor3 = C.BtnHov }) end)
    DiscordBtn.MouseLeave:Connect(function() Tween(DiscordBtn, { BackgroundColor3 = C.Btn }) end)
    DiscordBtn.MouseButton1Click:Connect(function()
        if setclipboard then setclipboard(DISCORD_INVITE) end
        StatusLabel.Text = "Discord link copied!"; StatusLabel.TextColor3 = C.Success
    end)

    -- ── HELPERS ──────────────────────────────
    local function SetStatus(msg, isErr)
        StatusLabel.Text       = msg
        StatusLabel.TextColor3 = isErr and C.Error or C.Success
    end

    local function FinishAndLoad(resolvedUsername)
        SetStatus("✓ Verified! Loading ExecSync...", false)
        task.wait(1.2)
        Tween(Win,     { Position = UDim2.new(0.5, 0, 1.5, 0) }, 0.4)
        Tween(Overlay, { BackgroundTransparency = 1 },             0.4)
        task.wait(0.45)
        Gui:Destroy()
        if onSuccess then task.spawn(function() onSuccess(resolvedUsername) end) end
    end

    -- ── VERIFY IDENTITY ──────────────────────
    VerifyBtn.MouseButton1Click:Connect(function()
        local code = CodeBox.Text:match("^%s*(.-)%s*$")
        if code == "" then SetStatus("Please enter your security code.", true); return end
        if not code:match("^%d%d%d%d%d$") then SetStatus("Code must be exactly 5 digits.", true); return end

        SetStatus("Verifying…", false); StatusLabel.TextColor3 = C.TextSub
        VerifyBtn.Active = false

        task.spawn(function()
            local docName, err = queryByCode(LocalPlayer.Name, code)
            if not docName then
                SetStatus(err or "Invalid code.", true); VerifyBtn.Active = true; return
            end
            local token = generateToken()
            if not writeTokenToDoc(docName, token) then
                SetStatus("Could not save session. Try again.", true); VerifyBtn.Active = true; return
            end
            saveToken(token)
            FinishAndLoad(LocalPlayer.Name)
        end)
    end)

    -- ── RESTORE SESSION ───────────────────────
    RestoreBtn.MouseButton1Click:Connect(function()
        local token = TokenBox.Text:match("^%s*(.-)%s*$")
        if token == "" then SetStatus("Please paste your session token.", true); return end

        SetStatus("Checking token…", false); StatusLabel.TextColor3 = C.TextSub
        RestoreBtn.Active = false

        task.spawn(function()
            local resolvedUser = queryByToken(token)
            if not resolvedUser then
                SetStatus("Token not found. Check your dashboard.", true); RestoreBtn.Active = true; return
            end
            saveToken(token)
            FinishAndLoad(resolvedUser)
        end)
    end)

    -- Slide in from bottom
    Win.Position = UDim2.new(0.5, 0, 1.5, 0)
    Tween(Win, { Position = UDim2.fromScale(0.5, 0.5) }, 0.35)
end

-- ─────────────────────────────────────────────
--  ENTRY POINT
-- ─────────────────────────────────────────────
logInfo("ExecSync starting — place=" .. tostring(game.PlaceId) .. " user=" .. LocalPlayer.Name)

task.spawn(function()
    -- Silently validate saved token first — no UI shown
    local savedToken = readToken()
    if savedToken then
        logInfo("Found saved token — validating silently")
        local resolvedUser = queryByToken(savedToken)
        if resolvedUser then
            logInfo("Session valid → loading for " .. resolvedUser)
            LoadMainScript(resolvedUser)
            return
        else
            logWarn("Token invalid — deleting and showing key system")
            deleteSessionFile()
        end
    end

    -- Show IceWare-style key system
    BuildKeySystem(function(username)
        LoadMainScript(username)
    end)
end)
