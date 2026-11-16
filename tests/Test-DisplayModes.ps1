# Plain assertion test runner (no Pester). Windows PowerShell 5.1 compatible.
# Usage: powershell -NoProfile -File tests\Test-DisplayModes.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'DisplayModes.ps1')

$script:Failures = 0

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

# ---- Tests: add new Test-* functions below and list them in $tests ----

function Test-TaskbarRoundTrip {
    foreach ($want in @($true, $false)) {
        $ret = Set-TaskbarAutoHide -Enabled $want
        Assert-Equal $ret $want "Set-TaskbarAutoHide -Enabled $want return value"
        Assert-Equal (Get-TaskbarAutoHide) $want "Get-TaskbarAutoHide after setting $want"
    }
}

# Independent oracle: a fresh per-monitor-v2 DPI-aware child process reads the primary monitor's
# effective DPI. (AppliedDPI in the registry only updates at sign-in, so it cannot be used.)
$script:LiveDpiChild = @'
$ProgressPreference = 'SilentlyContinue'  # keep progress CLIXML out of the parent's console
Add-Type -Namespace LiveDpi -Name Native -MemberDefinition @"
[DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr value);
[DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(long pt, uint flags);
[DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);
"@
if ([LiveDpi.Native]::SetProcessDpiAwarenessContext([IntPtr](-4)) -eq [IntPtr]::Zero) { throw 'SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2) failed' }
$mon = [LiveDpi.Native]::MonitorFromPoint(0, 1)  # point (0,0), MONITOR_DEFAULTTOPRIMARY
$x = [uint32]0; $y = [uint32]0
$hr = [LiveDpi.Native]::GetDpiForMonitor($mon, 0, [ref]$x, [ref]$y)  # MDT_EFFECTIVE_DPI
if ($hr -ne 0) { throw "GetDpiForMonitor failed ($hr)" }
[int][math]::Round($x / 96 * 100)
'@

function Get-LiveDisplayScale {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script:LiveDpiChild))
    $out = & powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded
    if ($LASTEXITCODE -ne 0) { throw "Live DPI child process failed: $out" }
    return [int]($out | Select-Object -Last 1)
}

function Wait-LiveDisplayScale([int]$Expected) {
    # Poll up to ~2s in case the live DPI lags the set call; returns the last value seen.
    $deadline = (Get-Date).AddSeconds(2)
    $live = Get-LiveDisplayScale
    while ($live -ne $Expected -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 200
        $live = Get-LiveDisplayScale
    }
    return $live
}

function Test-ScaleCurrent {
    $api = Get-DisplayScale
    Assert-Equal (Wait-LiveDisplayScale $api) $api 'Get-DisplayScale vs live monitor DPI'
}

function Test-ScaleRoundTrip {
    $orig = Get-DisplayScale
    try {
        foreach ($want in @(175, 225)) {
            $ret = Set-DisplayScale -Percent $want
            Assert-Equal $ret $want "Set-DisplayScale -Percent $want return value"
            Assert-Equal (Get-DisplayScale) $want "Get-DisplayScale after setting $want"
            Assert-Equal (Wait-LiveDisplayScale $want) $want "Live monitor DPI after setting $want"
        }
    } finally {
        if ((Get-DisplayScale) -ne $orig) { [void](Set-DisplayScale -Percent $orig) }
    }
}

function Test-ScaleUnsupported {
    $before = Get-DisplayScale
    $threw = $false
    try { [void](Set-DisplayScale -Percent 137) } catch { $threw = $true; $msg = $_.Exception.Message }
    Assert-Equal $threw $true 'Set-DisplayScale -Percent 137 should throw'
    if ($msg -notmatch '175' -or $msg -notmatch '225') { throw "Error message should list supported percentages, got: $msg" }
    Assert-Equal (Get-DisplayScale) $before 'Scale unchanged after unsupported request'
}

function Test-ModeApplies {
    $origAH = Get-TaskbarAutoHide; $origScale = Get-DisplayScale
    $saved = $script:ShowError
    $script:ShowError = { param($m) throw "ShowError must not fire on success: $m" }
    try {
        foreach ($mode in @(@{ AH = $true; P = 175 }, @{ AH = $false; P = 225 })) {
            $ret = Set-DisplayMode -AutoHide $mode.AH -Percent $mode.P
            Assert-Equal $ret $true "Set-DisplayMode $($mode.AH)/$($mode.P) return value"
            Assert-Equal (Get-TaskbarAutoHide) $mode.AH "Auto-hide after mode $($mode.AH)/$($mode.P)"
            Assert-Equal (Get-DisplayScale) $mode.P "Scale after mode $($mode.AH)/$($mode.P)"
            Assert-Equal (Wait-LiveDisplayScale $mode.P) $mode.P "Live DPI after mode $($mode.AH)/$($mode.P)"
        }
    } finally {
        $script:ShowError = $saved
        if ((Get-TaskbarAutoHide) -ne $origAH) { [void](Set-TaskbarAutoHide -Enabled $origAH) }
        if ((Get-DisplayScale) -ne $origScale) { [void](Set-DisplayScale -Percent $origScale) }
    }
}

function Test-ModeIdempotent {
    $origAH = Get-TaskbarAutoHide; $origScale = Get-DisplayScale
    $realTaskbar = (Get-Command Set-TaskbarAutoHide -CommandType Function).ScriptBlock
    $realScale = (Get-Command Set-DisplayScale -CommandType Function).ScriptBlock
    $saved = $script:ShowError
    try {
        $script:ShowError = { param($m) throw "ShowError must not fire: $m" }
        Assert-Equal (Set-DisplayMode -AutoHide $true -Percent 175) $true 'First call to reach compact'
        $script:TaskbarCalls = 0; $script:ScaleCalls = 0
        function script:Set-TaskbarAutoHide { param([bool]$Enabled) $script:TaskbarCalls++; return $Enabled }
        function script:Set-DisplayScale { param([int]$Percent) $script:ScaleCalls++; return $Percent }
        $ret = Set-DisplayMode -AutoHide $true -Percent 175
        Assert-Equal $ret $true 'Second call to already-active mode returns true'
        Assert-Equal $script:TaskbarCalls 0 'Set-TaskbarAutoHide calls on already-active mode'
        Assert-Equal $script:ScaleCalls 0 'Set-DisplayScale calls on already-active mode'
    } finally {
        Set-Item -Path 'function:script:Set-TaskbarAutoHide' -Value $realTaskbar
        Set-Item -Path 'function:script:Set-DisplayScale' -Value $realScale
        $script:ShowError = $saved
        if ((Get-TaskbarAutoHide) -ne $origAH) { [void](Set-TaskbarAutoHide -Enabled $origAH) }
        if ((Get-DisplayScale) -ne $origScale) { [void](Set-DisplayScale -Percent $origScale) }
    }
}

function Test-ModeReportsFailure {
    $origAH = Get-TaskbarAutoHide; $origScale = Get-DisplayScale
    $realTaskbar = (Get-Command Set-TaskbarAutoHide -CommandType Function).ScriptBlock
    $realScale = (Get-Command Set-DisplayScale -CommandType Function).ScriptBlock
    $saved = $script:ShowError
    try {
        $script:Messages = @()
        $script:ShowError = { param($m) $script:Messages += $m }
        $wantAH = -not $origAH
        $wantScale = if ($origScale -eq 175) { 225 } else { 175 }

        # Taskbar setter that does not change state
        function script:Set-TaskbarAutoHide { param([bool]$Enabled) return $Enabled }
        $ret = Set-DisplayMode -AutoHide $wantAH -Percent $origScale
        Assert-Equal $ret $false 'Taskbar mismatch returns false'
        Assert-Equal $script:Messages.Count 1 'Taskbar mismatch message count'
        if ($script:Messages[0] -notmatch '(?i)taskbar|auto-?hide') { throw "Message should mention taskbar: $($script:Messages[0])" }
        Set-Item -Path 'function:script:Set-TaskbarAutoHide' -Value $realTaskbar

        # Scale setter that does not change state
        $script:Messages = @()
        function script:Set-DisplayScale { param([int]$Percent) return $Percent }
        $ret = Set-DisplayMode -AutoHide $origAH -Percent $wantScale
        Assert-Equal $ret $false 'Scale mismatch returns false'
        Assert-Equal $script:Messages.Count 1 'Scale mismatch message count'
        if ($script:Messages[0] -notmatch '(?i)scal') { throw "Message should mention scale: $($script:Messages[0])" }
        Set-Item -Path 'function:script:Set-DisplayScale' -Value $realScale

        # Setter that throws
        $script:Messages = @()
        function script:Set-DisplayScale { param([int]$Percent) throw 'boom from stub' }
        $ret = Set-DisplayMode -AutoHide $origAH -Percent $wantScale
        Assert-Equal $ret $false 'Setter exception returns false'
        Assert-Equal $script:Messages.Count 1 'Setter exception message count'
        if ($script:Messages[0] -notmatch 'boom from stub') { throw "Message should include the exception text: $($script:Messages[0])" }
    } finally {
        Set-Item -Path 'function:script:Set-TaskbarAutoHide' -Value $realTaskbar
        Set-Item -Path 'function:script:Set-DisplayScale' -Value $realScale
        $script:ShowError = $saved
        if ((Get-TaskbarAutoHide) -ne $origAH) { [void](Set-TaskbarAutoHide -Enabled $origAH) }
        if ((Get-DisplayScale) -ne $origScale) { [void](Set-DisplayScale -Percent $origScale) }
    }
}

function Test-ModeScriptReportsLoadFailure {
    # Copy Compact.ps1 (+ ShowFatal.ps1) to a folder with no DisplayModes.ps1; capture the message via
    # DISPLAYMODES_CAPTURE_FILE (ShowFatal.ps1 writes there instead of showing a MessageBox).
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("dm-loadfail " + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $dir)
    $capture = Join-Path $dir 'captured.txt'
    $oldEnv = $env:DISPLAYMODES_CAPTURE_FILE
    try {
        Copy-Item (Join-Path $root 'Compact.ps1') $dir
        if (Test-Path (Join-Path $root 'ShowFatal.ps1')) { Copy-Item (Join-Path $root 'ShowFatal.ps1') $dir }
        $env:DISPLAYMODES_CAPTURE_FILE = $capture
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $dir 'Compact.ps1') | Out-Null
        Assert-Equal $LASTEXITCODE 1 'Exit code when helper cannot be loaded'
        if (-not (Test-Path $capture)) { throw 'No error message was reported when the helper could not be loaded' }
        $msg = Get-Content -Raw $capture
        if ($msg -notmatch 'Compact' -or $msg -notmatch 'DisplayModes') { throw "Message should name the mode and the failure, got: $msg" }
    } finally {
        $env:DISPLAYMODES_CAPTURE_FILE = $oldEnv
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
    }
}

function Test-ShortcutsInstall {
    # Run the installer in a temp copy of the project (path contains a space) and read the .lnk files back.
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("dm shortcuts " + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $dir)
    try {
        foreach ($f in 'Install-Shortcuts.ps1', 'Compact.ps1', 'Roomy.ps1') {
            $src = Join-Path $root $f
            if (Test-Path $src) { Copy-Item $src $dir }
        }
        if (Test-Path (Join-Path $root 'icons')) { Copy-Item (Join-Path $root 'icons') $dir -Recurse }
        # Run twice: the installer must be idempotent.
        1..2 | ForEach-Object {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $dir 'Install-Shortcuts.ps1') | Out-Null
            Assert-Equal $LASTEXITCODE 0 'Installer exit code'
        }
        $wsh = New-Object -ComObject WScript.Shell
        $expectedExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $icons = @()
        foreach ($mode in 'Compact', 'Roomy') {
            $lnkPath = Join-Path $dir "$mode.lnk"
            if (-not (Test-Path $lnkPath)) { throw "$mode.lnk was not created" }
            $lnk = $wsh.CreateShortcut($lnkPath)
            Assert-Equal $lnk.TargetPath $expectedExe "$mode.lnk TargetPath"
            foreach ($frag in '-ExecutionPolicy Bypass', '-WindowStyle Hidden', ('-File "' + (Join-Path $dir "$mode.ps1") + '"')) {
                if ($lnk.Arguments -notlike "*$frag*") { throw "$mode.lnk Arguments missing '$frag': $($lnk.Arguments)" }
            }
            Assert-Equal $lnk.WorkingDirectory $dir "$mode.lnk WorkingDirectory"
            $expectedIcon = Join-Path $dir "icons\$mode.ico"
            Assert-Equal $lnk.IconLocation "$expectedIcon,0" "$mode.lnk IconLocation"
            if (-not (Test-Path -LiteralPath $expectedIcon)) { throw "$mode icon file missing: $expectedIcon" }
            $icons += (Get-FileHash -LiteralPath $expectedIcon -Algorithm SHA256).Hash
        }
        if ($icons[0] -eq $icons[1]) { throw 'Compact and Roomy icon files must differ, but their contents are identical' }
    } finally {
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
    }
}

$tests = @(
    'Test-TaskbarRoundTrip'
    'Test-ScaleCurrent'
    'Test-ScaleRoundTrip'
    'Test-ScaleUnsupported'
    'Test-ModeApplies'
    'Test-ModeIdempotent'
    'Test-ModeReportsFailure'
    'Test-ModeScriptReportsLoadFailure'
    'Test-ShortcutsInstall'
)

# ---- Runner ----
$origTaskbar = $null
try { $origTaskbar = Get-TaskbarAutoHide } catch { }
$origScale = $null
try { $origScale = Get-DisplayScale } catch { }

foreach ($t in $tests) {
    try {
        & $t
        Write-Host "PASS $t"
    } catch {
        $script:Failures++
        Write-Host "FAIL $t : $($_.Exception.Message)"
    }
}

# ---- Restore original state ----
if ($null -ne $origTaskbar) {
    try { [void](Set-TaskbarAutoHide -Enabled $origTaskbar) } catch { Write-Host "WARN could not restore taskbar: $($_.Exception.Message)" }
}
if ($null -ne $origScale) {
    try { if ((Get-DisplayScale) -ne $origScale) { [void](Set-DisplayScale -Percent $origScale) } } catch { Write-Host "WARN could not restore scale: $($_.Exception.Message)" }
}

if ($script:Failures -gt 0) { Write-Host "$script:Failures test(s) failed"; exit 1 }
Write-Host 'All tests passed'
exit 0
