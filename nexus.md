# Equipped Item Tooltips

Equipped gear should not feel like dead UI.

In the inventory, backpack items already show useful tooltips when you hover them. Equipped items, however, can sit right there on the character sheet without showing the same information. Armor, rings, amulets, weapons, and similar equipped slots deserve the same treatment.

This UE4SS Lua mod shows item tooltips when hovering equipped inventory items and automatically compares compatible backpack equipment with currently equipped gear.

## What It Does

- Shows the game's existing item tooltip for equipped inventory slots
- Works for wearable/equipment slots such as armor, jewelry, and weapons
- Adds native comparison support for compatible backpack armor, jewelry, and weapons
- Adds a localized ON/OFF option under Settings -> Game -> Mods for enabling comparisons by default
- Uses the game's existing tooltip UI
- Does not add new items
- Does not change item stats, balance, equipment, or inventory contents
- Existing savegames are supported
- The mod only changes equipped-slot hover tooltip behavior

## Manual Configuration

You can edit EquippedItemTooltips.ini in the mod folder:

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

EnableComparisonTooltips enables the comparison feature. Left Ctrl toggles the
native comparison view while the inventory is open.

ComparisonDefaultEnabled determines whether comparisons start enabled whenever
the inventory is opened. The same option is available in-game under
Settings -> Game -> Mods and changes made there are saved to this INI.

Advanced users can override the inventory slot hover/unhover hook paths in the ini file:

```ini
SlotHoverHooks=
SlotUnhoverHooks=
```

Leave these empty unless a game update changes the widget function names.

## Requirements

- Gothic 1 Remake
- UE4SS

## Installation

Install the mod folder into your UE4SS Mods directory:

```text
G1R/Binaries/Win64/ue4ss/Mods/EquippedItemTooltips/
```

The installed folder should include:

```text
EquippedItemTooltips/enabled.txt
EquippedItemTooltips/EquippedItemTooltips.ini
EquippedItemTooltips/readme.txt
EquippedItemTooltips/Scripts/main.lua
```

## Compatibility

This mod touches inventory slot hover behavior, the existing wearable tooltip widget, and the native comparison toggle. It should be compatible with most other mods unless they modify the same inventory functions or tooltip visibility handling.

No new items, stats, quests, save data, or balance changes are introduced.

## Updating

When updating from an older version, replace or merge the whole EquippedItemTooltips folder.

If you customized EquippedItemTooltips.ini, you can keep your existing values.

## Changelog

### Initial Release

- Added equipped item tooltips for inventory equipment slots
- Uses the game's current ToolTipInfoSlot after equipped-slot hover
- Keeps the existing wearable tooltip widget visible through its Visibility property
- Restores the wearable-compare flag when the cursor leaves the equipped slot
- Reduced the implementation to the confirmed working hover/unhover hooks

### Native Comparison

- Added automatic comparison for compatible backpack equipment
- Uses the game's native comparison filtering and layout
- Supports armor, jewelry, melee weapons, and ranged weapons where the game marks them as compatible

## Why?

Because if backpack items can tell you what they are, equipped items should be polite enough to do the same.
