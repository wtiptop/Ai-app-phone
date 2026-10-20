# ADR 011 — zachowawczy tryb MiniCPM dla źródeł i lore

Data: 20.10.2026. Status: przyjęta; odbiór i granice w docs/TESTS_PL.md.

## Diagnoza

W 0.5.0 zatwierdzony pakiet zawierał COMPASS, a odpowiedź brzmiała COMASS. Samo polecenie kopiowania verbatim ani oczekiwanie na odświeżenie UI nie usunęły błędu. Diagnostyka JNI na tym samym oficjalnym GGUF i emulatorze, przed Dart/UI, dała kolejno COMASS, COMPASS, COMPASS. Dla błędu surowe fragmenty miały bajty COM (`Q09N`) i ASS (`QVNT`), dla poprawnej odpowiedzi COMP (`Q09NUA==`) i ASS. Litera nie zginęła w warstwie wyświetlania. Tokenizer hosta zachował COMPASS w roundtripie jako tokeny 67026 + 12229; COMASS ma odrębny pierwszy token 19855. Również polski tekst przeszedł roundtrip.

Wniosek z tych prób: aktywny losowy profil dekodowania potrafił wybrać alternatywną pisownię. Nie jest to diagnoza wszystkich możliwych błędów modelu ani dowód, że kwantyzacja lub sprzęt nie wpływają na jakość. Zachowujemy surowy wynik wcześniejszej porażki.

## Decyzja

Dla MiniCPM z jawnym zatwierdzonym załącznikiem projektu/RPG dodajemy flagę sourceGrounded. Sesja wylicza ją z dostawcy i załącznika, obejmuje ją digestem razem z całym promptem, przelicza digest przed dispatch i ponownie waliduje źródła. Adapter przekazuje bool przez kanał, Kotlin i JNI do C++. Model wybiera token o największym logitcie przez llama_sampler_init_greedy zamiast top-p/temperatury/losowania. Zwykły czat zachowuje dotychczasowe parametry. Nie stosujemy podmiany COMASS→COMPASS, słownika wyjątków, korekty wygenerowanego tekstu ani odpowiedzi z atrapy.

Własna stała instrukcja aplikacji jest osobną wiadomością systemową: źródła to dane, nazwy/liczby mają pozostać, brak danych i konflikty wymagają oznaczenia, a propozycje oddziela się od kanonu. Niezaufane źródła nadal mają rolę user i istniejące ograniczenia specjalnych tokenów. Instrukcja jest widoczna w dokładnym podglądzie. Budżet uwzględnia jej rzeczywiste bajty. Zgoda opisuje zachowawczy tryb; źródła, role i zakres nadal wymagają osobnego wyboru/zgody.

Nie zmieniamy bazy v3, formatu backupu v2 ani struktury receipt. Historyczny digest jest dowodem starego pakietu, nie nowym pozwoleniem. Nie przenosimy dawnych sekretów do gracza, indeksu ani źródeł systemowych. Diagnostyka plaintextu działa tylko w androidTest na własnym AVD i sprawdzonej syntetycznej fixture; produkcyjny silnik nadal nie loguje promptów i odpowiedzi.

## Weryfikacja i granice

Test kanału sprawdza dokładne złożenie COMP+ASS oraz UTF-8 rozciętego między bajtami. Testy sesji/adaptera sprawdzają źródła, flagę, hash, zwykły czat i cofnięcie zgody. Android porównuje surowe generacje z tym samym wejściem bez nowej instrukcji systemowej, by oddzielić zmianę samplera od promptu. Osobno UI sprawdza trzy odpowiedzi oraz dowód źródeł. Wyniki pozostają w raporcie, także gdy test nie przechodzi.

Greedy usuwa losowanie alternatyw, ale nie gwarantuje prawdziwości. Może deterministycznie wybrać błędny token; nie jest automatyczną kontrolą lore. Narracja z zatwierdzonymi źródłami może być mniej różnorodna. Nie potwierdzamy jakości całej polskiej kampanii, profilu 2B ani fizycznego Pixela 9. MG nadal zatwierdza kanon, a odpowiedź modelu nie zapisuje faktów automatycznie.

Źródła techniczne sprawdzone 20.10.2026: [OpenBMB — domyślne parametry generacji](https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/llama_cpp.md), [przypięty publiczny interfejs llama.cpp](https://github.com/ggml-org/llama.cpp/blob/5aeac37a35b44fde4bdffaec9159f2fcb253b622/include/llama.h). Tryb zachowawczy jest decyzją aplikacji dla pracy ze źródłami; nie deklarujemy go jako zalecenia wydawcy dla wszystkich zastosowań.
