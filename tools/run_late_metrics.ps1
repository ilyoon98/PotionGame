param(
    [ValidateSet('pilot', 'pilot1', 'matrix', 'growth')][string]$Mode = 'pilot',
    [int]$Seed = 73129,
    [string]$Tag = 'double-supply',
    [int]$Seconds = 0,
    [int]$ReturnSeconds = 30,
    [int]$Training = -1
)
$ErrorActionPreference = 'Stop'
$taskProject = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$taskGodot = 'C:/Users/imtl/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe'
$taskEvidence = Join-Path $taskProject '.verification/late-investment-f19-20261019'
if ($Seconds -le 0) { $Seconds = if ($Mode -eq 'growth') { 64800 } else { 7200 } }
if ($Tag -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Use a dedicated evidence tag without a path.' }
$env:APPDATA = Join-Path $taskEvidence ('appdata-' + $Mode + '-' + $Seed)
$env:LOCALAPPDATA = Join-Path $taskEvidence ('localappdata-' + $Mode + '-' + $Seed)
$taskLogs = Join-Path $taskEvidence ('logs/' + $Tag)
$taskCurrentHash = (Get-FileHash -LiteralPath (Join-Path $taskProject 'scripts/shop_late_investments.gd') -Algorithm SHA256).Hash.ToLowerInvariant()
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA,$taskLogs | Out-Null

function Invoke-WorkspaceHeadless([string]$TaskScript, [string]$TaskLog, [string[]]$TaskArguments) {
    & $taskGodot --headless --path $taskProject --script $TaskScript --log-file $TaskLog -- @TaskArguments
    if ($LASTEXITCODE -ne 0) { throw "Headless verification failed: $TaskLog" }
    if (Select-String -LiteralPath $TaskLog -Pattern 'SCRIPT ERROR|^ERROR:|^FAIL ' -Quiet) {
        throw "The engine reported an error despite its exit status: $TaskLog"
    }
}

if ($Mode -eq 'growth') {
    $taskTrainingLevels = if ($Training -lt 0) { @(0,1,2,3) } else { @($Training) }
    foreach ($taskTraining in $taskTrainingLevels) {
        $taskName = 'return' + $ReturnSeconds + '-training' + $taskTraining + '-seed' + $Seed
        $taskFile = Join-Path $taskEvidence ('growth/' + $Tag + '/' + $taskName + '.json')
        if (Test-Path -LiteralPath $taskFile) {
            $taskExisting = Get-Content -LiteralPath $taskFile -Raw | ConvertFrom-Json
            if (-not $taskExisting.passed -or ($taskExisting.actual_seconds -lt $Seconds -and -not $taskExisting.all_late_completed)) { throw "Prior failing or shorter evidence is preserved; use a fresh tag: $taskName" }
            if ($taskExisting.metadata.source_sha256.'scripts/shop_late_investments.gd' -ne $taskCurrentHash) { throw "Source changed; use a fresh growth tag: $taskName" }
            Write-Output "Preserved matching existing growth evidence: $taskName"
            continue
        }
        Invoke-WorkspaceHeadless 'res://tools/measure_late_growth.gd' (Join-Path $taskLogs ($taskName + '.log')) @("--seed=$Seed", "--return=$ReturnSeconds", "--training=$taskTraining", "--seconds=$Seconds", "--tag=$Tag")
    }
    exit
}

$taskScenarios = if ($Mode -ne 'matrix') { @('normal') } else { @('normal','scarce_upper','inventory_full') }
$taskCombos = if ($Mode -eq 'pilot1') { @('none','both1') } elseif ($Mode -eq 'pilot') { @('none','both1','both3') } else { @('none','support1','support2','support3','bulk1','bulk2','bulk3','both1','both2','both3') }
foreach ($taskTerms in @('standard','final')) {
    foreach ($taskScenario in $taskScenarios) {
        foreach ($taskCombo in $taskCombos) {
            $taskName = $taskTerms + '-' + $taskScenario + '-seed' + $Seed + '-' + $taskCombo
            $taskFile = Join-Path $taskEvidence ('effects/' + $Tag + '/' + $taskName + '.json')
            if (Test-Path -LiteralPath $taskFile) {
                $taskExisting = Get-Content -LiteralPath $taskFile -Raw | ConvertFrom-Json
                if (-not $taskExisting.passed) { throw "Prior failing evidence is preserved; use a fresh tag: $taskName" }
                if ($taskExisting.metadata.source_sha256.'scripts/shop_late_investments.gd' -ne $taskCurrentHash) { throw "Source changed; use a fresh evidence tag: $taskName" }
                Write-Output "Preserved matching existing effect evidence: $taskName"
                continue
            }
            Invoke-WorkspaceHeadless 'res://tools/measure_late_investments.gd' (Join-Path $taskLogs ($taskName + '.log')) @("--seed=$Seed", "--terms=$taskTerms", "--scenario=$taskScenario", "--combo=$taskCombo", "--tag=$Tag", "--seconds=$Seconds")
        }
    }
}
