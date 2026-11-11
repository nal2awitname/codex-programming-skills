# Changelog

## 2.3.0 — 2026-11-11

### New skill: powershell-code-runner

- Add `Invoke-Code.ps1`, one runner for 53 languages and project types (Python, C, C++, C#, Java, JavaScript, TypeScript, Go, Rust, PHP, Ruby, Kotlin, Swift, Batch, VBScript, Bash and more; Cargo, Go module, .NET and npm folders). It detects the language from the extension or shebang, probes each toolchain before use (skipping broken stubs such as the Microsoft Store python alias), builds in a temporary folder that is always removed, and returns the program's exit code.
- Pass arguments identically in Windows PowerShell 5.1 and PowerShell 7 with an exact MSVC quoting implementation, run batch files through cmd.exe with cmd-safe quoting, keep runner messages and build output on stderr, and add `-Plan`, `-List`, `-InputFile`, `-TimeoutSeconds` (kills the process tree), `-Toolchain`, `-BuildArg`, `-KeepBuild` and `-Pause`.
- Make non-ASCII output and paths work on Thai and other non-English Windows installations: UTF-8 console during runs, UTF-8 settings for Python, Java, javac, MSVC, csc and vbc, static MinGW linking, and an ASCII build root when the temporary folder is non-ASCII.
- Add `Test-PowerShellScript.ps1`, a static checker for syntax, PowerShell 7-only syntax and parameters, BOM-less non-ASCII sources, platform-dependent aliases, `Invoke-Expression`, hard-coded profile paths, machine-wide execution policy changes and unchecked native exit codes.
- Add a script template, cmd.exe launchers for terminals and drag-and-drop, reliability rules and a troubleshooting table.
- Add tests that run every language fixture whose toolchain is installed, plus quoting, option parsing, exit codes, stdin, timeouts, CRLF scripts, project folders, launchers and checker rules under every available PowerShell. Release smoke tests run them against the standalone installed skill.

### Documentation

- Add a Thai guide for the runner and the `skill for creating code` catalog that groups all seven skills by task.

Contract schemas, Python minimum (3.10) and existing toolkit command formats are unchanged.

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
