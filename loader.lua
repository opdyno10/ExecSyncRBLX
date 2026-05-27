-- ╔══════════════════════════════════════════════════════╗
-- ║         ExecSync  v1.4.1                             ║
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
--  COLOUR PALETTE  (IceWare dark theme)
-- ─────────────────────────────────────────────
local C = {
    BG       = Color3.fromRGB(11,  10,  14),
    Panel    = Color3.fromRGB(22,  22,  26),
    Border   = Color3.fromRGB(29,  29,  33),
    TitleBar = Color3.fromRGB(14,  14,  19),
    TextPrim = Color3.fromRGB(255, 255, 255),
    TextSub  = Color3.fromRGB(185, 185, 185),
    TextDim  = Color3.fromRGB(100, 100, 100),
    Btn      = Color3.fromRGB(34,  39,  45),
    BtnHov   = Color3.fromRGB(49,  55,  64),
    BtnBord  = Color3.fromRGB(29,  29,  33),
    Input    = Color3.fromRGB(14,  14,  19),
    InpBord  = Color3.fromRGB(29,  29,  33),
    Success  = Color3.fromRGB(52,  255, 164),
    Error    = Color3.fromRGB(255, 80,  80),
    Accent   = Color3.fromRGB(255, 255, 255),
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
local function Corner(r)
    return New("UICorner", { CornerRadius = UDim.new(0, r) })
end
local function Stroke(color, thick)
    return New("UIStroke", {
        Color = color, Thickness = thick or 1,
        LineJoinMode = Enum.LineJoinMode.Miter
    })
end
local function Pad(t, b, l, r)
    return New("UIPadding", {
        PaddingTop    = UDim.new(0, t or 0),
        PaddingBottom = UDim.new(0, b or 0),
        PaddingLeft   = UDim.new(0, l or 0),
        PaddingRight  = UDim.new(0, r or 0),
    })
end
local function ListV(align, gap)
    return New("UIListLayout", {
        FillDirection       = Enum.FillDirection.Vertical,
        HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
        SortOrder           = Enum.SortOrder.LayoutOrder,
        Padding             = UDim.new(0, gap or 0),
    })
end
local function ListH(align, gap)
    return New("UIListLayout", {
        FillDirection       = Enum.FillDirection.Horizontal,
        HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
        SortOrder           = Enum.SortOrder.LayoutOrder,
        Padding             = UDim.new(0, gap or 0),
    })
end
local function Tw(inst, props, t)
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
    local ok, res = pcall(function()
        return request({ Url = QUERY_URL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
    end)
    if not ok then logError("queryByCode: " .. tostring(res)); return nil, "Network error." end
    if res.StatusCode ~= 200 then logError("queryByCode HTTP " .. res.StatusCode); return nil, "Server error (" .. res.StatusCode .. ")." end
    local parsed = HttpService:JSONDecode(res.Body)
    if type(parsed) ~= "table" or not parsed[1] or not parsed[1].document then
        logWarn("queryByCode: no match"); return nil, "Invalid code."
    end
    return parsed[1].document.name, nil
end

local function writeTokenToDoc(docName, token)
    local patchUrl = "https://firestore.googleapis.com/v1/" .. docName
        .. "?updateMask.fieldPaths=used&updateMask.fieldPaths=sessionToken"
    local ok, res = pcall(function()
        return request({
            Url = patchUrl, Method = "PATCH",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({ fields = {
                used         = { booleanValue = true },
                sessionToken = { stringValue  = token },
            }}),
        })
    end)
    if not ok or res.StatusCode ~= 200 then logError("writeTokenToDoc failed"); return false end
    logInfo("writeTokenToDoc: OK"); return true
end

local function queryByToken(token)
    logInfo("queryByToken: " .. token:sub(1, 8) .. "…")
    local body = HttpService:JSONEncode({
        structuredQuery = {
            from  = {{ collectionId = "verificationCodes" }},
            where = { fieldFilter = {
                field = { fieldPath = "sessionToken" }, op = "EQUAL",
                value = { stringValue = token }
            }},
            limit = 1,
        }
    })
    local ok, res = pcall(function()
        return request({ Url = QUERY_URL, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
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
        return request({ Url = FIRESTORE_BASE .. "/settings/global", Method = "GET", Headers = { ["Content-Type"] = "application/json" } })
    end)
    if not ok or res.StatusCode ~= 200 then return nil end
    local parsed = HttpService:JSONDecode(res.Body)
    return parsed and parsed.fields or nil
end

-- ─────────────────────────────────────────────
--  SESSION HELPERS
-- ─────────────────────────────────────────────
local function saveToken(t)   pcall(function() writefile(SESSION_FILE, t) end) end
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
local function startSettingsPoll(ML)
    task.spawn(function()
        while true do
            task.wait(300)
            local s = fetchRemoteSettings()
            if s then
                if s.killSwitch and s.killSwitch.booleanValue == true then
                    logWarn("Kill switch activated")
                    ML:Notification({ Name = "ExecSync", Description = "Script disabled remotely.", Duration = 6 })
                    task.wait(3); ML:Unload(); return
                end
                if s.maintenanceMessage and s.maintenanceMessage.stringValue ~= "" then
                    ML:Notification({ Name = "ExecSync – Notice", Description = s.maintenanceMessage.stringValue, Duration = 8, Icon = "116339777575852" })
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
        ["Main"]   = Window:Page({ Name = "Main",          Icon = "7733960981",      SubPages = true }),
        ["Misc"]   = Window:Page({ Name = "Miscellaneous", Icon = "136623465713368",  Columns = 2 }),
        ["Players"]= Window:Page({ Name = "Player List",   Icon = "103174889897193" }),
        ["Settings"] = Window:Page({ Name = "Settings",    Icon = "137300573942266",  SubPages = true }),
    }

    -- ── Main SubPages ─────────────────────────
    local MainSub = {
        ["AutoFarm"] = Pages["Main"]:SubPage({ Name = "Auto Farm", Icon = "13107902118",      Columns = 2 }),
        ["CarMods"]  = Pages["Main"]:SubPage({ Name = "Car Mods",  Icon = "103174889897193",  Columns = 2 }),
    }

    -- ────────────────────────────────────────────
    --  AUTO FARM  (matches screenshot 7)
    -- ────────────────────────────────────────────
    do
        local Racing  = MainSub["AutoFarm"]:Section({ Name = "Racing",  Side = 1 })
        local Robbery = MainSub["AutoFarm"]:Section({ Name = "Robbery", Side = 2 })

        -- Racing
        Racing:Toggle({ Name = "Auto Race",           Flag = "AutoRace",     Default = false, Callback = function() end })
        Racing:Toggle({ Name = "Start Solo",          Flag = "StartSolo",    Default = false, Callback = function() end })
        Racing:Slider({ Name = "Race Speed",          Flag = "RaceSpeed",    Min = 1,  Max = 500, Default = 250, Decimals = 1,   Callback = function() end })
        Racing:Slider({ Name = "Minimum Wait Time",   Flag = "MinWaitTime",  Min = 0,  Max = 10,  Default = 0.5, Decimals = 0.1, Suffix = "s", Callback = function() end })
        Racing:Toggle({ Name = "Auto Vary Wait Time", Flag = "AutoVaryWait", Default = false, Callback = function() end })
        Racing:Dropdown({
            Name = "Select Race", Flag = "SelectRace",
            Items = { "Circuit Race", "Street Race", "Derby", "Drag Race" },
            Default = "Circuit Race", MaxSize = 150,
            Callback = function() end
        })
        Racing:Label("Auto Drive is not great for revenues,\nif you are trying to farm money use auto rob/arrest", "Left")

        -- Robbery
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

    -- ────────────────────────────────────────────
    --  CAR MODS  (matches screenshot 8)
    -- ────────────────────────────────────────────
    do
        local Perf  = MainSub["CarMods"]:Section({ Name = "Performance",    Side = 1 })
        local Extra = MainSub["CarMods"]:Section({ Name = "Extra Features", Side = 2 })

        -- Performance
        Perf:Toggle({ Name = "Top Speed",   Flag = "TopSpeedEnabled",     Default = false, Callback = function() end })
        Perf:Slider({ Name = "Speed",        Flag = "TopSpeed",            Min = 1,   Max = 600, Default = 300, Decimals = 1,   Callback = function() end })
        Perf:Toggle({ Name = "Nitrous",      Flag = "NitrousEnabled",      Default = false, Callback = function() end })
        Perf:Slider({ Name = "Scale",        Flag = "NitrousScale",        Min = 0.1, Max = 10,  Default = 2,   Decimals = 0.1, Callback = function() end })
        Perf:Toggle({ Name = "Acceleration", Flag = "AccelerationEnabled", Default = false, Callback = function() end })
        Perf:Slider({ Name = "Scale",        Flag = "AccelerationScale",   Min = 0.1, Max = 10,  Default = 2,   Decimals = 0.1, Callback = function() end })
        Perf:Toggle({ Name = "Traction",     Flag = "TractionEnabled",     Default = false, Callback = function() end })
        Perf:Slider({ Name = "Scale",        Flag = "TractionScale",       Min = 0.1, Max = 10,  Default = 2,   Decimals = 0.1, Callback = function() end })

        -- Extra Features
        Extra:Toggle({ Name = "Horn Boost",           Flag = "HornBoost",          Default = false, Callback = function() end })
        Extra:Slider({ Name = "Horn Boost Intensity",  Flag = "HornBoostIntensity", Min = 1, Max = 10, Default = 1, Decimals = 1, Callback = function() end })
        Extra:Toggle({ Name = "Instant Stop",          Flag = "InstantStop",        Default = false, Callback = function() end })
        Extra:Toggle({ Name = "Car Breakable Aura",    Flag = "CarBreakableAura",   Default = false, Callback = function() end })
        Extra:Toggle({ Name = "Infinite Nitro",        Flag = "InfiniteNitro",      Default = false, Callback = function() end })
    end

    -- ────────────────────────────────────────────
    --  MISCELLANEOUS  (matches screenshots 9 & 10)
    -- ────────────────────────────────────────────
    do
        local Rewards   = Pages["Misc"]:Section({ Name = "Rewards",      Side = 1 })
        local Trolling  = Pages["Misc"]:Section({ Name = "Trolling",     Side = 1 })
        local Inventory = Pages["Misc"]:Section({ Name = "Inventory",    Side = 1 })
        local Dealer    = Pages["Misc"]:Section({ Name = "Dealership",   Side = 2 })
        local Optim     = Pages["Misc"]:Section({ Name = "Optimization", Side = 2 })
        local Misc      = Pages["Misc"]:Section({ Name = "Misc",         Side = 2 })
        local Webhook   = Pages["Misc"]:Section({ Name = "Webhook",      Side = 2 })

        -- Rewards
        Rewards:Toggle({ Name = "Auto Claim Daily Rewards",    Flag = "AutoDailyRewards",       Default = false, Callback = function() end })
        Rewards:Toggle({ Name = "Auto Double Daily Rewards",   Flag = "AutoDoubleDailyRewards",  Default = false, Callback = function() end })
        Rewards:Toggle({ Name = "Auto Claim AD Rewards",       Flag = "AutoADRewards",           Default = false, Callback = function() end })
        Rewards:Button({ Name = "Redeem All Codes",            Callback = function() end })
        Rewards:Button({ Name = "Free Trophies (Nascar QUIZ)", Callback = function() end })

        -- Trolling
        Trolling:Toggle({ Name = "Spam Outfits", Flag = "SpamOutfits", Default = false, Callback = function() end })

        -- Inventory
        Inventory:Toggle({ Name = "Auto Open Packs [$$$]", Flag = "AutoOpenPacks",   Default = false, Callback = function() end })
        Inventory:Slider({ Name = "Gacha Open Amount",     Flag = "GachaOpenAmount", Min = 1, Max = 100, Default = 1, Decimals = 1, Callback = function() end })

        -- Dealership
        Dealer:Dropdown({
            Name = "Select Vehicle", Flag = "SelectVehicle",
            Items = { "Cars", "Motorcycles", "Trucks", "Sports Cars" },
            Default = "Cars", MaxSize = 200,
            Callback = function() end
        })
        Dealer:Button({ Name = "Open Dealership", Callback = function() end })

        -- Optimization
        Optim:Toggle({ Name = "Disable Rendering",       Flag = "DisableRendering",  Default = false, Callback = function() end })

        -- Misc
        Misc:Toggle({ Name = "No Telemetry",              Flag = "NoTelemetry",       Default = false, Callback = function() end })
        Misc:Toggle({ Name = "Always See Bounties [$$$]", Flag = "AlwaysSeeBounties", Default = false, Callback = function() end })

        -- Webhook
        Webhook:Toggle({ Name = "Webhook Alerts",         Flag = "WebhookAlerts", Default = false, Callback = function() end })
        Webhook:Textbox({ Name = "Webhook URL",           Flag = "WebhookURL",    Default = "", Placeholder = "...", Callback = function() end })
        Webhook:Toggle({ Name = "Ping on alert (@here)",  Flag = "WebhookPing",   Default = false, Callback = function() end })
    end

    -- ────────────────────────────────────────────
    --  PLAYER LIST  (matches screenshot 1)
    -- ────────────────────────────────────────────
    Pages["Players"]:Playerlist({ Callback = function(...) end })

    -- ────────────────────────────────────────────
    --  SETTINGS  (matches screenshots 2, 3, 4)
    -- ────────────────────────────────────────────
    local SettingsSub = {
        ["Config"]  = Pages["Settings"]:SubPage({ Name = "Configuration", Icon = "137300573942266", Columns = 2 }),
        ["Configs"] = Pages["Settings"]:SubPage({ Name = "Configs",       Icon = "96491224522405",  Columns = 2 }),
        ["Theme"]   = Pages["Settings"]:SubPage({ Name = "Theming",       Icon = "103863157706913", Columns = 2 }),
    }

    -- ── Configuration (screenshot 2) ──────────
    do
        local Session = SettingsSub["Config"]:Section({ Name = "Session",        Side = 1 })
        local UI      = SettingsSub["Config"]:Section({ Name = "User Interface", Side = 2 })
        local Anim    = SettingsSub["Config"]:Section({ Name = "Animations",     Side = 2 })

        Session:Label("Driving Empire", "Center")
        Session:Label(username or LocalPlayer.Name, "Center")

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
            ML:Notification({
                Name = "ExecSync",
                Description = "Logged out. Re-run the script to sign in again.",
                Duration = 4, Icon = "116339777575852"
            })
            task.wait(2); ML:Unload()
        end })

        Session:Button({ Name = "Join Discord", Callback = function()
            if setclipboard then setclipboard(DISCORD_INVITE) end
            ML:Notification({ Name = "ExecSync", Description = "Discord link copied!", Duration = 3, Icon = "116339777575852" })
        end })

        -- User Interface
        UI:Label("Menu Keybind", "Left"):Keybind({
            Name    = "MenuKeybind",
            Flag    = "MenuKeybind",
            Mode    = "toggle",
            Default = Enum.KeyCode.RightControl,
            Callback = function() ML.MenuKeybind = ML.Flags["MenuKeybind"].Key end
        })
        UI:Toggle({ Name = "Keybind List", Flag = "KeybindList", Default = false, Callback = function(v) KeybindList:SetVisibility(v) end })
        UI:Toggle({ Name = "Watermark",    Flag = "Watermark",   Default = true,  Callback = function(v) Watermark:SetVisibility(v) end })

        -- Animations
        Anim:Slider({ Name = "Time", Flag = "TweenTime", Min = 0, Max = 5, Default = 0.3, Decimals = 0.01,
            Callback = function(v) ML.Tween.Time = v end })
        Anim:Dropdown({ Name = "Style", Flag = "TweenStyle",
            Items   = { "Linear","Sine","Quad","Cubic","Quart","Quint","Exponential","Circular","Back","Elastic","Bounce" },
            Default = "Cubic", MaxSize = 150,
            Callback = function(v) ML.Tween.Style = Enum.EasingStyle[v] end })
        Anim:Dropdown({ Name = "Direction", Flag = "TweenDirection",
            Items = { "In","Out","InOut" }, Default = "Out", MaxSize = 80,
            Callback = function(v) ML.Tween.Direction = Enum.EasingDirection[v] end })
    end

    -- ── Configs (screenshot 3) ─────────────────
    do
        local Profiles = SettingsSub["Configs"]:Section({ Name = "Profiles", Side = 1 })
        local Autoload = SettingsSub["Configs"]:Section({ Name = "Autoload", Side = 2 })

        local ConfigSelected, ConfigName

        local CfgDropdown = Profiles:Dropdown({
            Name = "Configs", Flag = "ConfigsList", Items = {}, Multi = false,
            Callback = function(v) ConfigSelected = v end
        })

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

    -- ── Theming (screenshot 4) ─────────────────
    do
        local Theming  = SettingsSub["Theme"]:Section({ Name = "Theming",  Side = 1 })
        local Profiles = SettingsSub["Theme"]:Section({ Name = "Profiles", Side = 2 })
        local Autoload = SettingsSub["Theme"]:Section({ Name = "Autoload", Side = 2 })

        -- All theme colour pickers
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

        -- Built-in themes
        Profiles:Dropdown({
            Name = "Built-in Themes",
            Items = { "Default", "Halloween", "Aqua", "One Tap" },
            Default = "Default", MaxSize = 150, Multi = false,
            Callback = function(v)
                local Name = v == "Default" and "Preset" or v
                local ThemeData = ML.Themes[Name]
                if not ThemeData then return end
                for k, col in ThemeData do
                    ML.Theme[k] = col
                    ML:ChangeTheme(k, col)
                    if ML.ThemeColorpickers and ML.ThemeColorpickers[k] then
                        ML.ThemeColorpickers[k]:Set(col)
                    end
                end
            end
        })

        local ThemeSelected, ThemeName
        local ThemeDropdown = Profiles:Dropdown({
            Name = "Custom Themes", Flag = "ThemesList", Items = {}, Multi = false,
            Callback = function(v) ThemeSelected = v end
        })
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
        Autoload:Button({ Name = "Set Current As Autoload", Callback = function()
            writefile(ML.Folders.Directory .. "/AutoLoadTheme (do not modify this).json", ML:GetTheme())
        end })
        Autoload:Button({ Name = "Remove Autoload", Callback = function()
            writefile(ML.Folders.Directory .. "/AutoLoadTheme (do not modify this).json", "")
        end })
    end

    -- Loaded notification
    ML:Notification({
        Name        = "ExecSync",
        Description = "Loaded in: " .. string.format("%.4f", os.clock() - LoadingTick) .. " seconds",
        Duration    = 5,
        Icon        = "116339777575852",
        IconColor   = Color3.fromRGB(255, 255, 255),
    })

    ML:Init()
    startSettingsPoll(ML)
    logInfo("Main GUI loaded for " .. (username or "unknown"))
end

-- ─────────────────────────────────────────────
--  KEY SYSTEM UI  (pixel-perfect IceWare style)
--  Matches screenshot 6 / IceWare github design
-- ─────────────────────────────────────────────
local function BuildKeySystem(onSuccess)

    local Gui = New("ScreenGui", {
        Name           = "ExecSyncKeySystem",
        ResetOnSpawn   = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder   = 999,
        Parent         = PlayerGui,
    })

    -- Dark overlay
    local Overlay = New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.5,
        ZIndex = 1, Parent = Gui,
    })

    -- Main window frame
    local Win = New("Frame", {
        Name            = "Window",
        AnchorPoint     = Vector2.new(0.5, 0.5),
        Position        = UDim2.new(0.5, 0, 1.5, 0),   -- starts off-screen, slides in
        Size            = UDim2.fromOffset(680, 370),
        BackgroundColor3 = C.BG,
        ZIndex          = 2,
        Parent          = Gui,
    })
    Corner(6).Parent = Win
    Stroke(C.Border).Parent = Win

    -- Drop shadow
    New("ImageLabel", {
        Size             = UDim2.new(1, 47, 1, 47),
        AnchorPoint      = Vector2.new(0.5, 0.5),
        Position         = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundTransparency = 1,
        Image            = "http://www.roblox.com/asset/?id=18245826428",
        ImageColor3      = Color3.fromRGB(0, 0, 0),
        ImageTransparency = 0.7,
        ScaleType        = Enum.ScaleType.Slice,
        SliceCenter      = Rect.new(Vector2.new(21, 21), Vector2.new(79, 79)),
        ZIndex           = 1,
        Parent           = Win,
    })

    -- ── Title Bar ────────────────────────────
    local TitleBar = New("Frame", {
        Name             = "TitleBar",
        Size             = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = C.TitleBar,
        ZIndex           = 3,
        Parent           = Win,
    })
    Corner(6).Parent = TitleBar
    -- square off the bottom two corners
    New("Frame", {
        Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 1, -8),
        BackgroundColor3 = C.TitleBar, BorderSizePixel = 0, ZIndex = 3, Parent = TitleBar,
    })
    Stroke(C.Border).Parent = TitleBar

    -- "iw" badge (white pill)
    local Badge = New("TextLabel", {
        Text             = "iw",
        Size             = UDim2.fromOffset(26, 18),
        Position         = UDim2.fromOffset(10, 9),
        BackgroundColor3 = C.Accent,
        TextColor3       = Color3.fromRGB(0, 0, 0),
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        ZIndex           = 4,
        Parent           = TitleBar,
    })
    Corner(4).Parent = Badge

    -- Vertical separator after badge
    New("Frame", {
        Size = UDim2.fromOffset(1, 16), Position = UDim2.new(0, 46, 0.5, -8),
        BackgroundColor3 = C.Border, BorderSizePixel = 0, ZIndex = 4, Parent = TitleBar,
    })

    -- "IceWare" bold title
    New("TextLabel", {
        Text                 = "IceWare",
        Size                 = UDim2.new(0, 72, 1, 0),
        Position             = UDim2.fromOffset(52, 0),
        BackgroundTransparency = 1,
        TextColor3           = C.TextPrim,
        Font                 = Enum.Font.GothamBold,
        TextSize             = 13,
        TextXAlignment       = Enum.TextXAlignment.Left,
        ZIndex               = 4,
        Parent               = TitleBar,
    })

    -- Separator between "IceWare" and "Key System"
    New("Frame", {
        Size = UDim2.fromOffset(1, 16), Position = UDim2.new(0, 127, 0.5, -8),
        BackgroundColor3 = C.Border, BorderSizePixel = 0, ZIndex = 4, Parent = TitleBar,
    })

    -- "Key System" subtitle
    New("TextLabel", {
        Text                 = "Key System",
        Size                 = UDim2.new(0, 100, 1, 0),
        Position             = UDim2.fromOffset(134, 0),
        BackgroundTransparency = 1,
        TextColor3           = C.TextSub,
        Font                 = Enum.Font.Gotham,
        TextSize             = 13,
        TextXAlignment       = Enum.TextXAlignment.Left,
        ZIndex               = 4,
        Parent               = TitleBar,
    })

    -- Minimize button
    New("TextButton", {
        Text = "─", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -60, 0.5, -14),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.GothamBold, TextSize = 14, ZIndex = 4, Parent = TitleBar,
    })

    -- Close button
    local CloseBtn = New("TextButton", {
        Text = "×", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -32, 0.5, -14),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.GothamBold, TextSize = 18, ZIndex = 4, Parent = TitleBar,
    })
    CloseBtn.MouseButton1Click:Connect(function() Gui:Destroy() end)

    -- Drag logic
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
                Win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                          startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
    end

    -- ── Content Area ─────────────────────────
    local Content = New("Frame", {
        Size = UDim2.new(1, 0, 1, -36), Position = UDim2.fromOffset(0, 36),
        BackgroundTransparency = 1, ZIndex = 3, Parent = Win,
    })

    -- Centre divider line
    New("Frame", {
        Size = UDim2.new(0, 1, 1, -24), Position = UDim2.new(0.5, 0, 0, 12),
        BackgroundColor3 = C.Border, BorderSizePixel = 0, ZIndex = 3, Parent = Content,
    })

    -- ── LEFT PANEL ───────────────────────────
    local Left = New("Frame", {
        Size = UDim2.new(0.5, -1, 1, 0),
        BackgroundTransparency = 1, ZIndex = 3, Parent = Content,
    })
    Pad(16, 16, 16, 16).Parent = Left
    ListV(Enum.HorizontalAlignment.Left, 8).Parent = Left

    -- Section header: "Key Verification"
    New("TextLabel", {
        Text = "Key Verification", Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1, TextColor3 = C.TextPrim,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 1, Parent = Left,
    })

    -- Info box
    local InfoBox = New("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = C.Panel, ZIndex = 4, LayoutOrder = 2, Parent = Left,
    })
    Corner(5).Parent = InfoBox
    New("TextLabel", {
        Text = "Enter your 5-digit code to unlock access",
        Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment  = Enum.TextXAlignment.Center,
        TextYAlignment  = Enum.TextYAlignment.Center,
        ZIndex = 5, Parent = InfoBox,
    })

    -- Label above input
    New("TextLabel", {
        Text = "Key Input", Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 3, Parent = Left,
    })

    -- Text input
    local CodeBox = New("TextBox", {
        PlaceholderText  = "Enter your key here..",
        Text             = "",
        Size             = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = C.Input,
        TextColor3       = C.TextPrim,
        PlaceholderColor3 = C.TextDim,
        Font             = Enum.Font.Gotham,
        TextSize         = 12,
        TextXAlignment   = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ZIndex           = 4, LayoutOrder = 4, Parent = Left,
    })
    Corner(5).Parent = CodeBox
    Stroke(C.InpBord).Parent = CodeBox
    Pad(0, 0, 10, 10).Parent = CodeBox

    -- Status label (for errors / success messages)
    local StatusLabel = New("TextLabel", {
        Text = "", Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1, TextColor3 = C.Error,
        Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 4, LayoutOrder = 5, Parent = Left,
    })

    -- "Check Key" primary button
    local CheckBtn = New("TextButton", {
        Text = "Check Key", Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = C.Btn, TextColor3 = C.TextPrim,
        Font = Enum.Font.Gotham, TextSize = 12,
        ZIndex = 4, LayoutOrder = 6, Parent = Left, AutoButtonColor = false,
    })
    Corner(5).Parent = CheckBtn
    Stroke(C.BtnBord).Parent = CheckBtn
    CheckBtn.MouseEnter:Connect(function() Tw(CheckBtn, { BackgroundColor3 = C.BtnHov }) end)
    CheckBtn.MouseLeave:Connect(function() Tw(CheckBtn, { BackgroundColor3 = C.Btn   }) end)

    -- Row: Get Key (12H)  |  Get Key (1D)
    local BtnRow = New("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1, ZIndex = 4, LayoutOrder = 7, Parent = Left,
    })
    ListH(Enum.HorizontalAlignment.Left, 8).Parent = BtnRow

    local function MakeSecondaryBtn(label, order, parent)
        local Btn = New("TextButton", {
            Text = label, Size = UDim2.new(0.5, -4, 1, 0),
            BackgroundColor3 = C.Btn, TextColor3 = C.TextPrim,
            Font = Enum.Font.Gotham, TextSize = 11,
            ZIndex = 4, LayoutOrder = order, Parent = parent, AutoButtonColor = false,
        })
        Corner(5).Parent = Btn
        Stroke(C.BtnBord).Parent = Btn
        Btn.MouseEnter:Connect(function() Tw(Btn, { BackgroundColor3 = C.BtnHov }) end)
        Btn.MouseLeave:Connect(function() Tw(Btn, { BackgroundColor3 = C.Btn   }) end)
        return Btn
    end

    local Btn12H = MakeSecondaryBtn("Get Key (12H)", 1, BtnRow)
    local Btn1D  = MakeSecondaryBtn("Get Key (1D)",  2, BtnRow)

    -- Both open Discord
    Btn12H.MouseButton1Click:Connect(function()
        if setclipboard then setclipboard(DISCORD_INVITE) end
        StatusLabel.Text = "Discord link copied to clipboard!"
        StatusLabel.TextColor3 = C.Success
    end)
    Btn1D.MouseButton1Click:Connect(function()
        if setclipboard then setclipboard(DISCORD_INVITE) end
        StatusLabel.Text = "Discord link copied to clipboard!"
        StatusLabel.TextColor3 = C.Success
    end)

    -- ── RIGHT PANEL ──────────────────────────
    local Right = New("Frame", {
        Size = UDim2.new(0.5, -1, 1, 0), Position = UDim2.new(0.5, 1, 0, 0),
        BackgroundTransparency = 1, ZIndex = 3, Parent = Content,
    })
    Pad(16, 16, 16, 16).Parent = Right
    ListV(Enum.HorizontalAlignment.Left, 10).Parent = Right

    -- "Information" header
    New("TextLabel", {
        Text = "Information", Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1, TextColor3 = C.TextPrim,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 1, Parent = Right,
    })

    -- Info block 1
    local IB1 = New("Frame", {
        Size = UDim2.new(1, 0, 0, 54),
        BackgroundColor3 = C.Panel, ZIndex = 4, LayoutOrder = 2, Parent = Right,
    })
    Corner(5).Parent = IB1
    New("TextLabel", {
        Text = "Codes are tied to your Roblox username.\nEach code can only be used once.",
        Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 5, Parent = IB1,
    })

    -- Info block 2
    local IB2 = New("Frame", {
        Size = UDim2.new(1, 0, 0, 66),
        BackgroundColor3 = C.Panel, ZIndex = 4, LayoutOrder = 3, Parent = Right,
    })
    Corner(5).Parent = IB2
    New("TextLabel", {
        Text = "Premium removes the key system and gives you\naccess to the best features, join our discord\nto learn more",
        Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1, TextColor3 = C.TextSub,
        Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 5, Parent = IB2,
    })

    -- "Discord" header
    New("TextLabel", {
        Text = "Discord", Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1, TextColor3 = C.TextPrim,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 4, Parent = Right,
    })

    New("TextLabel", {
        Text = "Need help or updates? Join our Discord server",
        Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
        TextColor3 = C.TextSub, Font = Enum.Font.Gotham, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 4, LayoutOrder = 5, Parent = Right,
    })

    local DiscordBtn = New("TextButton", {
        Text = "Join Discord", Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = C.Btn, TextColor3 = C.TextPrim,
        Font = Enum.Font.Gotham, TextSize = 12,
        ZIndex = 4, LayoutOrder = 6, Parent = Right, AutoButtonColor = false,
    })
    Corner(5).Parent = DiscordBtn
    Stroke(C.BtnBord).Parent = DiscordBtn
    DiscordBtn.MouseEnter:Connect(function() Tw(DiscordBtn, { BackgroundColor3 = C.BtnHov }) end)
    DiscordBtn.MouseLeave:Connect(function() Tw(DiscordBtn, { BackgroundColor3 = C.Btn   }) end)
    DiscordBtn.MouseButton1Click:Connect(function()
        if setclipboard then setclipboard(DISCORD_INVITE) end
        StatusLabel.Text = "Discord link copied to clipboard!"
        StatusLabel.TextColor3 = C.Success
    end)

    -- ── Helpers ──────────────────────────────
    local function SetStatus(msg, isErr)
        StatusLabel.Text       = msg
        StatusLabel.TextColor3 = isErr and C.Error or C.Success
    end

    local function FinishAndLoad(resolvedUser)
        SetStatus("✓ Verified! Loading ExecSync...", false)
        task.wait(1.2)
        Tw(Win,     { Position = UDim2.new(0.5, 0, 1.5, 0) }, 0.4)
        Tw(Overlay, { BackgroundTransparency = 1 },             0.4)
        task.wait(0.45)
        Gui:Destroy()
        if onSuccess then task.spawn(function() onSuccess(resolvedUser) end) end
    end

    -- ── Check Key (5-digit code verification) ─
    CheckBtn.MouseButton1Click:Connect(function()
        local code = CodeBox.Text:match("^%s*(.-)%s*$")
        if code == "" then SetStatus("Please enter your security code.", true); return end
        if not code:match("^%d%d%d%d%d$") then SetStatus("Code must be exactly 5 digits.", true); return end

        SetStatus("Verifying…", false)
        StatusLabel.TextColor3 = C.TextDim
        CheckBtn.Active = false

        task.spawn(function()
            local docName, err = queryByCode(LocalPlayer.Name, code)
            if not docName then
                SetStatus(err or "Invalid code.", true)
                CheckBtn.Active = true
                return
            end
            local token = generateToken()
            if not writeTokenToDoc(docName, token) then
                SetStatus("Could not save session. Try again.", true)
                CheckBtn.Active = true
                return
            end
            saveToken(token)
            FinishAndLoad(LocalPlayer.Name)
        end)
    end)

    -- ── Slide in from below ───────────────────
    Tw(Win, { Position = UDim2.fromScale(0.5, 0.5) }, 0.35)
end

-- ─────────────────────────────────────────────
--  ENTRY POINT
-- ─────────────────────────────────────────────
logInfo("ExecSync starting — place=" .. tostring(game.PlaceId) .. " user=" .. LocalPlayer.Name)

task.spawn(function()
    -- Silently validate any saved token first
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
