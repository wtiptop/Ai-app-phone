# Próby promptów MiniCPM5-2B na hoście

To diagnostyka Windows, nie test telefonu. Plik modelu i przypięcie silnika są takie jak w `../../minicpm5-2b-provenance.json` oraz głównej dokumentacji MiniCPM. Profil `minicpm5_2b`, kontekst 4096, greedy `source_grounded=true`, limit 96/160 zapisany osobno dla każdej próby. Nie zmieniano wag, szablonu ani silnika. Nie użyto API ani serwera.

Trzy pary plików `input.json` / `output.json` zawierają wszystkie **18 rzeczywistych generacji**, również nieudane warianty. Każda zakończyła się `stop`. Pierwsze trzy próby odtwarzają dokładnie błędy z pierwszego przebiegu Androida: wadliwą scenę, „Medalion” zamiast BURSZTYN i OTWARTA zamiast bieżącej ZAMKNIĘTA.

Jawne etykiety tytułu i treści poprawiły odczyt BURSZTYN. Czytelna hierarchia kanonu oraz historycznej notatki poprawiła odpowiedź o bramie. Ogólna angielska instrukcja zmniejszyła skłonność do deklarowania ujawnienia niedostępnych sekretów w sprawdzonej próbie. Żaden wariant nie został zaliczony jako pełna poprawna polska narracja. Nie wybrano wariantu, który z zakazu magii wywnioskował zamknięcie archiwum. Finalną aplikację trzeba ocenić na osobnym pełnym przebiegu Androida.

`prompt_probe.cpp` jest kopią użytego programu diagnostycznego. Przyjmuje trzy argumenty: ścieżkę oficjalnego modelu 2B, wejściowy JSON z listą prób i ścieżkę raportu. Korzysta z `local_engine.h` oraz `common/json.h` i istniejącej biblioteki `scalajaca_core` z przypiętymi zależnościami llama/ggml. To źródło dowodu, nie składnik budowanego APK. Model nie jest częścią archiwum projektu. Wszystkie dane kampanii są syntetyczne.
