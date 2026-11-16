# Roomy mode: taskbar auto-hide $false, display scale 225%.
. (Join-Path $PSScriptRoot 'DisplayModes.ps1')
if (Set-DisplayMode -AutoHide $false -Percent 225) { exit 0 } else { exit 1 }
