param([string]$Flutter = 'flutter', [string]$Target = 'android-arm64,android-x64')
$ErrorActionPreference = 'Stop'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  & $Flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Nie udało się pobrać zależności.' }
  & $Flutter analyze
  if ($LASTEXITCODE -ne 0) { throw 'Analiza statyczna nie przeszła.' }
  & $Flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Testy nie przeszły.' }
  & $Flutter build apk --debug --target-platform $Target
  if ($LASTEXITCODE -ne 0) { throw 'Budowanie APK nie przeszło.' }
  Get-FileHash -LiteralPath 'build/app/outputs/flutter-apk/app-debug.apk' -Algorithm SHA256
} finally { Pop-Location }
