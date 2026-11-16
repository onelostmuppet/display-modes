# Roomy mode: taskbar auto-hide $false, display scale 225%.
. (Join-Path $PSScriptRoot 'ShowFatal.ps1')
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'DisplayModes.ps1')
    $ok = Set-DisplayMode -AutoHide $false -Percent 225
} catch {
    Show-FatalError 'Roomy' $_.Exception.Message
    exit 1
}
if ($ok) { exit 0 } else { exit 1 }
