[CmdletBinding()]
param(
    [string] $DestinationRoot,

    [string[]] $ModNames = @(
        'JP_ScriptLibrary',
        'JP_TradeSubscriptionExplorer'
    ),

    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'mods\JP_X4Mods'

if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $documentsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    $x4Root = Join-Path $documentsRoot 'Egosoft\X4'
    $profileDirectories = @(
        Get-ChildItem -LiteralPath $x4Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+$' }
    )

    if ($profileDirectories.Count -ne 1) {
        throw "Could not select a unique X4 profile below $x4Root. Pass -DestinationRoot explicitly."
    }
    $DestinationRoot = Join-Path $profileDirectories[0].FullName 'extensions'
}

$destinationRootPath = [System.IO.Path]::GetFullPath($DestinationRoot)

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Mod source directory does not exist: $sourceRoot"
}

$robocopy = Get-Command 'robocopy.exe' -ErrorAction SilentlyContinue
if ($null -eq $robocopy) {
    throw 'robocopy.exe was not found on PATH.'
}

if (-not $DryRun -and -not (Test-Path -LiteralPath $destinationRootPath -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $destinationRootPath -Force
}

Write-Host "X4 extension target: $destinationRootPath"
Write-Host "Mode: $(if ($DryRun) { 'preview (/L)' } else { 'mirror (/MIR)' })"
Write-Host 'Only the named extension directories are mirrored; other installed extensions are untouched.'
Write-Host ''

$results = [System.Collections.Generic.List[object]]::new()

foreach ($modName in $ModNames) {
    if ([string]::IsNullOrWhiteSpace($modName) -or
        $modName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $modName.Contains([System.IO.Path]::DirectorySeparatorChar) -or
        $modName.Contains([System.IO.Path]::AltDirectorySeparatorChar)) {
        throw "Invalid extension directory name: $modName"
    }

    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $sourceRoot $modName))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "Mod source does not exist: $sourcePath"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sourcePath 'content.xml') -PathType Leaf)) {
        throw "Mod source has no content.xml: $sourcePath"
    }

    $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $destinationRootPath $modName))
    $destinationRootPrefix = $destinationRootPath.TrimEnd([char[]] @('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $destinationPath.StartsWith($destinationRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved extension target escapes the configured destination root: $destinationPath"
    }

    $arguments = @(
        $sourcePath,
        $destinationPath,
        '/MIR',
        '/COPY:DAT',
        '/DCOPY:DAT',
        '/XF',
        'AGENTS.md',
        '/R:2',
        '/W:1',
        '/XJ',
        '/NP'
    )
    if ($DryRun) {
        $arguments += '/L'
    }

    Write-Host "[$modName] $sourcePath"
    & $robocopy.Source @arguments
    $exitCode = $LASTEXITCODE

    # Robocopy uses 0-7 for successful runs with different copy/change states.
    if ($exitCode -ge 8) {
        throw "Robocopy failed for $modName with exit code $exitCode."
    }

    $results.Add([pscustomobject]@{
        Extension = $modName
        ExitCode  = $exitCode
        Target    = $destinationPath
    })
    Write-Host "[$modName] completed with robocopy exit code $exitCode."
    Write-Host ''
}

$results | Format-Table -AutoSize
if ($DryRun) {
    Write-Host 'Preview completed; no files were changed.'
}
else {
    Write-Host 'Deployment completed successfully.'
}

exit 0
