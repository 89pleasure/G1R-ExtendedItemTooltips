local InventoryComparison = {}

local WEAPON_COMPARISON_RETRY_DELAYS_MS = {
    50, 100, 200, 350, 500, 750, 1000, 1500,
}

function InventoryComparison.new(options)
    if type(options) ~= "table" then return nil end

    local pleasure_lib = options.pleasure_lib
    local runtime = options.runtime
    local config = options.config
    local weapon_comparison_hover_settle_ms =
        options.weapon_comparison_hover_settle_ms
    local inventory_helpers = options.inventory_helpers
    local hotbar_resolver = options.hotbar_resolver
    local widget_helpers = options.widget_helpers
    local weapon_state = options.weapon_state
    local weapon_bridge = options.weapon_bridge
    if type(pleasure_lib) ~= "table"
        or type(runtime) ~= "table"
        or type(config) ~= "table"
        or type(weapon_comparison_hover_settle_ms) ~= "function"
        or type(inventory_helpers) ~= "table"
        or type(hotbar_resolver) ~= "table"
        or type(widget_helpers) ~= "table"
        or type(weapon_state) ~= "table"
        or type(weapon_bridge) ~= "table"
        or type(runtime.is_valid) ~= "function"
        or type(runtime.full_name) ~= "function"
        or type(runtime.object_instance_key) ~= "function"
        or type(runtime.property_value) ~= "function"
        or type(runtime.bool_property) ~= "function"
        or type(runtime.related_object_with_name) ~= "function"
        or type(runtime.run_later) ~= "function"
        or type(runtime.comparison_clock_ms) ~= "function"
        or type(runtime.array_length) ~= "function"
        or type(inventory_helpers.first_hotbar_weapon_position)
            ~= "function"
        or type(inventory_helpers.slot_has_hotbar_assignment)
            ~= "function"
        or type(inventory_helpers.slot_item_pos) ~= "function"
        or type(inventory_helpers.weapon_inventory_type_at_position)
            ~= "function"
        or type(hotbar_resolver.find_weapon_hotbar) ~= "function"
        or type(widget_helpers.inventory_main_tooltip_widget)
            ~= "function"
        or type(widget_helpers.inventory_weapon_compare_widget)
            ~= "function"
        or type(widget_helpers.ensure_inventory_tooltip_activation)
            ~= "function"
        or type(widget_helpers.set_widget_visibility) ~= "function"
        or type(widget_helpers.force_weapon_comparison_hint)
            ~= "function"
        or type(widget_helpers.visibility_collapsed) ~= "number"
        or type(weapon_state.is_active) ~= "function"
        or type(weapon_state.source_matches) ~= "function"
        or type(weapon_state.activate) ~= "function"
        or type(weapon_state.maintain_visibility) ~= "function"
        or type(weapon_state.end_comparison) ~= "function"
        or type(weapon_bridge.is_busy) ~= "function"
        or type(weapon_bridge.run) ~= "function"
    then
        return nil
    end

    local is_valid = runtime.is_valid
    local full_name = runtime.full_name
    local object_instance_key = runtime.object_instance_key
    local property_value = runtime.property_value
    local bool_property = runtime.bool_property
    local related_object_with_name =
        runtime.related_object_with_name
    local run_later = runtime.run_later
    local comparison_clock_ms = runtime.comparison_clock_ms
    local array_length = runtime.array_length
    local inventory_main_tooltip_widget =
        widget_helpers.inventory_main_tooltip_widget
    local inventory_weapon_compare_widget =
        widget_helpers.inventory_weapon_compare_widget
    local ensure_inventory_tooltip_activation =
        widget_helpers.ensure_inventory_tooltip_activation
    local set_widget_visibility =
        widget_helpers.set_widget_visibility
    local force_weapon_comparison_hint =
        widget_helpers.force_weapon_comparison_hint
    local visibility_collapsed =
        widget_helpers.visibility_collapsed

    local inventory_session_token = 0
    local settle_pending = false
    local settle_timer_generation = 0
    local settle_timer_due_at_ms = nil
    local hint_reassert_pending = false
    local hint_reassert_token = nil
    local hint_reassert_inventory_main_key = nil
    local hint_reassert_label = nil
    local active_comparison = {
        active = false,
        token = 0,
        slot_key = nil,
        item_pos = nil,
        inventory_main = nil,
        inventory_main_key = nil,
        weapon_type = nil,
        definition_name = nil,
        resolution_attempt = 0,
        comparison_attempt = 0,
        settle_not_before_ms = nil,
    }

    local function schedule_hint_reassert(label)
        if active_comparison.active ~= true
            or active_comparison.weapon_type == nil
        then
            return false
        end

        hint_reassert_token = active_comparison.token
        hint_reassert_inventory_main_key =
            active_comparison.inventory_main_key
        hint_reassert_label = tostring(label)
        if hint_reassert_pending then return true end

        hint_reassert_pending = true
        local scheduled = run_later(0, function()
            hint_reassert_pending = false
            local requested_token = hint_reassert_token
            local requested_inventory_main_key =
                hint_reassert_inventory_main_key
            local requested_label = hint_reassert_label
            hint_reassert_token = nil
            hint_reassert_inventory_main_key = nil
            hint_reassert_label = nil

            if active_comparison.active ~= true
                or active_comparison.weapon_type == nil
                or active_comparison.token ~= requested_token
                or active_comparison.inventory_main_key
                    ~= requested_inventory_main_key
            then
                return
            end
            force_weapon_comparison_hint(
                active_comparison.inventory_main,
                true,
                tostring(requested_label) .. ".postUpdate")
        end)
        if not scheduled then
            hint_reassert_pending = false
        end
        return scheduled
    end

    local function on_tooltip_updated(_hook_name, context)
        if config.Enabled ~= true
            or config.EnableComparisonTooltips ~= true
            or active_comparison.active ~= true
            or active_comparison.weapon_type == nil
        then
            return nil
        end

        local updated_tooltip = pleasure_lib:unwrap(context)
        local inventory_main = active_comparison.inventory_main
        local base_tooltip =
            inventory_main_tooltip_widget(inventory_main)
        if not is_valid(updated_tooltip)
            or object_instance_key(updated_tooltip)
                ~= object_instance_key(base_tooltip)
        then
            return nil
        end

        force_weapon_comparison_hint(
            inventory_main, true, "comparison.tooltipUpdated")
        return nil
    end

    local function begin_weapon_comparison(
        inventory_main,
        weapon_type,
        definition_name,
        source_slot_key,
        source_item_pos,
        comparison_token,
        attempt)
        attempt = tonumber(attempt) or 0
        if weapon_type == nil or source_item_pos == nil then
            return false, false, "invalid comparison snapshot"
        end
        if active_comparison.active ~= true
            or active_comparison.token ~= comparison_token
        then
            return false, false, "comparison request changed"
        end

        local source_inventory_main_key =
            active_comparison.inventory_main_key
        if weapon_state.source_matches(
            source_inventory_main_key,
            source_slot_key,
            source_item_pos,
            weapon_type,
            definition_name)
        then
            weapon_state.maintain_visibility(
                "weaponComparison.unchanged")
            -- A regular inventory refresh evaluates the weapon's native
            -- specs and collapses this already-configured
            -- wearable-comparison input. Restore only its visibility;
            -- never mutate the shared item definition.
            force_weapon_comparison_hint(
                inventory_main,
                true,
                "weaponComparison.unchanged")
            return true, false, nil
        end

        if weapon_bridge.is_busy() then
            return false, false, "comparison bridge busy"
        end

        local hotbar = hotbar_resolver.find_weapon_hotbar(
            inventory_main, weapon_type, attempt)
        if not is_valid(hotbar) then
            return false, true, "vanilla hotbar unavailable"
        end

        local weapon_position, weapon_definition, hotbar_ready =
            inventory_helpers.first_hotbar_weapon_position(
                hotbar,
                weapon_type)
        if weapon_position == nil
            or not is_valid(weapon_definition)
        then
            if hotbar_ready ~= true then
                return false, true, "hotbar inventory not ready"
            end
            return false, true, "matching hotbar weapon unavailable"
        end

        local base_widget =
            inventory_main_tooltip_widget(inventory_main)
        local compare_widget =
            inventory_weapon_compare_widget(inventory_main)
        if not is_valid(base_widget)
            or not is_valid(compare_widget)
        then
            return false, true, "inventory tooltip widgets unavailable"
        end

        local hotbar_slot_count = array_length(
            property_value(hotbar, "m_SlotsData"))
        if hotbar_slot_count == nil
            or weapon_position == nil
            or weapon_position < 0
            or weapon_position >= hotbar_slot_count
        then
            return false, true, "hotbar slot index unavailable"
                .. " position=" .. tostring(weapon_position)
                .. " slotCount=" .. tostring(hotbar_slot_count)
        end
        pleasure_lib:debug_log(
            "resolved hotbar weapon comparison entry"
            .. " position=" .. tostring(weapon_position)
            .. " inventoryType=" .. tostring(weapon_type)
            .. " definition=" .. full_name(weapon_definition))

        -- Hotbar creation can dispatch UI events. Do not enter the native
        -- bridge if one of them replaced this hover while readiness was
        -- being resolved.
        if active_comparison.active ~= true
            or active_comparison.token ~= comparison_token
            or active_comparison.inventory_main_key
                ~= source_inventory_main_key
            or active_comparison.slot_key ~= source_slot_key
            or active_comparison.item_pos ~= source_item_pos
        then
            return false, false,
                "comparison request changed during readiness"
        end

        if weapon_state.is_active() then
            weapon_state.end_comparison("weaponComparison.replace")
        end

        local route_ok, route_error = weapon_bridge.run(
            hotbar,
            inventory_main,
            base_widget,
            compare_widget,
            weapon_position)
        if not route_ok then
            set_widget_visibility(
                compare_widget,
                visibility_collapsed,
                "weaponComparison.bridgeFailed",
                true)
            pleasure_lib:debug_log(
                "weapon comparison native route failed"
                .. " reason=" .. tostring(route_error)
                .. " inventoryType=" .. tostring(weapon_type)
                .. " position=" .. tostring(weapon_position)
                .. " definition=" .. tostring(definition_name))
            -- A native bridge failure is not retried for the same hover.
            return false, false, route_error
        end

        if active_comparison.active ~= true
            or active_comparison.token ~= comparison_token
            or active_comparison.slot_key ~= source_slot_key
            or active_comparison.item_pos ~= source_item_pos
        then
            set_widget_visibility(
                compare_widget,
                visibility_collapsed,
                "weaponComparison.requestChanged",
                true)
            return false, false,
                "comparison request changed during bridge"
        end

        weapon_state.activate(
            compare_widget,
            source_inventory_main_key,
            source_slot_key,
            source_item_pos,
            weapon_type,
            definition_name)
        weapon_state.maintain_visibility("weaponComparison")
        -- UpdateToolTipOnSlot refreshes the base tooltip synchronously and
        -- hides this input for weapons because they have no wearable
        -- ItemSpec. Reassert the configured CTRL hint only after the native
        -- bridge has returned.
        force_weapon_comparison_hint(
            inventory_main,
            true,
            "weaponComparison.afterBridge")
        pleasure_lib:debug_log("weapon comparison active"
            .. " inventoryType=" .. tostring(weapon_type)
            .. " position=" .. tostring(weapon_position)
            .. " definition=" .. tostring(definition_name))
        return true, false, nil
    end

    local function invalidate_settle_timer()
        settle_timer_generation = settle_timer_generation + 1
        settle_pending = false
        settle_timer_due_at_ms = nil
    end

    local function clear_state()
        invalidate_settle_timer()
        active_comparison.active = false
        active_comparison.slot_key = nil
        active_comparison.item_pos = nil
        active_comparison.inventory_main = nil
        active_comparison.inventory_main_key = nil
        active_comparison.weapon_type = nil
        active_comparison.definition_name = nil
        active_comparison.resolution_attempt = 0
        active_comparison.comparison_attempt = 0
        active_comparison.settle_not_before_ms = nil
        hint_reassert_token = nil
        hint_reassert_inventory_main_key = nil
        hint_reassert_label = nil
    end

    local function end_comparison(label)
        if active_comparison.active ~= true then return false end

        active_comparison.token = active_comparison.token + 1
        weapon_state.end_comparison(
            tostring(label) .. ".weapon")
        clear_state()
        return true
    end

    local function is_active()
        return active_comparison.active == true
    end

    local function matches(slot, item_pos)
        if active_comparison.active ~= true then return false end
        return active_comparison.slot_key
                == object_instance_key(slot)
            and active_comparison.item_pos == item_pos
    end

    local schedule_settle = nil

    local function settle_active()
        if active_comparison.active ~= true then return false end

        local comparison_token = active_comparison.token
        local inventory_main = active_comparison.inventory_main
        local inventory_main_key =
            active_comparison.inventory_main_key
        local item_pos = active_comparison.item_pos
        if not is_valid(inventory_main)
            or object_instance_key(inventory_main)
                ~= inventory_main_key
        then
            end_comparison("comparison.inventoryUnavailable")
            return false
        end

        local weapon_type = active_comparison.weapon_type
        local definition_name =
            active_comparison.definition_name or ""
        if weapon_type == nil then
            local definition_resolved = false
            weapon_type, definition_name, definition_resolved =
                inventory_helpers.weapon_inventory_type_at_position(
                    inventory_main,
                    item_pos)
            if active_comparison.active ~= true
                or active_comparison.token ~= comparison_token
            then
                return false
            end

            if definition_resolved ~= true then
                local attempt =
                    active_comparison.resolution_attempt + 1
                local delay_ms =
                    WEAPON_COMPARISON_RETRY_DELAYS_MS[attempt]
                if delay_ms == nil then
                    pleasure_lib:debug_log(
                        "weapon classification readiness exhausted"
                        .. " itemPos=" .. tostring(item_pos)
                        .. " attempts=" .. tostring(
                            active_comparison.resolution_attempt))
                    end_comparison(
                        "comparison.classificationUnavailable")
                    return false
                end

                active_comparison.resolution_attempt = attempt
                pleasure_lib:debug_log(
                    "weapon classification waiting for inventory"
                    .. " itemPos=" .. tostring(item_pos)
                    .. " attempt=" .. tostring(attempt)
                    .. " delayMs=" .. tostring(delay_ms))
                return schedule_settle(delay_ms)
            end

            if weapon_type == nil then
                end_comparison("comparison.nativeItem")
                pleasure_lib:debug_log(
                    "comparison uses native item handling"
                    .. " definition=" .. tostring(definition_name))
                return false
            end

            active_comparison.weapon_type = weapon_type
            active_comparison.definition_name = definition_name
            active_comparison.resolution_attempt = 0
        end

        ensure_inventory_tooltip_activation(
            inventory_main, "comparison.settled")
        force_weapon_comparison_hint(
            inventory_main, true, "comparison.settled")
        if bool_property(
            inventory_main,
            "ShouldShowWearableCompare") ~= true
        then
            weapon_state.end_comparison("comparison.disabled")
            return true
        end

        local source_slot_key = active_comparison.slot_key
        local source_item_pos = active_comparison.item_pos
        local attempt = active_comparison.comparison_attempt
        local started, retry_ready, reason =
            begin_weapon_comparison(
                inventory_main,
                weapon_type,
                definition_name,
                source_slot_key,
                source_item_pos,
                comparison_token,
                attempt)
        if active_comparison.active ~= true
            or active_comparison.token ~= comparison_token
        then
            return false
        end
        if started then
            active_comparison.comparison_attempt = 0
            return true
        end
        if retry_ready ~= true then
            pleasure_lib:debug_log(
                "weapon comparison stopped for hover"
                .. " reason=" .. tostring(reason)
                .. " definition=" .. tostring(definition_name))
            return false
        end

        local next_attempt = attempt + 1
        local delay_ms =
            WEAPON_COMPARISON_RETRY_DELAYS_MS[next_attempt]
        if delay_ms == nil then
            pleasure_lib:debug_log(
                "weapon comparison readiness exhausted"
                .. " reason=" .. tostring(reason)
                .. " attempts=" .. tostring(attempt)
                .. " definition=" .. tostring(definition_name))
            end_comparison(
                "weaponComparison.readinessExhausted")
            return false
        end

        active_comparison.comparison_attempt = next_attempt
        pleasure_lib:debug_log(
            "weapon comparison waiting for readiness"
            .. " reason=" .. tostring(reason)
            .. " attempt=" .. tostring(next_attempt)
            .. " delayMs=" .. tostring(delay_ms)
            .. " definition=" .. tostring(definition_name))
        return schedule_settle(delay_ms)
    end

    schedule_settle = function(delay_ms)
        if active_comparison.active ~= true then return false end

        local inventory_main = active_comparison.inventory_main
        local now_ms = comparison_clock_ms(inventory_main)
        delay_ms = math.max(0, math.floor(tonumber(delay_ms)
            or weapon_comparison_hover_settle_ms(
                config.TooltipCooldownMs)))
        local timer_due_at_ms = nil
        if now_ms ~= nil then
            timer_due_at_ms = now_ms + delay_ms
        end

        -- Keep one effective wake-up. A later request can reuse the existing
        -- earlier timer; an earlier request supersedes it while the old
        -- callback becomes a generation-checked no-op.
        if settle_pending then
            if settle_timer_due_at_ms == nil
                or timer_due_at_ms == nil
                or settle_timer_due_at_ms <= timer_due_at_ms
            then
                return true
            end
        end

        settle_timer_generation = settle_timer_generation + 1
        local timer_generation = settle_timer_generation
        local scheduled_token = active_comparison.token
        local session_token = inventory_session_token
        settle_pending = true
        settle_timer_due_at_ms = timer_due_at_ms
        local scheduled = run_later(delay_ms, function()
            if timer_generation ~= settle_timer_generation then
                return
            end

            settle_pending = false
            settle_timer_due_at_ms = nil
            if active_comparison.active ~= true then return end

            local current_time_ms = comparison_clock_ms(
                active_comparison.inventory_main)
            local settle_not_before_ms = tonumber(
                active_comparison.settle_not_before_ms)
            if current_time_ms ~= nil
                and settle_not_before_ms ~= nil
                and current_time_ms < settle_not_before_ms
            then
                schedule_settle(
                    settle_not_before_ms - current_time_ms)
                return
            end

            if inventory_session_token ~= session_token
                or active_comparison.token ~= scheduled_token
            then
                local replacement_delay_ms = 0
                if current_time_ms == nil
                    or settle_not_before_ms == nil
                then
                    replacement_delay_ms =
                        weapon_comparison_hover_settle_ms(
                            config.TooltipCooldownMs)
                end
                schedule_settle(replacement_delay_ms)
                return
            end
            settle_active()
        end)
        if not scheduled
            and timer_generation == settle_timer_generation
        then
            settle_pending = false
            settle_timer_due_at_ms = nil
        end
        return scheduled
    end

    local function schedule_hover_settle()
        if active_comparison.active ~= true then return false end

        local delay_ms = weapon_comparison_hover_settle_ms(
            config.TooltipCooldownMs)
        local current_time_ms = comparison_clock_ms(
            active_comparison.inventory_main)
        active_comparison.settle_not_before_ms = nil
        if current_time_ms ~= nil then
            active_comparison.settle_not_before_ms =
                current_time_ms + delay_ms
        end
        pleasure_lib:debug_log(
            "scheduled weapon comparison hover settle"
            .. " delayMs=" .. tostring(delay_ms)
            .. " itemPos="
            .. tostring(active_comparison.item_pos))
        return schedule_settle(delay_ms)
    end

    local function hover(slot)
        if config.EnableComparisonTooltips ~= true then
            return false
        end

        local inventory_main =
            related_object_with_name(slot, "W_Inventory_Main")
        if not is_valid(inventory_main) then
            if active_comparison.active == true then
                end_comparison("comparison.inventoryMissing")
            end
            return false
        end
        if inventory_helpers.slot_has_hotbar_assignment(slot) then
            if active_comparison.active == true then
                end_comparison("comparison.hotbarAssigned")
            end
            force_weapon_comparison_hint(
                inventory_main,
                false,
                "comparison.hotbarAssigned")
            pleasure_lib:debug_log(
                "comparison skipped: item is assigned to hotbar"
                .. " slot=" .. full_name(slot))
            return false
        end

        -- The list slot is virtualized. Read everything needed while the
        -- hook owns a live object, then keep only scalar identity values.
        local slot_key = object_instance_key(slot)
        local item_pos = inventory_helpers.slot_item_pos(slot)
        if slot_key == ""
            or item_pos == nil
            or item_pos < 0
        then
            if active_comparison.active == true then
                end_comparison("comparison.snapshotInvalid")
            end
            return false
        end
        local inventory_main_key = object_instance_key(inventory_main)
        local weapon_type, definition_name, definition_resolved =
            inventory_helpers.weapon_inventory_type_at_position(
                inventory_main,
                item_pos)
        if definition_resolved == true
            and weapon_type == nil
        then
            if active_comparison.active == true then
                end_comparison("comparison.nativeItem")
            end
            pleasure_lib:debug_log(
                "comparison uses native item handling"
                .. " definition=" .. tostring(definition_name))
            return false
        end

        local same_target = active_comparison.active == true
            and active_comparison.slot_key == slot_key
            and active_comparison.item_pos == item_pos
            and active_comparison.inventory_main_key
                == inventory_main_key
            and active_comparison.weapon_type == weapon_type
            and active_comparison.definition_name == definition_name
        if same_target then
            -- A re-hover of the same virtual row is still a newer event.
            -- Advance the epoch so a queued unhover from its prior
            -- incarnation cannot clear the current comparison.
            active_comparison.token =
                active_comparison.token + 1
            if weapon_type ~= nil then
                ensure_inventory_tooltip_activation(
                    inventory_main, "comparison.rehover")
                force_weapon_comparison_hint(
                    inventory_main, true, "comparison.rehover")
                schedule_hint_reassert("comparison.rehover")
            end
            return schedule_hover_settle()
        end

        if weapon_state.is_active()
            and not weapon_state.source_matches(
                inventory_main_key,
                slot_key,
                item_pos,
                weapon_type,
                definition_name)
        then
            weapon_state.end_comparison(
                "weaponComparison.targetChanged")
        end

        active_comparison.active = true
        active_comparison.token = active_comparison.token + 1
        active_comparison.slot_key = slot_key
        active_comparison.item_pos = item_pos
        active_comparison.inventory_main = inventory_main
        active_comparison.inventory_main_key = inventory_main_key
        active_comparison.weapon_type = weapon_type
        active_comparison.definition_name = definition_name
        active_comparison.resolution_attempt = 0
        active_comparison.comparison_attempt = 0

        ensure_inventory_tooltip_activation(
            inventory_main, "comparison.snapshot")
        if weapon_type ~= nil then
            force_weapon_comparison_hint(
                inventory_main, true, "comparison.snapshot")
            schedule_hint_reassert("comparison.snapshot")
        end
        pleasure_lib:debug_log(
            "queued stable weapon comparison snapshot"
            .. " itemPos=" .. tostring(item_pos)
            .. " weaponType=" .. tostring(weapon_type)
            .. " definition=" .. tostring(definition_name))
        return schedule_hover_settle()
    end

    local function on_toggled(_hook_name, context)
        local inventory_main = pleasure_lib:unwrap(context)
        if not is_valid(inventory_main) then return nil end
        if active_comparison.active ~= true then return nil end
        if active_comparison.inventory_main_key
            ~= object_instance_key(inventory_main)
        then
            return nil
        end

        local enabled = bool_property(
            inventory_main,
            "ShouldShowWearableCompare") == true
        active_comparison.token =
            active_comparison.token + 1
        active_comparison.comparison_attempt = 0
        force_weapon_comparison_hint(
            inventory_main, true, "comparison.toggle")
        if enabled then
            -- Toggling does not restart the hover stability window. If it
            -- already elapsed, the native comparison starts on the next
            -- game-thread tick.
            schedule_settle(0)
        else
            weapon_state.end_comparison("comparison.toggleOff")
        end
        pleasure_lib:debug_log(
            "weapon comparison toggle handled"
            .. " enabled=" .. tostring(enabled)
            .. " itemPos="
            .. tostring(active_comparison.item_pos))
        return nil
    end

    local function unhover(slot)
        local item_pos = inventory_helpers.slot_item_pos(slot)
        if bool_property(slot, "Hovered") == true then
            pleasure_lib:debug_log(
                "ignored recycled inventory unhover"
                .. " slot=" .. full_name(slot)
                .. " itemPos=" .. tostring(item_pos))
            return false
        end
        if not matches(slot, item_pos) then
            pleasure_lib:debug_log(
                "ignored stale inventory unhover"
                .. " slot=" .. full_name(slot)
                .. " itemPos=" .. tostring(item_pos))
            return false
        end

        -- Invalidate settle/readiness work immediately. The delayed cleanup
        -- exists only to let a following hover claim a newer token.
        active_comparison.token =
            active_comparison.token + 1
        local token = active_comparison.token
        run_later(10, function()
            if active_comparison.active == true
                and active_comparison.token == token
            then
                end_comparison("comparison.end")
            end
        end)
        return true
    end

    local function advance_inventory_session()
        inventory_session_token = inventory_session_token + 1
    end

    local function reset(label)
        if active_comparison.active == true then
            end_comparison(tostring(label) .. ".inventory")
        elseif weapon_state.is_active() then
            weapon_state.end_comparison(
                tostring(label) .. ".weapon")
        end

        active_comparison.token = active_comparison.token + 1
        clear_state()
    end

    return {
        is_active = is_active,
        hover = hover,
        unhover = unhover,
        end_comparison = end_comparison,
        advance_inventory_session = advance_inventory_session,
        reset = reset,
        on_toggled = on_toggled,
        on_tooltip_updated = on_tooltip_updated,
    }
end

return InventoryComparison
