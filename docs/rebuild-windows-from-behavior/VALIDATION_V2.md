# Validation record — 2.0.0

Date: 2026-11-06. All target artifacts in automated checks are independently authored synthetic fixtures; no third-party program source, tests, binaries or assets are included.

## Executed locally

- Python 3.12.14 on the execution host: Linux.
- Personal skill frontmatter/name validation: passed against the installed skill directory.
- Toolkit acceptance suite: 32 discovered, 31 passed, 1 skipped because Windows PowerShell is unavailable on this host.
- Command: `python -m unittest discover -s tests/rebuild-windows-from-behavior -v`.

The suite exercises non-execution and unchanged reference files during inspection, source-free inventory output, cautious native/managed language hints, PE32/PE32+ and malformed-header bounds, file/read limits, no-overwrite behavior, strict contract fields and requirement coverage, independent fixtures, observation IDs, audited allowlist exports, captured-result failures, missing cases, JSON booleans/numbers/order, duplicate keys, non-finite JSON and clear CLI exit codes.

## Cross-platform checks

The workflow `.github/workflows/windows-behavior-rebuild.yml` runs Python 3.10 and 3.12 on Linux, Windows and macOS. Windows jobs also exercise the PowerShell wrapper and installer preview/install/no-overwrite behavior. Check the actual GitHub Actions run for the commit being reviewed; configuration alone does not mean a job passed.

## Limits

The toolkit does not launch programs, provide a GUI recorder, execute Windows binaries on Linux, discover every hidden function, establish exact native source language or prove absence of copying. Supplied observations and result files need an honest capture method. Manual contract review remains necessary, including fixture values and exact public literals. Windows desktop, services, hardware, installer and remote-service reconstruction must be tested per target and cannot be inferred from this suite.
