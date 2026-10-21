#!/usr/bin/env python3
"""Niezależna kontrola dense i próbek ekspertów względem kwantyzatora upstream C.

Najpierw --write-oracle oracle.c, następnie skompiluj C lokalnym kompilatorem.
Kontrola: --model źródło --converted wynik --oracle oracle.exe --report raport.json.
Bez sieci. Ścieżka oracle oznacza jawnie wybrany lokalny program, nie plik z modelu.
"""
import argparse
import hashlib
import json
import pathlib
import struct
import subprocess
import tempfile

import numpy as np
from convert_streaming import EXPERT, SKIP, digest, header, to_float

REPO = pathlib.Path(__file__).resolve().parents[2]


def write_oracle(path):
    # Wyłącznie przypięte, uprzednio skontrolowane źródło z repo, nigdy z wag.
    source = REPO / 'third_party/colibri/c/quant.h'
    expected = next(line.split()[0] for line in (source.parents[1] / 'SHA256SUMS.txt').read_text().splitlines()
                    if line.split()[-1] == 'c/quant.h')
    if digest(source) != expected:
        raise ValueError('Zmodyfikowane źródło kwantyzatora')
    code = source.read_text()
    function = code[code.index('static void quantize_rows('):code.index('static void pack_int4(')]
    program = ('/* Colibri e0db083c, quant.h; Apache-2.0, LICENSE/NOTICE w third_party/colibri. */\n'
               '#include <math.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>\n' + function + r'''
int main(int argc,char**argv) {
 if(argc!=3)return 2;
 FILE *in=fopen(argv[1],"rb"),*out=fopen(argv[2],"wb"); if(!in||!out)return 3;
 int O=0,I=0; if(fread(&O,4,1,in)!=1||fread(&I,4,1,in)!=1)return 4;
 if(O<1||O>10000||I<1||I>4096)return 4;
 float *w=malloc((size_t)O*I*4),*s=malloc((size_t)O*4);int8_t*q=malloc((size_t)O*I);
 if(!w||!s||!q)return 5;
 if(fread(w,4,(size_t)O*I,in)!=(size_t)O*I)return 6;
 quantize_rows(w,q,s,O,I,8);fwrite(q,1,(size_t)O*I,out);fwrite(s,4,O,out);
 if(fclose(in)||fclose(out))return 7;free(w);free(s);free(q);return 0;
}
''')
    with pathlib.Path(path).open('x', encoding='utf-8', newline='\n') as out:
        out.write(program)


def tensor_sha(entry):
    h = hashlib.sha256()
    remain = entry['data_offsets'][1] - entry['data_offsets'][0]
    with entry['file'].open('rb') as f:
        f.seek(entry['absolute'])
        while remain:
            b = f.read(min(remain, 4 * 1024**2))
            if not b: raise ValueError('Urwany tensor')
            h.update(b); remain -= len(b)
    return h.hexdigest()


def verify(source, converted, oracle):
    source, converted, oracle = map(lambda p: pathlib.Path(p).resolve(), (source, converted, oracle))
    if source in oracle.parents or converted in oracle.parents:
        raise ValueError('Nie wolno uruchamiać programu pochodzącego z katalogu modelu')
    src, dst = {}, {}
    for folder, target in ((source, src), (converted, dst)):
        for file in folder.glob('*.safetensors'):
            entries = header(file)
            if target.keys() & entries.keys(): raise ValueError('Powtórzony tensor')
            target.update(entries)
    dense = {n:e for n,e in dst.items() if '.mlp.experts.' not in n}
    wanted_dense = {n for n in src if not EXPERT.fullmatch(n) and not SKIP.search(n)}
    if set(dense) != wanted_dense:
        raise ValueError('Brakujące lub nadmiarowe dense tensory')
    wanted_experts = {f'model.layers.{l}.mlp.experts.{e}.{suffix}'
                      for l in range(16) for e in range(64) for suffix in ('merged_weight','qs')}
    if set(dst) != wanted_dense | wanted_experts:
        raise ValueError('Brakujące lub nadmiarowe tensory wyjściowe')
    for name in wanted_experts:
        shape, dtype = ([4096], 'F32') if name.endswith('.qs') else ([6291456], 'I8')
        if dst[name]['shape'] != shape or dst[name]['dtype'] != dtype:
            raise ValueError('Nieprawidłowa reprezentacja eksperta')
    for name, entry in dense.items():
        original = src[name]
        if entry['dtype'] != original['dtype'] or entry['shape'] != original['shape'] or tensor_sha(entry) != tensor_sha(original):
            raise ValueError('Niezgodne dense: ' + name)
    compared = 0
    with tempfile.TemporaryDirectory() as tmp:
        inp, out = pathlib.Path(tmp)/'in.bin', pathlib.Path(tmp)/'out.bin'
        for layer in range(16):
            for projection, qoff, soff in (('gate_proj', 0, 0), ('up_proj', 2097152, 4096), ('down_proj', 4194304, 8192)):
                values, locations = [], []
                for expert in range(64):
                    base = f'model.layers.{layer}.mlp.experts.{expert}'
                    entry = src[base+'.'+projection+'.weight']
                    n, d = entry['shape']
                    if entry['dtype'] != 'BF16': raise ValueError('Kontrola przeznaczona dla źródła BF16')
                    with entry['file'].open('rb') as f:
                        for row in (0, n//2, n-1):
                            f.seek(entry['absolute'] + row*d*2)
                            values.append(to_float(f.read(d*2), 'BF16', (1,d)))
                            locations.append((base,row,d))
                weights = np.concatenate(values)
                # Floor skali w C wynosi1e-8, a konwerter upstream Python ma
                # max(abs(w),1e-12)/127. Nie ukrywamy tej różnicy dla tiny rows.
                if not np.all(np.max(np.abs(weights),axis=1)/127 >= 1e-8):
                    raise ValueError('Próbka wpada w różne floor skali C/Python')
                inp.write_bytes(struct.pack('<ii', *weights.shape) + weights.tobytes())
                subprocess.run([str(oracle), str(inp), str(out)], check=True, timeout=60, stdout=subprocess.DEVNULL)
                actual = out.read_bytes()
                rows, dim = weights.shape
                if len(actual) != rows*dim + rows*4: raise ValueError('Nieprawidłowy wynik wzorca C')
                q, scales = actual[:rows*dim], actual[rows*dim:]
                for i,(base,row,d) in enumerate(locations):
                    for suffix, offset, expected in (
                        ('.merged_weight', qoff + row*d, q[i*d:(i+1)*d]),
                        ('.qs', soff + row*4, scales[i*4:(i+1)*4])):
                        entry = dst[base+suffix]
                        with entry['file'].open('rb') as f:
                            f.seek(entry['absolute']+offset)
                            if f.read(len(expected)) != expected:
                                raise ValueError(f'Niezgodność: {base} {projection} row{row} {suffix}')
                    compared += 1
            print(f'Warstwa {layer}: PASS', flush=True)
    return dict(denseTensors=len(dense), allDenseBytesIdentical=True, experts=1024, projections=3072,
                rowsCompared=compared, allSampledInt8AndScaleBytesIdentical=True,
                fullTensorComparison=False, oracleExecutableSha256=digest(oracle))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--write-oracle', type=pathlib.Path)
    p.add_argument('--model', type=pathlib.Path)
    p.add_argument('--converted', type=pathlib.Path)
    p.add_argument('--oracle', type=pathlib.Path)
    p.add_argument('--report', type=pathlib.Path)
    args = p.parse_args()
    if args.write_oracle:
        write_oracle(args.write_oracle)
    else:
        if not all((args.model,args.converted,args.oracle,args.report)): p.error('Wskaż wszystkie ścieżki kontroli')
        result = verify(args.model,args.converted,args.oracle)
        with args.report.open('x',encoding='utf-8') as out: json.dump(result,out,indent=2);out.write('\n')
        print(json.dumps(result), flush=True)
