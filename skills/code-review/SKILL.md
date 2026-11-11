---
name: code-review
description: "Review code, files, diffs, or pull requests for evidence-backed bugs and regressions. Use for actionable findings with triggers, impact, and exact locations. Route requested fixes to debug-and-fix and feature implementation to app-builder."
---

# Review code using evidence

Report defects that a maintainer can evaluate and repair. Respond in the user's language; use English for any generated code or machine-facing configuration. Preserve exact existing symbols and paths when citing evidence. Default to findings in chat; modify code or post reviews only when authorized.

## Route and scope

- Identify the requested files, project, diff, or PR. Read applicable repository instructions and only the surrounding callers, validators, schemas, migrations, and configuration needed to assess behavior.
- For a diff, record the actual base and head. Use the PR's merge-base semantics rather than guessing from branch tips. Separate introduced defects from pre-existing problems.
- For partial input, review what is available and state missing context. Do not imply that the whole repository was reviewed.
- Use `debug-and-fix` when repair is requested and `app-builder` for new behavior.

## Workflow

1. **Inspect.** Establish intended behavior and public contracts from requirements and relevant code.
2. **Plan.** For a broad review, choose the behavior paths with the largest plausible impact and state a short review scope. A small diff needs no separate plan artifact.
3. **Trace.** Follow changed data and state through reachable callers. Check applicable empty/zero/false values, type conversions, bounds, cleanup, partial writes, async ordering, cancellation, retries, compatibility, authorization, and secret handling.
4. **Validate.** Use a minimal input, meaningful test, or concise static trace. Check whether a caller or validator already prevents the suspected condition. Run related checks when they add evidence; distinguish observed failures from static findings.

## Finding requirements

Report a finding only when all four are supported:

1. A concrete, reachable trigger or input.
2. Actual behavior that violates the intended contract.
3. A specific user or system impact.
4. An exact current file/line and supporting evidence or reproduction.

Use impact for priority: `P0` widespread critical breakage requiring immediate action; `P1` major reachable functionality or data failure; `P2` a concrete defect for normal correction; `P3` a low-impact behavioral error. Merge findings with the same cause. Keep requested style or architecture advice separate from defects; do not fill a quota.

## Recovery and completion

- If a check cannot run, preserve useful static findings and report the exact environment limitation. Do not invent results or repeatedly rerun unchanged failures.
- Recheck locations against the reviewed head. For PR findings, prefer the smallest relevant changed line range.
- Stop when the scoped paths have been assessed and material suspicions are confirmed, rejected, or explicitly blocked. Unread or inaccessible areas remain outside the conclusion.

## Delivery

List findings by priority with a short title, `path:line`, trigger, impact, and evidence; suggest a repair only when it clarifies the defect. End with the reviewed scope, actual test results, and material limits. If no supported defects were found, say so directly without guaranteeing that the code is bug-free.
