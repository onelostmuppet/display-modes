# Minimal, dependency-free fatal-error reporter for the mode scripts. Dot-source only.
# Test override: if $env:DISPLAYMODES_CAPTURE_FILE is set, the message is appended to that file
# instead of showing a MessageBox.
function Show-FatalError {
    param([string]$Mode, [string]$Message)
    $text = "$Mode mode failed: $Message"
    if ($env:DISPLAYMODES_CAPTURE_FILE) {
        Add-Content -LiteralPath $env:DISPLAYMODES_CAPTURE_FILE -Value $text
        return
    }
    Add-Type -AssemblyName System.Windows.Forms
    $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
    try {
        [void][System.Windows.Forms.MessageBox]::Show($owner, $text, 'Display Modes', 'OK', 'Error')
    } finally { $owner.Dispose() }
}
