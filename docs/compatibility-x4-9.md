# X4 9.00 compatibility

## Status and evidence standard

This port targets X4: Foundations 9.00. The current implementation is suitable
for normal play on the paths tested so far. Static validation and manual tests
do not establish universal compatibility with every save, DLC combination,
third-party mod or engine state.

Findings in this document use three evidence levels:

- **Static:** demonstrated by the mod, the X4 9.00 XML schemas, or a concrete
  Vanilla use in the local reference tree.
- **Runtime:** observed in an X4 9.00 game and, where available, correlated
  with script logs.
- **Open:** can only be resolved by further in-game testing.

Paths beginning with `x4-reference/x4-9.00/base` refer to a local, untracked,
read-only game reference. They are not part of this repository.

## Baseline and external context

The original TSE 2.04 and ScriptLibrary 1.03 files are dated 2023-07-19. The
original author described the development base as X4 6.20 Beta 4 on the
[TSE Nexus discussion](https://www.nexusmods.com/x4foundations/mods/339?tab=posts).
The same page contains community reports of a missing text ID and unusually
high custom experience gain. Those reports were investigation leads, not
proof of the X4 9.00 contracts.

Official releases after that baseline created concrete review targets:

- [X4 7.00](https://store.egosoft.com/news/archive/2024June_en.php) was a major
  update with broad game and AI changes, which justified rechecking movement,
  gates and order integration rather than assuming the 6.20 scripts remained
  compatible.
- [X4 8.00](https://www.egosoft.com/news/archive/2025September_en.php) added
  dynamic diplomacy, including changing alliances, wars and ceasefires. Trade
  Data Explorer therefore revalidates access, blacklist and hostility conditions instead of
  treating candidate selection as permanent.
- [X4 9.00](https://www.egosoft.com/news/archive/2026June_en.php) introduced
  Priority Orders, substantial AI and capital-movement work, more elaborate
  NPC stations and new recycling activity. These changes led to explicit
  checks of order interruption, movement, radar approach geometry, station
  categories and wreck handling.

The release notes identify areas worth investigating; the actual compatibility
decisions below are based on the local 9.00 schemas and Vanilla scripts.

## Core APIs retained in X4 9.00

No removed API was found for the core radar-update mechanism.

| Mod contract | X4 9.00 evidence | Result |
| --- | --- | --- |
| `tradesknownto` candidate filter | `libraries/common.xsd`; used by `aiscripts/order.trade.single.xml` | Retained |
| `hastradesubscription` completion property | `libraries/scriptproperties.xml`; used by Vanilla trade scripts | Retained |
| `maxradarrange` | `libraries/scriptproperties.xml`; used by `aiscripts/order.move.recon.xml` | Retained |
| `find_sector` and `find_object` | `libraries/common.xsd` | Retained |
| `match_use_blacklist` and `useblacklist` | `libraries/common.xsd`; current trade and movement uses | Retained |
| `accessgrantedto` | `libraries/common.xsd` | Retained |
| Station classification properties | `libraries/scriptproperties.xml`; grouped uses in `order.move.recon.xml` | Retained |
| `ishostileto` | `libraries/scriptproperties.xml` | Retained |
| `command.investigate` and related actions | `libraries/aiscripts.xsd`; current recon uses | Retained |

The present implementation still relies on normal radar reception. It does not
add module scanning, information-point scanning, object reveal actions,
economy edits or permanent trade subscriptions.

## Incompatibilities and defects resolved

### Order and save-state integration

- The original `order.assist.xml` diff selector no longer matched the X4 9.00
  control tree. The port anchors its Trade Data Explorer branch at the current, unique
  `SupplyFleet` branch and preserves Vanilla's required-skill guard. See
  `mods/MSX4_TradeDataExplorer/aiscripts/order.assist.xml`
  and Vanilla `aiscripts/order.assist.xml`.
- Top-level MD listeners could evaluate the legacy `global.$SL_PlayerShips`
  and `global.$TSE_ShipsGroup` before those groups existed when loading a save.
  Setup now creates or reconciles state before child listeners become active.
  See both mod files under `md/` and commit `b6e161e`.
- A ready-event race could cancel a newly selected Trade Data Explorer order during
  activation. Cleanup now remains tied to leaving or changing the applicable
  order. See commit `c9684b9`.

### Sector selection and movement

- X4 9.00 requires a valid containing space for the affected sector lookup.
  The target and access queries now use the current 9.00 finder contract. See
  `aiscripts/msx4.tde.GetTradeDataToUpdate.xml` and commit `6520da1`.
- The original custom gate-by-gate movement conflicted with current movement
  behavior. Normal Trade Data Explorer travel now delegates sector travel to Vanilla
  `move.generic`, with a known-path and effective travel-blacklist contract.
- A dedicated escape helper is the only Trade Data Explorer path allowed to relax the travel
  blacklist, and only to leave an already blacklisted current sector for a
  known, reachable, allowed sector. It then returns to normal strict target
  selection. See `mods/MSX4_ScriptLibrary/aiscripts/msx4.lib.EscapeTravelBlacklist.xml`
  and commits `bbbc2ba` and `7afc74d`.
- Candidate selection and final movement revalidate sector access, sector
  activity, object activity, travel blacklist and known path. This prevents a
  stale selection from silently bypassing a changed rule.
- Short engine transitions in which a ship has no current sector are handled
  by a scheduler wait before sector properties are read. See commit `01632b7`.

### Target validation

- Stations whose trade information became current after selection are skipped
  by final validation.
- Hostile stations and hostile resolved targets are rejected before path work
  and rechecked before travel, after travel, after approach and while waiting.
  This is faction-neutral and uses X4's `ishostileto` property. See commit
  `05f1764` and Vanilla `libraries/scriptproperties.xml`.
- Existing station wreck components are explicitly rejected before reading
  container trade properties. Construction sites remain supported. See commit
  `01632b7`.
- The radar approach target was reduced from 75% to 50% of the ship's maximum
  radar range after a rare runtime case updated only when manually moved
  closer. This is a conservative observed workaround, not a documented engine
  threshold. See commit `1aa7a3b`.

### Idle, fleet and special-event behavior

- The idle timeout previously removed only the top immediate child, causing
  `IdleReturnHome` to restart without returning to a Trade Data Explorer search. The manager
  now cancels the exact Trade Data Explorer idle parent and only children explicitly tagged as
  belonging to it. Foreign queue orders are not removed. See commit `9f211f6`.
- Productive completion starts a fresh candidate search; empty or failed work
  still uses the configured idle backoff. A single `Idle Action` selector now
  replaces the former independent Move, Follow and Dock switches. Only that
  action is passed to `msx4.lib.IdleReturnHome`; Hold Position or an unavailable
  selected target waits without falling through to a different action. The
  order definitions are in both `MSX4_TradeDataExplorerG.xml` and
  `MSX4_TradeDataExplorerS.xml`.
- A Galaxy worker blocked by an active cache build receives an explicit
  `cache_build_pending` result and performs the configured idle action before
  retrying. Ordinary search-coordinator contention receives `search_busy` and
  uses a short paced retry instead; a completed search with no candidates
  retains the normal configured idle backoff.
- Automatic suitable-station docking remembers its validated per-ship target
  across idle cycles and retains a still-valid current dock before considering
  that remembered target. The idle interval now drives periodic candidate
  probes without ending Hold Position, Move to Position, Follow or the tagged
  Vanilla `DockAndWait` child. The dock path explicitly transfers ownership
  from its exact internal idle parent and leaves Vanilla's `callerid` lifecycle
  unchanged. An idle action finishes only after a probe finds TDE work, instead
  of being ended merely to run an empty check. New fallback selection
  orders current-sector stations by physical distance before using a bounded
  galaxy gate-distance tier, preventing nearby ships from converging on an
  arbitrary same-sector station.
  X4 9.00 rejected the initial component-valued ship property used for this
  memory. The target now lives in a TDE-owned table that is reconstructed on
  load and cleared when TDE ownership, ship ownership, target validity or the
  selected automatic-docking action ends.
- X4 9.00's `libraries/aiscripts.xsd` provides bounded numeric, position and
  object order parameters but no declarative dropdown parameter. The narrowly
  guarded adapter in
  `mods/MSX4_TradeDataExplorer/ui/addons/msx4_trade_data_explorer/idle_action.lua`
  renders the bounded action value as a dropdown and delegates contextual
  target selection to Vanilla `menu_map.lua`'s `buttonSetOrderParam` flow. The
  extension-root `mods/MSX4_TradeDataExplorer/ui.xml` manifest loads the
  adapter after `ego_detailmonitor`. It follows X4 9.00's third-party
  `ui/core/addon.xsd` contract: unlike a Vanilla core addon, its addon name
  does not use the reserved `ego_` prefix. Dropdown option IDs are explicitly
  converted to numbers before entering Vanilla's number-parameter setter; the
  AI side also accepts the textual values produced by the first development
  adapter so active test orders recover without reassignment.
  Correct rendering and map interaction remain an in-game test requirement.
- Vanilla Tide escape docking can pass `dockfollowers=true` even with
  `recallsubordinates=false`. A narrow Trade Data Explorer diff disables that follower recall
  only when a ship currently has the Galaxy default behavior and has
  subordinates. Other Vanilla behaviors are unchanged. See
  `mods/MSX4_TradeDataExplorer/aiscripts/order.dock.xml`, Vanilla
  `aiscripts/move.flee.dock.xml` and commit `417b67a`.

### User-facing contracts

- Obsolete icon texture paths were replaced with paths present in the X4 9.00
  icon library. See commit `60db63e`.
- Trade Data Explorer Sector requires combined skill 20. Galaxy requires combined skill
  40, the visible two-star boundary used by current Vanilla order definitions.
  The original value 45 rendered as the same two stars while rejecting some
  captains shown as eligible. Vanilla's Mimic skill check remains authoritative.
- Custom experience awards were removed. Vanilla's station-update path
  does not provide a matching award, while discovery experience belongs to a
  different recon path. This avoids creating a non-Vanilla training shortcut.

## Narrow impact on Vanilla scripts

The port does not replace Vanilla files. Its XML diffs add guarded behavior to
specific order scripts:

- ScriptLibrary forwards internal idle parameters through Dock, DockAndWait
  and Follow only for its own idle stack. Its DockAndWait ownership handoff is
  guarded by the MSX4 marker, the exact internal parent order ID and the same
  controlled ship.
- Trade Data Explorer adds its Mimic branch to Assist for its custom Galaxy order.
- Trade Data Explorer suppresses follower docking only for an active Galaxy commander in
  the two relevant docking paths.

Every guard includes the custom order ID or an internal parameter supplied by
this mod. Ships not using these Trade Data Explorer/MSX4 Script Library paths retain the Vanilla
branches. Diff selectors are applied against a simulated X4 9.00 target tree
by the regression suite.

## Runtime-only coverage still open

The following cannot be proven by XML validation alone:

- every gate, accelerator and superhighway topology, especially a multi-sector
  escape from a newly changed travel blacklist;
- interruption and resumption at every frame of a Priority Order, attack,
  inspection, scan or resupply interrupt;
- all S/M/L/XL approach and collision-avoidance outcomes for very large
  stations and construction storage, in-sector and out-of-sector;
- Commander destruction/promotion with deep Mimic chains and preserved
  per-ship blacklists;
- the exact engine state of `event.object.subordinates` after destruction;
- a controlled Tide warning in Avarice with widely dispersed subordinates;
- the single-choice idle dropdown, conditional target row and Vanilla map
  target-selection flow for each action in both Sector and Galaxy behavior;
- interactions with third-party mods that patch the same Vanilla order files.

These are tracked as test boundaries, not described as known failures.

No compatibility is claimed with the original `JP_ScriptLibrary`, the
original `JP_TradeSubscriptionExplorer`, or compatibility patches targeting
their identifiers. The MSX4 extensions are intended to replace that pair, not
to run beside it.
