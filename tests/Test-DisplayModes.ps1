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

function Test-ScaleCurrent {
    $dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name AppliedDPI).AppliedDPI
    $expected = [int][math]::Round($dpi / 96 * 100)
    Assert-Equal (Get-DisplayScale) $expected "Get-DisplayScale vs AppliedDPI $dpi"
}

function Test-ScaleRoundTrip {
    $orig = Get-DisplayScale
    try {
        foreach ($want in @(175, 225)) {
            $ret = Set-DisplayScale -Percent $want
            Assert-Equal $ret $want "Set-DisplayScale -Percent $want return value"
            Assert-Equal (Get-DisplayScale) $want "Get-DisplayScale after setting $want"
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

$tests = @(
    'Test-TaskbarRoundTrip'
    'Test-ScaleCurrent'
    'Test-ScaleRoundTrip'
    'Test-ScaleUnsupported'
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
