# Scalająca

## Aktualne wydanie 0.4.0: pełna szyfrowana kopia

**241/241 Flutter, 36/36 JUnit, 7/7 Android PASS; analiza i APK PASS.**

Pełna kopia obejmuje projekty, źródła i wersje, checkpointy analiz, kampanie RPG z historią lore i sekretami MG, rozmowy zakresowe i dowody kontekstu oraz zwykłe czaty/notatki/zadania. Strumieniowy kontener AES-256-GCM pod osobnym hasłem jest przywracany atomowo, z nowym kluczem urządzenia i zachowaniem identyfikatorów. Kolizja odrzuca całą operację. [Instrukcja backupu](docs/BACKUP_PL.md), [rzeczywiste wyniki testów](docs/TESTS_PL.md).

Urządzenie docelowe: Pixel 9; fizycznego telefonu nie przetestowano. Synchronizacja, embeddingi i potwierdzona jakość długiej kampanii pozostają zaplanowane. Backup nie przenosi niezaimportowanych plików vaultu, modeli GGUF, uprawnień folderów ani kluczy API. [Instrukcja vaultu, pamięci i RPG](docs/OBSIDIAN_PAMIEC_RPG_PL.md). Raporty 0.3.x i 0.2.x poniżej są historią.

Samodzielna aplikacja Flutter dla Androida: czat wielu modeli, lokalna pamięć i zadania. **Rdzeń nie potrzebuje OPPO, JARVIS, Termuxa, serwera ani Obsidiana.** Połączenie sieciowe jest potrzebne wybranym zewnętrznym modelom. Stan prac: wczesna wersja 0.4.0 z natywnym MiniCPM offline; szczegóły i rzeczywiste wyniki w [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) oraz [docs/TESTS_PL.md](docs/TESTS_PL.md).

**0.2.1: 4/4 scenariusze emulatora, 141/141 testów Flutter i 21/21 testów JUnit modułu lokalnych modeli PASS; analiza bez uwag.** Na emulatorze Android 11 x86_64 zaimportowano prawdziwy GGUF przez SAF i czat wygenerował OK bez sieci. JNI zatrzymał streaming po pierwszym tokenie. Nowy APK zawiera ARM64 i x86_64; podpis, manifest oraz wyrównanie 16 KiB są poprawne. Nie przeprowadzono instalacji ani generacji JNI na fizycznym telefonie. Zaczynasz w wyraźnie oznaczonym demo bez konta.

## Uruchomienie

1. Zainstaluj Flutter stable i Android SDK/JDK zgodnie z [instrukcją](docs/SETUP_ANDROID_PL.md).
2. `flutter pub get`
3. `flutter analyze`
4. `flutter test`
5. `flutter run` albo `flutter build apk --debug --target-platform android-arm64,android-x64`.

Bez kluczy wybierz **Demo offline**: to jawna atrapa, nie lokalny LLM. Możesz tworzyć rozmowy, zapisywać szkice, wyszukiwać historię, dodawać notatki i zadania. Zaimportowany Markdown staje się notatką po ręcznym zatwierdzeniu. Eksport tekstu i zaszyfrowana kopia korzystają z systemowego wyboru pliku Androida. Demo i dane lokalne nie wykonują żadnych połączeń z dostawcami.

## Własne API

Ustawienia → Dostawcy AI → klucz BYOK, ID modelu oraz aktualne stawki tego modelu. Klucz trafia do chronionego magazynu Androida, a nie do SQLite/repozytorium. Test pobiera wyłącznie katalog modeli — nie generuje odpowiedzi i nie dowodzi dostępu do wybranego modelu. Włącz płatne API świadomie. Przed każdą generacją potwierdzasz odbiorcę, zakres historii i lokalną rezerwę kosztową. Domyślne limity to 1 USD/dzień i 5 USD/miesiąc (UTC). Rezerwa jest zachowywana także po przerwaniu; nie jest rachunkiem ani gwarancją limitu u dostawcy.

OpenAI, Anthropic, Gemini i xAI mają oddzielne adaptery oficjalnego API. **Kod transportu i testy mock nie są testem prywatnego konta.** Obecnie wspieramy tekst/SSE; media i narzędzia są zaplanowane. Aktualna [macierz integracji](INTEGRATIONS_MATRIX.md) oddziela tożsamość, abonament, kredyty i BYOK, w tym oficjalne Sign in with ChatGPT dla kwalifikujących się aplikacji OSS. SSO nie zostało zaimplementowane. Gemini ma dodatkowe ograniczenia warunków i regionu wymagające oceny przed użyciem.

## MiniCPM — opcjonalne rozszerzenie

Ustawienia → Dostawcy AI → **MiniCPM • własny serwer**. Dodano adapter tekstowy HTTPS zgodny z API llama.cpp, katalog modeli, SSE, anulowanie, kontrolę kosztów i jawny adres odbiorcy w czacie oraz porównaniu. Klucz własnego serwera jest opcjonalny. Zadeklarowany własny serwer z obiema stawkami 0 nie wymaga włączania płatnych API; pozostali dostawcy pozostają zablokowani. Zmiana adresu wymaga nowej deklaracji i nie przenosi starego klucza.

**MiniCPM offline** jest osobną opcją: APK zawiera silnik llama.cpp CPU/JNI. Zaimportuj dobrowolnie oficjalny plik MiniCPM5-1B/2B GGUF w Ustawienia → Dostawcy AI → MiniCPM offline, a następnie wybierz go w czacie. Bez serwera i klucza; brak fallbacku do chmury. Wagi pozostają osobnym plikiem (testowany 1B: około 657 MiB). Import, SHA-256, usuwanie, strumieniowanie i stop są wdrożone. Generację i import uruchomiono na emulatorze; wydajność, język polski, bateria i termika fizycznego telefonu wymagają odbioru. [Dokładna instrukcja i ograniczenia](docs/MINICPM_PL.md).

## Dane i bezpieczeństwo

Treść wiadomości, tytuły, szkice, notatki i tytuły zadań szyfrujemy AES-GCM kluczem chronionym przez Keystore. Metadane SQLite pozostają jawne; nie deklarujemy SQLCipher. Android Auto Backup jest wyłączony. Eksport Markdown jest świadomym jawnym eksportem. Zaszyfrowana kopia używa osobnego hasła, AES-GCM i PBKDF2; nie zawiera kluczy API. Tryb prywatny nowych rozmów utrzymuje je wyłącznie w RAM. Nie ma telemetrii, mikrofonu w tle, Accessibility ani przechwytywania sesji.

Przeczytaj [SECURITY.md](SECURITY.md), [PRIVACY.md](PRIVACY.md), [ARCHITECTURE.md](ARCHITECTURE.md), [ADR](ADR/) i [licencje zależności](docs/LICENSES_PL.md).

## Zakres kolejnych etapów

Porównanie 2–4 różnych dostawców ma jawne potwierdzenie i osobne odpowiedzi w RAM. Silniki polityk agentów, budżetów, dostępu i izolacji RPG istnieją jako testowalne moduły domenowe; ich obecność nie oznacza działającego autonomicznego zespołu w telefonie. Auto, konsensus, semantyczny retrieval, przypomnienia, głos, GPW, WFRP, komunikatory, SSO, synchronizacja i JARVIS mają jawny plan w [roadmapie](docs/ROADMAP_PL.md) i [pełnej macierzy wymagań](docs/REQUIREMENTS_TRACEABILITY_PL.md).

Oryginalna specyfikacja jest zachowana w `SPECYFIKACJA.md`. Żaden wymóg nie jest odrzucany przez sam fakt, że nie należy do bieżącego etapu. Nie wykonano płatnych operacji, logowania kont, wysyłki do osób trzecich ani publikacji aplikacji.
