// TouchLauncher.exe — vỏ chạy Launcher.ps1 ngay trong tiến trình (không mở powershell.exe, không nháy cửa sổ đen).
//
// - Nếu cạnh exe có Launcher.ps1 (thư mục mã nguồn) thì chạy tệp đó.
// - Nếu không, giải nén bản nhúng sẵn vào %LOCALAPPDATA%\TouchLauncher\app rồi chạy:
//   Launcher.ps1 và MCP luôn được cập nhật theo exe; launcher.config.json của người dùng được giữ nguyên.
//
// Build: powershell -ExecutionPolicy Bypass -File build.ps1

using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

// Thông tin phiên bản (AssemblyVersion…) do build.ps1 sinh ra trong build\AssemblyInfo.cs.

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        bool check = args.Any(a => a.Equals("-Check", StringComparison.OrdinalIgnoreCase));
        if (check)
        {
            // Exe không có cửa sổ console: ghi thẳng ra luồng chuẩn (khi bị chuyển hướng) bằng UTF-8.
            var utf8 = new System.Text.UTF8Encoding(false);
            Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), utf8) { AutoFlush = true });
            Console.SetError(new StreamWriter(Console.OpenStandardError(), utf8) { AutoFlush = true });
        }
        try
        {
            string script = PrepareScript();
            return Run(script, check);
        }
        catch (Exception ex)
        {
            if (check) { Console.Error.WriteLine(ex); return 1; }
            MessageBox.Show("Không khởi động được Touch Launcher:\n\n" + ex.Message, "Touch Launcher",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    static string PrepareScript()
    {
        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
        string beside = Path.Combine(exeDir, "Launcher.ps1");
        if (File.Exists(beside)) return beside;

        string appDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TouchLauncher", "app");
        Directory.CreateDirectory(Path.Combine(appDir, "mcp"));
        Extract("Launcher.ps1", Path.Combine(appDir, "Launcher.ps1"), true);
        Extract("touch_launcher_mcp.py", Path.Combine(appDir, "mcp", "touch_launcher_mcp.py"), true);
        Extract("launcher.config.json", Path.Combine(appDir, "launcher.config.json"), false);
        return Path.Combine(appDir, "Launcher.ps1");
    }

    // Ghi tài nguyên nhúng ra đĩa; bỏ qua nếu tệp đã giống hệt (hoặc đã có và không được ghi đè).
    static void Extract(string resource, string path, bool overwrite)
    {
        if (!overwrite && File.Exists(path)) return;
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource))
        {
            if (s == null) throw new FileNotFoundException("Thiếu tài nguyên nhúng: " + resource);
            byte[] data;
            using (var ms = new MemoryStream()) { s.CopyTo(ms); data = ms.ToArray(); }
            if (File.Exists(path) && File.ReadAllBytes(path).SequenceEqual(data)) return;
            File.WriteAllBytes(path, data);
        }
    }

    static int Run(string script, bool check)
    {
        InitialSessionState iss = InitialSessionState.CreateDefault();
        using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
        {
            // WPF cần luồng STA; chạy script ngay trên luồng chính của exe.
            rs.ApartmentState = ApartmentState.STA;
            rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
            rs.Open();

            using (PowerShell ps = PowerShell.Create())
            {
                ps.Runspace = rs;
                // Chỉ áp dụng cho tiến trình này, không đổi cài đặt bảo mật của máy.
                ps.AddCommand("Set-ExecutionPolicy").AddParameter("Scope", "Process")
                  .AddParameter("ExecutionPolicy", "Bypass").AddParameter("Force");
                ps.Invoke();
                ps.Commands.Clear();

                ps.AddCommand(script);
                if (check) ps.AddParameter("Check");
                var output = ps.Invoke();

                if (check)
                {
                    foreach (PSObject o in output) Console.WriteLine(o);
                    foreach (ErrorRecord e in ps.Streams.Error) Console.Error.WriteLine("LỖI: " + e);
                }
                return 0;
            }
        }
    }
}
