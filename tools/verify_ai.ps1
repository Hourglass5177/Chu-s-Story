param(
    [string]$GodotPath = 'F:\godot 4.7.2\Godot_v4.7.2-stable_win64_console.exe',
    [switch]$SkipBeta,
    [switch]$SkipGui,
    [switch]$SkipCleanImport
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$artifactRoot = Join-Path $projectRoot 'artifacts'

function Invoke-AICheck([string]$Name, [string[]]$Arguments) {
    $logPath = Join-Path $artifactRoot ($Name + '.log')
    Write-Host "AI 验证：$Name"
    & $GodotPath @Arguments *> $logPath
    if ($LASTEXITCODE -ne 0) { throw "$Name 失败：$logPath" }
    if (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR|ERROR:' -Quiet) {
        throw "$Name 包含运行错误：$logPath"
    }
}

if (-not $SkipBeta) {
    & (Join-Path $PSScriptRoot 'verify_beta.ps1') -GodotPath $GodotPath -SkipCleanImport:$SkipCleanImport
    if ($LASTEXITCODE -ne 0) { throw 'Beta 验证失败。' }
}
& python (Join-Path $PSScriptRoot 'summarize_ai_validation.py') --freeze-code
if ($LASTEXITCODE -ne 0) { throw '无法记录 AI 验证代码快照。' }
foreach ($offset in @(0, 324, 648)) {
    Invoke-AICheck "ai-normal-final-$offset" @('--headless', '--fixed-fps', '1000', '--path', $projectRoot,
        'res://tools/ai_simulation_runner.tscn', '--', '--matches=324', "--offset=$offset",
        "--output=res://artifacts/ai-normal-final-$offset.json")
}
foreach ($baseline in @(0, 1, 2)) {
    Invoke-AICheck "ai-baseline-final-$baseline" @('--headless', '--fixed-fps', '1000', '--path', $projectRoot,
        'res://tools/ai_simulation_runner.tscn', '--', '--matches=108', "--baseline=$baseline",
        "--output=res://artifacts/ai-baseline-final-$baseline.json")
}
& python (Join-Path $PSScriptRoot 'summarize_ai_validation.py')
if ($LASTEXITCODE -ne 0) { throw 'AI 批次配置或结果校验失败。' }
if (-not $SkipGui) {
    Invoke-AICheck 'ai-gui-final' @('--path', $projectRoot, '--resolution', '1280x800', 'res://tools/ai_gui_review.tscn')
    Invoke-AICheck 'ai-gui-interactions-final' @('--path', $projectRoot, '--resolution', '1280x800', 'res://tools/ai_interaction_gui_review.tscn')
}
Write-Host '普通 AI 验证通过：972 局正式批次，324 局旧策略轮换对照。'
