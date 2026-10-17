# MiniCPM w Scalającej

Przegląd oficjalnych źródeł: 17.10.2026. Wersja aplikacji: 0.1.1.

**Zaimplementowany jest opcjonalny klient własnego serwera HTTPS. Wbudowana inferencja na Androidzie pozostaje zaplanowana.** Aplikacja nadal uruchamia się i obsługuje dane lokalne bez serwera, OPPO, JARVIS i Termuxa. Wybranie MiniCPM nie uruchamia pobierania modelu ani połączenia.

## Zweryfikowane możliwości i licencje

[OpenBMB MiniCPM](https://github.com/OpenBMB/MiniCPM) udostępnia tekstowe modele MiniCPM5-1B i MiniCPM5-2B. Oficjalny [poradnik llama.cpp](https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/llama_cpp.md) opisuje GGUF oraz interfejs `/v1/chat/completions`. Karty [1B GGUF](https://huggingface.co/openbmb/MiniCPM5-1B-GGUF) i [2B GGUF](https://huggingface.co/openbmb/MiniCPM5-2B-GGUF) wskazują Apache-2.0. Nie przenosimy tego założenia na wszystkie starsze wydania. Wagi, kod modeli i silnik nie są dołączone ani rozpowszechniane z tym APK. Własny adapter napisano w Dart bez kopiowania kodu OpenBMB.

Warianty Q4_K_M mają według wydawcy około 657 MB (1B) i 1,56 GB (2B). To rozmiar pliku, nie całkowite wymaganie RAM. Rozmiar kontekstu deklarowany przez model nie stanowi obietnicy działania takiego kontekstu w telefonie. Obsługa polskiego i jakość odpowiedzi wymagają pomiaru; karty eksponują angielski i chiński. MiniCPM-V oraz modele audio to odrębne integracje, niewdrożone przez ten adapter tekstowy.

## Konfiguracja istniejącego własnego serwera

1. W Ustawienia → Dostawcy AI rozwiń „MiniCPM • własny serwer”.
2. Wpisz adres, np. `https://ai.example.org/v1`. Akceptujemy bazę domeny albo `/v1`, z opcjonalnym portem. Ścieżki proxy inne niż `/v1` nie są obsługiwane. Certyfikat musi być zaufany przez Androida. Nie wyłączamy TLS; HTTP, dane logowania i tokeny w URL są odrzucane.
3. Podaj ID/alias modelu faktycznie udostępnionego przez serwer. Nie zakładamy, że każdy model z katalogu jest MiniCPM. Katalog i nazwa nie dowodzą tożsamości wag; odpowiada za nie właściciel serwera.
4. Jeśli serwer wymaga klucza API, wpisz go w osobnym polu. Jest przechowywany w Keystore, nie w adresie i nie w SQLite. Puste pole zachowuje klucz przy tym samym adresie. Zmiana adresu usuwa poprzedni klucz, jeżeli nie wprowadzono nowego.
5. Wprowadź stawki USD za milion tokenów. Dla własnego serwera bez opłat za wywołania ustaw obie stawki 0 i jawnie zaznacz deklarację. Zmiana adresu zeruje zaznaczenie. To deklaracja użytkownika, nie audyt rozliczeń; hosting i energia mogą kosztować. Nie odblokowuje płatnych API. Jeśli serwer nalicza opłaty, obowiązują zwykłe limity i osobne włączenie API.
6. Zapis nie łączy się z siecią. „Test / katalog” po osobnym potwierdzeniu wysyła `GET /v1/models` do zapisanego adresu, bez promptu i bez generacji. Nie dowodzi działania wybranego modelu.
7. W czacie wybierz MiniCPM. Potwierdzenie pokazuje adres, model, zakres rozmowy, treść i koszt. W porównaniu otrzymuje tylko wspólny prompt; historia i odpowiedzi innych kart nie są dołączane.

Domyślny profil żądania: tekst/SSE, 1024 tokeny wyjścia, temperatura 0,7, top-p 0,95, min-p 0,0, prośba szablonu o `enable_thinking:false`. Jest zbliżony do profilu No-think MiniCPM5-1B; zgodność z innym modelem/szablonem wymaga sprawdzenia. Parametry nie są gwarancją zachowania serwera. `reasoning_content` nie trafia do odpowiedzi. Adapter nie wysyła definicji narzędzi i odrzuca `tool_calls`; nigdy ich nie wykonuje.

Oficjalny `llama-server` domyślnie pokazany w dokumentacji działa przez HTTP. Do tego adaptera potrzebny jest świadomie skonfigurowany zaufany terminator TLS albo obsługiwany przez wybraną wersję serwera TLS. Nie konfigurujemy infrastruktury ani nie otwieramy portów automatycznie. Adres `localhost` w telefonie oznacza telefon, nie komputer. Nie udostępniono żadnego publicznego serwera testowego.

## Granice bezpieczeństwa i rzeczywiste testy

Brak przekierowań, automatycznego retry, obchodzenia błędów certyfikatu i przechwytywania sesji. Klucz trafia tylko do jawnie skonfigurowanego odbiorcy HTTPS. Domyślne timeouty: 30 s nagłówki, 45 s bezczynności, 5 min całość. Stop przerywa transport; nie gwarantuje cofnięcia pracy/rachunku serwera. Brak `[DONE]`, niepoprawny protokół i zakończenie limitem są raportowane jako niepełne odpowiedzi. Body błędu nie jest wyświetlane ani logowane.

Testy używają atrap HTTP i lokalnego SQLite. Nie uruchomiono realnego serwera MiniCPM, nie pobrano wag, nie zalogowano kont i nie wykonano płatnej generacji. Aktualne wyniki są w [TESTS_PL.md](TESTS_PL.md).

## Następny etap: model bezpośrednio w telefonie

Docelowy niezależny moduł `local_inference`: llama.cpp przez natywne JNI/FFI, bez serwera HTTP, dobrowolny import/pobranie GGUF do prywatnego magazynu aplikacji, kontrola SHA-256 i pochodzenia, usuwanie zasobów, limit RAM/kontekstu i temperatury urządzenia, przerwanie inferencji. Bez automatycznego fallbacku do chmury. [Oficjalny binding Android llama.cpp](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md) potwierdza taką ścieżkę.

W obecnym środowisku próby dostępu do GitHub przez git i PowerShell zostały zablokowane na poziomie sieci/DNS. Oficjalną dokumentację sprawdzono narzędziem przeglądania. Nie ma pobranych źródeł silnika ani pomiarów na telefonie, dlatego nie deklarujemy działającego lokalnego LLM. Etap odbioru wymaga przypięcia wersji/hasza llama.cpp, kompilacji ARM64, testów importu uszkodzonych modeli i realnej generacji na urządzeniu z dostępnymi zasobami.
