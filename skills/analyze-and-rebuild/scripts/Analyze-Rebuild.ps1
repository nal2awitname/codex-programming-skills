[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'evidence', 'attach', 'status', 'report', 'check', 'seal', 'handoff', 'observe', 'verify')]
    [string]$Action,
    [Parameter(Mandatory = $true)][string]$Work,
    [string]$Source,
    [string]$CommandFile,
    [string]$Destination,
    [switch]$Reviewed,
    [ValidateRange(0.05, 120.0)][double]$TimeoutSeconds = 10,
    [ValidateRange(1, 16777216)][int]$OutputLimit = 1048576,
    [ValidateRange(1, 2147483647)][int]$MaxFiles = 5000,
    [ValidateRange(1, 2147483647)][int]$MaxBytes = 2097152,
    [string]$EvidenceId,
    [string]$EvidenceFile,
    [int]$StartLine,
    [int]$EndLine,
    [string]$Summary,
    [string]$Artifact,
    [string]$Method
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
    $arguments += @('--source', $Source, '--max-files', $MaxFiles.ToString(), '--max-bytes', $MaxBytes.ToString())
}
if ($Action -in @('evidence', 'attach')) {
    if ([string]::IsNullOrWhiteSpace($EvidenceId) -or [string]::IsNullOrWhiteSpace($Summary)) {
        throw '-EvidenceId and -Summary are required for evidence or attach.'
    }
    $arguments += @('--id', $EvidenceId, '--summary', $Summary)
}
if ($Action -eq 'evidence') {
    if ([string]::IsNullOrWhiteSpace($EvidenceFile) -or $StartLine -lt 1 -or $EndLine -lt $StartLine) {
        throw '-EvidenceFile and a valid -StartLine/-EndLine range are required for evidence.'
    }
    $arguments += @('--file', $EvidenceFile, '--start', $StartLine.ToString(), '--end', $EndLine.ToString())
}
if ($Action -eq 'attach') {
    if ([string]::IsNullOrWhiteSpace($Artifact) -or [string]::IsNullOrWhiteSpace($Method)) {
        throw '-Artifact and -Method are required for attach.'
    }
    $arguments += @('--artifact', $Artifact, '--method', $Method)
}
if ($Action -in @('observe', 'verify')) {
    if (-not $CommandFile) { throw '-CommandFile is required.' }
    $arguments += @('--command', $CommandFile, '--timeout', $TimeoutSeconds.ToString([Globalization.CultureInfo]::InvariantCulture),
                    '--output-limit', $OutputLimit.ToString())
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
