# Palindrome check
Kind: recipe
Keywords: palindrome, reverse string, พาลินโดรม, กลับคำ, อ่านกลับ
Module: palindrome

A phrase is a palindrome when its letters and digits read the same backwards, ignoring case, spaces and punctuation.

```python module
"""Palindrome detection that ignores case, spacing and punctuation."""


def normalize(text: str) -> str:
    """Keep only letters and digits, case-folded."""
    return "".join(char.casefold() for char in text if char.isalnum())


def is_palindrome(text: str) -> bool:
    """Return True when ``text`` reads the same forwards and backwards."""
    cleaned = normalize(text)
    return cleaned == cleaned[::-1]


def reverse_text(text: str) -> str:
    """Return ``text`` reversed character by character."""
    return text[::-1]


if __name__ == "__main__":
    print(is_palindrome("A man, a plan, a canal: Panama"))
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from palindrome import is_palindrome, reverse_text


class PalindromeTests(unittest.TestCase):
    def test_phrases(self):
        self.assertTrue(is_palindrome("A man, a plan, a canal: Panama"))
        self.assertTrue(is_palindrome("No 'x' in Nixon"))
        self.assertFalse(is_palindrome("collaboration"))

    def test_edge_cases(self):
        self.assertTrue(is_palindrome(""))
        self.assertEqual(reverse_text("abc"), "cba")


if __name__ == "__main__":
    unittest.main()
```
