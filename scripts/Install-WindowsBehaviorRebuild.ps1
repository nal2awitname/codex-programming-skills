[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $Destination = (Join-Path $env:USERPROFILE '.agents\skills\rebuild-windows-from-behavior')
)
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\rebuild-windows-from-behavior'
if (-not (Test-Path -LiteralPath (Join-Path $sourcePath 'SKILL.md') -PathType Leaf)) {
    throw 'Missing skill files. Run this installer from the complete repository checkout.'
}
if (Test-Path -LiteralPath $Destination) {
    throw 'Destination already exists. Back it up and choose a new destination; nothing was overwritten.'
}
if ($PSCmdlet.ShouldProcess($Destination, 'Install rebuild-windows-from-behavior skill')) {
    New-Item -ItemType Directory -Path $Destination -ErrorAction Stop | Out-Null
    try {
        Get-ChildItem -LiteralPath $sourcePath -Force | Copy-Item -Destination $Destination -Recurse -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $Destination -Recurse -Force
        throw
    }
    Write-Output "Installed rebuild-windows-from-behavior at $Destination"
}
