local Runtime = {}

local GAMEPLAY_STATICS_DEFAULT_OBJECT =
    "/Script/Engine.Default__GameplayStatics"

function Runtime.new(options)
    if type(options) ~= "table" then return nil end

    local pleasure_lib = options.pleasure_lib
    local generation_is_current = options.generation_is_current
    local inventory_main_path_needles =
        options.inventory_main_path_needles
    if type(pleasure_lib) ~= "table"
        or type(generation_is_current) ~= "function"
        or type(inventory_main_path_needles) ~= "table"
    then
        return nil
    end

    local gameplay_statics_default = nil
    local comparison_clock_source_logged = nil

    local function is_valid(obj)
        -- Preserve an explicit false from PleasureLib. Stale widgets from a
        -- previous save can still expose a readable object name.
        return pleasure_lib:is_valid(obj)
    end

    local function full_name(obj)
        local name = pleasure_lib:full_name(obj)
        if name ~= "" or not is_valid(obj) then return name end
        return pleasure_lib:try(function()
            return obj:GetFullName()
        end) or ""
    end

    local function object_instance_key(obj)
        if not is_valid(obj) then return "" end
        local address = pleasure_lib:try(function()
            if type(obj.GetAddress) == "function" then
                return obj:GetAddress()
            end
            return nil
        end)
        local numeric_address = tonumber(address)
        if numeric_address ~= nil and numeric_address ~= 0 then
            return full_name(obj) .. "|@" .. tostring(address)
        end
        return full_name(obj)
    end

    local function object_world_key(obj)
        if not is_valid(obj) then return "" end
        local world = pleasure_lib:try(function()
            if type(obj.GetWorld) == "function" then
                return obj:GetWorld()
            end
            return nil
        end)
        world = pleasure_lib:unwrap(world)
        if not is_valid(world) then return "" end
        return object_instance_key(world)
    end

    local function object_class_token(obj)
        local text = full_name(obj)
        return text:match("^([^%s]+)") or ""
    end

    local function object_short_name(obj)
        local name = pleasure_lib:try(function()
            if type(obj.GetName) == "function" then
                return obj:GetName()
            end
            return nil
        end)
        if name ~= nil then return tostring(name) end

        local text = full_name(obj)
        local path = text:match("%s(.+)$") or text
        return path:match("([^%.:]+)$") or ""
    end

    local function contains(haystack, needle)
        return string.find(
            pleasure_lib:lower(haystack),
            pleasure_lib:lower(needle),
            1,
            true) ~= nil
    end

    local function object_named_like(object, needle)
        local text =
            object_class_token(object) .. " " .. object_short_name(object)
        return contains(text, needle)
    end

    local function object_is_inventory_main(object)
        for _, needle in ipairs(inventory_main_path_needles) do
            if object_named_like(object, needle) then return true end
        end
        return false
    end

    local function property_value(object, property_name)
        if not is_valid(object) then return nil end
        local value = pleasure_lib:try(function()
            if type(object.GetPropertyValue) == "function" then
                return object:GetPropertyValue(property_name)
            end
            return nil
        end)
        if value ~= nil then return pleasure_lib:unwrap(value) end

        value = pleasure_lib:try(function()
            return object[property_name]
        end)
        return pleasure_lib:unwrap(value)
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
        if setter_ok then
            return true, setter_result or "SetPropertyValue"
        end

        return false, setter_result
    end

    local function number_property(object, property_name)
        local value =
            pleasure_lib:unwrap(property_value(object, property_name))
        local number = tonumber(value)
        if number ~= nil then return number end
        return nil
    end

    local function bool_property(object, property_name)
        local value =
            pleasure_lib:unwrap(property_value(object, property_name))
        if value == true or value == 1 then return true end
        if value == false or value == 0 then return false end

        local text = pleasure_lib:lower(value)
        if text == "true" or text == "1" then return true end
        if text == "false" or text == "0" then return false end
        return nil
    end

    local function widget_visibility_value(widget)
        local value =
            pleasure_lib:unwrap(property_value(widget, "Visibility"))
        if value == nil then return "nil" end
        return tostring(value)
    end

    local function ufunction_loaded(path)
        return is_valid(pleasure_lib:find_object(path))
    end

    local function related_object_with_name(start_object, needle)
        local current = pleasure_lib:unwrap(start_object)
        local depth = 0
        while is_valid(current) and depth < 14 do
            if object_named_like(current, needle) then return current end

            local next_object = pleasure_lib:try(function()
                if type(current.GetOuter) == "function" then
                    return current:GetOuter()
                end
                return nil
            end)
            if not is_valid(next_object)
                and type(current.GetParent) == "function"
            then
                next_object = pleasure_lib:try(function()
                    return current:GetParent()
                end)
            end
            current = pleasure_lib:unwrap(next_object)
            depth = depth + 1
        end
        return nil
    end

    local function tooltip_is_valid(info)
        if info == nil then return false end
        local valid =
            pleasure_lib:unwrap(property_value(info, "IsValid"))
        if valid == true or valid == 1 then return true end
        if valid == false or valid == 0 then return false end
        return true
    end

    local function call_delegate(delegate, ...)
        delegate = pleasure_lib:unwrap(delegate)
        if delegate == nil then return false, "delegate missing" end

        local method_names = { "Broadcast", "Execute", "Call" }
        local args = { ... }
        args.n = select("#", ...)
        local unpack_args = table.unpack or unpack
        if not unpack_args then return false, "unpack unavailable" end

        for _, name in ipairs(method_names) do
            local method = pleasure_lib:try(function()
                return delegate[name]
            end)
            if type(method) == "function" then
                local ok, result = pcall(function()
                    return method(
                        delegate,
                        unpack_args(args, 1, args.n))
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
        -- Schedule directly on the game thread so rapid hover events cannot
        -- build another queue of callbacks waiting to be marshalled later.
        return pleasure_lib:delay_game_thread(ms, function()
            if generation_is_current() then fn() end
        end)
    end

    local function comparison_clock_ms(world_context)
        if not is_valid(gameplay_statics_default) then
            gameplay_statics_default =
                pleasure_lib:find_object(GAMEPLAY_STATICS_DEFAULT_OBJECT)
        end

        local real_time_seconds = pleasure_lib:try(function()
            if is_valid(gameplay_statics_default)
                and type(gameplay_statics_default.GetRealTimeSeconds)
                    == "function"
            then
                return gameplay_statics_default:GetRealTimeSeconds(
                    world_context)
            end
            return nil
        end)
        real_time_seconds =
            tonumber(pleasure_lib:unwrap(real_time_seconds))
        if real_time_seconds ~= nil then
            if comparison_clock_source_logged ~= "GameplayStatics" then
                comparison_clock_source_logged = "GameplayStatics"
                pleasure_lib:debug_log(
                    "weapon comparison clock source=GameplayStatics")
            end
            return math.floor(real_time_seconds * 1000)
        end

        local world = pleasure_lib:try(function()
            if is_valid(world_context)
                and type(world_context.GetWorld) == "function"
            then
                return world_context:GetWorld()
            end
            return nil
        end)
        world = pleasure_lib:unwrap(world)
        real_time_seconds =
            tonumber(property_value(world, "RealTimeSeconds"))
        if real_time_seconds ~= nil then
            if comparison_clock_source_logged ~= "UWorld" then
                comparison_clock_source_logged = "UWorld"
                pleasure_lib:debug_log(
                    "weapon comparison clock source=UWorld")
            end
            return math.floor(real_time_seconds * 1000)
        end

        -- Never mix this world-relative clock with another time origin while
        -- the inventory is being torn down.
        return nil
    end

    local function array_length(value)
        value = pleasure_lib:unwrap(value)
        if value == nil then return nil end

        local ok, length = pcall(function()
            return #value
        end)
        if ok and type(length) == "number" then return length end

        for _, method_name in ipairs({ "Num", "GetArrayNum" }) do
            local method = pleasure_lib:try(function()
                return value[method_name]
            end)
            if type(method) == "function" then
                length = pleasure_lib:try(function()
                    return pleasure_lib:unwrap(method(value))
                end)
                length = tonumber(length)
                if length ~= nil then return length end
            end
        end
        return nil
    end

    return {
        is_valid = is_valid,
        full_name = full_name,
        object_instance_key = object_instance_key,
        object_world_key = object_world_key,
        object_is_inventory_main = object_is_inventory_main,
        property_value = property_value,
        set_property_value = set_property_value,
        number_property = number_property,
        bool_property = bool_property,
        widget_visibility_value = widget_visibility_value,
        ufunction_loaded = ufunction_loaded,
        related_object_with_name = related_object_with_name,
        tooltip_is_valid = tooltip_is_valid,
        call_delegate = call_delegate,
        run_later = run_later,
        comparison_clock_ms = comparison_clock_ms,
        array_length = array_length,
    }
end

return Runtime
