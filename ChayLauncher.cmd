@echo off
rem Chay TouchLauncher.exe neu co va Windows cho phep; nguoc lai chay thang script PowerShell.
rem Smart App Control (Windows 11) chan exe chua ky so -> khi no dang bat thi dung script.
set "SAC=0"
for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v VerifiedAndReputablePolicyState 2^>nul ^| "%SystemRoot%\System32\findstr.exe" /c:"0x"') do set "SAC=%%a"
if exist "%~dp0TouchLauncher.exe" if not "%SAC%"=="0x1" (
  start "" "%~dp0TouchLauncher.exe"
  goto :eof
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Launcher.ps1"
