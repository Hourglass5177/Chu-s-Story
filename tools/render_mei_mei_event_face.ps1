param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sourcePath = Join-Path $ProjectRoot 'arts\事件卡\事件牌（牌面）(1)_08.jpg'
$outputDir = Join-Path $ProjectRoot 'arts\事件卡\数字版\beta-0.2.1'
$outputPath = Join-Path $outputDir '美美与共.jpg'
[IO.Directory]::CreateDirectory($outputDir) | Out-Null

$description = '全场存活玩家依次投一枚六面骰，并获得等同于自己点数的精力。'
$source = [Drawing.Bitmap]::FromFile($sourcePath)
try {
    $bitmap = New-Object Drawing.Bitmap($source.Width, $source.Height, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.DrawImageUnscaled($source, 0, 0)
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $sx = $source.Width / 2572.0
        $sy = $source.Height / 3609.0
        $clearBounds = [Drawing.RectangleF]::new(300 * $sx, 1600 * $sy, 1970 * $sx, 1600 * $sy)
        $textBounds = [Drawing.RectangleF]::new(360 * $sx, 1690 * $sy, 1850 * $sx, 1400 * $sy)
        $panelColor = $source.GetPixel([int](1286 * $sx), [int](1800 * $sy))
        $panelBrush = New-Object Drawing.SolidBrush($panelColor)
        $textBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 8, 8, 8))
        $font = [Drawing.Font]::new('华文行楷', [single](145 * $sx), [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
        $format = New-Object Drawing.StringFormat
        try {
            $format.Alignment = [Drawing.StringAlignment]::Center
            $format.LineAlignment = [Drawing.StringAlignment]::Center
            $format.Trimming = [Drawing.StringTrimming]::None
            $graphics.FillRectangle($panelBrush, $clearBounds)
            $graphics.DrawString($description, $font, $textBrush, $textBounds, $format)
        }
        finally {
            $format.Dispose(); $font.Dispose(); $textBrush.Dispose(); $panelBrush.Dispose()
        }
    }
    finally { $graphics.Dispose() }
    $encoder = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg' | Select-Object -First 1
    $parameters = New-Object Drawing.Imaging.EncoderParameters(1)
    $parameters.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, 95L)
    $bitmap.Save($outputPath, $encoder, $parameters)
    $parameters.Dispose(); $bitmap.Dispose()
}
finally { $source.Dispose() }

Write-Output $outputPath
