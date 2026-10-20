# Odtworzenie testu wielosesyjnej kampanii offline

Wersja 0.5.2. To próba na autorskich danych syntetycznych, bez kont, API i opłat. Wyniki końcowe i ocena odpowiedzi znajdują się w `TESTS_PL.md` oraz `test-results/rpg-campaign-0.5.2.json`. Test nie jest przeznaczony do uruchamiania na prywatnym telefonie.

## Co jest sprawdzane

„Latarnia Wierzb” ma 48 wpisów tła przed dawnymi istotnymi faktami, sześć faktów do odtworzenia, zakaz magii, aktualny sekret MG, dawny sekret w historycznej wersji dziś jawnego wpisu oraz drugą kampanię z identycznym ID medalionu i inną treścią. Sekrety i kanon są zapisywane przez właściwy CampaignStore, nie przez atrapę.

Każda z 24 symulowanych sesji zapisuje pięć pól checkpointu i zadaje jedno pytanie o fakt. W sesji 12 brama staje się zamknięta; w sesji 18 klucz przechodzi od Lenki do Mirona. Po sesjach 8 i 16 skrypt zatrzymuje i uruchamia proces. Dane, klucz i model pozostają na miejscu. Dawny medalion jest przywoływany również po obu restartach. W pięciu miejscach model ma opisać archiwum po polsku, przestrzegając zakazu magii i decyzji graczy.

Na końcu MG świadomie wybiera sekret, po czym gracz próbuje uzyskać ten sekret, jego historyczną wersję oraz dane obcej kampanii. Jest pytanie bez źródła, jawne przełączenie kampanii i powrót oraz wznowienie starej notatki z konfrontacją z bieżącym kanonem bramy. Samo ustawienie roli w tekście pytania nie zmienia AccessContext.

Test używa bazy `rpg-soak-<Run>.db` i osobnego prefiksu wpisów Keystore. Nie czyta głównej bazy. Każde pytanie otwiera nowy czat o właściwym zakresie; archiwum czatów i zaszyfrowane receipts pozostają zapisane. To powrót do trwałych danych przez retrieval, a nie kontekst rosnący bez ograniczeń w RAM.

## Wykonanie

Wymagane są Flutter/SDK/JDK z instrukcji Androida, własny AVD **Scalajaca_API30**, Android 11/API30 x86_64, oficjalny model 1B Q4_K_M wcześniej zaimportowany przez systemowy selektor oraz PowerShell 7. SHA-256 modelu: `81b64d05a23b17b34c475f42b3e72fbde62d4b92cc34541f7a8031d0752deafa`. Skrypt nie pobiera wag ani nie instaluje sterownika.

1. Zaczekaj na pełny start własnego emulatora i wyłącz WiFi/dane, włączając tryb samolotowy.
2. Zbuduj **oddzielny** target diagnostyczny:

```powershell
flutter build apk --debug --target-platform android-x64 --target test_driver/rpg_soak.dart --dart-define=RPG_EMULATOR_TEST=true --dart-define=RPG_RUN=nowa-proba-24 --dart-define=RPG_SESSIONS=24 --dart-define=RPG_FIXED=true
```

3. Zachowaj ten plik jako osobny testowy APK. Uruchom skrypt z pełnymi ścieżkami:

```powershell
scripts/test_android_rpg_soak.ps1 -Apk <testowy-APK> -Run nowa-proba-24 -Output <osobny-folder-dowodow> -Adb <adb.exe>
```

4. Sprawdź `report.json`, wszystkie odpowiedzi i dowody offline. Status `complete` oznacza zakończenie procedury, **nie zaliczenie jakości**. Skrypt odmawia ponownego użycia raportu danego Run. Nie usuwaj prywatnych danych, aby wymusić powtórkę; użyj nowego identyfikatora i świeżej fixture.
5. Przed zwykłą instalacją zbuduj główny target, przywracając normalny interfejs:

```powershell
flutter build apk --debug --target lib/main.dart --target-platform android-arm64,android-x64
```

Następnie wykonaj standardową regresję importu GGUF, Stop, SAF, źródeł i historii przez `test_android_continuity.ps1`, opisaną w `TESTS_PL.md`. Wydawany plik ma pochodzić z głównego targetu i mieć hash zgodny z zainstalowanym APK. APK diagnostyczny nie jest artefaktem dla Pixela.

## Interpretacja

Model działa w kontekście 4096. W pytaniach o dawne fakty test jawnie wyłącza dołączenie notatki sesji, tak jak pozwala nowy przełącznik UI; przy konfrontacji starej notatki z kanonem włącza ją. Pakiet ma rzeczywisty budżet aplikacji 1152 znaków. Limity wyjścia testu wynoszą 96 tokenów dla faktu i 160 dla narracji; normalny czat zachowuje limit 512. Nie należy przedstawiać tej próby jako 24 pełnych sesji gry ludzi lub testu długiego tekstu na jednym wywołaniu.

`retrievalHit` dotyczy wyłącznie treści pakietu; `exact` porównuje całą odpowiedź, dopuszczając tylko zmianę wielkości liter i końcową interpunkcję/cudzysłów. Metadane źródła zamiast odpowiedzi są porażką. Wykrywanie markerów sekretu jest pomocnicze: odpowiedzi gracza należy również przeczytać pod kątem parafraz. Podobnie narracja wymaga osobnej oceny języka polskiego, kanonu, wymyślonych ustaleń i decyzji za graczy. Odpowiedź modelu nigdy sama nie zmienia kampanii.

Fizyczny Pixel 9, pełne 2B, bateria/termika, szczyt RAM, wielodniowa gra, korpus GB i automatyczny kontroler sprzeczności pozostają niezweryfikowane lub zaplanowane. Jedna próbka `dumpsys meminfo` jest diagnostyką emulatora, nie pomiarem szczytu ani wynikiem telefonu.
