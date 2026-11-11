# Invoke-Code.ps1 runner guide

`Invoke-Code.ps1` runs one source file, an inline snippet or a project folder. It works in Windows PowerShell 5.1 and PowerShell 7+ on Windows, macOS and Linux, needs no modules, and never changes system settings.

## Command forms

```powershell
.\Invoke-Code.ps1 [runner options] <file-or-folder> [program arguments...]
.\Invoke-Code.ps1 [runner options] -Language <name> -Code <text> [program arguments...]
.\Invoke-Code.ps1 -List
```

```bat
run-code.cmd [runner options] <file-or-folder> [program arguments...]
```

- Runner options must come before the file. Every token after the file goes to the program unchanged, including `-v`, `--help`, empty strings and quoted text with spaces.
- In `-Code` mode the first token that is not a runner option starts the program arguments; `--` also ends the runner options.
- The script has no `param()` block on purpose, so PowerShell cannot bind, abbreviate or swallow program arguments.
- PowerShell itself splits a bare `-name:value` token before any script sees it. Quote such arguments from PowerShell, for example `'-n:3'`; numbers such as `1.0` should also be quoted when exact text matters.
- From cmd.exe, Explorer or another program, use `run-code.cmd`; it starts PowerShell 7 when installed, otherwise Windows PowerShell 5.1, with `-NoProfile -ExecutionPolicy Bypass`.
- Drag a file onto `run-code-wait.cmd` to run it in a window that stays open until Enter is pressed.

## Options

| Option | Effect |
| --- | --- |
| `-Language <name>` | Force a language by id, alias or extension (`python`, `py`, `cpp`, `c#`, `ts` ...). Required with `-Code` and for unknown extensions. |
| `-Code <text>` | Write the text to a temporary source file and run it. Java uses the public class name as the file name. |
| `-Toolchain <name>` | Use one toolchain of the language, for example `clang`, `bun`, `ts-node`, `csc`. |
| `-BuildArg <arg>` | Add one compiler argument; repeat for more: `-BuildArg -O2 -BuildArg -std=c++20`. |
| `-InputFile <path>` | Send a file to standard input. |
| `-WorkingDirectory <path>` | Program working folder. Default: the current PowerShell location; project folders run inside the folder. |
| `-TimeoutSeconds <n>` | Stop the program and its child processes after `n` seconds (exit code 124). Builds are not limited. |
| `-Plan` | Print detection, toolchain, folders and exact commands as PowerShell lines; run nothing. |
| `-List` | Show PowerShell version, execution policy, console code page and the readiness of every language. |
| `-KeepBuild` | Keep the temporary build folder and print its path. |
| `-NoUtf8` | Leave console code page and runtime encodings unchanged. |
| `-Quiet` | Print only the program's output; build output appears only when a build fails. |
| `-Pause` | Wait for Enter at the end when a person is at the keyboard. |
| `-Help` | Short usage. `Get-Help .\Invoke-Code.ps1 -Full` shows the full help. |

## Exit codes and output

The program's own exit code is returned. The runner uses these codes for its own outcomes:

| Code | Meaning |
| --- | --- |
| 64 | Usage error: unknown option or language, nothing to run, unrecognized file type, unsafe batch argument |
| 65 | A build or compile step failed (the compiler's own messages are shown) |
| 66 | Source file, input file or working folder not found |
| 69 | No working toolchain; the message shows the install command for this OS |
| 70 | Internal runner error (with a stack trace) |
| 124 | `-TimeoutSeconds` reached |

Runner messages and build output go to standard error, so `> out.txt` captures only the program. Common Windows crash codes are explained, for example `-1073741515` = a required DLL was not found.

The program inherits the console directly: interactive input works and output is never re-encoded. Because of that, PowerShell variables cannot capture program output from an in-process call (`$x = .\Invoke-Code.ps1 ...`); capture at process level instead: `$x = powershell -NoProfile -File .\Invoke-Code.ps1 -Quiet .\app.py`.

## How a file is resolved

1. `-Language`, otherwise the file extension, otherwise the shebang line (`#!/usr/bin/env python3`).
2. Each toolchain of the language is tried in order. An executable must exist in `PATH` or a known install folder and answer a version probe with exit code 0, so broken stubs such as the Microsoft Store `python.exe` alias are skipped.
3. Compiled languages build into a new temporary folder, which is deleted afterwards. Interpreted languages run the source in place.
4. A tool found outside `PATH` gets its own folder prepended to `PATH` for the run, so its DLLs load.
5. Shell scripts with Windows CRLF line endings run from a converted LF copy, with a warning.

A folder runs as a project when it contains `Cargo.toml` (cargo build, then cargo run), `go.mod` (go build), one `.csproj`/`.fsproj`/`.vbproj` (dotnet build, then dotnet run), or `package.json` with a `start` script (npm run start). Otherwise its entry file is used: the package.json `main`, `__main__.py`, `main.py`, then a single file named `main`, `program`, `app`, `index`, `run` or `start`, or the only recognized source file.

## Reliability details

- Arguments are passed with an exact quoting implementation (MSVC/CommandLineToArgvW rules) in Windows PowerShell 5.1 and with `ProcessStartInfo.ArgumentList` in PowerShell 7, so both behave the same. Batch files run through `cmd.exe /d /s /c` with cmd-safe quoting; arguments containing `"`, `%` or line breaks are refused instead of being reinterpreted by cmd.exe.
- Unless `-NoUtf8` is given, the Windows console output code page is UTF-8 during the run and restored afterwards; `PYTHONUTF8`, `PYTHONIOENCODING` are set when not already set; Java runs with UTF-8 `file.encoding`, `stdout.encoding` and `stderr.encoding`; javac reads sources as UTF-8; MSVC gets `/utf-8`; csc and vbc get `/utf8output /codepage:65001`.
- MinGW gcc, g++ and gfortran link with `-static` on Windows, so the program needs no MinGW DLLs at run time.
- Go builds an executable first because `go run` replaces non-zero exit codes with 1; Zig builds inside the temporary folder so its cache never lands in the working folder.
- C# uses `dotnet run --file` on .NET 10+, a generated project on .NET 6-9 (top-level statements and implicit usings work), the built-in .NET Framework `csc.exe` (C# 5) on any Windows, or Mono `mcs`.
- Rust single files compile with `--edition 2021`; TypeScript runs with tsx, Bun, Deno (`-A`), ts-node or Node.js 22.6+ type stripping.
- Non-ASCII temporary folders on Windows (for example a Thai user name) are avoided by building under `%ProgramData%\code-runner`; set `CODE_RUNNER_BUILD_ROOT` to choose another build root.

## Languages

PowerShell tries the edition that is running the runner first. Tools marked with an operating system are used only there.

| Id | Language | Extensions | Toolchains in order |
| --- | --- | --- | --- |
| `python` | Python | .py .pyw .pyz | py (windows), python3, python, pypy3 |
| `javascript` | JavaScript (Node.js) | .js .mjs .cjs | node, bun, deno |
| `typescript` | TypeScript | .ts .mts .cts | tsx, bun, deno, ts-node, node |
| `powershell` | PowerShell | .ps1 | pwsh, powershell (windows) |
| `batch` | Batch (cmd.exe) | .cmd .bat | cmd (windows) |
| `vbscript` | VBScript / Windows Script Host | .vbs .wsf | cscript (windows) |
| `bash` | Bash / POSIX shell | .sh .bash | bash |
| `zsh` | Zsh | .zsh | zsh |
| `fish` | Fish | .fish | fish |
| `c` | C | .c | gcc, clang, cc (unix), cl (windows) |
| `cpp` | C++ | .cpp .cc .cxx .c++ .cp | g++, clang++, c++ (unix), cl (windows) |
| `csharp` | C# | .cs | dotnet, csc (windows), mono (unix) |
| `fsharp` | F# script | .fsx | dotnet fsi |
| `vbnet` | Visual Basic .NET | .vb | vbc (windows) |
| `java` | Java | .java | javac, java |
| `jar` | Java archive | .jar | java |
| `kotlin` | Kotlin | .kt | kotlinc |
| `kotlinscript` | Kotlin script | .kts | kotlinc |
| `scala` | Scala | .scala .sc | scala-cli, scala |
| `groovy` | Groovy | .groovy .gvy | groovy |
| `go` | Go | .go | go |
| `rust` | Rust | .rs | rustc |
| `swift` | Swift | .swift | swiftc, swift |
| `dart` | Dart | .dart | dart |
| `ruby` | Ruby | .rb .rbw | ruby |
| `perl` | Perl | .pl .pm .t | perl |
| `php` | PHP | .php | php |
| `lua` | Lua | .lua | lua |
| `r` | R | .r | Rscript |
| `julia` | Julia | .jl | julia |
| `haskell` | Haskell | .hs .lhs | runghc, ghc |
| `ocaml` | OCaml | .ml | ocaml |
| `elixir` | Elixir | .exs .ex | elixir |
| `erlang` | Erlang (escript) | .erl .escript | escript |
| `clojure` | Clojure | .clj .bb | babashka, clojure |
| `racket` | Racket | .rkt | racket |
| `scheme` | Scheme | .scm .ss | guile, chez, chicken |
| `commonlisp` | Common Lisp | .lisp .lsp | sbcl, clisp |
| `tcl` | Tcl | .tcl | tclsh |
| `awk` | AWK | .awk | awk |
| `autohotkey` | AutoHotkey | .ahk | AutoHotkey (windows) |
| `zig` | Zig | .zig | zig |
| `nim` | Nim | .nim | nim |
| `crystal` | Crystal | .cr | crystal |
| `d` | D | .d | dmd, ldc2, gdc |
| `v` | V | .v | v |
| `fortran` | Fortran | .f90 .f95 .f03 .f08 .f .for .f77 | gfortran, flang |
| `pascal` | Pascal | .pas .pp .lpr .dpr | fpc |
| `cobol` | COBOL | .cob .cbl .cobol | cobc |
| `ada` | Ada | .adb | gnatmake |
| `prolog` | Prolog (SWI) | (use -Language) | swipl |
| `native` | Windows program | .exe .com | direct (windows) |
| `html` | HTML page (opens the browser) | .html .htm | default browser (windows), open (mac), xdg-open (linux) |

Verified results (every fixture prints its arguments and exits with code 3; the runner must return exactly that):

- **Windows, Windows PowerShell 5.1 (GitHub Actions windows-latest):** Batch, VBScript, PowerShell (5.1 and 7), Python, JavaScript, TypeScript (Node.js), C and C++ (gcc, clang), C# (dotnet and the built-in csc.exe), VB.NET (vbc.exe), F# script, Java (javac and source launcher), Kotlin, Go, Rust, Haskell, Julia, R, Ruby, Perl, PHP, Bash (Git Bash), AWK, Tcl and Fortran, plus `run-code.cmd` and `run-code-wait.cmd`.
- **Ubuntu and macOS, PowerShell 7 (GitHub Actions):** Python, JavaScript, TypeScript, PowerShell, Bash, Zsh (macOS), C and C++ (gcc, clang), C#, F#, Java, Kotlin, Swift, Go (Ubuntu), Rust, Haskell (Ubuntu), Ruby, Perl, PHP (Ubuntu), AWK, Tcl and Fortran (Ubuntu).
- **Linux during development, PowerShell 7.4:** additionally Lua, Pascal (fpc), COBOL, Common Lisp (sbcl), Scheme (guile), OCaml, C# with Mono and .NET 8/10, TypeScript with Bun and ts-node, and Rust, Go, .NET and npm project folders.

The test suite runs every fixture whose toolchain is installed and lists the skipped ones, so each CI log shows exactly what ran. Entries never exercised so far (for example Dart, Elixir, Erlang, Groovy, Zig, Nim, Crystal, D, V, Ada, Prolog, AutoHotkey) follow the toolchain's documented command line.

## Adding a language

Add one hashtable to `$script:Languages` in `Invoke-Code.ps1`:

```powershell
@{ Id = 'example'; Name = 'Example'; Ext = @('.ex1'); Alias = @('ex'); Shebang = @('example')
   Tools = @(
       # Interpreter: <exe> [Pre...] <source> [Post...] <program arguments>
       @{ Name = 'example'; Exe = 'example'; Probe = @('--version'); Pre = @('--quiet') }
       # Compiler: return build and run steps; $c holds Source, BuildDir, Exe, Args, BuildArgs.
       @{ Name = 'examplec'; Exe = 'examplec'; Probe = @('--version')
          Steps = { param($t, $c)
              New-Step build $t.Path $c.Source '-o' $c.Exe $c.BuildArgs
              New-Step run $c.Exe $c.Args } })
   Install = @{ windows = 'winget install -e --id Vendor.Example'; mac = 'brew install example'; linux = 'sudo apt install example' } }
```

`Probe = $null` skips the version check (use `Describe` for the label), `Os = 'windows' | 'unix' | 'mac' | 'linux'` limits a tool, `Paths` lists known install locations (wildcards allowed), `Accept` rejects versions that are too old, and `PosixPath = $true` passes forward-slash paths on Windows (MSYS tools such as Git Bash, awk and Git's perl need them; native programs accept them too). Add a fixture to `tests/powershell-code-runner/fixtures/` that prints `OK:` followed by its arguments joined with `|` and exits with code 3; the test suite runs it whenever the toolchain exists.
