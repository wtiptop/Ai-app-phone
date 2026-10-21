param(
  [Parameter(Mandatory=$true)][string]$Apk,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9-]{1,40}$')][string]$Run,
  [Parameter(Mandatory=$true)][string]$Output,
  [ValidateRange(10,180)][int]$TimeoutMinutes=40,
  [string]$Serial='emulator-5556',
  [string]$Adb=(Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe')
)
$ErrorActionPreference='Stop'
if($Serial -notmatch '^emulator-[0-9]+$') { throw 'Test wymaga własnego emulatora.' }
function Device {
  $taskResult=& $script:Adb -s $script:Serial @args
  if($LASTEXITCODE -ne 0) { throw "Błąd ADB: $args" }
  return $taskResult
}
function Guard {
  if((Device shell getprop ro.kernel.qemu).Trim() -ne '1') { throw 'To nie jest emulator.' }
  $taskAvd=(Device shell getprop ro.boot.qemu.avd_name).Trim()
  if(!$taskAvd) { $taskAvd=(Device shell getprop ro.kernel.qemu.avd_name).Trim() }
  if($taskAvd -ne 'Scalajaca_API30') { throw 'Nieoczekiwany AVD.' }
}
function Offline([string]$Name) {
  if((Device shell settings get global airplane_mode_on).Trim() -ne '1') { throw 'Brak trybu samolotowego.' }
  $taskConnectivity=Device shell dumpsys connectivity
  $taskConnectivity | Set-Content (Join-Path $Output "$Name.txt") -Encoding utf8
  if(($taskConnectivity -join "`n") -notmatch 'Active default network: (none|null)') { throw 'Aktywna sieć emulatora.' }
}
function Launch {
  $taskStart=Device shell am start -W -n pl.scalajaca.scalajaca/.MainActivity
  if(($taskStart -join "`n") -notmatch 'Status:\s+ok') { throw "Nie uruchomiono aktywności: $taskStart" }
  Write-Output $taskStart
}
Guard
if((Device shell getprop sys.boot_completed).Trim() -ne '1') { throw 'Zaczekaj na pełny rozruch emulatora.' }
Device shell input keyevent KEYCODE_WAKEUP
Device shell wm dismiss-keyguard
$Output=[IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$taskRemote="code_cache/rpg-soak/$Run/report.json"
$taskExists=& $Adb -s $Serial shell run-as pl.scalajaca.scalajaca test -e $taskRemote
if($LASTEXITCODE -eq 0) { throw 'Ten identyfikator próby już istnieje. Wybierz nowy; nie nadpisujemy dowodów.' }
$taskDbExists=& $Adb -s $Serial shell run-as pl.scalajaca.scalajaca test -e "databases/rpg-soak-$Run.db"
if($LASTEXITCODE -eq 0) { throw 'Baza tej próby już istnieje. Użyj nowego Run, również gdy Android usunął code_cache.' }
Offline 'offline-before'
Device install -r $Apk
$taskPackage=(Device shell pm path pl.scalajaca.scalajaca | Select-Object -First 1).Substring(8).Trim()
Device shell sha256sum $taskPackage | Set-Content (Join-Path $Output 'installed-harness-sha256.txt') -Encoding utf8
Device shell am force-stop pl.scalajaca.scalajaca
Launch
$taskDeadline=[DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
$taskCount=0
$taskRestarts=[Collections.Generic.HashSet[string]]::new()
while([DateTime]::UtcNow -lt $taskDeadline) {
  Start-Sleep -Seconds 10
  $taskJson=& $Adb -s $Serial exec-out run-as pl.scalajaca.scalajaca cat $taskRemote 2>$null
  if($LASTEXITCODE -ne 0) { continue }
  try { $taskReport=$taskJson | ConvertFrom-Json } catch { continue }
  $taskJson | Set-Content (Join-Path $Output 'report.json') -Encoding utf8
  if($taskReport.status -eq 'generating') {
    $taskSample=Device shell dumpsys meminfo pl.scalajaca.scalajaca
    $taskSampleName='memory-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'.txt'
    $taskSample | Set-Content (Join-Path $Output $taskSampleName) -Encoding utf8
    [ordered]@{ utc=[DateTime]::UtcNow.ToString('o'); activeCase=$taskReport.activeCaseId; sample=$taskSampleName } | ConvertTo-Json -Compress | Add-Content (Join-Path $Output 'memory-samples.jsonl') -Encoding utf8
  }
  while($taskCount -lt $taskReport.cases.Count) {
    $taskCase=$taskReport.cases[$taskCount++]
    [ordered]@{ proba=$taskCase.id; trafienie=$taskCase.retrievalHit; dokladnie=$taskCase.exact; odpowiedz=$taskCase.output; blad=$taskCase.error } | ConvertTo-Json -Compress
  }
  if($taskReport.status -eq 'fatal') { throw "Błąd kampanii: $($taskReport.fatal)" }
  if($taskReport.status -eq 'complete') {
    Offline 'offline-after'
    Write-Output "Zakończono $($taskReport.completedSessions) sesji; $($taskReport.cases.Count) prób, $($taskReport.processStarts) uruchomienia procesu. Jakość odpowiedzi wymaga oceny raportu."
    exit 0
  }
  if($taskReport.status -match '^pause-restart-(8|16)$' -and $taskRestarts.Add($taskReport.status)) {
    Guard
    Offline $taskReport.status
    Device shell am force-stop pl.scalajaca.scalajaca
    Launch
    Write-Output "Wznowiono proces po sesji $($taskReport.completedSessions), bez czyszczenia bazy i klucza."
  }
}
throw 'Przekroczono czas testu. Ostatni raport pozostaje dowodem nieukończonej próby.'
