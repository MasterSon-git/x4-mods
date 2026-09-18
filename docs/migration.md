# Migration to the MSX4 namespace

Trade Data Explorer and MSX4 Script Library use new extension, order, script,
Mission Director, text-page and diagnostic identifiers. They replace the
earlier JP-namespaced development build; they are not add-ons for it.

An active custom behavior cannot transparently change to a new order ID.
Migrate a copy of the save as follows:

1. With the old `JP_TradeSubscriptionExplorer` and `JP_ScriptLibrary` build
   still installed, set every ship using TSE Sector, TSE Galaxy or a related
   Mimic assignment to Hold or another Vanilla behavior.
2. Save the game and exit X4.
3. Disable or remove both old JP-namespaced extensions.
4. Install and enable `MSX4_ScriptLibrary` and `MSX4_TradeDataExplorer`. Do not
   run both generations together: they patch some of the same Vanilla orders,
   and coexistence is neither intended nor tested.
5. Load the migrated save and assign Trade Data Explorer Sector or Galaxy
   again. Recreate Mimic assignments where applicable.
6. Verify the ships' behavior, then make a new save rather than overwriting
   the only pre-migration save.

Both new extensions declare `save="0"`, so they are not intended to become
hard save dependencies. That metadata does not migrate a currently active
custom order, which is why the behavior must be cleared before switching.
This procedure follows the static order/state design; a dedicated migration
smoke test remains required before release.
