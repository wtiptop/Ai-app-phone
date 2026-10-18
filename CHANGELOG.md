# Dziennik zmian

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
