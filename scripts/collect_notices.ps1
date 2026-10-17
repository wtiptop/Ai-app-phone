param([string]$FlutterRoot = $env:FLUTTER_ROOT)
$ErrorActionPreference = 'Stop'
$taskRepo = Split-Path $PSScriptRoot -Parent
$taskConfigDir = Join-Path $taskRepo '.dart_tool'
$taskPackages = (Get-Content -LiteralPath (Join-Path $taskConfigDir 'package_config.json') -Raw | ConvertFrom-Json).packages
$taskText = [System.Text.StringBuilder]::new()
[void]$taskText.AppendLine('SCALAJĄCA — INFORMACJE O LICENCJACH ZALEŻNOŚCI')
[void]$taskText.AppendLine('Lokalne teksty LICENSE/NOTICE pakietów rozwiązanych w package_config.json.')
[void]$taskText.AppendLine('Zestawienie nie zmienia licencji własnego kodu ani praw do znaków.')
[void]$taskText.AppendLine()
$taskCount = 0
$taskMissing = @()
foreach ($taskPackage in ($taskPackages | Sort-Object name)) {
  if ($taskPackage.name -eq 'scalajaca') { continue }
  $taskUri = [Uri]$taskPackage.rootUri
  $taskPath = if ($taskUri.IsAbsoluteUri) { $taskUri.LocalPath } else {
    [System.IO.Path]::GetFullPath((Join-Path $taskConfigDir $taskPackage.rootUri))
  }
  $taskLicenses = @(Get-ChildItem -LiteralPath $taskPath -File | Where-Object {
    $_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE)([._-].*)?$'
  })
  if ($taskLicenses.Count -eq 0 -and $FlutterRoot -and $taskPath.StartsWith($FlutterRoot, [StringComparison]::OrdinalIgnoreCase)) {
    $taskLicenses = @(Get-Item -LiteralPath (Join-Path $FlutterRoot 'LICENSE'))
  }
  if ($taskLicenses.Count -eq 0) { $taskMissing += $taskPackage.name }
  [void]$taskText.AppendLine("===== $($taskPackage.name) =====")
  foreach ($taskLicense in $taskLicenses) {
    [void]$taskText.AppendLine("--- $($taskLicense.Name) ---")
    [void]$taskText.AppendLine([System.IO.File]::ReadAllText($taskLicense.FullName))
  }
  $taskCount++
}
[System.IO.File]::WriteAllText((Join-Path $taskRepo 'docs/THIRD_PARTY_NOTICES.txt'), $taskText.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Output "Pakiety: $taskCount; brak lokalnej licencji: $($taskMissing -join ', ')"
if ($taskMissing.Count -gt 0) { throw 'Przejrzyj brakujące licencje przed dystrybucją.' }
