# Independent implementation contract

Use the following outline selectively. Replace prompts with concrete requirements; omit irrelevant sections. Write plain language, tables, mathematical properties, and independently created examples. Do not include original code or implementation-shaped pseudocode.

## Purpose and scope

- User-visible job:
- Features included:
- Features excluded:
- Target platform, language constraints, and deliverable:
- Known environmental requirements:

## Public interfaces

| Interface | Inputs and types | Outputs | Errors | Compatibility literals and why |
| --- | --- | --- | --- | --- |

Describe commands, exported APIs, UI actions, network messages, file formats, and their externally required behavior. Retain exact public names/literals only where needed. Do not include private helper names, original file paths, or implementation dependencies discovered in source unless they are an externally imposed requirement.

## Behavioral requirements

| ID | Trigger/precondition | Required result | State/side effects | Evidence status/observation ID |
| --- | --- | --- | --- | --- |

State ordering, validation, errors, retry/idempotency, and cancellation rules where applicable. Use neutral observation IDs; keep source citations in the separate analyst record.

## State and invariants

- Externally meaningful state and legal transitions:
- Persistence and restart behavior:
- Ordering and concurrency properties:
- Invariants that all successful operations preserve:

Describe observable state rather than original classes, private caches, call graphs, or storage layout. Permit the builder to choose its own data model.

## Examples and independent test scenarios

| Case ID | Requirement IDs | Synthetic input and initial state | Expected output/state or property | Evidence status |
| --- | --- | --- | --- | --- |

Include valid, boundary, invalid, and failure cases. Generate fresh synthetic data rather than transferring an original fixture corpus. Exact interface output examples are allowed when necessary to specify behavior; executable implementation fragments are not.

## Quality constraints

- Required scale and measurable latency/throughput/resource limits, if specified:
- Numerical tolerance and formatting rules:
- Platform and interoperability constraints:
- Deterministic clock/seed/locale assumptions:

Do not invent thresholds. Separate measured properties, user requirements, and proposed targets.

## Unknowns and decisions

| Issue | Evidence available | Assumption or alternative | Consequence | Resolution needed |
| --- | --- | --- | --- | --- |

Keep unsupported behavior unverified. Ask only for decisions that materially change the result; implement supported independent work while awaiting any essential answer.

## Acceptance criteria

- Runnable build and agreed interfaces.
- Requirement-to-test mapping and recorded results.
- Observable compatibility for exercised cases, with explicit gaps.
- Independent implementation provenance and actual isolation record.

## Handoff audit

Before sharing with a builder, verify all of the following:

- No copied code, translated code, decompiler snippets, copied tests, or original assets.
- No private identifiers, source paths, internal module layout, call graph, source-derived constants, or implementation-shaped pseudocode.
- Only necessary public compatibility facts; each retained exact literal has a recorded reason.
- No original artifact location, source-facing report, credentials, hidden instructions, or inherited source context in the handoff.
- Enough examples and invariants to build and test without consulting the original.
- Actual context/filesystem isolation documented honestly; shared filesystem access is not an enforced clean room.
