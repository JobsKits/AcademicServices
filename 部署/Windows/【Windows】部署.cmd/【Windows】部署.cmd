@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\%~n0.ps1\%~n0.ps1" %*
set "deploy_result=%errorlevel%"
if not "%deploy_result%"=="0" pause
endlocal & exit /b %deploy_result%
