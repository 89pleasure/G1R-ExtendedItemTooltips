local MOD = "ExtendedItemTooltips"
local pleasureLib = require("pleasure_lib_loader").new(MOD)
if type(pleasureLib) ~= "table" then return end

local CONFIG_FILE_NAME = "ExtendedItemTooltips.ini"
local VERSION = "0.19.7"

local WEAPON_COMPARISON_HOVER_SETTLE_MIN_MS = 150
local WEAPON_COMPARISON_HOVER_SETTLE_MAX_MS = 500
local EQUIPPED_HOVER_DUPLICATE_COOLDOWN_MS = 40

_G.__EXTENDED_ITEM_TOOLTIPS_GENERATION =
    (_G.__EXTENDED_ITEM_TOOLTIPS_GENERATION or 0) + 1
local SCRIPT_GENERATION = _G.__EXTENDED_ITEM_TOOLTIPS_GENERATION

local function generation_is_current()
    return _G.__EXTENDED_ITEM_TOOLTIPS_GENERATION == SCRIPT_GENERATION
end

local DEFAULT_CONFIG = {
    Enabled = true,
    Debug = false,
    TooltipCooldownMs = WEAPON_COMPARISON_HOVER_SETTLE_MIN_MS,
    ForceTooltipVisibility = true,
    EnableComparisonTooltips = true,
    ComparisonDefaultEnabled = false,
}

local UI_OBJECT_NOTIFY_CLASSES = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Main.W_Inventory_Main_C",
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Slot.W_Inventory_Slot_C",
    "/Game/UI/ManagementUI/Inventory/W_Inventory_ItemTooltip.W_Inventory_ItemTooltip_C",
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

local TOOLTIP_HINT_REFRESH_HOOKS = {
    "/Script/G1R.InventoryItemTooltip:UpdateTooltip",
    "/Game/UI/ManagementUI/Inventory/W_Inventory_ItemTooltip.W_Inventory_ItemTooltip_C:CheckInputWearableTooltipButtonViaTags",
}

local INVENTORY_TYPE_MAIN_CONTAINER = 1
local INVENTORY_TYPE_MELEE_SLOT = 3
local INVENTORY_TYPE_RANGED_SLOT = 4
local WIDGET_SET_VISIBILITY_FUNCTION =
    "/Script/UMG.Widget:SetVisibility"
local GAMEPLAY_STATICS_DEFAULT_OBJECT =
    "/Script/Engine.Default__GameplayStatics"
local WEAPON_COMPARISON_RETRY_DELAYS_MS = {
    50, 100, 200, 350, 500, 750, 1000, 1500,
}
local HOOK_REGISTRATION_RETRY_INITIAL_MS = 50
local HOOK_REGISTRATION_RETRY_MAX_MS = 2000
local HOTBAR_CREATION_MAX_ATTEMPTS = 3
local HOTBAR_CREATION_RETRY_ATTEMPTS = {
    [0] = true,
    [3] = true,
    [6] = true,
    [7] = true,
}

local INVENTORY_MAIN_PATH_NEEDLES = {
    "W_Inventory_Main",
    "InventoryMain",
}

local config = {}
local registered_hooks = {}
local hook_retry_logged = {}
local handled_ui_notification_classes = {}
local hook_registration_retry_pending = false
local hook_registration_immediate_pending = false
local hook_registration_retry_delay_ms =
    HOOK_REGISTRATION_RETRY_INITIAL_MS
local hook_registration_complete_handled = false
local cached_inventory_main = nil
local cached_wearables_bar = nil
local cached_hotbar = nil
local widget_set_visibility_function = nil
local gameplay_statics_default = nil
local comparison_clock_source_logged = nil
local hotbar_creation_requested_for_controller = {}
local inventory_session_token = 0
local weapon_comparison_settle_pending = false
local weapon_comparison_settle_timer_generation = 0
local weapon_comparison_settle_timer_due_at_ms = nil
local weapon_comparison_bridge_busy = false
local weapon_comparison_hint_reassert_pending = false
local weapon_comparison_hint_reassert_token = nil
local weapon_comparison_hint_reassert_inventory_main_key = nil
local weapon_comparison_hint_reassert_label = nil
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
local active_weapon_comparison = {
    active = false,
    token = 0,
    compare_widget = nil,
    source_inventory_main_key = nil,
    source_slot_key = nil,
    source_item_pos = nil,
    source_weapon_type = nil,
    source_definition_name = nil,
}
local refresh_inventory_main_from_slot = nil
local reset_inventory_runtime_state = nil
local on_slot_hovered = nil

local function merge_list(defaults, override)
    local parsed = pleasureLib:split_list(override)
    if #parsed > 0 then return parsed end
    return pleasureLib:copy_array(defaults)
end

local function weapon_comparison_hover_settle_ms(value)
    local delay_ms = math.floor(tonumber(value)
        or DEFAULT_CONFIG.TooltipCooldownMs)
    return math.max(WEAPON_COMPARISON_HOVER_SETTLE_MIN_MS,
        math.min(WEAPON_COMPARISON_HOVER_SETTLE_MAX_MS, delay_ms))
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
            local configured_cooldown =
                tonumber(ini.TOOLTIPCOOLDOWNMS)
                    or config.TooltipCooldownMs
            config.TooltipCooldownMs =
                weapon_comparison_hover_settle_ms(configured_cooldown)
            config.SlotHoverHooks = merge_list(
                SLOT_HOVER_HOOKS, ini.SLOTHOVERHOOKS)
            config.SlotUnhoverHooks = merge_list(
                SLOT_UNHOVER_HOOKS, ini.SLOTUNHOVERHOOKS)

            config.ConfigPath = path
            pleasureLib:set_debug(config.Debug)
            if configured_cooldown ~= config.TooltipCooldownMs then
                local normalized = pleasureLib:update_ini_value(
                    path, "TooltipCooldownMs",
                    tostring(config.TooltipCooldownMs))
                pleasureLib:debug_log(
                    "clamped weapon comparison delay"
                    .. " configuredMs=" .. tostring(configured_cooldown)
                    .. " effectiveMs="
                    .. tostring(config.TooltipCooldownMs)
                    .. " persisted=" .. tostring(normalized))
            end
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

local WEAPON_COMPARISON_DELAY_SETTING_TRANSLATIONS = {
    en = {
        name = "Weapon comparison delay",
        description = "Time in milliseconds a backpack weapon must remain hovered before its comparison is built. The Ctrl hint appears immediately.",
    },
    de = {
        name = "Waffenvergleich-Verzoegerung",
        description = "Zeit in Millisekunden, die eine Rucksackwaffe ausgewaehlt bleiben muss, bevor ihr Vergleich aufgebaut wird. Der Strg-Hinweis erscheint sofort.",
    },
}

local function setting_persist_options(key)
    return {
        path = function() return config.ConfigPath end,
        key = key,
    }
end

local function register_game_settings()
    pleasureLib:register_game_bool_setting({
        id = "ExtendedItemTooltips.ComparisonDefaultEnabled",
        section = "Extended Item Tooltips",
        default = DEFAULT_CONFIG.ComparisonDefaultEnabled,
        get = function()
            return config.ComparisonDefaultEnabled == true
        end,
        set = function(value)
            config.ComparisonDefaultEnabled = value == true
            return true
        end,
        persist = setting_persist_options("ComparisonDefaultEnabled"),
        translations = COMPARISON_DEFAULT_SETTING_TRANSLATIONS,
    })

    local required_api = {
        "register_game_int_setting",
    }
    for _, api_name in ipairs(required_api) do
        if type(pleasureLib[api_name]) ~= "function" then
            pleasureLib:log("PleasureLib 0.5.0 settings API unavailable: "
                .. api_name)
            return false
        end
    end

    pleasureLib:register_game_int_setting({
        id = "ExtendedItemTooltips.TooltipCooldownMs",
        section = "Extended Item Tooltips",
        minimum = WEAPON_COMPARISON_HOVER_SETTLE_MIN_MS,
        maximum = WEAPON_COMPARISON_HOVER_SETTLE_MAX_MS,
        default = DEFAULT_CONFIG.TooltipCooldownMs,
        get = function()
            return config.TooltipCooldownMs
        end,
        set = function(value)
            config.TooltipCooldownMs =
                weapon_comparison_hover_settle_ms(value)
            return true
        end,
        persist = setting_persist_options("TooltipCooldownMs"),
        translations = WEAPON_COMPARISON_DELAY_SETTING_TRANSLATIONS,
    })

    return true
end

local function is_valid(obj)
    -- PleasureLib already falls back to GetFullName when IsValid is
    -- unavailable, but preserves an explicit false. Do not rehabilitate
    -- stale widgets from a previous save merely because they still have a
    -- readable object name.
    return pleasureLib:is_valid(obj)
end

local function full_name(obj)
    local name = pleasureLib:full_name(obj)
    if name ~= "" or not is_valid(obj) then return name end
    return pleasureLib:try(function() return obj:GetFullName() end) or ""
end

local function object_instance_key(obj)
    if not is_valid(obj) then return "" end
    local address = pleasureLib:try(function()
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
    local world = pleasureLib:try(function()
        if type(obj.GetWorld) == "function" then return obj:GetWorld() end
        return nil
    end)
    world = pleasureLib:unwrap(world)
    if not is_valid(world) then return "" end
    return object_instance_key(world)
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
    -- Schedule directly on the game thread so rapid hover events cannot
    -- build a second queue of callbacks waiting to be marshalled later.
    return pleasureLib:delay_game_thread(ms, function()
        if generation_is_current() then fn() end
    end)
end

local function comparison_clock_ms(world_context)
    if not is_valid(gameplay_statics_default) then
        gameplay_statics_default =
            pleasureLib:find_object(GAMEPLAY_STATICS_DEFAULT_OBJECT)
    end

    local real_time_seconds = pleasureLib:try(function()
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
        tonumber(pleasureLib:unwrap(real_time_seconds))
    if real_time_seconds ~= nil then
        if comparison_clock_source_logged ~= "GameplayStatics" then
            comparison_clock_source_logged = "GameplayStatics"
            pleasureLib:debug_log(
                "weapon comparison clock source=GameplayStatics")
        end
        return math.floor(real_time_seconds * 1000)
    end

    local world = pleasureLib:try(function()
        if is_valid(world_context)
            and type(world_context.GetWorld) == "function"
        then
            return world_context:GetWorld()
        end
        return nil
    end)
    world = pleasureLib:unwrap(world)
    real_time_seconds =
        tonumber(property_value(world, "RealTimeSeconds"))
    if real_time_seconds ~= nil then
        if comparison_clock_source_logged ~= "UWorld" then
            comparison_clock_source_logged = "UWorld"
            pleasureLib:debug_log(
                "weapon comparison clock source=UWorld")
        end
        return math.floor(real_time_seconds * 1000)
    end

    -- Never mix this world-relative clock with a different time origin while
    -- the inventory is being torn down. Callers safely fall back to a full
    -- settle window when no comparable timestamp is available.
    return nil
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
    if is_valid(current)
        and object_instance_key(current) == object_instance_key(target)
    then
        return true
    end

    local ok, result = set_property_value(owner, property_name, target)
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
            and object_instance_key(after) == object_instance_key(target)
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

    if type(reset_inventory_runtime_state) == "function" then
        reset_inventory_runtime_state("inventory.shown")
    end
    hotbar_creation_requested_for_controller = {}
    cached_inventory_main = inventory_main
    cached_wearables_bar = nil
    cached_hotbar = nil
    set_wearable_compare_flag(inventory_main,
        config.EnableComparisonTooltips == true
            and config.ComparisonDefaultEnabled == true,
        "inventory.shown.default")
    return nil
end

local function set_widget_visibility(widget, visibility, label, ignore_config)
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

local function set_live_widget_visibility(widget, visibility, label)
    if config.ForceTooltipVisibility ~= true then return false end
    if not is_valid(widget) then return false end

    if not is_valid(widget_set_visibility_function) then
        widget_set_visibility_function =
            pleasureLib:find_object(WIDGET_SET_VISIBILITY_FUNCTION)
    end

    local before = widget_visibility_value(widget)
    local mode = nil
    local call_result = nil
    if is_valid(widget_set_visibility_function) then
        local reflected_ok, reflected_result = pcall(function()
            return widget_set_visibility_function(widget, visibility)
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

    -- A direct UPROPERTY write does not update the live Slate widget. Keep it
    -- only as a degraded fallback after both real UWidget setters failed.
    if mode == nil and set_widget_visibility(
        widget, visibility, label .. ".fallback")
    then
        mode = "property-fallback"
    end

    local after = widget_visibility_value(widget)
    pleasureLib:debug_log("updated live tooltip widget visibility"
        .. " label=" .. tostring(label)
        .. " mode=" .. tostring(mode)
        .. " before=" .. tostring(before)
        .. " after=" .. tostring(after)
        .. " result=" .. tostring(call_result))
    return mode ~= nil and tostring(after) == tostring(visibility)
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
    return set_live_widget_visibility(hint_widget, visible and 4 or 1,
        tostring(label) .. ".comparisonHint")
end

local function schedule_weapon_comparison_hint_reassert(label)
    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.weapon_type == nil
    then
        return false
    end

    weapon_comparison_hint_reassert_token =
        active_inventory_comparison.token
    weapon_comparison_hint_reassert_inventory_main_key =
        active_inventory_comparison.inventory_main_key
    weapon_comparison_hint_reassert_label = tostring(label)
    if weapon_comparison_hint_reassert_pending then return true end

    weapon_comparison_hint_reassert_pending = true
    local scheduled = run_later(0, function()
        weapon_comparison_hint_reassert_pending = false
        local requested_token =
            weapon_comparison_hint_reassert_token
        local requested_inventory_main_key =
            weapon_comparison_hint_reassert_inventory_main_key
        local requested_label =
            weapon_comparison_hint_reassert_label
        weapon_comparison_hint_reassert_token = nil
        weapon_comparison_hint_reassert_inventory_main_key = nil
        weapon_comparison_hint_reassert_label = nil

        if active_inventory_comparison.active ~= true
            or active_inventory_comparison.weapon_type == nil
            or active_inventory_comparison.token ~= requested_token
            or active_inventory_comparison.inventory_main_key
                ~= requested_inventory_main_key
        then
            return
        end
        force_weapon_comparison_hint(
            active_inventory_comparison.inventory_main, true,
            tostring(requested_label) .. ".postUpdate")
    end)
    if not scheduled then
        weapon_comparison_hint_reassert_pending = false
    end
    return scheduled
end

local function on_inventory_tooltip_updated(_hook_name, context)
    if config.Enabled ~= true
        or config.EnableComparisonTooltips ~= true
        or active_inventory_comparison.active ~= true
        or active_inventory_comparison.weapon_type == nil
    then
        return nil
    end

    local updated_tooltip = pleasureLib:unwrap(context)
    local inventory_main = active_inventory_comparison.inventory_main
    local base_tooltip = inventory_main_tooltip_widget(inventory_main)
    if not is_valid(updated_tooltip)
        or object_instance_key(updated_tooltip)
            ~= object_instance_key(base_tooltip)
    then
        return nil
    end

    force_weapon_comparison_hint(inventory_main, true,
        "comparison.tooltipUpdated")
    return nil
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
    if slot_count == nil or slot_count <= 0 then
        return nil, nil, false
    end

    local inventory_base = property_value(hotbar, "m_InventoryBase")
    if not is_valid(inventory_base) then return nil, nil, false end
    local valid_fn = pleasureLib:try(function()
        return inventory_base["IsItemValidByPos"]
    end)
    local definition_fn = pleasureLib:try(function()
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
        if valid_ok and pleasureLib:unwrap(item_valid) == true then
            local definition_ok, definition = pcall(function()
                return definition_fn(inventory_base, position)
            end)
            definition = pleasureLib:unwrap(definition)
            if not definition_ok or not is_valid(definition) then
                scan_complete = false
            end
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
                if matches then return position, definition, true end
            end
        end
    end

    return nil, nil, scan_complete
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

local function equipped_rehover_allowed(slot)
    local key = full_name(slot)
    if key == "" then return true end

    local now = math.floor(os.clock() * 1000)
    local previous = last_hover_at[key] or -1000000
    if now - previous < EQUIPPED_HOVER_DUPLICATE_COOLDOWN_MS then
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
    active_equipped_hover.slot_key = object_instance_key(slot)
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
    return active_equipped_hover.slot_key == object_instance_key(slot)
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

local function find_weapon_hotbar(
    inventory_main, inventory_type, comparison_attempt)
    comparison_attempt = tonumber(comparison_attempt) or 0
    local expected_world = object_world_key(inventory_main)
    local fallback = nil
    local seen = {}

    local function hotbar_is_shaped(candidate)
        candidate = pleasureLib:unwrap(candidate)
        return is_valid(candidate)
            and is_valid(property_value(candidate, "m_InventoryBase"))
            and (is_valid(property_value(candidate, "Slot_Melee"))
                or is_valid(property_value(candidate, "Slot_Ranged")))
    end

    local function inspect_hotbar(candidate, source)
        candidate = pleasureLib:unwrap(candidate)
        if not hotbar_is_shaped(candidate) then return nil end

        local candidate_world = object_world_key(candidate)
        if expected_world ~= "" and candidate_world ~= ""
            and candidate_world ~= expected_world
        then
            pleasureLib:debug_log("ignored hotbar from another world"
                .. " source=" .. tostring(source)
                .. " world=" .. tostring(candidate_world)
                .. " expected=" .. tostring(expected_world))
            return nil
        end

        local candidate_key = object_instance_key(candidate)
        if seen[candidate_key] == true then return nil end
        seen[candidate_key] = true

        local position, definition, ready =
            first_hotbar_weapon_position(candidate, inventory_type)
        if position ~= nil and is_valid(definition) then
            cached_hotbar = candidate
            pleasureLib:debug_log("resolved matching weapon hotbar"
                .. " source=" .. tostring(source)
                .. " object=" .. full_name(candidate)
                .. " position=" .. tostring(position))
            return candidate
        end

        if fallback == nil then fallback = candidate end
        pleasureLib:debug_log("inspected weapon hotbar candidate"
            .. " source=" .. tostring(source)
            .. " ready=" .. tostring(ready)
            .. " object=" .. full_name(candidate))
        return nil
    end

    if is_valid(cached_hotbar) then
        local matched = inspect_hotbar(cached_hotbar, "cache")
        if matched ~= nil then return matched end
    end
    cached_hotbar = nil

    local controllers = pleasureLib:find_all_of("HUDQuickSlotController")
    if type(controllers) == "table" then
        for _, object in ipairs(controllers) do
            local controller = pleasureLib:unwrap(object)
            local hotbar = inspect_hotbar(
                property_value(controller, "m_QuickSlot"), "controller")
            if hotbar ~= nil then return hotbar end
        end
    end

    local objects = pleasureLib:find_all_of("W_Hotbar_C")
    if type(objects) == "table" then
        for _, object in ipairs(objects) do
            local hotbar = inspect_hotbar(object, "objectScan")
            if hotbar ~= nil then return hotbar end
        end
    end

    -- Vanilla clears the hidden keyboard hotbar. Drive the same instant
    -- press/release path a bounded number of times so it creates a normal
    -- instance without latching it visible like AlwaysVisibleHotbar does.
    if type(controllers) == "table" then
        for _, object in ipairs(controllers) do
            local controller = pleasureLib:unwrap(object)
            local controller_world = object_world_key(controller)
            local same_world = expected_world == ""
                or controller_world == ""
                or controller_world == expected_world
            local controller_key = object_instance_key(controller)
            local creation_attempts = tonumber(
                hotbar_creation_requested_for_controller[controller_key])
                or 0
            local current_hotbar =
                property_value(controller, "m_QuickSlot")
            if is_valid(controller) and same_world
                and not hotbar_is_shaped(current_hotbar)
                and creation_attempts < HOTBAR_CREATION_MAX_ATTEMPTS
                and HOTBAR_CREATION_RETRY_ATTEMPTS[comparison_attempt]
                    == true
            then
                hotbar_creation_requested_for_controller[controller_key] =
                    creation_attempts + 1
                local pressed, press_error = pcall(function()
                    controller:QuickSlotBindingPress()
                    controller:QuickSlotBindingRelease()
                end)
                pleasureLib:debug_log("requested vanilla hotbar creation"
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

local function item_definition_from_inventory_position(inventory_main, item_pos)
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

local function weapon_inventory_type_at_position(inventory_main, item_pos)
    local definition =
        item_definition_from_inventory_position(inventory_main, item_pos)
    if not is_valid(definition) then return nil, "", false end

    if definition_is_a(definition, "/Script/G1R.WeaponRangedDefinition")
        or definition_is_a(definition, "/Script/G1R.WeaponArcheryDefinition")
    then
        return INVENTORY_TYPE_RANGED_SLOT, full_name(definition), true
    end
    if definition_is_a(definition, "/Script/G1R.WeaponMeleeDefinition") then
        return INVENTORY_TYPE_MELEE_SLOT, full_name(definition), true
    end
    return nil, full_name(definition), true
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
    active_weapon_comparison.compare_widget = nil
    active_weapon_comparison.source_inventory_main_key = nil
    active_weapon_comparison.source_slot_key = nil
    active_weapon_comparison.source_item_pos = nil
    active_weapon_comparison.source_weapon_type = nil
    active_weapon_comparison.source_definition_name = nil
end

local function end_weapon_comparison(label)
    if active_weapon_comparison.active ~= true then return false end

    local compare_widget = active_weapon_comparison.compare_widget
    active_weapon_comparison.token = active_weapon_comparison.token + 1
    clear_weapon_comparison_state()
    -- The hotbar bridge is restored before a comparison becomes active.
    -- Cleanup therefore only touches the long-lived InventoryMain widget.
    set_widget_visibility(compare_widget, 1,
        tostring(label) .. ".weaponCompare", true)
    return true
end

local function maintain_weapon_comparison_visibility(compare_widget, label)
    set_widget_visibility(compare_widget, 4,
        tostring(label) .. ".immediate")
end

local function weapon_comparison_source_matches(
    inventory_main_key, slot_key, item_pos, weapon_type, definition_name)
    if active_weapon_comparison.active ~= true then return false end
    if not is_valid(active_weapon_comparison.compare_widget) then return false end
    return active_weapon_comparison.source_inventory_main_key
            == inventory_main_key
        and active_weapon_comparison.source_slot_key == slot_key
        and active_weapon_comparison.source_item_pos == item_pos
        and active_weapon_comparison.source_weapon_type == weapon_type
        and active_weapon_comparison.source_definition_name
            == definition_name
end

local function restore_widget_reference(
    owner, property_name, previous, label)
    if is_valid(previous) then
        if set_widget_reference(
            owner, property_name, previous, label)
        then
            return true
        end

        -- If exact restoration fails, at least remove the borrowed
        -- InventoryMain reference before leaving the bridge.
        local cleared = set_property_value(owner, property_name, nil)
        local safely_cleared = cleared == true
            and not is_valid(property_value(owner, property_name))
        pleasureLib:debug_log(
            "failed to restore hotbar widget; cleared temporary reference"
            .. " label=" .. tostring(label)
            .. " property=" .. tostring(property_name)
            .. " cleared=" .. tostring(safely_cleared))
        return false
    end

    local ok, result = set_property_value(owner, property_name, nil)
    pleasureLib:debug_log("cleared temporary hotbar widget reference"
        .. " label=" .. tostring(label)
        .. " property=" .. tostring(property_name)
        .. " ok=" .. tostring(ok)
        .. " result=" .. tostring(result))
    return ok == true
        and not is_valid(property_value(owner, property_name))
end

local function run_weapon_comparison_bridge(
    hotbar, inventory_main, base_widget, compare_widget, weapon_position)
    if weapon_comparison_bridge_busy then
        return false, "bridge busy"
    end

    local previous_show_tooltips = bool_property(hotbar, "ShowToolTips")
    local previous_base_widget = property_value(hotbar,
        "W_Inventory_ItemTooltip_ItemToAssign")
    local previous_slot_widget = property_value(hotbar,
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo")
    if previous_show_tooltips == nil then
        return false, "hotbar state snapshot unavailable"
    end

    weapon_comparison_bridge_busy = true
    local call_ok, route_ok = pcall(function()
        local show_set = set_property_value(hotbar, "ShowToolTips", true)
        if show_set ~= true
            or bool_property(hotbar, "ShowToolTips") ~= true
        then
            return false
        end

        local linked_base = set_widget_reference(hotbar,
            "W_Inventory_ItemTooltip_ItemToAssign", base_widget,
            "weaponComparison.transaction.base")
        if not linked_base then return false end

        local linked_slot = set_widget_reference(hotbar,
            "W_Inventory_ItemTooltip_ItemInSlotToAssignTo", compare_widget,
            "weaponComparison.transaction.slot")
        if not linked_slot then return false end

        if not copy_inventory_tooltip_info(inventory_main, hotbar) then
            return false
        end
        return call_hotbar_slot_tooltip(
            hotbar, weapon_position, true) == true
    end)

    -- Restore the borrowed UObject references and control flag immediately.
    -- ToolTipInfoBase/Slot are value scratch state owned by the hidden
    -- hotbar; UE4SS exposes them as live mapped structs, not copy snapshots.
    -- No InventoryMain widget reference may survive this native call.
    local slot_restored = restore_widget_reference(hotbar,
        "W_Inventory_ItemTooltip_ItemInSlotToAssignTo",
        previous_slot_widget, "weaponComparison.transaction.restoreSlot")
    local base_restored = restore_widget_reference(hotbar,
        "W_Inventory_ItemTooltip_ItemToAssign",
        previous_base_widget, "weaponComparison.transaction.restoreBase")
    local show_restored = set_property_value(hotbar, "ShowToolTips",
        previous_show_tooltips) == true
        and bool_property(hotbar, "ShowToolTips")
            == previous_show_tooltips
    weapon_comparison_bridge_busy = false

    local restored = slot_restored and base_restored and show_restored
    local succeeded = call_ok and route_ok == true and restored
    pleasureLib:debug_log("completed scoped hotbar comparison"
        .. " callOk=" .. tostring(call_ok)
        .. " routeOk=" .. tostring(route_ok)
        .. " restored=" .. tostring(restored))
    if succeeded then return true, nil end
    return false, call_ok and "native route or restore failed"
        or tostring(route_ok)
end

local function begin_weapon_comparison(
    inventory_main, weapon_type, definition_name, source_slot_key,
    source_item_pos, comparison_token, attempt)
    attempt = tonumber(attempt) or 0
    if weapon_type == nil or source_item_pos == nil then
        return false, false, "invalid comparison snapshot"
    end
    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.token ~= comparison_token
    then
        return false, false, "comparison request changed"
    end

    local source_inventory_main_key =
        active_inventory_comparison.inventory_main_key
    if weapon_comparison_source_matches(source_inventory_main_key,
        source_slot_key, source_item_pos, weapon_type, definition_name)
    then
        maintain_weapon_comparison_visibility(
            active_weapon_comparison.compare_widget,
            "weaponComparison.unchanged")
        -- A regular inventory refresh evaluates the weapon's native specs
        -- and collapses this already-configured wearable-comparison input.
        -- Restore only its visibility; never mutate the shared item definition.
        force_weapon_comparison_hint(inventory_main, true,
            "weaponComparison.unchanged")
        return true, false, nil
    end

    if weapon_comparison_bridge_busy then
        return false, false, "comparison bridge busy"
    end

    local hotbar = find_weapon_hotbar(
        inventory_main, weapon_type, attempt)
    if not is_valid(hotbar) then
        return false, true, "vanilla hotbar unavailable"
    end

    local weapon_position, weapon_definition, hotbar_ready =
        first_hotbar_weapon_position(hotbar, weapon_type)
    if weapon_position == nil or not is_valid(weapon_definition) then
        if hotbar_ready ~= true then
            return false, true, "hotbar inventory not ready"
        end
        return false, true, "matching hotbar weapon unavailable"
    end

    local base_widget = inventory_main_tooltip_widget(inventory_main)
    local compare_widget = inventory_weapon_compare_widget(inventory_main)
    if not is_valid(base_widget) or not is_valid(compare_widget) then
        return false, true, "inventory tooltip widgets unavailable"
    end

    local hotbar_slot_count = array_length(property_value(hotbar, "m_SlotsData"))
    if hotbar_slot_count == nil or weapon_position == nil or weapon_position < 0
        or weapon_position >= hotbar_slot_count
    then
        return false, true, "hotbar slot index unavailable"
            .. " position=" .. tostring(weapon_position)
            .. " slotCount=" .. tostring(hotbar_slot_count)
    end
    pleasureLib:debug_log("resolved hotbar weapon comparison entry"
        .. " position=" .. tostring(weapon_position)
        .. " inventoryType=" .. tostring(weapon_type)
        .. " definition=" .. full_name(weapon_definition))

    -- Hotbar creation can dispatch UI events. Do not enter the native bridge
    -- if one of them replaced this hover while readiness was being resolved.
    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.token ~= comparison_token
        or active_inventory_comparison.inventory_main_key
            ~= source_inventory_main_key
        or active_inventory_comparison.slot_key ~= source_slot_key
        or active_inventory_comparison.item_pos ~= source_item_pos
    then
        return false, false, "comparison request changed during readiness"
    end

    if active_weapon_comparison.active == true then
        end_weapon_comparison("weaponComparison.replace")
    end

    local route_ok, route_error = run_weapon_comparison_bridge(
        hotbar, inventory_main, base_widget, compare_widget,
        weapon_position)
    if not route_ok then
        set_widget_visibility(compare_widget, 1,
            "weaponComparison.bridgeFailed", true)
        pleasureLib:debug_log("weapon comparison native route failed"
            .. " reason=" .. tostring(route_error)
            .. " inventoryType=" .. tostring(weapon_type)
            .. " position=" .. tostring(weapon_position)
            .. " definition=" .. tostring(definition_name))
        -- A native bridge failure is not retried for the same hover.
        return false, false, route_error
    end

    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.token ~= comparison_token
        or active_inventory_comparison.slot_key ~= source_slot_key
        or active_inventory_comparison.item_pos ~= source_item_pos
    then
        set_widget_visibility(compare_widget, 1,
            "weaponComparison.requestChanged", true)
        return false, false, "comparison request changed during bridge"
    end

    active_weapon_comparison.active = true
    active_weapon_comparison.token = active_weapon_comparison.token + 1
    active_weapon_comparison.compare_widget = compare_widget
    active_weapon_comparison.source_inventory_main_key =
        source_inventory_main_key
    active_weapon_comparison.source_slot_key = source_slot_key
    active_weapon_comparison.source_item_pos = source_item_pos
    active_weapon_comparison.source_weapon_type = weapon_type
    active_weapon_comparison.source_definition_name = definition_name

    maintain_weapon_comparison_visibility(compare_widget,
        "weaponComparison")
    -- UpdateToolTipOnSlot refreshes the base tooltip synchronously and hides
    -- this input for weapons because they have no wearable ItemSpec. Reassert
    -- the configured CTRL hint only after the native bridge has returned.
    force_weapon_comparison_hint(inventory_main, true,
        "weaponComparison.afterBridge")
    pleasureLib:debug_log("weapon comparison active"
        .. " inventoryType=" .. tostring(weapon_type)
        .. " position=" .. tostring(weapon_position)
        .. " definition=" .. tostring(definition_name))
    return true, false, nil
end

local function invalidate_weapon_comparison_settle_timer()
    weapon_comparison_settle_timer_generation =
        weapon_comparison_settle_timer_generation + 1
    weapon_comparison_settle_pending = false
    weapon_comparison_settle_timer_due_at_ms = nil
end

local function clear_inventory_comparison_state()
    invalidate_weapon_comparison_settle_timer()
    active_inventory_comparison.active = false
    active_inventory_comparison.slot_key = nil
    active_inventory_comparison.item_pos = nil
    active_inventory_comparison.inventory_main = nil
    active_inventory_comparison.inventory_main_key = nil
    active_inventory_comparison.weapon_type = nil
    active_inventory_comparison.definition_name = nil
    active_inventory_comparison.resolution_attempt = 0
    active_inventory_comparison.comparison_attempt = 0
    active_inventory_comparison.settle_not_before_ms = nil
    weapon_comparison_hint_reassert_token = nil
    weapon_comparison_hint_reassert_inventory_main_key = nil
    weapon_comparison_hint_reassert_label = nil
end

local function end_inventory_comparison(inventory_main, label)
    if active_inventory_comparison.active ~= true then return false end

    active_inventory_comparison.token = active_inventory_comparison.token + 1
    end_weapon_comparison(tostring(label) .. ".weapon")
    clear_inventory_comparison_state()
    return true
end

reset_inventory_runtime_state = function(label)
    inventory_session_token = inventory_session_token + 1

    if active_equipped_hover.active == true then
        stop_active_equipped_hover(tostring(label) .. ".equipped")
    end
    if active_inventory_comparison.active == true then
        end_inventory_comparison(
            active_inventory_comparison.inventory_main,
            tostring(label) .. ".inventory")
    elseif active_weapon_comparison.active == true then
        end_weapon_comparison(tostring(label) .. ".weapon")
    end

    active_inventory_comparison.token =
        active_inventory_comparison.token + 1
    clear_inventory_comparison_state()
    active_equipped_hover.token = active_equipped_hover.token + 1
    last_hover_at = {}
    cached_inventory_main = nil
    cached_wearables_bar = nil
    cached_hotbar = nil
end

local function inventory_comparison_matches(slot, item_pos)
    if active_inventory_comparison.active ~= true then return false end
    return active_inventory_comparison.slot_key == object_instance_key(slot)
        and active_inventory_comparison.item_pos == item_pos
end

local schedule_weapon_comparison_settle = nil

local function settle_active_inventory_comparison()
    if active_inventory_comparison.active ~= true then return false end

    local comparison_token = active_inventory_comparison.token
    local inventory_main = active_inventory_comparison.inventory_main
    local inventory_main_key =
        active_inventory_comparison.inventory_main_key
    local item_pos = active_inventory_comparison.item_pos
    if not is_valid(inventory_main)
        or object_instance_key(inventory_main) ~= inventory_main_key
    then
        end_inventory_comparison(inventory_main,
            "comparison.inventoryUnavailable")
        return false
    end

    local weapon_type = active_inventory_comparison.weapon_type
    local definition_name =
        active_inventory_comparison.definition_name or ""
    if weapon_type == nil then
        local definition_resolved = false
        weapon_type, definition_name, definition_resolved =
            weapon_inventory_type_at_position(inventory_main, item_pos)
        if active_inventory_comparison.active ~= true
            or active_inventory_comparison.token ~= comparison_token
        then
            return false
        end

        if definition_resolved ~= true then
            local attempt =
                active_inventory_comparison.resolution_attempt + 1
            local delay_ms =
                WEAPON_COMPARISON_RETRY_DELAYS_MS[attempt]
            if delay_ms == nil then
                pleasureLib:debug_log(
                    "weapon classification readiness exhausted"
                    .. " itemPos=" .. tostring(item_pos)
                    .. " attempts=" .. tostring(
                        active_inventory_comparison.resolution_attempt))
                end_inventory_comparison(inventory_main,
                    "comparison.classificationUnavailable")
                return false
            end

            active_inventory_comparison.resolution_attempt = attempt
            pleasureLib:debug_log(
                "weapon classification waiting for inventory"
                .. " itemPos=" .. tostring(item_pos)
                .. " attempt=" .. tostring(attempt)
                .. " delayMs=" .. tostring(delay_ms))
            return schedule_weapon_comparison_settle(delay_ms)
        end

        if weapon_type == nil then
            end_inventory_comparison(inventory_main,
                "comparison.nativeItem")
            pleasureLib:debug_log("comparison uses native item handling"
                .. " definition=" .. tostring(definition_name))
            return false
        end

        active_inventory_comparison.weapon_type = weapon_type
        active_inventory_comparison.definition_name = definition_name
        active_inventory_comparison.resolution_attempt = 0
    end

    ensure_inventory_tooltip_activation(inventory_main,
        "comparison.settled")
    force_weapon_comparison_hint(inventory_main, true,
        "comparison.settled")
    if bool_property(inventory_main,
        "ShouldShowWearableCompare") ~= true
    then
        end_weapon_comparison("comparison.disabled")
        return true
    end

    local source_slot_key = active_inventory_comparison.slot_key
    local source_item_pos = active_inventory_comparison.item_pos
    local attempt = active_inventory_comparison.comparison_attempt
    local started, retry_ready, reason = begin_weapon_comparison(
        inventory_main, weapon_type, definition_name, source_slot_key,
        source_item_pos, comparison_token, attempt)
    if active_inventory_comparison.active ~= true
        or active_inventory_comparison.token ~= comparison_token
    then
        return false
    end
    if started then
        active_inventory_comparison.comparison_attempt = 0
        return true
    end
    if retry_ready ~= true then
        pleasureLib:debug_log("weapon comparison stopped for hover"
            .. " reason=" .. tostring(reason)
            .. " definition=" .. tostring(definition_name))
        return false
    end

    local next_attempt = attempt + 1
    local delay_ms = WEAPON_COMPARISON_RETRY_DELAYS_MS[next_attempt]
    if delay_ms == nil then
        pleasureLib:debug_log("weapon comparison readiness exhausted"
            .. " reason=" .. tostring(reason)
            .. " attempts=" .. tostring(attempt)
            .. " definition=" .. tostring(definition_name))
        end_inventory_comparison(inventory_main,
            "weaponComparison.readinessExhausted")
        return false
    end

    active_inventory_comparison.comparison_attempt = next_attempt
    pleasureLib:debug_log("weapon comparison waiting for readiness"
        .. " reason=" .. tostring(reason)
        .. " attempt=" .. tostring(next_attempt)
        .. " delayMs=" .. tostring(delay_ms)
        .. " definition=" .. tostring(definition_name))
    return schedule_weapon_comparison_settle(delay_ms)
end

schedule_weapon_comparison_settle = function(delay_ms)
    if active_inventory_comparison.active ~= true then return false end

    local inventory_main = active_inventory_comparison.inventory_main
    local now_ms = comparison_clock_ms(inventory_main)
    delay_ms = math.max(0, math.floor(tonumber(delay_ms)
        or weapon_comparison_hover_settle_ms(
            config.TooltipCooldownMs)))
    local timer_due_at_ms = nil
    if now_ms ~= nil then timer_due_at_ms = now_ms + delay_ms end

    -- Keep one effective wake-up. A later request can reuse the existing
    -- earlier timer; an earlier request supersedes it while the old callback
    -- becomes a generation-checked no-op.
    if weapon_comparison_settle_pending then
        if weapon_comparison_settle_timer_due_at_ms == nil
            or timer_due_at_ms == nil
            or weapon_comparison_settle_timer_due_at_ms
                <= timer_due_at_ms
        then
            return true
        end
    end

    weapon_comparison_settle_timer_generation =
        weapon_comparison_settle_timer_generation + 1
    local timer_generation =
        weapon_comparison_settle_timer_generation
    local scheduled_token = active_inventory_comparison.token
    local session_token = inventory_session_token
    weapon_comparison_settle_pending = true
    weapon_comparison_settle_timer_due_at_ms = timer_due_at_ms
    local scheduled = run_later(delay_ms, function()
        if timer_generation
            ~= weapon_comparison_settle_timer_generation
        then
            return
        end

        weapon_comparison_settle_pending = false
        weapon_comparison_settle_timer_due_at_ms = nil
        if active_inventory_comparison.active ~= true then return end

        local current_time_ms = comparison_clock_ms(
            active_inventory_comparison.inventory_main)
        local settle_not_before_ms = tonumber(
            active_inventory_comparison.settle_not_before_ms)
        if current_time_ms ~= nil
            and settle_not_before_ms ~= nil
            and current_time_ms < settle_not_before_ms
        then
            schedule_weapon_comparison_settle(
                settle_not_before_ms - current_time_ms)
            return
        end

        if inventory_session_token ~= session_token
            or active_inventory_comparison.token ~= scheduled_token
        then
            local replacement_delay_ms = 0
            if current_time_ms == nil
                or settle_not_before_ms == nil
            then
                replacement_delay_ms =
                    weapon_comparison_hover_settle_ms(
                        config.TooltipCooldownMs)
            end
            schedule_weapon_comparison_settle(replacement_delay_ms)
            return
        end
        settle_active_inventory_comparison()
    end)
    if not scheduled
        and timer_generation
            == weapon_comparison_settle_timer_generation
    then
        weapon_comparison_settle_pending = false
        weapon_comparison_settle_timer_due_at_ms = nil
    end
    return scheduled
end

local function schedule_weapon_comparison_hover_settle()
    if active_inventory_comparison.active ~= true then return false end

    local delay_ms = weapon_comparison_hover_settle_ms(
        config.TooltipCooldownMs)
    local current_time_ms = comparison_clock_ms(
        active_inventory_comparison.inventory_main)
    active_inventory_comparison.settle_not_before_ms = nil
    if current_time_ms ~= nil then
        active_inventory_comparison.settle_not_before_ms =
            current_time_ms + delay_ms
    end
    pleasureLib:debug_log("scheduled weapon comparison hover settle"
        .. " delayMs=" .. tostring(delay_ms)
        .. " itemPos="
        .. tostring(active_inventory_comparison.item_pos))
    return schedule_weapon_comparison_settle(delay_ms)
end

local function begin_inventory_comparison(slot)
    if config.EnableComparisonTooltips ~= true then return false end

    local inventory_main = related_object_with_name(slot, "W_Inventory_Main")
    if not is_valid(inventory_main) then
        if active_inventory_comparison.active == true then
            end_inventory_comparison(
                active_inventory_comparison.inventory_main,
                "comparison.inventoryMissing")
        end
        return false
    end
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

    -- The list slot is virtualized. Read everything needed while the hook
    -- owns a live object, then keep only scalar identity values.
    local slot_key = object_instance_key(slot)
    local item_pos = slot_item_pos(slot)
    if slot_key == "" or item_pos == nil or item_pos < 0 then
        if active_inventory_comparison.active == true then
            end_inventory_comparison(
                active_inventory_comparison.inventory_main,
                "comparison.snapshotInvalid")
        end
        return false
    end
    local inventory_main_key = object_instance_key(inventory_main)
    local weapon_type, definition_name, definition_resolved =
        weapon_inventory_type_at_position(inventory_main, item_pos)
    if definition_resolved == true and weapon_type == nil then
        if active_inventory_comparison.active == true then
            end_inventory_comparison(
                active_inventory_comparison.inventory_main,
                "comparison.nativeItem")
        end
        pleasureLib:debug_log("comparison uses native item handling"
            .. " definition=" .. tostring(definition_name))
        return false
    end

    local same_target = active_inventory_comparison.active == true
        and active_inventory_comparison.slot_key == slot_key
        and active_inventory_comparison.item_pos == item_pos
        and active_inventory_comparison.inventory_main_key
            == inventory_main_key
        and active_inventory_comparison.weapon_type == weapon_type
        and active_inventory_comparison.definition_name
            == definition_name
    if same_target then
        -- A re-hover of the same virtual row is still a newer event. Advance
        -- the epoch so a queued unhover from its prior incarnation cannot
        -- clear the current comparison.
        active_inventory_comparison.token =
            active_inventory_comparison.token + 1
        if weapon_type ~= nil then
            ensure_inventory_tooltip_activation(inventory_main,
                "comparison.rehover")
            force_weapon_comparison_hint(inventory_main, true,
                "comparison.rehover")
            schedule_weapon_comparison_hint_reassert(
                "comparison.rehover")
        end
        return schedule_weapon_comparison_hover_settle()
    end

    if active_weapon_comparison.active == true
        and not weapon_comparison_source_matches(inventory_main_key,
            slot_key, item_pos, weapon_type, definition_name)
    then
        end_weapon_comparison("weaponComparison.targetChanged")
    end

    active_inventory_comparison.active = true
    active_inventory_comparison.token =
        active_inventory_comparison.token + 1
    active_inventory_comparison.slot_key = slot_key
    active_inventory_comparison.item_pos = item_pos
    active_inventory_comparison.inventory_main = inventory_main
    active_inventory_comparison.inventory_main_key = inventory_main_key
    active_inventory_comparison.weapon_type = weapon_type
    active_inventory_comparison.definition_name = definition_name
    active_inventory_comparison.resolution_attempt = 0
    active_inventory_comparison.comparison_attempt = 0

    ensure_inventory_tooltip_activation(inventory_main,
        "comparison.snapshot")
    if weapon_type ~= nil then
        force_weapon_comparison_hint(inventory_main, true,
            "comparison.snapshot")
        schedule_weapon_comparison_hint_reassert(
            "comparison.snapshot")
    end
    pleasureLib:debug_log("queued stable weapon comparison snapshot"
        .. " itemPos=" .. tostring(item_pos)
        .. " weaponType=" .. tostring(weapon_type)
        .. " definition=" .. tostring(definition_name))
    return schedule_weapon_comparison_hover_settle()
end

local function on_comparison_toggled(_hook_name, context)
    local inventory_main = pleasureLib:unwrap(context)
    if not is_valid(inventory_main) then return nil end
    if active_inventory_comparison.active ~= true then return nil end
    if active_inventory_comparison.inventory_main_key
        ~= object_instance_key(inventory_main)
    then
        return nil
    end

    local enabled = bool_property(inventory_main,
        "ShouldShowWearableCompare") == true
    active_inventory_comparison.token =
        active_inventory_comparison.token + 1
    active_inventory_comparison.comparison_attempt = 0
    force_weapon_comparison_hint(inventory_main, true,
        "comparison.toggle")
    if enabled then
        -- Toggling does not restart the hover stability window. If it already
        -- elapsed, the native comparison starts on the next game-thread tick.
        schedule_weapon_comparison_settle(0)
    else
        end_weapon_comparison("comparison.toggleOff")
    end
    pleasureLib:debug_log("weapon comparison toggle handled"
        .. " enabled=" .. tostring(enabled)
        .. " itemPos=" .. tostring(
            active_inventory_comparison.item_pos))
    return nil
end

on_slot_hovered = function(_hook_name, context)
    if config.Enabled ~= true then return nil end

    local slot = pleasureLib:unwrap(context)
    if not is_valid(slot) then return nil end
    if slot_is_main_inventory(slot) then
        stop_active_equipped_hover("gridHover")
        begin_inventory_comparison(slot)
        return nil
    end
    if bool_property(slot, "IsWearableSlot") ~= true then return nil end

    if active_inventory_comparison.active == true then
        end_inventory_comparison(active_inventory_comparison.inventory_main,
            "equippedHover")
    end

    local item_pos = slot_item_pos(slot)
    if equipped_hover_matches(slot, item_pos)
        and not equipped_rehover_allowed(slot)
    then
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
        if bool_property(slot, "Hovered") == true then
            pleasureLib:debug_log("ignored recycled inventory unhover"
                .. " slot=" .. full_name(slot)
                .. " itemPos=" .. tostring(item_pos))
            return nil
        end
        if not inventory_comparison_matches(slot, item_pos) then
            pleasureLib:debug_log("ignored stale inventory unhover"
                .. " slot=" .. full_name(slot)
                .. " itemPos=" .. tostring(item_pos))
            return nil
        end

        -- Invalidate settle/readiness work immediately. The delayed cleanup
        -- exists only to let a following hover claim a newer token.
        active_inventory_comparison.token =
            active_inventory_comparison.token + 1
        local token = active_inventory_comparison.token
        local inventory_main = active_inventory_comparison.inventory_main
        run_later(10, function()
            if active_inventory_comparison.active == true
                and active_inventory_comparison.token == token
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

local function register_hook(path, handler, post_handler)
    if type(RegisterHook) ~= "function" then
        pleasureLib:log("RegisterHook unavailable")
        return false
    end
    if registered_hooks[path] == true then return false end

    if not ufunction_loaded(path) then
        if hook_retry_logged[path] ~= "not-loaded" then
            hook_retry_logged[path] = "not-loaded"
            pleasureLib:debug_log("Hook target not loaded yet; retrying "
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
        -- UE4SS executes callback two after Blueprint functions and ignores
        -- callback three. Route an explicitly requested post-handler into
        -- the only callback slot that Blueprint hooks support.
        primary_handler = post_handler or handler
        secondary_handler = nil
    end

    local ok, pre_id, post_id = pcall(function()
        if type(secondary_handler) == "function" then
            return RegisterHook(path, guarded(primary_handler),
                guarded(secondary_handler))
        end
        return RegisterHook(path, guarded(primary_handler))
    end)
    if not ok or (pre_id == nil and post_id == nil) then
        if hook_retry_logged[path] ~= "not-hookable" then
            hook_retry_logged[path] = "not-hookable"
            pleasureLib:debug_log("Hook target loaded but not hookable "
                .. path
                .. " error=" .. tostring(pre_id))
        end
        return false
    end

    registered_hooks[path] = true
    hook_retry_logged[path] = nil
    pleasureLib:debug_log("registered hook"
        .. " path=" .. tostring(path)
        .. " preId=" .. tostring(pre_id)
        .. " postId=" .. tostring(post_id))
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
    for _, path in ipairs(TOOLTIP_HINT_REFRESH_HOOKS) do
        if register_hook(path, nil, on_inventory_tooltip_updated) then
            count = count + 1
        end
    end
    return count
end

local function hook_path_groups()
    return {
        config.SlotHoverHooks or {},
        config.SlotUnhoverHooks or {},
        COMPARISON_TOGGLE_HOOKS,
        INVENTORY_SHOWN_HOOKS,
        TOOLTIP_HINT_REFRESH_HOOKS,
    }
end

local function pending_hook_group_count()
    local pending = 0
    for _, paths in ipairs(hook_path_groups()) do
        local has_candidates = false
        local has_registered_candidate = false
        for _, path in ipairs(paths) do
            has_candidates = true
            if registered_hooks[path] == true then
                has_registered_candidate = true
                break
            end
        end
        if has_candidates and not has_registered_candidate then
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
    pleasureLib:debug_log("all inventory hook groups registered")
end

local schedule_hook_registration_retry
schedule_hook_registration_retry = function(delay_override_ms)
    if pending_hook_group_count() == 0 then
        handle_hook_registration_complete()
        return true
    end
    if hook_registration_retry_pending == true then return true end

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
            math.max(HOOK_REGISTRATION_RETRY_INITIAL_MS,
                hook_registration_retry_delay_ms * 2),
            HOOK_REGISTRATION_RETRY_MAX_MS)
        schedule_hook_registration_retry()
    end)
    if not scheduled then
        hook_registration_retry_pending = false
        pleasureLib:log(
            "Could not schedule inventory hook registration retry.")
    end
    return scheduled
end

local function schedule_immediate_hook_registration_retry()
    if pending_hook_group_count() == 0 then
        handle_hook_registration_complete()
        return true
    end
    if hook_registration_immediate_pending == true then return true end

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
        pleasureLib:log("NotifyOnNewObject unavailable; late UI hooks cannot be registered.")
        return 0
    end

    local registered = 0
    for _, class_name in ipairs(UI_OBJECT_NOTIFY_CLASSES) do
        local notify_class = class_name
        local ok, result = pcall(function()
            return NotifyOnNewObject(notify_class, function(object)
                if not generation_is_current() then return end
                if handled_ui_notification_classes[notify_class] == true then
                    return
                end
                handled_ui_notification_classes[notify_class] = true
                pleasureLib:debug_log(
                    "UI object created; registering loaded hooks"
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
    register_game_settings()
    local notification_count = install_ui_object_notifications()
    local count = register_hooks()
    if pending_hook_group_count() == 0 then
        handle_hook_registration_complete()
    else
        schedule_hook_registration_retry()
    end
    pleasureLib:log("Loaded v" .. VERSION .. "; G1R wearable tooltip hooks registered="
        .. tostring(count)
        .. "; UI object notifications=" .. tostring(notification_count)
        .. ".")
end
