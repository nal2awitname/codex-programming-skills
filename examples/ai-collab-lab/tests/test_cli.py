"""Command-line entry point."""
import json
import os
import socket
import subprocess
import sys
import time
import unittest
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "collab_lab.py"


def run(*args, timeout=60):
    environment = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONDONTWRITEBYTECODE="1")
    return subprocess.run([sys.executable, "-B", str(LAUNCHER), *args], cwd=ROOT, capture_output=True, text=True,
                          encoding="utf-8", timeout=timeout, env=environment, check=False)


class CliTests(unittest.TestCase):
    def test_demo_prints_completed_project(self):
        result = run("--demo")
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads(result.stdout)
        self.assertEqual([t["status"] for t in summary["tasks"]], ["done"] * 5)
        self.assertIn("src/temperature.py", summary["files"])
        self.assertEqual(summary["polls"][0]["result"]["winner"], "ship")
        self.assertIn("is complete", summary["final_reply"])

    def test_demo_with_execution_and_custom_request(self):
        result = run("--demo", "--allow-code-execution", "--request", "Write a prime number checker")
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads(result.stdout)
        tester = next(t for t in summary["tasks"] if t["title"].startswith("Test"))
        self.assertRegex(tester["result"], r"^2 test\(s\) passed: tests/test_primes.py")

    def test_demo_without_recipe_reports_failure_status(self):
        result = run("--demo", "--request", "Build a teleporter firmware")
        self.assertEqual(result.returncode, 1)
        summary = json.loads(result.stdout)
        self.assertIn("blocked", [t["status"] for t in summary["tasks"]])

    def test_version(self):
        result = run("--version")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "1.0.0"))

    def test_server_starts_and_serves_the_gui(self):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        environment = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONDONTWRITEBYTECODE="1")
        process = subprocess.Popen([sys.executable, "-B", str(LAUNCHER), "--no-browser", "--port", str(port)],
                                   cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   encoding="utf-8", env=environment)
        try:
            body = None
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline and body is None:
                try:
                    # Bypass any proxy configured in the environment; the server is local.
                    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                    with opener.open(f"http://127.0.0.1:{port}/", timeout=2) as response:
                        body = response.read().decode("utf-8")
                except OSError:
                    time.sleep(0.1)
            self.assertIsNotNone(body, "server did not start")
            self.assertIn("<title>AI Collab Lab</title>", body)
        finally:
            process.terminate()
            process.communicate(timeout=10)


if __name__ == "__main__":
    unittest.main()
