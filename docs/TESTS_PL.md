# Rzeczywiste testy Scalającej

## Aktualizacja MiniCPM 0.1.1 — 17–18.10.2026

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
