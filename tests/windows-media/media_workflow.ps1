param([Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)][string]$Scenario)
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('media-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
# macOS exposes its temporary directory through /var -> /private/var. Keep
# fixtures on the physical path so production reparse checks still run intact.
if ([IO.Path]::DirectorySeparatorChar -eq '/') {
    Push-Location -LiteralPath $testRoot
    try {
        $physicalRoot = & /bin/pwd -P
        if ($LASTEXITCODE -ne 0 -or -not $physicalRoot) { throw 'Cannot resolve physical fixture path' }
        $testRoot = [string]$physicalRoot
    } finally {
        Pop-Location
    }
}
$source = Join-Path $testRoot 'source'
$output = Join-Path $testRoot 'output'
New-Item -ItemType Directory -Path (Join-Path $source 'sources') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $source 'setup.exe') -Value 'fixture'
Set-Content -LiteralPath (Join-Path $source 'sources/install.esd') -Value 'original fixture'

# Keep the actual production body; the Windows administrator requirement is
# inapplicable to mocked platform commands and the Linux test runner.
$testScript = Join-Path $testRoot 'under-test.ps1'
$body = (Get-Content -LiteralPath $ScriptPath -Raw) -replace '(?m)^#Requires -RunAsAdministrator\r?\n', ''
Set-Content -LiteralPath $testScript -Value $body -Encoding UTF8
$global:mediaTest = [pscustomobject]@{
    copies = 0; exports = 0; mounts = 0; dismounts = 0; diskReads = 0
    edition = 'Windows 11 Enterprise'; architecture = 12
}
function robocopy($From, $To) {
    $global:mediaTest.copies++
    Get-ChildItem -LiteralPath $From -Force | Copy-Item -Destination $To -Recurse -Force
    $global:LASTEXITCODE = 1
}
function Get-WindowsImage($ImagePath, $Index) {
    if ($Index) { return [pscustomobject]@{ Architecture = $global:mediaTest.architecture } }
    $imageIndex = if ([IO.Path]::GetFileName($ImagePath) -eq 'install_single.wim') { 1 } else { 3 }
    return [pscustomobject]@{ ImageName = $global:mediaTest.edition; ImageIndex = $imageIndex }
}
function Export-WindowsImage($SourceImagePath, $SourceIndex, $DestinationImagePath,
                             $CompressionType, [switch]$CheckIntegrity) {
    $global:mediaTest.exports++
    Set-Content -LiteralPath $DestinationImagePath -Value 'exported fixture'
}
function Get-DiskImage($ImagePath) {
    $global:mediaTest.diskReads++
    return [pscustomobject]@{ Attached = ($Scenario -eq 'already-mounted'); ImagePath = $ImagePath }
}
function Mount-DiskImage($ImagePath, [switch]$PassThru) {
    $global:mediaTest.mounts++
    return [pscustomobject]@{ Attached = $true; ImagePath = $ImagePath }
}
function Dismount-DiskImage($ImagePath) { $global:mediaTest.dismounts++ }
function Get-Volume { process { [pscustomobject]@{ DriveLetter = 'R' } } }
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { & $Action } catch { $message = $_.Exception.Message }
    Assert-True ($message -and $message -match $Pattern) "Expected rejection '$Pattern', got '$message'"
}
try {
    switch ($Scenario) {
        'edition-and-architecture' {
            foreach ($entry in @(@(0, 'x86'), @(9, 'amd64'), @(12, 'arm64'))) {
                $global:mediaTest.architecture = $entry[0]
                $output = Join-Path $testRoot ('output-' + $entry[1])
                & $testScript -Source $source -WorkDir $output -Edition $global:mediaTest.edition
                [xml]$answer = Get-Content -LiteralPath (Join-Path $output 'autounattend.xml') -Raw
                $ns = [Xml.XmlNamespaceManager]::new($answer.NameTable)
                $ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
                $component = $answer.SelectSingleNode('//u:component', $ns)
                Assert-True ($component.processorArchitecture -eq $entry[1]) 'Architecture must follow exported image'
                Assert-True ($null -eq $answer.SelectSingleNode('//u:ProductKey', $ns)) 'Must not force Pro product key'
                Assert-True ($answer.SelectSingleNode('//u:MetaData/u:Value', $ns).InnerText -eq '1') 'Select exported index 1'
                Assert-True (-not (Test-Path -LiteralPath (Join-Path $output 'sources/install.esd'))) 'Old ESD must be removed'
                Assert-True ((Get-Content -LiteralPath (Join-Path $source 'sources/install.esd') -Raw).Trim() -eq 'original fixture') 'Source must be preserved'
            }
        }
        'native-copy-success' {
            # Function mocks cannot reproduce PowerShell's handling of a native
            # nonzero exit. Use real robocopy on Windows and a native shim on Unix.
            Remove-Item -LiteralPath Function:\robocopy
            if ([IO.Path]::DirectorySeparatorChar -eq '/') {
                $nativeBin = Join-Path $testRoot 'native-bin'
                New-Item -ItemType Directory -Path $nativeBin | Out-Null
                $nativeCopy = Join-Path $nativeBin 'robocopy'
                $nativeBody = @'
#!/bin/sh
cp -R "$1/." "$2/" || exit 8
exit 1
'@
                Set-Content -LiteralPath $nativeCopy -Value $nativeBody -Encoding ASCII
                & /bin/chmod +x $nativeCopy
                if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare native copy fixture' }
                $env:PATH = $nativeBin + [IO.Path]::PathSeparator + $env:PATH
            }
            $PSNativeCommandUseErrorActionPreference = $true
            & $testScript -Source $source -WorkDir $output -Edition $global:mediaTest.edition
            Assert-True (Test-Path -LiteralPath (Join-Path $output 'sources/install.wim')) 'Native copy exit 1 must allow export to complete'
            Assert-True ($global:mediaTest.exports -eq 1) 'Successful native copy must reach image export'
            Assert-True ($PSNativeCommandUseErrorActionPreference -eq $true) 'Copy policy override must not change the caller preference'
        }
        'nested-output' {
            Assert-Rejected { & $testScript -Source $source -WorkDir (Join-Path $source 'nested') } 'WorkDir'
            Assert-True ($global:mediaTest.copies -eq 0) 'Nested target must be rejected before robocopy'
        }
        'linked-output' {
            $alias = Join-Path $testRoot 'alias'
            $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkType -Path $alias -Target $source | Out-Null
            try {
                Assert-Rejected { & $testScript -Source $source -WorkDir (Join-Path $alias 'nested') } 'reparse point'
                Assert-True ($global:mediaTest.copies -eq 0) 'Linked destination must be rejected before robocopy'
            } finally { Remove-Item -LiteralPath $alias -Force }
        }
        'whatif' {
            $iso = Join-Path $testRoot 'image.iso'
            Set-Content -LiteralPath $iso -Value 'fixture'
            & $testScript -Source $iso -WorkDir $output -WhatIf
            Assert-True ($global:mediaTest.diskReads -eq 0 -and $global:mediaTest.mounts -eq 0) 'WhatIf must not mount or query a disk image'
            Assert-True (-not (Test-Path -LiteralPath $output)) 'WhatIf must not create output'
        }
        'two-images' {
            Set-Content -LiteralPath (Join-Path $source 'sources/install.wim') -Value 'other fixture'
            Assert-Rejected { & $testScript -Source $source -WorkDir $output } 'install.wim'
            Assert-True ($global:mediaTest.exports -eq 0) 'Ambiguous images must not be exported'
        }
        'stale-export' {
            Set-Content -LiteralPath (Join-Path $source 'sources/install_single.wim') -Value 'existing fixture'
            Assert-Rejected { & $testScript -Source $source -WorkDir $output -Edition $global:mediaTest.edition } 'install_single.wim'
            Assert-True ($global:mediaTest.exports -eq 0) 'Must not append to preexisting export image'
        }
        'unknown-architecture' {
            $global:mediaTest.architecture = 99
            Assert-Rejected { & $testScript -Source $source -WorkDir $output -Edition $global:mediaTest.edition } '99'
            Assert-True (Test-Path -LiteralPath (Join-Path $output 'sources/install.esd')) 'Keep source image on unsupported architecture'
        }
        'already-mounted' {
            $iso = Join-Path $testRoot 'image.iso'
            Set-Content -LiteralPath $iso -Value 'fixture'
            New-PSDrive -Name R -PSProvider FileSystem -Root $source | Out-Null
            & $testScript -Source $iso -WorkDir $output -Edition $global:mediaTest.edition
            Assert-True ($global:mediaTest.copies -eq 1) 'Mounted source should be copied'
            Assert-True ($global:mediaTest.mounts -eq 0 -and $global:mediaTest.dismounts -eq 0) 'Do not unmount an existing user mount'
        }
        default { throw "Unknown test scenario: $Scenario" }
    }
    Write-Output "PASS: $Scenario"
} finally {
    Remove-PSDrive -Name R -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
