# ADR 001 — Flutter, stan i lokalne dane

Status: przyjęte 2026-10-17.

Flutter stable dla Androida, Material 3 i minimalny Kotlin platform channel do systemowych dokumentów i udostępniania. Rezygnacja z obowiązkowego backendu wynika z samodzielności telefonu. SQLite przez sqflite zapewnia utrzymywaną implementację, migracje i transakcje bez generatora kodu; FFI jest zależnością testową hosta. Pola treści szyfruje AES-GCM, klucz chroni flutter_secure_storage/Keystore. Nie deklarujemy pełnego szyfrowania pliku bazy.

Na MVP ChangeNotifier/StatefulWidget i Navigator ograniczają zależności i pozwalają wstrzykiwać repozytorium oraz adaptery do testów. Warstwa domenowa agentów nie importuje Fluttera. Przy rozroście UI należy wydzielić kontrolery funkcji i rozważyć Riverpod/router na podstawie realnej potrzeby, bez zmiany kontraktów domenowych. Widget Home jest obecnie duży — jego podział to zadanie porządkowe kolejnej iteracji.
