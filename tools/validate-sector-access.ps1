[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modsRoot = Join-Path $repoRoot 'mods'
$aiSchemaPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/libraries/aiscripts.xsd'
$getTargetsPath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/aiscripts/jp.lib.TSE.GetTradesubscriptionsToUpdate.xml'
$updateTargetPath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/aiscripts/jp.lib.TSE.UpdateSubscription.xml'
$idlePath = Join-Path $repoRoot 'mods/JP_ScriptLibrary/aiscripts/jp.lib.IdleReturnHome.xml'
$galaxyOrderPath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerG.xml'
$sectorOrderPath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerS.xml'

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

$allXmlFiles = @(Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml')
foreach ($file in $allXmlFiles) {
    [void](Read-XmlDocument -Path $file.FullName)
}
Write-Output "XML well-formedness: OK ($($allXmlFiles.Count) mod XML files)"

$getTargets = Read-XmlDocument -Path $getTargetsPath
$updateTarget = Read-XmlDocument -Path $updateTargetPath
$idle = Read-XmlDocument -Path $idlePath

$documents = @($getTargets, $updateTarget, $idle)
$allFindSectorNodes = @($documents | ForEach-Object { $_.SelectNodes("//find_sector[not(contains(@name, 'Trace'))]") })
Assert-Condition ($allFindSectorNodes.Count -eq 7) 'The three affected scripts must retain exactly their seven reviewed find_sector actions.'
foreach ($node in $allFindSectorNodes) {
    Assert-Condition ($node.GetAttribute('space') -eq 'player.galaxy') "find_sector '$($node.GetAttribute('name'))' must use player.galaxy as its containing search space."
}

$expectedAccessChecks = @(
    @{ Document = $getTargets; Name = '$_AccessibleSector'; Macro = '$_Sector.macro'; Count = 1 },
    @{ Document = $updateTarget; Name = '$_AccessibleTargetSector'; Macro = '$_Station.sector.macro'; Count = 1 },
    @{ Document = $idle; Name = '$_AccessibleIdleMoveSector'; Macro = '$WHERE_TO_MOVE.{1}.macro'; Count = 1 },
    @{ Document = $idle; Name = '$_AccessibleIdleFollowSector'; Macro = '$WHO_TO_FOLLOW.sector.macro'; Count = 1 },
    @{ Document = $idle; Name = '$_AccessibleIdleDockSector'; Macro = '$WHERE_TO_DOCK.sector.macro'; Count = 1 },
    @{ Document = $idle; Name = '$_AccessibleIdleDockSector'; Macro = '$_FoundStation.sector.macro'; Count = 1 }
)

foreach ($check in $expectedAccessChecks) {
    $matching = @($check.Document.SelectNodes("//find_sector[@name='$($check.Name)' and @space='player.galaxy' and @macro='$($check.Macro)' and @accessgrantedto='`$_Ship.owner']"))
    Assert-Condition ($matching.Count -eq $check.Count) "Expected exact access check $($check.Name) with macro $($check.Macro)."
}

$accessChecks = @($documents | ForEach-Object { $_.SelectNodes("//find_sector[starts-with(@name, '`$_Accessible')]") })
Assert-Condition ($accessChecks.Count -eq 6) 'Exactly six reviewed exact-sector access checks must exist.'
foreach ($node in $accessChecks) {
    Assert-Condition ($node.HasAttribute('macro')) "Access check '$($node.GetAttribute('name'))' must retain an exact sector macro filter."
    Assert-Condition ($node.GetAttribute('accessgrantedto') -eq '$_Ship.owner') "Access check '$($node.GetAttribute('name'))' must retain the ship-owner access filter."
}

Assert-Condition ($null -ne $getTargets.SelectSingleNode("//do_if[@value='`$_AccessibleSector != `$_Sector']")) 'Candidate selection must reject a sector not returned by its exact access check.'
Assert-Condition ($null -ne $updateTarget.SelectSingleNode("//do_if[@value='`$_AccessibleTargetSector != `$_Station.sector']")) 'Target validation must reject a sector not returned by its exact access check.'
foreach ($comparison in @(
    '$_AccessibleIdleMoveSector == $WHERE_TO_MOVE.{1}',
    '$_AccessibleIdleFollowSector == $WHO_TO_FOLLOW.sector',
    '$_AccessibleIdleDockSector == $WHERE_TO_DOCK.sector',
    '$_AccessibleIdleDockSector == $_FoundStation.sector'
)) {
    Assert-Condition ($null -ne $idle.SelectSingleNode("//do_if[contains(@value, '$comparison')]")) "Idle access result must still be compared with its intended target: $comparison."
}

Assert-Condition ($null -ne $getTargets.SelectSingleNode("//find_sector[@name='`$_Sectors' and @space='player.galaxy' and @multiple='true' and @accessgrantedto='`$_Ship.owner']/match[@knownto='`$_Ship.owner']")) 'The known-sector galaxy search and its access filter must remain intact.'
Assert-Condition ($null -ne $getTargets.SelectSingleNode("//find_object[@name='`$_Stations']/match[@tradesknownto='`$_Ship.owner' and @negate='true']")) 'The expired-trade-information station filter must remain intact.'

$interSectorMove = $updateTarget.SelectSingleNode("//run_script[contains(@name, 'move.generic') and param[@name='destination' and @value='`$_Station.sector']]")
Assert-Condition ($null -ne $interSectorMove) 'TSE must retain the reviewed Vanilla move.generic call to the target sector.'
Assert-Condition ($null -eq $interSectorMove.SelectSingleNode("./param[@name='endintargetsector']")) 'A sector destination must not also set endintargetsector; Vanilla 9.00 otherwise reports immediate success outside the target sector.'
Assert-Condition ($null -ne $interSectorMove.SelectSingleNode("./param[@name='strictblacklist' and @value='true']")) 'The inter-sector move must remain strict-blacklist aware.'
Assert-Condition ($null -ne $interSectorMove.SelectSingleNode("./param[@name='useknownpath' and @value='true']")) 'The inter-sector move must remain restricted to a known path.'

foreach ($orderPath in @($galaxyOrderPath, $sectorOrderPath)) {
    $orderDocument = Read-XmlDocument -Path $orderPath
    $debugParam = $orderDocument.SelectSingleNode("/aiscript/order/params/param[@name='DEBUG']")
    Assert-Condition ($null -ne $debugParam) "The existing TSE DEBUG parameter must remain present in $orderPath."
    Assert-Condition ($debugParam.GetAttribute('advanced') -eq 'true') "The TSE DEBUG parameter must remain an advanced-only parameter in $orderPath."
}

$jshell = Get-Command 'jshell' -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $jshell) 'jshell is required for validation against the recursive vanilla AI schema.'

$schemaJavaPath = ConvertTo-JavaPath -Path $aiSchemaPath
$javaFilePaths = @($getTargetsPath, $updateTargetPath, $idlePath) | ForEach-Object { ConvertTo-JavaPath -Path $_ }
$validationStatements = ($javaFilePaths | ForEach-Object { "  validator.validate(new StreamSource(new File(`"$_`")));" }) -join [Environment]::NewLine
$javaValidation = @"
import javax.xml.XMLConstants;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.SchemaFactory;
import java.io.File;
try {
  var factory = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
  var schema = factory.newSchema(new File("$schemaJavaPath"));
  var validator = schema.newValidator();
$validationStatements
  System.out.println("AI XSD validation: OK (3 AI files)");
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
Write-Output 'AI XSD validation: OK (3 AI files)'
Write-Output 'find_sector containing-space invariants: OK'
Write-Output 'Exact target-sector access filters and identity comparisons: OK (6 checks)'
Write-Output 'Known-sector and expired-trade-information filters: OK'
Write-Output 'Sector-destination move.generic parameters: OK'
Write-Output 'TSE debug parameters remain advanced-only: OK'
