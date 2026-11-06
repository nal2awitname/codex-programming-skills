"""All reference/rebuild snippets here are original synthetic test fixtures."""

import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from arbkit.common import digest, read_json, write_json
from arbkit.inventory import scan
from arbkit.runner import execute, run, verification_current
from arbkit.reporting import report
from arbkit.workflow import add_evidence, attach_observation, handoff, initialize, readiness, seal


class WorkbenchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / "reference"
        self.source.mkdir()
        self.work = self.base / "lab"
        # Synthetic program; never imported by the analyzer.
        (self.source / "main.py").write_text(
            "import json, sys\n"
            "def _synthetic_cost(value):\n"
            "    return sum(value)\n"
            "for line in sys.stdin:\n"
            "    print(json.dumps({'sum': _synthetic_cost(json.loads(line))}))\n", encoding="utf-8")

    def prepare(self):
        initialize(self.source, self.work)
        add_evidence(self.work, "E-one", "main.py", 1, 5,
                     "The supplied collection is aggregated and returned as an integer total.")
        contract = {"schema_version": 2, "project": "Synthetic aggregation", "scope": "JSON-lines numeric collections",
            "requirements": [{"id": "R-total", "behavior": "Return the sum of the numeric entries under the public sum field.",
                              "evidence_ids": ["E-one"], "case_ids": ["C-basic", "C-empty"]}],
            "compatibility_facts": [{"value": "sum", "reason": "Public JSON response field."}], "unknowns": []}
        cases = {"schema_version": 2, "cases": [
            {"id": "C-basic", "requirements": ["R-total"], "stdin": "[5, -2, 9]\n", "mode": "json",
             "expected": {"exit_code": 0, "stdout": {"sum": 12}, "stderr": ""}},
            {"id": "C-empty", "requirements": ["R-total"], "stdin": "[]\n", "mode": "json",
             "expected": {"exit_code": 0, "stdout": {"sum": 0}, "stderr": ""}}]}
        write_json(self.work / "contract.json", contract)
        write_json(self.work / "cases.json", cases)
        ledger = read_json(self.work / "analyst/ledger.json")
        ledger["feature_discovery"] = "Reviewed the full synthetic stdin/stdout interface and its pure calculation."
        ledger["features"] = [{"id": "B-total", "scope": "in", "state": "understood",
                               "summary": "Aggregate one numeric collection per request.",
                               "evidence_ids": ["E-one"], "requirement_ids": ["R-total"]}]
        for item in ledger["units"]:
            item.update(state="understood", summary="Numeric aggregation behavior.", evidence_ids=["E-one"], requirement_ids=["R-total"])
        for item in ledger["files"]:
            item.update(state="understood", summary="Line-oriented input and output.", evidence_ids=["E-one"],
                        discovery_review="Entire synthetic file reviewed; no generated code or external dispatch.")
        write_json(self.work / "analyst/ledger.json", ledger)
        self.reference_command = self.base / "reference-command.json"
        write_json(self.reference_command, {"argv": [sys.executable, "-B", str(self.source / "main.py")], "cwd": str(self.source)})
        return contract, cases

    def test_python_nested_async_lambda_inventory_without_execution(self):
        (self.source / "main.py").write_text("raise RuntimeError('must not execute')\nclass Unit:\n    async def process(self):\n        def local():\n            return 1\n        return lambda x: x\n", encoding="utf-8")
        result = scan(self.source)
        symbols = result["files"][0]["symbols"]
        self.assertEqual({x["kind"] for x in symbols}, {"class", "async_function", "function", "lambda"})
        self.assertEqual(len({x["id"] for x in symbols}), 4)
        self.assertNotIn("must not execute", json.dumps(result))

    def test_js_discovery_is_explicitly_partial(self):
        (self.source / "ui.ts").write_text("export function start() {}\nconst stop = () => 2;\n", encoding="utf-8")
        entry = next(f for f in scan(self.source)["files"] if f["path"] == "ui.ts")
        self.assertIsNone(entry["confirmed_language"])
        self.assertEqual(len(entry["symbols"]), 2)
        self.assertTrue(all(x["discovery"] == "heuristic" for x in entry["symbols"]))

    def test_initial_state_blocks_and_preserves_original(self):
        before = (self.source / "main.py").read_bytes()
        initialize(self.source, self.work)
        self.assertFalse(readiness(self.work)["ready_for_handoff"])
        self.assertEqual(before, (self.source / "main.py").read_bytes())
        with self.assertRaises(ValueError): initialize(self.source, self.work)

    def test_handoff_requires_review_and_contains_only_allowlisted_inputs(self):
        self.prepare()
        self.assertTrue(readiness(self.work)["ready_for_handoff"])
        with self.assertRaises(ValueError): seal(self.work, False)
        seal(self.work, True)
        target = self.base / "builder-input"
        handoff(self.work, target)
        self.assertEqual({p.name for p in target.iterdir()}, {"contract.json", "cases.json", "BUILD_BRIEF.md", "manifest.json"})
        for p in target.iterdir():
            self.assertNotIn(str(self.source), p.read_text())
            self.assertNotIn("_synthetic_cost", p.read_text())

    def test_private_symbol_and_copied_line_block(self):
        contract, _ = self.prepare()
        contract["requirements"][0]["behavior"] += " Use _synthetic_cost."
        write_json(self.work / "contract.json", contract)
        self.assertTrue(any("private symbol" in x for x in readiness(self.work)["issues"]))
        contract["requirements"][0]["behavior"] = "print(json.dumps({'sum': _synthetic_cost(json.loads(line))}))"
        write_json(self.work / "contract.json", contract)
        self.assertTrue(any("copied source line" in x for x in readiness(self.work)["issues"]))

    def test_missing_unit_cannot_be_silently_removed(self):
        self.prepare()
        ledger = read_json(self.work / "analyst/ledger.json")
        ledger["units"] = []
        write_json(self.work / "analyst/ledger.json", ledger)
        self.assertFalse(readiness(self.work)["ready_for_handoff"])

    def test_changed_source_and_stale_review_fail(self):
        contract, _ = self.prepare()
        seal(self.work, True)
        contract["scope"] = "Changed scope"
        write_json(self.work / "contract.json", contract)
        with self.assertRaises(ValueError): handoff(self.work, self.base / "builder")
        (self.source / "main.py").write_text("print('changed')\n")
        with self.assertRaises(ValueError): readiness(self.work)

    def test_complete_reference_and_independent_rebuild_verification(self):
        self.prepare()
        self.assertTrue(execute(self.work, self.reference_command, "observe")["success"])
        rebuilt = self.base / "rebuilt"
        rebuilt.mkdir()
        # Independently authored synthetic replacement: a different aggregation design.
        (rebuilt / "app.py").write_text("import json\nfrom functools import reduce\nimport sys\nfor request in sys.stdin:\n    values = json.loads(request)\n    answer = reduce(lambda a, b: a + b, values, 0)\n    sys.stdout.write(json.dumps(dict(sum=answer)) + '\\n')\n", encoding="utf-8")
        command = self.base / "rebuilt-command.json"
        write_json(command, {"argv": [sys.executable, "-B", "app.py"], "cwd": str(rebuilt)})
        result = execute(self.work, command, "verify")
        self.assertEqual(result["passed"], 2)
        self.assertEqual(result["oracle"], "observed_reference")
        record = read_json(self.work / "analyst/verification.json")
        self.assertTrue(verification_current(self.work, record))
        (rebuilt / "app.py").write_text("print('broken')\n")
        self.assertFalse(verification_current(self.work, record))
        self.assertFalse(execute(self.work, command, "verify")["success"])

    def test_expected_only_is_not_reported_as_reference_equivalence(self):
        self.prepare()
        cwd = self.base / "rebuilt"
        cwd.mkdir()
        cmd = self.base / "cmd.json"
        write_json(cmd, {"argv": [sys.executable, "-B", "-c", "print('{\"sum\":12}') # " + "padding" * 100], "cwd": str(cwd)})
        result = execute(self.work, cmd, "verify")
        self.assertEqual(result["oracle"], "specified_expectations_only")
        self.assertFalse(result["success"])

    def test_reference_expectation_disagreement_is_not_valid_evidence(self):
        _, cases = self.prepare()
        cases["cases"][0]["expected"]["stdout"] = {"sum": 999}
        write_json(self.work / "cases.json", cases)
        self.assertFalse(execute(self.work, self.reference_command, "observe")["success"])

    def test_timeout_and_output_limit(self):
        command = {"argv": [sys.executable, "-B", "-c", "import time; time.sleep(3)"], "cwd": str(self.base)}
        self.assertTrue(run(command, "", timeout=0.1)["timed_out"])
        command["argv"][-1] = "print('x' * 100000)"
        result = run(command, "", limit=32)
        self.assertTrue(result["output_limited"])
        self.assertLessEqual(len(result["stdout"].encode()), 32)
        self.assertFalse(result["valid"])

    def test_symlinks_skips_limits_and_nested_work(self):
        if os.name != "nt":
            (self.source / "linked.py").symlink_to(self.source / "main.py")
            self.assertEqual(scan(self.source)["skipped"][0]["reason"], "symlink_or_special_file")
        self.assertTrue(scan(self.source, max_bytes=1)["skipped"])
        with self.assertRaises(ValueError): initialize(self.source, self.source / "lab")
        with self.assertRaises(ValueError): scan(self.source, max_files=0)

    def test_cli_error_code_and_no_overwrite(self):
        cli = Path(__file__).parents[1] / "scripts/arb.py"
        initialized = subprocess.run([sys.executable, "-B", str(cli), "init", "--source", str(self.source), "--work", str(self.work)], capture_output=True, text=True)
        self.assertEqual(initialized.returncode, 0, initialized.stderr)
        checked = subprocess.run([sys.executable, "-B", str(cli), "check", "--work", str(self.work)], capture_output=True, text=True)
        self.assertEqual(checked.returncode, 2)
        self.assertFalse(json.loads(checked.stdout)["ready_for_handoff"])

    def test_manual_feature_inventory_is_required(self):
        self.prepare()
        ledger = read_json(self.work / "analyst/ledger.json")
        ledger["features"] = []
        write_json(self.work / "analyst/ledger.json", ledger)
        self.assertFalse(readiness(self.work)["ready_for_handoff"])

    def test_utf16_powershell_is_text_not_misreported_as_binary(self):
        (self.source / "module.ps1").write_text("function Invoke-Synthetic { return 7 }\n", encoding="utf-16")
        item = next(x for x in scan(self.source)["files"] if x["path"] == "module.ps1")
        self.assertNotIn("artifact_kind", item)
        self.assertEqual(item["symbols"][0]["name"], "Invoke-Synthetic")

    def test_analyst_report_and_safe_argument_arrays(self):
        self.prepare()
        result = report(self.work)
        text = Path(result["report"]).read_text()
        self.assertIn("not proven", text)
        self.assertIn("_synthetic_cost", text)
        self.assertNotIn("return sum(value)", text)
        value = "; & this-is-data-not-a-shell-command"
        result = run({"argv": [sys.executable, "-B", "-c", "import sys; sys.stdout.write(sys.argv[1])", value],
                      "cwd": str(self.base)}, "")
        self.assertTrue(result["valid"])
        self.assertEqual(result["stdout"], value)

    def test_original_cannot_be_used_as_rebuilt_command(self):
        self.prepare()
        with self.assertRaises(ValueError): execute(self.work, self.reference_command, "verify")

    def test_external_observation_is_hash_bound_and_never_copied(self):
        self.prepare()
        artifact = self.base / "synthetic-ui-observation.txt"
        artifact.write_text("Synthetic recorded user-visible result", encoding="utf-8")
        attach_observation(self.work, "E-ui", artifact, "Synthetic local UI observation record", "User-visible result captured.")
        self.assertTrue(readiness(self.work)["ready_for_handoff"])
        artifact.write_text("Changed record", encoding="utf-8")
        self.assertFalse(readiness(self.work)["ready_for_handoff"])

    @unittest.skipIf(os.name == "nt", "symlink creation may require Windows-specific privileges")
    def test_rebuilt_symlink_cannot_alias_the_original_program(self):
        self.prepare()
        target = self.base / "rebuilt"
        target.mkdir()
        (target / "alias.py").symlink_to(self.source / "main.py")
        command = self.base / "alias-command.json"
        write_json(command, {"argv": [sys.executable, "-B", "alias.py"], "cwd": str(target)})
        with self.assertRaises(ValueError): execute(self.work, command, "verify")

    @unittest.skipUnless(shutil.which("pwsh") or (os.name == "nt" and shutil.which("powershell")),
                         "native PowerShell runtime is unavailable")
    def test_native_powershell_parser_and_wrapper_whatif(self):
        executable = shutil.which("pwsh") or shutil.which("powershell")
        script = self.source / "functions.ps1"
        marker = self.base / "must-not-exist"
        script.write_text("function Read-Synthetic { param($x) return $x }\nSet-Content -LiteralPath '" + str(marker).replace("'", "''") + "' -Value 'executed'\n", encoding="utf-8")
        item = next(x for x in scan(self.source)["files"] if x["path"] == "functions.ps1")
        self.assertEqual(item["parser"], "powershell_ast")
        self.assertFalse(marker.exists())
        wrapper = Path(__file__).parents[1] / "scripts/Analyze-Rebuild.ps1"
        result = subprocess.run([executable, "-NoProfile", "-File", str(wrapper), "-Action", "init",
                                 "-Source", str(self.source), "-Work", str(self.work), "-WhatIf"],
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.work.exists())


if __name__ == "__main__":
    unittest.main()
