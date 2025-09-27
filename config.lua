Config = {}

-- Framework setting
Config.Framework = 'qbcore' -- 'qbcore' for QBCore/QBox or 'esx' for ESX

-- Locale setting
Config.Locale = 'en' -- You can edit all the texts to you language in locales.lua

-- === LEVELS / XP ===
Config.LevelCap = 3       -- Maximum level
Config.XPPerLevel = 100   -- XP needed to level up

-- Items per level when completing at FINAL CONTACT
-- define here what each level delivers
Config.LevelRewards = {
    [1] = {item = 'produtolimpeza', quantity = 5},
    [2] = {item = 'produtolimpeza2', quantity = 10},
    [3] = {item = 'produtolimpeza3', quantity = 15},
}

Config.RequiredFinalItem = 'paint_stripper'

-- How much XP gained per complete route (you can adjust)
Config.XPOnFinal = 2        -- added when completing with final contact

-- NPC and interaction
Config.NPCCoord = vec4(714.23, -1199.70, 24.29, 6.16) -- Mission npc starting point location
Config.NPCModel = 'g_m_y_lost_03' -- Change if you want
Config.TargetDistance = 2.0

-- Stash
Config.StashLabel = 'Deliver Items' -- Will be overridden by locale system
Config.StashSlots = 3
Config.StashMaxWeight = 750000 -- Max stash weight the npc will hold, i recommend the exact weight of the RequiredCount items count.
Config.AllowedItem = 'fentanyl_batch'
Config.RequiredCount = 3

Config.TrackerPingSeconds = 15

Config.DestCoords = {
    vec4(-800.14, -1296.41, 5.00, 301.46),
    vec4(-610.18, -2338.47, 13.83, 135.95),
    vec4(-1269.72, -1359.52, 4.29, 38.86),
    vec4(-2176.09, -382.44, 13.25, 64.34),
    vec4(-3043.84, 132.08, 11.60, 10.49),
    vec4(-926.81, -164.35, 41.88, 282.39),
    vec4(-593.87, 192.81, 71.14, 316.15),
    vec4(622.13, 613.10, 128.91, 168.12),
    vec4(1136.52, 60.72, 80.50, 328.09),
    vec4(-1694.38, 49.69, 64.45, 203.81),
    vec4(-1426.87, -961.52, 6.99, 305.99),
}

-- Second contact point
Config.SecondNPCCoords = {
    vec4(802.58, -492.48, 30.48, 82.47),
    vec4(582.94, -1438.13, 19.76, 154.79),
    vec4(493.50, -582.37, 24.70, 267.62),
    vec4(501.39, -1966.43, 24.99, 126.02),
    vec4(-880.99, -2109.61, 8.95, 45.99),
}

Config.SecondNPCModel = 'g_m_y_lost_02'
Config.SecondTargetDistance = 2.0

Config.FinalNPCCoords = {
    vec4(1073.08, -3269.50, 5.90, 4.52),
    vec4(-1690.28, -3165.01, 13.99, 314.01),
    vec4(1550.40, 3566.37, 35.36, 150.81),
    vec4(1646.38, 4839.76, 42.03, 104.99),
    vec4(2520.16, 4960.74, 44.80, 42.35),
    vec4(1608.26, 6624.30, 15.73, 114.30),
    vec4(1368.50, 6573.17, 12.49, 235.51),
    vec4(-440.45, 6338.82, 12.73, 25.56),
    vec4(-1582.15, 5169.64, 19.57, 215.02),
    vec4(-2164.16, 4287.08, 48.96, 138.93),
    vec4(-2153.04, 3310.52, 32.81, 62.46),
    vec4(842.34, 2195.41, 52.13, 318.14),
}

Config.FinalNPCModel = 'g_m_y_lost_01'     -- Change if you want
Config.FinalTargetDistance = 2.0
Config.FinalNeedCarRadius = 25.0           -- max radius from CAR to NPC to allow delivery
Config.FinalProgressMs = 10000             -- 10s progress bar

-- (optional) radius to consider arrived at a blip
Config.ArriveRadius = 65.0

-- possible models (one will be chosen randomly)
Config.VehicleModels = {
    'kuruma2',   -- Kuruma (Armored)
    'dukes2',  -- Dukes (Armored)
    'schafter5', -- Schafter V12 (Armored)
}

-- Radius (in meters) to consider arrived at armored vehicle location
Config.ArriveRadius = 45.0

Config.Guard = {
    model = 's_m_y_blackops_01',
    count = 5,
    weapon = 'WEAPON_PISTOL50',
    accuracy = 45,
    armor = 0,
    health = 100,
    spawnRadius = 6.0,
    detectionRadius = 60.0,
    losFlags = 17,
    relGroup = 'FENT_GUARDS',
    stayNearCar = true,
    leashRadius = 25.0
}

Config.TrackerDuration = 60 -- The duration of the tracker in seconds.

-- === POLICE DISPATCH ===
-- Choose your dispatch system by uncommenting ONE of the options below

Config.PoliceDispatch = {
    enabled = true,

    -- OPTION 1: ORIGEN POLICE (Default)
    type = 'origen_police',

    -- OPTION 2: PS-DISPATCH (Uncomment to use)
    -- type = 'ps_dispatch',

    -- OPTION 3: CD_DISPATCH (Uncomment to use)
    -- type = 'cd_dispatch',

    -- OPTION 4: LINDEN OUTLAW ALERT (Uncomment to use)
    -- type = 'linden_outlaw',

    -- OPTION 5: CUSTOM (Uncomment and edit the custom function below)
    -- type = 'custom',
}

-- =============================================================================
-- DISPATCH SYSTEM CONFIGURATIONS
-- =============================================================================

Config.DispatchSystems = {

    -- ORIGEN POLICE
    ['origen_police'] = {
        jobs = {'police', 'sheriff', 'sahp', 'ranger'},
        sendAlert = function(coords, title, message, alertType)
            pcall(function()
                exports['origen_police']:SendAlert({
                    coords = coords,
                    title = title,
                    type = alertType or 'GENERAL',
                    message = message,
                    job = 'police',
                })
            end)
        end
    },

    -- PS-DISPATCH
    ['ps_dispatch'] = {
        jobs = {'leo', 'police', 'sheriff'},
        sendAlert = function(coords, title, message, alertType)
            local dispatchData = {
                message = message,
                codeName = 'armored_vehicle_theft',
                code = title,
                icon = 'fas fa-car-burst',
                priority = 2,
                coords = coords,
                street = GetStreetAndZone and GetStreetAndZone(coords) or 'Unknown Street',
                jobs = {'leo'}
            }
            TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
        end
    },

    -- CD_DISPATCH
    ['cd_dispatch'] = {
        jobs = {'police', 'sheriff', 'sahp'},
        sendAlert = function(coords, title, message, alertType)
            local data = exports['cd_dispatch']:GetPlayerInfo()
            TriggerServerEvent('cd_dispatch:AddNotification', {
                job_table = {'police', 'sheriff'},
                coords = coords,
                title = title,
                message = message,
                flash = 0,
                unique_id = tostring(math.random(0000000, 9999999)),
                blip = {
                    sprite = 225,
                    scale = 1.0,
                    colour = 1,
                    flashes = false,
                    text = 'Armored Vehicle Theft',
                    time = (5 * 60 * 1000),
                    sound = 1,
                }
            })
        end
    },

    -- LINDEN OUTLAW ALERT
    ['linden_outlaw'] = {
        jobs = {'police', 'sheriff'},
        sendAlert = function(coords, title, message, alertType)
            local alertData = {
                coords = coords,
                title = title,
                message = message,
                alertTime = 30000, -- 30 seconds
                jobs = {'police', 'sheriff'}
            }
            exports['linden_outlawalert']:SendAlert('robbery', alertData)
        end
    },

    -- CUSTOM DISPATCH (Edit this function for your custom system)
    ['custom'] = {
        jobs = {'police'}, -- Add your police jobs here
        sendAlert = function(coords, title, message, alertType)
            -- ADD YOUR CUSTOM DISPATCH CODE HERE
            -- Example:
            -- exports['your_dispatch']:YourFunction({
            --     coords = coords,
            --     title = title,
            --     message = message,
            --     -- other parameters...
            -- })

            print('Custom dispatch not configured! Edit the custom function in config.lua')
        end
    }
}

-- =============================================================================
-- HELPER FUNCTION TO ADD CUSTOM DISPATCH SYSTEMS
-- =============================================================================
-- Use this function to easily add your own dispatch system without editing the code above
--
-- Example usage:
-- Config.AddCustomDispatch('my_dispatch', {'police', 'sheriff'}, function(coords, title, message, alertType)
--     -- Your dispatch code here
--     exports['my_dispatch']:SendAlert({
--         coords = coords,
--         title = title,
--         message = message
--     })
-- end)

Config.AddCustomDispatch = function(name, jobs, alertFunction)
    Config.DispatchSystems[name] = {
        jobs = jobs,
        sendAlert = alertFunction
    }
end

-- ===== DISPATCH SYSTEM VALIDATION =====
Config.ValidateDispatchConfig = function()
    -- Check if current dispatch type is valid
    if not Config.PoliceDispatch or not Config.PoliceDispatch.type then
        print('[fenrun-config] Warning: No dispatch type configured')
        return false
    end

    local dispatchType = Config.PoliceDispatch.type
    local system = Config.DispatchSystems[dispatchType]

    if not system then
        print(('[fenrun-config] Error: Dispatch system "%s" not found in DispatchSystems'):format(dispatchType))
        return false
    end

    if not system.jobs or type(system.jobs) ~= 'table' or #system.jobs == 0 then
        print(('[fenrun-config] Warning: No police jobs configured for dispatch system "%s"'):format(dispatchType))
        return false
    end

    if not system.sendAlert or type(system.sendAlert) ~= 'function' then
        print(('[fenrun-config] Error: sendAlert function missing for dispatch system "%s"'):format(dispatchType))
        return false
    end

    print(('[fenrun-config] Dispatch system "%s" validated successfully'):format(dispatchType))
    return true
end

-- Auto-validate dispatch configuration on startup
if Config.PoliceDispatch and Config.PoliceDispatch.enabled then
    CreateThread(function()
        Wait(1000) -- Wait for all systems to load
        Config.ValidateDispatchConfig()
    end)
end

-- Note: Config.StashLabel is handled by GetLocaleText('config_stash_label') in locales.lua

