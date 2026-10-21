$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$taskRoot = Split-Path -Parent $PSScriptRoot
$source = [System.Drawing.Image]::FromFile((Join-Path $taskRoot 'assets/branding/finmi/icon.png'))
function Write-FinmiIcon([string]$Target, [int]$Size) {
    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.DrawImage($source, 0, 0, $Size, $Size)
    $graphics.Dispose()
    $bitmap.Save($Target, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}
try {
    $densities = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
    foreach ($density in $densities.Keys) {
        Write-FinmiIcon (Join-Path $taskRoot "android/app/src/main/res/mipmap-$density/ic_launcher.png") $densities[$density]
    }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $taskRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset') -Filter '*.png') {
        $old = [System.Drawing.Image]::FromFile($file.FullName)
        $size = $old.Width
        $old.Dispose()
        Write-FinmiIcon $file.FullName $size
    }
    foreach ($size in @(192, 512)) {
        Write-FinmiIcon (Join-Path $taskRoot "web/icons/Icon-$size.png") $size
        Write-FinmiIcon (Join-Path $taskRoot "web/icons/Icon-maskable-$size.png") $size
    }
    Write-FinmiIcon (Join-Path $taskRoot 'web/favicon.png') 32
} finally { $source.Dispose() }
Write-Output 'Generated Android, iOS and web icons from the approved Finmi icon.'
