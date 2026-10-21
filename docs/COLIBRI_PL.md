# Colibri na Androidzie — eksperymentalny port 0.5.4

Colibri jest **silnikiem uruchamiającym modele**, nie osobnym modelem językowym. Dodano rzeczywisty port jego silnika OLMoE CPU do aplikacji Android. MiniCPM/llama.cpp pozostaje osobnym dostawcą i importerem GGUF.

Stan: **eksperymentalna**. Kompilacja ARM64 jest przeznaczona dla Pixela 9; runtime sprawdzamy na emulatorze x86_64. Fizyczny Pixel 9, pełne wytrenowane wagi OLMoE, polska narracja, 24 sesje RPG na Colibri, termika, bateria i wydajność dużego modelu pozostają **niezweryfikowane**. Wyników MiniCPM 0.5.3 nie przypisujemy Colibri. Bieżące wyniki: [TESTS_PL.md](TESTS_PL.md).

## Co działa w kodzie

- Natywny silnik w APK, bez Termuxa, Pythona w telefonie, HTTP, konta ani serwera. Protokół upstream o nazwie `SERVE` oznacza tutaj wyłącznie ramki przez anonimowe potoki w urządzeniu. Nie uruchamiamy `openai_server.py`.
- Nieeksportowana usługa Androida `:colibri` uruchamia C w osobnym procesie. Stop kończy proces, zamyka potoki i zwalnia jego RAM. Nowa odpowiedź dostaje nowy proces/KV; całą zatwierdzoną historię podaje aplikacja.
- Wspólny interfejs czatu, streaming UTF-8, limity kontekstu i wyjścia, błędy, lokalny zapis i archiwum, kontrola zgody oraz modelu, 0 USD kosztu API bez włączenia płatnych usług. Bez automatycznego fallbacku.
- Import ZIP przez systemowy SAF, plik po pliku, z ograniczeniem rozpakowanych rozmiarów, sumą każdego pliku, atomową publikacją i anulowaniem. Wybrane pliki są kopiowane do prywatnego katalogu aplikacji. Niedokończone importy po awarii są sprzątane przy kolejnym uruchomieniu pod blokadą importu.
- Wybór zatwierdzonych źródeł, pierwszeństwo bieżącego kanonu i kontrola roli/kampanii przed przekazaniem do adaptera. To nie jest automatyczny kontroler lore ani dowód jakości modelu.

## Model i instalacja

Pierwszy obsługiwany profil to **allenai/OLMoE-1B-7B-0125-Instruct**, przekonwertowany do **merged int8** Colibri. Nazwa „1B-7B” oznacza model MoE: około 7B parametrów ogółem i około 1B aktywnych. Wszystkie wagi są nadal potrzebne na dysku. Nie importuj go jako GGUF; importer MiniCPM pozostaje odrębny.

1. Przygotuj źródłowe wagi z [oficjalnego repozytorium AllenAI](https://huggingface.co/allenai/OLMoE-1B-7B-0125-Instruct). Pobieranie pełnego źródła to około 14 GB, wynik konwersji około 7–8 GB. W tym etapie **nie pobrano pełnych wag**, aby nie przedstawiać testu syntetycznego jako odbioru tego modelu. Osobno sprawdź kartę i licencję modelu; licencja silnika nie zastępuje licencji wag.
2. Na komputerze użyj przypiętego konwertera `third_party/colibri/c/tools/convert_olmoe_merged.py` z już pobranym katalogiem, bez automatycznego uruchamiania serwera. Konwerter wymaga osobnego środowiska Python z numpy, torch, safetensors i huggingface_hub. Aplikacja Android tych pakietów nie potrzebuje. Nie zainstalowano ich automatycznie w systemie użytkownika. Konwerter jest narzędziem upstream; trzeba zapewnić miejsce i RAM również dla przetwarzanych shardów.

   ```powershell
   python third_party/colibri/c/tools/convert_olmoe_merged.py --model C:/modele/OLMoE-Instruct --out C:/modele/OLMoE-colibri
   ```

   Nie używaj starego `convert_olmoe.py`: tworzy nieobsługiwany przez bieżący silnik rozdzielony format ekspertów. Konwersja w telefonie nie jest zaimplementowana.

3. Zbuduj paczkę danych narzędziem Scalającej (tylko biblioteka standardowa Pythona):

   ```powershell
   python tools/colibri/package_model.py --model C:/modele/OLMoE-colibri --output C:/modele/OLMoE-colibri-android.zip
   ```

   Narzędzie nie pobiera modelu ani nie uruchamia kodu z jego katalogu. Nie nadpisuje istniejącego ZIP. Wypisuje SHA-256 manifestu i ZIP. Kopiuj sumę manifestu do aplikacji, jeśli masz zaufanie do miejsca przygotowania paczki.

4. Przenieś ZIP na telefon. W Scalającej otwórz **Ustawienia → Dostawcy → Colibri offline → Zainstaluj paczkę Colibri ZIP**. Wskaż paczkę w systemowym wyborze pliku i pozostań na ekranie do końca instalacji. Następnie wybierz Colibri offline w czacie, sprawdź model i zatwierdź dokładny pakiet wejścia. Nie jest potrzebne połączenie z komputerem ani serwerem podczas rozmowy.

5. Po udanym imporcie oryginalny ZIP nadal jest na urządzeniu. Możesz usunąć go samodzielnie po sprawdzeniu modelu; aplikacja nie usuwa plików źródłowych. Usunięcie modelu w ustawieniach usuwa wyłącznie prywatną kopię jego wag, zachowując historię.

Pełne wagi nie są częścią APK, ZIP źródeł ani zaszyfrowanego backupu projektów/kampanii. Po odtworzeniu backupu na innym urządzeniu ponownie zainstaluj model. Sekrety MG, źródła, wersje i checkpointy nadal obejmuje dotychczasowy backup danych aplikacji.

## Pamięć i ograniczenia

Pixel 9 ma 12 GB RAM według [Google](https://store.google.com/au/magazine/introducing-google-pixel-9?hl=en-GB). To pamięć całego telefonu, nie budżet aplikacji. Port wymaga **co najmniej 4 GiB aktualnie dostępnego RAM** i braku sygnału `lowMemory` przed generacją. Ten zachowawczy próg nie jest pomiarem szczytu ani gwarancją, że Android nie zakończy procesu.

Dense wagi są ładowane do f32; do tego dochodzą KV, bufory obliczeń, cache dwóch ekspertów na warstwę, Flutter i baza. Wstępne oszacowanie dla kontekstu 4096: około 3 GB samych głównych struktur C, dodatkowo bufory i rezerwa. Rozmiar plików modelu nie jest zużyciem RAM. Eksperci są doczytywani z prywatnego magazynu; mały cache może powodować intensywny odczyt i niską szybkość. Port CPU ma jeden wątek obliczeń, bez OpenMP, GPU/NPU i Vulkan. Nie obiecujemy płynnej pracy ani jakości lepszej niż MiniCPM.

Limit paczki: 10 GiB rozpakowanych danych, 128 plików, 512 MiB rezerwy na dysku. ZIP i kopia prywatna zajmują miejsce równocześnie — dla pełnego profilu przygotuj około 16 GB wolnego miejsca. Rozpakowanie jest strumieniowe, bez wczytywania całych wag do RAM. JSON ma osobne limity i kontrolę duplikatów kluczy; identyfikatory tokenów muszą mieścić się w słowniku modelu.

Kontekst 4096, najwyżej 512 nowych tokenów, maksymalnie 3 minuty. Model otrzymuje wybrane fragmenty uprawnionych danych; duże projekty i stare sesje pozostają na dysku i są wyszukiwane przez aplikację. Nie próbujemy utrzymywać całej kampanii w kontekście LLM. Przejście w tło lub stan termiczny `SEVERE` kończy proces; port nie działa jako asystent 24/7 w tle.

Treści zawierające `|||IP_ADDRESS|||`, `<|system|>`, `<|user|>` lub `<|assistant|>` są odrzucane przed uruchomieniem silnika. Obecny tokenizer upstream rozpoznaje je także w treści użytkownika, dlatego bez oddzielnej tokenizacji literalnej nie można bezpiecznie zachować takich źródeł. Aplikacja nie przepisuje ich po cichu. Jest to jawne ograniczenie portu, a nie pełna odporność na prompt injection.

## Odtwarzanie testów portu

Dane syntetyczne są generowane lokalnie i ignorowane przez Git; nie trafiają do głównego APK ani ZIP źródeł. Uruchom przed budową APK testów:

```powershell
python tools/colibri/make_test_fixture.py android/app/src/androidTest/assets/colibri-tiny
flutter test --no-pub
python -m unittest discover -s tools/colibri -p test_package_model.py -v
Push-Location android
./gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest -Ptarget-platform=android-arm64,android-x64
Pop-Location
./scripts/test_android_colibri.ps1 -Output C:/testy/colibri-nowy-przebieg
```

Wymagany jest skonfigurowany Flutter/Android SDK oraz własny uruchomiony emulator `Scalajaca_API30` na porcie 5556. Skrypt odłącza wyłącznie ten emulator od sieci, aktualizuje APK przez `install -r` i zachowuje dane. Testy importu pełnych GGUF w JUnit wymagają zmiennych `SCALAJACA_TEST_MODEL` i `SCALAJACA_TEST_MODEL_2B`; bez nich dwa przypadki są jawnie pomijane. W odbiorze 0.5.4 oba istniejące pliki były ustawione: pominiętych 0. Skrypt portu nie jest testem jakości narracji, pełnych wag ani fizycznego telefonu.

Ręczna kontrola instalatora otworzyła systemowy SAF i potwierdziła odrzucenie profilu syntetycznego w produkcji bez pozostawienia modelu/stagingu. W selektorze Androida 11 tego emulatora użyto fokusu klawiatury i Enter; dotyk wiersza nie aktywował pliku. Nie przedstawiamy tej próby jako pełnego odbioru dotykowego selektora na Pixelu. Dowody: `test-results/colibri-0.5.4/ui-import-result.json` i zrzuty ekranu.

## Bezpieczeństwo i pochodzenie

Osobny proces zabezpiecza główny interfejs przed zwykłym `exit`/awarią C. **Nie jest sandboxem innego UID**: ma uprawnienia aplikacji. Wagi/tokenizer muszą pochodzić z zaufanego źródła. SHA-256 sprawdza integralność, a nie podpis wydawcy. Nie wykonujemy kodu Python, szablonów Jinja, skryptów ani binariów z paczki. Parser natywny pozostaje kodem wymagającym dalszego audytu.

Źródła: [Colibri, przypięty commit](https://github.com/JustVugg/colibri/tree/e0db083cdc9e563e0766cc6fc661ef23c32298e0), [oficjalny quickstart](https://github.com/JustVugg/colibri/blob/e0db083cdc9e563e0766cc6fc661ef23c32298e0/docs/quickstart.md), [konwerter OLMoE](https://github.com/JustVugg/colibri/blob/e0db083cdc9e563e0766cc6fc661ef23c32298e0/c/tools/convert_olmoe_merged.py). Oficjalny instalator upstream nie stanowi wydania Androida. Nasz port obejmuje OLMoE, nie wszystkie rodziny z katalogu Colibri.

Pobrane pliki upstream mają inwentarz `third_party/colibri/SHA256SUMS.txt`, `PIN.json`, LICENSE, NOTICE i THIRD_PARTY_NOTICES. Biblioteka w APK zawiera port CPU i wymagane nagłówki; pozostałe backendy i narzędzia serwerowe nie są budowane. Licencje są dostępne także w ekranie licencji Fluttera.
