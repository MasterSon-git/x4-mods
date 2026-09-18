[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modsRoot = Join-Path $repoRoot 'mods'
$loggingFixCommit = '326107189620a293deef6c432246d35977bc754d'

$managerPath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_ScriptLibrary/md/jp.ScriptLibrary.md.xml'
$idlePath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_ScriptLibrary/aiscripts/jp.lib.IdleReturnHome.xml'
$dockWaitDiffPath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_ScriptLibrary/aiscripts/order.dock.wait.xml'
$dockDiffPath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_ScriptLibrary/aiscripts/order.dock.xml'
$followDiffPath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_ScriptLibrary/aiscripts/order.move.follow.xml'
$sectorPath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerS.xml'
$galaxyPath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_TradeSubscriptionExplorer/aiscripts/JP_TradeSubscriptionExplorerG.xml'
$targetsPath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_TradeSubscriptionExplorer/aiscripts/jp.lib.TSE.GetTradesubscriptionsToUpdate.xml'
$escapePath = Join-Path $repoRoot 'mods/JP_X4Mods/JP_ScriptLibrary/aiscripts/jp.lib.EscapeTravelBlacklist.xml'

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

function Get-DocumentOrder {
    param([Parameter(Mandatory)] [System.Xml.XmlNode] $Node)

    return @($Node.SelectNodes('preceding::*')).Count
}

$allXmlFiles = @(Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml')
$documents = @{}
foreach ($file in $allXmlFiles) {
    $documents[$file.FullName] = Read-XmlDocument -Path $file.FullName
}

$manager = $documents[$managerPath]
$idle = $documents[$idlePath]
$dockWaitDiff = $documents[$dockWaitDiffPath]
$dockDiff = $documents[$dockDiffPath]
$followDiff = $documents[$followDiffPath]
$sector = $documents[$sectorPath]
$galaxy = $documents[$galaxyPath]
$targets = $documents[$targetsPath]
$escape = $documents[$escapePath]

$managerShipLoop = $manager.SelectSingleNode("//cue[@name='SL_ManageIdleReturnHome_MD']/actions/do_for_each[@name='`$_Ship']")
Assert-Condition ($null -ne $managerShipLoop) 'The idle manager ship loop is missing.'
$timeoutContinue = $managerShipLoop.SelectSingleNode("./do_if[@value='`$_IdleOrderPresent and ((player.age - `$_IdleStartTime) lt `$_IdleTime)']/continue")
Assert-Condition ($null -ne $timeoutContinue) 'The existing idle-time comparison and continue path changed.'

$targetedLoop = $managerShipLoop.SelectSingleNode("./do_for_each[@name='`$_Order' and @in='`$_Ship.orders.clone']")
Assert-Condition ($null -ne $targetedLoop) 'Timeout cleanup must iterate over a stable clone of the ship order queue.'
$targetedCondition = $targetedLoop.SelectSingleNode("./do_if")
Assert-Condition ($null -ne $targetedCondition) 'Timeout cleanup has no selective order guard.'
$targetedExpression = $targetedCondition.GetAttribute('value')
Assert-Condition ($targetedExpression -eq "`$_Order.exists and (`$_Order.id == 'JP_lib_IdleReturnHome' or @`$_Order.`$IDLE_RETURN_HOME)") 'Timeout cleanup must select only the idle parent or explicitly tagged idle children.'
$targetedCancel = @($targetedCondition.SelectNodes("./cancel_order[@order='`$_Order']"))
Assert-Condition ($targetedCancel.Count -eq 1) 'Timeout cleanup must cancel each selected order by its exact order reference.'
Assert-Condition ((Get-DocumentOrder $targetedLoop) -lt (Get-DocumentOrder $managerShipLoop.SelectSingleNode("./remove_value[@name='global.`$SL_IdleShips.{`$_Ship}']"))) 'The idle stack must be cancelled before its timer entry is removed.'

$cancelSignals = @(
    foreach ($document in $documents.Values) {
        $document.SelectNodes("//signal_objects[@param=`"'Cancel_IdleReturnHome'`"]")
    }
)
Assert-Condition ($cancelSignals.Count -eq 0) 'The timeout must not broadcast Cancel_IdleReturnHome and accidentally target only this.ship.order.'
Write-Output '1/24 active IdleReturnHome parent is selected and cancelled by exact reference: OK'

$dockWaitCreate = $idle.SelectSingleNode("//create_order[@id=`"'DockAndWait'`" and @immediate='true' and param[@name='IDLE_RETURN_HOME' and @value='true'] and param[@name='callerid' and @value='this.assignedcontrolled.order']]")
Assert-Condition ($null -ne $dockWaitCreate) 'Strict Idle Dock must retain its tagged immediate DockAndWait child and callerid.'
$dockAtPropagation = $dockWaitDiff.SelectSingleNode("/diff/add/param[@name='IDLE_RETURN_HOME' and @value='`$IDLE_RETURN_HOME']")
Assert-Condition ($null -ne $dockAtPropagation) 'DockAndWait must continue to tag its immediate DockAt child.'
Assert-Condition ($targetedExpression -match '@\$_Order\.\$IDLE_RETURN_HOME') 'Tagged DockAndWait and DockAt children must be selected by timeout cleanup.'
Write-Output '2/24 tagged DockAndWait/DockAt immediate children are included in exact cleanup: OK'

Assert-Condition ($manager.SelectNodes("//create_order[@id=`"'JP_lib_IdleReturnHome'`"]").Count -eq 0) 'The manager must not hard-start IdleReturnHome.'
Assert-Condition ($manager.SelectNodes("//run_script[contains(@name, 'TradeSubscriptionExplorer')] | //create_order[contains(@id, 'TradeSubscriptionExplorer')]").Count -eq 0) 'The ScriptLibrary manager must not directly start a TSE main order.'
Write-Output '3/24 timeout cleanup contains no direct IdleReturnHome restart: OK'

function Assert-TseCycleContract {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlDocument] $Document,
        [Parameter(Mandatory)] [string] $Mode,
        [Parameter(Mandatory)] [string] $TraceSource
    )

    $searchLabel = $Document.SelectSingleNode("//attention[@min='unknown']/actions/label[@name='SEARCH_LBL']")
    $escapeCall = $Document.SelectSingleNode("//attention[@min='unknown']/actions/run_script[@name=`"'jp.lib.EscapeTravelBlacklist'`"]")
    $candidateCall = $Document.SelectSingleNode("//attention[@min='unknown']/actions/run_script[@name=`"'jp.lib.TSE.GetTradesubscriptionsToUpdate'`"]")
    $idleLabel = $Document.SelectSingleNode("//attention[@min='unknown']/actions/label[@name='IDLE_LBL']")
    $idleCreate = $Document.SelectSingleNode("//attention[@min='unknown']/actions/create_order[@id=`"'JP_lib_IdleReturnHome'`" and @immediate='true']")

    Assert-Condition ($null -ne $searchLabel -and $null -ne $escapeCall -and $null -ne $candidateCall -and $null -ne $idleLabel -and $null -ne $idleCreate) "$Mode main-cycle nodes are incomplete."
    Assert-Condition ((Get-DocumentOrder $searchLabel) -lt (Get-DocumentOrder $escapeCall)) "$Mode must check Escape after SEARCH_LBL."
    Assert-Condition ((Get-DocumentOrder $escapeCall) -lt (Get-DocumentOrder $candidateCall)) "$Mode must search candidates after Escape."
    Assert-Condition ((Get-DocumentOrder $candidateCall) -lt (Get-DocumentOrder $idleLabel)) "$Mode must complete candidate search before its idle fallback."
    Assert-Condition ((Get-DocumentOrder $idleLabel) -lt (Get-DocumentOrder $idleCreate)) "$Mode may create IdleReturnHome only in the idle fallback."
    Assert-Condition ($Document.SelectNodes("//create_order[@id=`"'JP_lib_IdleReturnHome'`"]").Count -eq 1) "$Mode must retain exactly one idle fallback creation site."
    Assert-Condition ($null -ne $Document.SelectSingleNode("//*[self::debug_to_file or self::debug_text][contains(@text, 'source=$TraceSource') and contains(@text, 'event=cycle_start')]")) "$Mode must retain its observable cycle_start trace."

    $emptyResult = $Document.SelectSingleNode("//do_if[@value='`$_FoundStations.count == 0']/resume[@label='IDLE_LBL']")
    Assert-Condition ($null -ne $emptyResult) "$Mode must enter idle after a zero-candidate result."
}

Assert-TseCycleContract -Document $sector -Mode 'TSE Sector' -TraceSource 'tse_s'
Assert-TseCycleContract -Document $galaxy -Mode 'TSE Galaxy' -TraceSource 'tse_g'
Write-Output '4-5/24 cancelling the immediate idle stack exposes TSE-S/G, whose restart begins at a full observable main cycle: OK'

$notRequiredGuard = $escape.SelectSingleNode("//do_if[@value='not `$_Ship.sector.isblacklisted.{blacklisttype.sectortravel}.{`$blacklistgroup}.{`$_Ship}']/return[@value=`"'not_required'`"]")
Assert-Condition ($null -ne $notRequiredGuard) 'Escape must still return not_required while the current sector is travel-allowed.'
foreach ($document in @($sector, $galaxy)) {
    $escapeResultGuard = $document.SelectSingleNode("//do_if[@value=`"`$_EscapeResult != 'not_required' and `$_EscapeResult != 'success'`"]")
    Assert-Condition ($null -ne $escapeResultGuard) 'TSE must accept not_required without entering escape backoff.'
}
Write-Output '6-8/24 every new cycle checks the effective travel blacklist; allowed sectors proceed directly and only blocked sectors escape: OK'

$sectorCandidateCall = $sector.SelectSingleNode("//run_script[@name=`"'jp.lib.TSE.GetTradesubscriptionsToUpdate'`"]")
$galaxyCandidateCall = $galaxy.SelectSingleNode("//run_script[@name=`"'jp.lib.TSE.GetTradesubscriptionsToUpdate'`"]")
Assert-Condition ($null -ne $sectorCandidateCall.SelectSingleNode("./param[@name='SECTOR' and @value='`$SECTOR']")) 'TSE-S candidate search must remain limited to its configured sector.'
Assert-Condition ($null -eq $galaxyCandidateCall.SelectSingleNode("./param[@name='SECTOR']")) 'TSE-G candidate search must not be limited to the current or idle-dock sector.'
$galaxySectorSearch = $targets.SelectSingleNode("//do_if[@value='`$SECTOR == null']//find_sector[@name='`$_BuildSectors' and @space='player.galaxy' and @multiple='true']")
$cachedSectorSelection = $targets.SelectSingleNode("//do_if[@value='`$SECTOR == null']//append_to_list[@name='`$_Sectors' and @exact='`$_CachedStation.sector']")
Assert-Condition ($null -ne $galaxySectorSearch -and $null -ne $cachedSectorSelection) 'TSE-G helper must retain cached galaxy-wide discovery.'
Assert-Condition ($null -ne $targets.SelectSingleNode("//run_script[@name=`"'jp.lib.SortByEstimatedTravelTime'`" and param[@name='LIST' and @value='`$_ReachableSectors']]")) 'TSE-G must retain travel-time ranking of reachable sectors.'
Assert-Condition ($null -ne $targets.SelectSingleNode("//do_if[@value='`$_FoundStations.count']/set_value[@name='`$SECTOR' and @exact='`$_Sector']")) 'TSE-G must continue deriving the selected sector from actual station candidates.'
Write-Output '9-11/24 TSE-S remains sector-bound; TSE-G remains galaxy-wide and may select another candidate sector: OK'

foreach ($document in @($sector, $galaxy)) {
    $candidateCall = $document.SelectSingleNode("//run_script[@name=`"'jp.lib.TSE.GetTradesubscriptionsToUpdate'`"]")
    $idleCreate = $document.SelectSingleNode("//create_order[@id=`"'JP_lib_IdleReturnHome'`"]")
    Assert-Condition ((Get-DocumentOrder $candidateCall) -lt (Get-DocumentOrder $idleCreate)) 'Candidate search must precede every idle fallback.'
}
Write-Output '12-13/24 a new candidate pass necessarily precedes any later idle fallback or redock: OK'

Assert-Condition ($null -ne $idle.SelectSingleNode("/aiscript/order/params/param[@name='cannotdock' and @default='false']")) 'IdleReturnHome must retain cannotdock.'
Assert-Condition ($null -ne $idle.SelectSingleNode("//create_order[@id=`"'DockAndWait'`"]/param[@name='callerid' and @value='this.assignedcontrolled.order']")) 'Idle Dock must retain callerid-based cannotdock communication.'
Assert-Condition ($dockWaitDiff.SelectNodes("//edit_order_param[@param=`"'cannotdock'`" and @value='true']").Count -eq 0) 'DockAndWait logging diff must not replace productive cannotdock edits.'
Assert-Condition ($dockDiff.SelectNodes("//edit_order_param[@param=`"'cannotdock'`" and @value='true']").Count -eq 0) 'DockAt logging diff must not replace productive cannotdock edits.'
Write-Output '14/24 cannotdock parameter and caller contract remain present: OK'

$idleMove = $idle.SelectSingleNode("//run_script[@name=`"'move.generic'`" and param[@name='destination' and @value='`$WHERE_TO_MOVE.{1}']]")
Assert-Condition ($null -ne $idleMove) 'Strict Idle Move must remain a synchronous move.generic call under IdleReturnHome.'
$idleFollow = $idle.SelectSingleNode("//run_script[@name=`"'order.move.follow'`" and param[@name='IDLE_RETURN_HOME' and @value='true']]")
Assert-Condition ($null -ne $idleFollow) 'Strict Idle Follow must remain a synchronous tagged call under IdleReturnHome.'
Assert-Condition ($null -ne $followDiff.SelectSingleNode("//do_if[@value='not `$movesuccess']/do_if[@value='not `$IDLE_RETURN_HOME and @this.assignedcontrolled.order.isrunning']")) 'Idle Follow target/move failure must remain distinct from the parent order failure path.'
Assert-Condition ($null -ne $idle.SelectSingleNode("//do_if[@value='`$_IdleActionFailed']/wait[@exact='`$IDLE_TIME']")) 'Observed idle-action failures must retain their configured full backoff.'
Assert-Condition ($null -ne $idle.SelectSingleNode("//do_if[@value='`$_IdleActionFailed']/following-sibling::do_else[1]/wait[not(@exact)]")) 'No available idle action must retain the parent wait until the manager timeout.'
Write-Output '15-17/24 Idle Move, Idle Follow and both normal backoff paths remain intact: OK'

Assert-Condition ($managerShipLoop.SelectNodes(".//cancel_all_orders").Count -eq 0) 'Idle timeout cleanup must never cancel the whole queue.'
Assert-Condition ($managerShipLoop.SelectNodes(".//cancel_order").Count -eq 1) 'Idle timeout cleanup must contain only its one filtered exact-order cancellation site.'
Write-Output '18/24 no cancel_all_orders or unfiltered foreign-queue deletion was introduced: OK'

& (Join-Path $PSScriptRoot 'validate-cycle-idle-refinement.ps1') | Out-Null
Write-Output '19/24 later cycle/idle refinements preserve the selective CANDIDATE-007 timeout contract: OK'

& (Join-Path $PSScriptRoot 'validate-runtime-debug-logging.ps1') | ForEach-Object { "  $_" }
Write-Output "20-23/24 XML, AI XSD, MD XSD and all previous regressions: OK ($($allXmlFiles.Count) mod XML files)"

$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'SilentlyContinue'
    $diffCheck = & git -c core.autocrlf=false -C $repoRoot diff $loggingFixCommit --check -- 2>&1
    $gitExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
Assert-Condition ($gitExitCode -eq 0) ("git diff --check failed: " + ($diffCheck -join ' | '))
Write-Output '24/24 git diff --check: OK'
Write-Output 'TSE idle timeout return validation: PASS'
