local Discovery = {}

function Discovery.new(options)
    if type(options) ~= "table" then return nil end

    local pleasure_lib = options.pleasure_lib
    local runtime = options.runtime
    if type(pleasure_lib) ~= "table"
        or type(runtime) ~= "table"
    then
        return nil
    end

    local is_valid = runtime.is_valid
    local object_is_inventory_main =
        runtime.object_is_inventory_main
    local property_value = runtime.property_value
    local related_object_with_name =
        runtime.related_object_with_name

    local cached_inventory_main = nil
    local cached_wearables_bar = nil

    local function refresh_inventory_main_from_slot(slot)
        local related =
            related_object_with_name(slot, "W_Inventory_Main")
        if is_valid(related) then
            cached_inventory_main = related
            return related
        end

        local parent = pleasure_lib:try(function()
            if type(slot.GetParent) == "function" then
                return slot:GetParent()
            end
            return nil
        end)
        local depth = 0
        while is_valid(parent) and depth < 10 do
            if object_is_inventory_main(parent) then
                cached_inventory_main = parent
                return parent
            end
            local current = parent
            parent = pleasure_lib:try(function()
                if type(current.GetParent) == "function" then
                    return current:GetParent()
                end
                return nil
            end)
            depth = depth + 1
        end

        return cached_inventory_main
    end

    local function wearables_bar_from(slot_or_inventory)
        local direct = pleasure_lib:unwrap(
            property_value(
                slot_or_inventory,
                "EquippedWearables"))
        if is_valid(direct) then
            cached_wearables_bar = direct
            return direct
        end

        local related = related_object_with_name(
            slot_or_inventory,
            "W_EquippedWearables")
        if is_valid(related) then
            cached_wearables_bar = related
            return related
        end

        local inventory_main =
            refresh_inventory_main_from_slot(slot_or_inventory)
        direct = pleasure_lib:unwrap(
            property_value(inventory_main, "EquippedWearables"))
        if is_valid(direct) then
            cached_wearables_bar = direct
            return direct
        end

        if is_valid(cached_wearables_bar) then
            return cached_wearables_bar
        end
        return nil
    end

    local function reset()
        cached_inventory_main = nil
        cached_wearables_bar = nil
    end

    local function begin_inventory_session(inventory_main)
        cached_inventory_main = inventory_main
        cached_wearables_bar = nil
    end

    return {
        refresh_inventory_main_from_slot =
            refresh_inventory_main_from_slot,
        wearables_bar_from = wearables_bar_from,
        reset = reset,
        begin_inventory_session = begin_inventory_session,
    }
end

return Discovery
