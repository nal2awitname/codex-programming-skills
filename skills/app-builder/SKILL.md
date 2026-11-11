---
name: app-builder
description: "Build or extend runnable applications, including CLI tools, APIs, desktop apps, and existing projects. Use for implementation of new capabilities. Route existing defects to debug-and-fix and review-only requests to code-review."
---

# Build applications

Turn the requested behavior into a working, verifiable application. This skill supplies a workflow, not a runtime, service, connector, or account access. Respond in the user's language; write generated code, comments, identifiers, commands, and machine-facing configuration in English.

## Route and scope

- Preserve the requested application type and the project's existing language, framework, package manager, and conventions unless a requirement justifies changing them.
- Use `debug-and-fix` for existing defects, `code-review` for findings without implementation, and `windows-simulator` for preparing a Windows test host. Use a reconstruction skill only for an explicitly requested independent rebuild.
- Read repository instructions and the working-tree status. Preserve unrelated files and user edits.
- Infer reversible details from available context. Ask only for missing information that materially changes behavior, compatibility, or data handling; continue independent work while waiting.

## Workflow

1. **Inspect.** Identify users, inputs, outputs, existing entrypoints, public contracts, dependencies, and available runtimes. Check current official documentation when a required API or version is uncertain.
2. **Plan.** Define observable acceptance criteria for the main path and relevant empty, invalid, or failure states. For nontrivial work, give a short action plan tied to those criteria; omit planning ceremony for a small change.
3. **Implement.** Complete one path from real input through processing to usable output, then cover the remaining criteria. Keep changes cohesive. Add storage, accounts, services, or frameworks only when requirements need them.
4. **Verify.** Run the project's applicable build/check commands and exercise the changed behavior. Use meaningful acceptance or regression tests when they protect important behavior. Fix failures within scope and rerun affected checks.

## Behavior requirements

- CLI: validate arguments, relevant stdin/stdout, errors, and exit status. API: verify request/response contracts, validation, and dependency failure behavior.
- UI: exercise the principal interaction and applicable loading, empty, error, save, and shutdown states. A successful build alone does not verify interaction.
- Persistence: save, reopen, and verify data after restart when durability is required. Choose storage for the actual lifetime and sharing needs.
- Integration: verify a real response with available tools. Mark mocks and sample data clearly; do not report a button, placeholder, or in-memory value as a working external connection or durable storage.
- Keep secrets outside source control; document required configuration with safe examples.

## Recovery and completion

- Diagnose a failed command before retrying. Separate code defects from unavailable dependencies, credentials, services, or platform support; keep supported work moving and state the exact blocker.
- Do not suppress errors, disable validation, weaken tests, or change unrelated systems to force success.
- Stop expanding scope when the agreed criteria pass and material concerns are resolved. Do not repeat broad checks without a changed input or new concern.
- Continue authorized development and verification without redundant approval. Publish, deploy, or send external messages only within the user's authorized scope and applicable tool rules.

## Delivery

Lead with the usable result. Link important files and give the actual setup/run command, one representative usage example, checks run with results, and any remaining limitation. Distinguish completed functionality, mocked behavior, and unverified platform or integration work.
