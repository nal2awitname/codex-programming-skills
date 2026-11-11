#Requires -Version 5.1
<#
.SYNOPSIS
    Build and run a source file, an inline snippet or a project folder in many languages.

.DESCRIPTION
    Usage:
      Invoke-Code.ps1 [options] <file-or-folder> [program arguments...]
      Invoke-Code.ps1 [options] -Language <name> -Code <text> [program arguments...]
      Invoke-Code.ps1 -List

    Runner options must come before the file. Everything after the file is passed to
    the program unchanged, so program flags such as -v or --help never reach the runner.
    In -Code mode the first token that is not a runner option starts the program
    arguments; "--" also ends the runner options.

    The runner detects the language (forced -Language, then file extension, then the
    shebang line), finds a working interpreter or compiler (each candidate is probed,
    so broken stubs such as the Microsoft Store python alias are skipped), builds into
    a temporary folder when the language is compiled, runs the program and returns the
    program's own exit code. It works in Windows PowerShell 5.1 and PowerShell 7+ on
    Windows, macOS and Linux.

    Options:
      -Language <name>          Force a language or alias (see -List): python, c, cpp ...
      -Code <text>              Run inline source text; requires -Language.
      -Toolchain <name>         Force one toolchain of the language, e.g. clang or bun.
      -BuildArg <argument>      Extra compiler/build argument; repeat it for more.
      -InputFile <path>         Send this file to the program's standard input.
      -WorkingDirectory <path>  Program working directory. Default: the current
                                directory; project folders run inside the folder.
      -TimeoutSeconds <n>       Stop the program and its child processes after n seconds.
      -Plan                     Show detection, toolchain and exact commands; run nothing.
      -List                     Show every language and whether it is ready here.
      -KeepBuild                Keep the temporary build folder and print its path.
      -NoUtf8                   Do not switch the console and runtimes to UTF-8.
      -Quiet                    Print only the program's own output.
      -Pause                    Wait for Enter before exiting (for double-click and
                                drag-and-drop launchers; ignored when input is redirected).
      -Help                     Show this help.

    Runner messages go to standard error, so redirecting standard output captures only
    the program's output. Exit codes: the program's own code, or one of these:
      64  usage error or unrecognized file type     65  build/compile step failed
      66  source or input file not found            69  no working toolchain installed
      70  internal runner error                     124 timeout reached

.EXAMPLE
    .\Invoke-Code.ps1 .\hello.py

.EXAMPLE
    .\Invoke-Code.ps1 .\main.c --verbose "two words"

.EXAMPLE
    .\Invoke-Code.ps1 -Language javascript -Code 'console.log(6 * 7)'

.EXAMPLE
    .\Invoke-Code.ps1 -TimeoutSeconds 5 -InputFile .\input.txt .\solve.cpp

.EXAMPLE
    .\Invoke-Code.ps1 -Plan .\Program.cs

.EXAMPLE
    .\Invoke-Code.ps1 -List
#>

# No param() block on purpose: PowerShell would otherwise bind, abbreviate or swallow
# program arguments such as -v, -o or -Verbose before the program could see them.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:RunnerVersion = '1.0.0'
$script:OnWindows = [System.IO.Path]::DirectorySeparatorChar -eq '\'
$script:OnMac = (-not $script:OnWindows) -and [bool](Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue)
$script:OsKey = if ($script:OnWindows) { 'windows' } elseif ($script:OnMac) { 'mac' } else { 'linux' }
$script:ExeSuffix = if ($script:OnWindows) { '.exe' } else { '' }
$script:IsCore = $PSVersionTable.PSEdition -eq 'Core'
$script:Quiet = $false

# ---------------------------------------------------------------------------
# Messages and runner errors
# ---------------------------------------------------------------------------

function Write-Info {
    param([string] $Message)
    if (-not $script:Quiet) { [Console]::Error.WriteLine('[code-runner] ' + $Message) }
}

function Write-Warn {
    param([string] $Message)
    [Console]::Error.WriteLine('[code-runner] WARNING: ' + $Message)
}

function New-RunnerError {
    # Runner failures carry their documented exit code to the single exit point.
    param([int] $ExitCode, [string] $Message)
    $exception = New-Object System.Exception $Message
    $exception.Data['RunnerExitCode'] = $ExitCode
    return $exception
}

function Get-UsageText {
    return @'
Usage:
  Invoke-Code.ps1 [options] <file-or-folder> [program arguments...]
  Invoke-Code.ps1 [options] -Language <name> -Code <text> [program arguments...]
  Invoke-Code.ps1 -List

Options (before the file): -Language <name>  -Code <text>  -Toolchain <name>
  -BuildArg <arg>  -InputFile <path>  -WorkingDirectory <path>  -TimeoutSeconds <n>
  -Plan  -List  -KeepBuild  -NoUtf8  -Quiet  -Pause  -Help
Full help: Get-Help .\Invoke-Code.ps1 -Full
'@
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

function ConvertTo-FlatStringList {
    # In-process callers may pass numbers or arrays; native callers always pass strings.
    param([object[]] $Items)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Items) {
        if ($null -eq $item) { continue }
        if ($item -is [System.Array]) {
            foreach ($inner in (ConvertTo-FlatStringList -Items $item)) { $result.Add($inner) }
        } else {
            $result.Add([string]$item)
        }
    }
    return , ([string[]]$result.ToArray())
}

function Read-RunnerArguments {
    param([object[]] $RawArguments)
    $tokens = ConvertTo-FlatStringList -Items $RawArguments
    $options = @{
        Path = $null; Code = $null; Language = $null; Toolchain = $null; InputFile = $null
        WorkingDirectory = $null; TimeoutSeconds = 0; Plan = $false; List = $false
        KeepBuild = $false; NoUtf8 = $false; Quiet = $false; Pause = $false; Help = $false
        BuildArgs = (New-Object System.Collections.Generic.List[string])
        ProgramArgs = (New-Object System.Collections.Generic.List[string])
    }
    $valueOptions = @{
        'language' = 'Language'; 'lang' = 'Language'; 'code' = 'Code'; 'toolchain' = 'Toolchain'
        'buildarg' = 'BuildArg'; 'buildargs' = 'BuildArg'; 'inputfile' = 'InputFile'; 'input' = 'InputFile'
        'workingdirectory' = 'WorkingDirectory'; 'cwd' = 'WorkingDirectory'
        'timeoutseconds' = 'TimeoutSeconds'; 'timeout' = 'TimeoutSeconds'
    }
    $switchOptions = @{
        'plan' = 'Plan'; 'whatif' = 'Plan'; 'list' = 'List'; 'keepbuild' = 'KeepBuild'
        'noutf8' = 'NoUtf8'; 'quiet' = 'Quiet'; 'pause' = 'Pause'; 'help' = 'Help'; 'h' = 'Help'; '?' = 'Help'
    }
    $index = 0
    $optionsEnded = $false
    while ($index -lt $tokens.Count) {
        $token = $tokens[$index]
        if (-not $optionsEnded -and $token -eq '--') { $optionsEnded = $true; $index++; continue }
        if (-not $optionsEnded -and $token -eq '/?') { $options.Help = $true; $index++; continue }
        $match = $null
        if (-not $optionsEnded) { $match = [regex]::Match($token, '^--?([A-Za-z?][A-Za-z0-9]*):?$') }
        if ($null -ne $match -and $match.Success) {
            $key = $match.Groups[1].Value.ToLowerInvariant()
            if ($valueOptions.ContainsKey($key)) {
                if ($index + 1 -ge $tokens.Count) { throw (New-RunnerError 64 "Option $token needs a value.") }
                $value = $tokens[$index + 1]
                $name = $valueOptions[$key]
                if ($name -eq 'BuildArg') {
                    $options.BuildArgs.Add($value)
                } elseif ($name -eq 'TimeoutSeconds') {
                    $seconds = 0
                    if (-not [int]::TryParse($value, [ref]$seconds) -or $seconds -lt 0) {
                        throw (New-RunnerError 64 "-TimeoutSeconds needs a whole number of seconds, not '$value'.")
                    }
                    $options.TimeoutSeconds = $seconds
                } else {
                    $options[$name] = $value
                }
                $index += 2
                continue
            }
            if ($switchOptions.ContainsKey($key)) {
                $options[$switchOptions[$key]] = $true
                # Known immediately, so the window also stays open after a usage error.
                if ($switchOptions[$key] -eq 'Pause') { $script:PauseAtEnd = $true }
                $index++
                continue
            }
            if ($null -eq $options.Code -and $null -eq $options.Path) {
                throw (New-RunnerError 64 ("Unknown runner option '$token'. Runner options go before the file; " +
                    'program arguments go after it.'))
            }
        }
        # The first non-option token is the file, unless inline code was given.
        if ($null -eq $options.Code -and $null -eq $options.Path) {
            $options.Path = $token
            $index++
        }
        break
    }
    # PowerShell splits "-name:value" into "-name:" and the value for in-process calls.
    for (; $index -lt $tokens.Count; $index++) {
        $token = $tokens[$index]
        if ($token -match '^-[^\s:]+:$' -and $index + 1 -lt $tokens.Count) {
            $options.ProgramArgs.Add($token + $tokens[$index + 1])
            $index++
        } else {
            $options.ProgramArgs.Add($token)
        }
    }
    return $options
}

# ---------------------------------------------------------------------------
# Process launching (identical behavior in Windows PowerShell 5.1 and PowerShell 7)
# ---------------------------------------------------------------------------

function ConvertTo-WindowsArgument {
    # Quote one argument so CommandLineToArgvW and the MSVC runtime read it back exactly.
    param([AllowEmptyString()] [string] $Argument)
    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') { return $Argument }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append('\' * ($slashes * 2 + 1))
            [void]$builder.Append('"')
        } else {
            if ($slashes -gt 0) { [void]$builder.Append('\' * $slashes) }
            [void]$builder.Append($character)
        }
        $slashes = 0
    }
    if ($slashes -gt 0) { [void]$builder.Append('\' * ($slashes * 2)) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-CmdArgument {
    # cmd.exe expands % and treats quotes specially even inside quoted text, so batch
    # files only receive arguments that cmd.exe cannot reinterpret.
    param([AllowEmptyString()] [string] $Argument)
    if ($Argument -match '["%\r\n]') {
        throw (New-RunnerError 64 ("Cannot pass an argument containing a quote, percent sign or line break " +
            "to a batch file safely: $Argument"))
    }
    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s&|<>^(),;=!]') { return $Argument }
    $trailing = [regex]::Match($Argument, '\\*$').Value
    return '"' + $Argument + $trailing + '"'
}

function Test-BatchFile {
    param([string] $FilePath)
    if (-not $script:OnWindows) { return $false }
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    return ($extension -eq '.cmd' -or $extension -eq '.bat')
}

function New-NativeProcess {
    param(
        [string] $FilePath,
        [string[]] $ArgumentList,
        [string] $WorkingDirectory,
        [switch] $Capture,
        [switch] $RedirectInput,
        [switch] $RedirectOutput
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.UseShellExecute = $false
    $startInfo.WorkingDirectory = $WorkingDirectory
    $arguments = @($ArgumentList | Where-Object { $null -ne $_ })
    if (Test-BatchFile $FilePath) {
        # Run batch files through cmd.exe explicitly with cmd-safe quoting.
        $comSpec = $env:ComSpec
        if (-not $comSpec) { $comSpec = Join-Path $env:SystemRoot 'System32\cmd.exe' }
        $startInfo.FileName = $comSpec
        $line = (@($FilePath) + $arguments | ForEach-Object { ConvertTo-CmdArgument $_ }) -join ' '
        $startInfo.Arguments = '/d /s /c "' + $line + '"'
    } else {
        $startInfo.FileName = $FilePath
        if ($null -ne $startInfo.PSObject.Properties['ArgumentList']) {
            foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) }
        } else {
            $startInfo.Arguments = ($arguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
        }
    }
    if ($Capture) {
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.RedirectStandardInput = $true
    } else {
        if ($RedirectInput) { $startInfo.RedirectStandardInput = $true }
        if ($RedirectOutput) { $startInfo.RedirectStandardOutput = $true }
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    return $process
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process] $Process)
    try {
        if ($Process.HasExited) { return }
        $killTree = [System.Diagnostics.Process].GetMethod('Kill', [Type[]]@([bool]))
        if ($null -ne $killTree) {
            $Process.Kill($true)
        } elseif ($script:OnWindows) {
            $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            $killer = New-NativeProcess -FilePath $taskkill -ArgumentList @('/PID', [string]$Process.Id, '/T', '/F') `
                -WorkingDirectory $env:SystemRoot -Capture
            [void]$killer.Start()
            $killer.StandardInput.Close()
            [void]$killer.WaitForExit(10000)
            $killer.Dispose()
        } else {
            $Process.Kill()
        }
        [void]$Process.WaitForExit(5000)
    } catch {
        Write-Warn ('Could not stop process ' + $Process.Id + ': ' + $_.Exception.Message)
    }
}

function Invoke-Captured {
    # Probe a tool quietly; stdin is closed so a tool that opens a REPL cannot hang.
    param([string] $FilePath, [string[]] $ArgumentList, [int] $TimeoutMilliseconds = 20000, [string] $WorkingDirectory)
    if (-not $WorkingDirectory) { $WorkingDirectory = $script:StartDirectory }
    $process = New-NativeProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -Capture
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            Stop-ProcessTree $process
            return @{ ExitCode = 124; Output = '' }
        }
        $process.WaitForExit()
        return @{ ExitCode = $process.ExitCode; Output = ($stdout.Result + "`n" + $stderr.Result) }
    } catch {
        return @{ ExitCode = -1; Output = $_.Exception.Message }
    } finally {
        $process.Dispose()
    }
}

function Invoke-Interactive {
    # The child inherits this console (or the caller's pipes) directly: interactive
    # input works, output is never re-encoded, and stderr never becomes a PowerShell error.
    param(
        [string] $FilePath,
        [string[]] $ArgumentList,
        [string] $WorkingDirectory,
        [string] $InputFile,
        [int] $TimeoutSeconds,
        [switch] $OutputToStderr
    )
    # Build tools print progress on stdout; sending it to stderr keeps stdout for the program.
    $process = New-NativeProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory `
        -RedirectInput:([bool]$InputFile) -RedirectOutput:$OutputToStderr
    $inputStream = $null
    $copy = $null
    $inputClosed = $true
    try {
        try {
            [void]$process.Start()
        } catch {
            throw (New-RunnerError 69 ("Cannot start '$FilePath': " + $_.Exception.Message))
        }
        if ($InputFile) {
            $inputStream = [System.IO.File]::OpenRead($InputFile)
            $copy = $inputStream.CopyToAsync($process.StandardInput.BaseStream)
            $inputClosed = $false
        }
        if ($OutputToStderr) {
            # Only stdout is redirected (stderr is inherited), so reading it to the end cannot deadlock.
            $buffered = New-Object System.Collections.Generic.List[string]
            while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
                if ($script:Quiet) { $buffered.Add($line) } else { [Console]::Error.WriteLine($line) }
            }
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { foreach ($line in $buffered) { [Console]::Error.WriteLine($line) } }
        }
        $deadline = [DateTime]::MaxValue
        if ($TimeoutSeconds -gt 0) { $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds) }
        while (-not $process.WaitForExit(50)) {
            if (-not $inputClosed -and $copy.IsCompleted) {
                try { $process.StandardInput.Close() } catch { $null = $_ }
                $inputClosed = $true
            }
            if ([DateTime]::UtcNow -gt $deadline) {
                Stop-ProcessTree $process
                Write-Warn "Time limit of $TimeoutSeconds second(s) reached; the program was stopped."
                return 124
            }
        }
        $process.WaitForExit()
        return $process.ExitCode
    } finally {
        if (-not $inputClosed) { try { $process.StandardInput.Close() } catch { $null = $_ } }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        try { if (-not $process.HasExited) { Stop-ProcessTree $process } } catch { $null = $_ }
        $process.Dispose()
    }
}

# ---------------------------------------------------------------------------
# Toolchain discovery
# ---------------------------------------------------------------------------

function Get-WindowsPath {
    # Known install locations; returns nothing outside Windows or when a base is missing.
    param([string] $Base, [string] $Child)
    if ($script:OnWindows -and $Base) { return (Join-Path $Base $Child) }
}

function Get-VersionNumber {
    param([string] $Text)
    $match = [regex]::Match([string]$Text, '(\d+)\.(\d+)(?:\.(\d+))?')
    if (-not $match.Success) { return $null }
    return [version]($match.Groups[1].Value + '.' + $match.Groups[2].Value + '.' + $(if ($match.Groups[3].Success) { $match.Groups[3].Value } else { '0' }))
}

function Get-FirstLine {
    param([string] $Text)
    foreach ($line in ([string]$Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -and $trimmed -notmatch '^Picked up ') {
            if ($trimmed.Length -gt 70) { $trimmed = $trimmed.Substring(0, 70) }
            return $trimmed
        }
    }
    return ''
}

function Find-CandidatePaths {
    param([hashtable] $Tool)
    $paths = New-Object System.Collections.Generic.List[object]
    foreach ($name in @($Tool.Exe)) {
        if (-not $name) { continue }
        foreach ($command in @(Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue)) {
            if ($command.Path) { $paths.Add(@{ Path = $command.Path; Known = $false }) }
        }
    }
    foreach ($pattern in @($Tool.Paths)) {
        if (-not $pattern) { continue }
        $items = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Sort-Object -Property FullName -Descending)
        foreach ($item in $items) { $paths.Add(@{ Path = $item.FullName; Known = $true }) }
    }
    $seen = @{}
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in $paths) {
        $key = $candidate.Path.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if ($Tool.Exclude -and $candidate.Path -match $Tool.Exclude) { continue }
        $result.Add($candidate)
    }
    return , $result
}

function Test-ToolOs {
    param([hashtable] $Tool)
    $os = $Tool.Os
    if (-not $os -or $os -eq 'any') { return $true }
    if ($os -eq 'unix') { return -not $script:OnWindows }
    return $os -eq $script:OsKey
}

function Resolve-Tool {
    # Return the first toolchain whose executable exists and answers its probe.
    param([object] $Language, [string] $Forced)
    $tools = @($Language.Tools | Where-Object { Test-ToolOs $_ })
    if ($Forced) {
        $tools = @($tools | Where-Object { $_.Name -eq $Forced })
        if ($tools.Count -eq 0) {
            $names = (@($Language.Tools | ForEach-Object { $_.Name }) -join ', ')
            throw (New-RunnerError 64 "Toolchain '$Forced' is not defined for $($Language.Name) on this OS. Choose one of: $names")
        }
    }
    foreach ($tool in $tools) {
        $attempts = 0
        foreach ($candidate in (Find-CandidatePaths $tool)) {
            if ($attempts -ge 3) { break }
            $attempts++
            $version = ''
            if ($null -ne $tool.Probe) {
                $probe = Invoke-Captured -FilePath $candidate.Path -ArgumentList @($tool.Probe)
                if ($probe.ExitCode -ne 0) { continue }
                $version = Get-FirstLine $probe.Output
            } elseif ($tool.Describe) {
                $version = $tool.Describe
            }
            if ($tool.Accept -and -not (& $tool.Accept $version)) { continue }
            return [pscustomobject]@{
                Name = $tool.Name; Path = $candidate.Path; Version = $version
                FromKnownPath = $candidate.Known; Definition = $tool
            }
        }
    }
    return $null
}

function Find-Executable {
    # Locate a helper program (for example java next to javac) or fail with code 69.
    param([string[]] $Names, [string] $NearPath, [string] $Purpose)
    if ($NearPath) {
        $folder = Split-Path -Parent $NearPath
        foreach ($name in $Names) {
            $sibling = Join-Path $folder ($name + $script:ExeSuffix)
            if (Test-Path -LiteralPath $sibling -PathType Leaf) { return $sibling }
        }
    }
    foreach ($name in $Names) {
        $command = @(Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($null -ne $command) { return $command.Path }
    }
    throw (New-RunnerError 69 "$Purpose needs '$($Names[0])', which was not found in PATH.")
}

# ---------------------------------------------------------------------------
# Build and run steps
# ---------------------------------------------------------------------------

function New-Step {
    # New-Step <build|run|open> <program> [arguments...]
    param([string] $Phase, [string] $FilePath)
    return [pscustomobject]@{
        Phase = $Phase; FilePath = $FilePath; Arguments = (ConvertTo-FlatStringList -Items $args); WorkingDirectory = $null
    }
}

function Set-StepDirectory {
    param([object] $Step, [string] $Directory)
    $Step.WorkingDirectory = $Directory
    return $Step
}

function Get-SourceArgument {
    # Git Bash and MSYS shells read forward-slash Windows paths reliably.
    param([object] $Context, [hashtable] $Tool)
    if ($script:OnWindows -and $Tool.PosixPath) { return $Context.Source.Replace('\', '/') }
    return $Context.Source
}

function Get-InterpreterSteps {
    param([object] $Tool, [object] $Context)
    $definition = $Tool.Definition
    $source = Get-SourceArgument $Context $definition
    return @(New-Step run $Tool.Path @($definition.Pre) $source @($definition.Post) $Context.Args)
}

function Get-JavaMainClass {
    param([string] $SourcePath, [string] $BaseName)
    $text = [System.IO.File]::ReadAllText($SourcePath)
    $package = [regex]::Match($text, '(?m)^\s*package\s+([\w.]+)\s*;')
    if ($package.Success) { return $package.Groups[1].Value + '.' + $BaseName }
    return $BaseName
}

function Get-JavaSourceRoot {
    param([string] $SourcePath)
    $text = [System.IO.File]::ReadAllText($SourcePath)
    $package = [regex]::Match($text, '(?m)^\s*package\s+([\w.]+)\s*;')
    $root = Split-Path -Parent $SourcePath
    if ($package.Success) {
        foreach ($segment in $package.Groups[1].Value.Split('.')) { $root = Split-Path -Parent $root }
    }
    return $root
}

function Get-Utf8JavaFlags {
    param([object] $Context)
    if ($Context.NoUtf8) { return @() }
    return @('-Dfile.encoding=UTF-8', '-Dstdout.encoding=UTF-8', '-Dstderr.encoding=UTF-8')
}

function New-DotnetProjectFile {
    param([object] $Context, [string] $TargetFramework)
    $project = Join-Path $Context.BuildDir 'App.csproj'
    $source = [System.Security.SecurityElement]::Escape($Context.Source)
    $xml = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>$TargetFramework</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>disable</Nullable>
    <LangVersion>latest</LangVersion>
    <AssemblyName>App</AssemblyName>
    <RootNamespace>App</RootNamespace>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
    <SatelliteResourceLanguages>en</SatelliteResourceLanguages>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="$source" />
  </ItemGroup>
</Project>
"@
    if (-not $Context.PlanOnly) {
        [void](New-Item -ItemType Directory -Path $Context.BuildDir -Force)
        Write-Utf8File -Path $project -Text $xml
    }
    return $project
}

function Complete-ToolDefinition {
    # Give every tool all keys so strict mode never meets a missing one.
    param([hashtable] $Tool)
    $defaults = @{ Os = 'any'; Exe = @(); Paths = @(); Exclude = $null; Probe = @('--version'); Describe = ''
                   Accept = $null; Steps = $null; Pre = @(); Post = @(); PosixPath = $false }
    foreach ($key in $defaults.Keys) {
        if (-not $Tool.ContainsKey($key)) { $Tool[$key] = $defaults[$key] }
    }
    return $Tool
}

function Complete-LanguageDefinition {
    param([hashtable] $Language)
    foreach ($key in @('Alias', 'Shebang', 'Ext')) {
        if (-not $Language.ContainsKey($key)) { $Language[$key] = @() }
    }
    $Language['Tools'] = @($Language['Tools'] | ForEach-Object { Complete-ToolDefinition $_ })
    return [pscustomobject]$Language
}

function Write-Utf8File {
    param([string] $Path, [string] $Text, [switch] $Bom)
    $encoding = New-Object System.Text.UTF8Encoding ([bool]$Bom)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

# ---------------------------------------------------------------------------
# Language table. Each tool is tried in order; Pre/Post wrap the source path for
# interpreters, and Steps returns build/run steps for compiled languages.
# ---------------------------------------------------------------------------

$pythonProbe = 'import sys; print("Python " + sys.version.split()[0])'
$programFiles = $env:ProgramFiles
$programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$localAppData = $env:LOCALAPPDATA
$systemRoot = $env:SystemRoot
$powerShellOrder = @(
    @{ Name = 'pwsh'; Exe = 'pwsh'; Probe = @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', '$PSVersionTable.PSVersion.ToString()')
       Pre = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')
       Paths = @(Get-WindowsPath $programFiles 'PowerShell\*\pwsh.exe') }
    @{ Name = 'powershell'; Os = 'windows'; Exe = 'powershell'; Probe = @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', '$PSVersionTable.PSVersion.ToString()')
       Pre = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')
       Paths = @(Get-WindowsPath $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') }
)
if (-not $script:IsCore) { [array]::Reverse($powerShellOrder) }
$gccPaths = @(@(
    (Get-WindowsPath 'C:\' 'msys64\ucrt64\bin\{0}.exe'), (Get-WindowsPath 'C:\' 'msys64\mingw64\bin\{0}.exe'),
    (Get-WindowsPath 'C:\' 'msys64\clang64\bin\{0}.exe'), (Get-WindowsPath 'C:\' 'MinGW\bin\{0}.exe'),
    (Get-WindowsPath 'C:\' 'TDM-GCC-64\bin\{0}.exe'), (Get-WindowsPath 'C:\' 'mingw64\bin\{0}.exe')
) | Where-Object { $_ })
$cStaticFlags = if ($script:OnWindows) { @('-static') } else { @() }
$mathFlag = if ($script:OnWindows) { @() } else { @('-lm') }

$cGcc = { param($t, $c)
    New-Step build $t.Path $c.Source '-o' $c.Exe $script:cStaticFlags $c.BuildArgs $script:mathFlag
    New-Step run $c.Exe $c.Args }
$cMsvc = { param($t, $c)
    $flags = @('/nologo', '/utf-8', '/W3')
    if ($c.Language.Id -eq 'cpp') { $flags += '/EHsc' }
    Set-StepDirectory (New-Step build $t.Path $flags $c.BuildArgs $c.Source ('/Fe:' + $c.Exe) ('/Fo:' + $c.BuildDir + '\')) $c.BuildDir
    New-Step run $c.Exe $c.Args }
$cppGcc = { param($t, $c)
    New-Step build $t.Path $c.Source '-o' $c.Exe $script:cStaticFlags $c.BuildArgs
    New-Step run $c.Exe $c.Args }
$compileSimple = { param($t, $c)
    # <compiler> -o <exe> <source>
    New-Step build $t.Path '-o' $c.Exe $c.BuildArgs $c.Source
    New-Step run $c.Exe $c.Args }

$script:Languages = @(
    @{ Id = 'python'; Name = 'Python'; Ext = @('.py', '.pyw', '.pyz'); Alias = @('py', 'python3')
       Shebang = @('python', 'python3', 'python2', 'pypy', 'pypy3')
       Tools = @(
           @{ Name = 'py'; Os = 'windows'; Exe = 'py'; Probe = @('-3', '-c', $pythonProbe); Pre = @('-3') }
           @{ Name = 'python3'; Exe = 'python3'; Probe = @('-c', $pythonProbe) }
           @{ Name = 'python'; Exe = 'python'; Probe = @('-c', $pythonProbe)
              Paths = @((Get-WindowsPath $localAppData 'Programs\Python\Python3*\python.exe'), (Get-WindowsPath $programFiles 'Python3*\python.exe')) }
           @{ Name = 'pypy3'; Exe = 'pypy3'; Probe = @('-c', $pythonProbe) })
       Install = @{ windows = 'winget install -e --id Python.Python.3.13'; mac = 'brew install python'; linux = 'sudo apt install python3' } }

    @{ Id = 'javascript'; Name = 'JavaScript (Node.js)'; Ext = @('.js', '.mjs', '.cjs'); Alias = @('js', 'node', 'nodejs')
       Shebang = @('node', 'nodejs')
       Tools = @(
           @{ Name = 'node'; Exe = 'node'; Probe = @('--version'); Paths = @(Get-WindowsPath $programFiles 'nodejs\node.exe') }
           @{ Name = 'bun'; Exe = 'bun'; Probe = @('--version') }
           @{ Name = 'deno'; Exe = 'deno'; Probe = @('--version'); Pre = @('run', '-A') })
       Install = @{ windows = 'winget install -e --id OpenJS.NodeJS.LTS'; mac = 'brew install node'; linux = 'sudo apt install nodejs' } }

    @{ Id = 'typescript'; Name = 'TypeScript'; Ext = @('.ts', '.mts', '.cts'); Alias = @('ts')
       Shebang = @('ts-node', 'tsx', 'deno', 'bun')
       Tools = @(
           @{ Name = 'tsx'; Exe = 'tsx'; Probe = @('--version') }
           @{ Name = 'bun'; Exe = 'bun'; Probe = @('--version') }
           @{ Name = 'deno'; Exe = 'deno'; Probe = @('--version'); Pre = @('run', '-A') }
           @{ Name = 'ts-node'; Exe = 'ts-node'; Probe = @('--version') }
           @{ Name = 'node'; Exe = 'node'; Probe = @('--version'); Pre = @('--experimental-strip-types', '--no-warnings')
              Accept = { param($v) $n = Get-VersionNumber $v; ($null -ne $n) -and $n -ge [version]'22.6.0' } })
       Install = @{ windows = 'winget install -e --id OpenJS.NodeJS.LTS; then: npm install -g tsx'; mac = 'brew install node; npm install -g tsx'; linux = 'install Node.js 22+, then: npm install -g tsx' } }

    @{ Id = 'powershell'; Name = 'PowerShell'; Ext = @('.ps1'); Alias = @('ps1', 'pwsh', 'ps'); Shebang = @('pwsh', 'powershell')
       Tools = $powerShellOrder
       Install = @{ windows = 'built in (powershell.exe); PowerShell 7: winget install -e --id Microsoft.PowerShell'; mac = 'brew install --cask powershell'; linux = 'see https://aka.ms/install-powershell' } }

    @{ Id = 'batch'; Name = 'Batch (cmd.exe)'; Ext = @('.cmd', '.bat'); Alias = @('cmd', 'bat')
       Tools = @(@{ Name = 'cmd'; Os = 'windows'; Exe = 'cmd'; Probe = $null; Describe = 'cmd.exe'
                    Steps = { param($t, $c) New-Step run $c.Source $c.Args } })
       Install = @{ windows = 'built in'; mac = 'Windows only'; linux = 'Windows only' } }

    @{ Id = 'vbscript'; Name = 'VBScript / Windows Script Host'; Ext = @('.vbs', '.wsf'); Alias = @('vbs')
       Tools = @(@{ Name = 'cscript'; Os = 'windows'; Exe = 'cscript'; Probe = $null; Describe = 'Windows Script Host'; Pre = @('//NoLogo') })
       Install = @{ windows = 'built in (optional feature VBSCRIPT on newer Windows 11 builds)'; mac = 'Windows only'; linux = 'Windows only' } }

    @{ Id = 'bash'; Name = 'Bash / POSIX shell'; Ext = @('.sh', '.bash'); Alias = @('sh', 'shell')
       Shebang = @('bash', 'sh', 'dash', 'ksh')
       Tools = @(@{ Name = 'bash'; Exe = 'bash'; Probe = @('--version'); PosixPath = $true; Exclude = '(?i)\\(System32|WindowsApps)\\bash\.exe$'
                    Paths = @((Get-WindowsPath $programFiles 'Git\bin\bash.exe'), (Get-WindowsPath $programFilesX86 'Git\bin\bash.exe'),
                              (Get-WindowsPath $localAppData 'Programs\Git\bin\bash.exe'), (Get-WindowsPath 'C:\' 'msys64\usr\bin\bash.exe')) })
       Install = @{ windows = 'winget install -e --id Git.Git (provides Git Bash)'; mac = 'built in'; linux = 'built in' } }

    @{ Id = 'zsh'; Name = 'Zsh'; Ext = @('.zsh'); Shebang = @('zsh')
       Tools = @(@{ Name = 'zsh'; Exe = 'zsh'; Probe = @('--version'); PosixPath = $true })
       Install = @{ windows = 'install MSYS2 and its zsh package'; mac = 'built in'; linux = 'sudo apt install zsh' } }

    @{ Id = 'fish'; Name = 'Fish'; Ext = @('.fish'); Shebang = @('fish')
       Tools = @(@{ Name = 'fish'; Exe = 'fish'; Probe = @('--version'); PosixPath = $true })
       Install = @{ windows = 'install MSYS2 and its fish package'; mac = 'brew install fish'; linux = 'sudo apt install fish' } }

    @{ Id = 'c'; Name = 'C'; Ext = @('.c'); Alias = @('clang', 'gcc')
       Tools = @(
           @{ Name = 'gcc'; Exe = 'gcc'; Probe = @('--version'); Paths = @($gccPaths | ForEach-Object { $_ -f 'gcc' }); Steps = $cGcc }
           @{ Name = 'clang'; Exe = 'clang'; Probe = @('--version'); Paths = @(Get-WindowsPath $programFiles 'LLVM\bin\clang.exe'); Steps = $cGcc }
           @{ Name = 'cc'; Os = 'unix'; Exe = 'cc'; Probe = @('--version'); Steps = $cGcc }
           @{ Name = 'cl'; Os = 'windows'; Exe = 'cl'; Probe = $null; Describe = 'Microsoft C/C++ (cl.exe)'; Steps = $cMsvc })
       Install = @{ windows = 'winget install -e --id MSYS2.MSYS2, then in MSYS2 UCRT64: pacman -S mingw-w64-ucrt-x86_64-gcc'; mac = 'xcode-select --install'; linux = 'sudo apt install build-essential' } }

    @{ Id = 'cpp'; Name = 'C++'; Ext = @('.cpp', '.cc', '.cxx', '.c++', '.cp'); Alias = @('c++', 'cxx', 'g++', 'clang++')
       Tools = @(
           @{ Name = 'g++'; Exe = 'g++'; Probe = @('--version'); Paths = @($gccPaths | ForEach-Object { $_ -f 'g++' }); Steps = $cppGcc }
           @{ Name = 'clang++'; Exe = 'clang++'; Probe = @('--version'); Paths = @(Get-WindowsPath $programFiles 'LLVM\bin\clang++.exe'); Steps = $cppGcc }
           @{ Name = 'c++'; Os = 'unix'; Exe = 'c++'; Probe = @('--version'); Steps = $cppGcc }
           @{ Name = 'cl'; Os = 'windows'; Exe = 'cl'; Probe = $null; Describe = 'Microsoft C/C++ (cl.exe)'; Steps = $cMsvc })
       Install = @{ windows = 'winget install -e --id MSYS2.MSYS2, then in MSYS2 UCRT64: pacman -S mingw-w64-ucrt-x86_64-gcc'; mac = 'xcode-select --install'; linux = 'sudo apt install build-essential' } }

    @{ Id = 'csharp'; Name = 'C#'; Ext = @('.cs'); Alias = @('cs', 'c#', 'dotnet')
       Tools = @(
           @{ Name = 'dotnet'; Exe = 'dotnet'; Probe = @('--version'); Paths = @(Get-WindowsPath $programFiles 'dotnet\dotnet.exe')
              Accept = { param($v) $n = Get-VersionNumber $v; ($null -ne $n) -and $n.Major -ge 6 }
              Steps = { param($t, $c)
                  # global.json selects the SDK per folder, so ask in the folder that builds.
                  $probeDir = Split-Path -Parent $c.BuildDir
                  if (-not (Test-Path -LiteralPath $probeDir)) { $probeDir = $script:StartDirectory }
                  $sdk = Get-VersionNumber (Invoke-Captured -FilePath $t.Path -ArgumentList @('--version') -WorkingDirectory $probeDir).Output
                  if ($null -eq $sdk) { $sdk = Get-VersionNumber $t.Version }
                  $major = $sdk.Major
                  if ($major -ge 10) {
                      # .NET 10+ runs single-file apps directly, including #: directives.
                      New-Step run $t.Path 'run' '--file' $c.Source $c.BuildArgs '--' $c.Args
                  } else {
                      $project = New-DotnetProjectFile $c ('net' + $major + '.0')
                      $output = Join-Path $c.BuildDir 'out'
                      Set-StepDirectory (New-Step build $t.Path 'build' $project '-nologo' '-v:q' '-clp:NoSummary' '-o' $output $c.BuildArgs) $c.BuildDir
                      New-Step run $t.Path (Join-Path $output 'App.dll') $c.Args
                  } } }
           @{ Name = 'csc'; Os = 'windows'; Exe = 'csc'; Probe = $null; Describe = 'C# 5 compiler (.NET Framework)'
              Paths = @((Get-WindowsPath $systemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'), (Get-WindowsPath $systemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe'))
              Steps = { param($t, $c)
                  New-Step build $t.Path '/nologo' '/utf8output' '/codepage:65001' ('/out:' + $c.Exe) $c.BuildArgs $c.Source
                  New-Step run $c.Exe $c.Args } }
           @{ Name = 'mono'; Os = 'unix'; Exe = 'mcs'; Probe = @('--version')
              Steps = { param($t, $c)
                  $mono = Find-Executable -Names @('mono') -NearPath $t.Path -Purpose 'C# with mcs'
                  $assembly = Join-Path $c.BuildDir 'App.exe'
                  New-Step build $t.Path ('-out:' + $assembly) $c.BuildArgs $c.Source
                  New-Step run $mono $assembly $c.Args } })
       Install = @{ windows = 'winget install -e --id Microsoft.DotNet.SDK.10 (C# 5 also works with the built-in csc.exe)'; mac = 'brew install --cask dotnet-sdk'; linux = 'sudo apt install dotnet-sdk-8.0' } }

    @{ Id = 'fsharp'; Name = 'F# script'; Ext = @('.fsx'); Alias = @('fs', 'f#', 'fsx')
       Tools = @(@{ Name = 'dotnet fsi'; Exe = 'dotnet'; Probe = @('--version'); Pre = @('fsi', '--quiet') })
       Install = @{ windows = 'winget install -e --id Microsoft.DotNet.SDK.10'; mac = 'brew install --cask dotnet-sdk'; linux = 'sudo apt install dotnet-sdk-8.0' } }

    @{ Id = 'vbnet'; Name = 'Visual Basic .NET'; Ext = @('.vb'); Alias = @('vb')
       Tools = @(@{ Name = 'vbc'; Os = 'windows'; Exe = 'vbc'; Probe = $null; Describe = 'VB compiler (.NET Framework)'
                    Paths = @((Get-WindowsPath $systemRoot 'Microsoft.NET\Framework64\v4.0.30319\vbc.exe'), (Get-WindowsPath $systemRoot 'Microsoft.NET\Framework\v4.0.30319\vbc.exe'))
                    Steps = { param($t, $c)
                        New-Step build $t.Path '/nologo' '/utf8output' '/codepage:65001' ('/out:' + $c.Exe) $c.BuildArgs $c.Source
                        New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'built in (.NET Framework vbc.exe)'; mac = 'not supported by this runner'; linux = 'not supported by this runner' } }

    @{ Id = 'java'; Name = 'Java'; Ext = @('.java')
       Tools = @(
           @{ Name = 'javac'; Exe = 'javac'; Probe = @('-version')
              Steps = { param($t, $c)
                  $java = Find-Executable -Names @('java') -NearPath $t.Path -Purpose 'Java'
                  $classes = Join-Path $c.BuildDir 'classes'
                  New-Step build $t.Path '-encoding' 'UTF-8' '-d' $classes '-sourcepath' (Get-JavaSourceRoot $c.Source) $c.BuildArgs $c.Source
                  New-Step run $java (Get-Utf8JavaFlags $c) '-cp' $classes (Get-JavaMainClass $c.Source $c.BaseName) $c.Args } }
           @{ Name = 'java'; Exe = 'java'; Probe = @('-version')
              Accept = { param($v) $n = Get-VersionNumber $v; ($null -ne $n) -and ($n.Major -ge 11) }
              Steps = { param($t, $c) New-Step run $t.Path (Get-Utf8JavaFlags $c) $c.BuildArgs $c.Source $c.Args } })
       Install = @{ windows = 'winget install -e --id EclipseAdoptium.Temurin.21.JDK'; mac = 'brew install --cask temurin'; linux = 'sudo apt install default-jdk' } }

    @{ Id = 'jar'; Name = 'Java archive'; Ext = @('.jar')
       Tools = @(@{ Name = 'java'; Exe = 'java'; Probe = @('-version')
                    Steps = { param($t, $c) New-Step run $t.Path (Get-Utf8JavaFlags $c) '-jar' $c.Source $c.Args } })
       Install = @{ windows = 'winget install -e --id EclipseAdoptium.Temurin.21.JDK'; mac = 'brew install --cask temurin'; linux = 'sudo apt install default-jre' } }

    @{ Id = 'kotlin'; Name = 'Kotlin'; Ext = @('.kt'); Alias = @('kt')
       Tools = @(@{ Name = 'kotlinc'; Exe = 'kotlinc'; Probe = @('-version')
                    Steps = { param($t, $c)
                        $java = Find-Executable -Names @('java') -Purpose 'Kotlin'
                        $jar = Join-Path $c.BuildDir 'app.jar'
                        New-Step build $t.Path $c.Source '-include-runtime' '-d' $jar $c.BuildArgs
                        New-Step run $java (Get-Utf8JavaFlags $c) '-jar' $jar $c.Args } })
       Install = @{ windows = 'winget search Kotlin, or download the compiler from https://kotlinlang.org'; mac = 'brew install kotlin'; linux = 'sdk install kotlin (SDKMAN)' } }

    @{ Id = 'kotlinscript'; Name = 'Kotlin script'; Ext = @('.kts'); Alias = @('kts')
       Tools = @(@{ Name = 'kotlinc'; Exe = 'kotlinc'; Probe = @('-version'); Pre = @('-script') })
       Install = @{ windows = 'download the compiler from https://kotlinlang.org'; mac = 'brew install kotlin'; linux = 'sdk install kotlin (SDKMAN)' } }

    @{ Id = 'scala'; Name = 'Scala'; Ext = @('.scala', '.sc')
       Tools = @(
           @{ Name = 'scala-cli'; Exe = 'scala-cli'; Probe = @('version')
              Steps = { param($t, $c) New-Step run $t.Path 'run' $c.Source $c.BuildArgs '--' $c.Args } }
           @{ Name = 'scala'; Exe = 'scala'; Probe = @('-version')
              Steps = { param($t, $c) New-Step run $t.Path 'run' $c.Source $c.BuildArgs '--' $c.Args } })
       Install = @{ windows = 'winget search scala, or see https://www.scala-lang.org/download'; mac = 'brew install Virtuslab/scala-cli/scala-cli'; linux = 'see https://scala-cli.virtuslab.org' } }

    @{ Id = 'groovy'; Name = 'Groovy'; Ext = @('.groovy', '.gvy'); Shebang = @('groovy')
       Tools = @(@{ Name = 'groovy'; Exe = 'groovy'; Probe = @('--version') })
       Install = @{ windows = 'see https://groovy.apache.org/download.html'; mac = 'brew install groovy'; linux = 'sdk install groovy (SDKMAN)' } }

    @{ Id = 'go'; Name = 'Go'; Ext = @('.go'); Alias = @('golang')
       Tools = @(@{ Name = 'go'; Exe = 'go'; Probe = @('version'); Paths = @(Get-WindowsPath $programFiles 'Go\bin\go.exe')
                    Steps = { param($t, $c)
                        # go run would replace the program's exit code with 1, so build first.
                        Set-StepDirectory (New-Step build $t.Path 'build' '-o' $c.Exe $c.BuildArgs $c.Source) $c.SourceDir
                        New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'winget install -e --id GoLang.Go'; mac = 'brew install go'; linux = 'sudo apt install golang' } }

    @{ Id = 'rust'; Name = 'Rust'; Ext = @('.rs'); Alias = @('rs')
       Tools = @(@{ Name = 'rustc'; Exe = 'rustc'; Probe = @('--version'); Paths = @(Get-WindowsPath $env:USERPROFILE '.cargo\bin\rustc.exe')
                    Steps = { param($t, $c)
                        Set-StepDirectory (New-Step build $t.Path '--edition' '2021' '-o' $c.Exe $c.BuildArgs $c.Source) $c.BuildDir
                        New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'winget install -e --id Rustlang.Rustup (needs Visual Studio Build Tools for linking)'; mac = 'brew install rustup'; linux = 'curl https://sh.rustup.rs -sSf | sh' } }

    @{ Id = 'swift'; Name = 'Swift'; Ext = @('.swift')
       Tools = @(
           @{ Name = 'swiftc'; Exe = 'swiftc'; Probe = @('--version'); Steps = $compileSimple }
           @{ Name = 'swift'; Exe = 'swift'; Probe = @('--version') })
       Install = @{ windows = 'winget install -e --id Swift.Toolchain'; mac = 'xcode-select --install'; linux = 'see https://www.swift.org/install' } }

    @{ Id = 'dart'; Name = 'Dart'; Ext = @('.dart')
       Tools = @(@{ Name = 'dart'; Exe = 'dart'; Probe = @('--version'); Pre = @('run') })
       Install = @{ windows = 'winget search Dart, or see https://dart.dev/get-dart'; mac = 'brew install dart-sdk'; linux = 'see https://dart.dev/get-dart' } }

    @{ Id = 'ruby'; Name = 'Ruby'; Ext = @('.rb', '.rbw'); Alias = @('rb'); Shebang = @('ruby')
       Tools = @(@{ Name = 'ruby'; Exe = 'ruby'; Probe = @('--version'); Paths = @(Get-WindowsPath 'C:\' 'Ruby*\bin\ruby.exe') })
       Install = @{ windows = 'winget search RubyInstallerTeam.Ruby'; mac = 'brew install ruby'; linux = 'sudo apt install ruby' } }

    @{ Id = 'perl'; Name = 'Perl'; Ext = @('.pl', '.pm', '.t'); Shebang = @('perl')
       Tools = @(@{ Name = 'perl'; Exe = 'perl'; Probe = @('-e', 'print qq(perl $])'); PosixPath = $true
                    Paths = @((Get-WindowsPath 'C:\' 'Strawberry\perl\bin\perl.exe'), (Get-WindowsPath $programFiles 'Git\usr\bin\perl.exe')) })
       Install = @{ windows = 'winget install -e --id StrawberryPerl.StrawberryPerl'; mac = 'built in'; linux = 'built in' } }

    @{ Id = 'php'; Name = 'PHP'; Ext = @('.php'); Shebang = @('php')
       Tools = @(@{ Name = 'php'; Exe = 'php'; Probe = @('-v'); Paths = @((Get-WindowsPath 'C:\' 'php\php.exe'), (Get-WindowsPath 'C:\' 'tools\php*\php.exe')) })
       Install = @{ windows = 'winget search PHP.PHP'; mac = 'brew install php'; linux = 'sudo apt install php-cli' } }

    @{ Id = 'lua'; Name = 'Lua'; Ext = @('.lua'); Shebang = @('lua', 'luajit')
       Tools = @(@{ Name = 'lua'; Exe = @('lua', 'lua5.4', 'lua54', 'lua5.3', 'lua53', 'luajit'); Probe = @('-v') })
       Install = @{ windows = 'winget install -e --id DEVCOM.Lua'; mac = 'brew install lua'; linux = 'sudo apt install lua5.4' } }

    @{ Id = 'r'; Name = 'R'; Ext = @('.r'); Alias = @('rscript'); Shebang = @('rscript')
       Tools = @(@{ Name = 'Rscript'; Exe = 'Rscript'; Probe = @('--version'); Paths = @(Get-WindowsPath $programFiles 'R\R-*\bin\Rscript.exe') })
       Install = @{ windows = 'winget install -e --id RProject.R'; mac = 'brew install r'; linux = 'sudo apt install r-base' } }

    @{ Id = 'julia'; Name = 'Julia'; Ext = @('.jl'); Shebang = @('julia')
       Tools = @(@{ Name = 'julia'; Exe = 'julia'; Probe = @('--version'); Pre = @('--startup-file=no')
                    Paths = @(Get-WindowsPath $localAppData 'Programs\Julia*\bin\julia.exe') })
       Install = @{ windows = 'winget install -e --id Julialang.Julia'; mac = 'brew install julia'; linux = 'curl -fsSL https://install.julialang.org | sh' } }

    @{ Id = 'haskell'; Name = 'Haskell'; Ext = @('.hs', '.lhs'); Alias = @('hs'); Shebang = @('runghc', 'runhaskell', 'stack')
       Tools = @(
           @{ Name = 'runghc'; Exe = @('runghc', 'runhaskell'); Probe = @('--version') }
           @{ Name = 'ghc'; Exe = 'ghc'; Probe = @('--version')
              Steps = { param($t, $c)
                  New-Step build $t.Path '-v0' '-outputdir' $c.BuildDir '-o' $c.Exe $c.BuildArgs $c.Source
                  New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'see https://www.haskell.org/ghcup'; mac = 'brew install ghc'; linux = 'sudo apt install ghc' } }

    @{ Id = 'ocaml'; Name = 'OCaml'; Ext = @('.ml'); Shebang = @('ocaml')
       Tools = @(@{ Name = 'ocaml'; Exe = 'ocaml'; Probe = @('-version') })
       Install = @{ windows = 'see https://ocaml.org/install'; mac = 'brew install ocaml'; linux = 'sudo apt install ocaml' } }

    @{ Id = 'elixir'; Name = 'Elixir'; Ext = @('.exs', '.ex'); Shebang = @('elixir')
       Tools = @(@{ Name = 'elixir'; Exe = 'elixir'; Probe = @('--version') })
       Install = @{ windows = 'see https://elixir-lang.org/install.html'; mac = 'brew install elixir'; linux = 'sudo apt install elixir' } }

    @{ Id = 'erlang'; Name = 'Erlang (escript)'; Ext = @('.erl', '.escript'); Shebang = @('escript')
       Tools = @(@{ Name = 'escript'; Exe = 'escript'; Probe = $null; Describe = 'escript' })
       Install = @{ windows = 'winget install -e --id Erlang.ErlangOTP'; mac = 'brew install erlang'; linux = 'sudo apt install erlang' } }

    @{ Id = 'clojure'; Name = 'Clojure'; Ext = @('.clj', '.bb'); Shebang = @('bb', 'clojure')
       Tools = @(
           @{ Name = 'babashka'; Exe = 'bb'; Probe = @('--version') }
           @{ Name = 'clojure'; Exe = 'clojure'; Probe = @('--version'); Pre = @('-M') })
       Install = @{ windows = 'see https://github.com/babashka/babashka#installation'; mac = 'brew install borkdude/brew/babashka'; linux = 'see https://github.com/babashka/babashka#installation' } }

    @{ Id = 'racket'; Name = 'Racket'; Ext = @('.rkt'); Shebang = @('racket')
       Tools = @(@{ Name = 'racket'; Exe = 'racket'; Probe = @('--version'); Paths = @(Get-WindowsPath $programFiles 'Racket\Racket.exe') })
       Install = @{ windows = 'winget install -e --id Racket.Racket'; mac = 'brew install --cask racket'; linux = 'sudo apt install racket' } }

    @{ Id = 'scheme'; Name = 'Scheme'; Ext = @('.scm', '.ss'); Shebang = @('guile', 'scheme', 'csi')
       Tools = @(
           @{ Name = 'guile'; Exe = 'guile'; Probe = @('--version'); Pre = @('--no-auto-compile', '-s') }
           @{ Name = 'chez'; Exe = @('scheme', 'chezscheme'); Probe = @('--version'); Pre = @('--script') }
           @{ Name = 'chicken'; Exe = 'csi'; Probe = @('-version'); Pre = @('-s') })
       Install = @{ windows = 'see https://www.gnu.org/software/guile'; mac = 'brew install guile'; linux = 'sudo apt install guile-3.0' } }

    @{ Id = 'commonlisp'; Name = 'Common Lisp'; Ext = @('.lisp', '.lsp'); Alias = @('lisp', 'sbcl'); Shebang = @('sbcl', 'clisp')
       Tools = @(
           @{ Name = 'sbcl'; Exe = 'sbcl'; Probe = @('--version'); Pre = @('--script'); Paths = @(Get-WindowsPath $programFiles 'Steel Bank Common Lisp\sbcl.exe') }
           @{ Name = 'clisp'; Exe = 'clisp'; Probe = @('--version') })
       Install = @{ windows = 'see https://www.sbcl.org/platform-table.html'; mac = 'brew install sbcl'; linux = 'sudo apt install sbcl' } }

    @{ Id = 'tcl'; Name = 'Tcl'; Ext = @('.tcl'); Shebang = @('tclsh', 'wish')
       Tools = @(@{ Name = 'tclsh'; Exe = @('tclsh', 'tclsh9.0', 'tclsh8.6', 'tclsh86t'); Probe = $null; Describe = 'tclsh' })
       Install = @{ windows = 'see https://www.tcl-lang.org/software/tcltk'; mac = 'built in'; linux = 'sudo apt install tcl' } }

    @{ Id = 'awk'; Name = 'AWK'; Ext = @('.awk'); Shebang = @('awk', 'gawk')
       Tools = @(@{ Name = 'awk'; Exe = @('gawk', 'awk'); Probe = $null; Describe = 'awk'; Pre = @('-f'); PosixPath = $true
                    Paths = @(Get-WindowsPath $programFiles 'Git\usr\bin\awk.exe') })
       Install = @{ windows = 'winget install -e --id Git.Git (includes awk)'; mac = 'built in'; linux = 'built in' } }

    @{ Id = 'autohotkey'; Name = 'AutoHotkey'; Ext = @('.ahk'); Alias = @('ahk')
       Tools = @(@{ Name = 'AutoHotkey'; Os = 'windows'; Exe = @('AutoHotkey64', 'AutoHotkey'); Probe = $null; Describe = 'AutoHotkey'; Pre = @('/ErrorStdOut')
                    Paths = @((Get-WindowsPath $programFiles 'AutoHotkey\v2\AutoHotkey64.exe'), (Get-WindowsPath $programFiles 'AutoHotkey\AutoHotkey.exe')) })
       Install = @{ windows = 'winget install -e --id AutoHotkey.AutoHotkey'; mac = 'Windows only'; linux = 'Windows only' } }

    @{ Id = 'zig'; Name = 'Zig'; Ext = @('.zig')
       Tools = @(@{ Name = 'zig'; Exe = 'zig'; Probe = @('version')
                    Steps = { param($t, $c)
                        Set-StepDirectory (New-Step build $t.Path 'build-exe' $c.Source ('-femit-bin=' + $c.Exe) $c.BuildArgs) $c.BuildDir
                        New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'winget install -e --id zig.zig'; mac = 'brew install zig'; linux = 'see https://ziglang.org/download' } }

    @{ Id = 'nim'; Name = 'Nim'; Ext = @('.nim')
       Tools = @(@{ Name = 'nim'; Exe = 'nim'; Probe = @('--version')
                    Steps = { param($t, $c)
                        New-Step build $t.Path 'c' '--hints:off' ('--nimcache:' + (Join-Path $c.BuildDir 'cache')) ('-o:' + $c.Exe) $c.BuildArgs $c.Source
                        New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'winget install -e --id nim.nim'; mac = 'brew install nim'; linux = 'sudo apt install nim' } }

    @{ Id = 'crystal'; Name = 'Crystal'; Ext = @('.cr')
       Tools = @(@{ Name = 'crystal'; Exe = 'crystal'; Probe = @('--version')
                    Steps = { param($t, $c)
                        New-Step build $t.Path 'build' $c.Source '-o' $c.Exe $c.BuildArgs
                        New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'see https://crystal-lang.org/install'; mac = 'brew install crystal'; linux = 'see https://crystal-lang.org/install' } }

    @{ Id = 'd'; Name = 'D'; Ext = @('.d'); Alias = @('dlang')
       Tools = @(
           @{ Name = 'dmd'; Exe = 'dmd'; Probe = @('--version')
              Steps = { param($t, $c)
                  New-Step build $t.Path ('-of=' + $c.Exe) ('-od=' + $c.BuildDir) $c.BuildArgs $c.Source
                  New-Step run $c.Exe $c.Args } }
           @{ Name = 'ldc2'; Exe = 'ldc2'; Probe = @('--version')
              Steps = { param($t, $c)
                  New-Step build $t.Path ('-of=' + $c.Exe) ('-od=' + $c.BuildDir) $c.BuildArgs $c.Source
                  New-Step run $c.Exe $c.Args } }
           @{ Name = 'gdc'; Exe = 'gdc'; Probe = @('--version'); Steps = $compileSimple })
       Install = @{ windows = 'see https://dlang.org/download.html'; mac = 'brew install ldc'; linux = 'sudo apt install ldc' } }

    @{ Id = 'v'; Name = 'V'; Ext = @('.v'); Alias = @('vlang')
       Tools = @(@{ Name = 'v'; Exe = 'v'; Probe = @('version'); Steps = $compileSimple })
       Install = @{ windows = 'see https://vlang.io'; mac = 'brew install vlang'; linux = 'see https://vlang.io' } }

    @{ Id = 'fortran'; Name = 'Fortran'; Ext = @('.f90', '.f95', '.f03', '.f08', '.f', '.for', '.f77'); Alias = @('f90')
       Tools = @(
           @{ Name = 'gfortran'; Exe = 'gfortran'; Probe = @('--version'); Paths = @($gccPaths | ForEach-Object { $_ -f 'gfortran' })
              Steps = { param($t, $c)
                  Set-StepDirectory (New-Step build $t.Path $c.Source '-o' $c.Exe $script:cStaticFlags $c.BuildArgs) $c.BuildDir
                  New-Step run $c.Exe $c.Args } }
           @{ Name = 'flang'; Exe = @('flang', 'flang-new'); Probe = @('--version')
              Steps = { param($t, $c)
                  Set-StepDirectory (New-Step build $t.Path $c.Source '-o' $c.Exe $c.BuildArgs) $c.BuildDir
                  New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'MSYS2: pacman -S mingw-w64-ucrt-x86_64-gcc-fortran'; mac = 'brew install gcc'; linux = 'sudo apt install gfortran' } }

    @{ Id = 'pascal'; Name = 'Pascal'; Ext = @('.pas', '.pp', '.lpr', '.dpr')
       Tools = @(@{ Name = 'fpc'; Exe = 'fpc'; Probe = @('-iV')
                    Steps = { param($t, $c)
                        New-Step build $t.Path '-l-' '-v0' ('-FU' + $c.BuildDir) ('-o' + $c.Exe) $c.BuildArgs $c.Source
                        New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'see https://www.freepascal.org/download.html'; mac = 'brew install fpc'; linux = 'sudo apt install fpc' } }

    @{ Id = 'cobol'; Name = 'COBOL'; Ext = @('.cob', '.cbl', '.cobol'); Alias = @('cob')
       Tools = @(@{ Name = 'cobc'; Exe = 'cobc'; Probe = @('--version')
                    Steps = { param($t, $c)
                        Set-StepDirectory (New-Step build $t.Path '-x' '-o' $c.Exe $c.BuildArgs $c.Source) $c.BuildDir
                        New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'see https://gnucobol.sourceforge.io'; mac = 'brew install gnucobol'; linux = 'sudo apt install gnucobol' } }

    @{ Id = 'ada'; Name = 'Ada'; Ext = @('.adb')
       Tools = @(@{ Name = 'gnatmake'; Exe = 'gnatmake'; Probe = @('--version')
                    Steps = { param($t, $c)
                        Set-StepDirectory (New-Step build $t.Path '-q' '-D' $c.BuildDir '-o' $c.Exe $c.BuildArgs $c.Source) $c.BuildDir
                        New-Step run $c.Exe $c.Args } })
       Install = @{ windows = 'see https://alire.ada.dev'; mac = 'see https://alire.ada.dev'; linux = 'sudo apt install gnat' } }

    @{ Id = 'prolog'; Name = 'Prolog (SWI)'; Ext = @(); Alias = @('swipl'); Shebang = @('swipl')
       Tools = @(@{ Name = 'swipl'; Exe = 'swipl'; Probe = @('--version') })
       Install = @{ windows = 'winget search SWI-Prolog'; mac = 'brew install swi-prolog'; linux = 'sudo apt install swi-prolog' } }

    @{ Id = 'native'; Name = 'Windows program'; Ext = @('.exe', '.com'); Alias = @('exe')
       Tools = @(@{ Name = 'direct'; Os = 'windows'; Exe = 'cmd'; Probe = $null; Describe = 'runs the program directly'
                    Steps = { param($t, $c) New-Step run $c.Source $c.Args } })
       Install = @{ windows = 'built in'; mac = 'Windows only'; linux = 'Windows only' } }

    @{ Id = 'html'; Name = 'HTML page (opens the browser)'; Ext = @('.html', '.htm'); Alias = @('web')
       Tools = @(
           @{ Name = 'default browser'; Os = 'windows'; Exe = 'explorer'; Probe = $null; Describe = 'default browser'
              Steps = { param($t, $c) New-Step open $c.Source } }
           @{ Name = 'open'; Os = 'mac'; Exe = 'open'; Probe = $null; Describe = 'default browser'
              Steps = { param($t, $c) New-Step run $t.Path $c.Source } }
           @{ Name = 'xdg-open'; Os = 'linux'; Exe = 'xdg-open'; Probe = $null; Describe = 'default browser'
              Steps = { param($t, $c) New-Step run $t.Path $c.Source } })
       Install = @{ windows = 'built in'; mac = 'built in'; linux = 'sudo apt install xdg-utils' } }
) | ForEach-Object { Complete-LanguageDefinition $_ }

# ---------------------------------------------------------------------------
# Language and project detection
# ---------------------------------------------------------------------------

function Find-LanguageByName {
    param([string] $Name)
    $key = $Name.Trim().ToLowerInvariant().TrimStart('.')
    foreach ($language in $script:Languages) {
        if ($language.Id -eq $key) { return $language }
        if ($language.Name.ToLowerInvariant() -eq $key) { return $language }
        if (@($language.Alias) -contains $key) { return $language }
        if (@($language.Ext) -contains ('.' + $key)) { return $language }
    }
    return $null
}

function Find-LanguageByExtension {
    param([string] $Extension)
    $key = $Extension.ToLowerInvariant()
    if (-not $key) { return $null }
    foreach ($language in $script:Languages) {
        if (@($language.Ext) -contains $key) { return $language }
    }
    return $null
}

function Find-LanguageByShebang {
    param([string] $SourcePath)
    $line = ''
    $reader = New-Object System.IO.StreamReader($SourcePath, $true)
    try { $line = [string]$reader.ReadLine() } finally { $reader.Dispose() }
    if (-not $line.StartsWith('#!')) { return $null }
    $words = @($line.Substring(2).Trim() -split '\s+' | Where-Object { $_ })
    if ($words.Count -eq 0) { return $null }
    $program = Split-Path -Leaf $words[0]
    if ($program -eq 'env') {
        $rest = @($words | Select-Object -Skip 1 | Where-Object { $_ -notmatch '^-' })
        if ($rest.Count -eq 0) { return $null }
        $program = Split-Path -Leaf $rest[0]
    }
    $program = $program.ToLowerInvariant()
    $plain = $program -replace '[\d.]+$', ''
    foreach ($language in $script:Languages) {
        $names = @($language.Shebang)
        if ($names -contains $program -or $names -contains $plain) { return $language }
    }
    return $null
}

function Resolve-ProjectFolder {
    # Return @{ Language; Source; Steps-builder } for a project folder.
    param([string] $Folder)
    $cargo = Join-Path $Folder 'Cargo.toml'
    if (Test-Path -LiteralPath $cargo -PathType Leaf) {
        return @{ Kind = 'Rust project (Cargo)'; Tool = @{ Name = 'cargo'; Exe = 'cargo'; Probe = @('--version')
            Paths = @(Get-WindowsPath $env:USERPROFILE '.cargo\bin\cargo.exe')
            Steps = { param($t, $c)
                New-Step build $t.Path 'build' '--quiet' '--manifest-path' $c.Source $c.BuildArgs
                New-Step run $t.Path 'run' '--quiet' '--manifest-path' $c.Source $c.BuildArgs '--' $c.Args } }
            Source = $cargo; Install = 'https://rustup.rs' }
    }
    $goModule = Join-Path $Folder 'go.mod'
    if (Test-Path -LiteralPath $goModule -PathType Leaf) {
        return @{ Kind = 'Go module'; Tool = @{ Name = 'go'; Exe = 'go'; Probe = @('version')
            Paths = @(Get-WindowsPath $programFiles 'Go\bin\go.exe')
            Steps = { param($t, $c)
                Set-StepDirectory (New-Step build $t.Path 'build' '-o' $c.Exe $c.BuildArgs '.') $c.SourceDir
                New-Step run $c.Exe $c.Args } }
            Source = $goModule; Install = 'https://go.dev/dl' }
    }
    $projects = @(Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.csproj', '.fsproj', '.vbproj') })
    if ($projects.Count -eq 1) {
        return @{ Kind = '.NET project'; Tool = @{ Name = 'dotnet'; Exe = 'dotnet'; Probe = @('--version')
            Paths = @(Get-WindowsPath $programFiles 'dotnet\dotnet.exe')
            Steps = { param($t, $c)
                New-Step build $t.Path 'build' $c.Source '-nologo' '-v:q' '-clp:NoSummary' $c.BuildArgs
                New-Step run $t.Path 'run' '--project' $c.Source '--no-build' '--' $c.Args } }
            Source = $projects[0].FullName; Install = 'winget install -e --id Microsoft.DotNet.SDK.10' }
    }
    $package = Join-Path $Folder 'package.json'
    if (Test-Path -LiteralPath $package -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $package -Raw -Encoding UTF8 | ConvertFrom-Json
        $hasStart = ($null -ne $manifest.PSObject.Properties['scripts']) -and ($null -ne $manifest.scripts.PSObject.Properties['start'])
        $hasDependencies = $false
        foreach ($field in @('dependencies', 'devDependencies')) {
            if ($null -ne $manifest.PSObject.Properties[$field] -and @($manifest.$field.PSObject.Properties).Count -gt 0) { $hasDependencies = $true }
        }
        if ($hasDependencies -and -not (Test-Path -LiteralPath (Join-Path $Folder 'node_modules'))) {
            Write-Warn 'package.json lists dependencies but node_modules is missing; run "npm install" in the folder first.'
        }
        if ($hasStart) {
            return @{ Kind = 'Node.js project (npm start)'; Tool = @{ Name = 'npm'; Exe = 'npm'; Probe = @('--version')
                Paths = @(Get-WindowsPath $programFiles 'nodejs\npm.cmd')
                Steps = { param($t, $c) Set-StepDirectory (New-Step run $t.Path 'run' 'start' '--silent' '--' $c.Args) $c.SourceDir } }
                Source = $package; Install = 'winget install -e --id OpenJS.NodeJS.LTS' }
        }
        $main = 'index.js'
        if ($null -ne $manifest.PSObject.Properties['main'] -and $manifest.main) { $main = [string]$manifest.main }
        $mainPath = Join-Path $Folder $main
        if (Test-Path -LiteralPath $mainPath -PathType Leaf) { return @{ File = $mainPath } }
    }
    foreach ($name in @('__main__.py', 'main.py')) {
        $candidate = Join-Path $Folder $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return @{ File = $candidate } }
    }
    $files = @(Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue |
        Where-Object { $null -ne (Find-LanguageByExtension $_.Extension) -and $_.Extension -notin @('.html', '.htm') })
    foreach ($stem in @('main', 'program', 'app', 'index', 'run', 'start')) {
        $match = @($files | Where-Object { $_.BaseName -ieq $stem })
        if ($match.Count -eq 1) { return @{ File = $match[0].FullName } }
    }
    if ($files.Count -eq 1) { return @{ File = $files[0].FullName } }
    $names = (@($files | Select-Object -First 8 | ForEach-Object { $_.Name }) -join ', ')
    if (-not $names) { $names = 'none' }
    throw (New-RunnerError 64 ("Cannot decide what to run in folder '$Folder'. Recognized source files: $names. " +
        'Pass the file to run instead of the folder.'))
}

function Get-SnippetFileName {
    param([object] $Language, [string] $Code)
    switch ($Language.Id) {
        'java' {
            $class = [regex]::Match($Code, '(?m)public\s+(?:final\s+|abstract\s+)*class\s+(\w+)')
            if (-not $class.Success) { $class = [regex]::Match($Code, '(?m)\bclass\s+(\w+)') }
            if ($class.Success) { return $class.Groups[1].Value + '.java' }
            return 'Main.java'
        }
        'csharp' { return 'Program.cs' }
        'go' { return 'main.go' }
        'rust' { return 'main.rs' }
        'html' { return 'index.html' }
        'native' { throw (New-RunnerError 64 'Inline code is not supported for native programs.') }
    }
    $extensions = @($Language.Ext)
    if ($extensions.Count -eq 0) {
        $fallback = @{ prolog = '.pl' }
        if ($fallback.ContainsKey($Language.Id)) { return 'snippet' + $fallback[$Language.Id] }
        throw (New-RunnerError 64 "Inline code needs a file extension for $($Language.Name).")
    }
    return 'snippet' + $extensions[0]
}

# ---------------------------------------------------------------------------
# Output helpers for -Plan and -List
# ---------------------------------------------------------------------------

function Format-PowerShellArgument {
    param([AllowEmptyString()] [string] $Value)
    if ($Value -match '^[\w./\\:=+,@-]+$' -and $Value -notmatch '^[-@]') { return $Value }
    if ($Value -match '^-[\w.:=/-]*$') { return $Value }
    return "'" + $Value.Replace("'", "''") + "'"
}

function Format-StepCommand {
    param([object] $Step)
    $parts = @("& '" + $Step.FilePath.Replace("'", "''") + "'")
    foreach ($argument in $Step.Arguments) { $parts += (Format-PowerShellArgument $argument) }
    return ($parts -join ' ')
}

function Get-InstallHint {
    param([object] $Language)
    $hints = $Language.Install
    if ($hints -is [hashtable] -and $hints.ContainsKey($script:OsKey)) { return $hints[$script:OsKey] }
    return [string]$hints
}

function Get-ExitCodeHint {
    param([int] $Code)
    $hints = @{
        -1073741515 = 'a required DLL was not found (0xC0000135)'
        -1073741819 = 'access violation / segmentation fault (0xC0000005)'
        -1073741571 = 'stack overflow (0xC00000FD)'
        -1073741676 = 'integer division by zero (0xC0000094)'
        -1073740791 = 'stack buffer overrun or fail-fast exit (0xC0000409)'
        -1073741510 = 'stopped with Ctrl+C (0xC000013A)'
        134 = 'aborted (SIGABRT)'; 136 = 'floating point error (SIGFPE)'; 137 = 'killed (SIGKILL)'
        139 = 'segmentation fault (SIGSEGV)'; 9009 = 'command not found (cmd.exe)'
    }
    if ($hints.ContainsKey($Code)) { return ' - ' + $hints[$Code] }
    return ''
}

function Show-LanguageList {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($language in $script:Languages) {
        $tools = @($language.Tools | Where-Object { Test-ToolOs $_ })
        $status = 'missing'
        $toolName = ''
        $version = ''
        if ($tools.Count -eq 0) {
            $status = 'n/a'
        } else {
            $tool = Resolve-Tool -Language $language -Forced $null
            if ($null -ne $tool) { $status = 'ready'; $toolName = $tool.Name; $version = $tool.Version }
        }
        $extensions = (@($language.Ext) -join ' ')
        if (-not $extensions) { $extensions = '(-Language ' + $language.Id + ')' }
        $rows.Add([pscustomobject]@{ Id = $language.Id; Language = $language.Name; Extensions = $extensions
            Status = $status; Toolchain = $toolName; Version = $version; Install = (Get-InstallHint $language) })
    }
    $edition = $PSVersionTable.PSEdition
    if (-not $edition) { $edition = 'Desktop' }
    $policy = 'n/a'
    try { $policy = [string](Get-ExecutionPolicy) } catch { $null = $_ }
    $codePage = 'n/a'
    try { $codePage = [string][Console]::OutputEncoding.CodePage } catch { $null = $_ }
    $os = [Environment]::OSVersion.VersionString
    try { $os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription } catch { $null = $_ }
    Write-Output ('Code runner ' + $script:RunnerVersion + ' | PowerShell ' + $PSVersionTable.PSVersion + ' ' + $edition +
        ' | ' + $os.Trim() + ' | execution policy ' + $policy + ' | console code page ' + $codePage)
    Write-Output ''
    $columns = @('Id', 'Language', 'Status', 'Toolchain', 'Version', 'Extensions')
    $widths = @{}
    foreach ($column in $columns) {
        $widths[$column] = [Math]::Max($column.Length, (@($rows | ForEach-Object { ([string]$_.$column).Length }) | Measure-Object -Maximum).Maximum)
    }
    $widths['Version'] = [Math]::Min($widths['Version'], 40)
    $format = { param($row) ($columns | ForEach-Object {
        $text = [string]$row.$_
        if ($text.Length -gt $widths[$_]) { $text = $text.Substring(0, $widths[$_]) }
        $text.PadRight($widths[$_]) }) -join '  ' }
    $header = [pscustomobject]@{ Id = 'Id'; Language = 'Language'; Status = 'Status'; Toolchain = 'Toolchain'; Version = 'Version'; Extensions = 'Extensions' }
    Write-Output ((& $format $header).TrimEnd())
    Write-Output ((& $format ([pscustomobject]@{ Id = '--'; Language = '--------'; Status = '------'; Toolchain = '---------'; Version = '-------'; Extensions = '----------' })).TrimEnd())
    foreach ($row in $rows) { Write-Output ((& $format $row).TrimEnd()) }
    $missing = @($rows | Where-Object { $_.Status -eq 'missing' })
    $ready = @($rows | Where-Object { $_.Status -eq 'ready' })
    Write-Output ''
    Write-Output ("Ready: " + $ready.Count + ' of ' + $rows.Count + ' languages.')
    if ($missing.Count -gt 0) {
        Write-Output 'Install hints for missing languages on this OS:'
        foreach ($row in $missing) { Write-Output ('  ' + $row.Id.PadRight(13) + $row.Install) }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Invoke-Main {
    # Writes normal output to the pipeline and stores the exit code in $script:ExitResult.
    param([object[]] $RawArguments)
    $options = Read-RunnerArguments -RawArguments $RawArguments
    $script:Quiet = [bool]$options.Quiet
    if ($options.Help) {
        Write-Output (Get-UsageText)
        $script:ExitResult = 0
        return
    }
    if ($options.List) {
        Show-LanguageList
        $script:ExitResult = 0
        return
    }
    if ($null -eq $options.Path -and $null -eq $options.Code) {
        throw (New-RunnerError 64 ("Nothing to run.`n" + (Get-UsageText)))
    }
    if ($null -ne $options.Path -and $null -ne $options.Code) {
        throw (New-RunnerError 64 'Use either a file or -Code, not both.')
    }

    $language = $null
    $detectedBy = ''
    if ($options.Language) {
        $language = Find-LanguageByName $options.Language
        if ($null -eq $language) {
            throw (New-RunnerError 64 "Unknown language '$($options.Language)'. Run with -List to see supported names.")
        }
        $detectedBy = 'forced with -Language'
    }

    $context = [pscustomobject]@{
        Language = $null; Source = $null; SourceDir = $null; BaseName = 'app'; BuildDir = $null; Exe = $null
        Args = [string[]]$options.ProgramArgs.ToArray(); BuildArgs = [string[]]$options.BuildArgs.ToArray()
        WorkDir = $script:StartDirectory; NoUtf8 = [bool]$options.NoUtf8; PlanOnly = [bool]$options.Plan
    }
    $projectTool = $null
    $projectKind = $null
    $buildRoot = [Environment]::GetEnvironmentVariable('CODE_RUNNER_BUILD_ROOT')
    if (-not $buildRoot) {
        $buildRoot = [System.IO.Path]::GetTempPath()
        # Older MinGW and Fortran tools fail on non-ASCII temp paths (for example a Thai user name).
        if ($script:OnWindows -and $buildRoot -match '[^\x20-\x7E]' -and $env:ProgramData) {
            $buildRoot = Join-Path $env:ProgramData 'code-runner'
        }
    }
    $context.BuildDir = Join-Path $buildRoot ('code-runner-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
    # A fresh, unique folder: removed at exit if anything created it (unless -KeepBuild).
    $script:CreatedBuildDir = $context.BuildDir

    if ($null -ne $options.Code) {
        if ($null -eq $language) { throw (New-RunnerError 64 '-Code needs -Language, for example -Language python.') }
        $fileName = Get-SnippetFileName $language $options.Code
        $snippetDir = Join-Path $context.BuildDir 'src'
        [void](New-Item -ItemType Directory -Path $snippetDir -Force)
        $context.Source = Join-Path $snippetDir $fileName
        $text = $options.Code
        if ($language.Id -eq 'batch') { $text = ($text -replace "`r?`n", "`r`n") }
        # Windows PowerShell 5.1 reads BOM-less non-ASCII scripts in the ANSI code page.
        Write-Utf8File -Path $context.Source -Text $text -Bom:($language.Id -eq 'powershell')
        $detectedBy = 'inline code, ' + $detectedBy
    } else {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($options.Path)
        if (Test-Path -LiteralPath $fullPath -PathType Container) {
            $project = Resolve-ProjectFolder $fullPath
            if ($project.ContainsKey('File')) {
                $fullPath = $project.File
                Write-Info ('Folder entry point: ' + $fullPath)
            } else {
                $projectTool = $project.Tool
                $projectKind = $project.Kind
                $context.Source = $project.Source
                $context.SourceDir = $fullPath
                $context.WorkDir = $fullPath
                $language = Complete-LanguageDefinition @{ Id = 'project'; Name = $project.Kind; Tools = @($projectTool); Install = $project.Install }
                $projectTool = $language.Tools[0]
                $detectedBy = 'project folder'
            }
        }
        if ($null -eq $projectTool) {
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                throw (New-RunnerError 66 "File not found: $fullPath")
            }
            $context.Source = (Get-Item -LiteralPath $fullPath).FullName
            if ($null -eq $language) {
                $extension = [System.IO.Path]::GetExtension($context.Source)
                $language = Find-LanguageByExtension $extension
                if ($null -ne $language) { $detectedBy = "extension $extension" }
            }
            if ($null -eq $language) {
                $language = Find-LanguageByShebang $context.Source
                if ($null -ne $language) { $detectedBy = 'shebang line' }
            }
            if ($null -eq $language) {
                throw (New-RunnerError 64 ("Cannot tell the language of '$($context.Source)'. " +
                    'Add -Language <name> before the file (run with -List for names).'))
            }
        }
    }
    if (-not $context.SourceDir) { $context.SourceDir = Split-Path -Parent $context.Source }
    $context.Language = $language
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($context.Source)
    if ($null -ne $projectTool) { $stem = Split-Path -Leaf $context.SourceDir }
    $context.BaseName = $stem
    $safeStem = ($stem -replace '[^A-Za-z0-9_-]', '_').Trim('_')
    if (-not $safeStem) { $safeStem = 'app' }
    $context.Exe = Join-Path $context.BuildDir ($safeStem + $script:ExeSuffix)

    if ($options.WorkingDirectory) {
        $work = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($options.WorkingDirectory)
        if (-not (Test-Path -LiteralPath $work -PathType Container)) {
            throw (New-RunnerError 66 "Working directory not found: $work")
        }
        $context.WorkDir = $work
    }
    $inputPath = $null
    if ($options.InputFile) {
        $inputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($options.InputFile)
        if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
            throw (New-RunnerError 66 "Input file not found: $inputPath")
        }
    }

    $tool = Resolve-Tool -Language $language -Forced $options.Toolchain
    if ($null -eq $tool) {
        $tried = (@($language.Tools | Where-Object { Test-ToolOs $_ } | ForEach-Object { $_.Name }) -join ', ')
        if (-not $tried) { $tried = 'none for this operating system' }
        throw (New-RunnerError 69 ("No working toolchain for $($language.Name) was found (tried: $tried).`n" +
            '  Install: ' + (Get-InstallHint $language)))
    }

    $definition = $tool.Definition
    if ($definition.Steps) {
        $steps = @(& $definition.Steps $tool $context)
    } else {
        $steps = @(Get-InterpreterSteps $tool $context)
    }
    foreach ($step in $steps) {
        if (-not $step.WorkingDirectory) {
            if ($step.Phase -eq 'build') { $step.WorkingDirectory = $context.SourceDir } else { $step.WorkingDirectory = $context.WorkDir }
        }
    }
    $needsBuildDir = $null -ne ($steps | Where-Object { $_.Phase -eq 'build' } | Select-Object -First 1)

    $shellIds = @('bash', 'zsh', 'fish')
    if ($shellIds -contains $language.Id -and $null -eq $options.Code) {
        $bytes = [System.IO.File]::ReadAllBytes($context.Source)
        if ([System.Text.Encoding]::ASCII.GetString($bytes).Contains("`r`n")) {
            # Shells read CR as part of each command; run an LF copy instead of failing.
            $needsBuildDir = $true
            $copy = Join-Path (Join-Path $context.BuildDir 'lf') (Split-Path -Leaf $context.Source)
            $originalSource = Get-SourceArgument $context $definition
            $copyArgument = $copy
            if ($script:OnWindows -and $definition.PosixPath) { $copyArgument = $copy.Replace('\', '/') }
            foreach ($step in $steps) {
                for ($i = 0; $i -lt $step.Arguments.Count; $i++) {
                    if ($step.Arguments[$i] -eq $originalSource) { $step.Arguments[$i] = $copyArgument }
                }
            }
            if (-not $options.Plan) {
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force)
                $text = [System.IO.File]::ReadAllText($context.Source)
                Write-Utf8File -Path $copy -Text ($text.Replace("`r`n", "`n"))
            }
            Write-Warn 'The script has Windows (CRLF) line endings; running a converted LF copy. Save it with LF endings to avoid this.'
        }
    }

    if ($options.Plan) {
        $toolVersion = ''
        if ($tool.Version) { $toolVersion = ' (' + $tool.Version + ')' }
        Write-Output ('Source       : ' + $context.Source)
        Write-Output ('Language     : ' + $language.Name + ' - ' + $detectedBy)
        Write-Output ('Toolchain    : ' + $tool.Name + $toolVersion)
        Write-Output ('Program      : ' + $tool.Path)
        Write-Output ('Working dir  : ' + $context.WorkDir)
        if ($needsBuildDir) { Write-Output ('Build folder : ' + $context.BuildDir + ' (temporary)') }
        if ($inputPath) { Write-Output ('Stdin from   : ' + $inputPath) }
        if ($options.TimeoutSeconds -gt 0) { Write-Output ('Time limit   : ' + $options.TimeoutSeconds + ' s') }
        Write-Output 'Steps:'
        $number = 1
        foreach ($step in $steps) {
            Write-Output ('  ' + $number + '. [' + $step.Phase + '] ' + (Format-StepCommand $step))
            $number++
        }
        $script:ExitResult = 0
        return
    }

    if ($needsBuildDir -and -not (Test-Path -LiteralPath $context.BuildDir)) {
        [void](New-Item -ItemType Directory -Path $context.BuildDir -Force)
    }

    # Child processes inherit these; every change is restored in the finally block.
    $environment = @{ 'DOTNET_NOLOGO' = '1'; 'MSBUILDTERMINALLOGGER' = 'off' }
    if (-not $options.NoUtf8) {
        $environment['PYTHONIOENCODING'] = 'utf-8'
        $environment['PYTHONUTF8'] = '1'
    }
    $savedEnvironment = @{}
    foreach ($name in @($environment.Keys)) {
        $current = [Environment]::GetEnvironmentVariable($name)
        $savedEnvironment[$name] = $current
        if ($null -eq $environment[$name] -or $null -ne $current) { continue }
        [Environment]::SetEnvironmentVariable($name, $environment[$name])
    }
    $savedPath = $env:PATH
    if ($tool.FromKnownPath) {
        # A tool found outside PATH may need DLLs or helpers from its own folder.
        $env:PATH = (Split-Path -Parent $tool.Path) + [System.IO.Path]::PathSeparator + $env:PATH
    }
    $savedEncoding = $null
    if (-not $options.NoUtf8 -and $script:OnWindows) {
        try {
            $savedEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
        } catch { $savedEncoding = $null }
    }
    try {
        $versionText = ''
        if ($tool.Version) { $versionText = ' (' + $tool.Version + ')' }
        Write-Info ($language.Name + ' via ' + $tool.Name + $versionText)
        $exitCode = 0
        foreach ($step in $steps) {
            if ($step.Phase -eq 'open') {
                Write-Info ('open: ' + $step.FilePath)
                Invoke-Item -LiteralPath $step.FilePath
                continue
            }
            Write-Info ($step.Phase + ': ' + (Format-StepCommand $step))
            if ($step.Phase -eq 'build') {
                $buildCode = Invoke-Interactive -FilePath $step.FilePath -ArgumentList $step.Arguments `
                    -WorkingDirectory $step.WorkingDirectory -OutputToStderr
                if ($buildCode -ne 0) {
                    throw (New-RunnerError 65 ("Build failed: '" + (Split-Path -Leaf $step.FilePath) + "' exited with code " + $buildCode + '.'))
                }
            } else {
                $exitCode = Invoke-Interactive -FilePath $step.FilePath -ArgumentList $step.Arguments `
                    -WorkingDirectory $step.WorkingDirectory -InputFile $inputPath -TimeoutSeconds $options.TimeoutSeconds
            }
        }
        if ($exitCode -ne 0) { Write-Info ('Program exited with code ' + $exitCode + (Get-ExitCodeHint $exitCode)) }
        if ($options.KeepBuild -and (Test-Path -LiteralPath $context.BuildDir)) {
            [Console]::Error.WriteLine('[code-runner] Build folder kept: ' + $script:CreatedBuildDir)
            $script:CreatedBuildDir = $null
        }
        $script:ExitResult = $exitCode
    } finally {
        foreach ($name in @($savedEnvironment.Keys)) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
        $env:PATH = $savedPath
        if ($null -ne $savedEncoding) { try { [Console]::OutputEncoding = $savedEncoding } catch { $null = $_ } }
    }
}

function Remove-BuildDirectory {
    param([string] $Directory)
    if (-not $Directory -or -not (Test-Path -LiteralPath $Directory)) { return }
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Remove-Item -LiteralPath $Directory -Recurse -Force -ErrorAction Stop
            return
        } catch {
            # A program that was just stopped can keep its executable locked briefly.
            Start-Sleep -Milliseconds (200 * $attempt)
        }
    }
    Write-Warn "Could not remove the temporary build folder: $Directory"
}

$script:StartDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
$script:CreatedBuildDir = $null
$script:PauseAtEnd = $false

# Allow tests to dot-source the functions without running anything.
if ($MyInvocation.InvocationName -eq '.') { return }

$script:ExitResult = 70
$finalExitCode = 70
try {
    Invoke-Main -RawArguments $args
    $finalExitCode = $script:ExitResult
} catch {
    $exception = $_.Exception
    if ($null -ne $exception -and $exception.Data.Contains('RunnerExitCode')) {
        $finalExitCode = [int]$exception.Data['RunnerExitCode']
        [Console]::Error.WriteLine('[code-runner] ERROR: ' + $exception.Message)
    } else {
        $finalExitCode = 70
        [Console]::Error.WriteLine('[code-runner] INTERNAL ERROR: ' + $_.Exception.Message)
        [Console]::Error.WriteLine($_.ScriptStackTrace)
    }
} finally {
    Remove-BuildDirectory $script:CreatedBuildDir
}
if ($script:PauseAtEnd) {
    $interactive = $false
    try { $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected } catch { $interactive = $false }
    if ($interactive) {
        [Console]::Error.Write('[code-runner] Finished with exit code ' + $finalExitCode + '. Press Enter to close...')
        [void][Console]::ReadLine()
    }
}
exit $finalExitCode
