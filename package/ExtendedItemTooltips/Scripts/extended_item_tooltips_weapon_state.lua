local WeaponState = {}

function WeaponState.new(options)
    if type(options) ~= "table" then return nil end

    local runtime = options.runtime
    local set_widget_visibility =
        options.set_widget_visibility
    local visibility_collapsed =
        options.visibility_collapsed
    local visibility_self_hit_test_invisible =
        options.visibility_self_hit_test_invisible
    if type(runtime) ~= "table"
        or type(runtime.is_valid) ~= "function"
        or type(set_widget_visibility) ~= "function"
        or type(visibility_collapsed) ~= "number"
        or type(visibility_self_hit_test_invisible) ~= "number"
    then
        return nil
    end

    local is_valid = runtime.is_valid
    local state = {
        active = false,
        compare_widget = nil,
        source_inventory_main_key = nil,
        source_slot_key = nil,
        source_item_pos = nil,
        source_weapon_type = nil,
        source_definition_name = nil,
    }

    local function clear()
        state.active = false
        state.compare_widget = nil
        state.source_inventory_main_key = nil
        state.source_slot_key = nil
        state.source_item_pos = nil
        state.source_weapon_type = nil
        state.source_definition_name = nil
    end

    local function is_active()
        return state.active == true
    end

    local function source_matches(
        inventory_main_key,
        slot_key,
        item_pos,
        weapon_type,
        definition_name)
        if state.active ~= true then return false end
        if not is_valid(state.compare_widget) then return false end
        return state.source_inventory_main_key == inventory_main_key
            and state.source_slot_key == slot_key
            and state.source_item_pos == item_pos
            and state.source_weapon_type == weapon_type
            and state.source_definition_name == definition_name
    end

    local function activate(
        compare_widget,
        inventory_main_key,
        slot_key,
        item_pos,
        weapon_type,
        definition_name)
        state.active = true
        state.compare_widget = compare_widget
        state.source_inventory_main_key = inventory_main_key
        state.source_slot_key = slot_key
        state.source_item_pos = item_pos
        state.source_weapon_type = weapon_type
        state.source_definition_name = definition_name
    end

    local function maintain_visibility(label)
        set_widget_visibility(
            state.compare_widget,
            visibility_self_hit_test_invisible,
            tostring(label) .. ".immediate")
    end

    local function end_comparison(label)
        if state.active ~= true then return false end

        local compare_widget = state.compare_widget
        clear()
        -- The hotbar bridge is restored before a comparison becomes active.
        -- Cleanup therefore only touches the long-lived InventoryMain widget.
        set_widget_visibility(
            compare_widget,
            visibility_collapsed,
            tostring(label) .. ".weaponCompare",
            true)
        return true
    end

    return {
        is_active = is_active,
        source_matches = source_matches,
        activate = activate,
        maintain_visibility = maintain_visibility,
        end_comparison = end_comparison,
    }
end

return WeaponState
