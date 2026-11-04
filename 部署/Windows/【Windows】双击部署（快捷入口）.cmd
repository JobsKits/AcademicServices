@echo off
rem ASCII source; select exactly one package carrying this action marker.
setlocal DisableDelayedExpansion
set "shortcut_target="
set "shortcut_count=0"
for /d %%D in ("%~dp0*.ps1") do (
  if exist "%%~fD\deployment.entry" if exist "%%~fD\%%~nxD" (
    set /a shortcut_count+=1 >nul
    set "shortcut_target=%%~fD\%%~nxD"
  )
)
if not "%shortcut_count%"=="1" goto shortcut_missing
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%shortcut_target%" %*
set "shortcut_result=%errorlevel%"
if not "%shortcut_result%"=="0" pause
endlocal & exit /b %shortcut_result%
:shortcut_missing
>&2 echo Expected exactly one matching marked PowerShell script package.
pause
endlocal & exit /b 1
