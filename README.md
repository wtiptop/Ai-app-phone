# Scalająca

Samodzielna aplikacja Flutter na Androida: lokalny czat AI, pamięć projektów,
lokalny vault Obsidiana i wersjonowane kampanie RPG. Serwer ani OPPO nie są
wymagane. MiniCPM i eksperymentalny Colibri OLMoE obliczają odpowiedzi w telefonie.

Dokumentacja projektu: [README_PL.md](README_PL.md).
Aktualny stan i ograniczenia: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

## APK i modele

Pliki instalacyjne są dystrybuowane osobno w [wydaniach GitHub](https://github.com/wtiptop/Ai-app-phone/releases).
Kod Git nie zawiera wag, kluczy, baz użytkownika ani backupów.
Obecne wydanie aplikacji: **0.5.5+12**, APK debug z ARM64 i x86_64.
Fizycznego Pixela 9 nie testowano; runtime sprawdzono na emulatorze x86_64.

- [Instalacja Androida](docs/SETUP_ANDROID_PL.md)
- [MiniCPM offline i import GGUF](docs/MINICPM_PL.md)
- [Colibri OLMoE offline](docs/COLIBRI_PL.md)
- [Pobieranie i składanie części modelu z GitHub](docs/PUBLIKACJA_GITHUB_PL.md)
- [Rzeczywiste wyniki testów](docs/TESTS_PL.md)

**Colibri pozostaje eksperymentalny.** Pełne wagi działają offline, jednak pięć
prób polskiej narracji nie przeszło odbioru. Wyniki faktów, narracji i ochrony
sekretów są opisane oddzielnie; nie deklarujemy niezawodnego Mistrza Gry.
