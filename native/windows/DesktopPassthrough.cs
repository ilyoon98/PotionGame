// Windows-only input bridge. No hooks, injected input, network or player data.
// A layered WS_EX_TRANSPARENT window passes input to OTHER processes as well.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class DesktopPassthrough
{
    const int ExStyle = -20, Style = -16;
    const long Layered = 0x80000, Transparent = 0x20, Caption = 0xC00000;
    [StructLayout(LayoutKind.Sequential)] struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetStyle(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] static extern IntPtr SetStyle(IntPtr window, int index, IntPtr value);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window, ref Point point);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SetLayeredWindowAttributes(IntPtr window, uint key, byte alpha, uint flags);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [StructLayout(LayoutKind.Sequential)] struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr window);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    const long Topmost = 0x8;
    static readonly IntPtr TopmostBand = new IntPtr(-1);
    // NOSIZE | NOMOVE | NOACTIVATE | ASYNCWINDOWPOS: z-order only, never focus or style.
    const uint ZOrderOnly = 0x1 | 0x2 | 0x10 | 0x4000;
    delegate bool EnumWindowsProc(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr data);
    static volatile bool stopped;
    // Owner windows this bridge stepped behind a full-screen app (main and management).
    static readonly HashSet<IntPtr> yielded = new HashSet<IntPtr>();

    static bool BelongsTo(IntPtr window, uint process)
    {
        uint actual;
        return IsWindow(window) && GetWindowThreadProcessId(window, out actual) != 0 && actual == process;
    }

    static void ChangeStyle(IntPtr window, long value)
    {
        // Zero can be a valid previous value; inspect the Win32 error instead.
        SetLastError(0);
        if (SetStyle(window, ExStyle, new IntPtr(value)) == IntPtr.Zero && Marshal.GetLastWin32Error() != 0)
            throw new System.ComponentModel.Win32Exception();
    }
    [DllImport("kernel32.dll")] static extern void SetLastError(uint error);

    static Rect[] ParseRegions(string encoded, int width, int toolbarBottom, int hudTop)
    {
        if (encoded.Length == 0) return new Rect[0];
        var entries = encoded.Split(';');
        if (entries.Length > 32) throw new FormatException("Too many desktop input regions.");
        var regions = new List<Rect>();
        foreach (string entry in entries)
        {
            var values = entry.Split(',');
            int x, y, w, h;
            if (values.Length != 4 ||
                !int.TryParse(values[0], NumberStyles.None, CultureInfo.InvariantCulture, out x) ||
                !int.TryParse(values[1], NumberStyles.None, CultureInfo.InvariantCulture, out y) ||
                !int.TryParse(values[2], NumberStyles.None, CultureInfo.InvariantCulture, out w) ||
                !int.TryParse(values[3], NumberStyles.None, CultureInfo.InvariantCulture, out h) ||
                x < 0 || y < toolbarBottom || w <= 0 || h <= 0 ||
                (long)x + w > width || (long)y + h > hudTop)
                throw new FormatException("Desktop input regions must be bounded rectangles inside the picture.");
            regions.Add(new Rect { Left = x, Top = y, Right = x + w, Bottom = y + h });
        }
        return regions.ToArray();
    }

    // A full-screen video or game in front on the game's own monitor. A
    // maximized window is not full screen even when the taskbar auto-hides.
    static IntPtr ForegroundFullscreen(IntPtr window, uint owner)
    {
        IntPtr front = GetForegroundWindow();
        if (front == IntPtr.Zero || BelongsTo(front, owner) || !IsWindowVisible(front) || IsZoomed(front)) return IntPtr.Zero;
        var name = new StringBuilder(32);
        if (GetClassName(front, name, name.Capacity) == 0) return IntPtr.Zero;
        string type = name.ToString();
        if (type == "Progman" || type == "WorkerW" || type == "Shell_TrayWnd" || type == "Shell_SecondaryTrayWnd") return IntPtr.Zero;
        var monitor = new MonitorInfo { Size = Marshal.SizeOf(typeof(MonitorInfo)) };
        Rect bounds;
        if (!GetMonitorInfo(MonitorFromWindow(window, 2), ref monitor) || !GetWindowRect(front, out bounds)) return IntPtr.Zero;
        bool covers = bounds.Left <= monitor.Monitor.Left && bounds.Top <= monitor.Monitor.Top && bounds.Right >= monitor.Monitor.Right && bounds.Bottom >= monitor.Monitor.Bottom;
        return covers ? front : IntPtr.Zero;
    }

    // Every visible top-level window of the game, so the management panel
    // yields with the main window without its own bridge.
    static List<IntPtr> OwnerWindows(uint owner)
    {
        var windows = new List<IntPtr>();
        EnumWindows(delegate(IntPtr candidate, IntPtr data) {
            if (IsWindowVisible(candidate) && BelongsTo(candidate, owner)) windows.Add(candidate);
            return true;
        }, IntPtr.Zero);
        return windows;
    }

    static void UpdateYield(uint owner)
    {
        var current = OwnerWindows(owner);
        foreach (IntPtr window in current)
        {
            IntPtr fullscreen = ForegroundFullscreen(window, owner);
            bool topmost = (GetStyle(window, ExStyle).ToInt64() & Topmost) != 0;
            if (fullscreen != IntPtr.Zero && topmost)
            {
                // Inserting after a non-topmost window also drops our topmost bit.
                SetWindowPos(window, fullscreen, 0, 0, 0, 0, ZOrderOnly);
                yielded.Add(window);
            }
            else if (fullscreen == IntPtr.Zero && yielded.Remove(window))
                SetWindowPos(window, TopmostBand, 0, 0, 0, 0, ZOrderOnly);
        }
        // Closed panels and hidden windows are restored when they appear again.
        yielded.RemoveWhere(window => !current.Contains(window) && !BelongsTo(window, owner));
    }

    static void RestoreYielded(uint owner)
    {
        // Godot still expects always-on-top after the bridge stops.
        foreach (IntPtr window in yielded)
            if (BelongsTo(window, owner)) SetWindowPos(window, TopmostBand, 0, 0, 0, 0, ZOrderOnly);
        yielded.Clear();
    }

    static bool InRegion(double x, double y, Rect[] regions)
    {
        foreach (Rect region in regions)
            if (x >= region.Left && x < region.Right && y >= region.Top && y < region.Bottom) return true;
        return false;
    }

    static int Main(string[] args)
    {
        if (args.Length != 6 && args.Length != 7) return 2;
        IntPtr window = IntPtr.Zero;
        uint owner = 0;
        long original = 0;
        bool changed = false;
        bool needsLayeredAlpha = false;
        int zOrderTick = 0;
        try
        {
            SetProcessDpiAwarenessContext(new IntPtr(-4));
            window = new IntPtr(long.Parse(args[0]));
            owner = uint.Parse(args[1]);
            int width = int.Parse(args[2]), height = int.Parse(args[3]);
            int toolbarBottom = int.Parse(args[4]), hudTop = int.Parse(args[5]);
            if (width <= 0 || height <= 0 || toolbarBottom < 0 || hudTop <= toolbarBottom || hudTop > height || !BelongsTo(window, owner)) return 3;
            Rect[] regions = args.Length == 7 ? ParseRegions(args[6], width, toolbarBottom, hudTop) : new Rect[0];
            original = GetStyle(window, ExStyle).ToInt64();
            // EOF also stops the bridge when Godot exits or closes its pipe.
            var reader = new Thread(delegate() {
                try { using (var input = new StreamReader(Console.OpenStandardInput())) { input.ReadLine(); } }
                catch (IOException) { }
                finally { stopped = true; }
            });
            reader.IsBackground = true;
            reader.Start();
            while (!stopped && BelongsTo(window, owner))
            {
                // Minimize/restore can temporarily rebuild Godot's native style.
                // Do not initialize a layered surface while it is minimized.
                if (IsIconic(window)) { Thread.Sleep(16); continue; }
                Rect rect;
                if (!GetClientRect(window, out rect) || (GetStyle(window, Style).ToInt64() & Caption) != 0) break;
                // Also restore if the scene changes mode before the pipe closes.
                if (Math.Abs((double)rect.Right / Math.Max(1, rect.Bottom) - (double)width / height) > 0.01) break;
                Point cursor;
                if (!GetCursorPos(out cursor) || !ScreenToClient(window, ref cursor))
                {
                    // Locked/switched desktop: restore input and resume after unlock.
                    if (changed)
                    {
                        long restore = GetStyle(window, ExStyle).ToInt64();
                        ChangeStyle(window, (restore & ~(Layered | Transparent)) | (original & (Layered | Transparent)));
                        changed = false;
                    }
                    Thread.Sleep(100);
                    continue;
                }
                double x = (double)cursor.X * width / Math.Max(1, rect.Right);
                double y = (double)cursor.Y * height / Math.Max(1, rect.Bottom);
                bool inside = cursor.X >= 0 && cursor.X < rect.Right && y >= 0 && y < height;
                long current = GetStyle(window, ExStyle).ToInt64();
                bool pass = inside && y >= toolbarBottom && y < hudTop && !InRegion(x, y, regions);
                // Keep the recipient of a held button, especially toolbar drags.
                bool held = (GetAsyncKeyState(1) & 0x8000) != 0 || (GetAsyncKeyState(2) & 0x8000) != 0 || (GetAsyncKeyState(4) & 0x8000) != 0;
                // About every 100 ms: step behind a full-screen app on this
                // monitor, and return to the topmost band once it is gone.
                if (++zOrderTick >= 12)
                {
                    zOrderTick = 0;
                    UpdateYield(owner);
                }
                if (!held)
                {
                    long desired = (current | Layered) & ~Transparent;
                    if (pass) desired |= Transparent;
                    if (desired != current)
                    {
                        ChangeStyle(window, desired);
                        changed = true;
                        if ((current & Layered) == 0) needsLayeredAlpha = true;
                    }
                    if (needsLayeredAlpha) {
                        if (SetLayeredWindowAttributes(window, 0, 255, 2)) needsLayeredAlpha = false;
                        else {
                            int error = Marshal.GetLastWin32Error();
                            // Godot or the taskbar bridge can update the style
                            // between the two calls. Retry a fresh style next
                            // frame instead of permanently disabling input.
                            if (error!=87 && error!=1400) throw new System.ComponentModel.Win32Exception(error);
                        }
                    }
                }
                Thread.Sleep(8);
            }
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error.Message);
            return 1;
        }
        finally
        {
            if (changed && BelongsTo(window, owner))
            {
                long current = GetStyle(window, ExStyle).ToInt64();
                // Preserve other flags Godot may have changed, e.g. always-on-top.
                SetStyle(window, ExStyle, new IntPtr((current & ~(Layered | Transparent)) | (original & (Layered | Transparent))));
            }
            RestoreYielded(owner);
        }
    }
}
