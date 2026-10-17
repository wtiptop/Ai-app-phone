# Budowanie i instalacja na Androidzie

**Aktualizacja 0.1.1 z MiniCPM:** dostępna jako źródła. Kompilacja Flutter bundle przeszła; nowy APK jest zablokowany przez brak połączenia z lokalnym procesem Gradle w środowisku wykonania. Poniższy APK 0.1.0 jest historyczny i nie zawiera MiniCPM. Po usunięciu ograniczenia środowiska wykonaj pełne `flutter test`, build APK i weryfikację podpisu; nie traktuj starego artefaktu jako aktualizacji. Instrukcja MiniCPM: `MINICPM_PL.md`.

Potrzebne: Flutter stable (środowisko prac: 3.47.7, Dart 3.13.5), Git, JDK 17, Android SDK Platform 36, Build Tools 36.0.0 i platform-tools. Projekt wymaga minSdk 24 (Android 7+) zgodnie z Flutter 3.47; bezpieczny magazyn wymaga co najmniej 23. Wiążące wersje zależności zapisuje pubspec.lock po rozwiązaniu.

W zweryfikowanym buildzie użyto także NDK 28.2.13676358 i CMake 3.22.1. Pluginy pobrały SDK Platform 35. ABI celu określa parametr `--target-platform`; dostarczany debug APK jest przeznaczony dla ARM64. Rozwiąż licencje SDK zgodnie z oficjalną instrukcją przed samodzielnym budowaniem.

**Dostarczony APK został rzeczywiście zbudowany.** `Scalajaca-0.1.0-debug-arm64.apk`: 90 011 814 bajtów; podpis debug v2 zweryfikowany. SHA-256: `65fb46821a1c36240529543e98aa7030b0a1c3be776d390a36c09b85a3cdd9db`. Wymaga telefonu ARM64 z Androidem 7 lub nowszym. Nie jest to wydanie produkcyjne/sklepowe. Test instalacji i działania na urządzeniu pozostaje niewykonany.

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
