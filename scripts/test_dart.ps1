param([string]$Dart = 'dart')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  & $Dart test test/providers test/security/minicpm_cost_test.dart --reporter expanded
  if ($LASTEXITCODE -ne 0) { throw 'Testy Dart nie przeszły.' }
} finally { Pop-Location }
