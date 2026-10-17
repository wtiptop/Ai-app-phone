# Scalająca

Samodzielna aplikacja Flutter dla Androida: czat wielu modeli, lokalna pamięć i zadania. **Nie potrzebuje OPPO, JARVIS, Termuxa, serwera ani Obsidiana.** Internet jest potrzebny wyłącznie funkcjom chmurowym. Stan prac: wczesna wersja 0.1.0; szczegóły i rzeczywiste wyniki w [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) oraz [docs/TESTS_PL.md](docs/TESTS_PL.md).

**Dostarczono debug APK ARM64 dla Androida 7+.** Pełny build, podpis i manifest zweryfikowano; **83/83 testów Flutter PASS**, analiza bez uwag. Nie przeprowadzono instalacji na prywatnym telefonie ani live API. Zaczynasz w wyraźnie oznaczonym demo bez konta.

## Uruchomienie

1. Zainstaluj Flutter stable i Android SDK/JDK zgodnie z [instrukcją](docs/SETUP_ANDROID_PL.md).
2. `flutter pub get`
3. `flutter analyze`
4. `flutter test`
5. `flutter run` albo `flutter build apk --debug --target-platform android-arm64`.

Bez kluczy wybierz **Demo offline**: to jawna atrapa, nie lokalny LLM. Możesz tworzyć rozmowy, zapisywać szkice, wyszukiwać historię, dodawać notatki i zadania. Zaimportowany Markdown staje się notatką po ręcznym zatwierdzeniu. Eksport tekstu i zaszyfrowana kopia korzystają z systemowego wyboru pliku Androida. Demo i dane lokalne nie wykonują żadnych połączeń z dostawcami.

## Własne API

Ustawienia → Dostawcy AI → klucz BYOK, ID modelu oraz aktualne stawki tego modelu. Klucz trafia do chronionego magazynu Androida, a nie do SQLite/repozytorium. Test pobiera wyłącznie katalog modeli — nie generuje odpowiedzi i nie dowodzi dostępu do wybranego modelu. Włącz płatne API świadomie. Przed każdą generacją potwierdzasz odbiorcę, zakres historii i lokalną rezerwę kosztową. Domyślne limity to 1 USD/dzień i 5 USD/miesiąc (UTC). Rezerwa jest zachowywana także po przerwaniu; nie jest rachunkiem ani gwarancją limitu u dostawcy.

OpenAI, Anthropic, Gemini i xAI mają oddzielne adaptery oficjalnego API. **Kod transportu i testy mock nie są testem prywatnego konta.** Obecnie wspieramy tekst/SSE; media i narzędzia są zaplanowane. Aktualna [macierz integracji](INTEGRATIONS_MATRIX.md) oddziela tożsamość, abonament, kredyty i BYOK, w tym oficjalne Sign in with ChatGPT dla kwalifikujących się aplikacji OSS. SSO nie zostało zaimplementowane. Gemini ma dodatkowe ograniczenia warunków i regionu wymagające oceny przed użyciem.

## Dane i bezpieczeństwo

Treść wiadomości, tytuły, szkice, notatki i tytuły zadań szyfrujemy AES-GCM kluczem chronionym przez Keystore. Metadane SQLite pozostają jawne; nie deklarujemy SQLCipher. Android Auto Backup jest wyłączony. Eksport Markdown jest świadomym jawnym eksportem. Zaszyfrowana kopia używa osobnego hasła, AES-GCM i PBKDF2; nie zawiera kluczy API. Tryb prywatny nowych rozmów utrzymuje je wyłącznie w RAM. Nie ma telemetrii, mikrofonu w tle, Accessibility ani przechwytywania sesji.

Przeczytaj [SECURITY.md](SECURITY.md), [PRIVACY.md](PRIVACY.md), [ARCHITECTURE.md](ARCHITECTURE.md), [ADR](ADR/) i [licencje zależności](docs/LICENSES_PL.md).

## Zakres kolejnych etapów

Porównanie 2–4 różnych dostawców ma jawne potwierdzenie i osobne odpowiedzi w RAM. Silniki polityk agentów, budżetów, dostępu i izolacji RPG istnieją jako testowalne moduły domenowe; ich obecność nie oznacza działającego autonomicznego zespołu w telefonie. Auto, konsensus, retrieval, przypomnienia, głos, GPW, WFRP, komunikatory, SSO, synchronizacja i JARVIS mają jawny plan w [roadmapie](docs/ROADMAP_PL.md) i [pełnej macierzy wymagań](docs/REQUIREMENTS_TRACEABILITY_PL.md).

Oryginalna specyfikacja jest zachowana w `SPECYFIKACJA.md`. Żaden wymóg nie jest odrzucany przez sam fakt, że nie należy do bieżącego etapu. Nie wykonano płatnych operacji, logowania kont, wysyłki do osób trzecich ani publikacji aplikacji.
