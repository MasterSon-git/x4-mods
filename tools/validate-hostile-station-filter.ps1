[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

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

function Get-ElementIndex {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlNode] $Parent,
        [Parameter(Mandatory)] [System.Xml.XmlNode] $Target
    )

    $elements = @($Parent.ChildNodes | Where-Object {
        $_.NodeType -eq [System.Xml.XmlNodeType]::Element
    })
    return [array]::IndexOf($elements, $Target)
}

$targetsPath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_TradeSubscriptionExplorer/aiscripts/jp.lib.TSE.GetTradesubscriptionsToUpdate.xml'
$updatePath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_TradeSubscriptionExplorer/aiscripts/jp.lib.TSE.UpdateSubscription.xml'
$vanillaReconPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/aiscripts/order.move.recon.xml'
$propertiesPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/libraries/scriptproperties.xml'

$targets = Read-XmlDocument $targetsPath
$update = Read-XmlDocument $updatePath
$vanillaRecon = Read-XmlDocument $vanillaReconPath
$properties = Read-XmlDocument $propertiesPath

$vanillaRelationFilter = $vanillaRecon.SelectSingleNode(
    "//do_if[@value='`$exploreupdate']//find_station[@name='`$list_knownstations']/match_relation_to[@relation='dock' and @object='this.assignedcontrolled']"
)
$hostilityProperties = @($properties.SelectNodes("//property[@name='ishostileto.{`$component}' or @name='ishostileto.{`$faction}']"))
Assert-Condition ($null -ne $vanillaRelationFilter) 'Vanilla ExploreUpdate no longer relation-filters known stations.'
Assert-Condition ($hostilityProperties.Count -gt 0) 'The documented X4 9.00 ishostileto property is missing.'
Write-Output '1/5 Vanilla ExploreUpdate relation safety and the documented mutual-hostility property are present: OK'

$stationLoop = $targets.SelectSingleNode("//do_for_each[@name='`$_Station' and @in='`$_Stations']")
Assert-Condition ($null -ne $stationLoop) 'The productive station-candidate loop is missing.'
$hostileSelectionGuard = $stationLoop.SelectSingleNode(
    "do_if[contains(@value, '`$_Ship.ishostileto.{`$_Station}') and contains(@value, '`$_Ship.ishostileto.{`$_SubscriptionTarget}')]"
)
$subscriptionGuard = $stationLoop.SelectSingleNode(
    "do_if[contains(@value, '`$_SubscriptionTarget.hastradesubscription')]"
)
$pathFinder = $stationLoop.SelectSingleNode("get_global_path[end/@object='`$_SubscriptionTarget']")
Assert-Condition ($null -ne $hostileSelectionGuard) 'The productive station loop does not reject hostile stations and buildstorage targets.'
Assert-Condition ($null -ne $hostileSelectionGuard.SelectSingleNode('continue')) 'The hostile candidate guard does not skip the candidate.'
Assert-Condition ($null -ne $hostileSelectionGuard.SelectSingleNode(".//debug_to_file[contains(@text, 'reason=hostile_target')]")) 'The hostile candidate exclusion has no structured reason.'
Assert-Condition ((Get-ElementIndex $stationLoop $hostileSelectionGuard) -lt (Get-ElementIndex $stationLoop $subscriptionGuard)) 'Hostility must be checked before normal subscription/blacklist processing.'
Assert-Condition ((Get-ElementIndex $stationLoop $hostileSelectionGuard) -lt (Get-ElementIndex $stationLoop $pathFinder)) 'A hostile target can reach path calculation.'
Write-Output '2/5 hostile stations and construction targets are removed before path calculation or reservation output: OK'

$traceHostileGuard = $targets.SelectSingleNode(
    "//do_for_each[@name='`$_TraceExpiredStation']/do_if[@value='`$_Ship.ishostileto.{`$_TraceExpiredStation}']"
)
Assert-Condition ($null -ne $traceHostileGuard) 'DEBUG diagnostics do not distinguish hostile expired stations.'
Assert-Condition ($null -ne $traceHostileGuard.SelectSingleNode("debug_to_file[contains(@text, 'reason=hostile_target')]")) 'DEBUG diagnostics use no stable hostile-target reason.'
Write-Output '3/5 DEBUG diagnostics identify hostile expired stations without affecting candidate selection: OK'

$validationLibrary = $update.SelectSingleNode("//interrupts/library/actions[@name='ValidateTarget']")
$hostileValidationGuard = $validationLibrary.SelectSingleNode(
    ".//do_if[contains(@value, '`$_Ship.ishostileto.{`$STATION}') and contains(@value, '`$_Ship.ishostileto.{`$_Station}')]"
)
Assert-Condition ($null -ne $hostileValidationGuard) 'Dynamic target validation does not reject a hostile source station and resolved target.'
Assert-Condition ($null -ne $hostileValidationGuard.SelectSingleNode("set_value[@name='`$_ValidationStatus' and @exact=`"'target_disallowed'`"]")) 'A hostile dynamic target does not return target_disallowed.'
Assert-Condition ($null -ne $hostileValidationGuard.SelectSingleNode(".//set_value[@name='`$_ValidationReason' and @exact=`"'hostile_target'`"]")) 'A hostile dynamic target has no stable validation reason.'
$validationCalls = @($update.SelectNodes("//attention[@min='unknown']/actions//include_interrupt_actions[@ref='ValidateTarget']"))
$waitValidation = $update.SelectSingleNode("//do_while/include_interrupt_actions[@ref='ValidateTarget']")
Assert-Condition ($validationCalls.Count -eq 4) "Expected four target revalidations, got $($validationCalls.Count)."
Assert-Condition ($null -ne $waitValidation) 'The subscription wait loop does not re-check dynamic hostility.'
Write-Output '4/5 hostility is revalidated before travel, after travel, after approach and during the subscription wait: OK'

$modFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'mods/JP_X4Mods/JP_TradeSubscriptionExplorer') -Recurse -File -Filter '*.xml')
$hardcodedHostileFactions = @($modFiles | Select-String -Pattern 'faction\.(?:khaak|xenon)' -CaseSensitive)
$forbiddenActions = @($modFiles | Select-String -Pattern '<(?:scan_|reveal_|set_trade_subscription|add_trade_subscription|subscribe_)')
Assert-Condition ($hardcodedHostileFactions.Count -eq 0) 'The fix hardcodes Khaak or Xenon instead of applying the hostility contract uniformly.'
Assert-Condition ($forbiddenActions.Count -eq 0) 'The fix introduced scanning, reveal, or permanent trade-subscription behavior.'
Write-Output '5/5 the rule is faction-agnostic and adds no scan, reveal, economy, or permanent-subscription action: OK'
Write-Output 'TSE hostile station target validation: PASS'
