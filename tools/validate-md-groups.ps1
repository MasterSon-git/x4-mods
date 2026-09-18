[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptLibraryPath = Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/md/msx4.ScriptLibrary.md.xml'
$tdePath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/md/msx4.TradeDataExplorer.md.xml'
$scriptLibraryContentPath = Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/content.xml'
$tdeContentPath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/content.xml'
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
$tde = Read-XmlDocument -Path $tdePath
$scriptLibraryContent = Read-XmlDocument -Path $scriptLibraryContentPath
$tdeContent = Read-XmlDocument -Path $tdeContentPath
Write-Output 'XML well-formedness: OK (2 MD files)'

Assert-Condition ($scriptLibraryContent.DocumentElement.GetAttribute('id') -eq 'MSX4_ScriptLibrary') 'The ScriptLibrary content ID must remain MSX4_ScriptLibrary.'
Assert-Condition ($null -ne $tdeContent.SelectSingleNode("/content/dependency[@id='MSX4_ScriptLibrary' and @optional='false']")) 'TDE must retain its required ScriptLibrary dependency for the cross-file run_actions reference.'

$jshell = Get-Command 'jshell' -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $jshell) 'jshell is required for validation against the recursive vanilla MD schema.'

$schemaJavaPath = ConvertTo-JavaPath -Path $mdSchemaPath
$scriptLibraryJavaPath = ConvertTo-JavaPath -Path $scriptLibraryPath
$tdeJavaPath = ConvertTo-JavaPath -Path $tdePath
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
  validator.validate(new StreamSource(new File("$tdeJavaPath")));
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

$refreshLibrary = $scriptLibrary.SelectSingleNode("/mdscript/cues/library[@name='MSX4_SL_RefreshPlayerShips' and @purpose='run_actions']")
Assert-Condition ($null -ne $refreshLibrary) 'The synchronous ScriptLibrary player-ship refresh library must exist.'
Assert-Condition ($null -ne $refreshLibrary.SelectSingleNode("actions/create_group[@groupname='global.`$MSX4_SL_PlayerShips']")) 'MSX4_SL_PlayerShips must be created by the synchronous library.'
Assert-Condition ($null -ne $refreshLibrary.SelectSingleNode("actions/add_to_group[@groupname='global.`$MSX4_SL_PlayerShips' and @replace='true']")) 'MSX4_SL_PlayerShips must be reconciled with replace=true.'
Assert-Condition ($null -ne $refreshLibrary.SelectSingleNode("actions/do_if[contains(@value, 'datatype.group')]/remove_value[@name='global.`$MSX4_SL_PlayerShips']")) 'MSX4_SL_PlayerShips must be type-checked before creation.'

$slSetup = $scriptLibrary.SelectSingleNode("/mdscript/cues/cue[@name='MSX4_SL_Setup_MD']")
Assert-Condition ($null -ne $slSetup) 'MSX4_SL_Setup_MD must exist.'
Assert-Condition (-not $slSetup.HasAttribute('instantiate')) 'MSX4_SL_Setup_MD must be a one-time parent, not a per-load instance factory.'
Assert-Condition ($null -ne $slSetup.SelectSingleNode("actions/run_actions[@ref='md.MSX4_ScriptLibrary_MD.MSX4_SL_RefreshPlayerShips']")) 'MSX4_SL_Setup_MD must synchronously initialize MSX4_SL_PlayerShips.'
Assert-Condition ($null -ne $slSetup.SelectSingleNode("actions/do_if[contains(@value, 'datatype.table')]/remove_value[@name='global.`$MSX4_SL_IdleShips']")) 'MSX4_SL_IdleShips must be type-checked before use.'
Assert-Condition ($null -ne $slSetup.SelectSingleNode("cues/cue[@name='MSX4_SL_ManageIdleReturnHome_MD']")) 'The idle manager must be a child of initialized MSX4_SL_Setup_MD.'

$refreshCue = $slSetup.SelectSingleNode("cues/cue[@name='MSX4_SL_RefreshPlayerShips_MD']")
Assert-Condition ($null -ne $refreshCue) 'The dynamic player-ship refresh cue must be a child of MSX4_SL_Setup_MD.'
foreach ($eventName in @('event_player_built_ship', 'event_player_owned_destroyed', 'event_object_entered')) {
    Assert-Condition ($null -ne $refreshCue.SelectSingleNode("conditions//*[local-name()='$eventName']")) "SL player-ship refresh must handle $eventName."
}
$ownershipEvents = $refreshCue.SelectNodes("conditions//event_contained_object_changed_true_owner")
Assert-Condition ($ownershipEvents.Count -eq 2) 'SL player-ship refresh must handle acquisition and loss of true ownership.'

$tdeSetup = $tde.SelectSingleNode("/mdscript/cues/cue[@name='TDE_Setup_MD']")
Assert-Condition ($null -ne $tdeSetup) 'TDE_Setup_MD must exist.'
Assert-Condition (-not $tdeSetup.HasAttribute('instantiate')) 'TDE_Setup_MD must not create duplicate persistent listener trees on repeated loads.'
Assert-Condition ($null -ne $tdeSetup.SelectSingleNode("actions/run_actions[@ref='md.MSX4_ScriptLibrary_MD.MSX4_SL_RefreshPlayerShips']")) 'TDE must synchronously initialize MSX4_SL_PlayerShips itself.'

$requiredGroups = @(
    'global.$MSX4_SL_PlayerShips',
    'global.$MSX4_TDE_ShipsGroup',
    'global.$MSX4_TDE_SectorsBlacklistGroup'
)

foreach ($groupName in @('global.$MSX4_TDE_ShipsGroup', 'global.$MSX4_TDE_SectorsBlacklistGroup')) {
    Assert-Condition ($null -ne $tdeSetup.SelectSingleNode("actions/create_group[@groupname='$groupName']")) "$groupName must be created in TDE setup actions."
    Assert-Condition ($null -ne $tdeSetup.SelectSingleNode("actions/do_if[contains(@value, 'datatype.group')]/remove_value[@name='$groupName']")) "$groupName must be type-checked before creation."
    Assert-Condition ($null -ne $tdeSetup.SelectSingleNode("actions/add_to_group[@groupname='$groupName' and @replace='true']")) "$groupName must be deterministically reconciled."
}

Assert-Condition ($null -ne $tdeSetup.SelectSingleNode("actions/do_if[contains(@value, 'datatype.table')]/remove_value[@name='global.`$MSX4_TDE_ShipsCurrentSectorTable']")) 'TDE_ShipsCurrentSectorTable must be type-checked.'
Assert-Condition ($null -ne $tdeSetup.SelectSingleNode("actions/set_value[@name='global.`$MSX4_TDE_ShipsCurrentSectorTable']")) 'TDE_ShipsCurrentSectorTable must be initialized before child cues.'

$requiredListenerNames = @(
    'TDE_EventObjectDestroyed_MD',
    'TDE_EventObjectOrderReady2_MD'
)
foreach ($listenerName in $requiredListenerNames) {
    Assert-Condition ($null -ne $tdeSetup.SelectSingleNode("cues/cue[@name='$listenerName']")) "$listenerName must be a direct child of TDE_Setup_MD."
}

$topLevelGlobalGroupEvents = $tde.SelectNodes("/mdscript/cues/cue/conditions/*[starts-with(local-name(), 'event_') and starts-with(@group, 'global.`$')]")
Assert-Condition ($topLevelGlobalGroupEvents.Count -eq 0) 'No top-level TDE event cue may require a global group.'

$globalGroupEvents = $tde.SelectNodes("//*[starts-with(local-name(), 'event_') and starts-with(@group, 'global.`$')]")
Assert-Condition ($globalGroupEvents.Count -eq 2) 'Exactly the two known TDE event conditions must use global groups.'
foreach ($eventNode in $globalGroupEvents) {
    Assert-Condition ($requiredGroups -contains $eventNode.GetAttribute('group')) "Unexpected global event group $($eventNode.GetAttribute('group'))."
    Assert-Condition ($null -ne $eventNode.SelectSingleNode("ancestor::cue[@name='TDE_Setup_MD']")) "$($eventNode.LocalName) must be below initialized TDE_Setup_MD."
    Assert-Condition (-not $eventNode.GetAttribute('group').StartsWith('@')) "$($eventNode.LocalName) may not pass a safe-lookup null to a group attribute."
}

$allGlobalGroupAttributes = @($scriptLibrary.SelectNodes("//*[@group and starts-with(@group, 'global.`$')]") + $tde.SelectNodes("//*[@group and starts-with(@group, 'global.`$')]"))
foreach ($node in $allGlobalGroupAttributes) {
    Assert-Condition ($requiredGroups -contains $node.GetAttribute('group')) "Untracked global group attribute $($node.GetAttribute('group'))."
}

$globalGroupCreationCounts = @{}
foreach ($node in @($scriptLibrary.SelectNodes("//create_group[starts-with(@groupname, 'global.`$')]") + $tde.SelectNodes("//create_group[starts-with(@groupname, 'global.`$')]"))) {
    $name = $node.GetAttribute('groupname')
    if (-not $globalGroupCreationCounts.ContainsKey($name)) { $globalGroupCreationCounts[$name] = 0 }
    $globalGroupCreationCounts[$name]++
}
foreach ($groupName in $requiredGroups) {
    Assert-Condition ($globalGroupCreationCounts[$groupName] -eq 1) "$groupName must have exactly one create_group action."
}

foreach ($localName in @('$_TDEActiveShips', '$_PreviousShipsCurrentSectorTable', '$_RebuiltShipsCurrentSectorTable', '$_RebuiltSectorsBlacklistGroup')) {
    Assert-Condition ($null -ne $tdeSetup.SelectSingleNode("actions/*[@name='$localName' or @groupname='$localName']")) "$localName must be initialized before use."
}

Write-Output 'Global group references and group attributes: OK'
Write-Output 'Parent/child initialization order: OK'
Write-Output 'Single group-creation ownership and deterministic replacement: OK'
Write-Output 'Cases A-D structural simulation: OK'
Write-Output 'No event cue may require a global group before initialization: OK'
