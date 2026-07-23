[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modsRoot = Join-Path $repoRoot 'mods'
$baselineCommit = 'f7f70dec53eaf01a11fe2979080e0e470a4a5b06'
$aiSchemaPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/libraries/aiscripts.xsd'
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

function Test-DebugGuard {
    param([Parameter(Mandatory)] [System.Xml.XmlNode] $Node)

    $ancestor = $Node.ParentNode
    while ($null -ne $ancestor) {
        if ($ancestor.NodeType -eq [System.Xml.XmlNodeType]::Element -and
            $ancestor.LocalName -in @('do_if', 'do_elseif') -and
            $ancestor.GetAttribute('value') -match '(?:\$DEBUG|TSETraceDebug|\.?\$DEBUG).*gt 0') {
            return $true
        }
        $ancestor = $ancestor.ParentNode
    }
    return $false
}

function Get-GitContent {
    param(
        [Parameter(Mandatory)] [string] $Revision,
        [Parameter(Mandatory)] [string] $Path
    )

    $content = & git -C $repoRoot show "${Revision}:$Path" 2>$null
    Assert-Condition ($LASTEXITCODE -eq 0) "Could not read $Path at $Revision."
    return ($content -join [Environment]::NewLine)
}

function Get-ContractSignature {
    param([Parameter(Mandatory)] [System.Xml.XmlDocument] $Document)

    $parts = [System.Collections.Generic.List[string]]::new()
    $contractNodes = $Document.SelectNodes(
        "//*[self::label or self::return or self::wait or self::resume or self::run_script or " +
        "self::create_order or self::set_order_failed or self::set_order_syncpoint_reached or " +
        "self::cancel_all_orders or self::cancel_order]"
    )
    foreach ($node in $contractNodes) {
        $attributes = @(
            foreach ($attribute in $node.Attributes) {
                "$($attribute.Name)=$($attribute.Value -replace '\s+', ' ')"
            }
        ) -join ';'
        $parts.Add("$($node.LocalName)|$attributes")
    }
    return $parts
}

$xmlFiles = @(Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml')
$documents = @{}
foreach ($file in $xmlFiles) {
    $documents[$file.FullName] = Read-XmlDocument -Path $file.FullName
}
Write-Output "1/20 XML well-formedness: OK ($($xmlFiles.Count) mod XML files)"

$traceNodes = @(
    foreach ($entry in $documents.GetEnumerator()) {
        foreach ($node in $entry.Value.SelectNodes("//*[@text and contains(@text, '[TSE-TRACE]')]")) {
            [pscustomobject]@{ Path = $entry.Key; Node = $node }
        }
    }
)
Assert-Condition ($traceNodes.Count -gt 0) 'At least one structured TSE trace must exist.'

foreach ($trace in $traceNodes) {
    $text = $trace.Node.GetAttribute('text')
    Assert-Condition ($text -match "^'\[TSE-TRACE\] ") "$($trace.Path) has a trace without the required prefix."
    Assert-Condition ($text -notmatch '(\\n|\\r|[\r\n])') "$($trace.Path) has a multiline trace."
    Assert-Condition ($text -cmatch '^[\x00-\x7F]+$') "$($trace.Path) has a non-ASCII trace template."
    foreach ($key in @('source=', 'ship=', 'phase=')) {
        Assert-Condition ($text.Contains($key)) "$($trace.Path) has a trace without mandatory key $key."
    }
    foreach ($field in @('result', 'reason')) {
        if ($text -match "(?:^| )${field}=([A-Za-z][A-Za-z0-9_-]*)") {
            Assert-Condition ($Matches[1] -cmatch '^[a-z0-9_]+$') "$($trace.Path) has a non-snake_case fixed $field value '$($Matches[1])'."
        }
    }

    if ($trace.Path -match '[\\/]aiscripts[\\/]') {
        Assert-Condition (Test-DebugGuard -Node $trace.Node) "$($trace.Path) contains an AI trace outside an effective DEBUG > 0 guard."
    }
    elseif ($trace.Path -match '[\\/]md[\\/]') {
        Assert-Condition ($trace.Node.LocalName -eq 'debug_text') "$($trace.Path) must use debug_text for MD lifecycle traces."
        Assert-Condition ($trace.Node.GetAttribute('filter') -eq 'scripts') "$($trace.Path) has an MD trace without filter=scripts."
        Assert-Condition ($null -eq $trace.Node.SelectSingleNode("ancestor::cue[@checkinterval]")) "$($trace.Path) has an MD trace in a polling cue."
    }
}
Write-Output "2-8/20 trace prefix, line shape, ASCII, mandatory keys, AI guards and MD lifecycle placement: OK ($($traceNodes.Count) trace points)"

$diagnosticFinders = @(
    foreach ($entry in $documents.GetEnumerator()) {
        if ($entry.Key -match '[\\/]aiscripts[\\/]') {
            $entry.Value.SelectNodes("//*[self::find_sector or self::find_object or self::find_station or self::find_ship][contains(@name, 'Trace')]")
        }
    }
)
foreach ($finder in $diagnosticFinders) {
    Assert-Condition (Test-DebugGuard -Node $finder) 'A diagnostic finder is outside an effective DEBUG > 0 guard.'
}

$diagnosticCounters = @(
    foreach ($entry in $documents.GetEnumerator()) {
        if ($entry.Key -match '[\\/]aiscripts[\\/]') {
            $entry.Value.SelectNodes("//set_value[(contains(@name, 'Trace') or @name='`$_ValidationReason') and not(contains(@name, 'TSETraceDebug')) and not(contains(@name, 'TSEDefaultOrderParamRef'))]")
        }
    }
)
foreach ($counter in $diagnosticCounters) {
    Assert-Condition (Test-DebugGuard -Node $counter) 'An AI diagnostic variable or counter is evaluated outside an effective DEBUG > 0 guard.'
}
Write-Output "9/20 DEBUG=0 diagnostic finder/counter isolation: OK ($($diagnosticFinders.Count) finders)"

$globalTraceState = @(
    foreach ($entry in $documents.GetEnumerator()) {
        $entry.Value.SelectNodes("//*[@name or @groupname][contains(@name, 'global.$') or contains(@groupname, 'global.$')][contains(@name, 'Trace') or contains(@groupname, 'Trace')]")
    }
)
Assert-Condition ($globalTraceState.Count -eq 0) 'A new global trace state variable was introduced.'

$orderFiles = @(
    'mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerS.xml',
    'mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerG.xml'
)
foreach ($relativePath in $orderFiles) {
    $current = $documents[(Join-Path $repoRoot $relativePath)]
    $baseline = [System.Xml.XmlDocument]::new()
    $baseline.LoadXml((Get-GitContent -Revision $baselineCommit -Path $relativePath))

    $currentParams = @($current.SelectNodes('/aiscript/order/params/param') | ForEach-Object { $_.GetAttribute('name') })
    $baselineParams = @($baseline.SelectNodes('/aiscript/order/params/param') | ForEach-Object { $_.GetAttribute('name') })
    Assert-Condition (($currentParams -join "`n") -ceq ($baselineParams -join "`n")) "$relativePath introduced or removed an order parameter."

    $debugParam = $current.SelectSingleNode("/aiscript/order/params/param[@name='DEBUG']")
    Assert-Condition ($null -ne $debugParam) "$relativePath must retain the DEBUG parameter."
    Assert-Condition ($debugParam.GetAttribute('advanced') -eq 'true') "$relativePath DEBUG must remain advanced=true."
    Assert-Condition ($debugParam.GetAttribute('default') -match 'else 0$') "$relativePath DEBUG must remain off without saved settings."
}
Write-Output '10-11/20 no new UI setting; existing advanced DEBUG default retained: OK'

$allModText = ($xmlFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join [Environment]::NewLine
Assert-Condition ($allModText -notmatch '\[TSE-(?:DIAG|AUDIT)\]') 'A retired TSE-DIAG or TSE-AUDIT marker was introduced.'

$diffText = (& git -C $repoRoot diff $baselineCommit --unified=0 -- 'mods/JP_TradeSubscriptionExplorer' 'mods/JP_ScriptLibrary') -join [Environment]::NewLine
Assert-Condition ($LASTEXITCODE -eq 0) 'Could not obtain the logging diff.'
$addedLines = @(
    $diffText -split "\r?\n" |
        Where-Object { $_ -match '^\+(?!\+\+)' } |
        ForEach-Object { $_.Substring(1).Trim() }
)
$removedLines = @(
    $diffText -split "\r?\n" |
        Where-Object { $_ -match '^-(?!--)' } |
        ForEach-Object { $_.Substring(1).Trim() }
)

$unprovenSectorId = $addedLines | Where-Object {
    $_ -match '(?:\$_Sector|\$SECTOR|\.sector|Sector)\.idcode'
}
Assert-Condition (@($unprovenSectorId).Count -eq 0) 'An unproven Sector.idcode access was added.'

$forbiddenDiagnostics = $addedLines | Where-Object {
    $_ -match '<(?:scan_|reveal_|set_trade_subscription|add_trade_subscription|subscribe_)'
}
Assert-Condition (@($forbiddenDiagnostics).Count -eq 0) 'A scan, reveal, or permanent subscription action was added.'
Write-Output '12-14/20 retired markers, unproven Sector.idcode, scan/reveal/subscription additions: absent'

$changedCodePaths = @(
    & git -C $repoRoot diff $baselineCommit --name-only -- 'mods/JP_TradeSubscriptionExplorer' 'mods/JP_ScriptLibrary' |
        Where-Object { $_ -match '\.xml$' }
)
foreach ($relativePath in $changedCodePaths) {
    $baselineText = Get-GitContent -Revision $baselineCommit -Path $relativePath
    $baseline = [System.Xml.XmlDocument]::new()
    $baseline.PreserveWhitespace = $true
    $baseline.LoadXml($baselineText)
    $current = $documents[(Join-Path $repoRoot $relativePath)]

    $baselineSignature = Get-ContractSignature -Document $baseline
    $currentSignature = Get-ContractSignature -Document $current
    Assert-Condition (($baselineSignature -join "`n") -ceq ($currentSignature -join "`n")) "$relativePath changed a productive label, return, wait, order, call, cancellation, failure, or resume contract."
}

$removedProductive = @(
    $removedLines | Where-Object {
        $_ -and
        $_ -notmatch '^</?(?:diff|aiscript)>$' -and
        $_ -notmatch '<debug_(?:to_file|text)\b' -and
        $_ -notmatch '<set_value name="\$_DebugFileName"'
    } | Where-Object { $addedLines -cnotcontains $_ }
)
Assert-Condition ($removedProductive.Count -eq 0) ("Productive removed lines were not preserved: " + ($removedProductive -join ' | '))

$forbiddenAddedActions = @(
    $addedLines | Where-Object {
        $_ -match '<(?:wait|return|resume|run_script|create_order|cancel_all_orders|cancel_order|set_order_failed|set_order_syncpoint_reached|signal_|scan_|reveal_)' -and
        $removedLines -cnotcontains $_
    }
)
Assert-Condition ($forbiddenAddedActions.Count -eq 0) ("New productive actions lie outside the logging allow-list: " + ($forbiddenAddedActions -join ' | '))
Write-Output '15/20 productive status, return, wait, call, order and cancellation contracts plus explicit diff allow-list: OK'

$completeAiFiles = @(
    foreach ($entry in $documents.GetEnumerator()) {
        if ($entry.Value.DocumentElement.LocalName -eq 'aiscript') {
            $entry.Key
        }
    }
)
$mdFiles = @(
    Join-Path $repoRoot 'mods/JP_ScriptLibrary/md/jp.ScriptLibrary.md.xml'
    Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/md/jp.TradeSubscriptionExplorer.md.xml'
)
$jshell = Get-Command 'jshell' -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $jshell) 'jshell is required for recursive Vanilla XSD validation.'

$aiValidationStatements = ($completeAiFiles | Sort-Object | ForEach-Object {
    "  validator.validate(new StreamSource(new File(`"$(ConvertTo-JavaPath -Path $_)`")));"
}) -join [Environment]::NewLine
$mdValidationStatements = ($mdFiles | ForEach-Object {
    "  validator.validate(new StreamSource(new File(`"$(ConvertTo-JavaPath -Path $_)`")));"
}) -join [Environment]::NewLine
$javaValidation = @"
import javax.xml.XMLConstants;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.SchemaFactory;
import java.io.File;
try {
  var factory = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
  var aiSchema = factory.newSchema(new File("$(ConvertTo-JavaPath -Path $aiSchemaPath)"));
  var validator = aiSchema.newValidator();
$aiValidationStatements
  var mdSchema = factory.newSchema(new File("$(ConvertTo-JavaPath -Path $mdSchemaPath)"));
  validator = mdSchema.newValidator();
$mdValidationStatements
  System.out.println("XSD validation complete");
} catch (Exception exception) {
  exception.printStackTrace();
  System.exit(1);
}
/exit
"@
$javaOutput = $javaValidation | & $jshell.Source --feedback silent 2>&1
if ($LASTEXITCODE -ne 0) {
    $javaOutput | ForEach-Object { Write-Error $_ }
    throw 'AI/MD XSD validation failed.'
}
Write-Output "16-18/20 XML, AI XSD ($($completeAiFiles.Count) complete scripts), MD XSD (2 files): OK"

$diffMappings = @{
    'mods/JP_ScriptLibrary/aiscripts/order.dock.wait.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.dock.wait.xml'
    'mods/JP_ScriptLibrary/aiscripts/order.dock.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.dock.xml'
    'mods/JP_ScriptLibrary/aiscripts/order.move.follow.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.move.follow.xml'
    'mods/JP_TradeSubscriptionExplorer/aiscripts/order.assist.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.assist.xml'
    'mods/JP_TradeSubscriptionExplorer/aiscripts/order.dock.wait.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.dock.wait.xml'
}
foreach ($mapping in $diffMappings.GetEnumerator()) {
    $diffDocument = $documents[(Join-Path $repoRoot $mapping.Key)]
    $vanillaDocument = Read-XmlDocument -Path (Join-Path $repoRoot $mapping.Value)
    foreach ($operation in $diffDocument.SelectNodes('/diff/*[@sel]')) {
        $matches = @($vanillaDocument.SelectNodes($operation.GetAttribute('sel')))
        Assert-Condition ($matches.Count -gt 0) "$($mapping.Key) selector did not resolve against Vanilla 9.00: $($operation.GetAttribute('sel'))"
    }
}
Write-Output 'Diff selectors against Vanilla 9.00: OK'

$existingRegressions = @(
    'validate-escape-sector-move.ps1',
    'validate-icon-paths.ps1',
    'validate-sector-access.ps1',
    'validate-md-groups.ps1',
    'validate-order-ready.ps1'
)
foreach ($regression in $existingRegressions) {
    & (Join-Path $PSScriptRoot $regression) | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "$regression failed."
}
Write-Output "19/20 existing regressions: OK ($($existingRegressions.Count) scripts)"

$diffCheck = & git -C $repoRoot diff $baselineCommit --check -- 2>&1
Assert-Condition ($LASTEXITCODE -eq 0) ("git diff --check failed: " + ($diffCheck -join ' | '))
Write-Output '20/20 git diff --check: OK'
Write-Output 'Structured TSE runtime debug logging validation: PASS'
