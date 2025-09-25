Locales = {}

Locales['en'] = {
    -- Menu
    menu_title = 'Suspicious Man',
    menu_level = 'Level %d | XP %d',
    menu_level_description = 'Complete the route to earn XP and level up.',
    menu_start_route = 'Start Route',
    menu_start_route_description = 'Take the vehicle and escape from police.',
    menu_deliver_items = 'Deliver Items',
    menu_deliver_items_description = 'Place the necessary items to start.',

    -- Notifications
    notify_someone_started_route = 'Someone already started a route, security is alert!',
    notify_wrong_item = 'You didn\'t place what\'s necessary to start.',
    notify_route_started = 'Route started, follow the GPS point.',
    notify_already_received = 'You already received the thinner from this route.',
    notify_no_inventory_space = 'No inventory space for the thinner.',
    notify_received_thinner = 'You received your thinner.',
    notify_need_paint_remover = 'You need paint remover to complete the delivery.',
    notify_stash_only_accepts = 'This stash only accepts %s',
    notify_final_reward_not_configured = 'Reward not configured.',
    notify_item_removal_failed = 'Failed to remove mandatory item.',
    notify_no_inventory_space_reward = 'No inventory space.',
    notify_delivery_completed = 'Delivery completed! Total XP: %d.',
    notify_defeat_guards = 'Defeat the guards and take the vehicle!',
    notify_police_alerted = 'Police have been alerted, escape from the cops!',
    notify_fence_waiting = 'The fence is waiting for you!',
    notify_already_finished = 'Already finished.',
    notify_wheres_car = 'Where\'s the car? Bring the armored vehicle here.',
    notify_bring_car_closer = 'Bring the car closer (≤ %dm).',
    notify_checking_items = 'Checking items...',
    notify_delivery_completed_simple = 'Delivery completed.',
    notify_delivery_failed = 'Could not complete delivery.',
    notify_he_doesnt_trust = 'He doesn\'t trust you',
    notify_stash_failed = 'Failed to prepare stash.',
    notify_stash_open_failed = 'Could not open stash now.',

    -- Progress bars
    progress_completing_delivery = 'Completing delivery...',

    -- Blips
    blip_armored_vehicle = 'Armored Vehicle',
    blip_fence = 'Fence',
    blip_contact_reagent = 'Contact: Reagent',
    blip_tracked_armored = 'Tracked Armored Vehicle',

    -- Target labels
    target_talk = 'Talk',
    target_receive_remover = 'Receive Remover',
    target_fence = 'Fence',

    -- Error messages
    error_no_player = 'No player',
    error_no_stash = 'No stash to consume',
    error_global_route_started = 'Global route already started in this server cycle.',
    error_remaining_items = 'Remaining items in stash (%d). Check server log.',
    error_item_not_identified = 'Could not identify item. Try again.',

    -- Police alert
    police_alert_title = '10-60',
    police_alert_message = 'Tracked Armored Vehicle Theft',

    -- Config labels
    config_stash_label = 'Deliver Items',

    -- Additional notifications
    notify_police_alerted = 'Police have been alerted, escape from the cops!',
}

-- Função para obter texto localizado
function GetLocaleText(key, ...)
    local locale = Config.Locale or 'en'
    local text = Locales[locale] and Locales[locale][key]

    if not text then
        return key -- Retorna a key se não encontrar o texto
    end

    if select('#', ...) > 0 then
        return string.format(text, ...)
    end

    return text
end