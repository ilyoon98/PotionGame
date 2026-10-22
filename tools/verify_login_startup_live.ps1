# Explicit desktop verification for the user's authorized startup repair.
# Runs only the game's prepared production requests; never logs off/reboots Windows.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$proof = Join-Path $project '.verification\startup-always-20261015'
$expected = [IO.File]::ReadAllText((Join-Path $proof 'expected.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$statePath = $expected.registration.session_path
$dataFolder = [IO.Path]::GetDirectoryName($statePath)
$diagnosticPath = Join-Path $dataFolder 'login_resume.last-result.json'
$powershell = $expected.registration.powershell
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$taskName = 'MoonshadePotionShop-' + $sid
$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$folder = $service.GetFolder('\')
$script:evidence = [Collections.Generic.List[object]]::new()
$requests = @{}
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Read-State { return [IO.File]::ReadAllText($statePath, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function Record([string]$Stage, [object]$Details) {
    $script:evidence.Add(@{stage=$Stage; time_utc=[DateTime]::UtcNow.ToString('o'); details=$Details})
    [IO.File]::WriteAllText((Join-Path $proof 'live-results.json'), (@{stages=$script:evidence; real_logon_tested=$false; reboot_tested=$false} | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    Write-Output ('PASS: ' + $Stage)
}
foreach ($action in @('install','query','remove')) {
    $scriptPath = Join-Path $proof ($action + '.ps1')
    $source = [IO.File]::ReadAllText($scriptPath, [Text.Encoding]::UTF8)
    $encoded = [regex]::Match($source, "FromBase64String\('([^']+)'\)").Groups[1].Value
    $path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
    Check ([IO.Path]::GetFullPath($path).StartsWith([IO.Path]::GetFullPath($proof) + '\', [StringComparison]::OrdinalIgnoreCase)) 'Request must stay in the project proof directory'
    $requests[$action] = @{script=$scriptPath; path=$path; body=[IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)}
}
function Invoke-Registration([string]$Action) {
    $request = $requests[$Action]
    [IO.File]::WriteAllText($request.path, $request.body, [Text.UTF8Encoding]::new($false))
    $output = @(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $request.script)
    Check ($LASTEXITCODE -eq 0 -and $output.Count -gt 0) 'Production bootstrap failed to execute'
    $envelope = $output[-1] | ConvertFrom-Json
    $reply = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($envelope.response_utf8_base64)) | ConvertFrom-Json
    Check ($reply.ok) ('Production registration failed: ' + $reply.error)
    Check (-not [IO.File]::Exists($request.path)) 'Production bootstrap must clean up its request'
    return $reply
}
function Wait-TaskLaunch {
    $before = [DateTime]::UtcNow
    $task = $folder.GetTask($taskName)
    $task.Run($null) | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    do {
        Start-Sleep -Milliseconds 200
        try {
            $state = Read-State
            $record = [IO.File]::ReadAllText($diagnosticPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ([DateTime]::Parse($record.time_utc).ToUniversalTime() -le $before) { continue }
            if ($record.result.reason -eq 'invoked') { continue }
            Check ($record.result.ok -and $record.result.would_launch -and $record.result.reason -eq 'started' -and $record.marker_acknowledged) ('Task launcher failed to confirm startup: ' + ($record | ConvertTo-Json -Compress -Depth 5))
            if (-not $state.was_running -or [int]$state.pid -ne [int]$record.child_pid) { continue }
            $game = Get-Process -Id ([int]$state.pid) -ErrorAction Stop
            Check ($game.Path -ieq $expected.launch.executable) 'Session PID must belong to the intended window executable'
            $game.Refresh()
            if ($game.MainWindowHandle -eq [IntPtr]::Zero -or -not $game.Responding) { continue }
            return @{process=$game; diagnostic=$record; handle=$game.MainWindowHandle.ToInt64(); task_last_result=$folder.GetTask($taskName).LastTaskResult}
        } catch [System.Management.Automation.ItemNotFoundException] { }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'The scheduled task did not open a responsive game window within 40 seconds.'
}
$initial = Read-State
Check ($initial.owner -ceq 'moonshade-potion-shop' -and $initial.enabled -eq $true -and $initial.was_running -eq $false) 'Start from the real enabled, previously closed marker'
$existing = Get-Process -Id ([int]$initial.pid) -ErrorAction SilentlyContinue
Check ($null -eq $existing) 'Do not close or interfere with a pre-existing process'
Invoke-Registration 'install' | Out-Null
$query = Invoke-Registration 'query'
Check ($query.exists -and $query.configured -and $query.registration -ceq 'login_task' -and $query.command -ceq $expected.registration.command) 'Query must confirm the actual matching enabled login task'
Check ([IO.File]::ReadAllText($expected.registration.launcher_path, [Text.Encoding]::UTF8) -ceq [IO.File]::ReadAllText((Join-Path $project 'native\windows\ResumeLogin.ps1'), [Text.Encoding]::UTF8).Replace("`r`n", "`n")) 'Installed helper must match the production source'
Record 'production install and query' $query
Invoke-Registration 'remove' | Out-Null
$off = Invoke-Registration 'query'
Check (-not $off.exists) 'Disabling must remove both this user login task and legacy Run entry'
Record 'production disable removes startup' $off
Invoke-Registration 'install' | Out-Null
$query = Invoke-Registration 'query'
Check ($query.exists -and $query.configured) 'Re-enabling must recreate a configured login task'
$task = $folder.GetTask($taskName)
[IO.File]::WriteAllText((Join-Path $proof 'installed-task.xml'), $task.Xml, [Text.UTF8Encoding]::new($false))
Record 'production re-enable' $query
$first = Wait-TaskLaunch
$game = $first.process
Record 'task opens previously closed real game' @{pid=$game.Id; window_handle=$first.handle; responding=$game.Responding; diagnostic=$first.diagnostic}
Check ($game.CloseMainWindow()) 'The actual game must accept a normal window close request'
Check ($game.WaitForExit(15000)) 'The actual game must save and close normally'
$closed = Read-State
Check ($closed.enabled -and -not $closed.was_running) 'Normal close must preserve startup while recording the closed session'
Check ((Invoke-Registration 'query').exists) 'Normal close must retain the registered task'
Record 'real normal close retains startup' @{enabled=$closed.enabled; was_running=$closed.was_running; pid=$closed.pid}
$second = Wait-TaskLaunch
Check ($second.process.Id -ne $game.Id) 'The task must open a new game after normal manual close'
Record 'task reopens after real manual close' @{pid=$second.process.Id; window_handle=$second.handle; responding=$second.process.Responding; diagnostic=$second.diagnostic}
$duplicateBefore = [DateTime]::UtcNow
# Allow the first task helper to finish before demanding another task instance.
$deadline = [DateTime]::UtcNow.AddSeconds(10)
while ($folder.GetTask($taskName).State -eq 4 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
$folder.GetTask($taskName).Run($null) | Out-Null
$deadline = [DateTime]::UtcNow.AddSeconds(15)
do {
    Start-Sleep -Milliseconds 200
    $duplicate = [IO.File]::ReadAllText($diagnosticPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ([DateTime]::Parse($duplicate.time_utc).ToUniversalTime() -gt $duplicateBefore -and $duplicate.result.reason -eq 'already_running') { break }
} while ([DateTime]::UtcNow -lt $deadline)
Check ($duplicate.result.reason -eq 'already_running' -and -not $duplicate.result.would_launch) 'Another task execution must skip the running game'
Check ((Read-State).pid -eq $second.process.Id -and -not $second.process.HasExited) 'Duplicate launch must retain the original session'
$games = @(Get-CimInstance Win32_Process -Filter "Name like 'Godot%exe'" | Where-Object { $_.ExecutablePath -ieq $expected.launch.executable -and $_.CommandLine.Contains($project) -and $_.CommandLine -notmatch '--headless|--script|--editor' })
Check ($games.Count -eq 1 -and $games[0].ProcessId -eq $second.process.Id) 'Exactly one playable game process must remain'
Record 'task duplicate launch is skipped' @{pid=$second.process.Id; playable_process_count=$games.Count; diagnostic=$duplicate}
$task = $folder.GetTask($taskName)
Record 'final task and visible game' @{task=$taskName; enabled=$task.Enabled; last_run=$task.LastRunTime.ToString('o'); last_result=$task.LastTaskResult; game_pid=$second.process.Id; session_id=$second.process.SessionId; responding=$second.process.Responding}
Write-Output 'LIVE LOGIN STARTUP PASS: production install/query/remove/reinstall, real enabled closed-state task launch, normal game close, task relaunch, duplicate skip, responsive visible window. Actual logoff/reboot not performed.'
