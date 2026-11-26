[CmdletBinding()]
param(
    [string]$RunnerPath = 'D:\Github-runner\parabank-soatest-runner\run.cmd',
    [ValidateRange(0, 300)][int]$IdleTimeoutSeconds = 30
)
$ErrorActionPreference = 'Stop'
$RunnerPath = [IO.Path]::GetFullPath($RunnerPath)
$runnerDir = Split-Path $RunnerPath -Parent
if (-not (Test-Path $RunnerPath -PathType Leaf)) { throw "Runner script not found: $RunnerPath" }
$stateFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.runtime\runner\state.json'
$runnerPattern = '^' + [Regex]::Escape($runnerDir) + '\\bin(?:\.[^\\]+)?\\Runner\.Listener\.exe$'
$deadline = [DateTime]::UtcNow.AddSeconds($IdleTimeoutSeconds)
do {
    $processes = @(Get-CimInstance Win32_Process)
    $listeners = @($processes | Where-Object { $_.Name -eq 'Runner.Listener.exe' -and $_.ExecutablePath -match $runnerPattern })
    $console = $null
    if (Test-Path $stateFile) {
        $state = Get-Content $stateFile -Raw | ConvertFrom-Json
        $candidate = Get-Process -Id $state.consolePid -ErrorAction SilentlyContinue
        if ($state.runnerDir -eq $runnerDir -and $candidate -and
            $candidate.StartTime.ToUniversalTime().Ticks.ToString() -eq $state.startTicks) {
            $console = $candidate
        }
    }
    # Traverse only this runner's process trees, including a verified managed console.
    $ownedIds = @($listeners | ForEach-Object { [int]$_.ProcessId })
    if ($console) { $ownedIds += $console.Id }
    do {
        $children = @($processes | Where-Object { [int]$_.ParentProcessId -in $ownedIds -and [int]$_.ProcessId -notin $ownedIds })
        $ownedIds += @($children | ForEach-Object { [int]$_.ProcessId })
    } while ($children.Count -gt 0)
    $workers = @($processes | Where-Object { $_.Name -eq 'Runner.Worker.exe' -and [int]$_.ProcessId -in $ownedIds })
    if ($workers.Count -eq 0) { break }
    if ([DateTime]::UtcNow -ge $deadline) { throw 'The selected runner still has an active job; it has not been stopped.' }
    Start-Sleep -Seconds 1
} while ($true)

if ($ownedIds.Count -eq 0) {
    $hidden = @($processes | Where-Object { $_.Name -eq 'Runner.Listener.exe' -and -not $_.ExecutablePath })
    if ($hidden.Count -gt 0) {
        throw 'A runner is running with hidden process details. Its directory cannot be verified. Run Stop-Runner.ps1 as the runner user or as Administrator; no unidentified process was stopped.'
    }
    Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
    Write-Host "No listener is running for $runnerDir."
    return
}
# A job could finish and the PID be recycled; revalidate the executable before stopping.
foreach ($listener in $listeners) {
    $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.ProcessId)"
    if (-not $current) { continue }
    if ($current.ExecutablePath -notmatch $runnerPattern -or $current.CreationDate -ne $listener.CreationDate) {
        throw 'Runner process identity changed before shutdown. Retry after checking its status.'
    }
    Stop-Process -Id $listener.ProcessId -ErrorAction Stop
    Write-Host "Stopped runner listener PID $($listener.ProcessId)."
}
# Closing the managed console also prevents run.cmd from restarting a stopped listener.
if ($console) {
    $current = Get-Process -Id $console.Id -ErrorAction SilentlyContinue
    if ($current -and $current.StartTime.ToUniversalTime().Ticks.ToString() -eq $state.startTicks) {
        Stop-Process -Id $console.Id -ErrorAction Stop
    }
}
Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
Write-Host 'Runner stopped; its registration and credentials are preserved.'
