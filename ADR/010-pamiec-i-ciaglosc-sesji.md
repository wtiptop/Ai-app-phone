# ADR 010: stronicowane przywołanie źródeł i jawna ciągłość sesji

Data: 20.10.2026. Status: przyjęte dla 0.5.0.

## Problem

Pierwsze 64 trafienia według liczby wspólnych słów i daty mogły zostać zdominowane przez wiele fragmentów jednej notatki. Lista analiz kończyła się na 30 wpisach. Zapisane rewizje sesji RPG istniały w bazie i kopii, ale nie miały osobnego, bezpiecznego sposobu przeglądania i wznowienia.

## Decyzja

HMAC indeksuje dotychczasowe dokładne słowa. Stoplista PL/EN dotyczy wyłącznie pytania; nie zmienia indeksu ani przenośnej kopii. Zapytanie wykorzystuje do 12 różnych słów treści. SQL filtruje właściciela, projekt, aktualną rewizję, zatwierdzenie i brak restricted przed rankingiem. Najpierw zwraca najlepszy fragment każdego dokumentu, następnie kolejne rundy; w rundzie porządkuje według pokrycia pytania i stabilnych ID. Odszyfrowuje tylko stronę do 30 fragmentów (UI: 10). Licznik i sortowanie nadal przetwarzają pasujące metadane w SQLite.

W SQLite >=3.25 stosujemy ROW_NUMBER/PARTITION BY. Starszy silnik używa zgodnego zapytania skorelowanego, które może być wolniejsze przy wielu fragmentach jednego dokumentu. Sprawdzamy rzeczywistą wersję silnika, a nie model telefonu. [SQLite opisuje dostępność funkcji okienkowych od 3.25](https://www.sqlite.org/windowfunctions.html#history); [Android dokumentuje różne wersje SQLite i sposób ich sprawdzania](https://developer.android.com/reference/android/database/sqlite/package-summary). Weryfikacja źródeł: 20.10.2026.

Wybranie strony nie wysyła jej całej. Oddzielne retrieveSelected waliduje wszystkie wskazane ID w jednej transakcji, następnie buduje dokładny prefix JSON/UTF-8 w budżecie. Podgląd i późniejszy dispatch sprawdzają aktualność. Zmiana pytania unieważnia wynik, zaznaczenia i numer strony. Strony OFFSET są stabilne przy niezmienionym korpusie; nie są snapshotem równoległego importu. Zmiana projektu czyści lokalny formularz i dobór źródeł.

Punkty analiz mają stronicowany odczyt i dokładny odczyt po ID w projekcie. UI wznawia formularz, a kolejny zapis tworzy osobny ID. Notatka analizy nie staje się zatwierdzonym źródłem modelu. Starsze wersje dokumentu nadal wymagają jawnego podglądu i nie trafiają do bieżącego wyszukiwania.

Archiwum sesji i wersji lore odczytujemy z istniejących rpg_versions. Keyset beforeRevision zapobiega przesuwaniu starszych stron podczas dopisywania sesji. Wszystkie historyczne wersje są dostępne tylko lokalnie dla MG z jawnym opt-in, przed odszyfrowaniem; nawet dzisiejszy jawny wpis mógł kiedyś być sekretem. Archiwum nie zasila indeksu, modelu, recenzenta ani eksportu gracza. UI pokazuje bieżący wpis obok wersji historycznej oraz listę zmienionych pól.

Wznowienie historycznego checkpointu kopiuje tylko notatkę sesji jako nową rewizję active-session, z pochodzeniem w cytacji, expectedRevision i istniejącym zdarzeniem checkpointSaved. Nie cofa świata. Pełny rollback pozostaje oddzielną, potwierdzaną akcją. Nie dodajemy tabel ani nowego enum zdarzeń: baza v3 i szyfrowana kopia v2 zachowują kompatybilność z 0.4.0.

## Konsekwencje i granice

Nie jest to semantyczne wyszukiwanie, stemmer, automatyczna ekstrakcja faktów ani merytoryczny kontroler sprzeczności. Różnice pól ułatwiają kontrolę lore przez MG; nie dowodzą zgodności narracji z podręcznikiem. Model widzi ograniczony wycinek źródeł i bieżący stan sesji, nie cały vault lub całą historię. Test syntetycznego indeksu nie zastępuje odbioru wielogigabajtowego vaultu i długiej kampanii na fizycznym Pixelu 9.
