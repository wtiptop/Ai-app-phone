# ADR 008: lokalny vault, ograniczony kontekst i wersjonowany stan kampanii

Data: 19.10.2026. Status: przyjęte dla wersji 0.3.0, z ograniczeniami odbioru urządzenia.

Użytkownik wybrał lokalny vault teraz, możliwą synchronizację w przyszłości i Google Pixel 9 jako urządzenie docelowe. Wielkość pamięci trwałej nie może oznaczać ładowania całej wiedzy do RAM lub okna MiniCPM.

Używamy ACTION_OPEN_DOCUMENT_TREE i utrwalanych uprawnień lokalnego providera. Zewnętrzne pliki są domyślnie tylko czytane. Stronicowany importer zapisuje pozycję po każdym pliku; prywatne zaszyfrowane wersje i fragmenty są oddzielone od oryginałów. Zatwierdzenie dotyczy konkretnej rewizji. Indeks słów HMAC filtruje właściciela, kolekcję, zgodę i bieżącą wersję przed rankingiem i odszyfrowaniem.

Wybrany pakiet jest zamrażany przed zgodą. Digest obejmuje role, tekst, odbiorcę, model, zakres i limit odpowiedzi; jest ponownie sprawdzany przy dispatch. Dokładne źródła są utrwalane przy odpowiedzi. Aktualizacja messages musi używać UPDATE, ponieważ REPLACE usuwałby receipt przez FK CASCADE. Baza v3 migruje dane v1 i v2 bez kasowania.

Kampania jest osobnym agregatem z właścicielem, edycją, rewizją, zatwierdzanymi wpisami, stanem sesji i dopisywanym audytem. Cofanie tworzy nową rewizję. Sekretów nie indeksujemy. Pakiet gracza nie zawiera encji świata, sekretów i checkpointu MG. Zakres rozmowy zawiera kampanię i rolę; nowy pakiet otwiera nowy czat. Szybkie przełączanie historii używa ticketu i atomowego przypisania stanu, żeby opóźniony odczyt MG nie nadpisał widoku gracza.

Koszty: przechowujemy stare wersje, potrzebujemy retencji i pełnej kopii. Obecny prosty backup wyklucza czaty zakresowe, a nowa pamięć nie jest jeszcze przenośna. Wyszukiwanie dokładnych słów jest ograniczone semantycznie. SAFE tree nie daje uniwersalnej gwarancji symlinków. Nie ma automatycznego sync, obserwatora, ciągłej generacji w tle, pełnej mechaniki RPG ani potwierdzonej jakości wielosesyjnej narracji. Szczegóły i instrukcja: `docs/OBSIDIAN_PAMIEC_RPG_PL.md`.
