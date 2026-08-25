param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$tablePath = Join-Path $ProjectRoot "docs\食物牌效果与价格表（省级与国家级）.md"
$sourceDir = Join-Path $ProjectRoot "arts\食物牌"
$outputDir = Join-Path $sourceDir "数字版\完全版-v2"
[System.IO.Directory]::CreateDirectory($outputDir) | Out-Null
$overviewDir = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "docs\牌面验收"))
[System.IO.Directory]::CreateDirectory($overviewDir) | Out-Null

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

function Get-BalancedLines(
    [System.Drawing.Graphics]$graphics,
    [string]$text,
    [System.Drawing.Font]$font,
    [float]$width,
    [int]$maxLines = 3
) {
    $format = [System.Drawing.StringFormat]::GenericTypographic.Clone()
    try {
        $length = $text.Length
        $best = $null
        for ($lineCount = 1; $lineCount -le $maxLines; $lineCount++) {
            $candidates = @()
            if ($lineCount -eq 1) {
                $candidates = ,@($text)
            }
            elseif ($lineCount -eq 2) {
                for ($a = 1; $a -lt $length; $a++) {
                    $candidates += ,@($text.Substring(0, $a), $text.Substring($a))
                }
            }
            else {
                for ($a = 1; $a -lt $length - 1; $a++) {
                    for ($b = $a + 1; $b -lt $length; $b++) {
                        $candidates += ,@($text.Substring(0, $a), $text.Substring($a, $b - $a), $text.Substring($b))
                    }
                }
            }
            foreach ($candidate in $candidates) {
                $widths = @($candidate | ForEach-Object { $graphics.MeasureString($_, $font, 4096, $format).Width })
                if (($widths | Measure-Object -Maximum).Maximum -gt $width) { continue }
                $average = ($widths | Measure-Object -Average).Average
                $variance = ($widths | ForEach-Object { [math]::Pow($_ - $average, 2) } | Measure-Object -Sum).Sum
                $punctuationBonus = 0
                for ($index = 0; $index -lt $candidate.Count - 1; $index++) {
                    if ($candidate[$index] -match '[，。；、]$') { $punctuationBonus += 1500 }
                }
                $score = $variance - $punctuationBonus
                if ($null -eq $best -or $score -lt $best.Score) {
                    $best = [pscustomobject]@{ Lines = $candidate; Score = $score }
                }
            }
            if ($null -ne $best) { return @($best.Lines) }
        }
        return @()
    }
    finally {
        $format.Dispose()
    }
}

function New-FittedLayout(
    [System.Drawing.Graphics]$graphics,
    [string]$text,
    [System.Drawing.RectangleF]$bounds
) {
    for ($size = 42; $size -ge 32; $size--) {
        $font = New-Object System.Drawing.Font("华文中宋", $size, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $lines = @(Get-BalancedLines $graphics $text $font ($bounds.Width - 24) 3)
        # DrawString 的默认行高包含较大的字体留白；逐行绘制时采用紧凑基线间距，
        # 但不使用矮矩形裁剪字形，否则长文案会只剩上下半截。
        $lineHeight = [math]::Ceiling($font.GetHeight($graphics) * 0.83)
        if ($lines.Count -gt 0 -and $lineHeight * $lines.Count -le $bounds.Height - 20) {
            return [pscustomobject]@{ Font = $font; Lines = $lines; LineHeight = $lineHeight }
        }
        $font.Dispose()
    }
    throw "描述无法在不低于32px的字号下排入三行：$text"
}

$rows = Get-TableRows
if ($rows.Count -ne 40) {
    throw "正式策划表应包含40张省级/国家级食物，实际读取到 $($rows.Count) 张。"
}

$manifest = @()
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
            # 旧版只从 y=895 开始覆盖，原描述的抗锯齿上缘会残留在遮罩上方。
            # 保留等级标题与边框，仅完整重建其下方的描述内框。
            $clearBounds = [System.Drawing.RectangleF]::new(112 * $sx, 875 * $sy, 591 * $sx, 164 * $sy)
            $textBounds = [System.Drawing.RectangleF]::new(106 * $sx, 890 * $sy, 603 * $sx, 145 * $sy)
            $panelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 241, 237, 236))
            $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 36, 24, 19))
            $layout = New-FittedLayout $graphics $row.Description $textBounds
            $font = $layout.Font
            $fontSize = [int]$font.Size
            $lineCount = $layout.Lines.Count
            $format = New-Object System.Drawing.StringFormat
            try {
                $format.Alignment = [System.Drawing.StringAlignment]::Center
                $format.LineAlignment = [System.Drawing.StringAlignment]::Near
                $format.Trimming = [System.Drawing.StringTrimming]::None
                $graphics.FillRectangle($panelBrush, $clearBounds)
                $totalHeight = $layout.LineHeight * $layout.Lines.Count
                $lineTop = $textBounds.Top + ($textBounds.Height - $totalHeight) / 2.0
                foreach ($line in $layout.Lines) {
                    $lineOrigin = [System.Drawing.PointF]::new($textBounds.Left + $textBounds.Width / 2.0, $lineTop)
                    $graphics.DrawString($line, $font, $textBrush, $lineOrigin, $format)
                    $lineTop += $layout.LineHeight
                }
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
        $hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest += [PSCustomObject]@{
            name = $row.Name
            description = $row.Description
            price = $row.Price
            font_size = $fontSize
            line_count = $lineCount
            output = [System.IO.Path]::GetFileName($outputPath)
            sha256 = $hash
        }
        $bitmap.Dispose()
    }
    finally {
        $source.Dispose()
    }
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputDir "manifest.json") -Encoding utf8

# 100% 牌面逐张校验仍以单图为准；总览图用于快速发现残影、错位和异常字号。
$columns = 8
$rowsCount = [math]::Ceiling($manifest.Count / [double]$columns)
$thumbWidth = 204
$thumbHeight = 287
$labelHeight = 32
$sheet = [System.Drawing.Bitmap]::new(
    [int]($columns * $thumbWidth),
    [int]($rowsCount * ($thumbHeight + $labelHeight))
)
$sheetGraphics = [System.Drawing.Graphics]::FromImage($sheet)
$sheetGraphics.Clear([System.Drawing.Color]::FromArgb(255, 238, 222, 188))
$sheetGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$sheetFont = New-Object System.Drawing.Font("Microsoft YaHei UI", 15, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$sheetBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 55, 35, 26))
$sheetFormat = New-Object System.Drawing.StringFormat
$sheetFormat.Alignment = [System.Drawing.StringAlignment]::Center
try {
    for ($index = 0; $index -lt $manifest.Count; $index++) {
        $entry = $manifest[$index]
        $image = [System.Drawing.Image]::FromFile((Join-Path $outputDir $entry.output))
        try {
            $x = ($index % $columns) * $thumbWidth
            $y = [math]::Floor($index / $columns) * ($thumbHeight + $labelHeight)
            $sheetGraphics.DrawImage($image, $x, $y, $thumbWidth, $thumbHeight)
            $labelBounds = [System.Drawing.RectangleF]::new($x, $y + $thumbHeight + 3, $thumbWidth, $labelHeight - 3)
            $sheetGraphics.DrawString($entry.name, $sheetFont, $sheetBrush, $labelBounds, $sheetFormat)
        }
        finally {
            $image.Dispose()
        }
    }
    $sheet.Save((Join-Path $overviewDir "食物牌v2总览.png"), [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $sheetFormat.Dispose()
    $sheetBrush.Dispose()
    $sheetFont.Dispose()
    $sheetGraphics.Dispose()
    $sheet.Dispose()
}

$fullWidth = 815
$fullHeight = 1147
$fullLabelHeight = 48
$fullSheet = [System.Drawing.Bitmap]::new(
    [int]($columns * $fullWidth),
    [int]($rowsCount * ($fullHeight + $fullLabelHeight))
)
$fullGraphics = [System.Drawing.Graphics]::FromImage($fullSheet)
$fullGraphics.Clear([System.Drawing.Color]::FromArgb(255, 238, 222, 188))
$fullFont = New-Object System.Drawing.Font("Microsoft YaHei UI", 28, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$fullBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 55, 35, 26))
$fullFormat = New-Object System.Drawing.StringFormat
$fullFormat.Alignment = [System.Drawing.StringAlignment]::Center
try {
    for ($index = 0; $index -lt $manifest.Count; $index++) {
        $entry = $manifest[$index]
        $image = [System.Drawing.Image]::FromFile((Join-Path $outputDir $entry.output))
        try {
            $x = ($index % $columns) * $fullWidth
            $y = [math]::Floor($index / $columns) * ($fullHeight + $fullLabelHeight)
            $fullGraphics.DrawImageUnscaled($image, $x, $y)
            $labelBounds = [System.Drawing.RectangleF]::new($x, $y + $fullHeight + 4, $fullWidth, $fullLabelHeight - 4)
            $fullGraphics.DrawString($entry.name, $fullFont, $fullBrush, $labelBounds, $fullFormat)
        }
        finally {
            $image.Dispose()
        }
    }
    $fullSheet.Save((Join-Path $overviewDir "食物牌v2总览-100%.png"), [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $fullFormat.Dispose()
    $fullBrush.Dispose()
    $fullFont.Dispose()
    $fullGraphics.Dispose()
    $fullSheet.Dispose()
}

Write-Output "已按正式策划表生成 $($rows.Count) 张自适应字号居中效果牌面及总览：$outputDir"
