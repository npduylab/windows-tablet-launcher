@echo off
rem Chay TouchLauncher.exe neu co (build.ps1 tao ra), neu khong thi chay thang script PowerShell.
if exist "%~dp0TouchLauncher.exe" (
  start "" "%~dp0TouchLauncher.exe"
) else (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Launcher.ps1"
)
