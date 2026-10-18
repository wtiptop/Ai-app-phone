# MiniCPM offline w Scalającej 0.2.1

Stan: **18.10.2026**. APK zawiera prawdziwy silnik llama.cpp CPU połączony przez JNI. Generacja odbywa się w procesie Androida, bez serwera, Termuxa, OPPO, konta, klucza API i automatycznego fallbacku do sieci. **Na Androidzie 11 / API 30 x86_64 w emulatorze wykonano rzeczywistą generację i import SAF bez sieci. Test fizycznego telefonu ARM64 pozostaje niewykonany.** Funkcja jest eksperymentalna.

## Pierwsze uruchomienie na telefonie

1. Zainstaluj `Scalajaca-0.2.1-debug-arm64-x64.apk` zgodnie z [instrukcją](SETUP_ANDROID_PL.md). Wymagany Android 7+ i procesor ARM64. Wagi nie są częścią APK.
2. Skopiuj na telefon pobrany za zgodą właściciela `MiniCPM5-1B-Q4_K_M.gguf`. Oficjalny przypięty plik: [OpenBMB na Hugging Face](https://huggingface.co/openbmb/MiniCPM5-1B-GGUF/resolve/3d55fac80935ae6456986ad2384b5cbcc4d6c948/MiniCPM5-1B-Q4_K_M.gguf). Nie wymaga logowania ani płatnego API. Aplikacja sama go nie pobiera.
3. Ustawienia → Dostawcy AI → **MiniCPM offline** → zarządzanie modelami. Wklej zalecane SHA-256 podane poniżej, wybierz **Importuj plik GGUF** i wskaż lokalny plik w systemowym selektorze. Użyj lokalnej pamięci telefonu; dostawca plików chmurowych w SAF może potrzebować internetu do samego udostępnienia pliku.
4. Poczekaj na skopiowanie, sprawdzenie struktury i hasha. Pozostań na ekranie podczas importu. Zaimportowany model jest wybierany do czatu. Można anulować import, skopiować hash lub usunąć prywatną kopię; oryginał pozostaje w swoim katalogu.
5. W czacie wybierz **MiniCPM offline**, wpisz krótki prompt i zatwierdź **Uruchom offline**. Zgoda wskazuje telefon jako miejsce przetwarzania i koszt API 0. Nie włączaj płatnego API. Na pierwszy test nadaje się `Reply with only the single word: OK`.
6. Sprawdź tę samą generację w trybie samolotowym. Stop przerywa obliczenia. Przejście aplikacji w tło też je zatrzymuje. Szczegóły odbioru emulatora i jego granice opisuje TESTS_PL.md; fizyczny telefon nadal wymaga testu.

Model testowy: **688 065 920 bajtów**, około **656,2 MiB** (wydawca podaje około 657 MB).

```text
SHA-256: 81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa
Repozytorium: openbmb/MiniCPM5-1B-GGUF
Rewizja: 3d55fac80935ae6456986ad2384b5cbcc4d6c948
```

Import wymaga miejsca na kopię w prywatnych danych aplikacji i 256 MiB rezerwy. Jeśli pozostawisz oryginał w Pobranych, oba pliki zajmują miejsce. Wagi są zwykłym publicznym modelem; rozmowy nadal podlegają szyfrowaniu/trybowi prywatnemu. Model nie jest dołączany do zaszyfrowanej kopii historii. Po ponownej instalacji lub przeniesieniu danych może wymagać ponownego importu; hash w ustawieniach nie zastępuje pliku.

## Zakres i limity

Obsługiwane są wyłącznie tekstowe **MiniCPM5-1B i MiniCPM5-2B** w pojedynczym GGUF v2/v3 o rozpoznanym profilu. Test prawdziwych wag dotyczy **1B Q4_K_M**. Profil 2B i jego przypięty szablon mają testy strukturalne, ale nie pobrano ani nie uruchomiono pełnych wag 2B. MiniCPM-V, audio, narzędzia, starsze rodziny, modele dzielone na pliki i pozostałe kwantyzacje nie są obsługiwane. Preflight dopuszcza F32/F16/BF16/Q8_0/Q4_K/Q6_K, w tym mieszaną Q4_K_M; zgodność każdej kombinacji wymaga osobnego testu.

Domyślny kontekst: 2048 tokenów, do wyboru 1024 lub 4096. Maks. 512 nowych tokenów, 128 wiadomości, 64 KiB wejścia JSON, do 4 wątków CPU i 3 min całej inferencji. Zbyt długa historia jest odrzucana bez cichego usuwania wiadomości. Odpowiedź zakończona limitem jest oznaczana jako niepełna. Brak automatycznych ponowień.

Przed startem sprawdzamy niski stan RAM oraz dostępność co najmniej rozmiaru wag + 320 MiB. To konserwatywna bramka wstępna, nie pomiar szczytowego zużycia i nie gwarancja braku OOM. Po zakończeniu zwalniane są wagi i KV; kolejne pytanie ponownie ładuje model. Stan termiczny co najmniej SEVERE blokuje/zatrzymuje generację (Android 10+). Obecny wariant używa przenośnego CPU; brak GPU/NPU, usługi tła i obietnicy 24/7. Wydajność, RAM, bateria i nagrzewanie na telefonie wymagają pomiaru.

**Jakość polskiego nie jest potwierdzona.** Pierwszy krótki prompt po polsku na hoście dał słabą, rozwlekłą odpowiedź i doszedł do limitu 128 tokenów. Nie był to pozytywny test jakości. Końcowy test techniczny po angielsku zwrócił `OK` i zakończenie `stop`. Nie należy traktować małego modelu jako zweryfikowanego źródła faktów, specjalisty ani narzędzia wykonującego działania.

## Silnik, pochodzenie i bezpieczeństwo

Ścieżkę GGUF opisuje [oficjalny poradnik MiniCPM](https://github.com/OpenBMB/MiniCPM/blob/main/docs/deployment/llama_cpp.md), a budowanie natywne Androida — [llama.cpp Android](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md). Kod silnika jest przypięty do **5aeac37a35b44fde4bdffaec9159f2fcb253b622**. `third_party/llama.cpp/UPSTREAM.json` i `FILE_SHA256.json` zapisują źródło oraz pełne sumy plików. Lokalny audyt porównał 1818 plików z obiektami Git przypiętego commitu.

llama.cpp/ggml: MIT; parser JSON: MIT; przypięte szablony OpenBMB: Apache-2.0. Zachowano oryginalne licencje w źródłach i `assets/native_notices.txt`, widocznym w ekranie licencji aplikacji. Wagi pobrano osobno za zgodą właściciela; karty [1B GGUF](https://huggingface.co/openbmb/MiniCPM5-1B-GGUF) i [2B GGUF](https://huggingface.co/openbmb/MiniCPM5-2B-GGUF) wskazują Apache-2.0. Nie rozszerzamy tej deklaracji na inne wydania.

Importer sprawdza granice metadanych/tensorów, kwantyzacje, rozmiar, nakładanie zakresów i oczekiwany hash. Nie jest to certyfikat bezpieczeństwa natywnego parsera. Nazwa i metadane nie dowodzą autentyczności modelu; używaj oficjalnego pliku i hasha. Szablon z importowanego GGUF jest ignorowany. Używamy wyłącznie przypiętych szablonów `MiniCPM5-1B.jinja` / `MiniCPM5-2B.jinja` wraz z rewizjami i hashami w `templates/PROVENANCE.json`. Treści wejściowe nie są traktowane jako specjalne tokeny protokołu. W silniku wyłączono logowanie llama/ggml i nie linkowano kodu HTTP z `common`. Model nie otrzymuje dostępu do notatek, plików, narzędzi ani innych rozmów.

## Osobny opcjonalny adapter serwerowy

**MiniCPM • własny serwer** z 0.1.1 pozostaje osobną opcją. Wymaga ręcznego adresu HTTPS (baza domeny albo `/v1`, zaufany TLS, bez credentials/query/fragmentu), ID modelu oraz opcjonalnego klucza Keystore. Zapis konfiguracji nie wysyła żądania. Test/katalog po zgodzie pobiera `/v1/models`, bez generacji. Deklaracja własnego serwera bez opłat i dwie stawki 0 nie odblokowują innych płatnych API. Zmiana adresu resetuje deklarację i nie przenosi poprzedniego sekretu bez nowego klucza.

Ta opcja wysyła zatwierdzony kontekst do wskazanego serwera. Nie jest potrzebna do działania MiniCPM offline. Domyślne timeouty sieciowe: 30 s nagłówki, 45 s bezczynności, 5 min całość; brak redirect/retry i wykonywania `tool_calls`. Nie uruchamiano rzeczywistego serwera ani płatnego API. Wyniki testów obu ścieżek: [TESTS_PL.md](TESTS_PL.md).
