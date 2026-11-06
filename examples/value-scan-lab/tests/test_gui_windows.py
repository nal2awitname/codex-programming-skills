"""Real Tk window/button smoke test, intended for an interactive Windows runner."""

import os
import sys
import unittest


class WindowsGuiSmokeTests(unittest.TestCase):
    def test_real_buttons_scan_137_then_120_and_restart(self):
        required = os.environ.get("VALUE_SCAN_REQUIRE_GUI") == "1"

        def unavailable(reason):
            if required:
                self.fail(f"VALUE_SCAN_REQUIRE_GUI=1: {reason}")
            self.skipTest(reason)

        if sys.platform != "win32":
            unavailable(f"Windows-only GUI smoke: host {sys.platform} has no Windows desktop/display; not exercised")
        try:
            import tkinter as tk
        except ImportError as error:
            unavailable(f"Tkinter unavailable; GUI/display not exercised: {error}")
        from valuescanlab.gui import LabWindow

        try:
            root = tk.Tk()
        except tk.TclError as error:
            unavailable(f"No usable desktop/display; GUI not exercised: {error}")
        try:
            window = LabWindow(root)
            root.update()
            self.assertEqual(root.winfo_exists(), 1)

            def rows():
                return [tuple(map(str, window.results.item(item, "values")))
                        for item in window.results.get_children()]

            window.first_button.invoke()
            root.update()
            self.assertEqual(rows(), [("0", "137"), ("8", "137"), ("16", "137")])

            window.lower_button.invoke()
            root.update()
            self.assertEqual(window.buffer.read(2), 120)
            self.assertEqual(rows(), [("0", "137"), ("8", "120"), ("16", "137")])

            window.value_var.set("120")
            window.refine_button.invoke()
            root.update()
            self.assertEqual(rows(), [("8", "120")])

            window.restart_button.invoke()
            root.update()
            self.assertEqual(window.buffer.values(), [137, 20, 137, -3, 137, 0])
            self.assertEqual(rows(), [])
            self.assertEqual(window.value_var.get(), "137")
            self.assertFalse(window.scanner.started)
        finally:
            root.destroy()


if __name__ == "__main__":
    unittest.main()
