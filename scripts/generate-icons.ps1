$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$workspace = Split-Path $PSScriptRoot -Parent
function Write-FarmIcon([string]$relativePath, [int]$size) {
    $path = Join-Path $workspace $relativePath
    $bitmap = New-Object Drawing.Bitmap($size, $size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#234C3D'))
    $graphics.ScaleTransform($size / 1024.0, $size / 1024.0)
    $pen = New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml('#F6F5EF'), 46)
    $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLine($pen, 280, 735, 744, 735)
    $graphics.DrawLine($pen, 512, 735, 512, 350)
    $left = New-Object Drawing.Drawing2D.GraphicsPath
    $left.AddBezier(508,552,320,538,270,415,292,296)
    $left.AddBezier(292,296,450,324,513,403,508,552)
    $left.CloseFigure()
    $leftBrush = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#C4D2A8'))
    $graphics.FillPath($leftBrush, $left)
    $right = New-Object Drawing.Drawing2D.GraphicsPath
    $right.AddBezier(520,639,705,619,757,500,735,382)
    $right.AddBezier(735,382,576,412,514,490,520,639)
    $right.CloseFigure()
    $rightBrush = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#F6F5EF'))
    $graphics.FillPath($rightBrush, $right)
    $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose(); $pen.Dispose(); $left.Dispose(); $right.Dispose(); $leftBrush.Dispose(); $rightBrush.Dispose()
}
foreach ($item in @(@('mdpi',48),@('hdpi',72),@('xhdpi',96),@('xxhdpi',144),@('xxxhdpi',192))) {
    Write-FarmIcon "android/app/src/main/res/mipmap-$($item[0])/ic_launcher.png" $item[1]
}
$icons = Get-Content -LiteralPath (Join-Path $workspace 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json') -Raw | ConvertFrom-Json
foreach ($icon in $icons.images) {
    if ($icon.filename) {
        $size = [double]($icon.size.Split('x')[0]) * [double]($icon.scale.TrimEnd('x'))
        Write-FarmIcon "ios/Runner/Assets.xcassets/AppIcon.appiconset/$($icon.filename)" ([int]$size)
    }
}
foreach ($size in @(192,512)) {
    Write-FarmIcon "web/icons/Icon-$size.png" $size
    Write-FarmIcon "web/icons/Icon-maskable-$size.png" $size
}
Write-FarmIcon 'web/favicon.png' 48
Write-FarmIcon 'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png' 96
Write-FarmIcon 'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png' 192
Write-FarmIcon 'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png' 288
