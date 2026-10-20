# Testy akceptacyjne

Aktualizacja 0.4.0: w Ustawieniach działa osobna **Pełna szyfrowana kopia** z przywracaniem projektów, wszystkich wersji źródeł, checkpointów, kampanii i sekretów MG. Zachowuje ID i granice ról, a każda kolizja wycofuje całość. Po odtworzeniu folder projektu łączy się ponownie jawnie przez SAF. Instrukcja i wyłączenia: [BACKUP_PL.md](BACKUP_PL.md); dowody: [TESTS_PL.md](TESTS_PL.md). Wzmianki o zaplanowanym pełnym backupie w historycznych sekcjach 0.3.0 opisują poprzednie wydanie. Synchronizacja nadal pozostaje zaplanowana.

Odbiór 0.3.0: 193 Flutter, 27 JUnit i 5 AndroidJUnitRunner PASS. A07/A15: rzeczywisty SAF drzewa lokalnego, import syntetycznych Markdown, wybór źródła i MiniCPM offline na emulatorze. A09/A14/A25: trwały RPG, role/scope/źródła, rewizje/cofanie i checkpointy oraz wznowienie 205 plików sprawdzone na hoście; nie jest to odbiór pełnej gry i uwierzytelniania graczy. Fizyczny Pixel 9, duży rzeczywisty vault, pełny eksport/rotacja SAF, pełny backup nowej pamięci i jakość wielosesyjnej narracji pozostają otwarte. Dowody: TESTS_PL.md oraz test-results/android-emulator-0.3.0.json.

Każdy scenariusz ma wynik **nieuruchomiony**, dopóki rzeczywisty raport `TESTS_PL.md` nie wskaże inaczej. Test jednostkowy atrapy HTTP potwierdza logikę klienta, a nie połączenie z prawdziwym dostawcą. Live API, prywatne konta, publikacja i wiadomości zewnętrzne są wyłączone bez osobnej zgody właściciela.

| ID | Scenariusz i oczekiwany wynik | Dowód / środowisko |
|---|---|---|
| A01 | Czysta instalacja Android, tryb samolotowy, brak kluczy/OPPO/Obsidiana/Termuxa. Start i lokalne demo bez żądań sieci, opłat i zbędnych pozwoleń. | Emulator/telefon + log sieci + APK build |
| A02 | Utwórz dwie rozmowy, wpisz polskie znaki i emoji, zamknij aplikację, wymuś zatrzymanie, ponownie otwórz; treści i kolejność zachowane. Szukaj istniejącej i brakującej frazy. | SQLite na urządzeniu + integracja repozytorium |
| A03 | Skonfiguruj API dopiero po zgodzie; jawny dostawca/model; poprawny stream, stop przed nagłówkiem i w środku odpowiedzi, częściowa treść oznaczona. Bez klucza brak HTTP i czytelny błąd. Zmiana dostawcy zachowuje historię. | Fake HTTP automatycznie; live dopiero za zgodą |
| A04 | Porównaj 2, 3 i 4 modele. Równoległe osobne wyniki z pochodzeniem i kosztem/„nieznany”; jedna awaria pozostawia inne. Kopiuj i zestaw wyniki. Anuluj jedną/wszystkie. | Fake HTTP + widget/integracja |
| A05 | Wprowadź klucz znacznikowy; brak sekretu w SQLite, eksportach, logach, błędach, zrzutach diagnostyki i repo. Secure storage read/write/delete. Szyfrowany backup ma losowy nonce i odrzuca złe hasło/modyfikację. | Testy bezpieczeństwa + Keystore na Android |
| A06 | Most domyślnie wyłączony. Błędne parowanie/timeout/revoke/utrata sieci nie blokuje czatu, pamięci i zadań lokalnych. | Fake bridge; Android po implementacji |
| A07 | Eksport MD/JSON z polskimi znakami i blokiem kodu, import MD, odtworzenie danych bez Obsidiana; odmowa SAF nie usuwa danych. Porównaj treść i metadane. | Unit + Android SAF |
| A08 | Ekran rozróżnia demo, wymaganie klucza, zatwierdzenie SSO i brak integracji. Zakaz konsumenckich cookies/tokenów, nieudokumentowanych endpointów, Accessibility i CAPTCHA bypass. | Przegląd źródeł + UI |
| A09 | Odrębne profile/projekty/kampanie i role. Canary GM_SECRET z kampanii A nie trafia do gracza A/B, zwykłego czatu, promptu kontrolera, retrievalu, logu ani eksportu. Gość nie podmienia ownerId/role. | Unit negatywne + integracja; nie sam filtr UI |
| A10 | Raport zawiera pliki, polecenia, exit code, ograniczenia, instrukcję, następny krok. APK tylko po exit 0, istniejącym pliku i sumie SHA-256. | Artefakty builda i TESTS_PL.md |
| A11 | Kolejka przetrwa restart i awarię; deduplikacja ID; atomowy zapis użytkownik/próba/stan; anulowane/niepewne płatne próby nie ponawiają się bez zgody. Sprawdź brak duplikatu po przerwaniu w każdej fazie zapisu. | SQLite unit/integration + force stop |
| A12 | Ekran 320 dp, tekst 200%, klawiatura, jasny/ciemny motyw, TalkBack, rotacja, Android Wstecz; brak overflow i utraty szkicu. | Widget golden/layout + ręczny Android |
| A13 | Plan agenta widoczny przed wykonaniem; ID i rejestr decyzji, 2 korekty domyślnie; limit kroku/czasu/kosztu/wywołań blokuje start; stop i bezpieczne wznowienie; Auto wyjaśnia model i daje zmianę; recenzent/arbiter ujawnia spór. | Unit router/orchestrator + UI |
| A14 | Notatka/fakt/dokument/stan zadania mają wymagane metadane i wersję; foldery ze specyfikacji; zakres retrievalu; zatwierdzenie trwałego faktu, korekta, usuwanie i zapomnienie także z indeksu. | Storage/retrieval unit + integracja |
| A15 | SAF wybiera konkretny plik/katalog, odmowa/anulowanie bez szkody; ACTION_SEND/MULTIPLE działa przez chooser z właściwym MIME i tymczasowym URI permission. Niewspierany załącznik blokowany przed siecią. | Android natywna integracja |
| A16 | Fake odpowiedzi: 401/403/408/429/500/503, timeout nagłówków i przerwa streamu, SSE podzielone między bajtami UTF-8 i ramkami, puste/malformed JSON, rozłączenie. Błędy bez surowego body/sekr. Retry ograniczony, bez cichego dublowania płatnego POST. | Unit HTTP, parser, cancellation |
| A17 | Ponów/edytuj/rozgałęź zachowuje oryginalną próbę i metadane, nie dubluje poprzedniej user message. Stop oznacza „anulowano”, pełna odpowiedź „zakończono”. | Unit controller + widget |
| A18 | Cytat ma faktyczne źródło/link/datę/stronę jeśli dostępna; brak źródła = „niezweryfikowane”. Zgodność kilku modeli nie uzyskuje etykiety „prawda”. Przykład prompt injection w dokumencie nie uruchamia narzędzia. | Unit walidator + review scenariuszowe |
| A19 | Mikrofon/aparat/powiadomienia proszą o pozwolenie przy funkcji; odmowa nie blokuje czatu; nagrywanie tylko push-to-talk; brak stałego mikrofonu. TTS start/stop. | Ręczny Android + manifest review |
| A20 | Zgoda wylicza odbiorców, historię, fragmenty pamięci i załączniki. Odmowa daje 0 żądań. Nowy odbiorca/załącznik wymaga nowego zakresu. Zewnętrzna wiadomość/plik/zakup nie zachodzi na instrukcję z dokumentu ani bez zgody właściciela. | Unit polityk + fake tools + UI |
| A21 | Migracja poprzedniej wersji zachowuje dane; brakujące/zepsute dane nie tworzą cichego pustego profilu. Backup/restore sprawdza wersję i integralność, konflikt sync ma jawny wybór/rejestr, nie nadpisuje po cichu. | SQLite migracja + crypto unit |
| A22 | Domeny osobiste/IT/badania/GPW/AI/gry/RPG/komunikacja mają kontrolera. GPW: ticker zawsze z pełną zweryfikowaną nazwą, bez tradingu; WFRP wszystkie edycje i Hamburg tylko ze źródeł; PL/DE objaśnienia. Repo zmieniane dopiero za zgodą/dostępem. | Testy fixture + kontrola produktu |
| A23 | Zadanie/przypomnienie/lista ma status, ostatni przebieg, retry i dedup; tryb lokalny opisany best-effort. Test Doze/reboot/odmowa notyfikacji/brak sieci; brak obietnicy konkretnej godziny i 24/7. | WorkManager na Android + fake clock |
| A24 | Discord/Telegram bot, WhatsApp oficjalna platforma biznesowa; Signal brak obietnicy oficjalnego bot API. Mapowanie ID kanału→osoba nie daje podszycia; webhook ma auth/replay/dedup. Bez backendu brak fałszywej obietnicy stałego odbioru. | Fake webhook + review; live tylko za zgodą |
| A25 | Kampania ma manifest i rewizje, replay/rollback spójny, świat oddzielony od wiedzy; brak decyzji za gracza; ilustracja async; role świata i lore niezależne. Brak plików kanonu Fio = brak importu/startu/resetu. wfrp 3 nigdy nie scala się z Fio. | Domain unit + A09 + fixtures bez danych prywatnych |
| A26 | Estymata przed multi i rezerwacja budżetu atomowo; dzień/miesiąc; usage API jeśli obecne, nieznane ceny nie są zerem; konkurencyjne starty nie przekraczają limitu. Fallback tylko polityka/zgoda, lokalny limit opisany jako lokalny. | Unit fake clock + równoległe żądania |
| A27 | Wiadomość/import Markdown z obrazem HTTPS do serwera śledzącego i obrazem `file:`/lokalną ścieżką nie pobiera nic ani nie czyta lokalnego pliku podczas renderowania. Link wymaga jawnej akcji; renderer bez auto-HTML/skryptów. | Widget z imageBuilder + fake klient/HttpOverrides |

## Warunki zamknięcia faz

Uzupełnienie MiniCPM 0.1.1:

| ID | Scenariusz | Metoda / stan |
|---|---|---|
| A28 | Zły URL, HTTP, URL credentials/query/fragment odrzucone, brak wysyłki sekretu po zmianie zatwierdzonego adresu | Dart mock — PASS |
| A29 | SSE UTF-8, usage, stop, brak retry/redirect, niepełna odpowiedź i odrzucone tool_calls | Dart mock — PASS |
| A30 | Zero kosztu wymaga obu stawek i deklaracji, nie odblokowuje płatnych API; rezerwy porównania atomowe | Dart + prawdziwy SQLite FFI — PASS |
| A31 | UI rozróżnia serwer i silnik offline; zmiana adresu usuwa stary klucz i resetuje deklarację | Dwa testy widgetów wykonane w pełnym zestawie Flutter 141 PASS; Keystore urządzenia do odbioru |
| A32 | Rzeczywista generacja MiniCPM w czacie i porównaniu, Keystore i TLS na Androidzie | Nieuruchomione; wymaga własnego serwera i urządzenia |
| A33 | Wbudowany silnik bez serwera, import GGUF, uszkodzony model, brak RAM, stop i usuwanie | Wdrożony CPU/JNI; 21 JUnit z prawdziwym GGUF i testy adaptera/kanału/UI PASS. Host C++ realna generacja/stop PASS. SAF/JNI/Stop/tło emulatora x86_64 PASS w 4 testach; fizyczny telefon, RAM i termika do odbioru |
| A34 | Android w trybie samolotowym po imporcie GGUF: start, krótka generacja, Stop, tło/powrót, rotacja, usuwanie; brak sieci/fallbacku, pomiar RAM/baterii i jakość PL | Częściowy odbiór: import, rzeczywisty czat offline, Stop/JNI po tokenie, następna generacja i tło/powrót emulatora x86_64 PASS. Rotacja/usuwanie, bateria/termika, PL i fizyczny telefon niewykonane |

Faza 0: datowane źródła pierwotne i jawne ograniczenia. Faza 1: repo, ADR, macierz, UX, akceptacja i zależności. Faza 2: sam kod nie wystarcza — wymagane wyniki analizy, testów oraz w miarę środowiska build i instalacja. Brak urządzenia lub klucza jest wynikiem „nieuruchomiony/ograniczony”, nigdy pozytywnym testem. Fazy 3–6 mają osobne kryteria wymienione wyżej i pozostają otwarte, dopóki nie ma dowodów.

## Dodatkowy odbiór pamięci 0.5.0

| ID | Scenariusz | Dowód i granica |
|---|---|---|
| A35 | 1202 dokumenty/2201 fragmentów, w tym 1000 jednego pliku: późny fakt, strony, zgodność fallbacku, tylko strona odszyfrowana, brak cudzych/cofniętych/starych fragmentów | Syntetyczny indeks hosta, nie benchmark importu SAF ani korpusu GB; TESTS_PL.md |
| A36 | Starsza strona analiz → formularz → nowy zapis; powrót po restarcie/restore, źródła wymagają aktualnej zgody | SQLite i widgety; brak autozapisu ustaleń modelu |
| A37 | CP1→CP2→wznowienie CP1 tworzy nową rewizję, stare szyfrogramy i dzisiejszy kanon pozostają; konflikt CAS odrzucany; backup i nowy klucz | Testy store/backup/UI oraz osobny AndroidJUnitRunner; wyniki TESTS_PL.md |
| A38 | Dawny sekret dziś jawnego lore w archiwum tylko localView MG+opt-in przed decrypt, brak indeksu i gracza; porównanie wersji bez automatycznego promowania kanonu | Negatywne testy roli/purpose + mały ekran; merytoryczny kontroler sprzeczności zaplanowany |

## Dodatkowy odbiór 0.5.1

A39: z zatwierdzonym syntetycznym źródłem MiniCPM zachowuje nazwę COMPASS w trzech odpowiedziach UI, w tym ponowieniach, a receipt wskazuje właściwy pakiet. Osobny JNI sprawdza 3×COMPASS i LANTERN/RAVEN bez UI. Wyniki: TESTS_PL.md; nie jest to odbiór całej kampanii ani fizycznego Pixela 9.
