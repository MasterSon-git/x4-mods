# Repository instructions

This repository contains independently maintained mods for X4: Foundations.

## Repository layout

- Distributable extensions live below `mods/JP_X4Mods/`.
- `JP_TradeSubscriptionExplorer` requires `JP_ScriptLibrary`.
- Regression and deployment scripts live in `tools/`.
- Public maintenance records live in `docs/`.

Keep repository-maintained documentation, code comments and commit messages in
English. Localization files remain in their respective languages.

Follow the public issue, branch and pull-request workflow in
`CONTRIBUTING.md`. In particular, issue-linked branches use GitHub's
`<issue-number>-<short-kebab-case-title>` format.

## X4 reference files

Local Vanilla X4 9.00 files are expected below `x4-reference/x4-9.00/`.
Treat them as read-only reference material. Never modify, commit or
redistribute extracted game files, schemas or other Egosoft data.

Technical compatibility claims should cite a concrete mod file and, where
possible, an X4 9.00 schema definition or Vanilla usage. Distinguish static
evidence from behavior that still requires an in-game test.

## Change boundaries

- Preserve the upstream copyright notice, license and provenance documented in
  `LICENSE` and `THIRD_PARTY_NOTICES.md`.
- Do not commit saves, logs, archives, screenshots, local profile IDs,
  credentials or absolute user paths.
- Preserve extension IDs, AI script/order IDs and saved parameter contracts
  unless a migration is explicitly designed and tested.
- Keep Vanilla order diffs narrowly guarded by TSE order IDs or internal
  parameters so unrelated ships retain Vanilla behavior.
- Do not add station reveal, module scanning, information-point scanning,
  permanent trade subscriptions or economy changes unless the requested
  feature explicitly changes the documented scope.
- Update the relevant public document when a behavior, compatibility boundary
  or manual-test status changes.

## Validation

Run the directly relevant `tools/validate-*.ps1` scripts while developing.
Before a release or history publication, run all validators from the repository
root and verify `git diff --check`.

Validators require the local X4 9.00 reference tree and a JDK that provides
`jshell`. Use `tools/deploy-mods.ps1 -DryRun` to preview local deployment;
never commit the resolved X4 profile destination.
