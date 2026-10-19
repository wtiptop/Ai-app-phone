# Rzeczywiste testy Scalającej

## Odbiór 0.4.0 — 19.10.2026, Europe/Warsaw

| Sprawdzenie | Rzeczywisty wynik | Dowód / granica |
|---|---|---|
| Flutter analyze | PASS, bez uwag, exit 0 | analyze-0.4.0.log |
| Pełny runner Flutter | **241/241 PASS**, exit 0 | flutter-tests-0.4.0.log; źródła, historia/checkpointy/role, nowe szyfrowanie, rollback, uszkodzenia i mały ekran RPG |
| JUnit Android | **36/36 PASS**, zero błędów i pominiętych | 21 GGUF, 6 vaultu, 9 backupu; XML i android-junit-0.4.0.log |
| Eksport i próby błędów na Androidzie | **1/1 PASS**, 59.109 s | prawdziwy ACTION_CREATE_DOCUMENT/OPEN_DOCUMENT w Downloads, złe hasło odrzucone przed potwierdzeniem, kolizja wycofana bez zmiany żadnego z 16 zestawów ID/liczników/szyfrogramów; prywatny staging usunięty |
| Przywrócenie po resecie testowej aplikacji | **1/1 PASS**, 86.917 s | pm clear wyłącznie własnej Scalającej na sprawdzonym AVD, nowy klucz treści, potwierdzony restore, czytelne projekty/notatki/checkpoint i RPG; sekret ukryty graczowi i dostępny MG |
| Porównanie kopii i celu | **PASS**, 72 rekordy w 16 tabelach | wszystkie liczniki i skróty identyfikatorów identyczne; szyfrogramy chronionych tabel inne; summary.json, backup-export.json i backup-restore.json |
| MiniCPM offline — regresja | **5/5 PASS**, 116.272 s | nowy import prawdziwego GGUF 688065920 B, odpowiedź OK, JNI Stop po tokenie, Stop UI i kolejna odpowiedź, Home/tło, SAF vaultu i fakt LANTERN z zachowanym dowodem źródeł |
| Offline | PASS przed/po każdym scenariuszu | samolotowy, WiFi/dane wyłączone, brak aktywnej sieci; bez płatnego API, kont i serwera |
| APK ARM64+x86_64 | **PASS**, build exit 0 | 0.4.0+6, podpis debug/manifest/ZIP i ELF 16 KiB, niezmieniony przypięty silnik, brak wag w APK; android-build-0.4.0.json/log |

Dwa scenariusze backupu uruchomiono osobno, z kontrolowanym resetem testowej aplikacji pomiędzy nimi, a pięć regresji modeli jednym standardowym AndroidJUnitRunner. Łącznie **7/7**, nie siedem w jednym procesie. Emulator: Android 11/API 30 x86_64, 4096 MiB RAM, AVD Scalajaca_API30. SHA APK wiąże oba raporty z dokładnie tym samym plikiem. Wagi: oficjalny MiniCPM5-1B Q4_K_M, hash 81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa, bez dołączenia do APK/źródeł.

Rzeczywisty zbiór Androida: 8 projektów, 9 dokumentów/wersji/fragmentów, 1 checkpoint analizy, 8 stanów importu, 2 kampanie, 1 wpis/wersja/zdarzenie RPG z sekretem MG, 5 rozmów, 10 wiadomości, 1 zakres i 1 dowód kontekstu oraz 6 notatek. Plik szyfrowany miał 18734 B. Zadania w tej fixture były puste; ich roundtrip i pełne wielowersyjne lore/rollback/checkpoint sesji zweryfikowano w testach hosta. Nie przeniesiono ustawień, kluczy, uprawnień folderów ani GGUF.

Testy kryptografii obejmują Unicode i rekord >256 KiB dzielony na odczyty 64 KiB, złe hasło, nagłówek/parametry, zmiany tagu/ciphertextu/metadanych, przestawienie/usunięcie/powtórzenie/splicing ramek, ucięcie, brak footera, dodatkowe bajty, autentycznie zaszyfrowane lecz błędne liczniki/manifest/footer, limity i anulowanie. Test danych przenosi wszystkie 16 tabel pomiędzy różnymi kluczami, zachowuje ID i dokładne historyczne receipts także po usunięciu źródła, odbudowuje HMAC i sprawdza role/GM, relacje, checkpointy, historię/rollback, późną kolizję i błąd po ostatnim wierszu. Chronione dane docelowe oraz ustawienia pozostają nietknięte przy błędzie.

Przegląd i testy ujawniły potrzebę sprawdzania anulowania przed każdym rekordem oraz końcowym zapisem SAF, poprawy kompatybilności historycznych cytowań i jawnego trybu wt w providerze. Poprawiono też rzeczywiste granice dostępności wiersza źródła oraz przepełnienia formularza i stronicowania RPG na małym ekranie. Test nowego ekranu sprawdza zapis sekretu przy 360×640 i brak wyjątków układu.

Wstępne próby automatu nie są liczone jako PASS. Miały błędne trafienie w scalaną kartę, za szybkie przewijanie dialogu, problemy z fokusem/klawiaturą, powrotem do katalogu i klikaniem ikony podglądu zamiast tytułu dokumentu. Zachowano przykładowe logi prób. Ostateczny backup/restore wykonano na już przygotowanym przez UI syntetycznym zbiorze z flagą ReuseExistingFixture; jego liczniki i role sprawdzono przed testem. Pełnego automatycznego tworzenia fixture przez formularze w jednym przebiegu nie odebrano. Nie pominięto kontroli integralności ani odczytu i filtracji sekretu po przywróceniu.

Odtworzenie: instrukcja BACKUP_PL.md oraz scripts/test_android_backup.ps1, a regresja modelu: scripts/test_android_emulator.ps1. Dowody i zrzuty: emulator-0.4.0/. Fizyczny Pixel 9, backup bliski 2 GiB, ogromny rzeczywisty vault, zewnętrzny chmurowy provider SAF, bateria/termika/szczyt RAM i jakość wielosesyjnej narracji RPG pozostają niezweryfikowane. Nie wykonano płatnych operacji, łączenia kont ani publikacji.


## Odbiór 0.3.0 — 19.10.2026, Europe/Warsaw

| Sprawdzenie | Wynik końcowy | Dowód / granica |
|---|---|---|
| Flutter analyze | PASS, bez uwag, exit 0 | analyze-0.3.0.log |
| Pełny runner Flutter | 193/193 PASS, exit 0 | flutter-tests-0.3.0.log |
| JUnit Android | 27/27 PASS, 0 pominiętych | android-junit-0.3.0.log, XML modeli i vaultu; pełny GGUF 688065920 B |
| Standardowy AndroidJUnitRunner | 5/5 PASS, exit 0 | android-emulator-0.3.0.log/json; emulator API 30 x86_64, 4 GB, prawdziwy model |
| GGUF / realna generacja / Stop | PASS | SAF pliku, odpowiedź OK, anulowanie JNI po tokenie, Stop UI i kolejna odpowiedź, Home/tło; osobne JSON i PNG |
| Lokalny vault i źródło w czacie | PASS | Prawdziwy SAF drzewa → import syntetycznych notatek → zatwierdzenie → wyszukanie → preview → fakt LANTERN z MiniCPM → zapisany receipt |
| Offline | PASS przed i po każdym scenariuszu | Tryb samolotowy, WiFi/dane wyłączone, brak aktywnej sieci; connectivity i offline-after w emulator-0.3.0/ |
| Migracje i wznowienie | PASS na hoście | v1/v2→v3 z zachowaniem danych; RPG close/reopen i rollback; 205 małych plików, przerwanie przy 102, nowy importer, retry cofniętego uprawnienia, max jeden aktywny odczyt |
| Granice kontekstu i sekretów | PASS na hoście | Scope MG/gracz/projekt/właściciel, szybkie dwa load, cofnięcie/zmiana źródła, podrobione cytaty i digest, brak dispatch bez właściwej zgody, UTF-8, archiwum 120 wiadomości, zachowanie receipt podczas UPDATE |
| APK | PASS, build exit 0 | android-build-0.3.0.json/log; podpis debug, manifest, ARM64+x86_64, silnik bez symboli socket/connect, ZIP i ELF 16 KiB, brak wag |

Wstępny pełny Flutter run miał 3 nieudane przypadki: test odczytu pierwszego rekordu zamiast konkretnego kanonu, kontrakt wyjątku przy ponownym użyciu permit i trafienie w przewinięty przycisk fixture. Skorygowano konkretny odczyt testu, zachowano odrzucenie użytej zgody przed dispatch i ustabilizowano przewijanie widget testu. Końcowy pełny run wszystkich 193 testów przeszedł. Zachowano `flutter-first-attempt-0.3.0.log`.

Nowy scenariusz emulatora wymagał naprawy fixture: Download root nie jest dozwolonym drzewem na Androidzie 11, UiAutomation nie wykonuje shell pipes/redirection do przygotowania plików, a przewijanie wymaga oczekiwania na stabilne położenie elementów. Fixture jest teraz przygotowywany przez adb push; test używa prawdziwego selektora folderu. Wcześniejsze próby nie są liczone jako PASS. Nie zmieniano asercji na atrapę modelu. Dokładne końcowe wyjście/usage/czas znajdują się w JSON scenariusza.

Odtworzenie: zbuduj APK, ustaw środowisko Android SDK/JDK/Flutter i uruchom `scripts/test_android_emulator.ps1 -Model <oficjalny GGUF>`. Skrypt sprawdza emulator/API 30 i hash modelu, przygotowuje własny syntetyczny folder, odłącza sieć, instaluje APK i uruchamia pięć testów. Nie uruchamiać go na telefonie z prywatnymi danymi. Nie wymaga adb root.

Nie wykonano odbioru fizycznego Pixel 9, testu dużego rzeczywistego vaultu, pełnego eksportu/rotacji SAF, wielomiesięcznej kampanii, jakości polskiej narracji, baterii/termiki/Doze ani ręcznego TalkBack. Wyszukiwanie po słowach i prosty fakt po angielsku nie dowodzą rozumienia całego zbioru i ciągłości RPG. Nowe projekty/RPG nie mają jeszcze pełnej przenośnej kopii. Brak kont, płatnego API i publikacji.

## Odbiór 0.2.1 — 18.10.2026, Europe/Warsaw

| Sprawdzenie | Rzeczywisty wynik | Dowód / granica |
|---|---|---|
| Flutter analyze | **PASS, No issues found, exit 0** | analyze-0.2.1.log |
| Pełny Flutter runner | **141/141 PASS, exit 0** | flutter-tests-0.2.1.log; asercja etykiety i live region statusu w istniejącym teście czatu |
| JUnit magazynu Androida | **21/21 PASS, 0 pominiętych, exit 0** | android-junit-0.2.1.xml i log; w tym pełny GGUF 688 065 920 bajtów |
| AndroidJUnitRunner 1.7.0 / UIAutomator 2.3.0 | **4/4 PASS, 0 błędów** | android-emulator-0.2.1.log/json; prawdziwe JNI, bez atrap modelu |
| Systemowy import GGUF | **PASS** | DocumentsUI → fizyczny Download → GGUF; hash 81b64d05…52deafa, prywatna kopia 688 065 920 bajtów i profil minicpm5_1b; imported.png |
| Czat offline z prawdziwym modelem | **PASS: OK, 21 wejście / 1 wyjście** | saf-offline-chat w JSON, offline-chat.png/xml; brak aktywnej sieci |
| Zatrzymanie po pierwszym tokenie JNI | **PASS, cancelled, 1 token wyjścia** | jni-stream-stop w JSON; rzeczywisty tekst przed Stop; opóźnienie 60 ms w tym przebiegu emulatora |
| Stop UI → następna generacja | **PASS** | Anulowano → nowa rozmowa → OK i dodatnia liczba tokenów; ui-stop-recovery, stopped.png / recovered.png |
| Przejście w tło | **PASS** | Home podczas generacji, powrót → Anulowano; background-stop i background-cancelled.png |
| Brak internetu | **PASS** | airplane_mode_on=1, Wi-Fi/data wyłączone, Active default network: none; asercje przed i po każdym teście |
| Build debug APK | **PASS, exit 0, 46,8 s** | android-build-0.2.1.log; testowano dokładnie hash z android-build-0.2.1.json |
| Podpis / manifest / biblioteki | **PASS** | debug v2; minSdk 24, targetSdk 36, arm64-v8a+x86_64; allowBackup/cleartext wyłączone; ZIP i ELF 16 KiB, JNI version/prepare/cancel/generate, bez importów sieciowych silnika |
| Licencje | **100 pakietów Dart, 0 braków** | zaktualizowane THIRD_PARTY_NOTICES.txt; źródła 1818 plików silnika i przypięte szablony bez zmian |
| Fizyczny telefon ARM64 | **Niewykonane** | Brak benchmarku telefonu, termiki, baterii i ręcznego TalkBack. Instalacja i inferencja potwierdzone tylko na x86_64 emulatora |
| Polski / 2B / porównanie na urządzeniu | **Niepotwierdzone** | Angielski prompt techniczny nie ocenia jakości PL. Wcześniejsza słaba próba PL pozostaje ograniczeniem |

Dowody w `docs/test-results/`; zrzuty w `emulator-0.2.1/`. Emulowane środowisko: Android Emulator 37.2.12.0, obraz Android 11 Google APIs x86_64 API 30 rev16, 4096 MiB RAM i 4 vCPU. AEHD 2.2.0 zainstalowano po wyraźnej zgodzie właściciela. To narzędzie hosta, nie zależność aplikacji na telefonie. Pomiar Stop dotyczy tego przebiegu, nie gwarantuje czasu na telefonie.

Wykryte problemy: ARM64 0.2.0 nie uruchomił się w translatorze ARM emulatora (SIGILL/libndk_translation); 0.2.1 dodaje pełny natywny x86_64. Usunięto nieużywane integration_test wnoszące konflikt starego runnera. Android scalał status z podpowiedzią zaznaczalnej odpowiedzi; dodano osobną granicę semantyki i ogłaszanie stanu. Wczesne przebiegi miały także błędy fixture: szukanie labelText jako tekstu, brak fokusu przed edycją, animacje/ukryte elementy selektora, zapamiętany katalog i zbyt późne zwalnianie SemanticsHandle. Nie zaliczono tych prób jako PASS. Końcowy pełny runner wykonał wszystkie cztery scenariusze oraz 141 testów Flutter po poprawkach.

Odtworzenie: zbuduj APK dla `android-arm64,android-x64`, uruchom przygotowany własny AVD Google APIs API 30 x86_64 po angielsku, następnie `scripts/test_android_emulator.ps1 -Model <pełna-ścieżka-oficjalnego-GGUF> -Serial emulator-5556`. Skrypt sprawdza model, instaluje APK i osobny testowy APK, wyłącza sieć, uruchamia standardowy runner i odczytuje prywatne dowody przez debug run-as. Bez pobierania wag, roota, kont i opłat. Błędy runnera kończą skrypt błędem, nawet jeśli samo am instrument zwróci exit 0.

Otwarte: fizyczny ARM64, cold start/force-stop i pełna trwałość, rotacja, usuwanie i anulowanie SAF na urządzeniu, TalkBack ręcznie, szczytowy RAM, bateria/Doze/termika, 2B, jakość PL i wszystkie pozostałe niewykonane kryteria A01–A34. Test importu GGUF nie odbiera eksportu innych plików przez SAF. Wszystkie live API/konta/publikacja pozostały niewykonane.

## Historia MiniCPM offline 0.2.0 — 18.10.2026

| Sprawdzenie | Wynik rzeczywisty | Dowód / granica |
|---|---|---|
| Dart analyze | **PASS, No issues found, exit 0** | test-results/analyze-0.2.0.log |
| Pełny Flutter test, concurrency=1 | **141/141 PASS, exit 0** | test-results/flutter-tests-0.2.0.log; obejmuje poprzednie testy, transporty, koszty, SQLite, kanał natywny oraz widgety |
| JUnit lokalnych modeli | **21/21 PASS, 0 skipped/errors/failures** | test-results/gguf-junit-0.2.0.xml; standardowy JUnit 4.13.2, prawdziwy plik GGUF przekazany przez SCALAJACA_TEST_MODEL |
| Gradle testDebugUnitTest | **BUILD SUCCESSFUL, exit 0** | test-results/android-unit-0.2.0.log; także dostępne zadania testów pluginów; nie dodajemy ich do licznika 21 aplikacji |
| Wspólny rdzeń C++ / Windows | **PASS, exit 0** | test-results/native-real-model-0.2.0.log; rzeczywiste wagi 1B, odpowiedź OK, wejście 21 / wyjście 1, finish stop; drugi scenariusz: anulowanie przed startem, 0 tokenów |
| Kompilacja JNI ARM64 i APK debug | **PASS, exit 0** | test-results/android-build-0.2.0.log oraz android-build-0.2.0.json |
| APK: podpis / manifest / ZIP 16 KiB / JNI | **PASS** | podpis debug v2, minSdk 24, targetSdk 36, arm64-v8a; ELF LOAD 0x4000, cztery eksporty JNI, brak importów funkcji sieciowych w silniku |
| Licencje / pochodzenie | **106 pakietów bez braków; 1818 plików upstream zgodnych** | THIRD_PARTY_NOTICES.txt, assets/native_notices.txt, vendor-audit-0.2.0.json i FILE_SHA256.json |
| Fizyczny Android / emulator | **Niewykonane** | Brak testu JNI na urządzeniu, SAF, cyklu życia, RAM, baterii, termiki i TalkBack; host/build nie zastępują odbioru |
| Jakość polskiego i rzeczywisty 2B | **Niepotwierdzone** | Pierwszy prompt PL: słaba odpowiedź, limit 128 tokenów. Test techniczny OK nie jest oceną jakości; nie pobrano wag 2B |
| Konta / płatne API / publikacja | **Niewykonane** | Model pobrano po osobnej zgodzie; brak kont, płatnych operacji i publikacji |

Zestaw natywny sprawdza metadane 1B/2B, błędne magic/version/architekturę/rodzinę, zduplikowane klucze, limity rozmiarów, nieznaną kwantyzację, wyrównanie wierszy, zakresy/nakładanie i ucięcie tensorów, anulowanie, SHA-256, deduplikację, ochronę ścieżek oraz sprzątanie wyłącznie zarządzanych plików częściowych/osieroconych. Test realnego pliku kopiuje 688 065 920 bajtów, weryfikuje oficjalny hash i 219 tensorów, usuwa kopię i potwierdza istnienie oryginału. Nie jest testem platformowego selektora SAF.

Nowe testy Flutter obejmują granice adaptera offline (bez klucza/chmury, kontekst, limity i stop), składanie UTF-8 między tokenami, redakcję błędów platformy, częściowe odpowiedzi i ignorowanie obcych zdarzeń, wybór/import/usuwanie w UI oraz lokalny czat po zgodzie bez płatnego API. Atrapa kanału potwierdza protokół, nie uruchamia JNI. Pojedynczy silnik w porównaniu nie przekazuje odpowiedzi do innych kart.

Naprawy podczas testowania: dopasowano kod do rzeczywistego API llama.cpp 0.7; testy UI przewijają zewnętrzną listę zamiast pola SelectableText, czekają na zniknięcie SnackBar przed usuwaniem i wykonują rzeczywisty SQLite przez runAsync poza zegarem testWidgets. Pierwsze przebiegi zawierały błędy fixture i zostały odrzucone; dopiero końcowy pełny wynik to 141 PASS. Początkowe blokady localhost/PDB zostały rozwiązane przez zatwierdzone uruchomienie poza piaskownicą. Nie zastępowano frameworka ani kodów błędów sztucznym sukcesem.

Odtworzenie: `flutter analyze`, `flutter test --reporter expanded --concurrency=1`, `scripts/test_android_local.ps1 -Model <pełna-ścieżka-GGUF>`, a w środowisku z kompilatorem C++/CMake/Ninja `scripts/test_local_native.ps1 -Model <pełna-ścieżka-GGUF>`. Bez wskazanego pliku JUnit pomija jeden test prawdziwych wag; takiego przebiegu nie wolno opisać jako 21 testów z wagami. Skrypty nie pobierają modelu. Build: `flutter build apk --debug --target-platform android-arm64`. Narzędzia: Flutter 3.47.7, Dart 3.13.5, JDK 17.0.20.1, Gradle 9.3.1, AGP 9.1.0, SDK/build-tools 36, NDK 28.2.13676358, CMake 3.22.1, MSVC 2022 dla testu hosta.

Ostrzeżenia buildu: starszy parser SDK XML i zapowiedzi usunięcia opcji zgodności Kotlin/AGP w Gradle/AGP 10. Obecny build kończy się kodem 0; nie wykonano migracji do przyszłej wersji narzędzi. Historyczne nieudane próby 0.1.1 poniżej nie opisują bieżącego APK.

## Historia MiniCPM 0.1.1 — 17–18.10.2026

| Sprawdzenie | Wynik rzeczywisty | Dowód / ograniczenie |
|---|---|---|
| Offline pub get | Rozwiązane; 106 pakietów, notice bez braków | Bieżący pubspec.lock, scripts/collect_notices.ps1 |
| Dart analyze | **PASS, No issues found, exit 0** | test-results/analyze-0.1.1.log |
| Dart test: providers + minicpm_cost | **73/73 PASS, exit 0** | test-results/dart-tests-0.1.1.log; 37 wcześniejszych + 29 MiniCPM + 7 kosztów |
| SQLite kosztów | **7/7 PASS**, część powyższych 73 | Prawdziwy SQLite FFI: deklaracja 0, jednorazowy permit, brak odblokowania płatnego API, mieszane porównanie, atomowe równoległe rezerwy |
| Flutter bundle ARM64 debug | **PASS, exit 0** | test-results/flutter-bundle-0.1.1.json; kernel_blob.bin 79 307 200 bajtów, to kompilacja części Flutter, nie APK |
| Pełny runner Flutter / widgety | **Zablokowane przed wykonaniem testów** | test-results/flutter-tests-0.1.1-blocked.log; SocketException localhost errno 10057, 11 plików nie załadowano; nie jest to zaliczenie testów UI |
| Android APK 0.1.1 | **Zablokowane, brak nowego APK** | test-results/android-build-0.1.1-blocked.log; Gradle „Could not connect to the Gradle daemon”, zgłoszony exit 1, proces Flutter zakończył się NTSTATUS -1073741816 |
| Serwer, wagi, generacja i telefon MiniCPM | **Niewykonane** | Bez pobrania wag, kont, płatnych operacji i publikacji |

Testy adapterów używają prawdziwych atrap `package:http`, bez ruchu sieciowego. Zestaw zawiera walidację HTTPS/URL, tekst UTF-8, parametry, katalog, opcjonalny klucz, błędy 302/401/429/503, brak retry/redirect, redakcję body, niepełny stream, stop przed dispatch i nagłówkami, blokadę narzędzi oraz zmianę zatwierdzonego odbiorcy. Nie dowodzi jakości ani tożsamości modelu na serwerze.

W tej sesji pierwszy test odpowiedzi Unicode miał błędną atrapę `http.Response` bez charset UTF-8; poprawiono fixture, a końcowy zestaw 73/73 przeszedł. Pierwsza analiza wskazała styl składania tekstu w teście; poprawiono. Próba testów Flutter nie doszła do asercji z powodu ograniczenia środowiska; nie przemianowano jej na PASS. Dwa nowe widget testy są przygotowane, lecz wymagają uruchomienia standardowego runnera w środowisku z działającym localhost. Nowy pakiet `test` jest zależnością deweloperską, nie silnikiem MiniCPM.

Odtworzenie po `flutter pub get`: `dart test test/providers test/security/minicpm_cost_test.dart --reporter expanded` (lub scripts/test_dart.ps1). W ograniczonym środowisku uruchomiono bezpośrednio `test-1.31.1/bin/test.dart` z `--packages=.dart_tool/package_config.json`; jest to standardowy runner Dart i te same pliki testów, bez własnego licznika udającego framework. Pełne `flutter test` i build APK trzeba ponowić po usunięciu blokady localhost. Bez obchodzenia uprawnień systemowych.

## Historia potwierdzonej wersji 0.1.0

Data: **17.10.2026**, Europe/Warsaw. Środowisko: Windows, Flutter **3.47.7**, Dart **3.13.5**, JDK **17.0.20.1**, AGP **9.1.0**, Gradle **9.3.1**, SDK 36, NDK **28.2.13676358**. Testy hosta nie oznaczają instalacji na telefonie.

| Sprawdzenie | Rzeczywisty wynik | Dowód / granica |
|---|---|---|
| Zależności | Rozwiązane; prawdziwy YAML lockfile | pubspec.lock; 82 pakiety zależności, bez sekretów |
| dart analyze | **PASS — No issues found, exit 0** | test-results/dart-analyze.log |
| flutter --suppress-analytics --no-version-check test --no-pub --reporter expanded | **PASS — 83/83 testów, exit 0** | test-results/flutter-tests.log; oryginalne testy w standardowym runnerze Flutter |
| Po późniejszej korekcie ID kolejki: flutter ... test/storage | **PASS — 6/6, exit 0** | test-results/storage-tests.log; to podzbiór 83, nie sumujemy drugi raz |
| standalone_domain_check.dart | **PASS — 35 kontroli, exit 0** | Wcześniejszy niezależny runtime domeny/kryptografii; nie dodawany do 83 |
| Pokrycie dokumentacji | 129 ID, 17/17 sekcji, brak powielonych ID | REQUIREMENTS_TRACEABILITY_PL.md; to nie 129 ukończonych funkcji |
| Akceptacja | 27 scenariuszy przygotowanych | ACCEPTANCE_PL.md; nie wszystkie wykonano ręcznie |
| Android build | **PASS — exit 0** | Finalny pełny build: 35,5 s; `test-results/android-build.json` |
| APK: podpis / manifest / ABI | **PASS — exit 0 / 0** | Podpis debug v2, minSdk 24, targetSdk 36, arm64-v8a; `apk-signature.log`, `apk-badging.log` |
| Emulator / telefon | **Niewykonane** | Brak deklaracji native lifecycle, TalkBack, SAF i Keystore na urządzeniu |
| Live API czterech AI | **Niewykonane** | Wszystkie HTTP testowe są atrapami; brak płatnych operacji i kont |
| Konta, komunikatory, publikacja | **Niewykonane** | Nie połączono kont, nie wysłano wiadomości, nie opublikowano aplikacji |

## Zakres 83 testów

- **37 scenariuszy providerów:** cztery protokoły, katalogi, UTF-8/chunking/multiline SSE, terminalne znaczniki, usage, HTTP/SSE errors, 401/429, brak klucza, brak retry, redakcja body, przekierowania, timeouty, anulowanie przed nagłówkami i podczas oczekiwania na bajty.
- **Bezpieczeństwo i domena:** zgody, jednorazowy permit, brak wysyłki po stop przed dispatch, jedna pierwsza wysyłka, prywatne rozmowy bez DB, ACL/GM_SECRET, izolacja kampanii/projektów, spoofing kanału, plany/kontrolerzy i max 2 korekty, limity czasu/kroków/wywołań/kosztów, stop/wznowienie i wyłączony most.
- **Kryptografia i transfery:** realne AES-GCM/PBKDF2, random salt/nonce, złe hasło, sabotaż, parametry/wersja kopii, szyfrowane pola SQLite, brak API keys w snapshot, import system-role/path rollback, portable restore innym kluczem, nieskończone limity i atomowe rezerwy porównania.
- **6 scenariuszy plikowej bazy:** v1→v2, close/reopen z historią/szkicem/search/notatką, interrupted bez retry, deduplikacja/kaskada, brak osieroconej wiadomości, utrata klucza bez jego nadpisania.
- **7 scenariuszy UI/granicy sesji:** start bez konta, demo czat, notatka/zadanie, 320×640 i tekst 200% z semantyką wysyłania, brak pobierania obrazów Markdown, API bez zgody zablokowane, prywatna sesja bez DB.

MemorySecrets nie potwierdza Android Keystore. Close/reopen pliku nie zastępuje ubicia procesu Android. Mock nie potwierdza uprawnień konta ani dostępności modelu.

## Poprawki po przeglądzie i nieudanych testach

| Problem | Stan |
|---|---|
| Podwójne szyfrowanie tasks.title przy restore | Odszyfrowanie przed snapshot; portable restore PASS |
| Infinity w budżecie i częściowa rezerwa porównania | Walidacja oraz jedna transakcja grupy; testy PASS |
| Wyścig pierwszych wysyłek i anulowanie przed dispatch | Blokada synchroniczna i kontrola cancellation; PASS |
| Pierwsze szkice zapisywane równolegle | Serializacja UI; poprawka w kodzie |
| Retry zachowywał ostatnią odpowiedź assistant | Kontekst ponowienia kończy się na właściwym user; stare dane zachowane |
| Cichy GET / odczyt pliku przez obraz Markdown | Blokujący imageBuilder; widget test PASS |
| Testowe bazy :memory: współdzieliły instancję | singleInstance=false dla RAM; test portable restore PASS |
| Semantyka przycisku i niezamknięty uchwyt w teście | Jawna etykieta i prawidłowy dispose; 200% UI PASS |
| Równoczesny SAF mógł zgubić wcześniejszy pending | Drugi wynik busy bez kasowania pierwszego; wymaga testu Android |
| Zduplikowane zadanie kolejki zwracało nowe nieistniejące ID | Zwraca prawdziwe ID w transakcji; test dedup PASS |

Wcześniejsze próby subagentów blokował sandbox loopback OS 10057, TEMP i hook natywny. Po konfiguracji główny proces wykonał oryginalny zestaw Flutter (83/83, exit 0). Backend testowy opisuje ADR 004. Nie zmieniano źródeł SDK ani nie pomijano nieudanych asercji.

## Następny odbiór

Po udanym buildzie wykonać A01/A02/A05/A07/A12/A15/A19/A21 na Androidzie: offline i bez kluczy, cold start/ubijanie procesu, trwałość, Keystore, SAF anulowanie/rotacja, backup i TalkBack. Live API wymaga osobnej zgody na konkretny płatny zakres. Scenariusze agentów, RPG i narzędzi pozostają ograniczone do faktycznie podłączonych komponentów.
