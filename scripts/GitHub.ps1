# Dot-source this file. Credentials are kept in memory and never printed.
function Get-GitHubToken {
    foreach ($name in @('GH_TOKEN', 'GITHUB_TOKEN')) {
        $token = [Environment]::GetEnvironmentVariable($name)
        if ($token) { return $token }
    }
    $previous = $env:GCM_INTERACTIVE
    try {
        $env:GCM_INTERACTIVE = 'Never'
        $credential = "protocol=https`nhost=github.com`n`n" | & git credential fill 2>$null
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in $credential) {
                if ($line.StartsWith('password=')) { return $line.Substring(9) }
            }
        }
    } finally { $env:GCM_INTERACTIVE = $previous }
    throw 'No GitHub credential found. Set GH_TOKEN/GITHUB_TOKEN or authenticate Git for github.com.'
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GET', 'POST')][string]$Method = 'GET',
        [object]$Body
    )
    $request = @{
        Uri = "https://api.github.com$Path"
        Method = $Method
        Headers = @{
            Authorization = "Bearer $script:GitHubToken"
            Accept = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent' = 'parabank-soatest'
        }
        TimeoutSec = 30
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $request.Body = ConvertTo-Json $Body -Depth 10 -Compress
        $request.ContentType = 'application/json; charset=utf-8'
    }
    try { Invoke-RestMethod @request }
    catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'network' }
        throw "GitHub API $Method $Path failed ($status). Check repository access and token permissions."
    }
}

function Get-GitHubRepository {
    param([string]$Remote = 'origin')
    $url = & git remote get-url $Remote
    if ($LASTEXITCODE -ne 0) { throw "Git remote not found: $Remote" }
    if ($url.Trim() -notmatch '^(?:https://github\.com/|git@github\.com:)([^/]+/[^/]+?)(?:\.git)?/?$') {
        throw 'A GitHub HTTPS or SSH remote is required.'
    }
    return $Matches[1]
}
