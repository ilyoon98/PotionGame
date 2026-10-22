// One named Windows mutex per user/game identity. No windows, registry or saves.
using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;

internal static class SingleInstanceGuard
{
    static volatile bool stopped;

    static int Main(string[] args)
    {
        if (args.Length != 2 || !Regex.IsMatch(args[1], @"^Local\\MoonshadePotionShop\.Instance\.[a-f0-9]{32}$")) return 2;
        int ownerId;
        if (!int.TryParse(args[0], out ownerId) || ownerId <= 0) return 2;
        Mutex mutex = null;
        Process owner = null;
        bool acquired = false;
        try
        {
            owner = Process.GetProcessById(ownerId);
            if (owner.HasExited) return 3;
            // Keep a handle to this exact owner process, so PID reuse cannot retain it.
            IntPtr ownerHandle = owner.Handle;
            mutex = new Mutex(false, args[1]);
            try { acquired = mutex.WaitOne(0); }
            catch (AbandonedMutexException) { acquired = true; }
            Console.Out.WriteLine(acquired ? "OWNER" : "DUPLICATE");
            Console.Out.Flush();
            if (!acquired) return 0;
            var input = new Thread(delegate() {
                try { using (var reader = new StreamReader(Console.OpenStandardInput())) { reader.ReadLine(); } }
                catch (IOException) { }
                finally { stopped = true; }
            });
            input.IsBackground = true;
            input.Start();
            while (!stopped && !owner.HasExited) Thread.Sleep(20);
            return 0;
        }
        catch (Exception)
        {
            Console.Out.WriteLine("ERROR");
            Console.Out.Flush();
            return 1;
        }
        finally
        {
            // Release on the same thread that acquired the mutex.
            if (acquired && mutex != null) mutex.ReleaseMutex();
            if (mutex != null) mutex.Dispose();
            if (owner != null) owner.Dispose();
        }
    }
}
