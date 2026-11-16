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

$tests = @(
    'Test-TaskbarRoundTrip'
)

# ---- Runner ----
$origTaskbar = $null
try { $origTaskbar = Get-TaskbarAutoHide } catch { }

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

if ($script:Failures -gt 0) { Write-Host "$script:Failures test(s) failed"; exit 1 }
Write-Host 'All tests passed'
exit 0
