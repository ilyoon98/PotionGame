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
Start-Process -FilePath $GodotPath -ArgumentList @('--path', ('"' + $PSScriptRoot + '"')) -WorkingDirectory $PSScriptRoot
