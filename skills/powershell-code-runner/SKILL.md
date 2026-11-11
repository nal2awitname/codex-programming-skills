---
name: powershell-code-runner
description: "Write, check, explain and run PowerShell terminal scripts that work unchanged on any Windows computer (Windows PowerShell 5.1 and PowerShell 7, also macOS/Linux), and build and run source code in 50+ languages from PowerShell with the bundled Invoke-Code.ps1 runner. Use when the user wants a PowerShell command or .ps1 script, wants a program in any language compiled or run from the terminal, or has a script that fails on another PC. Route new application features to app-builder and defects in non-PowerShell code to debug-and-fix."
---

# PowerShell scripts and a runner for any language

Produce PowerShell commands and scripts that run the first time on the user's computer, and run code in any supported language through one verified runner. Respond in the user's language; write code, comments, identifiers, commands and configuration in English. A result is done only when it has been checked and executed, or when the exact reason it could not be executed is stated.

## Route and scope

- Running or testing code in a language (Python, C, C++, C#, Java, Go, Rust, JavaScript, TypeScript, PowerShell, Batch, Bash and more): use `scripts/Invoke-Code.ps1`. Do not hand-write per-language build commands when the runner covers the language.
- Writing or fixing a PowerShell script or one-liner: follow the script workflow below and [the reliability rules](references/powershell-rules.md).
- Explaining an existing script: run the checker first, then explain it block by block, including what it changes on the computer.
- Route new application features to `app-builder`, reviews without repairs to `code-review`, and defects outside PowerShell to `debug-and-fix`. Windows system changes (registry, services, features) still follow this skill's script rules.

## Bundled files

| File | Purpose |
| --- | --- |
| `scripts/Invoke-Code.ps1` | Detects the language, finds a working toolchain, builds in a temporary folder, runs, returns the program's exit code. [Runner guide](references/runner.md). |
| `scripts/run-code.cmd` | Same runner from cmd.exe or Explorer, even where script execution is disabled. |
| `scripts/run-code-wait.cmd` | Same, but keeps the window open; for drag-and-drop and double-click. |
| `scripts/Test-PowerShellScript.ps1` | Static checker: syntax, 5.1 compatibility, encoding, risky aliases, unchecked exit codes. Never executes the script. |
| `assets/Script-Template.ps1` | Starting point for new scripts: help block, validated parameters, strict mode, native-call helper, exit codes. |

Load [the troubleshooting table](references/troubleshooting.md) when a command fails on the user's computer.

## Workflow: run code in any language

1. **Read the plan.** Run `Invoke-Code.ps1 -Plan <file>` first. It prints the detected language and why, the toolchain and version, the working folder and every exact build/run command, without running anything.
2. **Fix readiness.** Exit code 69 means no working toolchain; the message includes an install command for the current OS. Ask before installing software. `Invoke-Code.ps1 -List` shows every language and whether it is ready.
3. **Run.** `Invoke-Code.ps1 [runner options] <file-or-folder> [program arguments...]`. Runner options go before the file; everything after the file reaches the program unchanged. Use `-InputFile` for standard input, `-TimeoutSeconds` for programs that might hang, `-Toolchain` to choose a compiler, `-BuildArg` for compiler flags.
4. **Interpret the result.** The program's own exit code is returned. Runner codes: 64 usage, 65 build failed, 66 file not found, 69 toolchain missing, 70 internal error, 124 timeout. Runner messages go to standard error, so standard output holds only the program's output.

## Workflow: write a PowerShell script

1. **Fix the target.** Default to Windows PowerShell 5.1 and PowerShell 7 on Windows 10/11, a normal user without admin rights, a path that may contain spaces or Thai characters. Ask only when the requested action itself requires a different target (for example admin-only changes).
2. **Start from the template.** Copy `assets/Script-Template.ps1`; keep the help block, `[CmdletBinding()]`, typed and validated parameters, `Set-StrictMode -Version 3.0`, `$ErrorActionPreference = 'Stop'`, `try`/`catch` with explicit exit codes, and `SupportsShouldProcess` for anything that changes files or settings.
3. **Write for both engines and for readers.** Apply [the reliability rules](references/powershell-rules.md): no PowerShell 7-only syntax, full cmdlet names, `-LiteralPath`, `$LASTEXITCODE` after every external program, explicit file encodings, ASCII source or UTF-8 with BOM. Comment why, not what.
4. **Check statically.** Run `Test-PowerShellScript.ps1 -FailOnWarning <script>` and fix every error and warning. Info findings need a reason when they remain.
5. **Execute.** Run the script with realistic input, a failure case and `-WhatIf` when it changes things. Run it in both `powershell.exe` and `pwsh` when both exist. Use paths with spaces in tests.
6. **Deliver.** Give the exact command to run it, for example `powershell -NoProfile -ExecutionPolicy Bypass -File .\name.ps1 -InputPath .\data.txt`, what it changes, and how to undo it.

## Constraints

- Never claim that a script or program works without running it. When the current machine cannot run it (for example a Windows-only script on Linux), say so, still run the checker, and state what remains unverified.
- Do not change the machine-wide execution policy, disable security features, or install software without the user's consent. Prefer `-ExecutionPolicy Bypass` for one process and `Unblock-File` for downloaded scripts.
- Do not run text as code with `Invoke-Expression`; call commands with `&` and an argument array. Do not put passwords or tokens in scripts; read them from parameters, `Get-Credential` or the environment.
- Destructive operations need `-WhatIf` support and a confirmation path. Never delete or overwrite without first resolving and showing the full path.

## Recovery and completion

- Read the full error and the runner's exit code before retrying; change one thing at a time. Use [the troubleshooting table](references/troubleshooting.md) for common causes such as execution policy, missing toolchains, code pages and quoting.
- Stop when the checker is clean and the requested behavior has been executed successfully, or when a named external blocker remains (missing toolchain the user declined to install, admin rights, a different OS).

## Delivery

Lead with the result. Give copy-paste commands, the checker summary, the commands actually executed with their exit codes, and any remaining limitation. Keep explanations of the script in the user's language and refer to commands and parameters by their exact English names.
