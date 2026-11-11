#Requires -Version 5.1
<#
.SYNOPSIS
    One line that says what the script does.

.DESCRIPTION
    What it reads, what it changes and what it needs. Runs unchanged in Windows
    PowerShell 5.1 and PowerShell 7+ on any Windows computer.

.PARAMETER InputPath
    File to process.

.PARAMETER OutputPath
    Where to write the result. Default: next to the input, with the extension .out.txt.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Script-Template.ps1 -InputPath .\data.txt

.EXAMPLE
    .\Script-Template.ps1 -InputPath .\data.txt -WhatIf

.NOTES
    Exit codes: 0 success, 1 failure (the reason is written to standard error).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $InputPath,

    [string] $OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    # Relative to the PowerShell location, which .NET methods do not know about.
    param([string] $Path)
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Invoke-Native {
    # Run an external program and stop if it fails; PowerShell does not do that on its own.
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [string[]] $ArgumentList = @()
    )
    # In Windows PowerShell 5.1 native stderr can become a terminating error under 'Stop'.
    $ErrorActionPreference = 'Continue'
    & $FilePath @ArgumentList
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "'$FilePath' failed with exit code $code." }
}

function Write-Utf8Text {
    # The same bytes in 5.1 and 7: UTF-8 without a byte order mark.
    param([string] $Path, [string] $Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

try {
    $source = Resolve-FullPath $InputPath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Input file not found: $source" }
    if (-not $OutputPath) { $OutputPath = [System.IO.Path]::ChangeExtension($source, '.out.txt') }
    $target = Resolve-FullPath $OutputPath

    $text = [System.IO.File]::ReadAllText($source)
    $result = $text.ToUpperInvariant()

    if ($PSCmdlet.ShouldProcess($target, 'Write the result')) {
        Write-Utf8Text -Path $target -Text $result
        Write-Host "Wrote $target"
    }
    exit 0
} catch {
    [Console]::Error.WriteLine('ERROR: ' + $_.Exception.Message)
    exit 1
}
