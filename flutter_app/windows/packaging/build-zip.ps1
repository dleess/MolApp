# Builds the Windows distribution archive: flutter_app/dist/molapp-<version>-windows-x64.zip
#
# Run after `flutter build windows --release`. The release tree is already self-contained —
# molapp.exe, flutter_windows.dll and the plugin DLLs sit next to data/ — so the archive is
# the whole app: unzip anywhere and run. Same shape as linux/packaging/build-deb.sh and
# macos/packaging/build-dmg.sh: the built tree *is* the package.
#
#   flutter_app\windows\packaging\build-zip.ps1 [-OutDir <dir>]
#
# Unsigned. Windows SmartScreen will warn on first launch until the exe is code-signed.
param([string]$OutDir)

$ErrorActionPreference = 'Stop'

$flutterDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutDir) { $OutDir = Join-Path $flutterDir 'dist' }

$version = (Select-String -Path (Join-Path $flutterDir 'pubspec.yaml') `
  -Pattern '^version:\s*([0-9.]+)\+').Matches[0].Groups[1].Value
if (-not $version) { throw 'build-zip: could not read version from pubspec.yaml' }

$release = Join-Path $flutterDir 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'molapp.exe'))) {
  throw "build-zip: $release\molapp.exe is missing - run 'flutter build windows --release' first"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zip = Join-Path $OutDir "molapp-$version-windows-x64.zip"
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zip -Force
Write-Output $zip
