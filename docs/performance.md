# TSE Galaxy performance architecture

## Reported problem

A TSE Galaxy commander with 14 Mimic subordinates produced multi-second
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

TSE Galaxy maintains a coarse list of potentially stale known stations:

- state is `invalid`, `building` or `ready`;
- only one concrete ship owns a build;
- the build list remains local until atomic publication;
- waiters retry at a controlled five-second interval;
- ownership and age checks recover abandoned builds;
- save/load increments an epoch so an old partial build cannot publish;
- the cache lifetime follows the effective configured idle interval.

The snapshot is not a work queue. Each worker still applies current access,
hostility, categories, travel/activity/object blacklists, known path, sector
reservation and travel-time ordering. A successful or already-current target
is removed from the coarse snapshot; destroyed and wrecked entries are pruned.

### Work spreading

The cache builder yields for one universe second after every sector finder.
In the measured save this intentionally stretched roughly 106 sector queries
over about 106 seconds rather than grouping them into four or five universe
seconds. Delayed discovery is acceptable because trade-information expiry is
not urgent and every final target is revalidated.

Workers add a stable zero-to-four-second offset to TSE Galaxy idle wakeups.
This reduces synchronized resume waves without changing the configured idle
interval by a large amount. TSE Sector does not use the galaxy cache.

### Bounded idle docking

Strict TSE idle docking asks the finder for at most ten known operational
stations ordered by gate distance. It retains docking permission, access,
blacklist and known-path checks and stops at the first fully valid result. It
does not estimate travel time for the complete galaxy station list.

When automatic idle docking has no explicit destination, a TSE ship retains
its current station if that station remains operational, non-hostile,
accessible and permitted by its blacklists. The bounded station search runs
only when the current station no longer qualifies.

## Diagnostic counters

With the Advanced `DEBUG` order parameter set to `100`, `[TSE-PERF]` records
summarize:

- cache generation, builder and build start/end;
- sectors and stations considered;
- path and travel-time checks;
- cache hits, misses, age and lifetime;
- worker and waiter counts;
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

The permanent regression is `tools/validate-tse-galaxy-performance.ps1`. It
checks builder ownership, pacing, recovery, cache invalidation, per-ship final
rules, Mimic behavior, idle bounds, wreck handling, no-sector guards, XML/XSD
validity and the earlier behavioral regressions.
