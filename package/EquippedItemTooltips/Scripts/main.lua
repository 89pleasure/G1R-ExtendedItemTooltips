local MOD = "EquippedItemTooltips"
local CONFIG_FILE_NAME = "EquippedItemTooltips.ini"
local VERSION = "0.6.3"

local DEFAULT_CONFIG = {
    Enabled = true,
    Debug = false,
    TooltipCooldownMs = 40,
    ForceTooltipVisibility = true,
}

local SLOT_HOVER_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Slot.W_Inventory_Slot_C:OnHovered",
}

local SLOT_UNHOVER_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Slot.W_Inventory_Slot_C:OnUnhovered",
}

local INVENTORY_MAIN_PATH_NEEDLES = {
    "W_Inventory_Main",
    "InventoryMain",
}

local config = {}
local registered_hooks = {}
local pending_hooks = {}
local hook_retry_logged = {}
local cached_inventory_main = nil
local cached_wearables_bar = nil
local last_hover_at = {}
local active_equipped_hover = {
    active = false,
    token = 0,
    item_pos = nil,
    inventory_main = nil,
    wearables_bar = nil,
    should_show_wearable_compare = nil,
}

local refresh_inventory_main_from_slot = nil

local function log(message)
    print("[" .. MOD .. "] " .. tostring(message) .. "\n")
end

local function debug_log(message)
    if config.Debug == true then
        log("[debug] " .. tostring(message))
    end
end

local function try(fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
    return string.lower(trim(value))
end

local function parse_bool(value, default)
    local text = lower(value)
    if text == "" then return default end
    if text == "true" or text == "1" or text == "yes" or text == "on" then return true end
    if text == "false" or text == "0" or text == "no" or text == "off" then return false end
    return default
end

local function split_list(value)
    local result = {}
    for part in string.gmatch(tostring(value or ""), "([^;]+)") do
        local text = trim(part)
        if text ~= "" then
            table.insert(result, text)
        end
    end
    return result
end

local function merge_list(defaults, override)
    local parsed = split_list(override)
    if #parsed > 0 then return parsed end

    local result = {}
    for _, value in ipairs(defaults) do
        table.insert(result, value)
    end
    return result
end

local function script_directory()
    local info = try(function()
        if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then
            return nil
        end
        return debug.getinfo(1, "S")
    end)
    if not info or not info.source then return nil end

    local source = tostring(info.source)
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return source:match("^(.*[\\/])[^\\/]*$")
end

local function read_text_file(path)
    local file = try(function()
        if type(io) ~= "table" or type(io.open) ~= "function" then return nil end
        return io.open(path, "r")
    end)
    if not file then return nil end

    local content = file:read("*a")
    file:close()
    return content
end

local function config_candidate_paths()
    local paths = {}
    local dir = script_directory()
    if dir then
        table.insert(paths, dir .. "..\\" .. CONFIG_FILE_NAME)
        table.insert(paths, dir .. CONFIG_FILE_NAME)
    end
    table.insert(paths, "Mods\\EquippedItemTooltips\\" .. CONFIG_FILE_NAME)
    table.insert(paths, "ue4ss\\Mods\\EquippedItemTooltips\\" .. CONFIG_FILE_NAME)
    table.insert(paths, CONFIG_FILE_NAME)
    return paths
end

local function parse_ini(content)
    local result = {}
    for line in string.gmatch(tostring(content or ""), "[^\r\n]+") do
        local stripped = trim(line)
        if stripped ~= "" and stripped:sub(1, 1) ~= ";"
            and stripped:sub(1, 1) ~= "#"
            and stripped:sub(1, 1) ~= "["
        then
            local key, value = stripped:match("^([%w_%.%-]+)%s*=%s*(.-)%s*$")
            if key and value then
                result[string.upper(trim(key))] = trim(value)
            end
        end
    end
    return result
end

local function load_config()
    config = {
        Enabled = DEFAULT_CONFIG.Enabled,
        Debug = DEFAULT_CONFIG.Debug,
        TooltipCooldownMs = DEFAULT_CONFIG.TooltipCooldownMs,
        ForceTooltipVisibility = DEFAULT_CONFIG.ForceTooltipVisibility,
        SlotHoverHooks = SLOT_HOVER_HOOKS,
        SlotUnhoverHooks = SLOT_UNHOVER_HOOKS,
    }

    for _, path in ipairs(config_candidate_paths()) do
        local content = read_text_file(path)
        if content ~= nil then
            local ini = parse_ini(content)
            config.Enabled = parse_bool(ini.ENABLED, config.Enabled)
            config.Debug = parse_bool(ini.DEBUG, config.Debug)
            config.ForceTooltipVisibility = parse_bool(
                ini.FORCETOOLTIPVISIBILITY, config.ForceTooltipVisibility)
            config.TooltipCooldownMs =
                tonumber(ini.TOOLTIPCOOLDOWNMS) or config.TooltipCooldownMs
            config.SlotHoverHooks = merge_list(
                SLOT_HOVER_HOOKS, ini.SLOTHOVERHOOKS)
            config.SlotUnhoverHooks = merge_list(
                SLOT_UNHOVER_HOOKS, ini.SLOTUNHOVERHOOKS)

            log("Loaded config from " .. tostring(path)
                .. ": Enabled=" .. tostring(config.Enabled)
                .. " Debug=" .. tostring(config.Debug)
                .. " ForceTooltipVisibility=" .. tostring(config.ForceTooltipVisibility)
                .. " TooltipCooldownMs=" .. tostring(config.TooltipCooldownMs))
            return
        end
    end

    log("Config not found; using defaults.")
end

local function unwrap(param)
    if param == nil then return nil end
    local kind = type(param)
    if kind == "number" or kind == "string" or kind == "boolean" then return param end
    if kind == "userdata" or kind == "table" then
        local value = try(function()
            if type(param.get) == "function" then return param:get() end
            if type(param.Get) == "function" then return param:Get() end
            return param
        end)
        if value ~= nil then return value end
    end
    return param
end

local function is_valid(obj)
    if obj == nil then return false end
    if type(obj) ~= "userdata" and type(obj) ~= "table" then return false end

    local valid = try(function()
        if type(obj.IsValid) ~= "function" then return false end
        return obj:IsValid()
    end)
    if valid == true then return true end

    return try(function()
        if type(obj.GetFullName) ~= "function" then return false end
        return obj:GetFullName() ~= nil
    end) == true
end

local function full_name(obj)
    if not is_valid(obj) then return "" end
    return try(function() return obj:GetFullName() end) or ""
end

local function object_class_token(obj)
    local text = full_name(obj)
    return text:match("^([^%s]+)") or ""
end

local function object_short_name(obj)
    local name = try(function()
        if type(obj.GetName) == "function" then return obj:GetName() end
        return nil
    end)
    if name ~= nil then return tostring(name) end

    local text = full_name(obj)
    local path = text:match("%s(.+)$") or text
    return path:match("([^%.:]+)$") or ""
end

local function contains(haystack, needle)
    return string.find(lower(haystack), lower(needle), 1, true) ~= nil
end

local function object_named_like(object, needle)
    local text = object_class_token(object) .. " " .. object_short_name(object)
    return contains(text, needle)
end

local function object_is_inventory_main(object)
    for _, needle in ipairs(INVENTORY_MAIN_PATH_NEEDLES) do
        if object_named_like(object, needle) then return true end
    end
    return false
end

local function property_value(object, property_name)
    if not is_valid(object) then return nil end
    local value = try(function()
        if type(object.GetPropertyValue) == "function" then
            return object:GetPropertyValue(property_name)
        end
        return nil
    end)
    if value ~= nil then return unwrap(value) end

    value = try(function() return object[property_name] end)
    return unwrap(value)
end

local function set_property_value(object, property_name, value)
    if not is_valid(object) then return false, "object invalid" end

    local direct_ok = pcall(function()
        object[property_name] = value
    end)
    if direct_ok then return true, "direct" end

    local setter_ok, setter_result = pcall(function()
        if type(object.SetPropertyValue) == "function" then
            return object:SetPropertyValue(property_name, value)
        end
        return nil
    end)
    if setter_ok then return true, setter_result or "SetPropertyValue" end

    return false, setter_result
end

local function number_property(object, property_name)
    local value = unwrap(property_value(object, property_name))
    local number = tonumber(value)
    if number ~= nil then return number end
    return nil
end

local function bool_property(object, property_name)
    local value = unwrap(property_value(object, property_name))
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end

    local text = lower(value)
    if text == "true" or text == "1" then return true end
    if text == "false" or text == "0" then return false end
    return nil
end

local function widget_visibility_value(widget)
    local value = unwrap(property_value(widget, "Visibility"))
    if value == nil then return "nil" end
    return tostring(value)
end

local function find_uobject(path)
    if type(StaticFindObject) ~= "function" then return nil end

    local object = try(function()
        return StaticFindObject(nil, nil, path, false)
    end)
    if is_valid(object) then return object end

    return try(function() return StaticFindObject(path) end)
end

local function ufunction_loaded(path)
    return is_valid(find_uobject(path))
end

local function related_object_with_name(start_object, needle)
    local current = unwrap(start_object)
    local depth = 0
    while is_valid(current) and depth < 14 do
        if object_named_like(current, needle) then return current end

        local next_object = try(function()
            if type(current.GetOuter) == "function" then return current:GetOuter() end
            return nil
        end)
        if not is_valid(next_object) and type(current.GetParent) == "function" then
            next_object = try(function() return current:GetParent() end)
        end
        current = unwrap(next_object)
        depth = depth + 1
    end
    return nil
end

local function tooltip_is_valid(info)
    if info == nil then return false end
    local valid = unwrap(property_value(info, "IsValid"))
    if valid == true or valid == 1 then return true end
    if valid == false or valid == 0 then return false end
    return true
end

local function call_delegate(delegate, ...)
    delegate = unwrap(delegate)
    if delegate == nil then return false, "delegate missing" end

    local method_names = { "Broadcast", "Execute", "Call" }
    local args = { ... }
    args.n = select("#", ...)
    local unpack_args = table.unpack or unpack
    if not unpack_args then return false, "unpack unavailable" end

    for _, name in ipairs(method_names) do
        local method = try(function() return delegate[name] end)
        if type(method) == "function" then
            local ok, result = pcall(function()
                return method(delegate, unpack_args(args, 1, args.n))
            end)
            if ok then return true, name end
            return false, result
        end
    end

    if type(delegate) == "function" then
        local ok, result = pcall(function()
            return delegate(unpack_args(args, 1, args.n))
        end)
        if ok then return true, "call" end
        return false, result
    end

    return false, "delegate method missing"
end

local function run_later(ms, fn)
    if type(fn) ~= "function" then return false end
    if type(ExecuteWithDelay) == "function" then
        ExecuteWithDelay(ms, function()
            if type(ExecuteInGameThread) == "function" then
                ExecuteInGameThread(fn)
            else
                fn()
            end
        end)
        return true
    end
    return false
end

local function inventory_wearable_tooltip_widget(inventory_main)
    if not is_valid(inventory_main) then return nil end

    local widget = property_value(inventory_main,
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable")
    if is_valid(widget) then return widget end

    widget = property_value(inventory_main,
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Compare")
    if is_valid(widget) then return widget end

    return property_value(inventory_main, "W_Inventory_ItemTooltip_ItemToAssign")
end

local function inventory_new_item_tooltip_widget(inventory_main)
    if not is_valid(inventory_main) then return nil end
    return property_value(inventory_main, "W_Inventory_ItemTooltip_ItemToAssign")
end

local function set_widget_reference(owner, property_name, target, label)
    if not is_valid(owner) or not is_valid(target) then return false end

    local current = property_value(owner, property_name)
    if is_valid(current) and full_name(current) == full_name(target) then
        return true
    end

    local ok, result = set_property_value(owner, property_name, target)
    local after = property_value(owner, property_name)
    local linked = is_valid(after) and full_name(after) == full_name(target)
    if not linked and type(owner.SetPropertyValue) == "function" then
        local setter_ok, setter_result = pcall(function()
            return owner:SetPropertyValue(property_name, target)
        end)
        ok = setter_ok
        result = setter_result
        after = property_value(owner, property_name)
        linked = is_valid(after) and full_name(after) == full_name(target)
    end

    if linked then
        debug_log("linked wearable tooltip widget"
            .. " label=" .. tostring(label)
            .. " property=" .. tostring(property_name)
            .. " result=" .. tostring(result))
        return true
    end

    if config.Debug == true then
        log("[debug] failed to link wearable tooltip widget"
            .. " label=" .. tostring(label)
            .. " property=" .. tostring(property_name)
            .. " ok=" .. tostring(ok)
            .. " result=" .. tostring(result))
    end
    return false
end

local function ensure_wearable_tooltip_links(wearables_bar, inventory_main, label)
    if not is_valid(wearables_bar) or not is_valid(inventory_main) then return false end

    local linked = false
    linked = set_widget_reference(wearables_bar, "m_ToolTipEquippedItem",
        inventory_wearable_tooltip_widget(inventory_main), label) or linked
    linked = set_widget_reference(wearables_bar, "m_ToolTipNewItem",
        inventory_new_item_tooltip_widget(inventory_main), label) or linked
    return linked
end

local function add_unique_widget_entry(entries, seen, label, widget)
    widget = unwrap(widget)
    if not is_valid(widget) then return false end

    local key = full_name(widget)
    if key == "" then key = tostring(widget) end
    if seen[key] == true then return false end

    seen[key] = true
    table.insert(entries, { label = label, widget = widget })
    return true
end

local function equipped_tooltip_widgets(wearables_bar, inventory_main)
    local entries = {}
    local seen = {}

    if is_valid(wearables_bar) then
        add_unique_widget_entry(entries, seen, "Wearables.m_ToolTipEquippedItem",
            property_value(wearables_bar, "m_ToolTipEquippedItem"))
    end
    add_unique_widget_entry(entries, seen,
        "InventoryMain.W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable",
        property_value(inventory_main,
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable"))

    if #entries == 0 then
        if is_valid(wearables_bar) then
            add_unique_widget_entry(entries, seen, "Wearables.m_ToolTipNewItem",
                property_value(wearables_bar, "m_ToolTipNewItem"))
        end
        add_unique_widget_entry(entries, seen,
            "InventoryMain.W_Inventory_ItemTooltip_ItemToAssign",
            property_value(inventory_main, "W_Inventory_ItemTooltip_ItemToAssign"))
    end

    return entries
end

local function wearables_bar_from(slot_or_inventory)
    local direct = unwrap(property_value(slot_or_inventory, "EquippedWearables"))
    if is_valid(direct) then
        cached_wearables_bar = direct
        return direct
    end

    local related = related_object_with_name(slot_or_inventory, "W_EquippedWearables")
    if is_valid(related) then
        cached_wearables_bar = related
        return related
    end

    local inventory_main = refresh_inventory_main_from_slot(slot_or_inventory)
    direct = unwrap(property_value(inventory_main, "EquippedWearables"))
    if is_valid(direct) then
        cached_wearables_bar = direct
        return direct
    end

    if is_valid(cached_wearables_bar) then return cached_wearables_bar end
    return nil
end

local function enable_wearables_tooltips(wearables_bar)
    if not is_valid(wearables_bar) then return false end

    if bool_property(wearables_bar, "ShowToolTips") == true then return true end
    local ok = set_property_value(wearables_bar, "ShowToolTips", true)
    debug_log("enabled W_EquippedWearables.ShowToolTips"
        .. " ok=" .. tostring(ok))
    return ok == true
end

local function ensure_inventory_tooltip_activation(inventory_main, label)
    if config.ForceTooltipVisibility ~= true then return false end
    if not is_valid(inventory_main) then return false end

    if bool_property(inventory_main, "ActivateTooltip") == true then return true end
    local ok = set_property_value(inventory_main, "ActivateTooltip", true)
    debug_log("enabled InventoryMain.ActivateTooltip"
        .. " label=" .. tostring(label)
        .. " ok=" .. tostring(ok))
    return ok == true
end

local function set_wearable_compare_flag(inventory_main, value, label)
    if config.ForceTooltipVisibility ~= true then return false end
    if not is_valid(inventory_main) then return false end

    if bool_property(inventory_main, "ShouldShowWearableCompare") == value then
        return true
    end

    local ok = set_property_value(inventory_main,
        "ShouldShowWearableCompare", value == true)
    debug_log("set InventoryMain.ShouldShowWearableCompare"
        .. " label=" .. tostring(label)
        .. " value=" .. tostring(value)
        .. " ok=" .. tostring(ok))
    return ok == true
end

local function set_widget_visibility(widget, visibility, label)
    if config.ForceTooltipVisibility ~= true then return false end
    if not is_valid(widget) then return false end

    local wanted = tostring(visibility)
    local before = widget_visibility_value(widget)
    local property_ok, property_result = pcall(function()
        if type(widget.SetPropertyValue) == "function" then
            return widget:SetPropertyValue("Visibility", visibility)
        end
        widget.Visibility = visibility
        return "direct-property"
    end)
    local after = widget_visibility_value(widget)
    if property_ok and tostring(after) == wanted then
        debug_log("set tooltip widget visibility"
            .. " label=" .. tostring(label)
            .. " mode=property"
            .. " before=" .. tostring(before)
            .. " after=" .. tostring(after)
            .. " result=" .. tostring(property_result))
        return true
    end

    debug_log("failed to set tooltip widget visibility"
        .. " label=" .. tostring(label)
        .. " propertyOk=" .. tostring(property_ok)
        .. " propertyResult=" .. tostring(property_result)
        .. " before=" .. tostring(before)
        .. " after=" .. tostring(after))
    return false
end

local function force_equipped_tooltip_widgets(wearables_bar, inventory_main, label, token)
    if config.ForceTooltipVisibility ~= true then return false end
    if active_equipped_hover.active ~= true then return false end
    if token ~= nil and active_equipped_hover.token ~= token then return false end

    inventory_main = unwrap(inventory_main)
    wearables_bar = unwrap(wearables_bar)
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
        forced = set_widget_visibility(entry.widget, 4,
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
    run_later(20, function()
        force_equipped_tooltip_widgets(wearables_bar, inventory_main,
            tostring(label) .. ".delay20", token)
    end)
    run_later(80, function()
        force_equipped_tooltip_widgets(wearables_bar, inventory_main,
            tostring(label) .. ".delay80", token)
    end)
    run_later(160, function()
        force_equipped_tooltip_widgets(wearables_bar, inventory_main,
            tostring(label) .. ".delay160", token)
    end)
    run_later(320, function()
        force_equipped_tooltip_widgets(wearables_bar, inventory_main,
            tostring(label) .. ".delay320", token)
    end)
    return true
end

local function hide_equipped_tooltip_widgets(wearables_bar, inventory_main, label)
    if config.ForceTooltipVisibility ~= true then return false end

    ensure_wearable_tooltip_links(wearables_bar, inventory_main, label)
    local hidden = false
    for _, entry in ipairs(equipped_tooltip_widgets(wearables_bar, inventory_main)) do
        hidden = set_widget_visibility(entry.widget, 1,
            tostring(label) .. "." .. tostring(entry.label)) or hidden
    end
    return hidden
end

local function slot_item_pos(slot)
    local item_pos = number_property(slot, "ItemPos")
    if item_pos == nil then
        item_pos = number_property(property_value(slot, "Inventory Slot Data"), "m_Pos")
    end
    return item_pos
end

refresh_inventory_main_from_slot = function(slot)
    local related = related_object_with_name(slot, "W_Inventory_Main")
    if is_valid(related) then
        cached_inventory_main = related
        return related
    end

    local parent = try(function()
        if type(slot.GetParent) == "function" then return slot:GetParent() end
        return nil
    end)
    local depth = 0
    while is_valid(parent) and depth < 10 do
        if object_is_inventory_main(parent) then
            cached_inventory_main = parent
            return parent
        end
        local current = parent
        parent = try(function()
            if type(current.GetParent) == "function" then return current:GetParent() end
            return nil
        end)
        depth = depth + 1
    end

    return cached_inventory_main
end

local function hover_allowed(slot)
    local key = full_name(slot)
    if key == "" then return true end

    local now = math.floor(os.clock() * 1000)
    local previous = last_hover_at[key] or -1000000
    if now - previous < math.max(0, tonumber(config.TooltipCooldownMs) or 0) then
        return false
    end
    last_hover_at[key] = now
    return true
end

local function begin_equipped_hover(inventory_main, wearables_bar, item_pos)
    active_equipped_hover.active = true
    active_equipped_hover.token = active_equipped_hover.token + 1
    active_equipped_hover.item_pos = item_pos
    active_equipped_hover.inventory_main = inventory_main
    active_equipped_hover.wearables_bar = wearables_bar
    active_equipped_hover.should_show_wearable_compare =
        bool_property(inventory_main, "ShouldShowWearableCompare")

    ensure_inventory_tooltip_activation(inventory_main, "hover.begin")
    set_wearable_compare_flag(inventory_main, true, "hover.begin")
    ensure_wearable_tooltip_links(wearables_bar, inventory_main, "hover.begin")
end

local function end_equipped_hover(inventory_main)
    active_equipped_hover.active = false
    active_equipped_hover.token = active_equipped_hover.token + 1
    active_equipped_hover.item_pos = nil
    active_equipped_hover.inventory_main = nil
    active_equipped_hover.wearables_bar = nil

    local previous_compare = active_equipped_hover.should_show_wearable_compare
    active_equipped_hover.should_show_wearable_compare = nil
    if previous_compare ~= nil then
        set_wearable_compare_flag(inventory_main, previous_compare, "hover.end")
    end
end

local function broadcast_slot_hover(slot, is_hovered, item_pos)
    if not is_valid(slot) then return false end
    if item_pos == nil then return false end

    local ok, result = call_delegate(property_value(slot, "DispatcherOnHovered"),
        is_hovered, item_pos)
    debug_log("broadcasted slot hover dispatcher"
        .. " hovered=" .. tostring(is_hovered)
        .. " itemPos=" .. tostring(item_pos)
        .. " ok=" .. tostring(ok)
        .. " result=" .. tostring(result))
    return ok == true
end

local function on_slot_hovered(_hook_name, context)
    if config.Enabled ~= true then return nil end

    local slot = unwrap(context)
    if not is_valid(slot) then return nil end
    if bool_property(slot, "IsWearableSlot") ~= true then return nil end
    if not hover_allowed(slot) then return nil end

    local inventory_main = refresh_inventory_main_from_slot(slot)
    local wearables_bar = wearables_bar_from(slot)
    local item_pos = slot_item_pos(slot)

    enable_wearables_tooltips(wearables_bar)
    ensure_wearable_tooltip_links(wearables_bar, inventory_main, "hover.before")
    begin_equipped_hover(inventory_main, wearables_bar, item_pos)

    broadcast_slot_hover(slot, true, item_pos)
    local tooltip = property_value(wearables_bar, "ToolTipInfoSlot")
    if not tooltip_is_valid(tooltip) then
        debug_log("hover tooltip missing from ToolTipInfoSlot"
            .. " itemPos=" .. tostring(item_pos))
        end_equipped_hover(inventory_main)
        hide_equipped_tooltip_widgets(wearables_bar, inventory_main,
            "hover.noTooltip")
        return nil
    end

    debug_log("using hover tooltip from ToolTipInfoSlot"
        .. " itemPos=" .. tostring(item_pos))
    schedule_equipped_tooltip_force(wearables_bar, inventory_main,
        "hover.itemPos" .. tostring(item_pos))
    return nil
end

local function on_slot_unhovered(_hook_name, context)
    if config.Enabled ~= true then return nil end

    local slot = unwrap(context)
    if not is_valid(slot) then return nil end
    if bool_property(slot, "IsWearableSlot") ~= true then return nil end

    local item_pos = slot_item_pos(slot)
    local inventory_main = refresh_inventory_main_from_slot(slot)
    local wearables_bar = wearables_bar_from(slot)

    end_equipped_hover(inventory_main)
    broadcast_slot_hover(slot, false, item_pos)
    hide_equipped_tooltip_widgets(wearables_bar, inventory_main,
        "unhover.itemPos" .. tostring(item_pos))
    return nil
end

local function register_hook(path, handler, retry_if_missing)
    if type(RegisterHook) ~= "function" then
        log("RegisterHook unavailable")
        return false
    end
    if registered_hooks[path] == true then return false end

    if not ufunction_loaded(path) then
        if retry_if_missing == true then pending_hooks[path] = handler end
        if hook_retry_logged[path] ~= "not-loaded" then
            hook_retry_logged[path] = "not-loaded"
            debug_log("Hook target not loaded yet; will retry " .. path)
        end
        return false
    end

    local ok = pcall(function()
        RegisterHook(path, function(context, ...)
            return handler(path, context, ...)
        end)
    end)
    if not ok then
        pending_hooks[path] = handler
        if hook_retry_logged[path] ~= "not-hookable" then
            hook_retry_logged[path] = "not-hookable"
            debug_log("Hook target loaded but not hookable yet; will retry " .. path)
        end
        return false
    end

    registered_hooks[path] = true
    pending_hooks[path] = nil
    hook_retry_logged[path] = nil
    return true
end

local function retry_pending_hooks()
    local any_pending = false
    for path, handler in pairs(pending_hooks) do
        any_pending = true
        register_hook(path, handler, true)
    end

    if any_pending and type(ExecuteWithDelay) == "function" then
        ExecuteWithDelay(2000, retry_pending_hooks)
    end
end

local function register_hooks()
    local count = 0
    for _, path in ipairs(config.SlotHoverHooks or {}) do
        if register_hook(path, on_slot_hovered, true) then
            count = count + 1
        end
    end
    for _, path in ipairs(config.SlotUnhoverHooks or {}) do
        if register_hook(path, on_slot_unhovered, true) then
            count = count + 1
        end
    end
    retry_pending_hooks()
    return count
end

load_config()

if config.Enabled ~= true then
    log("Loaded v" .. VERSION .. " disabled by config.")
elseif type(RegisterHook) ~= "function" then
    log("Loaded v" .. VERSION .. " in degraded mode: RegisterHook unavailable.")
else
    local count = register_hooks()
    log("Loaded v" .. VERSION .. "; G1R wearable tooltip hooks registered="
        .. tostring(count) .. ".")
end
