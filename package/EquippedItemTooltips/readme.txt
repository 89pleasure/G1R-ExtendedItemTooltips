Equipped Item Tooltips

UE4SS Lua mod for Gothic 1 Remake.

Shows item tooltips when hovering equipped inventory items, using the game's existing wearable tooltip UI and compare flag where available.

Config:
- EquippedItemTooltips.ini

Troubleshooting:
- Set Debug=true, reload the game, hover equipped items, and check the UE4SS log.
- If tooltip forcing causes issues after a game update, set ForceTooltipVisibility=false.
- The mod uses the wearable tooltip widget's Visibility property directly; SetVisibility is not used.
