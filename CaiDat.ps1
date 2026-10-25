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
$exe = Join-Path $PSScriptRoot 'TouchLauncher.exe'

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
        $l.IconLocation = "$env:WINDIR\System32\shell32.dll,22"
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
