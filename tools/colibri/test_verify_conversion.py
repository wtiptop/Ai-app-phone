import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from convert_streaming import write_shard
from verify_conversion import verify


class VerificationCompletenessTest(unittest.TestCase):
    def test_missing_or_extra_dense_cannot_be_reported_as_success(self):
        for missing in (True, False):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root/'source'; target = root/'converted'
                source.mkdir(); target.mkdir()
                write_shard(source/'model.safetensors', [('model.norm.weight','F32',[1])], lambda f: f.write(bytes(4)))
                if not missing:
                    write_shard(target/'model.safetensors', [('model.norm.weight','F32',[1]),('extra','F32',[1])], lambda f: f.write(bytes(8)))
                with patch('verify_conversion.subprocess.run') as execution:
                    with self.assertRaisesRegex(ValueError, 'dense'):
                        verify(source, target, root/'trusted-oracle.exe')
                    execution.assert_not_called()

    def test_executable_in_model_directory_is_not_executed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); source=root/'source'; target=root/'converted'
            source.mkdir(); target.mkdir()
            with patch('verify_conversion.subprocess.run') as execution:
                with self.assertRaisesRegex(ValueError, 'programu'):
                    verify(source,target,source/'oracle.exe')
                execution.assert_not_called()


if __name__ == '__main__': unittest.main()
