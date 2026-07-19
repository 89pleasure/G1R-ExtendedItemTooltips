local Inventory = {}

local INVENTORY_TYPE_MAIN_CONTAINER = 1
local INVENTORY_TYPE_MELEE_SLOT = 3
local INVENTORY_TYPE_RANGED_SLOT = 4

function Inventory.new(options)
    if type(options) ~= "table" then return nil end

    local pleasure_lib = options.pleasure_lib
    local runtime = options.runtime
    if type(pleasure_lib) ~= "table"
        or type(runtime) ~= "table"
    then
        return nil
    end

    local is_valid = runtime.is_valid
    local full_name = runtime.full_name
    local property_value = runtime.property_value
    local number_property = runtime.number_property
    local bool_property = runtime.bool_property
    local array_length = runtime.array_length

    local function slot_item_pos(slot)
        local item_pos = number_property(slot, "ItemPos")
        if item_pos == nil then
            item_pos = number_property(
                property_value(slot, "Inventory Slot Data"),
                "m_Pos")
        end
        return item_pos
    end

    local function slot_inventory_type(slot)
        return number_property(
            property_value(slot, "Inventory Slot Data"),
            "m_InventoryType")
    end

    local function slot_is_main_inventory(slot)
        return slot_inventory_type(slot)
            == INVENTORY_TYPE_MAIN_CONTAINER
    end

    local function slot_has_hotbar_assignment(slot)
        -- W_Inventory_Slot sets this native flag for the numbered badge
        -- shown on items assigned to the hotbar. Those items are already
        -- the equipped comparison source and must not start a comparison
        -- with themselves.
        return bool_property(slot, "ShowingHotkey") == true
    end

    local function first_hotbar_weapon_position(
        hotbar, inventory_type)
        local slots = property_value(hotbar, "m_SlotsData")
        local slot_count = array_length(slots)
        if slot_count == nil or slot_count <= 0 then
            return nil, nil, false
        end

        local inventory_base =
            property_value(hotbar, "m_InventoryBase")
        if not is_valid(inventory_base) then
            return nil, nil, false
        end
        local valid_fn = pleasure_lib:try(function()
            return inventory_base["IsItemValidByPos"]
        end)
        local definition_fn = pleasure_lib:try(function()
            return inventory_base["GetBaseConfigByPos"]
        end)
        if valid_fn == nil or definition_fn == nil then
            return nil, nil, false
        end

        local scan_complete = true
        for position = 0, slot_count - 1 do
            local valid_ok, item_valid = pcall(function()
                return valid_fn(inventory_base, position)
            end)
            if not valid_ok then scan_complete = false end
            if valid_ok
                and pleasure_lib:unwrap(item_valid) == true
            then
                local definition_ok, definition = pcall(function()
                    return definition_fn(inventory_base, position)
                end)
                definition = pleasure_lib:unwrap(definition)
                if not definition_ok
                    or not is_valid(definition)
                then
                    scan_complete = false
                end
                if definition_ok and is_valid(definition) then
                    local matches = false
                    if inventory_type
                        == INVENTORY_TYPE_RANGED_SLOT
                    then
                        matches = pleasure_lib:try(function()
                            return definition:IsA(
                                "/Script/G1R.WeaponRangedDefinition")
                        end) == true or pleasure_lib:try(function()
                            return definition:IsA(
                                "/Script/G1R.WeaponArcheryDefinition")
                        end) == true
                    elseif inventory_type
                        == INVENTORY_TYPE_MELEE_SLOT
                    then
                        matches = pleasure_lib:try(function()
                            return definition:IsA(
                                "/Script/G1R.WeaponMeleeDefinition")
                        end) == true
                    end
                    pleasure_lib:debug_log(
                        "inspected hotbar item definition"
                        .. " position=" .. tostring(position)
                        .. " definition=" .. full_name(definition)
                        .. " matches=" .. tostring(matches))
                    if matches then
                        return position, definition, true
                    end
                end
            end
        end

        return nil, nil, scan_complete
    end

    local function item_definition_from_inventory_position(
        inventory_main, item_pos)
        if item_pos == nil or item_pos < 0 then return nil end

        local inventory_base =
            property_value(inventory_main, "InventoryBase")
        if not is_valid(inventory_base) then return nil end

        local valid_fn = pleasure_lib:try(function()
            return inventory_base["IsItemValidByPos"]
        end)
        if valid_fn == nil then return nil end
        local valid_ok, item_valid = pcall(function()
            return valid_fn(inventory_base, item_pos)
        end)
        if not valid_ok
            or pleasure_lib:unwrap(item_valid) ~= true
        then
            return nil
        end

        local fn = pleasure_lib:try(function()
            return inventory_base["GetBaseConfigByPos"]
        end)
        if fn == nil then return nil end
        local ok, definition = pcall(function()
            return fn(inventory_base, item_pos)
        end)
        definition = pleasure_lib:unwrap(definition)
        pleasure_lib:debug_log(
            "resolved hovered item definition"
            .. " itemPos=" .. tostring(item_pos)
            .. " ok=" .. tostring(ok)
            .. " definition=" .. full_name(definition))
        if ok and is_valid(definition) then return definition end
        return nil
    end

    local function definition_is_a(definition, class_name)
        if not is_valid(definition) then return false end
        return pleasure_lib:try(function()
            return definition:IsA(class_name)
        end) == true
    end

    local function weapon_inventory_type_at_position(
        inventory_main, item_pos)
        local definition =
            item_definition_from_inventory_position(
                inventory_main,
                item_pos)
        if not is_valid(definition) then
            return nil, "", false
        end

        if definition_is_a(
            definition,
            "/Script/G1R.WeaponRangedDefinition")
            or definition_is_a(
                definition,
                "/Script/G1R.WeaponArcheryDefinition")
        then
            return INVENTORY_TYPE_RANGED_SLOT,
                full_name(definition),
                true
        end
        if definition_is_a(
            definition,
            "/Script/G1R.WeaponMeleeDefinition")
        then
            return INVENTORY_TYPE_MELEE_SLOT,
                full_name(definition),
                true
        end
        return nil, full_name(definition), true
    end

    return {
        slot_item_pos = slot_item_pos,
        slot_is_main_inventory = slot_is_main_inventory,
        slot_has_hotbar_assignment =
            slot_has_hotbar_assignment,
        first_hotbar_weapon_position =
            first_hotbar_weapon_position,
        weapon_inventory_type_at_position =
            weapon_inventory_type_at_position,
    }
end

return Inventory
