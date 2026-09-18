# Porting and maintenance history

## Public-history design

The repository retains its original empty scaffold commit. The next commit is
an exact upstream mod-source baseline, followed by the X4 9.00 work in
reviewable steps. This avoids a single opaque import in which original
authorship and later maintenance are mixed together.

| Commit | Change |
| --- | --- |
| `be2d0e1` | Create the initial repository scaffold |
| `deead7b` | Import the unmodified JanPanthera baseline |
| `748355f` | Initial X4 9.00 port: current Assist anchor, Vanilla sector movement, strict path and blacklist handling, target revalidation and MD cleanup |
| `b6e161e` | Initialize MD groups deterministically before save-load listeners |
| `b0f1eb5` | Add local Robocopy deployment tooling |
| `6520da1` | Correct the X4 9.00 sector access lookup space |
| `60db63e` | Replace obsolete icon texture paths |
| `c9684b9` | Remove the TSE order-ready activation race |
| `bbbc2ba` | Correct TSE Galaxy inter-sector travel |
| `7afc74d` | Correct escape movement from a travel-blacklisted current sector |
| `e57e2b0` | Add structured runtime tracing |
| `f192803` | Make diagnostics inert for unrelated Vanilla orders and correct their parameter formatting |
| `9f211f6` | Return from an idle timeout to a full TSE cycle |
| `8c6c7d6` | Refine productive-cycle and no-action idle behavior |
| `d2efdbd` | Remove unsupported custom crew experience and align skill/delay behavior |
| `7c3ee49` | Improve visible behavior names, target context and optional ship tags |
| `88c1854` | Make runtime log sessions append-only and consistently formatted |
| `05f1764` | Exclude hostile stations and revalidate hostility during work |
| `2b5016a` | Align TSE Galaxy with the visible combined two-star threshold |
| `638192c` | Add bounded performance diagnostics |
| `925bbab` | Share coarse Galaxy discovery across multiple workers |
| `01632b7` | Spread cache work over time, bound idle docking, reject wrecks and handle transient no-sector states |
| `1aa7a3b` | Move closer to stations for more reliable radar updates |
| `417b67a` | Prevent a Tide escape by the commander from recalling the distributed TSE fleet |
| `6164995` | Group the maintained JP mods under `mods/JP_X4Mods` and keep tools/history-aware validators working |

## Current execution model

### TSE Sector

The sector behavior repeatedly:

1. waits through any transient no-sector state;
2. escapes only if the current sector is travel-blacklisted;
3. finds known stations with expired trade information in the selected sector;
4. applies category, access, hostility, blacklist and known-path checks;
5. processes candidates in travel-time order;
6. approaches a still-valid target to half radar range;
7. waits until X4 reports `hastradesubscription`;
8. starts a fresh search after productive work, or enters the configured idle
   fallback when the pass is empty or exhausted.

### TSE Galaxy and Mimic fleets

TSE Galaxy uses the same final per-ship validation. A shared coarse snapshot
only discovers potentially stale stations; it never stores a final assignment
or a per-ship permission decision. One builder constructs a generation and
workers reuse it until the shortest effective idle interval expires. Existing
sector reservations prevent multiple workers from choosing the same work area.

Mimic remains integrated through Vanilla `order.assist`. Vanilla first checks
the subordinate's combined skill. Eligible ships receive the TSE Galaxy
parameters, including their individual blacklist context; ineligible ships
use Vanilla's normal follow fallback.

### Movement and blacklists

Normal work is strict: target selection, final validation and `move.generic`
use the executing ship's effective policies and known paths. The separate
escape helper is intentionally asymmetric. It may relax only travel traversal
long enough to reach an allowed known sector when the ship is already trapped
inside a forbidden one. Station work never uses that relaxation.

### Idle behavior

Idle Move, Follow and Dock are optional fallback actions. A timeout removes
only the exact idle stack owned by TSE, exposing the suspended TSE default
behavior so it can run a new full search. If no idle action is enabled, the
ship simply waits. Dock-target search is bounded to the ten nearest
gate-distance candidates and retains per-ship final checks.

## Deliberate non-features

The port does not:

- discover or reveal unknown stations;
- scan modules or information points;
- grant permanent trade subscriptions;
- change the economy or trade offers;
- award custom pilot or crew experience;
- bypass Vanilla Mimic skill checks;
- cancel arbitrary queued orders;
- alter travel rules for ships outside the guarded TSE/idle paths;
- hardcode Kha'ak, Xenon or any other hostile faction.

These boundaries are enforced by the static validators where the XML contract
can express them.
