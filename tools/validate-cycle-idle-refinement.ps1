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

$sector = Read-XmlDocument (Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerS.xml')
$galaxy = Read-XmlDocument (Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerG.xml')
$targets = Read-XmlDocument (Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.GetTradeDataToUpdate.xml')
$idle = Read-XmlDocument (Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/aiscripts/msx4.lib.IdleReturnHome.xml')
$manager = Read-XmlDocument (Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/md/msx4.ScriptLibrary.md.xml')

function Assert-MainCycle {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlDocument] $Document,
        [Parameter(Mandatory)] [string] $Mode
    )

    $progressInit = @($Document.SelectNodes("//set_value[@name='`$_CycleMadeProgress' and @exact='false']"))
    Assert-Condition ($progressInit.Count -eq 1) "$Mode must reset its productive pass state exactly once per non-empty candidate pass."

    $progressSet = $Document.SelectSingleNode(
        "//do_if[@value=`"`$_UpdateResult == 'success' or `$_UpdateResult == 'already_current'`"]" +
        "/set_value[@name='`$_CycleMadeProgress' and @exact='true']"
    )
    Assert-Condition ($null -ne $progressSet) "$Mode must count success and already_current as forward progress."

    $freshSearch = $Document.SelectSingleNode(
        "//do_if[@value='`$_CycleMadeProgress']/resume[@label='SEARCH_LBL']"
    )
    Assert-Condition ($null -ne $freshSearch) "$Mode must start a fresh full cycle after a productive candidate pass."

    $emptyBackoff = $Document.SelectSingleNode(
        "//do_if[@value='`$_FoundStations.count == 0']/resume[@label='IDLE_LBL']"
    )
    Assert-Condition ($null -ne $emptyBackoff) "$Mode must retain the zero-candidate idle fallback."

    $failureBackoff = $Document.SelectSingleNode(
        "//do_if[@value='`$_CycleMadeProgress']/following-sibling::resume[1][@label='IDLE_LBL']"
    )
    Assert-Condition ($null -ne $failureBackoff) "$Mode must retain a backoff when the complete pass made no progress."

    $escapeBackoff = $Document.SelectSingleNode(
        "//do_if[contains(@value, `"`$_EscapeResult != 'not_required'`")]/wait[@exact='`$IDLE_TIME']"
    )
    Assert-Condition ($null -ne $escapeBackoff) "$Mode must retain its explicit escape-failure backoff."
}

Assert-MainCycle -Document $sector -Mode 'TDE Sector'
Assert-MainCycle -Document $galaxy -Mode 'TDE Galaxy'
Write-Output '1/5 productive TDE-S/G passes restart at a fresh search while empty and failed passes remain backed off: OK'

$sectorSearch = $sector.SelectSingleNode(
    "//run_script[@name=`"'msx4.tde.GetTradeDataToUpdate'`"]/param[@name='SECTOR' and @value='`$SECTOR']"
)
$galaxySearch = $galaxy.SelectSingleNode(
    "//run_script[@name=`"'msx4.tde.GetTradeDataToUpdate'`"]/param[@name='SECTOR']"
)
$galaxyFinder = $targets.SelectSingleNode(
    "//do_if[@value='`$SECTOR == null']//find_sector[@name='`$_BuildSectors' and @space='player.galaxy' and @multiple='true']"
)
$galaxySnapshotSectors = $targets.SelectSingleNode(
    "//do_if[@value='`$SECTOR == null']//append_to_list[@name='`$_Sectors' and @exact='`$_CachedStation.sector']"
)
$oneSectorBreak = $targets.SelectSingleNode(
    "//do_if[@value='`$_FoundStations.count']/set_value[@name='`$SECTOR' and @exact='`$_Sector']/following-sibling::break"
)
Assert-Condition ($null -ne $sectorSearch) 'TDE-S must remain bound to its configured sector.'
Assert-Condition ($null -eq $galaxySearch) 'TDE-G must continue to invoke a galaxy-wide finder.'
Assert-Condition ($null -ne $galaxyFinder -and $null -ne $galaxySnapshotSectors -and $null -ne $oneSectorBreak) 'TDE-G must retain cached galaxy discovery and one selected sector group per finder call.'
Write-Output '2/5 TDE-S remains sector-bound and TDE-G can choose a new galaxy sector on the fresh pass: OK'

$legacyFallback = $idle.SelectSingleNode(
    "//do_if[@value='not `$MSX4_STRICT_BLACKLIST and not `$IDLE_MOVE_TO and not `$IDLE_FOLLOW and not `$IDLE_DOCKING']" +
    "/set_value[@name='`$IDLE_MOVE_TO' and @exact='true']"
)
$strictFallback = $idle.SelectSingleNode(
    "//do_if[contains(@value, '`$MSX4_STRICT_BLACKLIST') and not(starts-with(@value, 'not `$MSX4_STRICT_BLACKLIST'))]" +
    "/set_value[@name='`$IDLE_MOVE_TO' and @exact='true']"
)
$strictWaitCommand = $idle.SelectSingleNode(
    "//do_if[@value='`$MSX4_STRICT_BLACKLIST and not `$IDLE_MOVE_TO and not `$IDLE_FOLLOW and not `$IDLE_DOCKING']" +
    "/set_command[@command='command.wait']"
)
$controlledWait = $idle.SelectSingleNode(
    "//do_if[@value='`$_IdleActionFailed']/following-sibling::do_else[1]/wait[not(@exact)]"
)
Assert-Condition ($null -ne $legacyFallback) 'The historical non-strict return-to-start fallback must remain.'
Assert-Condition ($null -eq $strictFallback) 'The strict TDE path must not synthesize an idle movement.'
Assert-Condition ($null -ne $strictWaitCommand -and $null -ne $controlledWait) 'No selected TDE idle action must display Wait and block under manager control.'
Write-Output '3/5 no selected strict idle action performs no movement and waits under the existing timeout manager: OK'

$targetedCleanup = $manager.SelectSingleNode(
    "//cue[@name='MSX4_SL_ManageIdleReturnHome_MD']//do_for_each[@name='`$_Order' and @in='`$_Ship.orders.clone']" +
    "/do_if/cancel_order[@order='`$_Order']"
)
$broadCleanup = $manager.SelectNodes("//cue[@name='MSX4_SL_ManageIdleReturnHome_MD']//cancel_all_orders")
Assert-Condition ($null -ne $targetedCleanup -and $broadCleanup.Count -eq 0) 'Bugfix 008 selective idle-stack cleanup must remain intact.'
Write-Output '4/5 Bugfix 008 selective timeout cleanup and foreign queue preservation remain intact: OK'

$forbidden = Select-String -Path @(
    (Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerS.xml'),
    (Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerG.xml'),
    (Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/aiscripts/msx4.lib.IdleReturnHome.xml')
) -Pattern '<(?:scan_|reveal_|set_trade_subscription|add_trade_subscription|subscribe_)'
Assert-Condition (@($forbidden).Count -eq 0) 'Cycle/idle refinement introduced a forbidden scan, reveal, or permanent subscription action.'
Write-Output '5/5 no scan, reveal or permanent subscription action was introduced: OK'
Write-Output 'TDE cycle and idle refinement validation: PASS'
