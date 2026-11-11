# Changelog

## 2.2.0 — 2026-11-11

### Installable and verified releases

- Build one full source archive and a self-contained archive for each skill, with file-level hashes, a release manifest and SHA256SUMS.
- Add a portable Python installer with selection, dry-run, preflight validation, no-overwrite behavior and rollback of newly created targets.
- Verify archive inventories, checksums, safe portable paths and source/standalone equivalence. Optional smoke verification installs all six skills outside the repository, executes both installed toolkit CLIs and runs tests from extracted source.
- Run a complete real-CLI ARB lifecycle from an isolated installed directory with spaces in its path.

### Clearer AI workflows and English code

- Rewrite all six skill instructions and metadata in English with explicit routing, observable acceptance criteria, bounded planning, execution, verification, recovery and completion conditions.
- Reduce duplicated workflow instructions while preserving artifact evidence, independent reconstruction boundaries and stage-specific references.
- Keep Thai explanations in external prose. Enforce absence of Thai in executable/configuration sources and Markdown fenced code blocks.

### Correctness fixes

- Normalize host-relative evidence paths before matching inventory paths, supporting leading ./ and native Windows separators.
- Accept successful robocopy status codes even when PowerShell native-command error preferences are enabled, without changing the caller's preference.
- Check package manifests against actual source VERSION and skill inventory, and reject invalid archive members and Windows path aliases.

Python minimum remains 3.10. Contract schemas and existing toolkit command formats remain unchanged. See [validation and package usage](docs/RELEASE_2.2.0_TH.md).

## 2.1.0 — 2026-11-11

### Correctness fixes

- ARB rejects duplicate JSON keys, non-finite values and overflowing float values in observed program output instead of accepting ambiguous comparisons.
- Captures truncated while cleaning up descendants are invalid. Verification freshness also tracks reference observations and source changes; command-file hashes are captured before execution so probes that rewrite their command cannot make old results current.
- Windows toolkit preserves JSONL records containing Unicode line separators and safely appends when the previous record has no final newline. Malformed records report their line number.
- ValueScanLab returns a structured `invalid_json` error when a JSON integer exceeds Python's digit limit.
- Windows media script derives the unattended setup architecture and selects the exported image index instead of forcing an amd64 Pro product key. It preserves already mounted ISOs, stops before work on WhatIf/declined confirmation, rejects overlapping paths and ambiguous/stale image inputs, and uses UTF-8 BOM for Windows PowerShell 5.1 source decoding.

### Usability and maintenance

- ARB PowerShell interpreter discovery handles multiple executables in PATH instead of attempting to invoke an array of paths; media fixtures resolve physical temporary paths on macOS.
- ARB PowerShell wrapper exposes evidence/attach commands and inventory/output limits; repeated handoff whitespace normalization is computed once.
- Skill instructions load references by task and avoid creating full reconstruction records for focused analysis. Windows simulation guidance distinguishes PowerShell runtime, virtualization and emulation.
- Adds cause comments beside non-obvious fixes and a Thai contributor guide for targeted regression tests and release checks.
- Adds repository-wide validation/test runner, reproducible source ZIP packaging and SHA-256 checksums. All six skills are listed in the Thai installation guide.
- Unifies CI across Ubuntu, Windows and macOS / Python 3.10 and 3.12; adds missing ARB and media regression suites while retaining Windows launcher/installer and GUI checks.

### Compatibility

Python minimum remains 3.10. ARB contract schema remains 2; Windows toolkit contract schema remains 1. These formats are separate. Existing verified ARB workspaces should rerun `verify` to record the reference-observation hash. Toolkit commands keep their existing argument conventions.

See [validation and limitations](docs/RELEASE_2.1.0_TH.md). Older validation documents describe their original releases and have not been rewritten as new results.
