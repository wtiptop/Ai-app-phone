# ADR 004 — zgodny backend SQLite do testów Windows

Status: przyjęte 2026-10-17.

Android używa aktualnego `sqflite` 2.4.4+2. Testowy `sqflite_common_ffi` przypięto do 2.3.6 oraz `sqlite3` do zgodnej linii 2.9.x. Nowsza linia FFI 2.4.x wymusza sqlite3 3 i hook natywny, który w tym środowisku uruchamiał wykrywanie Visual Studio oraz dodatkowe pobieranie DLL, blokując testy przed ich wykonaniem. Nie zmienia to magazynu Androida ani formatu SQLite.

Po wyborze zgodnego backendu wszystkie 83 testy Flutter przeszły. `pubspec.lock` utrwala dokładne wersje. SDK w ścieżce zawierającej spację wymagało lokalnej krótkiej ścieżki Windows dla wywołań hooków; nie zmieniano kodu Fluttera ani pakietów w celu uzyskania pozytywnego wyniku. Przed aktualizacją testowych zależności należy ponowić testy migracji i hosta.
