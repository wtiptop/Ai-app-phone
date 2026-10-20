param(
  [Parameter(Mandatory=$true)][string]$Model,
  [string]$Serial='emulator-5556',
  [string]$Adb=(Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'),
  [string]$Output=''
)
$ErrorActionPreference='Stop'
$taskRepo=Split-Path $PSScriptRoot -Parent
if(!$Output) { $Output=Join-Path $taskRepo 'work/continuity-emulator-tests' }
$Output=[IO.Path]::GetFullPath($Output)
if($Serial -notmatch '^emulator-[0-9]+$') { throw 'Scenariusz wymaga własnego emulatora.' }
$taskQemu=(& $Adb -s $Serial shell getprop ro.kernel.qemu).Trim()
if($LASTEXITCODE -ne 0 -or $taskQemu -ne '1') { throw 'To nie jest emulator.' }
$taskAvd=(& $Adb -s $Serial shell getprop ro.boot.qemu.avd_name).Trim()
if(!$taskAvd) { $taskAvd=(& $Adb -s $Serial shell getprop ro.kernel.qemu.avd_name).Trim() }
if($taskAvd -ne 'Scalajaca_API30') { throw 'Wymagany własny AVD Scalajaca_API30.' }
# Pierwsze sześć: prawdziwy GGUF, Stop/tło, SAF, źródła i późny fakt po trzech stronach.
$taskInferencePassed=$true
try {
  & (Join-Path $PSScriptRoot 'test_android_emulator.ps1') -Model $Model -Serial $Serial -Adb $Adb -Output $Output
} catch {
  $taskInferenceLog=Join-Path $Output 'instrumentation.log'
  # Po pełnym odbiorze z błędem asercji nadal sprawdzamy niezależną kampanię.
  # Błędy budowania/instalacji/niepełny runner kończą pracę od razu.
  if(!(Test-Path -LiteralPath $taskInferenceLog) -or
      (Get-Content -LiteralPath $taskInferenceLog -Raw) -notmatch 'Tests run: 6,\s+Failures: [1-6]') { throw }
  $taskInferencePassed=$false
  Write-Output 'MiniCPM/pamięć: FAIL, log zachowano. Kontynuuję niezależny test historii RPG; końcowy status pozostanie FAIL.'
}
$taskLog=Join-Path $Output 'campaign-continuity-instrumentation.log'
& $Adb -s $Serial shell am instrument -w -r -e scalajacaEmulator true -e class pl.scalajaca.scalajaca.rpg.ContinuityDeviceTest 'pl.scalajaca.scalajaca.test/androidx.test.runner.AndroidJUnitRunner' *> $taskLog
$taskExit=$LASTEXITCODE
Get-Content -LiteralPath $taskLog
$taskText=Get-Content -LiteralPath $taskLog -Raw
if($taskExit -ne 0 -or $taskText -notmatch 'OK \(1 tests?\)' -or $taskText -match 'FAILURES!!!|INSTRUMENTATION_FAILED') { throw 'Test ciągłości kampanii nie przeszedł.' }
$taskStart=[Diagnostics.ProcessStartInfo]::new($Adb)
$taskStart.UseShellExecute=$false
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
foreach($taskArg in @('-s',$Serial,'exec-out','run-as','pl.scalajaca.scalajaca','tar','-cf','-','files/emulator-proof')) { $taskStart.ArgumentList.Add($taskArg) }
$taskProcess=[Diagnostics.Process]::Start($taskStart)
$taskTar=Join-Path $Output 'continuity-proof.tar'
$taskStream=[IO.File]::Create($taskTar)
try { $taskProcess.StandardOutput.BaseStream.CopyTo($taskStream) } finally { $taskStream.Dispose() }
$taskError=$taskProcess.StandardError.ReadToEnd()
$taskProcess.WaitForExit()
if($taskProcess.ExitCode -ne 0) { throw "Odczyt dowodów: $taskError" }
& tar -xf $taskTar -C $Output
if($LASTEXITCODE -ne 0) { throw 'Nie rozpakowano dowodów.' }
$taskReport=Get-Content -LiteralPath (Join-Path $Output 'files/emulator-proof/campaign-continuity.json') -Raw | ConvertFrom-Json
if($taskReport.resumedRevision -ne 3 -or !$taskReport.oldCiphertextPreserved -or !$taskReport.playerNoHistoryOrCheckpoint) { throw 'Niepełny dowód ciągłości kampanii.' }
if(!$taskInferencePassed) { throw "MiniCPM/pamięć: FAIL; historia RPG: PASS. Wszystkie wyniki zachowano w $Output." }
Write-Output "Siedem scenariuszy PASS (6 MiniCPM/pamięć + 1 RPG). Dowody: $Output. Fizyczny Pixel 9 wymaga osobnego odbioru."
