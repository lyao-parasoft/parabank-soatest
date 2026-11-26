[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/-]*$')][string]$ActionRef = 'master',
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$ActionRepository = 'parasoft/run-soatest-action',
    [ValidateSet('Smoke.tst', 'PB-ParabankServices-v3.tst', 'PB-WebUI-v3.tst', 'PB-Bookstore1.tst', 'PB-Bookstore2.tst')]
    [string]$Suite = 'Smoke.tst',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/-]*$')][string]$Branch = 'master',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$Remote = 'origin',
    [string]$RunnerPath = 'D:\Github-runner\parabank-soatest-runner\run.cmd',
    [string]$InstallDir = 'C:\Program Files\Parasoft\SOAtest & Virtualize\2026.2',
    [switch]$PrepareOnly,
    [switch]$Wait = $true,
    [ValidateRange(1, 120)][int]$WaitMinutes = 45
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'GitHub.ps1')
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments[0]) failed (exit $LASTEXITCODE)." }
}
function Replace-WorkflowLine {
    param([string]$Text, [string]$Pattern, [string]$Replacement)
    $regex = New-Object Text.RegularExpressions.Regex($Pattern, [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($regex.Matches($Text).Count -ne 1) { throw "Expected exactly one workflow line matching: $Pattern" }
    return $regex.Replace($Text, [Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement })
}

$runnerReady = $false
$workflowPushed = $false
$runCompleted = $false
Push-Location $root
try {
    if (-not $PrepareOnly -and -not $Wait) { throw 'Automatic runner shutdown requires waiting. Omit -Wait:$false.' }
    Invoke-Git check-ref-format --branch $Branch
    $current = & git symbolic-ref --short HEAD
    if ($LASTEXITCODE -ne 0 -or $current.Trim() -ne $Branch) { throw "Check out '$Branch' first. Current branch: $current" }
    $staged = & git diff --cached --name-only
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the Git index.' }
    if ($staged) { throw 'The Git index contains staged changes. Commit or unstage them before running this script.' }
    $repository = Get-GitHubRepository -Remote $Remote
    if (-not (Test-Path $RunnerPath -PathType Leaf)) { throw "Runner script not found: $RunnerPath" }
    $registration = Get-Content (Join-Path (Split-Path $RunnerPath -Parent) '.runner') -Raw | ConvertFrom-Json
    if ($registration.gitHubUrl.TrimEnd('/') -ne "https://github.com/$repository") {
        throw "The selected runner is registered to another repository: $($registration.gitHubUrl)"
    }
    $runnerName = $registration.agentName
    if ($runnerName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Runner name cannot be used as a workflow scheduling label.' }
    if (-not (Test-Path (Join-Path $InstallDir 'soatestcli.exe') -PathType Leaf)) { throw "SOAtest CLI not found: $InstallDir" }
    Write-Host "Repository: $repository ($Branch); runner: $runnerName; required label: self-hosted"

    if (-not $PrepareOnly) {
        $script:GitHubToken = Get-GitHubToken
        $ref = [Uri]::EscapeDataString($ActionRef)
        $actionCommit = Invoke-GitHubApi -Path "/repos/$ActionRepository/commits/$ref"
        Write-Host "Action under test: $ActionRepository@$ActionRef ($($actionCommit.sha))"
        Invoke-Git fetch --no-tags $Remote "refs/heads/$Branch"
        & git merge-base --is-ancestor FETCH_HEAD HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Local branch is behind or diverged. Integrate the remote changes before running this script.' }
        $runnerApi = "/repos/$repository/actions/runners/$($registration.agentId)"
        $registered = Invoke-GitHubApi -Path $runnerApi
        if ($registered.name -ne $runnerName) { throw 'Local runner registration does not match GitHub.' }
        # Names do not automatically become scheduling labels. Preserve existing labels.
        if ($runnerName -notin @($registered.labels | ForEach-Object { $_.name })) {
            $null = Invoke-GitHubApi -Path "$runnerApi/labels" -Method POST -Body @{ labels = @($runnerName) }
            Write-Host "Added scheduling label '$runnerName' to this runner."
        }
        & (Join-Path $PSScriptRoot 'Start-Runner.ps1') -RunnerPath $RunnerPath -Once
        $runnerReady = $true
        $deadline = [DateTime]::UtcNow.AddSeconds(90)
        do {
            $registered = Invoke-GitHubApi -Path $runnerApi
            if ($registered.status -eq 'online') { break }
            Start-Sleep -Seconds 3
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($registered.status -ne 'online') { throw 'The selected runner is not online in GitHub.' }
        Write-Host "Runner is online (busy=$($registered.busy))."
    }

    $runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $file = Join-Path $root '.github\workflows\action-test.yml'
    $yaml = [IO.File]::ReadAllText($file).Replace("`r`n", "`n")
    $action = "$ActionRepository@$ActionRef"
    $yaml = Replace-WorkflowLine $yaml '^run-name: [^\n]*$' "run-name: 'ParaBank SOAtest $ActionRef / $runId'"
    $yaml = Replace-WorkflowLine $yaml '^    branches: [^\n]*# action-test-branch$' "    branches: ['$Branch'] # action-test-branch"
    $yaml = Replace-WorkflowLine $yaml '^  ACTION_UNDER_TEST: [^\n]*$' "  ACTION_UNDER_TEST: '$action'"
    $yaml = Replace-WorkflowLine $yaml '^  VALIDATION_RUN_ID: [^\n]*$' "  VALIDATION_RUN_ID: '$runId'"
    $yaml = Replace-WorkflowLine $yaml '^  EXPECTED_RUNNER: [^\n]*$' "  EXPECTED_RUNNER: '$runnerName'"
    $yaml = Replace-WorkflowLine $yaml '^  SOATEST_INSTALL_DIR: [^\n]*$' ("  SOATEST_INSTALL_DIR: '" + $InstallDir.Replace("'", "''") + "'")
    $yaml = Replace-WorkflowLine $yaml '^  SOATEST_SUITE: [^\n]*$' ('  SOATEST_SUITE: ${{ inputs.suite || ''' + $Suite + ''' }}')
    $yaml = Replace-WorkflowLine $yaml '^    runs-on: \[self-hosted,[^\n]*$' "    runs-on: [self-hosted, Windows, X64, $runnerName]"
    $yaml = Replace-WorkflowLine $yaml '^        uses: [^\n]+/run-soatest-action@[^\n]*$' "        uses: $action"
    [IO.File]::WriteAllText($file, $yaml, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Prepared action-test.yml: $action; suite=$Suite; invocation=$runId"
    if ($PrepareOnly) {
        Write-Host 'Preparation complete. No runner startup, GitHub API call, commit or push was performed.'
        return
    }

    # Only automation source files are staged. Reports, settings and runner credentials are excluded.
    $managed = @('.github/workflows/action-test.yml', '.gitignore', 'README.md', 'run-action-test.bat',
        'scripts/GitHub.ps1', 'scripts/Invoke-ActionTest.ps1', 'scripts/Start-Runner.ps1',
        'scripts/Stop-Runner.ps1', 'scripts/Parabank.ps1', 'scripts/Start-Parabank.ps1', 'scripts/Stop-Parabank.ps1',
        'scripts/Initialize-Soatest.ps1', 'scripts/Test-Reports.ps1', 'scripts/README.md')
    Invoke-Git add -- @managed
    Invoke-Git diff --cached --check
    Invoke-Git commit -m "test: validate $action ($Suite, $runId)"
    $sha = (& git rev-parse HEAD).Trim()
    Invoke-Git push $Remote "HEAD:refs/heads/$Branch"
    $workflowPushed = $true
    Write-Host "Pushed $sha; looking for the matching push-triggered workflow..."
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $run = $null
    do {
        $runs = Invoke-GitHubApi -Path "/repos/$repository/actions/workflows/action-test.yml/runs?event=push&head_sha=$sha&per_page=10"
        $run = $runs.workflow_runs | Where-Object { $_.head_sha -eq $sha } | Select-Object -First 1
        if ($run) { break }
        Start-Sleep -Seconds 3
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $run) { throw "Push succeeded but no workflow run appeared within 120 seconds. Check https://github.com/$repository/actions" }
    Write-Host "Workflow: $($run.html_url)"
    $deadline = [DateTime]::UtcNow.AddMinutes($WaitMinutes)
    $previousStatus = ''
    do {
        $run = Invoke-GitHubApi -Path "/repos/$repository/actions/runs/$($run.id)"
        if ($run.status -ne $previousStatus) {
            Write-Host "Workflow status: $($run.status)"
            $previousStatus = $run.status
        }
        if ($run.status -eq 'completed') {
            $runCompleted = $true
            Write-Host "Workflow conclusion: $($run.conclusion) - $($run.html_url)"
            if ($run.conclusion -ne 'success') { throw "Workflow finished with conclusion $($run.conclusion). Inspect the SOAtest report and step logs." }
            return
        }
        Start-Sleep -Seconds 5
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting; the run continues at $($run.html_url)"
} finally {
    $shutdownError = $null
    # Do not terminate an in-flight workflow after a monitoring timeout or API failure.
    # A newly launched --once runner will exit on its own when its job finishes.
    if ($runnerReady -and (-not $workflowPushed -or $runCompleted)) {
        try { & (Join-Path $PSScriptRoot 'Stop-Runner.ps1') -RunnerPath $RunnerPath }
        catch { $shutdownError = $_ }
    }
    $script:GitHubToken = $null
    Pop-Location
    if ($shutdownError) { throw $shutdownError }
}
