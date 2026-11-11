# Unit checks for argument quoting and runner option parsing; prints PASS/FAIL lines.
param([Parameter(Mandatory = $true)] [string] $RunnerPath)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
. $RunnerPath

$failures = 0
function Assert-Equal {
    param([string] $Name, [object] $Expected, [object] $Actual)
    $expectedText = (@($Expected) | ForEach-Object { '<' + $_ + '>' }) -join ' '
    $actualText = (@($Actual) | ForEach-Object { '<' + $_ + '>' }) -join ' '
    if ($expectedText -ceq $actualText) {
        Write-Output "PASS $Name"
    } else {
        Write-Output "FAIL $Name expected $expectedText but got $actualText"
        $script:failures++
    }
}

# Expected strings follow the MSVC runtime / CommandLineToArgvW parsing rules.
$vectors = @(
    @('abc', 'abc'), @('', '""'), @('a b', '"a b"'), @('a"b', '"a\"b"'), @('a\b', 'a\b'),
    @('a\ b', '"a\ b"'), @('a b\', '"a b\\"'), @('a\"b', '"a\\\"b"'), @('a\\"b c', '"a\\\\\"b c"'),
    @("tab`there", "`"tab`there`""), @('C:\Program Files\x\', '"C:\Program Files\x\\"')
)
foreach ($vector in $vectors) {
    Assert-Equal ('windows-quote ' + $vector[0]) $vector[1] (ConvertTo-WindowsArgument $vector[0])
}

Assert-Equal 'cmd-quote plain' 'abc' (ConvertTo-CmdArgument 'abc')
Assert-Equal 'cmd-quote metacharacters' '"a&b|c"' (ConvertTo-CmdArgument 'a&b|c')
Assert-Equal 'cmd-quote trailing backslash' '"C:\a b\\"' (ConvertTo-CmdArgument 'C:\a b\')
foreach ($unsafe in @('50%', 'say "hi"', "two`nlines")) {
    $code = 0
    try { [void](ConvertTo-CmdArgument $unsafe) } catch { $code = $_.Exception.Data['RunnerExitCode'] }
    Assert-Equal ('cmd-quote refuses ' + $unsafe.Replace("`n", '\n')) 64 $code
}

$parsed = Read-RunnerArguments @('-Plan', 'x.py', '-v', '', '-Quiet')
Assert-Equal 'parse plan flag' $true $parsed.Plan
Assert-Equal 'parse path' 'x.py' $parsed.Path
Assert-Equal 'parse program args stay untouched' @('-v', '', '-Quiet') $parsed.ProgramArgs.ToArray()
Assert-Equal 'parse quiet not taken from program args' $false $parsed.Quiet

$parsed = Read-RunnerArguments @('-Language', 'py', '-Code', 'print(1)', '-q', '--', 'a')
Assert-Equal 'parse code mode program args' @('-q', '--', 'a') $parsed.ProgramArgs.ToArray()
$parsed = Read-RunnerArguments @('-Language:', 'py', '-Code', 'x', '--', '-Plan')
Assert-Equal 'parse colon option and double dash' @('py', $false) @($parsed.Language, $parsed.Plan)
Assert-Equal 'parse double dash ends options' @('-Plan') $parsed.ProgramArgs.ToArray()
$parsed = Read-RunnerArguments @('-BuildArg', '-O2', '-BuildArg', '-Wall', '-TimeoutSeconds', '5', 'a.c', '-n:', '3')
Assert-Equal 'parse repeated build args' @('-O2', '-Wall') $parsed.BuildArgs.ToArray()
Assert-Equal 'parse timeout' 5 $parsed.TimeoutSeconds
Assert-Equal 'parse rejoins split colon argument' @('-n:3') $parsed.ProgramArgs.ToArray()
$parsed = Read-RunnerArguments @('app.py', 1.5, @('x', 'y'))
Assert-Equal 'parse flattens in-process values' @('1.5', 'x', 'y') $parsed.ProgramArgs.ToArray()
foreach ($bad in @(@('-Bogus', 'x.py'), @('-TimeoutSeconds', 'soon', 'x.py'), @('-Language'))) {
    $code = 0
    try { [void](Read-RunnerArguments $bad) } catch { $code = $_.Exception.Data['RunnerExitCode'] }
    Assert-Equal ('parse rejects ' + ($bad -join ' ')) 64 $code
}

Assert-Equal 'language by alias' 'cpp' (Find-LanguageByName 'c++').Id
Assert-Equal 'language by extension name' 'typescript' (Find-LanguageByName '.ts').Id
Assert-Equal 'language by extension' 'csharp' (Find-LanguageByExtension '.CS').Id
Assert-Equal 'unknown extension' $true ($null -eq (Find-LanguageByExtension '.nothing'))
Assert-Equal 'every language has tools and install hints' 0 (@($script:Languages | Where-Object {
    @($_.Tools).Count -eq 0 -or $null -eq $_.Install }).Count)
$ids = @($script:Languages | ForEach-Object { $_.Id })
Assert-Equal 'language ids are unique' $ids.Count (@($ids | Select-Object -Unique).Count)
$extensions = @($script:Languages | ForEach-Object { @($_.Ext) })
Assert-Equal 'extensions are unique' $extensions.Count (@($extensions | Select-Object -Unique).Count)

if ($failures -gt 0) {
    Write-Output "$failures check(s) failed"
    exit 1
}
Write-Output 'ALL PASS'
exit 0
