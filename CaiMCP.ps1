<#
  Đăng ký MCP server "touch-launcher" với Claude Desktop, để Claude điều khiển được máy tính bảng.
    .\CaiMCP.ps1           -> thêm (hoặc cập nhật) server
    .\CaiMCP.ps1 -Remove   -> gỡ server
  Mỗi tệp cấu hình được sao lưu (.bak-<thời gian>) trước khi sửa. Sau đó thoát hẳn rồi mở lại Claude Desktop.
#>
param([switch]$Remove)

$server = Join-Path $PSScriptRoot 'mcp\touch_launcher_mcp.py'
$python = $null
try { $python = (& python -c "import sys; print(sys.executable)" | Select-Object -First 1) } catch {}
if (-not $python -or -not (Test-Path $python)) {
    $python = Join-Path $env:LOCALAPPDATA 'Python\pythoncore-3.14-64\python.exe'
}
if (-not $Remove -and -not (Test-Path $python)) { Write-Error 'Không tìm thấy Python. Cài Python 3 rồi chạy lại.'; return }

# Claude Desktop bản cài thường đọc %APPDATA%\Claude; bản Microsoft Store đọc trong thư mục gói.
$targets = @(Join-Path $env:APPDATA 'Claude\claude_desktop_config.json')
Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Filter 'Claude_*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $targets += Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json'
}

foreach ($path in $targets) {
    $dir = Split-Path $path
    if (-not (Test-Path $dir)) {
        if ($Remove) { continue }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $cfg = [pscustomobject]@{}
    if (Test-Path $path) {
        Copy-Item $path "$path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        $text = [IO.File]::ReadAllText($path)
        if ($text.Trim()) { $cfg = $text | ConvertFrom-Json }
    } elseif ($Remove) { continue }

    if (-not $cfg.PSObject.Properties['mcpServers']) { $cfg | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
    if ($Remove) {
        $cfg.mcpServers.PSObject.Properties.Remove('touch-launcher')
    } else {
        $entry = [pscustomobject]@{ command = $python; args = @('-I', $server) }
        $cfg.mcpServers | Add-Member -NotePropertyName 'touch-launcher' -NotePropertyValue $entry -Force
    }
    [IO.File]::WriteAllText($path, ($cfg | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding $false))
    "$(if ($Remove) { 'Đã gỡ khỏi' } else { 'Đã đăng ký vào' }): $path"
}

if (-not $Remove) {
    ''
    'Xong. Thoát hẳn Claude Desktop (cả biểu tượng ở khay hệ thống) rồi mở lại.'
    'Thử hỏi Claude: "Mở YouTube và tìm nhạc Trịnh Công Sơn" hoặc "Pin còn bao nhiêu?"'
    ''
    'Dùng với Claude Code thì chạy:'
    "  claude mcp add touch-launcher -- `"$python`" -I `"$server`""
}
