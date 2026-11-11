# FizzBuzz
Kind: recipe
Keywords: fizzbuzz, fizz, buzz, ฟิซบัซ
Module: fizzbuzz

Numbers divisible by 3 become Fizz, by 5 become Buzz, by both become FizzBuzz.

```python module
"""The classic FizzBuzz sequence."""


def fizzbuzz_value(number: int) -> str:
    """Return the FizzBuzz word for one number."""
    word = ("Fizz" if number % 3 == 0 else "") + ("Buzz" if number % 5 == 0 else "")
    return word or str(number)


def fizzbuzz(limit: int) -> list:
    """Return FizzBuzz values from 1 to ``limit`` inclusive."""
    return [fizzbuzz_value(number) for number in range(1, limit + 1)]


if __name__ == "__main__":
    print("\n".join(fizzbuzz(15)))
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from fizzbuzz import fizzbuzz


class FizzBuzzTests(unittest.TestCase):
    def test_first_fifteen(self):
        values = fizzbuzz(15)
        self.assertEqual(values[:5], ["1", "2", "Fizz", "4", "Buzz"])
        self.assertEqual(values[14], "FizzBuzz")
        self.assertEqual(len(values), 15)

    def test_zero(self):
        self.assertEqual(fizzbuzz(0), [])


if __name__ == "__main__":
    unittest.main()
```
