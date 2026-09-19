[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$galaxyPath = Join-Path $repo 'mods\MSX4_TradeDataExplorer\aiscripts\MSX4_TradeDataExplorerG.xml'
$sectorPath = Join-Path $repo 'mods\MSX4_TradeDataExplorer\aiscripts\MSX4_TradeDataExplorerS.xml'
$updatePath = Join-Path $repo 'mods\MSX4_TradeDataExplorer\aiscripts\msx4.tde.UpdateTradeData.xml'

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

foreach ($entry in @(
    @{ Name = 'Galaxy'; Document = (Read-Xml $galaxyPath) },
    @{ Name = 'Sector'; Document = (Read-Xml $sectorPath) }
)) {
    $document = $entry.Document
    $queue = $document.SelectSingleNode("//do_while[@value='`$_RemainingStations.count']")
    Assert-True ($null -ne $queue) "$($entry.Name) behavior processes a mutable remaining-station queue"
    Assert-True ($null -ne $document.SelectSingleNode("//create_list[@name='`$_RemainingStations']/following-sibling::append_list_elements[@name='`$_RemainingStations' and @other='`$_FoundStations']")) "$($entry.Name) behavior seeds the queue from the filtered candidate list"
    Assert-True ($null -ne $queue.SelectSingleNode("set_value[@name='`$_CandidateStation' and @exact='`$_RemainingStations.{1}']") -and
        $null -ne $queue.SelectSingleNode("remove_from_list[@name='`$_RemainingStations' and @exact='`$_CandidateStation']")) "$($entry.Name) behavior consumes each queued candidate once"

    $rerank = $queue.SelectSingleNode("do_if[@value=`"`$_UpdateResult == 'success' and `$_RemainingStations.count gt 1`"]")
    Assert-True ($null -ne $rerank) "$($entry.Name) behavior re-ranks only after movement-producing success with alternatives remaining"
    Assert-True ($null -ne $rerank.SelectSingleNode("run_script[@name=`"'msx4.lib.SortByEstimatedTravelTime'`" and @result='`$_RemainingStations']/param[@name='LIST' and @value='`$_RemainingStations']")) "$($entry.Name) behavior ranks remaining stations from the ship's current position"
    Assert-True ($document.SelectNodes("//do_for_each[@name='`$_CandidateStation' and @in='`$_FoundStations']").Count -eq 0) "$($entry.Name) behavior no longer consumes the initial fixed order"
}

$update = Read-Xml $updatePath
Assert-True ($null -ne $update.SelectSingleNode("//actions[@name='ValidateTarget']//do_elseif[@value='`$_Station.hastradesubscription']/set_value[@name='`$_ValidationStatus' and @exact=`"'already_current'`"]")) 'final target validation still skips stations whose trade data became current'

Write-Host 'Nearest remaining station selection regression: PASS'
