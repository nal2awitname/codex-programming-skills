# Body mass index (BMI)
Kind: recipe
Keywords: bmi, body mass index, weight, height, ดัชนีมวลกาย, น้ำหนัก, ส่วนสูง
Module: bmi

BMI is weight in kilograms divided by height in metres squared. The categories follow the WHO adult ranges; other populations may use different cut-offs.

```python module
"""Body mass index calculation and WHO adult categories."""


def bmi(weight_kg: float, height_m: float) -> float:
    """Return BMI rounded to one decimal place."""
    if weight_kg <= 0 or height_m <= 0:
        raise ValueError("weight and height must be positive")
    return round(weight_kg / (height_m ** 2), 1)


def bmi_category(value: float) -> str:
    """Return the WHO adult category for a BMI value."""
    if value < 18.5:
        return "underweight"
    if value < 25:
        return "normal"
    if value < 30:
        return "overweight"
    return "obese"


if __name__ == "__main__":
    value = bmi(70, 1.75)
    print(value, bmi_category(value))
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from bmi import bmi, bmi_category


class BmiTests(unittest.TestCase):
    def test_value(self):
        self.assertEqual(bmi(70, 1.75), 22.9)

    def test_categories(self):
        self.assertEqual([bmi_category(v) for v in (17, 22, 27, 31)],
                         ["underweight", "normal", "overweight", "obese"])
        self.assertEqual(bmi_category(25), "overweight")

    def test_invalid(self):
        with self.assertRaises(ValueError):
            bmi(70, 0)


if __name__ == "__main__":
    unittest.main()
```
