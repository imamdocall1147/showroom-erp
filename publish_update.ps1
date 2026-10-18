$ErrorActionPreference = 'Stop'
# This file can be in the showroom-erp folder or in a sub-folder of it.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $root 'frontend'))) {
    $parent = Split-Path -Parent $root
    if (Test-Path (Join-Path $parent 'frontend')) { $root = $parent }
}
if (-not (Test-Path (Join-Path $root 'frontend\pubspec.yaml'))) {
    throw "frontend\pubspec.yaml not found. Put this file in the showroom-erp folder (or a sub-folder of it)."
}
Write-Host "Project folder: $root"

$pub = Join-Path $root 'frontend\pubspec.yaml'
$text = [System.IO.File]::ReadAllText($pub)
$m = [regex]::Match($text, 'version:\s*(\d+\.\d+\.\d+)\+(\d+)')
if (-not $m.Success) { throw 'No version line like "version: 1.0.0+1" found in pubspec.yaml' }
$name = $m.Groups[1].Value
$build = [int]$m.Groups[2].Value + 1
$text = [regex]::Replace($text, 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $name+$build", 1)
[System.IO.File]::WriteAllText($pub, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Building the phone app (version $name+$build). Please wait..."
Push-Location (Join-Path $root 'frontend')
flutter build apk --release --target-platform android-arm64
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { throw 'APK build failed' }

$apk = Join-Path $root 'frontend\build\app\outputs\flutter-apk\app-release.apk'
$dir = Join-Path $root 'backend\updates'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item $apk (Join-Path $dir 'app.apk') -Force
$json = '{"build": ' + $build + ', "name": "' + $name + '"}'
[System.IO.File]::WriteAllText((Join-Path $dir 'version.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""
Write-Host "Done. Version $name+$build is published. The phone will ask to update when the app is opened."
Write-Host "APK file: $dir\app.apk"
