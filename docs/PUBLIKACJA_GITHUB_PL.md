# Repozytorium i pliki wydania Scalającej

Repozytorium docelowe: [wtiptop/Ai-app-phone](https://github.com/wtiptop/Ai-app-phone).
Data przygotowania publikacji: **27.10.2026, Europe/Berlin**.

Git zawiera kod, przypięte źródła silników, dokumentację i dowody testów oraz
historię rozwoju. Pliki instalacyjne trafiają do osobnych wydań. Katalogi work,
SDK/NDK, cache, prywatne klucze, bazy i backupy nie należą do publikowanego kodu.
Nie są potrzebne do działania zainstalowanej aplikacji.

## Pobranie wersji 0.5.5

Otwórz [listę wydań](https://github.com/wtiptop/Ai-app-phone/releases).
Wydanie aplikacji 0.5.5 jest eksperymentalne, a APK podpisano kluczem debug.
Zainstaluj `Scalajaca-0.5.5-debug-arm64-x64.apk` jako aktualizację; nie czyść danych.
Wagi nie są częścią APK. Wersję i SHA-256 porównaj z plikiem
`Scalajaca-release-0.5.5.json` oraz `SUMY_SHA256-0.5.5.txt`.

Weryfikacja 0.5.5 została wykonana 21–22.10; publikacja plików nie oznacza
nowego odbioru telefonu, baterii lub jakości narracji. Pełny raport jest w
[TESTS_PL.md](TESTS_PL.md). Kod wydania APK odpowiada lokalnemu commitowi
`be53b03297861fa39f7857cfdd05bb42c7b1d563`; późniejsze zmiany dotyczą dystrybucji.

## Pełny OLMoE jako części

GitHub ogranicza pojedynczy załącznik wydania do mniej niż 2 GiB
([oficjalne limity](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)).
Po przerwaniu dużej przesyłki zmniejszono części: gotowy ZIP 7 416 461 483 B
jest dzielony na **111 części**, pierwsze 110 po 64 MiB i ostatnią
34 486 443 B. Wszystkie są potrzebne. To surowy podział bajtów, nie osobne
archiwa do importowania w aplikacji. Końcowe dane i SHA-256 nie zmieniły się.

Najwygodniej pobrać z wydania `pobierz_model_github.ps1` i uruchomić:

```powershell
./pobierz_model_github.ps1 -Model olmoe -Folder C:/Modele/OLMoE
```

Skrypt korzysta z systemowego curl z weryfikacją TLS, pobiera i sprawdza części,
wznawia niepełne pobrania oraz uruchamia składanie Pythonem 3.11+. Nie wymaga
logowania ani tokenu. Profil `minicpm1b` pobiera 11 części GGUF, a `minicpm2b`
24 części; każdy model wybierz do osobnego folderu. Instalator MiniCPM przyjmuje
złożony GGUF, a instalator Colibri — złożony ZIP. Składanie ręczne:

1. Pobierz do jednego folderu `OLMoE-1B-7B-0125-Instruct-Colibri-int8.zip.part001`
   do `.part111`, `OLMoE-Colibri-parts.json` oraz `join_release_parts.py`.
2. Na komputerze z Pythonem 3.11 lub nowszym uruchom w tym folderze:

   ```powershell
   python join_release_parts.py OLMoE-Colibri-parts.json
   ```

3. Program kontroluje rozmiary i SHA-256 każdej części oraz całego wyniku.
   Dopiero poprawny ZIP otrzymuje końcową nazwę. Nie nadpisuje istniejących
   plików; uszkodzona próba pozostawia `.partial` do ręcznego sprawdzenia.
4. Przenieś złożony ZIP na telefon. W ustawieniach dostawców otwórz Colibri,
   naciśnij **Wpisz hash paczki OLMoE 0.5.5**, następnie **Zainstaluj paczkę
   Colibri ZIP** i wskaż złożony plik. Części `.part001` nie są importerem ZIP.

Składanie potrzebuje dodatkowo około 7,42 GB miejsca obok części. Na telefonie
przygotuj około 16 GB na ZIP, prywatne wagi i rezerwę. Działająca aplikacja nie
potrzebuje potem komputera ani serwera. Nie zmieniono wag ani manifestu modelu.

SHA-256 pełnego ZIP:
`f0edda8eb956aef77f1820ba6e50bf317c9d233b5e83f9a3a83dfffbd6da24e2`.

SHA-256 manifestu wpisywanego w aplikacji:
`504f62581e7a16037d4aac6cc831a6de6e7cd93995501970f34a76de5f44210f`.

Sumy sprawdzają integralność, nie podpis wydawcy. Źródło wag, przypięty commit,
karta i licencja są opisane w [COLIBRI_PL.md](COLIBRI_PL.md) oraz dostarczane
obok części. Nie stosuj tych sum do samodzielnie zmodyfikowanych paczek.

## Uprawnienia do wysyłania

Połączenie aplikacji GitHub i logowanie lokalnego Gita/CLI są odrębne.
Do wypchnięcia historii wymagane jest działające logowanie klienta Git,
a do publikacji załączników — GitHub CLI albo interfejs wydań GitHub.
Hasła i tokenu nie umieszcza się w URL remote, kodzie, archiwum ani czacie.
Ustawienie `origin` nie potwierdza, że push się powiódł; wynik wymaga sprawdzenia
zdalnych commitów i listy plików wydania.

## Sprawdzenie narzędzi dystrybucji

22 testy Python zakończono wynikiem PASS, w tym siedem testów nowego składania:
poprawny wynik i ponowne użycie gotowego ZIP, uszkodzona część o prawidłowej
długości, ochrona istniejącego pliku, niedozwolona ścieżka, brak części i duplikat
nazwy oraz złożenie 111 fragmentów i odrzucenie przekroczenia limitu 128.
Wykonano rzeczywiste złożenie zarówno pierwotnych siedmiu, jak i końcowych
111 części — 7 416 461 483 B, SHA-256 identyczny z oryginalnym ZIP.

Dowody przygotowania są w `test-results/github-2026-10-27/`. Kontrola wzorców
poświadczeń objęła 14 wcześniejszych commitów, 3769 blobów i 76 611 200 B;
nie wykryto wskazanych wzorców ani prywatnych nazw plików. To kontrola przed
wysyłką, nie pełny audyt. Te wyniki nie potwierdzają jeszcze opublikowania
załączników — stan zdalny wymaga odrębnej weryfikacji.
