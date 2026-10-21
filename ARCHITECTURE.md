# Architektura Scalającej

<!-- release-0.5.4:start -->
## Colibri 0.5.4

Nowy adapter `colibri_local` używa osobnej nieeksportowanej usługi Androida `:colibri`, JNI i potoków stdin/stdout. Brak serwera i Pythona w telefonie. Każda odpowiedź ma świeży proces/KV; źródła i role kontroluje wspólna warstwa aplikacji. Lokalne modele w porównaniu działają kolejno. Decyzja: ADR/014-colibri-offline-android.md; szczegóły: docs/COLIBRI_PL.md.

<!-- release-0.5.4:end -->

Aktualizacja 0.5.2: `CampaignStore.contextPack` filtruje słowa pospolite pytań, stronicuje kandydatów po 40 z limitem 2000 i wymaga pełnego zmieszczenia ręcznego wyboru/checkpointu. Wynik zachowuje hierarchię i oznaczenie rodzaju wpisu. MG może wyłączyć automatyczny checkpoint bez zmiany trwałego świata. Lokalne pakiety kampanii wymagają kontekstu 4096; mniejsze okna pozwalają nadal przeglądać i edytować dane. `ChatSession` dla MiniCPM ze źródłami składa dane i pytanie w jedną turę user, zachowując osobny stały system i digest dokładnego tekstu. Baza v3, backup v2 i receipt v1 bez zmian. Próba 24 symulowanych sesji działa przez oddzielny target Androida; nie stanowi odbioru jakości pełnej gry. ADR 012, docs/RPG_KAMPANIA_TEST_PL.md i bieżący raport opisują granice.

## Zmiana 0.5.1

PreparedChat wylicza sourceGrounded dla lokalnego MiniCPM z załącznikiem, ujmuje bool i pełny prompt w digest i przekazuje go przez ProviderRequest → LocalModelAdapter → MethodChannel → Kotlin/JNI → greedy C++. Własny system prefix jest stały, źródła pozostają user-data; zgoda i walidacja scope/rewizji poprzedzają dispatch. False zachowuje poprzedni profil. Budżet obejmuje prefix; baza v3/backup v2/receipt v1 bez zmian. ADR 011 i rzeczywiste testy opisują granice jakości.

## Rozszerzenie 0.5.0 — przywołanie danych i historia sesji

MemoryStore.search stronicuje aktualne zatwierdzone źródła, rankinguje pokrycie pytania w rundach dokumentów i odszyfrowuje tylko stronę. retrieveSelected osobno sprawdza cały wybór i dokładny budżet JSON/UTF-8. Punkty analiz mają starsze strony i odczyt po ID. CampaignStore czyta historię rpg_versions kursorem rewizji; compareRecordVersion pokazuje różnice, a resumeCheckpoint atomowo tworzy nową rewizję samej notatki sesji. Archiwum jest tylko lokalnym widokiem MG z opt-in, bez dostępu gracza/modelu/recenzenta. Nie zmieniono schematu v3, indeksu HMAC ani kopii v2. Decyzje i granice: ADR/010-pamiec-i-ciaglosc-sesji.md; instrukcja: docs/PAMIEC_CIAGLOSC_PL.md.

Aktualizacja 0.4.0 (19.10.2026): `BackupDataset` odczytuje 16 tabel w jednej transakcji snapshotu → `EncryptedArchive` tworzy kontener v2 z łańcuchem AES-GCM → `BackupFilesBridge`/`BackupFilePlugin` zapisują szyfrogram przez SAF. Przywracanie uwierzytelnia manifest, prosi o potwierdzenie, następnie w jednej transakcji waliduje rekordy/relacje/role, szyfruje pola nowym kluczem i odbudowuje HMAC. Dopiero stopka i EOF pozwalają zatwierdzić. Kolizja odrzuca całość; ID i historyczne receipts pozostają dokładne. Szczegóły: ADR 009 oraz `docs/BACKUP_PL.md`. Synchronizacja nie jest częścią backupu.

Aktualizacja 0.3.0 (19.10.2026): `VaultBridge` → lokalny SAF → `VaultImporter` → szyfrowane wersje/fragmenty SQLite v3 → indeks słów HMAC → zatwierdzony `ContextPacket`. Osobny `CampaignStore` przechowuje kanon/encje/wiedzę gracza/checkpointy i audyt. `ChatSession.prepare` zamraża ograniczoną historię i źródła; zgoda jest związana z digestem, a dispatch sprawdza aktualność i zakres. Rozmowy MG i gracza nie dzielą historii. Import ma trwały checkpoint po pliku; stan analizy jest ręcznie zatwierdzany. Instrukcja i granice: `docs/OBSIDIAN_PAMIEC_RPG_PL.md`, ADR 008. Synchronizacja i automatyczne orkiestracje pozostają zaplanowane.

Aktualizacja 0.2.1 (18.10.2026): `local_inference` jest wdrożonym osobnym modułem. `LocalModelAdapter` → `AndroidLocalEngine` → MethodChannel → Kotlin executor → JNI → przypięte llama.cpp/ggml CPU. Prywatny magazyn GGUF i jego metadane są plikowe, wybór hasha/kontekstu jest ustawieniem SQLite. Jedna operacja silnika w procesie, brak sieci i fallbacku, limity zasobów i anulowanie w tle. Rdzeń C++ jest wspólny z testem rzeczywistych wag na hoście. APK ma ARM64 i x86_64. Generację JNI sprawdzono na emulatorze Android 11 x86_64; fizyczny telefon wymaga osobnego odbioru. Zobacz ADR 006/007 oraz `docs/MINICPM_PL.md`.

`MiniCpmAdapter` z 0.1.1 pozostaje osobnym opcjonalnym klientem własnego serwera HTTPS; `CostStore` nadal rozdziela politykę kosztów i SQLite. Lokalna generacja ma koszt API 0 i permit związany z hashem, bez znoszenia blokad innych dostawców.

Data decyzji: 2026-10-17. Główny produkt to proces Android/Flutter i lokalna baza na telefonie. OPPO nie uczestniczy w uruchamianiu, przechowywaniu danych ani podstawowym czacie.

```mermaid
flowchart TD
  UI[Flutter Material 3 / polski UI] --> Consent[Jawna zgoda: odbiorca + zakres + koszt]
  UI --> Local[SQLite i szyfrowane pola]
  Consent --> Budget[Trwała rezerwa lokalna / jednorazowy permit]
  Budget --> Chat[ChatSession / historia i stan strumienia]
  Chat --> Registry[ProviderRegistry]
  Registry --> Offline[LocalModelAdapter bez sieci]
  Offline --> Channel[MethodChannel i executor Kotlin]
  Channel --> JNI[JNI llama.cpp CPU w procesie Androida]
  JNI --> GGUF[Prywatny magazyn GGUF]
  Registry --> Demo[Demo bez sieci]
  Registry --> API[Oficjalne API HTTPS / SSE]
  API --> Chat
  Chat --> Local
  Keys[Android Keystore] --> Cipher[AES-GCM treści]
  Cipher --> Local
  UI --> SAF[SAF import / eksport i Sharesheet]
  UI -. zaplanowane .-> Agents[AgentRun / BudgetGuard / polityki dostępu]
  Agents -. opcjonalne .-> Bridge[JarvisBridge wyłączony]
```

## Moduły i granice

| Moduł | Odpowiedzialność i stan |
|---|---|
| `ui` | Ekrany, zgody, Material 3, polska lokalizacja, układ skalowalny |
| `chat` | Sesja, streaming, stop, ponawianie do ostatniego user, jawne stany i tryb RAM |
| `provider_registry` | Domenowy kontrakt, demo, cztery transporty HTTP, SSE, katalogi i opisy możliwości |
| `local_inference` | Adapter offline, kanał, zarządzanie modelami, CPU/JNI i bezpieczne błędy; odbiór urządzenia otwarty |
| `auth` | SecretStore i Android Keystore; SSO jest interfejsem rozszerzeń w registry |
| `storage` | Baza v3, migracje v1/v2→v3, transakcje, szyfrowanie pól; klasyczny snapshot zwykłych czatów/notatek/zadań |
| `memory` | Lokalny SAF, wznawialny import, wersje i zatwierdzenia, indeks słów HMAC, ograniczony retrieval, checkpointy analiz |
| `costs` | Trwały gate czatu i testowany domenowy BudgetGuard dla przyszłych agentów |
| `agents` | Plany, stany, korekty i role domenowe; brak podłączenia do wykonawcy LLM |
| `tasks` | Obecnie lista SQLite i kolejka odnośników do szkiców; harmonogram zaplanowany |
| `security` | Polityka dostępu fail-closed, backup, role i granice widoczności |
| `rpg` | UI własnych kampanii, zaszyfrowany kanon/stan świata/wiedza gracza, checkpoint i dopisywany audyt/cofanie; pełna mechanika i import Fio zaplanowane |
| `optional_jarvis_bridge` | Kontrakt i wyłączona implementacja; parowanie/transport niewdrożone |
| `orchestrator`, `tools`, `permissions`, `notifications`, `diagnostics` | Interfejsy i plan rozbudowy; brak automatycznych zadań/narzędzi zewnętrznych |

Stan UI: lokalne `StatefulWidget` i `ChangeNotifier` bez globalnego frameworka (ADR 001). Stan trwały wyłącznie przez repozytorium. Nawigacja: systemowy Navigator i 5 dolnych zakładek. Polskie teksty są obecnie w widgetach; pełne ARB/i18n to jawne zadanie następnego etapu.

## Dane

`Conversation(id,title,draft,updated,pinned)` → wiele `Message(id,role,text,provider,model,status,usage)`. `LocalNote(id,title,text,folder,updated)` i `tasks` są lokalne. `operations` przechowuje odnośnik, status, liczbę prób i unikalny klucz deduplikacji. `settings` nigdy nie przechowuje klucza API. `cost_reservations` utrzymuje konserwatywne rezerwy po restarcie.

Migracja v1 tworzy rozmowy, wiadomości, ustawienia i notatki; v2 dodaje kolejkę, zadania i rezerwy. Wersja v3 dodaje wersje i fragmenty pamięci, indeks HMAC, checkpointy analiz, zakresy i dowody kontekstu czatu oraz trwały agregat kampanii. Kod migracji jest w `AppDatabase.createV1/migrateV2/migrateV3`. Włączone są klucze obce i WAL. Import kopii odbywa się jako jedna transakcja dopisująca rekordy z nowymi ID; błąd walidacji wycofuje całość. Zwykły import nigdy nie nadaje roli systemowej.

Po awarii rekordy `streaming/running` stają się `interrupted`. Żadna płatna operacja nie jest automatycznie odtwarzana. Treść częściowa jest utrwalana co około sekundę i na zakończenie. Szkice są serializowane; wysłanie czeka na zakończenie zapisów. Kolejka nie jest obietnicą działania 24/7 i nie uruchamia automatycznie generacji. Brak synchronizacji oznacza brak obecnie aktywnych konfliktów między urządzeniami. Plan: rewizje, optimistic concurrency, jawne konflikty i tombstones przed włączeniem synchronizacji.

## Prywatność i retrieval

W zwykłym czacie wysyłamy wyłącznie wiadomości użytkownika i ukończone odpowiedzi tej sesji; nigdy cały vault, inne czaty i notatki. Porównanie wysyła tylko jeden jawny prompt do wskazanych odbiorców, bez przesyłania odpowiedzi między nimi. Nieznana cena blokuje realne API do konfiguracji. Modele nie wykonują narzędzi. Treści źródeł pozostają danymi. Obrazy Markdown nie są pobierane automatycznie.

Retrieval 0.3.0 używa zatwierdzonych wersji dokumentów z właścicielem i kolekcją. Kontrola SQL poprzedza ranking i odszyfrowanie; walidacja poprzedza eksport i dispatch. Ogólne źródła RPG/GM_SECRET są wyłączone z indeksu. Osobny CampaignStore sprawdza kampanię, rolę i cel, bez indeksowania sekretów. Zwykłe ręczne LocalNote pozostają osobną prostą funkcją, bez automatycznego dołączania do promptu. Semantyczny indeks i integracja agentów są zaplanowane.

## Opcjonalne usługi

Backend ma sens wyłącznie dla webhooków, pracy 24/7, wieloużytkownikowych sekretów, synchronizacji lub JARVIS. Nie ma obowiązkowego backendu. Nie ma przeglądarki z sesją dostawcy, headless automatyzacji jego UI ani serwera Python na telefonie. Parametry dostawcy są niezależne, błąd pojedynczego adaptera nie zatrzymuje pozostałych odpowiedzi porównania.
