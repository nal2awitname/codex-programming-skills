---
name: windows-simulator
description: "Prepare a reproducible Windows test environment for programs, PowerShell or batch scripts, and OS-specific behavior. Use for Windows host, VM, CI, or compatibility-layer setup. Route application implementation to app-builder and defect repair to debug-and-fix."
---

# Prepare and test Windows environments

Choose an available host that can verify the requested behavior, configure it reproducibly, and report actual results. This skill does not supply Windows licensing, images, virtualization, runners, or access to the user's machine. Respond in the user's language; write code, comments, commands, identifiers, and configuration in English.

## Route and scope

- Identify the target artifact, required Windows version/architecture, GUI needs, OS APIs, and whether an automated or interactive test is needed.
- Inspect the actual host, available runtimes, virtualization support, and CI access before selecting a method. Do not assume Docker, KVM, Wine, PowerShell, or a Windows runner exists.
- Follow an already chosen method. Otherwise select the available method with the least setup that establishes the required evidence; offer alternatives only when the tradeoff changes the outcome.
- A browser imitation of a desktop is a UI simulation, not Windows guest execution. Clarify that distinction when the request could mean either.

## Select a method

| Method | Appropriate use | Evidence limits |
| --- | --- | --- |
| Windows host or CI runner | Actual Windows scripts, APIs, and automated tests | Requires access and relevant runtime; CI is not a live interactive desktop |
| Full VM, including a VM managed by Docker | Windows guest execution and GUI workflows | Requires a usable image and license; KVM accelerates QEMU, while software emulation may be much slower |
| Wine | Preliminary checks for a compatible application | An API compatibility layer; results do not establish Windows compatibility |
| PowerShell on Linux/macOS | Platform-independent script logic | A script runtime, not Windows; excludes Windows PowerShell 5.1, COM, registry, and Windows services |

## Workflow

1. **Inspect.** Record available OS/runtime versions and the specific behavior to prove. Validate required resources, ports, volumes, image provenance, and permissions for the selected method.
2. **Plan.** State a short setup/test/cleanup plan for nontrivial work, with one observable acceptance check. Reuse an existing working environment instead of rebuilding it unnecessarily.
3. **Configure.** Store repeatable workflows, scripts, or VM configuration in the project. Keep credentials and license keys outside version control. For Windows PowerShell support, test the relevant `powershell` and `pwsh` runtimes; preserve test artifacts and use `fail-fast: false` when a matrix is needed.
4. **Verify.** Execute the intended program or tests in that environment. Check successful and failing inputs, record actual versions and results, and verify important GUI or OS interactions rather than relying on a build alone.

## Recovery and completion

- Diagnose missing dependencies or host support before retrying. Never claim a VM started, Windows ran, or a UI interaction passed without actual evidence.
- For Pester, use the project version and install only when needed. Use `-SkipPublisherCheck` only for a diagnosed publisher conflict after checking the package source.
- If the required host is unavailable, prepare usable configuration and exact run commands, continue supported checks, and mark Windows execution unverified.
- Clean up owned temporary processes/resources when applicable; record anything still running. Stop once the requested environment and behavior checks are complete or a concrete host/access blocker remains.
- Continue already authorized setup without extra approval; external services, downloads, and CI changes must remain within the user's authorized scope.

## Delivery

Link configuration files and give prerequisites, setup/run/cleanup commands, tested versions, actual results, and outstanding checks. Separate actual Windows results from Wine or cross-platform PowerShell results and from configuration that has not been executed.
