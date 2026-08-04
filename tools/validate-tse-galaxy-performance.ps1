[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $repo 'mods\JP_TradeSubscriptionExplorer\aiscripts\jp.lib.TSE.GetTradesubscriptionsToUpdate.xml'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
    Write-Host "PASS: $Message"
}

[xml]$xml = Get-Content -Raw -LiteralPath $helper
$text = Get-Content -Raw -LiteralPath $helper

$requiredFields = @(
    'scan_generation=', 'scan_owner=', 'scan_start_time=', 'scan_end_time=',
    'sectors_considered=', 'sectors_accepted=', 'stations_considered=',
    'stations_stale=', 'path_checks=', 'travel_time_checks=',
    'candidates_returned=', 'cache_hit=', 'cache_miss=', 'cache_age=',
    'worker_count=', 'waiting_workers='
)

Assert-True ($null -ne $xml.aiscript) 'TSE candidate helper is well formed XML'
Assert-True (($text | Select-String -Pattern '\[TSE-PERF\]' -AllMatches).Matches.Count -eq 1) 'exactly one bounded performance summary exists'
foreach ($field in $requiredFields) {
    Assert-True ($text.Contains($field)) "performance summary contains $field"
}
Assert-True (-not ($text -match '\[TSE-PERF\][^"]*</debug_to_file>')) 'performance trace is one summary action, not a per-candidate block'

Write-Host 'TSE Galaxy performance diagnostics validation passed.'
