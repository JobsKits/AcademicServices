@echo off
rem Zhixu: configure, bootstrap local Go, build and run. Ctrl+C stops.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" %*
if errorlevel 1 pause
