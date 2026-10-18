# Stan rzeczywistej implementacji

## Aktualizacja 0.2.0+3: prawdziwy MiniCPM offline — 18.10.2026

Dodano natywny silnik llama.cpp/ggml CPU/JNI w APK, osobny `LocalModelAdapter`, bezpośredni streaming do czatu i porównania oraz ekran lokalnych modeli. SAF importuje GGUF do prywatnego magazynu, oblicza SHA-256, sprawdza strukturę i pozwala anulować/usunąć kopię. Znane profile: tekstowe MiniCPM5-1B/2B; rzeczywiste wagi sprawdzono dla 1B Q4_K_M. Wbudowane przypięte szablony zastępują szablon z GGUF. Brak serwera, kont, klucza, pobierania w aplikacji i automatycznego fallbacku do chmury.

Zgoda wskazuje telefon, model i koszt API 0. LocalCostGate wiąże permit z wybranym hashem i nie odblokowuje płatnych dostawców. Limity kontekstu/wyjścia/CPU/czasu, wstępny test RAM, termika Android 10+ i anulowanie po przejściu w tło są wdrożone; ich zachowanie na telefonie wymaga odbioru.

**Wyniki rzeczywiste:** Flutter **141/141 PASS, exit 0**; JUnit modułu modeli **21/21 PASS, bez pominiętych, exit 0 całego Gradle** (w tym kopiowanie i walidacja pełnego 688 MB GGUF); Dart analyze bez uwag; ARM64 JNI build i APK **PASS**. Wspólny rdzeń C++ na Windows wygenerował `OK` z prawdziwych wag i przeszedł test anulowania przed startem. Audyt 1818 plików silnika potwierdził treść przypiętego commitu. Pobrano publiczne wagi wyłącznie po zgodzie właściciela. Nie wykonano płatnych operacji, łączenia prywatnych kont ani publikacji.

**Dostarczany artefakt:** `Scalajaca-0.2.0-debug-arm64.apk`, Android 7+, ARM64, podpis debug. Bieżący rozmiar i SHA-256: `docs/test-results/android-build-0.2.0.json`; instrukcja importu: `docs/MINICPM_PL.md`. APK zawiera silnik, bez wag.

**Ograniczenia:** brak instalacji, generacji JNI/SAF/Keystore/lifecycle/termiki na urządzeniu; brak benchmarku baterii/RAM/szybkości. Pierwsza próba po polsku dała słabą odpowiedź i limit tokenów; nie potwierdzono jakości PL. Brak testu rzeczywistych wag 2B, GPU/NPU, MiniCPM-V/audio, narzędzi i pobierania modeli w UI. Pozostałe niezrealizowane wymagania pierwotnej specyfikacji pozostają zaplanowane/ograniczone. Wyniki 0.1.1 i 0.1.0 poniżej są historyczne.

## Historia 0.1.1+2: MiniCPM — 18.10.2026

Dodano opcjonalny `MiniCpmAdapter`, konfigurację własnego serwera HTTPS, opcjonalny klucz Keystore, katalog modeli, tekst/SSE/usage/stop i bezpieczne błędy. Czat oraz porównanie pokazują adres odbiorcy. Zmiana adresu nie przenosi poprzedniego sekretu i zeruje deklarację bezpłatnego API. Własny serwer bez opłat wymaga jawnej deklaracji oraz obu stawek 0; pozostałe API nadal wymagają osobnej zgody i limitów. Minimalny port `CostStore` oddziela politykę kosztów od Fluttera, zachowując transakcje SQLite.

**Rzeczywisty wynik 0.1.1:** 73/73 testów Dart PASS, exit 0 (66 testów adapterów + 7 testów kosztów z prawdziwym SQLite FFI). Analiza kodu: bez uwag, exit 0. Kompilacja Flutter bundle ARM64 debug: PASS, exit 0. Pełny runner testów Flutter został zablokowany przed startem testów przez SocketException localhost; testów UI tej aktualizacji nie uznano za zaliczone. Próba APK: Gradle nie może połączyć się ze swoim procesem lokalnym. **Nie dostarczono nowego APK 0.1.1.** Wcześniejszy APK 0.1.0 nie zawiera MiniCPM.

**Zaplanowane / niewykonane:** silnik MiniCPM bezpośrednio w aplikacji, zarządzanie GGUF i test urządzenia; realny serwer/generacja, MiniCPM-V/audio i narzędzia. Nie pobrano wag, nie podłączono kont, nie wykonano płatnych operacji i niczego nie opublikowano. Szczegóły: `docs/MINICPM_PL.md`, ADR 005 i aktualna sekcja `docs/TESTS_PL.md`.

## Historia bazowej wersji 0.1.0

Data: **17.10.2026**. Wersja: **0.1.0+1**. Scalająca jest samodzielnym projektem Flutter/Android. Nie korzysta z OPPO, JARVIS, Termuxa, Obsidiana ani obowiązkowego serwera.

## Co działa w testach

- Polski interfejs pięciu zakładek, lokalny czat demo, strumieniowanie i zatrzymywanie atrapy, historia, szkice, wyszukiwanie i przypinanie.
- SQLite v2, migracja v1→v2, transakcje, zachowanie danych po ponownym otwarciu pliku, oznaczanie przerwanych odpowiedzi bez automatycznego retry, deduplikacja kolejki szkiców.
- AES-256-GCM treści i tytułów; testy integralności, przenoszenia kopii na inny klucz, błędnego hasła i wykluczenia API keys z kopii. Brak klucza istniejącej bazy blokuje odczyt bez nadpisywania klucza nowym.
- Tryb prywatny nowych rozmów w RAM. Testy potwierdzają brak zapisu tych rozmów, wiadomości i szkiców do SQLite.
- Cztery niezależne transporty oficjalnego API: OpenAI Responses, Anthropic Messages, Gemini SSE, xAI Chat Completions. 37 testów mock weryfikuje format żądań, SSE, katalogi, timeout, stop, przerwanie, brak retry, błędy i ochronę sekretów.
- Jednorazowa zgoda na realne API, płatne API domyślnie wyłączone, trwałe lokalne rezerwy dnia/miesiąca i atomowa rezerwa porównania. Nieznany cennik blokuje zapytanie do czasu konfiguracji.
- Ręczne notatki/foldery i lista zadań. Blokada automatycznych obrazów Markdown, semantyka przycisku wysyłania, test ekranu 320×640 z tekstem 200%.

**Wynik:** pełny zestaw **83/83 testów Flutter — PASS, exit 0**; późniejsza korekta ID deduplikacji kolejki: **6/6 testów storage — PASS, exit 0**. Analiza Dart: **No issues found, exit 0**. Szczegóły, poprawki i dowody w `docs/TESTS_PL.md`.

## Wymaga konfiguracji / weryfikacji na Androidzie

- Realna generacja API: użytkownik wprowadza klucz, model i cennik, włącza API, a następnie zatwierdza konkretną wysyłkę. **Nie wykonano live API ani płatnych operacji.** Test katalogu jest odrębną świadomą akcją i nie potwierdza płatnej generacji.
- Natywny Keystore i zapis pól są podłączone przez utrzymywany plugin. Natywnej ochrony kluczy nie potwierdza atrapa `MemorySecrets`; potrzebny test urządzenia.
- Kotlin implementuje SAF dla pojedynczych plików UTF-8 i eksportu oraz Sharesheet tekstu. Systemowe dialogi, powrót po anulowaniu i rotacja wymagają testu urządzenia. Wysyłka wielu plików, odbieranie share i katalogowy vault nie są wdrożone.
- Eksport rozmowy Markdown i zaszyfrowany JSON całych danych są dostępne w UI. Brak osobnego jawnego eksportu rozmowy JSON. Native SAF ma limit 16 MiB pliku; opakowanie base64 zmniejsza praktyczny rozmiar zaszyfrowanej kopii do około 12 MiB danych. Moduł kryptografii ma osobny większy limit.
- Eksperymentalne porównanie: 2–4 różnych dostawców, osobne odpowiedzi, jawny prompt/odbiorcy/rezerwy. Wyniki są w RAM; brak dwóch modeli jednego dostawcy, trwałego zapisu i zestawienia. Realne równoległe API nie zostało uruchomione.
- Model/cennik jest konfigurowalny. Katalog nie zawiera kompletnego, zweryfikowanego profilu każdej modalności/kontekstu/ceny. Wartości nieznane pozostają nieznane. Rezerwa to konserwatywny szacunek według stawek użytkownika, nie gwarancja rachunku dostawcy.

## Eksperymentalne moduły domenowe, bez pełnego wykonawcy w UI

- `AgentRun`, `AgentPlan`, role domenowe i niezależni kontrolerzy; wymagana zgoda, max 2 korekty, stany stop/błąd/wznowienie. Brak podłączonych LLM, narzędzi i trwałego wykonawcy. Ekran agentów jasno to opisuje.
- `BudgetGuard`: limity kroków, wywołań, czasu i kosztu, rezerwacje i blokady. Jest osobnym silnikiem RAM dla przyszłych agentów; trwały gate czatu jest w `LocalCostGate`.
- `MemoryAccessPolicy`: właściciel, projekt/kampania, widoczność i zatwierdzenie, fail-closed dla `GM_SECRET` w widoku gracza, recenzenta, indeksie i eksporcie. Zwykłe notatki nie są jeszcze pełnym repozytorium tej polityki. Nie importuj sekretów RPG do zwykłych notatek/czatu.
- RPG: manifest, izolowane agregaty, rewizje i rollback w RAM, hierarchia lore i jawne niezweryfikowane źródła. Brak narracji LLM, mechaniki WFRP, trwałego świata i kampanii Fio. Żadna istniejąca kampania nie została utworzona, zresetowana ani uruchomiona.
- `JarvisBridge`: wymienny kontrakt i wariant wyłączony. Parowanie, uwierzytelnienie, TLS i synchronizacja są zaplanowane; brak jakichkolwiek prób łączenia OPPO.

## Zaplanowane — nie uznawać za ukończone

SSO / użycie planów (w tym kwalifikowana ścieżka OpenAI), router Auto, konsensus/arbiter, wykonawcy agentów i narzędzi; pełne projekty/tagi/gałęzie rozmów; retrieval z uprawnionych fragmentów i wersjonowane fakty; vault/katalogi SAF; import plików/obrazów do modeli; głos/STT/TTS, aparat, przypomnienia i WorkManager; powiadomienia; kalendarz/poczta/dysk OAuth; monitoring AI/gospodarki/GPW/ESPI/EBI/gier/WFRP i Hamburga; nauka PL–DE; operacje w repozytoriach; boty Discord/Telegram/WhatsApp Business, Signal bez obietnicy oficjalnego API; osoby/profile/kanały; pełny RPG i lore z plików kanonu; synchronizacja, backend 24/7, most OPPO, AAB, optymalizacja baterii, biometria, ARB/i18n i testy TalkBack na urządzeniu.

Wszystkie wymagania (129 pozycji obejmujących 17 sekcji) są w `docs/REQUIREMENTS_TRACEABILITY_PL.md`; plan etapów jest w `docs/ROADMAP_PL.md`.

## Android i artefakt

**APK zbudowany i zweryfikowany — PASS, exit 0.** Plik: `Scalajaca-0.1.0-debug-arm64.apk`, 90 011 814 bajtów, Android 7+ (minSdk 24), targetSdk 36, wyłącznie ARM64. `apksigner verify` i `aapt2 dump badging`: exit 0; poprawny podpis debug v2. SHA-256: `65fb46821a1c36240529543e98aa7030b0a1c3be776d390a36c09b85a3cdd9db`.

Zweryfikowano wyłączone systemowe kopie danych i cleartext. Uprawnienia gotowego APK: INTERNET oraz wewnętrzne uprawnienie signature AndroidX `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`; brak mikrofonu, aparatu i szerokiego dostępu do plików. Dowody: `docs/test-results/android-build.json`, `apk-signature.log` i `apk-badging.log`.

Przygotowanie środowiska wymagało rzeczywistego NDK i CMake; błąd zakończenia podprocesu Flutter rozwiązano przez wyłączenie analityki także w procesach potomnych (`FLUTTER_SUPPRESS_ANALYTICS=true`). Nie zastępowano nieudanego wyniku sztucznym kodem sukcesu. Finalny pełny build przeszedł ponownie po ograniczeniu wszystkich bibliotek natywnych do ARM64 i dodaniu ikony Scalającej.

Nie przeprowadzono instalacji na telefonie/emulatorze. Żaden test hosta ani sam build nie potwierdza pełnej akceptacji urządzenia. Instrukcja: `docs/SETUP_ANDROID_PL.md`.

## Następny etap

Po udanym buildzie: ręczny odbiór na Androidzie bez sieci/kluczy/OPPO/Obsidiana, test SAF i Keystore, cykl życia i TalkBack. Dopiero po osobnej zgodzie właściciela — konkretne live API. Potem trwała obsługa porównań, pełne zakresy pamięci i wykonawca agentów. Kont i publikacji nie wykonujemy automatycznie.
