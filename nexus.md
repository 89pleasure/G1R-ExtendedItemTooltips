# Extended Item Tooltips

**Check out my other mods**

[G1R - Optimizer](https://www.nexusmods.com/gothic1remake/mods/68) | [G1R - Cancel Interactions](https://www.nexusmods.com/gothic1remake/mods/181) | [Let Snaf Cook](https://www.nexusmods.com/gothic1remake/mods/448) | [QuickBites](https://www.nexusmods.com/gothic1remake/mods/452)

Equipped gear should not feel like dead UI.

Extended Item Tooltips shows the game's existing tooltips when you hover
equipped armor, jewelry, or weapons. It also extends the native comparison flow
to compatible melee and ranged weapons in the backpack.

## Features

- Shows native item tooltips for equipped inventory slots
- Supports armor, jewelry, melee weapons, and ranged weapons
- Compares backpack weapons with equipped hotbar weapons of the same type
- Leaves the game's existing armor and jewelry comparison logic intact
- Uses the native UI and supports existing savegames
- Does not add items or change stats, balance, inventory contents, or save data

## Native Settings

PleasureLib adds native controls under
**Settings -> Mods -> Extended Item Tooltips**:

- **Show comparisons by default** determines whether compatible comparisons are
  already active when the inventory opens
- **Weapon comparison delay** controls how long a backpack weapon must remain
  hovered before its comparison is built (`150`-`500` ms)

Changes are saved automatically. The Left Ctrl hint appears immediately; only
the comparison update waits for a stable hover. Left Ctrl still toggles
comparisons temporarily while the inventory is open. No INI editing is needed
for normal use.

## Weapon Comparison

Weapons assigned to the hotbar act as the equipped comparison weapons. The mod
checks the hotbar from slot 1 upward and uses the first weapon of the matching
type:

- Melee weapons are compared with the first melee weapon
- Ranged weapons are compared with the first ranged weapon
- No comparison is shown without a matching hotbar weapon or when a weapon would
  be compared with itself

Armor, rings, and amulets continue to use the game's existing comparison logic.

## Requirements

- Gothic 1 Remake
- UE4SS
- PleasureLib 0.5.0 or newer

## Installation

Install PleasureLib and Extended Item Tooltips as neighboring folders in the
UE4SS `Mods` directory:

```text
G1R/Binaries/Win64/ue4ss/Mods/ExtendedItemTooltips/
G1R/Binaries/Win64/ue4ss/Mods/PleasureLib/
```

No additional setup is required.

## Advanced Configuration

Most players should use the native settings menu. Its values are stored in
`ExtendedItemTooltips.ini` as `ComparisonDefaultEnabled` and
`TooltipCooldownMs`.

The INI also provides master switches and troubleshooting options through
`Enabled`, `Debug`, `ForceTooltipVisibility`, and `EnableComparisonTooltips`.
Leave `SlotHoverHooks` and `SlotUnhoverHooks` empty unless a game update changes
the relevant inventory functions.

## Compatibility

The mod touches inventory slot hover behavior, the existing tooltip widgets, and
the native comparison toggle. It should be compatible with most mods unless they
modify the same UI functions.

## Updating from 0.18.0 or Older

Version 0.19.0 renamed the mod. With the game closed:

1. Rename `EquippedItemTooltips` to `ExtendedItemTooltips`
2. Rename `EquippedItemTooltips.ini` to `ExtendedItemTooltips.ini`
3. Replace the remaining files with the new version

Do not keep both mod folders installed.

## Source Code and Issues

Source code and issue tracking are available on
[GitHub](https://github.com/89pleasure/G1R-ExtendedItemTooltips).

Because if backpack items can tell you what they are, equipped items should be
polite enough to do the same.
