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

if (-not ('DisplayModesNative.DisplayConfig' -as [type])) {
    # Undocumented DPI scale get/set via DisplayConfig{Get,Set}DeviceInfo (types -3 / -4), as used by SetDPI.
    Add-Type -Namespace DisplayModesNative -Name DisplayConfig -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct LUID { public uint LowPart; public int HighPart; }

[StructLayout(LayoutKind.Sequential, Size = 72)]
public struct PATH_INFO {
    public LUID sourceAdapterId; public uint sourceId; public uint sourceModeInfoIdx; public uint sourceStatusFlags;
    public LUID targetAdapterId; public uint targetId; public uint targetModeInfoIdx; public uint outputTechnology;
    public uint rotation; public uint scaling; public uint refreshNum; public uint refreshDen;
    public uint scanLineOrdering; public int targetAvailable; public uint targetStatusFlags;
    public uint flags;
}

[StructLayout(LayoutKind.Explicit, Size = 64)]
public struct MODE_INFO {
    [FieldOffset(0)] public uint infoType;   // 1 = SOURCE
    [FieldOffset(4)] public uint id;
    [FieldOffset(8)] public LUID adapterId;
    [FieldOffset(16)] public uint width;     // sourceMode fields (valid when infoType == 1)
    [FieldOffset(20)] public uint height;
    [FieldOffset(24)] public uint pixelFormat;
    [FieldOffset(28)] public int positionX;
    [FieldOffset(32)] public int positionY;
}

[StructLayout(LayoutKind.Sequential)]
public struct DEVICE_INFO_HEADER { public int type; public uint size; public LUID adapterId; public uint id; }

[StructLayout(LayoutKind.Sequential)]
public struct GET_DPI_SCALE { public DEVICE_INFO_HEADER header; public int minScaleRel; public int curScaleRel; public int maxScaleRel; }

[StructLayout(LayoutKind.Sequential)]
public struct SET_DPI_SCALE { public DEVICE_INFO_HEADER header; public int scaleRel; }

[DllImport("user32.dll")]
public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);
[DllImport("user32.dll")]
public static extern int QueryDisplayConfig(uint flags, ref uint numPathArrayElements, [Out] PATH_INFO[] pathArray,
    ref uint numModeInfoArrayElements, [Out] MODE_INFO[] modeInfoArray, IntPtr currentTopologyId);
[DllImport("user32.dll")]
public static extern int DisplayConfigGetDeviceInfo(ref GET_DPI_SCALE requestPacket);
[DllImport("user32.dll")]
public static extern int DisplayConfigSetDeviceInfo(ref SET_DPI_SCALE setPacket);
'@
}

$script:DisplayScalePercents = @(100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500)

function Get-PrimaryDisplaySource {
    # Returns the source mode (adapter LUID + source id) of the active path positioned at (0,0).
    $qdcOnlyActivePaths = 2
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $numPaths = [uint32]0; $numModes = [uint32]0
        $rc = [DisplayModesNative.DisplayConfig]::GetDisplayConfigBufferSizes($qdcOnlyActivePaths, [ref]$numPaths, [ref]$numModes)
        if ($rc -ne 0) { throw "GetDisplayConfigBufferSizes failed ($rc)" }
        $paths = New-Object 'DisplayModesNative.DisplayConfig+PATH_INFO[]' $numPaths
        $modes = New-Object 'DisplayModesNative.DisplayConfig+MODE_INFO[]' $numModes
        $rc = [DisplayModesNative.DisplayConfig]::QueryDisplayConfig($qdcOnlyActivePaths, [ref]$numPaths, $paths, [ref]$numModes, $modes, [IntPtr]::Zero)
        if ($rc -eq 122) { continue }  # ERROR_INSUFFICIENT_BUFFER: topology changed, retry
        if ($rc -ne 0) { throw "QueryDisplayConfig failed ($rc)" }
        for ($i = 0; $i -lt $numPaths; $i++) {
            $idx = $paths[$i].sourceModeInfoIdx
            if ($idx -ge $numModes) { continue }
            $m = $modes[$idx]
            if ($m.infoType -eq 1 -and $m.positionX -eq 0 -and $m.positionY -eq 0) { return $m }
        }
        throw 'No active primary display (source at 0,0) found'
    }
    throw 'QueryDisplayConfig kept reporting insufficient buffer'
}

function New-DisplayDeviceInfoHeader {
    # Built standalone: assigning $pkt.header.x in PowerShell would only modify a boxed copy.
    param([int]$Type, [type]$PacketType, $Source)
    $h = New-Object DisplayModesNative.DisplayConfig+DEVICE_INFO_HEADER
    $h.type = $Type
    $h.size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]$PacketType)
    $h.adapterId = $Source.adapterId
    $h.id = $Source.id
    return $h
}

function Get-DisplayScaleInfo {
    $src = Get-PrimaryDisplaySource
    $pkt = New-Object DisplayModesNative.DisplayConfig+GET_DPI_SCALE
    # -3 = DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE
    $pkt.header = New-DisplayDeviceInfoHeader -Type -3 -PacketType ([DisplayModesNative.DisplayConfig+GET_DPI_SCALE]) -Source $src
    $rc = [DisplayModesNative.DisplayConfig]::DisplayConfigGetDeviceInfo([ref]$pkt)
    if ($rc -ne 0) { throw "DisplayConfigGetDeviceInfo(GET_DPI_SCALE) failed ($rc)" }
    $list = $script:DisplayScalePercents
    $rec = -$pkt.minScaleRel
    $cur = [math]::Max(0, [math]::Min($list.Count - 1, $rec + $pkt.curScaleRel))
    $hi = [math]::Min($list.Count - 1, $rec + $pkt.maxScaleRel)
    return [pscustomobject]@{
        Source           = $src
        RecommendedIndex = $rec
        Current          = $list[$cur]
        Supported        = @($list[0..$hi])
    }
}

function Get-DisplayScale {
    return [int](Get-DisplayScaleInfo).Current
}

function Set-DisplayScale {
    param([Parameter(Mandatory)][int]$Percent)
    $info = Get-DisplayScaleInfo
    $idx = [array]::IndexOf($script:DisplayScalePercents, $Percent)
    if ($info.Supported -notcontains $Percent -or $idx -lt 0) {
        throw "Scale $Percent% is not supported on the primary display. Supported: $($info.Supported -join ', ')"
    }
    $pkt = New-Object DisplayModesNative.DisplayConfig+SET_DPI_SCALE
    # -4 = DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE
    $pkt.header = New-DisplayDeviceInfoHeader -Type -4 -PacketType ([DisplayModesNative.DisplayConfig+SET_DPI_SCALE]) -Source $info.Source
    $pkt.scaleRel = $idx - $info.RecommendedIndex
    $rc = [DisplayModesNative.DisplayConfig]::DisplayConfigSetDeviceInfo([ref]$pkt)
    if ($rc -ne 0) { throw "DisplayConfigSetDeviceInfo(SET_DPI_SCALE) failed ($rc)" }
    $now = Get-DisplayScale
    $deadline = (Get-Date).AddSeconds(2)
    while ($now -ne $Percent -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 100
        $now = Get-DisplayScale
    }
    return $now
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
