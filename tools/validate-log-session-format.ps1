[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modsRoot = Join-Path $repoRoot 'mods'

function Assert-Condition {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        throw "Invariant failed: $Message"
    }
}

function Get-RepoRelativePath {
    param([Parameter(Mandatory)] [string] $Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return $fullPath.Substring($repoRoot.Length).TrimStart('\', '/')
}

function Read-XmlDocument {
    param([Parameter(Mandatory)] [string] $Path)

    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.Load($Path)
    return $document
}

$debugRecords = @(
    foreach ($file in Get-ChildItem -LiteralPath @(
        (Join-Path $modsRoot 'JP_TradeSubscriptionExplorer'),
        (Join-Path $modsRoot 'JP_ScriptLibrary')
    ) -Recurse -File -Filter '*.xml') {
        $document = Read-XmlDocument $file.FullName
        foreach ($node in $document.SelectNodes("//*[self::debug_to_file or self::debug_text]")) {
            [pscustomobject]@{
                File = $file
                Node = $node
                Text = $node.GetAttribute('text')
            }
        }
    }
)
$traceRecords = @($debugRecords | Where-Object { $_.Text.Contains('[TSE-TRACE]') })
Assert-Condition ($debugRecords.Count -gt 0) 'No custom debug output was found.'
Assert-Condition ($traceRecords.Count -gt 0) 'No structured TSE runtime traces were found.'

foreach ($record in $debugRecords) {
    $relativePath = Get-RepoRelativePath $record.File.FullName
    $expectedType = if ($relativePath -like 'mods\JP_TradeSubscriptionExplorer\aiscripts\*') {
        'TSEAI '
    }
    elseif ($relativePath -like 'mods\JP_TradeSubscriptionExplorer\md\*') {
        'TSEMD '
    }
    elseif ($relativePath -like 'mods\JP_ScriptLibrary\aiscripts\*') {
        'SLIBAI'
    }
    else {
        'SLIBMD'
    }

    $match = [regex]::Match(
        $record.Text,
        "^'\[(?<type>.{6})\] ' \+ player\.age \+ ' \*\*\* (?<function>[A-Za-z0-9_.]+):' \+ "
    )
    Assert-Condition ($match.Success) "$relativePath has an invalid log envelope."
    Assert-Condition ($match.Groups['type'].Value -ceq $expectedType) "$relativePath uses type '$($match.Groups['type'].Value)' instead of '$expectedType'."
    Assert-Condition ($record.Text -notmatch '(\\n|\\r|[\r\n])') "$relativePath has a multiline custom log template."
    Assert-Condition ($record.Text -cmatch '^[\x00-\x7F]+$') "$relativePath has a non-ASCII custom log template."
    Assert-Condition ($record.Text -notmatch 'player\.systemtime') "$relativePath uses system time instead of Universe time."
}
Write-Output "1/5 all $($debugRecords.Count) custom debug actions use the source-specific six-character type, player.age, function and one-line ASCII output: OK"

foreach ($record in $traceRecords) {
    $relativePath = Get-RepoRelativePath $record.File.FullName
    foreach ($key in @('source=', 'ship=', 'phase=', 'event=')) {
        Assert-Condition ($record.Text.Contains($key)) "$relativePath trace is missing $key."
    }
}
Write-Output "Structured payload contract remains present on all $($traceRecords.Count) TSE traces: OK"

$sessionMarkers = @($traceRecords | Where-Object { $_.Text -match 'phase=session event=session_start' })
Assert-Condition ($sessionMarkers.Count -eq 1) "Expected one session marker, got $($sessionMarkers.Count)."
$sessionMarker = $sessionMarkers[0]
$sessionRelativePath = Get-RepoRelativePath $sessionMarker.File.FullName
Assert-Condition ($sessionRelativePath -eq 'mods\JP_TradeSubscriptionExplorer\md\jp.TradeSubscriptionExplorer.md.xml') 'The session marker must be owned by the central TSE MD setup.'
Assert-Condition ($sessionMarker.Node.LocalName -eq 'debug_to_file') 'The session marker must write to the custom runtime file.'
Assert-Condition ($sessionMarker.Node.GetAttribute('directory') -eq "'JP_TradeSubscriptionExplorer.logs'") 'The session marker uses the wrong directory.'
Assert-Condition ($sessionMarker.Node.GetAttribute('name') -eq "'TSE_Runtime.log'") 'The session marker uses the wrong file.'
Assert-Condition ($sessionMarker.Node.GetAttribute('append') -eq 'true') 'The safe session boundary must append instead of racing to overwrite existing output.'
Assert-Condition ($null -ne $sessionMarker.Node.SelectSingleNode("ancestor::cue[@name='TSE_Setup_MD']")) 'The session marker must be at the low-frequency game start/load setup boundary.'
Write-Output '2/5 exactly one append-only session marker is owned by TSE_Setup_MD: OK'

$runtimeWriters = @(
    foreach ($record in $traceRecords) {
        if ($record.Node.LocalName -eq 'debug_to_file' -and
            $record.Node.GetAttribute('name') -match 'TSE_Runtime\.log') {
            $record
        }
    }
)
$overwritingRuntimeWriters = @(
    $runtimeWriters | Where-Object { $_.Node.GetAttribute('append') -eq 'false' }
)
Assert-Condition ($overwritingRuntimeWriters.Count -eq 0) 'A ship, cycle, Mimic, idle, or setup path can overwrite TSE_Runtime.log.'
Write-Output '3/5 no structured runtime writer can erase entries from this or an earlier session: OK'

$sessionMarkersOutsideSetup = @(
    $sessionMarkers | Where-Object {
        $null -eq $_.Node.SelectSingleNode("ancestor::cue[@name='TSE_Setup_MD']")
    }
)
Assert-Condition ($sessionMarkersOutsideSetup.Count -eq 0) 'A per-ship or polling session marker exists.'
Assert-Condition ($null -eq $sessionMarker.Node.SelectSingleNode('ancestor::cue[@checkinterval]')) 'The session marker must not live in a polling cue.'
Write-Output '4/5 starting additional ships, cycles, Mimic or Idle cannot create or reset a logging session: OK'

$aiUnguarded = @(
    foreach ($record in $traceRecords | Where-Object {
        (Get-RepoRelativePath $_.File.FullName) -like '*\aiscripts\*'
    }) {
        $ancestor = $record.Node.ParentNode
        $guarded = $false
        while ($null -ne $ancestor) {
            if ($ancestor.LocalName -in @('do_if', 'do_elseif') -and
                $ancestor.GetAttribute('value') -match '(?:\$DEBUG|TSETraceDebug|\.?\$DEBUG).*gt 0') {
                $guarded = $true
                break
            }
            $ancestor = $ancestor.ParentNode
        }
        if (-not $guarded) {
            $record
        }
    }
)
Assert-Condition ($aiUnguarded.Count -eq 0) 'An AI detail trace is active at DEBUG=0.'
Write-Output '5/5 AI detail tracing remains inert at DEBUG=0; the central session marker is the documented file-only exception: OK'
Write-Output 'TSE log session and format validation: PASS'
