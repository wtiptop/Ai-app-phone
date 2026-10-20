# Budowanie i instalacja na Androidzie

## Wydanie 0.5.1

Aktualny debug APK: `Scalajaca-0.5.1-debug-arm64-x64.apk`, versionCode 8, Android 7+/minSdk 24, targetSdk 36. Zawiera ARM64 dla Pixela 9 i natywny x86_64 dla emulatora. Wagi MiniCPM GGUF pozostają osobnym plikiem. Rozmiar i SHA-256: `test-results/android-build-0.5.1.json`. To lokalne wydanie testowe, bez publikacji sklepowej.

Przed aktualizacją wykonaj pełną szyfrowaną kopię w Ustawieniach, zgodnie z [BACKUP_PL.md](BACKUP_PL.md). Zainstaluj APK jako aktualizację podpisanej poprzedniej wersji (`adb install -r <APK>` lub systemowy instalator). Nie odinstalowuj aplikacji i nie używaj `pm clear` na swoim telefonie: usunęłoby to bazę i klucz urządzenia. Wydanie nadal używa bazy v3 i formatu pełnej kopii v2. Zachowuje zaimportowane źródła, ich wersje, checkpointy analiz i historię kampanii; nie wymaga ponownego konta ani serwera. Kolizje ID podczas przywracania kopii odrzucają całość, bez scalania.

Nowe ekrany wyszukiwania i wznowienia: [PAMIEC_CIAGLOSC_PL.md](PAMIEC_CIAGLOSC_PL.md). Model zaimportuj przez Ustawienia → Dostawcy AI → MiniCPM offline. Po imporcie sprawdź krótki czat, Stop i tło w trybie samolotowym. Fizycznego Pixela 9 nadal nie przetestowano: RAM, bateria, temperatura i długa narracja wymagają odbioru na telefonie. Wyniki hosta i emulatora są w [TESTS_PL.md](TESTS_PL.md).

Narzędzia użyte w środowisku: Flutter 3.47.7, Dart 3.13.5, JDK 17, Android SDK 36, Build Tools 36.0.0, NDK 28.2.13676358 i CMake 3.22.1. Pluginy używają także SDK Platform 35. Zależności pozostają przypięte w pubspec.lock. Dostarczany debug APK zawiera obie wybrane ABI; kod nie wymaga Obsidiana, OPPO, JARVIS, Termuxa ani płatnego API. Licencje SDK akceptuje właściciel narzędzi zgodnie z ich warunkami.

Źródła: [instalacja Flutter](https://docs.flutter.dev/install), [oficjalna konfiguracja Android](https://docs.flutter.dev/platform-integration/android/setup), [Android command line tools](https://developer.android.com/tools).

Test emulatora po zbudowaniu głównego APK (PowerShell 7, działający własny AVD Android 11 / API 30 Google APIs x86_64 po angielsku): `scripts/test_android_emulator.ps1 -Model <pełna-ścieżka-GGUF> -Serial emulator-5556`. Skrypt ogranicza się do emulatora, sprawdza hash publicznego modelu, buduje osobny testowy APK, ustawia tryb samolotowy, instaluje oba pakiety i wykonuje sześć scenariuszy. Wymaga wolnego miejsca na model w Pobranych i prywatnej kopii. Nie pobiera wag ani nie instaluje sterowników Windows; pozostawia AVD offline. Raport domyślnie trafia do ignorowanego `work/emulator-tests`. Testy nie wymagają kont, roota ani płatnego API.

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
