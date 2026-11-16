# Regenerates icons\Compact.ico and icons\Roomy.ico (multi-size, PNG-compressed). The .ico files are committed,
# so you only need to run this if you want to change the look.
# Usage: powershell -ExecutionPolicy Bypass -File tools\New-Icons.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'icons'
[void](New-Item -ItemType Directory -Force -Path $outDir)

# Compact = teal, "175", no taskbar strip (the taskbar is hidden). Roomy = indigo, "225", solid taskbar strip.
$modes = @(
    @{ Name = 'Compact'; Text = '175'; Color = [System.Drawing.Color]::FromArgb(255, 15, 140, 125); Bar = $false }
    @{ Name = 'Roomy';   Text = '225'; Color = [System.Drawing.Color]::FromArgb(255, 70, 80, 200);   Bar = $true }
)
$sizes = 16, 24, 32, 48, 64, 128, 256

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-IconPng([int]$size, $mode) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = 'AntiAlias'
        $g.TextRenderingHint = 'AntiAliasGridFit'
        $g.Clear([System.Drawing.Color]::Transparent)

        # Rounded square background.
        $pad = [math]::Max(0.5, $size * 0.03)
        $path = New-RoundedRectPath $pad $pad ($size - 2 * $pad) ($size - 2 * $pad) ($size * 0.18)
        $bg = New-Object System.Drawing.SolidBrush($mode.Color)
        $g.FillPath($bg, $path)

        # Taskbar strip along the bottom for Roomy (omitted when too small to read).
        $textBottom = $size
        if ($mode.Bar -and $size -ge 32) {
            $barH = $size * 0.14
            $g.SetClip($path)
            $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 255, 255, 255))
            $g.FillRectangle($white, 0, $size - $pad - $barH, $size, $barH + $pad)
            $g.ResetClip()
            $textBottom = $size - $barH
        }

        # Percent number, as large as fits (about 82% of the width), centred in the area above any strip.
        $family = New-Object System.Drawing.FontFamily('Segoe UI')
        $fontSize = $size * 0.40
        $font = New-Object System.Drawing.Font($family, $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $w = $g.MeasureString($mode.Text, $font).Width
        $target = $size * 0.86
        if ($w -gt 0) {
            $font.Dispose()
            $font = New-Object System.Drawing.Font($family, ($fontSize * $target / $w), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        }
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $rect = New-Object System.Drawing.RectangleF(0, 0, $size, $textBottom)
        $g.DrawString($mode.Text, $font, [System.Drawing.Brushes]::White, $rect, $sf)

        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        return , $ms.ToArray()
    } finally {
        $g.Dispose(); $bmp.Dispose()
    }
}

foreach ($m in $modes) {
    $images = foreach ($s in $sizes) { , @{ Size = $s; Data = (New-IconPng $s $m) } }
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$images.Count)   # ICONDIR
    $offset = 6 + 16 * $images.Count
    foreach ($img in $images) {                                                      # ICONDIRENTRY per image
        $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }
        $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]$img.Data.Length); $bw.Write([uint32]$offset)
        $offset += $img.Data.Length
    }
    foreach ($img in $images) { $bw.Write([byte[]]$img.Data) }
    $bw.Flush()
    $file = Join-Path $outDir "$($m.Name).ico"
    [IO.File]::WriteAllBytes($file, $ms.ToArray())
    Write-Host "Wrote $file ($($ms.Length) bytes)"
}
