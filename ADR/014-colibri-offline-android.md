# ADR 014: eksperymentalny Colibri OLMoE w procesie Androida

Data: 21.10.2026. Status: przyjęte dla eksperymentalnego portu, bez odbioru pełnych wag na Pixelu.

Polityka budowania: Android CMake wymusza zoptymalizowane biblioteki Release również w instalacyjnym APK debug. Bezpośredni Gradle nadpisywał sam argument build.gradle wartością `debug`, usuwając optymalizację i powodując timeout MiniCPM. Sprawdzamy rzeczywiste polecenia kompilacji obu ABI i ponawiamy runtime; nazwa APK debug nie oznacza wolnych bibliotek LLM.

Użytkownik wybrał Pixel 9 offline, bez serwera. Colibri upstream jest silnikiem desktopowym, korzystającym z safetensors; nie jest nazwą modelu ani zamiennikiem GGUF MiniCPM. Android ARM64 udało się skompilować istniejącym NDK 28.2, bez nowych sterowników czy instalacji systemowych.

Decyzja: dodać osobny adapter `colibri_local`, importer paczki danych i statyczny szablon OLMoE Instruct. Kod C jest przypięty do e0db083cdc9e563e0766cc6fc661ef23c32298e0 i niezmieniony; własny JNI wrapper wywołuje jego CLI w nieeksportowanej usłudze `:colibri`. Protokół `SERVE` używa wyłącznie potoków stdin/stdout. Nie uruchamiamy HTTP ani Pythona w telefonie.

Upstream używa globalnego stanu i `exit()`. Osobny proces na każdą generację ogranicza skutki awarii oraz usuwa stary KV przed zmianą roli/kampanii. Stop i lifecycle kończą proces, także podczas prefill/load. Izolacja jest wyłącznie procesowa — nadal to UID aplikacji, bez gwarancji sandboxa dla złośliwego kodu natywnego. Eksperymentalny CPU jest jednowątkowy; optymalizacje GPU/NPU i trwała sesja natywna wymagają osobnego projektu i testów.

Importer dopuszcza wyłącznie konkretne nazwy plików danych, profil konfiguracyjny OLMoE i manifest z SHA-256, limitem rozpakowanych danych i atomowym stagingiem. Odrzuca duplikaty kluczy JSON, niezgodne token IDs i profile syntetyczne. Crash cleanup jest pod globalną blokadą importera. Testowy magazyn jawnie dopuszcza osobny profil syntetyczny; produkcja go odrzuca. Zastrzeżone znaczniki OLMoE w treści powodują błąd przed dispatch; nie uruchamiamy szablonu z paczki.

Koszty, zgoda na dokładny pakiet, kontrola roli i selekcja źródeł pozostają wspólne. Historyczne testy RPG MiniCPM nie dowodzą jakości Colibri. Odbiór portu na danych syntetycznych jest oddzielony od instalacji pełnych wag, wydajności i narracji. Nie zmieniamy schematu SQLite ani formatu backupu; wagi są instalowane osobno po odtworzeniu danych.
