# Runnable toolkit

Use Python 3.10 or later; the bundled CLI has no third-party dependencies.
Resolve `SKILL_DIR` to the actual folder containing SKILL.md. All output paths must
be new. The scripts refuse replacing files, running a reference program, following
symlinks/reparse paths, or recursively exporting analysis. Use trusted, single-user
workspaces; these checks are not a security boundary against concurrent changes.

## Commands

```powershell
$tool = Join-Path $SKILL_DIR 'scripts/rebuild.py'
python $tool init 'C:\Rebuild\analysis-lab' --name 'IndependentTool'
python $tool inspect 'C:\Reference\TargetApp' --out 'C:\Rebuild\analysis-lab\analyst\inventory.json'
python $tool observe --workspace 'C:\Rebuild\analysis-lab' --record 'C:\Rebuild\probe-001.json'
python $tool validate-contract 'C:\Rebuild\analysis-lab\spec\contract.json'
python $tool export --workspace 'C:\Rebuild\analysis-lab' --out 'C:\Rebuild\builder-input-v1'
python $tool compare --contract 'C:\Rebuild\builder-input-v1\contract.json' --reference 'C:\Rebuild\reference-results.json' --candidate 'C:\Rebuild\new-results.json' --out 'C:\Rebuild\comparison-v1.json'
```

Alternatively run `& "$SKILL_DIR/scripts/Invoke-Rebuild.ps1" inspect ...`. The wrapper
forwards arguments to Python and preserves its exit code. `init` creates a draft,
not a working replacement application. Edit and review the contract before export.
The root `.gitignore` excludes analyst data; an ignore file is not access control.

`inspect` reads headers and bounded syntax indicators, streams bounded-size file
hashes and includes no source excerpts. Default: at most 5,000 file entries, 1 MiB
sample per file, full hash only for files at most 64 MiB, and a 256 MiB total read
budget. Adjust with `--max-files`, `--sample-kib`, `--hash-limit-mib`,
`--total-read-mib`. Skips and truncation remain visible in the report.
It does not unpack installers, decompile, prove language identity or discover functions.

## Observation JSON

Create this from a probe actually performed, using synthetic data. Keep it private.
Use a new `OBS-` ID for each observation; `observe` refuses duplicate IDs.

```json
{
  "id": "OBS-001",
  "scenario": "Add two synthetic line items",
  "input": {"items": [3, 8]},
  "actual": {"total": 11},
  "method": "Describe actual actions and capture method here",
  "environment": "Record actual reference version, host and locale here",
  "fixture_origin": "synthetic"
}
```

## Contract JSON schema 1

Use this shape; replace the illustrative scenario with actual evidence. Do not mark
the sample `observed` unless the corresponding real probe was performed. `SPEC-`
IDs refer to primary public specifications and `SRC-` IDs to private analyst notes.
Builder-facing text must not disclose original paths, private identifiers, original
algorithm steps, original code, copied tests or assets. Every exact public literal
retained for compatibility needs a reason and evidence ID.

```json
{
  "schema_version": 1,
  "project": {"name": "IndependentTool", "platform": "Windows"},
  "requirements": [{
    "id": "REQ-001",
    "description": "Return the sum of the supplied item amounts",
    "evidence_status": "proposed",
    "evidence_ids": ["DECISION-001"]
  }],
  "cases": [{
    "id": "CASE-001",
    "requirement_ids": ["REQ-001"],
    "input": {"items": [3, 8]},
    "expected": {"total": 11},
    "evidence_status": "proposed",
    "evidence_ids": ["DECISION-001"],
    "fixture_origin": "synthetic"
  }],
  "compatibility_literals": [],
  "exclusions": [],
  "unknowns": [],
  "handoff_review": {"status": "pending", "reviewer": "", "notes": ""}
}
```

Supported evidence statuses: `observed`, `source-confirmed`, `public-spec-confirmed`,
`proposed`. Keep unknowns outside accepted requirements. Every requirement needs a
mapped case. Observed cases/requirements require `OBS-` IDs and the records must
exist in the analyst ledger before export. The tool checks references, not whether
an expected result is faithful to the observation; review that relationship manually.

## Audit, export and isolation

Read the full contract, including all `input` and `expected` values. Remove copied
or translated implementation, decompiler output, source-shaped pseudocode, private
structure, original paths, unnecessary identifiers and hidden source in fixtures.
Check compatibility literals and evidence. Then set `handoff_review.status` to
`approved`, give the reviewer identity/role and record the audit in `notes`.
Never auto-approve merely to make export pass.

`export` writes exactly `contract.json`, generated `BUILDER.md`, and a SHA-256
manifest. No analyst record, source, binary or inventory is copied. Strict fields,
code-fence checks, a review flag and a manifest do not prove code independence.
The audit is mandatory because arbitrary behavior text and JSON fixture values
cannot be reliably classified as copied code by a schema validator.

Open a fresh builder context and give only the export. Use a separate OS/container
account or environment without original mounts/network access if enforced
isolation is required. A subagent on a shared filesystem still has shared access.
If using the same context, record its prior original exposure. Never claim stronger
separation than actually used.

## Compare separately captured results

Each results file is one JSON object keyed by case ID:

```json
{"CASE-001": {"total": 11}}
```

Capture the reference and new program separately using synthetic contract inputs.
The comparison requires both captures to equal the contract expectation and each
other. Missing cases fail; unexpected IDs are rejected. Object key order is ignored;
array order, strings, nulls, booleans and numeric values remain meaningful. No
floating tolerance, output sorting or nondeterminism normalization is implicit.
Choose an explicit reviewed comparator for domains that require tolerances or
binary/file/UI comparisons. Do not pretend this JSON comparator tests a GUI.

Exit codes: `0` success, `1` captured behavior mismatch, `2` invalid input or I/O
failure. Tools never execute either program; supplied captures may be wrong or
fabricated, so preserve the actual observation method in the reconstruction record.
