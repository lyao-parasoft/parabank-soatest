@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-ActionTest.ps1" -Wait %*
set "ACTION_TEST_EXIT=%ERRORLEVEL%"
if not "%ACTION_TEST_EXIT%"=="0" echo ParaBank SOAtest action test failed. See the error above.
if "%~1"=="" pause
exit /b %ACTION_TEST_EXIT%
