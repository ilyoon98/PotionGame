# Update only this game's already-enabled installed helper. No game restart.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$proof = Join-Path $project '.verification\startup-console-20261026'
[IO.Directory]::CreateDirectory($proof) | Out-Null
$config = [IO.File]::ReadAllText((Join-Path $project 'project.godot'),[Text.Encoding]::UTF8)
$appName = [regex]::Match($config,'(?m)^config/name="([^"\r\n]+)"').Groups[1].Value
if ($appName -eq '' -or $appName.Contains('\') -or $appName.Contains('/')) {throw 'Invalid application data folder name'}
$folder = Join-Path (Join-Path $env:APPDATA 'Godot\app_userdata') $appName
$markerPath = Join-Path $folder 'login_resume.json'
$markerBytes = [IO.File]::ReadAllBytes($markerPath)
$marker = [Text.Encoding]::UTF8.GetString($markerBytes) | ConvertFrom-Json
if ($marker.owner -cne 'moonshade-potion-shop' -or $marker.version -ne 1 -or $marker.enabled -ne $true) {throw 'Expected this game with startup already enabled'}
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$task = $service.GetFolder('\').GetTask(('MoonshadePotionShop-' + $sid))
$definition = $task.Definition
$helperPath = Join-Path $folder 'resume-login.ps1'
$principal = $definition.Principal.UserId
$principalSid = if ($principal.StartsWith('S-1-')) {$principal} else {([Security.Principal.NTAccount]::new($principal)).Translate([Security.Principal.SecurityIdentifier]).Value}
if (-not $task.Enabled -or $definition.Actions.Count -ne 1 -or
    $definition.RegistrationInfo.Description -ne 'moonshade-potion-shop login startup v2' -or
    $definition.RegistrationInfo.Author -ne $sid -or $principalSid -ne $sid -or
    -not $definition.Actions.Item(1).Arguments.Contains(('"'+$helperPath+'"'))) {throw 'Startup task ownership/path mismatch'}
$before = [IO.File]::ReadAllText($helperPath,[Text.Encoding]::UTF8)
if (-not $before.Contains('moonshade-potion-shop') -or -not $before.Contains('function Check-RecordedIdentity')) {throw 'Installed script is not the expected game launcher'}
$fixed = [IO.File]::ReadAllText((Join-Path $project 'native\windows\ResumeLogin.ps1'),[Text.Encoding]::UTF8)
if (-not $fixed.Contains('[MoonshadeLoginConsoleV1]::FreeConsole() | Out-Null')) {throw 'Detachment repair missing'}
$backup = Join-Path $proof ('installed-helper-before-' + [Guid]::NewGuid().ToString('N') + '.ps1')
Copy-Item -LiteralPath $helperPath -Destination $backup
[IO.File]::WriteAllText((Join-Path $proof 'installed-task-before.xml'),$task.Xml,[Text.UTF8Encoding]::new($false))
$gameBefore = Get-Process -Id ([int]$marker.pid) -ErrorAction SilentlyContinue
$temporary = $helperPath + '.console-fix.tmp'
[IO.File]::WriteAllText($temporary,$fixed,[Text.UTF8Encoding]::new($false))
[IO.File]::Replace($temporary,$helperPath,$backup)
if ([IO.File]::ReadAllText($helperPath,[Text.Encoding]::UTF8) -cne $fixed) {throw 'Installed helper differs from production source'}
if ($task.Xml -cne $service.GetFolder('\').GetTask($task.Name).Xml) {throw 'Task changed unexpectedly'}
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($markerPath)) -cne [Convert]::ToBase64String($markerBytes)) {throw 'Session metadata changed during installation; no marker was written by this repair'}
$gameAfter = Get-Process -Id ([int]$marker.pid) -ErrorAction SilentlyContinue
$result = @{passed=$true; helper_path=$helperPath; backup=$backup; startup_enabled=$task.Enabled;
    task_unchanged=$true; session_marker_unchanged=$true; game_restarted=$false;
    game_pid=[int]$marker.pid; original_game_alive=($null -ne $gameBefore -and $null -ne $gameAfter);
    sha256=(Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash; actual_reboot_tested=$false}
[IO.File]::WriteAllText((Join-Path $proof 'installed-repair.json'),($result|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
