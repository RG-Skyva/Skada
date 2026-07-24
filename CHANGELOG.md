# Changelog

All notable changes to this modified Skada distribution are documented here.

The project is based on Skada 1.8.87 by Kader Bouyakoub. The changes listed
below were made for the RG-Skyva version.

## Added

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

## Changed

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
