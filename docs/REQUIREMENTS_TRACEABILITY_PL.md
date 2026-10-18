# Macierz wymagań Scalającej

## Uzupełnienie 0.3.0: lokalny vault, duża pamięć, RPG i Pixel 9

Wybór właściciela: lokalny folder Androida teraz, możliwa synchronizacja później, urządzenie docelowe Pixel 9. Aktualny zakres i ograniczenia: [OBSIDIAN_PAMIEC_RPG_PL.md](OBSIDIAN_PAMIEC_RPG_PL.md), ADR 008 i bieżący raport testów. Zachowano wszystkie 129 identyfikatorów pierwotnych wymagań oraz MX1–MX7. Wdrożony leksykalny retrieval i trwały stan kampanii nie oznaczają pełnej autonomii, mechaniki WFRP ani potwierdzonej jakości długiej kampanii. Pełny backup nowej pamięci i sync pozostają zaplanowane.

## Uzupełnienie użytkownika: MiniCPM — 18.10.2026

Nie zmienia ani nie usuwa 129 wymagań pierwotnej specyfikacji.

| ID | Zakres | Status / dowód |
|---|---|---|
| MX1 | Oficjalne repozytorium, formaty i licencje | Zweryfikowane źródła wydawcy w MINICPM_PL.md; brak dołączonych wag |
| MX2 | Adapter własnego serwera tekst/SSE/katalog/stop/błędy | Potwierdzone testami Dart; realny model wymaga konfiguracji i testu |
| MX3 | HTTPS, opcjonalny klucz Keystore, jawny adres, brak przenoszenia sekretu | Transport i zmiana zatwierdzonego adresu testowane; widgety PASS; Keystore wymaga testu Android |
| MX4 | Kontrola kosztów i jednorazowa zgoda, darmowy własny serwer bez odblokowania innych API | 8 testów polityki na SQLite FFI PASS, w tym lokalny permit związany z hashem modelu |
| MX5 | Czat i porównanie z MiniCPM, zachowana samodzielność rdzenia | Kod, UI i pełny Flutter runner PASS; czat JNI offline i Stop/tło potwierdzone na emulatorze x86_64; porównanie na urządzeniu i fizyczny telefon do odbioru |
| MX6 | Lokalny silnik Android, dobrowolne GGUF, zasoby i usuwanie | Wdrożone CPU/JNI, prywatny import/stop/usuwanie, przypięte źródła i szablony, 21 JUnit PASS z prawdziwym GGUF; import SAF i Stop/tło na emulatorze PASS; termika i fizyczny telefon do odbioru |
| MX7 | APK i test telefonu z modelem | APK 0.3.0 ARM64+x86_64 build/podpis/manifest/16 KiB PASS; 5 scenariuszy emulatora, w tym lokalny vault i realna odpowiedź ze źródła offline; fizyczny Pixel 9 nieprzetestowany |

## Pierwotna specyfikacja

Źródło: pełna `SPECYFIKACJA.md`, sekcje 0–16. Data przeglądu: **17.10.2026**. Każdy wiersz jest wymaganiem do odbioru; zebranie kilku elementów w jednym wierszu nie znosi żadnego z nich.

Statusy realizacji: **zaplanowane** = brak odebranej implementacji; **ograniczone** = istnieje część kodu lub projekt, ale brak pełnego potwierdzenia; **potwierdzone** = wskazany dowód i test. Status realizacji różni się od statusów integracji pokazywanych użytkownikowi: `działa`, `wymaga konfiguracji`, `wymaga zatwierdzenia dostawcy`, `eksperymentalna`, `niedostępna`. Sam kod adaptera nie potwierdza działającego konta ani poprawności na Androidzie. Wyniki uruchomień znajdują się w `TESTS_PL.md`.

## 0. Samodzielny produkt

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R00.1 | Instalowalny samodzielny Android APK; AAB docelowo | 2/6 | Ograniczone: APK ARM64+x86_64 zbudowany, podpis/manifest PASS; instalacja i generacja offline emulatora potwierdzone; telefon/AAB do odbioru |
| R00.2 | Start, lokalne dane, czaty, chmura i podstawowe zadania bez OPPO, RPi, VPS, Termuxa i serwera | 2 | Ograniczone: kod lokalnego startu/UI/SQLite/BYOK obecny; samodzielny start i czat offline emulatora potwierdzone; pełne A01 na telefonie do odbioru |
| R00.3 | JARVIS/OPPO jako odłączalny moduł wyłączony domyślnie | 6 | Ograniczone: wyłączony JarvisBridge i test braku uprawnień; rzeczywiste parowanie zaplanowane |
| R00.4 | Offline: dane, szkice, wyszukiwanie, trwała kolejka i eksport | 2/3 | Ograniczone: kod historii/szkiców/notatek/listy zadań/kolejki odnośników/transferów; model MiniCPM CPU/JNI wdrożony w 0.2.0, odbiór telefonu otwarty; pełny dispatcher zaplanowany; A02/A11 do odbioru |
| R00.5 | Polski domyślny, i18n, responsywność i dostępność | 2 | Ograniczone: polski UI, motywy, semantyka i test 320×640 / 200% PASS; ARB i TalkBack urządzenia zaplanowane |

## 1. Cel i zasady

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R01.1 | Legalne OpenAI, Anthropic, Google, xAI i rozszerzalność | 0–3 | Ograniczone: oficjalne źródła i cztery transporty, 37 testów HTTP mock PASS; live API wymaga konfiguracji i zgody |
| R01.2 | Jeden model, porównanie i delegowanie agentom | 2/4 | Ograniczone: czat i porównanie w kodzie; domena agentów istnieje bez wykonawcy LLM |
| R01.3 | Wspólne projekty, notatki i zadania pod kontrolą użytkownika | 3–5 | Ograniczone: ręczne notatki i zadania w SQLite, testy hosta PASS; pełne projekty/retrieval zaplanowane |
| R01.4 | Priorytety: samodzielność, legalność, prywatność/koszt, niezawodność, rozszerzalność, agentowość | wszystkie | Ograniczone: kolejność zapisana w ROADMAP_PL.md; odbiór wymaga testów |
| R01.5 | Każda funkcja ma uczciwy status z pięciu statusów specyfikacji | 2 | Ograniczone: jawne demo, konfiguracja API i statusy modułów; pełne statusy wszystkich rozszerzeń w tej macierzy |

## 2. Hybrydowe podłączanie AI

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R02.1 | Interfejs ProviderAdapter i osobne uprawnienia dostawcy | 2 | Ograniczone: provider_registry i kontrakt obecne, testy mock; pełne capability/uprawnienia do rozbudowy |
| R02.2 | Oficjalne OAuth/OIDC/PKCE tylko gdy wspiera typ tej aplikacji i zatwierdzenie | 0/3 | Zaplanowane: A08; integracje niezatwierdzone nie mogą udawać logowania |
| R02.3 | Tożsamość, uprawnienie do planu i rozliczenie API jako osobne stany | 0/3 | Potwierdzone dokumentacyjnie: INTEGRATIONS_MATRIX rozdziela tożsamość, plan/kredyty i API; logowanie niewdrożone |
| R02.4 | Rozszerzenie zatwierdzonego dostępu planu ChatGPT i procedura zgody | 3 | Zaplanowane; zależne od dostępności i zgody dostawcy |
| R02.5 | Zakaz cookies/sesji konsumenckich, przechwytywania, nieudokumentowanych endpointów | wszystkie | Potwierdzone w kodzie: stałe oficjalne HTTPS, bez przekierowań, cookies i sesji konsumenckich; testy transportu PASS |
| R02.6 | BYOK OpenAI, Anthropic, Gemini, xAI; subskrypcja nie oznacza API | 2/3 | Ograniczone: cztery niezależne adaptery i formularze API; brak płatnych prób/live API, A03 pozostaje niewykonany na dostawcy |
| R02.7 | Sekrety poza kodem/APK/logami; Keystore; jawne ryzyko BYOK na telefonie | 2 | Ograniczone: SecretStore/KeystoreSecrets + ContentCipher + komunikat ryzyka; natywny Keystore A05 do odbioru |
| R02.8 | Opcjonalne bezpieczne proxy tylko przy realnej konieczności | 6 | Zaplanowane; zwykły czat nie może go wymagać |
| R02.9 | Ręczne Sharesheet ACTION_SEND/MULTIPLE tekst/plik; import/eksport; tylko oficjalne deep linki | 3 | Ograniczone: Kotlin ACTION_SEND tekst + SAF pojedynczego pliku; MULTIPLE, odbieranie share i katalog vault zaplanowane; test urządzenia niewykonany |
| R02.10 | Brak Accessibility automation, omijania CAPTCHA i obietnic bezobsługowego abonamentu | wszystkie | Potwierdzone w źródle/manifest: bez Accessibility i przechwytywania kont; ręczne udostępnianie nie jest dostępem do planu |
| R02.11 | ID, katalog modeli, tekst/obrazy/pliki/tools/stream/context i auth | 2/3 | Ograniczone: ID/auth/katalog/tekst/SSE i descriptor; media/tools nieobsługiwane, context/ceny nieznane zamiast fikcyjnych |
| R02.12 | Limity/ceny z datą, konfigurowalne modele, timeout/retry, status, test i błędy, miejsce przetwarzania | 2/3 | Ograniczone: stawki/model właściciela z datą, timeout/cancel/no-retry, test katalogu i błędy; pełne cenniki/regiony/limity kont zaplanowane |
| R02.13 | Awaria dostawcy nie blokuje pozostałych | 2 | Ograniczone: niezależne adaptery i osobne catch w porównaniu; transport mock PASS, live porównania niewykonane |

## 3. Czat i UX

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R03.1 | Pięć kart: Czat, Agenci, Projekty i pamięć, Zadania, Ustawienia | 2 | Ograniczone: kod lib/ui/home.dart obecny; dodano home_test; wyniki w TESTS_PL.md |
| R03.2 | Małe ekrany, motywy, duży tekst, TalkBack, przewidywalny Wstecz | 2/6 | Ograniczone: host UI / duży tekst / semantyka PASS, jasny/ciemny/systemowy; TalkBack i Wstecz na urządzeniu do odbioru |
| R03.3 | Jeden model: jawny wybór i zmiana z zachowaniem historii | 2 | Ograniczone: wybór modelu/dostawcy zachowuje historię; demo i granice zgód testowane, live niewykonane |
| R03.4 | Auto: możliwości/koszt/prywatność/latencja/jakość/preferencje; widoczny powód i zmiana | 4 | Zaplanowane: A13 |
| R03.5 | Porównanie 2–4: równoległe karty, zestawienie, kopiowanie, koszt i źródło każdej | 4 | Ograniczone: comparison.dart porównuje niezależnych dostawców; wyniki w RAM, bez 2 modeli tego samego dostawcy, brak pełnego panelu zestawienia; A04 |
| R03.6 | Konsensus: model główny/niezależny recenzent/arbiter; zgodność nie jest dowodem | 4 | Zaplanowane: A13 |
| R03.7 | Agenci: plan, przebieg, stop, kroki i koszty | 4 | Zaplanowane: A13 |
| R03.8 | Streaming, anuluj, ponów, edytuj, rozgałęź | 2/3 | Ograniczone: ChatSession stream/cancel/retry; edycja kopiuje tekst do nowej wiadomości; pełne gałęzie zaplanowane; A03/A17 |
| R03.9 | Szukaj, przypnij, tagi, foldery/projekty | 2/3 | Ograniczone: search/pin/notatki/foldery potwierdzone testami hosta; tagi i pełne projekty zaplanowane |
| R03.10 | Cytowania z datami/linkami, Markdown/kod, kopiowanie, MD/JSON | 2/3 | Ograniczone: Markdown/eksport oraz zapis dokładnych źródeł z wersją/hashem/liniami przy odpowiedzi w 0.3.0; automatyczna weryfikacja cytowań modelu i osobny jawny JSON czatu zaplanowane |
| R03.11 | Pliki/obrazy zgodne z możliwościami modelu, import | 3 | Ograniczone: wybrane zatwierdzone fragmenty Markdown jako kontekst są podłączone; obrazy/audio i inne załączniki multimodalne zaplanowane; A15 |
| R03.12 | Dobrowolne STT push-to-talk i TTS; mikrofon/aparat dopiero po zgodzie | 5 | Zaplanowane: A19; brak zawsze włączonego mikrofonu MVP |
| R03.13 | Wysyłka załączników do wielu AI: jawni odbiorcy i zgoda, brak cichego rozsyłania | 3/4 | Zaplanowane: A20 |

## 4. Technika

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R04.1 | Flutter/Dart Android, Kotlin channels tylko gdy potrzebne | 1/2 | Ograniczone: Flutter/Dart, Kotlin SAF/share/JNI; analiza i pełny build PASS; 5 testów emulatora 0.3.0 PASS, fizyczny telefon do odbioru |
| R04.2 | SQLite utrzymywany, Keystore, feature-first, interfejsy domen | 1/2 | Ograniczone: AppDatabase, SecretStore, moduły i domeny obecne; natywne A02/A05 do odbioru |
| R04.3 | Uzasadnione state/navigation ADR; HTTP timeout/cancel/stream | 1/2 | Potwierdzone w kodzie i ADR 001–004: stan/nawigacja uzasadnione; timeout/cancel/SSE testy PASS |
| R04.4 | Moduły ui, chat, provider_registry, auth, orchestrator, agents, memory, tools, tasks, permissions, costs, notifications, rpg, optional_jarvis_bridge, storage, security, diagnostics | 1–6 | Ograniczone: pełna lista granic w ARCHITECTURE; moduły core i domenowe istnieją, pozostałe jawnie zaplanowane |
| R04.5 | UI→zgody→router→adapter/narzędzie→walidacja→lokalny zapis→odpowiedź | 2/4 | Ograniczone: UI→zgoda→trwały gate→adapter→zapis działa w testach; router i narzędzia zaplanowane |
| R04.6 | Agenci jako role/zadania; brak serwera Python/Termux/kontenerów na telefonie | 4 | Potwierdzone architektonicznie: role i AgentRun, brak procesu serwera Python/Termux/kontenerów w aplikacji |
| R04.7 | Backend tylko opcjonalny: webhooks, 24/7, wieloużytkownikowe sekrety, sync, OPPO | 6 | Potwierdzone w architekturze: brak obowiązkowego backendu; opcjonalne usługi zaplanowane |
| R04.8 | Migracje, atomowość, trwała kolejka, odzyskanie po awarii i konflikty sync | 2/3/6 | Ograniczone: migracje v1/v2→v3, transakcje, wznawialny import z checkpointem po pliku i rewizje kampanii; pełny dispatcher oraz sync/conflicts zaplanowane |
| R04.9 | Start bez sieci, kont, kluczy, OPPO i Obsidiana | 2 | Ograniczone: start bez kont/kluczy/OPPO/Obsidiana oraz rzeczywisty lokalny model offline potwierdzone na emulatorze; fizyczny Pixel 9 do odbioru |

## 5. Orkiestracja

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R05.1 | Asystent→orkiestrator→kierownicy domen→wykonawcy→niezależni kontrolerzy | 4 | Ograniczone: role i plany domenowe; brak połączenia hierarchii z LLM/narzędziami |
| R05.2 | ID/plan/uprawnienia/budżet/model/wykonanie/weryfikacja/raport/opcjonalna pamięć | 4 | Ograniczone: AgentPlan/AgentRun stan i zgoda, bez podłączonego wykonawcy LLM/tools/retrievalu; A13 |
| R05.3 | Domyślnie max 2 korekty; twarde limity czasu/kroków/kosztu/wywołań, stop i wznowienie | 4 | Ograniczone: domenowy BudgetGuard i AgentRun; brak trwałego kompletnego wykonawcy; A13/A16 |
| R05.4 | Domeny: osobiste PL–DE, IT/cyber, badania, GPW, AI, gry/RPG, komunikacja; kontroler każdej | 4/5 | Ograniczone: deklaracje wszystkich domen i kontrolerów w kodzie; realne workflow domen zaplanowane |
| R05.5 | Jawne spory/niepewność, brak wymyślonych cytatów, minimalne uprawnienia | 4 | Zaplanowane: A18, A20 |
| R05.6 | Zgoda przed wiadomością, zmianą pliku, zakupem i ujawnieniem danych | 4/5 | Zaplanowane: A20; żadnych prób na prywatnych kontach bez zgody |

## 6. Pamięć i Obsidian

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R06.1 | Własne SQLite + pliki, indeks/retrieval ograniczony zakresem | 2/3 | Ograniczone: szyfrowane wersje i fragmenty, indeks HMAC oraz SQL filtrujące właściciela/kolekcję/zgodę/rewizję przed rankingiem; retrieval leksykalny, bez embeddingów; testy 0.3.0 |
| R06.2 | Obsidian opcjonalny; import/eksport vault przez SAF z jawnym katalogiem | 3 | Ograniczone: lokalny vault .md/.markdown przez ACTION_OPEN_DOCUMENT_TREE, odczyt domyślny, osobna zgoda na nowy eksport do Scalajaca-Exports; tylko lokalny provider, bez Sync; OBSIDIAN_PAMIEC_RPG_PL.md |
| R06.3 | SYSTEM, INBOX, PERSONAL, RESEARCH, TECH, FINANCE, GAMING, RPG/CAMPAIGNS/id, COMMUNICATIONS, REVIEWS, ARCHIVE | 3 | Ograniczone: podstawowe katalogi notatek istnieją; kampanie w odrębnym agregacie, pełny vault RPG/CAMPAIGNS/id zaplanowany |
| R06.4 | Rekord: ID, właściciel, projekt/kampania, autor/czas/źródło/pewność/zakres/zgoda/wersja/powiązania | 3 | Ograniczone: prywatne wersje źródła/sha256/linie/właściciel/kolekcja/zgoda, manualne checkpointy i osobny audyt kampanii; pełne pola autor/pewność/graf relacji i retencja zaplanowane |
| R06.5 | Kontekst krótki / zatwierdzone fakty długie / dokumenty / stan transakcyjny | 3/4 | Ograniczone: ograniczone okno czatu, zatwierdzone wersje dokumentów, checkpointy analiz i transakcyjny stan kampanii są podłączone; automatyczne streszczanie i semantyczny retrieval zaplanowane |
| R06.6 | Ślad zapisu faktu, korekta, zapomnienie, usuń, eksport, restore | 3 | Ograniczone: reimport tworzy wersję, cofnięcie zgody usuwa indeks, usunięcie kopii kasuje prywatne wersje; audyt i rollback kampanii działają; pełna przenośna kopia nowych danych i retencja zaplanowane |
| R06.7 | Uprawnione fragmenty i preview, poufność; bez wysyłki całego vaultu i indeksowania GM_SECRET | 3/5 | Ograniczone: wybrane fragmenty/preview/digest/receipt, walidacja przed dispatch, brak indeksu GM_SECRET, izolacja kampanii i historii MG/gracz; testy negatywne 0.3.0 PASS; narzędzia agentów i fizyczny Pixel 9 do odbioru |
| R06.8 | Szyfrowane kopie/eksporty; sync tylko dobrowolny | 3/6 | Ograniczone: klasyczny backup AES-GCM obejmuje zwykłe czaty/notatki/zadania, wyklucza czaty zakresowe i nowe projekty/RPG; pełny backup nowej pamięci oraz dobrowolny sync zaplanowane |

## 7. Asystent i narzędzia

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R07.1 | Zadania/przypomnienia/listy/powiadomienia/dokumenty/share/aparat/załączniki | 5 | Ograniczone: lokalna lista zadań i share tekstu/SAF; przypomnienia, powiadomienia, aparat i załączniki modeli zaplanowane |
| R07.2 | Legalne wyszukiwanie internetowe, push-to-talk | 5 | Zaplanowane: A18/A19 |
| R07.3 | Kalendarz/poczta/dysk oficjalne OAuth/API i zakresy za zgodą | 5 | Zaplanowane: A20; brak automatycznego łączenia |
| R07.4 | Lokalny harmonogram best-effort i opcjonalny zdalny; uczciwe ograniczenia Android | 5/6 | Zaplanowane: A23 |
| R07.5 | Uprawnienia powiadomień, bez nadużywania FGS/exact alarms | 5 | Zaplanowane: A19/A23 |
| R07.6 | Trwałe zadanie: status, ostatnie wykonanie, wznowienia, deduplikacja, błędy | 5 | Ograniczone: trwała lista i deduplikowana kolejka szkiców; harmonogram/dispatcher/ostatnie wykonanie zaplanowane |

## 8. Komunikatory i użytkownicy

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R08.1 | Adaptery Discord, Telegram, WhatsApp, Signal z weryfikacją oficjalnego interfejsu przed produkcją | 5 | Zaplanowane; Signal oficjalny bot API niepotwierdzony — niedostępny |
| R08.2 | Discord/Telegram bot, opcjonalny webhook; WhatsApp biznesowy Cloud API i wymagana konfiguracja | 5/6 | Zaplanowane; źródła i ograniczenia w ROADMAP_PL.md |
| R08.3 | Stały odbiór wymagający serwera zależy od opcjonalnego backendu, nigdy OPPO | 6 | Zaplanowane: A24 |
| R08.4 | Właściciel/zaufany/gość/gracz/MG-system i izolacja rozmów/zasobów | 5 | Ograniczone: domenowa polityka ról testowana; produkcyjne profile osób, kanały i mapowanie jeszcze niewdrożone |
| R08.5 | ID kanału, jawne mapowanie osoby, przeciwdziałanie podszyciu | 5 | Zaplanowane: A24 |
| R08.6 | Potwierdzenie działania w cudzym imieniu i wiadomości do osób trzecich | 5 | Zaplanowane: A20/A24 |

## 9. Domeny

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R09.1 | Monitoring AI/technologii/gospodarki/świata/GPW/gier/WFRP; daty/linki/deduplikacja/znaczenie | 5 | Zaplanowane: A18/A22 |
| R09.2 | Edytowalne tickery GPW i pełna zweryfikowana nazwa zawsze razem; raporty, ESPI/EBI, ryzyko | 5 | Zaplanowane: A22; bez transakcji automatycznych |
| R09.3 | WFRP wszystkie edycje i Hamburg: daty/miejsca/format tylko ze źródła | 5 | Zaplanowane: A18/A22 |
| R09.4 | Niemiecki, PL/DE krok po kroku, dokumenty i praca | 5 | Zaplanowane: A22 |
| R09.5 | IT: wymagania/kod/review/testy/ślad zmian; dostęp do repo i zgoda przed zmianą | 5 | Zaplanowane: A20/A22 |

## 10. Osobny silnik RPG

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R10.1 | Moduł osobny; izolowane kampanie: czas/świat/postaci/drużyna/lokacje/przedmioty/frakcje/zadania/kanon/źródła/sekrety | 5 | Ograniczone: CampaignStore SQLite/UI własnych kampanii z kanonem, encjami świata, wiedzą gracza i stanem sesji, ręcznie zatwierdzany kontekst LLM; pełna mechanika/narracja wielosesyjna zaplanowane |
| R10.2 | Audytowalne zdarzenia i rewizje; replay/rollback ze spójnością | 5 | Ograniczone: trwałe zaszyfrowane rewizje, dopisywany audyt i rollback jako nowa rewizja z CAS; test close/reopen i spójność transakcji PASS; wielomiesięczna próba na telefonie niewykonana |
| R10.3 | MG narracja bez podejmowania decyzji za gracza | 5 | Zaplanowane: A25 |
| R10.4 | Agenci czasu/mechaniki/drużyny/NPC/frakcji/wątków/ekwipunku/walki/lokacji/ciągłości/ilustracji | 5 | Zaplanowane: A25 |
| R10.5 | Cele/wiedza/plany/zasoby NPC/frakcji, działania poza sceną, trwałe konsekwencje | 5 | Zaplanowane: A25 |
| R10.6 | Oddzielny stan świata i wiedza bohatera; asynchroniczna ilustracja nie blokuje sesji | 5 | Ograniczone: odrębne encje świata, kanon i wiedza gracza oraz tajny checkpoint MG; widok gracza filtruje przed odczytem; asynchroniczne ilustracje zaplanowane |
| R10.7 | Lore: koordynator, oficjalny kanon/podręczniki, chronologia/geografia, frakcje/kultury, bestiariusz/magia, lokalny kanon, niezależny kontroler stron/źródeł | 5 | Ograniczone: wszystkie role lore zadeklarowane; kontrolerzy LLM i źródła podręczników niepodłączone |
| R10.8 | Hierarchia kanonu: kampania→właściwa edycja oficjalna→oznaczone pomocnicze; brak źródła = niezweryfikowane | 5 | Ograniczone: podłączony ręcznie zatwierdzany retrieval kampanii przestrzega hierarchii i edycji; źródło bez osobistej weryfikacji jest NIEZWERYFIKOWANE; niezależny recenzent LLM zaplanowany |
| R10.9 | GM_SECRET nigdy w widoku gracza, logach, promptach recenzenta, indeksie ani eksporcie | 5 | Ograniczone: SQL i testy gracz/recenzent/indeks/eksport fail-closed, sekrety tylko po wyborze MG, odrębne scope historii; eksport i clipboard/share czatu MG zablokowane; lokalny filtr roli nie jest logowaniem gracza |
| R10.10 | WFRP 4e k100/PS, tylko reguły z materiałów właściciela; bez wymyślonych talentów | 5 | Zaplanowane; zależne od zweryfikowanych źródeł |
| R10.11 | Fio tylko import z potwierdzonych plików; brak zgadywania/resetu/startu; osobne wfrp 3 | 5 | Zaplanowane: A25; plików kanonu nie dostarczono |
| R10.12 | Wersjonowany katalog/manifest kampanii, np. zoo.json po akceptacji formatu | 5 | Ograniczone: wersjonowany CampaignManifest w kodzie; tworzenie plikowego katalogu kampanii i akceptacja formatu zaplanowane |

## 11. Opcjonalny JARVIS

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R11.1 | Wymienny JarvisBridge domyślnie wyłączony | 6 | Ograniczone: interfejs i wyłączony wariant domenowy; realny transport/parowanie zaplanowane, A06 |
| R11.2 | Bezpieczne parowanie, mutual auth, TLS/VPN, wybór praw, selektywny sync/delegacja, revoke | 6 | Zaplanowane: A06/A20 |
| R11.3 | Bez założeń o publicznym IP/AnyDesk/Termux/usługach OPPO; awaria nie blokuje UI/czatu/pamięci | 6 | Ograniczone: core nie importuje działającego mostu, działa w testach bez OPPO; test odłączenia realnego transportu po jego wdrożeniu |

## 12. Prywatność i koszty

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R12.1 | Kontrola odbiorców, blokada danych osobistych dla recenzentów, potwierdzenie wielu AI | 2/4 | Ograniczone: jawni odbiorcy/prompt i zawsze zgoda wielu AI; polityka recenzentów zapisana, recenzent niewdrożony |
| R12.2 | Tryb prywatny i zapisuj/nie zapisuj; minimalne uprawnienia i ochrona sekretów | 2/3 | Ograniczone: nowe prywatne rozmowy ChatSession w RAM, przełącznik UI i bezpieczne klucze; lifecycle/Android A05/A20 do odbioru |
| R12.3 | Separacja profili/projektów/kampanii, szyfrowanie danych wrażliwych/backupów | 2/3/5 | Ograniczone: szyfrowane projekty/kampanie i scope czatów są podłączone oraz testowane; pełne profile osób, backup nowej pamięci i natywny audyt Keystore pozostają do odbioru |
| R12.4 | Bez promptów/kluczy w logach bez zgody; prompt injection źródła ≠ instrukcje | 2/4 | Potwierdzone dla aktywnego kodu: brak logowania treści/kluczy, import odrzuca rolę systemową, obrazy Markdown nie pobierają zasobów; przyszłe tools wymagają odrębnej ochrony |
| R12.5 | Użycie model/dostawca/zadanie; estymata przed multi; usage rzeczywiste gdy API zwraca | 4 | Ograniczone: etykiety modelu/dostawcy, rezerwa i usage tokenów gdy API je zwróci; brak pełnej analityki zadań i rachunku USD |
| R12.6 | Budżet dzień/miesiąc, kroki, historia, alerty, lokalna blokada nowych płatnych zadań | 4 | Ograniczone: trwałe konserwatywne rezerwy LocalCostGate i domenowy BudgetGuard; pełna analityka/alerty i rozliczenie rzeczywistych cen zaplanowane; A26 |
| R12.7 | Fallback tylko zgoda/polityka; brak opłat i łączenia kont przy instalacji | 2/4 | Potwierdzone w aktywnym kodzie/testach: API domyślnie wyłączone, bez automatycznego fallbacku, kont i wywołań przy starcie |

## 13. Ekrany MVP

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R13.1 | Onboarding: prywatność, bez konta, import/eksport, dostawca | 2 | Ograniczone: dialog startowy demo i wskazówki do Ustawień; pełny wizard UX zaplanowany |
| R13.2 | Dostawcy: karta/status/logowanie/test/model domyślny | 2/3 | Ograniczone: ProviderSettings klucz/model/stawki/katalog; realne SSO niedostępne, A03/A08 |
| R13.3 | Historia i czat streaming/cancel | 2 | Ograniczone: kod Home/ChatSession obecny, wyniki home_test/transportu w TESTS_PL.md; A02/A03 na Android do odbioru |
| R13.4 | Porównanie odpowiedzi/koszt | 4 | Ograniczone: eksperymentalny ekran Comparison, wyniki RAM i rezerwa kosztu, A04 |
| R13.5 | Pamięć katalogi/search/notatka/share/import | 3 | Ograniczone: lokalne notatki/folder/search/MD; SAF/share wymagają natywnej weryfikacji A14/A15 |
| R13.6 | Agenci/zadania: plan/status/budżet/potwierdzenia | 4/5 | Ograniczone: lista zadań działa, ekran agentów opisuje stan eksperymentalny; plan/wykonawca LLM w UI zaplanowany |
| R13.7 | Ustawienia: bezpieczeństwo/eksport/język/motyw/zgody/opcjonalne integracje/diagnostyka | 2/3/6 | Ograniczone: motywy/zgody/backup/providers i licencje istnieją; pozostałe integracje i języki zaplanowane |

## 14. Etapy i jakość

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R14.0 | Oficjalna weryfikacja z datą/linkami; macierz konsument/API/OAuth/abonament/zgody/koszt/status | 0 | Potwierdzone dokumentacyjnie: datowana macierz czterech AI i źródła Android/komunikatorów/pakietów |
| R14.1 | Repo, README PL, ADR, licencje, katalogi, typy/diagram, kompatybilne libs, UX/akceptacja | 1 | Potwierdzone plikami: README, ADR, architektura, UX, akceptacja, lockfile i notices; natywny odbiór pozostaje osobny |
| R14.2 | Flutter Android, SQLite, historia, realny adapter BYOK + drugi, demo, stream/cancel/settings/errors | 2 | Ograniczone: core i 193 Flutter PASS; APK oraz 5 scenariuszy emulatora offline PASS; live API i fizyczny telefon niewykonane |
| R14.3 | 4 adaptery, magazyn sekretów, uczciwe SSO, share i MD, Obsidian opcjonalny | 3 | Ograniczone: cztery transporty + Keystore + SAF/share/MD/backup i lokalny vault 0.3.0; SSO i synchronizacja zaplanowane |
| R14.4 | Auto/compare/review/arbiter/role/budżety/limity/decyzje i testy przecieków | 4 | Ograniczone: porównanie, gate budżetów, domena agentów/ACL i testy; Auto/konsensus/arbiter/wykonawca zaplanowane |
| R14.5 | Asystent/notyfikacje/głos/search/monitoring/GPW/gry/nauka/RPG/kanały | 5 | Zaplanowane: A18–A25 |
| R14.6 | Bezpieczny backend webhook/24h, OPPO, sync, AAB, bateria/a11y | 6 | Zaplanowane: A06/A12/A21/A24 |
| R14.7 | Każda faza: kod→lint→unit/widget/integration→urządzenie jeśli dostępne→fakty→poprawki→docs | wszystkie | Ograniczone: 0.3.0 analyze bez uwag, 193 Flutter i 27 JUnit PASS; szczegóły APK/emulatora w aktualnym TESTS_PL.md; fizyczny Pixel 9 i pozostałe kryteria otwarte |
| R14.8 | Zgoda przed destrukcją, płatnym kontem, publikacją i wiadomościami | wszystkie | Wymaganie obowiązuje; brak takich autoryzacji w bieżącym zakresie |

## 15. Odbiór końcowy

| ID | Kryterium specyfikacji | Test | Status |
|---|---|---|---|
| R15.1 | Samodzielne uruchomienie Android | A01 | Ograniczone: źródła, host demo i APK build PASS; instalacja/start emulatora x86_64 PASS, telefon do odbioru |
| R15.2 | Rozmowa→restart→search→eksport | A02/A07 | Ograniczone: plik SQLite close/reopen/search i transfery testowane; pełny lifecycle oraz SAF na Androidzie do odbioru |
| R15.3 | Prawdziwe API stream/cancel i czytelne błędy | A03/A16 | Ograniczone: 37 mock testów API/SSE/cancel/błędów PASS; live wymaga zgody i konfiguracji |
| R15.4 | Niezależne adaptery/compare/źródło/koszt | A04 | Ograniczone: niezależne transporty i eksperymentalne porównanie; realny rachunek/lifecyle niepotwierdzone |
| R15.5 | Brak kluczy w logach/repo; auth/separacja/encryption testy | A05/A09 | Ograniczone: testy zgód/sekretów/separacji/szyfrowania PASS; natywny Keystore i audit APK do odbioru |
| R15.6 | Odłączenie OPPO nie wpływa na core | A06 | Ograniczone: brak zależności od mostu w core; realny transport wyłączony/niewdrożony |
| R15.7 | MD bez Obsidiana, brak utraty po restarcie | A02/A07 | Ograniczone: Markdown i trwałość SQLite testowane na hoście; rzeczywisty systemowy import vaultu i źródło MiniCPM na emulatorze PASS; pełny lifecycle/eksport vaultu i telefon do odbioru |
| R15.8 | Uczciwe statusy integracji i brak obchodzenia | A08 | Potwierdzone w dokumentacji/kodzie: oficjalne API i uczciwe statusy; bez sesji i Accessibility |
| R15.9 | RPG izolacja i niewymyślający źródeł weryfikator | A09/A18/A25 | Ograniczone: trwałe RPG i negatywne testy izolacji/źródeł/scope historii PASS; pełna gra, weryfikator LLM i jakość długiej narracji niepotwierdzone |
| R15.10 | Raport plików/testów/ograniczeń/instalacji/kolejnego kroku | A10 | Potwierdzone dokumentacyjnie: raport testów, stan realizacji, instrukcja, lista plików i następny etap |

## 16. Sposób dostarczenia

| ID | Pełny zakres do sprawdzenia | Faza | Status / dowód odbioru |
|---|---|---:|---|
| R16.1 | Podsumowanie samodzielnego Android, opcjonalne OPPO, integracje, architektura, ryzyka, kolejność | 0/1 | Weryfikacja w raporcie końcowym prowadzącego |
| R16.2 | Rzeczywista implementacja 1/2 w bieżącym zadaniu, bez zbędnych pytań | 1/2 | Potwierdzone kodem: rzeczywisty Flutter/Android, 193 testy Flutter, 27 JUnit i 5 scenariuszy emulatora PASS; dalsze ograniczenia jawne |
| R16.3 | README_PL, ARCHITECTURE, INTEGRATIONS_MATRIX, SECURITY, PRIVACY, ADR, SETUP_ANDROID_PL, TESTS_PL, ROADMAP_PL | 1/2 | Potwierdzone plikami wymaganych dokumentów, ADR i pełnej macierzy |
| R16.4 | Flutter/config bez sekretów/migracje/testy/build scripts/CHANGELOG/IMPLEMENTATION_STATUS | 2 | Potwierdzone plikami: kod/config bez sekretów, migracje, testy, skrypt, changelog i stan |
| R16.5 | Debug APK i instrukcja dopiero po rzeczywiście udanym buildzie | 2 | Potwierdzone: debug APK 0.3.0 ARM64+x86_64, build/podpis/manifest/wyrównanie PASS, SHA-256 i instrukcja; fizyczny Pixel 9 nieprzetestowany |

Nie ma domniemania ukończenia wymagań kolejnych faz. Kolejna aktualizacja tej macierzy powinna podnosić status wyłącznie dla konkretnych dowodów; dokumentacja projektu UX nie jest testem aplikacji.
