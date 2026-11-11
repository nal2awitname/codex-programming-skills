#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
สร้างชุดติดตั้ง Windows 11 ที่มีเฉพาะรุ่น Pro (Build a Windows 11 installer containing only the Pro edition).

.DESCRIPTION
รับ ISO หรือโฟลเดอร์ที่แตกไฟล์ติดตั้งแล้ว ส่งออกเฉพาะรุ่นที่ระบุจาก install.wim/install.esd
เขียนทับด้วยไฟล์ install.wim ใหม่ที่มีรุ่นเดียว และเขียน autounattend.xml ที่เลือกรุ่นให้
ไม่ฟอร์แมตดิสก์ใด ๆ; ถ้าระบุ -UsbDrive จะคัดลอกไฟล์ไปยัง USB ที่ฟอร์แมตไว้แล้วและว่างเปล่าเท่านั้น

.PARAMETER Source
ไฟล์ .iso หรือโฟลเดอร์ที่มี setup.exe และ sources\install.wim|esd

.PARAMETER WorkDir
โฟลเดอร์ทำงาน/ผลลัพธ์ (ต้องว่างหรือยังไม่มี) ใช้พื้นที่ประมาณ 15 GB

.PARAMETER Edition
ชื่อรุ่นตรงตัวตามที่ DISM แสดง ค่าเริ่มต้น "Windows 11 Pro"

.PARAMETER SkipAutounattend
ไม่เขียน autounattend.xml

.PARAMETER Split
แบ่ง install.wim เป็น install.swm เมื่อไฟล์ใหญ่เกิน 4 GB (จำเป็นถ้า USB เป็น FAT32)

.PARAMETER UsbDrive
อักษรไดรฟ์ USB เช่น E: ต้องเป็นไดรฟ์ถอดได้และว่างเปล่า

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
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    robocopy $From $To /E /XJ /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy ล้มเหลว (exit $LASTEXITCODE) จาก $From ไป $To" }
}

function Assert-NoReparsePath([string]$Path) {
    $current = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "ไม่รองรับเส้นทางลิงก์หรือ reparse point: $current"
            }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}

$WorkDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkDir)
Assert-NoReparsePath $WorkDir
if (Test-Path -LiteralPath $WorkDir -PathType Leaf) { throw 'WorkDir ต้องเป็นโฟลเดอร์ ไม่ใช่ไฟล์' }
if (Test-Path -LiteralPath $WorkDir) {
    if (Get-ChildItem -LiteralPath $WorkDir -Force | Select-Object -First 1) {
        throw "WorkDir '$WorkDir' ไม่ว่าง ใช้โฟลเดอร์ใหม่เพื่อไม่ให้ทับไฟล์เดิม"
    }
}

# Approve the whole local operation before mounting an ISO or creating files.
# A declined confirmation must not fall through into export/delete steps.
if (-not $PSCmdlet.ShouldProcess($WorkDir, "สร้างชุดติดตั้งรุ่น '$Edition' จาก $Source")) { return }

# 1) คัดลอกไฟล์ติดตั้งจาก ISO หรือโฟลเดอร์
$mounted = $null
$mountedByScript = $false
try {
    if ($Source -match '\.iso$') {
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "ไม่พบไฟล์ $Source" }
        $isoPath = (Resolve-Path -LiteralPath $Source).Path
        $mounted = Get-DiskImage -ImagePath $isoPath
        if (-not $mounted.Attached) {
            $mounted = Mount-DiskImage -ImagePath $isoPath -PassThru
            $mountedByScript = $true
        }
        $letter = ($mounted | Get-Volume).DriveLetter
        if (-not $letter) { throw 'เมานต์ ISO แล้วไม่พบอักษรไดรฟ์' }
        $srcRoot = "${letter}:\"
    } else {
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "ไม่พบโฟลเดอร์ $Source" }
        Assert-NoReparsePath $Source
        $srcRoot = (Resolve-Path -LiteralPath $Source).Path
    }
    $sourcePrefix = $srcRoot.TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
    if ($WorkDir.Equals($srcRoot.TrimEnd([char[]]'\/'), [StringComparison]::OrdinalIgnoreCase) -or
        $WorkDir.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'WorkDir ต้องอยู่นอกโฟลเดอร์ต้นทาง เพื่อป้องกันการคัดลอกวนซ้ำ'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $srcRoot 'setup.exe') -PathType Leaf)) { throw "ไม่พบ setup.exe ใน $srcRoot" }
    Write-Host "คัดลอกไฟล์ติดตั้งจาก $srcRoot ..."
    Copy-Tree $srcRoot $WorkDir
} finally {
    if ($mountedByScript) { Dismount-DiskImage -ImagePath $mounted.ImagePath | Out-Null }
}

# 2) หา index ของรุ่นที่ต้องการ (ชื่อตรงตัว ไม่เอา Pro N / Pro Education ฯลฯ)
$sources = Join-Path $WorkDir 'sources'
$sourceImages = @(@('install.wim', 'install.esd') |
    ForEach-Object { Join-Path $sources $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($sourceImages.Count -ne 1) { throw 'ต้องมี sources\install.wim หรือ install.esd เพียงไฟล์เดียว' }
$srcImage = $sourceImages[0]

$images = Get-WindowsImage -ImagePath $srcImage
$target = @($images | Where-Object { $_.ImageName -eq $Edition })
if ($target.Count -ne 1) {
    $list = ($images | ForEach-Object { "  [$($_.ImageIndex)] $($_.ImageName)" }) -join "`n"
    throw "ต้องพบรุ่น '$Edition' เพียงหนึ่ง index ใน $srcImage`nรุ่นที่มี:`n$list"
}
$index = @($target)[0].ImageIndex
Write-Host "พบ '$Edition' ที่ index $index"

# 3) ส่งออกเฉพาะรุ่นนั้นเป็น WIM ใหม่ แล้วแทนที่ไฟล์เดิม
$newWim = Join-Path $sources 'install_single.wim'
if (Test-Path -LiteralPath $newWim) { throw 'มี install_single.wim อยู่แล้ว หยุดเพื่อไม่ส่งออกต่อท้ายอิมเมจเดิม' }
Write-Host 'กำลังส่งออกอิมเมจ (ใช้เวลาหลายนาที) ...'
Export-WindowsImage -SourceImagePath $srcImage -SourceIndex $index `
    -DestinationImagePath $newWim -CompressionType Maximum -CheckIntegrity | Out-Null

$check = @(Get-WindowsImage -ImagePath $newWim)
if ($check.Count -ne 1 -or $check[0].ImageName -ne $Edition) {
    throw "ตรวจอิมเมจใหม่ไม่ผ่าน: พบ $($check.Count) รุ่น"
}
$imageArchitecture = $null
if (-not $SkipAutounattend) {
    $detail = Get-WindowsImage -ImagePath $newWim -Index 1
    $imageArchitecture = switch ([string]$detail.Architecture) {
        '0' { 'x86' }
        '9' { 'amd64' }
        '12' { 'arm64' }
        'x86' { 'x86' }
        'x64' { 'amd64' }
        'amd64' { 'amd64' }
        'arm64' { 'arm64' }
        default { throw "ไม่รองรับสถาปัตยกรรมอิมเมจ '$($detail.Architecture)' สำหรับ autounattend.xml" }
    }
}
Remove-Item -LiteralPath $srcImage -Force
$finalWim = Join-Path $sources 'install.wim'
Rename-Item -LiteralPath $newWim -NewName 'install.wim'

# 4) แบ่งไฟล์ถ้าต้องใช้กับ FAT32
$size = (Get-Item $finalWim).Length
Write-Host ('ขนาด install.wim: {0:N2} GB' -f ($size / 1GB))
if ($size -gt $limitBytes) {
    if ($Split) {
        Write-Host 'แบ่งเป็น install.swm ...'
        dism.exe /Split-Image /ImageFile:"$finalWim" /SWMFile:"$(Join-Path $sources 'install.swm')" /FileSize:3800
        if ($LASTEXITCODE -ne 0) { throw "dism /Split-Image ล้มเหลว (exit $LASTEXITCODE)" }
        Remove-Item -LiteralPath $finalWim -Force
    } else {
        Write-Warning 'ไฟล์เกิน 4 GB: ใส่ USB แบบ FAT32 ไม่ได้ ให้รันใหม่ด้วย -Split หรือใช้ USB แบบ NTFS/exFAT'
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
    Write-Host 'เขียน autounattend.xml แล้ว (ไม่มีการแบ่งดิสก์ คุณเลือกไดรฟ์ติดตั้งเอง)'
}

# 6) คัดลอกลง USB (ไม่ฟอร์แมต)
if ($UsbDrive) {
    if ($UsbDrive -notmatch '^[A-Za-z]:?\\?$') { throw 'UsbDrive ต้องเป็นอักษรไดรฟ์ เช่น E:' }
    $dl = $UsbDrive.TrimEnd(':', '\').ToUpper()
    $vol = Get-Volume -DriveLetter $dl -ErrorAction Stop
    if ($vol.DriveType -ne 'Removable') { throw "ไดรฟ์ ${dl}: ไม่ใช่ไดรฟ์ถอดได้ ($($vol.DriveType)) หยุดเพื่อความปลอดภัย" }
    if (Get-ChildItem -LiteralPath "${dl}:\" -Force -ErrorAction Stop | Select-Object -First 1) {
        throw "ไดรฟ์ ${dl}: ไม่ว่างเปล่า ย้ายหรือสำรองไฟล์ก่อน สคริปต์นี้ไม่ลบข้อมูลใน USB"
    }
    if ($vol.FileSystem -eq 'FAT32' -and (Test-Path $finalWim) -and (Get-Item $finalWim).Length -gt $limitBytes) {
        throw "ไดรฟ์ ${dl}: เป็น FAT32 แต่ install.wim เกิน 4 GB ให้รันด้วย -Split"
    }
    if ($PSCmdlet.ShouldProcess("${dl}:", 'คัดลอกชุดติดตั้ง')) {
        Copy-Tree $WorkDir "${dl}:\"
        Write-Host "คัดลอกไป ${dl}: แล้ว"
    }
}

Write-Host "เสร็จ: $WorkDir มีเฉพาะรุ่น '$Edition'"
