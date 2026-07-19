local Config = {}

local CONFIG_FILE_NAME = "ExtendedItemTooltips.ini"
local WEAPON_COMPARISON_DELAY_MIN_MS = 150
local WEAPON_COMPARISON_DELAY_MAX_MS = 500

local DEFAULT_CONFIG = {
    Enabled = true,
    Debug = false,
    TooltipCooldownMs = WEAPON_COMPARISON_DELAY_MIN_MS,
    ForceTooltipVisibility = true,
    EnableComparisonTooltips = true,
    ComparisonDefaultEnabled = false,
}

local SLOT_HOVER_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Slot.W_Inventory_Slot_C:OnHovered",
}

local SLOT_UNHOVER_HOOKS = {
    "/Game/UI/ManagementUI/Inventory/W_Inventory_Slot.W_Inventory_Slot_C:OnUnhovered",
}

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

local function clamp_weapon_comparison_delay_ms(value)
    local delay_ms = math.floor(tonumber(value)
        or DEFAULT_CONFIG.TooltipCooldownMs)
    return math.max(WEAPON_COMPARISON_DELAY_MIN_MS,
        math.min(WEAPON_COMPARISON_DELAY_MAX_MS, delay_ms))
end

function Config.new(pleasure_lib)
    if type(pleasure_lib) ~= "table" then return nil end

    local config = {}

    local function merge_list(defaults, override)
        local parsed = pleasure_lib:split_list(override)
        if #parsed > 0 then return parsed end
        return pleasure_lib:copy_array(defaults)
    end

    local function config_candidate_paths()
        local paths = {}
        local dir = pleasure_lib:script_directory()
        if dir then
            table.insert(paths, dir .. "..\\" .. CONFIG_FILE_NAME)
            table.insert(paths, dir .. CONFIG_FILE_NAME)
        end
        table.insert(paths,
            "Mods\\ExtendedItemTooltips\\" .. CONFIG_FILE_NAME)
        table.insert(paths,
            "ue4ss\\Mods\\ExtendedItemTooltips\\" .. CONFIG_FILE_NAME)
        table.insert(paths, CONFIG_FILE_NAME)
        return paths
    end

    local function reset_config()
        for key in pairs(config) do
            config[key] = nil
        end
        config.Enabled = DEFAULT_CONFIG.Enabled
        config.Debug = DEFAULT_CONFIG.Debug
        config.TooltipCooldownMs = DEFAULT_CONFIG.TooltipCooldownMs
        config.ForceTooltipVisibility =
            DEFAULT_CONFIG.ForceTooltipVisibility
        config.EnableComparisonTooltips =
            DEFAULT_CONFIG.EnableComparisonTooltips
        config.ComparisonDefaultEnabled =
            DEFAULT_CONFIG.ComparisonDefaultEnabled
        config.SlotHoverHooks = SLOT_HOVER_HOOKS
        config.SlotUnhoverHooks = SLOT_UNHOVER_HOOKS
    end

    local function load()
        reset_config()

        for _, path in ipairs(config_candidate_paths()) do
            local content = pleasure_lib:read_text_file(path)
            if content ~= nil then
                local ini = pleasure_lib:parse_ini(content)
                config.Enabled = pleasure_lib:parse_bool(
                    ini.ENABLED, config.Enabled)
                config.Debug = pleasure_lib:parse_bool(
                    ini.DEBUG, config.Debug)
                config.ForceTooltipVisibility = pleasure_lib:parse_bool(
                    ini.FORCETOOLTIPVISIBILITY,
                    config.ForceTooltipVisibility)
                config.EnableComparisonTooltips = pleasure_lib:parse_bool(
                    ini.ENABLECOMPARISONTOOLTIPS,
                    config.EnableComparisonTooltips)
                config.ComparisonDefaultEnabled = pleasure_lib:parse_bool(
                    ini.COMPARISONDEFAULTENABLED,
                    config.ComparisonDefaultEnabled)
                local configured_cooldown =
                    tonumber(ini.TOOLTIPCOOLDOWNMS)
                        or config.TooltipCooldownMs
                config.TooltipCooldownMs =
                    clamp_weapon_comparison_delay_ms(configured_cooldown)
                config.SlotHoverHooks = merge_list(
                    SLOT_HOVER_HOOKS, ini.SLOTHOVERHOOKS)
                config.SlotUnhoverHooks = merge_list(
                    SLOT_UNHOVER_HOOKS, ini.SLOTUNHOVERHOOKS)

                config.ConfigPath = path
                pleasure_lib:set_debug(config.Debug)
                if configured_cooldown ~= config.TooltipCooldownMs then
                    local normalized = pleasure_lib:update_ini_value(
                        path, "TooltipCooldownMs",
                        tostring(config.TooltipCooldownMs))
                    pleasure_lib:debug_log(
                        "clamped weapon comparison delay"
                        .. " configuredMs=" .. tostring(configured_cooldown)
                        .. " effectiveMs="
                        .. tostring(config.TooltipCooldownMs)
                        .. " persisted=" .. tostring(normalized))
                end
                pleasure_lib:log("Loaded config from " .. tostring(path)
                    .. ": Enabled=" .. tostring(config.Enabled)
                    .. " Debug=" .. tostring(config.Debug)
                    .. " ForceTooltipVisibility="
                    .. tostring(config.ForceTooltipVisibility)
                    .. " EnableComparisonTooltips="
                    .. tostring(config.EnableComparisonTooltips)
                    .. " ComparisonDefaultEnabled="
                    .. tostring(config.ComparisonDefaultEnabled)
                    .. " TooltipCooldownMs="
                    .. tostring(config.TooltipCooldownMs))
                return config
            end
        end

        pleasure_lib:set_debug(config.Debug)
        pleasure_lib:log("Config not found; using defaults.")
        return config
    end

    local function setting_persist_options(key)
        return {
            path = function() return config.ConfigPath end,
            key = key,
        }
    end

    local function register_game_settings()
        pleasure_lib:register_game_bool_setting({
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
            persist = setting_persist_options(
                "ComparisonDefaultEnabled"),
            translations = COMPARISON_DEFAULT_SETTING_TRANSLATIONS,
        })

        local required_api = {
            "register_game_int_setting",
        }
        for _, api_name in ipairs(required_api) do
            if type(pleasure_lib[api_name]) ~= "function" then
                pleasure_lib:log(
                    "PleasureLib 0.5.0 settings API unavailable: "
                    .. api_name)
                return false
            end
        end

        pleasure_lib:register_game_int_setting({
            id = "ExtendedItemTooltips.TooltipCooldownMs",
            section = "Extended Item Tooltips",
            minimum = WEAPON_COMPARISON_DELAY_MIN_MS,
            maximum = WEAPON_COMPARISON_DELAY_MAX_MS,
            default = DEFAULT_CONFIG.TooltipCooldownMs,
            get = function()
                return config.TooltipCooldownMs
            end,
            set = function(value)
                config.TooltipCooldownMs =
                    clamp_weapon_comparison_delay_ms(value)
                return true
            end,
            persist = setting_persist_options("TooltipCooldownMs"),
            translations = WEAPON_COMPARISON_DELAY_SETTING_TRANSLATIONS,
        })

        return true
    end

    return {
        values = config,
        load = load,
        register_game_settings = register_game_settings,
        clamp_weapon_comparison_delay_ms =
            clamp_weapon_comparison_delay_ms,
    }
end

return Config
