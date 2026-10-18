# Prywatność Scalającej

Aktualizacja 0.3.0: lokalny vault otrzymuje osobne uprawnienie SAF tylko do odczytu. Prywatna baza przechowuje zaszyfrowane kopie i wersje treści, ścieżki, punkty analiz oraz wpisy kampanii. Indeks słów używa HMAC; identyfikatory/rozmiary/rewizje i część metadanych są jawne. Wyłącznie wybrany pakiet i ograniczona historia trafiają do wskazanego modelu po dokładnym podglądzie; przy odpowiedzi pozostaje zaszyfrowany snapshot tych źródeł. Cofnięcie zgody źródła blokuje nowe wysyłki, nie usuwa wcześniej zapisanych odpowiedzi i ich dowodów. Lokalny tryb MG/gracz jest filtrem właściciela, bez uwierzytelniania osobnych osób. Stara kopia hasłem wyklucza czaty zakresowe i nie obejmuje nowych projektów ani kampanii. Eksport do vaultu jest osobną świadomą akcją zapisu nowego pliku. Nie ma Obsidian Sync ani kont. Dokładny zakres: `docs/OBSIDIAN_PAMIEC_RPG_PL.md`.

Aktualizacja 0.2.0: **MiniCPM offline** przetwarza wybrany kontekst w pamięci procesu na telefonie, bez serwera, klucza API, telemetrii i automatycznego fallbacku. Import GGUF przez SAF tworzy prywatną kopię publicznych wag, nazwę/profil/rozmiar/hash; te zasoby nie są objęte eksportem historii. Usunięcie kopii w aplikacji pozostawia oryginał z selektora. Wskazanie pliku u chmurowego dostawcy SAF może wymagać jego sieci do samego importu; do późniejszej inferencji nie jest potrzebna. Rozmowy lokalnego modelu korzystają ze zwykłego szyfrowanego zapisu lub prywatnej sesji RAM według wyboru użytkownika. Wagi nie są szyfrowane szyfrem rozmów; tekst promptu i odpowiedzi pozostaje w RAM podczas pracy. Brak gwarancji bezpiecznego wymazania RAM. Osobna opcja serwerowa nadal wysyła dane do jawnego odbiorcy. Test hosta i build nie zastępują odbioru fizycznego urządzenia.

Aktualizacja 0.1.1: po wybraniu opcji MiniCPM • własny serwer treść wskazanej rozmowy trafia do własnego serwera HTTPS pokazanego przed wysłaniem. Nie zakładamy, że ten serwer jest prywatny, lokalny lub bez logów: odpowiada za to właściciel. Adres serwera, model, stawki i deklaracja opłat są jawnymi ustawieniami SQLite; opcjonalny klucz pozostaje w Keystore i nie jest eksportowany. Nie ma automatycznego połączenia, pobierania wag, fallbacks do chmury ani telemetrii. Od 0.2.0 inferencja w APK jest osobnym trybem offline opisanym powyżej.

Stan: 17.10.2026. Scalająca przechowuje dane na telefonie i działa bez konta, serwera JARVIS, OPPO i Obsidiana. Dostęp do chmurowego AI wymaga internetu i dobrowolnej konfiguracji dostawcy.

## Jakie dane są przechowywane

Rozmowy, szkice, notatki, zadania, metadane dostawcy/modelu, statusy operacji i lokalne rezerwy kosztów są zapisywane lokalnie w SQLite. Treści rozmów i notatek, ich tytuły, szkice oraz tytuły zadań są szyfrowane polami AES-256-GCM. Część metadanych bazy pozostaje jawna; nie jest to pełne szyfrowanie SQLite ani SQLCipher. Klucz treści i klucze API są przechowywane osobno przez bezpieczny magazyn z Android Keystore.

Tryb prywatnej rozmowy utrzymuje jej treść w pamięci procesu i pomija zwykły zapis rozmowy oraz szkicu do bazy. Dla płatnych żądań pozostaje trwała rezerwa kwoty, dostawcy i czasu, potrzebna do egzekwowania budżetu; nie zawiera treści rozmowy. Tryb prywatny nie oznacza anonimowości wobec dostawcy chmurowego. Kopiowanie, wykonanie zrzutu ekranu, klawiatura systemowa, udostępnienie przez użytkownika i zachowanie systemu operacyjnego pozostają osobnymi kanałami ujawnienia. Nie ma wdrożonej gwarancji wymazywania każdej kopii tekstu z pamięci RAM.

## Kiedy dane opuszczają urządzenie

Demo nie wysyła treści do AI. Przy użyciu skonfigurowanego API wybrany dostawca otrzymuje treść wysyłanej rozmowy i wymagane dane protokołu. Dostawca może przetwarzać dane poza Polską/UE na warunkach swojego konta i usługi. Retencję, lokalizację przetwarzania i wykorzystanie danych należy sprawdzić w aktualnych warunkach dostawcy. Scalająca nie zmienia tych warunków i nie zamienia subskrypcji aplikacji konsumenckiej w dostęp API.

Zmiana modelu w istniejącej rozmowie może wysłać jej dotychczasowy wybrany kontekst nowemu dostawcy. Porównanie modeli wymaga jawnej zgody na wskazanych odbiorców. Nie ma automatycznej synchronizacji całego vaultu, importu kont prywatnych ani połączenia z OPPO. Wyszukiwanie internetu, komunikatory, chmury dyskowe, kalendarz i poczta wymagają osobnych przyszłych integracji i zgód.

Ręczny eksport Markdown/JSON i systemowe udostępnienie tekstu przekazują czytelną treść do wybranego miejsca lub aplikacji. Do prywatnej kopii danych należy używać kopii szyfrowanej hasłem. Klucze API nie są częścią przenośnego snapshotu. Hasło backupu nie jest zapisywane; jego utrata oznacza brak możliwości odszyfrowania kopii. Odbiorca pliku i aplikacja docelowa mogą zachować własną kopię.

## Kontrola i usuwanie

Użytkownik wybiera dostawcę i model, zatrzymuje odpowiedź, zarządza lokalnymi danymi oraz usuwa klucz przez ustawienia. Anulowanie żądania zatrzymuje odbiór i próbę połączenia w aplikacji, lecz nie cofa danych już odebranych przez dostawcę ani ewentualnego naliczenia. Usunięcie danych z telefonu nie usuwa wcześniej wykonanych eksportów, kopii ani danych przetwarzanych przez dostawcę. Usunięcie w SQLite nie stanowi certyfikowanego fizycznego nadpisania nośnika.

Lokalne limity kosztów dotyczą tej aplikacji. Nie blokują korzystania z tego samego klucza przez inne programy. Własny klucz API w telefonie wymaga zaufania do urządzenia; po utracie telefonu należy odwołać klucz u dostawcy.

## Pamięć, agentowość i RPG

Wdrożony komponent `MemoryAccessPolicy` oddziela właścicieli, projekty, kampanie, odbiorców i zatwierdzenia. Domyślnie nie wysyła danych osobistych do recenzenta. `GM_SECRET` nie trafia do graczy, recenzentów, zwykłego indeksu ani zwykłego eksportu. Są to reguły komponentu domenowego; pełne interfejsy pamięci współdzielonej, wielu użytkowników i trwałego RPG są jeszcze zaplanowane. Zwykła notatka nie otrzymuje automatycznie ochrony sekretu MG na podstawie jej treści.

Agent nie działa jako stale uruchomiony proces. Obecny automat stanów wymaga planu i zatwierdzonego zakresu, ma limit korekt i można go zatrzymać. Nie ma aktywnego mechanizmu automatycznego wysyłania wiadomości, zakupów, wykonywania zmian w cudzych repozytoriach ani obchodzenia dostępu do innych aplikacji.

## Diagnostyka i przyszłe zmiany

Projekt nie zawiera celowego automatycznego wysyłania promptów lub kluczy do własnej usługi analitycznej. Obsługa błędów adapterów nie pokazuje surowego body odpowiedzi HTTP. Nie należy publikować bazy, plików konfiguracji z kluczami, pełnych logów systemowych ani nieszyfrowanych eksportów. Ochrona przed sekretami wpisanymi bezpośrednio w tekst rozmowy nie oznacza automatycznej klasyfikacji każdej informacji.

Planowane funkcje wymagające dodatkowego przeglądu prywatności: oficjalne OAuth, synchronizacja urządzeń, dokumenty i retrieval z ACL, załączniki do wielu modeli, STT/TTS, kalendarz/poczta/dysk, komunikatory i opcjonalny most JARVIS. Żadna z nich nie jest opisywana tutaj jako już połączone konto ani aktywna usługa. Pozwolenia na mikrofon, aparat, powiadomienia lub katalogi powinny być żądane dopiero przy użyciu odpowiedniej funkcji.
