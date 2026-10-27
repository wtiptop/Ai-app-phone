import hashlib
import json
import pathlib
import tempfile
import unittest
from join_release_parts import join


class JoinPartsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.data = b'PK-model-\x00\xff-pelne-wagi'
        self.parts = [self.data[:7], self.data[7:]]
        self.manifest = dict(schemaVersion=1, file='model.zip', bytes=len(self.data),
                             sha256=hashlib.sha256(self.data).hexdigest(), parts=[])
        for i, data in enumerate(self.parts):
            name = f'model.zip.part{i + 1:03}'
            (self.root / name).write_bytes(data)
            self.manifest['parts'].append(dict(file=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
        self.path = self.root / 'parts.json'
        self.save()

    def save(self):
        self.path.write_text(json.dumps(self.manifest), encoding='utf-8')

    def test_join_and_existing_identical_file(self):
        target = join(self.path)
        self.assertEqual(target.read_bytes(), self.data)
        self.assertEqual(join(self.path), target)
        self.assertFalse((self.root / 'model.zip.partial').exists())

    def test_corrupt_same_size_never_publishes_zip(self):
        (self.root / self.manifest['parts'][1]['file']).write_bytes(b'x' * len(self.parts[1]))
        with self.assertRaises(ValueError):
            join(self.path)
        self.assertFalse((self.root / 'model.zip').exists())
        self.assertTrue((self.root / 'model.zip.partial').exists())

    def test_existing_different_output_not_overwritten(self):
        target = self.root / 'model.zip'
        target.write_bytes(b'prywatny plik')
        with self.assertRaises(FileExistsError):
            join(self.path)
        self.assertEqual(target.read_bytes(), b'prywatny plik')

    def test_path_traversal_rejected(self):
        self.manifest['parts'][0]['file'] = '../model.zip.part001'
        self.save()
        with self.assertRaises(ValueError):
            join(self.path)
        self.assertFalse((self.root / 'model.zip.partial').exists())

    def test_missing_part_rejected_before_writing(self):
        (self.root / self.manifest['parts'][0]['file']).unlink()
        with self.assertRaises(ValueError):
            join(self.path)
        self.assertFalse((self.root / 'model.zip.partial').exists())

    def test_duplicate_name_rejected(self):
        self.manifest['parts'][1]['file'] = self.manifest['parts'][0]['file']
        self.save()
        with self.assertRaises(ValueError):
            join(self.path)


if __name__ == '__main__':
    unittest.main()
