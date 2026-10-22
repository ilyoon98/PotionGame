// Headless test surrogate only. Never loads the game, player save or registry.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Web.Script.Serialization;

internal static class SingleInstanceFixture
{
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
    static string folder, id;

    static void Status(Dictionary<string, object> value)
    {
        string path = Path.Combine(folder, id + ".json");
        string temporary = path + ".tmp";
        File.WriteAllText(temporary, Json.Serialize(value));
        if (File.Exists(path)) File.Replace(temporary, path, null);
        else File.Move(temporary, path);
    }

    static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    static int Main(string[] args)
    {
        if (args.Length != 4) return 2;
        string executable = args[0], mutexName = args[1];
        folder = args[2]; id = args[3];
        int pid = Process.GetCurrentProcess().Id;
        Process guard = null;
        try
        {
            Status(new Dictionary<string, object> { {"phase", "ready"}, {"pid", pid} });
            DateTime deadline = DateTime.UtcNow.AddSeconds(30);
            while (!File.Exists(Path.Combine(folder, "gate")))
            {
                if (DateTime.UtcNow >= deadline) return 3;
                Thread.Sleep(10);
            }
            var start = new ProcessStartInfo(executable, pid + " " + Quote(mutexName));
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardInput = true;
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            guard = Process.Start(start);
            string reply = guard.StandardOutput.ReadLine();
            bool owner = reply == "OWNER", ok = owner || reply == "DUPLICATE";
            var status = new Dictionary<string, object> {
                {"phase", "claimed"}, {"pid", pid}, {"helper_pid", guard.Id},
                {"ok", ok}, {"owner", owner}, {"bypassed", false},
                {"effects", owner ? new string[] {"isolated-save", "isolated-login", "isolated-rng"} : new string[0]}
            };
            Status(status);
            if (!ok || !owner) return ok ? 0 : 4;
            deadline = DateTime.UtcNow.AddSeconds(20);
            while (!File.Exists(Path.Combine(folder, "stop-" + id)) && DateTime.UtcNow < deadline)
            {
                if (guard.HasExited)
                {
                    status["phase"] = "lost";
                    Status(status);
                    return 0;
                }
                Thread.Sleep(10);
            }
            guard.StandardInput.Close();
            guard.WaitForExit(3000);
            return 0;
        }
        catch (Exception error)
        {
            Status(new Dictionary<string, object> { {"phase", "error"}, {"pid", pid}, {"error", error.Message} });
            return 1;
        }
        finally
        {
            if (guard != null)
            {
                try { guard.StandardInput.Close(); } catch (IOException) { }
                guard.Dispose();
            }
        }
    }
}
