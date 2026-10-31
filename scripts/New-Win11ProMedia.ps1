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
    robocopy $From $To /E /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy ล้มเหลว (exit $LASTEXITCODE) จาก $From ไป $To" }
}

if (Test-Path -LiteralPath $WorkDir) {
    if (Get-ChildItem -LiteralPath $WorkDir -Force | Select-Object -First 1) {
        throw "WorkDir '$WorkDir' ไม่ว่าง ใช้โฟลเดอร์ใหม่เพื่อไม่ให้ทับไฟล์เดิม"
    }
}

# 1) คัดลอกไฟล์ติดตั้งจาก ISO หรือโฟลเดอร์
$mounted = $null
try {
    if ($Source -match '\.iso$') {
        if (-not (Test-Path -LiteralPath $Source)) { throw "ไม่พบไฟล์ $Source" }
        $mounted = Mount-DiskImage -ImagePath (Resolve-Path -LiteralPath $Source).Path -PassThru
        $letter = ($mounted | Get-Volume).DriveLetter
        if (-not $letter) { throw 'เมานต์ ISO แล้วไม่พบอักษรไดรฟ์' }
        $srcRoot = "${letter}:\"
    } else {
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "ไม่พบโฟลเดอร์ $Source" }
        $srcRoot = (Resolve-Path -LiteralPath $Source).Path
    }
    if (-not (Test-Path (Join-Path $srcRoot 'setup.exe'))) { throw "ไม่พบ setup.exe ใน $srcRoot" }
    Write-Host "คัดลอกไฟล์ติดตั้งจาก $srcRoot ..."
    if ($PSCmdlet.ShouldProcess($WorkDir, 'คัดลอกไฟล์ติดตั้ง')) { Copy-Tree $srcRoot $WorkDir }
} finally {
    if ($mounted) { Dismount-DiskImage -ImagePath $mounted.ImagePath | Out-Null }
}
if ($WhatIfPreference) { return }

# 2) หา index ของรุ่นที่ต้องการ (ชื่อตรงตัว ไม่เอา Pro N / Pro Education ฯลฯ)
$sources = Join-Path $WorkDir 'sources'
$srcImage = @('install.wim', 'install.esd') |
    ForEach-Object { Join-Path $sources $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $srcImage) { throw 'ไม่พบ sources\install.wim หรือ install.esd' }

$images = Get-WindowsImage -ImagePath $srcImage
$target = $images | Where-Object { $_.ImageName -eq $Edition }
if (-not $target) {
    $list = ($images | ForEach-Object { "  [$($_.ImageIndex)] $($_.ImageName)" }) -join "`n"
    throw "ไม่พบรุ่น '$Edition' ใน $srcImage`nรุ่นที่มี:`n$list"
}
$index = @($target)[0].ImageIndex
Write-Host "พบ '$Edition' ที่ index $index"

# 3) ส่งออกเฉพาะรุ่นนั้นเป็น WIM ใหม่ แล้วแทนที่ไฟล์เดิม
$newWim = Join-Path $sources 'install_single.wim'
Write-Host 'กำลังส่งออกอิมเมจ (ใช้เวลาหลายนาที) ...'
Export-WindowsImage -SourceImagePath $srcImage -SourceIndex $index `
    -DestinationImagePath $newWim -CompressionType Maximum -CheckIntegrity | Out-Null

$check = @(Get-WindowsImage -ImagePath $newWim)
if ($check.Count -ne 1 -or $check[0].ImageName -ne $Edition) {
    throw "ตรวจอิมเมจใหม่ไม่ผ่าน: พบ $($check.Count) รุ่น"
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

# 5) autounattend.xml: เลือกรุ่น Pro ด้วยคีย์ทั่วไป (ใช้เลือกรุ่นเท่านั้น ไม่ใช่คีย์ activate)
if (-not $SkipAutounattend) {
    $xml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <UserData>
        <ProductKey>
          <Key>VK7JG-NPHTM-C97JM-9MPGT-3V66T</Key>
        </ProductKey>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>
</unattend>
'@
    Set-Content -LiteralPath (Join-Path $WorkDir 'autounattend.xml') -Value $xml -Encoding UTF8
    Write-Host 'เขียน autounattend.xml แล้ว (ไม่มีการแบ่งดิสก์ คุณเลือกไดรฟ์ติดตั้งเอง)'
}

# 6) คัดลอกลง USB (ไม่ฟอร์แมต)
if ($UsbDrive) {
    $dl = $UsbDrive.TrimEnd(':', '\').ToUpper()
    $vol = Get-Volume -DriveLetter $dl -ErrorAction Stop
    if ($vol.DriveType -ne 'Removable') { throw "ไดรฟ์ ${dl}: ไม่ใช่ไดรฟ์ถอดได้ ($($vol.DriveType)) หยุดเพื่อความปลอดภัย" }
    if (Get-ChildItem -LiteralPath "${dl}:\" -Force -ErrorAction SilentlyContinue | Select-Object -First 1) {
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
