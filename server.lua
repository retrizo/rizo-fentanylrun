-- Framework detection
local QBCore, ESX = nil, nil
if Config.Framework == 'qbcore' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif Config.Framework == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
end

local DEBUG_ROUTE = false
local CASE_INSENSITIVE = true
local StashItemCount = {}  -- [stashId] = integer
local GlobalRouteLock = false      -- true = a route has already been started this cycle
local GlobalRouteStarter = nil     -- optional: who started (src/cid) for log
local GivenPaintThinner = {}   -- [src] = { given = true, last = os.time() }
local PAINT_THINNER_ANTISPAM = 2   -- seconds (anti double-click)
local DEBUG_HOOK = false

-- ===== INPUT VALIDATION FUNCTIONS =====
local function validateSource(src)
    return src and type(src) == 'number' and src > 0
end

local function validateNetId(netId)
    return netId and type(netId) == 'number' and netId > 0
end

local function validateCoords(coords)
    return coords and type(coords) == 'vector3' or
           (type(coords) == 'table' and coords.x and coords.y and coords.z)
end

local function validateString(str, minLength)
    minLength = minLength or 1
    return str and type(str) == 'string' and #str >= minLength
end

local function validateNumber(num, min, max)
    if not num or type(num) ~= 'number' then return false end
    if min and num < min then return false end
    if max and num > max then return false end
    return true
end

-- ===== ERROR HANDLING =====
local function safeExecute(func, errorMsg, ...)
    local success, result = pcall(func, ...)
    if not success then
        print(('[fenrun-error] %s: %s'):format(errorMsg or 'Unknown error', tostring(result)))
        return nil, result
    end
    return result
end

local function logError(context, error, playerSrc)
    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local player = playerSrc and (' [Player: %s]'):format(tostring(playerSrc)) or ''
    print(('[fenrun-error] [%s] %s%s: %s'):format(timestamp, context, player, tostring(error)))
end

-- ===== XP / LEVEL (fenrun) =====
-- Use Config values for consistency

local function getIdentifier(src)
    if Config.Framework == 'qbcore' then
        -- QBCore/QBox identifier
        if QBCore then
            local ok, result = pcall(function()
                local Player = QBCore.Functions.GetPlayer(src)
                return Player and Player.PlayerData and Player.PlayerData.citizenid
            end)
            if ok and result then return result end
        end
    elseif Config.Framework == 'esx' then
        -- ESX identifier
        if ESX then
            local ok, result = pcall(function()
                local xPlayer = ESX.GetPlayerFromId(src)
                return xPlayer and xPlayer.identifier
            end)
            if ok and result then return result end
        end
    end

    -- Fallback to license identifier
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('license:') then return id end
    end
    return ('unknown:%s'):format(src)
end

local function getXP(identifier)
    if not validateString(identifier, 5) then
        logError('getXP', 'Invalid identifier provided')
        return 0
    end

    local row = safeExecute(function()
        return MySQL.single.await('SELECT xp FROM fenrun_xp WHERE identifier = ?', { identifier })
    end, 'Database query failed in getXP')

    local maxXP = Config.LevelCap * Config.XPPerLevel
    return row and math.min(maxXP, math.max(0, tonumber(row.xp) or 0)) or 0
end

local function setXP(identifier, newXP)
    if not validateString(identifier, 5) then
        logError('setXP', 'Invalid identifier provided')
        return 0
    end

    local maxXP = Config.LevelCap * Config.XPPerLevel
    newXP = math.min(maxXP, math.max(0, tonumber(newXP) or 0))

    local success = safeExecute(function()
        return MySQL.update.await(
            'INSERT INTO fenrun_xp (identifier, xp) VALUES (?, ?) ON DUPLICATE KEY UPDATE xp = VALUES(xp)',
            { identifier, newXP }
        )
    end, 'Database update failed in setXP')

    if not success then
        logError('setXP', 'Failed to update XP for identifier: ' .. tostring(identifier))
        return 0
    end

    return newXP
end

local function addXP(identifier, amount)
    return setXP(identifier, getXP(identifier) + (tonumber(amount) or 0))
end

local function levelFromXP(xp)
    xp = tonumber(xp) or 0
    local level = math.floor(xp / Config.XPPerLevel) + 1
    if level > Config.LevelCap then level = Config.LevelCap end
    return level
end

local function xpInLevel(xp)
    xp = tonumber(xp) or 0
    return xp % Config.XPPerLevel
end

lib.callback.register('fenrun:getXP', function(src)
    local id = getIdentifier(src)
    local xp = getXP(id)
    local lvl = levelFromXP(xp)

    local prog = xpInLevel(xp)
    local pct = math.floor((prog / Config.XPPerLevel) * 100 + 0.5)

    return { xp = prog, level = lvl, progress = pct, cap = Config.XPPerLevel }
end)


local function getStashIdFromSrc(src)
    if Config.Framework == 'qbcore' then
        if not QBCore then return nil end
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return nil end
        return ('fentanyl_stash_%s'):format(player.PlayerData.citizenid)
    elseif Config.Framework == 'esx' then
        if not ESX then return nil end
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return nil end
        return ('fentanyl_stash_%s'):format(xPlayer.identifier:gsub('license:', ''))
    end
    return nil
end

-- ensures stash exists (idempotent)
local function ensureStash(stashId)
    exports.ox_inventory:RegisterStash(
        stashId,
        Config.StashLabel,
        Config.StashSlots,
        Config.StashMaxWeight,
        false
    )
    if StashItemCount[stashId] == nil then StashItemCount[stashId] = 0 end
end  -- <<< FALTAVA ESTE end

-- tries to get stash items from different ox_inventory versions
local function getStashItemsCompat(stashId)
    -- 1) GetInventoryItems('stash', id)
    local ok, inv = pcall(function()
        return exports.ox_inventory:GetInventoryItems('stash', stashId)
    end)
    if ok and inv then return inv end

    -- 2) GetInventory('stash', id) -> .items
    ok, inv = pcall(function()
        return exports.ox_inventory:GetInventory('stash', stashId)
    end)
    if ok and inv and inv.items then return inv.items end

    -- 3) prefixado
    ok, inv = pcall(function()
        return exports.ox_inventory:GetInventoryItems('stash:' .. stashId)
    end)
    if ok and inv then return inv end

    ok, inv = pcall(function()
        return exports.ox_inventory:GetInventory('stash:' .. stashId)
    end)
    if ok and inv and inv.items then return inv.items end

    return nil
end


lib.callback.register('rizo-fentanylroute:openStash', function(source)
    local stashId = getStashIdFromSrc(source)
    if not stashId then return false end
    ensureStash(stashId)
    return { id = stashId }
end)

-- validates if stash has exactly 5 fentanyl_batch and NO other items
lib.callback.register('rizo-fentanylroute:canStartRoute', function(source)
    local stashId = getStashIdFromSrc(source)
    if not stashId then
        if DEBUG_ROUTE then print('[fenrun-validate] sem player/source válido') end
        return { ok = false, reason = GetLocaleText('error_no_player') }
    end

    ensureStash(stashId)

    if GlobalRouteLock then
        return { ok = false, reason = GetLocaleText('notify_someone_started_route') }
    end

    -- 1) uses CACHE (robust to stash reading bug)
    local cached = StashItemCount[stashId] or 0

    -- 2) tries to read stash "for real" (if API cooperates) just to validate
    local items = getStashItemsCompat(stashId)
    if items == nil then
        Wait(50)
        items = getStashItemsCompat(stashId)
    end
    if items == nil then items = {} end

    local entries = 0
    for _ in pairs(items) do entries = entries + 1 end

    -- counts via real reading (if exists), checking other items
    local allow = Config.AllowedItem
    local want  = Config.RequiredCount
    local seenTotal = 0
    local otherFound, otherList = false, {}

    for _, it in pairs(items) do
        local name  = it and it.name
        local count = it and (it.count or it.amount or it.quantity or 0) or 0
        if name and count > 0 then
            local match = CASE_INSENSITIVE and (string.lower(name) == string.lower(allow)) or (name == allow)
            if match then
                seenTotal = seenTotal + count
            else
                otherFound = true
                otherList[#otherList+1] = (name .. ' x' .. tostring(count))
            end
        end
    end

    if DEBUG_ROUTE then
        local dump = nil
        pcall(function() dump = json.encode(items) end)
        print(('[fenrun-validate] stash=%s allow=%s req=%s entries=%s cache=%s seenTotal=%s'):format(
            tostring(stashId), tostring(allow), tostring(want), tostring(entries), tostring(cached), tostring(seenTotal)
        ))
        if dump then print('[fenrun-validate] dump='..dump) end
    end

    if otherFound then
        return { ok = false, reason = ('O stash só pode conter %s. Encontrado: %s'):format(allow, table.concat(otherList, ', ')) }
    end

    -- decision: prioritizes cache; if real reading exists, cross-references (uses the larger of the two)
    local effective = math.max(cached, seenTotal)

    if effective ~= want then
        return { ok = false, reason = GetLocaleText('notify_wrong_item') }
    end

    return { ok = true }
end)


-- HOOK pra bloquear qualquer item diferente de fentanyl_batch no stash + manter cache
local function isOurStash(invId)
    return type(invId) == 'string' and invId:find('^fentanyl_stash_') ~= nil
end

local function coerceSlot(slot)
    if type(slot) == 'number' then return slot end
    if type(slot) == 'table' then
        return slot.slot or slot[1] or slot.index or slot.id
    end
    return nil
end

exports.ox_inventory:registerHook('swapItems', function(payload)
    if DEBUG_HOOK then
        print(('[fenrun-hook] src=%s fromType=%s toType=%s fromInv=%s toInv=%s fromSlot=%s toSlot=%s count=%s'):format(
            tostring(payload and payload.source),
            tostring(payload and payload.fromType),
            tostring(payload and payload.toType),
            tostring(payload and payload.fromInventory),
            tostring(payload and payload.toInventory),
            type(payload and payload.fromSlot),
            tostring(payload and payload.toSlot),
            tostring(payload and payload.count)
        ))
    end

    -- só tratamos stashs nossos
    if not payload then return true end

    -------------------------------------------------------
    -- 1) ENTRADA no nosso stash -> só aceita AllowedItem
    -------------------------------------------------------
    if payload.toType == 'stash' and isOurStash(payload.toInventory) then
        local incomingName

        -- tenta pegar o nome do item
        if payload.fromItem and payload.fromItem.name then
            incomingName = payload.fromItem.name
        elseif payload.toItem and payload.toItem.name then
            incomingName = payload.toItem.name
        elseif payload.fromType == 'player' and payload.source and payload.fromSlot then
            local slotNum = coerceSlot(payload.fromSlot)
            if DEBUG_HOOK then print(('[fenrun-hook] coerced fromSlot => %s'):format(tostring(slotNum))) end
            if slotNum then
                local slotItem = exports.ox_inventory:GetSlot(payload.source, slotNum)
                if DEBUG_HOOK then print('[fenrun-hook] GetSlot =>', slotItem and slotItem.name or 'nil') end
                incomingName = slotItem and slotItem.name or incomingName
            end
        end

        if not incomingName then
            if DEBUG_HOOK then print('[fenrun-hook] incoming item não identificado; bloqueando por segurança.') end
            return false, GetLocaleText('error_item_not_identified')
        end

        if incomingName ~= Config.AllowedItem then
            return false, GetLocaleText('notify_stash_only_accepts', Config.AllowedItem)
        end

        -- aceito: atualiza cache
        local add = tonumber(payload.count) or 1
        local stashId = payload.toInventory
        ensureStash(stashId)
        StashItemCount[stashId] = math.max(0, (StashItemCount[stashId] or 0) + add)
        if DEBUG_HOOK then
            print(('[fenrun-hook] cache +%d -> %s = %d'):format(add, stashId, StashItemCount[stashId]))
        end
        return true
    end

    -------------------------------------------------------
    -- 2) SAÍDA do nosso stash -> se for AllowedItem, debita
    -------------------------------------------------------
    if payload.fromType == 'stash' and isOurStash(payload.fromInventory) then
        -- identificar nome do item que está saindo
        local outgoingName
        if payload.fromItem and payload.fromItem.name then
            outgoingName = payload.fromItem.name
        else
            -- fallback: ler pelo slot dentro do stash
            local inv = exports.ox_inventory:GetInventoryItems('stash', payload.fromInventory)
            local slotNum = coerceSlot(payload.fromSlot)
            if inv and slotNum then
                for _, it in pairs(inv) do
                    if it and it.slot == slotNum then
                        outgoingName = it.name
                        break
                    end
                end
            end
        end

        -- se for nosso item, debita do cache
        if outgoingName == Config.AllowedItem then
            local sub = tonumber(payload.count) or 1
            local stashId = payload.fromInventory
            ensureStash(stashId)
            StashItemCount[stashId] = math.max(0, (StashItemCount[stashId] or 0) - sub)
            if DEBUG_HOOK then
                print(('[fenrun-hook] cache -%d -> %s = %d'):format(sub, stashId, StashItemCount[stashId]))
            end
        end

        return true
    end

    return true
end, { print = false })

lib.callback.register('rizo-fentanylroute:consumeAndClearStash', function(source)
    local src = source
    if not src then
        print('[fenrun-clear] sem player/source válido')
        return { ok = false, reason = GetLocaleText('error_no_player') }
    end

    -- ===== Critical section: ensure global exclusivity =====
    if GlobalRouteLock then
        return { ok = false, reason = GetLocaleText('error_global_route_started') }
    end
    -- mark lock immediately to avoid race condition; if error occurs, we release at the end
    GlobalRouteLock = true
    GlobalRouteStarter = src
    -- ========================================================

    local stashId = getStashIdFromSrc(src)
    if not stashId then
        print('[fenrun-clear] sem stashId')
        GlobalRouteLock = false; GlobalRouteStarter = nil  -- release lock on failure
        return { ok = false, reason = GetLocaleText('error_no_stash') }
    end

    ensureStash(stashId)

    -- helper para ler itens do stash
    local function readItems()
        local t = getStashItemsCompat(stashId)
        if t == nil then
            Wait(50)
            t = getStashItemsCompat(stashId)
        end
        return t or {}
    end

    local items = readItems()
    local entries = 0
    for _ in pairs(items) do entries = entries + 1 end

    local removed = 0
    local used = {}

    -- 0) try to clear everything (various signatures)
    local ok0 = pcall(function() return exports.ox_inventory:ClearInventory(stashId) end)
    if ok0 then used[#used+1] = 'ClearInventory(<id>)' end

    if #used == 0 then
        local ok01 = pcall(function() return exports.ox_inventory:ClearInventory('stash', stashId) end)
        if ok01 then used[#used+1] = 'ClearInventory(stash,<id>)' end
    end

    if #used == 0 then
        local ok02 = pcall(function() return exports.ox_inventory:ClearInventory('stash:' .. stashId) end)
        if ok02 then used[#used+1] = 'ClearInventory(stash:<id>)' end
    end

    -- 1) fallback: remove item by item
    if #used == 0 then
        for _, it in pairs(items) do
            local name  = it and it.name
            local count = it and (it.count or it.amount or it.quantity or 0) or 0
            local slot  = it and it.slot
            if name and count > 0 then
                -- first WITHOUT prefix (as in your reference example)
                local okA = exports.ox_inventory:RemoveItem(stashId, name, count, it.metadata, slot)
                if not okA then okA = exports.ox_inventory:RemoveItem(stashId, name, count) end
                -- then WITH prefix (last attempt)
                if not okA then okA = exports.ox_inventory:RemoveItem('stash:' .. stashId, name, count, it.metadata, slot) end
                if not okA then okA = exports.ox_inventory:RemoveItem('stash:' .. stashId, name, count) end

                if okA then
                    removed = removed + count
                else
                    print(('[fenrun-clear] falha ao remover %s x%s (slot=%s) de %s'):format(
                        tostring(name), tostring(count), tostring(slot), stashId
                    ))
                end
            end
        end
        used[#used+1] = ('RemoveItem loop (%d entradas)'):format(entries)
    end

    -- zera o cache do hook, se estiver usando
    if StashItemCount then
        StashItemCount[stashId] = 0
    end

    -- verification: read again to confirm emptying
    local after = readItems()
    local left = 0
    for _, it in pairs(after) do
        local c = it and (it.count or it.amount or it.quantity or 0) or 0
        if c > 0 then left = left + c end
    end
    local dump
    pcall(function() dump = json.encode(after) end)

    print(('[fenrun-clear] stash=%s método=%s removidos=%s restantes=%s'):format(
        stashId, table.concat(used, ' | '), tostring(removed), tostring(left)
    ))
    if dump then print('[fenrun-clear] afterDump=' .. dump) end

    if left > 0 then
        -- failed to clear completely: release lock to not freeze server improperly
        GlobalRouteLock = false
        GlobalRouteStarter = nil
        return { ok = false, reason = GetLocaleText('error_remaining_items', left), removed = removed }
    end

    -- SUCCESS: keep lock active until restart
    GivenPaintThinner[source] = nil
    return { ok = true, removed = removed }
end)

-- Give 1x paint_stripper when player talks to second NPC
RegisterNetEvent('rizo-fentanylroute:givePaintThinner', function()
    local src = source
    if not validateSource(src) then return end

    -- fast anti-spam (prevents double click)
    local now = os.time()
    local state = GivenPaintThinner[src]
    if state and state.last and (now - state.last) < PAINT_THINNER_ANTISPAM then
        return
    end

    -- already received in this route?
    if state and state.given then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = GetLocaleText('notify_already_received')
        })
        return
    end

    -- validate ped/coords (robustness)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local pcoords = GetEntityCoords(ped)
    local v3 = vector3(pcoords.x, pcoords.y, pcoords.z)

    -- alerta policial (protegido com pcall)
    if Config.PoliceDispatch.enabled and Config.PoliceDispatch.type then
        local dispatchSystem = Config.DispatchSystems[Config.PoliceDispatch.type]
        if dispatchSystem and dispatchSystem.sendAlert then
            dispatchSystem.sendAlert(
                v3,
                GetLocaleText('police_alert_title'),
                GetLocaleText('police_alert_message'),
                'GENERAL'
            )
        end
    end

    -- tenta dar o item
    local ok = exports.ox_inventory:AddItem(src, 'paint_stripper', 1)
    if not ok then
        -- DON'T mark as "given" to allow trying again if it was just lack of space
        GivenPaintThinner[src] = { given = false, last = now }
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = GetLocaleText('notify_no_inventory_space')
        })
        print(('[fenrun] Falha ao dar paint_stripper para %s'):format(tostring(src)))
        return
    end

    -- success: mark that already received in this route
    GivenPaintThinner[src] = { given = true, last = now }

    TriggerClientEvent('ox_lib:notify', src, {
        type = 'success',
        description = GetLocaleText('notify_received_thinner')
    })
end)

-- Mark a vehicle for police for limited time
RegisterNetEvent('rizo-fentanylroute:markVehicleForPolice', function(netId)
    local src = source
    if not validateSource(src) or not validateNetId(netId) then return end
    -- DON'T use NetworkDoesNetworkIdExist here (client-only).
    -- Just forward to police officers; client validates entity existence before creating blip.

    local ms = math.max(1, (Config.TrackerDuration or 60)) * 1000

    if Config.Framework == 'qbcore' then
        if not QBCore then return end
        local players = QBCore.Functions.GetPlayers()

        for _, pid in ipairs(players) do
            local p = QBCore.Functions.GetPlayer(pid)
            if p and p.PlayerData and p.PlayerData.job then
                local job = p.PlayerData.job.name
                -- Check if job is in the configured police jobs list
                local dispatchSystem = Config.DispatchSystems[Config.PoliceDispatch.type]
                if dispatchSystem and dispatchSystem.jobs then
                    for _, policeJob in ipairs(dispatchSystem.jobs) do
                        if job == policeJob then
                            TriggerClientEvent('rizo-fentanylroute:createPoliceBlipOnVehicle', pid, netId, ms)
                            break
                        end
                    end
                end
            end
        end
    elseif Config.Framework == 'esx' then
        if not ESX then return end
        local players = ESX.GetExtendedPlayers()

        for _, xPlayer in pairs(players) do
            if xPlayer then
                local job = xPlayer.job.name
                -- Check if job is in the configured police jobs list
                local dispatchSystem = Config.DispatchSystems[Config.PoliceDispatch.type]
                if dispatchSystem and dispatchSystem.jobs then
                    for _, policeJob in ipairs(dispatchSystem.jobs) do
                        if job == policeJob then
                            TriggerClientEvent('rizo-fentanylroute:createPoliceBlipOnVehicle', xPlayer.source, netId, ms)
                            break
                        end
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('rizo-fentanylroute:giveFinalReward', function()
    local src = source
    if not validateSource(src) then return end

    local id  = getIdentifier(src)
    local xp  = getXP(id)
    local lvl = levelFromXP(xp)

    local required = (Config.RequiredFinalItem or 'paint_stripper')
    local reward   = (Config.LevelRewards or {})[lvl]

    if not reward then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description=GetLocaleText('notify_final_reward_not_configured') })
        return
    end

    -- 1) Check if player HAS the required item
    local have = 0
    local ok, count = pcall(function()
        return exports.ox_inventory:Search(src, 'count', required) -- conta total do item
    end)
    if ok and type(count) == 'number' then have = count end

    if have < 1 then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = GetLocaleText('notify_need_paint_remover')
        })
        return
    end

    -- 2) Remove the required item
    local removed = exports.ox_inventory:RemoveItem(src, required, 1)
    if not removed then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description=GetLocaleText('notify_item_removal_failed') })
        return
    end

    -- 3) Deliver the level reward
    local rewardItem = reward.item or reward  -- suporte para formato antigo e novo
    local rewardQty = reward.quantity or 1    -- suporte para formato antigo e novo

    local okGive = exports.ox_inventory:AddItem(src, rewardItem, rewardQty)
    if not okGive then
        -- (if it fails, return required item to not punish player)
        exports.ox_inventory:AddItem(src, required, 1)
        TriggerClientEvent('ox_lib:notify', src, { type='error', description=GetLocaleText('notify_no_inventory_space_reward') })
        return
    end

    -- 4) Apply XP and inform
    local gained = addXP(id, Config.XPOnFinal or 10)
    local newLvl = levelFromXP(gained)

    TriggerClientEvent('ox_lib:notify', src, {
        type = 'success',
        description = GetLocaleText('notify_delivery_completed', gained)
    })

    -- 5) Notify client to finish visually (blip/flag)
    TriggerClientEvent('fenrun:finalSuccess', src)
end)






