param(
  [Parameter(Mandatory=$true)][string]$Model,
  [string]$ExpectedSha256='81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa',
  [string]$CMake='cmake'
)
$ErrorActionPreference='Stop'
$taskRepo=Split-Path $PSScriptRoot -Parent
$taskModel=(Resolve-Path -LiteralPath $Model).Path
if((Get-FileHash -LiteralPath $taskModel -Algorithm SHA256).Hash -ine $ExpectedSha256) { throw 'Nieprawidłowy SHA-256 modelu testowego.' }
$taskBuild=Join-Path $taskRepo 'build/native-host'
# Windows: uruchom w Developer PowerShell z MSVC; Ninja i CMake w PATH.
& $CMake -S (Join-Path $taskRepo 'android/app/src/main/cpp') -B $taskBuild -G Ninja -DCMAKE_BUILD_TYPE=Release
if($LASTEXITCODE -ne 0) { throw 'Konfiguracja rdzenia C++ nie przeszła.' }
& $CMake --build $taskBuild --target scalajaca_local_smoke -j 2
if($LASTEXITCODE -ne 0) { throw 'Budowanie rdzenia C++ nie przeszło.' }
$taskBinary=if($IsWindows -or $env:OS -eq 'Windows_NT') { 'scalajaca_local_smoke.exe' } else { 'scalajaca_local_smoke' }
& (Join-Path $taskBuild $taskBinary) $taskModel
if($LASTEXITCODE -ne 0) { throw 'Test prawdziwej generacji nie przeszedł.' }
