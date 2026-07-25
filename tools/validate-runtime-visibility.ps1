[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tseRoot = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer'
$scriptLibraryRoot = Join-Path $repoRoot 'mods/JP_ScriptLibrary'

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

$sector = Read-XmlDocument (Join-Path $tseRoot 'aiscripts/JP_TradeSubscriptionExplorerS.xml')
$galaxy = Read-XmlDocument (Join-Path $tseRoot 'aiscripts/JP_TradeSubscriptionExplorerG.xml')
$update = Read-XmlDocument (Join-Path $tseRoot 'aiscripts/jp.lib.TSE.UpdateSubscription.xml')
$idle = Read-XmlDocument (Join-Path $scriptLibraryRoot 'aiscripts/jp.lib.IdleReturnHome.xml')
$tseMd = Read-XmlDocument (Join-Path $tseRoot 'md/jp.TradeSubscriptionExplorer.md.xml')
$scriptLibraryMd = Read-XmlDocument (Join-Path $scriptLibraryRoot 'md/jp.ScriptLibrary.md.xml')

$expectedOrders = @{
    $sector = 'JP_TradeSubscriptionExplorerS'
    $galaxy = 'JP_TradeSubscriptionExplorerG'
}
foreach ($entry in $expectedOrders.GetEnumerator()) {
    $order = $entry.Key.SelectSingleNode('/aiscript/order')
    Assert-Condition ($order.GetAttribute('id') -eq $entry.Value) "$($entry.Value) internal order ID changed."
    Assert-Condition ($entry.Key.DocumentElement.GetAttribute('name') -eq $entry.Value) "$($entry.Value) internal script ID changed."
    Assert-Condition ($order.GetAttribute('name') -match '^\{8888888, 97\}Trade Subscription Explorer - ') "$($entry.Value) visible name is not the expected text."
    Assert-Condition ($order.GetAttribute('name') -notmatch '^_|TradeSubscriptionExplorer') "$($entry.Value) visible name still has the legacy underscore or unspaced text."
}
Write-Output '1/6 visible behaviour names are improved while internal script and order IDs remain stable: OK'

foreach ($document in @($sector, $galaxy)) {
    $tagGuard = $document.SelectSingleNode("//do_if[@value='`$ADD_ORDER_TAG']")
    Assert-Condition ($null -ne $tagGuard) 'The ADD_ORDER_TAG guard is missing.'
    $tagSetters = @($document.SelectNodes('//set_object_name'))
    Assert-Condition ($tagSetters.Count -eq 1) 'Each TSE main script may have only one name mutation site.'
    Assert-Condition ($null -ne $tagSetters[0].SelectSingleNode("ancestor::do_if[@value='`$ADD_ORDER_TAG']")) 'Normal TSE name mutation must be guarded by ADD_ORDER_TAG.'
    Assert-Condition ($tagGuard.InnerXml -match [regex]::Escape('\033#FFA95908#[TSE]\033X ')) 'The visible [TSE] tag is missing.'
    Assert-Condition ($tagGuard.InnerXml -match '#TSE-S' -and $tagGuard.InnerXml -match '#TSE-G' -and $tagGuard.InnerXml -match '~ Idle') 'Tag setup must remove all legacy TSE markers before applying [TSE].'
}
Assert-Condition ($idle.SelectNodes('//set_object_name').Count -eq 0) 'IdleReturnHome must never mutate the visible ship name.'
Write-Output '2/6 ADD_ORDER_TAG=false has no normal rename path; enabled tagging is one idempotent [TSE] prefix without Idle suffix: OK'

$tseCleanup = $tseMd.SelectSingleNode("//cue[@name='TSE_ResetName_MD']//substitute_text")
$tseCleanupGuard = $tseMd.SelectSingleNode("//cue[@name='TSE_ResetName_MD']//do_if[set_object_name]")
$idleCleanupGuard = $scriptLibraryMd.SelectSingleNode("//cue[@name='SL_ManageIdleReturnHome_MD']//do_if[set_object_name]")
Assert-Condition ($null -ne $tseCleanup -and
    $tseCleanup.InnerXml -match [regex]::Escape('[TSE]') -and
    $tseCleanup.InnerXml -match '#TSE-S' -and
    $tseCleanup.InnerXml -match '#TSE-G' -and
    $tseCleanup.InnerXml -match '~ Idle') 'TSE cleanup must remove current and legacy tags.'
Assert-Condition ($tseCleanupGuard.GetAttribute('value') -eq 'event.param.knownname != $_ResultName') 'TSE cleanup must not write an unchanged name.'
Assert-Condition ($idleCleanupGuard.GetAttribute('value') -eq '$_Ship.knownname != $_ResultName') 'Idle legacy cleanup must not write an unchanged name.'
Write-Output '3/6 order change, Save/Load legacy state and Mimic cleanup remove tags without unconditional renames: OK'

$targetCommand = $update.SelectSingleNode(
    "//set_command[@command='command.investigate' and @param='`$STATION']"
)
$targetAction = $update.SelectSingleNode(
    "//set_command_action[@commandaction='commandaction.investigating' and @param='`$STATION']"
)
Assert-Condition ($null -ne $targetCommand -and $null -ne $targetAction) 'The update helper must expose the same station as command and action target.'
foreach ($document in @($sector, $galaxy)) {
    Assert-Condition ($null -ne $document.SelectSingleNode("//label[@name='SEARCH_LBL']/following-sibling::set_command[1][@command='command.investigate' and not(@param)]")) 'A fresh search must clear the station target.'
}
Assert-Condition ($null -ne $idle.SelectSingleNode("//set_command[@command='command.wait']")) 'The no-action idle state must expose Wait without a target.'
Write-Output '4/6 active station target is visible in the child context and search/idle states carry no stale station target: OK'

$newQueueOperations = @(
    & git -C $repoRoot diff 11027ec --unified=0 -- 'mods/JP_TradeSubscriptionExplorer' 'mods/JP_ScriptLibrary' |
        Where-Object { $_ -match '^\+(?!\+\+).*<(?:create_order|cancel_order|cancel_all_orders)\b' }
)
Assert-Condition ($LASTEXITCODE -eq 0) 'Could not inspect queue changes since the Experience/Skill commit.'
Assert-Condition ($newQueueOperations.Count -eq 0) 'Runtime visibility must not create or remove queue orders.'
Write-Output '5/6 UI visibility adds no visible suborder and does not change queue cleanup: OK'

$languageFiles = @(Get-ChildItem -LiteralPath (Join-Path $tseRoot 't') -File -Filter '*.xml')
$idSets = @(
    foreach ($file in $languageFiles) {
        $document = Read-XmlDocument $file.FullName
        [pscustomobject]@{
            Name = $file.Name
            Ids = (@($document.SelectNodes('/language/page/t') | ForEach-Object { $_.GetAttribute('id') }) -join ',')
        }
    }
)
Assert-Condition ($languageFiles.Count -eq 14) "Expected 14 TSE language files, got $($languageFiles.Count)."
$referenceIds = $idSets[0].Ids
Assert-Condition (@($idSets | Where-Object { $_.Ids -cne $referenceIds }).Count -eq 0) 'TSE language files do not have identical text-ID coverage.'
Write-Output '6/6 all 14 TSE language files retain identical text-ID coverage: OK'
Write-Output 'TSE runtime visibility validation: PASS'
