[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tseIconsPath = Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer/libraries/icons.xml'
$scriptLibraryIconsPath = Join-Path $repoRoot 'mods/JP_ScriptLibrary/libraries/icons.xml'
$vanillaIconsPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/libraries/icons.xml'
$expectedPrefix = 'assets\textures\ui\order\'
$obsoletePrefix = 'assets\fx\gui\textures\order\'

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

$tseIcons = Read-XmlDocument -Path $tseIconsPath
$scriptLibraryIcons = Read-XmlDocument -Path $scriptLibraryIconsPath
$vanillaIcons = Read-XmlDocument -Path $vanillaIconsPath
Write-Output 'XML well-formedness: OK (2 mod icon libraries and Vanilla 9.00 icon reference)'

$expectedIcons = @{
    'order_jp_tradesubscriptionexplorers' = 'order_recon.tga'
    'order_jp_tradesubscriptionexplorerg' = 'order_recon.tga'
    'order_jp_lib_tse_updatesubscription' = 'order_exploreupdate.tga'
    'order_jp_lib_movetoposition' = 'order_movewait.tga'
    'order_jp_lib_movetoobject' = 'order_movetoobject.tga'
    'order_jp_lib_movetosector' = 'order_movewait.tga'
    'order_jp_lib_movethroughgate' = 'order_movewait.tga'
    'order_jp_lib_idlereturnhome' = 'order_wait.tga'
}

$modIconNodes = @($tseIcons.SelectNodes('/icons/icon')) + @($scriptLibraryIcons.SelectNodes('/icons/icon'))
Assert-Condition ($modIconNodes.Count -eq $expectedIcons.Count) 'The two mod libraries must retain exactly the eight reviewed icon definitions.'
Assert-Condition ((@($modIconNodes | ForEach-Object { $_.GetAttribute('name') } | Sort-Object -Unique)).Count -eq $expectedIcons.Count) 'Every mod icon name must remain unique.'

foreach ($node in $modIconNodes) {
    $name = $node.GetAttribute('name')
    Assert-Condition ($expectedIcons.ContainsKey($name)) "Unexpected mod icon definition: $name."
    $expectedTexture = $expectedPrefix + $expectedIcons[$name]
    Assert-Condition ($node.GetAttribute('texture') -eq $expectedTexture) "$name must use the Vanilla 9.00 texture path $expectedTexture."
    Assert-Condition ($node.GetAttribute('height') -eq '32' -and $node.GetAttribute('width') -eq '32') "$name must retain its 32 by 32 dimensions."
}

$fileNames = @($expectedIcons.Values | Sort-Object -Unique)
foreach ($fileName in $fileNames) {
    $expectedTexture = $expectedPrefix + $fileName
    $vanillaMatches = @($vanillaIcons.SelectNodes("/icons/icon[@texture='$expectedTexture']"))
    Assert-Condition ($vanillaMatches.Count -gt 0) "Vanilla 9.00 must contain at least one icon using $expectedTexture."
}

$modXmlFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'mods/JP_TradeSubscriptionExplorer') -Recurse -File -Filter '*.xml'
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'mods/JP_ScriptLibrary') -Recurse -File -Filter '*.xml'
)
$obsoleteReferences = @($modXmlFiles | Select-String -SimpleMatch $obsoletePrefix)
Assert-Condition ($obsoleteReferences.Count -eq 0) 'The obsolete assets\fx\gui\textures\order prefix must not remain in either extension.'

Write-Output 'Mod icon inventory: OK (8 unique definitions)'
Write-Output 'Vanilla 9.00 texture prefix and filenames: OK (5 referenced files)'
Write-Output 'Obsolete icon texture prefix absent: OK'
