[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'status', 'report', 'check', 'seal', 'handoff', 'observe', 'verify')]
    [string]$Action,
    [Parameter(Mandatory = $true)][string]$Work,
    [string]$Source,
    [string]$CommandFile,
    [string]$Destination,
    [switch]$Reviewed,
    [double]$TimeoutSeconds = 10
)
$ErrorActionPreference = 'Stop'
$pythonCommand = $null
$prefix = @()
foreach ($candidate in @('py', 'python', 'python3')) {
    $found = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue
    if ($found) {
        $probePrefix = @()
        if ($candidate -eq 'py') { $probePrefix = @('-3') }
        try {
            & $found.Source @probePrefix -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null
        } catch { continue }
        if ($LASTEXITCODE -eq 0) {
            $pythonCommand = $found.Source
            $prefix = $probePrefix
            break
        }
    }
}
if (-not $pythonCommand) { throw 'Python 3.10 or newer is required.' }
$arguments = @((Join-Path $PSScriptRoot 'arb.py'), $Action, '--work', $Work)
if ($Action -eq 'init') {
    if (-not $Source) { throw '-Source is required for init.' }
    $arguments += @('--source', $Source)
}
if ($Action -in @('observe', 'verify')) {
    if (-not $CommandFile) { throw '-CommandFile is required.' }
    $arguments += @('--command', $CommandFile, '--timeout', $TimeoutSeconds.ToString([Globalization.CultureInfo]::InvariantCulture))
}
if ($Action -eq 'handoff') {
    if (-not $Destination) { throw '-Destination is required.' }
    $arguments += @('--destination', $Destination)
}
if ($Action -eq 'seal' -and $Reviewed) { $arguments += '--reviewed' }
if ($PSCmdlet.ShouldProcess($Work, ('Analyze-Rebuild ' + $Action))) {
    & $pythonCommand @prefix @arguments
    exit $LASTEXITCODE
}
