# Maintainable components and GitHub delivery

## Organize the new project

Use the project's normal layout rather than forcing a framework or splitting every function into a file. Separate components where responsibilities or dependencies differ. Provide this map using the real paths:

| Responsibility | Typical location | Required handoff detail |
| --- | --- | --- |
| Entrypoint and adapters | CLI, API, UI, platform-specific entrypoints | Public inputs, outputs, validation, error behavior |
| Domain behavior | Domain modules or equivalent | Requirement IDs, invariants, independently selected algorithms |
| External I/O | Storage, networking, hardware adapters | Side effects, configuration, unavailable integrations |
| Tests | Project test directory | Independent acceptance/regression cases and actual run command |
| Behavior contract | `docs/behavior-contract.md` or project equivalent | Observable requirements, edge cases, evidence status |
| Component map | `docs/components.md` or project equivalent | Responsibilities, dependencies, interfaces, change locations |
| Development guide | `README.md` and project development notes | Prerequisites, dependencies, configure/build/run/test, next useful changes |
| Reconstruction record | `docs/reconstruction-record.md` or equivalent | Builder inputs, actual isolation, provenance, verification, gaps |

Keep deployment credentials out of example configuration. State required environment-variable names and safe example values when needed. Keep build outputs and local working data out of version control unless the project explicitly requires them. Preserve existing naming, package management, formatting, and test conventions.

## Prepare the complete handoff

1. Map public behavior requirements to new components and independently written tests. Document how to add a feature without consulting the original implementation.
2. Provide exact commands from project configuration. Run applicable checks and state any environmental blocker. Do not invent a completed integration test or claim that placeholders are implemented features.
3. Include only the new implementation and shareable supporting documentation. Do not upload target source/binaries, original tests/fixtures/assets, captured secrets, private reverse-engineering notes, full local paths, or a copy of the original repository history. Summarize necessary observations with neutral IDs and public interface facts.
4. Keep analyst and builder areas separate until construction is complete. An eventual public development report does not permit giving source-facing material to the builder during implementation.
5. If the user requests the skill itself in GitHub, export its complete validated directory under an appropriate `skills/<name>/` path. Keep repository-facing guides and starter project templates outside the installable skill directory. Preserve the installed personal-skill identity when updating it; exporting is not a second installation.

## Publish through the connected GitHub tools

1. Discover the available tools. Use the GitHub connection when it supports the required repository reads and writes. Do not substitute browser automation or raw credential handling for sufficient connected tools.
2. Resolve the destination from the explicit repository, current project remote, or a clearly suitable existing user-owned repository. Inspect repository visibility, write access, relevant `AGENTS.md` instructions, paths, current head commit, and its tree. If several destinations are equally plausible, prepare the files and ask which destination to use. Do not invent an owner or repository name.
3. Add only intended paths and preserve the base tree. Read any existing file before editing it. Prefer an atomic multi-file commit. Check for concurrent head changes before advancing the branch, and inspect/reapply against the new head if a lease fails. Never force-push to bypass a conflict.
4. Follow explicit branch preferences and repository rules. If a protected branch blocks the authorized update, use a new branch and pull request when supported. Do not merge a PR unless the user's scope authorizes it. Do not automatically assign or notify reviewers.
5. If the tools cannot create a required repository or lack write access, preserve the completed handoff and explain the specific missing destination or access. Do not report a GitHub upload as complete merely because local files exist.
6. Read back the resulting remote commit/tree and the intended file contents or blob identities. Confirm unrelated content was preserved, then return clickable repository/component links and the actual branch/PR status.

## Future development

Record the next change in terms of a requirement, the component to modify, and the check that demonstrates the result. Add a new behavior requirement and acceptance case before changing observable behavior. Update the component map when boundaries change. A repository copy of a skill and an installed personal skill do not automatically update each other; explicitly update the requested copy when the user asks for changes.
