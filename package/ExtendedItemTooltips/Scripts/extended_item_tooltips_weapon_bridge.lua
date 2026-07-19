local WeaponBridge = {}

function WeaponBridge.new(options)
    if type(options) ~= "table" then return nil end

    local pleasure_lib = options.pleasure_lib
    local runtime = options.runtime
    local set_widget_reference =
        options.set_widget_reference
    if type(pleasure_lib) ~= "table"
        or type(runtime) ~= "table"
        or type(set_widget_reference) ~= "function"
    then
        return nil
    end

    local is_valid = runtime.is_valid
    local property_value = runtime.property_value
    local set_property_value = runtime.set_property_value
    local bool_property = runtime.bool_property

    local busy = false

    local function is_busy()
        return busy
    end

    local function copy_inventory_tooltip_info(
        inventory_main, hotbar)
        local tooltip_info =
            property_value(inventory_main, "TooltipInfo")
        if tooltip_info == nil then return false end

        local ok, result = set_property_value(
            hotbar,
            "ToolTipInfoBase",
            tooltip_info)
        pleasure_lib:debug_log(
            "copied inventory tooltip info to hotbar"
            .. " ok=" .. tostring(ok)
            .. " result=" .. tostring(result))
        return ok == true
    end

    local function call_hotbar_slot_tooltip(
        hotbar, weapon_position, show)
        local fn = pleasure_lib:try(function()
            return hotbar["UpdateToolTipOnSlot"]
        end)
        if fn == nil then return false end
        local ok, result = pcall(function()
            return fn(hotbar, weapon_position, show == true)
        end)
        pleasure_lib:debug_log(
            "updated hotbar weapon comparison"
            .. " weaponPosition=" .. tostring(weapon_position)
            .. " show=" .. tostring(show)
            .. " ok=" .. tostring(ok)
            .. " result=" .. tostring(result))
        return ok
    end

    local function restore_widget_reference(
        owner, property_name, previous, label)
        if is_valid(previous) then
            if set_widget_reference(
                owner,
                property_name,
                previous,
                label)
            then
                return true
            end

            -- If exact restoration fails, at least remove the borrowed
            -- InventoryMain reference before leaving the bridge.
            local cleared =
                set_property_value(owner, property_name, nil)
            local safely_cleared = cleared == true
                and not is_valid(
                    property_value(owner, property_name))
            pleasure_lib:debug_log(
                "failed to restore hotbar widget;"
                .. " cleared temporary reference"
                .. " label=" .. tostring(label)
                .. " property=" .. tostring(property_name)
                .. " cleared=" .. tostring(safely_cleared))
            return false
        end

        local ok, result =
            set_property_value(owner, property_name, nil)
        pleasure_lib:debug_log(
            "cleared temporary hotbar widget reference"
            .. " label=" .. tostring(label)
            .. " property=" .. tostring(property_name)
            .. " ok=" .. tostring(ok)
            .. " result=" .. tostring(result))
        return ok == true
            and not is_valid(
                property_value(owner, property_name))
    end

    local function run(
        hotbar,
        inventory_main,
        base_widget,
        compare_widget,
        weapon_position)
        if busy then
            return false, "bridge busy"
        end

        local previous_show_tooltips =
            bool_property(hotbar, "ShowToolTips")
        local previous_base_widget = property_value(
            hotbar,
            "W_Inventory_ItemTooltip_ItemToAssign")
        local previous_slot_widget = property_value(
            hotbar,
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo")
        if previous_show_tooltips == nil then
            return false, "hotbar state snapshot unavailable"
        end

        busy = true
        local call_ok, route_ok = pcall(function()
            local show_set =
                set_property_value(hotbar, "ShowToolTips", true)
            if show_set ~= true
                or bool_property(hotbar, "ShowToolTips") ~= true
            then
                return false
            end

            local linked_base = set_widget_reference(
                hotbar,
                "W_Inventory_ItemTooltip_ItemToAssign",
                base_widget,
                "weaponComparison.transaction.base")
            if not linked_base then return false end

            local linked_slot = set_widget_reference(
                hotbar,
                "W_Inventory_ItemTooltip_ItemInSlotToAssignTo",
                compare_widget,
                "weaponComparison.transaction.slot")
            if not linked_slot then return false end

            if not copy_inventory_tooltip_info(
                inventory_main,
                hotbar)
            then
                return false
            end
            return call_hotbar_slot_tooltip(
                hotbar,
                weapon_position,
                true) == true
        end)

        -- Restore borrowed UObject references and the control flag
        -- immediately. ToolTipInfoBase/Slot are value scratch state owned
        -- by the hidden hotbar; UE4SS exposes them as live mapped structs,
        -- not copy snapshots. No InventoryMain widget reference may
        -- survive this native call.
        local slot_restored = restore_widget_reference(
            hotbar,
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo",
            previous_slot_widget,
            "weaponComparison.transaction.restoreSlot")
        local base_restored = restore_widget_reference(
            hotbar,
            "W_Inventory_ItemTooltip_ItemToAssign",
            previous_base_widget,
            "weaponComparison.transaction.restoreBase")
        local show_restored = set_property_value(
            hotbar,
            "ShowToolTips",
            previous_show_tooltips) == true
            and bool_property(hotbar, "ShowToolTips")
                == previous_show_tooltips
        busy = false

        local restored =
            slot_restored and base_restored and show_restored
        local succeeded =
            call_ok and route_ok == true and restored
        pleasure_lib:debug_log(
            "completed scoped hotbar comparison"
            .. " callOk=" .. tostring(call_ok)
            .. " routeOk=" .. tostring(route_ok)
            .. " restored=" .. tostring(restored))
        if succeeded then return true, nil end
        return false,
            call_ok and "native route or restore failed"
                or tostring(route_ok)
    end

    return {
        is_busy = is_busy,
        run = run,
    }
end

return WeaponBridge
