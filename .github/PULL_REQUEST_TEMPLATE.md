## Thay đổi gì? / What changed?

<!-- Mô tả ngắn, kèm ảnh chụp nếu thay đổi giao diện. Nhớ che thông tin riêng tư. -->
<!-- Short description, with a screenshot for UI changes. Hide private info. -->

Closes #

## Đã kiểm tra / Checklist

- [ ] `powershell -ExecutionPolicy Bypass -STA -File Launcher.ps1 -Check` chạy không lỗi
- [ ] `powershell -ExecutionPolicy Bypass -File tests\validate_config.ps1` báo OK (nếu sửa cấu hình)
- [ ] `python tests/test_mcp.py` báo OK (nếu sửa MCP server)
- [ ] Đã chạy thử giao diện thật trên máy (cảm ứng hoặc chuột)
- [ ] Tệp `.ps1` vẫn lưu dạng UTF-8 **có BOM** (để Windows PowerShell đọc đúng tiếng Việt)
