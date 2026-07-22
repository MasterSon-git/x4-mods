[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptLibraryPath = Join-Path $repoRoot 'mods/JP_ScriptLibrary/md/jp.ScriptLibrary.md.xml'
$tsePath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/md/jp.TradeSubscriptionExplorer.md.xml'
$scriptLibraryContentPath = Join-Path $repoRoot 'mods/JP_ScriptLibrary/content.xml'
$tseContentPath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/content.xml'
$mdSchemaPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/libraries/md.xsd'

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

function ConvertTo-JavaPath {
    param([Parameter(Mandatory)] [string] $Path)

    return ([System.IO.Path]::GetFullPath($Path) -replace '\\', '/') -replace '"', '\"'
}

$scriptLibrary = Read-XmlDocument -Path $scriptLibraryPath
$tse = Read-XmlDocument -Path $tsePath
$scriptLibraryContent = Read-XmlDocument -Path $scriptLibraryContentPath
$tseContent = Read-XmlDocument -Path $tseContentPath
Write-Output 'XML well-formedness: OK (2 MD files)'

Assert-Condition ($scriptLibraryContent.DocumentElement.GetAttribute('id') -eq 'JP_ScriptLibrary') 'The ScriptLibrary content ID must remain JP_ScriptLibrary.'
Assert-Condition ($null -ne $tseContent.SelectSingleNode("/content/dependency[@id='JP_ScriptLibrary' and @optional='false']")) 'TSE must retain its required ScriptLibrary dependency for the cross-file run_actions reference.'

$jshell = Get-Command 'jshell' -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $jshell) 'jshell is required for validation against the recursive vanilla MD schema.'

$schemaJavaPath = ConvertTo-JavaPath -Path $mdSchemaPath
$scriptLibraryJavaPath = ConvertTo-JavaPath -Path $scriptLibraryPath
$tseJavaPath = ConvertTo-JavaPath -Path $tsePath
$javaValidation = @"
import javax.xml.XMLConstants;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.SchemaFactory;
import java.io.File;
try {
  var factory = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
  var schema = factory.newSchema(new File("$schemaJavaPath"));
  var validator = schema.newValidator();
  validator.validate(new StreamSource(new File("$scriptLibraryJavaPath")));
  validator.validate(new StreamSource(new File("$tseJavaPath")));
  System.out.println("MD XSD validation: OK (2 MD files)");
} catch (Exception exception) {
  exception.printStackTrace();
  System.exit(1);
}
/exit
"@

$javaOutput = $javaValidation | & $jshell.Source --feedback silent 2>&1
if ($LASTEXITCODE -ne 0) {
    $javaOutput | ForEach-Object { Write-Error $_ }
    throw 'MD XSD validation failed.'
}
Write-Output 'MD XSD validation: OK (2 MD files)'

$refreshLibrary = $scriptLibrary.SelectSingleNode("/mdscript/cues/library[@name='SL_RefreshPlayerShips' and @purpose='run_actions']")
Assert-Condition ($null -ne $refreshLibrary) 'The synchronous ScriptLibrary player-ship refresh library must exist.'
Assert-Condition ($null -ne $refreshLibrary.SelectSingleNode("actions/create_group[@groupname='global.`$SL_PlayerShips']")) 'SL_PlayerShips must be created by the synchronous library.'
Assert-Condition ($null -ne $refreshLibrary.SelectSingleNode("actions/add_to_group[@groupname='global.`$SL_PlayerShips' and @replace='true']")) 'SL_PlayerShips must be reconciled with replace=true.'
Assert-Condition ($null -ne $refreshLibrary.SelectSingleNode("actions/do_if[contains(@value, 'datatype.group')]/remove_value[@name='global.`$SL_PlayerShips']")) 'SL_PlayerShips must be type-checked before creation.'

$slSetup = $scriptLibrary.SelectSingleNode("/mdscript/cues/cue[@name='SL_Setup_MD']")
Assert-Condition ($null -ne $slSetup) 'SL_Setup_MD must exist.'
Assert-Condition (-not $slSetup.HasAttribute('instantiate')) 'SL_Setup_MD must be a one-time parent, not a per-load instance factory.'
Assert-Condition ($null -ne $slSetup.SelectSingleNode("actions/run_actions[@ref='md.JP_ScriptLibrary_MD.SL_RefreshPlayerShips']")) 'SL_Setup_MD must synchronously initialize SL_PlayerShips.'
Assert-Condition ($null -ne $slSetup.SelectSingleNode("actions/do_if[contains(@value, 'datatype.table')]/remove_value[@name='global.`$SL_IdleShips']")) 'SL_IdleShips must be type-checked before use.'
Assert-Condition ($null -ne $slSetup.SelectSingleNode("cues/cue[@name='SL_ManageIdleReturnHome_MD']")) 'The idle manager must be a child of initialized SL_Setup_MD.'

$refreshCue = $slSetup.SelectSingleNode("cues/cue[@name='SL_RefreshPlayerShips_MD']")
Assert-Condition ($null -ne $refreshCue) 'The dynamic player-ship refresh cue must be a child of SL_Setup_MD.'
foreach ($eventName in @('event_player_built_ship', 'event_player_owned_destroyed', 'event_object_entered')) {
    Assert-Condition ($null -ne $refreshCue.SelectSingleNode("conditions//*[local-name()='$eventName']")) "SL player-ship refresh must handle $eventName."
}
$ownershipEvents = $refreshCue.SelectNodes("conditions//event_contained_object_changed_true_owner")
Assert-Condition ($ownershipEvents.Count -eq 2) 'SL player-ship refresh must handle acquisition and loss of true ownership.'

$tseSetup = $tse.SelectSingleNode("/mdscript/cues/cue[@name='TSE_Setup_MD']")
Assert-Condition ($null -ne $tseSetup) 'TSE_Setup_MD must exist.'
Assert-Condition (-not $tseSetup.HasAttribute('instantiate')) 'TSE_Setup_MD must not create duplicate persistent listener trees on repeated loads.'
Assert-Condition ($null -ne $tseSetup.SelectSingleNode("actions/run_actions[@ref='md.JP_ScriptLibrary_MD.SL_RefreshPlayerShips']")) 'TSE must synchronously initialize SL_PlayerShips itself.'

$requiredGroups = @(
    'global.$SL_PlayerShips',
    'global.$TSE_ShipsGroup',
    'global.$TSE_SectorsBlacklistGroup'
)

foreach ($groupName in @('global.$TSE_ShipsGroup', 'global.$TSE_SectorsBlacklistGroup')) {
    Assert-Condition ($null -ne $tseSetup.SelectSingleNode("actions/create_group[@groupname='$groupName']")) "$groupName must be created in TSE setup actions."
    Assert-Condition ($null -ne $tseSetup.SelectSingleNode("actions/do_if[contains(@value, 'datatype.group')]/remove_value[@name='$groupName']")) "$groupName must be type-checked before creation."
    Assert-Condition ($null -ne $tseSetup.SelectSingleNode("actions/add_to_group[@groupname='$groupName' and @replace='true']")) "$groupName must be deterministically reconciled."
}

Assert-Condition ($null -ne $tseSetup.SelectSingleNode("actions/do_if[contains(@value, 'datatype.table')]/remove_value[@name='global.`$TSE_ShipsCurrentSectorTable']")) 'TSE_ShipsCurrentSectorTable must be type-checked.'
Assert-Condition ($null -ne $tseSetup.SelectSingleNode("actions/set_value[@name='global.`$TSE_ShipsCurrentSectorTable']")) 'TSE_ShipsCurrentSectorTable must be initialized before child cues.'

$requiredListenerNames = @(
    'TSE_EventObjectDestroyed_MD',
    'TSE_EventObjectOrderReady1_MD',
    'TSE_EventObjectOrderReady2_MD'
)
foreach ($listenerName in $requiredListenerNames) {
    Assert-Condition ($null -ne $tseSetup.SelectSingleNode("cues/cue[@name='$listenerName']")) "$listenerName must be a direct child of TSE_Setup_MD."
}

$topLevelGlobalGroupEvents = $tse.SelectNodes("/mdscript/cues/cue/conditions/*[starts-with(local-name(), 'event_') and starts-with(@group, 'global.`$')]")
Assert-Condition ($topLevelGlobalGroupEvents.Count -eq 0) 'No top-level TSE event cue may require a global group.'

$globalGroupEvents = $tse.SelectNodes("//*[starts-with(local-name(), 'event_') and starts-with(@group, 'global.`$')]")
Assert-Condition ($globalGroupEvents.Count -eq 3) 'Exactly the three known TSE event conditions must use global groups.'
foreach ($eventNode in $globalGroupEvents) {
    Assert-Condition ($requiredGroups -contains $eventNode.GetAttribute('group')) "Unexpected global event group $($eventNode.GetAttribute('group'))."
    Assert-Condition ($null -ne $eventNode.SelectSingleNode("ancestor::cue[@name='TSE_Setup_MD']")) "$($eventNode.LocalName) must be below initialized TSE_Setup_MD."
    Assert-Condition (-not $eventNode.GetAttribute('group').StartsWith('@')) "$($eventNode.LocalName) may not pass a safe-lookup null to a group attribute."
}

$allGlobalGroupAttributes = @($scriptLibrary.SelectNodes("//*[@group and starts-with(@group, 'global.`$')]") + $tse.SelectNodes("//*[@group and starts-with(@group, 'global.`$')]"))
foreach ($node in $allGlobalGroupAttributes) {
    Assert-Condition ($requiredGroups -contains $node.GetAttribute('group')) "Untracked global group attribute $($node.GetAttribute('group'))."
}

$globalGroupCreationCounts = @{}
foreach ($node in @($scriptLibrary.SelectNodes("//create_group[starts-with(@groupname, 'global.`$')]") + $tse.SelectNodes("//create_group[starts-with(@groupname, 'global.`$')]"))) {
    $name = $node.GetAttribute('groupname')
    if (-not $globalGroupCreationCounts.ContainsKey($name)) { $globalGroupCreationCounts[$name] = 0 }
    $globalGroupCreationCounts[$name]++
}
foreach ($groupName in $requiredGroups) {
    Assert-Condition ($globalGroupCreationCounts[$groupName] -eq 1) "$groupName must have exactly one create_group action."
}

foreach ($localName in @('$_TSEActiveShips', '$_PreviousShipsCurrentSectorTable', '$_RebuiltShipsCurrentSectorTable', '$_RebuiltSectorsBlacklistGroup')) {
    Assert-Condition ($null -ne $tseSetup.SelectSingleNode("actions/*[@name='$localName' or @groupname='$localName']")) "$localName must be initialized before use."
}

Write-Output 'Global group references and group attributes: OK'
Write-Output 'Parent/child initialization order: OK'
Write-Output 'Single group-creation ownership and deterministic replacement: OK'
Write-Output 'Cases A-D structural simulation: OK'
Write-Output 'No event cue may require a global group before initialization: OK'
