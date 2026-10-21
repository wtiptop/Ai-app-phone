param(
    [string]$Adb = (Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'),
    [string]$Apk = (Join-Path $PSScriptRoot '../build/app/outputs/apk/debug/app-debug.apk'),
    [string]$TestApk = (Join-Path $PSScriptRoot '../build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk'),
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Output | Out-Null
function Device {
    & $script:Adb -s emulator-5556 @args
    if ($LASTEXITCODE -ne 0) { throw 'Nie udało się wykonać operacji na emulatorze.' }
}
if ((Device shell getprop ro.kernel.qemu).Trim() -ne '1' -or
    (Device shell getprop ro.kernel.qemu.avd_name).Trim() -ne 'Scalajaca_API30') {
    throw 'Test jest ograniczony do własnego emulatora Scalajaca_API30, port 5556.'
}
Device shell cmd connectivity airplane-mode enable
Device shell svc wifi disable
Device shell svc data disable
Device shell dumpsys connectivity | Set-Content (Join-Path $Output 'offline-before.txt') -Encoding utf8
Device install -r $Apk
Device install -r $TestApk
$taskHash = (Get-FileHash $Apk -Algorithm SHA256).Hash.ToLowerInvariant()
Device shell am instrument -w -r -e class pl.scalajaca.scalajaca.colibri.ColibriDeviceTest pl.scalajaca.scalajaca.test/androidx.test.runner.AndroidJUnitRunner |
    Set-Content (Join-Path $Output 'instrumentation.log') -Encoding utf8
$taskLog = Get-Content (Join-Path $Output 'instrumentation.log') -Raw
Device shell dumpsys connectivity | Set-Content (Join-Path $Output 'offline-after.txt') -Encoding utf8
if ($taskLog -notmatch 'OK \(5 tests\)' -or $taskLog -match 'FAILURES!!!|INSTRUMENTATION_FAILED') { throw 'Nie zaliczono testów portu.' }
foreach ($taskState in @('offline-before.txt','offline-after.txt')) {
    if ((Get-Content (Join-Path $Output $taskState) -Raw) -notmatch 'Active default network: (none|null)') {
        throw 'Nie potwierdzono odłączenia emulatora od internetu.'
    }
}
[ordered]@{
    apkSha256 = $taskHash; tests = 5; failures = 0; emulator = 'Scalajaca_API30'
    data = 'synthetic-test; NIE wytrenowany model'; fullModelWeightsTested = $false
    physicalPixel9Tested = $false
} | ConvertTo-Json | Set-Content (Join-Path $Output 'result.json') -Encoding utf8
Write-Output '5 testów portu Colibri PASS offline na danych syntetycznych. Nie jest to odbiór jakości pełnego modelu.'
