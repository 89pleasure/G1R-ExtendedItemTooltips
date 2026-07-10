# Equipped Item Tooltips

Equipped Item Tooltips is a UE4SS Lua mod for Gothic 1 Remake. It tries to show the same item tooltip for equipped inventory items that backpack items already show when hovered.

The current target is the inventory equipment area shown on the character sheet: armor, jewelry, weapons, and other equipped slots should no longer feel like dead UI when the mouse is over them.

## Requirements

- Gothic 1 Remake
- UE4SS installed and enabled for the game

## Installation

1. Create this folder in the game's UE4SS mods directory:

   ```text
   <GameDir>/G1R/Binaries/Win64/ue4ss/Mods/EquippedItemTooltips/
   ```

2. Copy the contents of `package/EquippedItemTooltips` into that folder.
3. Start the game with UE4SS enabled.

## Configuration

Defaults live in `EquippedItemTooltips.ini`:

```ini
Enabled=true
Debug=false
TooltipCooldownMs=40
ForceTooltipVisibility=true
```

Leave `Debug=false` for normal play. Enable it only while collecting UE4SS log output for inventory hover issues.

`ForceTooltipVisibility=true` keeps the game's wearable tooltip widget visible while an equipped item slot is actively hovered. If that widget is not linked by the game UI, the mod links it to the `EquippedWearables` bar before broadcasting the hover event and temporarily enables the wearable-compare flag. Disable this if a future game update starts showing equipped item tooltips natively.

The mod writes the wearable tooltip widget's `Visibility` property directly. This is the path confirmed by UE4SS logs; the inherited `SetVisibility` function is not used.

Advanced users can override the inventory slot hover/unhover hook candidates with semicolon-separated INI values.

## Development Notes

The mod is deliberately defensive. Gothic 1 Remake UI internals can vary between builds, so reflected object access and UI calls are wrapped in `pcall`.

The implementation is based on the UE4SS object dump from the game directory. It links the `EquippedWearables` bar to the inventory's wearable tooltip widget, broadcasts wearable slot hover events, reads the game's current `ToolTipInfoSlot`, enables the inventory tooltip and wearable-compare flags, and keeps the wearable tooltip visible through the widget `Visibility` property while the equipped slot hover is active. If a game update changes these function names, add semicolon-separated overrides in the INI.
