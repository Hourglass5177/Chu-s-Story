[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = Join-Path $projectRoot 'arts\游戏指南\示意图\v1'
$fontPath = Join-Path $projectRoot 'arts\像素字体.ttf'
[System.IO.Directory]::CreateDirectory($outputRoot) | Out-Null

function New-RoundedPath {
    param(
        [System.Drawing.RectangleF]$Bounds,
        [float]$Radius
    )
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2.0
    $arc = [System.Drawing.RectangleF]::new($Bounds.X, $Bounds.Y, $diameter, $diameter)
    $path.AddArc($arc, 180, 90)
    $arc.X = $Bounds.Right - $diameter
    $path.AddArc($arc, 270, 90)
    $arc.Y = $Bounds.Bottom - $diameter
    $path.AddArc($arc, 0, 90)
    $arc.X = $Bounds.X
    $path.AddArc($arc, 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-CenteredText {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [System.Drawing.Font]$Font,
        [System.Drawing.Brush]$Brush,
        [System.Drawing.RectangleF]$Bounds
    )
    $format = [System.Drawing.StringFormat]::new()
    try {
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $Graphics.DrawString($Text, $Font, $Brush, $Bounds, $format)
    }
    finally {
        $format.Dispose()
    }
}

function Draw-Die {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.RectangleF]$Bounds,
        [int]$Value,
        [System.Drawing.Brush]$FaceBrush,
        [System.Drawing.Pen]$BorderPen,
        [System.Drawing.Brush]$PipBrush
    )
    $path = New-RoundedPath -Bounds $Bounds -Radius 30
    try {
        $Graphics.FillPath($FaceBrush, $path)
        $Graphics.DrawPath($BorderPen, $path)
    }
    finally {
        $path.Dispose()
    }
    $positions = @(
        @(0.25, 0.25), @(0.50, 0.25), @(0.75, 0.25),
        @(0.25, 0.50), @(0.50, 0.50), @(0.75, 0.50),
        @(0.25, 0.75), @(0.50, 0.75), @(0.75, 0.75)
    )
    $patterns = @{
        1 = @(4)
        2 = @(0, 8)
        3 = @(0, 4, 8)
        4 = @(0, 2, 6, 8)
        5 = @(0, 2, 4, 6, 8)
        6 = @(0, 2, 3, 5, 6, 8)
    }
    foreach ($index in $patterns[$Value]) {
        $position = $positions[$index]
        $x = $Bounds.X + $Bounds.Width * $position[0]
        $y = $Bounds.Y + $Bounds.Height * $position[1]
        $Graphics.FillEllipse($PipBrush, $x - 18, $y - 18, 36, 36)
    }
}

$privateFonts = [System.Drawing.Text.PrivateFontCollection]::new()
try {
    if (Test-Path -LiteralPath $fontPath -PathType Leaf) {
        $privateFonts.AddFontFile($fontPath)
    }
    $fontFamily = if ($privateFonts.Families.Count -gt 0) {
        $privateFonts.Families[0]
    }
    else {
        [System.Drawing.FontFamily]::GenericSansSerif
    }
    $titleFont = [System.Drawing.Font]::new($fontFamily, 54, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $operatorFont = [System.Drawing.Font]::new($fontFamily, 82, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $resultFont = [System.Drawing.Font]::new($fontFamily, 88, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $bodyFont = [System.Drawing.Font]::new($fontFamily, 38, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    try {
        $bitmap = [System.Drawing.Bitmap]::new(1600, 640)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
                $graphics.Clear([System.Drawing.Color]::FromArgb(255, 250, 238, 207))

                $panelBounds = [System.Drawing.RectangleF]::new(18, 18, 1564, 604)
                $panelPath = New-RoundedPath -Bounds $panelBounds -Radius 32
                $panelBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 255, 246, 220))
                $panelPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 181, 117, 67), 6)
                try {
                    $graphics.FillPath($panelBrush, $panelPath)
                    $graphics.DrawPath($panelPen, $panelPath)
                }
                finally {
                    $panelBrush.Dispose()
                    $panelPen.Dispose()
                    $panelPath.Dispose()
                }

                $brownBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 76, 43, 31))
                $orangeBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 199, 99, 34))
                $dieFaceBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 255, 253, 245))
                $dieBorderPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 151, 91, 50), 7)
                try {
                    Draw-CenteredText -Graphics $graphics -Text '投两枚六面骰' -Font $titleFont -Brush $brownBrush -Bounds ([System.Drawing.RectangleF]::new(0, 48, 1600, 74))
                    Draw-Die -Graphics $graphics -Bounds ([System.Drawing.RectangleF]::new(210, 160, 270, 270)) -Value 4 -FaceBrush $dieFaceBrush -BorderPen $dieBorderPen -PipBrush $brownBrush
                    Draw-CenteredText -Graphics $graphics -Text '+' -Font $operatorFont -Brush $orangeBrush -Bounds ([System.Drawing.RectangleF]::new(500, 235, 120, 100))
                    Draw-Die -Graphics $graphics -Bounds ([System.Drawing.RectangleF]::new(640, 160, 270, 270)) -Value 5 -FaceBrush $dieFaceBrush -BorderPen $dieBorderPen -PipBrush $brownBrush
                    Draw-CenteredText -Graphics $graphics -Text '=' -Font $operatorFont -Brush $orangeBrush -Bounds ([System.Drawing.RectangleF]::new(930, 235, 120, 100))
                    Draw-CenteredText -Graphics $graphics -Text '9 步' -Font $resultFont -Brush $brownBrush -Bounds ([System.Drawing.RectangleF]::new(1045, 184, 360, 210))
                    Draw-CenteredText -Graphics $graphics -Text '基础移动步数 = 两枚骰子的点数之和（2—12）' -Font $bodyFont -Brush $brownBrush -Bounds ([System.Drawing.RectangleF]::new(90, 500, 1420, 70))
                }
                finally {
                    $brownBrush.Dispose()
                    $orangeBrush.Dispose()
                    $dieFaceBrush.Dispose()
                    $dieBorderPen.Dispose()
                }
            }
            finally {
                $graphics.Dispose()
            }
            $target = Join-Path $outputRoot '2D6掷骰.png'
            $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Host "已生成 $target"
        }
        finally {
            $bitmap.Dispose()
        }
    }
    finally {
        $titleFont.Dispose()
        $operatorFont.Dispose()
        $resultFont.Dispose()
        $bodyFont.Dispose()
    }
}
finally {
    $privateFonts.Dispose()
}
