<#
  Tạo shortcut cho Touch Launcher.
    .\CaiDat.ps1              -> shortcut ngoài Desktop
    .\CaiDat.ps1 -AutoStart   -> thêm: tự chạy khi đăng nhập Windows
    .\CaiDat.ps1 -Remove      -> gỡ các shortcut
#>
param([switch]$AutoStart, [switch]$Remove)

$ps1     = Join-Path $PSScriptRoot 'Launcher.ps1'
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Touch Launcher.lnk'
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'Touch Launcher.lnk'

if ($Remove) {
    Remove-Item $desktop, $startup -ErrorAction SilentlyContinue
    'Đã gỡ shortcut.'
    return
}

# Có TouchLauncher.exe cạnh script (build.ps1 tạo ra) thì shortcut trỏ thẳng vào exe: có icon riêng, mở nhanh hơn.
# Riêng khi Smart App Control (Windows 11) đang bật: exe chưa ký số bị chặn, nên dùng script.
$exe = Join-Path $PSScriptRoot 'TouchLauncher.exe'
$sac = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
if ($sac -eq 1 -and (Test-Path $exe)) {
    'Smart App Control đang bật: shortcut sẽ chạy bằng script PowerShell (exe chưa ký số bị Windows chặn).'
    $exe = Join-Path $PSScriptRoot '__khong_dung_exe__'
}

$shell = New-Object -ComObject WScript.Shell
function New-Shortcut([string]$path) {
    $l = $shell.CreateShortcut($path)
    if (Test-Path $exe) {
        $l.TargetPath   = $exe
        $l.IconLocation = "$exe,0"
    } else {
        $l.TargetPath   = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $l.Arguments    = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$ps1`""
        $l.WindowStyle  = 7   # thu nhỏ, tránh nháy cửa sổ console
        $ico = Join-Path $PSScriptRoot 'assets\TouchLauncher.ico'
        $l.IconLocation = if (Test-Path $ico) { "$ico,0" } else { "$env:WINDIR\System32\shell32.dll,22" }
    }
    $l.WorkingDirectory = $PSScriptRoot
    $l.Description      = 'Touch Launcher'
    $l.Save()
}

New-Shortcut $desktop
"Đã tạo: $desktop"
if ($AutoStart) {
    New-Shortcut $startup
    "Đã bật tự chạy: $startup"
}
