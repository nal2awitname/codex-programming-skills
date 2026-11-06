# Windows observation and independent reconstruction

## Contents

- Evidence and coverage
- Route by artifact
- Observe behavior on Windows
- Select a new implementation
- Limits and verification
- Primary references

## Evidence and coverage

Accept any Windows program as a triage request. Classify unsupported or unavailable
surfaces explicitly; never promise automatic reconstruction of every program.
An EXE cannot generally reveal its exact original language or all its functions.
Treat a framework/runtime as evidence about one component, not the whole product.

Inventory the accessible surfaces before implementation:

| Surface | Required record |
| --- | --- |
| Menus, dialogs, shortcuts, commands | Action, preconditions, input, visible output, errors |
| Files and persistent settings | Synthetic fixture, save/open round trip, restart behavior |
| Background tasks and state | Start, cancellation, ordering, retries, failure recovery |
| Services, hardware, plugins and network | Observable interface, environment, access gaps |
| Undiscovered or inaccessible behavior | Explicit unknown; never label fully covered |

Maintain a feature matrix with `observed`, `source-confirmed`, `inferred`, `unknown`
evidence and `implemented`, `tested`, `blocked`, `excluded` delivery status. Keep
the denominator as enumerated surfaces; do not invent a percentage of all functions.
Use distinct observation IDs for normal, boundary, invalid, failure and stateful
probes where relevant. Do not convert a guess into a measured reference output.

## Route by artifact

| Family or package | Inspect first | What remains uncertain |
| --- | --- | --- |
| Native EXE/DLL/SYS, x86/x64/ARM64 | PE signature, machine, subsystem, dependencies; runtime behavior in a suitable Windows host | Exact C/C++/Rust/Go/Delphi language, private algorithms and hidden paths |
| Managed .NET | CLR metadata, runtime/project configuration and UI behavior | A CLR directory alone cannot distinguish C#, VB.NET, F# or mixed mode |
| Electron or embedded web UI | Package/host evidence, UI events, IPC/public messages | `app.asar` filename alone proves neither Electron nor source language |
| Python/Java/PowerShell and scripts | Runtime, manifests and syntax indicators; shipped wrappers separately | Runtime filenames may belong only to a dependency |
| MSI/MSIX/APPX | Container and declared package metadata, installed components | Installer format is not the application's language; do not install during triage |
| COM, Office add-ins, services | Host/registration metadata and public interfaces | Host availability, bitness, service identity and permissions |
| Games, CAD, GPU, industrial and hardware apps | File/interaction contracts and repeatable scenarios | Proprietary engines, drivers, real-time timing, hardware and remote services |
| Packed, encrypted or legacy programs | Package identity and observed external behavior | Missing metadata remains unknown; avoid fabricated language identification |

Do not copy recovered/decompiled implementation, resources, graphics, fonts,
original test corpora or private symbol names. Any reverse-engineering tool output
stays analyst-only. Read a relevant artifact workflow when deeper analysis is needed.

## Observe behavior on Windows

1. Record the application identity/version, Windows version, architecture, locale,
   display scaling, dependencies and selected feature scope. Record only values
   actually available. A skill does not grant access to a user's computer.
2. Inspect statically with `scripts/rebuild.py inspect`. Keep the JSON report outside
   the original directory, in the analyst area. Never run or install a target just
   to identify it. The bundled script does not launch any target.
3. For authorized runtime observation, use an available Windows host/VM and supported
   UI tools. Use synthetic files, controlled starting state and a repeatable action
   sequence. Record actual screenshots/log observations privately where supported;
   the toolkit does not provide a GUI recorder or Windows VM.
4. Observe user actions, input/output, error messages, save/reopen, cancellation,
   concurrent operations and failure modes relevant to the feature. Tools such as
   UI Automation, Inspect or Process Monitor may help when available; read current
   official docs before using tool-specific commands. Do not infer hidden server
   code from network traffic or UI appearance.
5. Append a neutral observation record using `observe`. This stores a supplied
   observation; it is not proof that the tool measured it. Preserve original
   observations when later evidence changes the contract.
6. Convert observations into behavior requirements and new synthetic acceptance
   cases. Express concepts as invariants, visible state and contracts. Describe the
   original internal design only in private prose, never source-shaped pseudocode.
7. Audit and export the contract. Start a fresh builder with only the exported
   files, this skill and the requested output directory. If real access controls
   are absent, state context/data separation rather than an enforced clean room.

## Select a new implementation

Choose from requirements and the user's development constraints. Examples include
.NET for Windows desktop integration, Python for suitable tools, or native code
for a measured hardware/performance need. These are options, not requirements to
reuse the target's stack. Explain why the selected stack meets the public contract.
Use original UI artwork and independently designed components. Register the
provenance/licenses of new dependencies separately from the target's dependencies.

## Limits and verification

Build and test the new implementation on the claimed Windows architecture.
Verify real dialogs, file paths, persistence, encoding, locale, cancellation and
external interfaces where in scope. Cross-platform unit tests alone do not prove
Windows desktop behavior. Keep unavailable cloud, hardware, signing and installer
checks marked unverified. Source-free workflow records are evidence of process,
not a legal certification or proof that no copying occurred.

## Primary references

- PE/COFF headers, machine values, directory bounds: https://learn.microsoft.com/windows/win32/debug/pe-format
- Electron package layout: https://www.electronjs.org/docs/latest/tutorial/application-distribution
- ASAR semantics: https://www.electronjs.org/docs/latest/tutorial/asar-archives
- Windows UI Automation overview: https://learn.microsoft.com/windows/win32/winauto/entry-uiauto-win32

Consult current primary documentation for additional tools or APIs; never treat an
example tool listed here as installed or already exercised.
