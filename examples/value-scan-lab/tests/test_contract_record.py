"""Protect the audited contract copy and its acceptance-case mapping."""

import hashlib
import json
from pathlib import Path
import unittest

class ContractRecordTests(unittest.TestCase):
    def test_saved_contract_is_byte_identical_to_audited_handoff(self):
        contract = Path(__file__).resolve().parents[1] / "docs" / "contract.json"
        digest = hashlib.sha256(contract.read_bytes()).hexdigest()
        self.assertEqual(digest, "c24796ad9fe73b97caba1a0175957f02ed66ab7925d21e9818ce442762a4c58a")

    def test_every_contract_case_has_an_independent_acceptance_test(self):
        from test_acceptance import ContractAcceptanceTests

        contract = Path(__file__).resolve().parents[1] / "docs" / "contract.json"
        data = json.loads(contract.read_text(encoding="utf-8"))
        methods = unittest.defaultTestLoader.getTestCaseNames(ContractAcceptanceTests)
        implemented = {"CASE-" + name.split("_")[2] for name in methods}
        self.assertEqual(implemented, {case["id"] for case in data["cases"]})
        self.assertEqual(len(implemented), 22)
        mapped = {req for case in data["cases"] for req in case["requirement_ids"]}
        self.assertEqual(mapped, {req["id"] for req in data["requirements"]})


if __name__ == "__main__":
    unittest.main()
