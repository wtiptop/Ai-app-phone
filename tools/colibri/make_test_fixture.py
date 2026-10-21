#!/usr/bin/env python3
"""Syntetyczny transformer MoE do testów portu; NIE jest wytrenowanym modelem.
Wagi przewidują A z obliczenia głowicy. Nie służy do pomiaru jakości ani wydajności.
Generator używa wyłącznie biblioteki standardowej Pythona.
"""
import hashlib
import json
import struct
import zipfile
from pathlib import Path

from package_model import COMMIT


def create(output):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    cfg = dict(model_type="olmoe", hidden_size=16, num_hidden_layers=1,
               num_attention_heads=2, num_key_value_heads=2, num_experts=2,
               num_experts_per_tok=1, intermediate_size=8, vocab_size=257,
               rope_theta=10000., rms_norm_eps=1e-5, norm_topk_prob=True)
    (output / "config.json").write_text(json.dumps(cfg), encoding="utf-8")
    direct = list(range(33, 127)) + list(range(161, 173)) + list(range(174, 256))
    mapping, extra = {}, 0
    for byte in range(256):
        point = byte if byte in direct else 256 + extra
        if byte not in direct:
            extra += 1
        mapping[chr(point)] = byte
    (output / "tokenizer.json").write_text(json.dumps(dict(model=dict(type="BPE", vocab=mapping, merges=[]),
        added_tokens=[dict(id=256, content="|||IP_ADDRESS|||", special=True)])), encoding="utf-8")
    header, data = {}, bytearray()

    def tensor(name, shape, value=0., dtype="F32", values=None):
        count = 1
        for dim in shape:
            count *= dim
        values = values if values is not None else [value] * count
        blob = struct.pack("<" + ("f" if dtype == "F32" else "b") * count, *values)
        begin = len(data)
        data.extend(blob)
        header[name] = dict(dtype=dtype, shape=shape, data_offsets=[begin, len(data)])

    tensor("model.embed_tokens.weight", [257, 16], 1.)
    tensor("lm_head.weight", [257, 16], values=[1. if i // 16 == 65 else 0. for i in range(257*16)])
    tensor("model.norm.weight", [16], 1.)
    p = "model.layers.0."
    for name in ["input_layernorm", "post_attention_layernorm", "self_attn.q_norm", "self_attn.k_norm"]:
        tensor(p + name + ".weight", [16], 1.)
    for name in ["q_proj", "k_proj", "v_proj", "o_proj"]:
        tensor(p + "self_attn." + name + ".weight", [16, 16])
    tensor(p + "mlp.gate.weight", [2, 16])
    for expert in range(2):
        tensor(p + f"mlp.experts.{expert}.merged_weight", [384], value=0, dtype="I8")
        tensor(p + f"mlp.experts.{expert}.qs", [32], 1.)
    blob = json.dumps(header, separators=(",", ":")).encode()
    blob += b" " * (-len(blob) % 8)
    (output / "model.safetensors").write_bytes(struct.pack("<Q", len(blob)) + blob + data)
    paths = [output / n for n in ["config.json", "tokenizer.json", "model.safetensors"]]
    manifest = dict(format=1, engineCommit=COMMIT, profile="synthetic-test", name="SYNTHETIC PORT TEST — NOT A CHAT MODEL",
        source="Scalajaca/tools/colibri/make_test_fixture.py", files=[dict(name=p.name, bytes=p.stat().st_size,
            sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in paths])
    raw = json.dumps(manifest, separators=(",", ":")).encode()
    with zipfile.ZipFile(output / "fixture.zip", "w", compression=zipfile.ZIP_STORED) as z:
        z.writestr("manifest.json", raw)
        for p in paths:
            z.write(p, p.name)
    (output / "manifest.json").write_bytes(raw)
    print("Syntetyczne dane testu:", output)


if __name__ == "__main__":
    import sys
    create(sys.argv[1])
