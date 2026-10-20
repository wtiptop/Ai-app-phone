# 012 — Wielosesyjna kampania po polsku, pamięć i granice modelu

Data: 20.10.2026. Status: przyjęte dla wersji 0.5.2.

## Problem

Test krótkiego angielskiego słowa nie potwierdza jakości polskiej kampanii. Potrzebna jest osobna ocena przechowania świata, wyboru źródeł, odpowiedzi MiniCPM i ochrony sekretów. Wstępna kampania Androida odnalazła 6/6 faktów, lecz model podał dokładnie tylko 3/6. Narracja powtarzała pytanie. Zapis i retrieval nie były przyczyną wszystkich błędów odpowiedzi.

## Decyzje

1. Kampania testowa jest autorska i syntetyczna. Oddzielny target `test_driver/rpg_soak.dart` korzysta z prawdziwego SQLite Androida, szyfrowania i Keystore, ChatSession, kontroli zgody oraz JNI. Ma własną bazę i prefiks kluczy. Nie czyta głównej bazy użytkownika. Nie jest dołączany do głównego APK.
2. Próba obejmuje 24 symulowane sesje: zapis checkpointu, przywołanie dawnego faktu, zmianę stanu bramy i właściciela klucza, pięć prób narracji, dwa restarty procesu oraz próby zakresów i sekretów. Każde pytanie ma nowy czat zakresowy i zachowany dowód źródeł. To test trwałej pamięci, nie jednej rozmowy mieszczącej całą kampanię w kontekście.
3. Pytania wyszukiwarki korzystają z istniejącej stoplisty PL/EN przed limitem 12 terminów. Indeks HMAC zachowuje format. Nie ma stemmingu, embeddingów ani odgadywania synonimów.
4. Kandydaci RPG są odczytywani stronami po 40, maksymalnie 2000. Zbyt długi automatyczny kandydat nie blokuje późniejszego krótkiego. Przekroczenie limitu jest oznaczone. Jawnie wybrany wpis i dołączony checkpoint muszą wejść w całości albo powstaje błąd; nie wolno ich cicho zastąpić materiałem pomocniczym. Końcowa kolejność zachowuje hierarchię źródeł, a rodzaj wpisu jest nazwany w pakiecie.
5. MG może jawnie wyłączyć automatyczne dołączenie checkpointu przy szukaniu faktu. Stan pozostaje w bazie i historii. Przełącznik wraca do domyślnego ustawienia po zmianie kampanii lub roli. Nie znosi ograniczeń sekretów. Przy kontekście MiniCPM 1024/2048 kampania nadal jest dostępna do edycji, ale pakiet dla modelu wymaga ustawienia 4096.
6. MiniCPM z załącznikiem otrzymuje źródła i pytanie w jednej turze user, ze zwięzłymi technicznymi nagłówkami `Sources` i `Question`. Własna instrukcja aplikacji pozostaje osobną turą system. Polski tekst źródeł nie jest promowany do instrukcji systemowych. Dokładne role i tekst nadal są objęte budżetem, digestem, zgodą i ponowną walidacją rewizji. Zwykły czat oraz pozostałe adaptery zachowują dotychczasowy format.
7. Żadnych podmian nazw ani gotowych odpowiedzi dla fixture. Oceniamy osobno dokładne odpowiedzi, sens narracji, zgodność z kanonem i sekretami. Model nie zapisuje kanonu samodzielnie. Niezaliczone próby pozostają w raporcie.

## Zgodność i ograniczenia

Baza v3, pełna kopia v2 i dowody kontekstu v1 zachowują zgodność. Nie zmieniono wag, przypiętego silnika ani polityki kont, kosztów i sieci. Skrypt odtwarzający test akceptuje wyłącznie własny AVD Scalajaca_API30, sprawdza offline i odmawia ponownego użycia identyfikatora próby.

Raport nie jest pomiarem fizycznego Pixela 9, wielodniowej gry ludzi ani korpusu GB. Oficjalna [karta MiniCPM5-1B](https://huggingface.co/openbmb/MiniCPM5-1B) oznacza języki angielski i chiński; nie stanowi potwierdzenia jakości polskiego. Nawet deterministyczne dekodowanie może powtarzać tekst lub błędnie zastosować lore. Pełny agent ciągłości i automatyczna merytoryczna kontrola sprzeczności pozostają zaplanowane. Rzeczywiste wyniki i ograniczenia: `docs/TESTS_PL.md` i raport kampanii w `docs/test-results/`.
