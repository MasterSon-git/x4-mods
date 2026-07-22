[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tseMdPath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/md/jp.TradeSubscriptionExplorer.md.xml'
$tseSinglePath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerS.xml'
$tseGalaxyPath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerG.xml'
$tseAssistDiffPath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/aiscripts/order.assist.xml'
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

$tseMd = Read-XmlDocument -Path $tseMdPath
$tseSingle = Read-XmlDocument -Path $tseSinglePath
$tseGalaxy = Read-XmlDocument -Path $tseGalaxyPath
$tseAssistDiff = Read-XmlDocument -Path $tseAssistDiffPath
$vanillaAssist = Read-XmlDocument -Path $vanillaAssistPath
Write-Output 'XML well-formedness: OK (4 mod files, 1 vanilla reference)'

$setupCue = $tseMd.SelectSingleNode("/mdscript/cues/cue[@name='TSE_Setup_MD']")
Assert-Condition ($null -ne $setupCue) 'TSE_Setup_MD must exist.'
Assert-Condition ($null -eq $setupCue.SelectSingleNode("cues/cue[@name='TSE_EventObjectOrderReady1_MD']")) 'The activation-time order-ready cancellation cue must remain removed.'

$tseReadyCancellations = $setupCue.SelectNodes("cues/cue[conditions/event_object_order_ready and conditions//check_value[contains(@value, '@event.param.id')]]/actions//cancel_all_orders")
Assert-Condition ($tseReadyCancellations.Count -eq 0) 'No TSE order-ready handler may cancel the newly activated TSE order.'

$cleanupCue = $setupCue.SelectSingleNode("cues/cue[@name='TSE_EventObjectOrderReady2_MD']")
Assert-Condition ($null -ne $cleanupCue) 'The cleanup listener for leaving TSE must remain present.'
Assert-Condition ($null -ne $cleanupCue.SelectSingleNode("conditions/event_object_order_ready[@group='global.`$SL_PlayerShips']")) 'The cleanup listener must still observe player-ship order changes.'
Assert-Condition ($null -ne $cleanupCue.SelectSingleNode("actions/signal_cue_instantly[@cue='TSE_ClearBlacklist_MD']")) 'Leaving TSE must still clear the ship reservation and group membership.'
Assert-Condition ($null -ne $cleanupCue.SelectSingleNode("actions/signal_cue_instantly[@cue='TSE_ResetName_MD']")) 'Leaving TSE must still reset the ship name.'

foreach ($orderDocument in @($tseSingle, $tseGalaxy)) {
    $orderId = $orderDocument.DocumentElement.GetAttribute('name')
    Assert-Condition ($null -ne $orderDocument.SelectSingleNode("/aiscript/init/add_to_group[@groupname='global.`$TSE_ShipsGroup']")) "$orderId must still register its active ship for cleanup and reservations."
}

$assistRestartHandler = $vanillaAssist.SelectSingleNode("/aiscript/interrupts/handler[conditions/check_any/check_all/event_object_order_ready[@object='`$orderobject'] and actions/abort_called_scripts[@resume='init']]")
Assert-Condition ($null -ne $assistRestartHandler) 'Vanilla order.assist must still restart inherited behavior when the commander default order becomes ready.'
Assert-Condition ($null -ne $tseAssistDiff.SelectSingleNode("/diff/add/do_if[contains(@value, 'JP_TradeSubscriptionExplorerG')]")) 'The TSE Galaxy compatibility branch must remain in the order.assist diff.'

Write-Output 'TSE activation-time order cancellation: absent'
Write-Output 'TSE leave-order cleanup listener: preserved'
Write-Output 'TSE active-ship registration: preserved (S and G)'
Write-Output 'Vanilla Assist order-change restart and TSE inheritance branch: preserved'
