[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tdeRoot = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer'
$scriptLibraryRoot = Join-Path $repoRoot 'mods/MSX4_ScriptLibrary'

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

$sector = Read-XmlDocument (Join-Path $tdeRoot 'aiscripts/MSX4_TradeDataExplorerS.xml')
$galaxy = Read-XmlDocument (Join-Path $tdeRoot 'aiscripts/MSX4_TradeDataExplorerG.xml')
$update = Read-XmlDocument (Join-Path $tdeRoot 'aiscripts/msx4.tde.UpdateTradeData.xml')
$idle = Read-XmlDocument (Join-Path $scriptLibraryRoot 'aiscripts/msx4.lib.IdleReturnHome.xml')
$tdeMd = Read-XmlDocument (Join-Path $tdeRoot 'md/msx4.TradeDataExplorer.md.xml')
$scriptLibraryMd = Read-XmlDocument (Join-Path $scriptLibraryRoot 'md/msx4.ScriptLibrary.md.xml')

$expectedOrders = @{
    $sector = 'MSX4_TradeDataExplorerS'
    $galaxy = 'MSX4_TradeDataExplorerG'
}
foreach ($entry in $expectedOrders.GetEnumerator()) {
    $order = $entry.Key.SelectSingleNode('/aiscript/order')
    Assert-Condition ($order.GetAttribute('id') -eq $entry.Value) "$($entry.Value) internal order ID changed."
    Assert-Condition ($entry.Key.DocumentElement.GetAttribute('name') -eq $entry.Value) "$($entry.Value) internal script ID changed."
    Assert-Condition ($order.GetAttribute('name') -match '^\{975210, 97\}Trade Data Explorer - ') "$($entry.Value) visible name is not the expected text."
    Assert-Condition ($order.GetAttribute('name') -notmatch '^_|TradeDataExplorer') "$($entry.Value) visible name still has the legacy underscore or unspaced text."
}
Write-Output '1/6 visible behaviour names are improved while internal script and order IDs remain stable: OK'

foreach ($document in @($sector, $galaxy)) {
    $tagGuard = $document.SelectSingleNode("//do_if[@value='`$ADD_ORDER_TAG']")
    Assert-Condition ($null -ne $tagGuard) 'The ADD_ORDER_TAG guard is missing.'
    $tagSetters = @($document.SelectNodes('//set_object_name'))
    Assert-Condition ($tagSetters.Count -eq 1) 'Each TDE main script may have only one name mutation site.'
    Assert-Condition ($null -ne $tagSetters[0].SelectSingleNode("ancestor::do_if[@value='`$ADD_ORDER_TAG']")) 'Normal TDE name mutation must be guarded by ADD_ORDER_TAG.'
    Assert-Condition ($tagGuard.InnerXml -match [regex]::Escape('\033#FFA95908#[MSX4-TDE]\033X ')) 'The visible [MSX4-TDE] tag is missing.'
    Assert-Condition ($tagGuard.InnerXml -match '#MSX4-TDE-S' -and $tagGuard.InnerXml -match '#MSX4-TDE-G' -and $tagGuard.InnerXml -match '~ Idle') 'Tag setup must remove all current MSX4-TDE markers before applying [MSX4-TDE].'
    Assert-Condition ($tagGuard.InnerXml -match [regex]::Escape('[TSE]') -and $tagGuard.InnerXml -match [regex]::Escape('[TDE]')) 'Tag setup must remove legacy JP and pre-release development tags during migration.'
}
Assert-Condition ($idle.SelectNodes('//set_object_name').Count -eq 0) 'IdleReturnHome must never mutate the visible ship name.'
Write-Output '2/6 ADD_ORDER_TAG=false has no normal rename path; enabled tagging is one idempotent [MSX4-TDE] prefix without Idle suffix: OK'

$tdeCleanup = $tdeMd.SelectSingleNode("//cue[@name='TDE_ResetName_MD']//substitute_text")
$tdeCleanupGuard = $tdeMd.SelectSingleNode("//cue[@name='TDE_ResetName_MD']//do_if[set_object_name]")
$idleCleanupGuard = $scriptLibraryMd.SelectSingleNode("//cue[@name='MSX4_SL_ManageIdleReturnHome_MD']//do_if[set_object_name]")
Assert-Condition ($null -ne $tdeCleanup -and
    $tdeCleanup.InnerXml -match [regex]::Escape('[MSX4-TDE]') -and
    $tdeCleanup.InnerXml -match '#MSX4-TDE-S' -and
    $tdeCleanup.InnerXml -match '#MSX4-TDE-G' -and
    $tdeCleanup.InnerXml -match [regex]::Escape('[TSE]') -and
    $tdeCleanup.InnerXml -match [regex]::Escape('[TDE]') -and
    $tdeCleanup.InnerXml -match '~ Idle') 'TDE cleanup must remove current and legacy tags.'
Assert-Condition ($tdeCleanupGuard.GetAttribute('value') -eq 'event.param.knownname != $_ResultName') 'TDE cleanup must not write an unchanged name.'
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

$queueContractPairs = @{
    'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerS.xml' = 'mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerS.xml'
    'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerG.xml' = 'mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerG.xml'
    'mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.UpdateTradeData.xml' = 'mods/JP_TradeSubscriptionExplorer/aiscripts/jp.lib.TSE.UpdateSubscription.xml'
    'mods/MSX4_TradeDataExplorer/md/msx4.TradeDataExplorer.md.xml' = 'mods/JP_TradeSubscriptionExplorer/md/jp.TradeSubscriptionExplorer.md.xml'
    'mods/MSX4_ScriptLibrary/aiscripts/msx4.lib.IdleReturnHome.xml' = 'mods/JP_ScriptLibrary/aiscripts/jp.lib.IdleReturnHome.xml'
    'mods/MSX4_ScriptLibrary/md/msx4.ScriptLibrary.md.xml' = 'mods/JP_ScriptLibrary/md/jp.ScriptLibrary.md.xml'
}
$queueBaseline = 'd2efdbda348179b465b4781948b0c9243e9fe2df'
foreach ($pair in $queueContractPairs.GetEnumerator()) {
    $historicalText = (& git -C $repoRoot show "$queueBaseline`:$($pair.Value)") -join [Environment]::NewLine
    Assert-Condition ($LASTEXITCODE -eq 0) "Could not read the queue baseline for $($pair.Value)."
    $historical = [System.Xml.XmlDocument]::new()
    $historical.LoadXml($historicalText)
    $current = Read-XmlDocument (Join-Path $repoRoot $pair.Key)
    $queueXPath = '//*[self::create_order or self::cancel_order or self::cancel_all_orders]'
    Assert-Condition ($current.SelectNodes($queueXPath).Count -eq $historical.SelectNodes($queueXPath).Count) "$($pair.Key) changed the number of queue operations."
}
Write-Output '5/6 UI visibility adds no visible suborder and does not change queue cleanup: OK'

$languageFiles = @(Get-ChildItem -LiteralPath (Join-Path $tdeRoot 't') -File -Filter '*.xml')
$idSets = @(
    foreach ($file in $languageFiles) {
        $document = Read-XmlDocument $file.FullName
        [pscustomobject]@{
            Name = $file.Name
            Ids = (@($document.SelectNodes('/language/page/t') | ForEach-Object { $_.GetAttribute('id') }) -join ',')
        }
    }
)
Assert-Condition ($languageFiles.Count -eq 14) "Expected 14 TDE language files, got $($languageFiles.Count)."
$referenceIds = $idSets[0].Ids
Assert-Condition (@($idSets | Where-Object { $_.Ids -cne $referenceIds }).Count -eq 0) 'TDE language files do not have identical text-ID coverage.'
Write-Output '6/6 all 14 TDE language files retain identical text-ID coverage: OK'
Write-Output 'TDE runtime visibility validation: PASS'
