local Hooks = {}

local UI_OBJECT_NOTIFY_CLASSES = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Main.W_Inventory_Main_C",
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Slot.W_Inventory_Slot_C",
    "/Game/UI/ManagementUI/Inventory/W_Inventory_ItemTooltip.W_Inventory_ItemTooltip_C",
}

local COMPARISON_TOGGLE_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Main.W_Inventory_Main_C:DoToggleWearableComparisonTooltip",
}

local INVENTORY_SHOWN_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Main.W_Inventory_Main_C:OnShown",
}

local TOOLTIP_HINT_REFRESH_HOOKS = {
    "/Script/G1R.InventoryItemTooltip:UpdateTooltip",
    "/Game/UI/ManagementUI/Inventory/W_Inventory_ItemTooltip.W_Inventory_ItemTooltip_C:CheckInputWearableTooltipButtonViaTags",
}

local HOOK_REGISTRATION_RETRY_INITIAL_MS = 50
local HOOK_REGISTRATION_RETRY_MAX_MS = 2000

function Hooks.new(options)
    if type(options) ~= "table" then return nil end

    local pleasure_lib = options.pleasure_lib
    local runtime = options.runtime
    local generation_is_current =
        options.generation_is_current
    local config = options.config
    local handlers = options.handlers
    if type(pleasure_lib) ~= "table"
        or type(runtime) ~= "table"
        or type(generation_is_current) ~= "function"
        or type(config) ~= "table"
        or type(handlers) ~= "table"
        or type(handlers.slot_hovered) ~= "function"
        or type(handlers.slot_unhovered) ~= "function"
        or type(handlers.comparison_toggled) ~= "function"
        or type(handlers.inventory_shown) ~= "function"
        or type(handlers.inventory_tooltip_updated) ~= "function"
    then
        return nil
    end

    local full_name = runtime.full_name
    local ufunction_loaded = runtime.ufunction_loaded
    local run_later = runtime.run_later

    local hook_groups = {
        {
            config_key = "SlotHoverHooks",
            handler = handlers.slot_hovered,
        },
        {
            config_key = "SlotUnhoverHooks",
            handler = handlers.slot_unhovered,
        },
        {
            paths = COMPARISON_TOGGLE_HOOKS,
            handler = handlers.comparison_toggled,
        },
        {
            paths = INVENTORY_SHOWN_HOOKS,
            handler = handlers.inventory_shown,
        },
        {
            paths = TOOLTIP_HINT_REFRESH_HOOKS,
            post_handler =
                handlers.inventory_tooltip_updated,
        },
    }

    local registered_hooks = {}
    local hook_retry_logged = {}
    local handled_ui_notification_classes = {}
    local hook_registration_retry_pending = false
    local hook_registration_immediate_pending = false
    local hook_registration_retry_delay_ms =
        HOOK_REGISTRATION_RETRY_INITIAL_MS
    local hook_registration_complete_handled = false

    local function register_hook(path, handler, post_handler)
        if type(RegisterHook) ~= "function" then
            pleasure_lib:log("RegisterHook unavailable")
            return false
        end
        if registered_hooks[path] == true then return false end

        if not ufunction_loaded(path) then
            if hook_retry_logged[path] ~= "not-loaded" then
                hook_retry_logged[path] = "not-loaded"
                pleasure_lib:debug_log(
                    "Hook target not loaded yet; retrying "
                    .. path)
            end
            return false
        end

        local function guarded(callback)
            return function(context, ...)
                if not generation_is_current() then return nil end
                if type(callback) ~= "function" then return nil end
                return callback(path, context, ...)
            end
        end

        local primary_handler = handler
        local secondary_handler = post_handler
        if path:sub(1, 8) ~= "/Script/" then
            -- UE4SS executes callback two after Blueprint functions and
            -- ignores callback three. Route an explicitly requested
            -- post-handler into the only callback slot that Blueprint
            -- hooks support.
            primary_handler = post_handler or handler
            secondary_handler = nil
        end

        local ok, pre_id, post_id = pcall(function()
            if type(secondary_handler) == "function" then
                return RegisterHook(
                    path,
                    guarded(primary_handler),
                    guarded(secondary_handler))
            end
            return RegisterHook(path, guarded(primary_handler))
        end)
        if not ok or (pre_id == nil and post_id == nil) then
            if hook_retry_logged[path] ~= "not-hookable" then
                hook_retry_logged[path] = "not-hookable"
                pleasure_lib:debug_log(
                    "Hook target loaded but not hookable "
                    .. path
                    .. " error=" .. tostring(pre_id))
            end
            return false
        end

        registered_hooks[path] = true
        hook_retry_logged[path] = nil
        pleasure_lib:debug_log("registered hook"
            .. " path=" .. tostring(path)
            .. " preId=" .. tostring(pre_id)
            .. " postId=" .. tostring(post_id))
        return true
    end

    local function hook_group_paths(group)
        if group.config_key ~= nil then
            return config[group.config_key] or {}
        end
        return group.paths or {}
    end

    local function register_hooks()
        local count = 0
        for _, group in ipairs(hook_groups) do
            for _, path in ipairs(hook_group_paths(group)) do
                if register_hook(
                    path,
                    group.handler,
                    group.post_handler)
                then
                    count = count + 1
                end
            end
        end
        return count
    end

    local function pending_hook_group_count()
        local pending = 0
        for _, group in ipairs(hook_groups) do
            local has_candidates = false
            local has_registered_candidate = false
            for _, path in ipairs(hook_group_paths(group)) do
                has_candidates = true
                if registered_hooks[path] == true then
                    has_registered_candidate = true
                    break
                end
            end
            if has_candidates
                and not has_registered_candidate
            then
                pending = pending + 1
            end
        end
        return pending
    end

    local function handle_hook_registration_complete()
        if hook_registration_complete_handled == true then return end
        if pending_hook_group_count() ~= 0 then return end

        hook_registration_complete_handled = true
        hook_registration_retry_delay_ms =
            HOOK_REGISTRATION_RETRY_INITIAL_MS
        pleasure_lib:debug_log(
            "all inventory hook groups registered")
    end

    local schedule_hook_registration_retry
    schedule_hook_registration_retry =
        function(delay_override_ms)
            if pending_hook_group_count() == 0 then
                handle_hook_registration_complete()
                return true
            end
            if hook_registration_retry_pending == true then
                return true
            end

            local delay_ms = tonumber(delay_override_ms)
                or hook_registration_retry_delay_ms
            hook_registration_retry_pending = true
            local scheduled = run_later(delay_ms, function()
                hook_registration_retry_pending = false
                register_hooks()
                if pending_hook_group_count() == 0 then
                    handle_hook_registration_complete()
                    return
                end

                hook_registration_retry_delay_ms = math.min(
                    math.max(
                        HOOK_REGISTRATION_RETRY_INITIAL_MS,
                        hook_registration_retry_delay_ms * 2),
                    HOOK_REGISTRATION_RETRY_MAX_MS)
                schedule_hook_registration_retry()
            end)
            if not scheduled then
                hook_registration_retry_pending = false
                pleasure_lib:log(
                    "Could not schedule inventory hook"
                    .. " registration retry.")
            end
            return scheduled
        end

    local function schedule_immediate_hook_registration_retry()
        if pending_hook_group_count() == 0 then
            handle_hook_registration_complete()
            return true
        end
        if hook_registration_immediate_pending == true then
            return true
        end

        hook_registration_immediate_pending = true
        local scheduled = run_later(0, function()
            hook_registration_immediate_pending = false
            register_hooks()
            if pending_hook_group_count() == 0 then
                handle_hook_registration_complete()
            end
        end)
        if not scheduled then
            hook_registration_immediate_pending = false
        end
        return scheduled
    end

    local function install_ui_object_notifications()
        if type(NotifyOnNewObject) ~= "function" then
            pleasure_lib:log(
                "NotifyOnNewObject unavailable;"
                .. " late UI hooks cannot be registered.")
            return 0
        end

        local registered = 0
        for _, class_name in ipairs(UI_OBJECT_NOTIFY_CLASSES) do
            local notify_class = class_name
            local ok, result = pcall(function()
                return NotifyOnNewObject(
                    notify_class,
                    function(object)
                        if not generation_is_current() then return end
                        if handled_ui_notification_classes[
                            notify_class] == true
                        then
                            return
                        end
                        handled_ui_notification_classes[
                            notify_class] = true
                        pleasure_lib:debug_log(
                            "UI object created;"
                            .. " registering loaded hooks"
                            .. " class=" .. tostring(notify_class)
                            .. " object=" .. full_name(object))

                        register_hooks()
                        if pending_hook_group_count() == 0 then
                            handle_hook_registration_complete()
                        else
                            hook_registration_retry_delay_ms =
                                HOOK_REGISTRATION_RETRY_INITIAL_MS
                            schedule_immediate_hook_registration_retry()
                        end
                    end)
            end)
            if ok then
                registered = registered + 1
                pleasure_lib:debug_log(
                    "UI object notification registered"
                    .. " class=" .. tostring(notify_class)
                    .. " result=" .. tostring(result))
            else
                pleasure_lib:debug_log(
                    "UI object notification failed"
                    .. " class=" .. tostring(notify_class)
                    .. " error=" .. tostring(result))
            end
        end
        return registered
    end

    local function start()
        local notification_count =
            install_ui_object_notifications()
        local hook_count = register_hooks()
        if pending_hook_group_count() == 0 then
            handle_hook_registration_complete()
        else
            schedule_hook_registration_retry()
        end
        return notification_count, hook_count
    end

    return {
        start = start,
    }
end

return Hooks
