# Isolated regression: hidden fixture console, never the real game's console.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$proof = Join-Path $project ('.verification\startup-console-20261026\native-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($proof) | Out-Null
$source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;
public static class LoginConsoleProbe {
    [DllImport("kernel32.dll")] static extern bool AllocConsole();
    [DllImport("kernel32.dll")] static extern bool FreeConsole();
    [DllImport("kernel32.dll")] static extern bool AttachConsole(uint pid);
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int command);
    static JavaScriptSerializer json = new JavaScriptSerializer();
    static string Quote(string path) {
        if (path.Contains("\"") || path.EndsWith("\\")) throw new Exception("Invalid fixture path");
        return "\"" + path + "\"";
    }
    [STAThread] public static int Main(string[] args) {
        try {
            if (args.Length > 0 && args[0] == "--harness") {
                string folder = args[3];
                if (!AllocConsole()) throw new Exception("Fixture must own its own console");
                ShowWindow(GetConsoleWindow(), 0); // Only this new fixture's console.
                var info = new ProcessStartInfo(args[1]);
                info.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(args[2]) + " -StatePath " + Quote(Path.Combine(folder,"login_resume.json"));
                info.UseShellExecute = false;
                info.CreateNoWindow = false; // Reproduce console inheritance deliberately.
                info.RedirectStandardOutput = true;
                info.RedirectStandardError = true;
                var helper = Process.Start(info);
                if (!helper.WaitForExit(20000)) throw new Exception("Fixture helper timeout");
                var child = json.DeserializeObject(File.ReadAllText(Path.Combine(folder,"probe.json"))) as System.Collections.Generic.Dictionary<string,object>;
                var process = Process.GetProcessById(Convert.ToInt32(child["pid"]));
                bool survived = !process.HasExited;
                var record = new {helper_exit=helper.ExitCode, child_survived_helper_exit=survived,
                    helper_stdout=helper.StandardOutput.ReadToEnd(), helper_stderr=helper.StandardError.ReadToEnd()};
                if (!process.WaitForExit(10000)) throw new Exception("Fixture child did not self-exit");
                File.WriteAllText(Path.Combine(folder,"harness.json"),json.Serialize(record));
                FreeConsole();
                return 0;
            }
            // Model Godot GUI startup: it explicitly attempts parent-console attachment.
            bool attached = AttachConsole(0xffffffff);
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string statePath = Path.Combine(root,"login_resume.json");
            var state = json.DeserializeObject(File.ReadAllText(statePath)) as System.Collections.Generic.Dictionary<string,object>;
            state["pid"] = Process.GetCurrentProcess().Id;
            state["was_running"] = true;
            File.WriteAllText(Path.Combine(root,"probe.json"),json.Serialize(new {attached=attached, console_handle=GetConsoleWindow().ToInt64(), pid=Process.GetCurrentProcess().Id}));
            File.WriteAllText(statePath,json.Serialize(state));
            Thread.Sleep(5000); // Survive helper exit, then self-exit without input.
            return 0;
        } catch (Exception ex) {
            File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"failure.txt"),ex.ToString());
            return 1;
        }
    }
}
'@
$codePath = Join-Path $proof 'Probe.cs'
[IO.File]::WriteAllText($codePath,$source,[Text.UTF8Encoding]::new($false))
$executable = Join-Path $proof 'Probe.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /reference:System.Web.Extensions.dll /out:$executable $codePath
if ($LASTEXITCODE -ne 0) {throw 'Native fixture compilation failed'}
$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$fixed = [IO.File]::ReadAllText((Join-Path $project 'native\windows\ResumeLogin.ps1'),[Text.Encoding]::UTF8)
foreach ($scenario in @('before','after')) {
    $folder = Join-Path $proof $scenario
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $probe = Join-Path $folder 'Probe.exe'
    Copy-Item -LiteralPath $executable -Destination $probe
    $helperPath = Join-Path $folder 'ResumeLogin.ps1'
    $helper = if ($scenario -eq 'before') {$fixed.Replace('[MoonshadeLoginConsoleV1]::FreeConsole() | Out-Null','# Before: helper still owns a console')} else {$fixed}
    [IO.File]::WriteAllText($helperPath,$helper,[Text.UTF8Encoding]::new($false))
    $marker = @{owner='moonshade-potion-shop';version=1;enabled=$true;was_running=$false;executable=$probe;args=@('--','--autostart');pid=0;started_at=0}
    [IO.File]::WriteAllText((Join-Path $folder 'login_resume.json'),($marker | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    $driver = Start-Process -FilePath $executable -ArgumentList @('--harness',('"'+$powershell+'"'),('"'+$helperPath+'"'),('"'+$folder+'"')) -WindowStyle Hidden -PassThru
    if (-not $driver.WaitForExit(35000) -or $driver.ExitCode -ne 0) {throw ('Native fixture failed: ' + $folder)}
    $probeResult = Get-Content -LiteralPath (Join-Path $folder 'probe.json') -Raw | ConvertFrom-Json
    $harness = Get-Content -LiteralPath (Join-Path $folder 'harness.json') -Raw | ConvertFrom-Json
    $diagnostic = Get-Content -LiteralPath (Join-Path $folder 'login_resume.last-result.json') -Raw | ConvertFrom-Json
    if ($probeResult.attached -ne ($scenario -eq 'before')) {throw ('Unexpected console attachment in ' + $scenario)}
    if (($scenario -eq 'after') -and $probeResult.console_handle -ne 0) {throw 'Fixed child must have no console'}
    if ($harness.helper_exit -ne 0 -or -not $harness.child_survived_helper_exit -or -not $diagnostic.marker_acknowledged -or $diagnostic.result.reason -ne 'started') {throw 'Helper exit or acknowledgement regression'}
    if (($harness.helper_stdout | ConvertFrom-Json).reason -ne 'started') {throw 'Captured diagnostics must remain available after detachment'}
    Write-Output ('PASS '+$scenario+': attached='+$probeResult.attached+'; survives helper exit; acknowledged; stdout preserved')
}
Write-Output ('LOGIN CONSOLE DETACHMENT PASS: '+$proof+'; no player save, registry, actual game or desktop input')
