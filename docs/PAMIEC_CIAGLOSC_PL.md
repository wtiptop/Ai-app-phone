# Pamięć dużych projektów i ciągłość RPG — 0.5.0

## Obsługa pamięci kampanii w 0.5.2

Wyszukiwanie RPG pomija pospolite słowa pytania PL/EN przed wyborem maksymalnie 12 terminów. Nadal wymaga dokładnych form słów: odmiany i synonimy wpisuje się oddzielnie. Kandydaci są czytani stronami po 40 (do 2000). Długi automatyczny wpis nie zatrzymuje poszukiwania późniejszego krótkiego faktu. Ograniczony pakiet oznacza wycinek, nie całą pamięć.

Jawnie zaznaczone wpisy trafiają do pakietu w całości. Gdy wybrany wpis, limit liczby rekordów lub dołączony stan sesji przekracza budżet, aplikacja wyświetla błąd zamiast cicho zastąpić wybór innym źródłem. Zmniejsz wybór, skróć wpis lub wyłącz automatyczne dołączenie stanu sesji MG. Przełącznik **Dołącz stan sesji MG** działa tylko dla przygotowywanego pakietu: nie kasuje checkpointu ani historii. Po zmianie roli/kampanii wraca do domyślnego ustawienia. W API `includeCheckpoint:false` wyłącza automatyczny wybór; ręczne dołączenie notatki nadal wymaga MG i jawnej zgody na sekrety.

Pakiet nazywa rodzaj materiału: kanon, stan świata, wiedza postaci i notatka sesji MG. Notatka jest kontekstem pracy, a nie nową prawdą świata. Bieżący kanon ma pierwszeństwo przed dawną notatką. Wznowienie punktu nadal nie cofa świata.

Dla przygotowywania kampanii do MiniCPM ustaw kontekst **4096** w konfiguracji modeli offline. Przy 1024/2048 pozostają dostępne lokalne przeglądanie i edycja, a przycisk pakietu wskazuje wymagane ustawienie. Nie włączamy większego kontekstu ani płatnego modelu automatycznie.

MiniCPM otrzymuje jeden komunikat użytkownika zawierający źródła i pytanie, z technicznymi nagłówkami `Sources`/`Question`. Tekst źródeł pozostaje danymi. Podgląd całego żądania, zgoda i dowód kontekstu obejmują dokładnie przekazaną treść. Takie formatowanie nie gwarantuje poprawnej polskiej narracji. Wyniki prób wielosesyjnych, także porażki, opisuje bieżący `TESTS_PL.md`.

## Aktualizacja 0.5.1

Po wskazaniu zatwierdzonego pakietu MiniCPM stosuje zachowawcze odpowiedzi i osobną instrukcję zachowania nazw/liczb. Zgoda i podgląd obejmują tę instrukcję; źródła nadal są danymi. Przypadek COMPASS przechodzi po zmianie dekodowania w powtarzanych próbach JNI i czatu, ale ogólna kontrola poprawności lore nadal należy do MG. Historyczna obserwacja COMASS poniżej dotyczy wcześniejszego profilu 0.5.0. Format kopii, role, checkpointy i sposób zatwierdzania kanonu pozostają zgodne.

Aplikacja działa lokalnie bez serwera, OPPO i Obsidiana. Pliki vaultu są źródłami, baza jest trwałą pamięcią, a kontekst MiniCPM pozostaje małym pakietem wybranych danych. Większa baza nie oznacza wczytania jej całej do RAM ani do modelu.

## Powrót do projektu

1. Otwórz Pamięć → Obsidian i pamięć projektów. Wybierz projekt; listę projektów można przewijać stronami po 50.
2. Zaimportuj lub wznów skan wskazanego lokalnego folderu. Obejrzyj i zatwierdź aktualne wersje potrzebnych notatek. Zmienione pliki ponownie wymagają zatwierdzenia.
3. Wyszukaj istotne słowa. Wyniki mają licznik i strony po 10 fragmentów. Ranking najpierw pokazuje różne dokumenty, zamiast zapełniać początek fragmentami jednej notatki. Pomijamy słowa pospolite PL/EN; odmiany wyrazów i synonimy nadal wpisuje się osobno.
4. Wybierz fragmenty na danej stronie i otwórz podgląd. Zobaczysz dokładny tekst dla modelu, ścieżki, rewizje, hash i linie. Przy przekroczeniu budżetu tekst zostanie skrócony i oznaczony. Przejście na inną stronę tworzy nowy wybór; zmiana pytania usuwa poprzedni.
5. Zatwierdź użycie w czacie. Aplikacja ponownie sprawdzi źródła przed generacją. Odpowiedź zachowa dowód użytego pakietu. Zmiana pliku lub cofnięcie zgody wymaga ponownego wyszukania; historyczny dowód nie jest nową zgodą.

W sekcji punktów analiz dostępne są starsze strony po 30 wpisów. „Wróć do tej analizy” odtwarza cel, ustalenia, następny krok i zapisane odnośniki w formularzu. Nowy zapis z formularza zachowuje poprzedni punkt jako osobny rekord. „Odszukaj źródła do kolejnego kroku” uruchamia nowe wyszukanie; nie dołącza dawnych ustaleń automatycznie i nie uznaje ich za zweryfikowany kanon. Sprawdź aktualne wersje źródeł. API aktualizacji tego samego ID checkpointu nadal przechowuje tylko jego bieżące pola; UI używa osobnych ID.

## Powrót do sesji RPG

Wybierz właściwą kampanię i jawnie włącz „Widok MG z sekretami”. Otwórz historię sesji MG. Starsze zapisy pobierane są po 20, z kursorem rewizji. Kliknięcie rewizji pokazuje historyczny cel, scenę, otwarte wątki, drużynę i zegar obok bieżącego wpisu. Archiwalny punkt jest notatką z przeszłości, a nie aktualnym stanem świata.

„Wybierz punkt do wznowienia” wymaga osobnego potwierdzenia. Powstaje nowa rewizja notatki sesji z podanym pochodzeniem. Kanon, postaci, lokacje i inne wpisy świata pozostają bieżące. Dzięki temu powrót do starego celu nie usuwa późniejszych wydarzeń. Gdy kampania zmieniła się w międzyczasie, zapis zostanie odrzucony jako konflikt rewizji. Pełne cofnięcie świata ma oddzielny przycisk audytu i potwierdzenie.

Przy wpisie lore MG może otworzyć historię wersji. Podgląd wskazuje różnice treści, źródeł, rodzaju, widoczności i zatwierdzenia oraz pokazuje obie wersje. Jest to pomoc w ręcznym sprawdzaniu ciągłości. Nie rozstrzyga automatycznie, czy opowieść jest sprzeczna z oficjalnym podręcznikiem.

Historia może zawierać dawne sekrety, także gdy obecny wpis jest już jawny. Dlatego dostęp do całego archiwum ma wyłącznie lokalny widok MG z jawnym opt-in. Historia nie trafia automatycznie do promptów, indeksu ani gracza. Widok na jednym telefonie jest filtrem lokalnego właściciela; odrębne konta graczy i rzeczywiste uwierzytelnianie wieloosobowe pozostają zaplanowane.

Zapisany pakiet potwierdza, jakie źródła otrzymał model; nie potwierdza prawdziwości jego odpowiedzi. W próbie MiniCPM5-1B poprawne źródło „COMPASS” dało odpowiedź „COMASS”. Przy nazwach własnych proś o dosłowne kopiowanie i porównuj odpowiedź z pakietem. Kanon zatwierdza MG; samo wygenerowanie tekstu nie zmienia zatwierdzonych wpisów. Kontroler automatycznie porównujący odpowiedź z lore pozostaje zaplanowany.

## Kopia i ograniczenia

Pełny szyfrowany backup zachowuje źródła, rewizje, punkty analiz, historię sesji i sekretne wersje lore. Nie zmieniliśmy formatu kopii v2 ani bazy v3. Przywracanie zachowuje ID i ponownie szyfruje dane kluczem docelowego urządzenia. Obowiązują reguły z BACKUP_PL.md: bez automatycznego scalania kolizji, bez kluczy API, wag GGUF i uprawnień SAF.

Nowe testy obejmują duży syntetyczny indeks i wiele rewizji; rzeczywiste wyniki są w TESTS_PL.md. Embeddingi, graf encji, automatyczne wykrywanie sprzeczności, agent ciągłości, retencja, uniwersalna obsługa wielkich plików (>1 MiB), odbiór wielogigabajtowego vaultu i długiej polskiej kampanii pozostają zaplanowane lub niezweryfikowane. Fizyczny Pixel 9 wymaga osobnego testu pamięci RAM, baterii, temperatury i jakości narracji.
