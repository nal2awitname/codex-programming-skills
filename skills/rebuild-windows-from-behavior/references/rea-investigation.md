# Apply REA investigation discipline without transferring original code

## Contents

- [Source and capabilities](#establish-the-source-and-available-capabilities)
- [Question-led investigation](#investigate-a-question-against-the-selected-artifact)
- [Artifact and host routing](#route-by-facts-then-check-host-support)
- [Independent implementation boundary](#preserve-the-independent-implementation-boundary)
- [Upstream references](#pinned-upstream-references)

## Establish the source and available capabilities

Use the user's [REA fork](https://github.com/nal2awitname/rea) as methodological
guidance. This adaptation was checked against commit
`d3ab0faf52a02ff5a618f3ed7beb608b78752abd` (source manifest 6.8.0).
Read current relevant documentation and the connected tool's actual schema before
using a capability; repository main and an installed release can differ.

Discover actual REA MCP tools, or check an existing CLI when local execution is
needed. GitHub access and an installed skill do not establish MCP registration,
an available native analysis engine, or access to the user's Windows machine.
Do not repeat setup/readiness for an already working connection. If tools are
missing, state the observed blocker and continue supported work. Do not silently
install toolchains, repair client settings, launch targets or change the task just
to make a planned operation appear available.

## Investigate a question against the selected artifact

1. Name the original application/build and supplied artifact. Record its actual
   path, byte identity and digest scope when available; leave missing fields null.
   A directory snapshot or metadata-file hash is not a full executable hash.
2. List concrete questions, the evidence each requires and its stopping condition.
   For a scan feature, distinguish value representation, initial selection,
   subsequent filtering, state updates, errors and observable side effects.
3. Reuse evidence only when target/build, provider/profile and capture conditions
   still match. Never select a nearby fixture or a reconstructed example as the
   original merely because its workflow is similar.
4. Start with the smallest sufficient inventory; deepen only for a specific gap.
   Use retained parent evidence, selected functions/fields and pages when the
   actual server supports them. Preserve complete records outside model context.
   Do not repeat a producer merely because its displayed preview was truncated.
5. Keep a finding ledger: question, status (`answered`, `partial`, `unresolved`),
   evidence kind, exact source identity/location, examined coverage, limitations,
   contradiction and the next discriminating check. An empty bounded search or
   exhausted page does not prove a feature is absent.
6. For execution, declare the target, synthetic input, actions, expected observable
   result, failure signal and stopping condition. Use only available suitable
   hosts/adapters within authorized scope. Record effects, termination and cleanup;
   a timeout or cancelled request does not establish that execution stopped.
7. Revisit every question before reporting. Keep missing original-runtime evidence
   unresolved even when metadata, public specifications or candidate tests pass.

## Route by facts, then check host support

The following names identify documented REA operations, not tools this skill
registers. Invoke one only when its actual interface and availability are known.

| Supplied material or question | Candidate route | Meaning and limits |
| --- | --- | --- |
| Installed directory, runtime unknown | `inspect_desktop_application` | Bounded entries/headers/metadata and next probes; no application execution |
| Native EXE/DLL with a focused code question | `open_binary`, focused native tools; optional `binary_overview` | Select an available provider and preserve source/profile identity; pseudocode is analysis material |
| PE imports/resources/exports | `inspect_pe_imports`, `inspect_pe_resources`, `inspect_native_exports` | Portable static facts; neither loading nor calls at runtime are established |
| Managed CLI assembly | `inspect_managed_artifact` | Managed declarations/relationships; a CLR header alone cannot determine the exact source language |
| Electron/ASAR or JavaScript artifact | `analyze_javascript_application` | Static application evidence; code execution remains unobserved |
| Observed native calls or native desktop actions | Select the documented runtime adapter for the host | At the pinned revision, LLDB call observation and native UI are macOS-specific; do not advertise them as Windows adapters |
| Process scenario | `capture_process_scenario`, compatible capture comparison | New captures are Linux/macOS in the pinned guide; comparison on Windows does not mean Windows capture exists |
| Caller-authored Frida instrumentation | Advertised Frida session operations | Requires real compatible bindings/device access; Linux verification is not Windows qualification and instrumentation can alter the target |

Treat Windows Ghidra support as a static-analysis capability with its documented
limitations. Do not infer Windows runtime/UI automation or database mutation
authority from its presence. For original Windows behavior without a supported
REA runtime adapter, use an independently available Windows observation workflow
or keep that question blocked. Name the actual producer instead of labelling
non-REA observations as REA captures.

`trace_native_values` concerns recovered static dependencies. Ghidra `read_bytes`
reads initialized analysis memory, not a live process. Keep file offsets, analysis
virtual addresses and runtime addresses distinct; unread bytes remain unknown.

## Preserve the independent implementation boundary

Keep raw tool output, recovered code, native addresses, private symbols and source
structure in the analyst area. Summarize responsibilities, state, inputs/outputs
and evidence in prose. Source recovery or artifact reconstruction features in REA
do not authorize using recovered implementation in this user's new program.

Audit an implementation-neutral behavior contract and synthetic fixtures, then
give a fresh builder only that export, this skill and a new output directory.
Keep evidence links in the analyst ledger; use neutral IDs in builder inputs.
Do not weaken the existing no-copy rules or describe a shared filesystem as an
enforced clean room. Record exact public compatibility facts only when necessary.

Separate four results: documented behavior, static original-artifact facts,
observed original execution, and tests of the new implementation. Claim a finite
behavioral comparison only for compatible actual reference/candidate captures.
REA `verify_reconstruction` also concerns declared comparable claims; it cannot
prove full equivalence or originality. No tool or review flag replaces provenance
review and the actual reference observations needed by a claim.

Close owned sessions with their matching lifecycle operations and checkpoint
evidence when it must survive the connection. Keep failed cleanup explicit.

## Pinned upstream references

REA is an MIT-licensed project by morluto, forked by the user. These links identify
the guidance used; no REA implementation is bundled with this skill.

- [Core workflow](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/.agents/skills/reverse-engineer-anything/SKILL.md)
- [Evidence and finite comparisons](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/.agents/skills/reverse-engineer-anything/references/evidence-workflows.md)
- [Runtime host/effect boundaries](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/.agents/skills/reverse-engineer-anything/references/runtime-observation.md)
- [Desktop directory triage](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/docs/desktop-applications.md)
- [Connection recovery](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/.agents/skills/reverse-engineer-anything/references/connection-and-recovery.md)
- [License](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/LICENSE)
