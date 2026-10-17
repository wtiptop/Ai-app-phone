# ADR 003 — odzyskiwanie i kopie

Status: przyjęte 2026-10-17.

SQLite pozostaje jedynym źródłem trwałego stanu lokalnego. Po awarii nie ponawiamy automatycznie operacji sieciowych; zaznaczamy przerwane odpowiedzi. Eksport i backup są dostępne bez Obsidiana. Import kopii jest append-only i atomowy. Jawny eksport Markdown wymaga ręcznej akcji; zaszyfrowany backup używa osobnego hasła i nie zawiera API keys. Wyłączony Android Auto Backup zapobiega odtworzeniu szyfrogramów bez lokalnego klucza Keystore.

Metadane SQLite nie są szyfrowane; sekrety nigdy nie trafiają do ustawień bazy. Utrata Keystore bez zaszyfrowanej kopii oznacza utratę dostępu do treści. Tryb prywatny nie zapisuje rozmowy w DB. Pełne SQLCipher, blokada biometryczna, profile wielu osób i synchronizacja pozostają zaplanowane.
