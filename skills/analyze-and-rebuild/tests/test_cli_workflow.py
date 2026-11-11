"""Exercise an installed skill through its public command-line entrypoint."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class InstalledWorkflowTests(unittest.TestCase):
    def test_complete_workflow_from_a_skill_path_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix="arb acceptance ") as temporary:
            base = Path(temporary)
            installed = base / "installed skills" / "analyze-and-rebuild"
            shutil.copytree(Path(__file__).resolve().parents[1], installed,
                            ignore=shutil.ignore_patterns("__pycache__"))
            cli = installed / "scripts" / "arb.py"
            source = base / "reference program"
            source.mkdir()
            work = base / "analyst workspace"
            reference = source / "src files" / "reference.py"
            reference.parent.mkdir()
            # These reference and replacement programs are synthetic fixtures.
            reference_text = (
                "import json, sys\n"
                "def _accumulate(values):\n"
                "    return sum(values)\n"
                "try:\n"
                "    answer = _accumulate(json.loads(sys.stdin.read()))\n"
                "except (TypeError, ValueError):\n"
                "    print(json.dumps({'error': 'invalid input'}))\n"
                "    sys.exit(2)\n"
                "print(json.dumps({'total': answer}))\n")
            reference.write_text(reference_text, encoding="utf-8")
            reference_bytes = reference.read_bytes()
            environment = dict(os.environ)
            environment.pop("PYTHONPATH", None)

            def read(path):
                return json.loads(path.read_text(encoding="utf-8"))

            def write(path, value):
                path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")

            def invoke(action, *arguments, expected_code=0):
                result = subprocess.run(
                    [sys.executable, "-B", str(cli), action, "--work", str(work),
                     *(str(argument) for argument in arguments)],
                    cwd=base, env=environment, capture_output=True,
                    text=True, encoding="utf-8", timeout=30)
                self.assertEqual(result.returncode, expected_code,
                                 f"{action}: {result.stdout}\n{result.stderr}")
                self.assertNotIn("Traceback", result.stderr)
                return json.loads(result.stdout if result.stdout else result.stderr)

            initialized = invoke("init", "--source", source)
            self.assertEqual(initialized["files"], 1)
            self.assertEqual(initialized["units"], 1)
            self.assertFalse(invoke("check", expected_code=2)["ready_for_handoff"])
            invoke("evidence", "--id", "E-interface", "--file", os.path.join(".", "src files", "reference.py"),
                   "--start", 1, "--end", len(reference_text.splitlines()),
                   "--summary", "The interface returns totals or a structured invalid-input error.")

            scenarios = [
                ("C-basic", "[4, 9]\n", 0, {"total": 13}),
                ("C-negative", "[-6, 2]\n", 0, {"total": -4}),
                ("C-empty", "[]\n", 0, {"total": 0}),
                ("C-invalid", "invalid JSON\n", 2, {"error": "invalid input"}),
            ]
            write(work / "contract.json", {
                "schema_version": 2, "project": "Synthetic total interface",
                "scope": "Numeric arrays and malformed input through a JSON CLI",
                "requirements": [{
                    "id": "R-response", "behavior": "Return a numeric total; reject malformed input with an error and exit code 2.",
                    "evidence_ids": ["E-interface"], "case_ids": [case[0] for case in scenarios]}],
                "compatibility_facts": [
                    {"value": "total", "reason": "Public response field."},
                    {"value": "error", "reason": "Public error field."},
                    {"value": "invalid input", "reason": "Required public error description."}],
                "unknowns": []})
            write(work / "cases.json", {"schema_version": 2, "cases": [
                {"id": identifier, "requirements": ["R-response"], "stdin": request, "mode": "json",
                 "expected": {"exit_code": exit_code, "stdout": response, "stderr": ""}}
                for identifier, request, exit_code, response in scenarios]})
            ledger_path = work / "analyst" / "ledger.json"
            ledger = read(ledger_path)
            ledger["feature_discovery"] = "Reviewed the numeric-array request and invalid-input CLI paths."
            ledger["features"] = [{
                "id": "B-response", "scope": "in", "state": "understood",
                "summary": "One request produces a total or a structured error.",
                "evidence_ids": ["E-interface"], "requirement_ids": ["R-response"]}]
            for row in ledger["files"] + ledger["units"]:
                row.update(state="understood", summary="Numeric request and response handling.",
                           evidence_ids=["E-interface"])
            for row in ledger["files"]:
                row["discovery_review"] = "The complete synthetic CLI was reviewed; no external dispatch."
            for row in ledger["units"]:
                row["requirement_ids"] = ["R-response"]
            write(ledger_path, ledger)

            reference_command = base / "reference command.json"
            write(reference_command, {"argv": [sys.executable, "-B", str(reference)], "cwd": str(source)})
            observed = invoke("observe", "--command", reference_command)
            self.assertTrue(observed["success"])
            self.assertEqual(observed["valid"], 4)
            self.assertTrue(invoke("check")["ready_for_handoff"])
            self.assertTrue(invoke("seal", "--reviewed")["sealed"])
            builder_input = base / "builder input"
            invoke("handoff", "--destination", builder_input)
            self.assertEqual({path.name for path in builder_input.iterdir()},
                             {"contract.json", "cases.json", "BUILD_BRIEF.md", "manifest.json"})
            manifest_bytes = (builder_input / "manifest.json").read_bytes()
            for name, expected_hash in read(builder_input / "manifest.json")["files"].items():
                self.assertEqual(hashlib.sha256((builder_input / name).read_bytes()).hexdigest(), expected_hash)
            for path in builder_input.iterdir():
                exported_text = path.read_text(encoding="utf-8")
                self.assertNotIn(str(source), exported_text)
                self.assertNotIn("_accumulate", exported_text)

            rebuilt = base / "independent program"
            rebuilt.mkdir()
            app = rebuilt / "app.py"
            app.write_text(
                "from functools import reduce\nimport json\nimport operator\nimport sys\n"
                "try:\n"
                "    values = json.loads(sys.stdin.read())\n"
                "    response = dict(total=reduce(operator.add, values, 0))\n"
                "    status = 0\n"
                "except (TypeError, ValueError):\n"
                "    response = dict(error='invalid input')\n"
                "    status = 2\n"
                "sys.stdout.write(json.dumps(response))\n"
                "sys.exit(status)\n", encoding="utf-8")
            rebuilt_command = base / "rebuilt command.json"
            write(rebuilt_command, {"argv": [sys.executable, "-B", "app.py"], "cwd": str(rebuilt)})
            verified = invoke("verify", "--command", rebuilt_command)
            self.assertTrue(verified["success"])
            self.assertEqual(verified["passed"], 4)
            self.assertEqual(verified["oracle"], "observed_reference")
            verification = invoke("status")["verification"]
            self.assertTrue(verification["current"] and verification["all_passed"])
            report = invoke("report")
            self.assertTrue(Path(report["report"]).is_file())

            # A subsequent edit must stale the old result and fail a real rerun.
            app.write_text("print('{\"total\": 0}')\n", encoding="utf-8")
            stale = invoke("status")["verification"]
            self.assertFalse(stale["current"] or stale["all_passed"])
            self.assertFalse(invoke("verify", "--command", rebuilt_command, expected_code=2)["success"])
            invoke("handoff", "--destination", builder_input, expected_code=2)
            self.assertEqual((builder_input / "manifest.json").read_bytes(), manifest_bytes)
            self.assertEqual(reference.read_bytes(), reference_bytes)


if __name__ == "__main__":
    unittest.main()
