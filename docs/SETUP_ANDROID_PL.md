# Budowanie i instalacja na Androidzie

**Aktualizacja 0.2.0:** zbudowano APK z natywnym MiniCPM CPU/JNI, bez serwera i bez wag. Pełne testy Flutter: 141 PASS; JUnit lokalnego magazynu: 21 PASS, w tym pełny GGUF. Bieżący rozmiar/SHA i podpis potwierdza `test-results/android-build-0.2.0.json`. Instalacja oraz generacja na fizycznym Androidzie pozostają niewykonane. Instrukcja importu modelu: [MINICPM_PL.md](MINICPM_PL.md).

Potrzebne: Flutter stable (środowisko prac: 3.47.7, Dart 3.13.5), Git, JDK 17, Android SDK Platform 36, Build Tools 36.0.0 i platform-tools. Projekt wymaga minSdk 24 (Android 7+) zgodnie z Flutter 3.47; bezpieczny magazyn wymaga co najmniej 23. Wiążące wersje zależności zapisuje pubspec.lock po rozwiązaniu.

W zweryfikowanym buildzie użyto także NDK 28.2.13676358 i CMake 3.22.1. Pluginy pobrały SDK Platform 35. ABI celu określa parametr `--target-platform`; dostarczany debug APK jest przeznaczony dla ARM64. Rozwiąż licencje SDK zgodnie z oficjalną instrukcją przed samodzielnym budowaniem.

**Dostarczony APK:** `Scalajaca-0.2.0-debug-arm64.apk`, podpis debug v2 zweryfikowany, Android 7+ ARM64. Rozmiar i SHA-256 są w bieżącym raporcie JSON obok logów podpisu/manifestu. Nie jest to wydanie produkcyjne/sklepowe. Wagi GGUF skopiuj na telefon osobno i zaimportuj przez Ustawienia → Dostawcy AI → MiniCPM offline. Po imporcie uruchom krótki czat w trybie samolotowym, przetestuj Stop oraz przejście w tło. Aplikacja nie wymaga płatnego API ani OPPO.

Źródła: [instalacja Flutter](https://docs.flutter.dev/install), [oficjalna konfiguracja Android](https://docs.flutter.dev/platform-integration/android/setup), [Android command line tools](https://developer.android.com/tools).

```powershell
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

Można użyć `scripts/build_android.ps1`. APK debug służy testom i jest podpisany kluczem debug, bez publikacji. Wynik oczekiwany: `build/app/outputs/flutter-apk/app-debug.apk`. **O istnieniu zweryfikowanego artefaktu rozstrzyga IMPLEMENTATION_STATUS.md i raport testów, a nie ta przykładowa ścieżka.**

Instalacja ręczna: skopiuj APK na telefon, sprawdź sumę SHA256, otwórz plik i świadomie zezwól instalatorowi na tę instalację. Alternatywnie po włączeniu debugowania USB i autoryzacji komputera:

```powershell
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Nie instalujemy automatycznie na prywatnym telefonie. Nie podłączamy kont podczas instalacji. Nie włączamy mikrofonu, kamery, kontaktów, zarządzania wszystkimi plikami, dokładnych alarmów ani Accessibility. Internet jest jedynym deklarowanym uprawnieniem sieciowym. Pliki wybierasz przez SAF, a odbiorcę tekstu przez systemowy Sharesheet.

Wyniki testów hosta nie zastępują sprawdzenia Keystore, cyklu życia i systemowych dokumentów na urządzeniu. Po instalacji wykonaj A01–A26 z docs/ACCEPTANCE_PL.md; produkcyjna generacja API wymaga Twojego klucza, świadomej zgody i może być płatna. Nie była elementem automatycznych testów tego projektu.
