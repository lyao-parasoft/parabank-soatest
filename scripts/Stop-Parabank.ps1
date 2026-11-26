[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Parabank.ps1')
$root = Split-Path $PSScriptRoot -Parent
$stateFile = Join-Path $root '.runtime\parabank.json'
if (-not (Test-Path $stateFile)) { return }
$state = Get-Content $stateFile -Raw | ConvertFrom-Json
if ($state.owner -ne (Get-ServiceOwner)) {
    Write-Host 'The current run did not start this service; leaving it running.'
    return
}
if (-not (Test-ServiceProcess $state)) {
    throw 'The recorded launcher has exited. Inspect the service logs before manually stopping any remaining Tomcat process.'
}
Push-Location $root
try {
    & mvn -B -ntp cargo:stop
    if ($LASTEXITCODE -ne 0) { throw 'Maven Cargo could not stop the managed Tomcat.' }
    Remove-Item $stateFile -Force
} finally { Pop-Location }
