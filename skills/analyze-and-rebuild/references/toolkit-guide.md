# ARB workbench 2.1.0

## Contents

- [Commands](#commands)
- [Analysis and evidence](#analysis-and-evidence)
- [Contract and cases](#contract-and-cases)
- [Observe and verify](#observe-and-verify)
- [Audited builder handoff](#audited-builder-handoff)
- [Limits and testing](#limits-and-testing)

Use Python 3.10+ with standard libraries only. Resolve `SKILL_DIR` to the installed skill folder. The scripts provide inventory, records, gates and CLI testing; Codex or a developer performs the actual reasoning and writes the new implementation. Do not treat an automatically generated inventory as understanding.

This workbench uses schema 2 and separate `contract.json` and `cases.json` files. The Windows-specific `rebuild.py` toolkit uses a different schema and command set; its JSON files are not interchangeable with these inputs. Use `--help` on the installed entrypoint or subcommand to check its supported options.

## Commands

```text
python SKILL_DIR/scripts/arb.py init --source ORIGINAL --work LAB
python SKILL_DIR/scripts/arb.py status --work LAB
python SKILL_DIR/scripts/arb.py report --work LAB
python SKILL_DIR/scripts/arb.py evidence --work LAB --id E-main --file app.py --start 1 --end 30 --summary "Observed construction and behavior, explained in my own words"
python SKILL_DIR/scripts/arb.py attach --work LAB --id E-ui --artifact CAPTURE_FILE --method "Actual GUI/debugger/network observation method" --summary "What was actually observed"
python SKILL_DIR/scripts/arb.py observe --work LAB --command reference-command.json
python SKILL_DIR/scripts/arb.py check --work LAB
python SKILL_DIR/scripts/arb.py seal --work LAB --reviewed
python SKILL_DIR/scripts/arb.py handoff --work LAB --destination BUILDER_INPUT
python SKILL_DIR/scripts/arb.py verify --work LAB --command rebuilt-command.json
```

Replace placeholders with actual paths; quote paths containing spaces. `init` requires an existing source directory and a new, separate workspace; neither may contain the other. It does not execute the reference or overwrite an existing workspace. `status` reports blockers without treating them as an execution failure; `check`, failed probes, failed verification and errors return exit code 2. Successful operations return 0. `--version` prints the toolkit version.

PowerShell wrapper, from the skill's `scripts` directory:

```powershell
.\Analyze-Rebuild.ps1 -Action init -Source 'C:\Original' -Work 'C:\RebuildLab'
.\Analyze-Rebuild.ps1 -Action status -Work 'C:\RebuildLab'
.\Analyze-Rebuild.ps1 -Action observe -Work 'C:\RebuildLab' -CommandFile 'C:\reference-command.json'
.\Analyze-Rebuild.ps1 -Action seal -Work 'C:\RebuildLab' -Reviewed
.\Analyze-Rebuild.ps1 -Action handoff -Work 'C:\RebuildLab' -Destination 'C:\BuilderInput'
.\Analyze-Rebuild.ps1 -Action verify -Work 'C:\RebuildLab' -CommandFile 'C:\rebuilt-command.json'
```

The wrapper finds `py -3`, `python` or `python3`, checks the version, forwards exit codes, and supports `-WhatIf`. It does not alter execution policy or install dependencies. Use the Python entrypoint directly if local policy disallows `.ps1` scripts.

## Analysis and evidence

`analyst/inventory.json` contains hashes, language evidence, symbols and source locations, never source snippets. Python definitions, nested functions, classes, async functions and lambdas are discovered with `ast`. When PowerShell is available, its native parser reads `.ps1`/`.psm1` without executing the target and lists named functions, methods and types. JavaScript/TypeScript declarations and arrows receive **incomplete regex hints**. Other languages, binary/package internals, anonymous runtime closures, plugins, generated code and remote services require additional real analysis with appropriate tools. Inspect parser errors and default exclusions.

`analyst/ledger.json` has:

- `files`: every inspected or skipped file. For an included file record `state: "understood"`, a nonempty `summary`, `evidence_ids`, and `discovery_review` describing dynamic/unsupported discovery and actual scope.
- `units`: every discovered ID; never delete an inconvenient row. Record `scope`, `state`, `summary`, `evidence_ids`, and `requirement_ids` after reading/tracing the actual behavior.
- `feature_discovery`: describe the public surfaces examined: UI actions, CLI commands, APIs, file formats, storage, background work, external services and runtime-created behavior as applicable.
- `features`: manually record actual behaviors, including functions missed by static discovery, using unique `B-...` IDs and the same review/evidence/requirement fields. Account for every requirement.

Explicitly excluded rows use `scope: "excluded"` and a nonempty `exclusion_reason`. Excluding work narrows the completeness claim; it never makes the full original program complete. Keep in-scope unknowns in the contract until resolved. Dynamic discovery notes and evidence links require real analysis, not boilerplate assertions.

`report` writes `analyst/report.md` with file/unit tables, analyst explanations, feature inventory, blockers, exclusions and current verification results. This is an analyst-only view containing private names; it is never part of the builder package.

`evidence` creates an `E-...` record bound to inspected file hash and valid line ranges, with a prose summary. It copies no source text. This records a citation; the software cannot decide whether your explanation is true. Real CLI observations create neutral IDs `O-C-...` for valid captured cases. Keep source-facing descriptions, private names and raw outputs in `analyst/`.

Use `attach` for real GUI captures, debugger traces, protocol observations or other tool output. It records the method, summary, artifact path and SHA-256 without copying the artifact into the handoff. Changed or missing artifacts invalidate the evidence. This supports actual observations from appropriate tools; it does not perform those observations or prove their interpretation automatically.

## Contract and cases

Edit `LAB/contract.json` and `LAB/cases.json` from understanding. Example schema, using invented behavior:

```json
{
  "schema_version": 2,
  "project": "Numeric service",
  "scope": "One public JSON request type; no network or storage",
  "requirements": [{
    "id": "R-total",
    "behavior": "Return the numeric total under the public sum field.",
    "evidence_ids": ["E-main"],
    "case_ids": ["C-basic"]
  }],
  "compatibility_facts": [{"value": "sum", "reason": "Required public response field"}],
  "unknowns": []
}
```

```json
{
  "schema_version": 2,
  "cases": [{
    "id": "C-basic",
    "requirements": ["R-total"],
    "stdin": "[7,2]\n",
    "mode": "json",
    "expected": {"exit_code": 0, "stdout": {"sum": 9}, "stderr": ""}
  }]
}
```

Use `mode: "text"` for exact text including line endings. JSON mode ignores object key order/formatting, preserves array order, and distinguishes JSON value types. Multiple JSON lines in one output require text mode. Each case starts a fresh process; put a stateful sequence in one case or use an external adapter. Never copy original tests. All expected outputs must be independently specified interface facts. Do not automatically forward captured output into the builder package.

## Observe and verify

A command file contains exactly `argv` (an argument array) and `cwd` (an existing directory). Example for an analyst-authorized Python reference:

```json
{"argv": ["py", "-3", "C:\\Original\\app.py"], "cwd": "C:\\Original"}
```

Use an independently built directory and executable for `rebuilt-command.json`. Do not run a rebuild from the original tree. Keep the rebuilt working directory separate from the analyst area. `observe` explicitly executes the configured reference command. `verify` executes the configured rebuilt command, using valid matching observations when available, otherwise explicitly reporting `specified_expectations_only`. An invalid reference capture cannot become a passing comparison. If specified expectations contradict the actual reference, fix the supported contract or record the intentionally different behavior; do not hide the difference.

Each capture has a default 10-second timeout and a 1 MiB cap per output stream. `--timeout` and `--output-limit` adjust them within bounds. Timeout, output overflow, incomplete capture and non-UTF-8 output are failures. Commands use argument arrays with `shell=False`; shell operators in JSON are not interpreted. This runner does not create an OS sandbox or isolate network/filesystem access. Run unknown executables only in a suitable environment already authorized for the task. GUI applications, services, binary protocols and persistent multi-process behavior need dedicated adapters; do not pretend these CLI cases cover them.

## Audited builder handoff

Before sealing, actually audit the neutral contract and synthetic cases for source-derived code, comments, private identifiers, original structure and source-shaped pseudocode. `check` checks coverage mappings, evidence and source freshness, unresolved unknowns, private-symbol leakage and obvious copied long lines. These checks do not prove understanding, exhaustive coverage or absence of every possible copied fragment.

`seal --reviewed` is the analyst's audit record, **not a request for additional user permission**. It binds the current inventory, ledger, evidence, contract, cases and observations. Changes invalidate it. `handoff` writes only four files to a new directory: `contract.json`, `cases.json`, `BUILD_BRIEF.md`, `manifest.json`. It does not copy analyst records, original code, original assets or original binaries. Give only this directory to a fresh builder context. Restrict original access with a real sandbox/account when available; the exporter itself does not enforce access isolation.

After the independent builder finishes, the analyst runs `verify` and maps actual results to requirements. `status` detects changed cases, contract, command file or rebuilt working tree and marks the previous verification stale. Fix and rerun relevant checks. Report exercised cases and remaining gaps; never infer that all original functions are understood from a successful gate or a percentage.

## Limits and testing

Default discovery skips dependency/build folders and credential-like files, refuses links/reparse points, and records oversized/unreadable files. A file-count limit aborts discovery rather than silently truncating it. Source hashes detect changes within the declared inspection boundary. Analyze required excluded dependencies separately when their behavior matters.

Run the synthetic tests:

```text
python -B -m unittest discover -s SKILL_DIR/tests -v
```

Python tests exercise the CLI and workflow on the host where they run. Native PowerShell parser/wrapper checks require an actual PowerShell runtime; Windows behavior requires Windows testing. Record unavailable checks as untested.
