param(
  [Parameter(Mandatory=$true)][string]$Model,
  [ValidateSet('1b','2b')][string]$ModelSize='1b',
  [string]$Serial='emulator-5556',
  [string]$Adb=(Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'),
  [string]$Output=''
)
$ErrorActionPreference='Stop'
$taskRepo=Split-Path $PSScriptRoot -Parent
if(!$Output) { $Output=Join-Path $taskRepo 'work/emulator-tests' }
$Output=[IO.Path]::GetFullPath($Output)
if($Serial -notmatch '^emulator-[0-9]+$') { throw 'Ten skrypt obsługuje wyłącznie emulator.' }
function DeviceAdb {
  & $script:Adb -s $script:Serial @args
  if($LASTEXITCODE -ne 0) { throw "Błąd ADB: $args" }
}
if((DeviceAdb shell getprop ro.kernel.qemu).Trim() -ne '1') { throw 'To nie jest emulator.' }
if((DeviceAdb shell getprop ro.build.version.sdk).Trim() -ne '30') { throw 'Fixture selektora sprawdzono na API 30; użyj obrazu Google APIs x86_64 Android 11 po angielsku.' }
$taskModel=(Resolve-Path -LiteralPath $Model).Path
$taskModelHash=if($ModelSize -eq '2b') { 'ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd' } else { '81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa' }
if((Get-FileHash -LiteralPath $taskModel -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskModelHash) { throw 'Fixture wymaga przypiętego oficjalnego MiniCPM5 Q4_K_M w wybranym rozmiarze.' }
$taskApk=Join-Path $taskRepo 'build/app/outputs/flutter-apk/app-debug.apk'
if(!(Test-Path -LiteralPath $taskApk)) { throw 'Najpierw zbuduj APK: flutter build apk --debug --target-platform android-arm64,android-x64' }
Push-Location (Join-Path $taskRepo 'android')
try {
  & .\gradlew.bat :app:assembleDebugAndroidTest '-Ptarget-platform=android-arm64,android-x64' --console=plain
  if($LASTEXITCODE -ne 0) { throw 'Nie zbudowano testowego APK.' }
} finally { Pop-Location }
New-Item -ItemType Directory -Path $Output -Force | Out-Null
DeviceAdb shell cmd connectivity airplane-mode enable
DeviceAdb shell svc wifi disable
DeviceAdb shell svc data disable
foreach($taskAnimation in @('window_animation_scale','transition_animation_scale','animator_duration_scale')) { DeviceAdb shell settings put global $taskAnimation 0 }
DeviceAdb shell settings put system screen_off_timeout 2147483647
DeviceAdb shell input keyevent KEYCODE_WAKEUP
DeviceAdb shell wm dismiss-keyguard
DeviceAdb push $taskModel "/sdcard/Download/MiniCPM5-$($ModelSize.ToUpperInvariant())-Q4_K_M.gguf"
$taskFixture=Join-Path $Output 'ScalajacaTestVault'
New-Item -ItemType Directory -Force -Path (Join-Path $taskFixture '.obsidian') | Out-Null
$taskArchiveText="# Archive`nThe archive key is LANTERN.`n"
for($taskSection=1;$taskSection -le 22;$taskSection++) {
  $taskLine="Archive section $taskSection. This passage describes ordinary background details. "
  $taskArchiveText += $taskLine.PadRight(840,'x')+"`n"
}
$taskArchiveText += "Archive recovery. The recovery key is COMPASS.`n"
[IO.File]::WriteAllText((Join-Path $taskFixture 'Archive.md'),$taskArchiveText,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $taskFixture 'GM_SECRET.md'),"GM_SECRET: VAULT_GM_SENTINEL_426`n",[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $taskFixture '.obsidian/hidden.md'),"HIDDEN_PLUGIN_SENTINEL_426`n",[Text.UTF8Encoding]::new($false))
DeviceAdb shell mkdir -p '/sdcard/Documents'
DeviceAdb push $taskFixture '/sdcard/Documents/'
DeviceAdb install -r $taskApk
DeviceAdb install -r (Join-Path $taskRepo 'build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk')
DeviceAdb shell dumpsys package pl.scalajaca.scalajaca | Select-String 'versionCode|versionName|primaryCpuAbi' | Set-Content (Join-Path $Output 'installed-package.txt')
Get-FileHash -LiteralPath $taskApk -Algorithm SHA256 | Format-List | Out-String | Set-Content (Join-Path $Output 'installed-apk-sha256.txt')
$taskInstalledPath=(DeviceAdb shell pm path pl.scalajaca.scalajaca | Where-Object { $_ -match '^package:.*/base[.]apk$' } | Select-Object -First 1) -replace '^package:',''
$taskInstalledPath=$taskInstalledPath.Trim()
if($taskInstalledPath -notmatch '^/data/app/[a-zA-Z0-9_/+=.~\-]+/base[.]apk$') { throw 'Nieprawidłowa ścieżka zainstalowanego APK.' }
DeviceAdb shell sha256sum $taskInstalledPath | Set-Content (Join-Path $Output 'installed-device-apk-sha256.txt')
$taskLog=Join-Path $Output 'instrumentation.log'
& $Adb -s $Serial shell am instrument -w -r -e scalajacaEmulator true -e modelSize $ModelSize -e class pl.scalajaca.scalajaca.local.LocalInferenceDeviceTest 'pl.scalajaca.scalajaca.test/androidx.test.runner.AndroidJUnitRunner' *> $taskLog
$taskRunnerExit=$LASTEXITCODE
Get-Content -LiteralPath $taskLog
# Debug run-as zachowuje ograniczenia aplikacji. Nie wymaga adb root.
$taskStart=[Diagnostics.ProcessStartInfo]::new($Adb)
$taskStart.UseShellExecute=$false
$taskStart.RedirectStandardOutput=$true
$taskStart.RedirectStandardError=$true
foreach($taskArg in @('-s',$Serial,'exec-out','run-as','pl.scalajaca.scalajaca','tar','-cf','-','files/emulator-proof')) { $taskStart.ArgumentList.Add($taskArg) }
$taskProcess=[Diagnostics.Process]::Start($taskStart)
$taskTar=Join-Path $Output 'proof.tar'
$taskStream=[IO.File]::Create($taskTar)
try { $taskProcess.StandardOutput.BaseStream.CopyTo($taskStream) } finally { $taskStream.Dispose() }
$taskTarError=$taskProcess.StandardError.ReadToEnd()
$taskProcess.WaitForExit()
if($taskProcess.ExitCode -ne 0) { throw "Odczyt dowodów: $taskTarError" }
& tar -xf $taskTar -C $Output
if($LASTEXITCODE -ne 0) { throw 'Nie odczytano archiwum dowodów.' }
$taskResult=Get-Content -LiteralPath $taskLog -Raw
if($taskRunnerExit -ne 0 -or $taskResult -notmatch 'OK \(6 tests\)' -or $taskResult -match 'FAILURES!!!|INSTRUMENTATION_FAILED') { throw 'Testy emulatora nie przeszły. Raport zachowano.' }
Write-Output "Sześć testów urządzenia PASS, w tym syntetyczny vault i generacja ze źródłem. Dowody: $Output. Emulator pozostaje offline."
