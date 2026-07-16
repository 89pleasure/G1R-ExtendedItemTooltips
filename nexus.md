# Extended Item Tooltips

**Checkout my other mods**

[G1R - Optimizer](https://www.nexusmods.com/gothic1remake/mods/68) | [G1R - Cancel Interactions](https://www.nexusmods.com/gothic1remake/mods/181) | [Let Snaf Cook](https://www.nexusmods.com/gothic1remake/mods/448) | [QuickBites](https://www.nexusmods.com/gothic1remake/mods/452)

Equipped gear should not feel like dead UI.

In the inventory, backpack items already show useful tooltips when you hover them. Equipped items, however, can sit right there on the character sheet without showing the same information. Armor, rings, amulets, weapons, and similar equipped slots deserve the same treatment.

This UE4SS Lua mod shows item tooltips when hovering equipped inventory items
and extends the game's native comparison flow to compatible backpack weapons.

## What It Does

- Shows the game's existing item tooltip for equipped inventory slots
- Works for wearable/equipment slots such as armor, jewelry, and weapons
- Adds comparison support for compatible backpack melee and ranged weapons
- Leaves the game's existing armor, ring, and amulet comparisons untouched
- Adds a localized ON/OFF option under Settings -> Game -> Mods for enabling comparisons by default
- Uses the game's existing tooltip UI
- Does not add new items
- Does not change item stats, balance, equipment, or inventory contents
- Existing savegames are supported
- Does not modify savegame data

## How Comparison Works

Left Ctrl toggles the native comparison view while the inventory is open. You
can choose whether comparisons start enabled under Settings -> Game -> Mods.
That preference is saved and restored automatically.

Armor, rings, and amulets continue to use the game's existing comparison logic.
The mod extends that same comparison flow to melee and ranged weapons.

Weapons assigned to the hotbar act as the equipped comparison weapons. When
several weapons of the same type are assigned, the mod checks the hotbar from
slot 1 upward and uses the first matching weapon:

- Melee weapons are compared with the first melee weapon in the hotbar
- Ranged weapons are compared with the first ranged weapon in the hotbar
- If the hotbar contains no weapon of the matching type, no comparison tooltip
  is shown
- A weapon that is itself assigned to the hotbar does not start a comparison
  with itself

Advanced users can override the inventory slot hover/unhover hook paths in the ini file:

```ini
SlotHoverHooks=
SlotUnhoverHooks=
```

Leave these empty unless a game update changes the widget function names.

## Requirements

- Gothic 1 Remake
- UE4SS
- PleasureLib 0.3.31 or newer

## Installation

Install PleasureLib and Extended Item Tooltips as neighboring folders in your
UE4SS Mods directory:

```text
G1R/Binaries/Win64/ue4ss/Mods/ExtendedItemTooltips/
G1R/Binaries/Win64/ue4ss/Mods/PleasureLib/
```

The installed folder should include:

```text
ExtendedItemTooltips/enabled.txt
ExtendedItemTooltips/ExtendedItemTooltips.ini
ExtendedItemTooltips/readme.txt
ExtendedItemTooltips/Scripts/main.lua
ExtendedItemTooltips/Scripts/pleasure_lib_loader.lua
```

## Optional INI Configuration

You can edit ExtendedItemTooltips.ini in the mod folder:

```ini
Enabled=true
Debug=false
TooltipCooldownMs=40
ForceTooltipVisibility=true
EnableComparisonTooltips=true
ComparisonDefaultEnabled=false
```

Leave Debug=false for normal play.

Enable Debug=true only when collecting UE4SS log output for hover or tooltip issues.

TooltipCooldownMs controls how quickly repeated hover events on the same slot are handled. The default value should feel instant while avoiding noisy duplicate events.

ForceTooltipVisibility keeps the game's wearable tooltip widget visible while an equipped item slot is actively hovered. Disable this only if a future game update starts showing equipped item tooltips natively or if you are troubleshooting UI conflicts.

EnableComparisonTooltips enables or disables comparison support completely.

ComparisonDefaultEnabled controls whether comparisons start enabled whenever
the inventory is opened. It stores the same value as the in-game option under
Settings -> Game -> Mods.

## Compatibility

This mod touches inventory slot hover behavior, the existing wearable tooltip widget, and the native comparison toggle. It should be compatible with most other mods unless they modify the same inventory functions or tooltip visibility handling.

No new items, stats, quests, save data, or balance changes are introduced.

## Updating

### Updating from Equipped Item Tooltips 0.18.0 or Older

Version 0.19.0 renamed the mod and its technical identifiers. With the game
closed:

1. Rename the existing `EquippedItemTooltips` folder to `ExtendedItemTooltips`
2. Rename `EquippedItemTooltips.ini` inside it to `ExtendedItemTooltips.ini`
3. Replace the remaining files with the new version

Do not keep both mod folders installed. Both versions would register the same
inventory hooks.

If you customized the old INI, renaming it preserves your existing values.

## Changelog

### Initial Release

- Added equipped item tooltips for inventory equipment slots
- Uses the game's current ToolTipInfoSlot after equipped-slot hover
- Keeps the existing wearable tooltip widget visible through its Visibility property
- Restores the wearable-compare flag when the cursor leaves the equipped slot
- Reduced the implementation to the confirmed working hover/unhover hooks

### Native Weapon Comparison

- Added comparison support for compatible backpack melee and ranged weapons
- Uses the game's native comparison filtering and layout
- Checks the hotbar from slot 1 upward and uses the first weapon of the matching type
- Shows no weapon comparison when the hotbar has no matching weapon
- Leaves armor, ring, and amulet comparison handling to the base game

### Native Settings Integration

- Added a localized ON/OFF option under Settings -> Game -> Mods
- Added persistent ComparisonDefaultEnabled state
- Added PleasureLib integration for reusable native mod settings
- Keeps only one functional entry across complete settings-menu recreation

### Renamed to Extended Item Tooltips

- Renamed the visible and technical mod name to Extended Item Tooltips
- Renamed the UE4SS mod folder and INI to `ExtendedItemTooltips`
- Renamed the runtime, native setting ID, hot-reload namespace, and package assets
- Updated the version to 0.19.0

## Current Version

`0.19.0`

## Why?

Because if backpack items can tell you what they are, equipped items should be polite enough to do the same.

## Source Code and Issues

The source code and issue tracker are available on
[GitHub](https://github.com/89pleasure/G1R-ExtendedItemTooltips).
