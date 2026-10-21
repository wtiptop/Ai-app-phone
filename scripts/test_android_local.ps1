param([Alias('Model1B')][string]$Model='', [string]$Model2B='')
$ErrorActionPreference='Stop'
$taskPreviousModel=$env:SCALAJACA_TEST_MODEL
$taskPreviousModel2B=$env:SCALAJACA_TEST_MODEL_2B
if($Model) { $env:SCALAJACA_TEST_MODEL=(Resolve-Path -LiteralPath $Model).Path }
if($Model2B) { $env:SCALAJACA_TEST_MODEL_2B=(Resolve-Path -LiteralPath $Model2B).Path }
Push-Location (Join-Path (Split-Path $PSScriptRoot -Parent) 'android')
try {
  & .\gradlew.bat :app:testDebugUnitTest '-Ptarget-platform=android-arm64' '--console=plain'
  if($LASTEXITCODE -ne 0) { throw 'Testy JUnit modułu Android nie przeszły.' }
} finally {
  Pop-Location
  $env:SCALAJACA_TEST_MODEL=$taskPreviousModel
  $env:SCALAJACA_TEST_MODEL_2B=$taskPreviousModel2B
}
