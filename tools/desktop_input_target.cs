using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
internal class DesktopInputTarget : Form
{
    readonly string path;
    int clicks;
    DesktopInputTarget(string status)
    {
        path=status;
        Text="Potion shop isolated input target";
        StartPosition=FormStartPosition.Manual;
        Location=new Point(80,80);
        Size=new Size(1100,850);
        BackColor=Color.FromArgb(225,238,220);
        TopMost=true;
    }
    void Record() { File.WriteAllText(path,"{\"window\":"+Handle.ToInt64()+",\"clicks\":"+clicks+"}"); }
    protected override void OnShown(EventArgs e) { base.OnShown(e); Record(); }
    protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); clicks++; Record(); }
    [STAThread] static void Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.Run(new DesktopInputTarget(args[0]));
    }
}
