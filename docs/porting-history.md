# Porting and maintenance history

## Public-history design

The repository history intentionally starts with an exact upstream source
baseline and then applies the X4 9.00 work in reviewable steps. This avoids a
single opaque import in which original authorship and later maintenance are
mixed together.

| Commit | Change |
| --- | --- |
| `8714522` | Import the unmodified JanPanthera baseline |
| `577426d` | Initial X4 9.00 port: current Assist anchor, Vanilla sector movement, strict path and blacklist handling, target revalidation and MD cleanup |
| `752d83e` | Initialize MD groups deterministically before save-load listeners |
| `9e530bb` | Add local Robocopy deployment tooling |
| `ce169b4` | Correct the X4 9.00 sector access lookup space |
| `6fa0c9c` | Replace obsolete icon texture paths |
| `19e2335` | Remove the TSE order-ready activation race |
| `2f92ac4` | Correct TSE Galaxy inter-sector travel |
| `68d17b5` | Correct escape movement from a travel-blacklisted current sector |
| `275d986` | Add structured runtime tracing |
| `3261071` | Make diagnostics inert for unrelated Vanilla orders and correct their parameter formatting |
| `caa76a1` | Return from an idle timeout to a full TSE cycle |
| `986e2c1` | Refine productive-cycle and no-action idle behavior |
| `ef4d9bb` | Remove unsupported custom crew experience and align skill/delay behavior |
| `703a51f` | Improve visible behavior names, target context and optional ship tags |
| `81cad8b` | Make runtime log sessions append-only and consistently formatted |
| `3bbc2f1` | Exclude hostile stations and revalidate hostility during work |
| `6c62cb8` | Align TSE Galaxy with the visible combined two-star threshold |
| `ef751be` | Add bounded performance diagnostics |
| `c512a8f` | Share coarse Galaxy discovery across multiple workers |
| `8bd843a` | Spread cache work over time, bound idle docking, reject wrecks and handle transient no-sector states |
| `5036366` | Move closer to stations for more reliable radar updates |
| `b8c0f62` | Prevent a Tide escape by the commander from recalling the distributed TSE fleet |
| `2828c66` | Group the maintained JP mods under `mods/JP_X4Mods` and keep tools/history-aware validators working |

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
