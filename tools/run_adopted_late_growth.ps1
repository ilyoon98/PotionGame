param(
    [int]$Seed,
    [ValidateSet(30,900)][int]$ReturnSeconds
)
$ErrorActionPreference = 'Stop'
$taskProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$taskEvidence = Join-Path $taskProject '.verification/f19-adopted180-20261019/growth'
$taskRaw = Join-Path $taskProject '.verification/late-investment-f19-20261019/growth/adopted180-20261019'
$taskGodot = 'C:/Users/imtl/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe'
$taskLate = Get-Content -LiteralPath (Join-Path $taskProject 'scripts/shop_late_investments.gd') -Raw
if (-not $taskLate.Contains('const COSTS := [150000, 300000, 450000]')) { throw 'Wait for the adopted production price' }
$env:APPDATA = Join-Path $taskEvidence ('appdata/' + $Seed + '-' + $ReturnSeconds)
$env:LOCALAPPDATA = Join-Path $taskEvidence ('localappdata/' + $Seed + '-' + $ReturnSeconds)
$taskLogs = Join-Path $taskEvidence 'logs'
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,$taskLogs | Out-Null
foreach ($taskTraining in @(0,1,2,3)) {
    $taskName = 'return' + $ReturnSeconds + '-training' + $taskTraining + '-seed' + $Seed
    if (Test-Path -LiteralPath (Join-Path $taskRaw ($taskName + '.json'))) { throw ('Preserve prior adopted evidence: ' + $taskName) }
    $taskLog = Join-Path $taskLogs ($taskName + '.log')
    & $taskGodot --headless --path $taskProject --script 'res://tools/measure_late_growth.gd' --log-file $taskLog -- "--seed=$Seed" "--return=$ReturnSeconds" "--training=$taskTraining" '--seconds=64800' '--tag=adopted180-20261019'
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $taskLog -Pattern 'SCRIPT ERROR|^ERROR:|^FAIL ' -Quiet)) {
        throw ('Adopted production growth failed: ' + $taskLog)
    }
}
