$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path $project ('.verification\login-diagnostics\' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$helper = Join-Path $project 'native\windows\ResumeLogin.ps1'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$state = Join-Path $fixture 'login_resume.json'
$diagnostic = Join-Path $fixture 'login_resume.last-result.json'
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Invoke-Helper([string]$Expected, [bool]$Dry = $false) {
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $helper, '-StatePath', $state)
    if ($Dry) { $arguments += '-DryRun' }
    $output = @(& $powershell @arguments)
    $exitCode = $LASTEXITCODE
    $reply = $output[-1] | ConvertFrom-Json
    Check (($reply.ok -and $exitCode -eq 0) -or (-not $reply.ok -and $exitCode -eq 1)) 'Task Scheduler must receive the correct success/error exit code'
    Check ($reply.reason -ceq $Expected) ('Unexpected result: ' + $output[-1])
    Check (-not $reply.would_launch) 'These fixtures must never start a game'
    if (-not $Dry) {
        $record = [IO.File]::ReadAllText($diagnostic) | ConvertFrom-Json
        Check ($record.result.reason -ceq $Expected -and $record.helper_pid -gt 0 -and $record.time_utc -ne '') 'Real invocation must retain a timestamped outcome'
        Check ($record.child_pid -eq 0 -and -not $record.marker_acknowledged) 'Skipped launches must not claim a game session'
    }
}
Invoke-Helper 'no_state' $true
Check (-not [IO.File]::Exists($diagnostic)) 'Dry-run must not create diagnostics'
Invoke-Helper 'no_state'
$marker = @{owner='moonshade-potion-shop'; version=1; enabled=$true; was_running=$false}
[IO.File]::WriteAllText($state, ($marker | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
$before = [IO.File]::ReadAllText($state)
Invoke-Helper 'invalid_executable'
$priorLog = [IO.File]::ReadAllText($diagnostic)
Invoke-Helper 'invalid_executable' $true
Check ([IO.File]::ReadAllText($diagnostic) -ceq $priorLog) 'Dry-run must not overwrite diagnostics'
Check ([IO.File]::ReadAllText($state) -ceq $before) 'Diagnostics must preserve the session marker'
$marker.enabled = $false
[IO.File]::WriteAllText($state, ($marker | ConvertTo-Json -Compress))
Invoke-Helper 'disabled'
$marker.owner = 'another-application'
[IO.File]::WriteAllText($state, ($marker | ConvertTo-Json -Compress))
Invoke-Helper 'invalid_owner'
[IO.File]::WriteAllText($state, '{invalid JSON')
Invoke-Helper 'error'
$errorRecord = [IO.File]::ReadAllText($diagnostic) | ConvertFrom-Json
Check (-not $errorRecord.result.ok -and $errorRecord.result.error -ne '') 'Parse errors must retain their cause'
# This windowless native fixture exits with code 2 for autostart arguments,
# before acquiring any mutex. It is not the game executable.
$fixtureExecutable = Join-Path $fixture 'early-exit.exe'
Copy-Item -LiteralPath (Join-Path $project 'native\windows\single_instance_guard.exe') -Destination $fixtureExecutable
$launchMarker = @{owner='moonshade-potion-shop'; version=1; enabled=$true; was_running=$false; executable=$fixtureExecutable; args=@('--', '--autostart'); pid=0; started_at=0}
[IO.File]::WriteAllText($state, ($launchMarker | ConvertTo-Json -Compress))
$launchBefore = [IO.File]::ReadAllText($state)
$output = @(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -StatePath $state)
$reply = $output[-1] | ConvertFrom-Json
Check (-not $reply.ok -and $reply.reason -ceq 'child_exited' -and $reply.would_launch) 'A closed enabled game must launch; early child exit must not count as success'
$exitRecord = [IO.File]::ReadAllText($diagnostic) | ConvertFrom-Json
Check ($exitRecord.child_pid -gt 0 -and -not $exitRecord.marker_acknowledged -and $exitRecord.result.error.Contains('2')) 'Early exit must retain child PID and exit code'
Check ([IO.File]::ReadAllText($state) -ceq $launchBefore) 'Failed child launch must preserve resume intent'
# A read-only/unwritable diagnostic must not change the resume decision.
[IO.File]::Delete($diagnostic)
[IO.Directory]::CreateDirectory($diagnostic) | Out-Null
$marker.owner = 'moonshade-potion-shop'
$marker.enabled = $true
[IO.File]::WriteAllText($state, ($marker | ConvertTo-Json -Compress))
$output = @(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -StatePath $state)
$reply = $output[-1] | ConvertFrom-Json
Check (-not $reply.ok -and $reply.reason -ceq 'invalid_executable') 'Logging failure must not affect the helper'
Write-Output 'LOGIN DIAGNOSTICS PASS: invocation outcomes, parse errors, timestamps, dry-run read-only, marker preservation, native fixture early exit, logging failure isolation; no registry or game launch'
