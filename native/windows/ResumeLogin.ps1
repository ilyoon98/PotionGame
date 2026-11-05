[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$StatePath = '',
    [string]$ProcessFixture = ''
)
# Login helper only. Startup registration and the primary session marker stay unchanged.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if ($StatePath -eq '') { $StatePath = Join-Path $PSScriptRoot 'login_resume.json' }
$script:childId = 0
$script:acknowledged = $false
$script:emitResult = $DryRun -or [Console]::IsOutputRedirected

function Write-Diagnostic([object]$Result) {
    if ($DryRun) { return }
    try {
        $entry = @{time_utc=[DateTime]::UtcNow.ToString('o'); helper_pid=$PID; child_pid=$script:childId; marker_acknowledged=$script:acknowledged; result=$Result}
        $path = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($StatePath))) 'login_resume.last-result.json'
        # Bounded diagnostic, separate from intent and game progress. Logging
        # failure must never prevent the game from opening.
        [IO.File]::WriteAllText($path, ($entry | ConvertTo-Json -Compress -Depth 5), [Text.UTF8Encoding]::new($false))
    } catch { }
}

function Finish([string]$Reason, [bool]$WouldLaunch, [bool]$Ok = $true, [string]$ErrorText = '') {
    $result = @{ok=$Ok; reason=$Reason; would_launch=$WouldLaunch; dry_run=[bool]$DryRun; error=$ErrorText}
    Write-Diagnostic $result
    # Interactive login tasks retain diagnostics in the bounded JSON file.
    # Only captured callers/dry runs need stdout after we detach the console.
    if ($script:emitResult) { $result | ConvertTo-Json -Compress }
    if ($Ok) { exit 0 } else { exit 1 }
}
function Is-AbsolutePath([string]$Value) {
    return $Value -match '^[a-zA-Z]:[\\/]' -or $Value -match '^\\\\[^\\]+\\[^\\]+'
}
function Quote-Argument([string]$Value) {
    $result = '"'
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) { $slashes++; continue }
        if ($character -eq [char]34) { $result += ('\' * ($slashes * 2 + 1)) + '"' }
        else { $result += ('\' * $slashes) + $character }
        $slashes = 0
    }
    return $result + ('\' * ($slashes * 2)) + '"'
}
function Get-RecordedProcess([int]$RecordedId) {
    if ($DryRun -and $ProcessFixture -ne '') {
        $fixture = [IO.File]::ReadAllText($ProcessFixture, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ([int]$fixture.pid -ne $RecordedId) { return $null }
        return $fixture
    }
    $process = Get-Process -Id $RecordedId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $null }
    try {
        $path = $process.Path
        $start = ($process.StartTime.ToUniversalTime() - [DateTime]::SpecifyKind([DateTime]'1970-01-01', [DateTimeKind]::Utc)).TotalSeconds
        $info = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = ' + $RecordedId) -ErrorAction SilentlyContinue
        return @{pid=$RecordedId; executable=$path; start_time=$start; command_line=[string]$info.CommandLine}
    } catch { return $null }
}
function Read-CommandArguments([string]$CommandLine) {
    if (-not ('MoonshadeResumeArgsV1' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MoonshadeResumeArgsV1 {
    [DllImport("shell32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern IntPtr CommandLineToArgvW(string value, out int count);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr value);
    public static string[] Split(string value) {
        int count;
        IntPtr buffer = CommandLineToArgvW(value, out count);
        if (buffer == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        try {
            var result = new string[count];
            for (int i=0; i<count; i++)
                result[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(buffer, i*IntPtr.Size));
            return result;
        } finally { LocalFree(buffer); }
    }
}
'@
    }
    return [MoonshadeResumeArgsV1]::Split($CommandLine)
}

function Is-OwnedState([object]$Record) {
    if ($Record.owner -isnot [string] -or $Record.owner -cne 'moonshade-potion-shop') { return $false }
    $version = $Record.version
    if ($version -isnot [int] -and $version -isnot [long] -and $version -isnot [double] -and $version -isnot [decimal]) { return $false }
    return -not [double]::IsNaN([double]$version) -and -not [double]::IsInfinity([double]$version) -and [double]$version -eq 1.0
}
function Same-EngineFamily([string]$RunningExecutable, [string]$LaunchExecutable, [bool]$Development) {
    if (-not (Is-AbsolutePath $RunningExecutable)) { return $false }
    $normalized = [IO.Path]::GetFullPath($RunningExecutable)
    if ($Development -and [IO.Path]::GetFileName($normalized) -like '*_console.exe') {
        $normalized = $normalized.Substring(0, $normalized.Length - '_console.exe'.Length) + '.exe'
    }
    return $normalized -ieq $LaunchExecutable
}
function Check-RecordedIdentity([object]$Record, [string]$RecordedExecutable, [object[]]$LaunchArguments, [bool]$ExactArguments) {
    $recordedId = 0
    $writtenAt = 0.0
    if (-not [int]::TryParse([string]$Record.pid, [ref]$recordedId) -or $recordedId -le 0 -or
        -not [double]::TryParse([Convert]::ToString($Record.started_at, [Globalization.CultureInfo]::InvariantCulture), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$writtenAt)) { return '' }
    if ([double]::IsNaN($writtenAt) -or [double]::IsInfinity($writtenAt)) { return '' }
    $existing = Get-RecordedProcess $recordedId
    if ($null -eq $existing -or [string]$existing.executable -eq '') { return '' }
    $samePath = [IO.Path]::GetFullPath([string]$existing.executable) -ieq [IO.Path]::GetFullPath($RecordedExecutable)
    $startTime = [double]$existing.start_time
    if (-not $samePath -or $startTime -gt $writtenAt -or $writtenAt -gt ($startTime + 60.0)) { return '' }
    if ([string]$existing.command_line -eq '') { return 'already_running_unverified' }
    $actual = @(Read-CommandArguments ([string]$existing.command_line))
    if ($ExactArguments) {
        if ($actual.Count -ne ($LaunchArguments.Count + 1)) { return '' }
        for ($i=0; $i -lt $LaunchArguments.Count; $i++) {
            if ($actual[$i + 1] -cne $LaunchArguments[$i]) { return '' }
        }
    } else {
        foreach ($toolFlag in @('--editor', '-e', '--headless', '--script', '-s', '--help', '-h', '--version')) {
            if ($actual -ccontains $toolFlag) { return '' }
        }
        if ($LaunchArguments.Count -eq 4) {
            $pathIndex = [Array]::IndexOf($actual, '--path')
            if ($pathIndex -lt 0 -or $pathIndex + 1 -ge $actual.Count -or -not (Is-AbsolutePath $actual[$pathIndex + 1])) { return 'already_running_unverified' }
            if ([IO.Path]::GetFullPath($actual[$pathIndex + 1]).TrimEnd([char[]]'\/') -ine [IO.Path]::GetFullPath($LaunchArguments[1]).TrimEnd([char[]]'\/')) { return '' }
        }
    }
    return 'already_running'
}

$mutex = $null
$acquired = $false
try {
    Write-Diagnostic @{reason='invoked'; ok=$true; would_launch=$false; dry_run=$false; error=''}
    if (-not $DryRun -and $ProcessFixture -ne '') { Finish 'invalid_fixture' $false $false 'Process fixtures are allowed only in dry-run mode.' }
    if (-not [IO.File]::Exists($StatePath)) { Finish 'no_state' $false }
    $state = [IO.File]::ReadAllText($StatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not (Is-OwnedState $state)) { Finish 'invalid_owner' $false $false 'Unsupported resume state.' }
    if ($state.enabled -isnot [bool] -or $state.was_running -isnot [bool]) { Finish 'invalid_flags' $false $false 'Resume flags must be booleans.' }
    if (-not $state.enabled) { Finish 'disabled' $false }
    if ($state.executable -isnot [string] -or -not (Is-AbsolutePath $state.executable)) { Finish 'invalid_executable' $false $false 'Executable path must be absolute.' }
    $executable = [IO.Path]::GetFullPath($state.executable)
    if (-not [IO.File]::Exists($executable) -or [IO.Path]::GetExtension($executable) -ine '.exe' -or [IO.Path]::GetFileName($executable) -like '*_console.exe') { Finish 'missing_executable' $false $false 'Window executable was moved or is missing.' }
    if ($state.args -isnot [Array]) { Finish 'invalid_args' $false $false 'Launch arguments must be an array.' }
    $arguments = @($state.args)
    foreach ($argument in $arguments) {
        if ($argument -isnot [string] -or $argument.Contains([char]0) -or $argument.Contains([char]10) -or $argument.Contains([char]13)) { Finish 'invalid_args' $false $false 'Launch arguments must be single-line strings.' }
    }
    $workingDirectory = [IO.Path]::GetDirectoryName($executable)
    if ($arguments.Count -eq 2 -and $arguments[0] -ceq '--' -and $arguments[1] -ceq '--autostart') {
        # Exported game. Never pass an editor switch or shell command.
    } elseif ($arguments.Count -eq 4 -and $arguments[0] -ceq '--path' -and $arguments[2] -ceq '--' -and $arguments[3] -ceq '--autostart') {
        if (-not (Is-AbsolutePath $arguments[1]) -or -not [IO.Directory]::Exists($arguments[1]) -or -not [IO.File]::Exists((Join-Path $arguments[1] 'project.godot'))) { Finish 'missing_project' $false $false 'Project folder was moved or is missing.' }
        $workingDirectory = [IO.Path]::GetFullPath($arguments[1])
    } else { Finish 'invalid_args' $false $false 'Only game autostart arguments are supported.' }
    if (-not $DryRun) {
        $hash = [Security.Cryptography.SHA256]::Create()
        try { $identity = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($StatePath).ToLowerInvariant()))).Replace('-', '') }
        finally { $hash.Dispose() }
        $mutex = [Threading.Mutex]::new($false, ('Local\MoonshadePotionShop.Resume.' + $identity))
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { Finish 'launcher_busy' $false }
    }
    # Current runtime identity is independent of the future autostart arguments.
    $recordedExecutable = $executable
    $checkPrimary = $true
    if ($state.running_executable -is [string]) {
        $recordedExecutable = [string]$state.running_executable
        $checkPrimary = Same-EngineFamily $recordedExecutable $executable ($arguments.Count -eq 4)
    }
    if ($checkPrimary) {
        $duplicate = Check-RecordedIdentity $state $recordedExecutable $arguments $false
        if ($duplicate -ne '') { Finish $duplicate $false }
    }
    $pendingPath = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($StatePath))) 'login_resume.pending.json'
    if ([IO.File]::Exists($pendingPath)) {
        try {
            $pending = [IO.File]::ReadAllText($pendingPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ((Is-OwnedState $pending) -and $pending.executable -is [string] -and $pending.args -is [Array] -and
                [IO.Path]::GetFullPath($pending.executable) -ieq $executable) {
                $pendingArguments = @($pending.args)
                $sameLaunch = $pendingArguments.Count -eq $arguments.Count
                if ($sameLaunch) {
                    for ($i=0; $i -lt $arguments.Count; $i++) {
                        if ($pendingArguments[$i] -isnot [string] -or $pendingArguments[$i] -cne $arguments[$i]) { $sameLaunch = $false; break }
                    }
                }
                if ($sameLaunch) {
                    $duplicate = Check-RecordedIdentity $pending $executable $arguments $true
                    if ($duplicate -ne '') { Finish 'already_running_pending' $false }
                }
            }
        } catch { }
    }
    if ($DryRun) { Finish 'ready' $true }
    $argumentLine = (($arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
    # Godot's GUI executable explicitly attaches to its parent's console.
    # WindowStyle Hidden alone does not break that connection: the game keeps
    # the login terminal alive and closing it can terminate the game.
    # Detach only this helper before creating the child; never detach or hide
    # an already running game. Captured stdout pipes remain available to tests.
    if (-not ('MoonshadeLoginConsoleV1' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class MoonshadeLoginConsoleV1 {
    [DllImport("kernel32.dll")] public static extern bool FreeConsole();
}
'@
    }
    [MoonshadeLoginConsoleV1]::FreeConsole() | Out-Null
    # The user's game window is intentionally visible, with no parent console.
    $child = Start-Process -FilePath $executable -ArgumentList $argumentLine -WorkingDirectory $workingDirectory -WindowStyle Normal -PassThru
    $script:childId = $child.Id
    # A pending identity covers loading before the game writes its own PID.
    try {
        $startTime = ($child.StartTime.ToUniversalTime() - [DateTime]::SpecifyKind([DateTime]'1970-01-01', [DateTimeKind]::Utc)).TotalSeconds
        $pending = @{owner='moonshade-potion-shop'; version=1; pid=$child.Id; started_at=$startTime; executable=$executable; args=$arguments}
        $temporary = $pendingPath + '.tmp.' + $PID
        [IO.File]::WriteAllText($temporary, ($pending | ConvertTo-Json -Compress -Depth 5), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($pendingPath)) { [IO.File]::Replace($temporary, $pendingPath, $null) }
        else { [IO.File]::Move($temporary, $pendingPath) }
    } catch { }
    $until = [DateTime]::UtcNow.AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 100
        try {
            $current = [IO.File]::ReadAllText($StatePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ([int]$current.pid -eq $child.Id -and $current.was_running -eq $true) { $script:acknowledged = $true; break }
        } catch { }
    } while ([DateTime]::UtcNow -lt $until -and -not $child.HasExited)
    if (-not $script:acknowledged -and $child.HasExited) { Finish 'child_exited' $true $false ('Game exited before recording its session. Exit code: ' + $child.ExitCode) }
    if (-not $script:acknowledged) { Finish 'launched_unconfirmed' $true }
    Finish 'started' $true
} catch { Finish 'error' $false $false $_.Exception.Message }
finally {
    if ($acquired -and $null -ne $mutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
