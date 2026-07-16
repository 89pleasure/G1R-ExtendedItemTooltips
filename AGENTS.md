# Repository Guidelines

## Project Structure & Module Organization

This repository contains a UE4SS Lua mod for Gothic 1 Remake.

- `package/ExtendedItemTooltips/Scripts/main.lua` contains all runtime mod logic.
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

If a Lua interpreter is available, run a syntax check with `luac -p package/ExtendedItemTooltips/Scripts/main.lua`.

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

`ExtendedItemTooltips.ini` supports `Enabled`, `Debug`, `TooltipCooldownMs`, `ForceTooltipVisibility`, `EnableComparisonTooltips`, and optional semicolon-separated override lists for inventory slot hover/unhover hook candidates.
