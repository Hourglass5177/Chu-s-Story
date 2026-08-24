param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$tablePath = Join-Path $ProjectRoot "docs\食物牌效果与价格表（省级与国家级）.md"
$sourceDir = Join-Path $ProjectRoot "arts\食物牌"
$outputDir = Join-Path $sourceDir "数字版\完全版-v1"
[System.IO.Directory]::CreateDirectory($outputDir) | Out-Null

$sourceOverrides = @{
    "孝感米酒（神霖牌）" = "孝感米酒 （神霖牌）.png"
    "皮条鳝鱼（竹节鳝鱼）" = "皮条鳝鱼(竹节鳝鱼）.png"
    "竹山懒豆腐" = "竹山懒豆磨.png"
    "蕲春酸米粉" = "蔪春酸米粉.png"
    "青砖茶" = "靑砖茶.png"
    "黄石港饼" = "黄石港饼.jpg"
}

function Get-TableRows {
    $rows = @()
    foreach ($line in [System.IO.File]::ReadAllLines($tablePath, [System.Text.Encoding]::UTF8)) {
        if (-not $line.StartsWith("|")) { continue }
        $parts = $line.Split('|', [System.StringSplitOptions]::RemoveEmptyEntries)
        if ($parts.Count -lt 4) { continue }
        $name = $parts[0].Trim()
        $description = $parts[1].Trim()
        $price = 0
        if (-not [int]::TryParse($parts[2].Trim(), [ref]$price)) { continue }
        $rows += [PSCustomObject]@{
            Name = $name
            Description = $description
            Price = $price
        }
    }
    return $rows
}

function Get-SourcePath([string]$name) {
    if ($sourceOverrides.ContainsKey($name)) {
        return Join-Path $sourceDir $sourceOverrides[$name]
    }
    return Join-Path $sourceDir ($name + ".png")
}

function New-FittedFont(
    [System.Drawing.Graphics]$graphics,
    [string]$text,
    [System.Drawing.RectangleF]$bounds
) {
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $format.Trimming = [System.Drawing.StringTrimming]::None
    for ($size = 31; $size -ge 20; $size--) {
        $font = New-Object System.Drawing.Font("华文中宋", $size, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $measured = $graphics.MeasureString($text, $font, [int]$bounds.Width, $format)
        if ($measured.Width -le $bounds.Width -and $measured.Height -le $bounds.Height) {
            $format.Dispose()
            return $font
        }
        $font.Dispose()
    }
    $format.Dispose()
    return New-Object System.Drawing.Font("华文中宋", 20, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
}

$rows = Get-TableRows
if ($rows.Count -ne 40) {
    throw "正式策划表应包含40张省级/国家级食物，实际读取到 $($rows.Count) 张。"
}

foreach ($row in $rows) {
    $sourcePath = Get-SourcePath $row.Name
    if (-not [System.IO.File]::Exists($sourcePath)) {
        throw "找不到 $($row.Name) 的原始牌面：$sourcePath"
    }

    $source = [System.Drawing.Bitmap]::FromFile($sourcePath)
    try {
        $bitmap = New-Object System.Drawing.Bitmap($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bitmap.SetResolution($source.HorizontalResolution, $source.VerticalResolution)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.DrawImageUnscaled($source, 0, 0)
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

            $sx = $source.Width / 815.0
            $sy = $source.Height / 1147.0
            $clearBounds = [System.Drawing.RectangleF]::new(112 * $sx, 895 * $sy, 591 * $sx, 132 * $sy)
            $textBounds = [System.Drawing.RectangleF]::new(126 * $sx, 899 * $sy, 563 * $sx, 122 * $sy)
            $panelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 241, 237, 236))
            $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 36, 24, 19))
            $font = New-FittedFont $graphics $row.Description $textBounds
            $format = New-Object System.Drawing.StringFormat
            try {
                $format.Alignment = [System.Drawing.StringAlignment]::Center
                $format.LineAlignment = [System.Drawing.StringAlignment]::Center
                $format.Trimming = [System.Drawing.StringTrimming]::None
                $graphics.FillRectangle($panelBrush, $clearBounds)
                $graphics.DrawString($row.Description, $font, $textBrush, $textBounds, $format)
            }
            finally {
                $format.Dispose()
                $font.Dispose()
                $textBrush.Dispose()
                $panelBrush.Dispose()
            }
        }
        finally {
            $graphics.Dispose()
        }

        $outputPath = Join-Path $outputDir ($row.Name + ".png")
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
    }
    finally {
        $source.Dispose()
    }
}

Write-Output "已按正式策划表生成 $($rows.Count) 张居中效果牌面：$outputDir"
