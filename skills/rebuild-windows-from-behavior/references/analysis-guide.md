# Evidence-driven program analysis

## Source projects

- Inventory with `rg --files` and search focused symbols/configuration with `rg -n`. Exclude dependencies, generated output, caches, and large artifacts from an initial inventory; inspect them later only when needed.
- Inspect manifests, lockfiles, toolchain settings, build targets, application entry points, routes/events, domain rules, persistence, and tests. Treat test content as analysis evidence; independently author new tests from behavior rather than copying test code or fixtures.
- Distinguish declared dependencies from actual runtime imports/calls, and development tooling from shipped components. Cite only locations actually inspected.
- Derive a minimal build/run command from project configuration. Record unavailable dependencies or services; do not invent a successful execution.

## Language and runtime clues

| Family | Confirm with | Explain in program context |
| --- | --- | --- |
| JavaScript/TypeScript | Syntax, package metadata, compiler settings, import graph | Browser versus server, build-time types versus runtime values, event loop, promises, bundling |
| Python | Syntax, project metadata, imports, entry-point declarations | Interpreter, environment, exceptions, generators/async, native extensions |
| Pascal/Object Pascal | Source syntax, Lazarus `.lpi` metadata, declared FPC/Delphi compiler modes | Units, classes, events, native compilation; a project dialect does not identify every component |
| C/C++/Rust | Source, build configuration, symbols, binary dependencies | Compilation/linking, ownership and lifetime, ABI/FFI, native resources |
| C#/Java/Kotlin | Project metadata, managed assembly/bytecode metadata, runtime files | Managed runtime, object model, tasks/threads, packaging, platform APIs |
| Go | Module/build files, syntax, executable metadata | Compilation, packages, goroutines/channels, resource lifetime |
| PowerShell/shell | Shebang or syntax, command invocations, pipeline usage | Host, shell semantics, pipelines, subprocesses, filesystem side effects |
| Web UI | HTML/templates, CSS, framework metadata, browser observations | Layout, events, client state, network calls, browser storage |
| PLC/industrial | Project/export format, language syntax, task configuration | Scan cycle, ladder/ST/FBD as evidenced, I/O mapping, timers, retained state |

Do not identify a binary's original language with certainty from one heuristic. Report mixed-language components separately. Distinguish storage formats, query languages, and serialization from the application's implementation language.

## Shipped artifacts without complete source

- Inspect file type/signature, architecture, package structure, imports, symbols, resource metadata, and runtime dependencies with available tools. Use the artifact-specific reverse-engineering workflow when available.
- For Electron/JavaScript bundles, distinguish the desktop host, renderer, IPC boundary, packaged resources, and remote services. Minified/decompiled output remains original-derived code and cannot enter the new implementation or contract.
- For managed binaries/APKs, distinguish metadata, bytecode, platform APIs, UI/resources, and native libraries. For native executables or firmware, distinguish file offsets, virtual addresses, recovered symbols, and uncertain decompilation.
- For websites, distinguish observable client behavior from inaccessible server implementation. A network response supports a behavior claim, not knowledge of hidden source or database design.
- Use controlled probes only within the requested task and accessible environment. Record inputs, outputs, state before/after, errors, timing conditions, and evidence IDs. Prefer synthetic, minimal data.
- Never say decompilation recovers the author's exact source, private intentions, or complete architecture. If a platform/tool/runtime is unavailable, state what static inspection can and cannot establish.

## Analysis report structure

1. **What it does:** program purpose and evidence scope.
2. **Languages and construction:** component languages, frameworks, toolchain, startup/build/run path, evidence versus inference.
3. **Components:** responsibility, inputs, outputs, dependencies, state/side effects, evidence.
4. **Execution trace:** one normal operation and one relevant edge/error, with data/state transformations.
5. **Behavior:** observable rules, public interfaces, edge cases, unknowns.
6. **Independent design options:** requirements and tradeoffs, without source-derived implementation recipes.

Keep this report in the analyst area. Do not pass it to the independent builder.

## Probe discipline

- Choose inputs that discriminate between plausible behavioral models: empty/singleton inputs, limits, missing values, malformed types, duplicates, ordering, restart/persistence, cancellation, concurrency, and service failure as applicable.
- Preserve real observations even when surprising; report a bug as observed behavior. Decide explicitly whether compatibility requires preserving it.
- Avoid inferring general behavior from one happy-path example. An unavailable oracle leaves a coverage gap, not permission to fabricate a reference result.
