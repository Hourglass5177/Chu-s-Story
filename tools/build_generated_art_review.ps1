param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$reviewSource = Join-Path $PSScriptRoot 'generated_art_review.html'
$assetRoot = Join-Path $projectRoot 'InheritanceTasks/Art/Pixel/v2/review/generated-motion-r4'
foreach ($asset in @('workshop-clean-plate.png','workshop-keyframe.png','character-handle-sheet.png','pump-cycle-matte.png','fire-sheet.png')) {
    if (-not (Test-Path -LiteralPath (Join-Path $assetRoot $asset) -PathType Leaf)) {
        throw "Missing generated review asset: $asset"
    }
}
foreach ($version in @('review-r4','review-r2')) {
    $reviewDirectory = Join-Path $projectRoot "artifacts/pixel-v2/$version"
    New-Item -ItemType Directory -Path $reviewDirectory -Force | Out-Null
    Copy-Item -LiteralPath $reviewSource -Destination (Join-Path $reviewDirectory 'index.html')
}
Write-Output 'Generated art review updated: artifacts/pixel-v2/review-r4/index.html'
