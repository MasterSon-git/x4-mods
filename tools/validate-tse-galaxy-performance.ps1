[CmdletBinding()]
param(
    [switch] $SkipExistingRegressions,
    [switch] $SkipGitCommitChecks
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$helperPath = Join-Path $repo 'mods\JP_TradeSubscriptionExplorer\aiscripts\jp.lib.TSE.GetTradesubscriptionsToUpdate.xml'
$galaxyPath = Join-Path $repo 'mods\JP_TradeSubscriptionExplorer\aiscripts\JP_TradeSubscriptionExplorerG.xml'
$sectorPath = Join-Path $repo 'mods\JP_TradeSubscriptionExplorer\aiscripts\JP_TradeSubscriptionExplorerS.xml'
$updatePath = Join-Path $repo 'mods\JP_TradeSubscriptionExplorer\aiscripts\jp.lib.TSE.UpdateSubscription.xml'
$idlePath = Join-Path $repo 'mods\JP_ScriptLibrary\aiscripts\jp.lib.IdleReturnHome.xml'
$mdPath = Join-Path $repo 'mods\JP_TradeSubscriptionExplorer\md\jp.TradeSubscriptionExplorer.md.xml'
$aiSchemaPath = Join-Path $repo 'x4-reference\x4-9.00\base\libraries\aiscripts.xsd'
$mdSchemaPath = Join-Path $repo 'x4-reference\x4-9.00\base\libraries\md.xsd'

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) {
        throw "Invariant failed: $Message"
    }
    Write-Host "PASS: $Message"
}

function Read-Xml {
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

$helper = Read-Xml $helperPath
$galaxy = Read-Xml $galaxyPath
$sector = Read-Xml $sectorPath
$update = Read-Xml $updatePath
$idle = Read-Xml $idlePath
$md = Read-Xml $mdPath
$helperText = Get-Content -Raw -LiteralPath $helperPath
$galaxyText = Get-Content -Raw -LiteralPath $galaxyPath
$sectorText = Get-Content -Raw -LiteralPath $sectorPath
$updateText = Get-Content -Raw -LiteralPath $updatePath
$idleText = Get-Content -Raw -LiteralPath $idlePath
$mdText = Get-Content -Raw -LiteralPath $mdPath

# 1-6: shared discovery and coordinator state.
Assert-True ($helperText.Contains('global.$TSE_GalaxyCandidateStations') -and
    $helperText.Contains('$_CacheHit')) 'a worker can reuse a shared galaxy snapshot instead of rebuilding every wakeup'
Assert-True (($helper.SelectNodes("//set_value[@name='global.`$TSE_GalaxyCandidateBuilder' and @exact='`$_Ship']")).Count -eq 1) 'only one builder assignment exists'
Assert-True ($helperText.Contains('global.$TSEGetTradesubscriptionsToUpdateAlreadyProcessing != $_Ship')) 'additional workers cannot enter a concurrent rebuild'
$coordinatorWait = $helper.SelectSingleNode("//label[@name='RESUME_LBL']/following-sibling::do_if[1]//wait[@exact='`$COORDINATOR_WAIT']")
Assert-True ($null -ne $coordinatorWait -and -not ($helperText -match '<wait exact="1ms"\s*/>\s*<resume label="RESUME_LBL"')) 'coordinator waiting is bounded and not a 1 ms polling loop'
$buildYield = $helper.SelectSingleNode("//do_for_each[@name='`$_BuildSector' and @in='`$_BuildSectors']/wait[@exact='`$CACHE_BUILD_YIELD']")
Assert-True ($null -ne $buildYield) 'incremental sector work has an explicit scheduler yield'
Assert-True ($null -ne $helper.SelectSingleNode("//param[@name='CACHE_BUILD_YIELD' and @default='1s']") -and
    $null -ne $helper.SelectSingleNode("//param[@name='COORDINATOR_WAIT' and @default='5s']") -and
    $null -ne $helper.SelectSingleNode("//param[@name='CACHE_BUILD_TIMEOUT' and @default='5min']")) 'cache rebuild and waiting work are paced across game ticks with recovery margin'
foreach ($state in @('invalid', 'building', 'ready')) {
    Assert-True ($helperText.Contains("'$state'") -and
        ($state -ne 'invalid' -or $mdText.Contains("'invalid'"))) "cache state $state is represented or initialized"
}

# 7-9: recovery, save/load, and end validation.
Assert-True ($helperText.Contains('$_CoordinatorOwner.exists') -and
    $helperText.Contains('$CACHE_BUILD_TIMEOUT') -and
    $helperText.Contains('defaultorder.id') -and
    $helperText.Contains('<on_abort>')) 'destroyed, departed, timed-out, and aborted owners are recoverable'
Assert-True ($mdText.Contains('global.$TSE_GalaxyCandidateEpoch + 1') -and
    $mdText.Contains('global.$TSE_GalaxyCandidateState') -and
    $mdText.Contains('exact="[]"') -and
    $helperText.Contains('$_BuildEpoch')) 'save/load invalidates incomplete state with an epoch guard'
Assert-True ($helperText.Contains('$_CachedSubscriptionTarget.hastradesubscription') -and
    $helperText.Contains('$_Ship.ishostileto') -and
    $updateText.Contains('ValidateTarget')) 'cache entries remain subject to current target validation'
$cachedTargetGuard = $helper.SelectSingleNode("//do_for_each[@name='`$_CachedStation' and @in='`$_CandidateSnapshot']/do_if[@value='not `$_CachedSubscriptionTarget.exists']")
$cachedTargetSubscription = $helper.SelectSingleNode("//do_for_each[@name='`$_CachedStation' and @in='`$_CandidateSnapshot']/do_if[@value='`$_CachedSubscriptionTarget.hastradesubscription']")
$cachedWreckGuard = $helper.SelectSingleNode("//do_for_each[@name='`$_CachedStation' and @in='`$_CandidateSnapshot']/do_if[@value='`$_CachedStation.iswreck']")
Assert-True ($null -ne $cachedTargetGuard -and
    $null -ne $cachedTargetSubscription -and
    $null -ne $cachedWreckGuard -and
    -not $helperText.Contains('not $_CachedSubscriptionTarget.exists or $_CachedSubscriptionTarget.hastradesubscription')) 'optional cached subscription targets are guarded before property lookup'
Assert-True ($updateText.Contains('$STATION.exists and not @$STATION.iswreck')) 'wrecked targets are rejected again by final update validation'

# 10-14: per-ship policy and reservations.
Assert-True ($helperText.Contains('blacklisttype.sectoractivity') -and
    $helperText.Contains('blacklisttype.sectortravel') -and
    $helperText.Contains('blacklisttype.objectactivity')) 'all effective ship blacklists remain active'
foreach ($category in @(
    '$CONSTRUCTION_SITES', '$WHARFS', '$SHIPYARDS', '$EQUIPMENTDOCKS',
    '$TRADING_STATIONS', '$PIRATE_BASES', '$RECYCLING_FACILITIES',
    '$DEFENCE_STATIONS', '$FACTION_HEADQUARTERS', '$NON_SPECIAL_STATIONS'
)) {
    Assert-True ($helperText.Contains($category)) "station category $category remains ship-specific"
}
Assert-True ($helperText.Contains('accessgrantedto="$_Ship.owner"') -and
    $helperText.Contains('$_AccessibleSector != $_Sector')) 'sector access is revalidated per ship'
Assert-True ($helperText.Contains('useknownpath="true"') -and
    $helperText.Contains('$_PathDistance lt 0')) 'known-path checks remain mandatory'
Assert-True ($helperText.Contains('global.$TSE_SectorsBlacklistGroup') -and
    $helperText.Contains('global.$TSE_ShipsCurrentSectorTable')) 'sector reservations still prevent duplicate work'

# 15-20: invalid targets, empty fallback, and stagger.
Assert-True ($galaxyText.Contains("`$_UpdateResult == 'success' or `$_UpdateResult == 'already_current'") -and
    $galaxyText.Contains('remove_from_list name="global.$TSE_GalaxyCandidateStations"')) 'success removes the current target from the snapshot'
Assert-True ($helperText.Contains('not $_CachedStation.exists') -and
    $helperText.Contains('remove_from_list name="global.$TSE_GalaxyCandidateStations"')) 'destroyed cached stations are pruned'
Assert-True ($galaxyText.Contains('$_FoundStations.count == 0') -and
    $galaxyText.Contains('resume label="IDLE_LBL"')) 'no candidates enter the controlled idle fallback'
Assert-True (-not ($helperText -match '<wait exact="1ms"\s*/>\s*<resume')) 'no hot empty-search loop exists'
Assert-True ($galaxyText.Contains('abs($_Ship.seed) % 5') -and
    $galaxyText.Contains('$IDLE_TIME + $_WakeOffset')) 'Galaxy worker wakeups use a bounded stable offset'
Assert-True (-not ($galaxyText -match '\[\$IDLE_TIME,\s*[^\]]+\]\.max') -and
    -not ($galaxyText -match 'IDLE_TIME"\s+value="[0-9]+min')) 'configured idle time is not replaced by a large minimum'
Assert-True ($helperText.Contains('if @$_DefaultOrderParamRef.$IDLE_TIME then $_DefaultOrderParamRef.$IDLE_TIME else $CACHE_TTL') -and
    $helperText.Contains('$_CacheAge lt $_CacheTTL') -and
    -not $helperText.Contains('default="15s"')) 'cache reuse follows the effective configured idle interval'
$strictIdleDockSearch = $idle.SelectSingleNode("//do_if[@value='`$IDLE_DOCKING and not `$FAILED_DOCK']/do_if[@value='not `$_IdleDockAllowed and `$FIND_STATION']")
Assert-True ($null -ne $strictIdleDockSearch -and
    $null -ne $strictIdleDockSearch.SelectSingleNode("find_station[@space='player.galaxy' and @sortbygatedistancefrom='`$_Ship' and @sortlimit='`$IDLE_DOCK_CANDIDATE_LIMIT']") -and
    $null -eq $strictIdleDockSearch.SelectSingleNode("run_script[@name=`"'jp.lib.SortByEstimatedTravelTime'`"]") -and
    $null -ne $strictIdleDockSearch.SelectSingleNode(".//do_if[@value='`$_IdlePathDistance ge 0']/break")) 'strict idle docking uses gate-distance order and stops after the first fully valid station'
Assert-True ($null -ne $idle.SelectSingleNode("//param[@name='IDLE_DOCK_CANDIDATE_LIMIT' and @default='10']")) 'strict idle docking caps path checks to ten nearby candidates per idle cycle'
Assert-True ($idleText.Contains('[TSE-PERF] event=idle_dock') -and
    $idleText.Contains('candidates_checked=') -and
    $idleText.Contains('path_checks=')) 'idle docking reports bounded candidate work'

# 21-24: mode boundaries and retained contracts.
$sectorCacheNodes = $sector.SelectNodes("//*[contains(@name, 'GalaxyCandidate') or contains(@exact, 'WakeOffset')]")
Assert-True ($sectorCacheNodes.Count -eq 0 -and $helperText.Contains('<do_if value="$SECTOR == null">')) 'TSE-S remains outside the galaxy cache path'
Assert-True ($helperText.Contains("defaultorder.id == 'Assist'") -and
    $galaxyText.Contains('global.$TSE_GalaxyCandidateStations')) 'Mimic workers use the same coordinator contract'
foreach ($script in @($galaxy, $sector)) {
    Assert-True ($script.SelectNodes("//do_if[@value='not @`$_Ship.sector.exists']/wait[@exact='1s']").Count -eq 2) 'TSE waits through transient no-sector transitions before property access'
}
$idleManagerPath = Join-Path $repo 'mods\JP_ScriptLibrary\md\jp.ScriptLibrary.md.xml'
$idleManagerText = Get-Content -Raw -LiteralPath $idleManagerPath
Assert-True ($idleManagerText.Contains('$_Ship.orders.clone') -and
    $idleManagerText.Contains('<cancel_order order="$_Order"/>') -and
    -not ($idleManagerText -match 'SL_ManageIdleReturnHome_MD[\s\S]*?<cancel_all_orders')) 'Bugfix 008 selective idle cleanup remains intact'
$forbidden = '<(?:start_long_range_scan|set_scan_target|set_object_scanned|set_object_long_range_scanned|add_trade_subscription|clear_fog_of_war)\b'
Assert-True (-not (($galaxyText + $sectorText + $helperText + $updateText) -match $forbidden)) 'No-Scan and No-Reveal remain intact'

# 25: XML well-formedness was established by Read-Xml.
Assert-True ($null -ne $helper.aiscript -and $null -ne $galaxy.aiscript -and
    $null -ne $sector.aiscript -and $null -ne $update.aiscript -and
    $null -ne $idle.aiscript -and
    $null -ne $md.mdscript) 'all directly changed/reached XML files are well formed'

# Performance summary contract.
$requiredFields = @(
    'scan_generation=', 'scan_owner=', 'scan_start_time=', 'scan_end_time=',
    'sectors_considered=', 'sectors_accepted=', 'stations_considered=',
    'stations_stale=', 'path_checks=', 'travel_time_checks=',
    'candidates_returned=', 'cache_hit=', 'cache_miss=', 'cache_age=',
    'cache_ttl=', 'worker_count=', 'waiting_workers='
)
$performanceNodes = @($helper.SelectNodes("//debug_to_file[contains(@text, '[TSE-PERF]')]"))
Assert-True ($performanceNodes.Count -eq 2) 'exactly two bounded performance summary actions exist'
foreach ($field in $requiredFields) {
    Assert-True ($helperText.Contains($field)) "performance summary contains $field"
}
foreach ($performanceNode in $performanceNodes) {
    $placeholderIndexes = @([regex]::Matches($performanceNode.GetAttribute('text'), '%(\d+)') | ForEach-Object {
        [int] $_.Groups[1].Value
    })
    Assert-True (($placeholderIndexes | Measure-Object -Maximum).Maximum -le 9) 'performance summary uses only X4 single-digit positional placeholders'
}
$idlePerformanceNodes = @($idle.SelectNodes("//debug_to_file[contains(@text, '[TSE-PERF]')]"))
Assert-True ($idlePerformanceNodes.Count -eq 1) 'exactly one bounded idle-dock performance summary action exists'
$idlePlaceholderIndexes = @([regex]::Matches($idlePerformanceNodes[0].GetAttribute('text'), '%(\d+)') | ForEach-Object {
    [int] $_.Groups[1].Value
})
Assert-True (($idlePlaceholderIndexes | Measure-Object -Maximum).Maximum -le 9) 'idle-dock performance summary uses only X4 single-digit positional placeholders'

# 26-27: recursive XSD validation through the JDK validator.
$jshell = Get-Command jshell -ErrorAction SilentlyContinue
Assert-True ($null -ne $jshell) 'jshell is available for recursive Vanilla XSD validation'
$aiFiles = @($helperPath, $galaxyPath, $sectorPath, $updatePath, $idlePath)
$aiStatements = ($aiFiles | ForEach-Object {
    "validator.validate(new StreamSource(new File(`"$(ConvertTo-JavaPath $_)`")));"
}) -join [Environment]::NewLine
$java = @"
import javax.xml.XMLConstants;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.SchemaFactory;
import java.io.File;
try {
  var factory = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
  var schema = factory.newSchema(new File("$(ConvertTo-JavaPath $aiSchemaPath)"));
  var validator = schema.newValidator();
$aiStatements
  schema = factory.newSchema(new File("$(ConvertTo-JavaPath $mdSchemaPath)"));
  validator = schema.newValidator();
  validator.validate(new StreamSource(new File("$(ConvertTo-JavaPath $mdPath)")));
  System.out.println("XSD validation complete");
} catch (Exception exception) {
  exception.printStackTrace();
  System.exit(1);
}
/exit
"@
$javaOutput = $java | & $jshell.Source --feedback silent 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "AI/MD XSD validation failed:`n$($javaOutput -join [Environment]::NewLine)"
}
Assert-True (($javaOutput -join "`n").Contains('XSD validation complete')) 'AI-XSD and MD-XSD validation pass'

# 28-29: the established diff simulation and prior regression suite.
if (-not $SkipExistingRegressions) {
    $existing = Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'validate-*.ps1' |
        Where-Object { $_.Name -ne 'validate-tse-galaxy-performance.ps1' } |
        Sort-Object Name
    foreach ($script in $existing) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script.FullName
        Assert-True ($LASTEXITCODE -eq 0) "existing regression $($script.Name) passes"
    }
}

# 30-31: whitespace and commit-object checks.
& git -c core.autocrlf=false -C $repo diff --check
Assert-True ($LASTEXITCODE -eq 0) 'git diff --check passes'
if (-not $SkipGitCommitChecks) {
    & git -C $repo show --check --oneline --stat HEAD
    Assert-True ($LASTEXITCODE -eq 0) 'git show --check passes for optimization commit'
    & git -C $repo show --check --oneline --stat HEAD^
    Assert-True ($LASTEXITCODE -eq 0) 'git show --check passes for diagnostics commit'
}

Write-Host 'TSE Galaxy performance regression: PASS'
