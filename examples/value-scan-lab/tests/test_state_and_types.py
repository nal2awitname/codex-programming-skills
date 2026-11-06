"""Boundary validation and state invariants beyond the acceptance examples."""

import copy
import ctypes
import unittest

from valuescanlab import LabError, OwnedIntBuffer, Scanner, demo_scenario, evaluate_scenario


class BufferValidationTests(unittest.TestCase):
    def assert_lab_error(self, name, operation):
        with self.assertRaises(LabError) as caught:
            operation()
        self.assertEqual(caught.exception.name, name)

    def test_storage_is_four_byte_signed_little_endian(self):
        buffer = OwnedIntBuffer([0x01020304, -2, -2147483648, 2147483647])
        actual = ctypes.string_at(ctypes.addressof(buffer._memory), 16)
        self.assertEqual(actual, b"\x04\x03\x02\x01\xfe\xff\xff\xff\x00\x00\x00\x80\xff\xff\xff\x7f")
        self.assertEqual(buffer.values(), [16909060, -2, -2147483648, 2147483647])

    def test_writes_preserve_neighboring_slots(self):
        buffer = OwnedIntBuffer([10, 20, 30])
        buffer.write(1, -2147483648)
        self.assertEqual(buffer.values(), [10, -2147483648, 30])
        buffer.write(1, 2147483647)
        self.assertEqual(buffer.values(), [10, 2147483647, 30])

    def test_buffer_owns_a_copy_of_supplied_values(self):
        initial = [5, 6]
        buffer = OwnedIntBuffer(initial)
        initial[0] = 99
        buffer.write(1, 7)
        self.assertEqual(buffer.values(), [5, 7])
        self.assertEqual(initial, [99, 6])

    def test_every_value_entry_point_rejects_nonintegers_and_overflow(self):
        for invalid in (True, False, None, "1", 1.0, [], {}, -2147483649, 2147483648):
            with self.subTest(value=invalid):
                self.assert_lab_error("invalid_value", lambda: OwnedIntBuffer([invalid]))
                buffer = OwnedIntBuffer([1])
                scanner = Scanner(buffer)
                scanner.first("unknown")
                self.assert_lab_error("invalid_value", lambda: buffer.write(0, invalid))
                self.assert_lab_error("invalid_value", lambda: scanner.first("exact", invalid))
                self.assert_lab_error("invalid_value", lambda: scanner.next("exact", invalid))
                self.assertEqual(buffer.values(), [1])

    def test_read_and_write_indices_are_strict_and_bounded(self):
        buffer = OwnedIntBuffer([10, 20])
        for invalid in (-1, 2, 100, True, False, 0.0, "0", None, [], {}):
            with self.subTest(index=invalid):
                self.assert_lab_error("invalid_index", lambda: buffer.read(invalid))
                self.assert_lab_error("invalid_index", lambda: buffer.write(invalid, 99))
        self.assertEqual(buffer.values(), [10, 20])

    def test_empty_buffer_has_no_valid_index(self):
        buffer = OwnedIntBuffer([])
        self.assertEqual(len(buffer), 0)
        self.assert_lab_error("invalid_index", lambda: buffer.read(0))
        self.assert_lab_error("invalid_index", lambda: buffer.write(0, 1))


class ScanStateTests(unittest.TestCase):
    def test_failed_first_does_not_replace_existing_state(self):
        buffer = OwnedIntBuffer([5, 1])
        scanner = Scanner(buffer)
        scanner.first("exact", 5)
        buffer.write(0, 6)
        for mode, value in (("changed", None), ("exact", True)):
            with self.assertRaises(LabError):
                scanner.first(mode, value)
        self.assertEqual(scanner.next("increased"), {"offsets": [0], "values": [6]})

    def test_failed_refinement_does_not_advance_baseline(self):
        buffer = OwnedIntBuffer([5])
        scanner = Scanner(buffer)
        scanner.first("unknown")
        buffer.write(0, 6)
        for mode, value in (("unknown", None), ("exact", "6"), ([], None)):
            with self.assertRaises(LabError):
                scanner.next(mode, value)
        self.assertEqual(scanner.next("increased"), {"offsets": [0], "values": [6]})

    def test_display_reads_do_not_complete_a_scan(self):
        buffer = OwnedIntBuffer([5])
        scanner = Scanner(buffer)
        scanner.first("unknown")
        buffer.write(0, 6)
        self.assertEqual(scanner.current_results(), {"offsets": [0], "values": [6]})
        self.assertEqual(scanner.next("changed"), {"offsets": [0], "values": [6]})

    def test_result_objects_do_not_expose_mutable_scan_state(self):
        buffer = OwnedIntBuffer([5, 5])
        scanner = Scanner(buffer)
        result = scanner.first("unknown")
        result["offsets"].clear()
        result["values"][0] = 99
        self.assertEqual(scanner.next("unchanged"), {"offsets": [0, 4], "values": [5, 5]})

    def test_reset_clears_candidates_but_preserves_current_buffer(self):
        buffer = OwnedIntBuffer([5])
        scanner = Scanner(buffer)
        scanner.first("unknown")
        buffer.write(0, 6)
        scanner.reset()
        self.assertFalse(scanner.started)
        self.assertEqual(scanner.current_results(), {"offsets": [], "values": []})
        self.assertEqual(buffer.values(), [6])
        with self.assertRaisesRegex(LabError, "scan_not_started"):
            scanner.next("unchanged")
        self.assertEqual(scanner.first("exact", 6), {"offsets": [0], "values": [6]})

    def test_empty_results_are_distinct_from_not_started(self):
        scanner = Scanner(OwnedIntBuffer([1]))
        scanner.first("exact", 2)
        self.assertTrue(scanner.started)
        self.assertEqual(scanner.next("unchanged"), {"offsets": [], "values": []})

    def test_exact_scan_updates_comparison_baseline(self):
        buffer = OwnedIntBuffer([5])
        scanner = Scanner(buffer)
        scanner.first("unknown")
        buffer.write(0, 7)
        scanner.next("exact", 7)
        buffer.write(0, 6)
        self.assertEqual(scanner.next("decreased"), {"offsets": [0], "values": [6]})

    def test_invalid_mode_types_are_named_errors(self):
        scanner = Scanner(OwnedIntBuffer([1]))
        scanner.first("unknown")
        for mode in (None, True, 1, [], {}, "EXACT", ""):
            with self.subTest(mode=mode):
                for operation in (scanner.first, scanner.next):
                    with self.assertRaisesRegex(LabError, "invalid_mode"):
                        operation(mode)


class ScenarioValidationTests(unittest.TestCase):
    def test_malformed_scenario_shapes_return_named_errors(self):
        invalid = (
            None, True, 1, [], "scenario", {},
            {"initial": [1]},
            {"initial": [1], "steps": None},
            {"initial": "1", "steps": []},
            {"initial": [1], "steps": [None]},
            {"initial": [1], "steps": [{}]},
            {"initial": [1], "steps": [{"action": []}]},
            {"initial": [1], "steps": [{"action": "attach"}]},
            {"initial": [1], "steps": [], "extra": 0},
            {"initial": [1], "steps": [{"action": "reset", "extra": 0}]},
            {"initial": [1], "steps": [{"action": "first", "mode": "unknown", "value": 1}]},
        )
        for data in invalid:
            with self.subTest(data=data):
                self.assertEqual(evaluate_scenario(data), {"error": "invalid_scenario"})

    def test_missing_required_step_fields_have_named_errors(self):
        cases = (
            ({"action": "first"}, "invalid_mode"),
            ({"action": "first", "mode": "exact"}, "invalid_value"),
            ({"action": "set", "value": 8}, "invalid_index"),
            ({"action": "set", "index": 0}, "invalid_value"),
        )
        for step, error in cases:
            with self.subTest(step=step):
                self.assertEqual(evaluate_scenario({"initial": [1], "steps": [step]}), {"error": error})

    def test_mutations_and_reset_do_not_add_history_entries(self):
        scenario = {
            "initial": [1],
            "steps": [
                {"action": "set", "index": 0, "value": 2},
                {"action": "first", "mode": "unknown"},
                {"action": "reset"},
                {"action": "set", "index": 0, "value": 3},
                {"action": "first", "mode": "unknown"},
            ],
        }
        self.assertEqual(evaluate_scenario(scenario), {"history": [
            {"offsets": [0], "values": [2]}, {"offsets": [0], "values": [3]},
        ]})

    def test_repeated_evaluations_are_independent_and_input_is_unchanged(self):
        scenario = demo_scenario()
        before = copy.deepcopy(scenario)
        first_result = evaluate_scenario(scenario)
        self.assertEqual(evaluate_scenario(scenario), first_result)
        self.assertEqual(scenario, before)

    def test_earlier_history_values_are_not_rewritten_after_mutation(self):
        data = {"initial": [7], "steps": [
            {"action": "first", "mode": "unknown"},
            {"action": "set", "index": 0, "value": 9},
            {"action": "next", "mode": "changed"},
        ]}
        self.assertEqual(evaluate_scenario(data), {"history": [
            {"offsets": [0], "values": [7]}, {"offsets": [0], "values": [9]},
        ]})


if __name__ == "__main__":
    unittest.main()
