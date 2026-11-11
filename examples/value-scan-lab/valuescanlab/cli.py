"""CLI transport; GUI dependencies are loaded only when requested."""

import argparse
import json
import sys
from pathlib import Path

from .scenario import demo_scenario, evaluate_scenario


def _emit(result: dict) -> int:
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if "error" in result else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="scan_lab.py",
        description="Scan signed 32-bit values in ValueScanLab's own buffer.",
    )
    choices = parser.add_mutually_exclusive_group()
    choices.add_argument("--demo", action="store_true", help="emit the 137 to 120 demonstration as JSON")
    choices.add_argument("--scenario", type=Path, metavar="FILE", help="evaluate a JSON scenario")
    options = parser.parse_args(argv)
    if options.demo:
        return _emit(evaluate_scenario(demo_scenario()))
    if options.scenario is not None:
        try:
            text = options.scenario.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            return _emit({"error": "io_error"})
        try:
            data = json.loads(text)
        # Python's integer digit guard raises ValueError rather than the more
        # specific JSONDecodeError. Keep decoder limits on the JSON boundary,
        # with the same named error instead of an uncaught traceback.
        except (ValueError, RecursionError):
            return _emit({"error": "invalid_json"})
        return _emit(evaluate_scenario(data))
    try:
        from .gui import launch

        launch()
    except (ImportError, RuntimeError) as error:
        # ImportError covers Python installations without the optional Tk module.
        print(json.dumps({"error": "gui_unavailable"}), file=sys.stderr)
        return 1
    return 0
