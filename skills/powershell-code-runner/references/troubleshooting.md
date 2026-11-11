# Troubleshooting PowerShell and the runner

| Symptom | Cause | Fix |
| --- | --- | --- |
| `... cannot be loaded because running scripts is disabled on this system` | Execution policy `Restricted` or `AllSigned` | `powershell -NoProfile -ExecutionPolicy Bypass -File .\script.ps1`, or use `run-code.cmd` |
| `... is not digitally signed` for a downloaded file | Zone.Identifier mark with `RemoteSigned` | Check the file, then `Unblock-File .\script.ps1` |
| `The term 'x' is not recognized` | Program not installed or not in `PATH`; new installs need a new terminal | Open a new terminal; `Get-Command x`; `Invoke-Code.ps1 -List` shows install commands |
| `Python was not found; run without arguments to install from the Microsoft Store` | The Store alias `python.exe` in `WindowsApps` | Install Python (`winget install -e --id Python.Python.3.13`) or turn the alias off in Settings > Apps > Advanced app settings > App execution aliases. The runner skips this stub automatically |
| Thai or other non-ASCII text shows as `???` or broken characters | Console code page is not UTF-8, or a `.ps1` saved without BOM | Runner switches the console to UTF-8 automatically; save `.ps1` files as UTF-8 with BOM; for other programs use `[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false` |
| `Unexpected token '?'` or `'&&' is not a valid statement separator` | PowerShell 7 syntax in Windows PowerShell 5.1 | Rewrite with `if`; `Test-PowerShellScript.ps1` lists every place (PS101) |
| `The property 'X' cannot be found on this object` | Strict mode and a missing property or hashtable key | Check with `$obj.PSObject.Properties['X']` or `$table.ContainsKey('X')`, or use `$table['X']` |
| Script stops at the first warning printed by git, npm or a compiler | Windows PowerShell 5.1 turns redirected stderr into errors under `Stop` | Call the program inside a helper that sets `$ErrorActionPreference = 'Continue'` and checks `$LASTEXITCODE` |
| Empty or quoted arguments arrive wrong in a program | Windows PowerShell 5.1 native argument passing | Use `Invoke-Code.ps1` (exact quoting) or pass arguments through `System.Diagnostics.Process` |
| Program exit code `-1073741515` (0xC0000135) | A DLL the program needs is missing (often MinGW runtime DLLs) | Build with `-static` (the runner does this for MinGW) or add the compiler's `bin` folder to `PATH` |
| `$'\r': command not found` in Bash | Script saved with CRLF line endings | Save with LF; the runner runs an LF copy and warns |
| `link.exe not found` (Rust) or `cl` not recognized | Visual Studio Build Tools missing or Developer PowerShell not used | Install Build Tools with the C++ workload, or use the GNU toolchain (`rustup default stable-gnu`) |
| `error: could not find a Visual Studio installation` (clang) | LLVM clang on Windows links with MSVC by default | Install Build Tools, or use MSYS2 gcc |
| Runner exits with 69 although a tool is installed | The tool's version probe failed or the tool is not in `PATH` | `Invoke-Code.ps1 -List`; run the tool's `--version` yourself; open a new terminal after installing |
| Runner exits with 64 for a file | Unknown extension or a runner option after the file | Add `-Language <name>` before the file; options go before the file |
| Program waits forever | It reads standard input or loops | Give `-InputFile` or `-TimeoutSeconds`; press Ctrl+C to stop |
| A path with `[` or `]` is "not found" | `-Path` treats brackets as wildcards | Use `-LiteralPath` |
| Output file has a BOM or is UTF-16 in 5.1 | `Out-File`/`Set-Content` defaults | `[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))` |
| `Invoke-WebRequest` fails with an Internet Explorer engine error | 5.1 parses HTML with IE by default | Add `-UseBasicParsing` |
