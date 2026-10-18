# Plan realizacji i dostępność rozszerzeń

## Etap 0.3.0 — lokalny vault i fundament trwałej kampanii

Wdrożono lokalny SAF, wznawialny import Markdown, szyfrowane wersje/chunki, zatwierdzanie, indeks słów HMAC, retrieval wybranych fragmentów, trwałe punkty analiz oraz SQLite/UI kampanii z audytem/cofaniem. Czat ma ograniczony snapshot i dowód źródeł, osobne zakresy projektu/kampanii/roli. Szczegóły i granice w OBSIDIAN_PAMIEC_RPG_PL.md.

Najbliższe prace: odbiór na fizycznym Pixel 9 (RAM/bateria/termika), pełna przenośna kopia nowych projektów i RPG, retencja wersji, stronicowanie wszystkich starszych list, pomiary dużego prawdziwego vaultu, embeddingi/graf źródeł, kontroler sprzeczności i test wielosesyjnego lore. Następnie trwałe workflow agentów i harmonogram best-effort. Synchronizacja pozostaje dobrowolnym przyszłym rozszerzeniem, z rewizjami i rozwiązywaniem konfliktów przed uruchomieniem. Starsze plany poniżej zachowują zakres pierwotnej specyfikacji.

Rozszerzenie 0.2.0 (18.10.2026): wdrożono lokalny silnik CPU/JNI, import GGUF i osobny adapter offline. 141 testów Flutter, 21 JUnit i generacja rzeczywistych wag na hoście przeszły; przygotowano nowy APK. Następny odbiór: fizyczny Android w trybie samolotowym, JNI/SAF/Keystore, Stop/tło/termika, pomiar RAM/baterii i jakości PL. Serwer pozostaje opcjonalny. Rzeczywisty 2B, GPU/NPU, downloader, MiniCPM-V/audio oraz narzędzia są zaplanowane. Pozostałe 129 wymagań specyfikacji nadal obowiązuje.

Stan planu: **17.10.2026**. Pełny zakres 17 sekcji specyfikacji jest śledzony w `REQUIREMENTS_TRACEABILITY_PL.md`. Kolejność wynika z samodzielności telefonu, kontroli danych i kosztów. Ten dokument nie oznacza ukończenia etapów.

| Faza | Rezultat | Warunek odbioru | Status planu |
|---|---|---|---|
| 0 | Oficjalna macierz OpenAI/Claude/Gemini/xAI, Android i zależności | Daty/linki; logowanie ≠ plan ≠ API; brak obchodzenia sesji | Weryfikacja dokumentacyjna |
| 1 | Repo Flutter/Android, ADR, modularność, UX, testy, licencje, model zagrożeń | Rzeczywiste pliki i decyzje | Dostarczono; analiza bez problemów i 83 testy hosta PASS |
| 2 | Demo lokalne, SQLite historia/szkice, streaming/cancel, niezależne adaptery BYOK, błędy i bezpieczne klucze | Analiza i testy; build APK i instalacja jeśli narzędzia dostępne | Implementacja i 83 testy hosta PASS; build debug przeszedł, instalacja/live API niezweryfikowane |
| 3 | Cztery API, uczciwy punkt SSO, Sharesheet, SAF, MD/JSON i szyfrowany backup, własna pamięć | Roundtrip/restart/crypto/Keystore; Obsidian niepotrzebny | Zaplanowane poza częścią aktualnego MVP |
| 4 | Auto, porównanie, konsensus/arbiter, domeny/kontrolerzy, budżety i limity, rejestr zgód/decyzji | Twarde limity i testy przecieków; jawny zakres danych | Zaplanowane poza częścią aktualnego MVP |
| 5 | Zadania/przypomnienia/notyfikacje, push-to-talk/TTS, wyszukiwanie i monitoring, GPW/ESPI/EBI, nauka PL–DE, IT, odrębne RPG, kanały | Pozwolenia przy użyciu, best-effort Android; RPG izolacja i kanon | Zaplanowane; źródła/zgody i kanon częściowo niedostarczone |
| 6 | Opcjonalny backend webhook/24h, mutual-auth JarvisBridge, sync i konflikty, AAB, bateria/a11y | Samodzielny core po odłączeniu rozszerzeń; zgoda przed publikacją | Zaplanowane |

## Android: oficjalne możliwości

Weryfikacja 17.10.2026, źródła pierwotne:

- [Android Sharesheet](https://developer.android.com/develop/ui/compose/sharing/send): oficjalne `ACTION_SEND` i chooser oraz binarne URI; dla wielu plików `ACTION_SEND_MULTIPLE`. Zapewnia świadomą ręczną wysyłkę do zainstalowanej aplikacji, nie dostęp do jej abonamentu ani automatyczne odebranie odpowiedzi. Zaplanowane: natywny kanał/utrzymywany plugin, MIME, FileProvider, chwilowe prawa URI, test powrotu/anulowania.
- [Storage Access Framework](https://developer.android.com/guide/topics/providers/document-provider): systemowy wybór pliku (`ACTION_OPEN_DOCUMENT`), nowego dokumentu (`ACTION_CREATE_DOCUMENT`) i katalogu (`ACTION_OPEN_DOCUMENT_TREE`). Import/eksport vault nie wymaga Obsidiana ani szerokiego dostępu do pamięci. Zaplanowane: trwały grant wyłącznie dla wskazanego katalogu, revoke, podgląd konfliktu i plików przed importem.
- [WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent): trwałe zadania z constraintami, retry i rescheduling po restarcie. Android stosuje ograniczenia energii; [harmonogram cykliczny](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work#schedule_periodic_work) ma minimalny okres 15 minut i elastyczne okno, nie dokładną godzinę. Wniosek projektowy: lokalne przypomnienia/monitoring są best-effort, ciągły odbiór kanałów potrzebuje opcjonalnego stale dostępnego backendu. Nie deklarujemy niezawodności 24/7 telefonu.

## Komunikatory: stan oficjalnej weryfikacji

Żaden adapter komunikatora nie jest w bieżącym etapie deklarowany jako działający. Nie podłączono kont ani botów i nie wysłano wiadomości. „Zależny od backendu” dotyczy rozszerzenia odbioru, nigdy zwykłego czatu.

| Kanał | Oficjalna droga i ograniczenia | Status w Scalającej | Źródło zweryfikowane 17.10.2026 |
|---|---|---|---|
| Discord | Aplikacja/bot, REST i Gateway WebSocket; uprawnienia/intents i ewentualne zatwierdzenia do treści. Webhook wejściowy nie jest czytnikiem wszystkich rozmów. Stabilny odbiór przez Gateway/webhook wymaga opcjonalnej stale dostępnej usługi. Bez self-bota prywatnego konta. | Zaplanowane; wymaga konfiguracji bota i uprawnień | [Developer Platform](https://docs.discord.com/developers/intro), [Gateway](https://docs.discord.com/developers/events/gateway), [OAuth2](https://docs.discord.com/developers/topics/oauth2), [zmiana ochrony danych 2026](https://discord.com/blog/updated-requirements-to-how-apps-access-data-in-servers) |
| Telegram | Oficjalny Bot API przez HTTPS; `getUpdates` long polling albo `setWebhook` są wzajemnie wykluczające się. ID aktualizacji służy deduplikacji; bot nie przejmuje prywatnego konta. | Zaplanowane; wymaga osobnego bota, tokenu i jawnego mapowania rozmów; backend opcjonalny dla stałego odbioru | [Bot API](https://core.telegram.org/bots/api), [webhooks](https://core.telegram.org/bots/webhooks) |
| WhatsApp | Oficjalne WhatsApp Business Platform / Cloud API, Meta business portfolio, WABA i numer biznesowy, access token oraz webhook. Nie obiecujemy przejęcia dowolnego konsumenckiego WhatsApp. Wymagania/polityki/ceny sprawdzić ponownie przed wdrożeniem. | Zaplanowane; wymaga konfiguracji i właściwych zgód; brak produkcyjnego adaptera | [oficjalna kolekcja Meta](https://www.postman.com/meta/whatsapp-business-platform/collection/wlk6lh4/whatsapp-cloud-api), [Meta: platforma biznesowa](https://about.fb.com/news/2022/05/announcing-new-products-to-make-business-messaging-easier/), [docelowa dokumentacja](https://developers.facebook.com/docs/whatsapp/cloud-api/overview) |
| Signal | Oficjalna dokumentacja publikuje protokoły i biblioteki kryptograficzne; nie znaleziono w niej zatwierdzonego bot API. To ograniczenie weryfikacji, nie twierdzenie, że żaden mechanizm nigdy nie powstanie. Nie traktować signal-cli ani bibliotek protokołu jako oficjalnego API bota. | Niedostępny jako oficjalny adapter bota; zaplanowany tylko punkt rozszerzenia i ręczne udostępnianie, gdy aplikacja systemowo je przyjmuje | [Signal Documentation](https://signal.org/docs/) |

Uwaga do audytu źródeł Meta: bezpośrednia strona developer documentation zwracała błąd w narzędziu przeglądania. Zakres potwierdzono oficjalną kolekcją publikowaną przez Meta i komunikatem Meta; szczegóły produkcyjne pozostają do ponownej weryfikacji przed implementacją. Nie wykorzystano porad z forów do ustalania wymagań.

## Zależności między modułami

Pamięć wymaga lokalnych zapisów i polityki zakresów; agentowość wymaga uprzednio niezależnych adapterów, anulowania i kontroli kosztów. Akcje asystenta wymagają egzekwowanej zgody, a nie jedynie etykiety w UI. RPG wymaga autoryzacji na poziomie danych i testów GM_SECRET przed podłączeniem jakichkolwiek modeli. Kampania Fio wymaga dostarczonych i potwierdzonych materiałów; bieżący kod nie może zawierać zgadywanego kanonu. Osobna kampania wfrp 3 pozostaje osobna.

Katalogi pamięci i domeny ze specyfikacji nie zostają usunięte z zakresu, nawet jeśli MVP udostępnia jedynie ich podstawę. Model offline, sync wielourządzeniowy, pełna mechanika WFRP 4e, stały odbiór komunikatorów oraz 24/7 nie są obietnicą obecnego wydania.

## Bramka przed kosztami i publikacją

Najpierw lokalne testy z atrapami. Live API oraz przyłączenie prywatnego konta dopiero po wyraźnej zgodzie właściciela na konkretny zakres. Publikacja AAB/sklep i wysyłka wiadomości to kolejne osobne decyzje. Debug APK nie jest publikacją, ale jego istnienie wymaga udanego builda. Wersja produkcyjna musi dodatkowo przejść test Android Keystore, lifecycle, dostępności, migracji, odzyskiwania danych i zachowania Doze.
