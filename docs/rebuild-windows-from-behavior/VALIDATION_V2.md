# Validation record — 2.0.0

Date: 2026-11-06. All target artifacts in automated checks are independently authored synthetic fixtures; no third-party program source, tests, binaries or assets are included.

## Executed locally

- Python 3.12.14 on the execution host: Linux.
- Personal skill frontmatter/name validation: passed against the installed skill directory.
- Toolkit acceptance suite: 32 discovered, 31 passed, 1 skipped because Windows PowerShell is unavailable on this host.
- Command: `python -m unittest discover -s tests/rebuild-windows-from-behavior -v`.

The suite exercises non-execution and unchanged reference files during inspection, source-free inventory output, cautious native/managed language hints, PE32/PE32+ and malformed-header bounds, file/read limits, no-overwrite behavior, strict contract fields and requirement coverage, independent fixtures, observation IDs, audited allowlist exports, captured-result failures, missing cases, JSON booleans/numbers/order, duplicate keys, non-finite JSON and clear CLI exit codes.

## Cross-platform checks

The published toolkit passed all six jobs on GitHub Actions: Linux, Windows and macOS, each on Python 3.10 and 3.12. Both Windows jobs also passed the PowerShell wrapper and installer preview/install/no-overwrite checks.

- Tested commit: `723ac4fc02ef319114729dc64e4bad75e05c49ee`.
- Actual completed run: [Windows behavior rebuild toolkit](https://github.com/nal2awitname/codex-programming-skills/actions/runs/42170906803), conclusion `success`.

These results verify the toolkit and installer in the tested runner environments. They do not establish compatibility with every Windows desktop application. Check the actual run for any later commit under review.

## Behavior-only reconstruction exercise

A fresh agent observed a task-supplied synthetic CLI by invoking its public command; it was instructed not to read the reference source. It recorded 39 observations, audited eight requirements and 29 synthetic acceptance cases, then implemented an independent single-pass integer-list summary. No original source was passed to that agent. It used the same context for behavior observation and building, with a shared filesystem and no enforced original-access restriction; this is not an enforced clean room or a proof of originality.

- Candidate acceptance: 29/29; independent mathematical/example tests: 9/9 (10 unittest methods including the acceptance method).
- Actual separately executed reference/candidate comparisons: 29/29 contract cases and 109/109 additional cases, all matched on Linux/Python 3.12.14.
- The additional set contains 80 seeded valid arrays, 20 invalid structures/types, eight CLI/JSON cases and one 10,000-integer array.
- Only the clean new implementation, contract, independent tests and neutral verification summaries are published in [the runnable example](../../examples/rebuild-windows-from-behavior/README.md). Original-facing capture drivers, reference code and private analyst records are excluded.
- The workflow now also runs the candidate example tests across all six matrix jobs and a `.cmd` launcher smoke check in the two Windows jobs. These are candidate-side checks; the reference differential run above was Linux-only. See the actual Actions status for the commit being reviewed.

## Limits

The toolkit does not launch programs, provide a GUI recorder, execute Windows binaries on Linux, discover every hidden function, establish exact native source language or prove absence of copying. Supplied observations and result files need an honest capture method. Manual contract review remains necessary, including fixture values and exact public literals. Windows desktop, services, hardware, installer and remote-service reconstruction must be tested per target and cannot be inferred from this suite.
