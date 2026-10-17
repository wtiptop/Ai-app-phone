# Dziennik zmian

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
