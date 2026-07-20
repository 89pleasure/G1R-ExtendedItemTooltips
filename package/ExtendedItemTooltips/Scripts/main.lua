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

local EquippedHover = load_local_module(
    "extended_item_tooltips_equipped_hover.lua",
    "extended_item_tooltips_equipped_hover")
if type(EquippedHover) ~= "table"
    or type(EquippedHover.new) ~= "function"
then
    pleasureLib:log("Equipped hover module factory unavailable")
    return
end

local InventoryComparison = load_local_module(
    "extended_item_tooltips_inventory_comparison.lua",
    "extended_item_tooltips_inventory_comparison")
if type(InventoryComparison) ~= "table"
    or type(InventoryComparison.new) ~= "function"
then
    pleasureLib:log(
        "Inventory comparison module factory unavailable")
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

local equipped_hover_ok, equippedHover = pcall(
    EquippedHover.new,
    {
        pleasure_lib = pleasureLib,
        runtime = runtime,
        config = config,
        inventory_helpers = inventoryHelpers,
        discovery = discovery,
        widget_helpers = widgetHelpers,
    })
if not equipped_hover_ok
    or type(equippedHover) ~= "table"
    or type(equippedHover.is_active) ~= "function"
    or type(equippedHover.stop_active) ~= "function"
    or type(equippedHover.hover) ~= "function"
    or type(equippedHover.unhover) ~= "function"
    or type(equippedHover.invalidate_session) ~= "function"
then
    pleasureLib:log("Could not initialize equipped hover module: "
        .. tostring(equippedHover))
    return
end

local inventory_comparison_ok, inventoryComparison = pcall(
    InventoryComparison.new,
    {
        pleasure_lib = pleasureLib,
        runtime = runtime,
        config = config,
        weapon_comparison_hover_settle_ms =
            weapon_comparison_hover_settle_ms,
        inventory_helpers = inventoryHelpers,
        hotbar_resolver = hotbarResolver,
        widget_helpers = widgetHelpers,
        weapon_state = weaponState,
        weapon_bridge = weaponBridge,
    })
if not inventory_comparison_ok
    or type(inventoryComparison) ~= "table"
    or type(inventoryComparison.is_active) ~= "function"
    or type(inventoryComparison.hover) ~= "function"
    or type(inventoryComparison.unhover) ~= "function"
    or type(inventoryComparison.end_comparison) ~= "function"
    or type(inventoryComparison.advance_inventory_session)
        ~= "function"
    or type(inventoryComparison.reset) ~= "function"
    or type(inventoryComparison.on_toggled) ~= "function"
    or type(inventoryComparison.on_tooltip_updated) ~= "function"
then
    pleasureLib:log(
        "Could not initialize inventory comparison module: "
        .. tostring(inventoryComparison))
    return
end

local is_valid = runtime.is_valid
local bool_property = runtime.bool_property
local set_wearable_compare_flag =
    widgetHelpers.set_wearable_compare_flag

local function reset_inventory_runtime_state(label)
    inventoryComparison.advance_inventory_session()

    if equippedHover.is_active() then
        equippedHover.stop_active(
            tostring(label) .. ".equipped")
    end
    inventoryComparison.reset(label)
    equippedHover.invalidate_session()
    discovery.reset()
    hotbarResolver.invalidate_cache()
end

local function on_inventory_shown(_hook_name, context)
    local inventory_main = pleasureLib:unwrap(context)
    if not is_valid(inventory_main) then return nil end

    reset_inventory_runtime_state("inventory.shown")
    hotbarResolver.begin_inventory_session()
    discovery.begin_inventory_session(inventory_main)
    set_wearable_compare_flag(
        inventory_main,
        config.EnableComparisonTooltips == true
            and config.ComparisonDefaultEnabled == true,
        "inventory.shown.default")
    return nil
end

local function on_slot_hovered(_hook_name, context)
    if config.Enabled ~= true then return nil end

    local slot = pleasureLib:unwrap(context)
    if not is_valid(slot) then return nil end
    if inventoryHelpers.slot_is_main_inventory(slot) then
        equippedHover.stop_active("gridHover")
        inventoryComparison.hover(slot)
        return nil
    end
    if bool_property(slot, "IsWearableSlot") ~= true then
        return nil
    end

    if inventoryComparison.is_active() then
        inventoryComparison.end_comparison("equippedHover")
    end
    equippedHover.hover(slot)
    return nil
end

local function on_slot_unhovered(_hook_name, context)
    if config.Enabled ~= true then return nil end

    local slot = pleasureLib:unwrap(context)
    if not is_valid(slot) then return nil end
    if inventoryHelpers.slot_is_main_inventory(slot) then
        inventoryComparison.unhover(slot)
        return nil
    end
    if bool_property(slot, "IsWearableSlot") ~= true then
        return nil
    end

    equippedHover.unhover(slot)
    return nil
end

configController.load()

if config.Enabled ~= true then
    pleasureLib:log("Loaded v" .. VERSION .. " disabled by config.")
elseif type(RegisterHook) ~= "function" then
    pleasureLib:log(
        "Loaded v" .. VERSION
        .. " in degraded mode: RegisterHook unavailable.")
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
            comparison_toggled =
                inventoryComparison.on_toggled,
            inventory_shown = on_inventory_shown,
            inventory_tooltip_updated =
                inventoryComparison.on_tooltip_updated,
        },
    })
    if not hooks_ok or type(hook_registrar) ~= "table" then
        pleasureLib:log("Could not initialize hook module: "
            .. tostring(hook_registrar))
        return
    end

    local notification_count, count = hook_registrar.start()
    pleasureLib:log(
        "Loaded v" .. VERSION
        .. "; G1R wearable tooltip hooks registered="
        .. tostring(count)
        .. "; UI object notifications="
        .. tostring(notification_count)
        .. ".")
end
