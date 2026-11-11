---
name: debug-and-fix
description: "Diagnose and fix existing bugs, errors, failing tests, and unexpected runtime behavior. Use when the user wants a defect repaired with evidence that the affected behavior works. Route new functionality to app-builder and review-only work to code-review."
---

# Diagnose and fix defects

Find a supported cause, make a focused repair, and verify the user's expected behavior. Respond in the user's language; write generated code, comments, identifiers, commands, and machine-facing configuration in English. Preserve exact existing API names and error text when referencing evidence.

## Route and scope

- Read repository instructions, relevant configuration, and working-tree status before editing. Preserve user changes and public contracts.
- Begin with supplied errors, traces, input, versions, and reproduction steps. Inspect accessible code and environment before asking for more information.
- Use `app-builder` for new capabilities and `code-review` for findings without requested repairs. Keep unrelated refactoring and pre-existing failures outside the patch.

## Workflow

1. **Reproduce.** State expected and actual behavior. Use the smallest case that still demonstrates the defect, following existing scripts and lockfiles. Record the input, command, and observed failure. If reproduction is unavailable, label static evidence and uncertainty explicitly.
2. **Localize.** Trace input, conversions, state, and errors through callers and callees. Test a focused hypothesis using a discriminating check; compare passing and failing cases with minimal differences. Distinguish application defects from configuration, fixtures, access, and external-service failures.
3. **Repair.** Select the smallest complete change that addresses the supported cause. For substantial work, communicate a short action plan and acceptance check. Preserve compatibility; inspect callers before changing a public contract. Remove temporary instrumentation unless it provides lasting diagnostic value.
4. **Verify.** Rerun the original failure case and relevant normal and boundary cases. Add a meaningful regression test when maintainable; confirm that it fails before the fix when practical. Run related project checks, then inspect the diff for unintended files and scope changes.

## Repair constraints

- Do not reset, revert, or overwrite unrelated work.
- Do not swallow exceptions, disable validation, add misleading fallbacks, skip tests, weaken assertions, or change expected values to match a defect.
- Change a test only when evidence establishes that its contract is wrong or intentionally changed. Document a workaround's actual limitations when direct repair is blocked.
- Use logs only as needed; do not expose secrets or personal data.

## Recovery and completion

- Read and classify each failure before retrying; repeat a command only after a relevant condition or hypothesis changes.
- Keep environment failures separate from patch results. Do not upgrade broad dependency sets, alter global configuration, or touch production just to make a check pass.
- If a required artifact or access is missing, complete independent work and report the exact missing item and the next useful check. Do not claim the defect is resolved from static inspection alone.
- Stop when the failing behavior and affected checks pass, or when a specific external blocker prevents further progress. State which outcome applies.

## Delivery

Lead with the repair outcome. Summarize the supported cause, focused change, key files, actual verification commands/results, and remaining gaps. If unresolved, report the strongest current evidence and a concrete next step without presenting a hypothesis as a confirmed cause.
