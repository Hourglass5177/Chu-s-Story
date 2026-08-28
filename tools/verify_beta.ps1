[CmdletBinding()]
param(
    [string]$GodotPath = $env:GODOT4_CONSOLE,
    [switch]$AllowOpenEditor,
    [switch]$SkipCleanImport
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$artifactDir = Join-Path $projectRoot 'artifacts\verify'
[System.IO.Directory]::CreateDirectory($artifactDir) | Out-Null

function Resolve-GodotConsole([string]$candidate) {
    $candidates = @(
        $candidate,
        $env:GODOT,
        'F:\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($item in $candidates) {
        if (Test-Path -LiteralPath $item -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($item)
        }
    }
    foreach ($commandName in @('godot4_console', 'godot4', 'godot')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    throw '未找到 Godot 控制台程序。请通过 -GodotPath 或 GODOT4_CONSOLE 指定 Godot 4.6.2 console 可执行文件。'
}

$ExpectedGutErrorLines = @(
    'ERROR: InteractionCoordinator: second 尝试在 first 仍等待时开启新交互。',
    'ERROR: 游戏指南目录格式无效：Expected key（第0行）'
)

function Assert-NoUnexpectedGodotErrors([string]$name, [string[]]$lines, [string]$logPath) {
    $unexpected = @()
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        $isError = $trimmed -match '^(SCRIPT ERROR|ERROR):'
        $isLeakWarning = $trimmed -match '^WARNING: ObjectDB instances leaked at exit' -or
            $trimmed -match '^WARNING: \d+ RIDs? of type .+ (was|were) leaked\.'
        if (-not $isError -and -not $isLeakWarning) { continue }
        if ($name -eq 'gut' -and $ExpectedGutErrorLines -contains $trimmed) { continue }
        $unexpected += $trimmed
    }
    if ($unexpected.Count -gt 0) {
        throw "步骤 $name 出现未列入白名单的 Godot 运行错误：`n$($unexpected -join "`n")`n日志：$logPath"
    }
}

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
    if ([int]$report.turns -le 0 -or [int]$report.result_turn_number -le 0) {
        throw "$context 没有完成任何有效回合。"
    }
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
    if ([int]$report.modal_snapshot.depth -ne 0 -or @($report.modal_snapshot.owners).Count -ne 0) {
        throw "$context 遗留模态租约。"
    }
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

function Invoke-GodotStep([string]$name, [string[]]$arguments) {
    $logPath = Join-Path $artifactDir ($name + '.log')
    $output = & $script:GodotConsole @arguments 2>&1 | Tee-Object -FilePath $logPath
    if ($LASTEXITCODE -ne 0) {
        throw "步骤 $name 失败，退出码 $LASTEXITCODE。日志：$logPath"
    }
    $lines = @($output | ForEach-Object { $_.ToString() })
    # GUT 的 assert_push_error 会把预期错误保留在原始日志中，但只允许上方两条
    # 精确消息；其余 ERROR（包括退出资源泄漏）一律阻止验证通过。
    Assert-NoUnexpectedGodotErrors $name $lines $logPath
    return $lines
}

$GodotConsole = Resolve-GodotConsole $GodotPath
$versionText = (& $GodotConsole --version 2>&1 | Out-String).Trim()
if ($versionText -notmatch '^4\.6\.2') {
    throw "需要 Godot 4.6.2，当前为：$versionText"
}

$normalizedProjectRoot = $projectRoot.Replace('\', '/')
$openEditors = Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
        $commandLine = [string]$_.CommandLine
        $normalizedCommandLine = $commandLine.Replace('\', '/')
        $normalizedCommandLine.IndexOf($normalizedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $normalizedCommandLine -notmatch '(?i)(^|\s)--headless(\s|$)'
    }
if ($openEditors -and -not $AllowOpenEditor) {
    throw '检测到当前 Godot 编辑器正在占用本项目。请关闭编辑器后重试，或明确使用 -AllowOpenEditor（将跳过清理导入）。'
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $pythonCommand) {
    throw '未找到 Python，无法校验数字版游戏指南生成结果。'
}
& $pythonCommand.Source (Join-Path $projectRoot 'tools\build_game_guide_catalog.py') --check
if ($LASTEXITCODE -ne 0) {
    throw '数字版游戏指南源稿与运行时目录不同步。请重新运行 tools/build_game_guide_catalog.py。'
}

if (-not $SkipCleanImport -and -not $openEditors) {
    $cachePath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot '.godot'))
    if ($cachePath.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $cachePath)) {
        Remove-Item -LiteralPath $cachePath -Recurse -Force
    }
}

Invoke-GodotStep 'import' @('--headless', '--path', $projectRoot, '--editor', '--quit') | Out-Null
Invoke-GodotStep 'main-scene' @('--headless', '--path', $projectRoot, '--quit-after', '2') | Out-Null
$frontendSessionOutput = Invoke-GodotStep 'frontend-session-e2e' @(
    '--headless', '--path', $projectRoot, 'res://tools/frontend_session_e2e_runner.tscn'
)
if (($frontendSessionOutput -join "`n") -notmatch '(?m)^FRONTEND_SESSION_E2E: PASS\s*$') {
    throw '真实前端会话 E2E 未报告明确成功标记。'
}
$gutOutput = Invoke-GodotStep 'gut' @('--headless', '--path', $projectRoot, '-s', 'addons/gut/gut_cmdln.gd', '-gdir=res://tests', '-gexit')
$gutText = $gutOutput -join "`n"
$testMatch = [regex]::Match($gutText, '(?m)^Tests\s+(\d+)\s*$')
if (-not $testMatch.Success -or [int]$testMatch.Groups[1].Value -le 0) {
    throw 'GUT 未报告实际执行的测试数量；拒绝把零测试当作成功。'
}
if ($gutText -notmatch 'All tests passed!' -or $gutText -match '(?m)^Failing Tests\s+[1-9]\d*') {
    throw 'GUT 未全部通过。'
}

$smokeRoot = Join-Path $projectRoot 'artifacts\verify\simulation-smoke'
$matches = @()
$smokeGroupCount = 0
$allIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($playerCount in @(2, 3, 6)) {
	foreach ($strategyName in @('legal_random', 'survival_greedy', 'score_greedy')) {
        $groupDir = Join-Path $smokeRoot "players-$playerCount\$strategyName"
        $groupOutput = $groupDir.Replace('\', '/')
        [System.IO.Directory]::CreateDirectory($groupDir) | Out-Null
        $matchesPath = Join-Path $groupDir 'matches.json'
        if (Test-Path -LiteralPath $matchesPath) { Remove-Item -LiteralPath $matchesPath -Force }
        Invoke-GodotStep "simulation-smoke-$playerCount-$strategyName" @(
        '--quiet', '--headless', '--path', $projectRoot,
            'res://tools/balance_simulation_runner.tscn', '--',
            '--matches=1', "--players=$playerCount", "--strategy=$strategyName", "--out=$groupOutput"
        ) | Out-Null
        if (-not (Test-Path -LiteralPath $matchesPath)) { throw "${playerCount} 人 $strategyName 模拟冒烟未生成 matches.json。" }
        $groupMatches = @(Get-Content -LiteralPath $matchesPath -Raw | ConvertFrom-Json)
        Assert-SimulationReportSet $groupMatches 1 $playerCount $strategyName 0 "${playerCount} 人 $strategyName 模拟冒烟"
        $identity = '{0}|{1}|{2}' -f $groupMatches[0].player_count, $groupMatches[0].strategy, $groupMatches[0].match_index
        if (-not $allIdentities.Add($identity)) { throw "模拟冒烟出现跨组重复配置：$identity。" }
        $matches += $groupMatches
        $smokeGroupCount += 1
    }
}
if ($smokeGroupCount -ne 9 -or $allIdentities.Count -ne 9 -or $matches.Count -ne 9) {
	throw '模拟冒烟必须完成 2/3/6 人 × 三种策略共 9 局，且不得异常终止。'
}

Write-Host "Beta 验证通过：$($testMatch.Groups[1].Value) 项测试，9 局模拟冒烟。"
