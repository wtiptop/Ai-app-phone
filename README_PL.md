# Scalająca

<!-- release-0.5.3:start -->
## Wydanie 0.5.3+10 — MiniCPM 2B offline

Scalająca działa samodzielnie na Androidzie, bez serwera i OPPO. MiniCPM5-2B Q4_K_M został zaimportowany przez systemowy selektor i uruchomiony bez internetu. Wagi importujesz osobno; nie są dołączone do APK. Instalacja: [instrukcja Androida](docs/SETUP_ANDROID_PL.md).

Naprawiono rozpoznawanie oficjalnych metadanych `MiniCPM5 2.6B`, ponowny wybór istniejącego vaultu tylko do odczytu przy limicie ośmiu uchwytów oraz format źródeł kampanii. Bieżący kanon wyprzedza dawną notatkę sesji; tytuł i treść wpisu są rozdzielone. Historia i obie sprzeczne wersje pozostają zachowane. Przyciski hashów 1B/2B tylko wypełniają pole; import jest osobną czynnością.

Rzeczywiste wyniki:

- **285/285 Flutter, 39/39 JUnit, 0 pominiętych.** Analiza bez uwag.
- **8/8 różnych scenariuszy Androida PASS**, dodatkowo ponowiony mocniejszy test: trzy różne ID i trzy nowe odpowiedzi COMPASS. Surowe JNI: 5/5 dokładnych wartości. Import, Stop, następna odpowiedź, tło, lokalny vault i historia kampanii przeszły na emulatorze.
- **24 symulowane sesje, 37/37 ukończonych generacji**, dwa restarty, 25 checkpointów i 37 zapisów źródeł. Fakty oraz retrieval: **24/24**. Poprawny powrót BURSZTYN i odpowiedź ZAMKNIĘTA mimo dawnej notatki OTWARTA.
- Ręczny i niezależny przegląd: **1/5 narracji**, **0 zaobserwowanych sekretów/parafraz w 11 próbach gracza**. Próba 31 nadal daje bezsensowną odpowiedź. Pełna jakość MG i zachowania wobec złośliwych instrukcji pozostają niezaliczone.

Pierwszy pełny 2B miał już 24/24 faktów, lecz 0/5 narracji oraz błędy powrotu do kampanii i starego checkpointu. Historyczny 1B miał 19/24 i 0/5. W finale zmieniono instrukcję, format i budżet źródeł (1152→1128 znaków), więc porównanie nie dotyczy wyłącznie wielkości modelu. Wszystkie wcześniejsze wyniki i porażki zachowano w [raporcie testów](docs/TESTS_PL.md), wraz z [niezależną oceną](docs/test-results/rpg-0.5.3/independent-review.json).

APK zawiera ARM64 i x86_64; podpis oraz wyrównanie 16 KiB są zweryfikowane. Fizyczny **Pixel 9 nie był testowany**. Największa z 136 próbek pamięci procesu na emulatorze to około 1,93 GiB PSS; nie jest to pomiar szczytu ani wyniku telefonu. Wielodniowa gra, bateria/termika, korpus GB, automatyczny kontroler lore i pełna mechanika WFRP pozostają do realizacji lub odbioru.

Baza v3, szyfrowana kopia v2 i receipts v1 zachowują zgodność. Aktualizacja nie wymaga odinstalowania ani ponownego importu zachowanego 1B. [Modele offline](docs/MINICPM_PL.md), [odtworzenie kampanii](docs/RPG_KAMPANIA_TEST_PL.md), [stan implementacji](IMPLEMENTATION_STATUS.md), [ADR 013](ADR/013-minicpm5-2b-i-porownanie-offline.md). Starsze sekcje poniżej opisują historię.
<!-- release-0.5.3:end -->

## Poprzednie wydanie 0.5.2: próba polskiej kampanii offline

**284/284 Flutter, 36/36 JUnit i 8/8 regresji Androida PASS; analiza i główny APK ARM64+x86_64 PASS.** Osobna próba MiniCPM: 24 symulowane sesje, 37 prawdziwych generacji, dwa restarty procesu. Źródła zawierały 24/24 potrzebnych faktów, a model odpowiedział dokładnie na **19/24**. Zmiany bramy i właściciela klucza były odtwarzane po zapisach/restartach. Nie zaobserwowano ujawnienia sekretów w 11 próbach gracza. **0/5 narracji spełniło pełne kryterium spójnej, dwuzdaniowej polskiej sceny.** Mały model nadal bywa niespójny lub zwraca metadane. Nie deklarujemy gotowego, niezawodnego MG.

Poprawiono wybór dawnych faktów, pomijanie ręcznie wskazanego wpisu i hierarchię pakietu. MG może odłączyć notatkę sesji od pytania bez kasowania jej z pamięci. MiniCPM dostaje źródła i pytanie w jednej turze; pełna kopia v2 i baza v3 zachowują zgodność. Dla pakietów kampanii wymagane jest ustawienie kontekstu 4096; lokalna edycja działa także przy mniejszym oknie.

[Rzeczywiste wyniki i porażki](docs/TESTS_PL.md), [instrukcja pamięci](docs/PAMIEC_CIAGLOSC_PL.md), [odtworzenie testu](docs/RPG_KAMPANIA_TEST_PL.md), [instalacja](docs/SETUP_ANDROID_PL.md). Fizyczny Pixel 9, pełne 2B, bateria/termika, szczyt RAM i GB vaultu nadal wymagają odbioru. Starsze sekcje poniżej opisują historię.

## Poprzednie wydanie 0.5.1: wierniejsze odpowiedzi ze źródeł

**270/270 Flutter, 36/36 JUnit i 8/8 scenariuszy Androida PASS; analiza i APK PASS.** Surowa diagnostyka JNI potwierdziła wybór COM+ASS przed UI. MiniCPM z zatwierdzonymi źródłami używa teraz zachowawczego wyboru tokenów oraz osobnej instrukcji kopiowania nazw i liczb. Zwykły czat zachowuje dotychczasowy profil. Nie ma podmiany pojedynczych słów ani atrapy odpowiedzi.

Na emulatorze: trzy dokładne COMPASS w JNI, LANTERN/RAVEN oraz trzy odpowiedzi COMPASS w rzeczywistym czacie z zachowanym receipt. To poprawa sprawdzonego przypadku, nie gwarancja prawdziwości całej narracji. Fizyczny Pixel 9, długa polska kampania, pełne 2B i automatyczny kontroler lore nadal wymagają odbioru. Źródła, backup i historia kampanii zachowują dotychczasowe zabezpieczenia.

[Diagnoza i wyniki](docs/TESTS_PL.md), [instrukcja MiniCPM](docs/MINICPM_PL.md), [instalacja APK](docs/SETUP_ANDROID_PL.md), decyzja ADR 011. Starsze wydania poniżej są historią.

## Poprzednie wydanie 0.5.0: powrót do danych i ciągłość sesji

**266/266 Flutter, 36/36 JUnit PASS; Android 6/7 PASS, 1 FAIL. Analiza i budowanie APK PASS.** Test późnego faktu odnalazł poprawne COMPASS, lecz MiniCPM zwrócił COMASS również przy poleceniu kopiowania verbatim. Wierność generacji pozostaje ograniczona; szczegóły i dowody w docs/TESTS_PL.md.

Stronicowane wyszukiwanie przegląda zatwierdzone bieżące źródła w projekcie, rozdziela trafienia między dokumenty i odszyfrowuje tylko stronę. Model dostaje dokładnie widoczny, ograniczony pakiet wybranych fragmentów. Starsze punkty analiz wczytują formularz; nowy zapis zachowuje poprzedni punkt.

MG ma prywatną historię stanów sesji i wersji lore oraz porównanie z dzisiejszym wpisem. Wznowienie starej notatki tworzy nową rewizję z zachowaniem historii i bieżącego kanonu świata. Archiwum nie trafia do gracza, indeksu ani automatycznie do modeli. Pełna szyfrowana kopia źródeł, wersji, checkpointów i sekretów nadal działa w zgodnym formacie v2.

[Instrukcja pamięci i ciągłości](docs/PAMIEC_CIAGLOSC_PL.md), [backup i przywracanie](docs/BACKUP_PL.md), [rzeczywiste wyniki testów](docs/TESTS_PL.md), [instalacja na Androidzie](docs/SETUP_ANDROID_PL.md).

Urządzenie docelowe: Pixel 9, APK z ARM64 i x86_64. Fizycznego telefonu nie przetestowano. Synchronizacja, embeddingi/graf, automatyczny kontroler sprzeczności i potwierdzona jakość długiej polskiej kampanii pozostają zaplanowane. Ranking dokładnych słów i podgląd różnic wersji nie zapewniają samodzielnie bezbłędnej narracji. Backup nie przenosi niezaimportowanych oryginalnych plików vaultu, wag GGUF, uprawnień folderów ani kluczy API. Starsze raporty poniżej są historią.

Samodzielna aplikacja Flutter dla Androida: czat wielu modeli, lokalna pamięć i zadania. **Rdzeń nie potrzebuje OPPO, JARVIS, Termuxa, serwera ani Obsidiana.** Połączenie sieciowe jest potrzebne wybranym zewnętrznym modelom. Stan prac: wczesna wersja 0.5.3 z natywnym MiniCPM offline; szczegóły i rzeczywiste wyniki w [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) oraz [docs/TESTS_PL.md](docs/TESTS_PL.md).

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
