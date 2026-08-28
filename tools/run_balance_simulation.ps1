[CmdletBinding()]
param(
    [ValidateSet('2', '3', '6', 'all')][string]$Players = 'all',
    [ValidateSet('legal_random', 'survival_greedy', 'score_greedy', 'balanced_greedy', 'all')][string]$Strategy = 'all',
    [ValidateRange(1, 10000)][int]$Matches = 108,
    [long]$Seed = 20260824,
    [Nullable[long]]$ReplaySeed = $null,
    [string]$ReplayMatch = '',
    [ValidateRange(0, 1000000)][int]$MatchIndex = 0,
    [ValidateRange(1, 3)][int]$MaxParallelGroups = 3,
    [string]$OutputDirectory = 'artifacts\balance',
    [string]$GodotPath = $env:GODOT4_CONSOLE
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = 'F:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw '未找到 Godot 控制台程序；请通过 -GodotPath 或 GODOT4_CONSOLE 指定。'
}

$strategyValue = if ($Strategy -eq 'balanced_greedy') { 'survival_greedy' } else { $Strategy }
if (-not [string]::IsNullOrWhiteSpace($ReplayMatch)) {
    $replayPath = if ([IO.Path]::IsPathRooted($ReplayMatch)) { [IO.Path]::GetFullPath($ReplayMatch) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $ReplayMatch)) }
    $replayDocument = Get-Content -LiteralPath $replayPath -Raw | ConvertFrom-Json
    $replayConfig = if ($null -ne $replayDocument.match_config) { $replayDocument.match_config } else { $replayDocument }
    $Players = [string]$replayConfig.player_count
    $strategyValue = [string]$replayConfig.strategy
    $MatchIndex = [int]$replayConfig.match_index
}
$playerCounts = if ($Players -eq 'all') { @('2', '3', '6') } else { @($Players) }
$strategies = if ($strategyValue -eq 'all') { @('legal_random', 'survival_greedy', 'score_greedy') } else { @($strategyValue) }
if ($null -ne $ReplaySeed -and ($Players -eq 'all' -or $strategyValue -eq 'all')) {
    throw '重放单局时必须同时指定单一 -Players 和 -Strategy。'
}

$absoluteOutput = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
[IO.Directory]::CreateDirectory($absoluteOutput) | Out-Null
$groups = @(
    foreach ($playerCount in $playerCounts) {
        foreach ($strategyName in $strategies) {
            [pscustomobject]@{ PlayerCount = $playerCount; Strategy = $strategyName }
        }
    }
)

function Assert-HasProperty($value, [string]$propertyName, [string]$context) {
    if ($null -eq $value -or $null -eq $value.PSObject.Properties[$propertyName]) {
        throw "$context 缺少字段 $propertyName。"
    }
}

function Assert-SimulationReport($report, [int]$expectedPlayerCount, [string]$expectedStrategy, [string]$context) {
    if ($null -eq $report) { throw "$context 结果为空。" }
    foreach ($field in @(
        'startup_ready', 'started_player_count', 'player_count', 'players', 'turns',
        'result_present', 'game_on', 'result_turn_number', 'result_entry_count', 'end_reason',
        'aborted', 'abort_reason', 'contract_valid', 'validation_errors',
        'interaction_snapshot', 'modal_snapshot', 'map_choice_active', 'match_config',
        'strategy', 'match_index', 'world_seed', 'decision_seed'
    )) {
        Assert-HasProperty $report $field $context
    }
    if (-not [bool]$report.startup_ready) { throw "$context 未完成正式开局。" }
    if ([int]$report.player_count -ne $expectedPlayerCount -or [int]$report.started_player_count -ne $expectedPlayerCount) {
        throw "$context 玩家数与预期 $expectedPlayerCount 不符。"
    }
    if (@($report.players).Count -ne $expectedPlayerCount -or [int]$report.result_entry_count -ne $expectedPlayerCount) {
        throw "$context 最终玩家或结果条目数量不完整。"
    }
    if ([int]$report.turns -le 0 -or [int]$report.result_turn_number -le 0) { throw "$context 没有完成任何有效回合。" }
    if (-not [bool]$report.result_present -or @(0, 1, 2, 3) -notcontains [int]$report.end_reason) {
        throw "$context 缺少有效 GameResult 或结束原因。"
    }
    if ([bool]$report.game_on) { throw "$context 已产生结果但对局仍在运行。" }
    if ([bool]$report.aborted -or -not [bool]$report.contract_valid -or @($report.validation_errors).Count -gt 0 -or
        -not [string]::IsNullOrEmpty([string]$report.abort_reason)) {
        throw "$context 被标记为异常：$($report.abort_reason)"
    }
    if ([string]$report.strategy -ne $expectedStrategy) { throw "$context 策略字段不符：$($report.strategy)。" }
    if (@($report.interaction_snapshot.PSObject.Properties).Count -ne 0) { throw "$context 遗留活动交互。" }
    if ([int]$report.modal_snapshot.depth -ne 0 -or @($report.modal_snapshot.owners).Count -ne 0) { throw "$context 遗留模态租约。" }
    foreach ($field in @('tree_pause_depth', 'tree_pause_owners', 'tree_paused')) {
        Assert-HasProperty $report.modal_snapshot $field "$context.modal_snapshot"
    }
    if ([int]$report.modal_snapshot.tree_pause_depth -ne 0 -or @($report.modal_snapshot.tree_pause_owners).Count -ne 0) {
        throw "$context 遗留 SceneTree 暂停所有者。"
    }
    if ([bool]$report.modal_snapshot.tree_paused -and [bool]$report.game_on) {
        throw "$context 对局运行中遗留无主 SceneTree 暂停。"
    }
    if ([bool]$report.map_choice_active) { throw "$context 遗留地图选择状态。" }

    $config = $report.match_config
    foreach ($field in @('player_count', 'strategy', 'match_index', 'world_seed', 'decision_seed', 'locations', 'professions')) {
        Assert-HasProperty $config $field "$context.match_config"
    }
    if ([int]$config.player_count -ne [int]$report.player_count -or
        [string]$config.strategy -ne [string]$report.strategy -or
        [int]$config.match_index -ne [int]$report.match_index -or
        [long]$config.world_seed -ne [long]$report.world_seed -or
        [long]$config.decision_seed -ne [long]$report.decision_seed) {
        throw "$context 顶层字段与 match_config 不一致。"
    }
    if (@($config.locations).Count -ne $expectedPlayerCount -or @($config.locations | Select-Object -Unique).Count -ne $expectedPlayerCount -or
        @($config.professions).Count -ne $expectedPlayerCount -or @($config.professions | Select-Object -Unique).Count -ne $expectedPlayerCount) {
        throw "$context 地区或职业调度并非完整且同局唯一。"
    }
}

function Assert-SimulationReportSet([object[]]$reports, [int]$expectedCount, [int]$expectedPlayerCount, [string]$expectedStrategy, [int]$firstMatchIndex, [string]$context) {
    if ($reports.Count -ne $expectedCount) { throw "$context 应有 $expectedCount 局，实际为 $($reports.Count) 局。" }
    $identities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    for ($index = 0; $index -lt $reports.Count; $index++) {
        $report = $reports[$index]
        Assert-SimulationReport $report $expectedPlayerCount $expectedStrategy "$context 第$($index + 1)局"
        if ([int]$report.match_index -ne $firstMatchIndex + $index) {
            throw "$context 对局编号不连续：应为 $($firstMatchIndex + $index)，实际为 $($report.match_index)。"
        }
        $identity = '{0}|{1}|{2}' -f $report.player_count, $report.strategy, $report.match_index
        if (-not $identities.Add($identity)) { throw "$context 出现重复配置：$identity。" }
    }
}

function Test-GodotLogHasFailure([string]$text) {
    return $text -match '(?m)^(SCRIPT ERROR|ERROR):' -or
        $text -match '(?m)^WARNING: ObjectDB instances leaked at exit' -or
        $text -match '(?m)^WARNING: \d+ RIDs? of type .+ (was|were) leaked\.'
}

function Start-SimulationGroup($group) {
    $groupOutput = Join-Path $absoluteOutput "players-$($group.PlayerCount)\$($group.Strategy)"
    [IO.Directory]::CreateDirectory($groupOutput) | Out-Null
    # 每组启动前删掉唯一会被后续读取的结果文件；子进程若启动失败，旧报告不能
    # 被误认成这一次运行的产物。
    $staleMatches = Join-Path $groupOutput 'matches.json'
    if (Test-Path -LiteralPath $staleMatches) { Remove-Item -LiteralPath $staleMatches -Force }
    $arguments = @(
        '--quiet', '--headless', '--path', $projectRoot,
        'res://tools/balance_simulation_runner.tscn', '--',
        "--matches=$Matches", "--seed=$Seed", "--players=$($group.PlayerCount)",
        "--strategy=$($group.Strategy)", "--match-index=$MatchIndex", "--out=$groupOutput"
    )
    if ($null -ne $ReplaySeed) { $arguments += "--exact-seed=$ReplaySeed" }
    if (-not [string]::IsNullOrWhiteSpace($ReplayMatch)) {
        $resolvedReplay = if ([IO.Path]::IsPathRooted($ReplayMatch)) { [IO.Path]::GetFullPath($ReplayMatch) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $ReplayMatch)) }
        $arguments += "--replay-match=$resolvedReplay"
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($startInfo)
    return [pscustomobject]@{
        PlayerCount = $group.PlayerCount; Strategy = $group.Strategy; Output = $groupOutput
        Log = Join-Path $groupOutput 'simulation.log'; Process = $process
        Stdout = $process.StandardOutput.ReadToEndAsync(); Stderr = $process.StandardError.ReadToEndAsync()
    }
}

$failedRuns = @()
for ($offset = 0; $offset -lt $groups.Count; $offset += $MaxParallelGroups) {
    $last = [Math]::Min($offset + $MaxParallelGroups - 1, $groups.Count - 1)
    $runs = @($groups[$offset..$last] | ForEach-Object { Start-SimulationGroup $_ })
    foreach ($run in $runs) {
        $run.Process.WaitForExit()
        $stdout = $run.Stdout.GetAwaiter().GetResult()
        $stderr = $run.Stderr.GetAwaiter().GetResult()
        ($stdout + $stderr) | Set-Content -LiteralPath $run.Log -Encoding utf8
        if ($run.Process.ExitCode -ne 0 -or (Test-GodotLogHasFailure ($stdout + $stderr))) {
            $failedRuns += "$($run.PlayerCount) 人 $($run.Strategy)：$($run.Log)"
        }
        Write-Host "模拟分组完成：$($run.PlayerCount) 人 $($run.Strategy)"
        $run.Process.Dispose()
    }
}
if ($failedRuns.Count -gt 0) { throw "平衡模拟失败：`n$($failedRuns -join "`n")" }

$allMatches = @()
$expectedMatchesPerGroup = if ($null -ne $ReplaySeed -or -not [string]::IsNullOrWhiteSpace($ReplayMatch)) { 1 } else { $Matches }
$allIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$validatedGroupCount = 0
foreach ($group in $groups) {
    $matchPath = Join-Path $absoluteOutput "players-$($group.PlayerCount)\$($group.Strategy)\matches.json"
    if (-not (Test-Path -LiteralPath $matchPath)) { throw "缺少模拟结果：$matchPath" }
    $groupMatches = @(Get-Content -LiteralPath $matchPath -Raw | ConvertFrom-Json)
    Assert-SimulationReportSet $groupMatches $expectedMatchesPerGroup ([int]$group.PlayerCount) ([string]$group.Strategy) $MatchIndex "$($group.PlayerCount) 人 $($group.Strategy)"
    foreach ($report in $groupMatches) {
        $identity = '{0}|{1}|{2}' -f $report.player_count, $report.strategy, $report.match_index
        if (-not $allIdentities.Add($identity)) { throw "不同模拟分组出现重复配置：$identity。" }
    }
    $allMatches += $groupMatches
    $validatedGroupCount += 1
}
if ($validatedGroupCount -ne $groups.Count -or $allMatches.Count -ne $groups.Count * $expectedMatchesPerGroup) {
    throw "模拟分组或对局总数不完整：组 $validatedGroupCount/$($groups.Count)，局 $($allMatches.Count)/$($groups.Count * $expectedMatchesPerGroup)。"
}
ConvertTo-Json -InputObject @($allMatches) -Depth 100 | Set-Content -LiteralPath (Join-Path $absoluteOutput 'matches.json') -Encoding utf8
$allMatches | ForEach-Object {
    [pscustomobject]@{
        world_seed = $_.world_seed; decision_seed = $_.decision_seed; match_index = $_.match_index
        player_count = $_.player_count; strategy = $_.strategy; turns = $_.turns
        end_reason = $_.end_reason; aborted = $_.aborted; abort_reason = $_.abort_reason
        winners = (@($_.winners) -join '|')
    }
} | Export-Csv -LiteralPath (Join-Path $absoluteOutput 'matches.csv') -NoTypeInformation -Encoding utf8

$combinedMatches = Join-Path $absoluteOutput 'matches.json'
$combinedSummary = Join-Path $absoluteOutput 'summary.md'
$reportOutput = & $GodotPath --quiet --headless --path $projectRoot -s res://tools/build_balance_report.gd -- "--input=$combinedMatches" "--output=$combinedSummary" 2>&1
$reportText = $reportOutput -join "`n"
if ($LASTEXITCODE -ne 0 -or (Test-GodotLogHasFailure $reportText)) {
    throw "生成聚合平衡报告失败：`n$($reportOutput -join "`n")"
}
Write-Host "平衡模拟完成：$absoluteOutput"
