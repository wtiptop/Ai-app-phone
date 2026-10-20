# Lokalny vault, długie analizy i kampanie RPG — 0.3.0

## Aktualizacja 0.5.0 — powrót do wcześniejszych danych

Bieżący opis nowych ekranów i granic: [PAMIEC_CIAGLOSC_PL.md](PAMIEC_CIAGLOSC_PL.md). Wdrożono stronicowane wyszukiwanie z rundami dokumentów i dokładnym budżetem, starsze punkty analiz, historię sesji MG oraz porównanie wersji lore. Wznowienie notatki sesji tworzy nową rewizję bez cofania świata. Baza v3 i pełny szyfrowany backup v2 pozostają zgodne. Synchronizacja, embeddingi/graf i automatyczny kontroler sprzeczności pozostają zaplanowane; historyczne opisy limitów pierwszych wydań poniżej nie oznaczają braku nowych stron lub pełnej kopii.

Aktualizacja 0.4.0: w Ustawieniach działa osobna **Pełna szyfrowana kopia** z przywracaniem projektów, wszystkich wersji źródeł, checkpointów, kampanii i sekretów MG. Zachowuje ID i granice ról, a każda kolizja wycofuje całość. Po odtworzeniu folder projektu łączy się ponownie jawnie przez SAF. Instrukcja i wyłączenia: [BACKUP_PL.md](BACKUP_PL.md); dowody: [TESTS_PL.md](TESTS_PL.md). Wzmianki o zaplanowanym pełnym backupie w historycznych sekcjach 0.3.0 opisują poprzednie wydanie. Synchronizacja nadal pozostaje zaplanowana.

Urządzenie docelowe: **Google Pixel 9**. Ta wersja działa samodzielnie, z lokalnym modelem i lokalnym folderem Markdown. Obsidian jest opcjonalnym edytorem tych samych plików. Nie podłączono konta ani Obsidian Sync. Przyszła synchronizacja pozostaje osobnym, niewdrożonym etapem.

## Pamięć robocza a pamięć trwała

Duży vault nie mieści się w oknie modelu i nie jest ładowany w całości do RAM. Pliki przechodzą przez stronicowany import; w RAM przetwarzany jest jeden plik do 1 MiB i strona do 100 pozycji. Prywatna baza przechowuje zaszyfrowane wersje treści, fragmenty i punkty wznowienia. Indeks słów przechowuje HMAC zamiast jawnych wyrazów. Identyfikatory, rozmiary, wersje i część metadanych pozostają jawne. To nie jest szyfrowanie całego SQLite.

Model dostaje mały, wybrany pakiet fragmentów z nazwą pliku, wersją, skrótem SHA-256 zapisanym jako base64url i liniami źródła. Wyszukiwanie jest leksykalne po dokładnych słowach, również polskich; nie ma jeszcze embeddingów, odmiany wyrazów, grafu wikilinków ani automatycznego rozumienia całego vaultu. Zapisane fragmenty są danymi, nigdy instrukcjami systemowymi ani zgodą na akcje.

Domyślny profil MiniCPM ma teraz 4096 tokenów kontekstu, do 512 tokenów odpowiedzi, do 4 wątków CPU i 3 minuty jednej generacji. Istniejące ustawienie użytkownika jest zachowywane. To profil konfiguracyjny dla Pixel 9, bez benchmarku na fizycznym telefonie. Oficjalne materiały Google podają 12 GB RAM i Tensor G4 dla zwykłego [Pixel 9](https://blog.google/products-and-platforms/devices/pixel/google-pixel-9-pro-xl/); aplikacja nie zakłada, że całe 12 GB jest dla niej dostępne.

Przed generacją czat tworzy niezmienny pakiet: źródła, ostatnie mieszczące się wiadomości i nowe pytanie. Budżet wejścia liczony konserwatywnie w bajtach UTF-8 pozostawia rezerwę na odpowiedź i szablon; natywny silnik dodatkowo sprawdza rzeczywiste tokeny. Zbyt duży nowy tekst lub źródła powodują czytelny błąd. Starsze wiadomości pozostają na dysku; interfejs trzyma ostatnie 80, archiwum czyta po 40. Podgląd zgody pokazuje pełny wysyłany pakiet i liczbę pominiętych wiadomości. Suma kontrolna wiąże jednorazową zgodę z tym pakietem. Zapis przy odpowiedzi zachowuje dokładny snapshot źródeł także po ich późniejszej zmianie.

Nie jest to nieskończona pamięć modelu. Wielogodzinna praca wymaga kolejnych kroków, wyboru źródeł i zapisu ustaleń. Model nadal może popełniać błędy; zapis cytatu potwierdza użyte dane wejściowe, nie prawdziwość odpowiedzi.

## Pierwsze połączenie

1. Umieść vault lokalnie na Androidzie, np. w `Documents/MojVault`. Ustaw MiniCPM i rozmiar kontekstu przed wybieraniem źródeł do małego lokalnego modelu.
2. Otwórz **Pamięć → Obsidian i pamięć projektów**. Nadaj nazwę i wybierz **Połącz lokalny vault — tylko odczyt**. W systemowym selektorze wybierz konkretny folder, następnie zatwierdź dostęp.
3. Wybierz **Importuj / wznów**. Połączenie samo nie czyta plików. Nowe i zmienione dokumenty oczekują na osobne zatwierdzenie. Obejrzyj dokument i zatwierdź właściwą wersję.
4. Wyszukaj dokładne słowa w zatwierdzonych dokumentach, wybierz fragmenty i obejrzyj podgląd. **Użyj w czacie** otwiera nową rozmowę o tym zakresie pamięci.
5. W czacie sprawdź odbiorcę, wybrany model i dokładny pakiet. Lokalny MiniCPM nie używa sieci. Przy odpowiedzi przycisk źródeł otwiera zachowany pakiet.

Import obsługuje `.md` i `.markdown` UTF-8, ścieżki do 20 poziomów. Pomija ukryte katalogi, `.obsidian`, `.git`, pliki wirtualne i własny katalog eksportów. Pierwsza wersja akceptuje wyłącznie lokalny systemowy provider `com.android.externalstorage.documents`, bez Google Drive i innych zdalnych providerów. Uprawnienie SAF obejmuje wskazane drzewo; nie ma szerokiego uprawnienia do całej pamięci telefonu. Nie uruchamiamy pluginów, Dataview, kodu ani osadzonych odsyłaczy. Zwykłe Markdown i wikilinki pozostają w tekście. To odpowiada [plikowej organizacji Obsidiana](https://help.obsidian.md/Files+and+folders/How+Obsidian+stores+data) i [oficjalnemu SAF Androida](https://developer.android.com/training/data-storage/shared/documents-files).

## Wznowienie i zmiany plików

Kursor i pozycja wewnątrz strony są zapisywane po każdym pliku. Import można anulować, zamknąć ekran i wznowić. Jedno uruchomienie ma limit 2000 plików; następne kontynuuje od checkpointu. Cofnięcie uprawnienia wstrzymuje import. Ten sam plik z tym samym skrótem nie tworzy kolejnej wersji. Zmieniony plik tworzy nową wersję oczekującą na zatwierdzenie; poprzedni pakiet przestaje być ważny do nowej wysyłki.

Po zmianach w Obsidianie użyj **Skanuj od początku**. Nie ma obserwatora plików ani automatycznej synchronizacji. Zmiany zewnętrzne są widoczne dla prywatnej kopii dopiero po ponownym skanie. Skan nie jest atomowym snapshotem zmieniającego się vaultu; kursor lokalnego providera jest best-effort. Usunięcie pliku z vaultu nie usuwa automatycznie jego lokalnych wersji. Cofnięcie zgody usuwa go z indeksu; osobna akcja usuwa lokalne kopie bez kasowania oryginału.

Sekcja **Punkt wznowienia długiej analizy** zapisuje zatwierdzane przez użytkownika: cel, ustalenia, następny krok oraz źródła i wersje. Po ponownym otwarciu możesz wrócić do tych pól. Nie jest to automatyczna analiza całego zbioru ani kolejka autonomicznych agentów. W tle nie działa ciągła generacja; Android może zatrzymać proces. Import utrwala postęp, a inferencja po przejściu w tło jest anulowana. Trwałe harmonogramowanie przez WorkManager jest zaplanowane, zgodnie z [ograniczeniami pracy w tle Androida](https://developer.android.com/develop/background-work/background-tasks/persistent).

## Eksport do vaultu

Eksport wybranych źródeł lub punktu analizy pokazuje podgląd i żąda osobnego systemowego wyboru folderu z prawem zapisu. Powstaje nowy plik z losowym sufiksem wyłącznie w `Scalajaca-Exports`. Aplikacja nie nadpisuje oryginalnych notatek. Przerwanie zapisu może zostawić nowy, częściowy plik eksportu. Katalog eksportów nie zasila ponownie indeksu. SAF nie daje uniwersalnej gwarancji wykrywania wszystkich symlinków systemu plików; adapter sprawdza lokalnego providera, identyfikatory drzewa, ścieżki i pliki wirtualne.

## Kampania z zachowaniem lore

**Pamięć → Kampanie RPG i lore** tworzy pustą, własną kampanię z jawną edycją. Nie generuje nieznanego kanonu Fio ani nie łączy go z wfrp 3. Przełącznik MG/gracz jest lokalnym filtrem właściciela telefonu, a nie osobnym logowaniem i zabezpieczeniem przed osobą mającą dostęp do odblokowanego urządzenia.

MG ręcznie zatwierdza import pojedynczego Markdown lub wpis: kanon, postać/lokacja/stan świata albo osobna wiedza gracza. Domyślny import jest sekretem MG. Źródło ma identyfikator, tytuł, edycję i stronę/linie/własny numer wpisu. Bez ręcznej weryfikacji jest oznaczone jako **NIEZWERYFIKOWANE**. Hierarchia: zatwierdzony własny kanon kampanii, oficjalne źródło właściwej edycji, materiał pomocniczy. Obca oficjalna edycja jest odrzucana.

Stan sesji zapisuje cel, scenę, otwarte wątki, drużynę i zegar świata. Każda zmiana ma wersję i dopisywany audyt. Cofnięcie do wcześniejszego punktu tworzy nową rewizję. Model nie może sam zapisać zmian świata ani opublikować sekretu. Gracz otrzymuje tylko zatwierdzony jawny kanon i własną kategorię wiedzy gracza; stan świata i sekretne checkpointy pozostają dla MG. Sekrety nie są indeksowane. Do pakietu MG trafiają tylko po jawnym wybraniu; checkpoint sesji ma pierwszeństwo i nie jest po cichu przycinany.

Każda kampania i rola mają osobny zakres rozmowy. Nowy wybrany pakiet otwiera nowy czat; archiwalny czat zakresowy wymaga ponownego wyboru aktualnych danych w module pamięci. Historia MG nie jest przekazywana do gracza. Kopiowanie, zaznaczanie, udostępnianie i zwykły eksport rozmowy MG są w interfejsie zablokowane. Porównanie modeli jest wyłączone dla rozmów zakresowych. Zmiana rewizji kampanii lub cofnięcie zgody źródła unieważnia wcześniejszy podgląd przed dispatch.

Sama ta infrastruktura nie potwierdza jakości długiej narracji MiniCPM5-1B po polsku, poprawności mechaniki WFRP ani wielomiesięcznej spójności lore. Automatyczny recenzent sprzeczności, semantyczne wyszukiwanie, pełna mechanika i testy wielosesyjnej kampanii pozostają zaplanowane.

## Kopie, pojemność i granice etapu

Dotychczasowa kopia hasłem obejmuje **zwykłe czaty, ręczne notatki i zadania**. Wyklucza wszystkie czaty zakresowe, aby ich przywrócenie nie zgubiło granicy MG/gracz. Nie obejmuje nowych projektów, wersji źródeł, indeksu, kampanii i checkpointów. Pełna przenośna kopia tych danych oraz synchronizacja z rozwiązywaniem konfliktów są zaplanowane. Nie usuwaj danych aplikacji w oczekiwaniu, że stara kopia odtworzy kampanię. Oryginalny vault oraz świadome eksporty przechowuj osobno.

Nie ma jeszcze polityki retencji starych wersji ani limitu całego vaultu: baza rośnie wraz z liczbą zmian i wolnym miejscem na telefonie. Błędy zapisu są obsługiwane, ale nie wykonano testu zapełnienia całego fizycznego nośnika. Interfejs listuje dokumenty po 30, wyszukiwanie wybiera do 64 kandydatów i do 6 fragmentów; projekty i checkpointy mają ograniczone listy. Starsza lista wszystkich rozmów i klasyczna kopia nie są rozwiązaniem do archiwów dowolnej wielkości. Następny etap obejmuje pełne stronicowanie, retencję, przenośny backup i pomiary dużego rzeczywistego vaultu na Pixel 9.

Wyniki testów i rzeczywiste ograniczenia wydania znajdują się w `TESTS_PL.md`, `test-results/` i głównym `IMPLEMENTATION_STATUS.md`. Testy syntetyczne i emulator nie zastępują odbioru na fizycznym Pixel 9.
