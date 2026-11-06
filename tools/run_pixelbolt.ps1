# Run from the project root. Install once from tools/pixelbolt with:
# npm ci --ignore-scripts --no-audit --no-fund
$ErrorActionPreference = 'Stop'
$pixelboltCli = Join-Path $PSScriptRoot 'pixelbolt\node_modules\pixelbolt\bin\pixelbolt.js'
if (-not (Test-Path -LiteralPath $pixelboltCli)) {
    throw 'Pixelbolt is not installed. In tools/pixelbolt run: npm ci --ignore-scripts --no-audit --no-fund'
}
$nodeCommand = Get-Command node -ErrorAction Stop
& $nodeCommand.Source $pixelboltCli @args
exit $LASTEXITCODE
