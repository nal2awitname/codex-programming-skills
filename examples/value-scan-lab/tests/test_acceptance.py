"""Independently authored acceptance assertions for CASE-001 through CASE-022."""

import unittest

from valuescanlab import evaluate_scenario


def first(mode, value=None):
    step = {"action": "first", "mode": mode}
    if mode == "exact":
        step["value"] = value
    return step


def refine(mode, value=None):
    step = {"action": "next", "mode": mode}
    if mode == "exact":
        step["value"] = value
    return step


def write(index, value):
    return {"action": "set", "index": index, "value": value}


def result(offsets, values):
    return {"offsets": offsets, "values": values}


class ContractAcceptanceTests(unittest.TestCase):
    def assert_run(self, initial, steps, *history):
        actual = evaluate_scenario({"initial": initial, "steps": steps})
        self.assertEqual(actual, {"history": list(history)})

    def assert_error(self, initial, steps, name):
        self.assertEqual(
            evaluate_scenario({"initial": initial, "steps": steps}),
            {"error": name},
        )

    def test_CASE_001_demo_narrows_three_matches_to_offset_eight(self):
        self.assert_run(
            [137, 20, 137, -3, 137, 0],
            [first("exact", 137), write(2, 120), refine("exact", 120)],
            result([0, 8, 16], [137, 137, 137]),
            result([8], [120]),
        )

    def test_CASE_002_newly_matching_slot_is_not_added(self):
        self.assert_run(
            [11, 3, 11],
            [first("exact", 11), write(0, 9), write(1, 9), refine("exact", 9)],
            result([0, 8], [11, 11]),
            result([0], [9]),
        )

    def test_CASE_003_changed_uses_immediately_previous_scan(self):
        self.assert_run(
            [4, 4],
            [first("unknown"), write(0, 5), refine("changed"), refine("changed")],
            result([0, 4], [4, 4]),
            result([0], [5]),
            result([], []),
        )

    def test_CASE_004_unchanged_excludes_modified_slot(self):
        self.assert_run(
            [4, 4, 9],
            [first("unknown"), write(1, 5), refine("unchanged")],
            result([0, 4, 8], [4, 4, 9]),
            result([0, 8], [4, 9]),
        )

    def test_CASE_005_increased_is_strict_and_signed(self):
        self.assert_run(
            [-5, 0, 7],
            [first("unknown"), write(0, -4), write(2, 6), refine("increased")],
            result([0, 4, 8], [-5, 0, 7]),
            result([0], [-4]),
        )

    def test_CASE_006_decreased_is_strict_and_signed(self):
        self.assert_run(
            [-5, 0, 7],
            [first("unknown"), write(0, -4), write(2, 6), refine("decreased")],
            result([0, 4, 8], [-5, 0, 7]),
            result([8], [6]),
        )

    def test_CASE_007_signed_32_bit_boundaries(self):
        self.assert_run(
            [-2147483648, 2147483647, -2147483648],
            [first("exact", -2147483648)],
            result([0, 8], [-2147483648, -2147483648]),
        )

    def test_CASE_008_empty_buffer_still_starts_a_scan(self):
        self.assert_run(
            [], [first("unknown"), refine("unchanged")],
            result([], []), result([], []),
        )

    def test_CASE_009_refine_requires_initial_scan(self):
        self.assert_error([1], [refine("exact", 1)], "scan_not_started")

    def test_CASE_010_boolean_initial_value_is_rejected(self):
        self.assert_error([True], [first("unknown")], "invalid_value")

    def test_CASE_011_noninteger_initial_value_is_rejected(self):
        self.assert_error([1.5], [first("unknown")], "invalid_value")

    def test_CASE_012_positive_overflow_is_rejected(self):
        self.assert_error([2147483648], [first("unknown")], "invalid_value")

    def test_CASE_013_changed_is_not_an_initial_mode(self):
        self.assert_error([1], [first("changed")], "invalid_mode")

    def test_CASE_014_unknown_is_not_a_refinement_mode(self):
        self.assert_error([1], [first("unknown"), refine("unknown")], "invalid_mode")

    def test_CASE_015_reset_requires_a_new_initial_scan(self):
        self.assert_error(
            [1], [first("unknown"), {"action": "reset"}, refine("unchanged")],
            "scan_not_started",
        )

    def test_CASE_016_negative_index_is_rejected(self):
        self.assert_error([1], [write(-1, 8)], "invalid_index")

    def test_CASE_017_boolean_search_value_is_rejected(self):
        self.assert_error([1], [first("exact", True)], "invalid_value")

    def test_CASE_018_new_initial_scan_searches_the_whole_buffer(self):
        self.assert_run(
            [8, 3, 8], [first("exact", 8), first("exact", 3)],
            result([0, 8], [8, 8]), result([4], [3]),
        )

    def test_CASE_019_empty_candidate_set_cannot_grow_on_refine(self):
        self.assert_run(
            [2, 3], [first("exact", 8), write(0, 8), refine("exact", 8)],
            result([], []), result([], []),
        )

    def test_CASE_020_negative_overflow_write_is_rejected(self):
        self.assert_error([0], [write(0, -2147483649)], "invalid_value")

    def test_CASE_021_increase_compares_with_last_changed_result(self):
        self.assert_run(
            [8, 8],
            [first("unknown"), write(0, 7), refine("changed"), write(0, 8), refine("increased")],
            result([0, 4], [8, 8]), result([0], [7]), result([0], [8]),
        )

    def test_CASE_022_boolean_index_is_rejected(self):
        self.assert_error([1], [write(True, 8)], "invalid_index")


if __name__ == "__main__":
    unittest.main()
