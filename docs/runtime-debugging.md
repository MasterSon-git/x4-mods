# Runtime debugging

## Starting X4

For script diagnostics, start X4 with:

```text
-debug scripts -logfile debuglog.txt -scriptlogfiles
```

`-debug scripts` enables script diagnostics, `-logfile` selects the central
debug log, and `-scriptlogfiles` permits `debug_to_file` output. These command
line flags do not themselves enable detailed TSE tracing.

TSE Sector and TSE Galaxy retain X4's standard Advanced order parameter named
`Debug`, with values `0` or `100`. If the current debug/inspection UI exposes
Advanced order parameters, set it to `100` before confirming the behavior.
Mimic workers inherit the value through the TSE Assist parameter contract.
Normal play should use `0`.

No custom settings menu or always-on diagnostic switch was added.

## Output

Detailed TSE traces are written below X4's script-log location in:

```text
JP_TradeSubscriptionExplorer.logs/TSE_Runtime.log
```

The setup MD writes one append-only `session_start` marker for each new/load
session. It does not erase older sessions. Starting another ship or another
cycle cannot reset the log.

Custom records use one line with a six-character source type, `player.age`,
the function and the payload. Structured behavioral records carry the
`[TSE-TRACE]` marker; performance summaries carry `[TSE-PERF]`.

Useful source types are:

- `TSEAI ` — TradeSubscriptionExplorer AI scripts;
- `TSEMD ` — TradeSubscriptionExplorer Mission Director setup and cleanup;
- `SLIBAI` — ScriptLibrary AI helpers;
- `SLIBMD` — ScriptLibrary Mission Director management.

## Important trace boundaries

The trace covers:

- behavior start, cycle start and interruption;
- blacklist escape decisions and movement result;
- galaxy cache build, reuse and worker-specific selection;
- candidate counts, rejection reasons and sector reservation;
- target validation before/after travel and approach;
- waiting for `hastradesubscription` and successful completion;
- idle action selection, Dock/DockAndWait integration and timeout cleanup;
- Mimic parameter propagation;
- MD setup, order changes and cleanup.

Expected rejection reasons include current information, invalid/wrecked target,
hostile target, access or blacklist denial, no known path, movement failure and
approach failure. A rejection reason is not automatically an error; many are
normal consequences of revalidation.

## Debugging invariants

When `DEBUG=0`, AI detail traces and their diagnostic-only finders/counters are
inactive. The central append-only session marker is the documented file-only
exception. Instrumentation is guarded against optional parameters so unrelated
Vanilla Dock, DockAndWait and Follow orders do not evaluate TSE-only state.

Run `tools/validate-runtime-debug-logging.ps1` after editing trace code. It
checks the line envelope, placeholders, mandatory fields, guards, Assist
parameter propagation, functional equivalence of the original logging-only
change, simulated Vanilla diff selectors and the broader regression suite.

Logs may contain player names, ship IDs, local paths and save-specific state.
They are intentionally ignored by Git and should be reviewed before sharing.
