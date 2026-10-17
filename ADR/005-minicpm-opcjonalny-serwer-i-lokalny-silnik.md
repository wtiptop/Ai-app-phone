# ADR 005: MiniCPM jako opcjonalny adapter; lokalny silnik osobnym modułem

Data: 17.10.2026. Status: przyjęta dla 0.1.1.

Użytkownik dodał OpenBMB/MiniCPM do zakresu. Repozytorium publikuje wagi i ścieżki wdrożenia, a nie konsumenckie konto lub abonament API. Zachowujemy samodzielność rdzenia Androida. Bez zgody nie pobieramy dużych wag, nie podłączamy kont i nie wykonujemy płatnych wywołań.

Wdrażamy `MiniCpmAdapter` zgodny z istniejącym `ProviderAdapter`, obsługujący tekstowy protokół OpenAI-compatible własnego serwera HTTPS. Adres jest ustawieniem właściciela, nigdy instrukcją z promptu. Dozwolone są baza domeny i `/v1`, bez URL credentials/query/fragment. Klucz jest opcjonalny i pozostaje w Keystore. Zmiana adresu bez nowego klucza usuwa stary. Deklaracja własnego serwera bez opłat i dwie stawki 0 pozwalają uzyskać jednorazową zgodę bez globalnego odblokowania płatnych API; inne serwery podlegają zwykłym rezerwom. Użytkownik zawsze widzi odbiorcę.

Nie łączymy w opisie serwera właściciela z inferencją wbudowaną w APK. Ta druga wymaga osobnego `local_inference`, natywnego silnika, zarządzania GGUF i pomiarów urządzenia. Oficjalny binding llama.cpp Android jest możliwą bazą; pobranie źródeł blokuje obecna polityka sieci środowiska. Nie wprowadzamy pozornego mostu zwracającego demo jako odpowiedź modelu. W tym wydaniu nie ma wag ani silnika MiniCPM.

Skutki: przyrost kodu bez nowych zależności Flutter i bez nowych uprawnień Androida; zachowane TLS, brak retry i brak auto-połączeń. MiniCPM jest opcjonalnym rozszerzeniem; awaria lub brak serwera nie blokuje pozostałej aplikacji. Testy mock potwierdzają protokół, nie działanie wag ani jakość modelu. Wymóg lokalnego LLM pozostaje ograniczony/zaplanowany do osobnego odbioru.
