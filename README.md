# Skada for Wrath of the Lich King `3.3.5`
Skada is a modular damage meter with various viewing modes, segmented fights and customizable windows. It aims to be highly efficient with memory and CPU.

The project is based on Skada 1.8.87 by Kader Bouyakoub. 

## IMPORTANT: How to install

1. If you used the default on **Skada** before, please make sure to delete all its files from `Interface\AddOns` folder as well as all its _SavedVariables_ from `WTF` folder (_just delete all `Skada.lua` and `Skada.lua.bak` for this folder. Use the search box for quick delete_). If you are new, skip this step.
2. Download
4. Extract or drag and drop the unique folder `Skada\Skada` () into your `Interface\AddOns` folder.
5. If you want to use `SkadaImprovement` and/or `SkadaStorage` modules, drop them there as well.


## Special Credits
* Original author: **Zarnivoop**
* New Version: **BKader** (https://github.com/bkader/Skada-WoTLK/blob/main/README.md)

## Difference to v1.8.87 / Changelog
The changes listed below were made for the RG-Skyva version. The changes were primarily created using AI.

### Added

- Added `Sunder Total Counter`, which counts every Sunder Armor application
  and refresh and attributes it to the player who performed the action.
- Added `Demo Shout Uptime`, including per-target uptime and source
  attribution for supported attack-power-reduction effects.
- Added General Vezax reports for healing and individual ticks caused by Mark
  of the Faceless.
- Added Lady Deathwhisper ghost-trigger reports with per-trigger encounter
  time, caused damage and affected-player drill-downs.
- Added Sindragosa Backlash reports for the full encounter and separately for
  phase 2 below 35% boss health, including per-trigger encounter time and
  affected-player drill-downs.
- Added Blood Prince Council knockback reports showing who knocked back whom.
- Added configuration switches for the Lady Deathwhisper, Sindragosa, General
  Vezax and Blood Prince Council encounter modules.
- Added `Useful Valkyrs` to Enemy Damage Taken for heroic Lich King encounters,
  tracking damage dealt before a Val'kyr reaches 50% health.

### Changed

- Renamed the original `Sunder Counter` to `Sunder Effective Counter`; its
  original effective-refresh logic remains unchanged.
- Enemy Damage Taken and its damage-list drill-down now display DPS.
- Improved Val'anyr absorb attribution by correlating queued healing events
  with delayed Protection of Ancient Kings aura refreshes, including multiple
  simultaneous heals and source/target matching.
- Twin Val'kyr essence mechanics now prevent matching orb, vortex and surge
  damage from being incorrectly attributed as player healing or absorbs.
- Moved the Lady Deathwhisper, Sindragosa, General Vezax and Blood Prince
  Council switches directly into the `RG-Skyva Module` section of the module
  options.