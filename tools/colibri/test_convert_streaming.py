import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from convert_streaming import convert, digest, ensure_shard, header, quantize_row, quantize_tensor, to_float, write_shard
from package_model import EXPECTED


class ConversionTest(unittest.TestCase):
    def test_bfloat16_preserves_signed_values(self):
        values = np.array([[1., -2., 0., 0.5]], dtype='<f4')
        raw = (values.view('<u4') >> 16).astype('<u2').tobytes()
        np.testing.assert_array_equal(values, to_float(raw, 'BF16', (1, 4)))

    def test_quantization_ties_even_and_row_scales(self):
        # Skala1: dokładne półliczby sprawdzają round-to-even, nie trunc/away.
        w = np.array([[127., 0.5, 1.5, -0.5, -1.5, -127.], [254., 1., 3., -1., -3., -254.]], dtype='<f4')
        q, scales = quantize_row(w)
        np.testing.assert_array_equal(q, [[127, 0, 2, 0, -2, -127]] * 2)
        np.testing.assert_array_equal(scales, [1., 2.])
        q, scales = quantize_row(np.zeros((1, 5), dtype='<f4'))
        np.testing.assert_array_equal(q, [[0] * 5])
        self.assertGreater(scales[0], 0.)
        for v in (float('nan'), float('inf')):
            with self.assertRaises(ValueError):
                quantize_row([[v, 1.]])

    def test_chunked_projection_matches_independent_scalar_reference(self):
        rng = np.random.default_rng(749)
        weights = rng.normal(size=(131, 17)).astype('<f4')
        raw = (weights.view('<u4') >> 16).astype('<u2').tobytes()
        weights = to_float(raw, 'BF16', weights.shape)
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            source = tmp / 'source.safetensors'
            write_shard(source, [('w', 'BF16', [131, 17])], lambda f: f.write(raw))
            with (tmp / 'q.bin').open('wb') as out:
                scales = quantize_tensor(out, header(source)['w'], rows=7)
            expected, expected_scales = [], []
            # Oddzielne operacje skalarne f32, bez broadcast/redukcji NumPy.
            f32 = lambda x: struct.unpack('<f', struct.pack('<f', x))[0]
            for row in weights:
                scale = f32(max(max(abs(float(x)) for x in row), f32(1e-12)) / 127.)
                expected_scales.append(scale)
                expected.extend(round(f32(float(x) / scale)) for x in row)
            self.assertEqual(np.array(expected, dtype='i1').tobytes(), (tmp / 'q.bin').read_bytes())
            np.testing.assert_array_equal(scales, expected_scales)

    def test_header_rejects_truncation_collision_duplicate_and_trailing_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / 'weights.safetensors'
            write_shard(file, [('a', 'F32', [1]), ('b', 'F32', [1])], lambda f: f.write(struct.pack('<ff', 1., 2.)))
            self.assertEqual({'a', 'b'}, set(header(file)))
            original = file.read_bytes()
            for bad in (original[:-1], original + b'x'):
                file.write_bytes(bad)
                with self.assertRaises(ValueError): header(file)
            for raw in (b'{"a":{"dtype":"F32","shape":[1],"data_offsets":[0,4]},"a":{"dtype":"F32","shape":[1],"data_offsets":[4,8]}}',
                        json.dumps(dict(a=dict(dtype='F32', shape=[1], data_offsets=[0,4]), b=dict(dtype='F32', shape=[1], data_offsets=[0,4]))).encode()):
                file.write_bytes(struct.pack('<Q', len(raw)) + raw + bytes(8))
                with self.assertRaises(ValueError): header(file)

    def test_partial_write_is_not_published(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / 'weights.safetensors'
            with self.assertRaises(ValueError):
                write_shard(file, [('a', 'F32', [2])], lambda f: f.write(bytes(4)))
            self.assertFalse(file.exists())

    def test_restart_between_durable_receipt_and_rename_recovers_verified_partial(self):
        with tempfile.TemporaryDirectory() as tmp:
            file=Path(tmp)/'model-00000.safetensors'; receipts={}
            def interrupted(item):
                receipts[item['file']]=item
                raise InterruptedError('Przerwanie po zapisie potwierdzenia')
            specs=[('w','F32',[2])]
            with self.assertRaises(InterruptedError):
                ensure_shard(file,specs,lambda f:f.write(bytes(8)),receipts,interrupted)
            self.assertFalse(file.exists())
            partial=file.with_suffix('.safetensors.partial')
            self.assertTrue(partial.exists())
            # Wznowienie weryfikuje hash; nie przelicza ani nie gubi receiptu.
            with patch('convert_streaming.write_shard') as rewrite:
                result=ensure_shard(file,specs,None,receipts,None)
                rewrite.assert_not_called()
            self.assertTrue(file.exists());self.assertFalse(partial.exists())
            self.assertEqual(receipts[file.name],result)

    def test_invalid_existing_shard_does_not_erase_previous_journal(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'source';output=root/'converted'
            source.mkdir();output.mkdir()
            (source/'config.json').write_text(json.dumps(dict(model_type='olmoe',**EXPECTED)))
            model=source/'model.safetensors';model.write_bytes(b'fixture')
            existing=output/'model-00000.safetensors';existing.write_bytes(b'changed')
            receipt=dict(file=existing.name,bytes=7,sha256='0'*64)
            old=dict(sourceFiles=[dict(file=model.name,bytes=7,sha256=digest(model))],
                     converterSha256=digest(Path(__file__).parent/'convert_streaming.py'),outputFiles=[receipt])
            provenance=output/'conversion.json';provenance.write_text(json.dumps(old))
            tensors={}
            for layer in range(16):
                for expert in range(64):
                    for projection in ('gate_proj','up_proj','down_proj'):
                        name=f'model.layers.{layer}.mlp.experts.{expert}.{projection}.weight'
                        tensors[name]=dict(dtype='BF16',shape=[2048,1024] if projection=='down_proj' else [1024,2048])
            with patch('convert_streaming.header',return_value=tensors):
                with self.assertRaisesRegex(ValueError,'potwierdzonego'):
                    convert(source,output)
            self.assertEqual([receipt],json.loads(provenance.read_text())['outputFiles'])


if __name__ == '__main__': unittest.main()
