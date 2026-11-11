# Student grades
Kind: recipe
Keywords: grade, grades, score, average, gpa, student, เกรด, คะแนน, ตัดเกรด, นักเรียน
Module: grades

Map 0-100 scores to letter grades using the common 80/70/60/50 bands and compute averages. Adjust the bands to match your institution.

```python module
"""Score to letter-grade conversion and averages."""

BANDS = ((80, "A"), (70, "B"), (60, "C"), (50, "D"))


def letter_grade(score: float) -> str:
    """Return the letter grade for a score between 0 and 100."""
    if not 0 <= score <= 100:
        raise ValueError("score must be between 0 and 100")
    for minimum, letter in BANDS:
        if score >= minimum:
            return letter
    return "F"


def average(scores: list) -> float:
    """Return the mean score rounded to two decimals."""
    if not scores:
        raise ValueError("scores must not be empty")
    return round(sum(scores) / len(scores), 2)


def report(scores: dict) -> dict:
    """Return each student's letter grade."""
    return {name: letter_grade(score) for name, score in scores.items()}


if __name__ == "__main__":
    print(report({"ann": 91, "bo": 64}))
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from grades import average, letter_grade, report


class GradeTests(unittest.TestCase):
    def test_bands(self):
        self.assertEqual([letter_grade(s) for s in (95, 80, 79.5, 65, 50, 10)],
                         ["A", "A", "B", "C", "D", "F"])

    def test_average_and_report(self):
        self.assertEqual(average([70, 80, 95]), 81.67)
        self.assertEqual(report({"ann": 91}), {"ann": "A"})

    def test_invalid(self):
        with self.assertRaises(ValueError):
            letter_grade(101)
        with self.assertRaises(ValueError):
            average([])


if __name__ == "__main__":
    unittest.main()
```
