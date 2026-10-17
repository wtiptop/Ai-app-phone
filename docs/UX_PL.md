# UX mobilnej Scalającej

Projekt interakcji na 17.10.2026. Makiety opisują **docelowe zachowanie**, a nie dowód, że każdy ekran już działa. Zakres aktualnego kodu i testów opisują `IMPLEMENTATION_STATUS.md` i `TESTS_PL.md`.

## Zasady

Język domyślny polski. Aplikacja startuje lokalnie bez kont, kluczy i sieci. Dostawca i model są widoczne przed wysyłką oraz przy każdej odpowiedzi. Koszt nieznany jest opisany jako „nieznany”, nigdy „0”. Demo ma stałą etykietę „Demo lokalne — bez połączenia z AI”. Funkcja planowana pokazuje „Zaplanowane”, wyjaśnienie i żadnego przycisku udającego jej wykonanie. Pięć statusów integracji jest zapisanych słownie, bez polegania wyłącznie na kolorze.

Dolna nawigacja ma pięć stałych miejsc. Na najmniejszych ekranach dopuszczalny krótki podpis „Pamięć”; nagłówek ekranu pozostaje „Projekty i pamięć”. Android Wstecz najpierw zamyka dialog/klawiaturę, potem widok szczegółu. Zmiana karty zachowuje szkic. Przycisk wysłania nie może zniknąć za klawiaturą.

## Pierwsze uruchomienie i prywatność

```text
Scalająca
Twoje rozmowy na tym telefonie.
Internet jest potrzebny do modeli chmurowych.
OPPO i Obsidian są opcjonalne.

[Rozpocznij w demo bez konta]   ← domyślny wybór
[Skonfiguruj dostawcę API] [Importuj dane]

Prywatność
[✓] Zapisuj rozmowy lokalnie
[✓] Potwierdzaj wysyłanie do kilku dostawców
[✓] Nie wysyłaj danych osobistych recenzentom
[ ] Tryb prywatny — bez trwałego zapisu treści

Domyślnie brak mikrofonu, aparatu i analityki treści.
[Jak chronimy dane] [Dalej]
```

Włączenie „trybu prywatnego” wyjaśnia różnicę między brakiem trwałego zapisu na telefonie a wysłaniem do wybranego AI. Nie usuwa poprzedniej historii bez osobnej czynności. Użytkownik może zmienić zgody w Ustawieniach. Zakupów, live testów API ani OAuth nie uruchamia sam onboarding.

## Czat

```text
Czat                         [Historia] [+ Nowa]
Tryb [Jeden model ▼]   [Demo lokalne ▼]
Model: demo / status: działa lokalnie
Projekt: INBOX        [Zapis lokalny: włączony]
────────────────────────────────────────────
Ty • 14:20
Treść pytania

Demo lokalne • 14:20 • odpowiedź testowa
Treść... [Kopiuj] [Ponów] [Eksportuj]
Stan: strumieniowanie  [Zatrzymaj]
────────────────────────────────────────────
[Napisz wiadomość…                    ]
[Załącznik] [Push-to-talk: zaplanowane] [Wyślij]
 Czat | Agenci | Pamięć | Zadania | Ustawienia
```

Historia: pole wyszukiwania, data, projekt, etykieta dostawcy. Pusty ekran zaprasza do pierwszej lokalnej rozmowy. Błąd sieci nie usuwa szkicu ani części odpowiedzi. Stan „zatrzymano” odróżnia anulowanie od błędu i od pełnego zakończenia. „Ponów” tworzy nową próbę i uprzedza o możliwym dodatkowym koszcie. Edytowanie wcześniejszej wiadomości docelowo tworzy gałąź zamiast nadpisywać audytowalną historię.

Porównanie: 2–4 karty przewijane poziomo z nazwą/model/stan/koszt/usage. Widoczne są postępy i błędy każdej karty; awaria jednej nie zatrzymuje pozostałych. Dla 2 kart opcja „Jedna pod drugą” ułatwia czytanie przy dużym tekście. Przycisk „Zatrzymaj wszystkie” oraz zatrzymanie jednej. Wybór „Użyj tej odpowiedzi” nie zmienia obiektywnej prawdziwości treści.

## Agenci

```text
Agenci                              [+ Plan]
[Zadanie / rola / status]
Plan: 1. analiza 2. wykonanie 3. niezależna kontrola
Dostawcy: …     Dane: wybrane fragmenty …
Budżet: …       Kroki: 0/6  Czas: 0/120 s
[Podgląd danych] [Zatwierdź uruchomienie]
Przebieg: decyzja → wynik → kontrola → raport
[Zatrzymaj] [Wznów] [Zapisz fakt do pamięci]
```

Brak gotowego orkiestratora: jawny ekran informacyjny „Zaplanowane — żaden agent nie jest uruchamiany”. Korekty maksymalnie dwie domyślnie, kontroler ma osobną rolę. Każda zgoda pokazuje zakres i skutek, a odmowa pozostawia plan do edycji.

## Projekty i pamięć

```text
Projekty i pamięć          [+ Notatka] [Import]
[Szukaj lokalnie…                          ]
SYSTEM / INBOX / PERSONAL / RESEARCH / TECH
FINANCE / GAMING / RPG / COMMUNICATIONS
REVIEWS / ARCHIVE
────────────────────────────────────────────
Notatka • projekt • źródło • widoczność
[Otwórz] [Popraw] [Eksport] [Zapomnij]
Fakt długoterminowy: oczekuje na zatwierdzenie
```

Zwykły czat nigdy nie włącza sekretów MG do wyników. Szczegół rekordu pokazuje autora, czas, wersję, źródło, pewność, właściciela i zakres. Import SAF pozwala wybrać plik/katalog i najpierw pokazuje podgląd, konflikty i zakres. Obsidian nie jest wymagany. Eksport rozróżnia plik Markdown do świadomego udostępnienia i szyfrowaną kopię do odtworzenia. Ryzyko jawnego Markdown jest widoczne przed udostępnieniem.

## Zadania

```text
Zadania                          [+ Zadanie]
[Lokalne] [Oczekujące] [Zakończone]
Tytuł • status • następne wykonanie
Ostatnie wykonanie / próby / ostatni błąd
Harmonogram: lokalny best-effort
Android może opóźnić wykonanie w tle.
[Szczegóły] [Odłóż] [Zatrzymaj] [Ponów]
```

Kolejka przechowuje zamiar, a nie zgodę bezterminową na przyszłą opłatę. Wznowienie po restarcie ponownie sprawdza klucz, zgodę, dane i budżet. Identyfikator deduplikacji chroni przed powieleniem czynności. Zdalny harmonogram jest osobną wyłączoną opcją.

## Ustawienia i dostawcy

```text
Ustawienia
Dostawcy AI [OpenAI] [Claude] [Gemini] [Grok]
  Typ: API BYOK / status: wymaga konfiguracji
  API rozliczane osobno od abonamentu aplikacji.
  Klucz: [••••••] [Zapisz] [Usuń]
  Model: [edytowalny identyfikator]
  [Test połączenia — może zużyć środki]
  Dane przetwarza: nazwa dostawcy / link polityki
Koszty i budżety / Prywatność i zgody
Eksport i kopie / Język i motyw / Diagnostyka
Integracje opcjonalne: OPPO [wyłączone], Obsidian
```

Nie ma przycisku „Zaloguj do abonamentu” dla niedostępnego programu. Punkt rozszerzenia SSO pokazuje „wymaga zatwierdzenia dostawcy” z opisem, bez otwierania fałszywego formularza. Usunięcie klucza usuwa poświadczenie i blokuje kolejne wywołania, nie usuwa historii rozmów.

## Budżet i świadoma wysyłka

```text
Uruchomić porównanie?
Odbiorcy: OpenAI / model A, Anthropic / model B
Dane: bieżąca wiadomość + ostatnie N wiadomości
Załączniki: … [podgląd]  Pamięć: wybrane 3 fragmenty
Szacunek: … waluta, według cennika z …
Budżet dnia: … / …    pozostało: …
Koszt nieznany? Wymagaj ręcznego limitu lub odmów.
[Anuluj] [Zatwierdź to uruchomienie]
```

Budżet lokalny obejmuje wywołania tej aplikacji. Przy nieznanej cenie nie wyświetla zera. Równoległe zadania rezerwują budżet atomowo przed startem. Fallback ujawnia nowego odbiorcę i model; przy braku pasującej uprzedniej polityki wymaga nowej zgody. Materiały z internetu i dokumentów są oznaczone jako niezaufane źródła, a nie instrukcje uprawniające do działania.

## Dostępność i stany błędów

Wymagane: dotyk minimum 48 dp, kontrast tekstu 4,5:1, tekst 200% bez ucięcia ważnych akcji, TalkBack z nazwami przycisków i spokojnym podsumowaniem streamu zamiast odczytu każdego tokena; focus nie przeskakuje podczas streamowania. Błędy mają przyczynę i czynność: „Brak klucza — skonfiguruj”, „Brak sieci — szkic zapisany”, „Limit dostawcy — spróbuj później”, „Budżet wyczerpany — zadanie niewysłane”. Diagnostyka domyślnie nie zawiera treści ani poświadczeń. Akcje usuwania danych wymagają konkretnego zakresu i potwierdzenia; ponowienie nie jest automatyczne dla niepewnej płatnej próby.
