"""Składa części wydania GitHub i sprawdza SHA-256 przed publikacją ZIP."""
import argparse
import hashlib
import json
import os
import pathlib
import re

BLOCK = 4 * 1024 * 1024


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def join(manifest_path, output=None):
    manifest_path = pathlib.Path(manifest_path).resolve()
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    if not isinstance(manifest, dict) or manifest.get('schemaVersion') != 1:
        raise ValueError('Nieobsługiwana wersja manifestu części.')
    names = set()
    parts = manifest.get('parts', [])
    if not isinstance(parts, list) or not 1 <= len(parts) <= 100 or not all(isinstance(p, dict) for p in parts):
        raise ValueError('Niekompletny manifest części.')
    for item in [manifest, *parts]:
        name = item.get('file', '')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,180}', name):
            raise ValueError('Niedozwolona nazwa pliku w manifeście.')
        if name in names:
            raise ValueError('Powtórzona nazwa pliku w manifeście.')
        names.add(name)
        if not re.fullmatch(r'[a-f0-9]{64}', item.get('sha256', '')):
            raise ValueError('Nieprawidłowy SHA-256 w manifeście.')
        if type(item.get('bytes')) is not int or item['bytes'] <= 0:
            raise ValueError('Nieprawidłowy rozmiar w manifeście.')
    if not 1 <= len(parts) <= 100 or sum(p['bytes'] for p in parts) != manifest['bytes']:
        raise ValueError('Niekompletny manifest części.')
    target = pathlib.Path(output).resolve() if output else manifest_path.parent / manifest['file']
    sources = [manifest_path.parent / p['file'] for p in parts]
    if target in [p.resolve() for p in sources] or target == manifest_path:
        raise ValueError('ZIP wyjściowy nie może zastępować części ani manifestu.')
    if target.exists():
        if target.stat().st_size == manifest['bytes'] and digest(target) == manifest['sha256']:
            return target
        raise FileExistsError('Plik wyjściowy już istnieje i ma inną sumę; nie nadpisuję go.')
    for item, source in zip(parts, sources):
        if source.is_symlink() or not source.is_file() or source.stat().st_size != item['bytes']:
            raise ValueError('Brak części lub niewłaściwy rozmiar: ' + item['file'])
    partial = target.with_name(target.name + '.partial')
    combined = hashlib.sha256()
    # Tryb xb nie nadpisuje wcześniejszego wyniku/przerwanego składania.
    with partial.open('xb') as sink:
        for item, source in zip(parts, sources):
            hasher = hashlib.sha256()
            size = 0
            with source.open('rb') as stream:
                while chunk := stream.read(BLOCK):
                    hasher.update(chunk)
                    combined.update(chunk)
                    size += len(chunk)
                    sink.write(chunk)
            if size != item['bytes'] or hasher.hexdigest() != item['sha256']:
                raise ValueError('Uszkodzona część: ' + item['file'] + '; pozostawiono .partial.')
    if partial.stat().st_size != manifest['bytes'] or combined.hexdigest() != manifest['sha256']:
        raise ValueError('Suma złożonego ZIP nie pasuje; pozostawiono .partial.')
    # Windows rename i POSIX link nie nadpiszą celu utworzonego w międzyczasie.
    if os.name == 'nt':
        os.rename(partial, target)
    else:
        os.link(partial, target)
        partial.unlink()
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    try:
        print('Gotowy ZIP, SHA-256 zgodny:', join(args.manifest, args.output))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, 'Nie złożono modelu: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
