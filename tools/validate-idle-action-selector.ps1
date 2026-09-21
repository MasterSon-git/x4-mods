[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tdeRoot = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer'
$scriptLibraryRoot = Join-Path $repoRoot 'mods/MSX4_ScriptLibrary'
$referenceRoot = Join-Path $repoRoot 'x4-reference/x4-9.00/base'

function Assert-Condition {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        throw "Invariant failed: $Message"
    }
    Write-Host "PASS: $Message"
}

function Read-XmlDocument {
    param([Parameter(Mandatory)] [string] $Path)

    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.Load($Path)
    return $document
}

function Get-OrderParam {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlDocument] $Document,
        [Parameter(Mandatory)] [string] $Name
    )

    return $Document.SelectSingleNode("/aiscript/order/params/param[@name='$Name']")
}

$behaviorDocuments = @{
    Galaxy = Read-XmlDocument (Join-Path $tdeRoot 'aiscripts/MSX4_TradeDataExplorerG.xml')
    Sector = Read-XmlDocument (Join-Path $tdeRoot 'aiscripts/MSX4_TradeDataExplorerS.xml')
}

$newParamNames = @(
    'IDLE_ACTION',
    'IDLE_MOVE_TARGET',
    'START_POSITION',
    'IDLE_FOLLOW_TARGET',
    'IDLE_DOCK_TARGET'
)
$retiredPublicParamNames = @(
    'IDLE_MOVE_TO',
    'WHERE_TO_MOVE',
    'IDLE_FOLLOW',
    'WHO_TO_FOLLOW',
    'IDLE_DOCKING',
    'FIND_STATION',
    'WHERE_TO_DOCK'
)
$messageLevelDefaults = [ordered]@{
    SHOW_MESSAGES = 'if global.$MSX4_TDE_Settings? then global.$MSX4_TDE_Settings.{17} else 1'
    WRITE_TO_LOG  = 'if global.$MSX4_TDE_Settings? then global.$MSX4_TDE_Settings.{18} else 3'
}
$idleMapping = [ordered]@{
    IDLE_MOVE_TO  = '$_IdleMoveEnabled'
    WHERE_TO_MOVE = '$IDLE_MOVE_TARGET'
    IDLE_FOLLOW   = '$_IdleFollowEnabled'
    WHO_TO_FOLLOW = '$IDLE_FOLLOW_TARGET'
    IDLE_DOCKING  = '$_IdleDockEnabled'
    FIND_STATION  = '$_IdleFindStationEnabled'
    WHERE_TO_DOCK = 'if $_IdleDockSelectedEnabled then $IDLE_DOCK_TARGET else (if @$_LastSuccessfulStation.exists then $_LastSuccessfulStation else @global.$MSX4_TDE_IdleDockTargetTable.{$_Ship})'
}
$idleDerivations = [ordered]@{
    '$_IdleMoveEnabled'         = '($IDLE_ACTION == 1) or ($IDLE_ACTION == ''1'')'
    '$_IdleFollowEnabled'       = '($IDLE_ACTION == 2) or ($IDLE_ACTION == ''2'')'
    '$_IdleDockSelectedEnabled' = '($IDLE_ACTION == 3) or ($IDLE_ACTION == ''3'')'
    '$_IdleFindStationEnabled'  = '($IDLE_ACTION == 4) or ($IDLE_ACTION == ''4'')'
    '$_IdleDockEnabled'         = '$_IdleDockSelectedEnabled or $_IdleFindStationEnabled'
}
$expectedSavedSettings = '[$OWNERLESS_SECTORS,$WHARFS,$SHIPYARDS,$EQUIPMENTDOCKS,$TRADING_STATIONS,$PIRATE_BASES,$RECYCLING_FACILITIES,$DEFENCE_STATIONS,$FACTION_HEADQUARTERS,$NON_SPECIAL_STATIONS,$CONSTRUCTION_SITES,$IDLE_TIME,$IDLE_ACTION,$IDLE_MOVE_TARGET,$IDLE_FOLLOW_TARGET,$IDLE_DOCK_TARGET,$SHOW_MESSAGES,$WRITE_TO_LOG,$ADD_ORDER_TAG,$DEBUG]'

foreach ($entry in $behaviorDocuments.GetEnumerator()) {
    $mode = $entry.Key
    $document = $entry.Value

    foreach ($paramName in $newParamNames) {
        Assert-Condition ($null -ne (Get-OrderParam -Document $document -Name $paramName)) "$mode defines $paramName"
    }
    foreach ($paramName in $retiredPublicParamNames) {
        Assert-Condition ($null -eq (Get-OrderParam -Document $document -Name $paramName)) "$mode no longer exposes retired parameter $paramName"
    }

    $action = Get-OrderParam -Document $document -Name 'IDLE_ACTION'
    Assert-Condition ($action.type -eq 'number' -and
        $action.SelectSingleNode("input_param[@name='min']").value -eq '0' -and
        $action.SelectSingleNode("input_param[@name='max']").value -eq '4' -and
        $action.SelectSingleNode("input_param[@name='step']").value -eq '1') "$mode stores the single idle choice as a bounded integer from 0 through 4"

    foreach ($messageLevel in $messageLevelDefaults.GetEnumerator()) {
        $messageParam = Get-OrderParam -Document $document -Name $messageLevel.Key
        Assert-Condition ($messageParam.type -eq 'number' -and
            $messageParam.default -eq $messageLevel.Value -and
            $messageParam.SelectSingleNode("input_param[@name='min']").value -eq '0' -and
            $messageParam.SelectSingleNode("input_param[@name='max']").value -eq '3' -and
            $messageParam.SelectSingleNode("input_param[@name='step']").value -eq '1') "$mode preserves the numeric $($messageLevel.Key) contract and default"
    }

    $moveTarget = Get-OrderParam -Document $document -Name 'IDLE_MOVE_TARGET'
    $followTarget = Get-OrderParam -Document $document -Name 'IDLE_FOLLOW_TARGET'
    $dockTarget = Get-OrderParam -Document $document -Name 'IDLE_DOCK_TARGET'
    Assert-Condition ($moveTarget.type -eq 'position' -and $moveTarget.SelectSingleNode("input_param[@name='class']").value -eq 'class.sector') "$mode Move action uses Vanilla's position target parameter"
    Assert-Condition ($followTarget.type -eq 'object' -and $followTarget.SelectSingleNode("input_param[@name='class']").value -eq '[class.ship]') "$mode Follow action accepts a ship target"
    Assert-Condition ($dockTarget.type -eq 'object' -and $dockTarget.SelectSingleNode("input_param[@name='class']").value -eq '[class.station]') "$mode selected Dock action accepts only a station target"

    $idleOrder = @($document.SelectNodes('//create_order') | Where-Object { $_.id -eq "'MSX4_lib_IdleReturnHome'" })
    Assert-Condition ($idleOrder.Count -eq 1) "$mode creates exactly one internal idle order site"
    foreach ($derivation in $idleDerivations.GetEnumerator()) {
        $derived = @($document.SelectNodes('//set_value') | Where-Object {
            $_.name -eq $derivation.Key -and $_.exact -eq $derivation.Value
        })
        Assert-Condition ($derived.Count -eq 1) "$mode resolves $($derivation.Key) from exactly one selected action"
    }
    foreach ($mapping in $idleMapping.GetEnumerator()) {
        $forwarded = $idleOrder[0].SelectSingleNode("param[@name='$($mapping.Key)']")
        Assert-Condition ($null -ne $forwarded -and $forwarded.value -eq $mapping.Value) "$mode derives $($mapping.Key) exclusively from the selected action"
    }
    Assert-Condition ($null -ne $document.SelectSingleNode("//do_if[@value=`"`$_UpdateResult == 'success'`"]//set_value[@name='`$_LastSuccessfulStation' and @exact='`$_CandidateStation']")) "$mode records the last successfully visited station for automatic idle docking"
    Assert-Condition ($null -ne $idleOrder[0].SelectSingleNode("param[@name='MSX4_AUTO_IDLE_DOCK' and @value='`$_IdleFindStationEnabled']")) "$mode enables remembered targets only for automatic idle docking"
    Assert-Condition ($null -ne $idleOrder[0].SelectSingleNode("param[@name='MSX4_IDLE_DOCK_TARGET_STORE_SCRIPT' and @value=`"'msx4.tde.StoreIdleDockTarget'`"]")) "$mode delegates automatic dock-target persistence to TDE"

    $savedSettings = $document.SelectSingleNode("//append_list_elements[@name='`$global.$MSX4_TDE_Settings']")
    if ($null -eq $savedSettings) {
        $savedSettings = $document.SelectSingleNode("//append_list_elements[@name='global.`$MSX4_TDE_Settings']")
    }
    $normalizedSettings = $savedSettings.other -replace '\s', ''
    Assert-Condition ($normalizedSettings -eq $expectedSavedSettings) "$mode persists the 20-value idle selector settings contract"
}

$md = Read-XmlDocument (Join-Path $tdeRoot 'md/msx4.TradeDataExplorer.md.xml')
Assert-Condition ($null -ne $md.SelectSingleNode("//do_if[@value='@global.`$MSX4_TDE_Settings.count != 20']")) 'Mission Director invalidates settings lists that do not match the new 20-value contract'

$assist = Read-XmlDocument (Join-Path $tdeRoot 'aiscripts/order.assist.xml')
foreach ($paramName in $newParamNames) {
    if ($paramName -eq 'START_POSITION') {
        continue
    }
    Assert-Condition ($assist.SelectNodes("//create_order[@default='true']/param[@name='$paramName']").Count -eq 1) "Mimic promotion forwards $paramName"
    Assert-Condition ($assist.SelectNodes("//run_script[@name='`$scriptname']/param[@name='$paramName']").Count -eq 1) "Mimic execution forwards $paramName"
    Assert-Condition ($assist.SelectNodes("//set_value[@name='`$orderdef.`$$paramName']").Count -eq 1) "Mimic inheritance stores $paramName"
}
foreach ($paramName in $retiredPublicParamNames) {
    Assert-Condition ($assist.SelectNodes("//param[@name='$paramName'] | //set_value[contains(@name, '.$paramName')]").Count -eq 0) "Mimic integration no longer forwards retired parameter $paramName"
}

$uiPath = Join-Path $tdeRoot 'ui.xml'
$uiSchemaPath = Join-Path $referenceRoot 'ui/core/addon.xsd'
$schemaErrors = [System.Collections.Generic.List[string]]::new()
$schemaSet = [System.Xml.Schema.XmlSchemaSet]::new()
$null = $schemaSet.Add($null, $uiSchemaPath)
$readerSettings = [System.Xml.XmlReaderSettings]::new()
$readerSettings.Schemas = $schemaSet
$readerSettings.ValidationType = [System.Xml.ValidationType]::Schema
$readerSettings.add_ValidationEventHandler({
    param($Sender, $EventArgs)
    $schemaErrors.Add($EventArgs.Message)
})
$reader = [System.Xml.XmlReader]::Create($uiPath, $readerSettings)
try {
    while ($reader.Read()) { }
}
finally {
    $reader.Close()
}
Assert-Condition ($schemaErrors.Count -eq 0) 'UI addon manifest validates against the local X4 9.00 third-party addon schema'

$ui = Read-XmlDocument $uiPath
Assert-Condition ($ui.addon.name -eq 'msx4_trade_data_explorer') 'Third-party UI addon name does not use the reserved ego_ prefix'
Assert-Condition ($null -ne $ui.SelectSingleNode("/addon/environment/dependency[@name='ego_detailmonitor']")) 'UI addon loads after the Vanilla detail monitor'
Assert-Condition ($null -ne $ui.SelectSingleNode("/addon/environment/file[@name='ui/addons/msx4_trade_data_explorer/idle_action.lua']")) 'Extension-root UI addon manifest loads the idle-action adapter from the extension UI tree'
Assert-Condition (-not (Test-Path (Join-Path $tdeRoot 'ui/addons/msx4_trade_data_explorer/ui.xml'))) 'UI addon manifest is not misplaced below the extension UI tree'

$luaPath = Join-Path $tdeRoot 'ui/addons/msx4_trade_data_explorer/idle_action.lua'
$lua = Get-Content -Raw $luaPath
Assert-Condition ($lua.Contains('MSX4_TradeDataExplorerG = true') -and $lua.Contains('MSX4_TradeDataExplorerS = true')) 'UI adapter explicitly recognizes both Trade Data Explorer order IDs'
Assert-Condition ($lua.Contains('if isTradeDataExplorerOrder(order) then')) 'UI interception is guarded by a Trade Data Explorer order check'
for ($actionId = 0; $actionId -le 4; $actionId++) {
    $textId = 102 + $actionId
    Assert-Condition ($lua -match "\{ id = $actionId, text = ReadText\(975210, $textId\)") "UI dropdown defines action $actionId with text $textId"
}
for ($level = 0; $level -le 3; $level++) {
    $textId = 107 + $level
    Assert-Condition ($lua -match "\{ id = $level, text = ReadText\(975210, $textId\)") "UI dropdown defines message level $level with text $textId"
}
Assert-Condition ($lua.Contains('param.name == "SHOW_MESSAGES" or param.name == "WRITE_TO_LOG"')) 'UI adapter intercepts both message-level parameters inside the TDE order guard'
foreach ($mapping in @{
    IDLE_MOVE_TARGET = 1
    IDLE_FOLLOW_TARGET = 2
    IDLE_DOCK_TARGET = 3
}.GetEnumerator()) {
    Assert-Condition ($lua -match "$($mapping.Key)\s*=\s*$($mapping.Value)") "UI shows $($mapping.Key) only for action $($mapping.Value)"
}
Assert-Condition ($lua.Contains('return menu.slidercellSetOrderParam(orderidx, paramidx, listidx, tonumber(choice), instance)')) 'Dropdown converts its option id and uses Vanilla number-parameter update handling'
Assert-Condition ($lua.Contains('return vanillaDisplayOrderParam(ftable, orderidx, order, paramidx, param, listidx, instance)')) 'Contextual target rows delegate to Vanilla order-parameter rendering'
Assert-Condition ($lua -notmatch '(?m)^\s*SetOrderParam\(') 'UI adapter does not bypass Vanilla parameter update handling'
Assert-Condition (-not (Test-Path (Join-Path $tdeRoot 'ui/addons/msx4_trade_data_explorer/menu_map.lua'))) 'Mod does not copy or replace Vanilla menu_map.lua'

$localizationFiles = @(Get-ChildItem (Join-Path $scriptLibraryRoot 't') -Filter '*.xml' -File)
Assert-Condition ($localizationFiles.Count -eq 14) 'Expected Script Library localization set is present'
foreach ($file in $localizationFiles) {
    $localization = Read-XmlDocument $file.FullName
    foreach ($textId in 90..91) {
        $nodes = @($localization.SelectNodes("//page[@id='975210']/t[@id='$textId']"))
        Assert-Condition ($nodes.Count -eq 1 -and $nodes[0].InnerText -notmatch '[?？]$') "$($file.Name) defines message-level label $textId as a non-question exactly once"
    }
    foreach ($textId in 100..106) {
        $nodes = @($localization.SelectNodes("//page[@id='975210']/t[@id='$textId']"))
        Assert-Condition ($nodes.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($nodes[0].InnerText)) "$($file.Name) defines idle UI text $textId exactly once"
    }
    foreach ($textId in 107..110) {
        $nodes = @($localization.SelectNodes("//page[@id='975210']/t[@id='$textId']"))
        Assert-Condition ($nodes.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($nodes[0].InnerText)) "$($file.Name) defines message-level UI text $textId exactly once"
    }
}

$messageLog = Read-XmlDocument (Join-Path $scriptLibraryRoot 'aiscripts/msx4.lib.MessageLog.xml')
Assert-Condition ($messageLog.SelectSingleNode("/aiscript/params/param[@name='MESSAGE_CHANCE']").default -eq '1') 'Basic message events retain threshold 1'
Assert-Condition ($messageLog.SelectSingleNode("/aiscript/params/param[@name='LOG_CHANCE']").default -eq '1') 'Basic logbook events retain threshold 1'
$showThreshold = @($messageLog.SelectNodes('//set_value') | Where-Object {
    $_.name -eq '$_ShowMessages' -and $_.exact -eq 'if $SHOW_MESSAGES ge $MESSAGE_CHANCE then 100 else 0'
})
$logThreshold = @($messageLog.SelectNodes('//set_value') | Where-Object {
    $_.name -eq '$_WriteToLog' -and $_.exact -eq 'if $WRITE_TO_LOG ge $LOG_CHANCE then 100 else 0'
})
Assert-Condition ($showThreshold.Count -eq 1) 'Message display retains its numeric threshold semantics'
Assert-Condition ($logThreshold.Count -eq 1) 'Logbook output retains its numeric threshold semantics'

$sectorSearch = Read-XmlDocument (Join-Path $tdeRoot 'aiscripts/msx4.tde.GetTradeDataToUpdate.xml')
$sectorThresholds = @($sectorSearch.SelectNodes('//run_script/param') | Where-Object {
    ($_.name -eq 'MESSAGE_CHANCE' -or $_.name -eq 'LOG_CHANCE') -and $_.value -eq '2' -and $_.ParentNode.name -eq "'msx4.lib.MessageLog'"
})
Assert-Condition ($sectorThresholds.Count -eq 2) 'Sector-update messages retain threshold 2 for display and logbook output'

$stationUpdate = Read-XmlDocument (Join-Path $tdeRoot 'aiscripts/msx4.tde.UpdateTradeData.xml')
$stationThresholds = @($stationUpdate.SelectNodes('//run_script/param') | Where-Object {
    ($_.name -eq 'MESSAGE_CHANCE' -or $_.name -eq 'LOG_CHANCE') -and $_.value -eq '3' -and $_.ParentNode.name -eq "'msx4.lib.MessageLog'"
})
Assert-Condition ($stationThresholds.Count -eq 2) 'Station-update messages retain threshold 3 for display and logbook output'

Write-Host 'Trade Data Explorer order-parameter dropdown regression: PASS'
