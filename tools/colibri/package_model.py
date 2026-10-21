#!/usr/bin/env python3
"""Pakuje lokalny, przekonwertowany OLMoE do instalacji offline w Androidzie.
Nie pobiera wag, nie wykonuje plików z modelu, nie wymaga bibliotek ML.
"""
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path

COMMIT = "e0db083cdc9e563e0766cc6fc661ef23c32298e0"
EXPECTED = dict(hidden_size=2048, num_hidden_layers=16, num_attention_heads=16,
                num_key_value_heads=16, num_experts=64, num_experts_per_tok=8,
                intermediate_size=1024, vocab_size=50304)


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def package(source, output, name, origin):
    source, output = Path(source).resolve(), Path(output).resolve()
    if output.exists():
        raise ValueError("Plik wyjściowy już istnieje; wybierz nową nazwę.")
    config = json.loads((source / "config.json").read_text(encoding="utf-8"))
    if config.get("model_type") != "olmoe" or any(config.get(k) != v for k, v in EXPECTED.items()):
        raise ValueError("Nieobsługiwana konfiguracja OLMoE Instruct.")
    paths = [source / "config.json", source / "tokenizer.json"] + sorted(source.glob("*.safetensors"))
    if len(paths) < 3 or len(paths) > 128 or not 1 <= len(name) <= 100 or not 1 <= len(origin) <= 300:
        raise ValueError("Niepoprawna lista plików lub metadane.")
    files, total = [], 0
    for path in paths:
        if path.is_symlink() or not path.is_file() or not re.fullmatch(r"(config\.json|tokenizer\.json|model(-[0-9]{5}(-of-[0-9]{5})?)?\.safetensors)", path.name):
            raise ValueError(f"Niedozwolony plik: {path.name}")
        size = path.stat().st_size
        if size < 1 or (path.name == "config.json" and size > 256 * 1024) or (path.name == "tokenizer.json" and size > 8 * 1024**2):
            raise ValueError(f"Niepoprawny rozmiar: {path.name}")
        total += size
        files.append(dict(name=path.name, bytes=size, sha256=digest(path)))
    if total > 10 * 1024**3:
        raise ValueError("Model przekracza limit 10 GiB portu.")
    manifest = json.dumps(dict(format=1, engineCommit=COMMIT, profile="olmoe-instruct",
                               name=name, source=origin, files=files), ensure_ascii=False,
                          separators=(",", ":")).encode("utf-8")
    # 'x' nigdy nie nadpisuje wcześniejszej paczki, ZIP64 obsługuje pliki >4 GiB.
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_STORED, allowZip64=True) as z:
        z.writestr("manifest.json", manifest)
        for path in paths:
            z.write(path, path.name)
    print(f"Paczka: {output}\nDane modelu: {total} B")
    print(f"SHA-256 manifestu: {hashlib.sha256(manifest).hexdigest()}")
    print(f"SHA-256 ZIP: {digest(output)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--name", default="OLMoE-1B-7B-0125-Instruct • Colibri int8")
    parser.add_argument("--source", default="https://huggingface.co/allenai/OLMoE-1B-7B-0125-Instruct")
    args = parser.parse_args()
    package(args.model, args.output, args.name, args.source)
