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

function Invoke-GodotStep([string]$name, [string[]]$arguments) {
    $logPath = Join-Path $artifactDir ($name + '.log')
    $output = & $script:GodotConsole @arguments 2>&1 | Tee-Object -FilePath $logPath
    if ($LASTEXITCODE -ne 0) {
        throw "步骤 $name 失败，退出码 $LASTEXITCODE。日志：$logPath"
    }
    $lines = @($output | ForEach-Object { $_.ToString() })
    # GUT 会把 assert_push_error 覆盖到的预期错误保留在原始日志中；
    # 该步骤由测试汇总和失败数判定，其他步骤仍执行严格错误扫描。
    if ($name -ne 'gut' -and $lines -match '^(SCRIPT ERROR|ERROR):') {
        throw "步骤 $name 出现 Godot 运行错误。日志：$logPath"
    }
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
foreach ($playerCount in @(2, 3, 6)) {
	foreach ($strategyName in @('legal_random', 'survival_greedy', 'score_greedy')) {
        $groupDir = Join-Path $smokeRoot "players-$playerCount\$strategyName"
        $groupOutput = $groupDir.Replace('\', '/')
        Invoke-GodotStep "simulation-smoke-$playerCount-$strategyName" @(
        '--quiet', '--headless', '--path', $projectRoot,
            'res://tools/balance_simulation_runner.tscn', '--',
            '--matches=1', "--players=$playerCount", "--strategy=$strategyName", "--out=$groupOutput"
        ) | Out-Null
        $matchesPath = Join-Path $groupDir 'matches.json'
        if (-not (Test-Path -LiteralPath $matchesPath)) { throw "${playerCount} 人 $strategyName 模拟冒烟未生成 matches.json。" }
        $matches += @(Get-Content -LiteralPath $matchesPath -Raw | ConvertFrom-Json)
    }
}
if ($matches.Count -ne 9 -or @($matches | Where-Object { $_.aborted }).Count -gt 0) {
	throw '模拟冒烟必须完成 2/3/6 人 × 三种策略共 9 局，且不得异常终止。'
}

Write-Host "Beta 验证通过：$($testMatch.Groups[1].Value) 项测试，9 局模拟冒烟。"
