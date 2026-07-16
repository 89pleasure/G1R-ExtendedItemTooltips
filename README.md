# Extended Item Tooltips

Extended Item Tooltips is a UE4SS Lua mod for Gothic 1 Remake. It shows
tooltips for equipped inventory items and extends the game's native comparison
flow to compatible backpack weapons.

Armor, jewelry, weapons, and other equipped slots no longer feel like dead UI
when the mouse is over them. Melee and ranged weapons in the backpack can be
compared with the first weapon of the same type assigned to the hotbar.

## Requirements

- Gothic 1 Remake
- UE4SS installed and enabled for the game
- PleasureLib installed next to this mod in the UE4SS `Mods` directory

## Installation

1. Create this folder in the game's UE4SS mods directory:

   ```text
   <GameDir>/G1R/Binaries/Win64/ue4ss/Mods/ExtendedItemTooltips/
   ```

2. Copy the contents of `package/ExtendedItemTooltips` into that folder.
3. Install `PleasureLib` as a neighboring UE4SS mod if it is not already present.
4. Start the game with UE4SS enabled.

## Configuration

Defaults live in `ExtendedItemTooltips.ini`:

```ini
Enabled=true
Debug=false
TooltipCooldownMs=40
ForceTooltipVisibility=true
EnableComparisonTooltips=true
ComparisonDefaultEnabled=false
```

Leave `Debug=false` for normal play. Enable it only while collecting UE4SS log output for inventory hover issues.

`ForceTooltipVisibility=true` keeps the game's wearable tooltip widget visible while an equipped item slot is actively hovered. If that widget is not linked by the game UI, the mod links it to the `EquippedWearables` bar before broadcasting the hover event and temporarily enables the wearable-compare flag. Disable this if a future game update starts showing equipped item tooltips natively.

`EnableComparisonTooltips=true` enables comparison support. By default, comparisons
remain off until Left Ctrl is pressed, matching the game's native toggle behavior.

`ComparisonDefaultEnabled` is also available as a native ON/OFF option under
`Settings -> Game -> Mods`. When enabled, compatible armor, jewelry, melee, and
ranged comparisons start enabled whenever the inventory is opened. Left Ctrl can
still toggle comparisons temporarily. The menu selection is saved back to the INI.

The mod writes the wearable tooltip widget's `Visibility` property directly. This is the path confirmed by UE4SS logs; the inherited `SetVisibility` function is not used.

Advanced users can override the inventory slot hover/unhover hook candidates with semicolon-separated INI values.

## Updating from Equipped Item Tooltips

Version 0.19.0 renamed the mod and its technical identifiers. With the game
closed, rename the existing `EquippedItemTooltips` mod folder to
`ExtendedItemTooltips` and rename `EquippedItemTooltips.ini` inside it to
`ExtendedItemTooltips.ini`. Then replace the remaining files with the new
version. Do not keep both mod folders installed, because both versions would
register the same inventory hooks.

## Development Notes

The mod is deliberately defensive. Gothic 1 Remake UI internals can vary between builds, so reflected object access and UI calls are wrapped in `pcall`.

The implementation is based on the UE4SS object dump from the game directory. It links the `EquippedWearables` bar to the inventory's wearable tooltip widget, broadcasts wearable slot hover events, reads the game's current `ToolTipInfoSlot`, and keeps the wearable tooltip visible while the equipped slot hover is active. For backpack equipment, it invokes the game's native `DoToggleWearableComparisonTooltip` function with a boolean only; no tooltip data structures are marshalled through Lua. If a game update changes the slot function names, add semicolon-separated overrides in the INI.
