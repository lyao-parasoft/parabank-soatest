[CmdletBinding()]
param([string]$ReportDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '.runtime\reports\ci'))
$ErrorActionPreference = 'Stop'
$nativePath = Join-Path $ReportDirectory 'report.xml'
$xunitPath = Join-Path $ReportDirectory 'report-xunit.xml'
if (-not (Test-Path $nativePath -PathType Leaf)) { throw "Native report missing: $nativePath" }
[xml]$native = [IO.File]::ReadAllText($nativePath)
$problems = @($native.SelectNodes('/ResultsSession/SetupProblems/Problem'))
if ($problems.Count -gt 0) { throw "SOAtest reported $($problems.Count) setup/load problems. See report.xml." }
$total = $native.SelectSingleNode('//ExecutedTestsDetails[@type="FT"]/Total')
if (-not $total -or [int]$total.GetAttribute('total') -le 0) { throw 'SOAtest executed no functional tests. A zero-test run is not a pass.' }
$executedCount = [int]$total.GetAttribute('total')
$passedCount = [int]$total.GetAttribute('pass')
$failedCount = [int]$total.GetAttribute('fail')
if ($failedCount -gt 0) { throw "SOAtest has failing tests: $failedCount." }
$nativeCases = @($native.SelectNodes('//ExecutedTestsDetails[@type="FT"]//TestCase'))
if ($nativeCases.Count -eq 0) { throw 'Native report has no functional test case details.' }
if (-not (Test-Path $xunitPath -PathType Leaf)) { throw "Converted xUnit report missing: $xunitPath" }
[xml]$xunit = [IO.File]::ReadAllText($xunitPath)
$cases = @($xunit.SelectNodes('//testcase'))
$skippedCases = @($xunit.SelectNodes('//testcase/skipped'))
$failures = @($xunit.SelectNodes('//testcase/failure | //testcase/error'))
if ($cases.Count -eq 0) { throw 'Converted xUnit report contains no test cases.' }
if ($failures.Count -gt 0) { throw 'Converted xUnit report contains failures or errors.' }
Write-Host "Verified native XML and converted xUnit XML: $executedCount executed, $passedCount passed, $failedCount failed, $($skippedCases.Count) skipped ($($cases.Count) xUnit cases)."
if ($env:GITHUB_STEP_SUMMARY) {
    @"
### SOAtest action validation

- Action: ``$env:ACTION_UNDER_TEST``
- Invocation: ``$env:VALIDATION_RUN_ID``
- Runner: ``$env:RUNNER_NAME``
- Executed test cases: $executedCount
- Passed: $passedCount
- Failed: $failedCount
- Skipped: $($skippedCases.Count)
- Native XML and converted xUnit XML both verified.
"@ | Add-Content $env:GITHUB_STEP_SUMMARY -Encoding UTF8
}
