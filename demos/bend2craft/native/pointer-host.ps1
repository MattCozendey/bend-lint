# The Windows side of native/pointer.bend.
#
# WSLg cannot report relative mouse motion, so the native client starts this script through
# WSL interop and reads its output. While the client's window is in front and the cursor is
# inside it, the script holds the cursor at the window's centre and writes every
# displacement from that centre as one line, "dx dy", in pixels. Those lines are the whole
# protocol; what they mean is decided in native/pointer.bend.
#
# The cursor is only taken once it is inside the window below the title bar, so the title
# bar stays usable for moving or closing the window, and it is let go the moment another
# window comes to the front. The script ends when the client's window is gone, when its
# output is closed, or when no window with the title appears within a minute.
param([Parameter(Mandatory = $true)][string]$Title)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class PointerHost {
  [StructLayout(LayoutKind.Sequential)]
  struct POINT { public int X; public int Y; }

  [StructLayout(LayoutKind.Sequential)]
  struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

  [DllImport("user32.dll")]
  static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
  [DllImport("user32.dll")]
  static extern bool GetWindowRect(IntPtr window, out RECT rect);
  [DllImport("user32.dll")]
  static extern bool IsWindow(IntPtr window);
  [DllImport("user32.dll")]
  static extern bool GetCursorPos(out POINT point);
  [DllImport("user32.dll")]
  static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")]
  static extern bool SetProcessDPIAware();
  [DllImport("winmm.dll")]
  static extern uint timeBeginPeriod(uint milliseconds);

  // The frame a window manager draws around the client area: the cursor is not taken
  // while it is over the title bar or a border.
  const int Border = 8;
  const int TitleBar = 40;

  public static void Run(string title) {
    // Physical pixels, so a scaled display does not quantize the movement.
    SetProcessDPIAware();
    timeBeginPeriod(1);
    StreamWriter output = new StreamWriter(Console.OpenStandardOutput(), Encoding.ASCII);
    StringBuilder name = new StringBuilder(512);
    IntPtr seen = IntPtr.Zero;
    bool held = false;
    int waited = 0;
    for (;;) {
      Thread.Sleep(2);
      IntPtr front = GetForegroundWindow();
      bool ours = false;
      if (front != IntPtr.Zero) {
        name.Length = 0;
        GetWindowText(front, name, name.Capacity);
        ours = name.ToString().StartsWith(title, StringComparison.Ordinal);
      }
      if (ours) {
        seen = front;
      }
      if (seen == IntPtr.Zero) {
        waited += 2;
        if (waited > 60000) {
          return;
        }
        continue;
      }
      if (!IsWindow(seen)) {
        return;
      }
      if (!ours) {
        held = false;
        continue;
      }
      RECT rect;
      POINT point;
      if (!GetWindowRect(front, out rect) || !GetCursorPos(out point)) {
        continue;
      }
      int cx = (rect.Left + rect.Right) / 2;
      int cy = (rect.Top + rect.Bottom) / 2;
      if (!held) {
        bool inside = point.X > rect.Left + Border && point.X < rect.Right - Border
          && point.Y > rect.Top + TitleBar && point.Y < rect.Bottom - Border;
        if (inside) {
          held = true;
          SetCursorPos(cx, cy);
        }
        continue;
      }
      int dx = point.X - cx;
      int dy = point.Y - cy;
      if (dx != 0 || dy != 0) {
        try {
          output.Write(dx + " " + dy + "\n");
          output.Flush();
        } catch (IOException) {
          return;
        }
        SetCursorPos(cx, cy);
      }
    }
  }
}
'@

[PointerHost]::Run($Title)
