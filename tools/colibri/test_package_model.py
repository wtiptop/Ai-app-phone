"""Kontrakt paczki/manifestu na sztucznych plikach, bez prawdziwych wag."""
import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from package_model import EXPECTED, package


class PackageContractTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        (self.path / "config.json").write_text(json.dumps(dict(model_type="olmoe", **EXPECTED)), encoding="utf-8")
        (self.path / "tokenizer.json").write_text('{"model":{"type":"BPE"}}', encoding="utf-8")
        (self.path / "model.safetensors").write_bytes(b"FORMAT TEST ONLY; NOT WEIGHTS")

    def test_archive_hashes_and_order(self):
        output = self.path / "test.zip"
        package(self.path, output, "TEST", "synthetic")
        with zipfile.ZipFile(output) as z:
            self.assertEqual("manifest.json", z.namelist()[0])
            manifest = json.loads(z.read("manifest.json"))
            self.assertEqual("olmoe-instruct", manifest["profile"])
            for entry in manifest["files"]:
                raw = z.read(entry["name"])
                self.assertEqual(len(raw), entry["bytes"])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), entry["sha256"])

    def test_existing_output_is_preserved(self):
        output = self.path / "existing.zip"
        output.write_bytes(b"PRESERVE")
        with self.assertRaises(ValueError):
            package(self.path, output, "TEST", "synthetic")
        self.assertEqual(b"PRESERVE", output.read_bytes())

    def test_incompatible_profile_is_rejected_before_zip(self):
        (self.path / "config.json").write_text('{"model_type":"llama"}')
        output = self.path / "bad.zip"
        with self.assertRaises(ValueError):
            package(self.path, output, "TEST", "synthetic")
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
