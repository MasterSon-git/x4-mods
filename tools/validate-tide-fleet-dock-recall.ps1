[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

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

function ConvertTo-JavaPath {
    param([string] $Path)

    return [System.IO.Path]::GetFullPath($Path).Replace('\', '/').Replace('"', '\"')
}

$diffPath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/order.dock.xml'
$existingWaitDiffPath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/order.dock.wait.xml'
$vanillaDockPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/aiscripts/order.dock.xml'
$vanillaFleeDockPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/aiscripts/move.flee.dock.xml'
$aiSchemaPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/libraries/aiscripts.xsd'

$diff = Read-XmlDocument $diffPath
$existingWaitDiff = Read-XmlDocument $existingWaitDiffPath
$vanillaDock = Read-XmlDocument $vanillaDockPath
$vanillaFleeDock = Read-XmlDocument $vanillaFleeDockPath

$add = $diff.SelectSingleNode("/diff/add[@sel='/aiscript/init']")
$vanillaInit = @($vanillaDock.SelectNodes('/aiscript/init'))
Assert-Condition ($null -ne $add -and $vanillaInit.Count -eq 1) 'the additive diff selector resolves to exactly one Vanilla order.dock init node'

$guard = $add.SelectSingleNode("do_if")
$expectedGuard = "`$dockfollowers and @this.ship.defaultorder.id == 'MSX4_TradeDataExplorerG' and this.ship.subordinates.count gt 0"
Assert-Condition ($guard.GetAttribute('value') -ceq $expectedGuard) 'the override is restricted to active dockfollowers on a TDE-G commander with subordinates'
Assert-Condition ($null -ne $guard.SelectSingleNode("set_value[@name='`$dockfollowers' and @exact='false']")) 'the guarded change only disables follower docking'
Assert-Condition ($null -ne $guard.SelectSingleNode("do_if[@value='@this.ship.defaultorder.`$DEBUG gt 0']/debug_to_file[contains(@text, 'event=dockfollowers_override')]")) 'the override has guarded runtime diagnostics'

$waitGuard = $existingWaitDiff.SelectSingleNode("/diff/add/do_if[contains(@value, `"@this.ship.defaultorder.id == 'MSX4_TradeDataExplorerG'`")]/set_value[@name='`$dockfollowers' and @exact='false']")
Assert-Condition ($null -ne $waitGuard) 'the existing DockAndWait protection remains in place'

$fleeCall = $vanillaFleeDock.SelectSingleNode("//run_script[@name=`"'order.dock'`"]/param[@name='dockfollowers' and @value='@`$attacker.isclass.celestialbody']")
$fleeRecallSetting = $vanillaFleeDock.SelectSingleNode("//run_script[@name=`"'order.dock'`"]/param[@name='recallsubordinates' and @value='false']")
$vanillaFollowerOrder = $vanillaDock.SelectSingleNode("//do_if[@value='`$dockfollowers and not `$subordinateorders.count']//create_order[@id=`"'DockAndWait'`"][@object='`$subordinates.{`$i}']/param[@name='isdockfollower' and @value='true']")
Assert-Condition ($null -ne $fleeCall -and $null -ne $fleeRecallSetting -and $null -ne $vanillaFollowerOrder) 'Vanilla Tide docking independently enables dockfollowers and creates subordinate DockAndWait orders'

$applied = [System.Xml.XmlDocument] $vanillaDock.CloneNode($true)
$target = $applied.SelectSingleNode('/aiscript/init')
$elementCountBefore = @($target.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)).Count
foreach ($child in @($add.ChildNodes)) {
    [void] $target.AppendChild($applied.ImportNode($child, $true))
}
$elementCountAfter = @($target.ChildNodes | Where-Object NodeType -eq ([System.Xml.XmlNodeType]::Element)).Count
$appliedGuard = $applied.SelectSingleNode("/aiscript/init/do_if[@value=`"$expectedGuard`"]")
Assert-Condition ($elementCountAfter -eq ($elementCountBefore + 1) -and $null -ne $appliedGuard) 'simulated diff application adds exactly one functional initialization guard'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tde-tide-dock-validation-' + [guid]::NewGuid().ToString('N'))
[void] (New-Item -ItemType Directory -Path $tempRoot)
try {
    $appliedPath = Join-Path $tempRoot 'order.dock.applied.xml'
    $applied.Save($appliedPath)

    $jshell = Get-Command jshell -ErrorAction SilentlyContinue
    Assert-Condition ($null -ne $jshell) 'jshell is available for recursive Vanilla XSD validation'
    $java = @"
import javax.xml.XMLConstants;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.SchemaFactory;
import java.io.File;
try {
  var factory = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
  var schema = factory.newSchema(new File("$(ConvertTo-JavaPath $aiSchemaPath)"));
  var validator = schema.newValidator();
  validator.validate(new StreamSource(new File("$(ConvertTo-JavaPath $appliedPath)")));
  System.out.println("XSD validation complete");
} catch (Exception exception) {
  exception.printStackTrace();
  System.exit(1);
}
/exit
"@
    $javaOutput = $java | & $jshell.Source --feedback silent 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (($javaOutput -join "`n").Contains('XSD validation complete'))) {
        throw "AI-XSD validation failed:`n$($javaOutput -join [Environment]::NewLine)"
    }
    Write-Host 'PASS: simulated order.dock with the TDE guard validates against the Vanilla 9.00 AI schema'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

& git -c core.autocrlf=false -C $repoRoot diff --check
Assert-Condition ($LASTEXITCODE -eq 0) 'git diff --check passes'

Write-Host 'TDE Tide fleet dock-recall regression: PASS'
