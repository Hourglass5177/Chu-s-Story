[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath = Join-Path $projectRoot 'arts\游戏指南\实机截图\v1\对局全景.png'
$outputRoot = Join-Path $projectRoot 'arts\游戏指南\实机截图\v2'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "缺少游戏指南实机截图：$sourcePath"
}
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null

$crops = @(
    @{ Name = '玩家信息近景.png'; X = 18; Y = 22; Width = 462; Height = 1464 },
    @{ Name = '初始资源近景.png'; X = 26; Y = 820; Width = 446; Height = 664 },
    @{ Name = '阶段信息近景.png'; X = 430; Y = 0; Width = 1160; Height = 190 },
    @{ Name = '地图近景.png'; X = 490; Y = 178; Width = 1032; Height = 708 },
    @{ Name = '信息操作近景.png'; X = 455; Y = 908; Width = 1090; Height = 602 },
    @{ Name = '手牌计分近景.png'; X = 1578; Y = 96; Width = 910; Height = 1400 },
    @{ Name = '地图与提示近景.png'; X = 448; Y = 170; Width = 1112; Height = 1340 }
)

$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
try {
    foreach ($crop in $crops) {
        $rect = [System.Drawing.Rectangle]::new(
            [int]$crop.X,
            [int]$crop.Y,
            [int]$crop.Width,
            [int]$crop.Height
        )
        if ($rect.Right -gt $source.Width -or $rect.Bottom -gt $source.Height) {
            throw "裁切区域超出源图：$($crop.Name) $rect"
        }
        $image = $source.Clone($rect, $source.PixelFormat)
        try {
            $target = Join-Path $outputRoot ([string]$crop.Name)
            $image.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Host "已生成 $target"
        }
        finally {
            $image.Dispose()
        }
    }
}
finally {
    $source.Dispose()
}
