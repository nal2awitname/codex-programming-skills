# Rules for PowerShell scripts that run on any computer

Every Windows 10/11 computer has Windows PowerShell 5.1 (`powershell.exe`). PowerShell 7 (`pwsh.exe`) is optional. A script that follows these rules runs unchanged in both, and `Test-PowerShellScript.ps1` checks the rules marked with a rule id.

## 1. Engine compatibility (5.1 and 7)

| Avoid (7 only) | Use instead (5.1 and 7) | Rule |
| --- | --- | --- |
| `$a ? $b : $c` | `if ($a) { $b } else { $c }` | PS101 |
| `$x ?? 'default'`, `$x ??= 1` | `if ($null -eq $x) { 'default' } else { $x }` | PS101 |
| `${obj}?.Name`, `${list}?[0]` | `if ($null -ne $obj) { $obj.Name }` | PS101 |
| `cmd1 && cmd2`, `cmd1 \|\| cmd2` | `cmd1; if ($LASTEXITCODE -eq 0) { cmd2 }` | PS101 |
| `ForEach-Object -Parallel` | `Start-Job`, runspaces or a plain loop | PS102 |
| `Get-Content -AsByteStream` | `[System.IO.File]::ReadAllBytes($path)` | PS102 |
| `-Encoding utf8NoBOM` | `[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))` | PS102 |
| `ConvertFrom-Json -AsHashtable` | Convert the PSCustomObject, or build a hashtable from `.PSObject.Properties` | PS102 |
| `Join-Path a b c` | `Join-Path (Join-Path a b) c` | PS102 |
| `$IsWindows`, `$IsLinux`, `$IsMacOS` | `[System.IO.Path]::DirectorySeparatorChar -eq '\'` | PS103 |
| `Test-Json`, `Get-Error`, `Join-String` | Hand-written checks, `$Error[0]`, `-join` | PS102 |

Also: `[Type]::new()` and classes need 5.0+ (fine). `Invoke-WebRequest` in 5.1 needs `-UseBasicParsing` on machines where Internet Explorer was never started; add it (7 accepts and ignores it). Use `#Requires -Version 5.1` at the top.

## 2. File encoding and text

- Keep `.ps1` files ASCII, or save them as UTF-8 with BOM. Windows PowerShell 5.1 reads BOM-less files in the ANSI code page, so Thai text or emoji in a BOM-less file becomes garbage or a syntax error. (PS002, PS003)
- Read and write text with explicit encodings. In 5.1, `Set-Content`/`Out-File` default to ANSI/UTF-16 and `-Encoding UTF8` adds a BOM; `[System.IO.File]::WriteAllText()` with `UTF8Encoding $false` produces the same bytes everywhere.
- Before printing non-ASCII text from external programs in the 5.1 console, set `[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false` and restore the old value in `finally`.
- Line endings: PowerShell accepts LF and CRLF. Batch files need CRLF (labels and `goto` break with LF). Shell scripts need LF.

## 3. External programs

- An external program never throws. Check `$LASTEXITCODE` right after each call and stop on failure. (PS403)
- In 5.1, when stderr is redirected, every stderr line becomes an error record and `$ErrorActionPreference = 'Stop'` turns the first one into a crash. Set `$ErrorActionPreference = 'Continue'` inside the helper that calls the program (see `Invoke-Native` in the template).
- Call with `& $exe @arguments` where `$arguments` is a string array. Never build a command string for `Invoke-Expression` or `cmd /c`. (PS301)
- Windows PowerShell 5.1 drops empty-string arguments and mangles embedded double quotes when calling external programs. When arguments can contain `"` or be empty, use `Invoke-Code.ps1`, or `System.Diagnostics.Process` with escaped arguments.
- Write `robocopy`, `xcopy`, `curl.exe`, `sc.exe` with their extensions when an alias exists; `curl` and `sc` mean different things in 5.1 and 7. (PS201)
- `robocopy` returns 0-7 for success. Check documented success codes, not only 0.

## 4. Paths and the file system

- Use `-LiteralPath` for paths that come from users or files; `-Path` treats `[` and `]` as wildcards.
- Resolve relative paths with `$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)`. .NET methods use the process folder, not the PowerShell location.
- Build paths with `Join-Path`; never hard-code `C:\Users\<name>`. Use `$env:USERPROFILE`, `$HOME`, `$env:TEMP`, `$PSScriptRoot` and `[Environment]::GetFolderPath('Desktop')` (the Desktop may be redirected to OneDrive). (PS302)
- Quote every path in examples: user names and folders often contain spaces and non-ASCII characters.
- Paths longer than 260 characters need the `\\?\` prefix in 5.1 unless long paths are enabled.

## 5. Running scripts: execution policy and downloads

- Default execution policy on Windows clients is `Restricted` (no scripts). Run with `powershell -NoProfile -ExecutionPolicy Bypass -File .\script.ps1`; it affects only that process.
- Files downloaded from the internet carry a Zone.Identifier mark. With `RemoteSigned` they are blocked; `Unblock-File .\script.ps1` removes the mark after the user trusts the file.
- Do not change the machine-wide policy (`Set-ExecutionPolicy` without `-Scope Process` or `-Scope CurrentUser`). (PS303)
- `-NoProfile` prevents the user's profile from changing behavior. `-File` returns the script's `exit` code; `-Command` returns only 0 or 1 unless you call `exit` explicitly.
- A `.cmd` launcher (`run-code.cmd` pattern) lets people run a script by double-click or from cmd.exe.

## 6. Errors, exit codes and output

- Start every script with `Set-StrictMode -Version 3.0` and `$ErrorActionPreference = 'Stop'`. (PS401, PS402) Under strict mode a missing hashtable key accessed with `.Key` throws; use `$table['Key']` or `ContainsKey()` for optional keys.
- Wrap the main body in `try`/`catch`, write the reason to standard error (`[Console]::Error.WriteLine()`), and `exit` with a documented code. Keep normal results on standard output.
- `Write-Host` is for people; `Write-Output` is for data that callers capture. Do not mix them for the same result.
- Support `-WhatIf` and `-Confirm` with `[CmdletBinding(SupportsShouldProcess = $true)]` and `$PSCmdlet.ShouldProcess()` before changing files, services, the registry or settings.

## 7. Administrator rights

- Check before acting: `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)`.
- To elevate, restart the script with `Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")` and explain the prompt to the user. Elevation always shows a UAC dialog; never try to bypass it.

## 8. Readability

- Use full cmdlet and parameter names: `Get-ChildItem -Path . -Filter *.log`, not `gci . *.log`. (PS202)
- Use approved verbs (`Get-Verb`) and `Verb-Noun` function names; one function per responsibility.
- Comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` and `.NOTES` (exit codes). `Get-Help .\script.ps1 -Full` then documents the script.
- Typed parameters with validation (`[ValidateNotNullOrEmpty()]`, `[ValidateSet()]`, `[ValidateRange()]`) instead of manual checks.
- Comments explain why a line exists (a compatibility workaround, a documented exit code), not what it does.
- Keep lines readable; use splatting (`$params = @{ ... }; Command @params`) for long calls instead of backtick continuation.

## 9. Verification before delivery

1. `Test-PowerShellScript.ps1 -FailOnWarning .\script.ps1`
2. Run in `powershell.exe` and in `pwsh` when present, with normal input, invalid input, a path with spaces and `-WhatIf`.
3. Check `$LASTEXITCODE` after the run and inspect created files and their encoding.
4. Deliver the exact command line and the expected output.
