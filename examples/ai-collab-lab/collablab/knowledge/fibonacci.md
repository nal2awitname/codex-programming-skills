# Fibonacci numbers
Kind: recipe
Keywords: fibonacci, fib, sequence, ฟีโบนัชชี, ลำดับ
Module: fibonacci

Iterative Fibonacci avoids recursion depth limits and runs in linear time. F(0) = 0 and F(1) = 1.

```python module
"""Fibonacci numbers computed iteratively."""


def fibonacci(n: int) -> int:
    """Return the n-th Fibonacci number, with fibonacci(0) == 0."""
    if not isinstance(n, int) or n < 0:
        raise ValueError("n must be a non-negative integer")
    previous, current = 0, 1
    for _ in range(n):
        previous, current = current, previous + current
    return previous


def fibonacci_sequence(count: int) -> list:
    """Return the first ``count`` Fibonacci numbers."""
    if not isinstance(count, int) or count < 0:
        raise ValueError("count must be a non-negative integer")
    return [fibonacci(index) for index in range(count)]


if __name__ == "__main__":
    print(fibonacci_sequence(10))
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from fibonacci import fibonacci, fibonacci_sequence


class FibonacciTests(unittest.TestCase):
    def test_known_values(self):
        self.assertEqual([fibonacci(n) for n in range(8)], [0, 1, 1, 2, 3, 5, 8, 13])
        self.assertEqual(fibonacci(50), 12586269025)

    def test_sequence(self):
        self.assertEqual(fibonacci_sequence(5), [0, 1, 1, 2, 3])
        self.assertEqual(fibonacci_sequence(0), [])

    def test_invalid(self):
        with self.assertRaises(ValueError):
            fibonacci(-1)


if __name__ == "__main__":
    unittest.main()
```
