# Value added tax (VAT)
Kind: recipe
Keywords: vat, value added tax, sales tax, tax, ภาษีมูลค่าเพิ่ม, ภาษี, แวต, ราคารวมภาษี
Module: vat

Add VAT to a net price or extract it from a gross price. Use Decimal and round half up to two places, as invoices do. The default rate is 7 percent.

```python module
"""VAT calculations with Decimal rounding to two places."""

from decimal import ROUND_HALF_UP, Decimal

DEFAULT_RATE = Decimal("0.07")
CENT = Decimal("0.01")


def _money(value) -> Decimal:
    """Convert to Decimal and round half up to cents."""
    return Decimal(str(value)).quantize(CENT, rounding=ROUND_HALF_UP)


def add_vat(net, rate=DEFAULT_RATE) -> Decimal:
    """Return the gross amount for a net amount."""
    if Decimal(str(net)) < 0:
        raise ValueError("amount must not be negative")
    return _money(Decimal(str(net)) * (1 + Decimal(str(rate))))


def vat_amount(net, rate=DEFAULT_RATE) -> Decimal:
    """Return only the tax part for a net amount."""
    return add_vat(net, rate) - _money(net)


def remove_vat(gross, rate=DEFAULT_RATE) -> Decimal:
    """Return the net amount contained in a gross amount."""
    if Decimal(str(gross)) < 0:
        raise ValueError("amount must not be negative")
    return _money(Decimal(str(gross)) / (1 + Decimal(str(rate))))


if __name__ == "__main__":
    print(add_vat(100), remove_vat(107))
```

```python tests
import os
import sys
import unittest
from decimal import Decimal

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from vat import add_vat, remove_vat, vat_amount


class VatTests(unittest.TestCase):
    def test_default_rate(self):
        self.assertEqual(add_vat(100), Decimal("107.00"))
        self.assertEqual(vat_amount(100), Decimal("7.00"))
        self.assertEqual(remove_vat(107), Decimal("100.00"))

    def test_rounding_half_up(self):
        self.assertEqual(add_vat("0.50"), Decimal("0.54"))

    def test_custom_rate_and_negative(self):
        self.assertEqual(add_vat(200, "0.10"), Decimal("220.00"))
        with self.assertRaises(ValueError):
            add_vat(-1)


if __name__ == "__main__":
    unittest.main()
```
