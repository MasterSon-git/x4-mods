[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modsRoot = Join-Path $repoRoot 'mods'
$baselineCommit = '7afc74d2c94b537e0468019458578766e214d469'
$loggingFixCommit = 'f192803581ec60476b8b5252f87ff4ca9e91875c'
$postLoggingFunctionalPaths = @(
    'mods/MSX4_ScriptLibrary/md/msx4.ScriptLibrary.md.xml',
    'mods/MSX4_ScriptLibrary/aiscripts/msx4.lib.IdleReturnHome.xml',
    'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerS.xml',
    'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerG.xml',
    'mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.GetTradeDataToUpdate.xml',
    'mods/MSX4_TradeDataExplorer/aiscripts/msx4.tde.UpdateTradeData.xml',
    'mods/MSX4_TradeDataExplorer/libraries/experiences.xml',
    'mods/MSX4_TradeDataExplorer/aiscripts/order.assist.xml',
    'mods/MSX4_TradeDataExplorer/md/msx4.TradeDataExplorer.md.xml'
)
$aiSchemaPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/libraries/aiscripts.xsd'
$mdSchemaPath = Join-Path $repoRoot 'x4-reference/x4-9.00/base/libraries/md.xsd'

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

function ConvertTo-JavaPath {
    param([Parameter(Mandatory)] [string] $Path)

    return ([System.IO.Path]::GetFullPath($Path) -replace '\\', '/') -replace '"', '\"'
}

function ConvertTo-HistoricalModPath {
    param([Parameter(Mandatory)] [string] $Path)

    $result = $Path
    $result = $result -replace '^mods/MSX4_ScriptLibrary/', 'mods/JP_ScriptLibrary/'
    $result = $result -replace '^mods/MSX4_TradeDataExplorer/', 'mods/JP_TradeSubscriptionExplorer/'
    $result = $result -replace 'md/msx4\.ScriptLibrary\.md\.xml$', 'md/jp.ScriptLibrary.md.xml'
    $result = $result -replace 'md/msx4\.TradeDataExplorer\.md\.xml$', 'md/jp.TradeSubscriptionExplorer.md.xml'
    $result = $result -replace 'aiscripts/MSX4_TradeDataExplorerS\.xml$', 'aiscripts/JP_TradeSubscriptionExplorerS.xml'
    $result = $result -replace 'aiscripts/MSX4_TradeDataExplorerG\.xml$', 'aiscripts/JP_TradeSubscriptionExplorerG.xml'
    $result = $result -replace 'aiscripts/msx4\.tde\.GetTradeDataToUpdate\.xml$', 'aiscripts/jp.lib.TSE.GetTradesubscriptionsToUpdate.xml'
    $result = $result -replace 'aiscripts/msx4\.tde\.UpdateTradeData\.xml$', 'aiscripts/jp.lib.TSE.UpdateSubscription.xml'
    $result = $result -replace 'aiscripts/msx4\.lib\.', 'aiscripts/jp.lib.'
    return $result
}

function ConvertTo-CurrentModPath {
    param([Parameter(Mandatory)] [string] $Path)

    $result = $Path
    $result = $result -replace '^mods/JP_ScriptLibrary/', 'mods/MSX4_ScriptLibrary/'
    $result = $result -replace '^mods/JP_TradeSubscriptionExplorer/', 'mods/MSX4_TradeDataExplorer/'
    $result = $result -replace 'md/jp\.ScriptLibrary\.md\.xml$', 'md/msx4.ScriptLibrary.md.xml'
    $result = $result -replace 'md/jp\.TradeSubscriptionExplorer\.md\.xml$', 'md/msx4.TradeDataExplorer.md.xml'
    $result = $result -replace 'aiscripts/JP_TradeSubscriptionExplorerS\.xml$', 'aiscripts/MSX4_TradeDataExplorerS.xml'
    $result = $result -replace 'aiscripts/JP_TradeSubscriptionExplorerG\.xml$', 'aiscripts/MSX4_TradeDataExplorerG.xml'
    $result = $result -replace 'aiscripts/jp\.lib\.TSE\.GetTradesubscriptionsToUpdate\.xml$', 'aiscripts/msx4.tde.GetTradeDataToUpdate.xml'
    $result = $result -replace 'aiscripts/jp\.lib\.TSE\.UpdateSubscription\.xml$', 'aiscripts/msx4.tde.UpdateTradeData.xml'
    $result = $result -replace 'aiscripts/jp\.lib\.', 'aiscripts/msx4.lib.'
    return $result
}

function Test-DebugGuard {
    param([Parameter(Mandatory)] [System.Xml.XmlNode] $Node)

    $ancestor = $Node.ParentNode
    while ($null -ne $ancestor) {
        if ($ancestor.NodeType -eq [System.Xml.XmlNodeType]::Element -and
            $ancestor.LocalName -in @('do_if', 'do_elseif') -and
            $ancestor.GetAttribute('value') -match '(?:\$DEBUG|TDETraceDebug|\.?\$DEBUG).*gt 0') {
            return $true
        }
        $ancestor = $ancestor.ParentNode
    }
    return $false
}

function Get-GitContent {
    param(
        [Parameter(Mandatory)] [string] $Revision,
        [Parameter(Mandatory)] [string] $Path
    )

    foreach ($candidate in @($Path, (ConvertTo-HistoricalModPath -Path $Path)) | Select-Object -Unique) {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'SilentlyContinue'
            $content = & git -C $repoRoot show "${Revision}:$candidate" 2>$null
            $gitExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($gitExitCode -eq 0) {
            return ($content -join [Environment]::NewLine)
        }
    }
    throw "Could not read $Path at $Revision."
}

function Get-ContractSignature {
    param([Parameter(Mandatory)] [System.Xml.XmlDocument] $Document)

    $parts = [System.Collections.Generic.List[string]]::new()
    $contractNodes = $Document.SelectNodes(
        "//*[self::label or self::return or self::wait or self::resume or self::run_script or " +
        "self::create_order or self::set_order_failed or self::set_order_syncpoint_reached or " +
        "self::cancel_all_orders or self::cancel_order]"
    )
    foreach ($node in $contractNodes) {
        $attributes = @(
            foreach ($attribute in $node.Attributes) {
                "$($attribute.Name)=$($attribute.Value -replace '\s+', ' ')"
            }
        ) -join ';'
        $parts.Add("$($node.LocalName)|$attributes")
    }
    return $parts
}

function Apply-XmlDiff {
    param(
        [Parameter(Mandatory)] [System.Xml.XmlDocument] $VanillaDocument,
        [Parameter(Mandatory)] [System.Xml.XmlDocument] $DiffDocument,
        [Parameter(Mandatory)] [string] $DiffPath
    )

    $result = [System.Xml.XmlDocument] $VanillaDocument.CloneNode($true)
    foreach ($operation in $DiffDocument.SelectNodes('/diff/*[@sel]')) {
        $selector = $operation.GetAttribute('sel')
        $matches = @($result.SelectNodes($selector))
        Assert-Condition ($matches.Count -eq 1) "$DiffPath selector must resolve exactly once while applying the diff, got $($matches.Count): $selector"
        $target = $matches[0]
        $children = @($operation.ChildNodes | Where-Object {
            $_.NodeType -in @([System.Xml.XmlNodeType]::Element, [System.Xml.XmlNodeType]::Comment)
        })

        switch ($operation.LocalName) {
            'add' {
                $position = $operation.GetAttribute('pos')
                if ($position -eq 'before') {
                    foreach ($child in $children) {
                        [void] $target.ParentNode.InsertBefore($result.ImportNode($child, $true), $target)
                    }
                }
                elseif ($position -eq 'after') {
                    $reference = $target
                    foreach ($child in $children) {
                        $inserted = $result.ImportNode($child, $true)
                        [void] $target.ParentNode.InsertAfter($inserted, $reference)
                        $reference = $inserted
                    }
                }
                else {
                    foreach ($child in $children) {
                        [void] $target.AppendChild($result.ImportNode($child, $true))
                    }
                }
            }
            'replace' {
                foreach ($child in $children) {
                    [void] $target.ParentNode.InsertBefore($result.ImportNode($child, $true), $target)
                }
                [void] $target.ParentNode.RemoveChild($target)
            }
            'remove' {
                [void] $target.ParentNode.RemoveChild($target)
            }
            default {
                throw "Unsupported diff operation '$($operation.LocalName)' in $DiffPath."
            }
        }
    }
    return $result
}

function Remove-DiagnosticXml {
    param([Parameter(Mandatory)] [System.Xml.XmlNode] $Parent)

    $children = @($Parent.ChildNodes)
    foreach ($child in $children) {
        if ($child.NodeType -in @(
            [System.Xml.XmlNodeType]::Whitespace,
            [System.Xml.XmlNodeType]::SignificantWhitespace,
            [System.Xml.XmlNodeType]::Comment
        )) {
            [void] $Parent.RemoveChild($child)
            continue
        }
        if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) {
            continue
        }

        $name = $child.GetAttribute('name')
        $groupName = $child.GetAttribute('groupname')
        $isDebugAction = $child.LocalName -in @('debug_to_file', 'debug_text')
        $isDiagnosticState = $name -match '^\$(?:_Trace|_(?:TSE|TDE)Trace|_(?:TSE|TDE)DefaultOrderParamRef|_Debug|_DefaultOrderParamRef|_ValidationReason)|^\$DEBUG$' -or
            $groupName -match '^\$(?:_Trace|_(?:TSE|TDE)Trace|_Debug)'
        $isDiagnosticFinder = $child.LocalName -match '^find_' -and $name -match 'Trace'

        if ($isDebugAction -or $isDiagnosticState -or $isDiagnosticFinder) {
            [void] $Parent.RemoveChild($child)
            continue
        }

        Remove-DiagnosticXml -Parent $child
        $elementChildren = @($child.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
        if ($elementChildren.Count -eq 0 -and $child.LocalName -in @('do_if', 'do_elseif', 'do_else', 'add', 'replace', 'init', 'on_abort')) {
            [void] $Parent.RemoveChild($child)
        }
    }
}

function Get-CanonicalXml {
    param([Parameter(Mandatory)] [System.Xml.XmlNode] $Node)

    if ($Node.NodeType -eq [System.Xml.XmlNodeType]::Document) {
        return Get-CanonicalXml -Node $Node.DocumentElement
    }
    if ($Node.NodeType -ne [System.Xml.XmlNodeType]::Element) {
        return ''
    }

    $attributes = @(
        $Node.Attributes |
            Sort-Object Name |
            ForEach-Object { "$($_.Name)=$($_.Value -replace '\s+', ' ');" }
    ) -join ''
    $children = @(
        $Node.ChildNodes |
            Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element } |
            ForEach-Object { Get-CanonicalXml -Node $_ }
    ) -join ''
    return "<$($Node.LocalName)|$attributes>$children</$($Node.LocalName)>"
}

function Get-TraceFieldMap {
    param([Parameter(Mandatory)] [System.Xml.XmlNode] $TraceNode)

    $text = $TraceNode.GetAttribute('text')
    $separator = $text.IndexOf("'.[")
    Assert-Condition ($separator -ge 0) 'Parameter trace must use a format list.'
    $template = $text.Substring(1, $separator - 1)
    $argumentText = $text.Substring($separator + 3)
    Assert-Condition ($argumentText.EndsWith(']')) 'Parameter trace format list is malformed.'
    $argumentText = $argumentText.Substring(0, $argumentText.Length - 1)

    $arguments = [System.Collections.Generic.List[string]]::new()
    $start = 0
    $depth = 0
    for ($index = 0; $index -lt $argumentText.Length; $index++) {
        switch ($argumentText[$index]) {
            '[' { $depth++ }
            ']' { $depth-- }
            ',' {
                if ($depth -eq 0) {
                    $arguments.Add($argumentText.Substring($start, $index - $start).Trim())
                    $start = $index + 1
                }
            }
        }
    }
    $arguments.Add($argumentText.Substring($start).Trim())

    $result = @{}
    foreach ($match in [regex]::Matches($template, '(?<![a-z0-9_])([a-z][a-z0-9_]*)=%([1-9])(?= |$)')) {
        $argumentIndex = [int] $match.Groups[2].Value - 1
        Assert-Condition ($argumentIndex -lt $arguments.Count) "Format placeholder %$($argumentIndex + 1) has no argument."
        $result[$match.Groups[1].Value] = $arguments[$argumentIndex]
    }
    return $result
}

$xmlFiles = @(Get-ChildItem -LiteralPath $modsRoot -Recurse -File -Filter '*.xml')
$documents = @{}
foreach ($file in $xmlFiles) {
    $documents[$file.FullName] = Read-XmlDocument -Path $file.FullName
}
Write-Output "1/20 XML well-formedness: OK ($($xmlFiles.Count) mod XML files)"

$traceNodes = @(
    foreach ($entry in $documents.GetEnumerator()) {
        foreach ($node in $entry.Value.SelectNodes("//*[@text and (contains(@text, '[MSX4-TDE-TRACE]') or contains(@text, '[MSX4-SLIB-TRACE]'))]")) {
            [pscustomobject]@{ Path = $entry.Key; Node = $node }
        }
    }
)
Assert-Condition ($traceNodes.Count -gt 0) 'At least one structured TDE trace must exist.'

foreach ($trace in $traceNodes) {
    $text = $trace.Node.GetAttribute('text')
    Assert-Condition ($text -match "^'\[(?:MSX4-TDE-AI|MSX4-TDE-MD|MSX4-SLIB-AI|MSX4-SLIB-MD)\] ' \+ player\.age \+ ' \*\*\* [A-Za-z0-9_.]+:' \+ '\[MSX4-(?:TDE|SLIB)-TRACE\] ") "$($trace.Path) has a trace without the required timestamp envelope."
    Assert-Condition ($text -notmatch '(\\n|\\r|[\r\n])') "$($trace.Path) has a multiline trace."
    Assert-Condition ($text -cmatch '^[\x00-\x7F]+$') "$($trace.Path) has a non-ASCII trace template."
    foreach ($key in @('source=', 'ship=', 'phase=')) {
        Assert-Condition ($text.Contains($key)) "$($trace.Path) has a trace without mandatory key $key."
    }
    foreach ($field in @('result', 'reason')) {
        if ($text -match "(?:^| )${field}=([A-Za-z][A-Za-z0-9_-]*)") {
            Assert-Condition ($Matches[1] -cmatch '^[a-z0-9_]+$') "$($trace.Path) has a non-snake_case fixed $field value '$($Matches[1])'."
        }
    }

    if ($trace.Path -match '[\\/]aiscripts[\\/]') {
        Assert-Condition (Test-DebugGuard -Node $trace.Node) "$($trace.Path) contains an AI trace outside an effective DEBUG > 0 guard."
    }
    elseif ($trace.Path -match '[\\/]md[\\/]') {
        $isSessionMarker = $text -match 'phase=session event=session_start'
        Assert-Condition ($trace.Node.LocalName -eq 'debug_text' -or ($isSessionMarker -and $trace.Node.LocalName -eq 'debug_to_file')) "$($trace.Path) must use debug_text except for the single session marker."
        if ($trace.Node.LocalName -eq 'debug_text') {
            Assert-Condition ($trace.Node.GetAttribute('filter') -eq 'scripts') "$($trace.Path) has an MD trace without filter=scripts."
        }
        Assert-Condition ($null -eq $trace.Node.SelectSingleNode("ancestor::cue[@checkinterval]")) "$($trace.Path) has an MD trace in a polling cue."
    }
}
Write-Output "2-8/20 trace prefix, line shape, ASCII, mandatory keys, AI guards and MD lifecycle placement: OK ($($traceNodes.Count) trace points)"

$ambiguousPlaceholders = @(
    foreach ($trace in $traceNodes) {
        if ($trace.Node.GetAttribute('text') -match '%[1-9][0-9]') {
            "$($trace.Path): $($trace.Node.GetAttribute('text'))"
        }
    }
)
Assert-Condition ($ambiguousPlaceholders.Count -eq 0) ("Ambiguous multi-digit format placeholders remain: " + ($ambiguousPlaceholders -join ' | '))

$optionalContextDiffs = @(
    Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/aiscripts/order.dock.xml'
    Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/aiscripts/order.dock.wait.xml'
    Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/aiscripts/order.move.follow.xml'
)
foreach ($path in $optionalContextDiffs) {
    $document = $documents[$path]
    foreach ($guard in $document.SelectNodes("//do_if[descendant::debug_to_file[contains(@text, '[MSX4-SLIB-TRACE]')] or descendant::debug_text[contains(@text, '[MSX4-SLIB-TRACE]')]]")) {
        $value = $guard.GetAttribute('value')
        if ($value -match '\$MSX4_IDLE_RETURN_HOME') {
            Assert-Condition ($value -match '@\$MSX4_IDLE_RETURN_HOME') "$path has an unsafe optional MSX4_IDLE_RETURN_HOME trace guard: $value"
        }
        if ($value -match '\$_TDETraceDebug') {
            Assert-Condition ($value -match '@\$_TDETraceDebug') "$path has an unsafe optional TDETraceDebug guard: $value"
        }
    }
    foreach ($trace in $document.SelectNodes("//*[self::debug_to_file or self::debug_text][contains(@text, '[MSX4-SLIB-TRACE]')]")) {
        $safeIdleGuard = $trace.SelectSingleNode("ancestor::do_if[contains(@value, '@`$MSX4_IDLE_RETURN_HOME')]")
        Assert-Condition ($null -ne $safeIdleGuard) "$path has a TDE trace without a safe optional idle-context guard."
    }
}
Write-Output 'Trace placeholders and optional TDE context: OK'

$assistPath = Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/aiscripts/order.assist.xml'
$assistDocument = $documents[$assistPath]
$expectedAssistParams = @(
    'OWNERLESS_SECTORS', 'WHARFS', 'SHIPYARDS', 'EQUIPMENTDOCKS',
    'TRADING_STATIONS', 'PIRATE_BASES', 'RECYCLING_FACILITIES',
    'DEFENCE_STATIONS', 'FACTION_HEADQUARTERS', 'NON_SPECIAL_STATIONS',
    'CONSTRUCTION_SITES', 'IDLE_TIME', 'IDLE_MOVE_TO', 'WHERE_TO_MOVE',
    'START_POSITION', 'IDLE_FOLLOW', 'WHO_TO_FOLLOW', 'IDLE_DOCKING',
    'FIND_STATION', 'WHERE_TO_DOCK', 'SHOW_MESSAGES', 'WRITE_TO_LOG',
    'ADD_ORDER_TAG', 'DEBUG'
)
$assistBranch = $assistDocument.SelectSingleNode("/diff/add/do_if[@value=`"`$orderdef.`$id == 'MSX4_TradeDataExplorerG'`"]")
Assert-Condition ($null -ne $assistBranch) 'The TDE-G Assist branch is missing.'

$createParams = @($assistBranch.SelectNodes("do_if[@value='`$createdefaultorder?']/create_order/param"))
$runParams = @($assistBranch.SelectNodes("do_else/run_script/param"))
$savedParams = @($assistBranch.SelectNodes("do_else/set_value[starts-with(@name, '`$orderdef.`$')]"))
Assert-Condition ($createParams.Count -eq 24) "Assist create path must copy 24 parameters, got $($createParams.Count)."
Assert-Condition ($runParams.Count -eq 24) "Assist run path must copy 24 parameters, got $($runParams.Count)."
Assert-Condition ($savedParams.Count -eq 24) "Assist saved-orderdef path must copy 24 parameters, got $($savedParams.Count)."
Assert-Condition ((@($createParams | ForEach-Object { $_.GetAttribute('name') }) -join "`n") -ceq ($expectedAssistParams -join "`n")) 'Assist create parameter names/order changed.'
Assert-Condition ((@($runParams | ForEach-Object { $_.GetAttribute('name') }) -join "`n") -ceq ($expectedAssistParams -join "`n")) 'Assist run parameter names/order changed.'
Assert-Condition ((@($savedParams | ForEach-Object { $_.GetAttribute('name') -replace '^\$orderdef\.\$', '' }) -join "`n") -ceq ($expectedAssistParams -join "`n")) 'Assist saved-orderdef parameter names/order changed.'

foreach ($parameter in $expectedAssistParams) {
    $createNode = $createParams | Where-Object { $_.GetAttribute('name') -eq $parameter }
    $runNode = $runParams | Where-Object { $_.GetAttribute('name') -eq $parameter }
    $savedNode = $savedParams | Where-Object { $_.GetAttribute('name') -eq "`$orderdef.`$$parameter" }
    Assert-Condition ($createNode.GetAttribute('value') -eq "`$orderdef.`$$parameter") "Assist create value for $parameter is shifted."
    if ($parameter -eq 'START_POSITION') {
        Assert-Condition ($runNode.GetAttribute('value') -eq '[this.ship.sector, this.ship.position]') 'Assist run START_POSITION must use the subordinate position.'
        Assert-Condition ($savedNode.GetAttribute('exact') -eq '[this.ship.sector, this.ship.position]') 'Assist saved START_POSITION must use the subordinate position.'
    }
    else {
        Assert-Condition ($runNode.GetAttribute('value') -eq "`$order.`$$parameter") "Assist run value for $parameter is shifted."
        Assert-Condition ($savedNode.GetAttribute('exact') -eq "`$order.`$$parameter") "Assist saved value for $parameter is shifted."
    }
}

$traceFieldToParam = [ordered]@{
    idle_time = 'IDLE_TIME'
    idle_move = 'IDLE_MOVE_TO'
    idle_follow = 'IDLE_FOLLOW'
    idle_dock = 'IDLE_DOCKING'
    where_to_move = 'WHERE_TO_MOVE'
    start_position = 'START_POSITION'
    who_to_follow = 'WHO_TO_FOLLOW'
    find_station = 'FIND_STATION'
    where_to_dock = 'WHERE_TO_DOCK'
    ownerless = 'OWNERLESS_SECTORS'
    wharfs = 'WHARFS'
    shipyards = 'SHIPYARDS'
    equipmentdocks = 'EQUIPMENTDOCKS'
    trading_stations = 'TRADING_STATIONS'
    pirate_bases = 'PIRATE_BASES'
    recycling = 'RECYCLING_FACILITIES'
    defence = 'DEFENCE_STATIONS'
    headquarters = 'FACTION_HEADQUARTERS'
    factories = 'NON_SPECIAL_STATIONS'
    construction = 'CONSTRUCTION_SITES'
    show_messages = 'SHOW_MESSAGES'
    write_to_log = 'WRITE_TO_LOG'
    add_order_tag = 'ADD_ORDER_TAG'
    debug = 'DEBUG'
}
foreach ($pathName in @('create', 'run')) {
    $parameterTraces = @($assistBranch.SelectNodes(".//debug_to_file[contains(@text, 'event=parameter_group') and contains(@text, 'path=$pathName')]"))
    Assert-Condition ($parameterTraces.Count -eq 5) "Assist $pathName path must use five unambiguous parameter trace lines."
    $fieldMap = @{}
    foreach ($trace in $parameterTraces) {
        foreach ($entry in (Get-TraceFieldMap -TraceNode $trace).GetEnumerator()) {
            if ($entry.Key -ne 'ship') {
                Assert-Condition (-not $fieldMap.ContainsKey($entry.Key)) "Assist $pathName trace duplicates field $($entry.Key)."
                $fieldMap[$entry.Key] = $entry.Value
            }
        }
    }
    Assert-Condition ($fieldMap.Count -eq 24) "Assist $pathName trace must expose all 24 parameters, got $($fieldMap.Count)."
    foreach ($entry in $traceFieldToParam.GetEnumerator()) {
        Assert-Condition ($fieldMap.ContainsKey($entry.Key)) "Assist $pathName trace is missing field $($entry.Key)."
        $expectedExpression = if ($pathName -eq 'create') {
            "`$orderdef.`$$($entry.Value)"
        }
        elseif ($entry.Value -eq 'START_POSITION') {
            '[this.ship.sector, this.ship.position]'
        }
        else {
            "`$order.`$$($entry.Value)"
        }
        Assert-Condition ($fieldMap[$entry.Key] -eq $expectedExpression) "Assist $pathName trace field $($entry.Key) is mapped to '$($fieldMap[$entry.Key])', expected '$expectedExpression'."
    }
}
Write-Output 'Assist parameter contract: OK (24 run/create/saved values and trace fields)'

$diagnosticFinders = @(
    foreach ($entry in $documents.GetEnumerator()) {
        if ($entry.Key -match '[\\/]aiscripts[\\/]') {
            $entry.Value.SelectNodes("//*[self::find_sector or self::find_object or self::find_station or self::find_ship][contains(@name, 'Trace')]")
        }
    }
)
foreach ($finder in $diagnosticFinders) {
    Assert-Condition (Test-DebugGuard -Node $finder) 'A diagnostic finder is outside an effective DEBUG > 0 guard.'
}

$diagnosticCounters = @(
    foreach ($entry in $documents.GetEnumerator()) {
        if ($entry.Key -match '[\\/]aiscripts[\\/]') {
            $entry.Value.SelectNodes("//set_value[(contains(@name, 'Trace') or @name='`$_ValidationReason') and not(contains(@name, 'TDETraceDebug')) and not(contains(@name, 'TDEDefaultOrderParamRef'))]")
        }
    }
)
foreach ($counter in $diagnosticCounters) {
    Assert-Condition (Test-DebugGuard -Node $counter) 'An AI diagnostic variable or counter is evaluated outside an effective DEBUG > 0 guard.'
}
Write-Output "9/20 DEBUG=0 diagnostic finder/counter isolation: OK ($($diagnosticFinders.Count) finders)"

$globalTraceState = @(
    foreach ($entry in $documents.GetEnumerator()) {
        $entry.Value.SelectNodes("//*[@name or @groupname][contains(@name, 'global.$') or contains(@groupname, 'global.$')][contains(@name, 'Trace') or contains(@groupname, 'Trace')]")
    }
)
Assert-Condition ($globalTraceState.Count -eq 0) 'A new global trace state variable was introduced.'

$orderFiles = @(
    'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerS.xml',
    'mods/MSX4_TradeDataExplorer/aiscripts/MSX4_TradeDataExplorerG.xml'
)
foreach ($relativePath in $orderFiles) {
    $current = $documents[(Join-Path $repoRoot $relativePath)]
    $baseline = [System.Xml.XmlDocument]::new()
    $baseline.LoadXml((Get-GitContent -Revision $baselineCommit -Path $relativePath))

    $currentParams = @($current.SelectNodes('/aiscript/order/params/param') | ForEach-Object { $_.GetAttribute('name') })
    $baselineParams = @($baseline.SelectNodes('/aiscript/order/params/param') | ForEach-Object { $_.GetAttribute('name') })
    Assert-Condition (($currentParams -join "`n") -ceq ($baselineParams -join "`n")) "$relativePath introduced or removed an order parameter."

    $debugParam = $current.SelectSingleNode("/aiscript/order/params/param[@name='DEBUG']")
    Assert-Condition ($null -ne $debugParam) "$relativePath must retain the DEBUG parameter."
    Assert-Condition ($debugParam.GetAttribute('advanced') -eq 'true') "$relativePath DEBUG must remain advanced=true."
    Assert-Condition ($debugParam.GetAttribute('default') -match 'else 0$') "$relativePath DEBUG must remain off without saved settings."
}
Write-Output '10-11/20 no new UI setting; existing advanced DEBUG default retained: OK'

$allModText = ($xmlFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join [Environment]::NewLine
Assert-Condition ($allModText -notmatch '\[MSX4-TDE-(?:DIAG|AUDIT)\]') 'A retired MSX4-TDE-DIAG or MSX4-TDE-AUDIT marker was introduced.'

$diffText = (& git -C $repoRoot diff --find-renames=20% $baselineCommit --unified=0 -- 'mods/MSX4_TradeDataExplorer' 'mods/MSX4_ScriptLibrary' 'mods/MSX4_TradeDataExplorer' 'mods/MSX4_ScriptLibrary') -join [Environment]::NewLine
Assert-Condition ($LASTEXITCODE -eq 0) 'Could not obtain the logging diff.'
$addedLines = @(
    $diffText -split "\r?\n" |
        Where-Object { $_ -match '^\+(?!\+\+)' } |
        ForEach-Object { $_.Substring(1).Trim() }
)
$removedLines = @(
    $diffText -split "\r?\n" |
        Where-Object { $_ -match '^-(?!--)' } |
        ForEach-Object { $_.Substring(1).Trim() }
)

$unprovenSectorId = $addedLines | Where-Object {
    $_ -match '(?:\$_Sector|\$SECTOR|\.sector|Sector)\.idcode'
}
Assert-Condition (@($unprovenSectorId).Count -eq 0) 'An unproven Sector.idcode access was added.'

$forbiddenDiagnostics = $addedLines | Where-Object {
    $_ -match '<(?:scan_|reveal_|set_trade_subscription|add_trade_subscription|subscribe_)'
}
Assert-Condition (@($forbiddenDiagnostics).Count -eq 0) 'A scan, reveal, or permanent subscription action was added.'
Write-Output '12-14/20 retired markers, unproven Sector.idcode, scan/reveal/subscription additions: absent'

$diffMappings = @{
    'mods/MSX4_ScriptLibrary/aiscripts/order.dock.wait.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.dock.wait.xml'
    'mods/MSX4_ScriptLibrary/aiscripts/order.dock.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.dock.xml'
    'mods/MSX4_ScriptLibrary/aiscripts/order.move.follow.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.move.follow.xml'
    'mods/MSX4_TradeDataExplorer/aiscripts/order.assist.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.assist.xml'
    'mods/MSX4_TradeDataExplorer/aiscripts/order.dock.wait.xml' = 'x4-reference/x4-9.00/base/aiscripts/order.dock.wait.xml'
}

$changedCodePaths = @(
    & git -C $repoRoot diff $baselineCommit $loggingFixCommit --name-only -- 'mods/JP_TradeSubscriptionExplorer' 'mods/JP_ScriptLibrary' |
        Where-Object { $_ -match '\.xml$' } |
        ForEach-Object { ConvertTo-CurrentModPath -Path $_ }
)
foreach ($relativePath in $changedCodePaths) {
    $baselineText = Get-GitContent -Revision $baselineCommit -Path $relativePath
    $baseline = [System.Xml.XmlDocument]::new()
    $baseline.PreserveWhitespace = $true
    $baseline.LoadXml($baselineText)
    # Compare the two historical snapshots directly. Later functional changes,
    # including the independent MSX4 namespace, have their own permanent
    # regressions and intentionally differ from both snapshots.
    $loggingSnapshot = [System.Xml.XmlDocument]::new()
    $loggingSnapshot.PreserveWhitespace = $true
    $loggingSnapshot.LoadXml((Get-GitContent -Revision $loggingFixCommit -Path $relativePath))
    $current = $loggingSnapshot

    if ($current.DocumentElement.LocalName -eq 'diff') {
        Assert-Condition ($diffMappings.ContainsKey($relativePath)) "$relativePath has no Vanilla mapping for functional comparison."
        $vanilla = Read-XmlDocument -Path (Join-Path $repoRoot $diffMappings[$relativePath])
        $baseline = Apply-XmlDiff -VanillaDocument $vanilla -DiffDocument $baseline -DiffPath "$relativePath at $baselineCommit"
        $current = Apply-XmlDiff -VanillaDocument $vanilla -DiffDocument $current -DiffPath $relativePath
    }

    Remove-DiagnosticXml -Parent $baseline
    Remove-DiagnosticXml -Parent $current
    $baselineSignature = Get-CanonicalXml -Node $baseline
    $currentSignature = Get-CanonicalXml -Node $current
    Assert-Condition ($baselineSignature -ceq $currentSignature) "$relativePath changed the functional XML tree after diagnostic elements were removed."
}

Write-Output "15/20 logging snapshot functional XML tree after removing diagnostics: unchanged from $baselineCommit"

$validationTempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tde-runtime-debug-validation-" + [guid]::NewGuid().ToString('N'))
[void] (New-Item -ItemType Directory -Path $validationTempRoot)
$simulatedAiFiles = @(
    foreach ($mapping in $diffMappings.GetEnumerator()) {
        $diffDocument = $documents[(Join-Path $repoRoot $mapping.Key)]
        $vanillaDocument = Read-XmlDocument -Path (Join-Path $repoRoot $mapping.Value)
        $applied = Apply-XmlDiff -VanillaDocument $vanillaDocument -DiffDocument $diffDocument -DiffPath $mapping.Key
        # XmlDocument.Save emits literal attribute CR/LF as character
        # references. Xerces preserves those references instead of applying
        # the whitespace normalization that the original Vanilla XML receives,
        # which can make an unchanged multi-line expression fail its pattern.
        # Normalize only line breaks, matching XML attribute parsing.
        foreach ($attribute in @($applied.SelectNodes('//@*'))) {
            if ($attribute.Value -match '[\r\n]') {
                $attribute.Value = $attribute.Value -replace '[\r\n]+', ' '
            }
        }
        $outputName = ($mapping.Key -replace '[^A-Za-z0-9._-]', '_') + '.xml'
        $outputPath = Join-Path $validationTempRoot $outputName
        $applied.Save($outputPath)
        $outputPath
    }
)

$completeAiFiles = @(
    foreach ($entry in $documents.GetEnumerator()) {
        if ($entry.Value.DocumentElement.LocalName -eq 'aiscript') {
            $entry.Key
        }
    }
) + $simulatedAiFiles
$mdFiles = @(
    Join-Path $repoRoot 'mods/MSX4_ScriptLibrary/md/msx4.ScriptLibrary.md.xml'
    Join-Path $repoRoot 'mods/MSX4_TradeDataExplorer/md/msx4.TradeDataExplorer.md.xml'
)
$jshell = Get-Command 'jshell' -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $jshell) 'jshell is required for recursive Vanilla XSD validation.'

$aiValidationStatements = ($completeAiFiles | Sort-Object | ForEach-Object {
    "  validator.validate(new StreamSource(new File(`"$(ConvertTo-JavaPath -Path $_)`")));"
}) -join [Environment]::NewLine
$mdValidationStatements = ($mdFiles | ForEach-Object {
    "  validator.validate(new StreamSource(new File(`"$(ConvertTo-JavaPath -Path $_)`")));"
}) -join [Environment]::NewLine
$javaValidation = @"
import javax.xml.XMLConstants;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.SchemaFactory;
import java.io.File;
try {
  var factory = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
  var aiSchema = factory.newSchema(new File("$(ConvertTo-JavaPath -Path $aiSchemaPath)"));
  var validator = aiSchema.newValidator();
$aiValidationStatements
  var mdSchema = factory.newSchema(new File("$(ConvertTo-JavaPath -Path $mdSchemaPath)"));
  validator = mdSchema.newValidator();
$mdValidationStatements
  System.out.println("XSD validation complete");
} catch (Exception exception) {
  exception.printStackTrace();
  System.exit(1);
}
/exit
"@
$javaOutput = $javaValidation | & $jshell.Source --feedback silent 2>&1
if ($LASTEXITCODE -ne 0) {
    $javaOutput | ForEach-Object { Write-Error $_ }
    throw 'AI/MD XSD validation failed.'
}
Write-Output "16-18/20 XML, AI XSD ($($completeAiFiles.Count) complete scripts), MD XSD (2 files): OK"
[System.IO.Directory]::Delete($validationTempRoot, $true)

foreach ($mapping in $diffMappings.GetEnumerator()) {
    $diffDocument = $documents[(Join-Path $repoRoot $mapping.Key)]
    $vanillaDocument = Read-XmlDocument -Path (Join-Path $repoRoot $mapping.Value)
    foreach ($operation in $diffDocument.SelectNodes('/diff/*[@sel]')) {
        $matches = @($vanillaDocument.SelectNodes($operation.GetAttribute('sel')))
        Assert-Condition ($matches.Count -eq 1) "$($mapping.Key) selector must resolve exactly once against Vanilla 9.00, got $($matches.Count): $($operation.GetAttribute('sel'))"
    }
}
Write-Output 'Diff selectors against Vanilla 9.00: OK (every selector exactly once)'

$existingRegressions = @(
    'validate-escape-sector-move.ps1',
    'validate-icon-paths.ps1',
    'validate-sector-access.ps1',
    'validate-md-groups.ps1',
    'validate-order-ready.ps1'
    'validate-cycle-idle-refinement.ps1'
    'validate-experience-skill-contract.ps1'
    'validate-runtime-visibility.ps1'
    'validate-log-session-format.ps1'
    'validate-hostile-station-filter.ps1'
)
foreach ($regression in $existingRegressions) {
    & (Join-Path $PSScriptRoot $regression) | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "$regression failed."
}
Write-Output "19/20 existing regressions: OK ($($existingRegressions.Count) scripts)"

$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'SilentlyContinue'
    $diffCheck = & git -c core.autocrlf=false -C $repoRoot diff $baselineCommit --check -- 2>&1
    $gitExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
Assert-Condition ($gitExitCode -eq 0) ("git diff --check failed: " + ($diffCheck -join ' | '))
Write-Output '20/20 git diff --check: OK'
Write-Output 'Structured TDE runtime debug logging validation: PASS'
