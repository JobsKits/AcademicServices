@echo off
rem 知序Windows本机打包：工程内环境、EXE及ZIP，清理Dist与取消范围见内层自述。
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Zhixu\Scripts\bootstrap.ps1" -Mode build
exit /b %errorlevel%
