[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tdeMdPath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/md/msx4.TradeDataExplorer.md.xml'
$tdeSinglePath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerS.xml'
$tdeGalaxyPath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerG.xml'
$tdeAssistDiffPath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/order.assist.xml'
$vanillaAssistPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/aiscripts/order.assist.xml'

function Assert-Condition {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        throw "Invariant failed: $Message"
    }
}

function Read-XmlDocument {
    param([Parameter(Mandatory)] [string] $Path)

    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.Load($Path)
    return $document
}

$tdeMd = Read-XmlDocument -Path $tdeMdPath
$tdeSingle = Read-XmlDocument -Path $tdeSinglePath
$tdeGalaxy = Read-XmlDocument -Path $tdeGalaxyPath
$tdeAssistDiff = Read-XmlDocument -Path $tdeAssistDiffPath
$vanillaAssist = Read-XmlDocument -Path $vanillaAssistPath
Write-Output 'XML well-formedness: OK (4 mod files, 1 vanilla reference)'

$setupCue = $tdeMd.SelectSingleNode("/mdscript/cues/cue[@name='TDE_Setup_MD']")
Assert-Condition ($null -ne $setupCue) 'TDE_Setup_MD must exist.'
Assert-Condition ($null -eq $setupCue.SelectSingleNode("cues/cue[@name='TDE_EventObjectOrderReady1_MD']")) 'The activation-time order-ready cancellation cue must remain removed.'

$tdeReadyCancellations = $setupCue.SelectNodes("cues/cue[conditions/event_object_order_ready and conditions//check_value[contains(@value, '@event.param.id')]]/actions//cancel_all_orders")
Assert-Condition ($tdeReadyCancellations.Count -eq 0) 'No TDE order-ready handler may cancel the newly activated TDE order.'

$cleanupCue = $setupCue.SelectSingleNode("cues/cue[@name='TDE_EventObjectOrderReady2_MD']")
Assert-Condition ($null -ne $cleanupCue) 'The cleanup listener for leaving TDE must remain present.'
Assert-Condition ($null -ne $cleanupCue.SelectSingleNode("conditions/event_object_order_ready[@group='global.`$MSX4_SL_PlayerShips']")) 'The cleanup listener must still observe player-ship order changes.'
Assert-Condition ($null -ne $cleanupCue.SelectSingleNode("actions/signal_cue_instantly[@cue='TDE_ClearBlacklist_MD']")) 'Leaving TDE must still clear the ship reservation and group membership.'
Assert-Condition ($null -ne $cleanupCue.SelectSingleNode("actions/signal_cue_instantly[@cue='TDE_ResetName_MD']")) 'Leaving TDE must still reset the ship name.'

foreach ($orderDocument in @($tdeSingle, $tdeGalaxy)) {
    $orderId = $orderDocument.DocumentElement.GetAttribute('name')
    Assert-Condition ($null -ne $orderDocument.SelectSingleNode("/aiscript/init/add_to_group[@groupname='global.`$MSX4_TDE_ShipsGroup']")) "$orderId must still register its active ship for cleanup and reservations."
}

$assistRestartHandler = $vanillaAssist.SelectSingleNode("/aiscript/interrupts/handler[conditions/check_any/check_all/event_object_order_ready[@object='`$orderobject'] and actions/abort_called_scripts[@resume='init']]")
Assert-Condition ($null -ne $assistRestartHandler) 'Vanilla order.assist must still restart inherited behavior when the commander default order becomes ready.'
Assert-Condition ($null -ne $tdeAssistDiff.SelectSingleNode("/diff/add/do_if[contains(@value, 'MSX4_TradeDataExplorerG')]")) 'The TDE Galaxy compatibility branch must remain in the order.assist diff.'

Write-Output 'TDE activation-time order cancellation: absent'
Write-Output 'TDE leave-order cleanup listener: preserved'
Write-Output 'TDE active-ship registration: preserved (S and G)'
Write-Output 'Vanilla Assist order-change restart and TDE inheritance branch: preserved'
