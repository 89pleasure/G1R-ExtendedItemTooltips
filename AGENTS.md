# Repository Guidelines

## Project Structure & Module Organization

This repository contains a UE4SS Lua mod for Gothic 1 Remake.

- `package/ExtendedItemTooltips/Scripts/main.lua` contains module wiring,
  cross-controller routing, hook dispatch, and UE4SS integration.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_config.lua`
  owns defaults, INI loading, localization, and game-settings registration.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_runtime.lua`
  provides reload-safe UE4SS object, reflection, delegate, timer, and clock
  helpers.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_inventory.lua`
  owns stateless slot, inventory-item, and weapon classification queries.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_discovery.lua`
  resolves and caches the active inventory and equipped-wearables widgets.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_hooks.lua`
  owns hook registration, late-UI notifications, and retry state.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_hotbar.lua`
  resolves the weapon hotbar and owns its cache and creation-attempt state.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_equipped_hover.lua`
  owns equipped-slot hover state, dispatcher calls, and visibility retries.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_inventory_comparison.lua`
  owns inventory comparison snapshots, settling, retries, and hook handling.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_widgets.lua`
  owns tooltip widget discovery, reference linking, and visibility operations.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_weapon_state.lua`
  owns the active weapon-comparison identity and widget visibility lifecycle.
- `package/ExtendedItemTooltips/Scripts/extended_item_tooltips_weapon_bridge.lua`
  owns the scoped native hotbar comparison transaction and restoration.
- `package/ExtendedItemTooltips/ExtendedItemTooltips.ini` is the user-facing configuration file.
- `package/ExtendedItemTooltips/enabled.txt` and `readme.txt` are packaged with the mod.
- `README.md` is the public project documentation.
- `assets/nexus/` stores Nexus Mods image assets.
- `package/ExtendedItemTooltips.zip` is package output; avoid editing it by hand.

There is currently no separate test suite or build system.

## Build, Test, and Development Commands

No build step is required. To install for local testing, copy the mod folder:

```powershell
Copy-Item .\package\ExtendedItemTooltips `
  "D:\SteamLibrary\steamapps\common\Gothic 1 Remake\G1R\Binaries\Win64\ue4ss\Mods\" `
  -Recurse -Force
```

Useful checks:

```powershell
rg -n "Tooltip|Hover|ForceTooltipVisibility" package/ExtendedItemTooltips
git diff
```

On this machine, `git` may not be on `PATH`. Use the GitHub Desktop bundled binary when needed:

```powershell
& "C:\Users\lenna\AppData\Local\GitHubDesktop\app-3.6.2\resources\app\git\cmd\git.exe" status --short
```

If a Lua interpreter is available, syntax-check every packaged script:

```powershell
Get-ChildItem package/ExtendedItemTooltips/Scripts -Filter *.lua |
  ForEach-Object { luac -p $_.FullName }
```

## Coding Style & Naming Conventions

Use Lua with 4-space indentation and local functions/variables. Keep constants near the top of `main.lua` and use uppercase names for hook and method candidate lists. Prefer small helper functions over inline repeated logic. Keep files ASCII-only unless existing game text requires otherwise.

## Testing Guidelines

Primary testing is in-game through UE4SS. Verify:

- open the inventory and hover equipped armor, rings, amulet, melee weapon, ranged weapon, and quick/equipment slots
- existing backpack item tooltips still work
- tooltip disappears normally when the cursor leaves a slot or the inventory closes
- `Debug=false` keeps logs quiet

Check UE4SS logs for `Loaded config from ...`, registered hook counts, and any debug lines when `Debug=true`.

## Commit & Pull Request Guidelines

Commit history uses short imperative messages, for example `Show equipped item tooltips`. Keep commits focused on one behavior or documentation change.

Pull requests should include a concise summary, changed files, in-game test notes, and any relevant UE4SS log output. If visual/Nexus assets change, include before/after screenshots.

## Configuration Notes

`ExtendedItemTooltips.ini` supports `Enabled`, `Debug`, `TooltipCooldownMs`,
`ForceTooltipVisibility`, `EnableComparisonTooltips`,
`ComparisonDefaultEnabled`, and optional semicolon-separated override lists for
inventory slot hover/unhover hook candidates.
