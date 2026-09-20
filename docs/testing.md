# Testing

## Static regression suite

The repository contains 18 permanent validators. They require PowerShell, Git,
a JDK providing `jshell`, and a local X4 9.00 reference tree at
`x4-reference/x4-9.00/base`.

Run all validators from the repository root:

```powershell
$failed = @()
Get-ChildItem tools -Filter 'validate-*.ps1' | Sort-Object Name | ForEach-Object {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { $failed += $_.Name }
}
if ($failed) { throw "Failed: $($failed -join ', ')" }
```

The suite covers:

- XML well-formedness and recursive X4 9.00 AI/MD XSD validation;
- unique XML diff selectors and simulated application to Vanilla scripts;
- MD group initialization and save/load ordering;
- sector access, blacklists, known paths and escape movement;
- order activation, Assist/Mimic parameters and combined-skill checks;
- productive-cycle, idle fallback and selective timeout cleanup;
- hostile-target, wreck and current-subscription rejection;
- staged and bounded trade-data recovery;
- icon paths, visible behavior state and localization ID coverage;
- runtime log guards, session format and functional diagnostic inertness;
- shared Galaxy cache, load spreading and bounded idle docking;
- the Trade Data Explorer-only Tide follower-docking guard;
- the standalone MSX4 extension, script, order, diagnostic and text namespaces;
- absence of scan, reveal and permanent-subscription actions.

`tools/deploy-mods.ps1 -DryRun` separately verifies the two source extension
paths and previews the exact Robocopy mirror without writing files.

## Manual runtime evidence

The following table records currently relevant X4 9.00 observations. It is an
evidence summary, not an investigation or commit history.

| Contract | Current evidence |
| --- | --- |
| Sector behavior | Known stale, non-hostile stations were visited and normal radar reception updated their trade information |
| Galaxy behavior | Local work, idle retries and later inter-sector work completed in the tested fleet |
| Mimic | Eligible subordinates inherited Galaxy parameters and performed distributed Trade Data Explorer work |
| Dynamic restrictions | A tested travel-blacklist escape completed; target access, hostility and blacklist changes are also statically revalidated |
| Save/load | The behavior remained functional through the tested active-order load cycle |
| Idle selector | The action rendered as a dropdown; only target-bearing actions displayed one contextual target row, and Dock at Suitable Station activated without a row |
| Persistent idle actions | In a 14-ship run, 128 empty probes did not release the selected idle action; observed releases followed positive work probes |
| Automatic docking | Current or remembered valid nearby docks were retained, and a traced run showed one DockAt child per ownership handoff without an immediate undock/redock loop |
| Avarice distribution | In the observed run, the reservation kept workers other than the commander out of the commander's Avarice IV sector |
| Large-fleet performance | A 15-ship Galaxy fleet remained subjectively satisfactory over longer sessions with diagnostics both enabled and disabled |
| Trade-data recovery | Runtime traces confirmed updates during staged approaches and eight marked recovery dock calls that returned with the ship docked and trade data current; several then retained the same station for configured idle docking. One further recovery dock attempt had started but had not returned when logging ended; no indefinite trade-data wait recurred |

These observations do not establish behavior for every timing, topology, ship
size, DLC combination or third-party mod.

## Recommended release smoke test

1. Follow [the migration procedure](migration.md) on a copy of an established
   X4 9.00 save. Confirm no Trade Data Explorer/MSX4 Script Library XML, diff
   or MD group errors and no missing-extension warning for the replaced build.
2. Give Trade Data Explorer Sector to one ship in a sector containing both
   current and stale known stations. Confirm only stale, non-hostile allowed
   targets are visited.
3. Give Trade Data Explorer Galaxy to a two-star captain. Confirm another
   eligible sector is selected after local work is complete.
4. Add at least one eligible Mimic subordinate and confirm it performs Trade
   Data Explorer work rather than merely following.
5. Change sector travel/activity and object-activity blacklists while work is
   active; confirm the next validation boundary rejects disallowed work.
6. Provide at least three stale stations in one sector. After the first visit,
   confirm the next target reflects estimated travel time from the ship's new
   position rather than the order calculated at the start of the cycle.
7. In both Sector and Galaxy behavior, confirm that `Idle Action` is one
   dropdown and that only Move to Position, Follow Object and Dock at Selected
   Station show one `Idle Target` row. Use that row once per target-bearing
   action and confirm it opens Vanilla's normal map target-selection mode.
8. Exercise Hold Position and Dock at Suitable Station. Make a selected target
   unavailable and confirm the ship waits rather than trying another idle
   action. Then wait for the timeout and confirm a fresh search occurs before
   the selected idle action runs again. With multiple workers and an expired
   Galaxy cache, confirm that non-builder ships perform their selected idle
   action while one builder continues the distributed scan.
9. Save and reload with active Trade Data Explorer and Mimic orders.
10. Repeat once with `DEBUG=100`, check the central and Trade Data Explorer
    runtime logs, then repeat the performance observation with `DEBUG=0`.

## Open targeted tests

- controlled Avarice Tide warning with a dispersed Galaxy fleet;
- all gate/accelerator/superhighway combinations through a multi-sector
  blacklist escape;
- very large stations and construction storage in-sector and out-of-sector
  through the complete recovery sequence, especially the final 2 km fallback,
  docking denied by relation, no compatible dock and a compatible but
  temporarily full dock;
- Commander destruction/promotion and deep Mimic chains;
- foreign queued orders through every Priority Order interruption boundary;
- reproducible frame-time capture for a large fleet, rather than subjective
  hitch observation;
- the single-choice idle UI in default-order, planned-default and Mimic
  inheritance paths;
- the distinction between cache-build idle and short search-busy retries;
- interactions with third-party mods that patch Assist, Dock, DockAndWait or
  Follow. Coexistence with the original JP extensions is not supported or an
  intended test case.

Passing the smoke test improves release confidence but does not turn these
open cases into proven compatibility.
