[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modsRoot = Join-Path $repoRoot 'mods'
$libraryRoot = Join-Path $modsRoot 'MSX4_ScriptLibrary'
$explorerRoot = Join-Path $modsRoot 'MSX4_TradeDataExplorer'

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

Assert-Condition (Test-Path -LiteralPath $libraryRoot -PathType Container) 'MSX4 Script Library extension directory must exist.'
Assert-Condition (Test-Path -LiteralPath $explorerRoot -PathType Container) 'Trade Data Explorer extension directory must exist.'

$libraryContent = Read-XmlDocument (Join-Path $libraryRoot 'content.xml')
$explorerContent = Read-XmlDocument (Join-Path $explorerRoot 'content.xml')

Assert-Condition ($libraryContent.content.id -eq 'MSX4_ScriptLibrary') 'Script Library must use the standalone MSX4 extension ID.'
Assert-Condition ($explorerContent.content.id -eq 'MSX4_TradeDataExplorer') 'Trade Data Explorer must use the standalone MSX4 extension ID.'
Assert-Condition ($libraryContent.content.name -eq 'MSX4 Script Library') 'Script Library must expose its maintained product name.'
Assert-Condition ($explorerContent.content.name -eq 'Trade Data Explorer') 'Trade Data Explorer must expose its maintained product name.'
Assert-Condition ($libraryContent.content.save -eq '0' -and $explorerContent.content.save -eq '0') 'Both replacement extensions must remain removable save dependencies.'

$libraryGameDependency = @($libraryContent.content.dependency | Where-Object { -not $_.id })
$explorerGameDependency = @($explorerContent.content.dependency | Where-Object { -not $_.id })
Assert-Condition ($libraryGameDependency.Count -eq 1 -and $libraryGameDependency[0].version -eq '900') 'Script Library must target X4 9.00.'
Assert-Condition ($explorerGameDependency.Count -eq 1 -and $explorerGameDependency[0].version -eq '900') 'Trade Data Explorer must target X4 9.00.'
$extensionDependencies = @($explorerContent.content.dependency | Where-Object { $_.id })
Assert-Condition ($extensionDependencies.Count -eq 1) 'Trade Data Explorer must declare exactly one extension dependency.'
Assert-Condition ($extensionDependencies[0].id -eq 'MSX4_ScriptLibrary' -and $extensionDependencies[0].optional -eq 'false') 'Trade Data Explorer must require MSX4 Script Library.'

$xmlFiles = @(Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml')
foreach ($file in $xmlFiles) {
    $null = Read-XmlDocument $file.FullName
}
Write-Output "XML well-formedness: OK ($($xmlFiles.Count) namespaced extension files)"

$activeText = ($xmlFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
$forbiddenPatterns = @(
    '(?i)JP_TradeSubscriptionExplorer',
    '(?i)JP_ScriptLibrary',
    '(?i)jp\.lib\.',
    '(?i)order_jp_',
    '\$JP_',
    '\$SL_',
    '\$TSE_',
    '\[TSE-(?:TRACE|PERF)\]',
    '(?i)TradeSubscriptionExplorer\.logs',
    '(?i)TSE_Runtime\.log'
)
foreach ($pattern in $forbiddenPatterns) {
    Assert-Condition (-not [regex]::IsMatch($activeText, $pattern)) "Legacy active identifier remains: $pattern"
}

$legacyTagMatches = [regex]::Matches($activeText, '(?:\[TSE\]|#TSE-[SG]|\[TDE\]|#TDE-[SG])')
Assert-Condition ($legacyTagMatches.Count -gt 0) 'Legacy visible ship-tag cleanup must remain for migration hygiene.'
$legacyTagLines = @($xmlFiles | Select-String -Pattern '(?:\[TSE\]|#TSE-[SG]|\[TDE\]|#TDE-[SG])')
Assert-Condition ((@($legacyTagLines | Where-Object { $_.Line -notmatch '<replace ' })).Count -eq 0) 'Legacy visible tags may occur only in cleanup replacements.'

$requiredTokens = @(
    'MSX4_TradeDataExplorerS',
    'MSX4_TradeDataExplorerG',
    'MSX4_TDE_UpdateTradeData',
    'MSX4_lib_IdleReturnHome',
    'MSX4_TradeDataExplorer.logs',
    'MSX4_TradeDataExplorer_Runtime.log',
    '[MSX4-TDE-TRACE]',
    '[MSX4-SLIB-TRACE]'
)
foreach ($token in $requiredTokens) {
    Assert-Condition ($activeText.Contains($token)) "Required namespaced contract is absent: $token"
}

$textPages = @()
foreach ($defaultTextFile in @((Join-Path $libraryRoot 't/0001.xml'), (Join-Path $explorerRoot 't/0001.xml'))) {
    $textDocument = Read-XmlDocument $defaultTextFile
    $textPages += [string]$textDocument.language.page.id
}
Assert-Condition ($textPages.Count -eq 2 -and (@($textPages | Sort-Object -Unique)).Count -eq 2) 'The two extensions must use distinct text-page IDs.'
Assert-Condition ($textPages -contains '975210' -and $textPages -contains '975211') 'The reviewed MSX4 text-page IDs must remain stable.'

$removedHelpers = @(
    'FindStationToEquipAt',
    'RestockDeployables',
    'RestockEquipment'
)
foreach ($helper in $removedHelpers) {
    Assert-Condition (-not $activeText.Contains($helper)) "Unmaintained helper remains referenced: $helper"
}

Write-Output 'Extension metadata and dependency boundary: OK'
Write-Output 'Legacy executable namespaces absent: OK'
Write-Output 'Legacy ship-tag strings limited to cleanup replacements: OK'
Write-Output 'MSX4 order, diagnostic and text-page contracts: OK'
Write-Output 'Removed out-of-scope helpers unreferenced: OK'
