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

## X4 9.00 integration contracts

### Order and save-state integration

- The `order.assist.xml` diff anchors its Trade Data Explorer branch at X4
  9.00's unique `SupplyFleet` branch and preserves Vanilla's required-skill
  guard. See
  `mods/MSX4_TradeDataExplorer/aiscripts/order.assist.xml`
  and Vanilla `aiscripts/order.assist.xml`.
- The Mission Director setup creates or reconciles its global groups before
  child listeners become active on a new game or save load. Order cleanup is
  tied to leaving or changing the applicable Trade Data Explorer order. See
  `mods/MSX4_ScriptLibrary/md/msx4.ScriptLibrary.md.xml` and
  `mods/MSX4_TradeDataExplorer/md/msx4.TradeDataExplorer.md.xml`.

### Sector selection and movement

- Target and access queries supply the containing space required by the X4
  9.00 finder contract. See
  `mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.GetTradeDataToUpdate.xml`
  and Vanilla uses of `find_sector` in `aiscripts/`.
- Normal Trade Data Explorer sector travel delegates to Vanilla
  `move.generic`, with a known-path and effective travel-blacklist contract.
- A dedicated escape helper is the only Trade Data Explorer path allowed to relax the travel
  blacklist, and only to leave an already blacklisted current sector for a
  known, reachable, allowed sector. It then returns to normal strict target
  selection. See
  `mods/MSX4_ScriptLibrary/aiscripts/msx4.lib.EscapeTravelBlacklist.xml`.
- Candidate selection and final movement revalidate sector access, sector
  activity, object activity, travel blacklist and known path. This prevents a
  stale selection from silently bypassing a changed rule.
- Short engine transitions in which a ship has no current sector are handled
  by a scheduler wait before sector properties are read. See both Trade Data
  Explorer order definitions.

### Target validation

- Stations whose trade information became current after selection are skipped
  by final validation.
- Hostile stations and hostile resolved targets are rejected before path work
  and rechecked before travel, after travel, after approach and while waiting.
  This is faction-neutral and uses X4's `ishostileto` property. See
  `mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.UpdateTradeData.xml` and
  Vanilla `libraries/scriptproperties.xml`.
- Existing station wreck components are explicitly rejected before reading
  container trade properties. Construction sites remain supported. See
  `mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.GetTradeDataToUpdate.xml`.
- Trade-data recovery starts at 75% radar range and advances only while
  information remains stale: 40%, 20%,
  a 30-second Vanilla dock-assignment window when docking is permitted and
  structurally possible, then a final collision-safe 2 km approach if no dock
  is assigned. Once assigned, the actual docking maneuver remains owned by
  Vanilla. Each stage has a short bounded grace period and the final result is
  `update_timeout`, not an indefinite range wait. These are empirical recovery
  distances, not documented engine thresholds. See
  `mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.UpdateTradeData.xml`,
  `mods/MSX4_TradeDataExplorer/aiscripts/order.dock.xml` and Vanilla
  `aiscripts/order.dock.xml`. Runtime traces confirm successful updates during
  the closer approach stages and through the marked Vanilla dock fallback.
  The final 2 km fallback, unavailable or full docks, construction storage and
  further out-of-sector cases remain open runtime coverage.

### Idle, fleet and special-event behavior

- The idle timeout cancels the exact Trade Data Explorer idle parent and only
  children explicitly tagged as belonging to it. Foreign queue orders are not
  removed. See
  `mods/MSX4_ScriptLibrary/aiscripts/msx4.lib.IdleReturnHome.xml` and
  `mods/MSX4_TradeDataExplorer/md/msx4.TradeDataExplorer.md.xml`.
- Productive completion starts a fresh candidate search; empty or failed work
  uses the configured idle backoff. `Idle Action` is a single-choice selector.
  Only that action is passed to `msx4.lib.IdleReturnHome`; Hold Position or an
  unavailable selected target waits without falling through to a different
  action. The order definitions are in both `MSX4_TradeDataExplorerG.xml` and
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
  of being ended merely to run an empty check. Fallback selection
  orders current-sector stations by physical distance before using a bounded
  galaxy gate-distance tier, preventing nearby ships from converging on an
  arbitrary same-sector station.
  The target lives in a TDE-owned table that is reconstructed on load and
  cleared when TDE ownership, ship ownership, target validity or the selected
  automatic-docking action ends. Component references are not written to ship
  properties.
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
  converted to numbers before entering Vanilla's number-parameter setter.
  Rendering and map interaction are confirmed for the tested default-order
  view; remaining UI contexts are listed under runtime-only coverage.
- Vanilla Tide escape docking can pass `dockfollowers=true` even with
  `recallsubordinates=false`. A narrow Trade Data Explorer diff disables that follower recall
  only when a ship currently has the Galaxy default behavior and has
  subordinates. Other Vanilla behaviors are unchanged. See
  `mods/MSX4_TradeDataExplorer/aiscripts/order.dock.xml`, Vanilla
  `aiscripts/move.flee.dock.xml` and Vanilla `aiscripts/order.dock.xml`.

### User-facing contracts

- The icon texture paths referenced by both extensions are present in the X4
  9.00 icon library. See both mod files under `libraries/icons.xml` and Vanilla
  `libraries/icons.xml`.
- Trade Data Explorer Sector requires combined skill 20. Galaxy requires combined skill
  40, the visible two-star boundary used by current Vanilla order definitions.
  Vanilla's Mimic skill check remains authoritative. See both Trade Data
  Explorer order definitions and Vanilla `aiscripts/order.assist.xml`.
- Trade Data Explorer awards no custom experience. Vanilla's station-update
  path does not provide a matching award, while discovery experience belongs
  to a different recon path. This avoids a non-Vanilla training shortcut.

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
- The trade-data recovery call adds an internal `order.dock` marker whose
  default is false. Only that marked synchronous call suppresses Vanilla's
  player-facing dock failure and consumes the boolean result itself; it cannot
  recall followers, store the ship, enqueue a replacement order or change the
  default behavior. A successful recovery dock is retained until another valid
  target is assigned, at which point the script calls Vanilla `move.undock`
  before resuming travel. Every unmarked Vanilla dock call retains its original
  failure handling.

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
  stations and construction storage, in-sector and out-of-sector, including
  the 75%/40%/20%/dock/2 km recovery sequence and a temporarily full dock;
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
