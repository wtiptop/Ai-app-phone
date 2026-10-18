# ADR 007: natywny x86_64 do testu Androida i ARM64 dla telefonu

Data: 18.10.2026. Status: przyjęta w 0.2.1.

Poprzedni APK 0.2.0 zawierał wyłącznie ARM64. Po instalacji na Androidzie 11 Google APIs x86_64 aplikacja zakończyła się SIGILL w `libndk_translation` przed wejściem do ekranu MiniCPM. Obsługa translacji ARM w obrazie nie zagwarantowała zgodności tego APK. Ten wynik nie dowodzi awarii na fizycznym ARM64.

Dodajemy pełne ABI x86_64 obok ARM64 w jednym APK. Emulator używa natywnego Flutter/JNI x86_64, telefon ARM64 wybiera arm64-v8a. Dla Androida x86_64 wyłączamy w ggml AVX, AVX2, warianty AVX512/AVX_VNNI, FMA, F16C i BMI2; pozostawiamy SSE4.2. Akcelerator emulatora na tym komputerze nie udostępnia AVX. Zmiana dotyczy konfiguracji CMake aplikacji, bez modyfikacji przypiętych źródeł upstream. Ceną dwóch ABI jest większy APK. Nie dodajemy serwera ani połączenia sieciowego do silnika.

Testy urządzenia uruchamia standardowy AndroidJUnitRunner 1.7.0 i UIAutomator 2.3.0 w osobnym testowym APK. Usunięto nieużywaną zależność Flutter `integration_test`, która wnosiła starszy runner 1.3.0 do grafu debug i powodowała konflikt rozwiązywania zależności. Runner AndroidX jest wyłącznie zależnością `androidTestImplementation`.

Scenariusze wybierają plik w prawdziwym DocumentsUI, sprawdzają SHA-256 i liczbę bajtów prywatnej kopii, uruchamiają czat oraz bezpośredni streaming JNI, Stop i przejście w tło. Warunkiem każdego testu jest emulator i brak aktywnej sieci; sprawdzamy to również po teście. Raporty są w prywatnym katalogu debug, odczytywane przez `run-as`, bez roota. Fixture ma tylko publiczny model i sztuczne angielskie prompty. Wczesne błędy wyszukiwania pola SHA, synchronizacji menu i przywracania selektora były błędami testu; nie stanowią potwierdzenia działania modelu.

Odtwarzanie: `scripts/test_android_emulator.ps1`, obraz Android 11 / API 30 Google APIs x86_64 w języku angielskim, przygotowany emulator i osobny publiczny GGUF. Skrypt nie pobiera wag ani nie instaluje sterowników Windows. Na komputerze testowym AEHD 2.2.0 zainstalowano po wyraźnej zgodzie właściciela. Sterownik jest narzędziem środowiska, nie zależnością aplikacji na telefonie.

Dokładne końcowe wyniki i ograniczenia: `docs/TESTS_PL.md`. Odbiór emulatora x86_64 nie potwierdza wydajności ARM64 telefonu, temperatury, baterii, TalkBack, jakości polskiego ani wszystkich scenariuszy pierwotnej specyfikacji.

Odbiór ujawnił, że Android łączył status/koszt/tokeny z podpowiedzią zaznaczalnego tekstu odpowiedzi. Status miał widoczną treść, ale brakowało osobnego węzła. W 0.2.1 otrzymuje granicę `Semantics(container: true)` oraz `liveRegion` po wyjściu ze streamingu/pending. Celem jest osobny odczyt i ogłoszenie zmiany stanu. Test Flutter sprawdza etykietę i flagę live region; test urządzenia odczytuje stan zakończenia/anulowania jako oddzielną etykietę. Ręczny odbiór TalkBack nadal pozostaje otwarty.
