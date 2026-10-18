# Rzeczywiste testy Scalającej

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
