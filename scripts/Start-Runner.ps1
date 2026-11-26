[CmdletBinding()]
param(
    [string]$RunnerPath = 'D:\Github-runner\parabank-soatest-runner\run.cmd',
    [ValidateRange(10, 300)][int]$TimeoutSeconds = 90,
    [switch]$Once,
    [switch]$Child
)
$ErrorActionPreference = 'Stop'
$RunnerPath = [IO.Path]::GetFullPath($RunnerPath)
$runnerDir = Split-Path $RunnerPath -Parent
if (-not (Test-Path $RunnerPath -PathType Leaf)) { throw "Runner script not found: $RunnerPath" }
$config = Get-Content (Join-Path $runnerDir '.runner') -Raw | ConvertFrom-Json
$runtime = Join-Path (Split-Path $PSScriptRoot -Parent) '.runtime\runner'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$stateFile = Join-Path $runtime 'state.json'
$consoleLog = Join-Path $runtime 'console.log'

function Get-OwnedListener {
    # Windows may resolve the runner's bin junction to bin.<version>.
    @(Get-CimInstance Win32_Process -Filter "Name='Runner.Listener.exe'" |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith("$runnerDir\bin", [StringComparison]::OrdinalIgnoreCase) })
}
function Get-LiveState {
    if (-not (Test-Path $stateFile)) { return $null }
    try {
        $state = Get-Content $stateFile -Raw | ConvertFrom-Json
        $process = Get-Process -Id $state.consolePid -ErrorAction SilentlyContinue
        if ($state.runnerDir -eq $runnerDir -and $process -and
            $process.StartTime.ToUniversalTime().Ticks.ToString() -eq $state.startTicks) { return $state }
    } catch { }
    return $null
}
if ($Child) {
    if ((Get-OwnedListener).Count -gt 0) { throw 'This runner already has a listener process.' }
    $self = Get-Process -Id $PID
    @{ consolePid = $PID; startTicks = $self.StartTime.ToUniversalTime().Ticks.ToString(); runnerDir = $runnerDir; once = [bool]$Once } |
        ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
    Set-Location $runnerDir
    Set-Content $consoleLog '' -Encoding Unicode
    $ErrorActionPreference = 'Continue'
    # --once exits after one job without removing the runner registration.
    $runnerArguments = @()
    if ($Once) { $runnerArguments += '--once' }
    & $RunnerPath @runnerArguments 2>&1 | Tee-Object -FilePath $consoleLog -Append
    $runnerExitCode = $LASTEXITCODE
    Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
    exit $runnerExitCode
}

$live = Get-LiveState
if (-not $live) {
    if ((Get-OwnedListener).Count -gt 0) {
        Write-Host "Runner '$($config.agentName)' already has a listener; reusing it. GitHub online status will be checked by the caller."
        return
    }
    Remove-Item $consoleLog, $stateFile -Force -ErrorAction SilentlyContinue
    $quote = { param($text) "'" + $text.Replace("'", "''") + "'" }
    $command = '& ' + (& $quote $PSCommandPath) + ' -Child -RunnerPath ' + (& $quote $RunnerPath)
    if ($Once) { $command += ' -Once' }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $null = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -WindowStyle Minimized -PassThru
}
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
do {
    $live = Get-LiveState
    if ($live -and (Test-Path $consoleLog)) {
        $text = Get-Content $consoleLog -Raw -ErrorAction SilentlyContinue
        if ($text) { $text = $text.Replace([string][char]0, '') }
        if ($text -match 'Connected to GitHub' -and $text -match 'Listening for Jobs') {
            Write-Host "Runner '$($config.agentName)' connected and Listening for Jobs. Log: $consoleLog"
            return
        }
    }
    Start-Sleep -Seconds 1
} while ([DateTime]::UtcNow -lt $deadline)
throw "Runner did not become ready within $TimeoutSeconds seconds. See $consoleLog"
