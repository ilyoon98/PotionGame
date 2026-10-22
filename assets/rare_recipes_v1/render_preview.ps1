param([string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$Root = [IO.Path]::GetFullPath($Root)
$taskCatalog = Get-Content -LiteralPath (Join-Path $Root 'catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$taskProject = Split-Path (Split-Path $Root -Parent) -Parent
$taskFont = New-Object Drawing.Font('Malgun Gothic',16,[Drawing.FontStyle]::Regular)
$taskSmallFont = New-Object Drawing.Font('Malgun Gothic',11,[Drawing.FontStyle]::Regular)
$taskTitleFont = New-Object Drawing.Font('Malgun Gothic',23,[Drawing.FontStyle]::Regular)
$taskText = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#f0dfc4'))
$taskMuted = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#b4a4bd'))
$taskGold = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#efc77c'))
$taskPanel = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#2c2437'))
function Draw-Sprite($Graphics, [string]$Path, [int]$X, [int]$Y, [int]$Scale) {
    $taskImage = [Drawing.Image]::FromFile($Path)
    try {
        $taskRect = New-Object Drawing.Rectangle($X,$Y,($taskImage.Width*$Scale),($taskImage.Height*$Scale))
        $Graphics.DrawImage($taskImage,$taskRect,0,0,$taskImage.Width,$taskImage.Height,[Drawing.GraphicsUnit]::Pixel)
    } finally { $taskImage.Dispose() }
}
function Local-Path([string]$Path) { return Join-Path $Root ($Path.Replace('res://assets/rare_recipes_v1/','')) }
function New-Board([int]$Width,[int]$Height) {
    $taskBitmap = New-Object Drawing.Bitmap($Width,$Height,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $taskGraphics = [Drawing.Graphics]::FromImage($taskBitmap)
    $taskGraphics.Clear([Drawing.ColorTranslator]::FromHtml('#211b2d'))
    $taskGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $taskGraphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
    $taskGraphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::None
    $taskGraphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    return @($taskBitmap,$taskGraphics)
}
$taskBoard = New-Board 1080 1248
$taskBitmap = $taskBoard[0]; $taskGraphics = $taskBoard[1]
try {
    $taskGraphics.DrawString('특별 레시피와 물약 · 4세트',$taskTitleFont,$taskText,24,18)
    $taskGraphics.DrawString('디자인 후보 · 게임 연결 대기 · 작은 병은 독립 원본 · 일반 물약은 기존 승인 에셋',$taskSmallFont,$taskMuted,24,58)
    $taskCompareNames = @{growth='성장';stealth='은신';moon='달빛';starlight='별빛'}
    $taskIndex = 0
    foreach ($taskEntry in $taskCatalog.assets) {
        $taskY = 96 + $taskIndex * 284
        $taskGraphics.FillRectangle($taskPanel,24,$taskY,1032,272)
        $taskGraphics.DrawString($taskEntry.name_candidate,$taskFont,$taskText,40,($taskY+10))
        $taskGraphics.DrawString($taskEntry.region_name,$taskSmallFont,$taskGold,880,($taskY+12))
        $taskLabels = @(@('특별 포션 · 3×',40),@('전용 레시피 · 3×',192),@('진열병 · 1× / 4×',354),@(('기존 '+$taskCompareNames[$taskEntry.comparison_general]+' · 3×'),570),@('기존 진열병 · 1× / 4×',744))
        foreach ($taskLabel in $taskLabels) { $taskGraphics.DrawString([string]$taskLabel[0],$taskSmallFont,$taskMuted,[single]$taskLabel[1],[single]($taskY+46)) }
        Draw-Sprite $taskGraphics (Local-Path $taskEntry.potion_path) 40 ($taskY+78) 3
        Draw-Sprite $taskGraphics (Local-Path $taskEntry.recipe_path) 192 ($taskY+78) 3
        Draw-Sprite $taskGraphics (Local-Path $taskEntry.bottle_path) 360 ($taskY+100) 1
        Draw-Sprite $taskGraphics (Local-Path $taskEntry.bottle_path) 408 ($taskY+88) 4
        Draw-Sprite $taskGraphics (Join-Path $taskProject ('assets/content_expansion_v1/potions/'+$taskEntry.comparison_general+'_icon.png')) 576 ($taskY+78) 3
        Draw-Sprite $taskGraphics (Join-Path $taskProject ('assets/content_expansion_v1/potions/'+$taskEntry.comparison_general+'_12x16.png')) 756 ($taskY+100) 1
        Draw-Sprite $taskGraphics (Join-Path $taskProject ('assets/content_expansion_v1/potions/'+$taskEntry.comparison_general+'_12x16.png')) 804 ($taskY+88) 4
        $taskGraphics.DrawString($taskEntry.id,$taskSmallFont,$taskMuted,40,($taskY+236))
        $taskIndex++
    }
    $taskBitmap.Save((Join-Path $Root 'previews/pairs-and-general-comparison.png'),[Drawing.Imaging.ImageFormat]::Png)
} finally { $taskGraphics.Dispose(); $taskBitmap.Dispose() }
$taskBoard = New-Board 840 300
$taskBitmap = $taskBoard[0]; $taskGraphics = $taskBoard[1]
try {
    $taskGraphics.DrawString('진열용 특별 물약 · 실제 12×16 및 8배 확대',$taskFont,$taskText,24,14)
    $taskIndex = 0
    foreach ($taskEntry in $taskCatalog.assets) {
        $taskX = 24 + $taskIndex * 204
        $taskGraphics.FillRectangle($taskPanel,$taskX,54,192,230)
        $taskGraphics.DrawString($taskEntry.name_candidate,$taskSmallFont,$taskText,($taskX+8),62)
        Draw-Sprite $taskGraphics (Local-Path $taskEntry.bottle_path) ($taskX+16) 112 1
        Draw-Sprite $taskGraphics (Local-Path $taskEntry.bottle_path) ($taskX+64) 94 8
        $taskGraphics.DrawString('원본 / 확대',$taskSmallFont,$taskMuted,($taskX+16),250)
        $taskIndex++
    }
    $taskBitmap.Save((Join-Path $Root 'previews/small-bottles.png'),[Drawing.Imaging.ImageFormat]::Png)
} finally { $taskGraphics.Dispose(); $taskBitmap.Dispose() }
$taskFont.Dispose();$taskSmallFont.Dispose();$taskTitleFont.Dispose()
$taskText.Dispose();$taskMuted.Dispose();$taskGold.Dispose();$taskPanel.Dispose()
Write-Output 'HEADLESS FILE PREVIEW PASS: pairs and tiny bottle boards saved; no window created'

