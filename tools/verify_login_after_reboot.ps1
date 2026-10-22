# Read-only runtime checks; writes evidence only inside the project.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$proof = Join-Path $project '.verification\startup-always-20261015'
$expected = [IO.File]::ReadAllText((Join-Path $proof 'expected.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$live = [IO.File]::ReadAllText((Join-Path $proof 'live-results.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$lastTest = [DateTime]::Parse($live.stages[-1].time_utc).ToUniversalTime()
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime()
if ($boot -le $lastTest) { throw 'No reboot has occurred since desktop verification; do not report a real reboot PASS.' }
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$task = $service.GetFolder('\').GetTask('MoonshadePotionShop-' + $sid)
if (-not $task.Enabled -or $task.LastRunTime.ToUniversalTime() -lt $boot) { throw 'The login task did not run after the new boot.' }
$dataFolder = [IO.Path]::GetDirectoryName($expected.registration.session_path)
$state = [IO.File]::ReadAllText($expected.registration.session_path, [Text.Encoding]::UTF8) | ConvertFrom-Json
$diagnostic = [IO.File]::ReadAllText((Join-Path $dataFolder 'login_resume.last-result.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
if ([DateTime]::Parse($diagnostic.time_utc).ToUniversalTime() -lt $boot -or -not $diagnostic.result.ok) { throw 'No successful launcher outcome after this boot.' }
if ($diagnostic.result.reason -notin @('started','already_running','already_running_pending')) { throw ('The launcher did not confirm a game: ' + $diagnostic.result.reason) }
if (-not $state.enabled -or -not $state.was_running -or $state.owner -cne 'moonshade-potion-shop') { throw 'The game has not recorded an enabled running session.' }
$game = Get-Process -Id ([int]$state.pid) -ErrorAction Stop
if ($game.Path -ine $expected.launch.executable -or $game.StartTime.ToUniversalTime() -lt $boot -or $game.MainWindowHandle -eq [IntPtr]::Zero -or -not $game.Responding) { throw 'The intended responsive game window is not running after this boot.' }
if ($task.LastTaskResult -ne 0) { throw ('The task failed: ' + $task.LastTaskResult) }
$evidence = @{pass=$true; reboot_tested=$true; time_utc=[DateTime]::UtcNow.ToString('o'); boot_utc=$boot.ToString('o'); task_last_run_utc=$task.LastRunTime.ToUniversalTime().ToString('o'); task_last_result=$task.LastTaskResult; diagnostic=$diagnostic; game_pid=$game.Id; window_handle=$game.MainWindowHandle.ToInt64(); game_started_utc=$game.StartTime.ToUniversalTime().ToString('o'); responding=$game.Responding}
[IO.File]::WriteAllText((Join-Path $proof 'after-reboot.json'), ($evidence | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Output 'REAL REBOOT LOGIN STARTUP PASS: new boot, login task run, new launcher outcome, intended responsive game window and process identity verified.'
