# ADR 009 — pełna logiczna kopia pod osobnym hasłem

Data: 19.10.2026. Status: przyjęta, implementacja 0.4.0.

Kopia SQLite zawierająca pola pod kluczem starego Keystore nie byłaby przenośna. Przenosimy logiczne rekordy 16 jawnie dopuszczonych tabel, nigdy surowe SQL ani klucze. Eksport odczytuje spójny snapshot jednej transakcji, odszyfrowuje pola w RAM i kieruje rekordy do szyfratora. Duże pola są pobierane pojedynczo; drobne rekordy stronami. Na dysku pośrednim występuje wyłącznie szyfrogram. Natywny kanał SAF ma jawne limity bloków, rozmiaru, uchwytów i jeden oczekujący selektor.

AES-GCM uwierzytelnia nagłówek i łańcuch ramek; typ, długość, kolejność, poprzedni tag, końcowe liczniki oraz EOF są obowiązkowe. Oddzielne losowe sól i prefiks nonce powstają dla każdej kopii. Parametry KDF są stałe i walidowane przed obliczeniami. Utrata hasła oznacza brak odzyskania. Format v2 nie jest zgodny ze starym JSON v1, który ma oddzielną ścieżkę w UI.

Przywracanie zapisuje ponownie zaszyfrowane pola pod kluczem docelowego urządzenia w jednej niezatwierdzonej transakcji. Wymagane są kompletna stopka/EOF i walidacja schematu/relacji/roli, także powiązań niewyrażonych w SQLite FK. Członkostwo importowanych rodziców jest śledzone w TEMP SQL, aby dziecko nie zostało podpięte do istniejących obcych danych. Każdy błąd cofa transakcję. Indeksy HMAC i source_key są obliczane od nowa, wyłącznie dla dopuszczonego bieżącego stanu. Stare wersje i sekrety nie trafiają do ogólnego indeksu.

Zachowujemy identyfikatory zamiast remapowania, ponieważ historyczne dowody zawierają podpisane digestem identyfikatory i snapshoty. Kolizja choć jednego rekordu odrzuca całość. Nie obsługujemy upsert, scalania, częściowego przywrócenia ani pomijania błędów. Dowód kontekstu pozostaje historycznie dokładny, nawet jeśli jego źródło zostało później usunięte. Trwająca odpowiedź staje się przerwana, bez wznowienia żądania.

Pełna kopia zawiera sekrety MG i poufne czaty jako świadoma funkcja właściciela. Nie zmienia blokad zwykłego eksportu, źródeł RPG ani zakresu MG/gracz. Lokalny właściciel odblokowanego urządzenia może odczytać swój backup; nie jest to uwierzytelnianie wielu graczy. Uprawnienia SAF, tokeny, ustawienia dostawców, płatności i GGUF nie są przenoszone. Import plików pozostaje wstrzymany do jawnego ponownego wskazania folderu.

Ograniczenia: 2 GiB/2 mln rekordów/32 MiB JSON rekordu, wolne miejsce na szyfrogram, brak gwarancji natychmiastowego przerwania wadliwego providera. Strumieniowanie nie zastępuje pomiaru RAM na Pixel 9 ani prób dużego rzeczywistego zbioru. Nie ma synchronizacji, retencji, zdalnego harmonogramu ani publikacji.
