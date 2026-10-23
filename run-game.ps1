param([string]$GodotPath)

$ErrorActionPreference = 'Stop'
if (-not $GodotPath) {
    $godotCommand = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($godotCommand) { $GodotPath = $godotCommand.Source }
}
if (-not $GodotPath) {
    $downloadRoot = Join-Path $env:USERPROFILE 'Downloads'
    $godotCandidate = Get-ChildItem -LiteralPath $downloadRoot -Filter 'Godot*_win64.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*console*' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($godotCandidate) { $GodotPath = $godotCandidate.FullName }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot 4.6 was not found. Run this script with -GodotPath "C:\path\to\Godot.exe".'
}
# Run outside the editor so Windows can keep the game window on top.
# Godot's GUI build attaches to its parent's console while the parent is alive, so a
# direct launch from play.cmd sometimes kept that cmd window open and closing it ended
# the game. Launch from a hidden helper console so the caller's window is never shared.
function Quote-Literal([string]$text) { "'" + $text.Replace("'", "''") + "'" }
$launchCommand = 'Start-Process -FilePath {0} -ArgumentList @(''--path'', {1}) -WorkingDirectory {2}' -f
    (Quote-Literal $GodotPath), (Quote-Literal ('"' + $PSScriptRoot + '"')), (Quote-Literal $PSScriptRoot)
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($launchCommand))
Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-EncodedCommand', $encodedCommand)
