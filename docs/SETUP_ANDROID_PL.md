# Budowanie i instalacja na Androidzie

Aktualizacja 0.4.0: w Ustawieniach działa osobna **Pełna szyfrowana kopia** z przywracaniem projektów, wszystkich wersji źródeł, checkpointów, kampanii i sekretów MG. Zachowuje ID i granice ról, a każda kolizja wycofuje całość. Po odtworzeniu folder projektu łączy się ponownie jawnie przez SAF. Instrukcja i wyłączenia: [BACKUP_PL.md](BACKUP_PL.md); dowody: [TESTS_PL.md](TESTS_PL.md). Wzmianki o zaplanowanym pełnym backupie w historycznych sekcjach 0.3.0 opisują poprzednie wydanie. Synchronizacja nadal pozostaje zaplanowana.

## Wydanie 0.3.0

Aktualny debug APK: `Scalajaca-0.3.0-debug-arm64-x64.apk`, Android 7+/minSdk 24, targetSdk 36, ARM64 dla Pixel 9 i x86_64 dla testowego emulatora. Wagi GGUF pozostają osobno. Build, podpis i wyrównanie 16 KiB potwierdzono; emulator API 30 przeszedł 5 scenariuszy offline, fizyczny Pixel 9 wymaga odbioru. Aktualizacja `adb install -r <APK>` zachowuje dane i migruje bazę do v3; nie odinstalowuj aplikacji, jeśli chcesz je zachować. Nowe projekty i RPG nie są objęte dotychczasową przenośną kopią. Vault i kampanie: OBSIDIAN_PAMIEC_RPG_PL.md; dokładne sumy: test-results/android-build-0.3.0.json.

**Aktualizacja 0.2.1:** zbudowano APK z natywnym MiniCPM CPU/JNI, bez serwera i bez wag. Pełne testy Flutter: 141 PASS; JUnit lokalnego magazynu: 21 PASS, w tym pełny GGUF. Bieżący rozmiar/SHA i podpis potwierdza `test-results/android-build-0.2.1.json`. Instalacja oraz generacja na fizycznym Androidzie pozostają niewykonane. Instrukcja importu modelu: [MINICPM_PL.md](MINICPM_PL.md).

Potrzebne: Flutter stable (środowisko prac: 3.47.7, Dart 3.13.5), Git, JDK 17, Android SDK Platform 36, Build Tools 36.0.0 i platform-tools. Projekt wymaga minSdk 24 (Android 7+) zgodnie z Flutter 3.47; bezpieczny magazyn wymaga co najmniej 23. Wiążące wersje zależności zapisuje pubspec.lock po rozwiązaniu.

W zweryfikowanym buildzie użyto także NDK 28.2.13676358 i CMake 3.22.1. Pluginy pobrały SDK Platform 35. ABI celu określa parametr `--target-platform`; dostarczany debug APK zawiera ARM64 dla telefonu oraz x86_64 sprawdzony na emulatorze. Rozwiąż licencje SDK zgodnie z oficjalną instrukcją przed samodzielnym budowaniem.

**Dostarczony APK:** `Scalajaca-0.2.1-debug-arm64-x64.apk`, podpis debug v2 zweryfikowany, Android 7+, ARM64 lub x86_64. Rozmiar i SHA-256 są w bieżącym raporcie JSON obok logów podpisu/manifestu. Nie jest to wydanie produkcyjne/sklepowe. Wagi GGUF skopiuj na telefon osobno i zaimportuj przez Ustawienia → Dostawcy AI → MiniCPM offline. Po imporcie uruchom krótki czat w trybie samolotowym, przetestuj Stop oraz przejście w tło. Aplikacja nie wymaga płatnego API ani OPPO.

Źródła: [instalacja Flutter](https://docs.flutter.dev/install), [oficjalna konfiguracja Android](https://docs.flutter.dev/platform-integration/android/setup), [Android command line tools](https://developer.android.com/tools).

Test emulatora po zbudowaniu głównego APK (PowerShell 7, działający własny AVD Android 11 / API 30 Google APIs x86_64 po angielsku): `scripts/test_android_emulator.ps1 -Model <pełna-ścieżka-GGUF> -Serial emulator-5556`. Skrypt ogranicza się do emulatora, sprawdza hash publicznego modelu, buduje osobny testowy APK, ustawia tryb samolotowy, instaluje oba pakiety i wykonuje cztery scenariusze. Wymaga wolnego miejsca na model w Pobranych i prywatnej kopii. Nie pobiera wag ani nie instaluje sterowników Windows; pozostawia AVD offline. Raport domyślnie trafia do ignorowanego `work/emulator-tests`. Testy nie wymagają kont, roota ani płatnego API.

```powershell
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64,android-x64
```

Można użyć `scripts/build_android.ps1`. APK debug służy testom i jest podpisany kluczem debug, bez publikacji. Wynik oczekiwany: `build/app/outputs/flutter-apk/app-debug.apk`. **O istnieniu zweryfikowanego artefaktu rozstrzyga IMPLEMENTATION_STATUS.md i raport testów, a nie ta przykładowa ścieżka.**

Instalacja ręczna: skopiuj APK na telefon, sprawdź sumę SHA256, otwórz plik i świadomie zezwól instalatorowi na tę instalację. Alternatywnie po włączeniu debugowania USB i autoryzacji komputera:

```powershell
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Nie instalujemy automatycznie na prywatnym telefonie. Nie podłączamy kont podczas instalacji. Nie włączamy mikrofonu, kamery, kontaktów, zarządzania wszystkimi plikami, dokładnych alarmów ani Accessibility. Internet jest jedynym deklarowanym uprawnieniem sieciowym. Pliki wybierasz przez SAF, a odbiorcę tekstu przez systemowy Sharesheet.

Wyniki testów hosta nie zastępują sprawdzenia Keystore, cyklu życia i systemowych dokumentów na urządzeniu. Po instalacji wykonaj A01–A26 z docs/ACCEPTANCE_PL.md; produkcyjna generacja API wymaga Twojego klucza, świadomej zgody i może być płatna. Nie była elementem automatycznych testów tego projektu.
