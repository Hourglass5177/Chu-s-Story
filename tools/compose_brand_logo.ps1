# Deterministic composition of the two supplied PNGs. No recoloring or background removal.
Add-Type -AssemblyName System.Drawing
$assetRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../arts/branding-v2'))
$frame = [Drawing.Bitmap]::new((Join-Path $assetRoot 'source/frame.png'))
$wordmark = [Drawing.Bitmap]::new((Join-Path $assetRoot 'source/wordmark.png'))
$combined = $frame.Clone([Drawing.Rectangle]::new(0,0,$frame.Width,$frame.Height), [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [Drawing.Graphics]::FromImage($combined)
try {
    # Frame inner opening: x=140..764, y=128..766. Ten-pixel clearance all around.
    $scale = [Math]::Min(604.0 / $wordmark.Width, 618.0 / $wordmark.Height)
    $w = [single]($wordmark.Width * $scale)
    $h = [single]($wordmark.Height * $scale)
    $rect = [Drawing.RectangleF]::new([single](452.0-$w/2), [single](447.0-$h/2), $w, $h)
    $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceOver
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.DrawImage($wordmark, $rect, [Drawing.RectangleF]::new(0,0,$wordmark.Width,$wordmark.Height), [Drawing.GraphicsUnit]::Pixel)
    $combined.Save((Join-Path $assetRoot 'logo-combined.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $graphics.Dispose(); $combined.Dispose(); $wordmark.Dispose(); $frame.Dispose() }
