#Requires -Version 5.1
<#
.SYNOPSIS
    Check PowerShell scripts for problems that stop them from running on other computers.

.DESCRIPTION
    Parses each script with the PowerShell parser (the script is never executed) and
    reports problems by rule:

      PS001 error    syntax error
      PS002 error    non-ASCII text without a UTF-8 BOM (Windows PowerShell 5.1 misreads it)
      PS003 error    file is not valid UTF-8
      PS101 error    syntax that needs PowerShell 7 (?:, ??, ??=, ?., ?[], &&, ||, clean)
      PS102 error    command, parameter or value that needs PowerShell 6 or 7
      PS103 error    $IsWindows/$IsLinux/$IsMacOS/$IsCoreCLR, which 5.1 does not define
      PS201 warning  alias that means something else in another PowerShell or OS (curl, ls ...)
      PS202 warning  alias; the full command name is easier to read
      PS301 warning  Invoke-Expression runs text as code
      PS302 warning  hard-coded user profile path
      PS303 warning  machine-wide execution policy change
      PS401 info     no Set-StrictMode
      PS402 info     no $ErrorActionPreference = 'Stop'
      PS403 info     external programs are called but $LASTEXITCODE is never checked

    Exit codes: 0 no errors (and no warnings with -FailOnWarning), 1 problems found,
    2 a path was not found.

.PARAMETER Path
    Script files or folders. Folders are searched recursively for .ps1 and .psm1 files.

.PARAMETER Target
    Both (default) checks that the script runs in Windows PowerShell 5.1 and PowerShell 7.
    Core skips the 5.1 compatibility rules (PS002, PS101, PS102, PS103).

.PARAMETER FailOnWarning
    Return exit code 1 for warnings too.

.PARAMETER Json
    Print the findings as JSON instead of text.

.EXAMPLE
    .\Test-PowerShellScript.ps1 .\deploy.ps1

.EXAMPLE
    .\Test-PowerShellScript.ps1 -FailOnWarning .\scripts
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Path,

    [ValidateSet('Both', 'Core')]
    [string] $Target = 'Both',

    [switch] $FailOnWarning,

    [switch] $Json
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$crossPlatformAliases = @{
    'curl' = 'Invoke-WebRequest in 5.1 but curl.exe in PowerShell 7; use Invoke-WebRequest or curl.exe'
    'wget' = 'Invoke-WebRequest in 5.1 but missing or wget in PowerShell 7; use Invoke-WebRequest'
    'ls' = 'Get-ChildItem on Windows but /bin/ls on Linux and macOS; use Get-ChildItem'
    'cat' = 'Get-Content on Windows but /bin/cat on Linux and macOS; use Get-Content'
    'cp' = 'Copy-Item on Windows but /bin/cp on Linux and macOS; use Copy-Item'
    'mv' = 'Move-Item on Windows but /bin/mv on Linux and macOS; use Move-Item'
    'rm' = 'Remove-Item on Windows but /bin/rm on Linux and macOS; use Remove-Item'
    'ps' = 'Get-Process on Windows but /bin/ps on Linux and macOS; use Get-Process'
    'kill' = 'Stop-Process on Windows but /bin/kill on Linux and macOS; use Stop-Process'
    'sort' = 'Sort-Object on Windows but /usr/bin/sort on Linux and macOS; use Sort-Object'
    'diff' = 'Compare-Object on Windows but /usr/bin/diff on Linux and macOS; use Compare-Object'
    'tee' = 'Tee-Object on Windows but /usr/bin/tee on Linux and macOS; use Tee-Object'
    'sleep' = 'Start-Sleep on Windows but /bin/sleep on Linux and macOS; use Start-Sleep'
    'man' = 'help on Windows but /usr/bin/man on Linux and macOS; use Get-Help'
    'mount' = 'New-PSDrive on Windows but /bin/mount on Linux and macOS; use New-PSDrive'
    'write' = 'Write-Output on Windows but /usr/bin/write on Linux and macOS; use Write-Output'
    'sc' = 'Set-Content in 5.1 but sc.exe (Service Control) in PowerShell 7; use Set-Content'
    'start' = 'Start-Process on Windows only; use Start-Process'
}
$readabilityAliases = @{
    '%' = 'ForEach-Object'; 'foreach' = 'ForEach-Object'; '?' = 'Where-Object'; 'where' = 'Where-Object'
    'select' = 'Select-Object'; 'gci' = 'Get-ChildItem'; 'dir' = 'Get-ChildItem'; 'gc' = 'Get-Content'
    'gi' = 'Get-Item'; 'gp' = 'Get-ItemProperty'; 'gcm' = 'Get-Command'; 'gm' = 'Get-Member'
    'iwr' = 'Invoke-WebRequest'; 'irm' = 'Invoke-RestMethod'; 'ni' = 'New-Item'; 'ri' = 'Remove-Item'
    'del' = 'Remove-Item'; 'erase' = 'Remove-Item'; 'rd' = 'Remove-Item'; 'rmdir' = 'Remove-Item'
    'copy' = 'Copy-Item'; 'cpi' = 'Copy-Item'; 'move' = 'Move-Item'; 'mi' = 'Move-Item'
    'ren' = 'Rename-Item'; 'rni' = 'Rename-Item'; 'type' = 'Get-Content'; 'echo' = 'Write-Output'
    'cls' = 'Clear-Host'; 'measure' = 'Measure-Object'; 'group' = 'Group-Object'; 'ft' = 'Format-Table'
    'fl' = 'Format-List'; 'gps' = 'Get-Process'; 'gsv' = 'Get-Service'; 'sal' = 'Set-Alias'
    'saps' = 'Start-Process'; 'spps' = 'Stop-Process'; 'sl' = 'Set-Location'; 'ac' = 'Add-Content'
    'compare' = 'Compare-Object'; 'epcsv' = 'Export-Csv'; 'ipcsv' = 'Import-Csv'; 'ogv' = 'Out-GridView'
    'gv' = 'Get-Variable'; 'sv' = 'Set-Variable'; 'nv' = 'New-Variable'; 'rv' = 'Remove-Variable'
    'h' = 'Get-History'; 'r' = 'Invoke-History'; 'gal' = 'Get-Alias'; 'icm' = 'Invoke-Command'
}
# Parameters that exist only in PowerShell 6+ (abbreviations are matched as PowerShell would).
$newParameters = @{
    'ForEach-Object' = @('Parallel', 'ThrottleLimit', 'TimeoutSeconds', 'AsJob', 'UseNewRunspace')
    'Get-Content' = @('AsByteStream'); 'Set-Content' = @('AsByteStream'); 'Add-Content' = @('AsByteStream')
    'ConvertFrom-Json' = @('AsHashtable', 'Depth', 'NoEnumerate', 'DateKind')
    'ConvertTo-Json' = @('AsArray', 'EscapeHandling', 'EnumsAsStrings')
    'Join-Path' = @('AdditionalChildPath', 'Extension')
    'Split-Path' = @('LeafBase', 'Extension')
    'Get-Date' = @('AsUTC', 'UnixTimeSeconds')
    'Invoke-WebRequest' = @('SkipCertificateCheck', 'Authentication', 'Token', 'StatusCodeVariable', 'ResponseHeadersVariable',
        'SkipHttpErrorCheck', 'SslProtocol', 'Resume', 'MaximumRetryCount', 'RetryIntervalSec', 'Form', 'HttpVersion', 'NoProxy')
    'Invoke-RestMethod' = @('SkipCertificateCheck', 'Authentication', 'Token', 'StatusCodeVariable', 'ResponseHeadersVariable',
        'SkipHttpErrorCheck', 'SslProtocol', 'Resume', 'MaximumRetryCount', 'RetryIntervalSec', 'Form', 'HttpVersion', 'NoProxy', 'FollowRelLink')
    'Select-String' = @('Raw', 'NoEmphasis', 'Culture')
    'Sort-Object' = @('Top', 'Bottom', 'Stable')
    'Select-Object' = @('SkipIndex')
    'Measure-Object' = @('AllStats', 'StandardDeviation')
    'Start-Process' = @('Environment')
    'Get-ChildItem' = @('FollowSymlink')
    'Test-Connection' = @('TargetName', 'Ping', 'Traceroute', 'TcpPort', 'MtuSize')
    'Out-File' = @(); 'Import-Module' = @('UseWindowsPowerShell'); 'Get-Item' = @(); 'Remove-Item' = @()
}
# Windows PowerShell 5.1 parameters that share a prefix with a newer one: -Leaf is not -LeafBase.
$oldParameters = @{
    'Split-Path' = @('Leaf', 'Parent', 'Qualifier', 'NoQualifier', 'Resolve', 'IsAbsolute', 'Path', 'LiteralPath', 'Credential')
    'Select-Object' = @('Skip', 'SkipLast', 'First', 'Last', 'Unique', 'Index', 'ExpandProperty', 'ExcludeProperty', 'Property', 'Wait')
    'Sort-Object' = @('Descending', 'Unique', 'CaseSensitive', 'Culture', 'Property', 'InputObject')
    'Select-String' = @('CaseSensitive', 'Context', 'Encoding', 'Exclude', 'Include', 'List', 'NotMatch', 'Quiet', 'SimpleMatch', 'AllMatches')
    'Measure-Object' = @('Average', 'Sum', 'Maximum', 'Minimum', 'Line', 'Word', 'Character', 'IgnoreWhiteSpace', 'Property')
    'Get-Date' = @('Date', 'Year', 'Month', 'Day', 'Hour', 'Minute', 'Second', 'Millisecond', 'DisplayHint', 'Format', 'UFormat')
    'Invoke-WebRequest' = @('TimeoutSec', 'Method', 'Body', 'Headers', 'InFile', 'OutFile', 'PassThru', 'Proxy', 'SessionVariable', 'WebSession', 'UseBasicParsing', 'UseDefaultCredentials', 'UserAgent', 'Uri', 'Certificate', 'CertificateThumbprint', 'ContentType', 'Credential', 'DisableKeepAlive', 'MaximumRedirection', 'TransferEncoding', 'ProxyCredential', 'ProxyUseDefaultCredentials')
    'Invoke-RestMethod' = @('TimeoutSec', 'Method', 'Body', 'Headers', 'InFile', 'OutFile', 'PassThru', 'Proxy', 'SessionVariable', 'WebSession', 'UseBasicParsing', 'UseDefaultCredentials', 'UserAgent', 'Uri', 'Certificate', 'CertificateThumbprint', 'ContentType', 'Credential', 'DisableKeepAlive', 'MaximumRedirection', 'TransferEncoding', 'ProxyCredential', 'ProxyUseDefaultCredentials')
}
$newCommands = @('Test-Json', 'Get-Error', 'Join-String', 'ConvertFrom-Markdown', 'Show-Markdown', 'Get-MarkdownOption',
    'Set-MarkdownOption', 'Remove-Alias', 'Remove-Service', 'Get-Uptime', 'ConvertTo-CliXml', 'ConvertFrom-CliXml',
    'Get-SecureRandom', 'Get-PSSubsystem', 'Enable-ExperimentalFeature', 'Disable-ExperimentalFeature', 'Get-ExperimentalFeature')
$newEncodings = @('utf8NoBOM', 'utf8BOM', 'ansi')
$nativeTools = @('git', 'npm', 'npx', 'node', 'python', 'python3', 'py', 'pip', 'pip3', 'dotnet', 'cargo', 'rustc', 'go', 'java',
    'javac', 'gcc', 'g++', 'clang', 'cmake', 'make', 'msbuild', 'winget', 'choco', 'scoop', 'docker', 'kubectl', 'robocopy',
    'xcopy', 'reg', 'sc.exe', 'netsh', 'dism', 'bcdedit', 'icacls', 'takeown', 'schtasks', 'msiexec', 'curl.exe', 'tar', 'ssh', 'az', 'gh')

function Add-Finding {
    param([string] $File, [int] $Line, [int] $Column, [string] $Severity, [string] $Rule, [string] $Message)
    $script:Findings.Add([pscustomobject]@{
        File = $File; Line = $Line; Column = $Column; Severity = $Severity; Rule = $Rule; Message = $Message
    })
}

function Test-ParameterMatch {
    param([string] $Given, [string[]] $Names, [string[]] $OldNames)
    foreach ($old in @($OldNames)) {
        if ($old -and $old.StartsWith($Given, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    }
    foreach ($name in $Names) {
        if ($name.StartsWith($Given, [StringComparison]::OrdinalIgnoreCase) -and $Given.Length -ge 2) { return $name }
    }
    return $null
}

function Read-ScriptText {
    # Decode like the checker's target engines do and report encoding hazards.
    param([string] $File)
    $bytes = [System.IO.File]::ReadAllBytes($File)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $isUnicodeBom = $bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))
    if ($isUnicodeBom) { return [System.IO.File]::ReadAllText($File) }
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    $offset = 0
    if ($hasBom) { $offset = 3 }
    try {
        $text = $strict.GetString($bytes, $offset, $bytes.Length - $offset)
    } catch {
        Add-Finding $File 1 1 'error' 'PS003' 'The file is not valid UTF-8. Save it as UTF-8 with BOM.'
        return [System.Text.Encoding]::Default.GetString($bytes)
    }
    if (-not $hasBom -and $Target -eq 'Both') {
        $lineNumber = 0
        foreach ($line in ($text -split "`n")) {
            $lineNumber++
            $match = [regex]::Match($line, '[^\x00-\x7F]')
            if ($match.Success) {
                Add-Finding $File $lineNumber ($match.Index + 1) 'error' 'PS002' ('Non-ASCII text without a UTF-8 BOM: Windows PowerShell 5.1 ' +
                    'reads it in the ANSI code page. Save the file as "UTF-8 with BOM" or keep it ASCII.')
                break
            }
        }
    }
    return $text
}

function Test-ScriptFile {
    param([string] $File)
    $text = Read-ScriptText $File
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, $File, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        if ($null -eq $parseError) { continue }
        Add-Finding $File $parseError.Extent.StartLineNumber $parseError.Extent.StartColumnNumber 'error' 'PS001' $parseError.Message
    }
    $compat = $Target -eq 'Both'
    $hasStrictMode = $false
    $hasStop = $false
    $checksExitCode = $false
    $firstNative = $null
    $nodes = $ast.FindAll({ param($node) $true }, $true)
    foreach ($node in $nodes) {
        $line = $node.Extent.StartLineNumber
        $column = $node.Extent.StartColumnNumber
        $typeName = $node.GetType().Name
        if ($compat) {
            switch ($typeName) {
                'TernaryExpressionAst' { Add-Finding $File $line $column 'error' 'PS101' 'The ?: operator needs PowerShell 7; use if/else.' }
                'PipelineChainAst' { Add-Finding $File $line $column 'error' 'PS101' '&& and || need PowerShell 7; use if ($LASTEXITCODE -eq 0) or try/catch.' }
                'BinaryExpressionAst' {
                    if ($node.Operator.ToString() -eq 'QuestionQuestion') {
                        Add-Finding $File $line $column 'error' 'PS101' 'The ?? operator needs PowerShell 7; use if ($null -eq $x).'
                    }
                }
                'AssignmentStatementAst' {
                    if ($node.Operator.ToString() -eq 'QuestionQuestionEquals') {
                        Add-Finding $File $line $column 'error' 'PS101' 'The ??= operator needs PowerShell 7.'
                    }
                }
                'ScriptBlockAst' {
                    $clean = $node.PSObject.Properties['CleanBlock']
                    if ($null -ne $clean -and $null -ne $clean.Value) {
                        Add-Finding $File $line $column 'error' 'PS101' 'The clean block needs PowerShell 7.3; use try/finally.'
                    }
                }
            }
            if ($typeName -in @('MemberExpressionAst', 'InvokeMemberExpressionAst', 'IndexExpressionAst')) {
                $nullConditional = $node.PSObject.Properties['NullConditional']
                if ($null -ne $nullConditional -and $nullConditional.Value) {
                    Add-Finding $File $line $column 'error' 'PS101' 'Null-conditional ?. and ?[] need PowerShell 7.'
                }
            }
        }
        if ($typeName -eq 'VariableExpressionAst') {
            $name = $node.VariablePath.UserPath
            if ($name -eq 'LASTEXITCODE') { $checksExitCode = $true }
            if ($compat -and $name -in @('IsWindows', 'IsLinux', 'IsMacOS', 'IsCoreCLR')) {
                $parent = $node.Parent
                $isAssignment = $parent -is [System.Management.Automation.Language.AssignmentStatementAst] -and $parent.Left -eq $node
                if (-not $isAssignment) {
                    Add-Finding $File $line $column 'error' 'PS103' ('$' + $name + ' does not exist in Windows PowerShell 5.1 (and fails under ' +
                        "strict mode). Use [System.IO.Path]::DirectorySeparatorChar -eq '\' to detect Windows.")
                }
            }
        }
        if ($typeName -eq 'AssignmentStatementAst') {
            $left = $node.Left
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $left.VariablePath.UserPath -eq 'ErrorActionPreference' -and $node.Right.Extent.Text -match 'Stop') {
                $hasStop = $true
            }
        }
        if ($typeName -eq 'StringConstantExpressionAst' -or $typeName -eq 'ExpandableStringExpressionAst') {
            if ($node.Extent.Text -match '(?i)[a-z]:\\Users\\(?!Public\\|Default\\|\$|%)[^\\''"]+\\') {
                Add-Finding $File $line $column 'warning' 'PS302' 'Hard-coded user folder; use $env:USERPROFILE, $HOME or [Environment]::GetFolderPath().'
            }
        }
        if ($typeName -ne 'CommandAst') { continue }

        $commandName = $node.GetCommandName()
        if (-not $commandName) { continue }
        $lower = $commandName.ToLowerInvariant()
        if ($lower -eq 'set-strictmode') { $hasStrictMode = $true }
        if ($crossPlatformAliases.ContainsKey($lower)) {
            Add-Finding $File $line $column 'warning' 'PS201' ("'" + $commandName + "' is " + $crossPlatformAliases[$lower] + '.')
        } elseif ($readabilityAliases.ContainsKey($lower)) {
            Add-Finding $File $line $column 'warning' 'PS202' ("Alias '" + $commandName + "'; write " + $readabilityAliases[$lower] + '.')
        }
        if ($lower -in @('invoke-expression', 'iex')) {
            Add-Finding $File $line $column 'warning' 'PS301' 'Invoke-Expression runs text as code; call commands directly with & and an argument array.'
        }
        if ($lower -eq 'set-executionpolicy') {
            $scopeText = ''
            for ($i = 0; $i -lt $node.CommandElements.Count; $i++) {
                $element = $node.CommandElements[$i]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -match '^(?i)sc') {
                    if ($null -ne $element.Argument) { $scopeText = $element.Argument.Extent.Text }
                    elseif ($i + 1 -lt $node.CommandElements.Count) { $scopeText = $node.CommandElements[$i + 1].Extent.Text }
                }
            }
            if ($scopeText -notmatch '(?i)Process|CurrentUser') {
                Add-Finding $File $line $column 'warning' 'PS303' ('Changes the machine-wide execution policy (needs admin). Prefer ' +
                    '"-ExecutionPolicy Bypass" on the command line or -Scope Process.')
            }
        }
        if ($nativeTools -contains $lower -or $lower -match '\.(exe|cmd|bat|com)$') {
            if ($null -eq $firstNative) { $firstNative = $node }
        }
        if (-not $compat) { continue }
        if ($newCommands -contains $commandName) {
            Add-Finding $File $line $column 'error' 'PS102' ("'" + $commandName + "' does not exist in Windows PowerShell 5.1.")
        }
        $canonical = $commandName
        if ($readabilityAliases.ContainsKey($lower)) { $canonical = $readabilityAliases[$lower] }
        $positional = 0
        $elements = $node.CommandElements
        for ($i = 1; $i -lt $elements.Count; $i++) {
            $element = $elements[$i]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                $known = $null
                foreach ($key in $newParameters.Keys) {
                    if ($key -ieq $canonical) {
                        $old = @()
                        if ($oldParameters.ContainsKey($key)) { $old = $oldParameters[$key] }
                        $known = Test-ParameterMatch $element.ParameterName $newParameters[$key] $old
                    }
                }
                if ($known) {
                    Add-Finding $File $element.Extent.StartLineNumber $element.Extent.StartColumnNumber 'error' 'PS102' (
                        "$canonical -$known needs PowerShell 6 or 7.")
                }
                if ($element.ParameterName -match '^(?i)enc') {
                    $value = $null
                    if ($null -ne $element.Argument) { $value = $element.Argument.Extent.Text }
                    elseif ($i + 1 -lt $elements.Count) { $value = $elements[$i + 1].Extent.Text }
                    if ($value -and ($newEncodings -contains $value.Trim("'", '"'))) {
                        Add-Finding $File $element.Extent.StartLineNumber $element.Extent.StartColumnNumber 'error' 'PS102' (
                            "-Encoding $value needs PowerShell 6 or 7. For BOM-less UTF-8 in both, use " +
                            '[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false)).')
                    }
                }
                if ($null -eq $element.Argument -and $i + 1 -lt $elements.Count -and
                    $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                    # Assume a named parameter consumes the next element unless it is a known switch.
                    if ($element.ParameterName -notmatch '^(?i)(Force|Recurse|Raw|Resolve|IsValid|NoNewline|PassThru|Wait|AsByteStream|Leaf|Parent|Qualifier|NoQualifier)$') { $i++ }
                }
            } else {
                $positional++
            }
        }
        if ($canonical -ieq 'Join-Path' -and $positional -gt 2) {
            Add-Finding $File $line $column 'error' 'PS102' 'Join-Path with more than two path parts needs PowerShell 6 or 7; nest Join-Path calls.'
        }
    }
    if (-not $hasStrictMode) { Add-Finding $File 1 1 'info' 'PS401' 'Add Set-StrictMode -Version 3.0 to catch typos in variable names.' }
    if (-not $hasStop) { Add-Finding $File 1 1 'info' 'PS402' "Add `$ErrorActionPreference = 'Stop' so failures stop the script." }
    if ($null -ne $firstNative -and -not $checksExitCode) {
        Add-Finding $File $firstNative.Extent.StartLineNumber $firstNative.Extent.StartColumnNumber 'info' 'PS403' (
            'External programs do not throw on failure; check $LASTEXITCODE after calls such as ' + $firstNative.GetCommandName() + '.')
    }
}

$script:Findings = New-Object System.Collections.Generic.List[object]
$files = New-Object System.Collections.Generic.List[string]
$missing = $false
foreach ($item in $Path) {
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($item)
    if (Test-Path -LiteralPath $full -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $full -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') } | Sort-Object FullName)) {
            $files.Add($file.FullName)
        }
    } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
        $files.Add((Get-Item -LiteralPath $full).FullName)
    } else {
        [Console]::Error.WriteLine("Path not found: $full")
        $missing = $true
    }
}
foreach ($file in $files) { Test-ScriptFile $file }

$errors = @($script:Findings | Where-Object { $_.Severity -eq 'error' }).Count
$warnings = @($script:Findings | Where-Object { $_.Severity -eq 'warning' }).Count
$infos = @($script:Findings | Where-Object { $_.Severity -eq 'info' }).Count
if ($Json) {
    # ToArray(): wrapping a generic List in @() inside a hashtable literal fails in some PowerShell versions.
    $report = [pscustomobject]@{ Files = $files.Count; Errors = $errors; Warnings = $warnings; Info = $infos
                                 Findings = [object[]]$script:Findings.ToArray() }
    Write-Output ($report | ConvertTo-Json -Depth 4)
} else {
    foreach ($finding in $script:Findings) {
        Write-Output ('{0}:{1}:{2}: {3} {4} {5}' -f $finding.File, $finding.Line, $finding.Column, $finding.Severity, $finding.Rule, $finding.Message)
    }
    Write-Output ("Checked $($files.Count) file(s): $errors error(s), $warnings warning(s), $infos info.")
}
if ($missing) { exit 2 }
if ($errors -gt 0 -or ($FailOnWarning -and $warnings -gt 0)) { exit 1 }
exit 0
