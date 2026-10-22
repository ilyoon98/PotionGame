param([Parameter(Mandatory=$true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$verifyDir = Join-Path $projectDir '.verification'
$statusPath = Join-Path $verifyDir 'desktop-input-status.json'
$commandPath = Join-Path $verifyDir 'desktop-input-command.txt'
New-Item -ItemType Directory -Path $verifyDir -Force | Out-Null
foreach ($path in @($statusPath, $commandPath)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DesktopInputProbe {
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X,Y; }
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point p);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] public static extern IntPtr GetStyle(IntPtr h,int index);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window,System.Text.StringBuilder text,int count);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window,uint msg,IntPtr w,IntPtr l);
}
'@
[DesktopInputProbe]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
$oldCursor = New-Object DesktopInputProbe+Point
if (-not [DesktopInputProbe]::GetCursorPos([ref]$oldCursor)) { throw 'Interactive desktop is required.' }
$backdropStatus = Join-Path $verifyDir 'desktop-backdrop.json'
if (Test-Path -LiteralPath $backdropStatus) { Remove-Item -LiteralPath $backdropStatus }
$backdropExecutable = Join-Path $verifyDir 'desktop-input-target.exe'
$compilerPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compilerPath /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "/out:$backdropExecutable" (Join-Path $PSScriptRoot 'desktop_input_target.cs')
if ($LASTEXITCODE -ne 0) { throw 'Test target compilation failed.' }
$backdrop = $null
$backdropProcess = $null
$previousAppData = $env:APPDATA
$gameProcess = $null
function Pump([int]$milliseconds) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.ElapsedMilliseconds -lt $milliseconds) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 10
    }
}
function Read-Status {
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        try { return (Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json) } catch { Pump 30 }
    }
    throw 'No test fixture status.'
}
function Assert-Receiver([int]$x, [int]$y, [IntPtr]$expected, [string]$description) {
    [DesktopInputProbe]::SetCursorPos($x,$y) | Out-Null
    Pump 150
    $point = New-Object DesktopInputProbe+Point
    $point.X=$x; $point.Y=$y
    $actual=[DesktopInputProbe]::GetAncestor([DesktopInputProbe]::WindowFromPoint($point),2)
    if ($actual -ne $expected) {
        $title=New-Object Text.StringBuilder(256)
        [DesktopInputProbe]::GetWindowText($actual,$title,256) | Out-Null
        $cursor=New-Object DesktopInputProbe+Point
        [DesktopInputProbe]::GetCursorPos([ref]$cursor) | Out-Null
        throw "$description : expected $expected, got $actual ($title); cursor $($cursor.X),$($cursor.Y); target $x,$y; flags $([DesktopInputProbe]::GetStyle($window,-20))"
    }
    Write-Output "PASS: $description"
}
function Click-TestPoint {
    $cursor=New-Object DesktopInputProbe+Point
    [DesktopInputProbe]::GetCursorPos([ref]$cursor) | Out-Null
    $receiver=[DesktopInputProbe]::GetAncestor([DesktopInputProbe]::WindowFromPoint($cursor),2)
    if ($receiver -ne $backdrop.Handle -and $receiver -ne $window) { throw 'Test interrupted: cursor is not over a test window.' }
    [DesktopInputProbe]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    Pump 40
    [DesktopInputProbe]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
    Pump 250
}
try {
    $backdropProcess = Start-Process -FilePath $backdropExecutable -ArgumentList ('"'+$backdropStatus+'"') -WindowStyle Hidden -PassThru
    for ($attempt=0; $attempt -lt 100 -and -not (Test-Path -LiteralPath $backdropStatus); $attempt++) { Pump 50 }
    $backdrop = @{ Handle=[IntPtr]([long](Get-Content -LiteralPath $backdropStatus -Raw | ConvertFrom-Json).window); BackColor=[Drawing.Color]::FromArgb(225,238,220) }
    $env:APPDATA = Join-Path $verifyDir 'input-test-appdata'
    New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    $gameProcess = Start-Process -FilePath $GodotPath -ArgumentList @('--path', ('"'+$projectDir+'"'), '--log-file', '.verification/desktop-input-game.log', '--script', 'res://tools/verify_desktop_input.gd') -WorkingDirectory $projectDir -WindowStyle Hidden -PassThru
    for ($attempt=0; $attempt -lt 150 -and -not (Test-Path -LiteralPath $statusPath); $attempt++) { Pump 100 }
    $status = Read-Status
    $window = [IntPtr]([long]$status.window)
    Pump 500
    [DesktopInputProbe]::SetWindowPos($backdrop.Handle,[IntPtr](-1),80,80,1100,850,0x40) | Out-Null
    [DesktopInputProbe]::SetWindowPos($window,[IntPtr](-1),0,0,0,0,0x13) | Out-Null
    Pump 100
    if ((Read-Status).bridge_failed) { throw 'Input bridge failed.' }
    $backRect=New-Object DesktopInputProbe+Rect
    [DesktopInputProbe]::GetWindowRect($backdrop.Handle,[ref]$backRect) | Out-Null
    $rect = New-Object DesktopInputProbe+Rect
    [DesktopInputProbe]::GetWindowRect($window,[ref]$rect) | Out-Null
    Assert-Receiver ($rect.Left+20) ($rect.Top+150) $backdrop.Handle 'Transparent gap targets a different process'
    Click-TestPoint
    if ((Get-Content -LiteralPath $backdropStatus -Raw | ConvertFrom-Json).clicks -ne 1) { throw 'Backdrop did not receive the physical click.' }
    [DesktopInputProbe]::SetWindowPos($window,[IntPtr](-1),0,0,0,0,0x13) | Out-Null
    Pump 100
    Assert-Receiver ($rect.Left+170) ($rect.Top+70) $backdrop.Handle 'Weather artwork also passes input without clipping'
    $screen = New-Object Drawing.Bitmap(($rect.Right-$rect.Left),($rect.Bottom-$rect.Top))
    $graphics=[Drawing.Graphics]::FromImage($screen)
    $graphics.CopyFromScreen($rect.Left,$rect.Top,0,0,$screen.Size)
    $screen.Save((Join-Path $verifyDir 'desktop-input-composite.png'))
    $sample = $screen.GetPixel(20,150)
    if ($sample.ToArgb() -ne $backdrop.BackColor.ToArgb()) { throw 'Layered window no longer has a transparent background.' }
    $graphics.Dispose(); $screen.Dispose()
    Assert-Receiver ($rect.Left+280) ($rect.Top+268) $window 'Bottom management button remains interactive'
    Click-TestPoint
    if (-not (Read-Status).management) { throw "Physical management click did not open the panel; backdrop clicks $script:receivedClicks; flags $([DesktopInputProbe]::GetStyle($window,-20))" }
    $before = (Read-Status).clock
    Assert-Receiver ($rect.Left+200) ($rect.Top+268) $window 'Management bar remains interactive'
    Pump 200
    if ((Read-Status).clock -le $before) { throw 'Game progress stopped.' }
    [IO.File]::WriteAllText($commandPath,'full')
    Pump 500
    if (([DesktopInputProbe]::GetStyle($window,-20).ToInt64() -band 0x80020) -ne 0) { throw 'Native input flags were not restored on mode change.' }
    [IO.File]::WriteAllText($commandPath,'workshop')
    Pump 500
    Assert-Receiver ($rect.Left+20) ($rect.Top+150) $backdrop.Handle 'Reentering workshop restores click-through'
    Write-Output 'DESKTOP INPUT PASS: real cross-process click, weather, management, transparency, continued progress, mode restore and restart'
}
finally {
    if ($gameProcess -and -not $gameProcess.HasExited) {
        [IO.File]::WriteAllText($commandPath,'quit')
        if (-not $gameProcess.WaitForExit(5000)) { $gameProcess.Kill() }
    }
    if ($backdrop) { [DesktopInputProbe]::SendMessage($backdrop.Handle,0x10,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null }
    if ($backdropProcess -and -not $backdropProcess.WaitForExit(2000)) { $backdropProcess.Kill() }
    [DesktopInputProbe]::SetCursorPos($oldCursor.X,$oldCursor.Y) | Out-Null
    $env:APPDATA = $previousAppData
}
