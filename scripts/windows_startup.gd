extends RefCounted
## Opt-in, current-user login registration. Tests inject an in-memory backend.
const VALUE_NAME := "MoonshadePotionShop"
const RUN_KEY := "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const LAUNCHER_SOURCE := "res://native/windows/ResumeLogin.ps1"
const MAX_RUN_COMMAND := 260 # Microsoft Run/RunOnce command-line limit.
const MAX_PROCESS_COMMAND := 32767 # CreateProcessW, including its terminating null.
const LOGIN_SCRIPT := """[CmdletBinding()]
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
    $result | ConvertTo-Json -Compress
    if ($Ok) { exit 0 } else { exit 1 }
}
function Is-AbsolutePath([string]$Value) {
    return $Value -match '^[a-zA-Z]:[\\\\/]' -or $Value -match '^\\\\\\\\[^\\\\]+\\\\[^\\\\]+'
}
function Quote-Argument([string]$Value) {
    $result = '"'
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) { $slashes++; continue }
        if ($character -eq [char]34) { $result += ('\\' * ($slashes * 2 + 1)) + '"' }
        else { $result += ('\\' * $slashes) + $character }
        $slashes = 0
    }
    return $result + ('\\' * ($slashes * 2)) + '"'
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
            if ([IO.Path]::GetFullPath($actual[$pathIndex + 1]).TrimEnd([char[]]'\\/') -ine [IO.Path]::GetFullPath($LaunchArguments[1]).TrimEnd([char[]]'\\/')) { return '' }
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
        $mutex = [Threading.Mutex]::new($false, ('Local\\MoonshadePotionShop.Resume.' + $identity))
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
    # The helper stays hidden. The user's game window is intentionally visible.
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
"""
var _backend: Callable
var _context: Dictionary
var _loaded := false
var _enabled := false
var _last := {"ok": true, "enabled": false, "status": "자동 다시 열기 설정 확인 전", "error": ""}

func _init(backend: Callable = Callable(), context: Dictionary = {}) -> void:
	_backend = backend
	_context = context.duplicate(true)

func enabled() -> bool:
	return _enabled # No registry query during UI refresh.

func status() -> Dictionary:
	return _last.duplicate(true)

func refresh() -> Dictionary:
	if _loaded: return status()
	_loaded = true
	var response := _request("query", {})
	if not response.get("ok", false): return _finish(false, str(response.get("error", "설정을 확인하지 못했어요.")))
	_enabled = bool(response.get("exists", false))
	var message := "꺼짐 · 로그인 때 게임을 다시 열지 않아요."
	if _enabled:
		message = "켜짐 · 종료 여부와 관계없이 Windows 로그인마다 열어요."
		var expected := registration_spec()
		if response.get("registration", "") == "legacy_run":
			message = "이전 자동 실행 등록이에요 · 다시 켜면 로그인 작업으로 갱신해요."
		elif not response.get("configured", true) or not expected.get("ok", false) or str(response.get("command", "")) != str(expected.get("command", "")):
			message = "등록 경로가 현재 위치와 달라요. 다시 켜면 현재 위치로 갱신해요."
	return _finish(true, "", message)

func set_enabled(value: bool) -> Dictionary:
	# Explicit user actions only. No constructor, model tick or UI refresh installs.
	if value:
		var launch := launch_spec()
		if not launch.get("ok", false): return _finish(false, str(launch.error))
		var registration := registration_spec()
		if not registration.get("ok", false): return _finish(false, str(registration.error))
		var payload: Dictionary = registration.duplicate(true)
		payload["script"] = LOGIN_SCRIPT
		if payload.script.is_empty(): return _finish(false, "로그인 도우미 파일을 찾을 수 없어요.")
		var response := _request("install", payload)
		if not response.get("ok", false): return _finish(false, str(response.get("error", "자동 다시 열기를 등록하지 못했어요.")))
	else:
		# Unregister remains available even after the executable/project moved.
		var response := _request("remove", {})
		if not response.get("ok", false): return _finish(false, str(response.get("error", "자동 다시 열기를 해제하지 못했어요.")))
	_enabled = value
	_loaded = true
	return _finish(true, "", "켜짐 · 종료 여부와 관계없이 Windows 로그인마다 열어요." if value else "꺼짐 · 로그인 때 게임을 다시 열지 않아요.")

func launch_spec() -> Dictionary:
	if str(_context.get("os", OS.get_name())) != "Windows": return _spec_error("Windows에서만 자동 다시 열기를 지원해요.")
	var executable := str(_context.get("executable", OS.get_executable_path())).replace("/", "\\")
	var exported := bool(_context.get("exported", not OS.has_feature("editor")))
	var args: Array[String] = []
	if not exported:
		# The console launcher is useful for development, but must not appear at login.
		if executable.to_lower().ends_with("_console.exe"):
			executable = executable.left(executable.length() - "_console.exe".length()) + ".exe"
		var project := str(_context.get("project", ProjectSettings.globalize_path("res://"))).replace("/", "\\").trim_suffix("\\")
		if not _absolute_windows_path(project) or not _exists(project.path_join("project.godot")):
			return _spec_error("게임 폴더가 이동했거나 project.godot을 찾을 수 없어요. 현재 위치에서 다시 설정해 주세요.")
		args.assign(["--path", project, "--", "--autostart"])
	else: args.assign(["--", "--autostart"])
	if not _absolute_windows_path(executable) or not executable.to_lower().ends_with(".exe") or executable.to_lower().ends_with("_console.exe") or not _exists(executable):
		return _spec_error("창 버전 실행 파일을 찾을 수 없어요. 게임 실행 파일이 이동했는지 확인해 주세요.")
	return {"ok": true, "executable": executable, "args": args, "command": windows_command(executable, args), "error": ""}

func registration_spec() -> Dictionary:
	if str(_context.get("os", OS.get_name())) != "Windows": return _spec_error("Windows에서만 자동 다시 열기를 지원해요.")
	var launcher := str(_context.get("launcher_path", ProjectSettings.globalize_path("user://resume-login.ps1"))).replace("/", "\\")
	var session := str(_context.get("session_path", ProjectSettings.globalize_path("user://login_resume.json"))).replace("/", "\\")
	var powershell := str(_context.get("powershell", OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe"))).replace("/", "\\")
	if not _absolute_windows_path(launcher) or not _absolute_windows_path(session): return _spec_error("로그인 도우미의 저장 경로가 올바르지 않아요.")
	if not _absolute_windows_path(powershell) or not _exists(powershell): return _spec_error("Windows PowerShell 실행 파일을 찾을 수 없어요.")
	var args: Array[String] = ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", launcher]
	if session != launcher.get_base_dir().path_join("login_resume.json").replace("/", "\\"):
		args.append_array(["-StatePath", session])
	var command := windows_command(powershell, args)
	if command.length() > MAX_RUN_COMMAND: return _spec_error("자동 시작 경로가 너무 길어요(260자 초과). 게임과 사용자 데이터의 더 짧은 경로가 필요해요.")
	return {"ok": true, "command": command, "launcher_path": launcher, "session_path": session, "powershell": powershell, "task_arguments": command.substr(quote_windows(powershell).length() + 1), "error": ""}

static func quote_windows(value: String) -> String:
	# Windows argv quoting: double backslashes before quotes and at a quoted tail.
	var output := "\""
	var slashes := 0
	for character in value:
		if character == "\\":
			slashes += 1
			continue
		if character == "\"": output += "\\".repeat(slashes * 2 + 1) + "\""
		else: output += "\\".repeat(slashes) + character
		slashes = 0
	return output + "\\".repeat(slashes * 2) + "\""

static func windows_command(executable: String, args: Array[String]) -> String:
	var parts := PackedStringArray([quote_windows(executable)])
	for argument in args:
		# Fixed flags need no quotes; path/data arguments always receive argv quoting.
		parts.append(argument if argument.begins_with("-") and not argument.contains(" ") and not argument.contains("\"") else quote_windows(argument))
	return " ".join(parts)

func _exists(path: String) -> bool:
	var check: Callable = _context.get("file_exists", Callable())
	return bool(check.call(path)) if check.is_valid() else FileAccess.file_exists(path)

static func _absolute_windows_path(path: String) -> bool:
	if path.contains("\"") or path.contains("\n") or path.contains("\r"): return false
	return (path.length() >= 3 and path[1] == ":" and path[2] == "\\") or path.begins_with("\\\\")

func _request(action: String, payload: Dictionary) -> Dictionary:
	if str(_context.get("os", OS.get_name())) != "Windows": return {"ok": false, "error": "Windows에서만 자동 다시 열기를 지원해요."}
	if _backend.is_valid():
		var result: Variant = _backend.call(action, payload.duplicate(true))
		return result if result is Dictionary else {"ok": false, "error": "자동 시작 응답을 확인하지 못했어요."}
	# Context cannot override the live guards. Only a test backend is allowed there.
	if not _native_allowed():
		return {"ok": false, "error": "격리 검사에서는 실제 시작프로그램을 변경하지 않아요."}
	return _native_request(action, payload)

func _native_allowed() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return OS.get_name() == "Windows" and DisplayServer.get_name() != "headless" and not "--smoke-test" in OS.get_cmdline_user_args() and not (tree != null and tree.has_meta("isolated_preview")) and not bool(_context.get("isolated", false)) and not bool(_context.get("smoke", false))

func _native_request(action: String, payload: Dictionary) -> Dictionary:
	if not _native_allowed(): return {"ok": false, "error": "격리 검사에서는 실제 시작프로그램을 변경하지 않아요."}
	var powershell := str(_context.get("powershell", OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")))
	if not FileAccess.file_exists(powershell): return {"ok": false, "error": "Windows PowerShell 실행 파일을 찾을 수 없어요."}
	var data := payload.duplicate(true)
	data["action"] = action
	# The full embedded login script belongs in this file, never in an already
	# base64-encoded payload inside another encoded process command.
	var prepared := _prepare_request(data, ProjectSettings.globalize_path("user://native"))
	if not prepared.ok: return prepared
	var request_path: String = prepared.path
	var arguments := _native_arguments(request_path)
	var command_length := _native_command_length(powershell, arguments)
	if command_length > MAX_PROCESS_COMMAND:
		DirAccess.remove_absolute(request_path)
		return {"ok": false, "error": "Windows 자동 시작 요청 명령이 너무 길어요(%d자, 최대 %d자)." % [command_length, MAX_PROCESS_COMMAND]}
	var output: Array = []
	var code := OS.execute(powershell, arguments, output, false, false)
	# PowerShell's finally normally deletes it; also clean up when it cannot start.
	if FileAccess.file_exists(request_path): DirAccess.remove_absolute(request_path)
	if code != 0: return {"ok": false, "error": "Windows 자동 시작 PowerShell 실행에 실패했어요(종료 코드 %d)." % code}
	if output.is_empty(): return {"ok": false, "error": "Windows 자동 시작 요청에서 응답을 받지 못했어요."}
	return parse_response(output)

func _prepare_request(data: Dictionary, folder: String) -> Dictionary:
	var directory_error := DirAccess.make_dir_recursive_absolute(folder)
	if directory_error != OK: return {"ok": false, "error": "자동 시작 요청 폴더를 준비하지 못했어요: " + error_string(directory_error)}
	if not DirAccess.dir_exists_absolute(folder): return {"ok": false, "error": "자동 시작 요청 폴더 경로가 폴더가 아니에요."}
	var name := "startup-request-%d-%d-%d.json" % [OS.get_process_id(), get_instance_id(), Time.get_ticks_usec()]
	var path := folder.path_join(name)
	var temporary := path + ".tmp"
	if FileAccess.file_exists(path) or FileAccess.file_exists(temporary):
		return {"ok": false, "error": "자동 시작 요청 파일 이름이 겹쳤어요. 다시 시도해 주세요."}
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "자동 시작 요청 파일을 쓰지 못했어요: " + error_string(FileAccess.get_open_error())}
	var encoded := JSON.stringify(data)
	file.store_string(encoded)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": "자동 시작 요청 파일을 저장하지 못했어요: " + error_string(write_error)}
	# Unique destination: no existing file is replaced or temporarily removed.
	var publish_error := DirAccess.rename_absolute(temporary, path)
	if publish_error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": "자동 시작 요청 파일을 게시하지 못했어요: " + error_string(publish_error)}
	if FileAccess.get_file_as_bytes(path) != encoded.to_utf8_buffer():
		DirAccess.remove_absolute(path)
		return {"ok": false, "error": "자동 시작 요청 파일의 저장 내용을 확인하지 못했어요."}
	return {"ok": true, "path": path, "error": ""}

static func _native_arguments(request_path: String, transport_probe: bool = false) -> PackedStringArray:
	return PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", Marshalls.raw_to_base64(_native_script(request_path, transport_probe).to_utf16_buffer())])

static func _native_command_length(executable: String, arguments: PackedStringArray) -> int:
	# Quote every argument conservatively and allow the Windows extended-path
	# prefix plus the terminating null, even when Godot can omit those quotes.
	var length := quote_windows(executable).length() + 4 + 1
	for argument in arguments: length += 1 + quote_windows(argument).length()
	return length

static func _native_script(request_path: String, transport_probe: bool = false) -> String:
	return """
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$requestPath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s'))
$transportProbe = %s
function Respond([object]$Value) {
    # Godot OS.execute decodes stdout using Windows ACP. Keep that boundary
    # ASCII, then restore the actual response explicitly as UTF8 in GDScript.
    $json = $Value | ConvertTo-Json -Compress -Depth 20
    @{ok=$true; response_utf8_base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))} | ConvertTo-Json -Compress
}
$key = $null
function Get-OwnedTask([object]$Folder, [string]$Name, [string]$Sid) {
    try { $task = $Folder.GetTask($Name) }
    catch {
        if ($_.Exception.HResult -eq -2147024894) { return $null }
        throw
    }
    if ($task.Definition.RegistrationInfo.Description -cne 'moonshade-potion-shop login startup v2' -or
        $task.Definition.RegistrationInfo.Author -cne $Sid) { throw 'The login task name belongs to another application.' }
    return $task
}
function Is-CurrentUser([string]$User, [string]$Sid) {
    if ($User -eq $Sid) { return $true }
    try { return ([Security.Principal.NTAccount]::new($User)).Translate([Security.Principal.SecurityIdentifier]).Value -eq $Sid }
    catch { return $false }
}
try {
    $p = [IO.File]::ReadAllText($requestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($transportProbe) {
        # Isolated transport proof: parse and echo; no registry or game execution.
        Respond @{ok=$true; payload=$p}
    } elseif ($p.action -eq 'query') {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder('\\')
        $task = Get-OwnedTask $folder ('MoonshadePotionShop-' + $sid) $sid
        if ($null -ne $task) {
            $definition = $task.Definition
            $configured = $definition.Actions.Count -eq 1 -and $definition.Triggers.Count -eq 1 -and
                $definition.Triggers.Item(1).Type -eq 9 -and $definition.Triggers.Item(1).Enabled -and
                (Is-CurrentUser $definition.Triggers.Item(1).UserId $sid) -and $definition.Principal.LogonType -eq 3 -and
                $definition.Principal.RunLevel -eq 0 -and (Is-CurrentUser $definition.Principal.UserId $sid)
            $action = $definition.Actions.Item(1)
            Respond @{ok=$true; exists=[bool]$task.Enabled; configured=[bool]$configured; registration='login_task'; command=('"' + $action.Path + '" ' + $action.Arguments)}
        } else {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\\Microsoft\\Windows\\CurrentVersion\\Run', $false)
        $value = if ($null -ne $key) { $key.GetValue('MoonshadePotionShop', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
        Respond @{ok=$true; exists=($null -ne $value); command=[string]$value; registration='legacy_run'}
        }
    } elseif ($p.action -eq 'install') {
        if ([string]$p.command -eq '' -or ([string]$p.command).Length -gt 260) { throw 'Invalid login command length.' }
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder('\\')
        $name = 'MoonshadePotionShop-' + $sid
        $existing = Get-OwnedTask $folder $name $sid
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([string]$p.launcher_path)) | Out-Null
        [IO.File]::WriteAllText([string]$p.launcher_path, [string]$p.script, [Text.UTF8Encoding]::new($false))
        $definition = $service.NewTask(0)
        $definition.RegistrationInfo.Description = 'moonshade-potion-shop login startup v2'
        $definition.RegistrationInfo.Author = $sid
        $definition.Principal.UserId = $sid
        $definition.Principal.LogonType = 3
        $definition.Principal.RunLevel = 0
        $trigger = $definition.Triggers.Create(9)
        $trigger.UserId = $sid
        $trigger.Delay = 'PT10S'
        $definition.Settings.Enabled = $true
        $definition.Settings.Hidden = $true
        $definition.Settings.AllowDemandStart = $true
        $definition.Settings.StartWhenAvailable = $true
        $definition.Settings.DisallowStartIfOnBatteries = $false
        $definition.Settings.StopIfGoingOnBatteries = $false
        $definition.Settings.ExecutionTimeLimit = 'PT2M'
        $definition.Settings.MultipleInstances = 2
        $action = $definition.Actions.Create(0)
        $action.Path = [string]$p.powershell
        $action.Arguments = [string]$p.task_arguments
        $action.WorkingDirectory = [IO.Path]::GetDirectoryName([string]$p.launcher_path)
        $registered = $folder.RegisterTaskDefinition($name, $definition, 6, $sid, $null, 3, $null)
        if (-not $registered.Enabled) { throw 'The login task was not enabled.' }
        # Migrate only this game's old Run value, after successful task registration.
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\\Microsoft\\Windows\\CurrentVersion\\Run', $true)
        if ($null -ne $key) { $key.DeleteValue('MoonshadePotionShop', $false) }
        Respond @{ok=$true}
    } elseif ($p.action -eq 'remove') {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder('\\')
        $name = 'MoonshadePotionShop-' + $sid
        $task = Get-OwnedTask $folder $name $sid
        if ($null -ne $task) { $folder.DeleteTask($name, 0) }
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\\Microsoft\\Windows\\CurrentVersion\\Run', $true)
        if ($null -ne $key) { $key.DeleteValue('MoonshadePotionShop', $false) }
        Respond @{ok=$true}
    } else { throw 'Unknown login registration operation.' }
} catch { Respond @{ok=$false; error=$_.Exception.Message} }
finally {
    if ($null -ne $key) { $key.Dispose() }
    if ([IO.File]::Exists($requestPath)) { [IO.File]::Delete($requestPath) }
}
""" % [Marshalls.utf8_to_base64(request_path), "$true" if transport_probe else "$false"]

static func parse_response(output: Array) -> Dictionary:
	# Windows PowerShell may print a provider diagnostic before our JSON line.
	# Only accept the final structured response, never evaluate console text.
	var lines := PackedStringArray()
	for part in output: lines.append_array(str(part).split("\n"))
	for i in range(lines.size() - 1, -1, -1):
		var line := lines[i].strip_edges().trim_prefix(String.chr(0xfeff))
		if not line.begins_with("{") or not line.ends_with("}"): continue
		var parser := JSON.new()
		if parser.parse(line) == OK and parser.data is Dictionary and parser.data.get("ok") is bool:
			if parser.data.get("response_utf8_base64") is String:
				var restored := JSON.new()
				var response := Marshalls.base64_to_raw(parser.data.response_utf8_base64).get_string_from_utf8()
				if restored.parse(response) == OK and restored.data is Dictionary and restored.data.get("ok") is bool: return restored.data
				return {"ok": false, "error": "Windows 자동 시작 UTF-8 응답을 확인하지 못했어요."}
			return parser.data
	return {"ok": false, "error": "Windows 자동 시작 응답을 확인하지 못했어요."}

func _finish(ok: bool, error: String = "", message: String = "") -> Dictionary:
	_last = {"ok": ok, "enabled": _enabled, "status": message if ok else error, "error": error}
	return status()

static func _spec_error(message: String) -> Dictionary:
	return {"ok": false, "error": message, "status": message}
