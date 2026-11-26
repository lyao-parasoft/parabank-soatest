# Shared runtime helpers for Start-Parabank.ps1 and Stop-Parabank.ps1.
function Test-Parabank {
    try {
        $page = Invoke-WebRequest 'http://localhost:8080/parabank/' -UseBasicParsing -TimeoutSec 3
        if ($page.StatusCode -ne 200 -or $page.Content -notmatch 'ParaBank') { return $false }
        $wsdl = Invoke-WebRequest 'http://localhost:8080/parabank/services/ParaBank?wsdl' -UseBasicParsing -TimeoutSec 3
        return $wsdl.StatusCode -eq 200 -and $wsdl.Content -match 'definitions' -and $wsdl.Content -match 'ParaBank'
    } catch { return $false }
}
function Get-ServiceOwner {
    if ($env:GITHUB_RUN_ID) { return "$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)" }
    return 'local'
}
function Test-ServiceProcess {
    param($State)
    $process = Get-Process -Id $State.pid -ErrorAction SilentlyContinue
    return $process -and $process.StartTime.ToUniversalTime().Ticks.ToString() -eq $State.startTicks
}
