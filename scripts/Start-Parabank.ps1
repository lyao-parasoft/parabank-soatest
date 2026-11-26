[CmdletBinding()]
param([ValidateRange(30, 900)][int]$TimeoutSeconds = 300)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Parabank.ps1')
$root = Split-Path $PSScriptRoot -Parent
$runtime = Join-Path $root '.runtime'
$stateFile = Join-Path $runtime 'parabank.json'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
if (Test-Parabank) {
    Write-Host 'ParaBank is already ready at http://localhost:8080/parabank/; reusing the existing service.'
    return
}
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    if (Test-ServiceProcess $state) { throw "A managed ParaBank process is running but unhealthy. See $runtime\parabank.stdout.log" }
    Remove-Item $stateFile -Force
}
if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) {
    throw 'Port 8080 is occupied by an unrecognized or unhealthy service. Wait for it to finish starting or stop it before retrying.'
}
$null = Get-Command java, mvn -ErrorAction Stop
$startScript = (Join-Path $root 'start.bat').Replace("'", "''")
$command = "& '$startScript'; exit `$LASTEXITCODE"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -WorkingDirectory $root `
    -RedirectStandardOutput (Join-Path $runtime 'parabank.stdout.log') `
    -RedirectStandardError (Join-Path $runtime 'parabank.stderr.log') -WindowStyle Hidden -PassThru
$process.Refresh()
@{ pid = $process.Id; startTicks = $process.StartTime.ToUniversalTime().Ticks.ToString(); owner = Get-ServiceOwner } |
    ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
do {
    $process.Refresh()
    if ($process.HasExited) { throw "ParaBank launcher exited ($($process.ExitCode)). See $runtime\parabank.stdout.log and parabank.stderr.log" }
    if (Test-Parabank) {
        Write-Host "ParaBank is ready at http://localhost:8080/parabank/ (launcher PID $($process.Id))."
        return
    }
    Start-Sleep -Seconds 2
} while ([DateTime]::UtcNow -lt $deadline)
throw "ParaBank did not become ready within $TimeoutSeconds seconds. See $runtime\parabank.stdout.log"
