using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class Program
{
    private const string AppId = "xAI.GrokBuild";
    private const string MutexName = @"Local\xAI.GrokBuild.SingleInstance";
    private const string WindowTitle = "Grok Build";

    [STAThread]
    private static int Main(string[] args)
    {
        SetCurrentProcessExplicitAppUserModelID(AppId);

        bool created;
        using (new Mutex(true, MutexName, out created))
        {
            if (!created)
            {
                ActivateExisting();
                return 0;
            }

            string grok = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                @".grok\bin\grok.exe");
            if (!File.Exists(grok))
            {
                MessageBox(IntPtr.Zero, "Could not find grok.exe at:\n" + grok, WindowTitle, 0x10);
                return 1;
            }

            AllocConsole();
            SetConsoleTitle(WindowTitle);
            LoadAppIcons();

            IntPtr hwnd = GetConsoleWindow();
            if (hwnd != IntPtr.Zero)
            {
                ApplyWindowAppId(hwnd);
                ApplyIcon(hwnd);
                ShowWindow(hwnd, SW_SHOWNORMAL);
            }

            var psi = new ProcessStartInfo
            {
                FileName = grok,
                WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                UseShellExecute = false,
                CreateNoWindow = false
            };
            if (args != null && args.Length > 0)
                psi.Arguments = EscapeArgs(args);

            try
            {
                using (Process child = Process.Start(psi))
                {
                    if (child == null)
                    {
                        MessageBox(IntPtr.Zero, "Failed to start Grok Build.", WindowTitle, 0x10);
                        return 1;
                    }

                    int childId = child.Id;
                    var titleKeeper = new Thread(() =>
                    {
                        try
                        {
                            while (!child.HasExited)
                            {
                                SetConsoleTitle(WindowTitle);
                                ApplyIconToOwnedWindows(childId);
                                Thread.Sleep(750);
                            }
                        }
                        catch (InvalidOperationException) { }
                    });
                    titleKeeper.IsBackground = true;
                    titleKeeper.Start();

                    child.WaitForExit();
                    return child.ExitCode;
                }
            }
            finally
            {
                FreeConsole();
            }
        }
    }

    private static void ActivateExisting()
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, _) =>
        {
            if (!IsWindowVisible(h)) return true;
            var sb = new StringBuilder(512);
            GetWindowText(h, sb, sb.Capacity);
            string title = sb.ToString();
            if (title.IndexOf("Grok Build", StringComparison.OrdinalIgnoreCase) < 0
                && !title.Equals("grok", StringComparison.OrdinalIgnoreCase))
                return true;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            try
            {
                string name = Process.GetProcessById(unchecked((int)pid)).ProcessName;
                if (!name.Equals("GrokBuild", StringComparison.OrdinalIgnoreCase)
                    && !name.Equals("grok", StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            catch { return true; }
            found = h;
            return false;
        }, IntPtr.Zero);

        if (found == IntPtr.Zero)
        {
            foreach (Process p in Process.GetProcessesByName("GrokBuild"))
            {
                if (p.Id == Process.GetCurrentProcess().Id) continue;
                if (p.MainWindowHandle != IntPtr.Zero)
                {
                    found = p.MainWindowHandle;
                    break;
                }
            }
        }

        if (found == IntPtr.Zero) return;
        ShowWindow(found, SW_RESTORE);
        SetForegroundWindow(found);
    }

    private static void ApplyWindowAppId(IntPtr hwnd)
    {
        Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IPropertyStore store;
        if (SHGetPropertyStoreForWindow(hwnd, ref iid, out store) != 0 || store == null)
            return;
        try
        {
            PROPERTYKEY key = AppUserModelIdKey();
            PROPVARIANT value = PropVariantFromString(AppId);
            store.SetValue(ref key, ref value);
            store.Commit();
            PropVariantClear(ref value);
        }
        finally
        {
            Marshal.ReleaseComObject(store);
        }
    }

    private static IntPtr _iconBig = IntPtr.Zero;
    private static IntPtr _iconSmall = IntPtr.Zero;

    private static string IconPath()
    {
        string home = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            @".grok\grok-build.ico");
        if (File.Exists(home)) return home;
        try
        {
            string beside = Path.Combine(Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName), "grok-build.ico");
            if (File.Exists(beside)) return beside;
        }
        catch { }
        return home;
    }

    private static void LoadAppIcons()
    {
        string ico = IconPath();
        if (!File.Exists(ico)) return;
        int big = GetSystemMetrics(SM_CXICON);
        int small = GetSystemMetrics(SM_CXSMICON);
        if (big <= 0) big = 32;
        if (small <= 0) small = 16;
        _iconBig = LoadImage(IntPtr.Zero, ico, IMAGE_ICON, big, big, LR_LOADFROMFILE);
        _iconSmall = LoadImage(IntPtr.Zero, ico, IMAGE_ICON, small, small, LR_LOADFROMFILE);
        if (_iconBig == IntPtr.Zero)
            _iconBig = LoadImage(IntPtr.Zero, ico, IMAGE_ICON, 0, 0, LR_LOADFROMFILE | LR_DEFAULTSIZE);
        if (_iconSmall == IntPtr.Zero)
            _iconSmall = _iconBig;
        if (_iconBig != IntPtr.Zero)
            SetConsoleIcon(_iconBig);
    }

    private static void ApplyIcon(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || _iconBig == IntPtr.Zero) return;
        SendMessage(hwnd, WM_SETICON, (IntPtr)ICON_BIG, _iconBig);
        SendMessage(hwnd, WM_SETICON, (IntPtr)ICON_SMALL, _iconSmall != IntPtr.Zero ? _iconSmall : _iconBig);
        SetClassLongPtr(hwnd, GCLP_HICON, _iconBig);
        SetClassLongPtr(hwnd, GCLP_HICONSM, _iconSmall != IntPtr.Zero ? _iconSmall : _iconBig);
        ApplyWindowAppId(hwnd);
    }

    private static void ApplyIconToOwnedWindows(int childPid)
    {
        IntPtr console = GetConsoleWindow();
        if (console != IntPtr.Zero) ApplyIcon(console);
        if (_iconBig != IntPtr.Zero) SetConsoleIcon(_iconBig);

        int self = Process.GetCurrentProcess().Id;
        EnumWindows((h, _) =>
        {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            int id = unchecked((int)pid);
            if (id != self && id != childPid) return true;
            if (!IsWindowVisible(h)) return true;
            ApplyIcon(h);
            return true;
        }, IntPtr.Zero);
    }

    private static string EscapeArgs(string[] args)
    {
        var sb = new StringBuilder();
        foreach (string a in args)
        {
            if (sb.Length > 0) sb.Append(' ');
            if (a.IndexOfAny(new[] { ' ', '"', '\t' }) < 0) sb.Append(a);
            else sb.Append('"').Append(a.Replace("\"", "\\\"")).Append('"');
        }
        return sb.ToString();
    }

    private static PROPERTYKEY AppUserModelIdKey()
    {
        return new PROPERTYKEY
        {
            fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
            pid = 5
        };
    }

    private static PROPVARIANT PropVariantFromString(string value)
    {
        return new PROPVARIANT
        {
            vt = VT_LPWSTR,
            pszVal = Marshal.StringToCoTaskMemUni(value)
        };
    }

    private const int SW_SHOWNORMAL = 1;
    private const int SW_RESTORE = 9;
    private const int WM_SETICON = 0x0080;
    private const int ICON_SMALL = 0;
    private const int ICON_BIG = 1;
    private const int IMAGE_ICON = 1;
    private const int LR_LOADFROMFILE = 0x0010;
    private const int LR_DEFAULTSIZE = 0x0040;
    private const int GCLP_HICON = -14;
    private const int GCLP_HICONSM = -34;
    private const int SM_CXICON = 11;
    private const int SM_CXSMICON = 49;
    private const ushort VT_LPWSTR = 31;

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appID);

    [DllImport("shell32.dll")]
    private static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, out IPropertyStore ppv);

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PROPVARIANT pvar);

    [DllImport("kernel32.dll")]
    private static extern bool AllocConsole();

    [DllImport("kernel32.dll")]
    private static extern bool FreeConsole();

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern bool SetConsoleTitle(string lpConsoleTitle);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr hWnd, string text, string caption, uint type);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadImage(IntPtr hInst, string name, int type, int cx, int cy, int fuLoad);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetClassLongPtrW")]
    private static extern IntPtr SetClassLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("kernel32.dll")]
    private static extern bool SetConsoleIcon(IntPtr hIcon);

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct PROPERTYKEY
    {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROPVARIANT
    {
        public ushort vt;
        public ushort wReserved1;
        public ushort wReserved2;
        public ushort wReserved3;
        public IntPtr pszVal;
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        uint GetCount(out uint cProps);
        uint GetAt(uint iProp, out PROPERTYKEY pkey);
        uint GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        uint SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        uint Commit();
    }
}
