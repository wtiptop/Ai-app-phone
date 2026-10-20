# Dziennik zmian

## 0.5.1 — 2026-10-20

- Diagnoza surowego JNI potwierdziła losowy wybór COM+ASS zamiast COMP+ASS; poprawne źródło i tokenizer nie usuwały litery.
- MiniCPM z zatwierdzonym pakietem wybiera greedy; osobna instrukcja systemowa zachowania nazw/liczb, tryb w digest/zgodzie/adapterze/JNI i uwzględniony budżet. Bez podmiany słów; zwykły czat zachowuje profil.
- 270 Flutter, 36 JUnit i 8 Android PASS; JNI 3×COMPASS i LANTERN/RAVEN, UI 3×COMPASS oraz receipt. Fizyczny Pixel 9 i długa kampania PL nadal nieprzetestowane. Baza v3 / backup v2 bez zmian.

## 0.5.0 — 2026-10-20

- Stronicowane wyszukiwanie z dokładnym licznikiem, filtrowaniem zakresu i rundami różnych dokumentów; stoplista PL/EN pytań. SQLite >=3.25 używa funkcji okienkowych, starsze wersje zachowują zgodny fallback.
- Oddzielna selekcja źródeł sprawdza wszystkie ID przed przycięciem, zachowuje dokładny budżet JSON/UTF-8 i cytowania linii. Zmiana pytania unieważnia poprzedni wynik i wybór. Poprawiono skok przewijania oraz semantykę kart z polami i przyciskami.
- Starsze strony projektów i punktów analiz, dokładny odczyt checkpointu, powrót do formularza i nowe wyszukiwanie źródeł do kolejnego kroku. Nowy zapis w UI zachowuje poprzedni punkt jako osobny rekord.
- Prywatne archiwum sesji i wersji lore MG z kursorem rewizji i porównaniem pól z bieżącym wpisem. Wznowienie checkpointu tworzy nową rewizję samej notatki; nie cofa dzisiejszego świata i nie usuwa historii.
- Kontrola roli/opt-in/purpose przed odszyfrowaniem historii, brak historycznych sekretów w indeksie i kontekście gracza, walidacja pustych cytacji po trim. Baza v3 i pełny backup v2 pozostają zgodne.
- Nowe testy dużego syntetycznego indeksu, wielosesyjnej trwałości, izolacji, restore i UI; test Androida dla późnego faktu oraz jawnego wznowienia kampanii. Wyniki końcowe i ograniczenia: docs/TESTS_PL.md.
- Brak deklaracji odbioru fizycznego Pixela 9, rzeczywistego wielogigabajtowego vaultu, długiej narracji PL, embeddingów/grafu, automatycznego kontrolera sprzeczności i synchronizacji.

## 0.4.0 — 2026-10-19

- Pełna szyfrowana kopia projektów i kampanii RPG: źródła i wszystkie wersje, checkpointy analiz/sesji, historia lore/zdarzeń, sekrety MG, rozmowy zakresowe i dowody kontekstu oraz zwykłe dane właściciela.
- Strumieniowy format v2 AES-256-GCM/PBKDF2-SHA256, uwierzytelniony łańcuch ramek i obowiązkowa stopka/EOF; prywatny staging wyłącznie szyfrogramu oraz systemowy SAF. Limit 2 GiB/2 mln rekordów/32 MiB rekordu, jawny błąd bez pomijania.
- Atomowy restore 16 tabel z zachowaniem ID, walidacją relacji i ról, ponownym szyfrowaniem pod kluczem celu i odbudową HMAC. Każda kolizja wycofuje całość. Bez przywracania kluczy API, płatności, GGUF i uprawnień folderów.
- Poprawione granice dostępności wierszy źródeł oraz przepełnienia formularza i stronicowania RPG na małym ekranie; osobny test zapisu sekretu MG.
- Ponowne jawne połączenie folderu do istniejącego projektu po przywróceniu; import wstrzymany i reset kursora. Stary format v1 zachowany osobno.
- Wyniki testów i nowego APK: aktualna sekcja docs/TESTS_PL.md. Instrukcja: docs/BACKUP_PL.md; decyzje: ADR 009. Synchronizacja i fizyczny Pixel 9 pozostają do osobnego odbioru.

## 0.3.0 — 2026-10-19

- Lokalny vault Markdown przez SAF, odczyt domyślny, osobny świadomy eksport nowych plików, stronicowany import i wznawianie po każdym pliku.
- Szyfrowane wersje/fragmenty w SQLite v3, zatwierdzanie i cofanie źródeł, indeks słów HMAC, ograniczony retrieval oraz trwałe ręczne punkty analiz.
- UI kampanii RPG: kanon/źródła/edycja, encje świata, wiedza gracza, checkpoint sesji, dopisywany audyt i rollback jako nowa rewizja.
- Dokładny podgląd ograniczonego kontekstu, digest jednorazowej zgody, receipt przy odpowiedzi, osobne zakresy projektów i ról. Poprawki FK receipt i wyścigu historii. Starsze wiadomości w stronicowanym archiwum.
- Docelowy Pixel 9, domyślny kontekst 4096 (zachowane istniejące ustawienia); bez potwierdzenia wydajności fizycznego telefonu. Synchronizacja, pełny backup nowych danych, embeddingi i pełna gra RPG zaplanowane.
- 193 Flutter, 27 JUnit i 5 testów emulatora PASS; rzeczywisty model offline i syntetyczny vault. Nowy debug APK ARM64+x86_64, bez wag i nowych zależności.

## 0.2.1 — 2026-10-18

- Jeden APK ARM64+x86_64; emulator używa natywnego x86_64 zamiast zawodnej translacji ARM. W ggml dla Androida x86_64 wyłączono instrukcje AVX/FMA/F16C/BMI2 niedostępne w testowym emulatorze.
- Osobna semantyka i ogłaszanie zmian statusu odpowiedzi: status, koszt i tokeny nie łączą się już z podpowiedzią zaznaczalnego tekstu. Dodano asercję dostępności do testu czatu Flutter.
- Standardowy AndroidJUnitRunner/UIAutomator i skrypt odtwarzający import GGUF przez SAF, prawdziwy czat offline, anulowanie po tokenie JNI, Stop w UI, następną odpowiedź i zatrzymanie w tle.
- Usunięto nieużywane Flutter integration_test i konflikt starego runnera Androida. Notices zaktualizowano dla 100 pakietów; przypięte źródła silnika bez zmian.
- Rzeczywiste wyniki oraz granice odbioru emulatora: docs/TESTS_PL.md. Fizyczny telefon ARM64, jakość polskiego, bateria, termika, 2B, multimodalność i pozostałe otwarte wymagania pozostają do realizacji/odbioru.

## 0.2.0 — 2026-10-18

- Prawdziwy silnik llama.cpp/ggml CPU/JNI w APK ARM64; MiniCPM5-1B/2B jako osobny dostawca offline w czacie i porównaniu.
- Dobrowolny import pojedynczego GGUF przez SAF, SHA-256, walidacja struktury, prywatny magazyn, deduplikacja, anulowanie i usuwanie kopii.
- Przypięte zaufane szablony, bez wykonywania szablonu z wag; brak sieci/fallbacku w adapterze, klucza i opłat API dla lokalnego modelu.
- Limity CPU/kontekstu/czasu, bramka RAM/termiki i anulowanie po przejściu w tło; pełny odbiór Androida pozostaje otwarty.
- 141/141 Flutter oraz 21/21 JUnit PASS; rzeczywista generacja i anulowanie rdzenia C++ na Windows. Build/podpis/manifest APK PASS. Wagi 1B pobrane osobno po zgodzie, poza APK i paczką źródeł.
- Zachowane licencje natywne, pełny hash spisu 1818 plików upstream, ADR 006 i instrukcja. Brak benchmarku telefonu, potwierdzonej jakości PL, pełnych wag 2B, GPU/NPU oraz MiniCPM-V/audio/tools.

## 0.1.1 — 2026-10-18

- Opcjonalny MiniCPM: własny serwer HTTPS, katalog, tekst/SSE, usage, anulowanie i bezpieczne błędy; czat oraz porównanie.
- Osobny adres odbiorcy w zgodzie; opcjonalny klucz Keystore nie jest przenoszony przy zmianie adresu bez nowego klucza.
- Deklarowany własny serwer bez opłat za API i dwie stawki 0; zachowana blokada płatnych API i atomowe rezerwy dla pozostałych wywołań.
- Port CostStore i osobne testy Dart: 73/73 PASS, w tym prawdziwe transakcje SQLite. Dwa nowe scenariusze widgetów wymagają uruchomienia runnera Flutter.
- Analiza bez uwag; kompilacja Flutter bundle PASS. Pełny runner Flutter i APK zablokowane przez localhost/Gradle w aktualnym środowisku. Brak APK 0.1.1.
- Oficjalne źródła MiniCPM/GGUF/licencji, instrukcja i ADR 005. Inferencja wbudowana Android, wagi i generacja na żywo pozostają niewykonane/zaplanowane.

## 0.1.0 — 2026-10-17

- Repozytorium Flutter Android i pełna macierz specyfikacji.
- Polski UI: czat, pamięć, zadania, agenci i ustawienia; demo bez konta.
- Lokalna baza v2, szyfrowanie treści, serializowane szkice i odzyskiwanie przerwanych odpowiedzi.
- Cztery adaptery oficjalnych API, parser SSE, anulowanie, katalogi i bezpieczne błędy.
- Jawne zgody, konfiguracja Keystore, lokalne rezerwy kosztowe i eksperymentalne porównanie.
- Systemowe pliki/udostępnianie Androida, przenośne zaszyfrowane kopie.
- Testowalne polityki agentów, izolacji kampanii i sekretów MG; bez deklaracji ukończonego silnika gry ani automatycznych agentów.
- Rzeczywiste wyniki w docs/TESTS_PL.md. Płatne API, prywatne konta i publikacja nie były uruchamiane.
- Finalny debug APK ARM64: build exit 0, podpis v2 i manifest zweryfikowane; 83/83 testów hosta, analiza bez uwag. Android 7+; test urządzenia pozostaje do odbioru.
