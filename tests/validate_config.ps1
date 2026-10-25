<#
  Kiểm tra launcher.config.json: JSON hợp lệ, mỗi app đủ trường, tên không trùng,
  "home"/"dock" chỉ nhắc tới app có thật, regex "match" hợp lệ.
    powershell -ExecutionPolicy Bypass -File tests\validate_config.ps1
#>
param([string]$Path = (Join-Path $PSScriptRoot '..\launcher.config.json'))

$errors = New-Object System.Collections.Generic.List[string]
try {
    $cfg = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Host "LỖI: launcher.config.json không phải JSON hợp lệ: $($_.Exception.Message)"
    exit 1
}

$validTypes = 'app', 'web', 'uri', 'exe'
$names = @{}
$i = 0
foreach ($t in $cfg.tiles) {
    $i++
    $label = if ($t.name) { "'$($t.name)'" } else { "#$i" }
    if (-not $t.name)   { $errors.Add("App $label thiếu 'name'.") }
    if (-not $t.target) { $errors.Add("App $label thiếu 'target'.") }
    if (-not $t.icon)   { $errors.Add("App $label thiếu 'icon'.") }
    if ($t.type -notin $validTypes) { $errors.Add("App $label có 'type' = '$($t.type)', phải là: $($validTypes -join ', ').") }
    if ($t.type -in 'app', 'web' -and $t.target -notmatch '^https?://') { $errors.Add("App ${label}: 'target' phải bắt đầu bằng https://") }
    if ($t.color -and $t.color -notmatch '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$') { $errors.Add("App ${label}: 'color' phải dạng #RRGGBB.") }
    if ($t.match) { try { [void][regex]::new($t.match) } catch { $errors.Add("App ${label}: 'match' không phải regex hợp lệ.") } }
    if ($t.name) {
        if ($names.ContainsKey($t.name)) { $errors.Add("Tên app bị trùng: '$($t.name)'.") }
        $names[$t.name] = $true
    }
}
foreach ($list in 'home', 'dock') {
    foreach ($n in @($cfg.$list)) {
        if ($n -and -not $names.ContainsKey($n)) { $errors.Add("'$list' nhắc tới app không tồn tại: '$n'.") }
    }
}

if ($errors.Count) {
    $errors | ForEach-Object { Write-Host "LỖI: $_" }
    exit 1
}
"OK: $($cfg.tiles.Count) app, $(@($cfg.home).Count) app trên trang chủ, $(@($cfg.dock).Count) app trên Dock."
