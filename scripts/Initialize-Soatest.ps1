[CmdletBinding()]
param([string]$InstallDir = 'C:\Program Files\Parasoft\SOAtest & Virtualize\2026.2')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$cli = Join-Path $InstallDir 'soatestcli.exe'
if (-not (Test-Path $cli -PathType Leaf)) { throw "SOAtest CLI not found: $cli" }
$workspace = Join-Path $root '.runtime\soatest-workspace'
New-Item -ItemType Directory -Path $workspace -Force | Out-Null
$env:PARASOFT_CONSOLE_ENCODING = 'utf-8'
# Import and execute in separate CLI calls; -import alone does not execute tests.
foreach ($project in @('TestAssets', 'Bookstore')) {
    & $cli -data $workspace -import (Join-Path $root "soatest\$project\.project")
    if ($LASTEXITCODE -ne 0) { throw "SOAtest import of $project failed (exit $LASTEXITCODE)." }
}
Write-Host "Imported TestAssets and Bookstore into $workspace"
