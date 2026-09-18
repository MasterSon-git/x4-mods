[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

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

$modsRoot = Join-Path $repoRoot 'mods/JP_X4Mods'
$tseRoot = Join-Path $modsRoot 'JP_TradeSubscriptionExplorer'
$sector = Read-XmlDocument (Join-Path $tseRoot 'aiscripts/JP_TradeSubscriptionExplorerS.xml')
$galaxy = Read-XmlDocument (Join-Path $tseRoot 'aiscripts/JP_TradeSubscriptionExplorerG.xml')
$assistDiff = Read-XmlDocument (Join-Path $tseRoot 'aiscripts/order.assist.xml')
$vanillaAssist = Read-XmlDocument (Join-Path $repoRoot 'x4-reference/x4-9.00/base/aiscripts/order.assist.xml')
$vanillaMove = Read-XmlDocument (Join-Path $repoRoot 'x4-reference/x4-9.00/base/aiscripts/move.generic.xml')
$vanillaUpdate = Read-XmlDocument (Join-Path $repoRoot 'x4-reference/x4-9.00/base/aiscripts/order.move.recon.update.xml')
$vanillaRecon = Read-XmlDocument (Join-Path $repoRoot 'x4-reference/x4-9.00/base/aiscripts/order.move.recon.xml')

$experienceFiles = @(Get-ChildItem -LiteralPath $tseRoot -Recurse -File -Filter 'experiences.xml')
$experienceActions = @(
    Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml' |
        Select-String -Pattern '<apply_experience\b'
)
$customExperienceRefs = @(
    Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml' |
        Select-String -Pattern 'JP_SHIP_TRADESUBSCRIPTION_UPDATED'
)
Assert-Condition ($experienceFiles.Count -eq 0) 'The unused TSE custom experiences library must be removed.'
Assert-Condition ($experienceActions.Count -eq 0) 'TSE and ScriptLibrary must not award experience for movement, idle, failure, or trade-information refresh.'
Assert-Condition ($customExperienceRefs.Count -eq 0) 'The retired custom experience ID is still referenced.'
Write-Output '1/5 custom TSE experience definition and all award actions are absent: OK'

$updateReconCall = $vanillaUpdate.SelectSingleNode(
    "//run_script[@name=`"'order.move.recon'`"]/param[@name='exploreupdate' and @value='true']"
)
$reconExperience = @($vanillaRecon.SelectNodes('//apply_experience'))
$exploreUpdateExperience = @(
    $vanillaRecon.SelectNodes("//do_if[@value='`$exploreupdate']//apply_experience")
)
$blindTouristExperience = @(
    $vanillaRecon.SelectNodes("//do_if[@value='`$blindtourist']//apply_experience")
)
Assert-Condition ($null -ne $updateReconCall) 'Vanilla ExploreUpdate must call Recon with exploreupdate=true.'
Assert-Condition ($reconExperience.Count -eq 2 -and $exploreUpdateExperience.Count -eq 0 -and $blindTouristExperience.Count -eq 2) 'Vanilla Recon experience must remain confined to actual blind-tourist discoveries.'
Write-Output '2/5 Vanilla 9.00 Update Stations has no experience award; discovery awards remain a distinct action: OK'

$sectorSkill = $sector.SelectSingleNode('/aiscript/order/skill').GetAttribute('min')
$galaxySkill = $galaxy.SelectSingleNode('/aiscript/order/skill').GetAttribute('min')
$updateSkill = $vanillaUpdate.SelectSingleNode('/aiscript/order/skill').GetAttribute('min')
$reconSkill = $vanillaRecon.SelectSingleNode('/aiscript/order/skill').GetAttribute('min')
Assert-Condition ($sectorSkill -eq '20') 'TSE-S required skill must remain 20.'
Assert-Condition ($galaxySkill -eq '40') 'TSE-G required skill must remain the visible two-star value 40.'
Assert-Condition ($updateSkill -eq '20') 'Vanilla ExploreUpdate comparison must require skill 20.'
Assert-Condition ($reconSkill -eq '40') 'Vanilla Recon comparison must require skill 40.'
Write-Output '3/5 TSE-S/TSE-G use visible one-/two-star thresholds 20/40, matching Vanilla Update/Recon thresholds: OK'

$assistTarget = $vanillaAssist.SelectSingleNode("//do_if[@value=`"`$orderdef.`$id == 'SupplyFleet'`"]")
$skillGuard = $assistTarget.SelectSingleNode(
    "ancestor::do_if[contains(@value, 'not `$order.requiredskill') and contains(@value, 'this.combinedskill ge `$order.requiredskill')]"
)
$expectedAssistAnchor = '//do_if[@value="$orderdef.$id == ''SupplyFleet''"]'
$tseAdd = @(
    $assistDiff.SelectNodes('/diff/add') |
        Where-Object { $_.GetAttribute('sel') -eq $expectedAssistAnchor }
)
$tseInsertion = if ($tseAdd.Count -eq 1) {
    $tseAdd[0].SelectSingleNode("do_if[@value=`"`$orderdef.`$id == 'JP_TradeSubscriptionExplorerG'`"]")
}
Assert-Condition ($null -ne $skillGuard) 'Vanilla Assist required-skill guard is missing around the extension anchor.'
Assert-Condition ($tseAdd.Count -eq 1 -and $null -ne $tseInsertion) 'The TSE-G Mimic branch must remain attached inside the Vanilla compatibility chain.'
Write-Output '4/5 Mimic executes the TSE-G branch only behind Vanilla required-skill validation: OK'

$moveDelay = $vanillaMove.SelectSingleNode(
    "//wait[@max='(not `$bigship) * (5.1 - (this.ship.pilot.skill.piloting / 3))s']"
)
$modSkillFormula = @(
    Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml' |
        Select-String -Pattern '5\.1\s*-\s*\(.*skill\.piloting|101\s*-\s*.*combinedskill|time_scandone'
)
$forbiddenActions = @(
    Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml' |
        Select-String -Pattern '<(?:scan_|reveal_|set_trade_subscription|add_trade_subscription|subscribe_)'
)
Assert-Condition ($null -ne $moveDelay) 'The referenced Vanilla 9.00 move.generic skill delay is missing.'
Assert-Condition ($modSkillFormula.Count -eq 0) 'A Vanilla movement or Recon scan delay was duplicated in mod code.'
Assert-Condition ($forbiddenActions.Count -eq 0) 'An NPC-only scan, reveal, or subscription action was introduced.'
Write-Output '5/5 move.generic owns its skill delay exactly once; no Recon/NPC-only formula was copied: OK'
Write-Output 'TSE experience and skill contract validation: PASS'
