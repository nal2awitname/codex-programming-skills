"""Portable integer-list summary CLI, implemented from the behavior contract."""

from __future__ import annotations

import json
import sys
from collections.abc import Sequence

Response = dict[str, int | str | None]


def summarize(request: object) -> Response:
    """Validate a request and return the public summary or error object."""
    if not isinstance(request, dict) or len(request) != 1 or "values" not in request:
        return {"error": "invalid_request"}

    values = request["values"]
    if not isinstance(values, list):
        return {"error": "integer_list_required"}

    count = 0
    total = 0
    low: int | None = None
    high: int | None = None
    for number in values:
        # JSON booleans are not accepted as integer values.
        if type(number) is not int:
            return {"error": "integer_list_required"}
        count += 1
        total += number
        low = number if low is None or number < low else low
        high = number if high is None or number > high else high

    width = None if low is None or high is None else high - low
    return {"count": count, "span": width, "total": total}


def evaluate_text(text: str | None) -> Response:
    """Decode one JSON argument; parsing errors use the public error response."""
    if text is None:
        return {"error": "invalid_json"}
    try:
        request = json.loads(text)
    except (ValueError, RecursionError):
        return {"error": "invalid_json"}
    return summarize(request)


def main(arguments: Sequence[str] | None = None) -> int:
    """Process the first argument only and emit one newline-terminated JSON object."""
    supplied = list(sys.argv[1:] if arguments is None else arguments)
    result = evaluate_text(supplied[0] if supplied else None)
    sys.stdout.write(json.dumps(result, ensure_ascii=True, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
