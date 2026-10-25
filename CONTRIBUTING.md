# Đóng góp cho Windows Tablet Launcher

🇻🇳 Tiếng Việt · [🇬🇧 English](#english)

Cảm ơn bạn muốn đóng góp! Dù chỉ là báo lỗi, đề xuất một app web, sửa câu chữ hay viết tính năng mới — đều rất quý.

## Cách đóng góp nhanh nhất

| Bạn muốn… | Làm thế này |
|---|---|
| Báo lỗi | [Mở issue "Báo lỗi"](https://github.com/npduylab/windows-tablet-launcher/issues/new?template=bug_report.yml) |
| Đề xuất app web mới (Zalo, Spotify…) | [Mở issue "Đề xuất app"](https://github.com/npduylab/windows-tablet-launcher/issues/new?template=new_app.yml) — hoặc tự thêm vào `launcher.config.json` rồi gửi pull request (việc rất hợp cho người mới!) |
| Đề xuất tính năng | [Mở issue "Đề xuất tính năng"](https://github.com/npduylab/windows-tablet-launcher/issues/new?template=feature_request.yml) |
| Hỏi cách dùng, khoe giao diện | [Discussions](https://github.com/npduylab/windows-tablet-launcher/discussions) |
| Viết code | Xem các issue gắn nhãn [`good first issue`](https://github.com/npduylab/windows-tablet-launcher/labels/good%20first%20issue), rồi làm theo hướng dẫn bên dưới |

## Chuẩn bị

- Windows 10/11 (khuyên dùng máy có màn hình cảm ứng để thử)
- Windows PowerShell 5.1 (có sẵn trong Windows) — **không cần** cài thêm gì để chạy launcher
- Google Chrome hoặc Microsoft Edge
- Python 3 — chỉ khi sửa MCP server
- Git, và một trình soạn thảo đọc được `.editorconfig` (VS Code, Notepad++…)

```powershell
git clone https://github.com/npduylab/windows-tablet-launcher.git
cd windows-tablet-launcher
.\ChayLauncher.cmd        # chạy launcher từ mã nguồn
```

## Cấu trúc dự án

| Đường dẫn | Nội dung |
|---|---|
| `Launcher.ps1` | Toàn bộ launcher: giao diện WPF (XAML), màn hình chính, Thư viện, Trung tâm điều khiển, đa nhiệm, PiP… Phần C# (Win32, âm lịch) nằm trong chuỗi `$NativeSource` ở đầu tệp |
| `launcher.config.json` | Danh sách app, nhóm, trang chủ, Dock và các tuỳ chọn |
| `mcp/touch_launcher_mcp.py` | MCP server cho Claude (Python thuần, không cần `pip`) |
| `src/TouchLauncher.cs` | Mã của `TouchLauncher.exe` — chạy `Launcher.ps1` ngay trong tiến trình |
| `build.ps1` | Tạo icon và biên dịch exe (dùng `csc.exe` có sẵn trong Windows) |
| `tests/` | `validate_config.ps1` (kiểm tra cấu hình), `test_mcp.py` (kiểm tra MCP server) |
| `docs/` | Trang giới thiệu (GitHub Pages) và ảnh chụp màn hình |
| `CaiDat.ps1`, `CaiMCP.ps1` | Tạo shortcut; đăng ký MCP với Claude Desktop |

## Thêm một app web (việc dễ nhất để bắt đầu)

Thêm một dòng vào `tiles` trong `launcher.config.json`:

```json
{ "group": "Mạng xã hội", "name": "Zalo", "icon": "Z", "color": "#0068FF",
  "type": "app", "target": "https://chat.zalo.me", "match": "Zalo" }
```

- `icon`: một ký tự (`Z`, `@`, `♪`) hoặc mã glyph [Segoe Fluent Icons](https://learn.microsoft.com/windows/apps/design/style/segoe-fluent-icons-font) như `E8D6`
- `match`: biểu thức (regex) khớp với tiêu đề cửa sổ của trang, để chạm lại thì chuyển về cửa sổ đang mở thay vì mở thêm
- `group`: một trong các nhóm đang có, hoặc nhóm mới

Rồi chạy `powershell -ExecutionPolicy Bypass -File tests\validate_config.ps1`.

## Quy ước viết code

- **Tệp `.ps1` phải lưu UTF-8 có BOM.** Windows PowerShell 5.1 đọc tệp không BOM theo bảng mã cũ → tiếng Việt bị lỗi. `.editorconfig` đã cấu hình sẵn; kiểm tra lại nếu trình soạn thảo không hỗ trợ.
- Code phải chạy được trên **Windows PowerShell 5.1** (không dùng cú pháp chỉ có ở PowerShell 7: `??`, `?.`, toán tử ba ngôi, `&&`).
- Không dùng dấu ngoặc kép cong `“ ”` trong chuỗi PowerShell — PowerShell coi chúng là dấu kết thúc chuỗi.
- Giao diện dùng tiếng Việt; chú thích code bằng tiếng Việt, ngắn gọn, giải thích *vì sao* hơn là *làm gì*.
- Tôn trọng pin và quyền riêng tư: không thêm timer chạy liên tục khi launcher ở nền, không gửi dữ liệu ra ngoài, không đọc nội dung cửa sổ của app khác ngoài tiêu đề.
- Thao tác cảm ứng: vùng chạm tối thiểu ~48px, không dựa vào hover.

## Kiểm tra trước khi gửi

```powershell
powershell -ExecutionPolicy Bypass -STA -File Launcher.ps1 -Check     # tải giao diện, không hiện cửa sổ
powershell -ExecutionPolicy Bypass -File tests\validate_config.ps1     # nếu sửa cấu hình
python tests/test_mcp.py                                               # nếu sửa MCP server
powershell -ExecutionPolicy Bypass -File build.ps1                     # nếu sửa src/ hoặc build.ps1
```

Và **chạy thử giao diện thật** — `-Check` không bắt được lỗi cảm ứng hay bố cục. CI trên GitHub sẽ tự chạy lại các bước trên cho mỗi pull request.

## Gửi pull request

1. Fork repo, tạo nhánh mới: `git checkout -b them-app-zalo`
2. Commit với mô tả rõ ràng (tiếng Việt hoặc tiếng Anh đều được), ví dụ `Thêm app Zalo vào nhóm Mạng xã hội`
3. Mở pull request, điền mẫu có sẵn; với thay đổi giao diện, kèm ảnh chụp (che thông tin riêng tư)

## Phát hành (dành cho người duy trì dự án)

1. Cập nhật tệp `VERSION` (vd. `1.2.0`) và commit
2. Gắn tag và đẩy lên:
   ```powershell
   git tag v1.2.0
   git push origin v1.2.0
   ```
3. GitHub Actions tự build `TouchLauncher.exe` đúng phiên bản và tạo Release kèm exe. Nút tải trên trang giới thiệu luôn trỏ tới bản mới nhất.

Bằng việc đóng góp, bạn đồng ý mã của mình được phát hành theo [giấy phép MIT](LICENSE) và tuân theo [Quy tắc ứng xử](CODE_OF_CONDUCT.md).

---

## English

Thanks for helping out! Bug reports, web-app suggestions, wording fixes and new features are all welcome.

- **Report a bug / suggest a feature or web app:** use the [issue templates](https://github.com/npduylab/windows-tablet-launcher/issues/new/choose). Questions go to [Discussions](https://github.com/npduylab/windows-tablet-launcher/discussions).
- **Run from source:** `git clone`, then `.\ChayLauncher.cmd`. Nothing else to install (Windows PowerShell 5.1 + WPF ship with Windows).
- **Easiest first contribution:** add a web app to `tiles` in `launcher.config.json` (see the example above), then run `tests\validate_config.ps1`.
- **Code rules:** save `.ps1` files as **UTF-8 with BOM**; target **Windows PowerShell 5.1** (no `??`, `?.`, ternaries, `&&`); never use curly quotes inside PowerShell strings; keep it battery- and privacy-friendly; touch targets ≥ 48px.
- **Before a PR:** `Launcher.ps1 -Check`, `tests\validate_config.ps1`, `tests/test_mcp.py`, `build.ps1` as relevant — and try the real UI. CI runs these on every pull request.
- **Releasing (maintainers):** bump `VERSION`, then `git tag vX.Y.Z && git push origin vX.Y.Z`; GitHub Actions builds the exe and publishes the release.

Contributions are released under the [MIT License](LICENSE) and covered by the [Code of Conduct](CODE_OF_CONDUCT.md).
