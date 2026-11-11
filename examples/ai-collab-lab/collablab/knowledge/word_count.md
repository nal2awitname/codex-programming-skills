# Word frequency counter
Kind: recipe
Keywords: word count, word frequency, count words, frequency, นับคำ, ความถี่
Module: wordcount

Split text into lowercase words and count them with collections.Counter. Ties are ordered alphabetically so results are stable.

```python module
"""Word frequency counting."""

import re
from collections import Counter

WORD = re.compile(r"[^\W_]+(?:'[^\W_]+)?")


def words(text: str) -> list:
    """Return the lowercase words of ``text``."""
    return [match.group(0).casefold() for match in WORD.finditer(text)]


def word_frequencies(text: str) -> dict:
    """Return a mapping of word to number of occurrences."""
    return dict(Counter(words(text)))


def top_words(text: str, count: int = 3) -> list:
    """Return the ``count`` most frequent (word, occurrences) pairs."""
    pairs = Counter(words(text)).items()
    return sorted(pairs, key=lambda pair: (-pair[1], pair[0]))[:count]


if __name__ == "__main__":
    print(top_words("the cat and the hat and the bat"))
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from wordcount import top_words, word_frequencies


class WordCountTests(unittest.TestCase):
    def test_frequencies(self):
        self.assertEqual(word_frequencies("Hi hi, there!"), {"hi": 2, "there": 1})

    def test_top_words_breaks_ties_alphabetically(self):
        self.assertEqual(top_words("b a c a b", 2), [("a", 2), ("b", 2)])

    def test_empty(self):
        self.assertEqual(word_frequencies(""), {})


if __name__ == "__main__":
    unittest.main()
```
