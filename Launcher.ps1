<#
  Touch Launcher — launcher toàn màn hình kiểu iPad cho máy Windows cảm ứng.
  Màn hình chính + Dock · Trung tâm điều khiển · thanh điều hướng nổi · đa nhiệm
  · bàn phím cảm ứng · PiP YouTube · tiết kiệm pin · dọn tiến trình.

  Chạy:  powershell -NoProfile -ExecutionPolicy Bypass -STA -File Launcher.ps1
  Kiểm tra (không hiện cửa sổ):  ... -File Launcher.ps1 -Check
#>
param([switch]$Check)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ---------------------------------------------------------------- Chỉ chạy 1 bản
if (-not $Check) {
    $created = $false
    $script:Mutex = New-Object System.Threading.Mutex($true, 'Local\TouchLauncherSingleton', [ref]$created)
    if (-not $created) { exit }
}

# ---------------------------------------------------------------- Win32
$NativeSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace TouchLauncher {
    public class WinInfo { public IntPtr Handle; public string Title; public bool Minimized; public int Pid; }
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);

    [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int cx; public int cy; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct DWM_THUMBNAIL_PROPERTIES {
        public int dwFlags; public RECT rcDestination; public RECT rcSource; public byte opacity; public bool fVisible; public bool fSourceClientAreaOnly;
    }

    [ComImport, Guid("37c994e7-432b-4834-a2f7-dce1f13b834b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ITipInvocation { void Toggle(IntPtr hwnd); }
    [ComImport, Guid("4ce576fa-83dc-4F88-951c-9d0782b4e376")]
    public class UIHostNoLaunch { }

    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItemImageFactory { [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr phbm); }

    // Báo khi một cửa sổ app đang được theo dõi bị đóng. Chỉ nghe sự kiện của đúng tiến trình
    // trình duyệt chứa cửa sổ đó (không nghe toàn hệ thống) để đỡ tốn pin.
    public delegate void WinEventDelegate(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
    public static class WinWatch {
        [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventDelegate proc, uint pid, uint tid, uint flags);
        [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        static readonly WinEventDelegate Proc = OnEvent;          // giữ tham chiếu để không bị thu gom
        static readonly Dictionary<uint, IntPtr> Hooks = new Dictionary<uint, IntPtr>();
        static readonly HashSet<long> Tracked = new HashSet<long>();
        public static Action<long> OnClosed;

        public static void Track(IntPtr hwnd) {
            if (hwnd == IntPtr.Zero || !Tracked.Add(hwnd.ToInt64())) return;
            uint pid; GetWindowThreadProcessId(hwnd, out pid);
            if (pid != 0 && !Hooks.ContainsKey(pid)) {
                IntPtr h = SetWinEventHook(0x8001, 0x8001, IntPtr.Zero, Proc, pid, 0, 0 /* OUTOFCONTEXT */);  // EVENT_OBJECT_DESTROY
                if (h != IntPtr.Zero) Hooks[pid] = h;
            }
        }
        public static bool IsTracked(IntPtr hwnd) { return Tracked.Contains(hwnd.ToInt64()); }
        public static void StopAll() { foreach (var h in Hooks.Values) UnhookWinEvent(h); Hooks.Clear(); Tracked.Clear(); }

        static void OnEvent(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time) {
            if (idObject != 0 || idChild != 0) return;              // chỉ cửa sổ, không phải đối tượng con
            if (!Tracked.Remove(hwnd.ToInt64())) return;
            var cb = OnClosed;
            if (cb != null) cb(hwnd.ToInt64());
        }
    }

    // Âm lịch Việt Nam (thuật toán Hồ Ngọc Đức, múi giờ +7).
    public static class Lunar {
        static int INT(double d) { return (int)Math.Floor(d); }
        public static int JdFromDate(int dd, int mm, int yy) {
            int a = INT((14 - mm) / 12.0), y = yy + 4800 - a, m = mm + 12 * a - 3;
            int jd = dd + INT((153 * m + 2) / 5.0) + 365 * y + INT(y / 4.0) - INT(y / 100.0) + INT(y / 400.0) - 32045;
            if (jd < 2299161) jd = dd + INT((153 * m + 2) / 5.0) + 365 * y + INT(y / 4.0) - 32083;
            return jd;
        }
        static double NewMoon(int k) {
            double T = k / 1236.85, T2 = T * T, T3 = T2 * T, dr = Math.PI / 180;
            double Jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * T2 - 0.000000155 * T3;
            Jd1 += 0.00033 * Math.Sin((166.56 + 132.87 * T - 0.009173 * T2) * dr);
            double M = 359.2242 + 29.10535608 * k - 0.0000333 * T2 - 0.00000347 * T3;
            double Mpr = 306.0253 + 385.81691806 * k + 0.0107306 * T2 + 0.00001236 * T3;
            double F = 21.2964 + 390.67050646 * k - 0.0016528 * T2 - 0.00000239 * T3;
            double C1 = (0.1734 - 0.000393 * T) * Math.Sin(M * dr) + 0.0021 * Math.Sin(2 * dr * M);
            C1 = C1 - 0.4068 * Math.Sin(Mpr * dr) + 0.0161 * Math.Sin(dr * 2 * Mpr);
            C1 = C1 - 0.0004 * Math.Sin(dr * 3 * Mpr);
            C1 = C1 + 0.0104 * Math.Sin(dr * 2 * F) - 0.0051 * Math.Sin(dr * (M + Mpr));
            C1 = C1 - 0.0074 * Math.Sin(dr * (M - Mpr)) + 0.0004 * Math.Sin(dr * (2 * F + M));
            C1 = C1 - 0.0004 * Math.Sin(dr * (2 * F - M)) - 0.0006 * Math.Sin(dr * (2 * F + Mpr));
            C1 = C1 + 0.0010 * Math.Sin(dr * (2 * F - Mpr)) + 0.0005 * Math.Sin(dr * (2 * Mpr + M));
            double deltat = T < -11
                ? 0.001 + 0.000839 * T + 0.0002261 * T2 - 0.00000845 * T3 - 0.000000081 * T * T3
                : -0.000278 + 0.000265 * T + 0.000262 * T2;
            return Jd1 + C1 - deltat;
        }
        static int NewMoonDay(int k, double tz) { return INT(NewMoon(k) + 0.5 + tz / 24); }
        static int SunLongitude(int dayNumber, double tz) {
            double jdn = dayNumber - 0.5 - tz / 24;
            double T = (jdn - 2451545.0) / 36525, T2 = T * T, dr = Math.PI / 180;
            double M = 357.52910 + 35999.05030 * T - 0.0001559 * T2 - 0.00000048 * T * T2;
            double L0 = 280.46645 + 36000.76983 * T + 0.0003032 * T2;
            double DL = (1.914600 - 0.004817 * T - 0.000014 * T2) * Math.Sin(dr * M);
            DL += (0.019993 - 0.000101 * T) * Math.Sin(dr * 2 * M) + 0.000290 * Math.Sin(dr * 3 * M);
            double L = (L0 + DL) * dr;
            L -= Math.PI * 2 * INT(L / (Math.PI * 2));
            return INT(L / Math.PI * 6);
        }
        static int LunarMonth11(int yy, double tz) {
            int off = JdFromDate(31, 12, yy) - 2415021;
            int k = INT(off / 29.530588853);
            int nm = NewMoonDay(k, tz);
            if (SunLongitude(nm, tz) >= 9) nm = NewMoonDay(k - 1, tz);
            return nm;
        }
        static int LeapMonthOffset(int a11, double tz) {
            int k = INT((a11 - 2415021.076998695) / 29.530588853 + 0.5);
            int last, i = 1, arc = SunLongitude(NewMoonDay(k + i, tz), tz);
            do { last = arc; i++; arc = SunLongitude(NewMoonDay(k + i, tz), tz); } while (arc != last && i < 14);
            return i - 1;
        }
        // Trả về { ngày, tháng, năm, nhuận(0/1) } âm lịch.
        public static int[] FromSolar(int dd, int mm, int yy) {
            const double tz = 7.0;
            int dayNumber = JdFromDate(dd, mm, yy);
            int k = INT((dayNumber - 2415021.076998695) / 29.530588853);
            int monthStart = NewMoonDay(k + 1, tz);
            if (monthStart > dayNumber) monthStart = NewMoonDay(k, tz);
            int a11 = LunarMonth11(yy, tz), b11 = a11, lunarYear;
            if (a11 >= monthStart) { lunarYear = yy; a11 = LunarMonth11(yy - 1, tz); }
            else { lunarYear = yy + 1; b11 = LunarMonth11(yy + 1, tz); }
            int lunarDay = dayNumber - monthStart + 1;
            int diff = INT((monthStart - a11) / 29.0);
            int leap = 0, lunarMonth = diff + 11;
            if (b11 - a11 > 365) {
                int leapDiff = LeapMonthOffset(a11, tz);
                if (diff >= leapDiff) { lunarMonth = diff + 10; if (diff == leapDiff) leap = 1; }
            }
            if (lunarMonth > 12) lunarMonth -= 12;
            if (lunarMonth >= 11 && diff < 4) lunarYear -= 1;
            return new int[] { lunarDay, lunarMonth, lunarYear, leap };
        }
    }

    public static class Native {
        [DllImport("user32.dll")] static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool LockWorkStation();
        [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
        [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
        // Số giây kể từ lần chạm / bấm phím cuối cùng.
        public static uint IdleSeconds() {
            LASTINPUTINFO l = new LASTINPUTINFO(); l.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            if (!GetLastInputInfo(ref l)) return 0;
            return unchecked((uint)Environment.TickCount - l.dwTime) / 1000;
        }
        // Giữ màn hình sáng (chế độ đồng hồ đầu giường); false = trả lại cho Windows quản lý.
        public static void KeepDisplayOn(bool on) { SetThreadExecutionState(on ? 0x80000003u : 0x80000000u); }
        [DllImport("user32.dll")] static extern IntPtr GetDesktopWindow();
        [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
        [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr64(IntPtr h, int i);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]    static extern int GetWindowLong32(IntPtr h, int i);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr64(IntPtr h, int i, IntPtr v);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongW")]    static extern int SetWindowLong32(IntPtr h, int i, int v);
        [DllImport("user32.dll", EntryPoint = "GetClassLongPtrW")]  static extern IntPtr GetClassLongPtr64(IntPtr h, int i);
        [DllImport("user32.dll", EntryPoint = "GetClassLongW")]     static extern uint GetClassLong32(IntPtr h, int i);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
        [DllImport("psapi.dll")]  public static extern bool EmptyWorkingSet(IntPtr hProcess);
        [DllImport("gdi32.dll")]  static extern int GetObject(IntPtr h, int c, out BITMAP bm);
        [DllImport("gdi32.dll")]  static extern int GetDIBits(IntPtr hdc, IntPtr hbm, uint start, uint lines, [Out] byte[] bits, ref BITMAPINFOHEADER bmi, uint usage);
        [DllImport("gdi32.dll")]  static extern bool DeleteObject(IntPtr h);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid, out IShellItemImageFactory ppv);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
        [DllImport("dwmapi.dll")] static extern int DwmRegisterThumbnail(IntPtr dest, IntPtr src, out IntPtr thumb);
        [DllImport("dwmapi.dll")] static extern int DwmUnregisterThumbnail(IntPtr thumb);
        [DllImport("dwmapi.dll")] static extern int DwmQueryThumbnailSourceSize(IntPtr thumb, out SIZE size);
        [DllImport("dwmapi.dll")] static extern int DwmUpdateThumbnailProperties(IntPtr thumb, ref DWM_THUMBNAIL_PROPERTIES props);

        // Chế độ năng lượng (Settings > Power mode) — không cần quyền admin.
        [DllImport("powrprof.dll")] public static extern uint PowerSetActiveOverlayScheme(Guid overlay);
        [DllImport("powrprof.dll")] public static extern uint PowerGetEffectiveOverlayScheme(out Guid overlay);

        [StructLayout(LayoutKind.Sequential)] struct PPTS { public uint Version; public uint ControlMask; public uint StateMask; }
        [DllImport("kernel32.dll")] static extern bool SetProcessInformation(IntPtr hProcess, int infoClass, ref PPTS info, uint size);

        [StructLayout(LayoutKind.Sequential)] struct BITMAP { public int bmType; public int bmWidth; public int bmHeight; public int bmWidthBytes; public ushort bmPlanes; public ushort bmBitsPixel; public IntPtr bmBits; }
        [StructLayout(LayoutKind.Sequential)] struct BITMAPINFOHEADER {
            public uint biSize; public int biWidth; public int biHeight; public ushort biPlanes; public ushort biBitCount;
            public uint biCompression; public uint biSizeImage; public int biXPelsPerMeter; public int biYPelsPerMeter; public uint biClrUsed; public uint biClrImportant;
        }

        // Bật EcoQoS (chế độ hiệu suất) cho tiến trình: CPU chạy ở xung thấp, tiết kiệm pin.
        public static void EcoQoS(IntPtr h) {
            PPTS s = new PPTS(); s.Version = 1; s.ControlMask = 1; s.StateMask = 1;
            SetProcessInformation(h, 4 /* ProcessPowerThrottling */, ref s, (uint)Marshal.SizeOf(typeof(PPTS)));
        }

        public static void Key(byte vk) { keybd_event(vk, 0, 1, UIntPtr.Zero); keybd_event(vk, 0, 3, UIntPtr.Zero); }
        // Phím thường (không phải phím mở rộng), vd. F5.
        public static void KeyPlain(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); keybd_event(vk, 0, 2, UIntPtr.Zero); }
        // Win + phím (vd. Win+N mở Trung tâm thông báo & lịch của Windows).
        public static void WinCombo(byte vk) {
            keybd_event(0x5B, 0, 1, UIntPtr.Zero);
            keybd_event(vk, 0, 0, UIntPtr.Zero); keybd_event(vk, 0, 2, UIntPtr.Zero);
            keybd_event(0x5B, 0, 3, UIntPtr.Zero);
        }
        public static void MonitorOff() { PostMessage((IntPtr)0xFFFF, 0x0112, (IntPtr)0xF170, (IntPtr)2); }

        // Bật/tắt bàn phím cảm ứng của Windows. Trả false nếu TabTip chưa chạy.
        public static bool ToggleTouchKeyboard() {
            try { ((ITipInvocation)new UIHostNoLaunch()).Toggle(GetDesktopWindow()); return true; }
            catch { return false; }
        }

        static long GetExStyle(IntPtr h) { return IntPtr.Size == 8 ? GetWindowLongPtr64(h, -20).ToInt64() : GetWindowLong32(h, -20); }

        // Cửa sổ không bao giờ nhận focus (thanh điều hướng, trung tâm điều khiển).
        public static void MakeNoActivate(IntPtr h) {
            long ex = GetExStyle(h) | 0x08000000 /* NOACTIVATE */ | 0x80 /* TOOLWINDOW */;
            if (IntPtr.Size == 8) SetWindowLongPtr64(h, -20, new IntPtr(ex)); else SetWindowLong32(h, -20, (int)ex);
        }

        // Các cửa sổ ứng dụng đang mở, theo thứ tự dùng gần nhất.
        public static List<WinInfo> GetAppWindows(int excludePid) {
            var list = new List<WinInfo>();
            EnumWindows((h, l) => {
                if (!IsWindowVisible(h) || GetWindow(h, 4 /* GW_OWNER */) != IntPtr.Zero) return true;
                long ex = GetExStyle(h);
                if ((ex & 0x80) != 0 && (ex & 0x40000) == 0) return true;       // tool window
                if ((ex & 0x08000000) != 0) return true;                        // no-activate
                int cloaked; if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
                int len = GetWindowTextLength(h); if (len == 0) return true;
                uint pid; GetWindowThreadProcessId(h, out pid);
                if ((int)pid == excludePid) return true;
                var sb = new StringBuilder(len + 1); GetWindowText(h, sb, sb.Capacity);
                string title = sb.ToString();
                if (title == "Program Manager") return true;
                list.Add(new WinInfo { Handle = h, Title = title, Minimized = IsIconic(h), Pid = (int)pid });
                return true;
            }, IntPtr.Zero);
            return list;
        }

        public static IntPtr GetWindowIcon(IntPtr h) {
            IntPtr r;
            SendMessageTimeout(h, 0x7F /* WM_GETICON */, (IntPtr)1, IntPtr.Zero, 2, 50, out r);
            if (r == IntPtr.Zero) SendMessageTimeout(h, 0x7F, (IntPtr)2, IntPtr.Zero, 2, 50, out r);
            if (r == IntPtr.Zero) r = IntPtr.Size == 8 ? GetClassLongPtr64(h, -14) : (IntPtr)GetClassLong32(h, -14);
            if (r == IntPtr.Zero) r = IntPtr.Size == 8 ? GetClassLongPtr64(h, -34) : (IntPtr)GetClassLong32(h, -34);
            return r;
        }

        [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
        // Đưa cửa sổ lên trước kể cả khi người dùng vừa bấm ở app khác (Windows thường chặn việc này):
        // tạm gắn vào luồng nhập liệu của cửa sổ đang ở trên cùng rồi mới chuyển.
        public static void ForceActivate(IntPtr h) {
            if (IsIconic(h)) ShowWindow(h, 9);
            IntPtr fg = GetForegroundWindow();
            uint dummy;
            uint fgThread = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, out dummy);
            uint me = GetCurrentThreadId();
            if (fgThread != 0 && fgThread != me) {
                AttachThreadInput(me, fgThread, true);
                BringWindowToTop(h); SetForegroundWindow(h);
                AttachThreadInput(me, fgThread, false);
            } else {
                SetForegroundWindow(h);
            }
        }

        public static void Activate(IntPtr h) {
            if (IsIconic(h)) ShowWindow(h, 9 /* SW_RESTORE */);
            SetForegroundWindow(h);
        }
        public static void Maximize(IntPtr h) { ShowWindow(h, 3 /* SW_MAXIMIZE */); }
        public static void Restore(IntPtr h)  { ShowWindow(h, 9 /* SW_RESTORE */); }
        public static void CloseWindow(IntPtr h) { PostMessage(h, 0x0010 /* WM_CLOSE */, IntPtr.Zero, IntPtr.Zero); }
        public static RECT GetRect(IntPtr h) { RECT r; GetWindowRect(h, out r); return r; }
        // Đặt vị trí/kích thước (pixel thật) và trạng thái luôn-trên-cùng, không lấy focus.
        public static void Place(IntPtr h, bool topmost, int x, int y, int w, int hh) {
            SetWindowPos(h, topmost ? (IntPtr)(-1) : (IntPtr)(-2), x, y, w, hh, 0x40 /* SHOWWINDOW */ | 0x10 /* NOACTIVATE */);
        }
        [DllImport("gdi32.dll")]  static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
        [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
        // Chỉ hiển thị một vùng chữ nhật bo góc của cửa sổ (tọa độ trong cửa sổ, pixel thật).
        public static void ClipTo(IntPtr h, int x, int y, int w, int hh, int r) {
            SetWindowRgn(h, CreateRoundRectRgn(x, y, x + w + 1, y + hh + 1, r, r), true);   // Windows giữ region, không xóa
        }
        public static void Unclip(IntPtr h) { SetWindowRgn(h, IntPtr.Zero, true); }
        public static void SetNotTopmost(IntPtr h) { SetWindowPos(h, (IntPtr)(-2), 0, 0, 0, 0, 0x1 | 0x2 | 0x10); }

        // Ảnh xem trước trực tiếp (DWM) của cửa sổ src, vẽ vừa khung trên cửa sổ dest. Tọa độ pixel thật.
        public static IntPtr ShowThumb(IntPtr dest, IntPtr src, int l, int t, int w, int h) {
            IntPtr th;
            if (DwmRegisterThumbnail(dest, src, out th) != 0) return IntPtr.Zero;
            SIZE sz;
            if (DwmQueryThumbnailSourceSize(th, out sz) != 0 || sz.cx < 120 || sz.cy < 80) { DwmUnregisterThumbnail(th); return IntPtr.Zero; }
            double s = Math.Min((double)w / sz.cx, (double)h / sz.cy);
            int tw = (int)(sz.cx * s), tht = (int)(sz.cy * s);
            DWM_THUMBNAIL_PROPERTIES p = new DWM_THUMBNAIL_PROPERTIES();
            p.dwFlags = 0x1 | 0x4 | 0x8 | 0x10;
            p.rcDestination.Left = l + (w - tw) / 2; p.rcDestination.Top = t + (h - tht) / 2;
            p.rcDestination.Right = p.rcDestination.Left + tw; p.rcDestination.Bottom = p.rcDestination.Top + tht;
            p.opacity = 255; p.fVisible = true; p.fSourceClientAreaOnly = false;
            DwmUpdateThumbnailProperties(th, ref p);
            return th;
        }
        public static void HideThumb(IntPtr th) { if (th != IntPtr.Zero) DwmUnregisterThumbnail(th); }

        // Lấy icon của một mục shell (vd. "shell:AppsFolder\<AppID>" hoặc đường dẫn .exe) dạng BGRA 32-bit.
        public static byte[] GetIcon(string parsingName, int size, out int width, out int height) {
            width = 0; height = 0;
            IShellItemImageFactory f;
            Guid iid = typeof(IShellItemImageFactory).GUID;
            if (SHCreateItemFromParsingName(parsingName, IntPtr.Zero, ref iid, out f) != 0 || f == null) return null;
            IntPtr hbm = IntPtr.Zero;
            try {
                SIZE s; s.cx = size; s.cy = size;
                if (f.GetImage(s, 0x4 /* SIIGBF_ICONONLY */, out hbm) != 0 || hbm == IntPtr.Zero) return null;
            } finally { Marshal.ReleaseComObject(f); }
            try {
                BITMAP bm;
                GetObject(hbm, Marshal.SizeOf(typeof(BITMAP)), out bm);
                int w = bm.bmWidth, h = bm.bmHeight;
                BITMAPINFOHEADER bi = new BITMAPINFOHEADER();
                bi.biSize = (uint)Marshal.SizeOf(typeof(BITMAPINFOHEADER));
                bi.biWidth = w; bi.biHeight = -h; bi.biPlanes = 1; bi.biBitCount = 32;
                byte[] bits = new byte[w * h * 4];
                IntPtr dc = GetDC(IntPtr.Zero);
                try { if (GetDIBits(dc, hbm, 0, (uint)h, bits, ref bi, 0) == 0) return null; }
                finally { ReleaseDC(IntPtr.Zero, dc); }
                bool anyAlpha = false;
                for (int i = 3; i < bits.Length; i += 4) { if (bits[i] != 0) { anyAlpha = true; break; } }
                if (!anyAlpha) { for (int i = 3; i < bits.Length; i += 4) bits[i] = 255; }
                width = w; height = h;
                return bits;
            } finally { DeleteObject(hbm); }
        }
    }
}
'@

# Biên dịch C# một lần rồi lưu DLL — các lần mở sau nạp thẳng, nhanh hơn ~1-2 giây.
$sha = [System.Security.Cryptography.SHA1]::Create()
$hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($NativeSource))[0..7] | ForEach-Object { $_.ToString('x2') })
$cacheDir = Join-Path $env:LOCALAPPDATA 'TouchLauncher'
$nativeDll = Join-Path $cacheDir "Native-$hash.dll"
if (-not (Test-Path $nativeDll)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Get-ChildItem $cacheDir -Filter 'Native-*.dll' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    try { Add-Type -TypeDefinition $NativeSource -OutputAssembly $nativeDll -OutputType Library } catch {}
}
if (-not ('TouchLauncher.Native' -as [type])) {
    if (Test-Path $nativeDll) { Add-Type -Path $nativeDll } else { Add-Type -TypeDefinition $NativeSource }
}

# ---------------------------------------------------------------- Cấu hình & trạng thái
$cfgPath   = Join-Path $PSScriptRoot 'launcher.config.json'
$pinsPath  = Join-Path $PSScriptRoot 'pinned.json'
try {
    $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    [System.Windows.MessageBox]::Show("Không đọc được launcher.config.json:`n$($_.Exception.Message)", 'Touch Launcher') | Out-Null
    exit 1
}
$Utf8NoBom = New-Object Text.UTF8Encoding $false

# Cài đặt chỉnh ngay trong app (vd. ghim thanh điều hướng) — ghi đè cấu hình, cập nhật không mất.
$settingsPath = Join-Path $PSScriptRoot 'settings.user.json'
$script:Settings = @{}
if (Test-Path $settingsPath) {
    try { (Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:Settings[$_.Name] = $_.Value } } catch {}
}
function Save-Setting([string]$key, $value) {
    $script:Settings[$key] = $value
    try { [IO.File]::WriteAllText($settingsPath, (ConvertTo-Json -InputObject ([pscustomobject]$script:Settings)), (New-Object Text.UTF8Encoding $false)) } catch {}
}

# App người dùng tự thêm (nút "+ Thêm app"): lưu riêng để cập nhật launcher không làm mất.
$userAppsPath = Join-Path $PSScriptRoot 'apps.user.json'
$IconDir      = Join-Path $PSScriptRoot 'icons'
$userApps = @()
if (Test-Path $userAppsPath) {
    try { $userApps = @((Get-Content $userAppsPath -Raw -Encoding UTF8 | ConvertFrom-Json) | Where-Object { $_.name -and $_.target }) } catch {}
}
foreach ($u in $userApps) { $u | Add-Member -NotePropertyName user -NotePropertyValue $true -Force }
$cfg.tiles = @(@($cfg.tiles) + $userApps)
function Save-UserApps {
    $list = @($cfg.tiles | Where-Object { $_.user } | ForEach-Object {
        [pscustomobject]@{ group = $_.group; folder = $_.folder; profile = $_.profile; name = $_.name; icon = $_.icon; iconImage = $_.iconImage; color = $_.color
                           type = $_.type; target = $_.target; match = $_.match } })
    [IO.File]::WriteAllText($userAppsPath, (ConvertTo-Json -InputObject $list -Depth 4), $Utf8NoBom)
}

$migrated = $false
foreach ($u in @($cfg.tiles | Where-Object { $_.user })) {
    if ([string]$u.target -match '^https://mail\.google\.com/mail/u/([^/?#]+@[^/?#]+)/?$') {
        $u.target = "https://mail.google.com/mail/u/?authuser=$([Uri]::EscapeDataString($Matches[1].ToLower()))"
        $migrated = $true
    }
}
if ($migrated) { Save-UserApps }

# Trang chủ = các app được ghim (theo tên, đúng thứ tự). Chưa có pinned.json thì lấy "home" trong cấu hình.
$script:Pins = $null
if (Test-Path $pinsPath) {
    try {
        $raw = Get-Content $pinsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:Pins = @($raw | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.name) { [string]$_.name } })
    } catch {}
}
if ($null -eq $script:Pins) {
    $script:Pins = if ($cfg.home) { @($cfg.home) } else { @($cfg.tiles | ForEach-Object { $_.name }) }
}
function Save-Pins {
    [IO.File]::WriteAllText($pinsPath, (ConvertTo-Json -InputObject @($script:Pins)), $Utf8NoBom)
}
function Get-Tile([string]$name) { @($cfg.tiles | Where-Object { $_.name -eq $name })[0] }

function Find-Browser([string]$pref) {
    if ($pref -and (Test-Path $pref)) { return $pref }
    $paths = @{
        edge   = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")
        chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
    }
    $order = if ($pref -eq 'edge') { 'edge', 'chrome' } else { 'chrome', 'edge' }
    foreach ($k in $order) { foreach ($p in $paths[$k]) { if (Test-Path $p) { return $p } } }
    return $null
}

$Browser     = Find-Browser $cfg.browser
$BrowserArgs = @($cfg.browserArgs | Where-Object { $_ })
$BrowserName = if ($Browser) { [IO.Path]::GetFileNameWithoutExtension($Browser) } else { '' }
$VolumeStep = if ($cfg.volumeStep) { [int]$cfg.volumeStep } else { 2 }

# Hồ sơ Chrome chính cho mọi app: "browserProfile" trong cấu hình; để trống thì dùng "Default".
# Nếu không chỉ định, Chrome mở bằng hồ sơ dùng gần nhất — đổi liên tục nên app trông như "quên đăng nhập".
$MainProfile = if ($cfg.browserProfile) { [string]$cfg.browserProfile } else { 'Default' }
if ($BrowserName -eq 'chrome' -and -not (Test-Path (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\$MainProfile"))) { $MainProfile = $null }
if ($BrowserName -eq 'msedge' -and -not $cfg.browserProfile) { $MainProfile = $null }

function Start-Browser([string[]]$parts, [string]$profileDir) {
    $a = @()
    if (-not $profileDir) { $profileDir = $MainProfile }
    if ($profileDir) { $a += "--profile-directory=`"$profileDir`"" }
    $a += $BrowserArgs
    $a += $parts
    Start-Process -FilePath $Browser -ArgumentList ($a -join ' ')
}

# ---------------------------------------------------------------- Giao diện chính (kiểu iPad)
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Touch Launcher" WindowStyle="None" ResizeMode="NoResize" WindowState="Maximized"
        Background="#000000" Foreground="#FFFFFF" FontFamily="Segoe UI Variable Display, Segoe UI"
        Stylus.IsPressAndHoldEnabled="False" Stylus.IsFlicksEnabled="False" Stylus.IsTapFeedbackEnabled="False"
        UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="Icon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="26"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
    </Style>

    <!-- Nút trong suốt (icon màn hình chính, Dock, thanh trạng thái) -->
    <Style x:Key="Plain" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
      <Setter Property="RenderTransform"><Setter.Value><ScaleTransform/></Setter.Value></Setter>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="B" Property="Opacity" Value="0.55"/>
                <Setter Property="RenderTransform"><Setter.Value><ScaleTransform ScaleX="0.92" ScaleY="0.92"/></Setter.Value></Setter>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Nút kính mờ -->
    <Style x:Key="Glass" TargetType="Button">
      <Setter Property="MinWidth" Value="64"/>
      <Setter Property="Height" Value="64"/>
      <Setter Property="Margin" Value="6"/>
      <Setter Property="Padding" Value="22,0"/>
      <Setter Property="FontSize" Value="19"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="#33FFFFFF"/>
      <Setter Property="BorderBrush" Value="#22FFFFFF"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
      <Setter Property="RenderTransform"><Setter.Value><ScaleTransform/></Setter.Value></Setter>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="22"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="B" Property="Opacity" Value="0.6"/>
                <Setter Property="RenderTransform"><Setter.Value><ScaleTransform ScaleX="0.96" ScaleY="0.96"/></Setter.Value></Setter>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="GlassRound" TargetType="Button" BasedOn="{StaticResource Glass}">
      <Setter Property="Width" Value="64"/>
      <Setter Property="Padding" Value="0"/>
    </Style>

    <Style x:Key="PowerItem" TargetType="Button" BasedOn="{StaticResource Glass}">
      <Setter Property="Width" Value="180"/>
      <Setter Property="Height" Value="160"/>
      <Setter Property="Padding" Value="0"/>
    </Style>

    <Style x:Key="Row" TargetType="ToggleButton">
      <Setter Property="Height" Value="72"/>
      <Setter Property="Margin" Value="0,5"/>
      <Setter Property="FontSize" Value="20"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="B" Background="#2C2C2E" CornerRadius="18" BorderBrush="#3A3A3C" BorderThickness="2" Padding="22,0">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock x:Name="C" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="28"
                           Text="&#xE739;" Margin="0,0,18,0" VerticalAlignment="Center" Foreground="#8E8E93"/>
                <ContentPresenter VerticalAlignment="Center"/>
              </StackPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="C" Property="Text" Value="&#xE73A;"/>
                <Setter TargetName="C" Property="Foreground" Value="#FF453A"/>
                <Setter TargetName="B" Property="BorderBrush" Value="#7A2420"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <!-- Hình nền -->
    <Grid>
      <Grid.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#1B2A5C" Offset="0"/>
          <GradientStop Color="#2B1650" Offset="0.45"/>
          <GradientStop Color="#120A1E" Offset="0.8"/>
          <GradientStop Color="#050508" Offset="1"/>
        </LinearGradientBrush>
      </Grid.Background>
      <Image x:Name="WallImage" Stretch="UniformToFill"/>
      <Border Background="#2A000000"/>
    </Grid>

    <Grid x:Name="MainArea" Margin="28,6,28,18">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Thanh trạng thái -->
      <DockPanel Grid.Row="0" Height="44">
        <Button x:Name="BtnStatus" DockPanel.Dock="Right" Style="{StaticResource Plain}" Padding="14,0">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="BatteryText" FontSize="17" FontWeight="SemiBold" VerticalAlignment="Center"/>
            <TextBlock x:Name="BatteryIcon" Style="{StaticResource Icon}" FontSize="22" Margin="8,0,0,0" Text="&#xE83F;"/>
            <TextBlock Style="{StaticResource Icon}" FontSize="18" Margin="16,0,0,0" Text="&#xE713;"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnNotify" DockPanel.Dock="Left" Style="{StaticResource Plain}" Padding="14,0" HorizontalAlignment="Left">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="StatusTime" FontSize="17" FontWeight="SemiBold" VerticalAlignment="Center"/>
            <TextBlock Style="{StaticResource Icon}" FontSize="16" Margin="12,0,0,0" Text="&#xEA8F;"/>
          </StackPanel>
        </Button>
      </DockPanel>

      <Grid Grid.Row="1" Margin="0,6,0,10">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Widget: đồng hồ + pin, lịch tháng có âm lịch -->
        <ScrollViewer x:Name="Widgets" Width="356" Margin="8,4,18,0" VerticalScrollBarVisibility="Hidden" PanningMode="VerticalOnly">
          <StackPanel Width="330">
            <Border Background="#26FFFFFF" CornerRadius="30" Padding="24,16" Margin="0,0,0,16" BorderBrush="#1FFFFFFF" BorderThickness="1">
              <StackPanel>
                <TextBlock x:Name="Clock" FontSize="68" FontWeight="Light" Text="--:--"/>
                <TextBlock x:Name="DateText" FontSize="18" Foreground="#CCFFFFFF"/>
                <TextBlock x:Name="LunarText" FontSize="15" Foreground="#99FFFFFF" Margin="0,2,0,10"/>
                <Grid Height="8" Margin="0,4,0,6">
                  <Border Background="#33FFFFFF" CornerRadius="4"/>
                  <Border x:Name="BatteryBar" Background="#30D158" CornerRadius="4" HorizontalAlignment="Left" Width="0"/>
                </Grid>
                <DockPanel>
                  <TextBlock x:Name="BatteryBig" DockPanel.Dock="Left" FontSize="15" FontWeight="SemiBold" Text="--%" Margin="0,0,10,0"/>
                  <TextBlock x:Name="BatteryNote" FontSize="15" Foreground="#AAFFFFFF" TextTrimming="CharacterEllipsis"/>
                </DockPanel>
              </StackPanel>
            </Border>
            <!-- Đang phát (ẩn khi không có nhạc/video) -->
            <Border x:Name="NowCard" Visibility="Collapsed" Background="#26FFFFFF" CornerRadius="30" Padding="16" Margin="0,0,0,16"
                    BorderBrush="#1FFFFFFF" BorderThickness="1">
              <DockPanel>
                <Grid DockPanel.Dock="Left" Width="80" Height="80">
                  <Border CornerRadius="18" Background="#33FFFFFF">
                    <TextBlock Style="{StaticResource Icon}" FontSize="30" Text="&#xE8D6;" Foreground="#99FFFFFF"/>
                  </Border>
                  <Image x:Name="NowArt" Stretch="UniformToFill"/>
                </Grid>
                <StackPanel Margin="14,0,0,0" VerticalAlignment="Center">
                  <TextBlock x:Name="NowSource" FontSize="12" Foreground="#99FFFFFF" TextTrimming="CharacterEllipsis"/>
                  <TextBlock x:Name="NowTitle" FontSize="16" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
                  <TextBlock x:Name="NowArtist" FontSize="13" Foreground="#BBFFFFFF" TextTrimming="CharacterEllipsis"/>
                  <StackPanel Orientation="Horizontal" Margin="-10,2,0,0">
                    <Button x:Name="BtnNowPrev" Style="{StaticResource Plain}" Width="52" Height="44">
                      <TextBlock Style="{StaticResource Icon}" FontSize="20" Text="&#xE892;"/>
                    </Button>
                    <Button x:Name="BtnNowPlay" Style="{StaticResource Plain}" Width="52" Height="44">
                      <TextBlock x:Name="NowPlayIcon" Style="{StaticResource Icon}" FontSize="24" Text="&#xE768;"/>
                    </Button>
                    <Button x:Name="BtnNowNext" Style="{StaticResource Plain}" Width="52" Height="44">
                      <TextBlock Style="{StaticResource Icon}" FontSize="20" Text="&#xE893;"/>
                    </Button>
                  </StackPanel>
                </StackPanel>
              </DockPanel>
            </Border>
            <Border Background="#26FFFFFF" CornerRadius="30" Padding="16,14" Margin="0,0,0,16" BorderBrush="#1FFFFFFF" BorderThickness="1">
              <StackPanel>
                <DockPanel Margin="6,0,0,6">
                  <Button x:Name="BtnCalNext" DockPanel.Dock="Right" Style="{StaticResource Plain}" Width="44" Height="40">
                    <TextBlock Style="{StaticResource Icon}" FontSize="16" Text="&#xE76C;"/>
                  </Button>
                  <Button x:Name="BtnCalPrev" DockPanel.Dock="Right" Style="{StaticResource Plain}" Width="44" Height="40">
                    <TextBlock Style="{StaticResource Icon}" FontSize="16" Text="&#xE76B;"/>
                  </Button>
                  <Button x:Name="BtnCalTitle" Style="{StaticResource Plain}" HorizontalAlignment="Left">
                    <TextBlock x:Name="CalTitle" FontSize="18" FontWeight="SemiBold" Foreground="#FF6961"/>
                  </Button>
                </DockPanel>
                <UniformGrid x:Name="CalHead" Columns="7" Margin="0,0,0,2"/>
                <UniformGrid x:Name="CalGrid" Columns="7"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>

        <!-- Tìm kiếm + icon ứng dụng -->
        <Grid Grid.Column="1">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border Background="#33FFFFFF" CornerRadius="24" Height="52" MaxWidth="640" Margin="12,4,12,10"
                  BorderBrush="#26FFFFFF" BorderThickness="1">
            <DockPanel>
              <TextBlock DockPanel.Dock="Left" Style="{StaticResource Icon}" FontSize="18" Margin="18,0,10,0" Text="&#xE721;"/>
              <Button x:Name="BtnSpotClear" DockPanel.Dock="Right" Style="{StaticResource Plain}" Width="48" Visibility="Collapsed">
                <TextBlock Style="{StaticResource Icon}" FontSize="14" Text="&#xE711;"/>
              </Button>
              <Grid>
                <TextBox x:Name="Spot" FontSize="19" Background="Transparent" BorderThickness="0" Foreground="#FFFFFF"
                         CaretBrush="#FFFFFF" VerticalContentAlignment="Center"/>
                <TextBlock x:Name="SpotHint" Text="Tìm app, hỏi Claude, tìm Google / YouTube…" FontSize="19"
                           Foreground="#99FFFFFF" VerticalAlignment="Center" Margin="3,0,0,0" IsHitTestVisible="False"/>
              </Grid>
            </DockPanel>
          </Border>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Hidden" PanningMode="VerticalOnly" PanningDeceleration="0.003">
            <WrapPanel x:Name="TilePanel" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,4,0,0"/>
          </ScrollViewer>
          <Border x:Name="SpotResults" Grid.Row="1" Visibility="Collapsed" VerticalAlignment="Top" MaxWidth="640" Margin="12,0"
                  Background="#1C1C1E" CornerRadius="24" Padding="10" BorderBrush="#3A3A3C" BorderThickness="1">
            <StackPanel x:Name="SpotList"/>
          </Border>
        </Grid>
      </Grid>

      <!-- Dock -->
      <Border Grid.Row="2" HorizontalAlignment="Center" Background="#40FFFFFF" CornerRadius="36" Padding="12,12"
              BorderBrush="#33FFFFFF" BorderThickness="1">
        <StackPanel Orientation="Horizontal">
          <StackPanel x:Name="DockFav" Orientation="Horizontal"/>
          <Border Width="1" Background="#55FFFFFF" Margin="10,10"/>
          <StackPanel x:Name="DockRecent" Orientation="Horizontal"/>
        </StackPanel>
      </Border>
    </Grid>

    <!-- Thư viện ứng dụng -->
    <Grid x:Name="AppsOverlay" Background="#FA0C0C12" Visibility="Collapsed">
      <DockPanel x:Name="AppsDock" Margin="40,24,40,24">
        <DockPanel DockPanel.Dock="Top" Margin="0,0,0,12">
          <TextBlock DockPanel.Dock="Left" Text="Thư viện ứng dụng" FontSize="36" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,24,0"/>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
            <Button x:Name="BtnAddApp" Style="{StaticResource Glass}" Background="#B30A84FF">
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Icon}" Text="&#xE710;" Margin="0,0,10,0"/>
                <TextBlock Text="Thêm app" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnPinMode" Style="{StaticResource Glass}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Icon}" Text="&#xE718;" Margin="0,0,12,0"/>
                <TextBlock x:Name="PinModeText" Text="Ghim ra trang chủ" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnKbd2" Style="{StaticResource GlassRound}"><TextBlock Style="{StaticResource Icon}" Text="&#xE765;"/></Button>
            <Button x:Name="BtnCloseApps" Style="{StaticResource GlassRound}"><TextBlock Style="{StaticResource Icon}" Text="&#xE711;"/></Button>
          </StackPanel>
          <Grid VerticalAlignment="Center" Margin="0,0,12,0">
            <TextBox x:Name="Search" FontSize="22" Height="60" Padding="18,0" VerticalContentAlignment="Center"
                     Background="#2C2C2E" Foreground="#FFFFFF" CaretBrush="#FFFFFF" BorderBrush="#3A3A3C" BorderThickness="2"/>
            <TextBlock x:Name="SearchHint" Text="Tìm ứng dụng…" FontSize="22" Foreground="#8E8E93"
                       Margin="22,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
          </Grid>
        </DockPanel>
        <TextBlock x:Name="AppsHint" DockPanel.Dock="Top" FontSize="18" Foreground="#8E8E93" Margin="4,0,0,10"
                   Text="Đang tải danh sách ứng dụng…"/>
        <ScrollViewer VerticalScrollBarVisibility="Hidden" PanningMode="VerticalOnly" PanningDeceleration="0.003">
          <StackPanel x:Name="AppGrid" MaxWidth="1400"/>
        </ScrollViewer>
      </DockPanel>
    </Grid>

    <!-- Đa nhiệm -->
    <Grid x:Name="SwitchOverlay" Background="#FA0C0C12" Visibility="Collapsed">
      <DockPanel x:Name="SwitchDock" Margin="40,24,40,24">
        <DockPanel DockPanel.Dock="Top" Margin="0,0,0,16" LastChildFill="False">
          <TextBlock DockPanel.Dock="Left" Text="Đa nhiệm" FontSize="36" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
            <Button x:Name="BtnSplit" Style="{StaticResource Glass}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Icon}" Text="&#xE90C;" Margin="0,0,12,0"/>
                <TextBlock Text="Chia đôi 2 app gần nhất" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnCloseAllWin" Style="{StaticResource Glass}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Style="{StaticResource Icon}" Text="&#xE74D;" Margin="0,0,12,0"/>
                <TextBlock Text="Đóng tất cả" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnSwitchHome" Style="{StaticResource GlassRound}"><TextBlock Style="{StaticResource Icon}" Text="&#xE80F;"/></Button>
          </StackPanel>
        </DockPanel>
        <Grid x:Name="SwitchArea">
          <TextBlock x:Name="SwitchEmpty" Text="Không có ứng dụng nào đang mở." FontSize="24" Foreground="#8E8E93"
                     HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
          <WrapPanel x:Name="SwitchGrid" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Grid>
      </DockPanel>
    </Grid>

    <!-- Dọn tiến trình -->
    <Grid x:Name="Overlay" Background="#CC000000" Visibility="Collapsed">
      <Border Background="#F21C1C1E" CornerRadius="30" Padding="30" MaxWidth="760" MaxHeight="880" Margin="24"
              BorderBrush="#3A3A3C" BorderThickness="1" VerticalAlignment="Center">
        <DockPanel>
          <StackPanel DockPanel.Dock="Top" Margin="0,0,0,12">
            <TextBlock Text="Dọn tiến trình thừa" FontSize="30" FontWeight="SemiBold"/>
            <TextBlock Text="Chạm để chọn / bỏ chọn. Chỉ đóng ứng dụng nền của bạn, không đụng tới Windows."
                       FontSize="16" Foreground="#8E8E93" TextWrapping="Wrap" Margin="0,6,0,0"/>
          </StackPanel>
          <WrapPanel DockPanel.Dock="Bottom" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="BtnCancel" Style="{StaticResource Glass}" Content="Hủy"/>
            <Button x:Name="BtnKill" Style="{StaticResource Glass}" Background="#B3FF453A" Content="Đóng mục đã chọn"/>
          </WrapPanel>
          <ScrollViewer VerticalScrollBarVisibility="Auto" PanningMode="VerticalOnly">
            <StackPanel x:Name="KillList"/>
          </ScrollViewer>
        </DockPanel>
      </Border>
    </Grid>

    <!-- Nguồn -->
    <Grid x:Name="PowerOverlay" Background="#CC000000" Visibility="Collapsed">
      <Border Background="#F21C1C1E" CornerRadius="30" Padding="26" Margin="24"
              BorderBrush="#3A3A3C" BorderThickness="1" HorizontalAlignment="Center" VerticalAlignment="Center">
        <StackPanel>
          <TextBlock x:Name="PowerTitle" Text="Nguồn" FontSize="30" FontWeight="SemiBold" Margin="10,0,0,12"/>
          <WrapPanel x:Name="PowerChoices" HorizontalAlignment="Center">
            <Button x:Name="BtnShutdown" Style="{StaticResource PowerItem}" Background="#59FF453A">
              <StackPanel>
                <TextBlock Style="{StaticResource Icon}" FontSize="50" Text="&#xE7E8;" Foreground="#FF6961"/>
                <TextBlock Text="Tắt máy" FontSize="21" Margin="0,16,0,0" HorizontalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnRestart" Style="{StaticResource PowerItem}">
              <StackPanel>
                <TextBlock Style="{StaticResource Icon}" FontSize="50" Text="&#xE777;" Foreground="#FFD60A"/>
                <TextBlock Text="Khởi động lại" FontSize="21" Margin="0,16,0,0" HorizontalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnSleep" Style="{StaticResource PowerItem}">
              <StackPanel>
                <TextBlock Style="{StaticResource Icon}" FontSize="50" Text="&#xE708;" Foreground="#64D2FF"/>
                <TextBlock Text="Ngủ" FontSize="21" Margin="0,16,0,0" HorizontalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnExit" Style="{StaticResource PowerItem}">
              <StackPanel>
                <TextBlock Style="{StaticResource Icon}" FontSize="50" Text="&#xE711;" Foreground="#AEAEB2"/>
                <TextBlock Text="Thoát launcher" FontSize="21" Margin="0,16,0,0" HorizontalAlignment="Center"/>
              </StackPanel>
            </Button>
          </WrapPanel>
          <WrapPanel x:Name="PowerConfirm" HorizontalAlignment="Center" Visibility="Collapsed">
            <Button x:Name="BtnPowerNo"  Style="{StaticResource PowerItem}" Content="Không"/>
            <Button x:Name="BtnPowerYes" Style="{StaticResource PowerItem}" Background="#B3FF453A" Content="Đồng ý"/>
          </WrapPanel>
          <Button x:Name="BtnPowerCancel" Style="{StaticResource Glass}" Content="Hủy" HorizontalAlignment="Center" Margin="0,12,0,0"/>
        </StackPanel>
      </Border>
    </Grid>

    <!-- Thư mục -->
    <Grid x:Name="FolderOverlay" Background="#99000000" Visibility="Collapsed">
      <Border Background="#E62C2C2E" CornerRadius="40" Padding="28,22,28,18" MaxWidth="640" Margin="24"
              HorizontalAlignment="Center" VerticalAlignment="Center" BorderBrush="#33FFFFFF" BorderThickness="1">
        <StackPanel>
          <TextBlock x:Name="FolderTitle" FontSize="26" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,0,0,10"/>
          <WrapPanel x:Name="FolderGrid" HorizontalAlignment="Center" MaxWidth="580"/>
        </StackPanel>
      </Border>
    </Grid>

    <!-- Thêm app web -->
    <Grid x:Name="AddOverlay" Background="#CC000000" Visibility="Collapsed">
      <Border Background="#F21C1C1E" CornerRadius="30" Padding="30" MaxWidth="680" Margin="24"
              BorderBrush="#3A3A3C" BorderThickness="1" VerticalAlignment="Center">
        <StackPanel>
          <TextBlock Text="Thêm app web" FontSize="30" FontWeight="SemiBold"/>
          <TextBlock Text="Dán địa chỉ trang web — hoặc gõ email Gmail để có một icon riêng cho tài khoản đó." FontSize="16" Foreground="#8E8E93"
                     TextWrapping="Wrap" Margin="0,6,0,18"/>
          <TextBlock Text="Địa chỉ" FontSize="15" Foreground="#AEAEB2" Margin="4,0,0,6"/>
          <TextBox x:Name="AddUrl" FontSize="20" Height="56" Padding="16,0" VerticalContentAlignment="Center"
                   Background="#2C2C2E" Foreground="#FFFFFF" CaretBrush="#FFFFFF" BorderBrush="#3A3A3C" BorderThickness="2"/>
          <WrapPanel x:Name="AddSuggest" Margin="0,8,0,0"/>
          <TextBlock Text="Tên app" FontSize="15" Foreground="#AEAEB2" Margin="4,14,0,6"/>
          <TextBox x:Name="AddName" FontSize="20" Height="56" Padding="16,0" VerticalContentAlignment="Center"
                   Background="#2C2C2E" Foreground="#FFFFFF" CaretBrush="#FFFFFF" BorderBrush="#3A3A3C" BorderThickness="2"/>
          <TextBlock Text="Nhóm" FontSize="15" Foreground="#AEAEB2" Margin="4,14,0,6"/>
          <WrapPanel x:Name="AddGroups"/>
          <DockPanel Margin="0,16,0,0">
            <Border x:Name="AddPreview" DockPanel.Dock="Left" Width="72" Height="72" CornerRadius="17" Background="#3A3A3C">
              <Grid>
                <TextBlock x:Name="AddLetter" FontSize="34" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                <Image x:Name="AddIcon" Width="50" Height="50"/>
              </Grid>
            </Border>
            <TextBlock x:Name="AddStatus" FontSize="16" Foreground="#AEAEB2" TextWrapping="Wrap" VerticalAlignment="Center" Margin="16,0,0,0"
                       Text="Ví dụ: chat.zalo.me hoặc ten@gmail.com"/>
          </DockPanel>
          <WrapPanel HorizontalAlignment="Right" Margin="0,18,0,0">
            <Button x:Name="BtnAddCancel" Style="{StaticResource Glass}" Content="Hủy"/>
            <Button x:Name="BtnAddSave" Style="{StaticResource Glass}" Background="#0A84FF" Content="Thêm vào Thư viện"/>
          </WrapPanel>
        </StackPanel>
      </Border>
    </Grid>

    <!-- Đồng hồ đầu giường / khung ảnh -->
    <Grid x:Name="NightOverlay" Background="#000000" Visibility="Collapsed">
      <Image x:Name="NightPhotoA" Stretch="UniformToFill" Opacity="0"/>
      <Image x:Name="NightPhotoB" Stretch="UniformToFill" Opacity="0"/>
      <Border>
        <Border.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#33000000" Offset="0"/>
            <GradientStop Color="#99000000" Offset="0.6"/>
            <GradientStop Color="#DD000000" Offset="1"/>
          </LinearGradientBrush>
        </Border.Background>
      </Border>
      <StackPanel x:Name="NightClock" HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="80,0,0,70">
        <TextBlock x:Name="NightTime" FontSize="150" FontWeight="Light" Foreground="#E6FFFFFF"/>
        <TextBlock x:Name="NightDate" FontSize="30" Foreground="#CCFFFFFF" Margin="6,-10,0,0"/>
        <TextBlock x:Name="NightLunar" FontSize="22" Foreground="#99FFFFFF" Margin="6,4,0,0"/>
        <TextBlock x:Name="NightInfo" FontSize="18" Foreground="#80FFFFFF" Margin="6,14,0,0"/>
      </StackPanel>
    </Grid>

    <!-- Có bản mới -->
    <Border x:Name="UpdateBar" Visibility="Collapsed" Background="#F21C1C1E" CornerRadius="22" Padding="20,10"
            HorizontalAlignment="Center" VerticalAlignment="Top" Margin="24,50,24,0" BorderBrush="#0A84FF" BorderThickness="1">
      <StackPanel Orientation="Horizontal">
        <TextBlock Style="{StaticResource Icon}" FontSize="22" Text="&#xE895;" Foreground="#64D2FF" Margin="0,0,14,0"/>
        <TextBlock x:Name="UpdateText" FontSize="17" VerticalAlignment="Center" Margin="0,0,14,0"/>
        <Button x:Name="BtnUpdateNow" Style="{StaticResource Glass}" Height="48" Background="#0A84FF" Content="Cập nhật"/>
        <Button x:Name="BtnUpdateLater" Style="{StaticResource Glass}" Height="48" Content="Để sau"/>
      </StackPanel>
    </Border>

    <!-- Thông báo (banner trên cùng) -->
    <Border x:Name="Toast" Visibility="Collapsed" Background="#F22C2C2E" CornerRadius="22" Padding="26,14"
            HorizontalAlignment="Center" VerticalAlignment="Top" Margin="24,54,24,0" IsHitTestVisible="False"
            BorderBrush="#3A3A3C" BorderThickness="1">
      <TextBlock x:Name="ToastText" FontSize="18" TextWrapping="Wrap"/>
    </Border>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xaml)
# Icon riêng của launcher (assets\TouchLauncher.ico) — chạy bằng PowerShell thì thanh tác vụ vẫn hiện đúng icon.
$AppIconPath = Join-Path $PSScriptRoot 'assets\TouchLauncher.ico'
$script:AppIcon = $null
if (Test-Path $AppIconPath) {
    try { $script:AppIcon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$AppIconPath); $win.Icon = $script:AppIcon } catch {}
}
$ui = @{}
foreach ($n in 'WallImage','MainArea','BtnStatus','BatteryText','BatteryIcon','StatusTime',
               'Widgets','Clock','DateText','BatteryBig','BatteryBar','BatteryNote',
               'TilePanel','DockFav','DockRecent','BtnNotify','LunarText',
               'NowCard','NowArt','NowSource','NowTitle','NowArtist','BtnNowPrev','BtnNowPlay','BtnNowNext','NowPlayIcon',
               'BtnAddApp','BtnSplit','AddOverlay','AddUrl','AddName','AddGroups','AddPreview','AddLetter','AddIcon','AddStatus','BtnAddCancel','BtnAddSave',
               'NightOverlay','NightPhotoA','NightPhotoB','NightClock','NightTime','NightDate','NightLunar','NightInfo',
               'UpdateBar','UpdateText','BtnUpdateNow','BtnUpdateLater','FolderOverlay','FolderTitle','FolderGrid','AddSuggest',
               'BtnCalPrev','BtnCalNext','BtnCalTitle','CalTitle','CalHead','CalGrid',
               'Spot','SpotHint','BtnSpotClear','SpotResults','SpotList',
               'AppsOverlay','AppsDock','BtnPinMode','PinModeText','BtnKbd2','BtnCloseApps','Search','SearchHint','AppsHint','AppGrid',
               'SwitchOverlay','SwitchDock','SwitchArea','SwitchEmpty','SwitchGrid','BtnCloseAllWin','BtnSwitchHome',
               'Overlay','KillList','BtnCancel','BtnKill',
               'PowerOverlay','PowerTitle','PowerChoices','PowerConfirm','BtnShutdown','BtnRestart','BtnSleep','BtnExit',
               'BtnPowerNo','BtnPowerYes','BtnPowerCancel',
               'Toast','ToastText') {
    $ui[$n] = $win.FindName($n)
}
$Brushes   = New-Object System.Windows.Media.BrushConverter
$IconFont  = New-Object System.Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')
$TextFont  = New-Object System.Windows.Media.FontFamily('Segoe UI')
$Vi = [Globalization.CultureInfo]::GetCultureInfo('vi-VN')
$BadgeColors = '#0A84FF','#FF9F0A','#30D158','#BF5AF2','#FF375F','#64D2FF','#FFD60A','#5E5CE6'
$LightTile = $Brushes.ConvertFromString('#ECECF1')
function ConvertTo-Brush([string]$hex) { $Brushes.ConvertFromString($hex) }

if ($cfg.wallpaper -and (Test-Path $cfg.wallpaper)) {
    try {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.UriSource = [Uri](Resolve-Path $cfg.wallpaper).Path
        $bi.DecodePixelWidth = 1920; $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
        $ui.WallImage.Source = $bi
    } catch {}
}

# ---------------------------------------------------------------- Thông báo
$ToastTimer = New-Object System.Windows.Threading.DispatcherTimer
$ToastTimer.Interval = [TimeSpan]::FromSeconds(2.8)
$ToastTimer.Add_Tick({ $ui.Toast.Visibility = 'Collapsed'; $ToastTimer.Stop() })
function Show-Toast([string]$msg) {
    $ui.ToastText.Text = $msg
    $ui.Toast.Visibility = 'Visible'
    $ToastTimer.Stop(); $ToastTimer.Start()
}

# ---------------------------------------------------------------- Đồng hồ & pin
function Get-Battery {
    $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
    if ($ps.BatteryChargeStatus -band [System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery) { return $null }
    [pscustomobject]@{
        Pct      = [int]([math]::Round($ps.BatteryLifePercent * 100))
        Charging = $ps.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online
        Minutes  = if ($ps.BatteryLifeRemaining -gt 0) { [int]($ps.BatteryLifeRemaining / 60) } else { $null }
    }
}

function Update-Status {
    $now = Get-Date
    Update-CalendarIfNeeded
    Update-Badges
    $ui.Clock.Text = $now.ToString('HH:mm')
    $ui.DateText.Text = $Vi.TextInfo.ToTitleCase($now.ToString('dddd, dd MMMM', $Vi))
    $ui.StatusTime.Text = $now.ToString('HH:mm') + '   ' + $Vi.TextInfo.ToTitleCase($now.ToString('ddd dd/MM', $Vi))

    $b = Get-Battery
    if (-not $b) {
        $ui.BatteryText.Text = ''; $ui.BatteryBig.Text = 'Cắm điện'; $ui.BatteryNote.Text = 'Máy không có pin'
        return
    }
    $low = (-not $b.Charging) -and $b.Pct -le 20
    $ui.BatteryText.Text = "$($b.Pct)%"
    $ui.BatteryIcon.Text = if ($b.Charging) { [string][char]0xEA93 } else { [string][char]0xE83F }
    $ui.BatteryBig.Text = "$($b.Pct)%"
    $ui.BatteryBar.Width = 282 * $b.Pct / 100
    $ui.BatteryBar.Background = ConvertTo-Brush $(if ($low) { '#FF453A' } elseif ($script:SaverOn) { '#FFD60A' } else { '#30D158' })
    $ui.BatteryNote.Text = if ($b.Charging) { 'Đang sạc' }
                           elseif ($b.Minutes) { 'Còn khoảng {0} giờ {1} phút' -f [int][math]::Floor($b.Minutes / 60), ($b.Minutes % 60) }
                           else { 'Đang dùng pin' }
}

# Chỉ cập nhật khi launcher đang hiển thị — tránh đánh thức CPU khi đang xem YouTube.
$StatusTimer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background)
$StatusTimer.Interval = [TimeSpan]::FromSeconds(20)
$StatusTimer.Add_Tick({ Update-Status })

# ---------------------------------------------------------------- Icon
function Get-AppIcon([string]$appId, [int]$size = 96) { Get-ShellIcon "shell:AppsFolder\$appId" $size }
function Get-ShellIcon([string]$parsingName, [int]$size = 96) {
    try {
        $w = 0; $h = 0
        $bits = [TouchLauncher.Native]::GetIcon($parsingName, $size, [ref]$w, [ref]$h)
        if ($null -eq $bits) { return $null }
        $bmp = [System.Windows.Media.Imaging.BitmapSource]::Create($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32, $null, $bits, $w * 4)
        $bmp.Freeze()
        return $bmp
    } catch { return $null }
}

function New-IconImage($src, [int]$px) {
    $img = New-Object System.Windows.Controls.Image
    $img.Source = $src; $img.Width = $px; $img.Height = $px
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality')
    return $img
}

function Get-BadgeColor([string]$name) { $BadgeColors[[math]::Abs($name.GetHashCode()) % $BadgeColors.Count] }

function New-Gradient([string]$hex) {
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
    $l = [System.Windows.Media.Color]::FromRgb([byte][math]::Min(255, $c.R + 45), [byte][math]::Min(255, $c.G + 45), [byte][math]::Min(255, $c.B + 45))
    $g = New-Object System.Windows.Media.LinearGradientBrush($l, $c, 90)
    $g.Freeze()
    return $g
}

function New-Glyph([string]$icon, [int]$px, [string]$fg, [bool]$allowGlyph) {
    $tb = New-Object System.Windows.Controls.TextBlock
    if ($allowGlyph -and $icon -match '^[0-9A-Fa-f]{4}$') {
        $tb.FontFamily = $IconFont; $tb.Text = [string][char][Convert]::ToInt32($icon, 16); $tb.FontSize = $px
    } else {
        $tb.FontFamily = $TextFont; $tb.FontWeight = 'Bold'; $tb.Text = $icon; $tb.FontSize = [int]($px * 1.05)
    }
    $tb.Foreground = ConvertTo-Brush $fg
    $tb.HorizontalAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
    return $tb
}

function Get-Initial([string]$name) { if ($name) { $name.Substring(0, 1).ToUpper() } else { '?' } }

# Icon bo góc kiểu iPad. $t.type: app/web/uri/exe (glyph), shellapp (icon thật), window (icon cửa sổ), letter (chữ cái).
# Ảnh icon từ tệp (favicon của app tự thêm). Đường dẫn tương đối tính từ thư mục launcher.
$script:ImgCache = @{}
function Get-FileImage([string]$path) {
    $p = if ([IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $PSScriptRoot $path }
    if ($script:ImgCache.ContainsKey($p)) { return $script:ImgCache[$p] }
    $img = $null
    if (Test-Path $p) {
        try {
            $img = New-Object System.Windows.Media.Imaging.BitmapImage
            $img.BeginInit(); $img.UriSource = [Uri]$p; $img.DecodePixelWidth = 128
            $img.CacheOption = 'OnLoad'; $img.CreateOptions = 'IgnoreImageCache'; $img.EndInit(); $img.Freeze()
        } catch { $img = $null }
    }
    $script:ImgCache[$p] = $img
    return $img
}

function New-Squircle($t, [int]$px) {
    $bd = New-Object System.Windows.Controls.Border
    $bd.Width = $px; $bd.Height = $px
    $bd.CornerRadius = New-Object System.Windows.CornerRadius ([math]::Round($px * 0.23))
    $glyphPx = [int]($px * 0.5)
    $src = $null
    if ($t.type -eq 'folder') {
        $bd.Background = ConvertTo-Brush '#4DFFFFFF'
        $grid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $grid.Columns = 2; $grid.Rows = 2; $grid.Margin = [int]($px * 0.12)
        foreach ($c in @($t.children | Select-Object -First 4)) {
            $mini = New-Squircle $c ([int]($px * 0.33)); $mini.Margin = 2
            [void]$grid.Children.Add($mini)
        }
        $bd.Child = $grid
        return $bd
    }
    if ($t.iconImage) { $src = Get-FileImage ([string]$t.iconImage) }
    switch ($t.type) {
        'shellapp' { $src = Get-AppIcon $t.target }
        'window'   { $src = $t.iconSource }
    }
    if ($src) {
        $bd.Background = $LightTile
        $bd.Child = New-IconImage $src ([int]($px * 0.7))
    } elseif ($t.type -in 'shellapp', 'window', 'letter') {
        $bd.Background = New-Gradient (Get-BadgeColor $t.name)
        $bd.Child = New-Glyph (Get-Initial $t.name) $glyphPx '#FFFFFF' $false
    } else {
        $bd.Background = New-Gradient $(if ($t.color) { $t.color } else { '#3A3A3C' })
        $bd.Child = New-Glyph ([string]$t.icon) $glyphPx $(if ($t.fg) { $t.fg } else { '#FFFFFF' }) $true
    }
    return $bd
}

# ---------------------------------------------------------------- Cửa sổ của từng app & số chưa đọc
# Mỗi cửa sổ chỉ thuộc về một app. App có "match" cụ thể hơn (app tự thêm, vd. Gmail theo tài khoản)
# được xét trước, nên icon Gmail chung chỉ nhận cửa sổ Gmail còn lại.
$script:ProcNames = @{}
function Get-TileWindowMap {
    $map = @{}
    if (-not $BrowserName) { return $map }
    $wins = @([TouchLauncher.Native]::GetAppWindows($PID) | Where-Object { $_.Title -notmatch '(Edge|Chrome)$' })
    $used = @{}
    $tiles = @($cfg.tiles | Where-Object { $_.match }) | Sort-Object @{ Expression = { if ($_.user) { 0 } else { 1 } } }, @{ Expression = { -([string]$_.match).Length } }
    foreach ($t in $tiles) {
        foreach ($w in $wins) {
            $key = $w.Handle.ToInt64()
            if ($used.ContainsKey($key) -or $w.Title -notmatch $t.match) { continue }
            if (-not $script:ProcNames.ContainsKey($w.Pid)) {
                $script:ProcNames[$w.Pid] = (Get-Process -Id $w.Pid -ErrorAction SilentlyContinue).ProcessName
            }
            if ($script:ProcNames[$w.Pid] -ne $BrowserName) { continue }
            $map[$t.name] = $w; $used[$key] = $true
            if ($HomeOnClose) { [TouchLauncher.WinWatch]::Track($w.Handle) }   # đã biết là cửa sổ trình duyệt
            break
        }
    }
    return $map
}

# Số trong ngoặc ở tiêu đề: "(3) Facebook", "Hộp thư đến (132) - ai@gmail.com - Gmail".
function Get-TitleCount([string]$title) {
    $m = [regex]::Match($title, '\((\d{1,4})\+?\)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

# Chấm đỏ trên icon: tên app -> danh sách chấm (một app có thể hiện ở trang chủ, Dock và trong thư mục).
$script:BadgeEls = @{}
$script:FolderKids = @{}
function New-Badge([string]$name) {
    $bd = New-Object System.Windows.Controls.Border
    $bd.Background = ConvertTo-Brush '#FF3B30'
    $bd.CornerRadius = 13; $bd.MinWidth = 26; $bd.Height = 26; $bd.Padding = '7,0'
    $bd.HorizontalAlignment = 'Right'; $bd.VerticalAlignment = 'Top'; $bd.Margin = '0,-9,-9,0'
    $bd.BorderBrush = ConvertTo-Brush '#40000000'; $bd.BorderThickness = 1
    $bd.Visibility = 'Collapsed'; $bd.IsHitTestVisible = $false
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.FontSize = 13; $tb.FontWeight = 'Bold'; $tb.Foreground = [System.Windows.Media.Brushes]::White
    $tb.HorizontalAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
    $bd.Child = $tb
    if (-not $script:BadgeEls.ContainsKey($name)) { $script:BadgeEls[$name] = New-Object System.Collections.ArrayList }
    [void]$script:BadgeEls[$name].Add($bd)
    return $bd
}

function Update-Badges {
    if ($script:BadgeEls.Count -eq 0) { return }
    $map = Get-TileWindowMap
    $counts = @{}
    foreach ($k in $map.Keys) { $counts[$k] = Get-TitleCount $map[$k].Title }
    foreach ($f in $script:FolderKids.Keys) {
        $sum = 0; foreach ($n in $script:FolderKids[$f]) { if ($counts.ContainsKey($n)) { $sum += $counts[$n] } }
        $counts["folder:$f"] = $sum
    }
    foreach ($name in $script:BadgeEls.Keys) {
        $c = if ($counts.ContainsKey($name)) { $counts[$name] } else { 0 }
        foreach ($bd in $script:BadgeEls[$name]) {
            if ($c -gt 0) { $bd.Child.Text = $(if ($c -gt 999) { '999+' } else { "$c" }); $bd.Visibility = 'Visible' }
            else { $bd.Visibility = 'Collapsed' }
        }
    }
}

# ---------------------------------------------------------------- Thư mục trên trang chủ (như iPhone)
function Show-Folder($f) {
    $ui.FolderTitle.Text = $f.name
    $ui.FolderGrid.Children.Clear()
    foreach ($t in $f.children) { [void]$ui.FolderGrid.Children.Add((New-HomeIcon $t 92 $true)) }
    $ui.FolderOverlay.Visibility = 'Visible'
    Update-Badges
}
function Hide-Folder {
    if ($ui.FolderOverlay.Visibility -ne 'Visible') { return }
    $ui.FolderOverlay.Visibility = 'Collapsed'
    # Bỏ các chấm đỏ của icon trong thư mục vừa đóng.
    foreach ($b in $ui.FolderGrid.Children) {
        $n = $b.Tag.name
        if ($script:BadgeEls.ContainsKey($n)) {
            foreach ($bd in @($script:BadgeEls[$n])) { if ($b.Content.Children[0].Children -contains $bd) { [void]$script:BadgeEls[$n].Remove($bd) } }
        }
    }
    $ui.FolderGrid.Children.Clear()
}
# Chạm ra ngoài khung thư mục thì đóng.
$ui.FolderOverlay.Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -eq $ui.FolderOverlay) { Hide-Folder } })

# ---------------------------------------------------------------- Mở ứng dụng (toàn màn hình, không mở trùng)
# Cửa sổ app web đã mở sẵn (khớp "match" trong cấu hình) — chạm lại thì chuyển tới, không mở thêm.
function Find-TileWindow($t) {
    if (-not $t.match -or -not $BrowserName) { return $null }
    return (Get-TileWindowMap)[$t.name]
}

# Chờ cửa sổ mới xuất hiện rồi phóng to toàn màn hình như app iPad.
$script:LaunchWatch = $null
$LaunchTimer = New-Object System.Windows.Threading.DispatcherTimer
$LaunchTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$LaunchTimer.Add_Tick({
    $lw = $script:LaunchWatch
    if (-not $lw -or (Get-Date) -gt $lw.Until) { $LaunchTimer.Stop(); $script:LaunchWatch = $null; return }
    foreach ($w in [TouchLauncher.Native]::GetAppWindows($PID)) {
        if (-not $lw.Before.Contains($w.Handle.ToInt64())) {
            [TouchLauncher.Native]::Maximize($w.Handle)
            Add-AppWindowWatch $w.Handle
            Watch-PageError $w.Handle
            $LaunchTimer.Stop(); $script:LaunchWatch = $null
            return
        }
    }
})
# Trang web vừa mở mà báo lỗi tạm thời (Gmail hay gặp) -> tự tải lại trang.
$script:ErrWatch = @{}
$ErrRetryTimer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background)
$ErrRetryTimer.Interval = [TimeSpan]::FromSeconds(1.5)
$ErrRetryTimer.Add_Tick({
    if ($script:ErrWatch.Count -eq 0) { $ErrRetryTimer.Stop(); return }
    $titles = @{}
    foreach ($w in [TouchLauncher.Native]::GetAppWindows($PID)) { $titles[$w.Handle.ToInt64()] = $w.Title }
    foreach ($k in @($script:ErrWatch.Keys)) {
        $e = $script:ErrWatch[$k]
        if (-not $titles.ContainsKey($k) -or (Get-Date) -gt $e.Until -or $e.Tries -ge 2) { $script:ErrWatch.Remove($k); continue }
        if ($titles[$k] -match 'Temporary Error|Lỗi tạm thời|^Error \d{3}') {
            $e.Tries++
            [TouchLauncher.Native]::Activate([IntPtr]$k)
            Start-Sleep -Milliseconds 150
            [TouchLauncher.Native]::KeyPlain(0x74)   # F5 = tải lại trang
        }
    }
})
function Watch-PageError([IntPtr]$h) {
    $script:ErrWatch[$h.ToInt64()] = @{ Until = (Get-Date).AddSeconds(20); Tries = 0 }
    $ErrRetryTimer.Start()
}

function Watch-NewWindow {
    if ($cfg.appWindowMode -eq 'normal') { return }
    $set = New-Object 'System.Collections.Generic.HashSet[long]'
    foreach ($w in [TouchLauncher.Native]::GetAppWindows($PID)) { [void]$set.Add($w.Handle.ToInt64()) }
    $script:LaunchWatch = @{ Before = $set; Until = (Get-Date).AddSeconds(8) }
    $LaunchTimer.Start()
}

function Invoke-Tile($t) {
    if ($t.type -eq 'drawer') { Show-Apps; return }
    if ($t.type -eq 'folder') { Show-Folder $t; return }
    if ($t.type -eq 'window') { Switch-ToWindow $t.handle; return }
    $existing = Find-TileWindow $t
    if ($existing) {
        Switch-ToWindow $existing.Handle
        # Cửa sổ đang mở mà còn trang lỗi tạm thời (vd. Gmail) -> tải lại luôn.
        if ($existing.Title -match 'Temporary Error|Lỗi tạm thời|^Error \d{3}') {
            Start-Sleep -Milliseconds 150
            [TouchLauncher.Native]::KeyPlain(0x74)
        }
        return
    }

    $target = [Environment]::ExpandEnvironmentVariables([string]$t.target)
    Watch-NewWindow
    switch ($t.type) {
        'app' {
            if ($Browser) { Start-Browser @("--app=`"$target`"") ([string]$t.profile) } else { Start-Process $target }
        }
        'web' {
            if ($Browser) { Start-Browser @("`"$target`"") ([string]$t.profile) } else { Start-Process $target }
        }
        'shellapp' { Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$target" }
        default {
            if ($t.args) { Start-Process -FilePath $target -ArgumentList $t.args }
            else { Start-Process $target }
        }
    }
    Hide-Overlays
    if ($cfg.minimizeOnLaunch -ne $false) { $win.WindowState = 'Minimized' }
}

# ---------------------------------------------------------------- Màn hình chính & Dock
function New-HomeIcon($t, [int]$px, [bool]$label) {
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $win.FindResource('Plain')
    $sp = New-Object System.Windows.Controls.StackPanel
    $iconBox = New-Object System.Windows.Controls.Grid
    $iconBox.HorizontalAlignment = 'Center'
    [void]$iconBox.Children.Add((New-Squircle $t $px))
    if ($t.name -and $t.type -notin 'drawer', 'window') {
        $key = if ($t.type -eq 'folder') { "folder:$($t.name)" } else { [string]$t.name }
        [void]$iconBox.Children.Add((New-Badge $key))
    }
    [void]$sp.Children.Add($iconBox)
    if ($label) {
        $b.Width = 132; $b.Margin = '6,8'
        $lb = New-Object System.Windows.Controls.TextBlock
        $lb.Text = $t.name; $lb.FontSize = 15; $lb.Margin = '0,8,0,0'; $lb.MaxWidth = 124
        $lb.TextTrimming = 'CharacterEllipsis'; $lb.HorizontalAlignment = 'Center'
        [void]$sp.Children.Add($lb)
    } else {
        $b.Margin = '7,0'
    }
    $b.Content = $sp
    $b.Tag = $t
    $b.Add_Click({
        if (Test-HoldHandled) { return }
        try { Invoke-Tile $this.Tag }
        catch { Show-Toast "Không mở được $($this.Tag.name): $($_.Exception.Message)" }
    })
    return $b
}

# Nhấn giữ (0,6 giây) như iPad: trong Thư viện -> ghim / bỏ ghim; trên trang chủ -> bỏ khỏi trang chủ.
$script:HoldTarget = $null
$script:HoldStart  = $null
$script:HoldFiredAt = $null
$HoldTimer = New-Object System.Windows.Threading.DispatcherTimer
$HoldTimer.Interval = [TimeSpan]::FromMilliseconds(600)
$HoldTimer.Add_Tick({
    $HoldTimer.Stop()
    $b = $script:HoldTarget
    if (-not $b) { return }
    $script:HoldFiredAt = Get-Date
    $t = $b.Tag
    if ($t.PSObject.Properties['Pin']) { Switch-Pin $t } else { Remove-FromHome $t.name }
})
function Start-Hold($b, [System.Windows.Point]$p) {
    $script:HoldTarget = $b; $script:HoldStart = $p
    $HoldTimer.Stop(); $HoldTimer.Start()
}
function Move-Hold([System.Windows.Point]$p) {
    if ($HoldTimer.IsEnabled -and $script:HoldStart -and
        ([math]::Abs($p.X - $script:HoldStart.X) + [math]::Abs($p.Y - $script:HoldStart.Y)) -gt 15) { $HoldTimer.Stop() }
}
# Nghe thẳng sự kiện chạm: trong vùng cuộn, WPF chỉ giả lập "nhấn chuột" khi đã nhấc tay nên không đo được thời gian giữ.
# Chuột thật vẫn dùng sự kiện chuột (bỏ qua chuột giả lập từ cảm ứng để không đếm hai lần).
function Register-Hold($b) {
    $b.Add_PreviewTouchDown({ param($s, $e) Start-Hold $this $e.GetTouchPoint($win).Position })
    $b.Add_PreviewTouchMove({ param($s, $e) Move-Hold $e.GetTouchPoint($win).Position })
    $b.Add_PreviewTouchUp({ $HoldTimer.Stop() })
    $b.Add_PreviewMouseLeftButtonDown({ param($s, $e) if (-not $e.StylusDevice) { Start-Hold $this $e.GetPosition($win) } })
    $b.Add_PreviewMouseMove({ param($s, $e) if (-not $e.StylusDevice) { Move-Hold $e.GetPosition($win) } })
    $b.Add_PreviewMouseLeftButtonUp({ param($s, $e) if (-not $e.StylusDevice) { $HoldTimer.Stop() } })
    $b.Add_MouseLeave({ param($s, $e) if (-not $e.StylusDevice) { $HoldTimer.Stop() } })
}
# Click ngay sau khi nhấn giữ (trong 1,5 giây) thì bỏ qua — thao tác đó là ghim, không phải mở app.
function Test-HoldHandled {
    if ($script:HoldFiredAt -and ((Get-Date) - $script:HoldFiredAt).TotalSeconds -lt 1.5) { $script:HoldFiredAt = $null; return $true }
    return $false
}
function Remove-FromHome([string]$name) {
    if (-not (Test-Pinned $name)) { return }
    $script:Pins = @($script:Pins | Where-Object { $_ -ne $name })
    Save-Pins
    Build-Home
    if ($script:AppItems) { foreach ($it in $script:AppItems) { if ($it.Name -eq $name) { $it.Pin.Visibility = 'Collapsed' } } }
    Show-Toast "Đã bỏ $name khỏi trang chủ (vẫn còn trong Thư viện)."
}
$LibraryTile = [pscustomobject]@{ name = 'Thư viện'; icon = 'E71D'; color = '#5E5CE6'; type = 'drawer' }

function Build-Home {
    $ui.TilePanel.Children.Clear()
    $script:BadgeEls = @{}
    $script:FolderKids = @{}
    foreach ($n in $script:Pins) {
        $t = Get-Tile $n
        if (-not $t) { continue }
        if ($t.folder) {
            $fname = [string]$t.folder
            if ($script:FolderKids.ContainsKey($fname)) { continue }
            $kids = @($script:Pins | ForEach-Object { Get-Tile $_ } | Where-Object { $_ -and $_.folder -eq $fname })
            $script:FolderKids[$fname] = @($kids | ForEach-Object { $_.name })
            if ($kids.Count -gt 1) {
                [void]$ui.TilePanel.Children.Add((New-HomeIcon ([pscustomobject]@{ name = $fname; type = 'folder'; children = $kids }) 92 $true))
                continue
            }
        }
        $hb = New-HomeIcon $t 92 $true; Register-Hold $hb; [void]$ui.TilePanel.Children.Add($hb)
    }
    [void]$ui.TilePanel.Children.Add((New-HomeIcon $LibraryTile 92 $true))

    $ui.DockFav.Children.Clear()
    $favNames = if ($cfg.dock) { @($cfg.dock) } else { @($cfg.tiles | Select-Object -First 5 | ForEach-Object { $_.name }) }
    foreach ($n in $favNames) {
        $t = @($cfg.tiles | Where-Object { $_.name -eq $n })[0]
        if ($t) { [void]$ui.DockFav.Children.Add((New-HomeIcon $t 68 $false)) }
    }
    Update-DockRecent
    Update-Badges
}

# Bên phải Dock: 3 app vừa dùng + Thư viện (như iPad).
$script:IconCache = @{}
function Get-WindowIconSource($w) {
    $key = $w.Handle.ToInt64()
    if ($script:IconCache.ContainsKey($key)) { return $script:IconCache[$key] }
    $src = $null
    try {
        $hi = [TouchLauncher.Native]::GetWindowIcon($w.Handle)
        if ($hi -ne [IntPtr]::Zero) {
            $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($hi, [System.Windows.Int32Rect]::Empty,
                    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
            $src.Freeze()
        }
    } catch {}
    if (-not $src) {
        try { $path = (Get-Process -Id $w.Pid -ErrorAction Stop).Path; if ($path) { $src = Get-ShellIcon $path 64 } } catch {}
    }
    $script:IconCache[$key] = $src
    return $src
}

function Update-DockRecent {
    $ui.DockRecent.Children.Clear()
    $recent = @([TouchLauncher.Native]::GetAppWindows($PID) | Select-Object -First 3)
    foreach ($w in $recent) {
        $t = [pscustomobject]@{ name = $w.Title; type = 'window'; handle = $w.Handle; iconSource = (Get-WindowIconSource $w) }
        [void]$ui.DockRecent.Children.Add((New-HomeIcon $t 68 $false))
    }
    [void]$ui.DockRecent.Children.Add((New-HomeIcon $LibraryTile 68 $false))
}

# Màn hình hẹp (xoay dọc): ẩn cột widget để icon có chỗ.
$win.Add_SizeChanged({ $ui.Widgets.Visibility = if ($win.ActualWidth -lt 1150) { 'Collapsed' } else { 'Visible' } })

# ---------------------------------------------------------------- Bộ sưu tập ứng dụng (thư viện)
# Chỉ gồm các app của launcher (web app trong "tiles"), chia nhóm như App Library của iPad.
# Bật "Ghim" rồi chạm vào app để thêm / bớt app trên trang chủ.
$script:AppItems = $null
$script:Sections = @()
$script:PinMode  = $false

function Test-Pinned([string]$name) { $script:Pins -contains $name }

function New-AppItem($t) {
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $win.FindResource('Plain')
    $b.Width = 132; $b.Margin = '6,10'

    $grid = New-Object System.Windows.Controls.Grid
    $sp = New-Object System.Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Squircle $t 72))

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $t.name; $tb.FontSize = 14
    $tb.TextWrapping = 'Wrap'; $tb.TextTrimming = 'CharacterEllipsis'; $tb.TextAlignment = 'Center'
    $tb.MaxHeight = 40; $tb.Margin = '4,8,4,0'
    [void]$sp.Children.Add($tb)
    [void]$grid.Children.Add($sp)

    # Dấu ghim: đã có trên trang chủ.
    $pin = New-Object System.Windows.Controls.Border
    $pin.Width = 26; $pin.Height = 26; $pin.CornerRadius = 13
    $pin.Background = ConvertTo-Brush '#FFD60A'
    $pin.HorizontalAlignment = 'Right'; $pin.VerticalAlignment = 'Top'; $pin.Margin = '0,-6,18,0'
    $pin.Child = New-Glyph 'E718' 14 '#1C1C1E' $true
    $pin.Visibility = if (Test-Pinned $t.name) { 'Visible' } else { 'Collapsed' }
    [void]$grid.Children.Add($pin)

    # App tự thêm: nút xóa đỏ, chỉ hiện ở chế độ ghim/sửa.
    $del = $null
    if ($t.user) {
        $del = New-Object System.Windows.Controls.Button
        $del.Style = $win.FindResource('Plain')
        $del.Width = 40; $del.Height = 40; $del.HorizontalAlignment = 'Left'; $del.VerticalAlignment = 'Top'; $del.Margin = '10,-10,0,0'
        $dot = New-Object System.Windows.Controls.Border
        $dot.Width = 30; $dot.Height = 30; $dot.CornerRadius = 15; $dot.Background = ConvertTo-Brush '#FF453A'
        $dot.Child = New-Glyph 'E711' 13 '#FFFFFF' $true
        $del.Content = $dot
        $del.Visibility = if ($script:PinMode) { 'Visible' } else { 'Collapsed' }
        $del.Tag = $t
        $del.Add_Click({ Remove-UserApp $this.Tag })
        [void]$grid.Children.Add($del)
    }

    $b.Content = $grid
    $b.Tag = [pscustomobject]@{ Name = $t.name; Tile = $t; Pin = $pin; Del = $del; Button = $b }
    $b.Add_Click({
        if (Test-HoldHandled) { return }
        $it = $this.Tag
        if ($script:PinMode) { Switch-Pin $it; return }
        try { Invoke-Tile $it.Tile } catch { Show-Toast "Không mở được $($it.Name)." }
    })
    Register-Hold $b
    return $b.Tag
}

function Switch-Pin($it) {
    if (Test-Pinned $it.Name) {
        $script:Pins = @($script:Pins | Where-Object { $_ -ne $it.Name })
        $it.Pin.Visibility = 'Collapsed'
        Show-Toast "Đã bỏ $($it.Name) khỏi trang chủ."
    } else {
        $script:Pins = @($script:Pins) + $it.Name
        $it.Pin.Visibility = 'Visible'
        Show-Toast "Đã ghim $($it.Name) ra trang chủ."
    }
    Save-Pins
    Build-Home
}

function Load-Apps {
    $ui.AppGrid.Children.Clear()
    $script:AppItems = New-Object System.Collections.ArrayList
    $script:Sections = @()
    $groups = [ordered]@{}
    foreach ($t in $cfg.tiles) {
        $g = if ($t.group) { [string]$t.group } else { 'Khác' }
        if (-not $groups.Contains($g)) { $groups[$g] = New-Object System.Collections.ArrayList }
        [void]$groups[$g].Add($t)
    }
    foreach ($g in $groups.Keys) {
        $sec = New-Object System.Windows.Controls.StackPanel
        $sec.Margin = '0,0,0,18'
        $hd = New-Object System.Windows.Controls.TextBlock
        $hd.Text = $g; $hd.FontSize = 22; $hd.FontWeight = 'SemiBold'; $hd.Margin = '12,0,0,4'
        [void]$sec.Children.Add($hd)
        $wrap = New-Object System.Windows.Controls.WrapPanel
        [void]$sec.Children.Add($wrap)
        $items = @()
        foreach ($t in $groups[$g]) {
            $it = New-AppItem $t
            [void]$script:AppItems.Add($it)
            [void]$wrap.Children.Add($it.Button)
            $items += $it
        }
        $script:Sections += [pscustomobject]@{ Panel = $sec; Items = $items }
        [void]$ui.AppGrid.Children.Add($sec)
    }
    Update-AppsHint
}

function Update-AppsHint {
    if ($script:PinMode) {
        $ui.AppsHint.Text = 'Chế độ ghim: chạm vào app để thêm / bớt trên trang chủ. App có dấu vàng đang ở trang chủ.'
        $ui.AppsHint.Foreground = ConvertTo-Brush '#FFD60A'
    } else {
        $ui.AppsHint.Text = "$($script:AppItems.Count) ứng dụng web · $(@($script:Pins).Count) app trên trang chủ · chạm để mở · nhấn giữ để ghim / bỏ ghim"
        $ui.AppsHint.Foreground = ConvertTo-Brush '#8E8E93'
    }
}

$LoadAppsTimer = New-Object System.Windows.Threading.DispatcherTimer
$LoadAppsTimer.Interval = [TimeSpan]::FromMilliseconds(60)   # để bảng kịp hiện trước khi nạp
$LoadAppsTimer.Add_Tick({
    $LoadAppsTimer.Stop()
    try { Load-Apps } catch { $ui.AppsHint.Text = "Không đọc được danh sách ứng dụng: $($_.Exception.Message)" }
})

# Thư viện trượt vào từ bên phải như trang cuối của iPad.
$AppsShift = New-Object System.Windows.Media.TranslateTransform
$ui.AppsOverlay.RenderTransform = $AppsShift
$SlideEase = New-Object System.Windows.Media.Animation.CubicEase
$SlideEase.EasingMode = 'EaseOut'
function Start-AppsSlide([double]$from, [double]$to, [scriptblock]$done) {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation($from, $to, (New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(240))))
    $a.EasingFunction = $SlideEase
    if ($done) { $a.Add_Completed($done) }
    $AppsShift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
}

function Show-Apps {
    $ui.AppsOverlay.Visibility = 'Visible'
    Start-AppsSlide $win.ActualWidth 0 $null
    if ($null -eq $script:AppItems) { $LoadAppsTimer.Start() }
}
function Close-AppsAnimated {
    Start-AppsSlide 0 $win.ActualWidth { Hide-Apps }
}
function Hide-Apps {
    $ui.AppsOverlay.Visibility = 'Collapsed'
    $script:PinMode = $false
    $ui.PinModeText.Text = 'Ghim ra trang chủ'
    $ui.BtnPinMode.Background = ConvertTo-Brush '#33FFFFFF'
    Update-DeleteBadges
    if ($ui.Search.Text) { $ui.Search.Text = '' }
}

$ui.Search.Add_TextChanged({
    $q = $ui.Search.Text.Trim()
    $ui.SearchHint.Visibility = if ($q) { 'Collapsed' } else { 'Visible' }
    if ($null -eq $script:AppItems) { return }
    foreach ($sec in $script:Sections) {
        $any = $false
        foreach ($it in $sec.Items) {
            $show = -not $q -or $it.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0
            $it.Button.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
            if ($show) { $any = $true }
        }
        $sec.Panel.Visibility = if ($any) { 'Visible' } else { 'Collapsed' }
    }
})
$ui.BtnPinMode.Add_Click({
    $script:PinMode = -not $script:PinMode
    $ui.PinModeText.Text = if ($script:PinMode) { 'Xong' } else { 'Ghim ra trang chủ' }
    $ui.BtnPinMode.Background = ConvertTo-Brush $(if ($script:PinMode) { '#B3FF9F0A' } else { '#33FFFFFF' })
    if ($null -ne $script:AppItems) { Update-AppsHint; Update-DeleteBadges }
})
$ui.BtnCloseApps.Add_Click({ Close-AppsAnimated })
function Update-DeleteBadges {
    if ($null -eq $script:AppItems) { return }
    foreach ($it in $script:AppItems) { if ($it.Del) { $it.Del.Visibility = if ($script:PinMode) { 'Visible' } else { 'Collapsed' } } }
}

# ---------------------------------------------------------------- Lịch (âm lịch) & Trung tâm thông báo
$Can = 'Canh', 'Tân', 'Nhâm', 'Quý', 'Giáp', 'Ất', 'Bính', 'Đinh', 'Mậu', 'Kỷ'                    # theo năm % 10
$Chi = 'Thân', 'Dậu', 'Tuất', 'Hợi', 'Tý', 'Sửu', 'Dần', 'Mão', 'Thìn', 'Tỵ', 'Ngọ', 'Mùi'        # theo năm % 12

function Get-LunarText([datetime]$d) {
    $l = [TouchLauncher.Lunar]::FromSolar($d.Day, $d.Month, $d.Year)
    'Âm lịch {0}/{1}{2} · năm {3} {4}' -f $l[0], $l[1], $(if ($l[3]) { ' nhuận' } else { '' }), $Can[$l[2] % 10], $Chi[$l[2] % 12]
}

$script:CalMonth = (Get-Date).Date.AddDays(1 - (Get-Date).Day)
$script:CalDay = $null

function Build-Calendar {
    $m = $script:CalMonth
    $ui.CalTitle.Text = "Tháng $($m.Month), $($m.Year)"
    if ($ui.CalHead.Children.Count -eq 0) {
        foreach ($h in 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $h; $tb.FontSize = 12; $tb.HorizontalAlignment = 'Center'
            $tb.Foreground = ConvertTo-Brush $(if ($h -eq 'CN') { '#FF6961' } else { '#99FFFFFF' })
            [void]$ui.CalHead.Children.Add($tb)
        }
    }
    $ui.CalGrid.Children.Clear()
    $offset = (([int]$m.DayOfWeek) + 6) % 7          # tuần bắt đầu từ thứ Hai
    $start = $m.AddDays(-$offset)
    $today = (Get-Date).Date
    $cells = if (($offset + [DateTime]::DaysInMonth($m.Year, $m.Month)) -gt 35) { 42 } else { 35 }
    for ($i = 0; $i -lt $cells; $i++) {
        $d = $start.AddDays($i)
        $l = [TouchLauncher.Lunar]::FromSolar($d.Day, $d.Month, $d.Year)

        $circle = New-Object System.Windows.Controls.Border
        $circle.Width = 40; $circle.Height = 40; $circle.CornerRadius = 20
        if ($d -eq $today) { $circle.Background = ConvertTo-Brush '#FF453A' }
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.VerticalAlignment = 'Center'
        $sol = New-Object System.Windows.Controls.TextBlock
        $sol.Text = $d.Day; $sol.FontSize = 15; $sol.HorizontalAlignment = 'Center'
        if ($d.DayOfWeek -eq 'Sunday' -and $d -ne $today) { $sol.Foreground = ConvertTo-Brush '#FF6961' }
        $lun = New-Object System.Windows.Controls.TextBlock
        $lun.FontSize = 9.5; $lun.HorizontalAlignment = 'Center'; $lun.Margin = '0,-2,0,0'
        if ($l[0] -eq 1 -or $l[0] -eq 15) {
            $lun.Text = if ($l[0] -eq 1) { "1/$($l[1])" } else { '15' }
            $lun.Foreground = ConvertTo-Brush $(if ($d -eq $today) { '#FFFFFF' } else { '#FFD60A' })
        } else {
            $lun.Text = $l[0]; $lun.Foreground = ConvertTo-Brush '#99FFFFFF'
        }
        [void]$sp.Children.Add($sol); [void]$sp.Children.Add($lun)
        $circle.Child = $sp

        $b = New-Object System.Windows.Controls.Button
        $b.Style = $win.FindResource('Plain')
        $b.Height = 44
        if ($d.Month -ne $m.Month) { $b.Opacity = 0.35 }
        $b.Content = $circle
        $b.Tag = $d
        $b.Add_Click({
            $d = [datetime]$this.Tag
            Show-Toast ($Vi.TextInfo.ToTitleCase($d.ToString('dddd, dd/MM/yyyy', $Vi)) + '  ·  ' + (Get-LunarText $d))
        })
        [void]$ui.CalGrid.Children.Add($b)
    }
}

# Gọi từ Update-Status: sang ngày mới thì vẽ lại lịch.
function Update-CalendarIfNeeded {
    $today = (Get-Date).Date
    if ($script:CalDay -eq $today) { return }
    $script:CalDay = $today
    $script:CalMonth = $today.AddDays(1 - $today.Day)
    $ui.LunarText.Text = Get-LunarText $today
    Build-Calendar
}

$ui.BtnCalPrev.Add_Click({ $script:CalMonth = $script:CalMonth.AddMonths(-1); Build-Calendar })
$ui.BtnCalNext.Add_Click({ $script:CalMonth = $script:CalMonth.AddMonths(1); Build-Calendar })
# Chạm tiêu đề: về tháng hiện tại; nếu đang ở tháng hiện tại thì mở Google Calendar.
$ui.BtnCalTitle.Add_Click({
    $now = (Get-Date).Date.AddDays(1 - (Get-Date).Day)
    if ($script:CalMonth -ne $now) { $script:CalMonth = $now; Build-Calendar; return }
    $t = Get-Tile 'Lịch'
    if ($t) { Invoke-Tile $t }
})

# Trung tâm thông báo + lịch của Windows (Win+N): thông báo của mọi app, lịch tháng, Không làm phiền.
function Open-NotificationCenter { [TouchLauncher.Native]::WinCombo(0x4E) }
$ui.BtnNotify.Add_Click({ Open-NotificationCenter })

# ---------------------------------------------------------------- Tìm kiếm (app · Claude · Google · YouTube)
$ClaudeUrl = if ($cfg.claudeUrl) { [string]$cfg.claudeUrl } else { 'https://claude.ai/new?q={q}' }

function Clear-Spot { $ui.Spot.Text = '' }

function Open-WebApp([string]$url) {
    Clear-Spot
    Watch-NewWindow
    if ($Browser) { Start-Browser @("--app=`"$url`"") } else { Start-Process $url }
    $win.WindowState = 'Minimized'
}

function Invoke-SpotAction($a) {
    $enc = [Uri]::EscapeDataString($a.Q)
    switch ($a.Kind) {
        'claude'  { Open-WebApp ($ClaudeUrl.Replace('{q}', $enc)) }
        'google'  { Open-WebApp "https://www.google.com/search?q=$enc" }
        'youtube' { Open-WebApp "https://www.youtube.com/results?search_query=$enc" }
        'app'     { Clear-Spot; Invoke-Tile $a.Tile }
    }
}

function Add-SpotRow($iconTile, [string]$text, $action) {
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $win.FindResource('Glass')
    $b.Height = 60; $b.Margin = '0,3'; $b.Padding = '12,0'; $b.HorizontalContentAlignment = 'Left'
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    [void]$sp.Children.Add((New-Squircle $iconTile 40))
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text; $tb.FontSize = 18; $tb.Margin = '14,0,0,0'; $tb.VerticalAlignment = 'Center'
    $tb.TextTrimming = 'CharacterEllipsis'; $tb.MaxWidth = 520
    [void]$sp.Children.Add($tb)
    $b.Content = $sp
    $b.Tag = $action
    $b.Add_Click({ Invoke-SpotAction $this.Tag })
    [void]$ui.SpotList.Children.Add($b)
}

function Update-Spot {
    $q = $ui.Spot.Text.Trim()
    $ui.SpotHint.Visibility = if ($ui.Spot.Text) { 'Collapsed' } else { 'Visible' }
    $ui.BtnSpotClear.Visibility = if ($ui.Spot.Text) { 'Visible' } else { 'Collapsed' }
    $ui.SpotList.Children.Clear()
    if (-not $q) { $ui.SpotResults.Visibility = 'Collapsed'; return }

    $claudeTile = Get-Tile 'Claude'
    if (-not $claudeTile) { $claudeTile = [pscustomobject]@{ icon = '✳'; color = '#D97757'; type = 'app' } }
    Add-SpotRow $claudeTile ('Hỏi Claude: "{0}"' -f $q) @{ Kind = 'claude'; Q = $q }
    foreach ($t in @($cfg.tiles | Where-Object { $_.name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 5)) {
        Add-SpotRow $t $t.name @{ Kind = 'app'; Q = $q; Tile = $t }
    }
    Add-SpotRow ([pscustomobject]@{ icon = 'E721'; color = '#0A84FF'; type = 'app' }) "Tìm trên Google: $q" @{ Kind = 'google'; Q = $q }
    Add-SpotRow ([pscustomobject]@{ icon = 'E768'; color = '#FF3B30'; type = 'app' }) "Tìm trên YouTube: $q" @{ Kind = 'youtube'; Q = $q }
    $ui.SpotResults.Visibility = 'Visible'
}

$ui.Spot.Add_TextChanged({ Update-Spot })
$ui.Spot.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Return' -and $ui.Spot.Text.Trim()) { Invoke-SpotAction @{ Kind = 'claude'; Q = $ui.Spot.Text.Trim() }; $e.Handled = $true }
    elseif ($e.Key -eq 'Escape') { Clear-Spot; $e.Handled = $true }
})
$ui.BtnSpotClear.Add_Click({ Clear-Spot })

# ---------------------------------------------------------------- Vuốt ngang
# Màn hình chính: vuốt sang trái -> mở Thư viện. Trong Thư viện: vuốt sang phải -> về màn hình chính.
# Dùng sự kiện Preview để nhận cả khi ngón tay bắt đầu trên icon hoặc vùng cuộn.
$script:SwipeStart = $null
function Complete-Swipe([System.Windows.Point]$p) {
    $s = $script:SwipeStart; $script:SwipeStart = $null
    if ($null -eq $s) { return $false }
    $dx = $p.X - $s.X; $dy = $p.Y - $s.Y
    if ($s.Y -lt 120 -and $dy -gt 110 -and $dy -gt 2 * [math]::Abs($dx) -and $ui.AppsOverlay.Visibility -ne 'Visible') { Open-NotificationCenter; return $true }
    if ([math]::Abs($dx) -lt 110 -or [math]::Abs($dx) -lt 2 * [math]::Abs($dy)) { return $false }
    if (@($ui.Overlay, $ui.PowerOverlay, $ui.SwitchOverlay | Where-Object { $_.Visibility -eq 'Visible' }).Count) { return $false }
    $appsOpen = $ui.AppsOverlay.Visibility -eq 'Visible'
    if ($dx -lt 0 -and -not $appsOpen) { Show-Apps; return $true }
    if ($dx -gt 0 -and $appsOpen) { Close-AppsAnimated; return $true }
    return $false
}
$win.Add_PreviewTouchDown({ param($s, $e) $script:SwipeStart = $e.GetTouchPoint($win).Position })
$win.Add_PreviewTouchUp({ param($s, $e) if (Complete-Swipe $e.GetTouchPoint($win).Position) { $e.Handled = $true } })
# Chuột thật (không phải cảm ứng giả lập chuột) cũng kéo được, tiện khi thử trên máy không cảm ứng.
$win.Add_PreviewMouseLeftButtonDown({ param($s, $e) if (-not $e.StylusDevice) { $script:SwipeStart = $e.GetPosition($win) } })
$win.Add_PreviewMouseLeftButtonUp({ param($s, $e) if (-not $e.StylusDevice -and (Complete-Swipe $e.GetPosition($win))) { $e.Handled = $true } })

# ---------------------------------------------------------------- Bàn phím cảm ứng
$TabTip = Join-Path $env:CommonProgramFiles 'microsoft shared\ink\TabTip.exe'
$TipKey = 'HKCU:\Software\Microsoft\TabletTip\1.7'

$KbdRetry = New-Object System.Windows.Threading.DispatcherTimer
$KbdRetry.Interval = [TimeSpan]::FromMilliseconds(800)
$KbdRetry.Add_Tick({
    $KbdRetry.Stop()
    if (-not [TouchLauncher.Native]::ToggleTouchKeyboard()) { Start-Process osk.exe }
})
function Switch-Keyboard {
    if ([TouchLauncher.Native]::ToggleTouchKeyboard()) { return }
    if (Test-Path $TabTip) { Start-Process $TabTip; $KbdRetry.Start() }
    else { Start-Process osk.exe }
}

# "Luôn hiện bàn phím cảm ứng" khi chạm vào ô nhập chữ — kể cả khi máy vẫn nhận bàn phím vật lý (bị hư).
function Get-AutoKeyboard {
    try { return ((Get-ItemProperty $TipKey -ErrorAction Stop).TouchKeyboardTapInvoke -eq 2) } catch { return $false }
}
function Set-AutoKeyboard([bool]$on) {
    try {
        if (-not (Test-Path $TipKey)) { New-Item -Path $TipKey -Force | Out-Null }
        Set-ItemProperty -Path $TipKey -Name TouchKeyboardTapInvoke -Value ([int]$(if ($on) { 2 } else { 1 })) -Type DWord
        Set-ItemProperty -Path $TipKey -Name EnableDesktopModeAutoInvoke -Value ([int]$on) -Type DWord
        return $true
    } catch { return $false }
}
$script:AutoKbd = Get-AutoKeyboard

$ui.BtnKbd2.Add_Click({ $ui.Search.Focus() | Out-Null; Switch-Keyboard })

# ---------------------------------------------------------------- Phím media & âm lượng
$VK = @{ Mute = 0xAD; VolDown = 0xAE; VolUp = 0xAF; Next = 0xB0; Prev = 0xB1; Play = 0xB3 }
function Send-Volume([byte]$vk) { 1..$VolumeStep | ForEach-Object { [TouchLauncher.Native]::Key($vk) } }

# ---------------------------------------------------------------- Độ sáng (màn hình laptop/tablet)
function Get-Brightness {
    try { (Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -OperationTimeoutSec 3 -ErrorAction Stop | Select-Object -First 1).CurrentBrightness }
    catch { $null }
}
function Set-Brightness([int]$v) {
    Initialize-Brightness
    if ($null -eq $script:Bri) { Show-Toast 'Màn hình này không chỉnh được độ sáng.'; return }
    $v = [math]::Max(0, [math]::Min(100, $v))
    try {
        Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -OperationTimeoutSec 3 -ErrorAction Stop | Select-Object -First 1 |
            Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = [byte]$v } -ErrorAction Stop | Out-Null
        $script:Bri = $v
    } catch { Show-Toast 'Không chỉnh được độ sáng trên màn hình này.' }
}
$script:Bri = $null
$script:BriLoaded = $false
function Initialize-Brightness { if (-not $script:BriLoaded) { $script:Bri = Get-Brightness; $script:BriLoaded = $true } }

# ---------------------------------------------------------------- Chế độ tiết kiệm pin
$OverlayEfficiency = '961cc777-2547-4f9d-8174-7d86181b8a7a'   # "Best power efficiency"
$OverlayBalanced   = '00000000-0000-0000-0000-000000000000'   # "Balanced"

function Get-SaverState {
    try {
        $g = [Guid]::Empty
        if ([TouchLauncher.Native]::PowerGetEffectiveOverlayScheme([ref]$g) -ne 0) { return $false }
        return ($g -eq [Guid]$OverlayEfficiency)
    } catch { return $false }
}
function Set-Saver([bool]$on) {
    $overlay   = if ($on) { $OverlayEfficiency } else { $OverlayBalanced }
    $threshold = if ($on) { 100 } else { 20 }   # Energy Saver tự bật khi pin dưới ngưỡng này
    $okOverlay = ([TouchLauncher.Native]::PowerSetActiveOverlayScheme([Guid]$overlay) -eq 0)
    & powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_ENERGYSAVER ESBATTTHRESHOLD $threshold | Out-Null
    & powercfg.exe /setactive SCHEME_CURRENT | Out-Null
    Initialize-Brightness
    if ($on -and $cfg.saverBrightness -and $null -ne $script:Bri -and $script:Bri -gt [int]$cfg.saverBrightness) {
        Set-Brightness ([int]$cfg.saverBrightness)
    }
    $script:SaverOn = $on
    Update-Status
    if (-not $okOverlay) { Show-Toast 'Windows không cho đổi chế độ năng lượng (thử chạy lại bằng quyền admin).' }
    elseif ($on) { Show-Toast 'Đã bật tiết kiệm pin: hiệu suất năng lượng tối đa + Energy Saver.' }
    else { Show-Toast 'Đã về chế độ cân bằng.' }
}
$script:SaverOn = Get-SaverState

# ---------------------------------------------------------------- Dọn tiến trình thừa
$MySession = (Get-Process -Id $PID).SessionId

function Get-JunkProcesses([string[]]$names) {
    $names = @($names | Where-Object { $_ -and $_ -ne $BrowserName })
    if ($names.Count -eq 0) { return @() }
    Get-Process -Name $names -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $MySession -and $_.Id -ne $PID } |
        Group-Object Name | ForEach-Object {
            [pscustomobject]@{
                Name  = $_.Name
                Count = $_.Count
                MB    = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
            }
        } | Sort-Object MB -Descending
}

function Stop-Junk([string[]]$names) {
    $result = [pscustomobject]@{ Killed = 0; MB = 0; Failed = 0 }
    $names = @($names | Where-Object { $_ })
    if ($names.Count -eq 0) { return $result }
    foreach ($p in Get-Process -Name $names -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $MySession -and $_.Id -ne $PID }) {
        $ws = $p.WorkingSet64
        try { $p.Kill(); $result.Killed++; $result.MB += $ws / 1MB } catch { $result.Failed++ }
    }
    $result.MB = [math]::Round($result.MB)
    return $result
}

function Add-KillRow($item, [bool]$checked) {
    $tb = New-Object System.Windows.Controls.Primitives.ToggleButton
    $tb.Style = $win.FindResource('Row')
    $tb.IsChecked = $checked
    $tb.Tag = $item.Name
    $extra = if ($item.Count -gt 1) { "  ($($item.Count) tiến trình)" } else { '' }
    $tb.Content = "{0}   ·   {1} MB{2}" -f $item.Name, $item.MB, $extra
    [void]$ui.KillList.Children.Add($tb)
}

function Show-CleanPanel {
    $ui.KillList.Children.Clear()
    $main = @(Get-JunkProcesses $cfg.killList)
    $opt  = @(Get-JunkProcesses $cfg.killListOptional)
    foreach ($it in $main) { Add-KillRow $it $true }
    foreach ($it in $opt)  { Add-KillRow $it $false }
    if ($main.Count + $opt.Count -eq 0) {
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = 'Không có tiến trình thừa nào đang chạy. Máy đang gọn nhẹ!'
        $t.FontSize = 20; $t.Margin = '0,24'; $t.TextWrapping = 'Wrap'
        [void]$ui.KillList.Children.Add($t)
        $ui.BtnKill.IsEnabled = $false
    } else {
        $ui.BtnKill.IsEnabled = $true
    }
    $ui.Overlay.Visibility = 'Visible'
}

$ui.BtnCancel.Add_Click({ $ui.Overlay.Visibility = 'Collapsed' })
$ui.BtnKill.Add_Click({
    $sel = @($ui.KillList.Children | Where-Object { $_ -is [System.Windows.Controls.Primitives.ToggleButton] -and $_.IsChecked } | ForEach-Object { $_.Tag })
    $r = Stop-Junk $sel
    $ui.Overlay.Visibility = 'Collapsed'
    $msg = "Đã đóng $($r.Killed) tiến trình, giải phóng khoảng $($r.MB) MB RAM."
    if ($r.Failed) { $msg += " ($($r.Failed) tiến trình cần quyền admin, bỏ qua.)" }
    Show-Toast $msg
})

# ---------------------------------------------------------------- Nguồn
$script:PowerAction = $null
function Reset-PowerMenu {
    $script:PowerAction = $null
    $ui.PowerTitle.Text = 'Nguồn'
    $ui.PowerChoices.Visibility = 'Visible'
    $ui.PowerConfirm.Visibility = 'Collapsed'
    $ui.BtnPowerCancel.Visibility = 'Visible'
}
# Tắt máy / khởi động lại phải xác nhận lần nữa để tránh chạm nhầm.
function Request-Power([string]$action, [string]$question) {
    $script:PowerAction = $action
    $ui.PowerTitle.Text = $question
    $ui.PowerChoices.Visibility = 'Collapsed'
    $ui.PowerConfirm.Visibility = 'Visible'
    $ui.BtnPowerCancel.Visibility = 'Collapsed'
}
function Show-PowerMenu { Reset-PowerMenu; $ui.PowerOverlay.Visibility = 'Visible' }
$ui.BtnPowerCancel.Add_Click({ $ui.PowerOverlay.Visibility = 'Collapsed' })
$ui.BtnPowerNo.Add_Click({ Reset-PowerMenu })
$ui.BtnShutdown.Add_Click({ Request-Power 'shutdown' 'Tắt máy ngay?' })
$ui.BtnRestart.Add_Click({ Request-Power 'restart' 'Khởi động lại máy?' })
$ui.BtnSleep.Add_Click({
    $ui.PowerOverlay.Visibility = 'Collapsed'
    [void][System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $false, $false)
})
$ui.BtnExit.Add_Click({ $win.Close() })
$ui.BtnPowerYes.Add_Click({
    switch ($script:PowerAction) {
        'shutdown' { Start-Process -FilePath 'shutdown.exe' -ArgumentList '/s', '/t', '0' -WindowStyle Hidden }
        'restart'  { Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/t', '0' -WindowStyle Hidden }
    }
    $ui.PowerOverlay.Visibility = 'Collapsed'
})


# ---------------------------------------------------------------- Đa nhiệm
$script:Hwnd   = [IntPtr]::Zero
$script:Thumbs = New-Object System.Collections.ArrayList
$win.Add_SourceInitialized({ $script:Hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle })

function Clear-Thumbs {
    foreach ($t in $script:Thumbs) { [TouchLauncher.Native]::HideThumb($t) }
    $script:Thumbs.Clear()
}
function Hide-Switcher {
    Clear-Thumbs
    $ui.SwitchOverlay.Visibility = 'Collapsed'
    $ui.SwitchGrid.Children.Clear()
}
function Hide-Overlays {
    Hide-Folder
    Hide-Switcher
    Hide-Apps
    foreach ($o in 'Overlay', 'PowerOverlay', 'AddOverlay') { $ui[$o].Visibility = 'Collapsed' }
}

# Đóng app web -> về trang chủ launcher (như iPad). Tắt bằng "homeOnAppClose": false.
$HomeOnClose = $cfg.homeOnAppClose -ne $false
function Add-AppWindowWatch([IntPtr]$h) {
    if (-not $HomeOnClose -or $h -eq [IntPtr]::Zero) { return }
    $p = $null
    try { $p = (Get-Process -Id ([TouchLauncher.Native]::GetAppWindows(0) | Where-Object { $_.Handle -eq $h } | Select-Object -First 1).Pid -ErrorAction Stop).ProcessName } catch {}
    if ($p -and $p -eq $BrowserName) { [TouchLauncher.WinWatch]::Track($h) }
}
$HomeOnCloseTimer = New-Object System.Windows.Threading.DispatcherTimer
$HomeOnCloseTimer.Interval = [TimeSpan]::FromMilliseconds(250)   # chờ Windows xong việc đóng cửa sổ
$HomeOnCloseTimer.Add_Tick({
    $HomeOnCloseTimer.Stop()
    if ($script:Split -or $script:AppClosing) { return }             # chia đôi: app còn lại tự phóng to
    if ($ui.NightOverlay.Visibility -eq 'Visible' -or $blackWin.IsVisible) { return }
    if (Test-LauncherForeground) { return }
    if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Maximized' }
    if ($script:Hwnd -ne [IntPtr]::Zero) { [TouchLauncher.Native]::ForceActivate($script:Hwnd) }
})
[TouchLauncher.WinWatch]::OnClosed = [Action[long]] { param($h) $HomeOnCloseTimer.Stop(); $HomeOnCloseTimer.Start() }

function Show-Launcher {
    if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Maximized' }
    [void]$win.Activate()
    if ($script:Hwnd -ne [IntPtr]::Zero) { [TouchLauncher.Native]::Activate($script:Hwnd) }
}

function Switch-ToWindow([IntPtr]$h) {
    [TouchLauncher.Native]::Activate($h)   # chuyển trước, khi launcher còn giữ quyền foreground
    Add-AppWindowWatch $h
    Hide-Overlays
    $win.WindowState = 'Minimized'
}

function New-WindowCard($w, [double]$cw, [double]$ch) {
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $win.FindResource('Glass')
    $b.Width = $cw; $b.Height = $ch; $b.Margin = '10'; $b.Padding = '12'

    $g = New-Object System.Windows.Controls.Grid
    $g.Width = $cw - 26; $g.Height = $ch - 26
    $r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = 'Auto'
    [void]$g.RowDefinitions.Add($r0)
    [void]$g.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))

    $head = New-Object System.Windows.Controls.DockPanel
    $head.Height = 52
    $close = New-Object System.Windows.Controls.Button
    $close.Style = $win.FindResource('GlassRound')
    $close.Width = 52; $close.Height = 52; $close.Margin = '8,0,0,0'
    $x = New-Object System.Windows.Controls.TextBlock
    $x.Style = $win.FindResource('Icon'); $x.Text = [string][char]0xE711; $x.FontSize = 20
    $close.Content = $x
    $close.Tag = $w.Handle
    $close.Add_Click({ [TouchLauncher.Native]::CloseWindow($this.Tag); $RefreshTimer.Stop(); $RefreshTimer.Start() })
    [System.Windows.Controls.DockPanel]::SetDock($close, 'Right')
    [void]$head.Children.Add($close)

    $src = Get-WindowIconSource $w
    $icon = New-Squircle ([pscustomobject]@{ name = $w.Title; type = 'window'; iconSource = $src }) 36
    $icon.Margin = '4,0,12,0'; $icon.VerticalAlignment = 'Center'
    [System.Windows.Controls.DockPanel]::SetDock($icon, 'Left')
    [void]$head.Children.Add($icon)

    $tt = New-Object System.Windows.Controls.TextBlock
    $tt.Text = $w.Title; $tt.FontSize = 17; $tt.TextTrimming = 'CharacterEllipsis'; $tt.VerticalAlignment = 'Center'
    [void]$head.Children.Add($tt)
    [void]$g.Children.Add($head)

    # Khung ảnh xem trước; icon lớn làm nền khi cửa sổ đang thu nhỏ (không có ảnh).
    $box = New-Object System.Windows.Controls.Border
    $box.Margin = '0,10,0,0'; $box.CornerRadius = 14
    $box.Background = ConvertTo-Brush '#99000000'
    $box.Child = New-Squircle ([pscustomobject]@{ name = $w.Title; type = 'window'; iconSource = $src }) 72
    [System.Windows.Controls.Grid]::SetRow($box, 1)
    [void]$g.Children.Add($box)

    $b.Content = $g
    $b.Tag = [pscustomobject]@{ Handle = $w.Handle; Box = $box }
    $b.Add_Click({ Switch-ToWindow $this.Tag.Handle })
    return $b
}

function Show-Switcher {
    Clear-Thumbs
    $ui.SwitchGrid.Children.Clear()
    $ui.SwitchOverlay.Visibility = 'Visible'
    $wins = @([TouchLauncher.Native]::GetAppWindows($PID))
    $ui.SwitchEmpty.Visibility = if ($wins.Count) { 'Collapsed' } else { 'Visible' }
    $ui.BtnCloseAllWin.IsEnabled = $wins.Count -gt 0
    if ($wins.Count -eq 0) { return }

    # Chọn số cột sao cho thẻ to nhất mà vẫn vừa màn hình, không cần cuộn.
    $win.UpdateLayout()
    $W = $ui.SwitchArea.ActualWidth; $H = $ui.SwitchArea.ActualHeight
    $n = $wins.Count; $gap = 20; $head = 70; $best = 0
    for ($c = 1; $c -le $n; $c++) {
        $rows = [math]::Ceiling($n / $c)
        $cw = [math]::Min(($W / $c) - $gap, ((($H / $rows) - $gap - $head) / 0.6))
        $best = [math]::Max($best, [math]::Min($cw, 560))
    }
    $cw = [math]::Max(170, [math]::Floor($best))
    $ch = [math]::Floor($cw * 0.6) + $head
    foreach ($w in $wins) { [void]$ui.SwitchGrid.Children.Add((New-WindowCard $w $cw $ch)) }
    $ThumbTimer.Start()
}

function Register-Thumbs {
    Clear-Thumbs
    if ($ui.SwitchOverlay.Visibility -ne 'Visible' -or $script:Hwnd -eq [IntPtr]::Zero) { return }
    $m = [System.Windows.PresentationSource]::FromVisual($win).CompositionTarget.TransformToDevice
    foreach ($card in $ui.SwitchGrid.Children) {
        $box = $card.Tag.Box
        $p = $box.TransformToAncestor($win).Transform((New-Object System.Windows.Point 0, 0))
        $th = [TouchLauncher.Native]::ShowThumb($script:Hwnd, $card.Tag.Handle,
                [int](($p.X + 6) * $m.M11), [int](($p.Y + 6) * $m.M22),
                [int](($box.ActualWidth - 12) * $m.M11), [int](($box.ActualHeight - 12) * $m.M22))
        if ($th -ne [IntPtr]::Zero) { [void]$script:Thumbs.Add($th) }
    }
}

$ThumbTimer = New-Object System.Windows.Threading.DispatcherTimer
$ThumbTimer.Interval = [TimeSpan]::FromMilliseconds(30)          # đợi bố cục xong rồi mới gắn ảnh xem trước
$ThumbTimer.Add_Tick({ $ThumbTimer.Stop(); Register-Thumbs })
$RefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$RefreshTimer.Interval = [TimeSpan]::FromMilliseconds(600)       # đợi app đóng xong rồi vẽ lại
$RefreshTimer.Add_Tick({ $RefreshTimer.Stop(); if ($ui.SwitchOverlay.Visibility -eq 'Visible') { Show-Switcher } })

$ui.BtnSwitchHome.Add_Click({ Hide-Switcher })
$ui.BtnCloseAllWin.Add_Click({
    foreach ($card in @($ui.SwitchGrid.Children)) { [TouchLauncher.Native]::CloseWindow($card.Tag.Handle) }
    $RefreshTimer.Stop(); $RefreshTimer.Start()
})

# ---------------------------------------------------------------- PiP YouTube
# Thu cửa sổ YouTube thành khung video nhỏ luôn nổi ở góc dưới; cửa sổ được cắt (window region)
# chỉ còn đúng khung video bo góc — thanh tiêu đề và thanh tìm kiếm của YouTube bị ẩn đi.
$PipMatch    = if ($cfg.pip.match) { [string]$cfg.pip.match } else { '(^|[-–] )YouTube$' }
$PipCropTop  = if ($cfg.pip.cropTop) { [double]$cfg.pip.cropTop } else { 89 }
$PipWidthPct = if ($cfg.pip.widthPercent) { [double]$cfg.pip.widthPercent } else { 36 }
$PipPos      = if ($cfg.pip.position) { [string]$cfg.pip.position } else { 'bottom-right' }
$script:Pip = $null

# Giữ khung PiP: nếu YouTube tự vẽ lại khung cửa sổ thì cắt lại và giữ luôn-trên-cùng.
$PipGuard = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background)
$PipGuard.Interval = [TimeSpan]::FromSeconds(2)
$PipGuard.Add_Tick({
    $p = $script:Pip
    if (-not $p -or -not [TouchLauncher.Native]::IsWindow($p.Handle)) { $PipGuard.Stop(); $script:Pip = $null; return }
    [TouchLauncher.Native]::Place($p.Handle, $true, $p.X, $p.Y, $p.W, $p.H)
    [TouchLauncher.Native]::ClipTo($p.Handle, 0, $p.Crop, $p.W, $p.H - $p.Crop, $p.Radius)
})

function Find-PipWindow {
    foreach ($w in [TouchLauncher.Native]::GetAppWindows($PID)) {
        if ($w.Title -match '(Edge|Chrome)$' -or $w.Title -notmatch $PipMatch) { continue }
        $p = Get-Process -Id $w.Pid -ErrorAction SilentlyContinue
        if ($p -and ($p.ProcessName -eq 'chrome' -or $p.ProcessName -eq 'msedge')) { return $w }
    }
    return $null
}

function Get-DpiScale {
    $src = [System.Windows.PresentationSource]::FromVisual($win)
    if ($src) { $src.CompositionTarget.TransformToDevice.M11 } else { 1.0 }
}

function Switch-Pip {
    if ($script:Pip) {
        $PipGuard.Stop()
        $h = $script:Pip.Handle
        if ([TouchLauncher.Native]::IsWindow($h)) {
            [TouchLauncher.Native]::Unclip($h)
            $r = $script:Pip.Rect
            [TouchLauncher.Native]::Place($h, $false, $r.Left, $r.Top, $r.Right - $r.Left, $r.Bottom - $r.Top)
            if ($script:Pip.WasMax) { [TouchLauncher.Native]::Maximize($h) }
            [TouchLauncher.Native]::Activate($h)
        }
        $script:Pip = $null
        Show-Toast 'Đã tắt PiP.'
        return
    }
    $w = Find-PipWindow
    if (-not $w) { Show-Toast 'Hãy mở YouTube và phát video trước, rồi bấm PiP.'; return }
    $h = $w.Handle
    $wasMax = [TouchLauncher.Native]::IsZoomed($h)
    if ($w.Minimized -or $wasMax) { [TouchLauncher.Native]::Restore($h) }
    $rect = [TouchLauncher.Native]::GetRect($h)

    $s  = Get-DpiScale
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $pw = [int][math]::Min($wa.Width * $PipWidthPct / 100, 720 * $s)
    $vh = [int]($pw * 9 / 16)
    $crop = [int]($PipCropTop * $s)
    $gap  = [int](16 * $s)
    $navGap = if ($NavEnabled -and $NavPos -eq 'right') { [int](90 * $s) } else { $gap }
    $x = if ($PipPos -like '*left') { $wa.Left + $(if ($NavEnabled -and $NavPos -eq 'left') { [int](90 * $s) } else { $gap }) }
         else { $wa.Right - $pw - $navGap }
    # Đáy khung video cách đáy màn hình một khoảng nhỏ (chừa thanh điều hướng nếu nằm dưới).
    $bottomGap = if ($NavEnabled -and $NavPos -eq 'bottom') { [int](90 * $s) } else { $gap }
    $y = if ($PipPos -like 'top*') { $wa.Top + $gap - $crop } else { $wa.Bottom - $bottomGap - $vh - $crop }
    $radius = [int](18 * $s)

    [TouchLauncher.Native]::Place($h, $true, $x, $y, $pw, $crop + $vh)
    [TouchLauncher.Native]::ClipTo($h, 0, $crop, $pw, $vh, $radius)
    $script:Pip = [pscustomobject]@{ Handle = $h; Rect = $rect; WasMax = $wasMax; X = $x; Y = $y; W = $pw; H = $crop + $vh; Crop = $crop; Radius = $radius }
    $PipGuard.Start()
    Show-Toast 'PiP: video nổi ở góc dưới. Bấm PiP lần nữa để phóng to lại.'
}

# ---------------------------------------------------------------- Thanh điều hướng nổi
function Test-LauncherForeground {
    $win.WindowState -ne 'Minimized' -and [TouchLauncher.Native]::GetForegroundWindow() -eq $script:Hwnd
}
function Invoke-NavBack {
    if (Test-LauncherForeground) {
        if ($ui.NightOverlay.Visibility -eq 'Visible') { Exit-Night; return }
        if ($ui.FolderOverlay.Visibility -eq 'Visible') { Hide-Folder; return }
        foreach ($o in 'PowerOverlay', 'Overlay', 'AddOverlay') { if ($ui[$o].Visibility -eq 'Visible') { $ui[$o].Visibility = 'Collapsed'; return } }
        if ($ui.SwitchOverlay.Visibility -eq 'Visible') { Hide-Switcher; return }
        if ($ui.AppsOverlay.Visibility -eq 'Visible') { Hide-Apps }
        return
    }
    [TouchLauncher.Native]::Key(0xA6)   # VK_BROWSER_BACK — trình duyệt, Explorer, Settings… đều hiểu
}
function Invoke-NavHome { Hide-CC; Hide-Overlays; Show-Launcher }
function Invoke-NavRecent {
    Hide-CC
    if ((Test-LauncherForeground) -and $ui.SwitchOverlay.Visibility -eq 'Visible') { Hide-Switcher; return }
    Hide-Overlays
    Show-Launcher
    Show-Switcher
}

$navXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Touch Launcher Nav" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        Stylus.IsPressAndHoldEnabled="False" Stylus.IsFlicksEnabled="False" Stylus.IsTapFeedbackEnabled="False">
  <Window.Resources>
    <Style x:Key="Nav" TargetType="Button">
      <Setter Property="Width" Value="62"/>
      <Setter Property="Height" Value="62"/>
      <Setter Property="Margin" Value="2"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="#01000000" CornerRadius="31">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="B" Property="Background" Value="#40FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="NavIcon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="24"/>
    </Style>
  </Window.Resources>
  <Grid>
  <!-- Thu gọn: chỉ còn một vạch nhỏ ở mép màn hình -->
  <Border x:Name="NavHandle" Visibility="Collapsed" Width="30" Height="130" Background="#01000000">
    <Border x:Name="NavPill" Width="6" Height="84" CornerRadius="3" Background="#E6FFFFFF" BorderBrush="#59000000" BorderThickness="1"/>
  </Border>
  <Border x:Name="NavPanel" Background="#D91C1C1E" CornerRadius="34" Padding="4" BorderBrush="#40FFFFFF" BorderThickness="1">
    <StackPanel x:Name="NavStack">
      <Button x:Name="NavBack"   Style="{StaticResource Nav}"><TextBlock Style="{StaticResource NavIcon}" Text="&#xE72B;"/></Button>
      <Button x:Name="NavHome"   Style="{StaticResource Nav}"><TextBlock Style="{StaticResource NavIcon}" Text="&#xE80F;"/></Button>
      <Button x:Name="NavRecent" Style="{StaticResource Nav}"><TextBlock Style="{StaticResource NavIcon}" Text="&#xE7C4;"/></Button>
      <Button x:Name="NavKbd"    Style="{StaticResource Nav}"><TextBlock Style="{StaticResource NavIcon}" Text="&#xE765;"/></Button>
      <Button x:Name="NavCC"     Style="{StaticResource Nav}"><TextBlock Style="{StaticResource NavIcon}" Text="&#xE713;"/></Button>
    </StackPanel>
  </Border>
  </Grid>
</Window>
'@

$NavEnabled = -not ($cfg.navBar -and $cfg.navBar.enabled -eq $false)
$NavPos     = if ($cfg.navBar.position) { [string]$cfg.navBar.position } else { 'right' }
$NavIdle    = if ($cfg.navBar.opacity) { [double]$cfg.navBar.opacity } else { 0.6 }
$script:NavAutoHide = if ($script:Settings.ContainsKey('navAutoHide')) { [bool]$script:Settings['navAutoHide'] }
                      else { -not ($cfg.navBar -and $cfg.navBar.autoHide -eq $false) }

$nav = [Windows.Markup.XamlReader]::Parse($navXaml)
$NavPanel = $nav.FindName('NavPanel'); $NavHandle = $nav.FindName('NavHandle'); $NavPill = $nav.FindName('NavPill')
if ($NavPos -eq 'bottom') {
    $nav.FindName('NavStack').Orientation = 'Horizontal'
    $NavHandle.Width = 130; $NavHandle.Height = 30; $NavPill.Width = 84; $NavPill.Height = 6
}
$nav.Opacity = $NavIdle
$nav.Add_SourceInitialized({ [TouchLauncher.Native]::MakeNoActivate((New-Object System.Windows.Interop.WindowInteropHelper $nav).Handle) })

function Set-NavPosition {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $w = $nav.ActualWidth; $h = $nav.ActualHeight
    $gap = if ($NavHandle.Visibility -eq 'Visible') { 0 } else { 6 }   # thu gọn: dính sát mép
    switch ($NavPos) {
        'left'   { $nav.Left = $wa.Left + $gap;                 $nav.Top = $wa.Top + ($wa.Height - $h) / 2 }
        'bottom' { $nav.Left = $wa.Left + ($wa.Width - $w) / 2; $nav.Top = $wa.Bottom - $h - $gap }
        default  { $nav.Left = $wa.Right - $w - $gap;           $nav.Top = $wa.Top + ($wa.Height - $h) / 2 }
    }
}
$nav.Add_Loaded({ Set-NavPosition })

# Tự ẩn: 4 giây không chạm -> thu thành vạch nhỏ ở mép; chạm vạch -> mở ra.
# (Tắt bằng "navBar": { "autoHide": false } — khi đó thanh chỉ mờ đi.)
function Expand-Nav {
    $NavHandle.Visibility = 'Collapsed'; $NavPanel.Visibility = 'Visible'
    $nav.Opacity = 1
    $nav.UpdateLayout(); Set-NavPosition
    $NavFade.Stop(); $NavFade.Start()
}
# Ghim (luôn hiện) / bỏ ghim (tự ẩn) thanh điều hướng — lưu lại cho lần mở sau.
function Switch-NavPin {
    $script:NavAutoHide = -not $script:NavAutoHide
    Save-Setting 'navAutoHide' $script:NavAutoHide
    $NavFade.Interval = [TimeSpan]::FromSeconds($(if ($script:NavAutoHide) { 4 } else { 2.5 }))
    Expand-Nav
    Show-CcToast $(if ($script:NavAutoHide) { 'Thanh điều hướng sẽ tự ẩn sau 4 giây không chạm.' } else { 'Đã ghim thanh điều hướng: luôn hiện.' })
}

function Collapse-Nav {
    if (-not $script:NavAutoHide) { $nav.Opacity = $NavIdle; return }
    $NavPanel.Visibility = 'Collapsed'; $NavHandle.Visibility = 'Visible'
    $nav.Opacity = 1
    $nav.UpdateLayout(); Set-NavPosition
}
$NavFade = New-Object System.Windows.Threading.DispatcherTimer
$NavFade.Interval = [TimeSpan]::FromSeconds($(if ($script:NavAutoHide) { 4 } else { 2.5 }))
$NavFade.Add_Tick({ $NavFade.Stop(); Collapse-Nav })
# Chạm vạch: chỉ mở thanh (không để cú chạm đi tiếp xuống nút nào).
$nav.Add_PreviewTouchDown({ param($s, $e) if ($NavHandle.Visibility -eq 'Visible') { Expand-Nav; $e.Handled = $true } else { $NavFade.Stop(); $NavFade.Start() } })
$nav.Add_PreviewMouseDown({ param($s, $e) if ($NavHandle.Visibility -eq 'Visible') { Expand-Nav; $e.Handled = $true } else { $nav.Opacity = 1; $NavFade.Stop(); $NavFade.Start() } })

$nav.FindName('NavBack').Add_Click({ Invoke-NavBack })
$nav.FindName('NavHome').Add_Click({ Invoke-NavHome })
$nav.FindName('NavRecent').Add_Click({ Invoke-NavRecent })
$nav.FindName('NavKbd').Add_Click({ Switch-Keyboard })
$nav.FindName('NavCC').Add_Click({ Switch-CC })

# Chừa chỗ cho thanh điều hướng để không che nội dung launcher.
if ($NavEnabled) {
    switch ($NavPos) {
        'left'   { $ui.MainArea.Margin = '104,6,28,18'; $ui.SwitchDock.Margin = '112,24,40,24'; $ui.AppsDock.Margin = '112,24,40,24' }
        'bottom' { $ui.MainArea.Margin = '28,6,28,96';  $ui.SwitchDock.Margin = '40,24,40,100'; $ui.AppsDock.Margin = '40,24,40,100' }
        default  { $ui.MainArea.Margin = '28,6,104,18'; $ui.SwitchDock.Margin = '40,24,112,24'; $ui.AppsDock.Margin = '40,24,112,24' }
    }
}

# ---------------------------------------------------------------- Chạm 2 lần
# Hai lần chạm cách nhau dưới 0,45 giây và gần nhau -> true. $key tách riêng từng màn hình.
$script:LastTap = @{}
function Test-DoubleTap([string]$key, [System.Windows.Point]$p) {
    $now = [Environment]::TickCount
    $prev = $script:LastTap[$key]
    $script:LastTap[$key] = @{ T = $now; P = $p }
    if ($prev -and ($now - $prev.T) -lt 450 -and ([math]::Abs($p.X - $prev.P.X) + [math]::Abs($p.Y - $prev.P.Y)) -lt 120) {
        $script:LastTap[$key] = $null
        return $true
    }
    return $false
}

# ---------------------------------------------------------------- Vạch "về trang chủ" (vuốt lên, như iPhone/iPad)
$HomeGesture = $cfg.homeGesture -ne $false
$homeBarXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Touch Launcher Home Bar" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize" Width="360" Height="30"
        Stylus.IsPressAndHoldEnabled="False" Stylus.IsFlicksEnabled="False" Stylus.IsTapFeedbackEnabled="False">
  <Grid x:Name="HB" Background="#01000000">
    <Border x:Name="HBPill" Width="150" Height="6" CornerRadius="3" Background="#E6FFFFFF" BorderBrush="#59000000" BorderThickness="1"
            VerticalAlignment="Bottom" Margin="0,0,0,10">
      <Border.RenderTransform><TranslateTransform x:Name="HBShift"/></Border.RenderTransform>
    </Border>
  </Grid>
</Window>
'@
$homeBar = [Windows.Markup.XamlReader]::Parse($homeBarXaml)
$homeBar.Add_SourceInitialized({ [TouchLauncher.Native]::MakeNoActivate((New-Object System.Windows.Interop.WindowInteropHelper $homeBar).Handle) })
$HB = $homeBar.FindName('HB'); $HBShift = $homeBar.FindName('HBShift')

function Set-HomeBarPosition {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $homeBar.Left = $wa.Left + ($wa.Width - $homeBar.Width) / 2
    $homeBar.Top = $wa.Bottom - $homeBar.Height
}
function Show-HomeBar { if ($HomeGesture -and -not $homeBar.IsVisible) { Set-HomeBarPosition; $homeBar.Show() } }

# Vuốt lên > 40 điểm ảnh -> về trang chủ. Vạch nhích lên theo ngón tay để thấy phản hồi.
$script:HbStart = $null
$HB.Add_MouseLeftButtonDown({ param($s, $e)
    $script:HbStart = $homeBar.PointToScreen($e.GetPosition($homeBar)).Y
    $script:HbFired = $false
    [void]$HB.CaptureMouse() })
$HB.Add_MouseMove({ param($s, $e)
    if ($null -eq $script:HbStart) { return }
    $dy = ($script:HbStart - $homeBar.PointToScreen($e.GetPosition($homeBar)).Y) / (Get-DpiScale)
    $HBShift.Y = -[math]::Max(0, [math]::Min(14, $dy * 0.35))
    if ($dy -gt 40 -and -not $script:HbFired) { $script:HbFired = $true; Invoke-NavHome } })
$HB.Add_MouseLeftButtonUp({
    $script:HbStart = $null
    $HB.ReleaseMouseCapture()
    $HBShift.Y = 0 })

# Chừa chỗ để vạch không đè lên Dock của launcher.
if ($HomeGesture) {
    $m = $ui.MainArea.Margin
    $ui.MainArea.Margin = New-Object System.Windows.Thickness ($m.Left, $m.Top, $m.Right, ($m.Bottom + 16))
}

# ---------------------------------------------------------------- Tắt màn hình — chạm 2 lần để mở
# Phủ màn đen lên mọi thứ rồi tắt màn hình. Chạm 1 lần (vô tình) màn hình có sáng lại nhưng vẫn đen,
# rồi tự tắt lại sau 8 giây; chạm 2 lần liên tiếp mới mở. Bấm phím bất kỳ cũng mở.
$blackXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Touch Launcher Screen Off" WindowStyle="None" ResizeMode="NoResize" Topmost="True" ShowInTaskbar="False"
        Background="Black" Cursor="None"
        Stylus.IsPressAndHoldEnabled="False" Stylus.IsFlicksEnabled="False" Stylus.IsTapFeedbackEnabled="False">
  <Grid Background="Black">
    <TextBlock x:Name="BsHint" Text="Chạm 2 lần để mở màn hình" FontFamily="Segoe UI" FontSize="22" Foreground="#80FFFFFF"
               HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,90" Opacity="0"/>
  </Grid>
</Window>
'@
$blackWin = [Windows.Markup.XamlReader]::Parse($blackXaml)
$BsHint = $blackWin.FindName('BsHint')

$BlackReoff = New-Object System.Windows.Threading.DispatcherTimer
$BlackReoff.Interval = [TimeSpan]::FromSeconds(8)
$BlackReoff.Add_Tick({ $BlackReoff.Stop(); $BsHint.Opacity = 0; if ($blackWin.IsVisible) { [TouchLauncher.Native]::MonitorOff() } })
$BlackOff = New-Object System.Windows.Threading.DispatcherTimer
$BlackOff.Interval = [TimeSpan]::FromMilliseconds(1200)   # chờ nhấc tay khỏi màn hình rồi mới tắt
$BlackOff.Add_Tick({ $BlackOff.Stop(); if ($blackWin.IsVisible) { [TouchLauncher.Native]::MonitorOff() } })

function Enter-ScreenOff {
    Hide-CC
    $blackWin.Left = [System.Windows.SystemParameters]::VirtualScreenLeft
    $blackWin.Top = [System.Windows.SystemParameters]::VirtualScreenTop
    $blackWin.Width = [System.Windows.SystemParameters]::VirtualScreenWidth
    $blackWin.Height = [System.Windows.SystemParameters]::VirtualScreenHeight
    $BsHint.Opacity = 0
    if ($NavEnabled) { $nav.Hide() }
    $homeBar.Hide()
    $blackWin.Show()
    [void]$blackWin.Activate()
    $BlackOff.Start()
}
function Exit-ScreenOff {
    $BlackOff.Stop(); $BlackReoff.Stop()
    if ($blackWin.IsVisible) { $blackWin.Hide() }
    if ($NavEnabled -and $ui.NightOverlay.Visibility -ne 'Visible') { $nav.Show() }
    if ($ui.NightOverlay.Visibility -ne 'Visible') { Show-HomeBar }
}
$blackWin.Add_PreviewMouseLeftButtonDown({ param($s, $e)
    $e.Handled = $true
    if (Test-DoubleTap 'black' $e.GetPosition($blackWin)) { Exit-ScreenOff; return }
    $BsHint.Opacity = 1
    $BlackReoff.Stop(); $BlackReoff.Start() })
$blackWin.Add_PreviewKeyDown({ param($s, $e) $e.Handled = $true; Exit-ScreenOff })
# Không cho đóng bằng Alt+F4 (chỉ ẩn).
$blackWin.Add_Closing({ param($s, $e) if (-not $script:AppClosing) { $e.Cancel = $true; Exit-ScreenOff } })

# ---------------------------------------------------------------- Chụp màn hình
# Ẩn các lớp nổi của launcher, chụp toàn bộ màn hình, lưu vào Pictures\Screenshots, chép vào clipboard,
# nháy trắng và hiện ảnh xem trước ở góc như iPhone (chạm để mở ảnh).
$ShotDir = if ($cfg.screenshotFolder) { [Environment]::ExpandEnvironmentVariables([string]$cfg.screenshotFolder) }
           else { Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots' }

$flashXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Touch Launcher Flash" WindowStyle="None" AllowsTransparency="True" Background="White" Opacity="0"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize" IsHitTestVisible="False"/>
'@
$flashWin = [Windows.Markup.XamlReader]::Parse($flashXaml)
$flashWin.Add_SourceInitialized({ [TouchLauncher.Native]::MakeNoActivate((New-Object System.Windows.Interop.WindowInteropHelper $flashWin).Handle) })

$previewXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Touch Launcher Screenshot" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        Stylus.IsPressAndHoldEnabled="False" Stylus.IsFlicksEnabled="False" Stylus.IsTapFeedbackEnabled="False">
  <Border x:Name="PvCard" Background="#F21C1C1E" CornerRadius="18" Padding="8" BorderBrush="#66FFFFFF" BorderThickness="1" Cursor="Hand">
    <StackPanel>
      <Border CornerRadius="12" ClipToBounds="True">
        <Image x:Name="PvImage" Width="240" Stretch="Uniform"/>
      </Border>
      <TextBlock x:Name="PvText" Foreground="White" FontFamily="Segoe UI" FontSize="14" Margin="4,8,4,2" TextWrapping="Wrap" MaxWidth="240"/>
    </StackPanel>
  </Border>
</Window>
'@
$previewWin = [Windows.Markup.XamlReader]::Parse($previewXaml)
$previewWin.Add_SourceInitialized({ [TouchLauncher.Native]::MakeNoActivate((New-Object System.Windows.Interop.WindowInteropHelper $previewWin).Handle) })
$PvImage = $previewWin.FindName('PvImage'); $PvText = $previewWin.FindName('PvText')
$script:LastShot = $null

$PreviewHide = New-Object System.Windows.Threading.DispatcherTimer
$PreviewHide.Interval = [TimeSpan]::FromSeconds(5)
$PreviewHide.Add_Tick({ $PreviewHide.Stop(); $previewWin.Hide(); $PvImage.Source = $null })
$previewWin.FindName('PvCard').Add_MouseLeftButtonUp({
    $PreviewHide.Stop(); $previewWin.Hide()
    if ($script:LastShot -and (Test-Path $script:LastShot)) { Start-Process $script:LastShot }
})

function Save-ScreenShot {
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $vs.Width, $vs.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($vs.Left, $vs.Top, 0, 0, $bmp.Size) } finally { $g.Dispose() }
    [void](New-Item -ItemType Directory -Force -Path $ShotDir)
    $path = Join-Path $ShotDir ('Ảnh chụp màn hình {0:yyyy-MM-dd HHmmss}.png' -f (Get-Date))
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $path
}

# Bước 1: ẩn các lớp nổi; bước 2 (sau 350 ms, khi màn hình đã vẽ lại): chụp.
$script:ShotRestore = $null
$ShotTimer = New-Object System.Windows.Threading.DispatcherTimer
$ShotTimer.Interval = [TimeSpan]::FromMilliseconds(350)
$ShotTimer.Add_Tick({
    $ShotTimer.Stop()
    $path = $null
    try { $path = Save-ScreenShot } catch { Show-CcToast "Không chụp được màn hình: $($_.Exception.Message)" }
    foreach ($w in $script:ShotRestore) { $w.Show() }
    if (-not $path) { return }
    $script:LastShot = $path

    $img = New-Object System.Windows.Media.Imaging.BitmapImage
    $img.BeginInit(); $img.UriSource = [Uri]$path; $img.DecodePixelWidth = 480; $img.CacheOption = 'OnLoad'; $img.EndInit(); $img.Freeze()
    try {
        $full = New-Object System.Windows.Media.Imaging.BitmapImage
        $full.BeginInit(); $full.UriSource = [Uri]$path; $full.CacheOption = 'OnLoad'; $full.EndInit(); $full.Freeze()
        [System.Windows.Clipboard]::SetImage($full)
    } catch {}

    # Nháy trắng toàn màn hình.
    $flashWin.Left = [System.Windows.SystemParameters]::VirtualScreenLeft; $flashWin.Top = [System.Windows.SystemParameters]::VirtualScreenTop
    $flashWin.Width = [System.Windows.SystemParameters]::VirtualScreenWidth; $flashWin.Height = [System.Windows.SystemParameters]::VirtualScreenHeight
    $flashWin.Show()
    $flashWin.BeginAnimation([System.Windows.Window]::OpacityProperty,
        (New-Object System.Windows.Media.Animation.DoubleAnimation(0.85, 0, (New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(320))))))

    # Ảnh xem trước ở góc trái dưới.
    $PvImage.Source = $img
    $PvText.Text = "Đã lưu vào $([IO.Path]::GetFileName($ShotDir)) và chép vào clipboard · chạm để mở"
    $wa = [System.Windows.SystemParameters]::WorkArea
    $previewWin.Show()
    $previewWin.UpdateLayout()
    $previewWin.Left = $wa.Left + 20
    $previewWin.Top = $wa.Bottom - $previewWin.ActualHeight - 40
    $PreviewHide.Stop(); $PreviewHide.Start()
})
$FlashHide = New-Object System.Windows.Threading.DispatcherTimer
$FlashHide.Interval = [TimeSpan]::FromMilliseconds(400)
$flashWin.Add_IsVisibleChanged({ if ($flashWin.IsVisible) { $FlashHide.Stop(); $FlashHide.Start() } })
$FlashHide.Add_Tick({ $FlashHide.Stop(); $flashWin.Hide() })

function Start-ScreenShot {
    Hide-CC
    $previewWin.Hide()
    $script:ShotRestore = @($nav, $homeBar | Where-Object { $_.IsVisible })
    foreach ($w in $script:ShotRestore) { $w.Hide() }
    $ShotTimer.Stop(); $ShotTimer.Start()
}
# Chụp một vùng: công cụ cắt vùng có sẵn của Windows (ảnh vào clipboard).
function Start-ScreenClip { Hide-CC; try { Start-Process 'ms-screenclip:' } catch { Show-Toast 'Không mở được công cụ cắt vùng của Windows.' } }

# ---------------------------------------------------------------- Trung tâm điều khiển (nổi trên mọi app)
$ccXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Touch Launcher Control Center" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        Foreground="#FFFFFF" FontFamily="Segoe UI Variable Text, Segoe UI"
        Stylus.IsPressAndHoldEnabled="False" Stylus.IsFlicksEnabled="False" Stylus.IsTapFeedbackEnabled="False">
  <Window.Resources>
    <Style x:Key="CC" TargetType="Button">
      <Setter Property="Width" Value="98"/>
      <Setter Property="Height" Value="98"/>
      <Setter Property="Margin" Value="5"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="#3A3A3C"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="26">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="B" Property="Opacity" Value="0.6"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border Background="#F21C1C1E" CornerRadius="36" Padding="14" BorderBrush="#40FFFFFF" BorderThickness="1">
    <StackPanel Width="432">
      <DockPanel Margin="10,4,10,10">
        <TextBlock x:Name="CcBattery" DockPanel.Dock="Right" FontSize="15" Foreground="#CCFFFFFF" VerticalAlignment="Center"/>
        <TextBlock Text="Trung tâm điều khiển" FontSize="18" FontWeight="SemiBold"/>
      </DockPanel>
      <WrapPanel x:Name="CcGrid"/>
    </StackPanel>
  </Border>
</Window>
'@

$ccWin = [Windows.Markup.XamlReader]::Parse($ccXaml)
$ccWin.Add_SourceInitialized({ [TouchLauncher.Native]::MakeNoActivate((New-Object System.Windows.Interop.WindowInteropHelper $ccWin).Handle) })
$CcBattery = $ccWin.FindName('CcBattery')
$CcGrid    = $ccWin.FindName('CcGrid')
$cc = @{}

# Mỗi nút: tên, glyph, nhãn, hành động. Nút cần bảng lớn sẽ mở launcher.
$ccDefs = @(
    @{ N = 'Prev';      G = 0xE892; L = 'Bài trước';       A = { [TouchLauncher.Native]::Key($VK.Prev) } }
    @{ N = 'Play';      G = 0xE768; L = 'Phát / Dừng';     A = { [TouchLauncher.Native]::Key($VK.Play) } }
    @{ N = 'Next';      G = 0xE893; L = 'Bài sau';         A = { [TouchLauncher.Native]::Key($VK.Next) } }
    @{ N = 'Mute';      G = 0xE74F; L = 'Tắt tiếng';       A = { [TouchLauncher.Native]::Key($VK.Mute) } }
    @{ N = 'VolDown';   G = 0xE993; L = 'Nhỏ hơn';         A = { Send-Volume $VK.VolDown } }
    @{ N = 'VolUp';     G = 0xE995; L = 'To hơn';          A = { Send-Volume $VK.VolUp } }
    @{ N = 'BriDown';   G = 0xEC8A; L = 'Tối hơn';         A = { Set-Brightness ($script:Bri - 10) } }
    @{ N = 'BriUp';     G = 0xE706; L = 'Sáng';            A = { Set-Brightness ($script:Bri + 10) } }
    @{ N = 'Saver';     G = 0xE83F; L = 'Tiết kiệm pin';   A = { Set-Saver (-not $script:SaverOn) } }
    @{ N = 'Kbd';       G = 0xE765; L = 'Bàn phím';        A = { Switch-Keyboard } }
    @{ N = 'AutoKbd';   G = 0xE961; L = 'Tự hiện bàn phím'; A = {
            if (Set-AutoKeyboard (-not $script:AutoKbd)) {
                $script:AutoKbd = -not $script:AutoKbd
                Show-CcToast $(if ($script:AutoKbd) { 'Bàn phím cảm ứng sẽ tự hiện khi chạm vào ô nhập chữ.' } else { 'Đã tắt tự hiện bàn phím.' })
            } } }
    @{ N = 'ScreenOff'; G = 0xE708; L = 'Tắt màn hình';    A = { Enter-ScreenOff } }
    @{ N = 'Pip';       G = 0xE8A7; L = 'PiP YouTube';     A = { Hide-CC; Switch-Pip } }
    @{ N = 'Sleep';     G = 0xE916; L = 'Hẹn giờ tắt';     A = { Switch-SleepTimer } }
    @{ N = 'Split';     G = 0xE90C; L = 'Chia đôi';        A = { Hide-CC; Start-SplitView } }
    @{ N = 'Night';     G = 0xE823; L = 'Đồng hồ';         A = { Hide-CC; Show-Launcher; Enter-Night $false } }
    @{ N = 'Shot';      G = 0xE722; L = 'Chụp màn hình';   A = { Start-ScreenShot } }
    @{ N = 'Clip';      G = 0xE8C6; L = 'Chụp một vùng';   A = { Start-ScreenClip } }
    @{ N = 'NavPin';    G = 0xE718; L = 'Ghim thanh điều hướng'; A = { Switch-NavPin } }
    @{ N = 'Notify';    G = 0xEA8F; L = 'Thông báo';       A = { Hide-CC; Open-NotificationCenter } }
    @{ N = 'Clean';     G = 0xE74D; L = 'Dọn dẹp';         A = { Hide-CC; Hide-Overlays; Show-Launcher; Show-CleanPanel } }
    @{ N = 'Power';     G = 0xE7E8; L = 'Nguồn';           A = { Hide-CC; Hide-Overlays; Show-Launcher; Show-PowerMenu } }
)
foreach ($d in $ccDefs) {
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $ccWin.FindResource('CC')
    $sp = New-Object System.Windows.Controls.StackPanel
    $ic = New-Object System.Windows.Controls.TextBlock
    $ic.FontFamily = $IconFont; $ic.FontSize = 26; $ic.Text = [string][char]$d.G; $ic.HorizontalAlignment = 'Center'
    $lb = New-Object System.Windows.Controls.TextBlock
    $lb.Text = $d.L; $lb.FontSize = 12; $lb.Margin = '4,8,4,0'; $lb.TextAlignment = 'Center'; $lb.TextWrapping = 'Wrap'; $lb.MaxWidth = 90
    [void]$sp.Children.Add($ic); [void]$sp.Children.Add($lb)
    $b.Content = $sp
    $b.Tag = $d
    $b.Add_Click({
        try { & $this.Tag.A } catch { Show-CcToast "Lỗi: $($_.Exception.Message)" }
        Update-CC
        $CcHide.Stop(); $CcHide.Start()
    })
    [void]$CcGrid.Children.Add($b)
    $cc[$d.N] = @{ Button = $b; Label = $lb }
}

if (-not $NavEnabled) { $cc.NavPin.Button.Visibility = 'Collapsed' }

# Thông báo khi launcher đang ẩn: hiện ngay trên tiêu đề Trung tâm điều khiển.
function Show-CcToast([string]$msg) { if ($ccWin.IsVisible) { $CcBattery.Text = $msg } else { Show-Toast $msg } }

function Update-CC {
    $b = Get-Battery
    $CcBattery.Text = if ($b) { "Pin $($b.Pct)%" + $(if ($b.Charging) { ' · đang sạc' } else { '' }) } else { '' }
    $cc.Saver.Button.Background   = ConvertTo-Brush $(if ($script:SaverOn) { '#30D158' } else { '#3A3A3C' })
    $cc.AutoKbd.Button.Background = ConvertTo-Brush $(if ($script:AutoKbd) { '#0A84FF' } else { '#3A3A3C' })
    $cc.Pip.Button.Background     = ConvertTo-Brush $(if ($script:Pip) { '#0A84FF' } else { '#3A3A3C' })
    $cc.BriUp.Label.Text = if ($null -ne $script:Bri) { "Sáng $($script:Bri)%" } else { 'Độ sáng' }
    $left = Get-SleepMinutesLeft
    $cc.Sleep.Label.Text = if ($left -gt 0) { "Tắt sau $left phút" } else { 'Hẹn giờ tắt' }
    $cc.Sleep.Button.Background = ConvertTo-Brush $(if ($left -gt 0) { '#FF9F0A' } else { '#3A3A3C' })
    $cc.Split.Button.Background = ConvertTo-Brush $(if ($script:Split) { '#0A84FF' } else { '#3A3A3C' })
    $cc.NavPin.Button.Background = ConvertTo-Brush $(if (-not $script:NavAutoHide) { '#0A84FF' } else { '#3A3A3C' })
}

# Tự đóng sau 8 giây không chạm.
$CcHide = New-Object System.Windows.Threading.DispatcherTimer
$CcHide.Interval = [TimeSpan]::FromSeconds(8)
$CcHide.Add_Tick({ Hide-CC })

function Hide-CC { $CcHide.Stop(); if ($ccWin.IsVisible) { $ccWin.Hide() } }
function Switch-CC {
    if ($ccWin.IsVisible) { Hide-CC; return }
    Initialize-Brightness
    Update-NowPlaying
    Update-CC
    $ccWin.Show()
    $ccWin.UpdateLayout()
    $wa = [System.Windows.SystemParameters]::WorkArea
    $navW = if ($NavEnabled -and $NavPos -eq 'right') { $nav.ActualWidth + 12 } else { 0 }
    $ccWin.Left = $wa.Right - $ccWin.ActualWidth - $navW - 8
    $ccWin.Top  = if ($NavPos -eq 'right' -or -not $NavEnabled) { $wa.Top + 10 } else { $wa.Top + ($wa.Height - $ccWin.ActualHeight) / 2 }
    $CcHide.Stop(); $CcHide.Start()
}
$ui.BtnStatus.Add_Click({ Switch-CC })

# Xoay màn hình / đổi độ phân giải -> đặt lại vị trí.
[System.Windows.SystemParameters]::add_StaticPropertyChanged({ param($s, $e) if ($e.PropertyName -eq 'WorkArea') { Set-NavPosition; Set-HomeBarPosition; Hide-CC } })

# ---------------------------------------------------------------- Việc nền (mạng, tải tệp) không làm đứng giao diện
# Chạy scriptblock trong runspace riêng; khi xong gọi $done với kết quả trên luồng giao diện.
$script:Jobs = New-Object System.Collections.ArrayList
$JobTimer = New-Object System.Windows.Threading.DispatcherTimer
$JobTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$JobTimer.Add_Tick({
    foreach ($j in @($script:Jobs)) {
        if (-not $j.Handle.IsCompleted) { continue }
        $res = $null
        try { $res = @($j.PS.EndInvoke($j.Handle))[0] } catch { $res = @{ Error = $_.Exception.Message } }
        $j.PS.Dispose()
        [void]$script:Jobs.Remove($j)
        try { & $j.Done $res } catch { Show-Toast "Lỗi: $($_.Exception.Message)" }
    }
    if ($script:Jobs.Count -eq 0) { $JobTimer.Stop() }
})
function Start-BgJob([scriptblock]$work, [object[]]$arguments, [scriptblock]$done) {
    $ps = [powershell]::Create()
    [void]$ps.AddScript($work.ToString())
    foreach ($a in $arguments) { [void]$ps.AddArgument($a) }
    [void]$script:Jobs.Add(@{ PS = $ps; Handle = $ps.BeginInvoke(); Done = $done })
    $JobTimer.Start()
}

# ---------------------------------------------------------------- Đang phát (bộ điều khiển media chung của Windows)
$script:Media = $null
$script:NowKey = $null
function Initialize-Media {
    if ($null -ne $script:Media) { return [bool]$script:Media.Ok }
    $script:Media = @{ Ok = $false }
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        $M = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
        $script:Media = @{
            Ok     = $true
            AsTask = $asTask
            Props  = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
            Stream = [Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]
        }
        $script:Media.Mgr = Wait-WinRT ($M::RequestAsync()) $M
        if (-not $script:Media.Mgr) { $script:Media.Ok = $false }
    } catch { $script:Media = @{ Ok = $false } }
    return [bool]$script:Media.Ok
}
# Chờ một thao tác WinRT (tối đa 2 giây — không treo giao diện lâu).
function Wait-WinRT($op, [type]$type) {
    $task = $script:Media.AsTask.MakeGenericMethod($type).Invoke($null, @($op))
    if ($task.Wait(2000)) { return $task.Result }
    return $null
}

# Tên trang web thường dính đuôi "- NhacCuaTui", "| lyric"… — bỏ cho gọn.
function Format-MediaText([string]$title, [string]$artist) {
    $t = ($title -split ' \| ')[0]
    $t = $t -replace '\s+-\s+(NhacCuaTui|YouTube Music|YouTube|Zing MP3|Spotify)\s*$', '' -replace '\s+-\s+mp3 download\s*$', ''
    if (-not $artist -and $t -match '^(.+?)\s+-\s+(.+)$') { $t = $Matches[1]; $artist = $Matches[2] }
    return @($t.Trim(), [string]$artist)
}
function Get-SourceName([string]$appId) {
    if ($appId -match '^(Chrome|MSEdge)\.(www\.)?([^_/]+)') { return $Matches[3] }
    if ($appId -match '([^\\!]+?)(\.exe)?$') { return $Matches[1] }
    return $appId
}

function Update-NowPlaying {
    if (-not (Initialize-Media)) { $ui.NowCard.Visibility = 'Collapsed'; return }
    try { $s = $script:Media.Mgr.GetCurrentSession() } catch { $s = $null }
    if (-not $s) { $ui.NowCard.Visibility = 'Collapsed'; $script:NowKey = $null; $script:NowText = $null; return }
    $p = Wait-WinRT ($s.TryGetMediaPropertiesAsync()) $script:Media.Props
    if (-not $p -or -not $p.Title) { $ui.NowCard.Visibility = 'Collapsed'; return }
    $playing = "$($s.GetPlaybackInfo().PlaybackStatus)" -eq 'Playing'
    $txt = Format-MediaText $p.Title $p.Artist
    $ui.NowTitle.Text = $txt[0]
    $ui.NowArtist.Text = $txt[1]
    $ui.NowSource.Text = (Get-SourceName $s.SourceAppUserModelId).ToUpper()
    $ui.NowPlayIcon.Text = [string][char]$(if ($playing) { 0xE769 } else { 0xE768 })
    $script:NowText = $txt[0]
    $ui.NowCard.Visibility = 'Visible'
    # Ảnh bìa chỉ đọc lại khi đổi bài.
    $key = "$($s.SourceAppUserModelId)|$($p.Title)"
    if ($key -ne $script:NowKey) {
        $script:NowKey = $key
        $ui.NowArt.Source = $null
        if ($p.Thumbnail) {
            try {
                $ws = Wait-WinRT ($p.Thumbnail.OpenReadAsync()) $script:Media.Stream
                if ($ws) {
                    $ms = New-Object System.IO.MemoryStream
                    [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($ws).CopyTo($ms)
                    $ms.Position = 0
                    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
                    $bi.BeginInit(); $bi.StreamSource = $ms; $bi.DecodePixelWidth = 160; $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
                    $ui.NowArt.Source = $bi
                }
            } catch {}
        }
    }
}
$ui.NowArt.Clip = New-Object System.Windows.Media.RectangleGeometry ((New-Object System.Windows.Rect 0, 0, 80, 80), 18, 18)

function Invoke-MediaCommand([string]$cmd) {
    if (Initialize-Media) {
        $s = $script:Media.Mgr.GetCurrentSession()
        if ($s) {
            $op = switch ($cmd) { 'prev' { $s.TrySkipPreviousAsync() } 'next' { $s.TrySkipNextAsync() } default { $s.TryTogglePlayPauseAsync() } }
            [void](Wait-WinRT $op ([bool]))
            Start-Sleep -Milliseconds 250
            Update-NowPlaying
            return
        }
    }
    [TouchLauncher.Native]::Key($(switch ($cmd) { 'prev' { $VK.Prev } 'next' { $VK.Next } default { $VK.Play } }))
}
$ui.BtnNowPrev.Add_Click({ Invoke-MediaCommand 'prev' })
$ui.BtnNowPlay.Add_Click({ Invoke-MediaCommand 'play' })
$ui.BtnNowNext.Add_Click({ Invoke-MediaCommand 'next' })

# Cập nhật 3 giây/lần, chỉ khi launcher đang hiện (bật/tắt theo Activated/Deactivated).
$NowTimer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background)
$NowTimer.Interval = [TimeSpan]::FromSeconds(3)
$NowTimer.Add_Tick({ Update-NowPlaying })

# Dừng mọi nguồn đang phát (dùng cho hẹn giờ). Không dùng phím Phát/Dừng vì nó có thể bật nhạc lên lại.
function Stop-AllMedia {
    if (Initialize-Media) {
        foreach ($s in @($script:Media.Mgr.GetSessions())) {
            if ("$($s.GetPlaybackInfo().PlaybackStatus)" -eq 'Playing') { [void](Wait-WinRT ($s.TryPauseAsync()) ([bool])) }
        }
        return
    }
    [TouchLauncher.Native]::Key(0xB2)   # VK_MEDIA_STOP
}

# ---------------------------------------------------------------- Hẹn giờ tắt nhạc
$script:SleepAt = $null
$SleepSteps = 0, 15, 30, 60
$SleepTimer = New-Object System.Windows.Threading.DispatcherTimer
$SleepTimer.Interval = [TimeSpan]::FromSeconds(20)
$SleepTimer.Add_Tick({
    if (-not $script:SleepAt) { $SleepTimer.Stop(); return }
    if ((Get-Date) -ge $script:SleepAt) {
        $script:SleepAt = $null
        $SleepTimer.Stop()
        Stop-AllMedia
        Exit-Night
        Enter-ScreenOff
    }
})
function Get-SleepMinutesLeft { if ($script:SleepAt) { [int][math]::Ceiling(($script:SleepAt - (Get-Date)).TotalMinutes) } else { 0 } }
# Bấm nút: Tắt -> 15 -> 30 -> 60 phút -> Tắt.
function Switch-SleepTimer {
    $left = Get-SleepMinutesLeft
    $next = ($SleepSteps | Where-Object { $_ -gt $left } | Select-Object -First 1)
    if (-not $next) { $next = 0 }
    if ($next -eq 0) {
        $script:SleepAt = $null; $SleepTimer.Stop()
        Show-CcToast 'Đã tắt hẹn giờ.'
    } else {
        $script:SleepAt = (Get-Date).AddMinutes($next); $SleepTimer.Start()
        Show-CcToast "Nhạc sẽ dừng và màn hình tắt sau $next phút."
    }
}

# ---------------------------------------------------------------- Chia đôi màn hình
$splitXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Touch Launcher Split" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False" ResizeMode="NoResize" Width="40"
        Stylus.IsPressAndHoldEnabled="False" Stylus.IsFlicksEnabled="False" Stylus.IsTapFeedbackEnabled="False">
  <Grid x:Name="Bar" Background="#01000000" Cursor="SizeWE">
    <Border Width="8" Height="96" CornerRadius="4" Background="#E6FFFFFF" VerticalAlignment="Center"/>
    <Button x:Name="SplitClose" VerticalAlignment="Top" Margin="0,12,0,0" Width="40" Height="40" Focusable="False" Cursor="Hand">
      <Button.Template>
        <ControlTemplate TargetType="Button">
          <Border CornerRadius="20" Background="#E61C1C1E" BorderBrush="#66FFFFFF" BorderThickness="1">
            <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Text="&#xE711;" Foreground="White"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
        </ControlTemplate>
      </Button.Template>
    </Button>
  </Grid>
</Window>
'@
$splitWin = [Windows.Markup.XamlReader]::Parse($splitXaml)
$splitWin.Add_SourceInitialized({ [TouchLauncher.Native]::MakeNoActivate((New-Object System.Windows.Interop.WindowInteropHelper $splitWin).Handle) })
$SplitBar = $splitWin.FindName('Bar')
$script:Split = $null

# Vùng làm việc (pixel thật), chừa chỗ thanh điều hướng.
function Get-SplitArea {
    $s = Get-DpiScale
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $l = $wa.Left; $r = $wa.Right
    if ($NavEnabled -and $NavPos -eq 'right') { $r -= [int](($nav.ActualWidth + 12) * $s) }
    if ($NavEnabled -and $NavPos -eq 'left')  { $l += [int](($nav.ActualWidth + 12) * $s) }
    $b = $wa.Bottom
    if ($NavEnabled -and $NavPos -eq 'bottom') { $b -= [int](($nav.ActualHeight + 12) * $s) }
    return @{ L = $l; T = $wa.Top; R = $r; B = $b; S = $s }
}

function Set-SplitLayout {
    $sp = $script:Split
    if (-not $sp) { return }
    $a = Get-SplitArea
    $gap = [int](8 * $a.S)
    $x = [int]($a.L + ($a.R - $a.L) * $sp.Ratio)
    foreach ($h in $sp.Left, $sp.Right) { if ([TouchLauncher.Native]::IsIconic($h) -or [TouchLauncher.Native]::IsZoomed($h)) { [TouchLauncher.Native]::Restore($h) } }
    [TouchLauncher.Native]::Place($sp.Left,  $false, $a.L, $a.T, $x - $a.L - $gap, $a.B - $a.T)
    [TouchLauncher.Native]::Place($sp.Right, $false, $x + $gap, $a.T, $a.R - $x - $gap, $a.B - $a.T)
    # Thanh chia (đơn vị DIP của WPF) nằm giữa hai cửa sổ.
    $splitWin.Height = ($a.B - $a.T) / $a.S
    $splitWin.Left = $x / $a.S - $splitWin.Width / 2
    $splitWin.Top = $a.T / $a.S
    if (-not $splitWin.IsVisible) { $splitWin.Show() }
}

function Start-SplitView {
    $wins = @([TouchLauncher.Native]::GetAppWindows($PID) | Select-Object -First 2)
    if ($wins.Count -lt 2) { Show-CcToast 'Cần mở ít nhất 2 app để chia đôi màn hình.'; return }
    Hide-Overlays
    $script:Split = @{ Left = $wins[0].Handle; Right = $wins[1].Handle; Ratio = 0.5 }
    $win.WindowState = 'Minimized'
    Set-SplitLayout
    [TouchLauncher.Native]::Activate($wins[0].Handle)
    $SplitGuard.Start()
}

function Stop-SplitView([bool]$maximize) {
    $sp = $script:Split
    $script:Split = $null
    $SplitGuard.Stop()
    if ($splitWin.IsVisible) { $splitWin.Hide() }
    if ($sp -and $maximize) {
        foreach ($h in $sp.Right, $sp.Left) { if ([TouchLauncher.Native]::IsWindow($h)) { [TouchLauncher.Native]::Maximize($h) } }
        if ([TouchLauncher.Native]::IsWindow($sp.Left)) { [TouchLauncher.Native]::Activate($sp.Left) }
    }
}

# Kéo thanh chia để đổi tỉ lệ (chuột hoặc ngón tay — cảm ứng được giả lập thành chuột).
$script:SplitDrag = $false
$SplitBar.Add_MouseLeftButtonDown({ param($s, $e)
    if ($e.OriginalSource -is [System.Windows.Controls.Button]) { return }
    $script:SplitDrag = $true; [void]$SplitBar.CaptureMouse(); $e.Handled = $true })
$SplitBar.Add_MouseMove({ param($s, $e)
    if (-not $script:SplitDrag) { return }
    $p = $splitWin.PointToScreen($e.GetPosition($splitWin))
    $a = Get-SplitArea
    $ratio = [math]::Max(0.25, [math]::Min(0.75, ($p.X - $a.L) / ($a.R - $a.L)))
    $splitWin.Left = ($a.L + ($a.R - $a.L) * $ratio) / $a.S - $splitWin.Width / 2
    $script:Split.Ratio = $ratio })
$SplitBar.Add_MouseLeftButtonUp({
    if (-not $script:SplitDrag) { return }
    $script:SplitDrag = $false; $SplitBar.ReleaseMouseCapture()
    Set-SplitLayout })
$splitWin.FindName('SplitClose').Add_Click({ Stop-SplitView $true })

# Một trong hai app bị đóng -> thoát chia đôi, app còn lại phóng to.
$SplitGuard = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background)
$SplitGuard.Interval = [TimeSpan]::FromSeconds(2)
$SplitGuard.Add_Tick({
    $sp = $script:Split
    if (-not $sp) { $SplitGuard.Stop(); return }
    if (-not [TouchLauncher.Native]::IsWindow($sp.Left) -or -not [TouchLauncher.Native]::IsWindow($sp.Right)) { Stop-SplitView $true }
})
$ui.BtnSplit.Add_Click({ Start-SplitView })

# ---------------------------------------------------------------- Đồng hồ đầu giường / khung ảnh
$NightCfg = $cfg.nightClock
$NightIdleMin = if ($NightCfg.idleMinutes) { [int]$NightCfg.idleMinutes } else { 5 }
$NightAuto = -not ($NightCfg -and $NightCfg.auto -eq $false)
$script:NightPhotos = $null
$script:NightIndex = 0
$script:NightTick = 0
$script:NightFront = $null

function Get-NightPhotos {
    if ($null -ne $script:NightPhotos) { return $script:NightPhotos }
    $dir = if ($cfg.photoFolder) { [Environment]::ExpandEnvironmentVariables([string]$cfg.photoFolder) } else { [Environment]::GetFolderPath('MyPictures') }
    $files = @()
    if ($dir -and (Test-Path $dir)) {
        $files = @(Get-ChildItem -Path $dir -Recurse -Depth 2 -File -Include *.jpg, *.jpeg, *.png -ErrorAction SilentlyContinue |
                   Where-Object { $_.Length -gt 30KB -and $_.FullName -notmatch '\\Screenshots\\' -and -not $_.FullName.StartsWith($ShotDir) } |
                   Select-Object -First 400 | ForEach-Object { $_.FullName })
    }
    $script:NightPhotos = @($files | Sort-Object { Get-Random })
    return $script:NightPhotos
}

function Show-NextPhoto {
    $photos = @(Get-NightPhotos)
    if ($photos.Count -eq 0) { return }
    $path = $photos[$script:NightIndex % $photos.Count]
    $script:NightIndex++
    try {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.UriSource = [Uri]$path; $bi.DecodePixelWidth = 1600; $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
    } catch { return }
    # Đảo hai lớp ảnh rồi làm mờ dần sang ảnh mới.
    $next = if ($script:NightFront -eq $ui.NightPhotoA) { $ui.NightPhotoB } else { $ui.NightPhotoA }
    $prev = $script:NightFront
    $next.Source = $bi
    $dur = New-Object System.Windows.Duration ([TimeSpan]::FromSeconds(1.5))
    $next.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(0, 1, $dur)))
    if ($prev) { $prev.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation(1, 0, $dur))) }
    $script:NightFront = $next
}

function Update-NightClock {
    $now = Get-Date
    $ui.NightTime.Text = $now.ToString('HH:mm')
    $ui.NightDate.Text = $Vi.TextInfo.ToTitleCase($now.ToString('dddd, dd MMMM', $Vi))
    $ui.NightLunar.Text = Get-LunarText $now
    $b = Get-Battery
    $info = if ($b) { "Pin $($b.Pct)%" + $(if ($b.Charging) { ' · đang sạc' } else { '' }) } else { '' }
    if ($script:NowText) { $info += "   ♪ $($script:NowText)" }
    $ui.NightInfo.Text = $info
}

$NightTimer = New-Object System.Windows.Threading.DispatcherTimer
$NightTimer.Interval = [TimeSpan]::FromSeconds(10)
$NightTimer.Add_Tick({
    $script:NightTick++
    Update-NightClock
    if ($script:NightTick % 2 -eq 0) { Show-NextPhoto }                       # ảnh mới mỗi 20 giây
    if ($script:NightTick % 6 -eq 0) {                                        # dời đồng hồ mỗi phút, tránh lưu ảnh trên màn hình
        $ui.NightClock.Margin = New-Object System.Windows.Thickness ((60 + (Get-Random -Maximum 60)), 0, 0, (50 + (Get-Random -Maximum 50)))
    }
    $b = Get-Battery
    if ($b -and -not $b.Charging -and $script:NightAutoEntered) { Exit-Night }  # rút sạc -> thoát để giữ pin
})

function Enter-Night([bool]$auto) {
    if ($ui.NightOverlay.Visibility -eq 'Visible') { return }
    Hide-Overlays
    $script:NightAutoEntered = $auto
    $script:NightTick = 0
    Update-NightClock
    $ui.NightOverlay.Visibility = 'Visible'
    Show-NextPhoto
    $NightTimer.Start()
    if ($NavEnabled) { $nav.Hide() }
    $homeBar.Hide()
    $b = Get-Battery
    if (-not $b -or $b.Charging) { [TouchLauncher.Native]::KeepDisplayOn($true) }
}
function Exit-Night {
    if ($ui.NightOverlay.Visibility -ne 'Visible') { return }
    $NightTimer.Stop()
    [TouchLauncher.Native]::KeepDisplayOn($false)
    $ui.NightOverlay.Visibility = 'Collapsed'
    if ($NavEnabled -and -not $nav.IsVisible) { $nav.Show() }
    Show-HomeBar
    foreach ($img in $ui.NightPhotoA, $ui.NightPhotoB) {
        $img.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null); $img.Opacity = 0; $img.Source = $null
    }
    $script:NightFront = $null
    $script:NightPhotos = $null   # đọc lại thư mục ảnh lần sau (có thể đã thêm ảnh mới)
}
# Chạm 2 lần để thoát (tránh chạm nhầm lúc ngủ); chạm 1 lần chỉ hiện lời nhắc.
$ui.NightOverlay.Add_PreviewMouseLeftButtonDown({ param($s, $e)
    $e.Handled = $true
    if (Test-DoubleTap 'night' $e.GetPosition($win)) { Exit-Night } else { Show-Toast 'Chạm 2 lần để thoát đồng hồ.' } })

# Tự bật khi: đang sạc + launcher đang ở trang chủ + không chạm máy N phút.
$IdleTimer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background)
$IdleTimer.Interval = [TimeSpan]::FromSeconds(60)
$IdleTimer.Add_Tick({
    if (-not $NightAuto -or $ui.NightOverlay.Visibility -eq 'Visible') { return }
    $b = Get-Battery
    if ($b -and -not $b.Charging) { return }
    if (-not (Test-LauncherForeground)) { return }
    if (@($ui.Overlay, $ui.PowerOverlay, $ui.AddOverlay, $ui.AppsOverlay, $ui.SwitchOverlay | Where-Object { $_.Visibility -eq 'Visible' }).Count) { return }
    if ([TouchLauncher.Native]::IdleSeconds() -ge $NightIdleMin * 60) { Enter-Night $true }
})

# ---------------------------------------------------------------- Thêm app web bằng địa chỉ
$script:AddInfo = $null
$script:AddGroup = 'Của tôi'

# Chạy nền: tải trang lấy tên (og:site_name / application-name / title) và icon tốt nhất (apple-touch-icon > icon > favicon.ico).
$FetchSiteWork = {
    param([string]$url, [string]$iconDir)
    Add-Type -AssemblyName System.Net.Http, System.Drawing
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $res = @{ Url = $url; Name = $null; IconPath = $null; Error = $null }
    $http = New-Object System.Net.Http.HttpClient
    $http.Timeout = [TimeSpan]::FromSeconds(10)
    $http.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36 TouchLauncher')
    $html = ''; $base = [Uri]$url
    try {
        $resp = $http.GetAsync($url).Result
        $base = $resp.RequestMessage.RequestUri
        $html = $resp.Content.ReadAsStringAsync().Result
    } catch { $res.Error = 'Không mở được trang (kiểm tra địa chỉ hoặc mạng).' }

    function Get-Meta([string]$key) {
        foreach ($p in @("<meta[^>]+(?:property|name)=[""']$key[""'][^>]*content=[""']([^""']+)", "<meta[^>]+content=[""']([^""']+)[""'][^>]*(?:property|name)=[""']$key[""']")) {
            $m = [regex]::Match($html, $p, 'IgnoreCase'); if ($m.Success) { return [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value).Trim() }
        }
    }
    $name = Get-Meta 'og:site_name'
    if (-not $name) { $name = Get-Meta 'application-name' }
    if (-not $name) {
        $m = [regex]::Match($html, '<title[^>]*>([^<]+)</title>', 'IgnoreCase')
        if ($m.Success) { $name = ([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value) -split '\s+[-|–·:]\s+')[0].Trim() }
    }
    if (-not $name) { $name = ($base.Host -replace '^(www|m|web|chat)\.', '' -split '\.')[0] }
    if ($name.Length -gt 22) { $name = $name.Substring(0, 22).Trim() }
    $res.Name = $name

    # Ứng viên icon, tốt nhất trước.
    $cands = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($html, '<link[^>]+>', 'IgnoreCase')) {
        $tag = $m.Value
        $rel = [regex]::Match($tag, 'rel=["'']([^"'']+)', 'IgnoreCase').Groups[1].Value.ToLower()
        $href = [regex]::Match($tag, 'href=["'']([^"'']+)', 'IgnoreCase').Groups[1].Value
        if (-not $href -or $href -match '\.svg($|\?)' -or $rel -notmatch 'icon') { continue }
        try { $abs = (New-Object Uri($base, [System.Net.WebUtility]::HtmlDecode($href))).AbsoluteUri } catch { continue }
        if ($rel -match 'apple-touch-icon') { $cands.Insert(0, $abs) } else { $cands.Add($abs) }
    }
    $cands.Add("$($base.Scheme)://$($base.Host)/favicon.ico")
    $cands.Add("https://www.google.com/s2/favicons?domain=$($base.Host)&sz=128")   # dự phòng cuối cùng

    [void](New-Item -ItemType Directory -Force -Path $iconDir)
    $out = Join-Path $iconDir (($base.Host -replace '[^a-zA-Z0-9.-]', '_') + '.png')
    $best = $null; $bestSize = 0
    foreach ($c in $cands) {
        try {
            $bytes = $http.GetByteArrayAsync($c).Result
            $ms = New-Object System.IO.MemoryStream (, $bytes)
            $bmp = $null
            if ($bytes.Length -ge 4 -and $bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 1) {
                $bmp = (New-Object System.Drawing.Icon($ms, 256, 256)).ToBitmap()
            } else {
                $bmp = New-Object System.Drawing.Bitmap $ms
            }
            if ($bmp.Width -gt $bestSize) { if ($best) { $best.Dispose() }; $best = $bmp; $bestSize = $bmp.Width } else { $bmp.Dispose() }
            if ($bestSize -ge 96) { break }
        } catch {}
    }
    if ($best) { $best.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $best.Dispose(); $res.IconPath = $out }
    $http.Dispose()
    return $res
}

# ---- Gmail theo tài khoản: mỗi email một icon, mở đúng hộp thư qua mail.google.com/mail/u/<email>/
$EmailPattern = '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
function Get-GmailTarget([string]$email) { "https://mail.google.com/mail/u/?authuser=$([Uri]::EscapeDataString($email.ToLower()))" }
# Đã có icon cho email này chưa (so theo email trong địa chỉ, kể cả dạng cũ /mail/u/<email>/).
function Test-GmailAdded([string]$email) {
    $e = $email.ToLower(); $enc = [Uri]::EscapeDataString($e)
    [bool](@($cfg.tiles | Where-Object { $t = ([string]$_.target).ToLower(); $t.Contains("authuser=$enc") -or $t.Contains("/mail/u/$e/") }).Count)
}

# Tài khoản Gmail đang mở trên máy (đọc từ tiêu đề cửa sổ "... - ten@gmail.com - Gmail").
function Get-OpenGmailAccounts {
    @([TouchLauncher.Native]::GetAppWindows($PID) | ForEach-Object {
        $m = [regex]::Match($_.Title, '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})\s+-\s+Gmail')
        if ($m.Success) { $m.Groups[1].Value.ToLower() } } | Select-Object -Unique)
}
# Tài khoản Google trong các hồ sơ Chrome (chỉ đọc email trên máy, không gửi đi đâu).
# Mỗi email lấy hồ sơ mà nó là tài khoản chính; nếu không có thì hồ sơ đầu tiên chứa nó.
function Get-ChromeGoogleAccounts {
    $ud = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    $ls = Join-Path $ud 'Local State'
    if ($BrowserName -ne 'chrome' -or -not (Test-Path $ls)) { return @() }
    $found = [ordered]@{}
    try {
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        $cache = $ser.DeserializeObject([IO.File]::ReadAllText($ls))['profile']['info_cache']
        $secondary = @()
        foreach ($dir in $cache.Keys) {
            $p = $cache[$dir]
            $main = if ($p.ContainsKey('user_name')) { ([string]$p['user_name']).ToLower() } else { '' }
            if ($main -and -not $found.Contains($main)) { $found[$main] = @{ Email = $main; Profile = $dir; ProfileName = [string]$p['name'] } }
            $pref = Join-Path $ud "$dir\Preferences"
            if (Test-Path $pref) {
                try {
                    $pr = $ser.DeserializeObject([IO.File]::ReadAllText($pref))
                    if ($pr.ContainsKey('account_info')) {
                        foreach ($a in $pr['account_info']) {
                            $e = ([string]$a['email']).ToLower()
                            if ($e) { $secondary += @{ Email = $e; Profile = $dir; ProfileName = [string]$p['name'] } }
                        }
                    }
                } catch {}
            }
        }
        foreach ($a in $secondary) { if (-not $found.Contains($a.Email)) { $found[$a.Email] = $a } }
    } catch {}
    return @($found.Values)
}

function New-GmailTile([string]$email, [string]$name, [string]$profileDir) {
    $email = $email.ToLower()
    if (-not $name) { $name = ($email -split '@')[0] }
    $base = $name; $i = 2
    while (Get-Tile $name) { $name = "$base $i"; $i++ }
    [pscustomobject]@{
        group = 'Tiện ích'; folder = 'Gmail'; profile = $profileDir; name = $name; icon = 'E715'; color = '#EA4335'; type = 'app'
        target = (Get-GmailTarget $email); match = ([regex]::Escape($email) + '\s+-\s+Gmail'); user = $true
    }
}

# Nhập mọi tài khoản Google chưa có thành icon Gmail (ghim ra trang chủ, gom vào thư mục Gmail).
function Import-GmailAccounts {
    $added = @()
    foreach ($a in Get-ChromeGoogleAccounts) {
        if (Test-GmailAdded $a.Email) { continue }
        $tile = New-GmailTile $a.Email $null $a.Profile
        $cfg.tiles = @(@($cfg.tiles) + $tile)
        $script:Pins = @($script:Pins) + $tile.name
        $added += $a.Email
    }
    if ($added.Count) {
        Save-UserApps; Save-Pins
        if ($null -ne $script:AppItems) { Load-Apps }
        Build-Home
    }
    return $added
}

function Update-AddSuggest {
    $ui.AddSuggest.Children.Clear()
    $chrome = @(Get-ChromeGoogleAccounts | Where-Object { -not (Test-GmailAdded $_.Email) })
    if ($chrome.Count -gt 1) {
        $all = New-Object System.Windows.Controls.Button
        $all.Style = $win.FindResource('Glass')
        $all.Height = 44; $all.Margin = '0,0,8,8'; $all.Padding = '14,0'; $all.FontSize = 15
        $all.Background = ConvertTo-Brush '#B3EA4335'
        $all.Content = "Nhập tất cả Gmail có sẵn ($($chrome.Count))"
        $all.Add_Click({
            $added = @(Import-GmailAccounts)
            $ui.AddOverlay.Visibility = 'Collapsed'
            Show-Toast $(if ($added.Count) { "Đã thêm $($added.Count) hộp thư vào thư mục Gmail: $($added -join ', ')" } else { 'Các tài khoản đã có sẵn.' })
        })
        [void]$ui.AddSuggest.Children.Add($all)
    }
    $emails = @(@($chrome | ForEach-Object { $_.Email }) + @(Get-OpenGmailAccounts) | Select-Object -Unique)
    foreach ($e in @($emails | Where-Object { -not (Test-GmailAdded $_) })) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $win.FindResource('Glass')
        $b.Height = 44; $b.Margin = '0,0,8,8'; $b.Padding = '14,0'; $b.FontSize = 15
        $b.Content = "+ Gmail $e"; $b.Tag = $e
        $b.Add_Click({ $ui.AddUrl.Text = $this.Tag })
        [void]$ui.AddSuggest.Children.Add($b)
    }
}

function ConvertTo-WebUrl([string]$text) {
    $t = $text.Trim()
    if (-not $t) { return $null }
    if ($t -notmatch '^[a-z]+://') { $t = "https://$t" }
    $u = $null
    if ([Uri]::TryCreate($t, 'Absolute', [ref]$u) -and $u.Scheme -in 'http', 'https' -and $u.Host -match '\.') { return $u.AbsoluteUri }
    return $null
}

function Update-AddGroups {
    $ui.AddGroups.Children.Clear()
    $groups = @($cfg.tiles | ForEach-Object { if ($_.group) { [string]$_.group } } | Select-Object -Unique)
    if ($groups -notcontains 'Của tôi') { $groups += 'Của tôi' }
    foreach ($g in $groups) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $win.FindResource('Glass')
        $b.Height = 48; $b.Margin = '0,0,8,8'; $b.Padding = '16,0'; $b.FontSize = 16
        $b.Content = $g; $b.Tag = $g
        if ($g -eq $script:AddGroup) { $b.Background = ConvertTo-Brush '#0A84FF' }
        $b.Add_Click({ $script:AddGroup = $this.Tag; Update-AddGroups })
        [void]$ui.AddGroups.Children.Add($b)
    }
}

function Show-AddApp {
    $script:AddInfo = $null
    $ui.AddUrl.Text = ''; $ui.AddName.Text = ''
    $ui.AddIcon.Source = $null; $ui.AddLetter.Text = '+'
    $ui.AddPreview.Background = ConvertTo-Brush '#3A3A3C'
    $ui.AddStatus.Text = 'Ví dụ: chat.zalo.me hoặc ten@gmail.com'
    Update-AddGroups
    Update-AddSuggest
    $ui.AddOverlay.Visibility = 'Visible'
    [void]$ui.AddUrl.Focus()
}

# Gõ xong địa chỉ (ngưng gõ 0,9 giây) -> tự lấy tên và icon.
$AddDebounce = New-Object System.Windows.Threading.DispatcherTimer
$AddDebounce.Interval = [TimeSpan]::FromMilliseconds(900)
$AddDebounce.Add_Tick({
    $AddDebounce.Stop()
    $email = $ui.AddUrl.Text.Trim()
    if ($email -match $EmailPattern) {
        $script:AddInfo = @{ Email = $email.ToLower(); Url = $null }
        if (-not $ui.AddName.Text -or $ui.AddName.Tag -eq 'auto') { $ui.AddName.Text = ($email -split '@')[0]; $ui.AddName.Tag = 'auto' }
        $ui.AddIcon.Source = $null; $ui.AddPreview.Background = New-Gradient '#EA4335'
        $ui.AddLetter.FontFamily = $IconFont; $ui.AddLetter.Text = [string][char]0xE715
        $ui.AddStatus.Text = if (Test-GmailAdded $email) { "Hộp thư $email đã có trong Thư viện." } else { "Hộp thư Gmail riêng của $email — nằm trong thư mục Gmail. (Tài khoản cần đăng nhập trong Chrome.)" }
        return
    }
    $ui.AddLetter.FontFamily = $TextFont
    $url = ConvertTo-WebUrl $ui.AddUrl.Text
    if (-not $url) { $ui.AddStatus.Text = 'Địa chỉ chưa hợp lệ.'; return }
    if ($script:AddInfo -and $script:AddInfo.Url -eq $url) { return }
    $ui.AddStatus.Text = 'Đang lấy tên và icon…'
    $script:AddPending = $url
    Start-BgJob $FetchSiteWork @($url, $IconDir) {
        param($r)
        if ($r.Url -ne $script:AddPending) { return }   # người dùng đã gõ địa chỉ khác
        $script:AddInfo = $r
        if (-not $ui.AddName.Text -or $ui.AddName.Tag -eq 'auto') { $ui.AddName.Text = $r.Name; $ui.AddName.Tag = 'auto' }
        if ($r.IconPath) {
            $script:ImgCache.Remove($r.IconPath)
            $ui.AddIcon.Source = Get-FileImage $r.IconPath
            $ui.AddLetter.Text = ''; $ui.AddPreview.Background = $LightTile
        } else {
            $ui.AddIcon.Source = $null; $ui.AddLetter.Text = Get-Initial $r.Name
            $ui.AddPreview.Background = New-Gradient (Get-BadgeColor $r.Name)
        }
        $ui.AddStatus.Text = if ($r.Error) { $r.Error + ' Vẫn có thể thêm.' } elseif ($r.IconPath) { 'Đã lấy được tên và icon.' } else { 'Không tìm thấy icon, sẽ dùng chữ cái đầu.' }
    }
})
$ui.AddUrl.Add_TextChanged({ $AddDebounce.Stop(); $AddDebounce.Start() })
$ui.AddName.Add_TextChanged({ if ($ui.AddName.IsKeyboardFocusWithin) { $ui.AddName.Tag = $null } })
$ui.BtnAddApp.Add_Click({ Show-AddApp })
$ui.BtnAddCancel.Add_Click({ $ui.AddOverlay.Visibility = 'Collapsed' })
$ui.BtnAddSave.Add_Click({
    $email = $ui.AddUrl.Text.Trim()
    if ($email -match $EmailPattern) {
        $email = $email.ToLower()
        if (Test-GmailAdded $email) { $ui.AddStatus.Text = "Hộp thư $email đã có rồi."; return }
        $acct = @(Get-ChromeGoogleAccounts | Where-Object { $_.Email -eq $email })[0]
        $tile = New-GmailTile $email $ui.AddName.Text.Trim() $(if ($acct) { $acct.Profile } else { $null })
        $name = $tile.name
        $cfg.tiles = @(@($cfg.tiles) + $tile)
        Save-UserApps
        $script:Pins = @($script:Pins) + $name
        Save-Pins
        $ui.AddOverlay.Visibility = 'Collapsed'
        Load-Apps
        Build-Home
        Show-Toast "Đã thêm hộp thư $email vào thư mục Gmail."
        return
    }
    $url = ConvertTo-WebUrl $ui.AddUrl.Text
    $name = $ui.AddName.Text.Trim()
    if (-not $url) { $ui.AddStatus.Text = 'Hãy nhập địa chỉ trang web hợp lệ.'; return }
    if (-not $name) { $ui.AddStatus.Text = 'Hãy đặt tên cho app.'; return }
    if (Get-Tile $name) { $ui.AddStatus.Text = "Đã có app tên '$name', hãy đặt tên khác."; return }
    $icon = if ($script:AddInfo -and $script:AddInfo.Url -eq $url -and $script:AddInfo.IconPath) {
        'icons\' + [IO.Path]::GetFileName($script:AddInfo.IconPath) } else { $null }
    $tile = [pscustomobject]@{
        group = $script:AddGroup; name = $name; icon = (Get-Initial $name); iconImage = $icon
        color = (Get-BadgeColor $name); type = 'app'; target = $url; match = [regex]::Escape($name); user = $true
    }
    $cfg.tiles = @(@($cfg.tiles) + $tile)
    Save-UserApps
    $script:Pins = @($script:Pins) + $name
    Save-Pins
    $ui.AddOverlay.Visibility = 'Collapsed'
    Load-Apps
    Build-Home
    Show-Toast "Đã thêm $name vào Thư viện và trang chủ."
})

function Remove-UserApp($t) {
    $cfg.tiles = @($cfg.tiles | Where-Object { $_ -ne $t })
    Save-UserApps
    if (Test-Pinned $t.name) { $script:Pins = @($script:Pins | Where-Object { $_ -ne $t.name }); Save-Pins }
    Load-Apps
    Update-DeleteBadges
    Build-Home
    Show-Toast "Đã xóa $($t.name)."
}

# ---------------------------------------------------------------- Tự kiểm tra bản mới (chỉ bản .exe một tệp)
$UpdateRepo = 'npduylab/windows-tablet-launcher'
$CurrentVersion = if ($env:TOUCHLAUNCHER_VERSION) { $env:TOUCHLAUNCHER_VERSION } else { '0.0.0' }
$UpdateStatePath = Join-Path $env:LOCALAPPDATA 'TouchLauncher\update.json'
$script:UpdateInfo = $null
$script:RestartExe = $null

$CheckUpdateWork = {
    param([string]$repo)
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $http = New-Object System.Net.Http.HttpClient
    $http.Timeout = [TimeSpan]::FromSeconds(15)
    $http.DefaultRequestHeaders.UserAgent.ParseAdd('TouchLauncher-UpdateCheck')
    try {
        $j = $http.GetStringAsync("https://api.github.com/repos/$repo/releases/latest").Result | ConvertFrom-Json
        $asset = @($j.assets | Where-Object { $_.name -eq 'TouchLauncher.exe' })[0]
        return @{ Tag = [string]$j.tag_name; Url = $asset.browser_download_url; Page = $j.html_url }
    } catch { return @{ Error = $_.Exception.Message } }
    finally { $http.Dispose() }
}

$DownloadWork = {
    param([string]$url, [string]$dest)
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $http = New-Object System.Net.Http.HttpClient
    $http.Timeout = [TimeSpan]::FromMinutes(3)
    $http.DefaultRequestHeaders.UserAgent.ParseAdd('TouchLauncher-Update')
    try {
        $bytes = $http.GetByteArrayAsync($url).Result
        if ($bytes.Length -lt 10KB -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) { return @{ Error = 'Tệp tải về không hợp lệ.' } }
        [IO.File]::WriteAllBytes($dest, $bytes)
        return @{ Path = $dest }
    } catch { return @{ Error = $_.Exception.Message } }
    finally { $http.Dispose() }
}

function Test-NewerVersion([string]$tag) {
    $a = $null; $b = $null
    if (-not [version]::TryParse($tag.TrimStart('v'), [ref]$a) -or -not [version]::TryParse($CurrentVersion, [ref]$b)) { return $false }
    return $a -gt $b
}

function Start-UpdateCheck {
    if (-not $env:TOUCHLAUNCHER_STANDALONE -or $cfg.updateCheck -eq $false) { return }
    # Tối đa 1 lần mỗi 20 giờ.
    try {
        $st = Get-Content $UpdateStatePath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($st.lastCheck -and ((Get-Date) - [datetime]$st.lastCheck).TotalHours -lt 20 -and -not $st.pending) { return }
    } catch {}
    Start-BgJob $CheckUpdateWork @($UpdateRepo) {
        param($r)
        if ($r.Error -or -not $r.Tag) { return }
        $newer = (Test-NewerVersion $r.Tag) -and $r.Url
        try { [IO.File]::WriteAllText($UpdateStatePath, (ConvertTo-Json @{ lastCheck = (Get-Date).ToString('o'); pending = [bool]$newer }), $Utf8NoBom) } catch {}
        if ($newer) {
            $script:UpdateInfo = $r
            $ui.UpdateText.Text = "Có bản mới $($r.Tag.TrimStart('v')) (đang dùng $CurrentVersion)"
            $ui.UpdateBar.Visibility = 'Visible'
        }
    }
}

$ui.BtnUpdateLater.Add_Click({ $ui.UpdateBar.Visibility = 'Collapsed' })
$ui.BtnUpdateNow.Add_Click({
    $u = $script:UpdateInfo
    if (-not $u) { return }
    $exe = $env:TOUCHLAUNCHER_EXE
    $ui.UpdateText.Text = 'Đang tải bản mới…'
    $ui.BtnUpdateNow.IsEnabled = $false
    Start-BgJob $DownloadWork @($u.Url, "$exe.new") {
        param($r)
        $exe = $env:TOUCHLAUNCHER_EXE
        $ui.BtnUpdateNow.IsEnabled = $true
        if ($r.Error) {
            $ui.UpdateText.Text = 'Không tải được bản mới. Mở trang tải về…'
            Start-Process $script:UpdateInfo.Page
            return
        }
        try {
            # Windows cho đổi tên exe đang chạy: cất bản cũ sang .old, đặt bản mới vào chỗ cũ, rồi khởi động lại.
            $old = "$exe.old"
            if (Test-Path $old) { Remove-Item $old -Force }
            Rename-Item -LiteralPath $exe -NewName ([IO.Path]::GetFileName($old))
            Move-Item -LiteralPath $r.Path -Destination $exe
            try { Remove-Item $UpdateStatePath -ErrorAction SilentlyContinue } catch {}
            $script:RestartExe = $exe
            $win.Close()
        } catch {
            $ui.UpdateText.Text = "Không thay được tệp ($($_.Exception.Message)). Mở trang tải về…"
            Start-Process $script:UpdateInfo.Page
        }
    }
})
# Dọn bản cũ còn lại sau lần cập nhật trước.
if ($env:TOUCHLAUNCHER_EXE -and (Test-Path "$($env:TOUCHLAUNCHER_EXE).old")) { Remove-Item "$($env:TOUCHLAUNCHER_EXE).old" -Force -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------- Tối ưu chính launcher
function Optimize-Self {
    [GC]::Collect()
    $h = [System.Diagnostics.Process]::GetCurrentProcess().Handle
    [void][TouchLauncher.Native]::EmptyWorkingSet($h)
}

# Trả RAM sau 30 giây ở nền (không trả ngay để quay lại launcher vẫn mượt).
$TrimTimer = New-Object System.Windows.Threading.DispatcherTimer
$TrimTimer.Interval = [TimeSpan]::FromSeconds(30)
$TrimTimer.Add_Tick({ $TrimTimer.Stop(); Optimize-Self })

$win.Add_Activated({
    $TrimTimer.Stop(); Update-Status; Update-DockRecent; $StatusTimer.Start()
    if ($script:Split) { Stop-SplitView $false }
    Update-NowPlaying; $NowTimer.Start()
})
$win.Add_Deactivated({
    $StatusTimer.Stop()
    $NowTimer.Stop()
    if ($ui.SwitchOverlay.Visibility -eq 'Visible') { Hide-Switcher }
    $TrimTimer.Start()
})
$win.Add_Closed({
    $script:AppClosing = $true
    [TouchLauncher.WinWatch]::StopAll()
    $nav.Close(); $ccWin.Close(); $splitWin.Close(); $homeBar.Close(); $blackWin.Close(); $flashWin.Close(); $previewWin.Close()
    [TouchLauncher.Native]::KeepDisplayOn($false)
})
$win.Add_ContentRendered({
    if ($cfg.autoCleanOnStart) {
        $r = Stop-Junk $cfg.killList
        if ($r.Killed) { Show-Toast "Tự dọn: đóng $($r.Killed) tiến trình, ~$($r.MB) MB RAM." }
    }
    if ($cfg.autoKeyboard -and -not $script:AutoKbd) {
        if (Set-AutoKeyboard $true) { $script:AutoKbd = $true; Show-Toast 'Đã bật: bàn phím cảm ứng tự hiện khi chạm vào ô nhập chữ.' }
    }
    if ($NavEnabled -and -not $nav.IsVisible) { $nav.Show(); $NavFade.Start() }
    Show-HomeBar
    $IdleTimer.Start()
    $UpdateDelay.Start()
    Optimize-Self
})

# Kiểm tra bản mới sau khi mở 15 giây (không làm chậm lúc khởi động).
$UpdateDelay = New-Object System.Windows.Threading.DispatcherTimer
$UpdateDelay.Interval = [TimeSpan]::FromSeconds(15)
$UpdateDelay.Add_Tick({ $UpdateDelay.Stop(); Start-UpdateCheck })

$GmailImportFlag = Join-Path $PSScriptRoot '.gmail-imported'
if ((-not $Check -or $env:TL_TEST_IMPORT) -and $cfg.importGmail -ne $false -and -not (Test-Path $GmailImportFlag)) {
    $script:ImportedGmail = @(Import-GmailAccounts)
    try { [IO.File]::WriteAllText($GmailImportFlag, (Get-Date).ToString('o')) } catch {}
}
Build-Home
Update-Status

if ($Check) {
    Load-Apps
    $ui.Spot.Text = 'you'
    "Tìm 'you': $($ui.SpotList.Children.Count) kết quả."
    Clear-Spot
    $open = @([TouchLauncher.Native]::GetAppWindows($PID))
    "Cửa sổ đang mở: $($open.Count). PiP tìm thấy: $(if (Find-PipWindow) { (Find-PipWindow).Title } else { '(chưa mở YouTube)' })"
    "Màn hình chính: $($ui.TilePanel.Children.Count) icon. Dock: $($ui.DockFav.Children.Count) + $($ui.DockRecent.Children.Count). Bộ sưu tập: $($script:AppItems.Count) app trong $(@($script:Sections).Count) nhóm. Lịch: $($ui.CalTitle.Text), $($ui.CalGrid.Children.Count) ô, $($ui.LunarText.Text). Trung tâm điều khiển: $($CcGrid.Children.Count) nút."
    "Trình duyệt: $Browser."
    "Thanh điều hướng: $(if ($script:NavAutoHide) { 'tự ẩn' } else { 'luôn hiện (đã ghim)' })."
    "Hồ sơ Chrome chính cho các app: $(if ($MainProfile) { $MainProfile } else { '(theo Chrome)' })."
    "Tài khoản Google trong Chrome: $(@(Get-ChromeGoogleAccounts | ForEach-Object { "$($_.Email) [$($_.Profile)]" }) -join ', '). Vừa nhập: $(if ($script:ImportedGmail) { @($script:ImportedGmail).Count } else { 0 })."
    "Thư mục trên trang chủ: $(@($script:FolderKids.Keys | ForEach-Object { "$_ ($(@($script:FolderKids[$_]).Count) app: $($script:FolderKids[$_] -join ', '))" }) -join '; '). Chấm đỏ đang theo dõi: $($script:BadgeEls.Count) icon."
    Update-NowPlaying
    "Đang phát: $(if ($ui.NowCard.Visibility -eq 'Visible') { "$($ui.NowTitle.Text) [$($ui.NowSource.Text)]" } else { '(không có)' }). App tự thêm: $(@($cfg.tiles | Where-Object { $_.user }).Count). Ảnh cho đồng hồ đêm: $(@(Get-NightPhotos).Count)."
    "Rảnh (không chạm): $([TouchLauncher.Native]::IdleSeconds()) giây. Phiên bản: $CurrentVersion$(if ($env:TOUCHLAUNCHER_STANDALONE) { ' (exe một tệp)' })."
    Initialize-Brightness
    "Tự hiện bàn phím: $script:AutoKbd. Độ sáng: $(if ($null -ne $script:Bri) { "$($script:Bri)%" } else { 'không hỗ trợ' }). Tiết kiệm pin: $script:SaverOn"
    exit 0
}

$self = [System.Diagnostics.Process]::GetCurrentProcess()
$self.PriorityClass = 'BelowNormal'
[TouchLauncher.Native]::EcoQoS($self.Handle)

[void]$win.ShowDialog()
$script:Mutex.ReleaseMutex()
if ($script:RestartExe) { Start-Process -FilePath $script:RestartExe }
