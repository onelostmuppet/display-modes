# Creates Compact.lnk and Roomy.lnk in this folder. Safe to re-run (overwrites). Re-run if the folder moves.
# Usage: powershell -ExecutionPolicy Bypass -File Install-Shortcuts.ps1
$ErrorActionPreference = 'Stop'
$folder = $PSScriptRoot
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$wsh = New-Object -ComObject WScript.Shell

# imageres.dll icons: 226 = arrows pointing inward (Compact), 225 = arrows pointing outward (Roomy).
$modes = @(
    @{ Name = 'Compact'; Icon = 226; Description = 'Compact desktop: taskbar auto-hide on, 175% scale' }
    @{ Name = 'Roomy';   Icon = 225; Description = 'Roomy desktop: taskbar auto-hide off, 225% scale' }
)

foreach ($m in $modes) {
    $script = Join-Path $folder "$($m.Name).ps1"
    if (-not (Test-Path -LiteralPath $script)) { throw "Missing $script" }
    $lnkPath = Join-Path $folder "$($m.Name).lnk"
    $lnk = $wsh.CreateShortcut($lnkPath)
    $lnk.TargetPath = $powershell
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
    $lnk.WorkingDirectory = $folder
    $lnk.IconLocation = "imageres.dll,$($m.Icon)"
    $lnk.Description = $m.Description
    $lnk.WindowStyle = 7  # minimized; belt and braces alongside -WindowStyle Hidden
    $lnk.Save()
    Write-Host "Wrote $lnkPath"
}
