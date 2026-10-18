param([string]$Model='')
$ErrorActionPreference='Stop'
$taskPreviousModel=$env:SCALAJACA_TEST_MODEL
if($Model) { $env:SCALAJACA_TEST_MODEL=(Resolve-Path -LiteralPath $Model).Path }
Push-Location (Join-Path (Split-Path $PSScriptRoot -Parent) 'android')
try {
  & .\gradlew.bat :app:testDebugUnitTest '-Ptarget-platform=android-arm64' '--console=plain'
  if($LASTEXITCODE -ne 0) { throw 'Testy JUnit modułu Android nie przeszły.' }
} finally {
  Pop-Location
  $env:SCALAJACA_TEST_MODEL=$taskPreviousModel
}
