<#
  Build TouchLauncher.exe (một tệp duy nhất, nhúng sẵn Launcher.ps1 + cấu hình mặc định + MCP server).
  Dùng trình biên dịch C# có sẵn trong Windows (.NET Framework 4) — không cần cài Visual Studio.

    powershell -ExecutionPolicy Bypass -File build.ps1                 # phiên bản lấy từ tệp VERSION
    powershell -ExecutionPolicy Bypass -File build.ps1 -Version 1.2.0  # chỉ định phiên bản (CI dùng theo tag)
  Kết quả: dist\TouchLauncher.exe
#>
param([string]$Version)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root  = $PSScriptRoot
$build = Join-Path $root 'build'
$dist  = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $build, $dist | Out-Null

# ---------------------------------------------------------------- Icon (4 ô vuông bo góc trên nền tím)
function New-RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}
function New-IconPng([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point 0, $s),
            ([System.Drawing.Color]::FromArgb(255, 124, 122, 255)), ([System.Drawing.Color]::FromArgb(255, 74, 72, 214))
    $g.FillPath($bg, (New-RoundRect 0 0 ($s - 1) ($s - 1) ($s * 0.23)))
    $m = $s * 0.21; $gap = $s * 0.08; $t = ($s - 2 * $m - $gap) / 2
    foreach ($cell in @(@(0, 0, 255), @(1, 0, 185), @(0, 1, 185), @(1, 1, 255))) {
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($cell[2], 255, 255, 255))
        $g.FillPath($brush, (New-RoundRect ($m + $cell[0] * ($t + $gap)) ($m + $cell[1] * ($t + $gap)) $t $t ($t * 0.28)))
    }
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return , $ms.ToArray()
}
# Tệp .ico nhiều kích thước (mỗi ảnh là PNG — Windows Vista trở lên đều đọc được).
$sizes = 16, 24, 32, 48, 64, 128, 256
$images = @($sizes | ForEach-Object { , (New-IconPng $_) })
$ico = Join-Path $build 'TouchLauncher.ico'
$fs = [System.IO.File]::Create($ico)
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $sz = $sizes[$i]; $len = $images[$i].Length
    $bw.Write([byte]($sz % 256)); $bw.Write([byte]($sz % 256)); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$len); $bw.Write([uint32]$offset)
    $offset += $len
}
foreach ($img in $images) { $bw.Write($img) }
$bw.Close()
[System.IO.File]::WriteAllBytes((Join-Path $build 'icon-256.png'), $images[-1])
"Icon: $ico"

# ---------------------------------------------------------------- Phiên bản
if (-not $Version) { $Version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim() }
$Version = $Version.TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Phiên bản không hợp lệ: '$Version' (cần dạng 1.2.3)." }
$asmInfo = Join-Path $build 'AssemblyInfo.cs'
[System.IO.File]::WriteAllText($asmInfo, @"
using System.Reflection;
[assembly: AssemblyTitle("Touch Launcher")]
[assembly: AssemblyProduct("Windows Tablet Launcher")]
[assembly: AssemblyDescription("iPad-style touch launcher for Windows")]
[assembly: AssemblyCompany("npduylab")]
[assembly: AssemblyCopyright("MIT License - Nguyen Phuc Duy (npduylab) and contributors")]
[assembly: AssemblyVersion("$Version.0")]
[assembly: AssemblyFileVersion("$Version.0")]
[assembly: AssemblyInformationalVersion("$Version")]
"@, (New-Object System.Text.UTF8Encoding $false))

# ---------------------------------------------------------------- Biên dịch
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
$sma = [psobject].Assembly.Location
$out = Join-Path $dist 'TouchLauncher.exe'

$cscArgs = @(
    '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu', '/utf8output', "/codepage:65001",
    "/out:$out", "/win32icon:$ico",
    "/reference:$sma", '/reference:System.Windows.Forms.dll', '/reference:System.Core.dll',
    "/resource:$(Join-Path $root 'Launcher.ps1'),Launcher.ps1",
    "/resource:$(Join-Path $root 'launcher.config.json'),launcher.config.json",
    "/resource:$(Join-Path $root 'mcp\touch_launcher_mcp.py'),touch_launcher_mcp.py",
    (Join-Path $root 'src\TouchLauncher.cs'), $asmInfo
)
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "Biên dịch thất bại (mã $LASTEXITCODE)." }

$f = Get-Item $out
"Đã build: $($f.FullName)  ($([math]::Round($f.Length / 1KB)) KB, phiên bản $($f.VersionInfo.FileVersion))"
