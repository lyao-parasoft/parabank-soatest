@echo off
setlocal
cd /d "%~dp0"
call mvn -B -ntp -DskipTests package cargo:run %*
exit /b %ERRORLEVEL%
