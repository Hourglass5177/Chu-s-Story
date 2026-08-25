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

function Start-SimulationGroup($group) {
    $groupOutput = Join-Path $absoluteOutput "players-$($group.PlayerCount)\$($group.Strategy)"
    [IO.Directory]::CreateDirectory($groupOutput) | Out-Null
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
        if ($run.Process.ExitCode -ne 0 -or ($stdout + $stderr) -match '(?m)^(SCRIPT ERROR|ERROR):') {
            $failedRuns += "$($run.PlayerCount) 人 $($run.Strategy)：$($run.Log)"
        }
        Write-Host "模拟分组完成：$($run.PlayerCount) 人 $($run.Strategy)"
        $run.Process.Dispose()
    }
}
if ($failedRuns.Count -gt 0) { throw "平衡模拟失败：`n$($failedRuns -join "`n")" }

$allMatches = @()
foreach ($group in $groups) {
    $matchPath = Join-Path $absoluteOutput "players-$($group.PlayerCount)\$($group.Strategy)\matches.json"
    if (-not (Test-Path -LiteralPath $matchPath)) { throw "缺少模拟结果：$matchPath" }
    $allMatches += @(Get-Content -LiteralPath $matchPath -Raw | ConvertFrom-Json)
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
if ($LASTEXITCODE -ne 0 -or ($reportOutput -join "`n") -match '(?m)^(SCRIPT ERROR|ERROR):') {
    throw "生成聚合平衡报告失败：`n$($reportOutput -join "`n")"
}
Write-Host "平衡模拟完成：$absoluteOutput"
