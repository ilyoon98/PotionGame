// Change only the two taskbar-style bits of explicitly registered, same-process
// Godot windows. No input injection, registry, hooks, network or player data.
using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

[ComImport, Guid("56FDF342-FD6D-11D0-958A-006097C9A090"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface ITaskbarList {
    void HrInit(); void AddTab(IntPtr window); void DeleteTab(IntPtr window);
    void ActivateTab(IntPtr window); void SetActiveAlt(IntPtr window);
}
[ComImport, Guid("56FDF344-FD6D-11D0-958A-006097C9A090")]
class TaskbarList { }

internal static class TrayTaskbar {
    const int ExStyle = -20;
    const long ToolWindow = 0x80, AppWindow = 0x40000, Mask = ToolWindow | AppWindow;
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window,int command);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetStyle(IntPtr window,int index);
    [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW",SetLastError=true)] static extern IntPtr SetStyle(IntPtr window,int index,IntPtr value);
    [DllImport("kernel32.dll")] static extern void SetLastError(uint value);
    static readonly ConcurrentQueue<string> commands = new ConcurrentQueue<string>();
    static volatile bool stopped;
    static uint ownerId;
    static IntPtr mainWindow;
    static uint trayId;
    static ITaskbarList taskbar;
    static readonly Dictionary<IntPtr,long> originals = new Dictionary<IntPtr,long>();
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct NotifyIconData {
        public uint cbSize; public IntPtr window; public uint id,flags,message; public IntPtr icon;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string tip;
        public uint state,stateMask;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=256)] public string info;
        public uint version;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=64)] public string title;
        public uint infoFlags; public Guid guid; public IntPtr balloonIcon;
    }
    [DllImport("shell32.dll",CharSet=CharSet.Unicode,EntryPoint="Shell_NotifyIconW")]
    static extern bool NotifyIcon(uint message,ref NotifyIconData data);
    static bool TrayExists() {
        // NIM_MODIFY with no flags verifies this exact existing notification
        // without changing its icon/menu/tip, including when it is in overflow.
        var data=new NotifyIconData { cbSize=(uint)Marshal.SizeOf(typeof(NotifyIconData)),window=mainWindow,id=trayId,tip="",info="",title="" };
        return NotifyIcon(1,ref data);
    }

    static bool Owned(IntPtr window) {
        uint pid;
        return IsWindow(window) && GetWindowThreadProcessId(window,out pid)!=0 && pid==ownerId;
    }
    static void Change(IntPtr window,long value) {
        SetLastError(0);
        if (SetStyle(window,ExStyle,new IntPtr(value))==IntPtr.Zero && Marshal.GetLastWin32Error()!=0)
            throw new System.ComponentModel.Win32Exception();
    }
    static void Apply(IntPtr window) {
        // Godot destroys secondary HWNDs when closing a panel. A queued add
        // may arrive after that close, which is normal rather than a failure.
        if (!IsWindow(window) && window!=mainWindow) return;
        if (!Owned(window)) throw new InvalidOperationException("Only the owner's registered windows are allowed.");
        long current=GetStyle(window,ExStyle).ToInt64();
        if (!originals.ContainsKey(window)) originals.Add(window,current&Mask);
        long desired=(current|ToolWindow)&~AppWindow;
        try {
            if (desired!=current) Change(window,desired);
            // Removing the tab through the shell avoids hide/show focus flicker.
            taskbar.DeleteTab(window);
        } catch(Exception) {
            if (window==mainWindow || IsWindow(window)) throw;
        }
    }
    static void Reply(string value) { Console.Out.WriteLine(value); Console.Out.Flush(); }
    [STAThread]
    static int Main(string[] args) {
        Process owner=null;
        try {
            long handle;
            if (args.Length!=3 || !uint.TryParse(args[0],out ownerId) || ownerId==0 || !long.TryParse(args[1],out handle) || !uint.TryParse(args[2],out trayId)) return 2;
            owner=Process.GetProcessById((int)ownerId);
            IntPtr exactOwner=owner.Handle;
            if (owner.HasExited) return 3;
            mainWindow=new IntPtr(handle);
            if (!Owned(mainWindow) || !TrayExists()) throw new InvalidOperationException("Windows Shell did not acknowledge the owner's tray icon.");
            taskbar=(ITaskbarList)new TaskbarList();
            taskbar.HrInit();
            Apply(new IntPtr(handle));
            Reply("READY");
            var reader=new Thread(delegate() {
                try { using(var input=new StreamReader(Console.OpenStandardInput())) {
                    string line;
                    while ((line=input.ReadLine())!=null) {
                        if (line=="stop") break;
                        commands.Enqueue(line);
                    }
                }} catch(IOException) { } finally { stopped=true; }
            });
            reader.IsBackground=true; reader.Start();
            while (!stopped && !owner.HasExited) {
                if (!TrayExists()) throw new InvalidOperationException("Tray icon disappeared; restoring normal taskbar access.");
                string line;
                while(commands.TryDequeue(out line)) {
                    if (line.StartsWith("add ") && long.TryParse(line.Substring(4),out handle)) {
                        Apply(new IntPtr(handle));
                    } else if (line=="inspect") {
                        var entries=new List<string>();
                        foreach(var pair in originals)
                            if (Owned(pair.Key)) entries.Add(pair.Key.ToInt64()+":"+GetStyle(pair.Key,ExStyle).ToInt64()+":"+(IsWindowVisible(pair.Key)?1:0)+":"+(IsIconic(pair.Key)?1:0));
                        Reply("STATE "+String.Join(";",entries.ToArray()));
                    } else if (line=="restore") {
                        if (!Owned(mainWindow)) throw new InvalidOperationException("The owner's main window no longer exists.");
                        ShowWindow(mainWindow,9); // SW_RESTORE also restores WS_VISIBLE.
                        Apply(mainWindow);
                    } else throw new FormatException("Invalid taskbar command.");
                }
                foreach(var window in new List<IntPtr>(originals.Keys)) {
                    if (!Owned(window)) { originals.Remove(window); continue; }
                    long current=GetStyle(window,ExStyle).ToInt64();
                    if ((current&Mask)!=ToolWindow) Apply(window);
                }
                Thread.Sleep(40);
            }
            return 0;
        } catch(Exception error) { Reply("ERROR "+error.Message); return 1; }
        finally {
            foreach(var pair in originals) {
                if (!Owned(pair.Key)) continue;
                try {
                    long current=GetStyle(pair.Key,ExStyle).ToInt64();
                    Change(pair.Key,(current&~Mask)|pair.Value);
                    if ((pair.Value&ToolWindow)==0 && IsWindowVisible(pair.Key) && taskbar!=null) taskbar.AddTab(pair.Key);
                } catch(Exception) { }
            }
            // A broken tray route must not strand the minimized main window.
            if (Owned(mainWindow) && IsIconic(mainWindow)) ShowWindow(mainWindow,9);
            if (taskbar!=null) Marshal.ReleaseComObject(taskbar);
            if (owner!=null) owner.Dispose();
        }
    }
}
