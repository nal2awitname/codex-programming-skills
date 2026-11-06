# Behavior contract

The authoritative machine-readable contract is `contract.json`: eight observed
requirements, 29 independently authored synthetic acceptance cases and ten public
compatibility literals with documented reasons and neutral evidence IDs.

| Requirement | Public behavior |
| --- | --- |
| REQ-001 | Exactly one object property named `values`; shape validation has priority. |
| REQ-002 | An array of integers; booleans, decimal/exponential tokens and other types are rejected. |
| REQ-003 | Nonempty arrays return exact `count`, greatest-minus-least `span`, and `total`. |
| REQ-004 | Empty arrays return count 0, span null and total 0. |
| REQ-005 | The exercised large integers, up to magnitude 10^100, retain exact arithmetic. |
| REQ-006 | Read the first JSON argument; missing, empty or malformed JSON gives `invalid_json`. |
| REQ-007 | Ignore later command arguments. |
| REQ-008 | Emit one newline-terminated JSON object, no stderr, and exit 0 for defined outcomes. |

Case input is a test envelope containing an `arguments` array, passed unchanged as
the CLI argument list. Expected results contain parsed `stdout_json`, `exit_code`
and `stderr`. Object key order and insignificant JSON whitespace are irrelevant;
numeric values, types, errors and output framing remain significant.

Only behavior is specified. No private architecture, algorithms or source layout
of the reference are prescribed. Examples are synthetic; the fixed public fields
and error strings are retained solely for observable compatibility.

No original language/version, hidden behavior, persistence or exhaustive input
limits are known. Windows runtime validation remains outstanding. Duplicate JSON
keys, nonstandard constants, extreme nesting and resource/encoding failures are
outside the accepted observations. Refer to `contract.json` for the complete audit,
exclusions and unknowns before extending behavior.
