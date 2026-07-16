local MOD = "ExtendedItemTooltips"
local pleasureLib = require("pleasure_lib_loader").new(MOD)
if type(pleasureLib) ~= "table" then return end

local CONFIG_FILE_NAME = "ExtendedItemTooltips.ini"
local VERSION = "0.19.0"

_G.__EXTENDED_ITEM_TOOLTIPS_GENERATION =
    (_G.__EXTENDED_ITEM_TOOLTIPS_GENERATION or 0) + 1
local SCRIPT_GENERATION = _G.__EXTENDED_ITEM_TOOLTIPS_GENERATION

local function generation_is_current()
    return _G.__EXTENDED_ITEM_TOOLTIPS_GENERATION == SCRIPT_GENERATION
end

local DEFAULT_CONFIG = {
    Enabled = true,
    Debug = false,
    TooltipCooldownMs = 40,
    ForceTooltipVisibility = true,
    EnableComparisonTooltips = true,
    ComparisonDefaultEnabled = false,
}

local UI_OBJECT_NOTIFY_CLASSES = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Main.W_Inventory_Main_C",
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Slot.W_Inventory_Slot_C",
}

local SLOT_HOVER_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Slot.W_Inventory_Slot_C:OnHovered",
}

local SLOT_UNHOVER_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Slot.W_Inventory_Slot_C:OnUnhovered",
}

local COMPARISON_TOGGLE_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Main.W_Inventory_Main_C:DoToggleWearableComparisonTooltip",
}

local INVENTORY_SHOWN_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Main.W_Inventory_Main_C:OnShown",
}

local INVENTORY_TYPE_MAIN_CONTAINER = 1
local INVENTORY_TYPE_MELEE_SLOT = 3
local INVENTORY_TYPE_RANGED_SLOT = 4
local QUICK_SLOT_UPDATE_BASE_FUNCTION =
    "/Script/G1R.QuickSlotBase:UpdateToolTipBaseItem"
local WEARABLE_COMPARISON_SPEC_TEXT = "Item.Property.Wereable"
local WEARABLE_COMPARISON_SOURCE_PATHS = {
    "/Script/Angelscript.Default__ItAt_Ring_Enlight",
    "/Script/Angelscript.Default__ItAt_Amulet_Life",
    "/Script/Angelscript.Default__NH_Armor",
    "/Script/Angelscript.Default__Grd_Armor",
}

local INVENTORY_MAIN_PATH_NEEDLES = {
    "W_Inventory_Main",
    "InventoryMain",
}

local config = {}
local registered_hooks = {}
local hook_retry_logged = {}
local handled_ui_notification_classes = {}
local cached_inventory_main = nil
local cached_wearables_bar = nil
local cached_hotbar = nil
local wearable_comparison_spec = nil
local wearable_spec_wait_logged = false
local last_hover_at = {}
local active_equipped_hover = {
    active = false,
    token = 0,
    slot = nil,
    slot_key = nil,
    item_pos = nil,
    inventory_main = nil,
    wearables_bar = nil,
    should_show_wearable_compare = nil,
}
local active_inventory_comparison = {
    active = false,
    token = 0,
    slot = nil,
    slot_key = nil,
    item_pos = nil,
    inventory_main = nil,
}
local active_weapon_comparison = {
    active = false,
    token = 0,
    slot_started = false,
    hotbar = nil,
    weapon_slot = nil,
    weapon_position = nil,
    compare_widget = nil,
    previous_show_tooltips = nil,
    previous_base_widget = nil,
    previous_slot_widget = nil,
}
local refresh_inventory_main_from_slot = nil

local function merge_list(defaults, override)
    local parsed = pleasureLib:split_list(override)
    if #parsed > 0 then return parsed end
    return pleasureLib:copy_array(defaults)
end

local function config_candidate_paths()
    local paths = {}
    local dir = pleasureLib:script_directory()
    if dir then
        table.insert(paths, dir .. "..\\" .. CONFIG_FILE_NAME)
        table.insert(paths, dir .. CONFIG_FILE_NAME)
    end
    table.insert(paths, "Mods\\ExtendedItemTooltips\\" .. CONFIG_FILE_NAME)
    table.insert(paths, "ue4ss\\Mods\\ExtendedItemTooltips\\" .. CONFIG_FILE_NAME)
    table.insert(paths, CONFIG_FILE_NAME)
    return paths
end

local function load_config()
    config = {
        Enabled = DEFAULT_CONFIG.Enabled,
        Debug = DEFAULT_CONFIG.Debug,
        TooltipCooldownMs = DEFAULT_CONFIG.TooltipCooldownMs,
        ForceTooltipVisibility = DEFAULT_CONFIG.ForceTooltipVisibility,
        EnableComparisonTooltips = DEFAULT_CONFIG.EnableComparisonTooltips,
        ComparisonDefaultEnabled = DEFAULT_CONFIG.ComparisonDefaultEnabled,
        SlotHoverHooks = SLOT_HOVER_HOOKS,
        SlotUnhoverHooks = SLOT_UNHOVER_HOOKS,
    }

    for _, path in ipairs(config_candidate_paths()) do
        local content = pleasureLib:read_text_file(path)
        if content ~= nil then
            local ini = pleasureLib:parse_ini(content)
            config.Enabled = pleasureLib:parse_bool(ini.ENABLED, config.Enabled)
            config.Debug = pleasureLib:parse_bool(ini.DEBUG, config.Debug)
            config.ForceTooltipVisibility = pleasureLib:parse_bool(
                ini.FORCETOOLTIPVISIBILITY, config.ForceTooltipVisibility)
            config.EnableComparisonTooltips = pleasureLib:parse_bool(
                ini.ENABLECOMPARISONTOOLTIPS, config.EnableComparisonTooltips)
            config.ComparisonDefaultEnabled = pleasureLib:parse_bool(
                ini.COMPARISONDEFAULTENABLED,
                config.ComparisonDefaultEnabled)
            config.TooltipCooldownMs =
                tonumber(ini.TOOLTIPCOOLDOWNMS) or config.TooltipCooldownMs
            config.SlotHoverHooks = merge_list(
                SLOT_HOVER_HOOKS, ini.SLOTHOVERHOOKS)
            config.SlotUnhoverHooks = merge_list(
                SLOT_UNHOVER_HOOKS, ini.SLOTUNHOVERHOOKS)

            pleasureLib:set_debug(config.Debug)
            config.ConfigPath = path
            pleasureLib:log("Loaded config from " .. tostring(path)
                .. ": Enabled=" .. tostring(config.Enabled)
                .. " Debug=" .. tostring(config.Debug)
                .. " ForceTooltipVisibility=" .. tostring(config.ForceTooltipVisibility)
                .. " EnableComparisonTooltips="
                .. tostring(config.EnableComparisonTooltips)
                .. " ComparisonDefaultEnabled="
                .. tostring(config.ComparisonDefaultEnabled)
                .. " TooltipCooldownMs=" .. tostring(config.TooltipCooldownMs))
            return
        end
    end

    pleasureLib:set_debug(config.Debug)
    pleasureLib:log("Config not found; using defaults.")
end

local COMPARISON_DEFAULT_SETTING_TRANSLATIONS = {
            en = {
                name = "Show comparisons by default",
                description = "Automatically shows compatible item comparisons when the inventory is opened. Press Left Ctrl to toggle them temporarily.",
            },
            de = {
                name = "Vergleiche standardmäßig anzeigen",
                description = "Zeigt beim Öffnen des Inventars automatisch passende Gegenstandsvergleiche an. Mit der linken Strg-Taste können sie vorübergehend umgeschaltet werden.",
            },
            fr = {
                name = "Afficher les comparaisons par défaut",
                description = "Affiche automatiquement les comparaisons d'objets compatibles à l'ouverture de l'inventaire. Appuyez sur Ctrl gauche pour les activer ou les désactiver temporairement.",
            },
            it = {
                name = "Mostra i confronti per impostazione predefinita",
                description = "Mostra automaticamente i confronti tra oggetti compatibili quando apri l'inventario. Premi Ctrl sinistro per attivarli o disattivarli temporaneamente.",
            },
            es = {
                name = "Mostrar comparaciones de forma predeterminada",
                description = "Muestra automáticamente comparaciones de objetos compatibles al abrir el inventario. Pulsa Ctrl izquierdo para activarlas o desactivarlas temporalmente.",
            },
            pl = {
                name = "Domyślnie pokazuj porównania",
                description = "Automatycznie pokazuje porównania zgodnych przedmiotów po otwarciu ekwipunku. Naciśnij lewy Ctrl, aby tymczasowo je przełączyć.",
            },
            ru = {
                name = "Показывать сравнения по умолчанию",
                description = "Автоматически показывает сравнение подходящих предметов при открытии инвентаря. Нажмите левый Ctrl, чтобы временно включить или выключить сравнение.",
            },
            ["zh-hans"] = {
                name = "默认显示对比",
                description = "打开物品栏时自动显示兼容物品的对比。按左 Ctrl 可临时开启或关闭对比。",
            },
            ["zh-cn"] = {
                name = "默认显示对比",
                description = "打开物品栏时自动显示兼容物品的对比。按左 Ctrl 可临时开启或关闭对比。",
            },
            ja = {
                name = "比較をデフォルトで表示",
                description = "インベントリを開いたときに、対応するアイテムの比較を自動的に表示します。左Ctrlキーで一時的に切り替えられます。",
            },
            ["pt-br"] = {
                name = "Mostrar comparações por padrão",
                description = "Mostra automaticamente comparações de itens compatíveis ao abrir o inventário. Pressione Ctrl esquerdo para ativá-las ou desativá-las temporariamente.",
            },
}

local function is_valid(obj)
    if pleasureLib:is_valid(obj) then return true end

    -- Preserve the stable mod's more permissive fallback for a few UE4SS
    -- wrappers whose IsValid result is unavailable but GetFullName still is.
    return pleasureLib:try(function()
        if type(obj.GetFullName) ~= "function" then return false end
        return obj:GetFullName() ~= nil
    end) == true
end

local function full_name(obj)
    local name = pleasureLib:full_name(obj)
    if name ~= "" or not is_valid(obj) then return name end
    return pleasureLib:try(function() return obj:GetFullName() end) or ""
end

local function object_class_token(obj)
    local text = full_name(obj)
    return text:match("^([^%s]+)") or ""
end

local function object_short_name(obj)
    local name = pleasureLib:try(function()
        if type(obj.GetName) == "function" then return obj:GetName() end
        return nil
    end)
    if name ~= nil then return tostring(name) end

    local text = full_name(obj)
    local path = text:match("%s(.+)$") or text
    return path:match("([^%.:]+)$") or ""
end

local function contains(haystack, needle)
    return string.find(pleasureLib:lower(haystack), pleasureLib:lower(needle), 1, true) ~= nil
end

local function object_named_like(object, needle)
    local text = object_class_token(object) .. " " .. object_short_name(object)
    return contains(text, needle)
end

local function object_is_inventory_main(object)
    for _, needle in ipairs(INVENTORY_MAIN_PATH_NEEDLES) do
        if object_named_like(object, needle) then return true end
    end
    return false
end

local function property_value(object, property_name)
    if not is_valid(object) then return nil end
    local value = pleasureLib:try(function()
        if type(object.GetPropertyValue) == "function" then
            return object:GetPropertyValue(property_name)
        end
        return nil
    end)
    if value ~= nil then return pleasureLib:unwrap(value) end

    value = pleasureLib:try(function() return object[property_name] end)
    return pleasureLib:unwrap(value)
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
    if setter_ok then return true, setter_result or "SetPropertyValue" end

    return false, setter_result
end

local function number_property(object, property_name)
    local value = pleasureLib:unwrap(property_value(object, property_name))
    local number = tonumber(value)
    if number ~= nil then return number end
    return nil
end

local function bool_property(object, property_name)
    local value = pleasureLib:unwrap(property_value(object, property_name))
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end

    local text = pleasureLib:lower(value)
    if text == "true" or text == "1" then return true end
    if text == "false" or text == "0" then return false end
    return nil
end

local function widget_visibility_value(widget)
    local value = pleasureLib:unwrap(property_value(widget, "Visibility"))
    if value == nil then return "nil" end
    return tostring(value)
end

local function ufunction_loaded(path)
    return is_valid(pleasureLib:find_object(path))
end

local function gameplay_tag_candidates(tag_name)
    local candidates = {}
    local fname = pleasureLib:try(function()
        return FName(tag_name)
    end)
    if fname == nil then return candidates end

    local function add(builder)
        local tag = pleasureLib:try(builder)
        if tag ~= nil then table.insert(candidates, tag) end
    end

    -- Match the construction order proven by QuickBites in this game build.
    -- The field is assigned only; it is never read or converted to a string.
    add(function()
        if type(FGameplayTag) ~= "function" then return nil end
        local tag = FGameplayTag()
        tag.TagName = fname
        return tag
    end)
    add(function()
        if type(FGameplayTag) ~= "function" then return nil end
        return FGameplayTag(fname)
    end)
    add(function()
        if type(FGameplayTag) ~= "function" then return nil end
        return FGameplayTag(tag_name)
    end)

    -- UE4SS also accepts a plain struct-shaped Lua table for small reflected
    -- FGameplayTag parameters. QuickBites needs this fallback on some builds.
    table.insert(candidates, { TagName = fname })

    return candidates
end

local function item_has_spec(item, tag)
    if not is_valid(item) or tag == nil then return false end

    local exact = pleasureLib:try(function()
        return pleasureLib:unwrap(item:HasItemSpecExactly(tag))
    end)
    if exact == true then return true end

    return pleasureLib:try(function()
        return pleasureLib:unwrap(item:HasItemSpec(tag))
    end) == true
end

local function resolve_wearable_comparison_spec()
    if wearable_comparison_spec ~= nil then
        return wearable_comparison_spec
    end

    local candidates = gameplay_tag_candidates(WEARABLE_COMPARISON_SPEC_TEXT)
    local valid_sources = 0
    for candidate_index, tag in ipairs(candidates)
    do
        for _, path in ipairs(WEARABLE_COMPARISON_SOURCE_PATHS) do
            local source_item = pleasureLib:find_object(path)
            if is_valid(source_item) then
                valid_sources = valid_sources + 1
                if item_has_spec(source_item, tag) then
                    wearable_comparison_spec = tag
                    wearable_spec_wait_logged = false
                    pleasureLib:debug_log("resolved native wearable comparison spec"
                        .. " source=" .. full_name(source_item)
                        .. " candidate=" .. tostring(candidate_index))
                    return tag
                end
            end
        end
    end

    if wearable_spec_wait_logged ~= true then
        wearable_spec_wait_logged = true
        pleasureLib:debug_log("native wearable comparison spec unresolved"
            .. " candidates=" .. tostring(#candidates)
            .. " validSourceChecks=" .. tostring(valid_sources))
    end
    return nil
end

local function related_object_with_name(start_object, needle)
    local current = pleasureLib:unwrap(start_object)
    local depth = 0
    while is_valid(current) and depth < 14 do
        if object_named_like(current, needle) then return current end

        local next_object = pleasureLib:try(function()
            if type(current.GetOuter) == "function" then return current:GetOuter() end
            return nil
        end)
        if not is_valid(next_object) and type(current.GetParent) == "function" then
            next_object = pleasureLib:try(function() return current:GetParent() end)
        end
        current = pleasureLib:unwrap(next_object)
        depth = depth + 1
    end
    return nil
end

local function tooltip_is_valid(info)
    if info == nil then return false end
    local valid = pleasureLib:unwrap(property_value(info, "IsValid"))
    if valid == true or valid == 1 then return true end
    if valid == false or valid == 0 then return false end
    return true
end

local function call_delegate(delegate, ...)
    delegate = pleasureLib:unwrap(delegate)
    if delegate == nil then return false, "delegate missing" end

    local method_names = { "Broadcast", "Execute", "Call" }
    local args = { ... }
    args.n = select("#", ...)
    local unpack_args = table.unpack or unpack
    if not unpack_args then return false, "unpack unavailable" end

    for _, name in ipairs(method_names) do
        local method = pleasureLib:try(function() return delegate[name] end)
        if type(method) == "function" then
            local ok, result = pcall(function()
                return method(delegate, unpack_args(args, 1, args.n))
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
    -- Keep the established two-stage scheduling behavior while delegating
    -- the generic delayed callback to PleasureLib. Generation guards remain
    -- mod-specific so callbacks from an old hotreload cannot touch new UI.
    return pleasureLib:delay(ms, function()
        if not generation_is_current() then return end
        if type(ExecuteInGameThread) == "function" then
            ExecuteInGameThread(function()
                if generation_is_current() then fn() end
            end)
        else
            fn()
        end
    end)
end

local function inventory_wearable_tooltip_widget(inventory_main)
    if not is_valid(inventory_main) then return nil end

    local widget = property_value(inventory_main,
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable")
    if is_valid(widget) then return widget end

    widget = property_value(inventory_main,
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Compare")
    if is_valid(widget) then return widget end

    return property_value(inventory_main, "W_Inventory_ItemTooltip_ItemToAssign")
end

local function inventory_new_item_tooltip_widget(inventory_main)
    if not is_valid(inventory_main) then return nil end
    return property_value(inventory_main, "W_Inventory_ItemTooltip_ItemToAssign")
end

local function inventory_main_tooltip_widget(inventory_main)
    if not is_valid(inventory_main) then return nil end
    local widget = property_value(inventory_main, "ItemTooltip")
    if is_valid(widget) then return widget end
    return inventory_new_item_tooltip_widget(inventory_main)
end

local function set_widget_reference(owner, property_name, target, label)
    if not is_valid(owner) or not is_valid(target) then return false end

    local current = property_value(owner, property_name)
    if is_valid(current) and full_name(current) == full_name(target) then
        return true
    end

    local ok, result = set_property_value(owner, property_name, target)
    local after = property_value(owner, property_name)
    local linked = is_valid(after) and full_name(after) == full_name(target)
    if not linked and type(owner.SetPropertyValue) == "function" then
        local setter_ok, setter_result = pcall(function()
            return owner:SetPropertyValue(property_name, target)
        end)
        ok = setter_ok
        result = setter_result
        after = property_value(owner, property_name)
        linked = is_valid(after) and full_name(after) == full_name(target)
    end

    if linked then
        pleasureLib:debug_log("linked wearable tooltip widget"
            .. " label=" .. tostring(label)
            .. " property=" .. tostring(property_name)
            .. " result=" .. tostring(result))
        return true
    end

    pleasureLib:debug_log("failed to link wearable tooltip widget"
        .. " label=" .. tostring(label)
        .. " property=" .. tostring(property_name)
        .. " ok=" .. tostring(ok)
        .. " result=" .. tostring(result))
    return false
end

local function ensure_wearable_tooltip_links(wearables_bar, inventory_main, label)
    if not is_valid(wearables_bar) or not is_valid(inventory_main) then return false end

    local linked = false
    linked = set_widget_reference(wearables_bar, "m_ToolTipEquippedItem",
        inventory_wearable_tooltip_widget(inventory_main), label) or linked
    linked = set_widget_reference(wearables_bar, "m_ToolTipNewItem",
        inventory_new_item_tooltip_widget(inventory_main), label) or linked
    return linked
end

local function add_unique_widget_entry(entries, seen, label, widget)
    widget = pleasureLib:unwrap(widget)
    if not is_valid(widget) then return false end

    local key = full_name(widget)
    if key == "" then key = tostring(widget) end
    if seen[key] == true then return false end

    seen[key] = true
    table.insert(entries, { label = label, widget = widget })
    return true
end

local function equipped_tooltip_widgets(wearables_bar, inventory_main)
    local entries = {}
    local seen = {}

    if is_valid(wearables_bar) then
        add_unique_widget_entry(entries, seen, "Wearables.m_ToolTipEquippedItem",
            property_value(wearables_bar, "m_ToolTipEquippedItem"))
    end
    add_unique_widget_entry(entries, seen,
        "InventoryMain.W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable",
        property_value(inventory_main,
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable"))

    if #entries == 0 then
        if is_valid(wearables_bar) then
            add_unique_widget_entry(entries, seen, "Wearables.m_ToolTipNewItem",
                property_value(wearables_bar, "m_ToolTipNewItem"))
        end
        add_unique_widget_entry(entries, seen,
            "InventoryMain.W_Inventory_ItemTooltip_ItemToAssign",
            property_value(inventory_main, "W_Inventory_ItemTooltip_ItemToAssign"))
    end

    return entries
end

local function wearables_bar_from(slot_or_inventory)
    local direct = pleasureLib:unwrap(property_value(slot_or_inventory, "EquippedWearables"))
    if is_valid(direct) then
        cached_wearables_bar = direct
        return direct
    end

    local related = related_object_with_name(slot_or_inventory, "W_EquippedWearables")
    if is_valid(related) then
        cached_wearables_bar = related
        return related
    end

    local inventory_main = refresh_inventory_main_from_slot(slot_or_inventory)
    direct = pleasureLib:unwrap(property_value(inventory_main, "EquippedWearables"))
    if is_valid(direct) then
        cached_wearables_bar = direct
        return direct
    end

    if is_valid(cached_wearables_bar) then return cached_wearables_bar end
    return nil
end

local function enable_wearables_tooltips(wearables_bar)
    if not is_valid(wearables_bar) then return false end

    if bool_property(wearables_bar, "ShowToolTips") == true then return true end
    local ok = set_property_value(wearables_bar, "ShowToolTips", true)
    pleasureLib:debug_log("enabled W_EquippedWearables.ShowToolTips"
        .. " ok=" .. tostring(ok))
    return ok == true
end

local function ensure_inventory_tooltip_activation(inventory_main, label)
    if config.ForceTooltipVisibility ~= true then return false end
    if not is_valid(inventory_main) then return false end

    if bool_property(inventory_main, "ActivateTooltip") == true then return true end
    local ok = set_property_value(inventory_main, "ActivateTooltip", true)
    pleasureLib:debug_log("enabled InventoryMain.ActivateTooltip"
        .. " label=" .. tostring(label)
        .. " ok=" .. tostring(ok))
    return ok == true
end

local function set_wearable_compare_flag(inventory_main, value, label)
    if not is_valid(inventory_main) then return false end

    if bool_property(inventory_main, "ShouldShowWearableCompare") == value then
        return true
    end

    local ok = set_property_value(inventory_main,
        "ShouldShowWearableCompare", value == true)
    pleasureLib:debug_log("set InventoryMain.ShouldShowWearableCompare"
        .. " label=" .. tostring(label)
        .. " value=" .. tostring(value)
        .. " ok=" .. tostring(ok))
    return ok == true
end

local function on_inventory_shown(_hook_name, context)
    local inventory_main = pleasureLib:unwrap(context)
    if not is_valid(inventory_main) then return nil end

    set_wearable_compare_flag(inventory_main,
        config.EnableComparisonTooltips == true
            and config.ComparisonDefaultEnabled == true,
        "inventory.shown.default")
    return nil
end

local function set_widget_visibility(widget, visibility, label)
    if config.ForceTooltipVisibility ~= true then return false end
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
        pleasureLib:debug_log("set tooltip widget visibility"
            .. " label=" .. tostring(label)
            .. " mode=property"
            .. " before=" .. tostring(before)
            .. " after=" .. tostring(after)
            .. " result=" .. tostring(property_result))
        return true
    end

    pleasureLib:debug_log("failed to set tooltip widget visibility"
        .. " label=" .. tostring(label)
        .. " propertyOk=" .. tostring(property_ok)
        .. " propertyResult=" .. tostring(property_result)
        .. " before=" .. tostring(before)
        .. " after=" .. tostring(after))
    return false
end

local function force_weapon_comparison_hint(inventory_main, visible, label)
    local tooltip_widget = inventory_main_tooltip_widget(inventory_main)
    local hint_widget = property_value(tooltip_widget,
        "m_Input_ShowWearableComparisonTooltip")
    if not is_valid(hint_widget) then
        pleasureLib:debug_log("weapon comparison hint unavailable"
            .. " label=" .. tostring(label))
        return false
    end
    return set_widget_visibility(hint_widget, visible and 4 or 1,
        tostring(label) .. ".comparisonHint")
end

local function maintain_weapon_comparison_hint(inventory_main, slot, label)
    local token = active_inventory_comparison.token
    force_weapon_comparison_hint(inventory_main, true,
        tostring(label) .. ".immediate")
    run_later(10, function()
        if active_inventory_comparison.active == true
            and active_inventory_comparison.token == token
            and active_inventory_comparison.slot == slot
            and is_valid(slot)
            and bool_property(slot, "Hovered") == true
        then
            force_weapon_comparison_hint(inventory_main, true,
                tostring(label) .. ".afterHover")
        end
    end)
end

local function force_equipped_tooltip_widgets(wearables_bar, inventory_main, label, token)
    if config.ForceTooltipVisibility ~= true then return false end
    if active_equipped_hover.active ~= true then return false end
    if token ~= nil and active_equipped_hover.token ~= token then return false end

    inventory_main = pleasureLib:unwrap(inventory_main)
    wearables_bar = pleasureLib:unwrap(wearables_bar)
    if not is_valid(inventory_main) then
        inventory_main = active_equipped_hover.inventory_main
    end
    if not is_valid(wearables_bar) then
        wearables_bar = active_equipped_hover.wearables_bar
    end

    ensure_wearable_tooltip_links(wearables_bar, inventory_main, label)
    local widgets = equipped_tooltip_widgets(wearables_bar, inventory_main)
    if #widgets == 0 then return false end

    local forced = false
    for _, entry in ipairs(widgets) do
        forced = set_widget_visibility(entry.widget, 4,
            tostring(label) .. "." .. tostring(entry.label)) or forced
    end
    return forced
end

local function schedule_equipped_tooltip_force(wearables_bar, inventory_main, label)
    if config.ForceTooltipVisibility ~= true then return false end
    if active_equipped_hover.active ~= true then return false end

    local token = active_equipped_hover.token
    force_equipped_tooltip_widgets(wearables_bar, inventory_main,
        tostring(label) .. ".immediate", token)
    run_later(20, function()
        force_equipped_tooltip_widgets(wearables_bar, inventory_main,
            tostring(label) .. ".delay20", token)
    end)
    run_later(80, function()
        force_equipped_tooltip_widgets(wearables_bar, inventory_main,
            tostring(label) .. ".delay80", token)
    end)
    run_later(160, function()
        force_equipped_tooltip_widgets(wearables_bar, inventory_main,
            tostring(label) .. ".delay160", token)
    end)
    run_later(320, function()
        force_equipped_tooltip_widgets(wearables_bar, inventory_main,
            tostring(label) .. ".delay320", token)
    end)
    return true
end

local function hide_equipped_tooltip_widgets(wearables_bar, inventory_main, label)
    if config.ForceTooltipVisibility ~= true then return false end

    ensure_wearable_tooltip_links(wearables_bar, inventory_main, label)
    local hidden = false
    for _, entry in ipairs(equipped_tooltip_widgets(wearables_bar, inventory_main)) do
        hidden = set_widget_visibility(entry.widget, 1,
            tostring(label) .. "." .. tostring(entry.label)) or hidden
    end
    return hidden
end

local function slot_item_pos(slot)
    local item_pos = number_property(slot, "ItemPos")
    if item_pos == nil then
        item_pos = number_property(property_value(slot, "Inventory Slot Data"), "m_Pos")
    end
    return item_pos
end

local function slot_inventory_type(slot)
    return number_property(property_value(slot, "Inventory Slot Data"),
        "m_InventoryType")
end

local function slot_is_main_inventory(slot)
    return slot_inventory_type(slot) == INVENTORY_TYPE_MAIN_CONTAINER
end

local function slot_has_hotbar_assignment(slot)
    -- W_Inventory_Slot sets this native flag for the numbered badge shown on
    -- items assigned to the hotbar. Those items are already the equipped
    -- comparison source and must not start a comparison with themselves.
    return bool_property(slot, "ShowingHotkey") == true
end

local function array_length(value)
    value = pleasureLib:unwrap(value)
    if value == nil then return nil end

    local ok, length = pcall(function() return #value end)
    if ok and type(length) == "number" then return length end

    for _, method_name in ipairs({ "Num", "GetArrayNum" }) do
        local method = pleasureLib:try(function() return value[method_name] end)
        if type(method) == "function" then
            length = pleasureLib:try(function() return pleasureLib:unwrap(method(value)) end)
            length = tonumber(length)
            if length ~= nil then return length end
        end
    end
    return nil
end

local function first_hotbar_weapon_position(hotbar, inventory_type)
    local slots = property_value(hotbar, "m_SlotsData")
    local slot_count = array_length(slots)
    if slot_count == nil or slot_count <= 0 then return nil, nil end

    local inventory_base = property_value(hotbar, "m_InventoryBase")
    if not is_valid(inventory_base) then return nil, nil end
    local valid_fn = pleasureLib:try(function()
        return inventory_base["IsItemValidByPos"]
    end)
    local definition_fn = pleasureLib:try(function()
        return inventory_base["GetBaseConfigByPos"]
    end)
    if valid_fn == nil or definition_fn == nil then return nil, nil end

    for position = 0, slot_count - 1 do
        local valid_ok, item_valid = pcall(function()
            return valid_fn(inventory_base, position)
        end)
        if valid_ok and pleasureLib:unwrap(item_valid) == true then
            local definition_ok, definition = pcall(function()
                return definition_fn(inventory_base, position)
            end)
            definition = pleasureLib:unwrap(definition)
            if definition_ok and is_valid(definition) then
                local matches = false
                if inventory_type == INVENTORY_TYPE_RANGED_SLOT then
                    matches = pleasureLib:try(function()
                        return definition:IsA(
                            "/Script/G1R.WeaponRangedDefinition")
                    end) == true or pleasureLib:try(function()
                        return definition:IsA(
                            "/Script/G1R.WeaponArcheryDefinition")
                    end) == true
                elseif inventory_type == INVENTORY_TYPE_MELEE_SLOT then
                    matches = pleasureLib:try(function()
                        return definition:IsA(
                            "/Script/G1R.WeaponMeleeDefinition")
                    end) == true
                end
                pleasureLib:debug_log("inspected hotbar item definition"
                    .. " position=" .. tostring(position)
                    .. " definition=" .. full_name(definition)
                    .. " matches=" .. tostring(matches))
                if matches then return position, definition end
            end
        end
    end

    return nil, nil
end

refresh_inventory_main_from_slot = function(slot)
    local related = related_object_with_name(slot, "W_Inventory_Main")
    if is_valid(related) then
        cached_inventory_main = related
        return related
    end

    local parent = pleasureLib:try(function()
        if type(slot.GetParent) == "function" then return slot:GetParent() end
        return nil
    end)
    local depth = 0
    while is_valid(parent) and depth < 10 do
        if object_is_inventory_main(parent) then
            cached_inventory_main = parent
            return parent
        end
        local current = parent
        parent = pleasureLib:try(function()
            if type(current.GetParent) == "function" then return current:GetParent() end
            return nil
        end)
        depth = depth + 1
    end

    return cached_inventory_main
end

local function hover_allowed(slot)
    local key = full_name(slot)
    if key == "" then return true end

    local now = math.floor(os.clock() * 1000)
    local previous = last_hover_at[key] or -1000000
    if now - previous < math.max(0, tonumber(config.TooltipCooldownMs) or 0) then
        return false
    end
    last_hover_at[key] = now
    return true
end

local function begin_equipped_hover(slot, inventory_main, wearables_bar, item_pos)
    local previous_compare = active_equipped_hover.should_show_wearable_compare
    active_equipped_hover.active = true
    active_equipped_hover.token = active_equipped_hover.token + 1
    active_equipped_hover.slot = slot
    active_equipped_hover.slot_key = full_name(slot)
    active_equipped_hover.item_pos = item_pos
    active_equipped_hover.inventory_main = inventory_main
    active_equipped_hover.wearables_bar = wearables_bar
    if previous_compare ~= nil then
        active_equipped_hover.should_show_wearable_compare = previous_compare
    else
        active_equipped_hover.should_show_wearable_compare =
            bool_property(inventory_main, "ShouldShowWearableCompare")
    end

    ensure_inventory_tooltip_activation(inventory_main, "hover.begin")
    set_wearable_compare_flag(inventory_main, true, "hover.begin")
    ensure_wearable_tooltip_links(wearables_bar, inventory_main, "hover.begin")
end

local function end_equipped_hover(inventory_main)
    active_equipped_hover.active = false
    active_equipped_hover.token = active_equipped_hover.token + 1
    active_equipped_hover.slot = nil
    active_equipped_hover.slot_key = nil
    active_equipped_hover.item_pos = nil
    active_equipped_hover.inventory_main = nil
    active_equipped_hover.wearables_bar = nil

    local previous_compare = active_equipped_hover.should_show_wearable_compare
    active_equipped_hover.should_show_wearable_compare = nil
    if previous_compare ~= nil then
        set_wearable_compare_flag(inventory_main, previous_compare, "hover.end")
    end
end

local function equipped_hover_matches(slot, item_pos)
    if active_equipped_hover.active ~= true then return false end
    return active_equipped_hover.slot_key == full_name(slot)
        and active_equipped_hover.item_pos == item_pos
end

local function broadcast_slot_hover(slot, is_hovered, item_pos)
    if not is_valid(slot) then return false end
    if item_pos == nil then return false end

    local ok, result = call_delegate(property_value(slot, "DispatcherOnHovered"),
        is_hovered, item_pos)
    pleasureLib:debug_log("broadcasted slot hover dispatcher"
        .. " hovered=" .. tostring(is_hovered)
        .. " itemPos=" .. tostring(item_pos)
        .. " ok=" .. tostring(ok)
        .. " result=" .. tostring(result))
    return ok == true
end

local function stop_active_equipped_hover(label)
    if active_equipped_hover.active ~= true then return false end

    local slot = active_equipped_hover.slot
    local item_pos = active_equipped_hover.item_pos
    local inventory_main = active_equipped_hover.inventory_main
    local wearables_bar = active_equipped_hover.wearables_bar
    end_equipped_hover(inventory_main)
    broadcast_slot_hover(slot, false, item_pos)
    hide_equipped_tooltip_widgets(wearables_bar, inventory_main,
        tostring(label) .. ".itemPos" .. tostring(item_pos))
    return true
end

local function find_weapon_hotbar()
    if is_valid(cached_hotbar)
        and is_valid(property_value(cached_hotbar, "m_InventoryBase"))
    then
        return cached_hotbar
    end
    cached_hotbar = nil
    local function accept_hotbar(candidate, source)
        candidate = pleasureLib:unwrap(candidate)
        if is_valid(candidate)
            and is_valid(property_value(candidate, "m_InventoryBase"))
            and (is_valid(property_value(candidate, "Slot_Melee"))
                or is_valid(property_value(candidate, "Slot_Ranged")))
        then
            cached_hotbar = candidate
            pleasureLib:debug_log("resolved weapon hotbar source=" .. tostring(source)
                .. " object=" .. full_name(candidate))
            return candidate
        end
        return nil
    end

    local controllers = pleasureLib:find_all_of("HUDQuickSlotController")
    if type(controllers) == "table" then
        for _, object in ipairs(controllers) do
            local controller = pleasureLib:unwrap(object)
            local hotbar = accept_hotbar(
                property_value(controller, "m_QuickSlot"), "controller")
            if hotbar ~= nil then return hotbar end
        end
    end

    local objects = pleasureLib:find_all_of("W_Hotbar_C")
    if type(objects) == "table" then
        for _, object in ipairs(objects) do
            local hotbar = accept_hotbar(object, "objectScan")
            if hotbar ~= nil then return hotbar end
        end
    end

    -- Vanilla clears the hidden keyboard hotbar. Drive the same instant
    -- press/release path the game uses so it creates a normal instance,
    -- without latching it visible like AlwaysVisibleHotbar does.
    if type(controllers) == "table" then
        for _, object in ipairs(controllers) do
            local controller = pleasureLib:unwrap(object)
            if is_valid(controller) then
                local pressed, press_error = pcall(function()
                    controller:QuickSlotBindingPress()
                    controller:QuickSlotBindingRelease()
                end)
                pleasureLib:debug_log("requested vanilla hotbar creation"
                    .. " ok=" .. tostring(pressed)
                    .. " error=" .. tostring(press_error))
                local hotbar = accept_hotbar(
                    property_value(controller, "m_QuickSlot"),
                    "controllerAfterTap")
                if hotbar ~= nil then return hotbar end
            end
        end
    end
    return nil
end

local function item_definition_from_inventory_slot(slot, inventory_main)
    local item_pos = slot_item_pos(slot)
    if item_pos == nil or item_pos < 0 then return nil end

    local inventory_base = property_value(inventory_main, "InventoryBase")
    if not is_valid(inventory_base) then return nil end

    local valid_fn = pleasureLib:try(function()
        return inventory_base["IsItemValidByPos"]
    end)
    if valid_fn == nil then return nil end
    local valid_ok, item_valid = pcall(function()
        return valid_fn(inventory_base, item_pos)
    end)
    if not valid_ok or pleasureLib:unwrap(item_valid) ~= true then return nil end

    local fn = pleasureLib:try(function() return inventory_base["GetBaseConfigByPos"] end)
    if fn == nil then return nil end
    local ok, definition = pcall(function()
        return fn(inventory_base, item_pos)
    end)
    definition = pleasureLib:unwrap(definition)
    pleasureLib:debug_log("resolved hovered item definition"
        .. " itemPos=" .. tostring(item_pos)
        .. " ok=" .. tostring(ok)
        .. " definition=" .. full_name(definition))
    if ok and is_valid(definition) then return definition end
    return nil
end

local function definition_is_a(definition, class_name)
    if not is_valid(definition) then return false end
    return pleasureLib:try(function() return definition:IsA(class_name) end) == true
end

local function hovered_weapon_inventory_type(slot, inventory_main)
    local definition = item_definition_from_inventory_slot(slot, inventory_main)
    if not is_valid(definition) then return nil, "" end

    if definition_is_a(definition, "/Script/G1R.WeaponRangedDefinition")
        or definition_is_a(definition, "/Script/G1R.WeaponArcheryDefinition")
    then
        return INVENTORY_TYPE_RANGED_SLOT, full_name(definition)
    end
    if definition_is_a(definition, "/Script/G1R.WeaponMeleeDefinition") then
        return INVENTORY_TYPE_MELEE_SLOT, full_name(definition)
    end
    return nil, full_name(definition)
end

local function ensure_weapon_native_comparison_spec(slot, inventory_main)
    if slot_has_hotbar_assignment(slot) then return false end

    local definition = item_definition_from_inventory_slot(slot, inventory_main)
    if not is_valid(definition) then return false end
    if not definition_is_a(definition, "/Script/G1R.WeaponMeleeDefinition")
        and not definition_is_a(definition, "/Script/G1R.WeaponRangedDefinition")
        and not definition_is_a(definition, "/Script/G1R.WeaponArcheryDefinition")
    then
        return false
    end

    local tag = resolve_wearable_comparison_spec()
    if tag == nil then return false end
    if item_has_spec(definition, tag) then return true end

    local ok, result = pcall(function()
        return definition:AddItemSpec(tag)
    end)
    local confirmed = ok and item_has_spec(definition, tag)
    pleasureLib:debug_log("patched weapon for native comparison input"
        .. " definition=" .. full_name(definition)
        .. " ok=" .. tostring(ok)
        .. " confirmed=" .. tostring(confirmed)
        .. " result=" .. tostring(result))
    return confirmed
end

local function inventory_weapon_compare_widget(inventory_main)
    for _, property_name in ipairs({
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Compare",
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_1_Compare",
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo_Wearable",
    }) do
        local widget = property_value(inventory_main, property_name)
        if is_valid(widget) then return widget end
    end
    return nil
end

local function call_hotbar_base_tooltip(hotbar, item_pos)
    local fn = pleasureLib:try(function() return hotbar["UpdateToolTipBaseItem"] end)
    local call_source = "member"
    local ok = false
    local result = nil

    if is_valid(fn) then
        ok, result = pcall(function()
            return fn(hotbar, item_pos, INVENTORY_TYPE_MAIN_CONTAINER)
        end)
    end

    -- UE4SS normally resolves inherited UFunctions through UObject.__index.
    -- W_Hotbar_C does not expose this inherited native function that way in
    -- this game build, so invoke the reflected UFunction with the hotbar as
    -- its explicit calling context instead.
    if not ok then
        fn = pleasureLib:find_object(QUICK_SLOT_UPDATE_BASE_FUNCTION)
        call_source = "reflected"
        if is_valid(fn) then
            ok, result = pcall(function()
                return fn(hotbar, item_pos, INVENTORY_TYPE_MAIN_CONTAINER)
            end)
        end
    end

    pleasureLib:debug_log("updated hotbar comparison base"
        .. " itemPos=" .. tostring(item_pos)
        .. " source=" .. tostring(call_source)
        .. " ok=" .. tostring(ok)
        .. " result=" .. tostring(pleasureLib:unwrap(result)))
    return ok and pleasureLib:unwrap(result) ~= false
end

local function copy_inventory_tooltip_info(inventory_main, hotbar)
    local tooltip_info = property_value(inventory_main, "TooltipInfo")
    if tooltip_info == nil then return false end

    local ok, result = set_property_value(hotbar, "ToolTipInfoBase",
        tooltip_info)
    pleasureLib:debug_log("copied inventory tooltip info to hotbar"
        .. " ok=" .. tostring(ok)
        .. " result=" .. tostring(result))
    return ok == true
end

local function call_hotbar_slot_tooltip(hotbar, weapon_position, show)
    local fn = pleasureLib:try(function() return hotbar["UpdateToolTipOnSlot"] end)
    if fn == nil then return false end
    local ok, result = pcall(function()
        return fn(hotbar, weapon_position, show == true)
    end)
    pleasureLib:debug_log("updated hotbar weapon comparison"
        .. " weaponPosition=" .. tostring(weapon_position)
        .. " show=" .. tostring(show)
        .. " ok=" .. tostring(ok)
        .. " result=" .. tostring(result))
    return ok
end

local function clear_weapon_comparison_state()
    active_weapon_comparison.active = false
    active_weapon_comparison.slot_started = false
    active_weapon_comparison.hotbar = nil
    active_weapon_comparison.weapon_slot = nil
    active_weapon_comparison.weapon_position = nil
    active_weapon_comparison.compare_widget = nil
    active_weapon_comparison.previous_show_tooltips = nil
    active_weapon_comparison.previous_base_widget = nil
    active_weapon_comparison.previous_slot_widget = nil
end

local function end_weapon_comparison(label)
    if active_weapon_comparison.active ~= true then return false end

    local hotbar = active_weapon_comparison.hotbar
    local weapon_position = active_weapon_comparison.weapon_position
    local compare_widget = active_weapon_comparison.compare_widget
    local slot_started = active_weapon_comparison.slot_started == true
    active_weapon_comparison.token = active_weapon_comparison.token + 1
    local base_restored = false
    local slot_restored = false
    if is_valid(hotbar) then
        -- Restore the slot target first. Restoring the base target can make
        -- the hidden vanilla hotbar rebuild its tooltip state immediately;
        -- touching the slot target afterwards caused the observed native
        -- access violation during rapid grid hovers.
        if is_valid(active_weapon_comparison.previous_slot_widget) then
            slot_restored = set_widget_reference(hotbar,
                "W_Inventory_ItemTooltip_ItemInSlotToAssignTo",
                active_weapon_comparison.previous_slot_widget,
                tostring(label) .. ".restoreSlot")
        end
        if is_valid(active_weapon_comparison.previous_base_widget) then
            base_restored = set_widget_reference(hotbar,
                "W_Inventory_ItemTooltip_ItemToAssign",
                active_weapon_comparison.previous_base_widget,
                tostring(label) .. ".restoreBase")
        end
    end

    -- Never let the hotbar's close path run while it still targets the
    -- inventory widgets. On a slot-to-slot hover transition the game has
    -- already populated the next main tooltip before this cleanup executes.
    if slot_started and base_restored and slot_restored
        and weapon_position ~= nil
    then
        call_hotbar_slot_tooltip(hotbar, weapon_position, false)
    elseif slot_started then
        pleasureLib:debug_log("skipped hotbar weapon comparison cleanup: widgets not restored"
            .. " baseRestored=" .. tostring(base_restored)
            .. " slotRestored=" .. tostring(slot_restored))
    end

    if slot_started then
        set_widget_visibility(compare_widget, 1,
            tostring(label) .. ".weaponCompare")
    end
    if is_valid(hotbar) then
        if active_weapon_comparison.previous_show_tooltips ~= nil then
            set_property_value(hotbar, "ShowToolTips",
                active_weapon_comparison.previous_show_tooltips)
        end
    end

    clear_weapon_comparison_state()
    return true
end

local function maintain_weapon_comparison_visibility(compare_widget, label)
    set_widget_visibility(compare_widget, 4,
        tostring(label) .. ".immediate")
end

local function begin_weapon_comparison(slot, inventory_main, attempt)
    attempt = tonumber(attempt) or 0
    local weapon_type, definition_name = hovered_weapon_inventory_type(
        slot, inventory_main)
    if weapon_type == nil then return false end

    local hotbar = find_weapon_hotbar()
    if not is_valid(hotbar) then
        if attempt < 3 then
            local comparison_token = active_inventory_comparison.token
            local scheduled = run_later(50 * (attempt + 1), function()
                if active_inventory_comparison.active == true
                    and active_inventory_comparison.token == comparison_token
                    and is_valid(slot)
                    and is_valid(inventory_main)
                then
                    begin_weapon_comparison(slot, inventory_main, attempt + 1)
                end
            end)
            pleasureLib:debug_log("weapon comparison waiting for vanilla hotbar"
                .. " attempt=" .. tostring(attempt + 1)
                .. " scheduled=" .. tostring(scheduled)
                .. " definition=" .. tostring(definition_name))
            return scheduled
        end
        pleasureLib:debug_log("weapon comparison skipped: vanilla hotbar unavailable"
            .. " attempts=" .. tostring(attempt)
            .. " definition=" .. tostring(definition_name))
        return false
    end

    local weapon_position, weapon_definition = first_hotbar_weapon_position(
        hotbar, weapon_type)
    if weapon_position == nil or not is_valid(weapon_definition) then
        pleasureLib:debug_log("weapon comparison skipped: matching hotbar weapon unavailable"
            .. " inventoryType=" .. tostring(weapon_type)
            .. " definition=" .. tostring(definition_name))
        return false
    end

    local base_widget = inventory_main_tooltip_widget(inventory_main)
    local compare_widget = inventory_weapon_compare_widget(inventory_main)
    if not is_valid(base_widget) or not is_valid(compare_widget) then
        pleasureLib:debug_log("weapon comparison skipped: inventory tooltip widgets unavailable")
        return false
    end

    local hotbar_slot_count = array_length(property_value(hotbar, "m_SlotsData"))
    if hotbar_slot_count == nil or weapon_position == nil or weapon_position < 0
        or weapon_position >= hotbar_slot_count
    then
        pleasureLib:debug_log("weapon comparison skipped: hotbar slot index unavailable"
            .. " position=" .. tostring(weapon_position)
            .. " slotCount=" .. tostring(hotbar_slot_count))
        return false
    end
    pleasureLib:debug_log("resolved hotbar weapon comparison entry"
        .. " position=" .. tostring(weapon_position)
        .. " inventoryType=" .. tostring(weapon_type)
        .. " definition=" .. full_name(weapon_definition))

    if active_weapon_comparison.active == true
        and full_name(active_weapon_comparison.hotbar) == full_name(hotbar)
    then
        active_weapon_comparison.token =
            active_weapon_comparison.token + 1
        active_weapon_comparison.weapon_slot = weapon_definition
        active_weapon_comparison.weapon_position = weapon_position
        active_weapon_comparison.compare_widget = compare_widget

        set_property_value(hotbar, "ShowToolTips", true)
        local linked_base = set_widget_reference(hotbar,
            "W_Inventory_ItemTooltip_ItemToAssign", base_widget,
            "weaponComparison.refresh.base")
        local linked_slot = set_widget_reference(hotbar,
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo", compare_widget,
            "weaponComparison.refresh.slot")
        local base_updated = linked_base
            and copy_inventory_tooltip_info(inventory_main, hotbar)
        local slot_updated = linked_slot and base_updated
            and call_hotbar_slot_tooltip(hotbar, weapon_position, true)

        if not slot_updated then
            pleasureLib:debug_log("weapon comparison in-place refresh failed"
                .. " inventoryType=" .. tostring(weapon_type)
                .. " position=" .. tostring(weapon_position)
                .. " definition=" .. tostring(definition_name))
            end_weapon_comparison("weaponComparison.refreshFailed")
            return false
        end

        active_weapon_comparison.slot_started = true
        maintain_weapon_comparison_visibility(compare_widget,
            "weaponComparison.refresh")
        pleasureLib:debug_log("weapon comparison refreshed in place"
            .. " inventoryType=" .. tostring(weapon_type)
            .. " position=" .. tostring(weapon_position)
            .. " definition=" .. tostring(definition_name))
        return true
    end

    if active_weapon_comparison.active == true then
        end_weapon_comparison("weaponComparison.hotbarChanged")
    end

    active_weapon_comparison.active = true
    active_weapon_comparison.slot_started = false
    active_weapon_comparison.token = active_weapon_comparison.token + 1
    active_weapon_comparison.hotbar = hotbar
    active_weapon_comparison.weapon_slot = weapon_definition
    active_weapon_comparison.weapon_position = weapon_position
    active_weapon_comparison.compare_widget = compare_widget
    active_weapon_comparison.previous_show_tooltips =
        bool_property(hotbar, "ShowToolTips")
    active_weapon_comparison.previous_base_widget = property_value(hotbar,
        "W_Inventory_ItemTooltip_ItemToAssign")
    active_weapon_comparison.previous_slot_widget = property_value(hotbar,
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo")

    set_property_value(hotbar, "ShowToolTips", true)
    local linked_base = set_widget_reference(hotbar,
        "W_Inventory_ItemTooltip_ItemToAssign", base_widget,
        "weaponComparison.base")
    local linked_slot = set_widget_reference(hotbar,
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo", compare_widget,
        "weaponComparison.slot")
    -- InventoryMain already owns the exact tooltip info produced by the
    -- native grid hover. Copying the property avoids resolving the filtered
    -- ItemPos a second time through the hotbar's unrelated inventory view.
    local base_updated = linked_base
        and copy_inventory_tooltip_info(inventory_main, hotbar)
    local slot_updated = linked_slot and base_updated
        and call_hotbar_slot_tooltip(hotbar, weapon_position, true)
    active_weapon_comparison.slot_started = slot_updated == true

    if not slot_updated then
        pleasureLib:debug_log("weapon comparison native route failed"
            .. " inventoryType=" .. tostring(weapon_type)
            .. " position=" .. tostring(weapon_position)
            .. " definition=" .. tostring(definition_name))
        end_weapon_comparison("weaponComparison.failed")
        return false
    end

    maintain_weapon_comparison_visibility(compare_widget,
        "weaponComparison")
    pleasureLib:debug_log("weapon comparison active"
        .. " inventoryType=" .. tostring(weapon_type)
        .. " position=" .. tostring(weapon_position)
        .. " definition=" .. tostring(definition_name))
    return true
end

local function end_inventory_comparison(inventory_main, label)
    if active_inventory_comparison.active ~= true then return false end

    active_inventory_comparison.token = active_inventory_comparison.token + 1
    inventory_main = pleasureLib:unwrap(inventory_main)
    if not is_valid(inventory_main) then
        inventory_main = active_inventory_comparison.inventory_main
    end
    end_weapon_comparison(tostring(label) .. ".weapon")

    active_inventory_comparison.active = false
    active_inventory_comparison.slot = nil
    active_inventory_comparison.slot_key = nil
    active_inventory_comparison.item_pos = nil
    active_inventory_comparison.inventory_main = nil
    return true
end


local function inventory_comparison_matches(slot, item_pos)
    if active_inventory_comparison.active ~= true then return false end
    return active_inventory_comparison.slot_key == full_name(slot)
        and active_inventory_comparison.item_pos == item_pos
end

local function begin_inventory_comparison(slot)
    if config.EnableComparisonTooltips ~= true then return false end

    local inventory_main = related_object_with_name(slot, "W_Inventory_Main")
    if not is_valid(inventory_main) then return false end
    if slot_has_hotbar_assignment(slot) then
        if active_inventory_comparison.active == true then
            end_inventory_comparison(
                active_inventory_comparison.inventory_main,
                "comparison.hotbarAssigned")
        end
        force_weapon_comparison_hint(inventory_main, false,
            "comparison.hotbarAssigned")
        pleasureLib:debug_log("comparison skipped: item is assigned to hotbar"
            .. " slot=" .. full_name(slot))
        return false
    end
    local weapon_type = hovered_weapon_inventory_type(slot, inventory_main)
    if weapon_type == nil then
        if active_inventory_comparison.active == true then
            end_inventory_comparison(
                active_inventory_comparison.inventory_main,
                "comparison.nativeItem")
        end
        -- Armor, rings and amulets are compared entirely by the game's
        -- native left-Control behavior. Do not alter its toggle state.
        return false
    end

    local comparison_enabled =
        bool_property(inventory_main, "ShouldShowWearableCompare") == true

    if active_inventory_comparison.active == true
        and active_weapon_comparison.active == true
        and comparison_enabled
    then
        active_inventory_comparison.token =
            active_inventory_comparison.token + 1
        local comparison_token = active_inventory_comparison.token
        active_inventory_comparison.slot = slot
        active_inventory_comparison.slot_key = full_name(slot)
        active_inventory_comparison.item_pos = slot_item_pos(slot)
        active_inventory_comparison.inventory_main = inventory_main

        ensure_inventory_tooltip_activation(inventory_main,
            "comparison.weaponRefresh")
        maintain_weapon_comparison_hint(inventory_main, slot,
            "comparison.weaponRefresh")
        return run_later(10, function()
            if active_inventory_comparison.active ~= true
                or active_inventory_comparison.token ~= comparison_token
                or not is_valid(slot)
                or not is_valid(inventory_main)
                or bool_property(inventory_main,
                    "ShouldShowWearableCompare") ~= true
            then
                return
            end
            local refreshed = begin_weapon_comparison(slot,
                inventory_main)
            if not refreshed
                and active_weapon_comparison.active == true
            then
                end_weapon_comparison(
                    "weaponComparison.refreshUnavailable")
            end
        end)
    end

    if active_inventory_comparison.active == true then
        end_inventory_comparison(active_inventory_comparison.inventory_main,
            "comparison.replace")
    end

    active_inventory_comparison.active = true
    active_inventory_comparison.token = active_inventory_comparison.token + 1
    local comparison_token = active_inventory_comparison.token
    active_inventory_comparison.slot = slot
    active_inventory_comparison.slot_key = full_name(slot)
    active_inventory_comparison.item_pos = slot_item_pos(slot)
    active_inventory_comparison.inventory_main = inventory_main

    ensure_inventory_tooltip_activation(inventory_main, "comparison.begin")
    maintain_weapon_comparison_hint(inventory_main, slot, "comparison.begin")
    if not comparison_enabled then return true end

    local comparison_scheduled = run_later(10, function()
        if active_inventory_comparison.active ~= true
            or active_inventory_comparison.token ~= comparison_token
            or not is_valid(slot)
            or not is_valid(inventory_main)
            or bool_property(inventory_main,
                "ShouldShowWearableCompare") ~= true
        then
            return
        end
        begin_weapon_comparison(slot, inventory_main)
    end)
    return comparison_scheduled
end

local function on_comparison_toggled(_hook_name, context)
    local inventory_main = pleasureLib:unwrap(context)
    if not is_valid(inventory_main) then return nil end
    if active_inventory_comparison.active ~= true then return nil end
    if full_name(active_inventory_comparison.inventory_main)
        ~= full_name(inventory_main)
    then
        return nil
    end

    local comparison_token = active_inventory_comparison.token
    run_later(1, function()
        local slot = active_inventory_comparison.slot
        if active_inventory_comparison.active ~= true
            or active_inventory_comparison.token ~= comparison_token
            or not is_valid(slot)
            or not is_valid(inventory_main)
            or bool_property(slot, "Hovered") ~= true
        then
            return
        end

        local enabled = bool_property(inventory_main,
            "ShouldShowWearableCompare") == true
        force_weapon_comparison_hint(inventory_main, true,
            "comparison.toggle")
        if enabled then
            begin_weapon_comparison(slot, inventory_main)
        else
            end_weapon_comparison("comparison.toggleOff")
        end
        pleasureLib:debug_log("weapon comparison toggle handled"
            .. " enabled=" .. tostring(enabled)
            .. " slot=" .. full_name(slot))
    end)
    return nil
end

local function on_slot_hovered(_hook_name, context)
    if config.Enabled ~= true then return nil end

    local slot = pleasureLib:unwrap(context)
    if not is_valid(slot) then return nil end
    if slot_is_main_inventory(slot) then
        stop_active_equipped_hover("gridHover")
        local inventory_main = related_object_with_name(slot,
            "W_Inventory_Main")
        if is_valid(inventory_main) then
            -- Register the same native comparison input used by armor,
            -- rings and amulets before W_Inventory_Slot:OnHovered builds
            -- and forwards this weapon's tooltip info.
            ensure_weapon_native_comparison_spec(slot, inventory_main)
        end
        begin_inventory_comparison(slot)
        return nil
    end
    if bool_property(slot, "IsWearableSlot") ~= true then return nil end

    if active_inventory_comparison.active == true then
        end_inventory_comparison(active_inventory_comparison.inventory_main,
            "equippedHover")
    end

    local item_pos = slot_item_pos(slot)
    if equipped_hover_matches(slot, item_pos) and not hover_allowed(slot) then
        return nil
    end

    local inventory_main = refresh_inventory_main_from_slot(slot)
    local wearables_bar = wearables_bar_from(slot)

    enable_wearables_tooltips(wearables_bar)
    ensure_wearable_tooltip_links(wearables_bar, inventory_main, "hover.before")
    begin_equipped_hover(slot, inventory_main, wearables_bar, item_pos)

    broadcast_slot_hover(slot, true, item_pos)
    local tooltip = property_value(wearables_bar, "ToolTipInfoSlot")
    if not tooltip_is_valid(tooltip) then
        pleasureLib:debug_log("hover tooltip missing from ToolTipInfoSlot"
            .. " itemPos=" .. tostring(item_pos))
        end_equipped_hover(inventory_main)
        hide_equipped_tooltip_widgets(wearables_bar, inventory_main,
            "hover.noTooltip")
        return nil
    end

    pleasureLib:debug_log("using hover tooltip from ToolTipInfoSlot"
        .. " itemPos=" .. tostring(item_pos))
    schedule_equipped_tooltip_force(wearables_bar, inventory_main,
        "hover.itemPos" .. tostring(item_pos))
    return nil
end

local function on_slot_unhovered(_hook_name, context)
    if config.Enabled ~= true then return nil end

    local slot = pleasureLib:unwrap(context)
    if not is_valid(slot) then return nil end
    if slot_is_main_inventory(slot) then
        local item_pos = slot_item_pos(slot)
        if not inventory_comparison_matches(slot, item_pos) then
            pleasureLib:debug_log("ignored stale inventory unhover"
                .. " slot=" .. full_name(slot)
                .. " itemPos=" .. tostring(item_pos))
            return nil
        end

        local token = active_inventory_comparison.token
        local inventory_main = active_inventory_comparison.inventory_main
        run_later(10, function()
            if active_inventory_comparison.active == true
                and active_inventory_comparison.token == token
                and inventory_comparison_matches(slot, item_pos)
                and bool_property(slot, "Hovered") ~= true
            then
                end_inventory_comparison(inventory_main, "comparison.end")
            end
        end)
        return nil
    end
    if bool_property(slot, "IsWearableSlot") ~= true then return nil end

    local item_pos = slot_item_pos(slot)
    if not equipped_hover_matches(slot, item_pos) then
        pleasureLib:debug_log("ignored stale equipped unhover"
            .. " slot=" .. full_name(slot)
            .. " itemPos=" .. tostring(item_pos))
        return nil
    end

    local inventory_main = refresh_inventory_main_from_slot(slot)
    local wearables_bar = wearables_bar_from(slot)
    local token = active_equipped_hover.token
    run_later(10, function()
        if active_equipped_hover.active == true
            and active_equipped_hover.token == token
            and equipped_hover_matches(slot, item_pos)
            and bool_property(slot, "Hovered") ~= true
        then
            end_equipped_hover(inventory_main)
            broadcast_slot_hover(slot, false, item_pos)
            hide_equipped_tooltip_widgets(wearables_bar, inventory_main,
                "unhover.itemPos" .. tostring(item_pos))
        end
    end)
    return nil
end

local function register_hook(path, handler)
    if type(RegisterHook) ~= "function" then
        pleasureLib:log("RegisterHook unavailable")
        return false
    end
    if registered_hooks[path] == true then return false end

    if not ufunction_loaded(path) then
        if hook_retry_logged[path] ~= "not-loaded" then
            hook_retry_logged[path] = "not-loaded"
            pleasureLib:debug_log("Hook target not loaded yet; waiting for UI object notification "
                .. path)
        end
        return false
    end

    local ok = pleasureLib:register_hook(path,
        function(context, ...)
            if not generation_is_current() then return nil end
            return handler(path, context, ...)
        end)
    if not ok then
        if hook_retry_logged[path] ~= "not-hookable" then
            hook_retry_logged[path] = "not-hookable"
            pleasureLib:debug_log("Hook target loaded but not hookable " .. path)
        end
        return false
    end

    registered_hooks[path] = true
    hook_retry_logged[path] = nil
    return true
end

local function register_hooks()
    local count = 0
    for _, path in ipairs(config.SlotHoverHooks or {}) do
        if register_hook(path, on_slot_hovered) then
            count = count + 1
        end
    end
    for _, path in ipairs(config.SlotUnhoverHooks or {}) do
        if register_hook(path, on_slot_unhovered) then
            count = count + 1
        end
    end
    for _, path in ipairs(COMPARISON_TOGGLE_HOOKS) do
        if register_hook(path, on_comparison_toggled) then
            count = count + 1
        end
    end
    for _, path in ipairs(INVENTORY_SHOWN_HOOKS) do
        if register_hook(path, on_inventory_shown) then
            count = count + 1
        end
    end
    return count
end

local function install_ui_object_notifications()
    if type(NotifyOnNewObject) ~= "function" then
        pleasureLib:log("NotifyOnNewObject unavailable; late UI hooks cannot be registered.")
        return 0
    end

    local registered = 0
    for _, class_name in ipairs(UI_OBJECT_NOTIFY_CLASSES) do
        local notify_class = class_name
        local ok, result = pcall(function()
            return NotifyOnNewObject(notify_class, function(object)
                if not generation_is_current() then return end
                if handled_ui_notification_classes[notify_class] == true then return end
                handled_ui_notification_classes[notify_class] = true
                pleasureLib:debug_log("UI object created; registering loaded hooks"
                    .. " class=" .. tostring(notify_class)
                    .. " object=" .. full_name(object))
                register_hooks()
            end)
        end)
        if ok then
            registered = registered + 1
            pleasureLib:debug_log("UI object notification registered"
                .. " class=" .. tostring(notify_class)
                .. " result=" .. tostring(result))
        else
            pleasureLib:debug_log("UI object notification failed"
                .. " class=" .. tostring(notify_class)
                .. " error=" .. tostring(result))
        end
    end
    return registered
end

load_config()

if config.Enabled ~= true then
    pleasureLib:log("Loaded v" .. VERSION .. " disabled by config.")
elseif type(RegisterHook) ~= "function" then
    pleasureLib:log("Loaded v" .. VERSION .. " in degraded mode: RegisterHook unavailable.")
else
    pleasureLib:register_game_bool_setting({
        id = "ExtendedItemTooltips.ComparisonDefaultEnabled",
        default = DEFAULT_CONFIG.ComparisonDefaultEnabled,
        get = function()
            return config.ComparisonDefaultEnabled == true
        end,
        set = function(value)
            config.ComparisonDefaultEnabled = value == true
            return true
        end,
        persist = {
            path = function() return config.ConfigPath end,
            key = "ComparisonDefaultEnabled",
        },
        translations = COMPARISON_DEFAULT_SETTING_TRANSLATIONS,
    })
    local notification_count = install_ui_object_notifications()
    local count = register_hooks()
    pleasureLib:log("Loaded v" .. VERSION .. "; G1R wearable tooltip hooks registered="
        .. tostring(count)
        .. "; UI object notifications=" .. tostring(notification_count)
        .. ".")
end
