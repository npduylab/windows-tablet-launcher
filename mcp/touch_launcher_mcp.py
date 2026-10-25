"""MCP server cho Touch Launcher — cho Claude điều khiển máy tính bảng Windows.

Chỉ dùng thư viện chuẩn Python (không cần pip). Giao tiếp MCP qua stdio (JSON-RPC 2.0, mỗi dòng một thông điệp).

Công cụ: mở app của launcher, tìm kiếm Google/YouTube, mở URL, điều khiển nhạc/âm lượng, độ sáng,
xem pin & cửa sổ đang mở, chuyển/đóng cửa sổ, về màn hình chính, mở Trung tâm thông báo.
"""

import ctypes
import ctypes.wintypes as wt
import datetime
import json
import os
import re
import subprocess
import sys
import time
import unicodedata
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
LAUNCHER_DIR = os.path.dirname(HERE)
CONFIG_PATH = os.path.join(LAUNCHER_DIR, "launcher.config.json")
SERVER_INFO = {"name": "touch-launcher", "version": "1.0.0"}

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
dwmapi = ctypes.WinDLL("dwmapi")

EnumWindowsProc = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
user32.EnumWindows.argtypes = [EnumWindowsProc, wt.LPARAM]
user32.GetWindowLongPtrW.restype = ctypes.c_ssize_t
user32.GetWindowLongPtrW.argtypes = [wt.HWND, ctypes.c_int]
user32.GetWindow.restype = wt.HWND
user32.GetWindow.argtypes = [wt.HWND, wt.UINT]
user32.GetWindowTextW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
user32.GetWindowTextLengthW.argtypes = [wt.HWND]
user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
user32.IsWindowVisible.argtypes = [wt.HWND]
user32.IsIconic.argtypes = [wt.HWND]
user32.ShowWindow.argtypes = [wt.HWND, ctypes.c_int]
user32.SetForegroundWindow.argtypes = [wt.HWND]
user32.PostMessageW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
user32.keybd_event.argtypes = [wt.BYTE, wt.BYTE, wt.DWORD, ctypes.c_size_t]
dwmapi.DwmGetWindowAttribute.argtypes = [wt.HWND, wt.DWORD, ctypes.c_void_p, wt.DWORD]
kernel32.OpenProcess.restype = wt.HANDLE
kernel32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
kernel32.QueryFullProcessImageNameW.argtypes = [wt.HANDLE, wt.DWORD, wt.LPWSTR, ctypes.POINTER(wt.DWORD)]
kernel32.CloseHandle.argtypes = [wt.HANDLE]


class SYSTEM_POWER_STATUS(ctypes.Structure):
    _fields_ = [("ACLineStatus", wt.BYTE), ("BatteryFlag", wt.BYTE), ("BatteryLifePercent", wt.BYTE),
                ("SystemStatusFlag", wt.BYTE), ("BatteryLifeTime", wt.DWORD), ("BatteryFullLifeTime", wt.DWORD)]


# ------------------------------------------------------------------ Tiện ích Windows

def log(*args):
    print(*args, file=sys.stderr, flush=True)


def load_config():
    with open(CONFIG_PATH, encoding="utf-8-sig") as f:
        cfg = json.load(f)
    # App người dùng tự thêm trong launcher (nút "+ Thêm app").
    user_path = os.path.join(LAUNCHER_DIR, "apps.user.json")
    if os.path.isfile(user_path):
        try:
            with open(user_path, encoding="utf-8-sig") as f:
                extra = json.load(f)
            if isinstance(extra, dict):
                extra = [extra]
            cfg["tiles"] = cfg.get("tiles", []) + [t for t in extra if isinstance(t, dict) and t.get("name") and t.get("target")]
        except (OSError, ValueError):
            pass
    return cfg


def process_name(pid):
    h = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return ""
    try:
        size = wt.DWORD(1024)
        buf = ctypes.create_unicode_buffer(size.value)
        if kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)):
            return os.path.splitext(os.path.basename(buf.value))[0].lower()
        return ""
    finally:
        kernel32.CloseHandle(h)


def app_windows():
    """Cửa sổ ứng dụng đang mở, theo thứ tự dùng gần nhất (giống thanh tác vụ)."""
    result = []

    def callback(hwnd, _):
        if not user32.IsWindowVisible(hwnd) or user32.GetWindow(hwnd, 4):  # GW_OWNER
            return True
        ex = user32.GetWindowLongPtrW(hwnd, -20)
        if (ex & 0x80 and not ex & 0x40000) or ex & 0x08000000:  # tool window / no-activate
            return True
        cloaked = ctypes.c_int(0)
        if dwmapi.DwmGetWindowAttribute(hwnd, 14, ctypes.byref(cloaked), 4) == 0 and cloaked.value:
            return True
        n = user32.GetWindowTextLengthW(hwnd)
        if n == 0:
            return True
        buf = ctypes.create_unicode_buffer(n + 1)
        user32.GetWindowTextW(hwnd, buf, n + 1)
        if buf.value == "Program Manager":
            return True
        pid = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        result.append({"hwnd": hwnd, "title": buf.value, "pid": pid.value,
                       "minimized": bool(user32.IsIconic(hwnd)), "process": process_name(pid.value)})
        return True

    user32.EnumWindows(EnumWindowsProc(callback), 0)
    return result


def activate(hwnd):
    if user32.IsIconic(hwnd):
        user32.ShowWindow(hwnd, 9)  # SW_RESTORE
    # Nhấn-nhả Alt để Windows cho phép chuyển cửa sổ lên trước từ tiến trình nền.
    user32.keybd_event(0x12, 0, 0, 0)
    user32.keybd_event(0x12, 0, 2, 0)
    user32.SetForegroundWindow(hwnd)


def press(vk):
    user32.keybd_event(vk, 0, 1, 0)
    user32.keybd_event(vk, 0, 3, 0)


def fold(s):
    """Chữ thường, bỏ dấu tiếng Việt — để 'nhac' khớp 'Nhạc'."""
    s = unicodedata.normalize("NFD", s.replace("đ", "d").replace("Đ", "D"))
    return "".join(c for c in s if unicodedata.category(c) != "Mn").casefold().strip()


def find_browser(cfg):
    pref = cfg.get("browser", "chrome")
    if pref and os.path.isfile(pref):
        return pref
    pf, pf86, local = os.environ.get("ProgramFiles", ""), os.environ.get("ProgramFiles(x86)", ""), os.environ.get("LOCALAPPDATA", "")
    paths = {
        "chrome": [os.path.join(pf, r"Google\Chrome\Application\chrome.exe"), os.path.join(pf86, r"Google\Chrome\Application\chrome.exe"),
                   os.path.join(local, r"Google\Chrome\Application\chrome.exe")],
        "edge": [os.path.join(pf86, r"Microsoft\Edge\Application\msedge.exe"), os.path.join(pf, r"Microsoft\Edge\Application\msedge.exe")],
    }
    order = ["edge", "chrome"] if pref == "edge" else ["chrome", "edge"]
    for k in order:
        for p in paths[k]:
            if os.path.isfile(p):
                return p
    return None


def launch_and_maximize(args, maximize=True):
    """Mở chương trình rồi phóng to cửa sổ mới xuất hiện (như launcher)."""
    before = {w["hwnd"] for w in app_windows()}
    subprocess.Popen(args, creationflags=0x00000008 | 0x00000200, close_fds=True)  # DETACHED | NEW_GROUP
    if not maximize:
        return None
    deadline = time.time() + 6
    while time.time() < deadline:
        time.sleep(0.2)
        for w in app_windows():
            if w["hwnd"] not in before:
                user32.ShowWindow(w["hwnd"], 3)  # SW_MAXIMIZE
                return w["title"]
    return None


def main_profile(cfg, browser):
    """Hồ sơ Chrome cố định cho các app (giống launcher): browserProfile, mặc định 'Default'."""
    prof = cfg.get("browserProfile") or ""
    if browser and os.path.basename(browser).lower() == "chrome.exe":
        prof = prof or "Default"
        if not os.path.isdir(os.path.join(os.environ.get("LOCALAPPDATA", ""), "Google", "Chrome", "User Data", prof)):
            return None
    return prof or None


def open_web_app(url, cfg=None, profile=None):
    cfg = cfg or load_config()
    browser = find_browser(cfg)
    profile = profile or main_profile(cfg, browser)
    if not browser:
        os.startfile(url)
        return "Đã mở bằng trình duyệt mặc định."
    args = [browser, f"--app={url}"] + list(cfg.get("browserArgs") or [])
    if profile:  # app gắn với một hồ sơ Chrome (vd. Gmail của từng tài khoản)
        args.insert(1, f"--profile-directory={profile}")
    launch_and_maximize(args, cfg.get("appWindowMode") != "normal")
    return f"Đã mở {url}."


def find_tile(cfg, name):
    tiles = cfg.get("tiles", [])
    key = fold(name)
    for t in tiles:
        if fold(t["name"]) == key:
            return t
    for t in tiles:
        if key in fold(t["name"]) or fold(t["name"]) in key:
            return t
    return None


def find_tile_window(cfg, tile):
    pattern = tile.get("match")
    if not pattern:
        return None
    browser = os.path.splitext(os.path.basename(find_browser(cfg) or ""))[0].lower()
    for w in app_windows():
        if w["process"] not in (browser, "chrome", "msedge"):
            continue
        if re.search(r"(Edge|Chrome)$", w["title"]) or not re.search(pattern, w["title"]):
            continue
        return w
    return None


def find_window(title):
    key = fold(title)
    wins = app_windows()
    for w in wins:
        if fold(w["title"]) == key:
            return w
    for w in wins:
        if key in fold(w["title"]):
            return w
    return None


def battery():
    s = SYSTEM_POWER_STATUS()
    if not kernel32.GetSystemPowerStatus(ctypes.byref(s)) or s.BatteryFlag == 128:
        return None
    return {"percent": s.BatteryLifePercent, "charging": s.ACLineStatus == 1,
            "minutes_left": s.BatteryLifeTime // 60 if s.BatteryLifeTime != 0xFFFFFFFF else None}


def run_powershell(script, timeout=20):
    r = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                       capture_output=True, text=True, timeout=timeout, creationflags=0x08000000)  # CREATE_NO_WINDOW
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()


# ------------------------------------------------------------------ Công cụ MCP

def t_list_apps(_):
    cfg = load_config()
    pins = cfg.get("home", [])
    pinned_path = os.path.join(LAUNCHER_DIR, "pinned.json")
    if os.path.isfile(pinned_path):
        try:
            with open(pinned_path, encoding="utf-8-sig") as f:
                pins = json.load(f)
        except Exception:
            pass
    lines = []
    for t in cfg.get("tiles", []):
        mark = " (trang chủ)" if t["name"] in pins else ""
        lines.append(f"- [{t.get('group', 'Khác')}] {t['name']}{mark}: {t.get('target', '')}")
    return "Ứng dụng trong launcher:\n" + "\n".join(lines)


def t_open_app(a):
    cfg = load_config()
    tile = find_tile(cfg, a.get("name", ""))
    if not tile:
        names = ", ".join(t["name"] for t in cfg.get("tiles", []))
        raise ValueError(f"Không có app '{a.get('name')}'. Các app hiện có: {names}")
    w = find_tile_window(cfg, tile)
    if w:
        activate(w["hwnd"])
        return f"{tile['name']} đang mở sẵn — đã chuyển tới cửa sổ \"{w['title']}\"."
    target = os.path.expandvars(tile.get("target", ""))
    kind = tile.get("type", "app")
    if kind == "app":
        return open_web_app(target, cfg, tile.get("profile")).replace("Đã mở", f"Đã mở {tile['name']}:", 1)
    if kind == "web":
        browser = find_browser(cfg)
        if browser:
            prof = tile.get("profile") or main_profile(cfg, browser)
            extra = [f"--profile-directory={prof}"] if prof else []
            launch_and_maximize([browser] + extra + [target] + list(cfg.get("browserArgs") or []), cfg.get("appWindowMode") != "normal")
        else:
            os.startfile(target)
        return f"Đã mở {tile['name']}."
    os.startfile(target)
    return f"Đã mở {tile['name']}."


SEARCH_URLS = {
    "google": "https://www.google.com/search?q={q}",
    "youtube": "https://www.youtube.com/results?search_query={q}",
    "youtube_music": "https://music.youtube.com/search?q={q}",
    "maps": "https://www.google.com/maps/search/{q}",
    "shopee": "https://shopee.vn/search?keyword={q}",
}


def t_search(a):
    where = a.get("where", "google")
    if where not in SEARCH_URLS:
        raise ValueError("where phải là: " + ", ".join(SEARCH_URLS))
    q = a.get("query", "").strip()
    if not q:
        raise ValueError("Thiếu query.")
    url = SEARCH_URLS[where].format(q=urllib.parse.quote(q))
    open_web_app(url)
    return f"Đã mở kết quả tìm \"{q}\" trên {where}: {url}"


def t_open_url(a):
    url = a.get("url", "").strip()
    if not re.match(r"^https?://", url):
        raise ValueError("url phải bắt đầu bằng http:// hoặc https://")
    return open_web_app(url)


MEDIA_KEYS = {"play_pause": 0xB3, "next": 0xB0, "previous": 0xB1, "stop": 0xB2,
              "volume_up": 0xAF, "volume_down": 0xAE, "mute": 0xAD}


def t_media(a):
    action = a.get("action", "")
    if action not in MEDIA_KEYS:
        raise ValueError("action phải là: " + ", ".join(MEDIA_KEYS))
    times = max(1, min(int(a.get("times", 1)), 25)) if action.startswith("volume") else 1
    for _ in range(times):
        press(MEDIA_KEYS[action])
    return f"Đã gửi {action}" + (f" x{times}" if times > 1 else "") + "."


def t_set_brightness(a):
    v = max(0, min(100, int(a.get("percent", 50))))
    code, _, err = run_powershell(
        "Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -OperationTimeoutSec 5 | "
        f"Select-Object -First 1 | Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{{Timeout=[uint32]1;Brightness=[byte]{v}}} | Out-Null")
    if code != 0:
        raise RuntimeError("Màn hình này không chỉnh được độ sáng. " + err[:200])
    return f"Đã đặt độ sáng {v}%."


def t_get_status(_):
    now = datetime.datetime.now()
    b = battery()
    if b:
        pin = f"Pin {b['percent']}%" + (" (đang sạc)" if b["charging"] else "")
        if b["minutes_left"] and not b["charging"]:
            pin += f", còn khoảng {b['minutes_left'] // 60} giờ {b['minutes_left'] % 60} phút"
    else:
        pin = "Không có pin (đang cắm điện)"
    wins = [w for w in app_windows() if not w["title"].startswith("Touch Launcher")]
    lines = [f"Bây giờ: {now:%H:%M, %d/%m/%Y}", pin, f"Đang mở {len(wins)} cửa sổ:"]
    lines += [f"- {w['title']}" + (" (thu nhỏ)" if w["minimized"] else "") for w in wins]
    return "\n".join(lines)


def t_list_windows(_):
    wins = [w for w in app_windows() if not w["title"].startswith("Touch Launcher")]
    if not wins:
        return "Không có cửa sổ nào đang mở."
    return "\n".join(f"- {w['title']} [{w['process']}]" + (" (thu nhỏ)" if w["minimized"] else "") for w in wins)


def t_switch_window(a):
    w = find_window(a.get("title", ""))
    if not w:
        raise ValueError(f"Không tìm thấy cửa sổ có tiêu đề chứa '{a.get('title')}'.")
    activate(w["hwnd"])
    return f"Đã chuyển tới \"{w['title']}\"."


def t_close_window(a):
    w = find_window(a.get("title", ""))
    if not w:
        raise ValueError(f"Không tìm thấy cửa sổ có tiêu đề chứa '{a.get('title')}'.")
    user32.PostMessageW(w["hwnd"], 0x0010, 0, 0)  # WM_CLOSE — app vẫn có thể hỏi lưu dữ liệu
    return f"Đã yêu cầu đóng \"{w['title']}\"."


def t_go_home(_):
    for w in app_windows():
        if w["title"] == "Touch Launcher":
            user32.ShowWindow(w["hwnd"], 3)
            activate(w["hwnd"])
            return "Đã về màn hình chính của launcher."
    script = os.path.join(LAUNCHER_DIR, "Launcher.ps1")
    subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-WindowStyle", "Hidden", "-File", script],
                     creationflags=0x08000000 | 0x00000008)
    return "Launcher chưa chạy — đã khởi động launcher."


def t_notifications(_):
    user32.keybd_event(0x5B, 0, 1, 0)
    user32.keybd_event(0x4E, 0, 0, 0)
    user32.keybd_event(0x4E, 0, 2, 0)
    user32.keybd_event(0x5B, 0, 3, 0)
    return "Đã mở Trung tâm thông báo & lịch của Windows."


TOOLS = [
    {"name": "list_apps", "fn": t_list_apps,
     "description": "List the apps available in the Touch Launcher (web apps such as YouTube, Telegram, Gmail, games), with their group and whether they are on the home screen.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "open_app", "fn": t_open_app,
     "description": "Open a launcher app by name (Vietnamese names, accents optional, e.g. 'YouTube', 'Nghe nhạc', 'Gmail', 'Xem TV'). If it is already open, switches to its window instead of opening a duplicate.",
     "inputSchema": {"type": "object", "properties": {"name": {"type": "string", "description": "App name as listed by list_apps"}}, "required": ["name"]}},
    {"name": "search", "fn": t_search,
     "description": "Search on the tablet and show the results full-screen: Google, YouTube (videos), YouTube Music (songs), Google Maps (places) or Shopee (products).",
     "inputSchema": {"type": "object", "properties": {
         "query": {"type": "string"},
         "where": {"type": "string", "enum": list(SEARCH_URLS), "default": "google"}}, "required": ["query"]}},
    {"name": "open_url", "fn": t_open_url,
     "description": "Open an http(s) URL as a full-screen app window on the tablet.",
     "inputSchema": {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}},
    {"name": "media", "fn": t_media,
     "description": "Control music/video playback and volume with system media keys (works for YouTube, YouTube Music, Spotify...). Each volume step is about 2%.",
     "inputSchema": {"type": "object", "properties": {
         "action": {"type": "string", "enum": list(MEDIA_KEYS)},
         "times": {"type": "integer", "minimum": 1, "maximum": 25, "description": "Repeat count for volume_up/volume_down"}}, "required": ["action"]}},
    {"name": "set_brightness", "fn": t_set_brightness,
     "description": "Set the built-in screen brightness (0-100).",
     "inputSchema": {"type": "object", "properties": {"percent": {"type": "integer", "minimum": 0, "maximum": 100}}, "required": ["percent"]}},
    {"name": "get_status", "fn": t_get_status,
     "description": "Get the tablet status: current time, battery level/charging, and the open windows.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "list_windows", "fn": t_list_windows,
     "description": "List open app windows, most recently used first.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "switch_window", "fn": t_switch_window,
     "description": "Bring an open window to the front, matching part of its title (accents optional).",
     "inputSchema": {"type": "object", "properties": {"title": {"type": "string"}}, "required": ["title"]}},
    {"name": "close_window", "fn": t_close_window,
     "description": "Politely close an open window (the app may still ask to save). Match part of its title.",
     "inputSchema": {"type": "object", "properties": {"title": {"type": "string"}}, "required": ["title"]}},
    {"name": "go_home", "fn": t_go_home,
     "description": "Show the Touch Launcher home screen (starts the launcher if it is not running).",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "open_notifications", "fn": t_notifications,
     "description": "Open the Windows notification center and calendar.",
     "inputSchema": {"type": "object", "properties": {}}},
]
TOOL_MAP = {t["name"]: t for t in TOOLS}
INSTRUCTIONS = ("Điều khiển máy tính bảng Windows chạy Touch Launcher. Dùng list_apps để biết các app, open_app để mở, "
                "search để tìm Google/YouTube/nhạc/bản đồ/Shopee, media để phát/dừng nhạc và chỉnh âm lượng, "
                "get_status để xem pin và cửa sổ đang mở. Trả lời người dùng bằng tiếng Việt.")


# ------------------------------------------------------------------ JSON-RPC qua stdio

def handle(msg):
    mid, method, params = msg.get("id"), msg.get("method"), msg.get("params") or {}
    if method == "initialize":
        result = {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                  "capabilities": {"tools": {"listChanged": False}},
                  "serverInfo": SERVER_INFO, "instructions": INSTRUCTIONS}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": [{k: v for k, v in t.items() if k != "fn"} for t in TOOLS]}
    elif method == "tools/call":
        tool = TOOL_MAP.get(params.get("name"))
        if not tool:
            return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": f"Unknown tool: {params.get('name')}"}}
        try:
            text, is_error = tool["fn"](params.get("arguments") or {}), False
        except Exception as e:  # lỗi công cụ trả về cho Claude đọc, không làm sập server
            text, is_error = f"Lỗi: {e}", True
        result = {"content": [{"type": "text", "text": text}], "isError": is_error}
    elif mid is None:
        return None  # notification (vd. notifications/initialized)
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"Method not found: {method}"}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main():
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    log("touch-launcher MCP server started")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        batch = msg if isinstance(msg, list) else [msg]
        replies = [r for r in (handle(m) for m in batch if isinstance(m, dict)) if r is not None]
        if replies:
            out = replies if isinstance(msg, list) else replies[0]
            sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
