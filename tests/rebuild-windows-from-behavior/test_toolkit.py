"""Acceptance checks with independently authored synthetic artifacts; no target code."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

SKILL = Path(os.environ.get("REBUILD_SKILL_DIR", Path(__file__).resolve().parents[2] / "skills/rebuild-windows-from-behavior"))
spec = importlib.util.spec_from_file_location("rebuild_tool", SKILL / "scripts/rebuild.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


def contract(observed=False):
    status = "observed" if observed else "proposed"
    evidence = ["OBS-001"] if observed else ["DECISION-001"]
    data = tool.initial_contract("Independent sum")
    data["requirements"] = [{"id": "REQ-001", "description": "Sum item values", "evidence_status": status,
                              "evidence_ids": evidence}]
    data["cases"] = [{"id": "CASE-001", "requirement_ids": ["REQ-001"], "input": {"items": [4, 7]},
                       "expected": {"total": 11}, "evidence_status": status, "evidence_ids": evidence,
                       "fixture_origin": "synthetic"}]
    data["handoff_review"] = {"status": "approved", "reviewer": "Analyst",
                               "notes": "Reviewed behavior-only requirements and synthetic fixtures"}
    return data


def observation():
    return {"id": "OBS-001", "scenario": "Sum synthetic values", "input": {"items": [4, 7]},
            "actual": {"total": 11}, "method": "Synthetic test fixture, not a real target observation",
            "environment": "unittest temporary workspace", "fixture_origin": "synthetic"}


def synthetic_pe(bits=64, managed=False, optional_size=None, directory_count=16):
    """Minimal header bytes per the public PE format, not an executable program."""
    data = bytearray(1024)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    size = (240 if bits == 64 else 224) if optional_size is None else optional_size
    struct.pack_into("<HH", data, 0x84, 0x8664 if bits == 64 else 0x14C, 1)
    struct.pack_into("<HH", data, 0x94, size, 0x2000)
    optional = 0x98
    struct.pack_into("<H", data, optional, 0x20B if bits == 64 else 0x10B)
    struct.pack_into("<H", data, optional + 68, 3)
    struct.pack_into("<I", data, optional + (108 if bits == 64 else 92), directory_count)
    if managed:
        struct.pack_into("<II", data, optional + (112 if bits == 64 else 96) + 14 * 8, 0x2000, 72)
    return bytes(data)


class ToolkitAcceptance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def json_file(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def cli(self, *args):
        return subprocess.run([sys.executable, str(SKILL / "scripts/rebuild.py"), *map(str, args)],
                              capture_output=True, text=True, encoding="utf-8")

    def workspace(self):
        path = self.root / "analysis"
        tool.init_workspace(path, "Example")
        return path

    def write_contract(self, workspace, data):
        (workspace / "spec/contract.json").write_text(json.dumps(data), encoding="utf-8")

    def test_inspect_does_not_execute_or_emit_source(self):
        source = self.root / "reference"
        source.mkdir()
        marker = self.root / "executed"
        original = "from pathlib import Path\nPath(" + repr(str(marker)) + ").touch()\n"
        target = source / "sample.py"
        target.write_text(original, encoding="utf-8")
        result = self.cli("inspect", source, "--out", self.root / "report.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        report = tool.load_json(self.root / "report.json")
        self.assertFalse(marker.exists())
        self.assertNotIn(original, json.dumps(report))
        self.assertEqual(target.read_text(), original)
        self.assertEqual(report["files"][0]["language_evidence"][0]["language"], "Python")

    def test_extension_alone_is_not_language_confirmation(self):
        target = self.root / "pretend.cs"
        target.write_text("just ordinary text")
        report = tool.inspect_target(target)
        self.assertEqual(report["files"][0]["language_evidence"][0]["status"], "extension-only")

    def test_pascal_syntax_hints_do_not_export_source(self):
        source = "unit IndependentExample;\ninterface\nimplementation\nend.\n"
        for extension in (".pas", ".pp", ".lpr", ".dpr"):
            target = self.root / ("sample" + extension)
            target.write_text(source, encoding="utf-8")
            report = tool.inspect_target(target)
            hint = report["files"][0]["language_evidence"][0]
            self.assertEqual(hint["language"], "Pascal")
            self.assertEqual(hint["status"], "inferred")
            self.assertNotIn(source, json.dumps(report))

    def test_lazarus_declared_modes_are_component_hints(self):
        target = self.root / "application.lpi"
        target.write_text('<CONFIG><ProjectOptions/><CompilerOptions><Parsing>'
                          '<SyntaxMode Value="Delphi"/></Parsing></CompilerOptions></CONFIG>')
        result = tool.inspect_target(target)
        hint = result["files"][0]["language_evidence"][0]
        self.assertEqual(hint["language"], "Object Pascal")
        self.assertEqual(hint["status"], "inferred")
        self.assertIn("delphi", hint["basis"])
        self.assertIn("component", result["files"][0]["runtime_hints"][0]["basis"])

    def test_invalid_truncated_and_unrelated_lpi_do_not_identify_language(self):
        contents = ('<CONFIG><ProjectOptions/><SyntaxMode Value="Delphi"/></CONFIG>',
                    '<CONFIG><ProjectOptions>',
                    '<Other><SyntaxMode Value="Delphi"/></Other>',
                    '<CONFIG><ProjectOptions/><SyntaxMode Value="MadeUp"/></CONFIG>')
        for number, text in enumerate(contents):
            target = self.root / f"unconfirmed-{number}.lpi"
            target.write_text(text)
            result = tool.inspect_target(target, sample_bytes=8) if number == 0 else tool.inspect_target(target)
            self.assertEqual(result["files"][0]["language_evidence"], [])

    def test_native_pe_does_not_claim_cpp(self):
        target = self.root / "native.exe"
        target.write_bytes(synthetic_pe())
        report = tool.inspect_target(target)
        binary = report["files"][0]["binary"]
        self.assertEqual(binary["architecture"], "x64")
        self.assertEqual(binary["implementation_language"], "unknown")
        self.assertFalse(binary["clr_directory_declared"])

    def test_managed_pe32_and_pe64_are_runtime_hints(self):
        for bits in (32, 64):
            binary = tool.pe_info(synthetic_pe(bits, managed=True))
            self.assertTrue(binary["clr_directory_declared"])
            self.assertEqual(binary["implementation_language"], "unknown")
            self.assertIn("Does not distinguish", binary["language_caveat"])

    def test_clr_probe_respects_declared_optional_header_size(self):
        binary = tool.pe_info(synthetic_pe(managed=True, optional_size=120))
        self.assertFalse(binary["clr_directory_declared"])
        self.assertIn("exceeds", binary["warning"])

    def test_clr_probe_respects_declared_directory_count(self):
        binary = tool.pe_info(synthetic_pe(managed=True, directory_count=14))
        self.assertFalse(binary["clr_directory_declared"])

    def test_truncated_and_non_pe_mz_are_reported(self):
        self.assertIn("warning", tool.pe_info(b"MZ"))
        data = bytearray(synthetic_pe())
        struct.pack_into("<I", data, 0x3C, 0xFFFFFF00)
        self.assertIn("warning", tool.pe_info(data))

    def test_inventory_limit_is_explicit(self):
        for name in ("a.txt", "b.txt"):
            (self.root / name).write_text("x")
        result = tool.inspect_target(self.root, max_files=1)
        self.assertEqual(len(result["files"]), 1)
        self.assertTrue(result["inventory_truncated"])

    def test_total_read_budget_keeps_large_inventories_bounded(self):
        for name in ("a.bin", "b.bin"):
            (self.root / name).write_bytes(b"z" * 100)
        result = tool.inspect_target(self.root, sample_bytes=100, read_budget=16)
        self.assertLessEqual(result["bytes_read"], 16)
        self.assertTrue(result["inventory_truncated"])
        self.assertIsNone(result["files"][0]["sha256"])

    def test_skipped_dependencies_and_hash_limits_are_visible(self):
        (self.root / "node_modules").mkdir()
        (self.root / "node_modules/private.js").write_text("const privateExample = 1;")
        (self.root / "large.bin").write_bytes(b"a" * 100)
        result = tool.inspect_target(self.root, sample_bytes=8, hash_limit=10)
        self.assertEqual(len(result["files"]), 1)
        self.assertIsNone(result["files"][0]["sha256"])
        self.assertTrue(result["files"][0]["sample_truncated"])
        self.assertTrue(result["warnings"])

    def test_inspection_refuses_output_in_original_tree(self):
        original = self.root / "reference"
        original.mkdir()
        result = self.cli("inspect", original, "--out", original / "report.json")
        self.assertEqual(result.returncode, 2)
        self.assertFalse((original / "report.json").exists())

    def test_existing_output_is_preserved(self):
        target = self.root / "target.txt"
        target.write_text("preserve")
        result = self.cli("inspect", target, "--out", target)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(target.read_text(), "preserve")

    def test_init_refuses_existing_workspace(self):
        ws = self.workspace()
        with self.assertRaises(tool.Invalid):
            tool.init_workspace(ws, "Other")

    def test_draft_contract_is_not_ready(self):
        with self.assertRaises(tool.Invalid):
            tool.validate_contract(tool.initial_contract("Empty"))

    def test_unmapped_requirements_and_unknown_case_links_fail(self):
        for mutation in ("unmapped", "unknown"):
            data = contract()
            if mutation == "unmapped":
                extra = copy.deepcopy(data["requirements"][0])
                extra["id"] = "REQ-002"
                data["requirements"].append(extra)
            else:
                data["cases"][0]["requirement_ids"] = ["REQ-999"]
            with self.assertRaises(tool.Invalid):
                tool.validate_contract(data)

    def test_duplicate_case_ids_fail(self):
        data = contract()
        data["cases"].append(copy.deepcopy(data["cases"][0]))
        with self.assertRaises(tool.Invalid):
            tool.validate_contract(data)

    def test_extra_source_field_and_code_fences_fail(self):
        for change in ("field", "fence"):
            data = contract()
            if change == "field":
                data["original_source"] = "should not enter handoff"
            else:
                data["requirements"][0]["description"] = "```source code```"
            with self.assertRaises(tool.Invalid):
                tool.validate_contract(data)

    def test_original_fixtures_fail(self):
        data = contract()
        data["cases"][0]["fixture_origin"] = "copied-target-test"
        with self.assertRaises(tool.Invalid):
            tool.validate_contract(data)

    def test_observed_claim_requires_observation_id(self):
        data = contract()
        data["requirements"][0]["evidence_status"] = "observed"
        with self.assertRaises(tool.Invalid):
            tool.validate_contract(data)

    def test_observation_append_preserves_first_capture(self):
        ws = self.workspace()
        tool.add_observation(ws, observation())
        before = (ws / "analyst/observations.jsonl").read_bytes()
        with self.assertRaises(tool.Invalid):
            tool.add_observation(ws, observation())
        self.assertEqual(before, (ws / "analyst/observations.jsonl").read_bytes())

    def test_unreviewed_export_fails_without_output(self):
        ws = self.workspace()
        data = contract()
        data["handoff_review"]["status"] = "pending"
        self.write_contract(ws, data)
        with self.assertRaises(tool.Invalid):
            tool.export_handoff(ws, self.root / "handoff")
        self.assertFalse((self.root / "handoff").exists())

    def test_export_rejects_missing_observed_capture(self):
        ws = self.workspace()
        self.write_contract(ws, contract(observed=True))
        with self.assertRaises(tool.Invalid):
            tool.export_handoff(ws, self.root / "handoff")

    def test_export_allowlist_keeps_analyst_and_extra_files_private(self):
        ws = self.workspace()
        self.write_contract(ws, contract(observed=True))
        tool.add_observation(ws, observation())
        (ws / "analyst/private-source.txt").write_text("Never transfer this private material")
        (ws / "spec/unreviewed.txt").write_text("Nor this adjacent file")
        out = self.root / "handoff"
        tool.export_handoff(ws, out)
        self.assertEqual({p.name for p in out.iterdir()}, {"contract.json", "BUILDER.md", "manifest.json"})
        self.assertNotIn("Never transfer", "".join(p.read_text() for p in out.iterdir()))
        manifest = tool.load_json(out / "manifest.json")
        self.assertEqual(manifest["files_sha256"]["contract.json"], tool.sha256_file(out / "contract.json"))
        with self.assertRaises(tool.Invalid):
            tool.export_handoff(ws, out)

    def test_matching_reference_and_candidate_must_also_match_contract(self):
        result = tool.compare_results(contract(), {"CASE-001": {"total": 99}}, {"CASE-001": {"total": 99}})
        self.assertFalse(result["passed"])
        self.assertTrue(result["cases"][0]["candidate_matches_reference"])

    def test_missing_capture_is_not_null(self):
        data = contract()
        data["cases"][0]["expected"] = None
        result = tool.compare_results(data, {"CASE-001": None}, {})
        self.assertFalse(result["passed"])
        self.assertFalse(result["cases"][0]["candidate_present"])

    def test_unexpected_capture_ids_fail(self):
        with self.assertRaises(tool.Invalid):
            tool.compare_results(contract(), {"CASE-999": 1}, {})

    def test_boolean_number_and_array_order_differences_are_preserved(self):
        self.assertFalse(tool.same_json({"value": True}, {"value": 1}))
        self.assertFalse(tool.same_json([1, 2], [2, 1]))
        self.assertTrue(tool.same_json({"a": 1, "b": 2}, {"b": 2, "a": 1}))
        self.assertTrue(tool.same_json(10 ** 500, 10 ** 500))

    def test_duplicate_json_keys_and_nonfinite_values_are_invalid(self):
        for number, text in enumerate(('{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}', '{"x":1e999}')):
            path = self.root / f"invalid-{number}.json"
            path.write_text(text)
            with self.assertRaises(tool.Invalid):
                tool.load_json(path)

    def test_cli_compare_pass_and_mismatch_exit_codes(self):
        spec_path = self.json_file("contract.json", contract())
        reference = self.json_file("reference.json", {"CASE-001": {"total": 11}})
        candidate = self.json_file("candidate.json", {"CASE-001": {"total": 11}})
        good = self.cli("compare", "--contract", spec_path, "--reference", reference,
                        "--candidate", candidate, "--out", self.root / "pass.json")
        self.assertEqual(good.returncode, 0, good.stderr)
        candidate.write_text('{"CASE-001":{"total":12}}')
        bad = self.cli("compare", "--contract", spec_path, "--reference", reference,
                       "--candidate", candidate, "--out", self.root / "mismatch.json")
        self.assertEqual(bad.returncode, 1, bad.stderr)

    def test_cli_invalid_contract_is_clear_error_without_traceback(self):
        path = self.json_file("bad.json", {"schema_version": 1})
        result = self.cli("validate-contract", path)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stderr)

    @unittest.skipIf(os.name == "nt", "Symlink creation may need privileges on Windows")
    def test_symlink_is_not_exported_or_inspected(self):
        private = self.root / "private.txt"
        private.write_text("private")
        linked = self.root / "link.txt"
        linked.symlink_to(private)
        with self.assertRaises(tool.Invalid):
            tool.inspect_target(linked)
        parent = self.root / "linked-parent"
        parent.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(tool.Invalid):
            tool.write_new_json(parent / "output.json", {})

    @unittest.skipUnless(os.name == "nt", "Requires Windows PowerShell")
    def test_powershell_wrapper_forwards_arguments_and_exit_code(self):
        shell = shutil.which("powershell") or shutil.which("pwsh")
        self.assertIsNotNone(shell)
        result = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                 str(SKILL / "scripts/Invoke-Rebuild.ps1"), "--version"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(tool.VERSION, result.stdout)


if __name__ == "__main__":
    unittest.main()
