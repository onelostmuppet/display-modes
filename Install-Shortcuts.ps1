# Creates Compact.lnk and Roomy.lnk in this folder. Safe to re-run (overwrites). Re-run if the folder moves.
# Usage: powershell -ExecutionPolicy Bypass -File Install-Shortcuts.ps1
$ErrorActionPreference = 'Stop'
$folder = $PSScriptRoot
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$wsh = New-Object -ComObject WScript.Shell

# Custom icons live in icons\ (regenerate with tools\New-Icons.ps1): teal "175" = Compact, indigo "225" = Roomy.
$modes = @(
    @{ Name = 'Compact'; Description = 'Compact desktop: taskbar auto-hide on, 175% scale' }
    @{ Name = 'Roomy';   Description = 'Roomy desktop: taskbar auto-hide off, 225% scale' }
)

foreach ($m in $modes) {
    $script = Join-Path $folder "$($m.Name).ps1"
    if (-not (Test-Path -LiteralPath $script)) { throw "Missing $script" }
    $icon = Join-Path $folder "icons\$($m.Name).ico"
    if (-not (Test-Path -LiteralPath $icon)) { throw "Missing $icon (run tools\New-Icons.ps1)" }
    $lnkPath = Join-Path $folder "$($m.Name).lnk"
    $lnk = $wsh.CreateShortcut($lnkPath)
    $lnk.TargetPath = $powershell
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
    $lnk.WorkingDirectory = $folder
    $lnk.IconLocation = "$icon,0"
    $lnk.Description = $m.Description
    $lnk.WindowStyle = 7  # minimized; belt and braces alongside -WindowStyle Hidden
    $lnk.Save()
    Write-Host "Wrote $lnkPath"
}
