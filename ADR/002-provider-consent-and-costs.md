# ADR 002 — BYOK, jawne koszty i oficjalne transporty

Status: przyjęte 2026-10-17.

Każdy dostawca ma niezależny adapter, stały oficjalny HTTPS endpoint i parser SSE. Biblioteka http zamiast czterech SDK ogranicza zależności i umożliwia testy żądań przez lokalny MockClient. Timeouty/anulowanie są jawne. Automatyczne retry płatnych POST wyłączono, bo błąd transportu nie dowodzi braku naliczenia kosztu. Nie stosujemy fallbacku bez zgody.

Model i stawki podaje użytkownik lub świadomie pobiera katalog. Brak nazw 'najlepszych modeli' w kodzie. Katalog nie gwarantuje obsługi tekstu i dostępności. Nieznane ceny/kontekst pozostają nieznane. Każda realna wysyłka wymaga jednorazowego permit i trwałej rezerwy. Rezerwa według podanego cennika jest konserwatywnym szacunkiem i nie stanowi zdalnego limitu rachunku. Dostawca może naliczyć koszt po anulowaniu.

SSO i korzystanie z planów jest odrębnym kontraktem. OpenAI ma aktualną ścieżkę dla kwalifikujących się OSS; trzeba wdrożyć i zweryfikować osobny callback, PKCE, tokeny i zakres plan usage. Nie wolno wkleić tokenu sesji konsumenckiej do BYOK. Podłączenie kont wymaga późniejszej wyraźnej zgody właściciela.
