# Actual verification

Reconstruction-stage environment: Linux x86_64, Python 3.12.14. No local Windows runtime was available during that stage.

| Check | Actual outcome |
| --- | --- |
| Contract content review and schema validation | Approved after full manual input/expected/literal review; 8 requirements, 29 cases |
| Export | Only audited contract, generated builder instructions and SHA-256 manifest exported |
| Candidate acceptance suite | All 29 CLI cases passed; newline, one object, stderr and exit status checked |
| Independent new-program tests | All 9 property/example tests passed; `unittest` reports 10 methods total including the acceptance method |
| Reference/candidate contract comparison | 29/29 separately captured cases matched the contract and each other |
| Additional differential comparison | 109/109 cases matched; 80 seeded valid arrays, 20 invalid structures/types, 8 CLI/JSON cases and a 10,000-integer array |
| Observed output framing | No framing failure in the reference or candidate differential captures |
| Native Windows launch | Not locally available; later candidate/launcher checks are recorded in repository CI |

The acceptance suite runs only the new implementation. It does not access the
reference. The differential measurements were performed separately by an external
analysis driver; their neutral summaries are `contract-comparison.json` and
`differential-summary.json`. The comparator checks supplied captures and does not
itself execute either application. Actual process captures preceded comparison.

These finite cases support compatibility for the exercised inputs. They do not
prove complete equivalence, undiscovered functions, exact original language, or
absence of copying. The original differential probes were not rerun on Windows. Repository CI separately
checks the candidate and Windows launcher on the declared runner/Python matrix.
Installation/signing and excluded input extremes remain outside this example.

To reproduce the self-contained candidate checks:

```sh
python -m unittest discover -s tests -v
```
