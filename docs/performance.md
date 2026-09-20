# Trade Data Explorer Galaxy performance architecture

## Reported problem

A Trade Data Explorer Galaxy commander with 14 Mimic subordinates produced multi-second
stalls after the fleet ran out of targets and entered its idle cycle. The first
implementation serialized discovery with a global boolean, but every waiting
worker polled rapidly and then repeated the complete galaxy search. The idle
docking fallback separately examined more than one thousand stations and
estimated travel time for most of them on every ship.

Logs established the action counts and their timing in universe time. They did
not provide a CPU wall-clock profiler, so the documents and code do not claim
that a particular XML action consumed an exact number of milliseconds.

## Implemented design

### Shared coarse discovery

Trade Data Explorer Galaxy maintains a coarse list of potentially stale known stations:

- state is `invalid`, `building` or `ready`;
- only one concrete ship owns a build;
- the build list remains local until atomic publication;
- workers that encounter an active builder perform their configured idle action
  and retry after their idle interval;
- ownership and age checks recover abandoned builds;
- save/load increments an epoch so an old partial build cannot publish;
- the cache lifetime follows the longer of the effective configured idle
  interval and the five-minute build recovery window.

The snapshot is not a work queue. Each worker still applies current access,
hostility, categories, travel/activity/object blacklists, known path, sector
reservation and travel-time ordering. A successful or already-current target
is removed from the coarse snapshot; destroyed and wrecked entries are pruned.

Within an active sector, a worker re-ranks only its already-filtered remaining
stations after a successful visit. This avoids repeating galaxy discovery and
policy filtering while allowing the next target to reflect the ship's new
position. No re-ranking is performed for an already-current target or when
fewer than two candidates remain.

Initial in-sector ranking and subsequent re-ranking estimate one station per
batch, yielding for 0.1 universe seconds between batches. Thirty candidates
therefore span roughly 2.9 universe seconds of scheduler yields
instead of performing all estimates in one uninterrupted script step.

### Work spreading

The cache builder yields for one universe second after every sector finder.
In the measured save this intentionally stretched roughly 106 sector queries
over about 106 seconds rather than grouping them into four or five universe
seconds. Delayed discovery is acceptable because trade-information expiry is
not urgent and every final target is revalidated.

Workers add a stable zero-to-four-second offset to Galaxy idle wakeups.
This reduces synchronized resume waves without changing the configured idle
interval by a large amount. The Sector behavior does not use the galaxy cache.
Keeping a published generation for at least five minutes also prevents a paced
galaxy build that takes longer than a short idle interval from immediately
triggering the next build wave.
If a Galaxy worker reaches the shared search coordinator during an actual
cache build, it uses the configured idle action until its next normal retry.
Contention after publication, or from the Sector behavior, instead receives a
short paced retry and does not enter the idle action. The cache owner remains
in the incremental build so the fleet cannot collectively idle before
publication. A completed search with no candidates still uses the configured
idle interval; this avoids an empty-search loop.

### Bounded idle docking

When automatic idle docking starts while a Trade Data Explorer ship is already
docked, it retains that station if it remains operational, non-hostile,
accessible and permitted by its blacklists. Otherwise it reuses the last
validated automatic dock target across idle-timeout restarts. A successful
trade-data update records that nearby station as the preferred target. These
paths require no replacement finder pass.

The per-ship preference is owned by Trade Data Explorer in a dedicated table;
the generic Script Library only invokes the supplied storage callback. The
table is filtered to active TDE ships with automatic docking whenever a game is
loaded. Entries are also removed when the action changes, the station becomes
invalid, the ship leaves TDE control, is destroyed, abandoned or changes true
owner. This prevents retained component references from outliving their TDE
orders.

For Trade Data Explorer, the configured idle interval is a work-probe interval,
not the lifetime of the selected idle action. Hold Position, a completed Move to
Position, Follow and Dock all retain their active state while Sector or Galaxy
candidate probes remain empty or busy. Only a positive candidate result returns
control to the behavior. In particular, the tagged Vanilla `DockAndWait` child
receives an explicit one-shot ownership handoff from the internal idle parent
and restarts its wait internally instead of ending. The handoff leaves
Vanilla's `callerid` contract untouched and avoids an unnecessary undock and
immediate redock at the same station.

Only when neither retained target qualifies does strict idle docking put up to
ten known operational stations from the current sector in physical-distance
order before a bounded galaxy fallback ordered by gate distance. It retains
docking permission, access, blacklist and known-path checks and stops at the
first fully valid result. It does not estimate travel time for the complete
galaxy station list.

## Diagnostic counters

With the Advanced `DEBUG` order parameter set to `100`, `[MSX4-TDE-PERF]` records
summarize:

- cache generation, builder and build start/end;
- sectors and stations considered;
- path and travel-time checks;
- cache hits, misses, age and lifetime;
- active worker counts and explicit deferred-search trace events;
- bounded idle-dock candidates, checks and selected target.

The clock is `player.age`, which is universe time and can be affected by pause
or time acceleration. It is suitable for sequence and pacing analysis, not
CPU benchmarking.

## Runtime result and limits

The first optimized runs exposed three separate issues: an existing station
wrack whose trade property was invalid, an unbounded idle-dock fallback, and a
short no-sector transition. The final optimization addressed all three and
spread cache construction across ticks.

The tester subsequently reported that the 15-ship scenario felt substantially
better with `DEBUG=100`, marginally better again with `DEBUG=0`, and remained
satisfactory over multiple longer play sessions. This is useful runtime
evidence, but it is a subjective acceptance result rather than a repeatable
frame-time benchmark.

The permanent regression is `tools/validate-tde-galaxy-performance.ps1`. It
checks builder ownership, pacing, recovery, cache invalidation, per-ship final
rules, Mimic behavior, idle bounds, wreck handling, no-sector guards, XML/XSD
validity and the earlier behavioral regressions.
