[CmdletBinding()]
param(
    [string]$TooltipSource = 'F:\Temp\codex-clipboard-65e7d6ec-b379-4d10-a86a-651fe07c5c2d.png',
    [string]$InfoSource = 'F:\Temp\codex-clipboard-373d8a92-ae9f-445e-ae64-d1d58f9fe263.png',
    [string]$HandSource = 'F:\Temp\codex-clipboard-373d8a92-ae9f-445e-ae64-d1d58f9fe263.png'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$guideRoot = Join-Path $projectRoot 'arts\游戏指南\实机截图'
$sourceRoot = Join-Path $guideRoot 'v1'
$outputRoot = Join-Path $guideRoot 'v4'
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null

function Export-Crop {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height,
        [int]$CornerRadius = 0
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "缺少源图：$Source"
    }

    $bitmap = [System.Drawing.Bitmap]::FromFile($Source)
    try {
        $rect = [System.Drawing.Rectangle]::new($X, $Y, $Width, $Height)
        if ($rect.X -lt 0 -or $rect.Y -lt 0 -or $rect.Right -gt $bitmap.Width -or $rect.Bottom -gt $bitmap.Height) {
            throw "裁切区域超出源图：$Source -> $rect"
        }
        if ($CornerRadius -gt 0) {
            $crop = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $graphics = [System.Drawing.Graphics]::FromImage($crop)
            $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
            try {
                $diameter = $CornerRadius * 2
                $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
                $path.AddArc($Width - $diameter - 1, 0, $diameter, $diameter, 270, 90)
                $path.AddArc($Width - $diameter - 1, $Height - $diameter - 1, $diameter, $diameter, 0, 90)
                $path.AddArc(0, $Height - $diameter - 1, $diameter, $diameter, 90, 90)
                $path.CloseFigure()
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.SetClip($path)
                $graphics.DrawImage(
                    $bitmap,
                    [System.Drawing.Rectangle]::new(0, 0, $Width, $Height),
                    $rect,
                    [System.Drawing.GraphicsUnit]::Pixel
                )
                $crop.Save($Target, [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $path.Dispose()
                $graphics.Dispose()
                $crop.Dispose()
            }
        }
        else {
            $crop = $bitmap.Clone($rect, $bitmap.PixelFormat)
            try {
                $crop.Save($Target, [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $crop.Dispose()
            }
        }
    }
    finally {
        $bitmap.Dispose()
    }
    Write-Host "已生成 $Target"
}

function Copy-Original {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target
    )

    if (Test-Path -LiteralPath $Source -PathType Leaf) {
        Copy-Item -LiteralPath $Source -Destination $Target -Force
        Write-Host "已复制 $Target"
        return
    }
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
        throw "缺少用户原始截图：$Source"
    }
    Write-Host "源截图不在本机，保留已生成素材 $Target"
}

$modeSource = Join-Path $sourceRoot '模式选择.png'
$countSource = Join-Path $sourceRoot '人数设置.png'
$hudSource = Join-Path $sourceRoot '对局全景.png'

# 只保留模式与人数弹窗，不把首页背景当作规则内容。
Export-Crop -Source $modeSource -Target (Join-Path $outputRoot '模式选择弹窗.png') -X 460 -Y 360 -Width 1640 -Height 875 -CornerRadius 26
Export-Crop -Source $countSource -Target (Join-Path $outputRoot '人数设置弹窗.png') -X 650 -Y 330 -Width 1260 -Height 930 -CornerRadius 26

# “先看懂你的桌面”按阅读顺序分为四张语义独立的实机裁图。
Export-Crop -Source $hudSource -Target (Join-Path $outputRoot '界面-左侧玩家.png') -X 18 -Y 22 -Width 462 -Height 1464
Export-Crop -Source $hudSource -Target (Join-Path $outputRoot '界面-中央地图.png') -X 490 -Y 178 -Width 1032 -Height 708

if (Test-Path -LiteralPath $InfoSource -PathType Leaf) {
    Export-Crop -Source $InfoSource -Target (Join-Path $outputRoot '界面-下方信息与操作.png') -X 430 -Y 900 -Width 1470 -Height 590
}
else {
    Export-Crop -Source $hudSource -Target (Join-Path $outputRoot '界面-下方信息与操作.png') -X 455 -Y 900 -Width 1500 -Height 620
}

if (Test-Path -LiteralPath $HandSource -PathType Leaf) {
    Export-Crop -Source $HandSource -Target (Join-Path $outputRoot '界面-右侧手牌与分数.png') -X 1990 -Y 90 -Width 510 -Height 1380
}
else {
    Export-Crop -Source $hudSource -Target (Join-Path $outputRoot '界面-右侧手牌与分数.png') -X 1578 -Y 96 -Width 910 -Height 1400
}

# 移动阶段保留用户原始截图，禁止绘制“起/终”或伪造路线。
$rawMovingSource = Join-Path $guideRoot 'v3\移动阶段-蓝色可达路线.png'
Copy-Original -Source $rawMovingSource -Target (Join-Path $outputRoot '移动阶段-用户原图.png')

# 这张用户截图中的悬浮信息明确标注“孝感117 · 平原 · 非遗”。
Copy-Original -Source $TooltipSource -Target (Join-Path $outputRoot '地图格悬浮信息.png')
