param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$sourcePath = Join-Path $ProjectRoot 'arts/游戏指南/实机截图/v3/移动阶段-蓝色可达路线.png'
$targetPath = Join-Path $ProjectRoot 'arts/游戏指南/实机截图/v3/移动阶段-实际路线标注.png'

Add-Type -AssemblyName System.Drawing
$source = [System.Drawing.Image]::FromFile($sourcePath)
$canvas = New-Object System.Drawing.Bitmap($source.Width, $source.Height)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.DrawImage($source, 0, 0, $source.Width, $source.Height)

$route = [System.Drawing.PointF[]]@(
    [System.Drawing.PointF]::new(585, 174),
    [System.Drawing.PointF]::new(483, 235),
    [System.Drawing.PointF]::new(380, 296),
    [System.Drawing.PointF]::new(380, 418),
    [System.Drawing.PointF]::new(277, 478),
    [System.Drawing.PointF]::new(277, 598)
)

$shadowPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 17, 67, 90), 18)
$routePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 92, 220, 234), 10)
$routePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$routePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$shadowPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$shadowPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$graphics.DrawLines($shadowPen, $route)
$graphics.DrawLines($routePen, $route)

$startBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 38, 113, 178))
$endBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 30, 151, 157))
$labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$labelFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 21, [System.Drawing.FontStyle]::Bold)
$labelFormat = New-Object System.Drawing.StringFormat
$labelFormat.Alignment = [System.Drawing.StringAlignment]::Center
$labelFormat.LineAlignment = [System.Drawing.StringAlignment]::Center

$graphics.FillEllipse($startBrush, 548, 137, 74, 74)
$graphics.DrawString('起', $labelFont, $labelBrush, [System.Drawing.RectangleF]::new(548, 137, 74, 74), $labelFormat)
$graphics.FillEllipse($endBrush, 240, 561, 74, 74)
$graphics.DrawString('终', $labelFont, $labelBrush, [System.Drawing.RectangleF]::new(240, 561, 74, 74), $labelFormat)

$canvas.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)

$labelFormat.Dispose()
$labelFont.Dispose()
$labelBrush.Dispose()
$endBrush.Dispose()
$startBrush.Dispose()
$routePen.Dispose()
$shadowPen.Dispose()
$graphics.Dispose()
$canvas.Dispose()
$source.Dispose()

$mapSourcePath = Join-Path $ProjectRoot 'arts/地图/地图完整版.png'
$mapTargetPath = Join-Path $ProjectRoot 'arts/游戏指南/实机截图/v3/快速上手-起点至非遗点路线.png'
$mapSource = [System.Drawing.Image]::FromFile($mapSourcePath)
$mapCrop = New-Object System.Drawing.Bitmap(1500, 950)
$mapGraphics = [System.Drawing.Graphics]::FromImage($mapCrop)
$mapGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$mapGraphics.DrawImage(
    $mapSource,
    [System.Drawing.Rectangle]::new(0, 0, 1500, 950),
    [System.Drawing.Rectangle]::new(650, 0, 1500, 950),
    [System.Drawing.GraphicsUnit]::Pixel
)

$journeyRoute = [System.Drawing.PointF[]]@(
    [System.Drawing.PointF]::new(410, 220),
    [System.Drawing.PointF]::new(650, 350),
    [System.Drawing.PointF]::new(890, 350),
    [System.Drawing.PointF]::new(1135, 350)
)
$shadowPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 17, 67, 90), 18)
$journeyPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 92, 220, 234), 10)
$startBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 38, 113, 178))
$mapGraphics.DrawLines($shadowPen, $journeyRoute)
$mapGraphics.DrawLines($journeyPen, $journeyRoute)
$mapGraphics.FillEllipse($startBrush, 373, 183, 74, 74)
$labelFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 21, [System.Drawing.FontStyle]::Bold)
$labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$labelFormat = New-Object System.Drawing.StringFormat
$labelFormat.Alignment = [System.Drawing.StringAlignment]::Center
$labelFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
$mapGraphics.DrawString('起', $labelFont, $labelBrush, [System.Drawing.RectangleF]::new(373, 183, 74, 74), $labelFormat)
$endBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 30, 151, 157))
$mapGraphics.FillEllipse($endBrush, 1098, 313, 74, 74)
$mapGraphics.DrawString('非遗点', $labelFont, $labelBrush, [System.Drawing.RectangleF]::new(1035, 398, 200, 52), $labelFormat)
$mapCrop.Save($mapTargetPath, [System.Drawing.Imaging.ImageFormat]::Png)

$labelFormat.Dispose()
$labelFont.Dispose()
$labelBrush.Dispose()
$endBrush.Dispose()
$startBrush.Dispose()
$journeyPen.Dispose()
$shadowPen.Dispose()
$mapGraphics.Dispose()
$mapCrop.Dispose()
$mapSource.Dispose()

Write-Output $targetPath
Write-Output $mapTargetPath
