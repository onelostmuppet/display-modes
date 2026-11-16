# Compact mode: taskbar auto-hide $true, display scale 175%.
. (Join-Path $PSScriptRoot 'DisplayModes.ps1')
if (Set-DisplayMode -AutoHide $true -Percent 175) { exit 0 } else { exit 1 }
