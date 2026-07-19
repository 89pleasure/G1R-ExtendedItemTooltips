local Widgets = {}

local WIDGET_VISIBILITY_COLLAPSED = 1
local WIDGET_VISIBILITY_SELF_HIT_TEST_INVISIBLE = 4
local WIDGET_SET_VISIBILITY_FUNCTION =
    "/Script/UMG.Widget:SetVisibility"

function Widgets.new(options)
    if type(options) ~= "table" then return nil end

    local pleasure_lib = options.pleasure_lib
    local runtime = options.runtime
    local config = options.config
    if type(pleasure_lib) ~= "table"
        or type(runtime) ~= "table"
        or type(config) ~= "table"
    then
        return nil
    end

    local is_valid = runtime.is_valid
    local full_name = runtime.full_name
    local object_instance_key = runtime.object_instance_key
    local property_value = runtime.property_value
    local set_property_value = runtime.set_property_value
    local bool_property = runtime.bool_property
    local widget_visibility_value = runtime.widget_visibility_value
    local widget_set_visibility_function = nil

    local function inventory_wearable_tooltip_widget(inventory_main)
        if not is_valid(inventory_main) then return nil end

        local widget = property_value(inventory_main,
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable")
        if is_valid(widget) then return widget end

        widget = property_value(inventory_main,
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Compare")
        if is_valid(widget) then return widget end

        return property_value(inventory_main,
            "W_Inventory_ItemTooltip_ItemToAssign")
    end

    local function inventory_new_item_tooltip_widget(inventory_main)
        if not is_valid(inventory_main) then return nil end
        return property_value(inventory_main,
            "W_Inventory_ItemTooltip_ItemToAssign")
    end

    local function inventory_main_tooltip_widget(inventory_main)
        if not is_valid(inventory_main) then return nil end
        local widget = property_value(inventory_main, "ItemTooltip")
        if is_valid(widget) then return widget end
        return inventory_new_item_tooltip_widget(inventory_main)
    end

    local function inventory_weapon_compare_widget(inventory_main)
        for _, property_name in ipairs({
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Compare",
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_1_Compare",
        }) do
            local widget = property_value(inventory_main, property_name)
            if is_valid(widget) then return widget end
        end
        return nil
    end

    local function set_widget_reference(
        owner, property_name, target, label)
        if not is_valid(owner) or not is_valid(target) then return false end

        local current = property_value(owner, property_name)
        if is_valid(current)
            and object_instance_key(current) == object_instance_key(target)
        then
            return true
        end

        local ok, result =
            set_property_value(owner, property_name, target)
        local after = property_value(owner, property_name)
        local linked = is_valid(after)
            and object_instance_key(after) == object_instance_key(target)
        if not linked and type(owner.SetPropertyValue) == "function" then
            local setter_ok, setter_result = pcall(function()
                return owner:SetPropertyValue(property_name, target)
            end)
            ok = setter_ok
            result = setter_result
            after = property_value(owner, property_name)
            linked = is_valid(after)
                and object_instance_key(after)
                    == object_instance_key(target)
        end

        if linked then
            pleasure_lib:debug_log("linked wearable tooltip widget"
                .. " label=" .. tostring(label)
                .. " property=" .. tostring(property_name)
                .. " result=" .. tostring(result))
            return true
        end

        pleasure_lib:debug_log("failed to link wearable tooltip widget"
            .. " label=" .. tostring(label)
            .. " property=" .. tostring(property_name)
            .. " ok=" .. tostring(ok)
            .. " result=" .. tostring(result))
        return false
    end

    local function ensure_wearable_tooltip_links(
        wearables_bar, inventory_main, label)
        if not is_valid(wearables_bar)
            or not is_valid(inventory_main)
        then
            return false
        end

        local linked = false
        linked = set_widget_reference(
            wearables_bar,
            "m_ToolTipEquippedItem",
            inventory_wearable_tooltip_widget(inventory_main),
            label) or linked
        linked = set_widget_reference(
            wearables_bar,
            "m_ToolTipNewItem",
            inventory_new_item_tooltip_widget(inventory_main),
            label) or linked
        return linked
    end

    local function add_unique_widget_entry(
        entries, seen, label, widget)
        widget = pleasure_lib:unwrap(widget)
        if not is_valid(widget) then return false end

        local key = full_name(widget)
        if key == "" then key = tostring(widget) end
        if seen[key] == true then return false end

        seen[key] = true
        table.insert(entries, {
            label = label,
            widget = widget,
        })
        return true
    end

    local function equipped_tooltip_widgets(
        wearables_bar, inventory_main)
        local entries = {}
        local seen = {}

        if is_valid(wearables_bar) then
            add_unique_widget_entry(
                entries,
                seen,
                "Wearables.m_ToolTipEquippedItem",
                property_value(
                    wearables_bar,
                    "m_ToolTipEquippedItem"))
        end
        add_unique_widget_entry(
            entries,
            seen,
            "InventoryMain.W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable",
            property_value(
                inventory_main,
                "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable"))

        if #entries == 0 then
            if is_valid(wearables_bar) then
                add_unique_widget_entry(
                    entries,
                    seen,
                    "Wearables.m_ToolTipNewItem",
                    property_value(wearables_bar, "m_ToolTipNewItem"))
            end
            add_unique_widget_entry(
                entries,
                seen,
                "InventoryMain.W_Inventory_ItemTooltip_ItemToAssign",
                property_value(
                    inventory_main,
                    "W_Inventory_ItemTooltip_ItemToAssign"))
        end

        return entries
    end

    local function enable_wearables_tooltips(wearables_bar)
        if not is_valid(wearables_bar) then return false end

        if bool_property(wearables_bar, "ShowToolTips") == true then
            return true
        end
        local ok =
            set_property_value(wearables_bar, "ShowToolTips", true)
        pleasure_lib:debug_log("enabled W_EquippedWearables.ShowToolTips"
            .. " ok=" .. tostring(ok))
        return ok == true
    end

    local function ensure_inventory_tooltip_activation(
        inventory_main, label)
        if config.ForceTooltipVisibility ~= true then return false end
        if not is_valid(inventory_main) then return false end

        if bool_property(inventory_main, "ActivateTooltip") == true then
            return true
        end
        local ok =
            set_property_value(inventory_main, "ActivateTooltip", true)
        pleasure_lib:debug_log("enabled InventoryMain.ActivateTooltip"
            .. " label=" .. tostring(label)
            .. " ok=" .. tostring(ok))
        return ok == true
    end

    local function set_wearable_compare_flag(
        inventory_main, value, label)
        if not is_valid(inventory_main) then return false end

        if bool_property(
            inventory_main,
            "ShouldShowWearableCompare") == value
        then
            return true
        end

        local ok = set_property_value(
            inventory_main,
            "ShouldShowWearableCompare",
            value == true)
        pleasure_lib:debug_log(
            "set InventoryMain.ShouldShowWearableCompare"
            .. " label=" .. tostring(label)
            .. " value=" .. tostring(value)
            .. " ok=" .. tostring(ok))
        return ok == true
    end

    local function set_widget_visibility(
        widget, visibility, label, ignore_config)
        if ignore_config ~= true
            and config.ForceTooltipVisibility ~= true
        then
            return false
        end
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
            pleasure_lib:debug_log("set tooltip widget visibility"
                .. " label=" .. tostring(label)
                .. " mode=property"
                .. " before=" .. tostring(before)
                .. " after=" .. tostring(after)
                .. " result=" .. tostring(property_result))
            return true
        end

        pleasure_lib:debug_log("failed to set tooltip widget visibility"
            .. " label=" .. tostring(label)
            .. " propertyOk=" .. tostring(property_ok)
            .. " propertyResult=" .. tostring(property_result)
            .. " before=" .. tostring(before)
            .. " after=" .. tostring(after))
        return false
    end

    local function set_live_widget_visibility(
        widget, visibility, label)
        if config.ForceTooltipVisibility ~= true then return false end
        if not is_valid(widget) then return false end

        if not is_valid(widget_set_visibility_function) then
            widget_set_visibility_function =
                pleasure_lib:find_object(
                    WIDGET_SET_VISIBILITY_FUNCTION)
        end

        local before = widget_visibility_value(widget)
        local mode = nil
        local call_result = nil
        if is_valid(widget_set_visibility_function) then
            local reflected_ok, reflected_result = pcall(function()
                return widget_set_visibility_function(
                    widget,
                    visibility)
            end)
            if reflected_ok then
                mode = "reflected"
                call_result = reflected_result
            end
        end

        if mode == nil then
            local method_ok, method_result = pcall(function()
                if type(widget.SetVisibility) ~= "function" then
                    return false
                end
                widget:SetVisibility(visibility)
                return true
            end)
            if method_ok and method_result == true then
                mode = "method"
                call_result = method_result
            end
        end

        -- A direct UPROPERTY write does not update the live Slate widget.
        -- Keep it only after both real UWidget setters failed.
        if mode == nil
            and set_widget_visibility(
                widget,
                visibility,
                label .. ".fallback")
        then
            mode = "property-fallback"
        end

        local after = widget_visibility_value(widget)
        pleasure_lib:debug_log(
            "updated live tooltip widget visibility"
            .. " label=" .. tostring(label)
            .. " mode=" .. tostring(mode)
            .. " before=" .. tostring(before)
            .. " after=" .. tostring(after)
            .. " result=" .. tostring(call_result))
        return mode ~= nil
            and tostring(after) == tostring(visibility)
    end

    local function force_weapon_comparison_hint(
        inventory_main, visible, label)
        local tooltip_widget =
            inventory_main_tooltip_widget(inventory_main)
        local hint_widget = property_value(
            tooltip_widget,
            "m_Input_ShowWearableComparisonTooltip")
        if not is_valid(hint_widget) then
            pleasure_lib:debug_log(
                "weapon comparison hint unavailable"
                .. " label=" .. tostring(label))
            return false
        end
        return set_live_widget_visibility(
            hint_widget,
            visible and WIDGET_VISIBILITY_SELF_HIT_TEST_INVISIBLE
                or WIDGET_VISIBILITY_COLLAPSED,
            tostring(label) .. ".comparisonHint")
    end

    return {
        visibility_collapsed = WIDGET_VISIBILITY_COLLAPSED,
        visibility_self_hit_test_invisible =
            WIDGET_VISIBILITY_SELF_HIT_TEST_INVISIBLE,
        inventory_main_tooltip_widget =
            inventory_main_tooltip_widget,
        inventory_weapon_compare_widget =
            inventory_weapon_compare_widget,
        set_widget_reference = set_widget_reference,
        ensure_wearable_tooltip_links =
            ensure_wearable_tooltip_links,
        equipped_tooltip_widgets = equipped_tooltip_widgets,
        enable_wearables_tooltips = enable_wearables_tooltips,
        ensure_inventory_tooltip_activation =
            ensure_inventory_tooltip_activation,
        set_wearable_compare_flag = set_wearable_compare_flag,
        set_widget_visibility = set_widget_visibility,
        force_weapon_comparison_hint =
            force_weapon_comparison_hint,
    }
end

return Widgets
