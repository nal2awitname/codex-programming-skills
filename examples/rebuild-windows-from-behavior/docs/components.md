# Components and change guide

| Path | Responsibility | Requirements / verification |
| --- | --- | --- |
| `range_totals.py` — `main` | CLI argument selection and one-line JSON output | REQ-007/008; all subprocess acceptance cases |
| `range_totals.py` — `evaluate_text` | JSON argument decoding and parse errors | REQ-006; malformed/empty/missing/whitespace cases |
| `range_totals.py` — `summarize` | Request validation and integer statistics | REQ-001–005; acceptance and mathematical property tests |
| `range_totals.cmd` | Windows Python launcher; preserves arguments and exit status | CRLF/static review only; Windows host test required |
| `tests/test_range_totals.py` | 29 contract subprocess cases plus 9 independent property checks | `python -m unittest discover -s tests -v` |
| `docs/contract.json` | Audited requirements, examples, literals and unknowns | Reviewed exported builder input |
| `pyproject.toml` | Python 3.10+ and zero third-party dependency declaration | Metadata/static inspection |

The new design uses a JSON adapter and one integer accumulator. Validation rejects
booleans before arithmetic; integer count, extrema and sum remain exact. The new
accumulator takes O(n) time and O(1) auxiliary arithmetic state after JSON decoding.
This complexity describes the new implementation, not an inferred original design.

For a behavior change, add or update a requirement and a synthetic acceptance case,
review the contract, then change the corresponding function and run the suite.
Keep reference execution and private observation records outside this application.
