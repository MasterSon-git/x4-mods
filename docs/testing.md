# Testing

## Static regression suite

The repository contains 15 permanent validators. They require PowerShell, Git,
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
- icon paths, visible behavior state and localization ID coverage;
- runtime log guards, session format and functional diagnostic inertness;
- shared Galaxy cache, load spreading and bounded idle docking;
- the Trade Data Explorer-only Tide follower-docking guard;
- the standalone MSX4 extension, script, order, diagnostic and text namespaces;
- absence of scan, reveal and permanent-subscription actions.

`tools/deploy-mods.ps1 -DryRun` separately verifies the two source extension
paths and previews the exact Robocopy mirror without writing files.

## Manual evidence obtained

The port was developed against X4 9.00 build 611726 and exercised repeatedly
on an existing save before the standalone MSX4 namespace was introduced. The
behavioral implementation is carried forward, but the renamed extension and
save-transition procedure still require a release smoke test. The following
are runtime observations, not deductions from static XML:

| Scenario | Result |
| --- | --- |
| Existing save with both extensions | Initial missing-group errors reproduced; deterministic MD initialization removed them |
| Sector behavior | Visited known stale stations and acquired current trade information |
| Galaxy behavior | Processed local stale stations, resumed after idle and selected work in another sector after travel fixes |
| Hold and reassign behavior | Order activation race and stuck-idle path were reproduced and corrected |
| Travel-blacklisted current sector | Instrumented escape path completed in the tested simple case |
| Save/load with active behavior | Core behavior survived the tested load cycle |
| Active pre-selector Galaxy orders | Work and Mimic cycling continued, but the replaced idle parameters produced property-lookup errors on idle entry; clearing and reassigning the development order is required and no migration is planned before the first release |
| Mimic subordinate | Inherited Galaxy parameters and executed the custom branch when skill permitted |
| Hostile station | Kha'ak defense-station targeting reproduced; the faction-neutral hostile filter was then confirmed in game |
| Idle timeout | Returned to a full behavior cycle after selective idle-stack cleanup in later play |
| 15-ship performance | Final cache/load-spreading design felt substantially better and remained satisfactory over several sessions |
| Debug disabled | Slight additional subjective improvement over the already acceptable `DEBUG=100` run |
| Idle selector UI | After correcting the extension-root manifest to X4 9.00's third-party `ui/core/addon.xsd` contract, the action rendered as a dropdown in game. Dock at Suitable Station showed no target row, while Dock at Selected Station showed exactly one station target row. The dropdown string/number mismatch was corrected and Dock at Suitable Station subsequently activated in game. Persistent per-ship target reuse and physical-distance local selection stopped a tested ship from changing to an arbitrary same-sector defense platform after the idle timeout. Both external cancellation and regular `DockAndWait` completion still caused tested ships to undock briefly before selecting the retained station. The subsequent design retains every selected idle action across empty periodic candidate probes and still requires confirmation for Dock, Hold, Move and Follow. A 14-ship, roughly 25-minute automatic-docking run then produced 128 empty probes without an empty result releasing a dock order; every observed release followed a positive work probe. ZAT-718 changed docks only after updating the second station, and the Avarice IV reservation kept all observed workers except the commander out of that sector. X4's rejection of component-valued ship properties was removed by replacing the target memory with a bounded TDE-owned table; the following runtime log contained no recurrence. That run exposed a separate long-approach race: the internal `IdleReturnHome` order could end before `DockAt` returned, and Vanilla correctly discarded a `DockAndWait` tied to it through `callerid`; Assist then selected the same station a second time. The revised path performs an explicit one-shot ownership handoff to a self-contained tagged `DockAndWait`, retires only the exact internal parent and leaves Vanilla's `callerid` lifecycle unchanged. A subsequent 14-ship runtime trace contained 16 such handoffs, exactly one `DockAt` child per handoff, one return per completed approach and no recurrence of the immediate undock/redock loop. The same run independently reproduced the long 20 km trade-data waits tracked in issue #11 and the distant-worker reservation tracked in issue #14. The split between cache-build idle and short search-busy retries also remains to be exercised separately |

The manually reported success of some later fixes was not always captured in
an isolated log tied to one exact commit. The history therefore distinguishes
between static regression proof, tester-reported success and open targeted
tests.

## Recommended release smoke test

1. Follow [the migration procedure](migration.md) on a copy of an established
   X4 9.00 save. Confirm no Trade Data Explorer/MSX4 Script Library XML, diff
   or MD group errors and no missing-extension warning for the replaced build.
2. Give Trade Data Explorer Sector to one ship in a sector containing both current and stale
   known stations. Confirm only stale, non-hostile allowed targets are visited.
3. Give Trade Data Explorer Galaxy to a two-star captain. Confirm another eligible sector is
   selected after local work is complete.
4. Add at least one eligible Mimic subordinate and confirm it performs Trade Data Explorer
   work rather than merely following.
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
10. Repeat once with `DEBUG=100`, check the central and Trade Data Explorer runtime logs, then
   repeat the performance observation with `DEBUG=0`.

## Open targeted tests

- standalone-namespace migration from the earlier JP-namespaced development
  build, including clearing and reassigning active orders;
- controlled Avarice Tide warning with a dispersed Galaxy fleet;
- all gate/accelerator/superhighway combinations through a multi-sector
  blacklist escape;
- very large stations and construction storage in-sector and out-of-sector
  after the 50% radar-range approach change;
- Commander destruction/promotion and deep Mimic chains;
- foreign queued orders through every Priority Order interruption boundary;
- reproducible frame-time capture for a large fleet, rather than subjective
  hitch observation;
- the new single-choice idle UI in default-order, planned-default and Mimic
  inheritance paths;
- interactions with third-party mods that patch Assist, Dock, DockAndWait or
  Follow. Coexistence with the original JP extensions is not supported or an
  intended test case.

Passing the smoke test improves release confidence but does not turn these
open cases into proven compatibility.
