# X4: Foundations mods

This repository contains an independently maintained X4 9.00 port of two
mods originally created by Jan Görl / JanPanthera:

- `JP_ScriptLibrary`
- `JP_TradeSubscriptionExplorer`

Trade Subscription Explorer sends player-owned ships to known stations whose
trade information has expired. The ships approach closely enough to receive
normal radar-based trade updates, skip stations whose information is already
current, and do not scan station modules or information points. It can work in
one sector or across the known galaxy, including fleets whose subordinates use
X4's Mimic assignment.

The current state has passed the repository's static X4 9.00 contract suite.
Its core behavior and performance design also received sustained manual play
with a 15-ship TSE Galaxy fleet; the last narrowly scoped approach and Tide
guards remain separately identified as targeted test gaps. This is evidence
for the tested paths, not a claim that every X4 9.00 game state or mod
combination is compatible. See
[X4 9.00 compatibility](docs/compatibility-x4-9.md) and
[testing](docs/testing.md).

## Install

Copy both extension directories into the X4 user extension directory:

```text
mods/JP_X4Mods/JP_ScriptLibrary
mods/JP_X4Mods/JP_TradeSubscriptionExplorer
```

On Windows this is normally below:

```text
%USERPROFILE%\Documents\Egosoft\X4\<profile-id>\extensions
```

The directory names inside `extensions` must remain `JP_ScriptLibrary` and
`JP_TradeSubscriptionExplorer`. TSE declares ScriptLibrary as a required
dependency.

For development, run the VS Code task `X4: Deploy mods`, or preview it with
`X4: Preview deployment`. The PowerShell script mirrors only these two named
extension directories. If more than one numeric X4 profile exists, pass an
explicit `-DestinationRoot` to `tools/deploy-mods.ps1`.

## Repository layout

- `mods/JP_X4Mods/` contains the distributable extensions.
- `tools/` contains deployment and regression scripts.
- `docs/` records the port, compatibility evidence, tests, diagnostics and
  performance work.
- `.vscode/tasks.json` exposes the local deployment tasks.

Extracted X4 game files are deliberately absent. Validators expect a local,
read-only X4 9.00 reference tree at `x4-reference/x4-9.00/base`; that path is
ignored by Git and must never be published from this repository.

## Documentation

- [Compatibility with X4 9.00](docs/compatibility-x4-9.md)
- [Porting and maintenance history](docs/porting-history.md)
- [Testing and remaining runtime coverage](docs/testing.md)
- [Performance architecture](docs/performance.md)
- [Runtime debugging](docs/runtime-debugging.md)
- [Third-party notices and provenance](THIRD_PARTY_NOTICES.md)

## Provenance and license

The first mod import commit preserves the original files imported from
[JanPanthera/JP_X4Mods_2023](https://github.com/JanPanthera/JP_X4Mods_2023)
at commit `fa2c795883890062d05c936bc0077c3d85438249`. Later commits contain the
X4 9.00 maintenance work, so the public history shows the boundary between
upstream code and this port.

The upstream GitHub source is MIT-licensed. Its original copyright notice is
retained in [LICENSE](LICENSE), together with the notice for later maintenance
work. This repository is not an official Egosoft or JanPanthera release.
