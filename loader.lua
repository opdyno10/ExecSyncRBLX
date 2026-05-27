-- ╔══════════════════════════════════════════════════════╗
-- ║         ExecSync  v1.4.1                             ║
-- ║   Firestore Token Auth  +  ExecSync Main GUI         ║
-- ╚══════════════════════════════════════════════════════╝

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")

-- ─────────────────────────────────────────────
--  CONFIG
-- ─────────────────────────────────────────────
local FIREBASE_PROJECT = "studio-9760542617-d373c"
local SESSION_FILE     = "execsync_session.txt"

local FIRESTORE_BASE = "https://firestore.googleapis.com/v1/projects/"
    .. FIREBASE_PROJECT .. "/databases/(default)/documents"
local QUERY_URL = FIRESTORE_BASE .. ":runQuery"

-- ─────────────────────────────────────────────
--  Load Kiwisense Library
-- ─────────────────────────────────────────────
local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Kiwisense/Library.lua"
))()

-- ─────────────────────────────────────────────
--  REMOTE LOGGER
--  Sends all logs to Firestore > debugLogs so
--  you can read errors from the Firebase console
-- ─────────────────────────────────────────────
local function remoteLog(level, message)
    -- Always print locally too
    print("[ExecSync][" .. level .. "] " .. tostring(message))

    -- Fire-and-forget to Firestore (non-blocking)
    task.spawn(function()
        pcall(function()
            request({
                Url     = FIRESTORE_BASE .. "/debugLogs",
                Method  = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = HttpService:JSONEncode({
                    fields = {
                        username  = { stringValue  = Players.LocalPlayer.Name },
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

local function logInfo(msg)  remoteLog("INFO",  msg) end
local function logWarn(msg)  remoteLog("WARN",  msg) end
local function logError(msg) remoteLog("ERROR", msg) end

-- ─────────────────────────────────────────────
--  TOKEN GENERATOR
-- ─────────────────────────────────────────────
local function generateToken()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local token  = ""
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

-- Find document matching username + code
local function queryByCode(username, code)
    logInfo("queryByCode → username=" .. username .. " code=" .. code)
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

    local ok, response = pcall(function()
        return request({
            Url     = QUERY_URL,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = body,
        })
    end)

    if not ok then
        logError("queryByCode pcall failed: " .. tostring(response))
        return nil, "Network error."
    end
    if response.StatusCode ~= 200 then
        logError("queryByCode HTTP " .. response.StatusCode .. ": " .. tostring(response.Body))
        return nil, "Server error (" .. response.StatusCode .. ")."
    end

    local parsed = HttpService:JSONDecode(response.Body)
    if type(parsed) ~= "table" or not parsed[1] or not parsed[1].document then
        logWarn("queryByCode: no matching document")
        return nil, "Invalid code."
    end

    logInfo("queryByCode: found " .. parsed[1].document.name)
    return parsed[1].document.name, nil
end

-- Write sessionToken + used=true onto a document
local function writeTokenToDoc(docName, token)
    logInfo("writeTokenToDoc → " .. docName)
    local patchUrl = "https://firestore.googleapis.com/v1/" .. docName
        .. "?updateMask.fieldPaths=used&updateMask.fieldPaths=sessionToken"

    local ok, response = pcall(function()
        return request({
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
        logError("writeTokenToDoc pcall failed: " .. tostring(response))
        return false
    end
    if response.StatusCode ~= 200 then
        logError("writeTokenToDoc HTTP " .. response.StatusCode .. ": " .. tostring(response.Body))
        return false
    end

    logInfo("writeTokenToDoc: success")
    return true
end

-- Find document by sessionToken, return username
local function queryByToken(token)
    logInfo("queryByToken → token=" .. token:sub(1, 8) .. "…")
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

    local ok, response = pcall(function()
        return request({
            Url     = QUERY_URL,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = body,
        })
    end)

    if not ok then
        logError("queryByToken pcall failed: " .. tostring(response))
        return nil
    end
    if response.StatusCode ~= 200 then
        logError("queryByToken HTTP " .. response.StatusCode)
        return nil
    end

    local parsed = HttpService:JSONDecode(response.Body)
    if type(parsed) ~= "table" or not parsed[1] or not parsed[1].document then
        logWarn("queryByToken: token not found in Firestore")
        return nil
    end

    local fields = parsed[1].document.fields
    if fields and fields.username and fields.username.stringValue then
        logInfo("queryByToken: resolved to " .. fields.username.stringValue)
        return fields.username.stringValue
    end

    logWarn("queryByToken: document found but no username field")
    return nil
end

-- Fetch global settings document from Firestore
local function fetchRemoteSettings()
    logInfo("fetchRemoteSettings: fetching…")
    local ok, response = pcall(function()
        return request({
            Url     = FIRESTORE_BASE .. "/settings/global",
            Method  = "GET",
            Headers = { ["Content-Type"] = "application/json" },
        })
    end)

    if not ok or response.StatusCode ~= 200 then
        logWarn("fetchRemoteSettings: failed (" .. tostring(response and response.StatusCode) .. ")")
        return nil
    end

    local parsed = HttpService:JSONDecode(response.Body)
    logInfo("fetchRemoteSettings: OK")
    return parsed and parsed.fields or nil
end

-- ─────────────────────────────────────────────
--  SESSION HELPERS
-- ─────────────────────────────────────────────

local function saveToken(token)
    pcall(function() writefile(SESSION_FILE, token) end)
    logInfo("Session token saved to disk")
end

local function readToken()
    local ok = pcall(function() return isfile(SESSION_FILE) end)
    if not ok or not isfile(SESSION_FILE) then return nil end
    local t = readfile(SESSION_FILE)
    if t and t ~= "" then return t end
    return nil
end

local function deleteSessionFile()
    -- Try delfile first (most executors support it), fall back to emptying
    local deleted = pcall(function() delfile(SESSION_FILE) end)
    if not deleted then
        pcall(function() writefile(SESSION_FILE, "") end)
    end
    logInfo("Session file deleted/cleared")
end

-- ─────────────────────────────────────────────
--  SETTINGS POLL LOOP
--  Runs every 5 minutes after main GUI loads.
--  Reads settings/global from Firestore and
--  applies them — including a kill switch.
-- ─────────────────────────────────────────────
local function startSettingsPoll(mainLibrary)
    task.spawn(function()
        while true do
            task.wait(300) -- 5 minutes

            local settings = fetchRemoteSettings()
            if settings then

                -- Kill switch: if killSwitch = true, force unload
                if settings.killSwitch and settings.killSwitch.booleanValue == true then
                    logWarn("Kill switch activated by remote settings — unloading")
                    mainLibrary:Notification({
                        Name        = "ExecSync",
                        Description = "Script has been disabled remotely.",
                        Duration    = 6,
                    })
                    task.wait(3)
                    mainLibrary:Unload()
                    return
                end

                -- Maintenance message: show a notification if set
                if settings.maintenanceMessage and settings.maintenanceMessage.stringValue ~= "" then
                    mainLibrary:Notification({
                        Name        = "ExecSync – Notice",
                        Description = settings.maintenanceMessage.stringValue,
                        Duration    = 8,
                        Icon        = "116339777575852",
                    })
                end

                logInfo("Settings refreshed from Firestore")
            end
        end
    end)
end

-- ─────────────────────────────────────────────
--  MAIN EXECSYNC GUI
-- ─────────────────────────────────────────────
local function LoadMainScript(username)
    logInfo("LoadMainScript → " .. tostring(username))
    Library:Unload()
    task.wait(0.3)

    local LoadingTick = os.clock()
    local MainLibrary = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Kiwisense/Library.lua"
    ))()

    local Window = MainLibrary:Window({
        Name      = "ExecSync",
        Version   = "v1.4.1",
        Logo      = "135215559087473",
        FadeSpeed = 0.25,
    })

    local Watermark = MainLibrary:Watermark("ExecSync | Driving Empire", "135215559087473")
    Watermark:SetVisibility(true)

    local KeybindList = MainLibrary:KeybindsList()
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

    do
        local RewardsSection   = Pages["Miscellaneous"]:Section({ Name = "Rewards",      Side = 1 })
        local TrollingSection  = Pages["Miscellaneous"]:Section({ Name = "Trolling",     Side = 1 })
        local InventorySection = Pages["Miscellaneous"]:Section({ Name = "Inventory",    Side = 1 })
        local DealerSection    = Pages["Miscellaneous"]:Section({ Name = "Dealership",   Side = 2 })
        local OptimSection     = Pages["Miscellaneous"]:Section({ Name = "Optimization", Side = 2 })
        local MiscSection      = Pages["Miscellaneous"]:Section({ Name = "Misc",         Side = 2 })
        local WebhookSection   = Pages["Miscellaneous"]:Section({ Name = "Webhook",      Side = 2 })

        RewardsSection:Toggle({ Name = "Auto Claim Daily Rewards",    Flag = "AutoDailyRewards",       Default = false, Callback = function(v) end })
        RewardsSection:Toggle({ Name = "Auto Double Daily Rewards",   Flag = "AutoDoubleDailyRewards",  Default = false, Callback = function(v) end })
        RewardsSection:Toggle({ Name = "Auto Claim AD Rewards",       Flag = "AutoADRewards",           Default = false, Callback = function(v) end })
        RewardsSection:Button({ Name = "Redeem All Codes",            Callback = function() end })
        RewardsSection:Button({ Name = "Free Trophies (Nascar QUIZ)", Callback = function() end })

        TrollingSection:Toggle({ Name = "Spam Outfits", Flag = "SpamOutfits", Default = false, Callback = function(v) end })

        InventorySection:Toggle({ Name = "Auto Open Packs [$$$]", Flag = "AutoOpenPacks",   Default = false, Callback = function(v) end })
        InventorySection:Slider({ Name = "Gacha Open Amount",     Flag = "GachaOpenAmount", Min = 1, Max = 100, Default = 1, Decimals = 1, Callback = function(v) end })

        DealerSection:Dropdown({ Name = "Select Vehicle", Flag = "SelectVehicle",
            Items = { "Cars", "Motorcycles", "Trucks", "Sports Cars" }, Default = "Cars", MaxSize = 200,
            Callback = function(v) end })
        DealerSection:Button({ Name = "Open Dealership", Callback = function() end })

        OptimSection:Toggle({ Name = "Disable Rendering",       Flag = "DisableRendering",  Default = false, Callback = function(v) end })
        MiscSection:Toggle({ Name = "No Telemetry",              Flag = "NoTelemetry",       Default = false, Callback = function(v) end })
        MiscSection:Toggle({ Name = "Always See Bounties [$$$]", Flag = "AlwaysSeeBounties", Default = false, Callback = function(v) end })

        WebhookSection:Toggle({ Name = "Webhook Alerts",        Flag = "WebhookAlerts", Default = false, Callback = function(v) end })
        WebhookSection:Textbox({ Name = "Webhook URL",          Flag = "WebhookURL",    Default = "", Placeholder = "...", Callback = function(v) end })
        WebhookSection:Toggle({ Name = "Ping on alert (@here)", Flag = "WebhookPing",   Default = false, Callback = function(v) end })
    end

    do
        Pages["PlayerList"]:Playerlist({ Callback = function(...) end })
    end

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
        SessionSection:Label("Logged in as: " .. (username or Players.LocalPlayer.Name), "Center")

        SessionSection:Button({ Name = "Rejoin", Callback = function()
            game:GetService("TeleportService"):Teleport(game.PlaceId)
        end })

        SessionSection:Button({ Name = "Server Hop", Callback = function()
            local TS      = game:GetService("TeleportService")
            local HS      = game:GetService("HttpService")
            local servers = HS:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            ))
            for _, server in ipairs(servers.data) do
                if server.id ~= game.JobId and server.playing < server.maxPlayers then
                    TS:TeleportToPlaceInstance(game.PlaceId, server.id)
                    return
                end
            end
        end })

        SessionSection:Button({ Name = "Eject", Callback = function()
            logInfo("Eject pressed")
            MainLibrary:Unload()
        end })

        SessionSection:Button({ Name = "Log Out", Callback = function()
            logInfo("Log Out pressed — clearing session")
            deleteSessionFile()
            MainLibrary:Notification({
                Name        = "ExecSync",
                Description = "Logged out. Re-run the script to sign in again.",
                Duration    = 4,
                Icon        = "116339777575852",
            })
            task.wait(2)
            MainLibrary:Unload()
        end })

        SessionSection:Button({ Name = "Join Discord", Callback = function()
            if setclipboard then setclipboard("https://discord.gg/execsync") end
        end })

        UISection:Label("Menu Keybind", "Left"):Keybind({
            Name     = "MenuKeybind", Flag = "MenuKeybind", Mode = "toggle",
            Default  = Enum.KeyCode.RightControl,
            Callback = function() MainLibrary.MenuKeybind = MainLibrary.Flags["MenuKeybind"].Key end
        })
        UISection:Toggle({ Name = "Keybind List", Flag = "KeybindList", Default = false,
            Callback = function(v) KeybindList:SetVisibility(v) end })
        UISection:Toggle({ Name = "Watermark", Flag = "Watermark", Default = true,
            Callback = function(v) Watermark:SetVisibility(v) end })

        AnimSection:Slider({ Name = "Time", Flag = "TweenTime", Min = 0, Max = 5, Default = 0.3, Decimals = 0.01,
            Callback = function(v) MainLibrary.Tween.Time = v end })
        AnimSection:Dropdown({ Name = "Style", Flag = "TweenStyle",
            Items = { "Linear","Sine","Quad","Cubic","Quart","Quint","Exponential","Circular","Back","Elastic","Bounce" },
            Default = "Cubic", MaxSize = 150,
            Callback = function(v) MainLibrary.Tween.Style = Enum.EasingStyle[v] end })
        AnimSection:Dropdown({ Name = "Direction", Flag = "TweenDirection",
            Items = { "In", "Out", "InOut" }, Default = "Out", MaxSize = 80,
            Callback = function(v) MainLibrary.Tween.Direction = Enum.EasingDirection[v] end })
    end

    do
        local ProfilesSection = SettingsSubpages["Configs"]:Section({ Name = "Profiles", Side = 1 })
        local AutoloadSection = SettingsSubpages["Configs"]:Section({ Name = "Autoload", Side = 2 })
        local ConfigSelected, ConfigName

        local ConfigsDropdown = ProfilesSection:Dropdown({
            Name = "Configs", Flag = "ConfigsList", Items = {}, Multi = false,
            Callback = function(v) ConfigSelected = v end
        })
        ProfilesSection:Textbox({ Name = "Config Name", Flag = "ConfigName", Default = "", Placeholder = "Enter Name",
            Callback = function(v) ConfigName = v end })
        ProfilesSection:Button({ Name = "Create", Callback = function()
            if ConfigName and ConfigName ~= "" then
                writefile(MainLibrary.Folders.Configs .. "/" .. ConfigName .. ".json", MainLibrary:GetConfig())
                MainLibrary:RefreshConfigsList(ConfigsDropdown)
            end
        end })
        ProfilesSection:Button({ Name = "Delete", Callback = function()
            if ConfigSelected then
                MainLibrary:DeleteConfig(ConfigSelected)
                MainLibrary:RefreshConfigsList(ConfigsDropdown)
            end
        end })
        ProfilesSection:Button({ Name = "Load", Callback = function()
            if ConfigSelected then
                MainLibrary:LoadConfig(readfile(MainLibrary.Folders.Configs .. "/" .. ConfigSelected))
            end
        end })
        ProfilesSection:Button({ Name = "Save", Callback = function()
            if ConfigSelected then MainLibrary:SaveConfig(ConfigSelected) end
        end })
        ProfilesSection:Button({ Name = "Refresh List", Callback = function()
            MainLibrary:RefreshConfigsList(ConfigsDropdown)
        end })
        MainLibrary:RefreshConfigsList(ConfigsDropdown)

        AutoloadSection:Button({ Name = "Set Selected As Autoload", Callback = function()
            if ConfigSelected then
                writefile(MainLibrary.Folders.Directory .. "/AutoLoadConfig (do not modify this).json",
                    readfile(MainLibrary.Folders.Configs .. "/" .. ConfigSelected))
            end
        end })
        AutoloadSection:Button({ Name = "Set Current As Autoload", Callback = function()
            writefile(MainLibrary.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", MainLibrary:GetConfig())
        end })
        AutoloadSection:Button({ Name = "Remove Autoload", Callback = function()
            writefile(MainLibrary.Folders.Directory .. "/AutoLoadConfig (do not modify this).json", "")
        end })
    end

    do
        local ThemingSection  = SettingsSubpages["Theming"]:Section({ Name = "Theming",  Side = 1 })
        local ProfilesSection = SettingsSubpages["Theming"]:Section({ Name = "Profiles", Side = 2 })
        local AutoloadSection = SettingsSubpages["Theming"]:Section({ Name = "Autoload", Side = 2 })

        for Index, Value in MainLibrary.Theme do
            MainLibrary.ThemeColorpickers = MainLibrary.ThemeColorpickers or {}
            MainLibrary.ThemeColorpickers[Index] = ThemingSection:Label(Index, "Left"):Colorpicker({
                Name     = "Colorpicker",
                Flag     = "ColorpickerTheme" .. Index,
                Default  = Value, Alpha = 0,
                Callback = function(Color)
                    MainLibrary.Theme[Index] = Color
                    MainLibrary:ChangeTheme(Index, Color)
                end
            })
        end

        ProfilesSection:Dropdown({ Name = "Built-in Themes",
            Items = { "Default", "Halloween", "Aqua", "One Tap" }, Default = "Default", MaxSize = 150, Multi = false,
            Callback = function(v)
                local Name      = v == "Default" and "Preset" or v
                local ThemeData = MainLibrary.Themes[Name]
                if not ThemeData then return end
                for k, col in ThemeData do
                    MainLibrary.Theme[k] = col
                    MainLibrary:ChangeTheme(k, col)
                    if MainLibrary.ThemeColorpickers and MainLibrary.ThemeColorpickers[k] then
                        MainLibrary.ThemeColorpickers[k]:Set(col)
                    end
                end
            end
        })

        local ThemeSelected, ThemeName
        local ThemesDropdown = ProfilesSection:Dropdown({
            Name = "Custom Themes", Flag = "ThemesList", Items = {}, Multi = false,
            Callback = function(v) ThemeSelected = v end
        })
        ProfilesSection:Textbox({ Name = "Theme Name", Flag = "ThemeName", Default = "", Placeholder = "Enter Name",
            Callback = function(v) ThemeName = v end })
        ProfilesSection:Button({ Name = "Save", Callback = function()
            if ThemeName and ThemeName ~= "" then
                writefile(MainLibrary.Folders.Themes .. "/" .. ThemeName .. ".json", MainLibrary:GetTheme())
                MainLibrary:RefreshThemesList(ThemesDropdown)
            end
        end })
        ProfilesSection:Button({ Name = "Load", Callback = function()
            if ThemeSelected then
                MainLibrary:LoadTheme(readfile(MainLibrary.Folders.Themes .. "/" .. ThemeSelected))
            end
        end })
        MainLibrary:RefreshThemesList(ThemesDropdown)

        AutoloadSection:Button({ Name = "Set Selected As Autoload", Callback = function()
            if ThemeSelected then
                writefile(MainLibrary.Folders.Directory .. "/AutoLoadTheme (do not modify this).json",
                    readfile(MainLibrary.Folders.Themes .. "/" .. ThemeSelected))
            end
        end })
    end

    MainLibrary:Notification({
        Name        = "ExecSync",
        Description = "Loaded in: " .. string.format("%.4f", os.clock() - LoadingTick) .. " seconds",
        Duration    = 5,
        Icon        = "116339777575852",
        IconColor   = Color3.fromRGB(140, 200, 255),
    })

    MainLibrary:Init()

    -- Start the 5-minute settings poll after GUI is live
    startSettingsPoll(MainLibrary)
    logInfo("Main GUI loaded for " .. (username or "unknown"))
end

-- ─────────────────────────────────────────────
--  AUTH UI
-- ─────────────────────────────────────────────
local function initUI()
    logInfo("initUI: starting")

    local AuthWindow = Library:Window({
        Name      = "System Bridge",
        Version   = "1.0.0",
        Logo      = "135215559087473",
        FadeSpeed = 0.25,
    })

    Library:Watermark("ExecSync Auth", "135215559087473"):SetVisibility(false)
    Library:KeybindsList():SetVisibility(false)

    task.spawn(function()

        -- ── Try restoring session from saved token ────
        local savedToken = readToken()
        if savedToken then
            logInfo("Found saved token — validating with Firestore")
            Library:Notification({
                Name        = "ExecSync – Checking Session",
                Description = "Validating your session token…",
                Duration    = 4,
            })

            local resolvedUser = queryByToken(savedToken)
            if resolvedUser then
                Library:Notification({
                    Name        = "ExecSync – Welcome Back",
                    Description = "Session restored for " .. resolvedUser .. ".",
                    Duration    = 4,
                    Icon        = "116339777575852",
                })
                task.wait(1.5)
                LoadMainScript(resolvedUser)
                return
            else
                -- Token invalid or revoked — delete file and show auth
                logWarn("Saved token invalid — deleting session file")
                deleteSessionFile()
                Library:Notification({
                    Name        = "ExecSync – Session Expired",
                    Description = "Your session has expired. Please verify again.",
                    Duration    = 5,
                })
                task.wait(2)
            end
        end

        -- ── Build verification page ───────────────────
        local AuthPage = AuthWindow:Page({ Name = "Verification", Icon = "111178525804834" })

        -- Left: verify by code
        local CodeSection = AuthPage:Section({ Name = "Verify with Code", Side = 1 })
        CodeSection:Label("Enter the 5-digit code from your dashboard", "Center")
        CodeSection:Textbox({
            Name        = "Security Code",
            Placeholder = "e.g. 30946",
            Default     = "",
            Flag        = "SecurityCode",
            Callback    = function(_) end,
        })
        CodeSection:Button({
            Name     = "Verify Identity",
            Callback = function()
                local code = (Library.Flags.SecurityCode or ""):match("^%s*(.-)%s*$")

                if not code:match("^%d%d%d%d%d$") then
                    Library:Notification({
                        Name        = "ExecSync – Input Error",
                        Description = "Please enter exactly 5 digits.",
                        Duration    = 4,
                    })
                    return
                end

                Library:Notification({
                    Name        = "ExecSync – Verifying",
                    Description = "Checking code, please wait…",
                    Duration    = 4,
                })

                task.spawn(function()
                    local docName, err = queryByCode(Players.LocalPlayer.Name, code)
                    if not docName then
                        logError("Verification failed: " .. tostring(err))
                        Library:Notification({
                            Name        = "ExecSync – Failed",
                            Description = err or "Invalid code. Check your dashboard.",
                            Duration    = 6,
                        })
                        return
                    end

                    local token = generateToken()
                    local wrote = writeTokenToDoc(docName, token)
                    if not wrote then
                        logError("Failed to write token to Firestore")
                        Library:Notification({
                            Name        = "ExecSync – Error",
                            Description = "Could not save session. Please try again.",
                            Duration    = 5,
                        })
                        return
                    end

                    saveToken(token)
                    Library:Notification({
                        Name        = "ExecSync – Verified!",
                        Description = "Welcome, " .. Players.LocalPlayer.Name .. "! Loading ExecSync…",
                        Duration    = 5,
                        Icon        = "116339777575852",
                    })
                    task.wait(1.5)
                    LoadMainScript(Players.LocalPlayer.Name)
                end)
            end,
        })

        -- Right: restore by pasting a token directly
        local TokenSection = AuthPage:Section({ Name = "Restore with Token", Side = 2 })
        TokenSection:Label("Already have a token from your dashboard?", "Center")
        TokenSection:Textbox({
            Name        = "Session Token",
            Placeholder = "Paste your token here",
            Default     = "",
            Flag        = "DirectToken",
            Callback    = function(_) end,
        })
        TokenSection:Button({
            Name     = "Restore Session",
            Callback = function()
                local token = (Library.Flags.DirectToken or ""):match("^%s*(.-)%s*$")

                if token == "" then
                    Library:Notification({
                        Name        = "ExecSync – Input Error",
                        Description = "Please paste your session token first.",
                        Duration    = 4,
                    })
                    return
                end

                Library:Notification({
                    Name        = "ExecSync – Checking Token",
                    Description = "Validating token against database…",
                    Duration    = 4,
                })

                task.spawn(function()
                    logInfo("Direct token restore attempt")
                    local resolvedUser = queryByToken(token)

                    if not resolvedUser then
                        logWarn("Direct token restore failed — token not found")
                        Library:Notification({
                            Name        = "ExecSync – Invalid Token",
                            Description = "That token doesn't match any account. Check your dashboard.",
                            Duration    = 6,
                        })
                        return
                    end

                    saveToken(token)
                    logInfo("Direct token restore success → " .. resolvedUser)
                    Library:Notification({
                        Name        = "ExecSync – Restored!",
                        Description = "Welcome back, " .. resolvedUser .. "! Loading ExecSync…",
                        Duration    = 5,
                        Icon        = "116339777575852",
                    })
                    task.wait(1.5)
                    LoadMainScript(resolvedUser)
                end)
            end,
        })

        Library:Init()
        logInfo("Auth UI ready")
    end)
end

-- ─────────────────────────────────────────────
--  ENTRY POINT
-- ─────────────────────────────────────────────
logInfo("ExecSync starting — place=" .. tostring(game.PlaceId) .. " user=" .. Players.LocalPlayer.Name)
initUI()
