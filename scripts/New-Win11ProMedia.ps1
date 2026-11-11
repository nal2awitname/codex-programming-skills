#Requires -Version 5.1
#Requires -RunAsAdministrator
# Keep this script ASCII so Windows PowerShell 5.1 reads it consistently under any ANSI code page.
<#
.SYNOPSIS
Build Windows 11 installation media containing only the selected edition (Pro by default).

.DESCRIPTION
Accept an ISO or extracted setup directory and export the selected edition from install.wim/install.esd.
Create a new install.wim with one edition and optionally write autounattend.xml to select it.
No disks are formatted. With -UsbDrive, files are copied only to an already formatted, empty removable drive.

.PARAMETER Source
An .iso file or directory containing setup.exe and sources\install.wim or install.esd.

.PARAMETER WorkDir
A new or empty output directory. Allow approximately 15 GB of free space.

.PARAMETER Edition
The exact edition name reported by DISM. Defaults to "Windows 11 Pro".

.PARAMETER SkipAutounattend
Do not write autounattend.xml.

.PARAMETER Split
Split install.wim into .swm files when larger than 4 GB, as required for FAT32 media.

.PARAMETER UsbDrive
A USB drive letter such as E:. The drive must be removable and empty.

.EXAMPLE
.\New-Win11ProMedia.ps1 -Source C:\iso\Win11.iso -WorkDir C:\Win11Pro -Split

.EXAMPLE
.\New-Win11ProMedia.ps1 -Source D:\ -WorkDir C:\Win11Pro -Split -UsbDrive E:
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$WorkDir,
    [string]$Edition = 'Windows 11 Pro',
    [switch]$SkipAutounattend,
    [switch]$Split,
    [string]$UsbDrive
)

$ErrorActionPreference = 'Stop'
$limitBytes = 4GB - 1MB

function Copy-Tree([string]$From, [string]$To) {
    # robocopy uses 1..7 for successful status, unlike ordinary native commands.
    # Handle its exit code here even when PowerShell's native error policy is on.
    $PSNativeCommandUseErrorActionPreference = $false
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    # Following source junctions could copy unrelated trees or recurse indefinitely.
    robocopy $From $To /E /XJ /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit $LASTEXITCODE) from $From to $To" }
}

function Assert-NoReparsePath([string]$Path) {
    $current = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Links and reparse points are not supported: $current"
            }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

$WorkDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkDir)
Assert-NoReparsePath $WorkDir
if (Test-Path -LiteralPath $WorkDir -PathType Leaf) { throw 'WorkDir must be a directory, not a file.' }
if (Test-Path -LiteralPath $WorkDir) {
    if (Get-ChildItem -LiteralPath $WorkDir -Force | Select-Object -First 1) {
        throw "WorkDir '$WorkDir' is not empty. Choose a new directory to preserve existing files."
    }
}

# Approve the whole local operation before mounting an ISO or creating files.
# A declined confirmation must not fall through into export/delete steps.
if (-not $PSCmdlet.ShouldProcess($WorkDir, "Build installation media for '$Edition' from $Source")) { return }

# 1) Copy setup files from an ISO or directory.
$mounted = $null
$mountedByScript = $false
try {
    if ($Source -match '\.iso$') {
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "File not found: $Source" }
        $isoPath = (Resolve-Path -LiteralPath $Source).Path
        $mounted = Get-DiskImage -ImagePath $isoPath
        if (-not $mounted.Attached) {
            $mounted = Mount-DiskImage -ImagePath $isoPath -PassThru
            $mountedByScript = $true
        }
        $letter = ($mounted | Get-Volume).DriveLetter
        if (-not $letter) { throw 'The mounted ISO has no drive letter.' }
        $srcRoot = "${letter}:\"
    } else {
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Directory not found: $Source" }
        Assert-NoReparsePath $Source
        $srcRoot = (Resolve-Path -LiteralPath $Source).Path
    }
    $sourcePrefix = $srcRoot.TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    if ($WorkDir.Equals($srcRoot.TrimEnd([char[]]'\/'), [StringComparison]::OrdinalIgnoreCase) -or
        $WorkDir.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'WorkDir must be outside the source directory to prevent recursive copying.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $srcRoot 'setup.exe') -PathType Leaf)) { throw "setup.exe not found in $srcRoot" }
    Write-Host "Copying setup files from $srcRoot ..."
    Copy-Tree $srcRoot $WorkDir
} finally {
    # An ISO mounted before this run belongs to the user; do not unmount it.
    if ($mountedByScript) { Dismount-DiskImage -ImagePath $mounted.ImagePath | Out-Null }
}

# 2) Match the exact edition name, excluding variants such as Pro N or Pro Education.
$sources = Join-Path $WorkDir 'sources'
# Picking the first image would leave the other edition container on the media.
$sourceImages = @(@('install.wim', 'install.esd') |
    ForEach-Object { Join-Path $sources $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($sourceImages.Count -ne 1) { throw 'Exactly one sources\install.wim or install.esd file is required.' }
$srcImage = $sourceImages[0]

$images = Get-WindowsImage -ImagePath $srcImage
$target = @($images | Where-Object { $_.ImageName -eq $Edition })
if ($target.Count -ne 1) {
    $list = ($images | ForEach-Object { "  [$($_.ImageIndex)] $($_.ImageName)" }) -join "`n"
    throw "Expected exactly one index for '$Edition' in $srcImage`nAvailable editions:`n$list"
}
$index = @($target)[0].ImageIndex
Write-Host "Found '$Edition' at index $index"

# 3) Export the selected edition to a new WIM, then replace the copied source image.
$newWim = Join-Path $sources 'install_single.wim'
# Export-WindowsImage appends to an existing WIM instead of replacing it.
if (Test-Path -LiteralPath $newWim) { throw 'install_single.wim already exists. Refusing to append to an existing image.' }
Write-Host 'Exporting the image (this can take several minutes) ...'
Export-WindowsImage -SourceImagePath $srcImage -SourceIndex $index `
    -DestinationImagePath $newWim -CompressionType Maximum -CheckIntegrity | Out-Null

$check = @(Get-WindowsImage -ImagePath $newWim)
if ($check.Count -ne 1 -or $check[0].ImageName -ne $Edition) {
    throw "Exported image validation failed: found $($check.Count) editions."
}
$imageArchitecture = $null
if (-not $SkipAutounattend) {
    # Setup ignores settings for a different architecture; amd64 is not universal.
    $detail = Get-WindowsImage -ImagePath $newWim -Index 1
    $imageArchitecture = switch ([string]$detail.Architecture) {
        '0' { 'x86' }
        '9' { 'amd64' }
        '12' { 'arm64' }
        'x86' { 'x86' }
        'x64' { 'amd64' }
        'amd64' { 'amd64' }
        'arm64' { 'arm64' }
        default { throw "Unsupported image architecture '$($detail.Architecture)' for autounattend.xml" }
    }
}
Remove-Item -LiteralPath $srcImage -Force
$finalWim = Join-Path $sources 'install.wim'
Rename-Item -LiteralPath $newWim -NewName 'install.wim'

# 4) Split large images when FAT32 compatibility is requested.
$size = (Get-Item $finalWim).Length
Write-Host ('install.wim size: {0:N2} GB' -f ($size / 1GB))
if ($size -gt $limitBytes) {
    if ($Split) {
        Write-Host 'Splitting into install.swm files ...'
        dism.exe /Split-Image /ImageFile:"$finalWim" /SWMFile:"$(Join-Path $sources 'install.swm')" /FileSize:3800
        if ($LASTEXITCODE -ne 0) { throw "dism /Split-Image failed (exit $LASTEXITCODE)" }
        Remove-Item -LiteralPath $finalWim -Force
    } else {
        Write-Warning 'The image exceeds 4 GB and cannot fit on FAT32. Rerun with -Split or use NTFS/exFAT media.'
    }
}

# 5) The exported edition is always index 1. Do not force a Pro key on another edition.
if (-not $SkipAutounattend) {
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="$imageArchitecture"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add">
              <Key>/IMAGE/INDEX</Key>
              <Value>1</Value>
            </MetaData>
          </InstallFrom>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>
</unattend>
"@
    Set-Content -LiteralPath (Join-Path $WorkDir 'autounattend.xml') -Value $xml -Encoding UTF8 -Force
    Write-Host 'Wrote autounattend.xml. No disks are partitioned; select the installation drive during setup.'
}

# 6) Copy to the USB drive without formatting it.
if ($UsbDrive) {
    if ($UsbDrive -notmatch '^[A-Za-z]:?\\?$') { throw 'UsbDrive must be a drive letter such as E:.' }
    $dl = $UsbDrive.TrimEnd(':', '\').ToUpper()
    $vol = Get-Volume -DriveLetter $dl -ErrorAction Stop
    if ($vol.DriveType -ne 'Removable') { throw "Drive ${dl}: is not removable ($($vol.DriveType)). Refusing to copy." }
    # A failed directory listing is not evidence that the USB drive is empty.
    if (Get-ChildItem -LiteralPath "${dl}:\" -Force -ErrorAction Stop | Select-Object -First 1) {
        throw "Drive ${dl}: is not empty. Move or back up its files first; this script does not delete USB data."
    }
    if ($vol.FileSystem -eq 'FAT32' -and (Test-Path $finalWim) -and (Get-Item $finalWim).Length -gt $limitBytes) {
        throw "Drive ${dl}: is FAT32 but install.wim exceeds 4 GB. Rerun with -Split."
    }
    if ($PSCmdlet.ShouldProcess("${dl}:", 'Copy installation media')) {
        Copy-Tree $WorkDir "${dl}:\"
        Write-Host "Copied installation media to ${dl}:"
    }
}

Write-Host "Complete: $WorkDir contains only '$Edition'"
