param(
  [ValidateSet('prepare','export','reset','restore','collect')][string]$Phase='prepare',
  [switch]$ReuseExistingFixture,
  [string]$ProjectFixture='',
  [string]$CampaignFixture='',
  [switch]$ResetOwnEmulatorApp,
  [string]$Adb=(Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'),
  [string]$Output=''
)
$ErrorActionPreference='Stop'
$BackupAdb=$Adb
$BackupSerial='emulator-5556'
$BackupPackage='pl.scalajaca.scalajaca'
$BackupRepo=Split-Path $PSScriptRoot -Parent
if(!$Output) { $Output=Join-Path $BackupRepo 'work/backup-emulator-proof' }
$BackupWork=[IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Path $BackupWork -Force | Out-Null
function BackupAdb {
  & $script:BackupAdb -s $script:BackupSerial @args
  if($LASTEXITCODE -ne 0) { throw 'Błąd polecenia własnego emulatora.' }
}
if((BackupAdb shell getprop ro.kernel.qemu).Trim() -ne '1') { throw 'Odmowa: to nie jest emulator.' }
$BackupAvd=(BackupAdb shell getprop ro.boot.qemu.avd_name).Trim()
if(!$BackupAvd) { $BackupAvd=(BackupAdb shell getprop ro.kernel.qemu.avd_name).Trim() }
if($BackupAvd -ne 'Scalajaca_API30') { throw 'Odmowa: niewłaściwy AVD.' }
$BackupInstalled=BackupAdb shell dumpsys package $BackupPackage
if(!($BackupInstalled -match 'versionName=0\.4\.')) { throw 'Odmowa: wymagany testowy APK Scalającej 0.4.x.' }
function ReadBackupProof([string]$Name) {
  if($Name -notin @('backup-export.json','backup-restore.json')) { throw 'Nieprawidłowa nazwa raportu.' }
  $BackupText=BackupAdb exec-out run-as $script:BackupPackage cat "files/emulator-proof/$Name"
  $BackupText -join "`n" | Set-Content -LiteralPath (Join-Path $script:BackupWork $Name) -Encoding utf8
  return ($BackupText -join "`n" | ConvertFrom-Json)
}
function SavedBackupProof {
  $BackupManifest=Get-Content -LiteralPath (Join-Path $script:BackupWork 'backup-export.json') -Raw | ConvertFrom-Json
  if($BackupManifest.filename -notmatch '^Scalajaca-E2E-[a-f0-9]{8}\.scalabackup$' -or $BackupManifest.fixture -notmatch '^[a-f0-9]{8}$') { throw 'Nieprawidłowa nazwa własnej fixture.' }
  if($BackupManifest.filename -ne "Scalajaca-E2E-$($BackupManifest.fixture).scalabackup") { throw 'Niezgodna fixture.' }
  return $BackupManifest
}
function RunBackupCase([string]$Method,[string[]]$Extra=@()) {
  $BackupLog=Join-Path $script:BackupWork "$Method.log"
  $BackupArgs=@('-s',$script:BackupSerial,'shell','am','instrument','-w','-r','-e','scalajacaEmulator','true') + $Extra + @('-e','class',"pl.scalajaca.scalajaca.backup.BackupDeviceTest#$Method",'pl.scalajaca.scalajaca.test/androidx.test.runner.AndroidJUnitRunner')
  & $script:BackupAdb @BackupArgs *> $BackupLog
  $BackupCode=$LASTEXITCODE
  Get-Content -LiteralPath $BackupLog -Tail 35
  $BackupRunnerOutput=Get-Content -LiteralPath $BackupLog -Raw
  if($BackupCode -ne 0 -or $BackupRunnerOutput -notmatch 'OK \(1 tests?\)' -or $BackupRunnerOutput -match 'FAILURES|INSTRUMENTATION_FAILED') { throw 'Test Androida nie przeszedł.' }
}
switch($Phase) {
  'prepare' {
    # Wyłącznie nowy katalog fikcyjnych danych testowych, bez prywatnych vaultów.
    $BackupFixtureFile=Join-Path $BackupWork 'BackupArchive.md'
    [System.IO.File]::WriteAllText($BackupFixtureFile,"# Testowa kronika`n`nFikcyjny znak archiwum to RIVERLIGHT.`n",[System.Text.UTF8Encoding]::new($false))
    BackupAdb shell mkdir -p '/sdcard/Documents/ScalajacaBackupVault'
    BackupAdb push $BackupFixtureFile '/sdcard/Documents/ScalajacaBackupVault/BackupArchive.md'
    Write-Output 'Przygotowano fikcyjny vault backupu. Żaden test jeszcze nie został uruchomiony.'
  }
  'export' {
    $BackupExtra=@()
    if($ReuseExistingFixture) {
      if($ProjectFixture -notmatch '^[a-f0-9]{8}$' -or $CampaignFixture -notmatch '^[a-f0-9]{8}$') { throw 'Wymagane poprawne sufiksy istniejących danych syntetycznych.' }
      $BackupExtra=@('-e','scalajacaBackupReuseFixture','true','-e','scalajacaBackupProjectFixture',$ProjectFixture,'-e','scalajacaBackupCampaignFixture',$CampaignFixture)
    }
    RunBackupCase 'a_exportSafWrongPasswordAndCollision' $BackupExtra
    $BackupManifest=ReadBackupProof 'backup-export.json'
    if(!$BackupManifest.wrongPasswordNoMutation -or !$BackupManifest.collisionNoMutation -or !$BackupManifest.stageClean) { throw 'Niepełne asercje eksportu.' }
    $BackupManifest=SavedBackupProof
    $BackupLocalFile=Join-Path $BackupWork $BackupManifest.filename
    BackupAdb pull "/sdcard/Download/$($BackupManifest.filename)" $BackupLocalFile
    $BackupInfo=Get-Item -LiteralPath $BackupLocalFile
    if($BackupInfo.Length -le 64 -or $BackupInfo.Length -gt 2147483648) { throw 'Nieprawidłowy rozmiar zaszyfrowanego archiwum.' }
    $BackupHash=(Get-FileHash -LiteralPath $BackupLocalFile -Algorithm SHA256).Hash.ToLowerInvariant()
    @{filename=$BackupInfo.Name;bytes=$BackupInfo.Length;sha256=$BackupHash;source='własny emulator Scalajaca_API30'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BackupWork 'ciphertext-file.json') -Encoding utf8
    Write-Output 'Eksport SAF, odrzucenie złego hasła i atomowy rollback kolizji przeszły. Kopię szyfrotekstu pobrano przed resetem.'
  }
  'reset' {
    if(!$ResetOwnEmulatorApp) { throw 'Wymagany jawny przełącznik -ResetOwnEmulatorApp. Reset dotyczy wyłącznie naszej aplikacji na sprawdzonym AVD.' }
    $BackupManifest=SavedBackupProof
    $BackupLocalFile=Join-Path $BackupWork $BackupManifest.filename
    $BackupSaved=Get-Content -LiteralPath (Join-Path $BackupWork 'ciphertext-file.json') -Raw | ConvertFrom-Json
    if(!(Test-Path -LiteralPath $BackupLocalFile -PathType Leaf) -or (Get-FileHash -LiteralPath $BackupLocalFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $BackupSaved.sha256) { throw 'Brak zweryfikowanej kopii na hoście; reset zabroniony.' }
    # Nie usuwamy plików z Documents ani danych innych aplikacji. pm clear resetuje
    # wyłącznie testową instalację tego pakietu, sprawdzoną powyżej jako qemu/AVD.
    BackupAdb shell am force-stop $BackupPackage
    $BackupReset=BackupAdb shell pm clear $BackupPackage
    if($BackupReset -notmatch 'Success') { throw 'Nie potwierdzono resetu.' }
    @{package=$BackupPackage;serial=$BackupSerial;avd=$BackupAvd;resetAppData=$true;at=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BackupWork 'authorized-reset.json') -Encoding utf8
    Write-Output 'Wyczyszczono wyłącznie dane testowej Scalającej na Scalajaca_API30. Plik kopii w Download i fixture vaultu w Documents pozostają.'
  }
  'restore' {
    $BackupManifest=SavedBackupProof
    $BackupReset=Get-Content -LiteralPath (Join-Path $BackupWork 'authorized-reset.json') -Raw | ConvertFrom-Json
    if(!$BackupReset.resetAppData -or $BackupReset.avd -ne $BackupAvd -or $BackupReset.package -ne $BackupPackage) { throw 'Brak potwierdzonego resetu testowej instalacji.' }
    RunBackupCase 'b_restoreAfterAuthorizedEmulatorAppReset' @('-e','scalajacaBackupAfterReset','true','-e','scalajacaBackupFixture',$BackupManifest.fixture,'-e','scalajacaBackupName',$BackupManifest.filename,'-e','scalajacaBackupProjectFixture',$BackupManifest.projectFixture,'-e','scalajacaBackupCampaignFixture',$BackupManifest.campaignFixture)
    $null=ReadBackupProof 'backup-restore.json'
    Write-Output 'Restore po resecie zakończył się. Uruchom collect dla porównania identyfikatorów i zaszyfrowanych rekordów.'
  }
  'collect' {
    $BackupBefore=SavedBackupProof
    $BackupAfter=ReadBackupProof 'backup-restore.json'
    if(!$BackupAfter.restoredAfterAppDataReset -or !$BackupAfter.encryptedFieldsReadable -or !$BackupAfter.gmSecretHiddenFromPlayer) { throw 'Niepełne asercje restore.' }
    foreach($BackupSection in @('counts','identities')) {
      foreach($BackupTable in $BackupBefore.snapshot.$BackupSection.PSObject.Properties.Name) {
        if($BackupBefore.snapshot.$BackupSection.$BackupTable -ne $BackupAfter.snapshot.$BackupSection.$BackupTable) { throw "Niezgodne $BackupSection/$BackupTable." }
      }
    }
    foreach($BackupTable in @('notes','memory_collections','memory_chunks','analysis_checkpoints','rpg_campaigns','rpg_records','rpg_events')) {
      if($BackupBefore.snapshot.counts.$BackupTable -lt 1) { throw "Brak syntetycznych danych $BackupTable." }
      if($BackupBefore.snapshot.ciphertextDigests.$BackupTable -eq $BackupAfter.snapshot.ciphertextDigests.$BackupTable) { throw "Nie potwierdzono ponownego szyfrowania $BackupTable." }
    }
    @{export=$true;wrongPasswordRollback=$true;collisionRollback=$true;restoreAfterAppReset=$true;sameIdsAndCounts=$true;ciphertextChanged=$true;gmSecretHiddenFromPlayer=$true} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BackupWork 'summary.json') -Encoding utf8
    Write-Output 'PASS: SAF eksport, błędne hasło, rollback kolizji, restore po resecie, zachowane ID/liczniki, zmienione szyfroteksty i filtr sekretów MG.'
  }
}
