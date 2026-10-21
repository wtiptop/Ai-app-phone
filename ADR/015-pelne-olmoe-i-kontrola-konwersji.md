# ADR015: pełny OLMoE, kontrola konwersji i próba kampanii

Prace rozpoczęto 21.10.2026; długa próba przechodzi przez noc 21–22.10 (Europe/Warsaw). Raporty mają dokładne czasy UTC. Status: przyjęte dla eksperymentalnego Colibri; jakość MG wymaga osobnego odbioru.

Użytkownik jawnie zatwierdził pobranie i instalację pełnych wag. Użyto publicznego AllenAI OLMoE-1B-7B-0125-Instruct, commit b89a7c4bc24fb9e55ce2543c9458ce0ca5c4650e. Wszystkie trzy BF16 shardy (13 838 721 960 B) sprawdzono względem opublikowanych LFS SHA-256. Bez kont, płatnych API i publikacji.

Nowy lokalny konwerter NumPy przetwarza bloki wierszy zamiast materializować model w torch. Zachowuje wszystkie 147 dense tensorów bez zmiany bajtów. Łączy gate/up/down każdego z 1024 ekspertów do merged int8 ze skalami F32 zgodnie z formatem upstream. Zapisuje 17 shardów atomowo i przypina źródła, konwerter oraz wynikowe SHA. Oryginalny konwerter i 119 vendored plików pozostają zachowane. Niezależny program z oryginalną quantize_rows z quant.h porównał 9216 wierszy wszystkich 3072 projekcji: bajty int8 i skal zgodne. To kontrola próbek; nie dowód identycznych logitów z Transformers.

Przegląd niezależny znalazł i zamknął dwie luki dowodu/narzędzia: weryfikator musi sprawdzać dokładny zbiór dense, a dziennik wznowienia nie może kasować starych potwierdzeń przed ich kontrolą. Nowy konwerter zapisuje i fsyncuje receipt przed publikacją sharda; wznowienie odzyskuje gotowy partial po kontroli rozmiaru, SHA i nagłówka. Testy negatywne oraz przerwania przechodzą. Wagi ukończono przed naprawą dziennika, bez zmiany ich matematyki; dokładny dawny skrypt zachowano wraz z SHA w `test-results/colibri-0.5.5/converter-used.py.txt`. Nowa wersja konwertera celowo nie wznawia katalogu utworzonego skryptem o innym SHA.

Cała paczka ma 7 416 456 156 B danych, ZIP 7 416 461 483 B. Model nie jest częścią APK, ZIP źródeł ani backupu kampanii. Wymaga osobnego importu przez SAF i miejsca jednocześnie na ZIP oraz prywatną kopię. Import wykonano na oddzielnym Scalajaca_OLMoE_API30 (5558, 6 GiB RAM, 24 GiB userdata), nie usuwając starego AVD i jego MiniCPM. Fizycznego Pixela 9 nie podłączono.

Włączono statyczny OpenMP z NDK i cztery wątki w samym Colibri, bez GPU/NPU ani serwera. IDOT pozostaje 0. Oryginalne pragmy SIMD/redukcji mogą zmieniać zaokrąglenia względem poprzedniego builda bez OpenMP; nie deklarujemy identycznych tokenów między tymi buildami. Zachowano produkcyjny preflight 4 GiB dostępnego RAM i limit 180 s. Nie obniżamy go wyłącznie na potrzeby emulatora.

Wykryto realne ucinanie tokena 19979 oficjalnego tokenizera (512 spacji) do 511 B. CMake sprawdza wejściowy SHA upstream, tworzy kopię kompilacyjną i nakłada jedną jawną łatkę bufora 512→65537 B, sprawdzając wynikowy SHA także po zapisie. Vendor pozostaje bez zmian. Osobny test native/JNI potwierdza 1024 spacje z dwóch tokenów; protokół nadal odrzuca pojedyncze ramki ponad 4096 B.

Generacja, Stop i ponowny start pełnych wag są odrębnym testem od sześciu syntetycznych testów portu. Harness RPG przyjmuje jawny dostawcę i tożsamość wag, odrzuca profil syntetyczny Colibri oraz zmianę silnika/modelu/instrukcji podczas jednej próby. Wciąż używa rzeczywistej SQLite, CampaignStore, scope, zgody na pakiet i produkcyjnego adaptera. 24 symulowane sesje nie są 24 sesjami ludzi; ścisłe odpowiedzi, jakość polszczyzny, lore i wycieki oceniamy oddzielnie. Surowe wyniki i ograniczenia są w docs/TESTS_PL.md.

SQLite v3, pełny backup v2, źródła, wersje, checkpointy i sekrety MG nie wymagają migracji. Nie zmieniamy kanonu automatycznie ani nie poprawiamy odpowiedzi fixture przez podstawianie oczekiwanych nazw.
