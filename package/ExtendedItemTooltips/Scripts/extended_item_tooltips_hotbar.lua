local Hotbar = {}

local HOTBAR_CREATION_MAX_ATTEMPTS = 3
local HOTBAR_CREATION_RETRY_ATTEMPTS = {
    [0] = true,
    [3] = true,
    [6] = true,
    [7] = true,
}

function Hotbar.new(options)
    if type(options) ~= "table" then return nil end

    local pleasure_lib = options.pleasure_lib
    local runtime = options.runtime
    local first_hotbar_weapon_position =
        options.first_hotbar_weapon_position
    if type(pleasure_lib) ~= "table"
        or type(runtime) ~= "table"
        or type(first_hotbar_weapon_position) ~= "function"
    then
        return nil
    end

    local is_valid = runtime.is_valid
    local full_name = runtime.full_name
    local object_instance_key = runtime.object_instance_key
    local object_world_key = runtime.object_world_key
    local property_value = runtime.property_value

    local cached_hotbar = nil
    local hotbar_creation_requested_for_controller = {}

    local function find_weapon_hotbar(
        inventory_main, inventory_type, comparison_attempt)
        comparison_attempt = tonumber(comparison_attempt) or 0
        local expected_world = object_world_key(inventory_main)
        local fallback = nil
        local seen = {}

        local function hotbar_is_shaped(candidate)
            candidate = pleasure_lib:unwrap(candidate)
            return is_valid(candidate)
                and is_valid(
                    property_value(candidate, "m_InventoryBase"))
                and (is_valid(
                    property_value(candidate, "Slot_Melee"))
                    or is_valid(
                        property_value(candidate, "Slot_Ranged")))
        end

        local function inspect_hotbar(candidate, source)
            candidate = pleasure_lib:unwrap(candidate)
            if not hotbar_is_shaped(candidate) then return nil end

            local candidate_world = object_world_key(candidate)
            if expected_world ~= "" and candidate_world ~= ""
                and candidate_world ~= expected_world
            then
                pleasure_lib:debug_log(
                    "ignored hotbar from another world"
                    .. " source=" .. tostring(source)
                    .. " world=" .. tostring(candidate_world)
                    .. " expected=" .. tostring(expected_world))
                return nil
            end

            local candidate_key = object_instance_key(candidate)
            if seen[candidate_key] == true then return nil end
            seen[candidate_key] = true

            local position, definition, ready =
                first_hotbar_weapon_position(
                    candidate,
                    inventory_type)
            if position ~= nil and is_valid(definition) then
                cached_hotbar = candidate
                pleasure_lib:debug_log(
                    "resolved matching weapon hotbar"
                    .. " source=" .. tostring(source)
                    .. " object=" .. full_name(candidate)
                    .. " position=" .. tostring(position))
                return candidate
            end

            if fallback == nil then fallback = candidate end
            pleasure_lib:debug_log(
                "inspected weapon hotbar candidate"
                .. " source=" .. tostring(source)
                .. " ready=" .. tostring(ready)
                .. " object=" .. full_name(candidate))
            return nil
        end

        if is_valid(cached_hotbar) then
            local matched =
                inspect_hotbar(cached_hotbar, "cache")
            if matched ~= nil then return matched end
        end
        cached_hotbar = nil

        local controllers =
            pleasure_lib:find_all_of("HUDQuickSlotController")
        if type(controllers) == "table" then
            for _, object in ipairs(controllers) do
                local controller = pleasure_lib:unwrap(object)
                local hotbar = inspect_hotbar(
                    property_value(controller, "m_QuickSlot"),
                    "controller")
                if hotbar ~= nil then return hotbar end
            end
        end

        local objects = pleasure_lib:find_all_of("W_Hotbar_C")
        if type(objects) == "table" then
            for _, object in ipairs(objects) do
                local hotbar = inspect_hotbar(
                    object,
                    "objectScan")
                if hotbar ~= nil then return hotbar end
            end
        end

        -- Vanilla clears the hidden keyboard hotbar. Drive the same
        -- instant press/release path a bounded number of times so it
        -- creates a normal instance without latching it visible like
        -- AlwaysVisibleHotbar does.
        if type(controllers) == "table" then
            for _, object in ipairs(controllers) do
                local controller = pleasure_lib:unwrap(object)
                local controller_world =
                    object_world_key(controller)
                local same_world = expected_world == ""
                    or controller_world == ""
                    or controller_world == expected_world
                local controller_key =
                    object_instance_key(controller)
                local creation_attempts = tonumber(
                    hotbar_creation_requested_for_controller[
                        controller_key])
                    or 0
                local current_hotbar =
                    property_value(controller, "m_QuickSlot")
                if is_valid(controller) and same_world
                    and not hotbar_is_shaped(current_hotbar)
                    and creation_attempts
                        < HOTBAR_CREATION_MAX_ATTEMPTS
                    and HOTBAR_CREATION_RETRY_ATTEMPTS[
                        comparison_attempt] == true
                then
                    hotbar_creation_requested_for_controller[
                        controller_key] = creation_attempts + 1
                    local pressed, press_error = pcall(function()
                        controller:QuickSlotBindingPress()
                        controller:QuickSlotBindingRelease()
                    end)
                    pleasure_lib:debug_log(
                        "requested vanilla hotbar creation"
                        .. " ok=" .. tostring(pressed)
                        .. " error=" .. tostring(press_error))
                    local hotbar = inspect_hotbar(
                        property_value(controller, "m_QuickSlot"),
                        "controllerAfterTap")
                    if hotbar ~= nil then return hotbar end
                end
            end
        end

        if fallback ~= nil then
            cached_hotbar = fallback
        end
        return fallback
    end

    local function invalidate_cache()
        cached_hotbar = nil
    end

    local function begin_inventory_session()
        hotbar_creation_requested_for_controller = {}
        cached_hotbar = nil
    end

    return {
        find_weapon_hotbar = find_weapon_hotbar,
        invalidate_cache = invalidate_cache,
        begin_inventory_session = begin_inventory_session,
    }
end

return Hotbar
