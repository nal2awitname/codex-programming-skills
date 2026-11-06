"""Exercise the real command entry point and process exit statuses."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CliTests(unittest.TestCase):
    def run_cli(self, *arguments):
        completed = subprocess.run(
            [sys.executable, "scan_lab.py", *map(str, arguments)],
            cwd=ROOT,
            text=True,
            encoding="utf-8",
            capture_output=True,
            timeout=15,
            check=False,
        )
        self.assertEqual(completed.stderr, "")
        return completed.returncode, json.loads(completed.stdout)

    def test_demo_emits_two_scan_entries(self):
        code, actual = self.run_cli("--demo")
        self.assertEqual(code, 0)
        self.assertEqual(actual, {"history": [
            {"offsets": [0, 8, 16], "values": [137, 137, 137]},
            {"offsets": [8], "values": [120]},
        ]})

    def test_scenario_file_matches_documented_demo(self):
        self.assertEqual(self.run_cli("--scenario", "examples/demo.json"), self.run_cli("--demo"))

    def test_invalid_scenario_returns_named_error_and_nonzero(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tests") as directory:
            path = Path(directory) / "invalid.json"
            path.write_text('{"initial": [true], "steps": []}', encoding="utf-8")
            code, actual = self.run_cli("--scenario", path)
        self.assertNotEqual(code, 0)
        self.assertEqual(actual, {"error": "invalid_value"})

    def test_malformed_json_returns_named_error_and_nonzero(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tests") as directory:
            path = Path(directory) / "malformed.json"
            path.write_text('{"initial":', encoding="utf-8")
            code, actual = self.run_cli("--scenario", path)
        self.assertNotEqual(code, 0)
        self.assertEqual(actual, {"error": "invalid_json"})

    def test_wrong_root_type_is_an_invalid_scenario(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tests") as directory:
            path = Path(directory) / "list.json"
            path.write_text("[]", encoding="utf-8")
            code, actual = self.run_cli("--scenario", path)
        self.assertNotEqual(code, 0)
        self.assertEqual(actual, {"error": "invalid_scenario"})

    def test_missing_file_returns_io_error_and_nonzero(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tests") as directory:
            code, actual = self.run_cli("--scenario", Path(directory) / "missing.json")
        self.assertNotEqual(code, 0)
        self.assertEqual(actual, {"error": "io_error"})

    def test_invalid_text_encoding_returns_io_error_and_nonzero(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tests") as directory:
            path = Path(directory) / "invalid-encoding.json"
            path.write_bytes(b"\xff\xfe")
            code, actual = self.run_cli("--scenario", path)
        self.assertNotEqual(code, 0)
        self.assertEqual(actual, {"error": "io_error"})


if __name__ == "__main__":
    unittest.main()
