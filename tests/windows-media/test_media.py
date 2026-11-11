"""Execute the real media workflow with mocked Windows image/disk operations."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
POWERSHELL = os.environ.get("POWERSHELL_EXE") or shutil.which("pwsh") or shutil.which("powershell")


class MediaEncoding(unittest.TestCase):
    def test_windows_powershell_can_decode_thai_script(self):
        # Windows PowerShell 5.1 otherwise decodes UTF-8 Thai as the ANSI code page.
        self.assertTrue((ROOT / "scripts/New-Win11ProMedia.ps1").read_bytes().startswith(b"\xef\xbb\xbf"))


@unittest.skipUnless(POWERSHELL, "PowerShell is required for mocked media workflow tests")
class MediaWorkflow(unittest.TestCase):
    def test_media_workflow_regressions(self):
        for scenario in ("edition-and-architecture", "nested-output", "linked-output", "whatif", "two-images",
                         "stale-export", "unknown-architecture", "already-mounted"):
            with self.subTest(scenario=scenario):
                result = subprocess.run(
                    [POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                     "-File", str(HERE / "media_workflow.ps1"),
                     "-ScriptPath", str(ROOT / "scripts/New-Win11ProMedia.ps1"),
                     "-Scenario", scenario], capture_output=True, text=True,
                    encoding="utf-8", errors="replace", timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: " + scenario, result.stdout)


if __name__ == "__main__":
    unittest.main()
