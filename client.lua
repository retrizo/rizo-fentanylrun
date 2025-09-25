-- Initialize random seed once for better performance
math.randomseed(GetGameTimer() + (PlayerId() or 0))

local ped
local blip
local spawnedVehNet
local guards = {}
local guardRelGroupHash  = nil
local secondPed
local secondBlip
local enteredSpawnedVeh = false
local finalPed
local finalBlip
local chosenFinalNPC = nil
local finalGiven = false

-- NEW: coordinates drawn from this execution
local chosenDest = nil          -- vec4 of CAR
local chosenSecondNPC = nil     -- vec4 of 2nd NPC
local arrivalWatcherStarted = false

-- ===== helpers =====
local function percent(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    return math.floor(v + 0.5)
end

-- chooses a random model from the list; if doesn't exist, falls back to old one (compat)
local function chooseVehicleModel()
    if Config.VehicleModels and #Config.VehicleModels > 0 then
        return Config.VehicleModels[math.random(1, #Config.VehicleModels)]
    end
    return Config.VehicleModel or 'kuruma2'
end

-- maximizes vehicle performance
local function maxOutPerformance(veh)
    if not DoesEntityExist(veh) then return end
    SetVehicleModKit(veh, 0)

    local function maxMod(typeId)
        local n = GetNumVehicleMods(veh, typeId)
        if n and n > 0 then SetVehicleMod(veh, typeId, n - 1, false) end
    end

    -- 11=Engine, 12=Brakes, 13=Transmission, 15=Suspension, 16=Armor
    maxMod(11); maxMod(12); maxMod(13); maxMod(15); maxMod(16)
    ToggleVehicleMod(veh, 18, true) -- Turbo

    SetVehicleFixed(veh)
    SetVehicleDirtLevel(veh, 0.0)
end

-- fills tank via lc_fuel (and sets native for safety)
local function fillFuelLC(veh, level)
    level = level or 100.0
    if DoesEntityExist(veh) then
        SetVehicleFuelLevel(veh, level)
        pcall(function() exports["lc_fuel"]:SetFuel(veh, level) end)
    end
end

local function loadModel(model)
    local m = (type(model) == 'string') and joaat(model) or model
    if not IsModelInCdimage(m) then return false end
    RequestModel(m)
    while not HasModelLoaded(m) do Wait(0) end
    return m
end

local function ensureGuardRelGroup()
    if not guardRelGroupHash then
        guardRelGroupHash = AddRelationshipGroup(Config.Guard.relGroup) -- retorna o hash
        local playerGrp = GetHashKey('PLAYER')
        SetRelationshipBetweenGroups(5, guardRelGroupHash, playerGrp) -- Hate
        SetRelationshipBetweenGroups(5, playerGrp, guardRelGroupHash) -- reciprocal
    end
end

local function spawnVehicleGuards(veh)
    ensureGuardRelGroup()
    local g = Config.Guard
    local pedModel = loadModel(g.model)
    if not pedModel then return end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    guards[netId] = guards[netId] or { peds = {}, car = veh }

    -- positions in circle around the vehicle
    for i = 1, g.count do
        local angle = (i-1) / g.count * (2.0 * math.pi)
        local offX = math.cos(angle) * g.spawnRadius
        local offY = math.sin(angle) * g.spawnRadius
        local pos = GetOffsetFromEntityInWorldCoords(veh, offX, offY, 0.0)

        local ped = CreatePed(30, pedModel, pos.x, pos.y, pos.z, GetEntityHeading(veh), true, true)
        SetEntityAsMissionEntity(ped, true, true)

        -- Hostility and perception
        SetPedRelationshipGroupHash(ped, guardRelGroupHash)
        SetPedAsEnemy(ped, true)
        SetCanAttackFriendly(ped, true, false)

        -- Enhanced perception (sees/hears far)
        local see = math.max(80.0, g.detectionRadius + 30.0)
        SetPedSeeingRange(ped, see)
        SetPedHearingRange(ped, see)
        SetPedIdRange(ped, see)

        -- Combat attributes
        SetPedCombatAttributes(ped, 46, true)
        SetPedCombatAttributes(ped, 5, true)
        SetPedCombatAbility(ped, 2)
        SetPedCombatRange(ped, 2)
        SetPedCombatMovement(ped, 2)
        SetPedAlertness(ped, 3)
        SetPedAccuracy(ped, g.accuracy)
        SetPedArmour(ped, g.armor)
        SetEntityMaxHealth(ped, g.health)
        SetEntityHealth(ped, g.health)

        GiveWeaponToPed(ped, joaat(g.weapon), 250, false, true)
        SetCurrentPedWeapon(ped, joaat(g.weapon), true)

        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedFleeAttributes(ped, 0, false)
        SetPedCanRagdoll(ped, true)

        TaskGuardCurrentPosition(ped, 4.0, 4.0, true)

        table.insert(guards[netId].peds, ped)

        local playerPed = PlayerPedId()
        if #(GetEntityCoords(playerPed) - pos) <= g.detectionRadius
           and HasEntityClearLosToEntity(ped, playerPed, g.losFlags) then
            TaskCombatPed(ped, playerPed, 0, 16)
        end
    end

    -- loop IA
    CreateThread(function()
        while guards[netId] and #guards[netId].peds > 0 do
            local car = guards[netId].car
            if not car or not DoesEntityExist(car) then break end

            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)

            for idx = #guards[netId].peds, 1, -1 do
                local ped = guards[netId].peds[idx]
                if not ped or not DoesEntityExist(ped) then
                    table.remove(guards[netId].peds, idx)
                else
                    local pedCoords = GetEntityCoords(ped)
                    local dist = #(playerCoords - pedCoords)

                    if Config.Guard.stayNearCar then
                        local dCar = #(pedCoords - GetEntityCoords(car))
                        if dCar > Config.Guard.leashRadius and not IsPedInCombat(ped, playerPed) then
                            TaskGoToEntity(ped, car, -1, 3.0, 2.0, 0, 0)
                        end
                    end

                    if dist <= g.detectionRadius
                       and HasEntityClearLosToEntity(ped, playerPed, g.losFlags)
                       and not IsPedDeadOrDying(playerPed, true) then
                        TaskCombatPed(ped, playerPed, 0, 16)
                    else
                        if not IsPedInCombat(ped, playerPed) then
                            TaskGuardCurrentPosition(ped, 4.0, 4.0, true)
                        end
                    end
                end
            end

            Wait(500)
        end

        -- remaining cleanup
        if guards[netId] then
            for _, ped in ipairs(guards[netId].peds) do
                if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
            end
            guards[netId] = nil
        end
    end)
end

local function loadModelBlocking(model)
    local m = (type(model) == 'string') and joaat(model) or model
    if not IsModelInCdimage(m) then return false end
    RequestModel(m)
    while not HasModelLoaded(m) do Wait(0) end
    return m
end

-- =================
-- MENU (ox_lib)
-- =================
local function OpenFenrunMenu()
    -- fetch XP/level from server for bar
    local data = lib.callback.await('fenrun:getXP', false) or { xp = 0, level = 1, progress = 0, cap = 100 }
    local xp   = data.xp or 0
    local lvl  = data.level or 1
    local prog = percent(data.progress or 0)

    lib.registerContext({
        id = 'fenrun_menu',
        title = GetLocaleText('menu_title'),
        options = {
            {
                title       = GetLocaleText('menu_level', lvl, xp),
                description = GetLocaleText('menu_level_description'),
                icon        = 'star',
                disabled    = true,
                progress    = prog,   -- 0..100
                colorScheme = 'teal',
            },
            {
                title = GetLocaleText('menu_start_route'),
                description = GetLocaleText('menu_start_route_description'),
                icon = 'route',
                onSelect = function()
                    -- (same logic that was previously in target "Start route")
                    lib.callback('rizo-fentanylroute:canStartRoute', false, function(result)
                        if not result or not result.ok then
                            local reason = (result and result.reason) or 'Requirement not met.'
                            lib.notify({ title = 'Rota', description = reason, type = 'error' })
                            return
                        end

                        lib.callback('rizo-fentanylroute:consumeAndClearStash', false, function(cons)
                            if not cons or not cons.ok then
                                local reason = (cons and cons.reason) or 'Failed to consume stash.'
                                lib.notify({ title = 'Rota', description = reason, type = 'error' })
                                return
                            end

                            lib.notify({
                                title = 'Rota',
                                description = GetLocaleText('notify_route_started'),
                                type = 'success'
                            })

                            -- draw car coordinates
                            if Config.DestCoords and #Config.DestCoords > 0 then
                                chosenDest = Config.DestCoords[math.random(1, #Config.DestCoords)]
                            else
                                chosenDest = Config.DestCoord
                            end

                            -- waypoint/blip of car
                            if chosenDest then
                                SetNewWaypoint(chosenDest.x, chosenDest.y)
                                if not blip or not DoesBlipExist(blip) then
                                    blip = AddBlipForCoord(chosenDest.x, chosenDest.y, chosenDest.z)
                                    SetBlipSprite(blip, 225)
                                    SetBlipScale(blip, 0.9)
                                    SetBlipColour(blip, 5)
                                    BeginTextCommandSetBlipName('STRING')
                                    AddTextComponentString(GetLocaleText('blip_armored_vehicle'))
                                    EndTextCommandSetBlipName(blip)
                                end
                            end

                            -- arrival watcher at car location
                            if not arrivalWatcherStarted and chosenDest then
                                arrivalWatcherStarted = true
                                CreateThread(function()
                                    local radius = (Config.ArriveRadius or 45.0)
                                    local dest = vector3(chosenDest.x, chosenDest.y, chosenDest.z)

                                    while true do
                                        if not blip or not DoesBlipExist(blip) then
                                            arrivalWatcherStarted = false
                                            break
                                        end
                                        local pcoords = GetEntityCoords(PlayerPedId())
                                        if #(pcoords - dest) <= radius then
                                            RemoveBlip(blip)
                                            blip = nil
                                            arrivalWatcherStarted = false
                                            if lib and lib.notify then
                                                lib.notify({
                                                    title = 'Rota',
                                                    description = GetLocaleText('notify_defeat_guards'),
                                                    type = 'inform'
                                                })
                                            end
                                            break
                                        end
                                        Wait(500)
                                    end
                                end)
                            end

                            -- vehicle spawn
                            if not spawnedVehNet and chosenDest then
                                local chosenModel = chooseVehicleModel()
                                local model = loadModel(chosenModel)
                                local c = chosenDest
                                local veh = CreateVehicle(model, c.x, c.y, c.z, c.w, true, false)
                                SetVehicleOnGroundProperly(veh)

                                -- random license plate
                                local plate = ('%s%s%s%s%s%s'):format(
                                    string.char(math.random(65,90)),
                                    string.char(math.random(65,90)),
                                    math.random(0,9),
                                    math.random(0,9),
                                    string.char(math.random(65,90)),
                                    string.char(math.random(65,90))
                                )
                                SetVehicleNumberPlateText(veh, plate)
                                SetEntityAsMissionEntity(veh, true, true)

                                maxOutPerformance(veh)
                                fillFuelLC(veh, 100.0)

                                spawnVehicleGuards(veh)

                                spawnedVehNet = NetworkGetNetworkIdFromEntity(veh)
                            end
                        end)
                    end)
                end
            },
            {
                title = GetLocaleText('menu_deliver_items'),
                description = GetLocaleText('menu_deliver_items_description'),
                icon = 'box-open',
                onSelect = function()
                    lib.callback('rizo-fentanylroute:openStash', false, function(data)
                        if not data or not data.id then
                            lib.notify({ title='Stash', description=GetLocaleText('notify_stash_failed'), type='error' })
                            return
                        end
                        local ok = exports.ox_inventory:openInventory('stash', { id = data.id })
                        if ok == false then
                            lib.notify({ title='Stash', description=GetLocaleText('notify_stash_open_failed'), type='error' })
                        end
                    end)
                end
            },
        }
    })

    lib.showContext('fenrun_menu')
end

-- =================
-- 2 NPC
-- =================
local function spawnSecondNPC()
    if secondPed and DoesEntityExist(secondPed) then return end
    local m = loadModel(Config.SecondNPCModel)
    local c = chosenSecondNPC or (Config.SecondNPCCoords and Config.SecondNPCCoords[1]) or Config.SecondNPCCoord

    secondPed = CreatePed(0, m, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetEntityInvincible(secondPed, true)
    SetBlockingOfNonTemporaryEvents(secondPed, true)
    FreezeEntityPosition(secondPed, true)

    exports.ox_target:addLocalEntity(secondPed, {
        {
            icon = 'fa-solid fa-flask',
            label = GetLocaleText('target_receive_remover'),
            distance = Config.SecondTargetDistance or 2.0,
            onSelect = function()
                TriggerServerEvent('rizo-fentanylroute:givePaintThinner')

                if secondBlip and DoesBlipExist(secondBlip) then
                    RemoveBlip(secondBlip)
                    secondBlip = nil
                end

                if lib and lib.notify then
                    lib.notify({ title = 'Contato', description = GetLocaleText('notify_police_alerted'), type = 'success' })
                end

                -- 🔴 REMOVE NPC after taking item
                if secondPed and DoesEntityExist(secondPed) then
                    DeletePed(secondPed)
                    secondPed = nil
                end

                local veh = nil
                if spawnedVehNet then veh = NetworkGetEntityFromNetworkId(spawnedVehNet) end
                if not (veh and DoesEntityExist(veh)) then
                    veh = GetVehiclePedIsIn(PlayerPedId(), false)
                end
                if veh and DoesEntityExist(veh) then
                    local netId = NetworkGetNetworkIdFromEntity(veh)
                    TriggerServerEvent('rizo-fentanylroute:markVehicleForPolice', netId)

                    CreateThread(function()
                        local ms = math.max(1, (Config.TrackerDuration or 60)) * 1000
                        Wait(ms)

                        -- draw final contact coordinates
                        if Config.FinalNPCCoords and #Config.FinalNPCCoords > 0 then
                            chosenFinalNPC = Config.FinalNPCCoords[math.random(1, #Config.FinalNPCCoords)]
                        else
                            chosenFinalNPC = nil
                        end

                        if chosenFinalNPC then
                            -- final waypoint + blip
                            SetNewWaypoint(chosenFinalNPC.x, chosenFinalNPC.y)

                            if finalBlip and DoesBlipExist(finalBlip) then
                                RemoveBlip(finalBlip)
                                finalBlip = nil
                            end

                            finalBlip = AddBlipForCoord(chosenFinalNPC.x, chosenFinalNPC.y, chosenFinalNPC.z)
                            SetBlipSprite(finalBlip, 480)
                            SetBlipScale(finalBlip, 0.9)
                            SetBlipColour(finalBlip, 2)
                            BeginTextCommandSetBlipName('STRING')
                            AddTextComponentString(GetLocaleText('blip_fence'))
                            EndTextCommandSetBlipName(finalBlip)

                            -- ensure final NPC in world
                            spawnFinalNPC()

                            if lib and lib.notify then
                                lib.notify({ title = 'Rota', description = GetLocaleText('notify_fence_waiting'), type = 'inform' })
                            end
                        end
                    end)
                end
            end
        }
    })
end

-- =================
-- FINAL NPC
-- =================
spawnFinalNPC = function()
    if finalPed and DoesEntityExist(finalPed) then return end
    local m = loadModel(Config.FinalNPCModel)
    local c = chosenFinalNPC or (Config.FinalNPCCoords and Config.FinalNPCCoords[1])
    if not c then return end

    finalPed = CreatePed(0, m, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetEntityInvincible(finalPed, true)
    SetBlockingOfNonTemporaryEvents(finalPed, true)
    FreezeEntityPosition(finalPed, true)

    exports.ox_target:addLocalEntity(finalPed, {{
        icon = 'fa-solid fa-flask',
        label = GetLocaleText('target_fence'),
        distance = Config.FinalTargetDistance or 2.0,
        onSelect = function()
            -- If already marked as completed (by server confirmation), just inform
            if finalGiven then
                if lib and lib.notify then
                    lib.notify({ title = 'Contato', description = GetLocaleText('notify_already_finished'), type = 'inform' })
                end
                return
            end

            -- Check if spawned ARMORED CAR is nearby
            local veh = nil
            if spawnedVehNet then veh = NetworkGetEntityFromNetworkId(spawnedVehNet) end
            if not (veh and DoesEntityExist(veh)) then
                if lib and lib.notify then
                    lib.notify({ title = 'Contato', description = GetLocaleText('notify_wheres_car'), type = 'error' })
                end
                return
            end

            local vx, vy, vz = table.unpack(GetEntityCoords(veh))
            local dist = #(vector3(vx, vy, vz) - vector3(c.x, c.y, c.z))
            local need = Config.FinalNeedCarRadius or 25.0
            if dist > need then
                if lib and lib.notify then
                    lib.notify({ title = 'Contato', description = GetLocaleText('notify_bring_car_closer', math.floor(need)), type = 'error' })
                end
                return
            end

            -- Within radius: start progressbar
            local ok = true
            if lib and lib.progressCircle then
                ok = lib.progressCircle({
                    duration = Config.FinalProgressMs or 10000,
                    label = GetLocaleText('progress_completing_delivery'),
                    position = 'bottom',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = false, combat = true, mouse = false }
                })
            else
                Wait(Config.FinalProgressMs or 10000)
            end

            if ok then
                -- ⚠️ CHANGED: don't mark finalGiven here.
                -- Let SERVER check/remove item and, on success, it notifies client.
                if lib and lib.notify then
                    lib.notify({ title = 'Contato', description = GetLocaleText('notify_checking_items'), type = 'inform' })
                end

                -- Server validates required item and gives reward
                TriggerServerEvent('rizo-fentanylroute:giveFinalReward')
            end
        end
    }})
end


RegisterNetEvent('fenrun:finalSuccess', function(msg)
    finalGiven = true

    if lib and lib.notify then
        lib.notify({ title = 'Contato', description = msg or GetLocaleText('notify_delivery_completed_simple'), type = 'success' })
    end

    -- remove fence blip
    if finalBlip and DoesBlipExist(finalBlip) then
        RemoveBlip(finalBlip)
    end
    finalBlip = nil

    -- remove final NPC from world (prevents repeating delivery in same cycle)
    if finalPed and DoesEntityExist(finalPed) then
        DeletePed(finalPed)
        finalPed = nil
    end
end)


-- Failure: server refused (e.g.: without required item)
RegisterNetEvent('fenrun:finalFail', function(msg)
    if lib and lib.notify then
        lib.notify({ title = 'Contato', description = msg or GetLocaleText('notify_delivery_failed'), type = 'error' })
    end
end)

-- =================
-- FIRST NPC (only 1 target -> opens menu)
-- =================
local function spawnNPC()
    if ped and DoesEntityExist(ped) then return end
    local m = loadModel(Config.NPCModel)
    local c = Config.NPCCoord
    ped = CreatePed(0, m, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    exports.ox_target:addLocalEntity(ped, {
        {
            icon = 'fa-solid fa-user-secret',
            label = GetLocaleText('target_talk'),
            distance = Config.TargetDistance,
            onSelect = function()
                OpenFenrunMenu()
            end
        }
    })
end

-- watcher: detect when player enters spawned car
CreateThread(function()
    while true do
        Wait(300)
        if not spawnedVehNet then goto continue end
        local veh = NetworkGetEntityFromNetworkId(spawnedVehNet)
        if veh and DoesEntityExist(veh) then
            local ped = PlayerPedId()
            if IsPedInVehicle(ped, veh, false) and not enteredSpawnedVeh then
                enteredSpawnedVeh = true

                if blip and DoesBlipExist(blip) then
                    RemoveBlip(blip)
                    blip = nil
                end

                -- mark second contact
                if Config.SecondNPCCoords and #Config.SecondNPCCoords > 0 then
                    chosenSecondNPC = Config.SecondNPCCoords[math.random(1, #Config.SecondNPCCoords)]
                else
                    chosenSecondNPC = Config.SecondNPCCoord
                end

                local c2 = chosenSecondNPC
                if c2 then
                    SetNewWaypoint(c2.x, c2.y)
                    secondBlip = AddBlipForCoord(c2.x, c2.y, c2.z)
                    SetBlipSprite(secondBlip, 480)
                    SetBlipScale(secondBlip, 0.9)
                    SetBlipColour(secondBlip, 3)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString(GetLocaleText('blip_contact_reagent'))
                    EndTextCommandSetBlipName(secondBlip)

                    spawnSecondNPC()
                end
            end
        end
        ::continue::
    end
end)

-- initial spawn of 1st NPC
CreateThread(function()
    spawnNPC()
end)

-- optional cleanup when leaving resource
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if ped and DoesEntityExist(ped) then DeletePed(ped) end
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    if guards then
        for _, pack in pairs(guards) do
            if pack and pack.peds then
                for _, ped in ipairs(pack.peds) do
                    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
                end
            end
        end
        guards = {}
    end
    if secondPed and DoesEntityExist(secondPed) then DeletePed(secondPed) end
    if secondBlip and DoesBlipExist(secondBlip) then RemoveBlip(secondBlip) end
    if spawnedVehNet then
        local veh = NetworkGetEntityFromNetworkId(spawnedVehNet)
        if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
    end
    if finalPed and DoesEntityExist(finalPed) then DeletePed(finalPed) end
    if finalBlip and DoesBlipExist(finalBlip) then RemoveBlip(finalBlip) end
end)

-- police tracker by "pings"
RegisterNetEvent('rizo-fentanylroute:createPoliceBlipOnVehicle', function(netId, durationMs)
    if not netId then return end
    local pingMs = math.max(1, (Config.TrackerPingSeconds or 10)) * 1000
    local deadline = GetGameTimer() + (tonumber(durationMs) or 60000)

    local currentBlip = nil

    CreateThread(function()
        while GetGameTimer() < deadline do
            local veh = NetworkGetEntityFromNetworkId(netId)

            if veh and veh ~= 0 and DoesEntityExist(veh) then
                local coords = GetEntityCoords(veh)

                if currentBlip and DoesBlipExist(currentBlip) then
                    RemoveBlip(currentBlip)
                    currentBlip = nil
                end

                currentBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
                SetBlipSprite(currentBlip, 225)
                SetBlipScale(currentBlip, 0.9)
                SetBlipColour(currentBlip, 1)
                SetBlipAlpha(currentBlip, 200)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(GetLocaleText('blip_tracked_armored'))
                EndTextCommandSetBlipName(currentBlip)
            end

            Wait(pingMs)
        end

        if currentBlip and DoesBlipExist(currentBlip) then
            RemoveBlip(currentBlip)
        end
    end)
end)
