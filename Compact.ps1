# Compact mode: taskbar auto-hide $true, display scale 175%.
. (Join-Path $PSScriptRoot 'ShowFatal.ps1')
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'DisplayModes.ps1')
    $ok = Set-DisplayMode -AutoHide $true -Percent 175
} catch {
    Show-FatalError 'Compact' $_.Exception.Message
    exit 1
}
if ($ok) { exit 0 } else { exit 1 }
