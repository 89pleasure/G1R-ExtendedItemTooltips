Extended Item Tooltips

UE4SS Lua mod for Gothic 1 Remake.
Version: 0.19.0

Requires PleasureLib.

Shows item tooltips when hovering equipped inventory items, using the game's existing wearable tooltip UI and compare flag where available.

EnableComparisonTooltips=true enables comparison support for compatible armor,
jewelry, and weapons. Left Ctrl toggles comparisons while the inventory is open.

Settings -> Game -> Mods contains a localized ON/OFF option that determines
whether comparisons start enabled whenever the inventory is opened. The same
value is available as ComparisonDefaultEnabled in the INI.

Config:
- ExtendedItemTooltips.ini

Troubleshooting:
- Set Debug=true, reload the game, hover equipped items, and check the UE4SS log.
- If tooltip forcing causes issues after a game update, set ForceTooltipVisibility=false.
- The mod uses the wearable tooltip widget's Visibility property directly; SetVisibility is not used.
