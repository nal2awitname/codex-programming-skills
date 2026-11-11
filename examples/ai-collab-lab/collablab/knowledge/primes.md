# Prime numbers
Kind: recipe
Keywords: prime, primes, sieve, eratosthenes, จำนวนเฉพาะ
Module: primes

Trial division up to the square root checks one number; the sieve of Eratosthenes lists all primes up to a limit.

```python module
"""Prime number checks and listing."""

import math


def is_prime(n: int) -> bool:
    """Return True when n is a prime number."""
    if n < 2:
        return False
    if n % 2 == 0:
        return n == 2
    for divisor in range(3, math.isqrt(n) + 1, 2):
        if n % divisor == 0:
            return False
    return True


def primes_up_to(limit: int) -> list:
    """Return all primes less than or equal to ``limit`` using a sieve."""
    if limit < 2:
        return []
    flags = [True] * (limit + 1)
    flags[0] = flags[1] = False
    for number in range(2, math.isqrt(limit) + 1):
        if flags[number]:
            for multiple in range(number * number, limit + 1, number):
                flags[multiple] = False
    return [number for number, prime in enumerate(flags) if prime]


if __name__ == "__main__":
    print(primes_up_to(50))
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from primes import is_prime, primes_up_to


class PrimeTests(unittest.TestCase):
    def test_is_prime(self):
        self.assertEqual([n for n in range(20) if is_prime(n)], [2, 3, 5, 7, 11, 13, 17, 19])
        self.assertTrue(is_prime(7919))
        self.assertFalse(is_prime(7917))

    def test_sieve_matches_trial_division(self):
        self.assertEqual(primes_up_to(200), [n for n in range(201) if is_prime(n)])
        self.assertEqual(primes_up_to(1), [])


if __name__ == "__main__":
    unittest.main()
```
