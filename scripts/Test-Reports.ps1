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
if ([int]$total.GetAttribute('fail') -gt 0) { throw "SOAtest has failing tests: $($total.GetAttribute('fail'))." }
$nativeCases = @($native.SelectNodes('//ExecutedTestsDetails[@type="FT"]//TestCase'))
if ($nativeCases.Count -eq 0) { throw 'Native report has no functional test case details.' }
if (-not (Test-Path $xunitPath -PathType Leaf)) { throw "Converted xUnit report missing: $xunitPath" }
[xml]$xunit = [IO.File]::ReadAllText($xunitPath)
$cases = @($xunit.SelectNodes('//testcase'))
if ($cases.Count -eq 0) { throw 'Converted xUnit report contains no test cases.' }
if ($xunit.SelectNodes('//testcase/failure | //testcase/error').Count -gt 0) { throw 'Converted xUnit report contains failures or errors.' }
Write-Host "Verified $($total.GetAttribute('total')) native executions and $($cases.Count) converted xUnit cases."
if ($env:GITHUB_STEP_SUMMARY) {
    "SOAtest executed $($total.GetAttribute('total')) functional tests. xUnit contains $($cases.Count) test cases." |
        Out-File $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Append
}
