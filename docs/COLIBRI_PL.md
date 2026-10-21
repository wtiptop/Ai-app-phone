# Colibri na Androidzie — eksperymentalny port 0.5.5

Colibri jest **silnikiem uruchamiającym modele**, nie osobnym modelem językowym. Dodano rzeczywisty port jego silnika OLMoE CPU do aplikacji Android. MiniCPM/llama.cpp pozostaje osobnym dostawcą i importerem GGUF.

Stan: **eksperymentalny**. W 0.5.5 pobrano wszystkie trzy oficjalne shardy BF16, sprawdzono opublikowane SHA-256, przekonwertowano wszystkich 1024 ekspertów do int8 i zainstalowano pełną paczkę przez produkcyjny SAF na osobnym emulatorze x86_64. Generacja, Stop i ponowny start pełnego modelu przeszły offline. Polska odpowiedź była niezręczna; nie oznacza to odbioru jakości MG. Wyniki kampanii: [TESTS_PL.md](TESTS_PL.md). Fizyczny Pixel 9, jego bateria i termika pozostają niezweryfikowane. Wyników MiniCPM nie przypisujemy Colibri.

## Co działa w kodzie

- Natywny silnik w APK, bez Termuxa, Pythona w telefonie, HTTP, konta ani serwera. Protokół upstream o nazwie `SERVE` oznacza tutaj wyłącznie ramki przez anonimowe potoki w urządzeniu. Nie uruchamiamy `openai_server.py`.
- Nieeksportowana usługa Androida `:colibri` uruchamia C w osobnym procesie. Stop kończy proces, zamyka potoki i zwalnia jego RAM. Nowa odpowiedź dostaje nowy proces/KV; całą zatwierdzoną historię podaje aplikacja.
- Wspólny interfejs czatu, streaming UTF-8, limity kontekstu i wyjścia, błędy, lokalny zapis i archiwum, kontrola zgody oraz modelu, 0 USD kosztu API bez włączenia płatnych usług. Bez automatycznego fallbacku.
- Import ZIP przez systemowy SAF, plik po pliku, z ograniczeniem rozpakowanych rozmiarów, sumą każdego pliku, atomową publikacją i anulowaniem. Wybrane pliki są kopiowane do prywatnego katalogu aplikacji. Niedokończone importy po awarii są sprzątane przy kolejnym uruchomieniu pod blokadą importu.
- Wybór zatwierdzonych źródeł, pierwszeństwo bieżącego kanonu i kontrola roli/kampanii przed przekazaniem do adaptera. To nie jest automatyczny kontroler lore ani dowód jakości modelu.

## Model i instalacja

Pierwszy obsługiwany profil to **allenai/OLMoE-1B-7B-0125-Instruct**, przekonwertowany do **merged int8** Colibri. Nazwa „1B-7B” oznacza model MoE: około 7B parametrów ogółem i około 1B aktywnych. Wszystkie wagi są nadal potrzebne na dysku. Nie importuj go jako GGUF; importer MiniCPM pozostaje odrębny.

1. Gotowa paczka wydania: `OLMoE-1B-7B-0125-Instruct-Colibri-int8.zip` (7 416 461 483 B). Zawiera wszystkie parametry po konwersji, nie próbkę. Źródło: [przypięty commit AllenAI](https://huggingface.co/allenai/OLMoE-1B-7B-0125-Instruct/tree/b89a7c4bc24fb9e55ce2543c9458ce0ca5c4650e), 13 838 721 960 B samych wag BF16. Karta deklaruje język angielski i Apache-2.0; nie gwarantuje polskiej narracji. Kartę, tekst licencji i pochodzenie dostarczono obok ZIP.
2. Do odtworzenia konwersji użyj `tools/colibri/convert_streaming.py` i NumPy. Narzędzie czyta bloki wag bez torch, sieci, pickle i kodu modelu; dense zachowuje bajtowo, a wszystkie projekcje ekspertów składa w 17 atomowych shardów. Aplikacja Android nie potrzebuje Pythona ani NumPy. Oryginalny konwerter upstream pozostaje bez zmian. Kontrola 9216 wierszy (trzy z każdej projekcji każdego eksperta) względem oryginalnego kwantyzatora C dała identyczne int8 i skale. Nie jest to porównanie wszystkich logitów z Transformers.

   ```powershell
   python tools/colibri/convert_streaming.py --model C:/modele/OLMoE-Instruct --out C:/modele/OLMoE-colibri
   ```

   Nie używaj starego `convert_olmoe.py`: tworzy nieobsługiwany przez bieżący silnik rozdzielony format ekspertów. Konwersja w telefonie nie jest zaimplementowana.

3. Zbuduj paczkę danych narzędziem Scalającej (tylko biblioteka standardowa Pythona):

   ```powershell
   python tools/colibri/package_model.py --model C:/modele/OLMoE-colibri --output C:/modele/OLMoE-colibri-android.zip --source https://huggingface.co/allenai/OLMoE-1B-7B-0125-Instruct/tree/b89a7c4bc24fb9e55ce2543c9458ce0ca5c4650e
   ```

   Narzędzie nie pobiera modelu ani nie uruchamia kodu z jego katalogu. Nie nadpisuje istniejącego ZIP. Wypisuje SHA-256 manifestu i ZIP. Kopiuj sumę manifestu do aplikacji, jeśli masz zaufanie do miejsca przygotowania paczki.

   Opcjonalna niezależna kontrola przed pakowaniem: wygeneruj kwantyzator z przypiętego kodu przez `python tools/colibri/verify_conversion.py --write-oracle C:/test/oracle.c`, skompiluj go z biblioteką matematyczną lokalnym kompilatorem C (MSVC: `cl /O2 /std:c11 /D_CRT_SECURE_NO_WARNINGS C:/test/oracle.c /Fe:C:/test/oracle.exe`), następnie wykonaj `python tools/colibri/verify_conversion.py --model C:/modele/OLMoE-Instruct --converted C:/modele/OLMoE-colibri --oracle C:/test/oracle.exe --report C:/test/verification.json`. Program kontrolny musi być przygotowany poza katalogami wag. Weryfikator porównuje cały zbiór dense, bajty każdego dense tensora oraz próbki każdej projekcji wszystkich ekspertów. Raport nie jest dowodem identycznych logitów ani kontroli każdej wagi int8.

4. Przenieś ZIP na telefon. W Scalającej otwórz **Ustawienia → Dostawcy → Colibri offline → Zainstaluj paczkę Colibri ZIP**. Wskaż paczkę w systemowym wyborze pliku i pozostań na ekranie do końca instalacji. Następnie wybierz Colibri offline w czacie, sprawdź model i zatwierdź dokładny pakiet wejścia. Nie jest potrzebne połączenie z komputerem ani serwerem podczas rozmowy.

   SHA-256 manifestu do pola aplikacji: `504f62581e7a16037d4aac6cc831a6de6e7cd93995501970f34a76de5f44210f`. SHA-256 ZIP do kontroli kopiowania: `f0edda8eb956aef77f1820ba6e50bf317c9d233b5e83f9a3a83dfffbd6da24e2`. Nie wpisuj sumy ZIP jako sumy manifestu.

   Powyższe sumy i przycisk „Wpisz hash paczki OLMoE 0.5.5” dotyczą dostarczonej paczki. Przy własnej konwersji użyj sumy manifestu wypisanej przez narzędzie; inne metadane paczki lub pliki zmieniają jej tożsamość. Daty plików ZIP mogą zmienić sumę całego archiwum bez zmiany manifestu.

5. Po udanym imporcie oryginalny ZIP nadal jest na urządzeniu. Możesz usunąć go samodzielnie po sprawdzeniu modelu; aplikacja nie usuwa plików źródłowych. Usunięcie modelu w ustawieniach usuwa wyłącznie prywatną kopię jego wag, zachowując historię.

Pełne wagi nie są częścią APK, ZIP źródeł ani zaszyfrowanego backupu projektów/kampanii. Po odtworzeniu backupu na innym urządzeniu ponownie zainstaluj model. Sekrety MG, źródła, wersje i checkpointy nadal obejmuje dotychczasowy backup danych aplikacji.

## Pamięć i ograniczenia

Pixel 9 ma 12 GB RAM według [Google](https://store.google.com/au/magazine/introducing-google-pixel-9?hl=en-GB). To pamięć całego telefonu, nie budżet aplikacji. Port wymaga **co najmniej 4 GiB aktualnie dostępnego RAM** i braku sygnału `lowMemory` przed generacją. Ten zachowawczy próg nie jest pomiarem szczytu ani gwarancją, że Android nie zakończy procesu.

Dense wagi są ładowane do f32; dochodzą KV, bufory obliczeń, cache dwóch ekspertów na warstwę, Flutter i baza. Oszacowanie dla kontekstu 4096 to około 3 GB głównych struktur C, dodatkowo bufory i rezerwa. Rozmiar plików nie jest zużyciem RAM. Eksperci są doczytywani z prywatnego magazynu, więc mały cache może powodować intensywny odczyt. W 0.5.5 działają cztery wątki CPU i statyczny OpenMP z NDK. Aktywne oryginalne pragmy SIMD mogą zmieniać zaokrąglenia względem dawnego builda bez OpenMP. IDOT=0, bez dodatkowej kwantyzacji aktywacji. Nie ma GPU/NPU ani Vulkan. Nie obiecujemy płynności ani przewagi jakości nad MiniCPM.

Limit paczki: 10 GiB rozpakowanych danych, 128 plików, 512 MiB rezerwy na dysku. ZIP i kopia prywatna zajmują miejsce równocześnie — dla pełnego profilu przygotuj około 16 GB wolnego miejsca. Rozpakowanie jest strumieniowe, bez wczytywania całych wag do RAM. JSON ma osobne limity i kontrolę duplikatów kluczy; identyfikatory tokenów muszą mieścić się w słowniku modelu.

Kontekst 4096, najwyżej 512 nowych tokenów, maksymalnie 3 minuty. Model otrzymuje wybrane fragmenty uprawnionych danych; duże projekty i stare sesje pozostają na dysku i są wyszukiwane przez aplikację. Nie próbujemy utrzymywać całej kampanii w kontekście LLM. Przejście w tło lub stan termiczny `SEVERE` kończy proces; port nie działa jako asystent 24/7 w tle.

Treści zawierające `|||IP_ADDRESS|||`, `<|system|>`, `<|user|>` lub `<|assistant|>` są odrzucane przed uruchomieniem silnika. Obecny tokenizer upstream rozpoznaje je także w treści użytkownika, dlatego bez oddzielnej tokenizacji literalnej nie można bezpiecznie zachować takich źródeł. Aplikacja nie przepisuje ich po cichu. Jest to jawne ograniczenie portu, a nie pełna odporność na prompt injection.

## Odtwarzanie testów portu

Dane syntetyczne są generowane lokalnie i ignorowane przez Git; nie trafiają do głównego APK ani ZIP źródeł. Uruchom przed budową APK testów:

```powershell
python tools/colibri/make_test_fixture.py android/app/src/androidTest/assets/colibri-tiny
flutter test --no-pub
python -m unittest discover -s tools/colibri -p test_*.py -v
Push-Location android
./gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest -Ptarget-platform=android-arm64,android-x64
Pop-Location
./scripts/test_android_colibri.ps1 -Output C:/testy/colibri-nowy-przebieg
```

Skrypt portu dopuszcza własny `Scalajaca_API30`/5556 lub `Scalajaca_OLMoE_API30`/5558 (parametr `-Serial emulator-5558`). Odłącza wyłącznie wybrany emulator, aktualizuje APK przez `install -r` i zachowuje dane. Wykonuje sześć testów syntetycznych, w tym pełny token 512 B. Testy JUnit pełnych GGUF wymagają `SCALAJACA_TEST_MODEL` i `SCALAJACA_TEST_MODEL_2B`; w 0.5.5 oba pliki wskazano, pominiętych 0. Test pełnych OLMoE uruchamia się oddzielnie klasą `ColibriFullModelDeviceTest`, z argumentami `fullModelTest=yes` i `modelSha256`. Wymaga produkcyjnie zainstalowanego modelu i minimum 4 GiB dostępnego RAM. Zapisuje surowy wynik, sprawdza generację, Stop i kolejny proces; nie zastępuje próby kampanii.

Po instalacji obu APK i imporcie pełnych wag można odtworzyć ten test poniżej. Najpierw potwierdź nazwę własnego AVD (`ro.kernel.qemu.avd_name`); polecenia dotyczą wyłącznie emulatora 5558. Każde uruchomienie wymaga nowego `runId`, aby nie nadpisać wyniku. Kod testu sprawdza zakończenie po Stop poniżej 5 s; czas ładowania do pierwszego tokena jest osobnym pomiarem.

```powershell
adb -s emulator-5558 shell getprop ro.kernel.qemu.avd_name
adb -s emulator-5558 shell cmd connectivity airplane-mode enable
adb -s emulator-5558 shell svc wifi disable
adb -s emulator-5558 shell svc data disable
adb -s emulator-5558 shell dumpsys connectivity
adb -s emulator-5558 shell am instrument -w -r -e class pl.scalajaca.scalajaca.colibri.ColibriFullModelDeviceTest -e fullModelTest yes -e runId moja-proba-001 -e modelSha256 504f62581e7a16037d4aac6cc831a6de6e7cd93995501970f34a76de5f44210f pl.scalajaca.scalajaca.test/androidx.test.runner.AndroidJUnitRunner
adb -s emulator-5558 exec-out run-as pl.scalajaca.scalajaca cat files/colibri-full-moja-proba-001.json
adb -s emulator-5558 shell dumpsys connectivity
```

Oczekiwany wynik techniczny to `OK (1 test)` i `finished: true` w JSON. Potwierdzenie offline wymaga `Active default network: none` przed i po próbie. Pierwszy smoke jest w `test-results/colibri-0.5.5/full/`, a powtórka z pomiarem reakcji na Stop w `full-timed/`. Te testy wykorzystują rzeczywiste wagi, lecz nie oceniają gramatyki ani lore.

Ręczna kontrola instalatora otworzyła systemowy SAF i potwierdziła odrzucenie profilu syntetycznego w produkcji bez pozostawienia modelu/stagingu. W selektorze Androida 11 tego emulatora użyto fokusu klawiatury i Enter; dotyk wiersza nie aktywował pliku. Nie przedstawiamy tej próby jako pełnego odbioru dotykowego selektora na Pixelu. Dowody: `test-results/colibri-0.5.4/ui-import-result.json` i zrzuty ekranu.

## Bezpieczeństwo i pochodzenie

Osobny proces zabezpiecza główny interfejs przed zwykłym `exit`/awarią C. **Nie jest sandboxem innego UID**: ma uprawnienia aplikacji. Wagi/tokenizer muszą pochodzić z zaufanego źródła. SHA-256 sprawdza integralność, a nie podpis wydawcy. Nie wykonujemy kodu Python, szablonów Jinja, skryptów ani binariów z paczki. Parser natywny pozostaje kodem wymagającym dalszego audytu.

Źródła: [Colibri, przypięty commit](https://github.com/JustVugg/colibri/tree/e0db083cdc9e563e0766cc6fc661ef23c32298e0), [oficjalny quickstart](https://github.com/JustVugg/colibri/blob/e0db083cdc9e563e0766cc6fc661ef23c32298e0/docs/quickstart.md), [konwerter OLMoE](https://github.com/JustVugg/colibri/blob/e0db083cdc9e563e0766cc6fc661ef23c32298e0/c/tools/convert_olmoe_merged.py). Oficjalny instalator upstream nie stanowi wydania Androida. Nasz port obejmuje OLMoE, nie wszystkie rodziny z katalogu Colibri.

Pobrane pliki upstream mają inwentarz `third_party/colibri/SHA256SUMS.txt`, `PIN.json`, LICENSE, NOTICE i THIRD_PARTY_NOTICES. Biblioteka w APK zawiera port CPU i wymagane nagłówki; pozostałe backendy i narzędzia serwerowe nie są budowane. Licencje są dostępne także w ekranie licencji Fluttera.
