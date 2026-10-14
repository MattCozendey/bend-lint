# The hosted pointer, end to end, driven from Windows.
#
#   powershell -ExecutionPolicy Bypass -File lab\native\pointer\host-probe.ps1
#
# What it runs is the client's own chain: lab/native/pointer/look_probe.bend, started in WSL
# from the repository root, opens the client's window, starts native/pointer-host.ps1 through
# interop and reads its lines through native/pointer.c into the client's tick. The probe's
# window lives in an Xvfb display, so this script supplies the one thing the host script
# needs from the desktop: a window in front whose title starts with the client's. It then
# moves the real cursor by a known amount and prints every yaw the client's camera held.
#
# The cursor is placed three pixels off the window's centre and the script waits for it to be
# pulled back, which is the host script taking it. Then eight steps of +10 px, a pause and
# eight of -10 px, each of which the host script must pull back to the centre. The camera
# must turn by 80 px of look and return: yaw 0 up to 960 and back to 0, in ten-thousandths
# of a radian, with `pointer=host` above it.
#
# This takes the mouse for about five seconds and shows a small window while it does.
param([string]$Title = 'Bend2Craft native (host probe)')

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$scratch = Join-Path $root 'scratchpad\pointer'
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$log = Join-Path $scratch 'host-probe.out'
$errors = Join-Path $scratch 'host-probe.err'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class HostProbe {
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
}
'@
[HostProbe]::SetProcessDPIAware() | Out-Null

function Wait-Pumping([int]$milliseconds) {
  $until = [DateTime]::UtcNow.AddMilliseconds($milliseconds)
  while ([DateTime]::UtcNow -lt $until) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 5
  }
}

$wslRoot = (& wsl.exe wslpath -a ($root -replace '\\', '/')).Trim()
& wsl.exe bash "$wslRoot/lab/native/pointer/look-probe.sh" build
if ($LASTEXITCODE -ne 0) { throw 'the look probe did not build' }

$started = [DateTime]::UtcNow
$probe = Start-Process -FilePath 'wsl.exe' `
  -ArgumentList @('env', 'BUILD=0', 'bash', "$wslRoot/lab/native/pointer/look-probe.sh", 'host') `
  -RedirectStandardOutput $log -RedirectStandardError $errors -WindowStyle Hidden -PassThru

$form = New-Object System.Windows.Forms.Form
$form.Text = $Title
$form.Width = 420
$form.Height = 420
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.Show()
Wait-Pumping 300
# A background process may not take the foreground; an Alt tap is what lifts that lock.
[HostProbe]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
[HostProbe]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
[HostProbe]::SetForegroundWindow($form.Handle) | Out-Null
Wait-Pumping 300
$front = [HostProbe]::GetForegroundWindow() -eq $form.Handle
Write-Output "foreground=$front"

$rect = New-Object HostProbe+RECT
[HostProbe]::GetWindowRect($form.Handle, [ref]$rect) | Out-Null
$cx = [int](($rect.Left + $rect.Right) / 2)
$cy = [int](($rect.Top + $rect.Bottom) / 2)
$point = New-Object HostProbe+POINT

# Three pixels off the centre, and wait to be pulled back: that is the host taking the cursor.
$held = $false
[HostProbe]::SetCursorPos($cx + 3, $cy) | Out-Null
$until = [DateTime]::UtcNow.AddSeconds(12)
while (-not $held -and [DateTime]::UtcNow -lt $until) {
  Wait-Pumping 50
  [HostProbe]::GetCursorPos([ref]$point) | Out-Null
  $held = ($point.X -eq $cx -and $point.Y -eq $cy)
}
$took = [int]([DateTime]::UtcNow - $started).TotalMilliseconds
Write-Output "host_took_cursor=$held after_ms=$took"

$returned = 0
if ($held) {
  foreach ($step in @(10, 10, 10, 10, 10, 10, 10, 10, 0, -10, -10, -10, -10, -10, -10, -10, -10)) {
    if ($step -eq 0) { Wait-Pumping 500; continue }
    [HostProbe]::SetCursorPos($cx + $step, $cy) | Out-Null
    Wait-Pumping 100
    [HostProbe]::GetCursorPos([ref]$point) | Out-Null
    if ($point.X -eq $cx -and $point.Y -eq $cy) { $returned += 1 }
  }
}
Write-Output "steps_pulled_back=$returned of 16"
Wait-Pumping 500
$form.Close()

if (-not $probe.WaitForExit(30000)) { $probe.Kill(); Write-Output 'the probe did not finish' }
Get-Content $log
$err = Get-Content $errors -ErrorAction SilentlyContinue
if ($err) { Write-Output '--- stderr'; $err }
