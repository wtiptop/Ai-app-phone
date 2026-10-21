# Budowanie i instalacja na Androidzie

<!-- release-0.5.3:start -->
## Wydanie 0.5.3+10

Nazwa głównego artefaktu: `Scalajaca-0.5.3-debug-arm64-x64.apk`, versionCode 10. Build, podpis, rozmiar i ABI potwierdza `test-results/android-build-0.5.3.json`. SHA-256 APK z raportu Androida: `c92206953a2cf83a5edbf4b6175318fdbf83d82386e8dea6021b1e827597a417`. Regresja: Flutter: **285/285 zaliczonych**; JUnit: **39/39 zaliczonych**; Android: **8/8 PASS; 0 FAIL; 0 pominiętych** (882.325 s). Android obejmuje 8 różnych scenariuszy oraz 1 dodatkowe wykonanie wzmocnionego testu f: trzy różne ID nowych odpowiedzi i odczyt ostatniej karty UI na końcu listy. Łącznie 9 wykonań instrumentacji; powtórne f nie jest dziewiątym różnym scenariuszem.

Aktualizacja przez `adb install -r <główny-APK>` lub systemowy instalator zachowuje dane i klucz. Najpierw wykonaj szyfrowaną kopię. Nie odinstalowuj aplikacji ani nie używaj `pm clear` na prywatnym telefonie. Baza v3/kopia v2/receipt v1 bez migracji. Nie instaluj targetu `test_driver/rpg_soak.dart` jako zwykłej aplikacji; diagnostyczny APK ma inny entrypoint i hash.

W Ustawienia → Dostawcy AI → MiniCPM offline przycisk „Wpisz hash 2B” tylko wypełnia oczekiwane SHA-256. Dopiero „Importuj plik GGUF” otwiera SAF i kopiuje dobrowolnie wybrane wagi. Pozostaw miejsce na oryginał, prywatną kopię i rezerwę 256 MiB; plik 2B to około 1489 MiB. Starszy 1B pozostaje dostępny. Większy plik nie jest pomiarem szczytu RAM.

Ponowne wskazanie identycznego, poprawnie zweryfikowanego lokalnego vaultu read-only zachowuje dawny uchwyt/ID także przy limicie 8. Nie czyść starych ID ani danych, aby powtarzać test. Nowy folder nadal podlega limitowi, a eksport z prawem zapisu zawsze wymaga osobnego uchwytu. Komunikat `vault_limit` nie ujawnia ścieżek.

Testy techniczne: `scripts/test_android_local.ps1 -Model <1B.gguf> -Model2B <2B.gguf>`; bez `Model2B` przypadek realnego 2B może być pominięty. UI/JNI: `scripts/test_android_continuity.ps1 -Model <2B.gguf> -ModelSize 2b -Output <osobny-folder>` na własnym AVD, nigdy na prywatnym telefonie. Instrukcja 24 sesji i parametr `RPG_MODEL_SHA`: [RPG_KAMPANIA_TEST_PL.md](RPG_KAMPANIA_TEST_PL.md).

Emulator x86_64 Android 11/API 30 ma 4 GiB RAM; konfiguracja modelu to 4096 tokenów. Próbki `dumpsys meminfo` pobierane około co 10 sekund są diagnostyką i mogą ominąć najwyższe zużycie — nie są pomiarem szczytu RAM. Nie są też wynikiem fizycznego Pixela 9/ARM64, baterii ani termiki. Sześć syntetycznych faktów jest pytanych wielokrotnie w nowych czatach; nie są to 24 pełne sesje gry ludzi. Markery sekretów i regex braku źródła nie zastępują ręcznego odczytu parafraz, języka i sprzeczności. Nie ma automatycznego kontrolera lore ani pełnej mechaniki WFRP. Ścisłe odtworzenie faktów nie zastępuje oceny narracji i konfliktów bieżącego kanonu ze starą notatką. Zachowanie zasad i poprawne rozumienie jawności są oceniane oddzielnie od samego braku markerów sekretu. Finał po zmianach promptu/formatu nie jest porównaniem wyłącznie modeli 1B i 2B. Starsza instrukcja wydania 0.5.2 poniżej pozostaje historią.
<!-- release-0.5.3:end -->

## Historyczne wydanie 0.5.2

Aktualny debug APK: `Scalajaca-0.5.2-debug-arm64-x64.apk`, versionCode 9, Android 7+/minSdk 24, targetSdk 36. Zawiera ARM64 dla Pixela 9 i natywny x86_64 dla emulatora. Wagi MiniCPM GGUF pozostają osobnym plikiem. Rozmiar i SHA-256: `test-results/android-build-0.5.2.json`. To lokalne wydanie testowe, bez publikacji sklepowej.

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
