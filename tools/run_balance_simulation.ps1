[CmdletBinding()]
param(
    [ValidateSet('2', '3', '6', 'all')][string]$Players = 'all',
    [ValidateSet('legal_random', 'balanced_greedy', 'all')][string]$Strategy = 'all',
    [ValidateRange(1, 10000)][int]$Matches = 100,
    [long]$Seed = 20260824,
    [Nullable[long]]$ReplaySeed = $null,
    [ValidateRange(0, 1000000)][int]$MatchIndex = 0,
    [string]$OutputDirectory = 'artifacts\balance',
    [string]$GodotPath = $env:GODOT4_CONSOLE
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = 'F:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw '未找到 Godot 控制台程序；请通过 -GodotPath 或 GODOT4_CONSOLE 指定。'
}
$playerCounts = if ($Players -eq 'all') { @('2', '3', '6') } else { @($Players) }
$strategies = if ($Strategy -eq 'all') { @('legal_random', 'balanced_greedy') } else { @($Strategy) }
if ($null -ne $ReplaySeed -and ($Players -eq 'all' -or $Strategy -eq 'all')) {
    throw '重放单局时必须同时指定单一 -Players 和 -Strategy。'
}
$absoluteOutput = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
[System.IO.Directory]::CreateDirectory($absoluteOutput) | Out-Null

$runs = @()
foreach ($playerCount in $playerCounts) {
    foreach ($strategyName in $strategies) {
        $groupOutput = Join-Path $absoluteOutput "players-$playerCount\$strategyName"
        [System.IO.Directory]::CreateDirectory($groupOutput) | Out-Null
        $logPath = Join-Path $groupOutput 'simulation.log'
        $arguments = @(
            '--quiet', '--headless', '--path', $projectRoot,
            'res://tools/balance_simulation_runner.tscn', '--',
            "--matches=$Matches", "--seed=$Seed", "--players=$playerCount",
            "--strategy=$strategyName", "--match-index=$MatchIndex", "--out=$groupOutput"
        )
        if ($null -ne $ReplaySeed) { $arguments += "--exact-seed=$ReplaySeed" }
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GodotPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) }
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $runs += [pscustomobject]@{
            PlayerCount = $playerCount; Strategy = $strategyName; Output = $groupOutput; Log = $logPath
            Process = $process
            Stdout = $process.StandardOutput.ReadToEndAsync()
            Stderr = $process.StandardError.ReadToEndAsync()
        }
    }
}

$failedRuns = @()
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
if ($failedRuns.Count -gt 0) {
    throw "平衡模拟失败：`n$($failedRuns -join "`n")"
}

$allMatches = @()
foreach ($playerCount in $playerCounts) {
    foreach ($strategyName in $strategies) {
        $matchPath = Join-Path $absoluteOutput "players-$playerCount\$strategyName\matches.json"
        if (-not (Test-Path -LiteralPath $matchPath)) { throw "缺少模拟结果：$matchPath" }
        $allMatches += @(Get-Content -LiteralPath $matchPath -Raw | ConvertFrom-Json)
    }
}
$allMatches | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $absoluteOutput 'matches.json') -Encoding utf8
$allMatches | ForEach-Object {
    [pscustomobject]@{
        seed = $_.seed; match_index = $_.match_index; player_count = $_.player_count; strategy = $_.strategy; turns = $_.turns
        end_reason = $_.end_reason; aborted = $_.aborted; abort_reason = $_.abort_reason
        winners = (@($_.winners) -join '|')
    }
} | Export-Csv -LiteralPath (Join-Path $absoluteOutput 'matches.csv') -NoTypeInformation -Encoding utf8

$summary = @(
    '# Beta 平衡模拟报告', '',
    "- 对局数：$($allMatches.Count)",
    "- 异常终止：$(@($allMatches | Where-Object { $_.aborted }).Count)", '',
    '| 人数 | 策略 | 对局 | 平均回合 |', '|---:|---|---:|---:|'
)
foreach ($playerCount in $playerCounts) {
    foreach ($strategyName in $strategies) {
        $group = @($allMatches | Where-Object { $_.player_count -eq [int]$playerCount -and $_.strategy -eq $strategyName })
        $averageTurns = if ($group.Count -gt 0) { ($group | Measure-Object -Property turns -Average).Average } else { 0 }
        $summary += "| $playerCount | $strategyName | $($group.Count) | $([math]::Round($averageTurns, 2)) |"
    }
}
$summary += @('', '各人数和策略的职业、座位与 95% 置信区间详表保存在对应 `players-*\*\summary.md`。报告只记录现状，不自动调整玩法数值。')
$summary -join "`n" | Set-Content -LiteralPath (Join-Path $absoluteOutput 'summary.md') -Encoding utf8

Write-Host "平衡模拟完成：$absoluteOutput"
