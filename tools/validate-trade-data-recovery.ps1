[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$updatePath = Join-Path $repoRoot 'mods\MSX4_TradeDataExplorer\aiscripts\msx4.tde.UpdateTradeData.xml'
$dockDiffPath = Join-Path $repoRoot 'mods\MSX4_TradeDataExplorer\aiscripts\order.dock.xml'
$vanillaDockPath = Join-Path $repoRoot 'x4-reference\x4-9.00\base\aiscripts\order.dock.xml'

function Assert-Condition {
    param([bool] $Condition, [string] $Message)

    if (-not $Condition) {
        throw "Invariant failed: $Message"
    }
    Write-Host "PASS: $Message"
}

function Read-XmlDocument {
    param([string] $Path)

    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.Load($Path)
    return $document
}

$update = Read-XmlDocument $updatePath
$dockDiff = Read-XmlDocument $dockDiffPath
$vanillaDock = Read-XmlDocument $vanillaDockPath

$distances = $update.SelectSingleNode("//set_value[@name='`$_ApproachDistances']")
Assert-Condition ($distances.GetAttribute('exact') -ceq "[(`$_Ship.maxradarrange * 0.75), (`$_Ship.maxradarrange * 0.4), (`$_Ship.maxradarrange * 0.2)]") 'recovery starts at the historical 75% radar distance and advances through 40% and 20%'

$stages = $update.SelectSingleNode("//do_for_each[@name='`$_ApproachDistance' and @in='`$_ApproachDistances']")
$stageMove = $stages.SelectSingleNode(".//run_script[@name=`"'msx4.lib.MoveToObject'`" and @result='`$_ApproachSuccess']")
$stageGrace = $stages.SelectSingleNode("do_all[@exact='2' and @counter='`$_ApproachWaitCheck']")
Assert-Condition ($null -ne $stageMove.SelectSingleNode("param[@name='DISTANCE_TO_OBJECT' and @value='`$_ApproachDistance']")) 'each recovery stage uses the existing collision-safe MoveToObject helper'
Assert-Condition ($null -ne $stages.SelectSingleNode("do_if[contains(@value, '`$_Ship.distanceto.{`$_Station}') and contains(@value, 'gt `$_ApproachDistance')]")) 'an outer stage never moves a ship away from a station it is already close to'
Assert-Condition ($null -ne $stageGrace.SelectSingleNode("wait[@exact='5s']") -and $null -ne $stageGrace.SelectSingleNode("include_interrupt_actions[@ref='ValidateTarget']")) 'each stage provides two bounded five-second engine update opportunities'
Assert-Condition ($update.SelectNodes("//do_while[.//include_interrupt_actions[@ref='ValidateTarget']]").Count -eq 0) 'the former unbounded trade-data wait loop is absent'

$conditionalUndock = $update.SelectSingleNode("//do_if[@value='`$_Ship.dock and not `$_Ship.hascontext.{`$_Station}']/run_script[@name=`"'move.undock'`"]")
Assert-Condition ($null -ne $conditionalUndock -and $null -ne $conditionalUndock.SelectSingleNode("param[@name='debugchance' and @value='`$debugchance']")) 'a retained recovery dock is released only after another valid target is assigned'

$dockingAllowed = $update.SelectSingleNode("//set_value[@name='`$_DockingAllowed' and @exact='`$_Station.dockingallowed.{`$_Ship}']")
$dockFinder = $update.SelectSingleNode("//find_dockingbay[@object='`$_Station' and @name='`$_RecoveryDock']")
$dockMatch = $dockFinder.SelectSingleNode("match_dock[@size='`$_Ship.docksize' and @storage='false' and @trading='false' and @building='false' and @allowplayeronly='false' and @showroom='false' and @ventureronly='false']")
Assert-Condition ($null -ne $dockingAllowed -and $null -ne $dockMatch -and $null -ne $dockFinder.SelectSingleNode("match_relation_to[@object='`$_Ship' and @comparison='not' and @relation='enemy']")) 'dock recovery preflights Vanilla permission, compatible size and relation constraints'

$dockCall = $update.SelectSingleNode("//do_if[@value='`$_DockEligible']/run_script[@name=`"'order.dock'`" and @result='`$_DockSuccess']")
foreach ($expected in @(
    @{ Name = 'destination'; Value = '$_Station' },
    @{ Name = 'waittime'; Value = '30s' },
    @{ Name = 'store'; Value = 'false' },
    @{ Name = 'dockfollowers'; Value = 'false' },
    @{ Name = 'internalorder'; Value = 'false' },
    @{ Name = 'recallsubordinates'; Value = 'false' },
    @{ Name = 'MSX4_TDE_TRADE_DATA_RECOVERY'; Value = 'true' }
)) {
    Assert-Condition ($null -ne $dockCall.SelectSingleNode("param[@name='$($expected.Name)' and @value='$($expected.Value)']")) "dock recovery fixes $($expected.Name) to $($expected.Value)"
}
Assert-Condition ($update.SelectNodes('//create_order').Count -eq 0) 'recovery does not enqueue a new order or replace the TDE default behavior'

$marker = $dockDiff.SelectSingleNode("/diff/add[@sel='/aiscript/order/params']/param[@name='MSX4_TDE_TRADE_DATA_RECOVERY' and @type='internal' and @default='false']")
$feedbackGuard = $dockDiff.SelectSingleNode("/diff/add[@sel='/aiscript/init']/set_value[@name='`$nofeedback' and @exact='true' and @chance='if `$MSX4_TDE_TRADE_DATA_RECOVERY then 100 else 0']")
$failureGuard = $dockDiff.SelectSingleNode("/diff/replace[contains(@sel, 'set_order_failed')]/do_if[@value='not `$MSX4_TDE_TRADE_DATA_RECOVERY']/set_order_failed")
Assert-Condition ($null -ne $marker -and $null -ne $feedbackGuard -and $null -ne $failureGuard) 'Vanilla dock failure and feedback suppression are opt-in and limited to the marked recovery call'

$vanillaCompatibleDock = $vanillaDock.SelectSingleNode("//find_dockingbay[@object='`$destination']/match_dock[@size='`$thisship.docksize' and @storage='false']")
$vanillaQueuedWait = $vanillaDock.SelectSingleNode("//do_if[@value='`$queuedresult']//wait[@exact='[10s, `$waittime].min']")
$vanillaSuccess = $vanillaDock.SelectSingleNode("//return[@value='true']")
$vanillaFailure = $vanillaDock.SelectSingleNode("//return[@value='false']")
Assert-Condition ($null -ne $vanillaCompatibleDock -and $null -ne $vanillaQueuedWait -and $null -ne $vanillaSuccess -and $null -ne $vanillaFailure) 'X4 9.00 order.dock supplies compatible-dock selection, bounded queued waiting and a boolean result'

$finalDistance = $update.SelectSingleNode("//set_value[@name='`$_FinalApproachDistance' and @exact='2km']")
$finalMove = $update.SelectSingleNode("//run_script[@name=`"'msx4.lib.MoveToObject'`"] /param[@name='DISTANCE_TO_OBJECT' and @value='`$_FinalApproachDistance']")
$finalWait = $update.SelectSingleNode("//do_all[@exact='2' and @counter='`$_FinalWaitCheck']/wait[@exact='5s']")
$timeouts = @($update.SelectNodes("//set_value[@name='`$_Result' and @exact=`"'update_timeout'`"]"))
Assert-Condition ($null -ne $finalDistance -and $null -ne $finalMove -and $null -ne $finalWait -and $timeouts.Count -eq 2) 'failed or ineligible docking falls back to a bounded 2 km approach and terminates with update_timeout'

$forbidden = @($update.SelectNodes("//*[starts-with(local-name(), 'scan_') or starts-with(local-name(), 'reveal_') or contains(local-name(), 'trade_subscription')]"))
Assert-Condition ($forbidden.Count -eq 0) 'recovery adds no scan, reveal or permanent trade-subscription action'

& git -c core.autocrlf=false -C $repoRoot diff --check
Assert-Condition ($LASTEXITCODE -eq 0) 'git diff --check passes'

Write-Host 'Trade-data recovery regression: PASS'
