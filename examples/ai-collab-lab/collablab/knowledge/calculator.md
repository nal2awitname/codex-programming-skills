# Safe calculator
Kind: recipe
Keywords: calculator, calculate, arithmetic, expression, เครื่องคิดเลข, คิดเลข, คำนวณเลข
Module: calculator

Evaluate arithmetic expressions by walking the Python AST. Never call eval on user input: only numbers and the four operators (plus power and modulo) are accepted.

```python module
"""A safe arithmetic calculator built on the ast module."""

import ast
import operator

OPERATORS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
}


def _evaluate(node: ast.AST) -> float:
    """Evaluate one supported AST node."""
    if isinstance(node, ast.Constant) and type(node.value) in (int, float):
        return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in OPERATORS:
        right = _evaluate(node.right)
        if isinstance(node.op, ast.Pow) and abs(right) > 100:
            raise ValueError("exponent too large")
        return OPERATORS[type(node.op)](_evaluate(node.left), right)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
        value = _evaluate(node.operand)
        return value if isinstance(node.op, ast.UAdd) else -value
    raise ValueError("unsupported expression")


def calculate(expression: str) -> float:
    """Return the value of an arithmetic expression such as '2 * (3 + 4)'."""
    try:
        tree = ast.parse(expression, mode="eval")
    except SyntaxError as error:
        raise ValueError("invalid expression") from error
    return _evaluate(tree.body)


if __name__ == "__main__":
    print(calculate("2 * (3 + 4) - 5 / 2"))
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from calculator import calculate


class CalculatorTests(unittest.TestCase):
    def test_arithmetic(self):
        self.assertEqual(calculate("2 * (3 + 4)"), 14)
        self.assertAlmostEqual(calculate("-5 / 2 + 1"), -1.5)
        self.assertEqual(calculate("2 ** 10 % 1000"), 24)

    def test_rejects_code(self):
        for expression in ("__import__('os')", "a + 1", "2 ** 1000", "1 +"):
            with self.assertRaises(ValueError):
                calculate(expression)

    def test_division_by_zero(self):
        with self.assertRaises(ZeroDivisionError):
            calculate("1 / 0")


if __name__ == "__main__":
    unittest.main()
```
