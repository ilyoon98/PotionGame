param(
    [ValidateSet('current210','candidate180')][string]$Variant,
    [int]$Seed
)
$ErrorActionPreference = 'Stop'
$taskProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$taskPricing = Join-Path $taskProject '.verification/f19-supplement-20261019/pricing'
$taskGodot = 'C:/Users/imtl/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe'
$taskScript = 'res://.verification/f19-supplement-20261019/pricing/' + $Variant + '/model/tools/measure_late_growth.gd'
foreach ($taskReturn in @(30,900)) {
    $taskName = 'return' + $taskReturn + '-training0-seed' + $Seed
    $taskOutput = Join-Path $taskPricing ($Variant + '/growth/comparison/' + $taskName + '.json')
    if (Test-Path -LiteralPath $taskOutput) { throw ('Preserve existing pricing measurement: ' + $taskOutput) }
    $env:APPDATA = Join-Path $taskPricing ('appdata/' + $Variant + '-' + $Seed + '-' + $taskReturn)
    $env:LOCALAPPDATA = Join-Path $taskPricing ('localappdata/' + $Variant + '-' + $Seed + '-' + $taskReturn)
    $taskLogs = Join-Path $taskPricing ($Variant + '/logs')
    New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,$taskLogs | Out-Null
    $taskLog = Join-Path $taskLogs ($taskName + '.log')
    & $taskGodot --headless --path $taskProject --script $taskScript --log-file $taskLog -- "--seed=$Seed" "--return=$taskReturn" '--training=0' '--seconds=64800' '--tag=comparison'
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $taskLog -Pattern 'SCRIPT ERROR|^ERROR:|^FAIL ' -Quiet)) {
        throw ('Pricing headless measurement failed: ' + $taskLog)
    }
}
