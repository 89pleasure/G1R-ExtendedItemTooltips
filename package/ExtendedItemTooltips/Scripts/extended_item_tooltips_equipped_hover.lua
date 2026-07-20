local EquippedHover = {}

local EQUIPPED_HOVER_DUPLICATE_COOLDOWN_MS = 40
local EQUIPPED_TOOLTIP_FORCE_DELAYS_MS = {
    20, 80, 160, 320,
}

function EquippedHover.new(options)
    if type(options) ~= "table" then return nil end

    local pleasure_lib = options.pleasure_lib
    local runtime = options.runtime
    local config = options.config
    local inventory_helpers = options.inventory_helpers
    local discovery = options.discovery
    local widget_helpers = options.widget_helpers
    if type(pleasure_lib) ~= "table"
        or type(runtime) ~= "table"
        or type(config) ~= "table"
        or type(inventory_helpers) ~= "table"
        or type(discovery) ~= "table"
        or type(widget_helpers) ~= "table"
        or type(runtime.is_valid) ~= "function"
        or type(runtime.full_name) ~= "function"
        or type(runtime.object_instance_key) ~= "function"
        or type(runtime.property_value) ~= "function"
        or type(runtime.bool_property) ~= "function"
        or type(runtime.tooltip_is_valid) ~= "function"
        or type(runtime.call_delegate) ~= "function"
        or type(runtime.run_later) ~= "function"
        or type(inventory_helpers.slot_item_pos) ~= "function"
        or type(discovery.refresh_inventory_main_from_slot) ~= "function"
        or type(discovery.wearables_bar_from) ~= "function"
        or type(widget_helpers.ensure_wearable_tooltip_links) ~= "function"
        or type(widget_helpers.equipped_tooltip_widgets) ~= "function"
        or type(widget_helpers.enable_wearables_tooltips) ~= "function"
        or type(widget_helpers.ensure_inventory_tooltip_activation)
            ~= "function"
        or type(widget_helpers.set_wearable_compare_flag) ~= "function"
        or type(widget_helpers.set_widget_visibility) ~= "function"
        or type(widget_helpers.visibility_collapsed) ~= "number"
        or type(widget_helpers.visibility_self_hit_test_invisible)
            ~= "number"
    then
        return nil
    end

    local is_valid = runtime.is_valid
    local full_name = runtime.full_name
    local object_instance_key = runtime.object_instance_key
    local property_value = runtime.property_value
    local bool_property = runtime.bool_property
    local tooltip_is_valid = runtime.tooltip_is_valid
    local call_delegate = runtime.call_delegate
    local run_later = runtime.run_later
    local slot_item_pos = inventory_helpers.slot_item_pos
    local refresh_inventory_main_from_slot =
        discovery.refresh_inventory_main_from_slot
    local wearables_bar_from = discovery.wearables_bar_from
    local ensure_wearable_tooltip_links =
        widget_helpers.ensure_wearable_tooltip_links
    local equipped_tooltip_widgets =
        widget_helpers.equipped_tooltip_widgets
    local enable_wearables_tooltips =
        widget_helpers.enable_wearables_tooltips
    local ensure_inventory_tooltip_activation =
        widget_helpers.ensure_inventory_tooltip_activation
    local set_wearable_compare_flag =
        widget_helpers.set_wearable_compare_flag
    local set_widget_visibility =
        widget_helpers.set_widget_visibility
    local visibility_collapsed =
        widget_helpers.visibility_collapsed
    local visibility_self_hit_test_invisible =
        widget_helpers.visibility_self_hit_test_invisible

    local last_hover_at = {}
    local active_hover = {
        active = false,
        token = 0,
        slot = nil,
        slot_key = nil,
        item_pos = nil,
        inventory_main = nil,
        wearables_bar = nil,
        should_show_wearable_compare = nil,
    }

    local function force_tooltip_widgets(
        wearables_bar, inventory_main, label, token)
        if config.ForceTooltipVisibility ~= true then return false end
        if active_hover.active ~= true then return false end
        if token ~= nil and active_hover.token ~= token then return false end

        inventory_main = pleasure_lib:unwrap(inventory_main)
        wearables_bar = pleasure_lib:unwrap(wearables_bar)
        if not is_valid(inventory_main) then
            inventory_main = active_hover.inventory_main
        end
        if not is_valid(wearables_bar) then
            wearables_bar = active_hover.wearables_bar
        end

        ensure_wearable_tooltip_links(
            wearables_bar, inventory_main, label)
        local widgets =
            equipped_tooltip_widgets(wearables_bar, inventory_main)
        if #widgets == 0 then return false end

        local forced = false
        for _, entry in ipairs(widgets) do
            forced = set_widget_visibility(
                entry.widget,
                visibility_self_hit_test_invisible,
                tostring(label) .. "." .. tostring(entry.label))
                or forced
        end
        return forced
    end

    local function schedule_tooltip_force(
        wearables_bar, inventory_main, label)
        if config.ForceTooltipVisibility ~= true then return false end
        if active_hover.active ~= true then return false end

        local token = active_hover.token
        force_tooltip_widgets(
            wearables_bar,
            inventory_main,
            tostring(label) .. ".immediate",
            token)
        local function schedule_force(delay_ms)
            run_later(delay_ms, function()
                force_tooltip_widgets(
                    wearables_bar,
                    inventory_main,
                    tostring(label) .. ".delay" .. tostring(delay_ms),
                    token)
            end)
        end
        for _, delay_ms in ipairs(EQUIPPED_TOOLTIP_FORCE_DELAYS_MS) do
            schedule_force(delay_ms)
        end
        return true
    end

    local function hide_tooltip_widgets(
        wearables_bar, inventory_main, label)
        if config.ForceTooltipVisibility ~= true then return false end

        ensure_wearable_tooltip_links(
            wearables_bar, inventory_main, label)
        local hidden = false
        for _, entry in ipairs(equipped_tooltip_widgets(
            wearables_bar, inventory_main))
        do
            hidden = set_widget_visibility(
                entry.widget,
                visibility_collapsed,
                tostring(label) .. "." .. tostring(entry.label))
                or hidden
        end
        return hidden
    end

    local function rehover_allowed(slot)
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

    local function begin_hover(
        slot, inventory_main, wearables_bar, item_pos)
        local previous_compare =
            active_hover.should_show_wearable_compare
        active_hover.active = true
        active_hover.token = active_hover.token + 1
        active_hover.slot = slot
        active_hover.slot_key = object_instance_key(slot)
        active_hover.item_pos = item_pos
        active_hover.inventory_main = inventory_main
        active_hover.wearables_bar = wearables_bar
        if previous_compare ~= nil then
            active_hover.should_show_wearable_compare =
                previous_compare
        else
            active_hover.should_show_wearable_compare =
                bool_property(
                    inventory_main,
                    "ShouldShowWearableCompare")
        end

        ensure_inventory_tooltip_activation(
            inventory_main, "hover.begin")
        set_wearable_compare_flag(
            inventory_main, true, "hover.begin")
        ensure_wearable_tooltip_links(
            wearables_bar, inventory_main, "hover.begin")
    end

    local function end_hover(inventory_main)
        active_hover.active = false
        active_hover.token = active_hover.token + 1
        active_hover.slot = nil
        active_hover.slot_key = nil
        active_hover.item_pos = nil
        active_hover.inventory_main = nil
        active_hover.wearables_bar = nil

        local previous_compare =
            active_hover.should_show_wearable_compare
        active_hover.should_show_wearable_compare = nil
        if previous_compare ~= nil then
            set_wearable_compare_flag(
                inventory_main, previous_compare, "hover.end")
        end
    end

    local function matches(slot, item_pos)
        if active_hover.active ~= true then return false end
        return active_hover.slot_key == object_instance_key(slot)
            and active_hover.item_pos == item_pos
    end

    local function broadcast_slot_hover(slot, is_hovered, item_pos)
        if not is_valid(slot) then return false end
        if item_pos == nil then return false end

        local ok, result = call_delegate(
            property_value(slot, "DispatcherOnHovered"),
            is_hovered,
            item_pos)
        pleasure_lib:debug_log("broadcasted slot hover dispatcher"
            .. " hovered=" .. tostring(is_hovered)
            .. " itemPos=" .. tostring(item_pos)
            .. " ok=" .. tostring(ok)
            .. " result=" .. tostring(result))
        return ok == true
    end

    local function stop_active(label)
        if active_hover.active ~= true then return false end

        local slot = active_hover.slot
        local item_pos = active_hover.item_pos
        local inventory_main = active_hover.inventory_main
        local wearables_bar = active_hover.wearables_bar
        end_hover(inventory_main)
        broadcast_slot_hover(slot, false, item_pos)
        hide_tooltip_widgets(
            wearables_bar,
            inventory_main,
            tostring(label) .. ".itemPos" .. tostring(item_pos))
        return true
    end

    local function is_active()
        return active_hover.active == true
    end

    local function hover(slot)
        local item_pos = slot_item_pos(slot)
        if matches(slot, item_pos)
            and not rehover_allowed(slot)
        then
            return false
        end

        local inventory_main =
            refresh_inventory_main_from_slot(slot)
        local wearables_bar = wearables_bar_from(slot)

        enable_wearables_tooltips(wearables_bar)
        ensure_wearable_tooltip_links(
            wearables_bar, inventory_main, "hover.before")
        begin_hover(
            slot, inventory_main, wearables_bar, item_pos)

        broadcast_slot_hover(slot, true, item_pos)
        local tooltip =
            property_value(wearables_bar, "ToolTipInfoSlot")
        if not tooltip_is_valid(tooltip) then
            pleasure_lib:debug_log(
                "hover tooltip missing from ToolTipInfoSlot"
                .. " itemPos=" .. tostring(item_pos))
            end_hover(inventory_main)
            hide_tooltip_widgets(
                wearables_bar,
                inventory_main,
                "hover.noTooltip")
            return false
        end

        pleasure_lib:debug_log(
            "using hover tooltip from ToolTipInfoSlot"
            .. " itemPos=" .. tostring(item_pos))
        schedule_tooltip_force(
            wearables_bar,
            inventory_main,
            "hover.itemPos" .. tostring(item_pos))
        return true
    end

    local function unhover(slot)
        local item_pos = slot_item_pos(slot)
        if not matches(slot, item_pos) then
            pleasure_lib:debug_log(
                "ignored stale equipped unhover"
                .. " slot=" .. full_name(slot)
                .. " itemPos=" .. tostring(item_pos))
            return false
        end

        local inventory_main =
            refresh_inventory_main_from_slot(slot)
        local wearables_bar = wearables_bar_from(slot)
        local token = active_hover.token
        run_later(10, function()
            if active_hover.active == true
                and active_hover.token == token
                and matches(slot, item_pos)
                and bool_property(slot, "Hovered") ~= true
            then
                end_hover(inventory_main)
                broadcast_slot_hover(slot, false, item_pos)
                hide_tooltip_widgets(
                    wearables_bar,
                    inventory_main,
                    "unhover.itemPos" .. tostring(item_pos))
            end
        end)
        return true
    end

    local function invalidate_session()
        active_hover.token = active_hover.token + 1
        last_hover_at = {}
    end

    return {
        is_active = is_active,
        stop_active = stop_active,
        hover = hover,
        unhover = unhover,
        invalidate_session = invalidate_session,
    }
end

return EquippedHover
