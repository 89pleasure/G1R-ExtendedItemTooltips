local MOD = "ExtendedItemTooltips"
local pleasureLib = require("pleasure_lib_loader").new(MOD)
if type(pleasureLib) ~= "table" then return end

_G.__EXTENDED_ITEM_TOOLTIPS_GENERATION =
    (_G.__EXTENDED_ITEM_TOOLTIPS_GENERATION or 0) + 1
local SCRIPT_GENERATION = _G.__EXTENDED_ITEM_TOOLTIPS_GENERATION

local function generation_is_current()
    return _G.__EXTENDED_ITEM_TOOLTIPS_GENERATION == SCRIPT_GENERATION
end

local function script_directory()
    local ok, info = pcall(function()
        if type(debug) ~= "table"
            or type(debug.getinfo) ~= "function"
        then
            return nil
        end
        return debug.getinfo(1, "S")
    end)
    if not ok or not info or not info.source then return nil end

    local source = tostring(info.source)
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return source:match("^(.*[\\/])[^\\/]*$")
end

local function load_local_module(file_name, module_name)
    local directory = script_directory()
    if type(directory) == "string" and directory ~= ""
        and type(dofile) == "function"
    then
        local ok, loaded = pcall(dofile, directory .. file_name)
        if ok and type(loaded) == "table" then return loaded end
        pleasureLib:log("Could not load " .. tostring(file_name)
            .. ": " .. tostring(loaded))
        return nil
    end

    local ok, loaded = pcall(require, module_name)
    if ok and type(loaded) == "table" then return loaded end
    pleasureLib:log("Could not load " .. tostring(module_name)
        .. ": " .. tostring(loaded))
    return nil
end

local Config = load_local_module(
    "extended_item_tooltips_config.lua",
    "extended_item_tooltips_config")
if type(Config) ~= "table" then return end
if type(Config.new) ~= "function" then
    pleasureLib:log("Config module factory unavailable")
    return
end
local config_ok, configController = pcall(Config.new, pleasureLib)
if not config_ok or type(configController) ~= "table" then
    pleasureLib:log("Could not initialize config module: "
        .. tostring(configController))
    return
end

local Runtime = load_local_module(
    "extended_item_tooltips_runtime.lua",
    "extended_item_tooltips_runtime")
if type(Runtime) ~= "table" or type(Runtime.new) ~= "function" then
    pleasureLib:log("Runtime module factory unavailable")
    return
end

local Inventory = load_local_module(
    "extended_item_tooltips_inventory.lua",
    "extended_item_tooltips_inventory")
if type(Inventory) ~= "table"
    or type(Inventory.new) ~= "function"
then
    pleasureLib:log("Inventory module factory unavailable")
    return
end

local Discovery = load_local_module(
    "extended_item_tooltips_discovery.lua",
    "extended_item_tooltips_discovery")
if type(Discovery) ~= "table"
    or type(Discovery.new) ~= "function"
then
    pleasureLib:log("Discovery module factory unavailable")
    return
end

local Hotbar = load_local_module(
    "extended_item_tooltips_hotbar.lua",
    "extended_item_tooltips_hotbar")
if type(Hotbar) ~= "table" or type(Hotbar.new) ~= "function" then
    pleasureLib:log("Hotbar module factory unavailable")
    return
end

local Hooks = load_local_module(
    "extended_item_tooltips_hooks.lua",
    "extended_item_tooltips_hooks")
if type(Hooks) ~= "table" or type(Hooks.new) ~= "function" then
    pleasureLib:log("Hook module factory unavailable")
    return
end

local Widgets = load_local_module(
    "extended_item_tooltips_widgets.lua",
    "extended_item_tooltips_widgets")
if type(Widgets) ~= "table" or type(Widgets.new) ~= "function" then
    pleasureLib:log("Widget module factory unavailable")
    return
end

local WeaponState = load_local_module(
    "extended_item_tooltips_weapon_state.lua",
    "extended_item_tooltips_weapon_state")
if type(WeaponState) ~= "table"
    or type(WeaponState.new) ~= "function"
then
    pleasureLib:log("Weapon state module factory unavailable")
    return
end

local WeaponBridge = load_local_module(
    "extended_item_tooltips_weapon_bridge.lua",
    "extended_item_tooltips_weapon_bridge")
if type(WeaponBridge) ~= "table"
    or type(WeaponBridge.new) ~= "function"
then
    pleasureLib:log("Weapon bridge module factory unavailable")
    return
end

local VERSION = "0.19.7"

local EQUIPPED_HOVER_DUPLICATE_COOLDOWN_MS = 40
local EQUIPPED_TOOLTIP_FORCE_DELAYS_MS = {
    20, 80, 160, 320,
}

local WEAPON_COMPARISON_RETRY_DELAYS_MS = {
    50, 100, 200, 350, 500, 750, 1000, 1500,
}

local INVENTORY_MAIN_PATH_NEEDLES = {
    "W_Inventory_Main",
    "InventoryMain",
}

local runtime_ok, runtime = pcall(Runtime.new, {
    pleasure_lib = pleasureLib,
    generation_is_current = generation_is_current,
    inventory_main_path_needles = INVENTORY_MAIN_PATH_NEEDLES,
})
if not runtime_ok or type(runtime) ~= "table" then
    pleasureLib:log("Could not initialize runtime module: "
        .. tostring(runtime))
    return
end

local inventory_ok, inventoryHelpers = pcall(Inventory.new, {
    pleasure_lib = pleasureLib,
    runtime = runtime,
})
if not inventory_ok or type(inventoryHelpers) ~= "table" then
    pleasureLib:log("Could not initialize inventory module: "
        .. tostring(inventoryHelpers))
    return
end

local hotbar_ok, hotbarResolver = pcall(Hotbar.new, {
    pleasure_lib = pleasureLib,
    runtime = runtime,
    first_hotbar_weapon_position =
        inventoryHelpers.first_hotbar_weapon_position,
})
if not hotbar_ok
    or type(hotbarResolver) ~= "table"
    or type(hotbarResolver.find_weapon_hotbar) ~= "function"
    or type(hotbarResolver.invalidate_cache) ~= "function"
    or type(hotbarResolver.begin_inventory_session) ~= "function"
then
    pleasureLib:log("Could not initialize hotbar module: "
        .. tostring(hotbarResolver))
    return
end

local discovery_ok, discovery = pcall(Discovery.new, {
    pleasure_lib = pleasureLib,
    runtime = runtime,
})
if not discovery_ok or type(discovery) ~= "table" then
    pleasureLib:log("Could not initialize discovery module: "
        .. tostring(discovery))
    return
end

local config = configController.values
local weapon_comparison_hover_settle_ms =
    configController.clamp_weapon_comparison_delay_ms
local widgets_ok, widgetHelpers = pcall(Widgets.new, {
    pleasure_lib = pleasureLib,
    runtime = runtime,
    config = config,
})
if not widgets_ok or type(widgetHelpers) ~= "table" then
    pleasureLib:log("Could not initialize widget module: "
        .. tostring(widgetHelpers))
    return
end

local weapon_state_ok, weaponState = pcall(WeaponState.new, {
    runtime = runtime,
    set_widget_visibility =
        widgetHelpers.set_widget_visibility,
    visibility_collapsed =
        widgetHelpers.visibility_collapsed,
    visibility_self_hit_test_invisible =
        widgetHelpers.visibility_self_hit_test_invisible,
})
if not weapon_state_ok
    or type(weaponState) ~= "table"
    or type(weaponState.is_active) ~= "function"
    or type(weaponState.source_matches) ~= "function"
    or type(weaponState.activate) ~= "function"
    or type(weaponState.maintain_visibility) ~= "function"
    or type(weaponState.end_comparison) ~= "function"
then
    pleasureLib:log("Could not initialize weapon state module: "
        .. tostring(weaponState))
    return
end

local bridge_ok, weaponBridge = pcall(WeaponBridge.new, {
    pleasure_lib = pleasureLib,
    runtime = runtime,
    set_widget_reference =
        widgetHelpers.set_widget_reference,
})
if not bridge_ok
    or type(weaponBridge) ~= "table"
    or type(weaponBridge.is_busy) ~= "function"
    or type(weaponBridge.run) ~= "function"
then
    pleasureLib:log("Could not initialize weapon bridge module: "
        .. tostring(weaponBridge))
    return
end

local is_valid = runtime.is_valid
local full_name = runtime.full_name
local object_instance_key = runtime.object_instance_key
local property_value = runtime.property_value
local bool_property = runtime.bool_property
local related_object_with_name = runtime.related_object_with_name
local tooltip_is_valid = runtime.tooltip_is_valid
local call_delegate = runtime.call_delegate
local run_later = runtime.run_later
local comparison_clock_ms = runtime.comparison_clock_ms
local array_length = runtime.array_length
local WIDGET_VISIBILITY_COLLAPSED =
    widgetHelpers.visibility_collapsed
local WIDGET_VISIBILITY_SELF_HIT_TEST_INVISIBLE =
    widgetHelpers.visibility_self_hit_test_invisible
local inventory_main_tooltip_widget =
    widgetHelpers.inventory_main_tooltip_widget
local inventory_weapon_compare_widget =
    widgetHelpers.inventory_weapon_compare_widget
local ensure_wearable_tooltip_links =
    widgetHelpers.ensure_wearable_tooltip_links
local equipped_tooltip_widgets =
    widgetHelpers.equipped_tooltip_widgets
local enable_wearables_tooltips =
    widgetHelpers.enable_wearables_tooltips
local ensure_inventory_tooltip_activation =
    widgetHelpers.ensure_inventory_tooltip_activation
local set_wearable_compare_flag =
    widgetHelpers.set_wearable_compare_flag
local set_widget_visibility =
    widgetHelpers.set_widget_visibility
local force_weapon_comparison_hint =
    widgetHelpers.force_weapon_comparison_hint
local inventory_session_token = 0
local weapon_comparison_settle_pending = false
local weapon_comparison_settle_timer_generation = 0
local weapon_comparison_settle_timer_due_at_ms = nil
local weapon_comparison_hint_reassert_pending = false
local weapon_comparison_hint_reassert_token = nil
local weapon_comparison_hint_reassert_inventory_main_key = nil
local weapon_comparison_hint_reassert_label = nil
local last_hover_at = {}
local active_equipped_hover = {
    active = false,
    token = 0,
    slot = nil,
    slot_key = nil,
    item_pos = nil,
    inventory_main = nil,
    wearables_bar = nil,
    should_show_wearable_compare = nil,
}
local active_inventory_comparison = {
    active = false,
    token = 0,
    slot_key = nil,
    item_pos = nil,
    inventory_main = nil,
    inventory_main_key = nil,
    weapon_type = nil,
    definition_name = nil,
    resolution_attempt = 0,
    comparison_attempt = 0,
    settle_not_before_ms = nil,
}
local reset_inventory_runtime_state = nil
local on_slot_hovered = nil

local function on_inventory_shown(_hook_name, context)
    local inventory_main = pleasureLib:unwrap(context)
    if not is_valid(inventory_main) then return nil end

    if type(reset_inventory_runtime_state) == "function" then
        reset_inventory_runtime_state("inventory.shown")
    end
    hotbarResolver.begin_inventory_session()
    discovery.begin_inventory_session(inventory_main)
    set_wearable_compare_flag(inventory_main,
        config.EnableComparisonTooltips == true
            and config.ComparisonDefaultEnabled == true,
        "inventory.shown.default")
    return nil
end

local function schedule_weapon_comparison_hint_reassert(label)
    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.weapon_type == nil
    then
        return false
    end

    weapon_comparison_hint_reassert_token =
        active_inventory_comparison.token
    weapon_comparison_hint_reassert_inventory_main_key =
        active_inventory_comparison.inventory_main_key
    weapon_comparison_hint_reassert_label = tostring(label)
    if weapon_comparison_hint_reassert_pending then return true end

    weapon_comparison_hint_reassert_pending = true
    local scheduled = run_later(0, function()
        weapon_comparison_hint_reassert_pending = false
        local requested_token =
            weapon_comparison_hint_reassert_token
        local requested_inventory_main_key =
            weapon_comparison_hint_reassert_inventory_main_key
        local requested_label =
            weapon_comparison_hint_reassert_label
        weapon_comparison_hint_reassert_token = nil
        weapon_comparison_hint_reassert_inventory_main_key = nil
        weapon_comparison_hint_reassert_label = nil

        if active_inventory_comparison.active ~= true
            or active_inventory_comparison.weapon_type == nil
            or active_inventory_comparison.token ~= requested_token
            or active_inventory_comparison.inventory_main_key
                ~= requested_inventory_main_key
        then
            return
        end
        force_weapon_comparison_hint(
            active_inventory_comparison.inventory_main, true,
            tostring(requested_label) .. ".postUpdate")
    end)
    if not scheduled then
        weapon_comparison_hint_reassert_pending = false
    end
    return scheduled
end

local function on_inventory_tooltip_updated(_hook_name, context)
    if config.Enabled ~= true
        or config.EnableComparisonTooltips ~= true
        or active_inventory_comparison.active ~= true
        or active_inventory_comparison.weapon_type == nil
    then
        return nil
    end

    local updated_tooltip = pleasureLib:unwrap(context)
    local inventory_main = active_inventory_comparison.inventory_main
    local base_tooltip = inventory_main_tooltip_widget(inventory_main)
    if not is_valid(updated_tooltip)
        or object_instance_key(updated_tooltip)
            ~= object_instance_key(base_tooltip)
    then
        return nil
    end

    force_weapon_comparison_hint(inventory_main, true,
        "comparison.tooltipUpdated")
    return nil
end

local function force_equipped_tooltip_widgets(wearables_bar, inventory_main, label, token)
    if config.ForceTooltipVisibility ~= true then return false end
    if active_equipped_hover.active ~= true then return false end
    if token ~= nil and active_equipped_hover.token ~= token then return false end

    inventory_main = pleasureLib:unwrap(inventory_main)
    wearables_bar = pleasureLib:unwrap(wearables_bar)
    if not is_valid(inventory_main) then
        inventory_main = active_equipped_hover.inventory_main
    end
    if not is_valid(wearables_bar) then
        wearables_bar = active_equipped_hover.wearables_bar
    end

    ensure_wearable_tooltip_links(wearables_bar, inventory_main, label)
    local widgets = equipped_tooltip_widgets(wearables_bar, inventory_main)
    if #widgets == 0 then return false end

    local forced = false
    for _, entry in ipairs(widgets) do
        forced = set_widget_visibility(entry.widget,
            WIDGET_VISIBILITY_SELF_HIT_TEST_INVISIBLE,
            tostring(label) .. "." .. tostring(entry.label)) or forced
    end
    return forced
end

local function schedule_equipped_tooltip_force(wearables_bar, inventory_main, label)
    if config.ForceTooltipVisibility ~= true then return false end
    if active_equipped_hover.active ~= true then return false end

    local token = active_equipped_hover.token
    force_equipped_tooltip_widgets(wearables_bar, inventory_main,
        tostring(label) .. ".immediate", token)
    local function schedule_force(delay_ms)
        run_later(delay_ms, function()
            force_equipped_tooltip_widgets(wearables_bar, inventory_main,
                tostring(label) .. ".delay" .. tostring(delay_ms), token)
        end)
    end
    for _, delay_ms in ipairs(EQUIPPED_TOOLTIP_FORCE_DELAYS_MS) do
        schedule_force(delay_ms)
    end
    return true
end

local function hide_equipped_tooltip_widgets(wearables_bar, inventory_main, label)
    if config.ForceTooltipVisibility ~= true then return false end

    ensure_wearable_tooltip_links(wearables_bar, inventory_main, label)
    local hidden = false
    for _, entry in ipairs(equipped_tooltip_widgets(wearables_bar, inventory_main)) do
        hidden = set_widget_visibility(entry.widget,
            WIDGET_VISIBILITY_COLLAPSED,
            tostring(label) .. "." .. tostring(entry.label)) or hidden
    end
    return hidden
end

local function equipped_rehover_allowed(slot)
    local key = full_name(slot)
    if key == "" then return true end

    local now = math.floor(os.clock() * 1000)
    local previous = last_hover_at[key] or -1000000
    if now - previous < EQUIPPED_HOVER_DUPLICATE_COOLDOWN_MS then
        return false
    end
    last_hover_at[key] = now
    return true
end

local function begin_equipped_hover(slot, inventory_main, wearables_bar, item_pos)
    local previous_compare = active_equipped_hover.should_show_wearable_compare
    active_equipped_hover.active = true
    active_equipped_hover.token = active_equipped_hover.token + 1
    active_equipped_hover.slot = slot
    active_equipped_hover.slot_key = object_instance_key(slot)
    active_equipped_hover.item_pos = item_pos
    active_equipped_hover.inventory_main = inventory_main
    active_equipped_hover.wearables_bar = wearables_bar
    if previous_compare ~= nil then
        active_equipped_hover.should_show_wearable_compare = previous_compare
    else
        active_equipped_hover.should_show_wearable_compare =
            bool_property(inventory_main, "ShouldShowWearableCompare")
    end

    ensure_inventory_tooltip_activation(inventory_main, "hover.begin")
    set_wearable_compare_flag(inventory_main, true, "hover.begin")
    ensure_wearable_tooltip_links(wearables_bar, inventory_main, "hover.begin")
end

local function end_equipped_hover(inventory_main)
    active_equipped_hover.active = false
    active_equipped_hover.token = active_equipped_hover.token + 1
    active_equipped_hover.slot = nil
    active_equipped_hover.slot_key = nil
    active_equipped_hover.item_pos = nil
    active_equipped_hover.inventory_main = nil
    active_equipped_hover.wearables_bar = nil

    local previous_compare = active_equipped_hover.should_show_wearable_compare
    active_equipped_hover.should_show_wearable_compare = nil
    if previous_compare ~= nil then
        set_wearable_compare_flag(inventory_main, previous_compare, "hover.end")
    end
end

local function equipped_hover_matches(slot, item_pos)
    if active_equipped_hover.active ~= true then return false end
    return active_equipped_hover.slot_key == object_instance_key(slot)
        and active_equipped_hover.item_pos == item_pos
end

local function broadcast_slot_hover(slot, is_hovered, item_pos)
    if not is_valid(slot) then return false end
    if item_pos == nil then return false end

    local ok, result = call_delegate(property_value(slot, "DispatcherOnHovered"),
        is_hovered, item_pos)
    pleasureLib:debug_log("broadcasted slot hover dispatcher"
        .. " hovered=" .. tostring(is_hovered)
        .. " itemPos=" .. tostring(item_pos)
        .. " ok=" .. tostring(ok)
        .. " result=" .. tostring(result))
    return ok == true
end

local function stop_active_equipped_hover(label)
    if active_equipped_hover.active ~= true then return false end

    local slot = active_equipped_hover.slot
    local item_pos = active_equipped_hover.item_pos
    local inventory_main = active_equipped_hover.inventory_main
    local wearables_bar = active_equipped_hover.wearables_bar
    end_equipped_hover(inventory_main)
    broadcast_slot_hover(slot, false, item_pos)
    hide_equipped_tooltip_widgets(wearables_bar, inventory_main,
        tostring(label) .. ".itemPos" .. tostring(item_pos))
    return true
end

local function begin_weapon_comparison(
    inventory_main, weapon_type, definition_name, source_slot_key,
    source_item_pos, comparison_token, attempt)
    attempt = tonumber(attempt) or 0
    if weapon_type == nil or source_item_pos == nil then
        return false, false, "invalid comparison snapshot"
    end
    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.token ~= comparison_token
    then
        return false, false, "comparison request changed"
    end

    local source_inventory_main_key =
        active_inventory_comparison.inventory_main_key
    if weaponState.source_matches(source_inventory_main_key,
        source_slot_key, source_item_pos, weapon_type, definition_name)
    then
        weaponState.maintain_visibility(
            "weaponComparison.unchanged")
        -- A regular inventory refresh evaluates the weapon's native specs
        -- and collapses this already-configured wearable-comparison input.
        -- Restore only its visibility; never mutate the shared item definition.
        force_weapon_comparison_hint(inventory_main, true,
            "weaponComparison.unchanged")
        return true, false, nil
    end

    if weaponBridge.is_busy() then
        return false, false, "comparison bridge busy"
    end

    local hotbar = hotbarResolver.find_weapon_hotbar(
        inventory_main, weapon_type, attempt)
    if not is_valid(hotbar) then
        return false, true, "vanilla hotbar unavailable"
    end

    local weapon_position, weapon_definition, hotbar_ready =
        inventoryHelpers.first_hotbar_weapon_position(
            hotbar,
            weapon_type)
    if weapon_position == nil or not is_valid(weapon_definition) then
        if hotbar_ready ~= true then
            return false, true, "hotbar inventory not ready"
        end
        return false, true, "matching hotbar weapon unavailable"
    end

    local base_widget = inventory_main_tooltip_widget(inventory_main)
    local compare_widget = inventory_weapon_compare_widget(inventory_main)
    if not is_valid(base_widget) or not is_valid(compare_widget) then
        return false, true, "inventory tooltip widgets unavailable"
    end

    local hotbar_slot_count = array_length(property_value(hotbar, "m_SlotsData"))
    if hotbar_slot_count == nil or weapon_position == nil or weapon_position < 0
        or weapon_position >= hotbar_slot_count
    then
        return false, true, "hotbar slot index unavailable"
            .. " position=" .. tostring(weapon_position)
            .. " slotCount=" .. tostring(hotbar_slot_count)
    end
    pleasureLib:debug_log("resolved hotbar weapon comparison entry"
        .. " position=" .. tostring(weapon_position)
        .. " inventoryType=" .. tostring(weapon_type)
        .. " definition=" .. full_name(weapon_definition))

    -- Hotbar creation can dispatch UI events. Do not enter the native bridge
    -- if one of them replaced this hover while readiness was being resolved.
    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.token ~= comparison_token
        or active_inventory_comparison.inventory_main_key
            ~= source_inventory_main_key
        or active_inventory_comparison.slot_key ~= source_slot_key
        or active_inventory_comparison.item_pos ~= source_item_pos
    then
        return false, false, "comparison request changed during readiness"
    end

    if weaponState.is_active() then
        weaponState.end_comparison("weaponComparison.replace")
    end

    local route_ok, route_error = weaponBridge.run(
        hotbar, inventory_main, base_widget, compare_widget,
        weapon_position)
    if not route_ok then
        set_widget_visibility(compare_widget, WIDGET_VISIBILITY_COLLAPSED,
            "weaponComparison.bridgeFailed", true)
        pleasureLib:debug_log("weapon comparison native route failed"
            .. " reason=" .. tostring(route_error)
            .. " inventoryType=" .. tostring(weapon_type)
            .. " position=" .. tostring(weapon_position)
            .. " definition=" .. tostring(definition_name))
        -- A native bridge failure is not retried for the same hover.
        return false, false, route_error
    end

    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.token ~= comparison_token
        or active_inventory_comparison.slot_key ~= source_slot_key
        or active_inventory_comparison.item_pos ~= source_item_pos
    then
        set_widget_visibility(compare_widget, WIDGET_VISIBILITY_COLLAPSED,
            "weaponComparison.requestChanged", true)
        return false, false, "comparison request changed during bridge"
    end

    weaponState.activate(compare_widget, source_inventory_main_key,
        source_slot_key, source_item_pos, weapon_type, definition_name)
    weaponState.maintain_visibility(
        "weaponComparison")
    -- UpdateToolTipOnSlot refreshes the base tooltip synchronously and hides
    -- this input for weapons because they have no wearable ItemSpec. Reassert
    -- the configured CTRL hint only after the native bridge has returned.
    force_weapon_comparison_hint(inventory_main, true,
        "weaponComparison.afterBridge")
    pleasureLib:debug_log("weapon comparison active"
        .. " inventoryType=" .. tostring(weapon_type)
        .. " position=" .. tostring(weapon_position)
        .. " definition=" .. tostring(definition_name))
    return true, false, nil
end

local function invalidate_weapon_comparison_settle_timer()
    weapon_comparison_settle_timer_generation =
        weapon_comparison_settle_timer_generation + 1
    weapon_comparison_settle_pending = false
    weapon_comparison_settle_timer_due_at_ms = nil
end

local function clear_inventory_comparison_state()
    invalidate_weapon_comparison_settle_timer()
    active_inventory_comparison.active = false
    active_inventory_comparison.slot_key = nil
    active_inventory_comparison.item_pos = nil
    active_inventory_comparison.inventory_main = nil
    active_inventory_comparison.inventory_main_key = nil
    active_inventory_comparison.weapon_type = nil
    active_inventory_comparison.definition_name = nil
    active_inventory_comparison.resolution_attempt = 0
    active_inventory_comparison.comparison_attempt = 0
    active_inventory_comparison.settle_not_before_ms = nil
    weapon_comparison_hint_reassert_token = nil
    weapon_comparison_hint_reassert_inventory_main_key = nil
    weapon_comparison_hint_reassert_label = nil
end

local function end_inventory_comparison(label)
    if active_inventory_comparison.active ~= true then return false end

    active_inventory_comparison.token = active_inventory_comparison.token + 1
    weaponState.end_comparison(tostring(label) .. ".weapon")
    clear_inventory_comparison_state()
    return true
end

reset_inventory_runtime_state = function(label)
    inventory_session_token = inventory_session_token + 1

    if active_equipped_hover.active == true then
        stop_active_equipped_hover(tostring(label) .. ".equipped")
    end
    if active_inventory_comparison.active == true then
        end_inventory_comparison(tostring(label) .. ".inventory")
    elseif weaponState.is_active() then
        weaponState.end_comparison(tostring(label) .. ".weapon")
    end

    active_inventory_comparison.token =
        active_inventory_comparison.token + 1
    clear_inventory_comparison_state()
    active_equipped_hover.token = active_equipped_hover.token + 1
    last_hover_at = {}
    discovery.reset()
    hotbarResolver.invalidate_cache()
end

local function inventory_comparison_matches(slot, item_pos)
    if active_inventory_comparison.active ~= true then return false end
    return active_inventory_comparison.slot_key == object_instance_key(slot)
        and active_inventory_comparison.item_pos == item_pos
end

local schedule_weapon_comparison_settle = nil

local function settle_active_inventory_comparison()
    if active_inventory_comparison.active ~= true then return false end

    local comparison_token = active_inventory_comparison.token
    local inventory_main = active_inventory_comparison.inventory_main
    local inventory_main_key =
        active_inventory_comparison.inventory_main_key
    local item_pos = active_inventory_comparison.item_pos
    if not is_valid(inventory_main)
        or object_instance_key(inventory_main) ~= inventory_main_key
    then
        end_inventory_comparison("comparison.inventoryUnavailable")
        return false
    end

    local weapon_type = active_inventory_comparison.weapon_type
    local definition_name =
        active_inventory_comparison.definition_name or ""
    if weapon_type == nil then
        local definition_resolved = false
        weapon_type, definition_name, definition_resolved =
            inventoryHelpers.weapon_inventory_type_at_position(
                inventory_main,
                item_pos)
        if active_inventory_comparison.active ~= true
            or active_inventory_comparison.token ~= comparison_token
        then
            return false
        end

        if definition_resolved ~= true then
            local attempt =
                active_inventory_comparison.resolution_attempt + 1
            local delay_ms =
                WEAPON_COMPARISON_RETRY_DELAYS_MS[attempt]
            if delay_ms == nil then
                pleasureLib:debug_log(
                    "weapon classification readiness exhausted"
                    .. " itemPos=" .. tostring(item_pos)
                    .. " attempts=" .. tostring(
                        active_inventory_comparison.resolution_attempt))
                end_inventory_comparison(
                    "comparison.classificationUnavailable")
                return false
            end

            active_inventory_comparison.resolution_attempt = attempt
            pleasureLib:debug_log(
                "weapon classification waiting for inventory"
                .. " itemPos=" .. tostring(item_pos)
                .. " attempt=" .. tostring(attempt)
                .. " delayMs=" .. tostring(delay_ms))
            return schedule_weapon_comparison_settle(delay_ms)
        end

        if weapon_type == nil then
            end_inventory_comparison("comparison.nativeItem")
            pleasureLib:debug_log("comparison uses native item handling"
                .. " definition=" .. tostring(definition_name))
            return false
        end

        active_inventory_comparison.weapon_type = weapon_type
        active_inventory_comparison.definition_name = definition_name
        active_inventory_comparison.resolution_attempt = 0
    end

    ensure_inventory_tooltip_activation(inventory_main,
        "comparison.settled")
    force_weapon_comparison_hint(inventory_main, true,
        "comparison.settled")
    if bool_property(inventory_main,
        "ShouldShowWearableCompare") ~= true
    then
        weaponState.end_comparison("comparison.disabled")
        return true
    end

    local source_slot_key = active_inventory_comparison.slot_key
    local source_item_pos = active_inventory_comparison.item_pos
    local attempt = active_inventory_comparison.comparison_attempt
    local started, retry_ready, reason = begin_weapon_comparison(
        inventory_main, weapon_type, definition_name, source_slot_key,
        source_item_pos, comparison_token, attempt)
    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.token ~= comparison_token
    then
        return false
    end
    if started then
        active_inventory_comparison.comparison_attempt = 0
        return true
    end
    if retry_ready ~= true then
        pleasureLib:debug_log("weapon comparison stopped for hover"
            .. " reason=" .. tostring(reason)
            .. " definition=" .. tostring(definition_name))
        return false
    end

    local next_attempt = attempt + 1
    local delay_ms = WEAPON_COMPARISON_RETRY_DELAYS_MS[next_attempt]
    if delay_ms == nil then
        pleasureLib:debug_log("weapon comparison readiness exhausted"
            .. " reason=" .. tostring(reason)
            .. " attempts=" .. tostring(attempt)
            .. " definition=" .. tostring(definition_name))
        end_inventory_comparison("weaponComparison.readinessExhausted")
        return false
    end

    active_inventory_comparison.comparison_attempt = next_attempt
    pleasureLib:debug_log("weapon comparison waiting for readiness"
        .. " reason=" .. tostring(reason)
        .. " attempt=" .. tostring(next_attempt)
        .. " delayMs=" .. tostring(delay_ms)
        .. " definition=" .. tostring(definition_name))
    return schedule_weapon_comparison_settle(delay_ms)
end

schedule_weapon_comparison_settle = function(delay_ms)
    if active_inventory_comparison.active ~= true then return false end

    local inventory_main = active_inventory_comparison.inventory_main
    local now_ms = comparison_clock_ms(inventory_main)
    delay_ms = math.max(0, math.floor(tonumber(delay_ms)
        or weapon_comparison_hover_settle_ms(
            config.TooltipCooldownMs)))
    local timer_due_at_ms = nil
    if now_ms ~= nil then timer_due_at_ms = now_ms + delay_ms end

    -- Keep one effective wake-up. A later request can reuse the existing
    -- earlier timer; an earlier request supersedes it while the old callback
    -- becomes a generation-checked no-op.
    if weapon_comparison_settle_pending then
        if weapon_comparison_settle_timer_due_at_ms == nil
            or timer_due_at_ms == nil
            or weapon_comparison_settle_timer_due_at_ms
                <= timer_due_at_ms
        then
            return true
        end
    end

    weapon_comparison_settle_timer_generation =
        weapon_comparison_settle_timer_generation + 1
    local timer_generation =
        weapon_comparison_settle_timer_generation
    local scheduled_token = active_inventory_comparison.token
    local session_token = inventory_session_token
    weapon_comparison_settle_pending = true
    weapon_comparison_settle_timer_due_at_ms = timer_due_at_ms
    local scheduled = run_later(delay_ms, function()
        if timer_generation
            ~= weapon_comparison_settle_timer_generation
        then
            return
        end

        weapon_comparison_settle_pending = false
        weapon_comparison_settle_timer_due_at_ms = nil
        if active_inventory_comparison.active ~= true then return end

        local current_time_ms = comparison_clock_ms(
            active_inventory_comparison.inventory_main)
        local settle_not_before_ms = tonumber(
            active_inventory_comparison.settle_not_before_ms)
        if current_time_ms ~= nil
            and settle_not_before_ms ~= nil
            and current_time_ms < settle_not_before_ms
        then
            schedule_weapon_comparison_settle(
                settle_not_before_ms - current_time_ms)
            return
        end

        if inventory_session_token ~= session_token
            or active_inventory_comparison.token ~= scheduled_token
        then
            local replacement_delay_ms = 0
            if current_time_ms == nil
                or settle_not_before_ms == nil
            then
                replacement_delay_ms =
                    weapon_comparison_hover_settle_ms(
                        config.TooltipCooldownMs)
            end
            schedule_weapon_comparison_settle(replacement_delay_ms)
            return
        end
        settle_active_inventory_comparison()
    end)
    if not scheduled
        and timer_generation
            == weapon_comparison_settle_timer_generation
    then
        weapon_comparison_settle_pending = false
        weapon_comparison_settle_timer_due_at_ms = nil
    end
    return scheduled
end

local function schedule_weapon_comparison_hover_settle()
    if active_inventory_comparison.active ~= true then return false end

    local delay_ms = weapon_comparison_hover_settle_ms(
        config.TooltipCooldownMs)
    local current_time_ms = comparison_clock_ms(
        active_inventory_comparison.inventory_main)
    active_inventory_comparison.settle_not_before_ms = nil
    if current_time_ms ~= nil then
        active_inventory_comparison.settle_not_before_ms =
            current_time_ms + delay_ms
    end
    pleasureLib:debug_log("scheduled weapon comparison hover settle"
        .. " delayMs=" .. tostring(delay_ms)
        .. " itemPos="
        .. tostring(active_inventory_comparison.item_pos))
    return schedule_weapon_comparison_settle(delay_ms)
end

local function begin_inventory_comparison(slot)
    if config.EnableComparisonTooltips ~= true then return false end

    local inventory_main = related_object_with_name(slot, "W_Inventory_Main")
    if not is_valid(inventory_main) then
        if active_inventory_comparison.active == true then
            end_inventory_comparison("comparison.inventoryMissing")
        end
        return false
    end
    if inventoryHelpers.slot_has_hotbar_assignment(slot) then
        if active_inventory_comparison.active == true then
            end_inventory_comparison("comparison.hotbarAssigned")
        end
        force_weapon_comparison_hint(inventory_main, false,
            "comparison.hotbarAssigned")
        pleasureLib:debug_log("comparison skipped: item is assigned to hotbar"
            .. " slot=" .. full_name(slot))
        return false
    end

    -- The list slot is virtualized. Read everything needed while the hook
    -- owns a live object, then keep only scalar identity values.
    local slot_key = object_instance_key(slot)
    local item_pos = inventoryHelpers.slot_item_pos(slot)
    if slot_key == "" or item_pos == nil or item_pos < 0 then
        if active_inventory_comparison.active == true then
            end_inventory_comparison("comparison.snapshotInvalid")
        end
        return false
    end
    local inventory_main_key = object_instance_key(inventory_main)
    local weapon_type, definition_name, definition_resolved =
        inventoryHelpers.weapon_inventory_type_at_position(
            inventory_main,
            item_pos)
    if definition_resolved == true and weapon_type == nil then
        if active_inventory_comparison.active == true then
            end_inventory_comparison("comparison.nativeItem")
        end
        pleasureLib:debug_log("comparison uses native item handling"
            .. " definition=" .. tostring(definition_name))
        return false
    end

    local same_target = active_inventory_comparison.active == true
        and active_inventory_comparison.slot_key == slot_key
        and active_inventory_comparison.item_pos == item_pos
        and active_inventory_comparison.inventory_main_key
            == inventory_main_key
        and active_inventory_comparison.weapon_type == weapon_type
        and active_inventory_comparison.definition_name
            == definition_name
    if same_target then
        -- A re-hover of the same virtual row is still a newer event. Advance
        -- the epoch so a queued unhover from its prior incarnation cannot
        -- clear the current comparison.
        active_inventory_comparison.token =
            active_inventory_comparison.token + 1
        if weapon_type ~= nil then
            ensure_inventory_tooltip_activation(inventory_main,
                "comparison.rehover")
            force_weapon_comparison_hint(inventory_main, true,
                "comparison.rehover")
            schedule_weapon_comparison_hint_reassert(
                "comparison.rehover")
        end
        return schedule_weapon_comparison_hover_settle()
    end

    if weaponState.is_active()
        and not weaponState.source_matches(inventory_main_key,
            slot_key, item_pos, weapon_type, definition_name)
    then
        weaponState.end_comparison("weaponComparison.targetChanged")
    end

    active_inventory_comparison.active = true
    active_inventory_comparison.token =
        active_inventory_comparison.token + 1
    active_inventory_comparison.slot_key = slot_key
    active_inventory_comparison.item_pos = item_pos
    active_inventory_comparison.inventory_main = inventory_main
    active_inventory_comparison.inventory_main_key = inventory_main_key
    active_inventory_comparison.weapon_type = weapon_type
    active_inventory_comparison.definition_name = definition_name
    active_inventory_comparison.resolution_attempt = 0
    active_inventory_comparison.comparison_attempt = 0

    ensure_inventory_tooltip_activation(inventory_main,
        "comparison.snapshot")
    if weapon_type ~= nil then
        force_weapon_comparison_hint(inventory_main, true,
            "comparison.snapshot")
        schedule_weapon_comparison_hint_reassert(
            "comparison.snapshot")
    end
    pleasureLib:debug_log("queued stable weapon comparison snapshot"
        .. " itemPos=" .. tostring(item_pos)
        .. " weaponType=" .. tostring(weapon_type)
        .. " definition=" .. tostring(definition_name))
    return schedule_weapon_comparison_hover_settle()
end

local function on_comparison_toggled(_hook_name, context)
    local inventory_main = pleasureLib:unwrap(context)
    if not is_valid(inventory_main) then return nil end
    if active_inventory_comparison.active ~= true then return nil end
    if active_inventory_comparison.inventory_main_key
        ~= object_instance_key(inventory_main)
    then
        return nil
    end

    local enabled = bool_property(inventory_main,
        "ShouldShowWearableCompare") == true
    active_inventory_comparison.token =
        active_inventory_comparison.token + 1
    active_inventory_comparison.comparison_attempt = 0
    force_weapon_comparison_hint(inventory_main, true,
        "comparison.toggle")
    if enabled then
        -- Toggling does not restart the hover stability window. If it already
        -- elapsed, the native comparison starts on the next game-thread tick.
        schedule_weapon_comparison_settle(0)
    else
        weaponState.end_comparison("comparison.toggleOff")
    end
    pleasureLib:debug_log("weapon comparison toggle handled"
        .. " enabled=" .. tostring(enabled)
        .. " itemPos=" .. tostring(
            active_inventory_comparison.item_pos))
    return nil
end

on_slot_hovered = function(_hook_name, context)
    if config.Enabled ~= true then return nil end

    local slot = pleasureLib:unwrap(context)
    if not is_valid(slot) then return nil end
    if inventoryHelpers.slot_is_main_inventory(slot) then
        stop_active_equipped_hover("gridHover")
        begin_inventory_comparison(slot)
        return nil
    end
    if bool_property(slot, "IsWearableSlot") ~= true then return nil end

    if active_inventory_comparison.active == true then
        end_inventory_comparison("equippedHover")
    end

    local item_pos = inventoryHelpers.slot_item_pos(slot)
    if equipped_hover_matches(slot, item_pos)
        and not equipped_rehover_allowed(slot)
    then
        return nil
    end

    local inventory_main =
        discovery.refresh_inventory_main_from_slot(slot)
    local wearables_bar = discovery.wearables_bar_from(slot)

    enable_wearables_tooltips(wearables_bar)
    ensure_wearable_tooltip_links(wearables_bar, inventory_main, "hover.before")
    begin_equipped_hover(slot, inventory_main, wearables_bar, item_pos)

    broadcast_slot_hover(slot, true, item_pos)
    local tooltip = property_value(wearables_bar, "ToolTipInfoSlot")
    if not tooltip_is_valid(tooltip) then
        pleasureLib:debug_log("hover tooltip missing from ToolTipInfoSlot"
            .. " itemPos=" .. tostring(item_pos))
        end_equipped_hover(inventory_main)
        hide_equipped_tooltip_widgets(wearables_bar, inventory_main,
            "hover.noTooltip")
        return nil
    end

    pleasureLib:debug_log("using hover tooltip from ToolTipInfoSlot"
        .. " itemPos=" .. tostring(item_pos))
    schedule_equipped_tooltip_force(wearables_bar, inventory_main,
        "hover.itemPos" .. tostring(item_pos))
    return nil
end

local function on_slot_unhovered(_hook_name, context)
    if config.Enabled ~= true then return nil end

    local slot = pleasureLib:unwrap(context)
    if not is_valid(slot) then return nil end
    if inventoryHelpers.slot_is_main_inventory(slot) then
        local item_pos = inventoryHelpers.slot_item_pos(slot)
        if bool_property(slot, "Hovered") == true then
            pleasureLib:debug_log("ignored recycled inventory unhover"
                .. " slot=" .. full_name(slot)
                .. " itemPos=" .. tostring(item_pos))
            return nil
        end
        if not inventory_comparison_matches(slot, item_pos) then
            pleasureLib:debug_log("ignored stale inventory unhover"
                .. " slot=" .. full_name(slot)
                .. " itemPos=" .. tostring(item_pos))
            return nil
        end

        -- Invalidate settle/readiness work immediately. The delayed cleanup
        -- exists only to let a following hover claim a newer token.
        active_inventory_comparison.token =
            active_inventory_comparison.token + 1
        local token = active_inventory_comparison.token
        run_later(10, function()
            if active_inventory_comparison.active == true
                and active_inventory_comparison.token == token
            then
                end_inventory_comparison("comparison.end")
            end
        end)
        return nil
    end
    if bool_property(slot, "IsWearableSlot") ~= true then return nil end

    local item_pos = inventoryHelpers.slot_item_pos(slot)
    if not equipped_hover_matches(slot, item_pos) then
        pleasureLib:debug_log("ignored stale equipped unhover"
            .. " slot=" .. full_name(slot)
            .. " itemPos=" .. tostring(item_pos))
        return nil
    end

    local inventory_main =
        discovery.refresh_inventory_main_from_slot(slot)
    local wearables_bar = discovery.wearables_bar_from(slot)
    local token = active_equipped_hover.token
    run_later(10, function()
        if active_equipped_hover.active == true
            and active_equipped_hover.token == token
            and equipped_hover_matches(slot, item_pos)
            and bool_property(slot, "Hovered") ~= true
        then
            end_equipped_hover(inventory_main)
            broadcast_slot_hover(slot, false, item_pos)
            hide_equipped_tooltip_widgets(wearables_bar, inventory_main,
                "unhover.itemPos" .. tostring(item_pos))
        end
    end)
    return nil
end

configController.load()

if config.Enabled ~= true then
    pleasureLib:log("Loaded v" .. VERSION .. " disabled by config.")
elseif type(RegisterHook) ~= "function" then
    pleasureLib:log("Loaded v" .. VERSION .. " in degraded mode: RegisterHook unavailable.")
else
    configController.register_game_settings()
    local hooks_ok, hook_registrar = pcall(Hooks.new, {
        pleasure_lib = pleasureLib,
        runtime = runtime,
        generation_is_current = generation_is_current,
        config = config,
        handlers = {
            slot_hovered = on_slot_hovered,
            slot_unhovered = on_slot_unhovered,
            comparison_toggled = on_comparison_toggled,
            inventory_shown = on_inventory_shown,
            inventory_tooltip_updated =
                on_inventory_tooltip_updated,
        },
    })
    if not hooks_ok or type(hook_registrar) ~= "table" then
        pleasureLib:log("Could not initialize hook module: "
            .. tostring(hook_registrar))
        return
    end

    local notification_count, count = hook_registrar.start()
    pleasureLib:log("Loaded v" .. VERSION .. "; G1R wearable tooltip hooks registered="
        .. tostring(count)
        .. "; UI object notifications=" .. tostring(notification_count)
        .. ".")
end
