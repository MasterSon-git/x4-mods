[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modsRoot = Join-Path $repoRoot 'mods'
$aiSchemaPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/libraries/aiscripts.xsd'
$escapePath = Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/aiscripts/msx4.lib.EscapeTravelBlacklist.xml'
$updatePath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.UpdateTradeData.xml'
$idlePath = Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/aiscripts/msx4.lib.IdleReturnHome.xml'
$getTargetsPath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.GetTradeDataToUpdate.xml'

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

function Assert-Param {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlElement] $Call,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [string] $Context
    )

    $matching = @($Call.SelectNodes("./param[@name='$Name' and @value='$Value']"))
    Assert-Condition ($matching.Count -eq 1) "$Context must retain exactly one $Name=$Value parameter."
}

$allXmlFiles = @(Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml')
$allXmlDocuments = @{}
foreach ($file in $allXmlFiles) {
    $allXmlDocuments[$file.FullName] = Read-XmlDocument -Path $file.FullName
}
Write-Output "XML well-formedness: OK ($($allXmlFiles.Count) mod XML files)"

$escape = $allXmlDocuments[$escapePath]
$update = $allXmlDocuments[$updatePath]
$idle = $allXmlDocuments[$idlePath]
$getTargets = $allXmlDocuments[$getTargetsPath]

$escapeMoves = @($escape.SelectNodes("//run_script[@name=`"'move.generic'`" and param[@name='destination' and @value='`$_EscapeSector']]"))
Assert-Condition ($escapeMoves.Count -eq 1) 'Escape must retain exactly one move.generic call with destination=$_EscapeSector.'
$escapeMove = [System.Xml.XmlElement] $escapeMoves[0]
Assert-Param -Call $escapeMove -Name 'destination' -Value '$_EscapeSector' -Context 'Escape move'
Assert-Param -Call $escapeMove -Name 'strictblacklist' -Value 'false' -Context 'Escape move'
Assert-Param -Call $escapeMove -Name 'useknownpath' -Value '$MSX4_USE_KNOWN_PATH' -Context 'Escape move'
Assert-Param -Call $escapeMove -Name 'recallsubordinates' -Value 'false' -Context 'Escape move'
Assert-Condition ($null -eq $escapeMove.SelectSingleNode("./param[@name='endintargetdector']")) 'Escape direct-Sector move must not set endintargetdector.'
Assert-Condition ($null -eq $escapeMove.SelectSingleNode("./param[@name='position']")) 'Escape must not introduce an artificial target position.'
$relaxedMoveCalls = @(
    foreach ($document in $allXmlDocuments.Values) {
        $document.SelectNodes("//run_script[@name=`"'move.generic'`" and param[@name='strictblacklist' and @value='false']]")
    }
)
Assert-Condition ($relaxedMoveCalls.Count -eq 1) 'Exactly one mod move.generic call may set strictblacklist=false.'
Assert-Condition ($null -ne $relaxedMoveCalls[0].SelectSingleNode("./param[@name='destination' and @value='`$_EscapeSector']")) 'The sole explicitly relaxed move.generic call must be the Escape move.'

$updateMoves = @($update.SelectNodes("//run_script[@name=`"'move.generic'`" and param[@name='destination' and @value='`$_Station.sector']]"))
Assert-Condition ($updateMoves.Count -eq 1) 'UpdateSubscription must retain exactly one move.generic call with destination=$_Station.sector.'
$updateMove = [System.Xml.XmlElement] $updateMoves[0]
Assert-Condition ($null -eq $updateMove.SelectSingleNode("./param[@name='endintargetdector']")) 'The normal TDE direct-Sector move must not set endintargetdector.'
Assert-Param -Call $updateMove -Name 'strictblacklist' -Value 'true' -Context 'Normal TDE move'
Assert-Param -Call $updateMove -Name 'useknownpath' -Value 'true' -Context 'Normal TDE move'
Assert-Param -Call $updateMove -Name 'recallsubordinates' -Value 'false' -Context 'Normal TDE move'
Assert-Condition ($null -eq $updateMove.SelectSingleNode("./param[@name='position']")) 'The normal TDE direct-Sector move must remain positionless.'

$idleMoves = @($idle.SelectNodes("//run_script[@name=`"'move.generic'`" and param[@name='destination' and @value='`$WHERE_TO_MOVE.{1}'] and param[@name='position' and @value='`$WHERE_TO_MOVE.{2}']]"))
Assert-Condition ($idleMoves.Count -eq 1) 'Idle Move must retain exactly one reviewed Sector-plus-position move.generic call.'
$idleMove = [System.Xml.XmlElement] $idleMoves[0]
Assert-Param -Call $idleMove -Name 'strictblacklist' -Value 'true' -Context 'Idle move'
Assert-Param -Call $idleMove -Name 'useknownpath' -Value '$MSX4_USE_KNOWN_PATH' -Context 'Idle move'
Assert-Param -Call $idleMove -Name 'recallsubordinates' -Value 'false' -Context 'Idle move'
Assert-Condition ($null -eq $idleMove.SelectSingleNode("./param[@name='endintargetdector']")) 'Idle Sector-plus-position move must remain free of endintargetdector.'

$initialEscapeGuard = $escape.SelectSingleNode("//do_if[@value='not `$_Ship.sector.isblacklisted.{blacklisttype.sectortravel}.{`$blacklistgroup}.{`$_Ship}']/return[@value=`"'not_required'`"]")
Assert-Condition ($null -ne $initialEscapeGuard) 'A ship outside a travel-blocked sector must still return not_required without escaping.'

$allowedSectorSearch = $escape.SelectSingleNode("//find_sector[@name='`$_AllowedSectors']/match_use_blacklist[@object='`$_Ship' and @type='blacklisttype.sectortravel' and @group='`$blacklistgroup']")
Assert-Condition ($null -ne $allowedSectorSearch) 'Escape destinations must still be selected through the effective Sector Travel blacklist.'
$allowedSectorRecheck = $escape.SelectSingleNode("//do_for_each[@name='`$_EscapeSector']/do_if[@value='`$_EscapeSector.isblacklisted.{blacklisttype.sectortravel}.{`$blacklistgroup}.{`$_Ship}']/continue")
Assert-Condition ($null -ne $allowedSectorRecheck) 'Every selected escape destination must still be rechecked as travel-allowed before movement.'

$postMoveBlacklistRefresh = $escapeMove.SelectSingleNode("following-sibling::include_interrupt_actions[1][@ref='GetBlacklistgroup']")
Assert-Condition ($null -ne $postMoveBlacklistRefresh) 'Escape must refresh the effective blacklist group after movement.'
$postMoveSectorCheck = $escapeMove.SelectSingleNode("following-sibling::do_if[1][@value='not `$_Ship.sector.isblacklisted.{blacklisttype.sectortravel}.{`$blacklistgroup}.{`$_Ship}']/return[@value=`"'success'`"]")
Assert-Condition ($null -ne $postMoveSectorCheck) 'Escape success must still be based on the actually reached ship sector being travel-allowed.'

$escapeRouteChecks = @($escape.SelectNodes('//get_global_path | //get_jump_path'))
Assert-Condition ($escapeRouteChecks.Count -eq 2) 'Escape must retain its reviewed global-path and jump-path checks.'
foreach ($pathCheck in $escapeRouteChecks) {
    Assert-Condition (-not $pathCheck.HasAttribute('useblacklist')) 'Only the escape route check may deliberately omit useblacklist.'
    Assert-Condition ($pathCheck.GetAttribute('useknownpath') -eq '$MSX4_USE_KNOWN_PATH') 'Escape route checks must retain useknownpath.'
    Assert-Condition ($pathCheck.SelectSingleNode("./end[@object='`$_AllowedSector']") -ne $null) 'Escape route checks must still target only a previously allowed sector.'
}

foreach ($normalDocument in @($getTargets, $update, $idle)) {
    foreach ($pathCheck in @($normalDocument.SelectNodes('//get_global_path'))) {
        Assert-Condition ($pathCheck.GetAttribute('useblacklist') -eq '$blacklistgroup') 'Every reviewed normal TDE/Idle global path must retain the effective blacklist.'
    }
}

Assert-Condition ($null -ne $escape.SelectSingleNode("//sort_list[@list='`$_SameJumpCount' and @sortbyvalue='loop.element.{2}']")) 'Escape targets must retain global-path-distance sorting within equal jump counts.'
Assert-Condition ($null -ne $escape.SelectSingleNode("//do_if[@value='`$_EscapePathDistance ge 0 and `$_EscapeJumpPath.count ge 2']")) 'Escape candidates must retain known physical path validation.'
foreach ($status in @('not_required', 'success', 'move_failed', 'no_valid_path')) {
    Assert-Condition ($null -ne $escape.SelectSingleNode("//return[@value=`"'$status'`"]")) "Escape must retain status '$status'."
}

$completeAiFiles = @(
    foreach ($entry in $allXmlDocuments.GetEnumerator()) {
        if ($entry.Value.DocumentElement.LocalName -eq 'aiscript') {
            $entry.Key
        }
    }
)
$jshell = Get-Command 'jshell' -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $jshell) 'jshell is required for validation against the recursive Vanilla AI schema.'

$validationStatements = ($completeAiFiles | Sort-Object | ForEach-Object {
    $javaPath = ConvertTo-JavaPath -Path $_
    "  validator.validate(new StreamSource(new File(`"$javaPath`")));"
}) -join [Environment]::NewLine
$javaValidation = @"
import javax.xml.XMLConstants;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.SchemaFactory;
import java.io.File;
try {
  var factory = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
  var schema = factory.newSchema(new File("$(ConvertTo-JavaPath -Path $aiSchemaPath)"));
  var validator = schema.newValidator();
$validationStatements
  System.out.println("AI XSD validation: OK ($($completeAiFiles.Count) complete mod AI files)");
} catch (Exception exception) {
  exception.printStackTrace();
  System.exit(1);
}
/exit
"@

$javaOutput = $javaValidation | & $jshell.Source --feedback silent 2>&1
if ($LASTEXITCODE -ne 0) {
    $javaOutput | ForEach-Object { Write-Error $_ }
    throw 'AI XSD validation failed.'
}
Write-Output "AI XSD validation: OK ($($completeAiFiles.Count) complete mod AI files)"
Write-Output 'Escape direct-Sector move contract: OK'
Write-Output 'Normal TDE direct-Sector move contract: OK'
Write-Output 'Idle Sector-plus-position move contract: OK'
Write-Output 'Escape actual-sector postcondition and status contract: OK'
Write-Output 'Escape-only blacklist relaxation and allowed-target contract: OK'
