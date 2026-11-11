# Temperature conversion
Kind: recipe
Keywords: temperature, celsius, fahrenheit, kelvin, degree, อุณหภูมิ, องศา, เซลเซียส, ฟาเรนไฮต์
Module: temperature

Convert temperatures between Celsius, Fahrenheit and Kelvin. Values below absolute zero are rejected with ValueError because they cannot exist physically.

```python module
"""Temperature conversion between Celsius, Fahrenheit and Kelvin."""

ABSOLUTE_ZERO_C = -273.15


def _check_celsius(value: float) -> float:
    """Reject temperatures colder than absolute zero."""
    if value < ABSOLUTE_ZERO_C:
        raise ValueError("temperature is below absolute zero")
    return value


def celsius_to_fahrenheit(celsius: float) -> float:
    """Convert degrees Celsius to degrees Fahrenheit."""
    return _check_celsius(celsius) * 9 / 5 + 32


def fahrenheit_to_celsius(fahrenheit: float) -> float:
    """Convert degrees Fahrenheit to degrees Celsius."""
    return _check_celsius((fahrenheit - 32) * 5 / 9)


def celsius_to_kelvin(celsius: float) -> float:
    """Convert degrees Celsius to kelvin."""
    return _check_celsius(celsius) - ABSOLUTE_ZERO_C


def kelvin_to_celsius(kelvin: float) -> float:
    """Convert kelvin to degrees Celsius."""
    return _check_celsius(kelvin + ABSOLUTE_ZERO_C)


if __name__ == "__main__":
    print(f"37 C = {celsius_to_fahrenheit(37):.1f} F")
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from temperature import (celsius_to_fahrenheit, celsius_to_kelvin, fahrenheit_to_celsius,
                         kelvin_to_celsius)


class TemperatureTests(unittest.TestCase):
    def test_reference_points(self):
        self.assertAlmostEqual(celsius_to_fahrenheit(100), 212)
        self.assertAlmostEqual(fahrenheit_to_celsius(32), 0)
        self.assertAlmostEqual(celsius_to_kelvin(0), 273.15)
        self.assertAlmostEqual(kelvin_to_celsius(0), -273.15)

    def test_round_trip(self):
        self.assertAlmostEqual(fahrenheit_to_celsius(celsius_to_fahrenheit(21.5)), 21.5)

    def test_below_absolute_zero(self):
        with self.assertRaises(ValueError):
            celsius_to_fahrenheit(-300)
        with self.assertRaises(ValueError):
            kelvin_to_celsius(-1)


if __name__ == "__main__":
    unittest.main()
```
