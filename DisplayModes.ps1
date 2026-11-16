# DisplayModes helper functions. Dot-source only; no side effects. PowerShell 5.1 compatible.

if (-not ('DisplayModesNative.Taskbar' -as [type])) {
    Add-Type -Namespace DisplayModesNative -Name Taskbar -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct APPBARDATA {
    public int cbSize;
    public IntPtr hWnd;
    public uint uCallbackMessage;
    public uint uEdge;
    public int left, top, right, bottom;
    public IntPtr lParam;
}
[DllImport("shell32.dll")]
public static extern UIntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
'@
}

function Get-TaskbarHandle {
    $h = [DisplayModesNative.Taskbar]::FindWindow('Shell_TrayWnd', $null)
    if ($h -eq [IntPtr]::Zero) { throw 'Shell_TrayWnd window not found' }
    return $h
}

function Get-TaskbarState {
    $abd = New-Object DisplayModesNative.Taskbar+APPBARDATA
    $abd.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][DisplayModesNative.Taskbar+APPBARDATA])
    $abd.hWnd = Get-TaskbarHandle
    return [int][DisplayModesNative.Taskbar]::SHAppBarMessage(4, [ref]$abd).ToUInt32()  # ABM_GETSTATE
}

function Get-TaskbarAutoHide {
    return [bool]((Get-TaskbarState) -band 1)  # ABS_AUTOHIDE
}

function Set-TaskbarAutoHide {
    param([Parameter(Mandatory)][bool]$Enabled)
    $state = (Get-TaskbarState) -band (-bnot 1)  # keep ABS_ALWAYSONTOP (2), clear autohide
    if ($Enabled) { $state = $state -bor 1 }
    $abd = New-Object DisplayModesNative.Taskbar+APPBARDATA
    $abd.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][DisplayModesNative.Taskbar+APPBARDATA])
    $abd.hWnd = Get-TaskbarHandle
    $abd.lParam = [IntPtr]$state
    [void][DisplayModesNative.Taskbar]::SHAppBarMessage(10, [ref]$abd)  # ABM_SETSTATE
    Start-Sleep -Milliseconds 300
    return (Get-TaskbarAutoHide)
}
