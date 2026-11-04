@echo off
rem 知序桌面用户端：准备工程私有Python环境并启动，内层先展示自述。
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Zhixu\Scripts\bootstrap.ps1" -Mode run
exit /b %errorlevel%
