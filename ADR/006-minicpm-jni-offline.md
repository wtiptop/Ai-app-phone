# ADR 006: MiniCPM bezpośrednio w procesie Androida

Data: 18.10.2026. Status: przyjęta dla 0.2.0; odbiór urządzenia otwarty.

Użytkownik wymaga prawdziwej inferencji offline, niezależnej od serwera. Dodajemy `LocalModelAdapter` o identyfikatorze `minicpm_local`. Wspólny kontrakt czatu i porównania pozostaje taki sam. Adapter własnego serwera `MiniCpmAdapter` jest osobną, opcjonalną ścieżką.

Przepływ: Flutter → MethodChannel → pojedynczy executor Kotlin → JNI → statycznie połączone llama.cpp/ggml CPU. Nie uruchamiamy serwera HTTP, procesu Python, usługi tła ani pobierania wag. Źródła llama.cpp przypięto do `5aeac37a35b44fde4bdffaec9159f2fcb253b622`, włączając wyłącznie potrzebne części parsera Jinja/JSON z `common`. Kod sieciowy `common` nie jest linkowany. CMake nie pobiera zależności. ABI dostarczanego APK: ARM64; Android 7+.

Wagi są dobrowolnie importowane przez SAF do prywatnego katalogu. Import oblicza SHA-256, opcjonalnie porównuje go z wartością właściciela, sprawdza strukturę GGUF i zapisuje plik dopiero po walidacji. Nazwa pliku to hash, nie ścieżka z importu. Obsługujemy wyłącznie tekstowe profile MiniCPM5-1B/2B. Podpisane pochodzenie wag nie wynika z samej nazwy/metadata: zalecane jest SHA-256 z oficjalnego źródła. Szablon w GGUF jest ignorowany; aplikacja używa dwóch przypiętych szablonów OpenBMB. Znaczniki specjalne we fragmencie wejściowym użytkownika nie są parsowane jako znaczniki protokołu.

Limity: jeden import/usuwanie/generacja w procesie; maks. 3 GiB pliku, 64 MiB metadanych, 4096 tensorów; 256 MiB rezerwy dysku po imporcie; kontrola wolnego RAM przed startem; kontekst 1024/2048/4096, maks. 512 tokenów odpowiedzi, 4 wątki CPU i 3 min. Długi kontekst jest odrzucany, bez cichego obcinania. Stop, przejście w tło i wysoki stan termiczny przerywają obliczenia. Bufory oraz KV są zwalniane po każdej odpowiedzi. Brak automatycznego fallbacku do innego modelu lub chmury.

Zgoda pokazuje telefon jako miejsce przetwarzania. Koszt API jest 0, bez klucza i bez włączania płatnych API; nie znosi limitów innych dostawców. Nadal obowiązują tryb prywatny RAM i zasady zapisu historii. Nie przyznajemy modelowi narzędzi, uprawnień ani dostępu do notatek/vaultu.

Weryfikacja: standardowy runner Flutter, JUnit z prawdziwym GGUF oraz wspólny rdzeń C++ na hoście z rzeczywistą generacją. Build/podpis/manifest/ABI APK są osobnymi dowodami. Te testy nie potwierdzają Android JNI, SAF, cyklu życia, temperatury, zużycia energii i jakości językowej na fizycznym telefonie. Dokładne wyniki: `docs/TESTS_PL.md`. MiniCPM-V/audio, GPU/NPU i pobieranie wag w UI pozostają zaplanowane.
