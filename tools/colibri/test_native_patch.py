"""Kontrakt minimalnej łatki CMake; bez kompilacji lub uruchamiania modelu."""
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "third_party/colibri/c/olmoe.c"
MODULE = REPO / "tools/colibri/patch_olmoe.cmake"
INPUT_SHA = "f630200cc4222e0e8bfaa178af4c063b4cfe90acc96b89ee50169daefcbc23bf"
OUTPUT_SHA = "598210464d936a2bffd4d01a69c4c487ab7d2280f3efee6b6d45b90c4297b3ca"
BEFORE = b"    int hist_len = np, gen = 0, limited = 1, cancelled = 0;\n    char buf[512];"
AFTER = b"    int hist_len = np, gen = 0, limited = 1, cancelled = 0;\n    char buf[65537];"


def find_cmake():
    cmake = os.environ.get("CMAKE") or shutil.which("cmake")
    if cmake:
        return cmake
    bundled = REPO.parents[1] / "work/toolchain/android-sdk/cmake/3.22.1/bin/cmake.exe"
    return str(bundled) if bundled.is_file() else None


class NativePatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cmake = find_cmake()
        if not cls.cmake:
            raise unittest.SkipTest("Wymagane CMake 3.22+; ustaw zmienną CMAKE.")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def patch(self, source, output):
        script = self.root / "apply.cmake"
        script.write_text(
            f'include("{MODULE.as_posix()}")\n'
            f'scalajaca_patch_olmoe("{source.as_posix()}" "{output.as_posix()}")\n',
            encoding="utf-8",
        )
        return subprocess.run([self.cmake, "-P", str(script)], capture_output=True, text=True)

    def test_exactly_one_change_and_pinned_hashes_vendor_untouched(self):
        original = SOURCE.read_bytes()
        self.assertEqual(INPUT_SHA, hashlib.sha256(original).hexdigest())
        self.assertEqual(1, original.count(BEFORE))
        output = self.root / "generated/scalajaca_olmoe.c"
        result = self.patch(SOURCE, output)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(original.replace(BEFORE, AFTER), output.read_bytes())
        self.assertEqual(OUTPUT_SHA, hashlib.sha256(output.read_bytes()).hexdigest())
        self.assertEqual(original, SOURCE.read_bytes())
        self.assertIn(OUTPUT_SHA, output.with_suffix(".c.sha256").read_text())
        # Ponowne konfigurowanie daje identyczny wynik.
        self.assertEqual(0, self.patch(SOURCE, output).returncode)
        self.assertEqual(OUTPUT_SHA, hashlib.sha256(output.read_bytes()).hexdigest())

    def test_modified_upstream_is_rejected_before_output(self):
        source = self.root / "changed.c"
        source.write_bytes(SOURCE.read_bytes() + b"\n/* changed */\n")
        output = self.root / "patched.c"
        result = self.patch(source, output)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("SHA-256", result.stderr)
        self.assertFalse(output.exists())

    def test_no_vendor_overwrite(self):
        source = self.root / "upstream.c"
        original = SOURCE.read_bytes()
        source.write_bytes(original)
        result = self.patch(source, source)
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(original, source.read_bytes())


if __name__ == "__main__":
    unittest.main()
