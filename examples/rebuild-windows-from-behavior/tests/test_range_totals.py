"""Independently authored acceptance and mathematical property checks."""
import importlib.util
import json
import random
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / "range_totals.py"
module_spec = importlib.util.spec_from_file_location("candidate_summary", ENTRY)
candidate = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(candidate)


class AcceptanceTests(unittest.TestCase):
    def test_all_reviewed_contract_cases(self):
        contract = json.loads((ROOT / "docs" / "contract.json").read_text(encoding="utf-8"))
        self.assertEqual(len(contract["cases"]), 29)
        with tempfile.TemporaryDirectory() as temporary:
            for case in contract["cases"]:
                with self.subTest(case=case["id"]):
                    result = subprocess.run(
                        [sys.executable, str(ENTRY), *case["input"]["arguments"]],
                        cwd=temporary, text=True, capture_output=True, timeout=5,
                    )
                    self.assertTrue(result.stdout.endswith("\n"))
                    self.assertEqual(len(result.stdout.splitlines()), 1)
                    self.assertEqual(
                        {"stdout_json": json.loads(result.stdout),
                         "exit_code": result.returncode, "stderr": result.stderr},
                        case["expected"],
                    )


class IndependentProperties(unittest.TestCase):
    def test_fresh_numeric_example(self):
        self.assertEqual(candidate.summarize({"values": [-12, 15, 3, 15]}),
                         {"count": 4, "span": 27, "total": 21})

    def test_permutation_invariance(self):
        values = [-51, 8, 8, 0, 204, -9, 17]
        expected = candidate.summarize({"values": values})
        random.Random(81).shuffle(values)
        self.assertEqual(candidate.summarize({"values": values}), expected)

    def test_translation_preserves_span(self):
        values = [-7, 0, 13, 13]
        shifted = candidate.summarize({"values": [x + 91 for x in values]})
        self.assertEqual(shifted, {"count": 4, "span": 20, "total": 383})

    def test_duplication_preserves_span_and_doubles_sum(self):
        values = [-8, 5, 23]
        self.assertEqual(candidate.summarize({"values": values * 2}),
                         {"count": 6, "span": 31, "total": 40})

    def test_validation_does_not_change_request(self):
        request = {"values": [12, -4, 12]}
        before = json.dumps(request)
        first = candidate.summarize(request)
        candidate.summarize({"values": [True]})
        self.assertEqual(candidate.summarize(request), first)
        self.assertEqual(json.dumps(request), before)

    def test_shape_precedes_value_error(self):
        self.assertEqual(candidate.summarize({"values": "bad", "other": 1}),
                         {"error": "invalid_request"})

    def test_large_exact_cancellation(self):
        big = 10 ** 85
        self.assertEqual(candidate.summarize({"values": [big, -7, -big]}),
                         {"count": 3, "span": 2 * big, "total": -7})

    def test_thousand_element_boundary(self):
        self.assertEqual(candidate.summarize({"values": list(range(1000))}),
                         {"count": 1000, "span": 999, "total": 499500})

    def test_invalid_element_at_the_end(self):
        self.assertEqual(candidate.summarize({"values": [1, 2, False]}),
                         {"error": "integer_list_required"})


if __name__ == "__main__":
    unittest.main()
