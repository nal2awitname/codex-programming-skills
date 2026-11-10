#requires -Version 5.1
<#
.SYNOPSIS
    แกนหลักของ Driver & Runtime Manager — ตรวจระบบ ตรวจไดรเวอร์และใบรับรอง ค้นหาอัปเดตจากผู้ผลิต
    และ Windows Update ติดตั้งรันไทม์/ไฟล์ทุกรูปแบบตามลำดับที่ผู้ผลิตแนะนำ ทำความสะอาด และออกรายงาน

.NOTES
    ใช้ได้กับ Windows PowerShell 5.1 และ PowerShell 7 บน Windows 10/11
    ฟังก์ชันที่ไม่แตะระบบ (เทียบเวอร์ชัน จัดลำดับ ตรวจแคตตาล็อก แยกชนิดไฟล์) ทดสอบได้บนทุกแพลตฟอร์ม
#>

# ---------------------------------------------------------------------------
# สถานะของโมดูล (แยกต่อ runspace)
# ---------------------------------------------------------------------------
$script:DrmState = @{
    LogFile        = $null
    Queue          = $null
    Sync           = $null
    DryRun         = $false
    Console        = $false
    Session        = $null
    UninstallCache = $null
    WingetPath     = $null
    WuCache        = $null
    DotnetIndex    = $null
    CancelNotified = $false
}

$script:Invariant = [Globalization.CultureInfo]::InvariantCulture
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)

$script:StatusText = @{
    Pending         = 'รอดำเนินการ'
    Running         = 'กำลังทำงาน'
    Downloading     = 'กำลังดาวน์โหลด'
    Installing      = 'กำลังติดตั้ง'
    Installed       = 'สำเร็จ'
    InstalledReboot = 'สำเร็จ (ต้องรีสตาร์ท)'
    UpToDate        = 'เป็นรุ่นล่าสุดแล้ว'
    Staged          = 'เพิ่มเข้า Driver Store แล้ว'
    Skipped         = 'ข้าม'
    Failed          = 'ล้มเหลว'
    Cancelled       = 'ยกเลิก'
    Manual          = 'เปิดหน้าผู้ผลิตแล้ว (ทำต่อในหน้าต่างผู้ผลิต)'
    DryRun          = 'ทดลอง (ไม่ได้ติดตั้งจริง)'
    NotApplicable   = 'ไม่เข้ากับเครื่องนี้'
    NotOffered      = 'ไม่ต้องติดตั้งแล้ว (มีรุ่นที่ดีกว่าอยู่แล้ว)'
    Missing         = 'ไม่พบเครื่องมือ'
}

$script:CertText = @{
    WHQL      = 'WHQL — Microsoft รับรอง (ผ่าน HLK)'
    Attested  = 'Microsoft ลงนามแบบ Attestation (ยังไม่ผ่าน HLK)'
    Inbox     = 'มากับ Windows'
    Microsoft = 'Microsoft ลงนาม'
    WindowsUpdate = 'Windows Update (Microsoft ลงนาม)'
    Vendor    = 'ผู้ผลิตลงนามเอง (ไม่ใช่ WHQL)'
    Unsigned  = 'ไม่มีลายเซ็น'
    Invalid   = 'ลายเซ็นไม่ถูกต้อง'
    None      = 'ไม่มีไดรเวอร์'
    Unknown   = 'ไม่ทราบ'
}

# รหัสปัญหาของ Device Manager ที่พบบ่อย
$script:ProblemText = @{
    1 = 'ตั้งค่าอุปกรณ์ไม่ถูกต้อง'; 3 = 'ไดรเวอร์เสียหายหรือหน่วยความจำไม่พอ'; 10 = 'อุปกรณ์เริ่มทำงานไม่ได้'
    12 = 'ทรัพยากรไม่พอ/ชนกัน'; 14 = 'ต้องรีสตาร์ทเครื่อง'; 18 = 'ต้องติดตั้งไดรเวอร์ใหม่'; 19 = 'ข้อมูลรีจิสทรีเสียหาย'
    21 = 'กำลังถอดอุปกรณ์'; 22 = 'อุปกรณ์ถูกปิดใช้งาน'; 24 = 'ไม่พบอุปกรณ์หรือทำงานไม่ถูกต้อง'
    28 = 'ยังไม่ได้ติดตั้งไดรเวอร์'; 31 = 'อุปกรณ์ทำงานไม่ถูกต้อง'; 32 = 'บริการของไดรเวอร์ถูกปิด'
    37 = 'ไดรเวอร์เริ่มต้นไม่สำเร็จ'; 39 = 'โหลดไดรเวอร์ไม่ได้ (เสียหาย/หายไป)'; 41 = 'โหลดไดรเวอร์แล้วแต่หาอุปกรณ์ไม่พบ'
    43 = 'อุปกรณ์รายงานปัญหาและถูกหยุด'; 45 = 'อุปกรณ์ไม่ได้เชื่อมต่อ'; 48 = 'ไดรเวอร์ถูกบล็อกเพราะเข้ากันไม่ได้'
    52 = 'ตรวจลายเซ็นดิจิทัลของไดรเวอร์ไม่ผ่าน'
}

# ลำดับติดตั้งไดรเวอร์ตามแนวทางผู้ผลิต: BIOS/เฟิร์มแวร์ → ชิปเซ็ต → ME → Storage → กราฟิก → เสียง → เครือข่าย → อื่น ๆ
$script:OrderRules = @(
    @{ Index = 10; Group = 'BIOS / เฟิร์มแวร์'; Class = '^Firmware$'; Name = 'BIOS|UEFI|Firmware|เฟิร์มแวร์|Embedded Controller' }
    @{ Index = 20; Group = 'ชิปเซ็ต / แพลตฟอร์ม'; Class = '^System$'; Name = 'Chipset|SMBus|Serial ?IO|GPIO|I2C|LPC|PCI Express Root|Host Bridge|Dynamic Tuning|DPTF|Integrated Sensor|\bISH\b|\bPMC\b|Power Engine|Gaussian|\bGNA\b|\bNPU\b|\bSPI\b|\bUART\b|Platform Monitoring|Innovation Platform' }
    @{ Index = 25; Group = 'Management Engine / ความปลอดภัย'; Class = ''; Name = 'Management Engine|\bMEI\b|HECI|CSME|\bPSP\b|Platform Security Processor|Trusted Platform|\bTPM\b' }
    @{ Index = 30; Group = 'Storage'; Class = '^(HDC|SCSIAdapter|DiskDrive)$'; Name = 'Rapid Storage|\bRST\b|\bVMD\b|NVMe|SATA|AHCI|RAID|Storage' }
    @{ Index = 40; Group = 'กราฟิก'; Class = '^Display$'; Name = 'Graphics|Display Driver|GeForce|Radeon|Arc\b|Iris|UHD' }
    @{ Index = 50; Group = 'เสียง'; Class = '^(MEDIA|AudioEndpoint|AudioProcessingObject)$'; Name = 'Audio|Sound|Smart Sound|\bSST\b|Realtek High Definition' }
    @{ Index = 60; Group = 'เครือข่าย (LAN/Wi-Fi)'; Class = '^Net$'; Name = 'Ethernet|\bLAN\b|Wi-?Fi|Wireless LAN|WLAN|Network|Killer|GbE' }
    @{ Index = 65; Group = 'Bluetooth'; Class = '^Bluetooth$'; Name = 'Bluetooth' }
    @{ Index = 70; Group = 'USB / Thunderbolt'; Class = '^(USB|USBDevice)$'; Name = 'Thunderbolt|USB4|USB' }
    @{ Index = 80; Group = 'อุปกรณ์อินพุต'; Class = '^(HIDClass|Keyboard|Mouse)$'; Name = 'Touchpad|TouchPad|Precision Touch|Keyboard|Mouse|\bPen\b' }
    @{ Index = 85; Group = 'กล้อง / ไบโอเมตริก'; Class = '^(Camera|Image|Biometric)$'; Name = 'Camera|Webcam|Fingerprint|Biometric' }
    @{ Index = 88; Group = 'การ์ดรีดเดอร์ / อื่น ๆ'; Class = '^(SDHost|MTD|SmartCardReader)$'; Name = 'Card Reader|SD Host' }
)
$script:GenericClasses = '^(|System|SoftwareComponent|Extension|Unknown|SoftwareDevice)$'

$script:PhaseNames = @{
    0 = 'เตรียมระบบ'
    1 = 'อัปเดตจากผู้ผลิตเครื่อง (OEM) — ทำก่อน'
    2 = 'เครื่องมือของผู้ผลิตชิ้นส่วน'
    3 = 'ไดรเวอร์/ไฟล์จากผู้ผลิต ตามลำดับที่แนะนำ'
    4 = 'ไดรเวอร์ที่ Microsoft รับรอง (Windows Update) — เฉพาะรุ่นที่ใหม่กว่า'
    5 = 'รันไทม์'
    6 = 'โปรแกรมเสริม'
    7 = 'ปรับแต่งประสิทธิภาพ'
}

# ---------------------------------------------------------------------------
# บันทึก (log) และการส่งข้อความไปหน้าต่าง GUI
# ---------------------------------------------------------------------------
function Get-DrmTimestamp {
    param([string]$Format = 'yyyy-MM-dd HH:mm:ss')
    (Get-Date).ToString($Format, $script:Invariant)
}

function Format-DrmDate {
    param($Date, [string]$Format = 'yyyy-MM-dd')
    if ($null -eq $Date -or $Date -eq '') { return '' }
    try { return ([datetime]$Date).ToString($Format, $script:Invariant) } catch { return [string]$Date }
}

function Write-DrmLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$Message,
        [ValidateSet('Info', 'Step', 'Ok', 'Warn', 'Error', 'Debug')][string]$Level = 'Info'
    )
    $line = '{0} [{1}] {2}' -f (Get-DrmTimestamp), $Level.ToUpperInvariant().PadRight(5), $Message
    if ($script:DrmState.LogFile) {
        try { [IO.File]::AppendAllText($script:DrmState.LogFile, $line + [Environment]::NewLine, $script:Utf8Bom) } catch { }
    }
    if ($script:DrmState.Queue) {
        $script:DrmState.Queue.Enqueue([pscustomobject]@{ Type = 'Log'; Level = $Level; Text = $line })
    }
    elseif ($script:DrmState.Console) {
        $color = switch ($Level) { 'Step' { 'Cyan' } 'Ok' { 'Green' } 'Warn' { 'Yellow' } 'Error' { 'Red' } 'Debug' { 'DarkGray' } default { 'Gray' } }
        Write-Host $line -ForegroundColor $color
    }
}

function Send-DrmEvent {
    param([Parameter(Mandatory)][string]$Type, [hashtable]$Data = @{})
    if (-not $script:DrmState.Queue) { return }
    $o = [ordered]@{ Type = $Type }
    foreach ($k in $Data.Keys) { $o[$k] = $Data[$k] }
    $script:DrmState.Queue.Enqueue([pscustomobject]$o)
}

function Set-DrmProgress {
    param([double]$Percent, [string]$Text)
    Send-DrmEvent -Type 'Progress' -Data @{ Percent = [Math]::Max(0, [Math]::Min(100, $Percent)); Text = $Text }
}

function Set-DrmItemStatus {
    param([string]$Id, [string]$Status, [string]$Detail = '', [string]$Level = '')
    $label = if ($script:StatusText.ContainsKey($Status)) { $script:StatusText[$Status] } else { $Status }
    Send-DrmEvent -Type 'ItemStatus' -Data @{ Id = $Id; Status = $label; Code = $Status; Detail = $Detail; Level = $Level }
}

function Test-DrmCancelRequested {
    $s = $script:DrmState.Sync
    return [bool]($s -and $s.Cancel)
}

function Initialize-DrmSession {
    [CmdletBinding()]
    param(
        [string]$Root,
        [string]$SessionId,
        $Queue,
        $Sync,
        [switch]$DryRun,
        [switch]$Console
    )
    if (-not $Root) {
        $base = if ($env:ProgramData) { $env:ProgramData } else { [IO.Path]::GetTempPath() }
        $Root = Join-Path $base 'DriverRuntimeManager'
    }
    if (-not $SessionId) { $SessionId = Get-DrmTimestamp -Format 'yyyyMMdd_HHmmss' }
    $logDir = Join-Path $Root 'Logs'
    $reportDir = Join-Path $Root 'Reports'
    $workDir = Join-Path (Join-Path $Root 'Work') $SessionId
    foreach ($d in @($logDir, $reportDir, $workDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    $session = [pscustomobject]@{
        Id        = $SessionId
        Root      = $Root
        LogDir    = $logDir
        LogFile   = (Join-Path $logDir ("DRM_{0}.log" -f $SessionId))
        ReportDir = $reportDir
        WorkDir   = $workDir
        Started   = (Get-DrmTimestamp)
        DryRun    = [bool]$DryRun
    }
    Use-DrmSession -Session $session -Queue $Queue -Sync $Sync -DryRun:$DryRun -Console:$Console
    return $session
}

function Use-DrmSession {
    param([Parameter(Mandatory)]$Session, $Queue, $Sync, [switch]$DryRun, [switch]$Console)
    $script:DrmState.Session = $Session
    $script:DrmState.LogFile = $Session.LogFile
    $script:DrmState.Queue = $Queue
    $script:DrmState.Sync = $Sync
    $script:DrmState.DryRun = [bool]$DryRun
    $script:DrmState.Console = [bool]$Console
    $script:DrmState.CancelNotified = $false
}

function Get-DrmSession { $script:DrmState.Session }

# ---------------------------------------------------------------------------
# ตัวช่วยทั่วไป
# ---------------------------------------------------------------------------
function Get-DrmProp {
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Test-DrmIsWindows {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    return [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

function Test-DrmIsAdmin {
    if (-not (Test-DrmIsWindows)) { return $false }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-DrmVersion {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Matches($Text, '\d+(?:[.,]\d+)+')
    if ($m.Count -gt 0) { return $m[$m.Count - 1].Value.Replace(',', '.') }
    if ($Text -match '^\s*v?(\d+)\s*$') { return $Matches[1] }
    return $null
}

function Compare-DrmVersion {
    <# คืนค่า -1 (A เก่ากว่า), 0 (เท่ากัน), 1 (A ใหม่กว่า) #>
    param([AllowNull()][AllowEmptyString()][string]$A, [AllowNull()][AllowEmptyString()][string]$B)
    $va = ConvertTo-DrmVersion $A
    $vb = ConvertTo-DrmVersion $B
    if (-not $va -and -not $vb) { return 0 }
    if (-not $va) { return -1 }
    if (-not $vb) { return 1 }
    $pa = $va.Split('.')
    $pb = $vb.Split('.')
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = [decimal]0; $y = [decimal]0
        if ($i -lt $pa.Count) { [void][decimal]::TryParse($pa[$i], [ref]$x) }
        if ($i -lt $pb.Count) { [void][decimal]::TryParse($pb[$i], [ref]$y) }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

function ConvertTo-DrmDate {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ($Value -is [datetime]) { return $Value }
    $s = [string]$Value
    if ($s -match '^(\d{4})(\d{2})(\d{2})\d{6}') {
        try { return New-Object DateTime ([int]$Matches[1]), ([int]$Matches[2]), ([int]$Matches[3]) } catch { return $null }
    }
    if ($s -match '^(\d{1,2})/(\d{1,2})/(\d{4})') {
        try { return New-Object DateTime ([int]$Matches[3]), ([int]$Matches[1]), ([int]$Matches[2]) } catch { return $null }
    }
    if ($s -match '^(\d{4})-(\d{2})-(\d{2})') {
        try { return New-Object DateTime ([int]$Matches[1]), ([int]$Matches[2]), ([int]$Matches[3]) } catch { return $null }
    }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($s, $script:Invariant, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    return $null
}

function Expand-DrmPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    $p = $Path
    if ($p.Contains('%ProgramFiles(x86)%')) {
        $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        if (-not $pf86) { $pf86 = $env:ProgramFiles }
        $p = $p.Replace('%ProgramFiles(x86)%', [string]$pf86)
    }
    return [Environment]::ExpandEnvironmentVariables($p)
}

function Expand-DrmTemplate {
    param([string]$Text, [hashtable]$Values)
    if (-not $Text) { return $Text }
    $out = $Text
    foreach ($k in $Values.Keys) { $out = $out.Replace('{' + $k + '}', [string]$Values[$k]) }
    return $out
}

function Get-DrmSafeFileName {
    param([string]$Name, [string]$Fallback = 'download.bin')
    if (-not $Name) { return $Fallback }
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $clean = -join ($Name.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })
    $clean = $clean.Trim(' ', '.')
    if (-not $clean) { return $Fallback }
    return $clean
}

function Get-DrmWindowsDir {
    foreach ($v in @($env:SystemRoot, $env:windir)) { if ($v) { return $v } }
    return 'C:\Windows'
}

function Get-DrmArchitecture {
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        switch ([int]$cpu.Architecture) { 12 { return 'arm64' } 9 { return 'x64' } 0 { return 'x86' } 5 { return 'arm' } }
    } catch { }
    $a = $env:PROCESSOR_ARCHITEW6432
    if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ($a) { 'ARM64' { 'arm64' } 'AMD64|x64' { 'x64' } default { 'x86' } }
}

function Format-DrmSize {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Format-DrmExitCode {
    param($Code)
    if ($null -eq $Code) { return 'n/a' }
    $c = [int64]$Code
    if ($c -lt 0 -or $c -gt 65535) { return ('{0} (0x{1:X8})' -f $c, ($c -band 0xFFFFFFFFL)) }
    return [string]$c
}

function New-DrmResult {
    param([string]$Status, [string]$Detail = '', $ExitCode = $null, [bool]$RebootRequired = $false, [string]$Method = '', [string]$Version = '')
    [pscustomobject]@{
        Status         = $Status
        StatusText     = $(if ($script:StatusText.ContainsKey($Status)) { $script:StatusText[$Status] } else { $Status })
        Detail         = $Detail
        ExitCode       = $ExitCode
        RebootRequired = $RebootRequired
        Method         = $Method
        Version        = $Version
    }
}

# ---------------------------------------------------------------------------
# รันโปรแกรม ดาวน์โหลด และตรวจลายเซ็น
# ---------------------------------------------------------------------------
function Invoke-DrmProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Arguments = '',
        [string]$WorkingDirectory,
        [int]$TimeoutMinutes = 90,
        [switch]$Capture,
        [switch]$Hidden,
        [string[]]$WaitForProcessNames,
        [switch]$IgnoreDryRun
    )
    $display = ('"{0}" {1}' -f $FilePath, $Arguments).Trim()
    if ($script:DrmState.DryRun -and -not $IgnoreDryRun) {
        Write-DrmLog ("ทดลอง: จะรัน {0}" -f $display) -Level Debug
        return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; Output = ''; Error = ''; Command = $display; Duration = 0; DryRun = $true }
    }
    Write-DrmLog ("รันคำสั่ง: {0}" -f $display) -Level Debug
    $sp = @{ FilePath = $FilePath; PassThru = $true; ErrorAction = 'Stop' }
    if ($Arguments) { $sp.ArgumentList = $Arguments }
    if ($WorkingDirectory) { $sp.WorkingDirectory = $WorkingDirectory }
    $outFile = $null; $errFile = $null
    if ($Capture) {
        $outFile = [IO.Path]::GetTempFileName()
        $errFile = [IO.Path]::GetTempFileName()
        $sp.RedirectStandardOutput = $outFile
        $sp.RedirectStandardError = $errFile
        $sp.NoNewWindow = $true
    }
    elseif ($Hidden) { $sp.WindowStyle = 'Hidden' }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process @sp
    $null = $p.Handle   # ทำให้อ่าน ExitCode ได้แน่นอนหลังโปรเซสจบ
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $timedOut = $false
    while (-not $p.WaitForExit(500)) {
        if ((Get-Date) -gt $deadline) { $timedOut = $true; break }
        if ((Test-DrmCancelRequested) -and -not $script:DrmState.CancelNotified) {
            $script:DrmState.CancelNotified = $true
            Write-DrmLog 'ได้รับคำสั่งหยุด — รอให้ตัวติดตั้งที่กำลังทำงานจบก่อน เพื่อไม่ให้ระบบเสียหาย' -Level Warn
        }
    }
    if ($timedOut) {
        Write-DrmLog ("หมดเวลา {0} นาที: {1} — ปล่อยให้ทำงานต่อและข้ามไปรายการถัดไป" -f $TimeoutMinutes, $display) -Level Warn
    }
    elseif ($WaitForProcessNames) {
        Start-Sleep -Seconds 2
        while ((Get-Date) -lt $deadline) {
            $running = Get-Process -Name $WaitForProcessNames -ErrorAction SilentlyContinue
            if (-not $running) { break }
            Start-Sleep -Seconds 2
        }
    }
    $sw.Stop()
    $exit = $null
    if (-not $timedOut) { try { $exit = $p.ExitCode } catch { $exit = $null } }
    $out = ''; $err = ''
    if ($Capture) {
        try { $out = [IO.File]::ReadAllText($outFile) } catch { }
        try { $err = [IO.File]::ReadAllText($errFile) } catch { }
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
    Write-DrmLog ("จบคำสั่ง (exit {0}, {1:N0} วินาที)" -f (Format-DrmExitCode $exit), $sw.Elapsed.TotalSeconds) -Level Debug
    return [pscustomobject]@{ ExitCode = $exit; TimedOut = $timedOut; Output = $out; Error = $err; Command = $display; Duration = $sw.Elapsed.TotalSeconds; DryRun = $false }
}

function Get-DrmCertLevelFromEku {
    <# จำแนกระดับใบรับรองจาก EKU ของใบรับรองที่ลงนาม catalog/ไฟล์ (เอกสาร Microsoft: OID ลงท้าย .5 = WHQL, .5.1 = Attestation) #>
    param([string[]]$Oids = @(), [string]$Subject = '')
    if ($Oids -contains '1.3.6.1.4.1.311.10.3.5.1') { return 'Attested' }
    if ($Oids -contains '1.3.6.1.4.1.311.10.3.5') { return 'WHQL' }
    if ($Oids -contains '1.3.6.1.4.1.311.10.3.6') { return 'Inbox' }
    if ($Subject -match 'O=Microsoft Corporation') { return 'Microsoft' }
    if ($Subject) { return 'Vendor' }
    return 'Unsigned'
}

function Get-DrmCertificateEku {
    param($Certificate)
    $oids = New-Object System.Collections.Generic.List[string]
    if (-not $Certificate) { return , $oids.ToArray() }
    foreach ($ext in $Certificate.Extensions) {
        $eku = $null
        if ($ext -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) { $eku = $ext }
        elseif ($ext.Oid -and $ext.Oid.Value -eq '2.5.29.37') {
            $eku = New-Object System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension($ext, $ext.Critical)
        }
        if ($eku) { foreach ($o in $eku.EnhancedKeyUsages) { $oids.Add($o.Value) } }
    }
    return , $oids.ToArray()
}

function Get-DrmCatalogSignerCertificate {
    <# อ่านใบรับรองผู้ลงนามจากไฟล์ .cat (PKCS#7) โดยตรง ใช้เมื่อ Get-AuthenticodeSignature ไม่คืนใบรับรอง #>
    param([string]$Path)
    try {
        try { Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue } catch { }
        $cms = New-Object System.Security.Cryptography.Pkcs.SignedCms
        $cms.Decode([IO.File]::ReadAllBytes($Path))
        if ($cms.SignerInfos.Count -gt 0) { return $cms.SignerInfos[0].Certificate }
    } catch { }
    return $null
}

function Get-DrmFileSignature {
    param([Parameter(Mandatory)][string]$Path)
    $result = [ordered]@{ Path = $Path; Status = 'Unknown'; IsValid = $false; Subject = ''; Signer = ''; Organization = ''; IsMicrosoft = $false; CertLevel = 'Unknown'; Thumbprint = '' }
    $cert = $null
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        $result.Status = [string]$sig.Status
        $result.IsValid = ($sig.Status -eq 'Valid')
        $cert = $sig.SignerCertificate
    } catch { $result.Status = 'Error' }
    if (-not $cert -and $Path -match '\.cat$') { $cert = Get-DrmCatalogSignerCertificate -Path $Path }
    if ($cert) {
        $result.Subject = $cert.Subject
        $result.Thumbprint = $cert.Thumbprint
        if ($cert.Subject -match '(?:^|,\s*)CN=("?)([^,"]+)\1') { $result.Signer = $Matches[2] }
        if ($cert.Subject -match '(?:^|,\s*)O=("?)([^,"]+)\1') { $result.Organization = $Matches[2] }
        $result.IsMicrosoft = ($result.Organization -eq 'Microsoft Corporation')
        $result.CertLevel = Get-DrmCertLevelFromEku -Oids (Get-DrmCertificateEku $cert) -Subject $cert.Subject
    }
    else { $result.CertLevel = 'Unsigned' }
    if ($result.Status -in @('HashMismatch', 'NotTrusted', 'Incompatible')) { $result.CertLevel = 'Invalid' }
    return [pscustomobject]$result
}

function Get-DrmCertText {
    param([string]$Level)
    if ($Level -and $script:CertText.ContainsKey($Level)) { return $script:CertText[$Level] }
    return $Level
}

function Initialize-DrmTls {
    try {
        $current = [Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol = $current -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
}

function Save-DrmDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$DestinationDir,
        [string]$FileName,
        [string]$Sha512,
        [string]$Sha256,
        [string]$ExpectedSigner,
        [string]$ItemId,
        [int]$Retries = 3
    )
    Initialize-DrmTls
    New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    $target = $null
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        $resp = $null; $in = $null; $out = $null
        try {
            Write-DrmLog ("ดาวน์โหลด ({0}/{1}): {2}" -f $attempt, $Retries, $Url)
            $req = [Net.HttpWebRequest]::Create($Url)
            $req.UserAgent = 'DriverRuntimeManager/1.0 (Windows NT)'
            $req.AllowAutoRedirect = $true
            $req.Timeout = 60000
            $req.ReadWriteTimeout = 300000
            $resp = $req.GetResponse()
            $name = $FileName
            if (-not $name) {
                $cd = $resp.Headers['Content-Disposition']
                if ($cd -and $cd -match 'filename\*?=(?:UTF-8'''')?"?([^";]+)"?') { $name = [Uri]::UnescapeDataString($Matches[1]) }
            }
            if (-not $name) { $name = [Uri]::UnescapeDataString($resp.ResponseUri.Segments[-1]) }
            $name = Get-DrmSafeFileName $name
            $target = Join-Path $DestinationDir $name
            $tmp = $target + '.part'
            $total = [int64]$resp.ContentLength
            $in = $resp.GetResponseStream()
            $out = [IO.File]::Create($tmp)
            $buffer = New-Object byte[] (1MB)
            $done = [int64]0
            $last = [Diagnostics.Stopwatch]::StartNew()
            while (($read = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $out.Write($buffer, 0, $read)
                $done += $read
                if (Test-DrmCancelRequested) { throw 'ผู้ใช้สั่งหยุดระหว่างดาวน์โหลด' }
                if ($last.ElapsedMilliseconds -ge 700) {
                    $last.Restart()
                    $pct = if ($total -gt 0) { [Math]::Round($done * 100.0 / $total, 0) } else { -1 }
                    $txt = if ($total -gt 0) { '{0} / {1} ({2}%)' -f (Format-DrmSize $done), (Format-DrmSize $total), $pct } else { Format-DrmSize $done }
                    Send-DrmEvent -Type 'Download' -Data @{ Id = $ItemId; Percent = $pct; Text = ('กำลังดาวน์โหลด {0}: {1}' -f $name, $txt) }
                }
            }
            $out.Close(); $out = $null
            if ($total -gt 0 -and $done -ne $total) { throw ("ไฟล์ไม่ครบ ({0} จาก {1} ไบต์)" -f $done, $total) }
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
            Move-Item -LiteralPath $tmp -Destination $target -Force
            Write-DrmLog ("ดาวน์โหลดเสร็จ: {0} ({1})" -f $target, (Format-DrmSize $done)) -Level Ok
            break
        }
        catch {
            $msg = $_.Exception.Message
            if ($out) { try { $out.Close() } catch { } ; $out = $null }
            if ($target -and (Test-Path -LiteralPath ($target + '.part'))) { Remove-Item -LiteralPath ($target + '.part') -Force -ErrorAction SilentlyContinue }
            if ((Test-DrmCancelRequested) -or $attempt -ge $Retries) { throw ("ดาวน์โหลดไม่สำเร็จ: {0}" -f $msg) }
            Write-DrmLog ("ดาวน์โหลดล้มเหลว ({0}) — ลองใหม่" -f $msg) -Level Warn
            Start-Sleep -Seconds (2 * $attempt)
        }
        finally {
            if ($in) { try { $in.Dispose() } catch { } }
            if ($resp) { try { $resp.Close() } catch { } }
        }
    }
    if ($Sha512) {
        $h = (Get-FileHash -LiteralPath $target -Algorithm SHA512).Hash
        if ($h -ne $Sha512.ToUpperInvariant()) { Remove-Item -LiteralPath $target -Force; throw 'ค่า SHA512 ไม่ตรงกับที่ผู้ผลิตประกาศ — ลบไฟล์ทิ้งแล้ว' }
        Write-DrmLog 'ตรวจ SHA512 ตรงกับ release metadata ของ Microsoft' -Level Ok
    }
    if ($Sha256) {
        $h = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($h -ne $Sha256.ToUpperInvariant()) { Remove-Item -LiteralPath $target -Force; throw 'ค่า SHA256 ไม่ตรง — ลบไฟล์ทิ้งแล้ว' }
    }
    if ($ExpectedSigner) {
        $sig = Get-DrmFileSignature -Path $target
        if ($sig.Status -eq 'NotSupportedFileFormat' -and $target -match '\.(msix|msixbundle|appx|appxbundle)$') {
            Write-DrmLog 'แพ็กเกจ MSIX: Windows จะตรวจลายเซ็นของ Microsoft ตอน Add-AppxPackage' -Level Debug
        }
        elseif (-not $sig.IsValid -or $sig.Organization -ne $ExpectedSigner) {
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            throw ("ลายเซ็นดิจิทัลไม่ผ่าน (สถานะ {0}, ผู้ลงนาม '{1}') — ต้องเป็น {2}" -f $sig.Status, $sig.Organization, $ExpectedSigner)
        }
        Write-DrmLog ("ลายเซ็นถูกต้อง: {0}" -f $sig.Subject) -Level Ok
    }
    return $target
}

function Test-DrmUrlReachable {
    param([string]$Url = 'https://download.microsoft.com/', [int]$TimeoutMs = 6000)
    Initialize-DrmTls
    try {
        $req = [Net.HttpWebRequest]::Create($Url)
        $req.Method = 'HEAD'
        $req.Timeout = $TimeoutMs
        $req.UserAgent = 'DriverRuntimeManager/1.0 (Windows NT)'
        $r = $req.GetResponse(); $r.Close()
        return $true
    } catch [Net.WebException] {
        if ($_.Exception.Response) { return $true }
        return $false
    } catch { return $false }
}

function Get-DrmJson {
    param([Parameter(Mandatory)][string]$Url, [int]$TimeoutMs = 20000)
    Initialize-DrmTls
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Timeout = $TimeoutMs
    $req.UserAgent = 'DriverRuntimeManager/1.0 (Windows NT)'
    $resp = $req.GetResponse()
    try {
        $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        $reader.Dispose()
    } finally { $resp.Close() }
    return ($text | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
# แคตตาล็อก
# ---------------------------------------------------------------------------
function Get-DrmCatalog {
    param([string]$Path)
    if (-not $Path) { $Path = Join-Path $PSScriptRoot 'catalog.json' }
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    return ($text | ConvertFrom-Json)
}

function Test-DrmCatalog {
    <# ตรวจความถูกต้องของแคตตาล็อก คืนรายการข้อผิดพลาด (ว่าง = ผ่าน) #>
    param([Parameter(Mandatory)]$Catalog)
    $errors = New-Object System.Collections.Generic.List[string]
    $validCategories = 'prereq', 'runtime', 'tool', 'tweak'
    $validPresets = 'recommended', 'gaming', 'work'
    $validArch = 'x64', 'x86', 'arm64'
    $validInstall = 'direct', 'winget', 'feature', 'builtin', 'url', 'dotnet'
    $validDetect = 'registry', 'uninstall', 'file', 'feature', 'appx', 'netfx', 'command', 'setting', 'wingetPackage', 'dotnet'
    $hosts = @($Catalog.trustedRuntimeHosts)
    $ids = @{}
    foreach ($it in @($Catalog.items)) {
        $id = Get-DrmProp $it 'id'
        if (-not $id) { $errors.Add('มีรายการที่ไม่มี id'); continue }
        if ($ids.ContainsKey($id)) { $errors.Add("id ซ้ำ: $id") } else { $ids[$id] = $true }
        foreach ($f in 'name', 'group', 'category', 'order') { if ($null -eq (Get-DrmProp $it $f)) { $errors.Add("$id ไม่มีฟิลด์ $f") } }
        if ((Get-DrmProp $it 'category') -and $validCategories -notcontains $it.category) { $errors.Add("$id category ไม่ถูกต้อง: $($it.category)") }
        foreach ($p in @(Get-DrmProp $it 'presets' @())) { if ($validPresets -notcontains $p) { $errors.Add("$id preset ไม่ถูกต้อง: $p") } }
        foreach ($a in @(Get-DrmProp $it 'arch' @())) { if ($validArch -notcontains $a) { $errors.Add("$id arch ไม่ถูกต้อง: $a") } }
        if ((Get-DrmProp $it 'dynamic') -eq 'dotnet') {
            if (-not (Get-DrmProp $it 'framework')) { $errors.Add("$id (dotnet) ไม่มี framework") }
            continue
        }
        $methods = @(Get-DrmProp $it 'install' @())
        if ($methods.Count -eq 0) { $errors.Add("$id ไม่มีวิธีติดตั้ง") }
        foreach ($m in $methods) {
            $t = Get-DrmProp $m 'type'
            if ($validInstall -notcontains $t) { $errors.Add("$id วิธีติดตั้งไม่รู้จัก: $t"); continue }
            if ($t -eq 'winget' -and -not ((Get-DrmProp $m 'id') -match '^[A-Za-z0-9][\w\-]*\.[\w\.\-\+]+$')) { $errors.Add("$id winget id ไม่ถูกต้อง: $($m.id)") }
            if ($t -eq 'direct') {
                $u = Get-DrmProp $m 'url'
                $uri = $null
                if (-not [Uri]::TryCreate([string]$u, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') { $errors.Add("$id url ต้องเป็น https: $u") }
                elseif ($it.category -in 'runtime', 'prereq' -and $hosts -notcontains $uri.Host) { $errors.Add("$id url ไม่ได้มาจากโดเมนของ Microsoft ที่อนุญาต: $($uri.Host)") }
            }
            if ($t -in 'feature' -and -not (Get-DrmProp $m 'name')) { $errors.Add("$id feature ไม่มี name") }
            if ($t -eq 'builtin' -and (Get-DrmProp $m 'action') -notin 'RepairWinget', 'GameMode', 'HAGS', 'PowerPlan') { $errors.Add("$id builtin action ไม่รู้จัก: $($m.action)") }
        }
        foreach ($d in @(Get-DrmProp $it 'detect' @())) {
            if ($validDetect -notcontains (Get-DrmProp $d 'type')) { $errors.Add("$id detect ไม่รู้จัก: $($d.type)") }
            if ((Get-DrmProp $d 'type') -eq 'uninstall') {
                try { [void][regex]::new($d.pattern) } catch { $errors.Add("$id regex ไม่ถูกต้อง: $($d.pattern)") }
            }
        }
    }
    foreach ($t in @($Catalog.oemTools)) {
        foreach ($f in 'vendor', 'match', 'name', 'supportUrl') { if (-not (Get-DrmProp $t $f)) { $errors.Add("oemTools ($($t.name)) ไม่มี $f") } }
        if ((Get-DrmProp $t 'automated') -and -not (Get-DrmProp $t 'applyArgs')) { $errors.Add("oemTools ($($t.name)) automated แต่ไม่มี applyArgs") }
        $su = Get-DrmProp $t 'supportUrl'
        if ($su -and $su -notmatch '^https://') { $errors.Add("oemTools ($($t.name)) supportUrl ต้องเป็น https") }
    }
    foreach ($l in @($Catalog.windowsLifecycle)) {
        foreach ($f in 'homePro', 'enterprise') {
            $v = Get-DrmProp $l $f
            if ($v -and -not (ConvertTo-DrmDate $v)) { $errors.Add("windowsLifecycle $($l.build) วันที่ไม่ถูกต้อง: $v") }
        }
    }
    return , $errors.ToArray()
}

# ---------------------------------------------------------------------------
# ข้อมูลระบบ
# ---------------------------------------------------------------------------
function Get-DrmWindowsLifecycle {
    param([int]$Build, [string]$EditionId = '', $Catalog, [datetime]$Today = (Get-Date))
    if ($EditionId -match '^Server') {
        return [pscustomobject]@{ Version = "Windows Server (บิลด์ $Build)"; EndOfSupport = ''; Status = 'Unknown'; Edition = 'server'; Message = "Windows Server บิลด์ $Build — ตรวจวงจรชีวิตของ Server ที่ learn.microsoft.com/windows-server/get-started/windows-server-release-info" }
    }
    $kind = 'homePro'
    if ($EditionId -match 'S$|LTSC|IoTEnterpriseS') { $kind = 'ltsc' }
    elseif ($EditionId -match 'Enterprise|Education|IoT|ServerRdsh') { $kind = 'enterprise' }
    $rows = @($Catalog.windowsLifecycle)
    $row = $rows | Where-Object { [int]$_.build -eq $Build } | Select-Object -First 1
    if (-not $row) {
        $max = ($rows | Measure-Object -Property build -Maximum).Maximum
        if ($Build -gt $max) {
            return [pscustomobject]@{ Version = 'ใหม่กว่าข้อมูลในแคตตาล็อก'; EndOfSupport = ''; Status = 'Supported'; Edition = $kind; Message = "บิลด์ $Build ใหม่กว่าข้อมูลแคตตาล็อก ($($Catalog.catalogDate)) — น่าจะยังได้รับการสนับสนุน" }
        }
        return [pscustomobject]@{ Version = 'ไม่ทราบ'; EndOfSupport = ''; Status = 'EndOfSupport'; Edition = $kind; Message = "บิลด์ $Build เก่ากว่ารุ่นที่ยังรองรับ — ควรอัปเดต Windows" }
    }
    $dateText = Get-DrmProp $row $kind
    if (-not $dateText) { $dateText = Get-DrmProp $row 'enterprise' }
    $end = ConvertTo-DrmDate $dateText
    $status = 'Supported'
    if ($end) {
        if ($Today.Date -gt $end.Date) { $status = 'EndOfSupport' }
        elseif (($end - $Today).TotalDays -le 90) { $status = 'EndingSoon' }
    }
    $label = '{0} {1}' -f $row.family, $row.version
    $msg = switch ($status) {
        'EndOfSupport' { "$label หมดการอัปเดตความปลอดภัยแล้วเมื่อ $dateText — ควรอัปเดตเป็นเวอร์ชันใหม่" }
        'EndingSoon' { "$label จะหมดการอัปเดตความปลอดภัย $dateText (เหลือไม่ถึง 90 วัน)" }
        default { "$label ได้รับการอัปเดตความปลอดภัยถึง $dateText" }
    }
    return [pscustomobject]@{ Version = $label; EndOfSupport = $dateText; Status = $status; Edition = $kind; Message = $msg }
}

function Get-DrmPendingReboot {
    $reasons = New-Object System.Collections.Generic.List[string]
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons.Add('Component Based Servicing') }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons.Add('Windows Update') }
    try {
        $pfr = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations
        if ($pfr -and @($pfr | Where-Object { $_ }).Count -gt 0) { $reasons.Add('ไฟล์รอแทนที่ (PendingFileRename)') }
    } catch { }
    try {
        $v = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Updates' -Name UpdateExeVolatile -ErrorAction Stop).UpdateExeVolatile
        if ($v -and $v -ne 0) { $reasons.Add('UpdateExeVolatile') }
    } catch { }
    return [pscustomobject]@{ Pending = ($reasons.Count -gt 0); Reasons = $reasons.ToArray() }
}

function Get-DrmRegistryValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Get-DrmWingetPath {
    if ($script:DrmState.WingetPath -and (Test-Path -LiteralPath $script:DrmState.WingetPath)) { return $script:DrmState.WingetPath }
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $path = $null
    if ($cmd) { $path = $cmd.Source }
    if (-not $path -and $env:LOCALAPPDATA) {
        $p = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
        if (Test-Path -LiteralPath $p) { $path = $p }
    }
    if (-not $path -and $env:ProgramFiles) {
        $cand = Get-ChildItem -Path (Join-Path $env:ProgramFiles 'WindowsApps') -Filter 'Microsoft.DesktopAppInstaller_*' -Directory -ErrorAction SilentlyContinue |
            Sort-Object { [version](($_.Name -split '_')[1]) } -Descending -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'winget.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($cand) { $path = $cand }
    }
    $script:DrmState.WingetPath = $path
    return $path
}

function Get-Drm7ZipPath {
    foreach ($p in @((Expand-DrmPath '%ProgramFiles%\7-Zip\7z.exe'), (Expand-DrmPath '%ProgramFiles(x86)%\7-Zip\7z.exe'))) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    $c = Get-Command 7z.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}

function Get-DrmSystemInfo {
    [CmdletBinding()]
    param($Catalog, [switch]$SkipNetworkTest)
    $warn = New-Object System.Collections.Generic.List[string]
    $info = [ordered]@{}
    $cs = $null; $os = $null; $csp = $null; $bios = $null; $board = $null
    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { $warn.Add("Win32_ComputerSystem: $($_.Exception.Message)") }
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $warn.Add("Win32_OperatingSystem: $($_.Exception.Message)") }
    try { $csp = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop } catch { }
    try { $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop } catch { }
    try { $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1 } catch { }
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int](Get-DrmProp $os 'BuildNumber' 0)
    $edition = [string](Get-DrmRegistryValue $cv 'EditionID')
    $arch = Get-DrmArchitecture

    $chassis = @()
    try { $chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop | Select-Object -First 1).ChassisTypes) } catch { }
    $hasBattery = $false
    try { $hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1) } catch { }
    $laptopTypes = 8, 9, 10, 11, 14, 30, 31, 32
    $isLaptop = $hasBattery -or [bool]($chassis | Where-Object { $laptopTypes -contains [int]$_ }) -or ([int](Get-DrmProp $cs 'PCSystemType' 0) -eq 2)

    $info.ComputerName = $env:COMPUTERNAME
    $info.OS = [pscustomobject]@{
        Caption        = [string](Get-DrmProp $os 'Caption')
        Version        = [string](Get-DrmProp $os 'Version')
        Build          = $build
        UBR            = [int](Get-DrmRegistryValue $cv 'UBR')
        DisplayVersion = [string](Get-DrmRegistryValue $cv 'DisplayVersion')
        EditionId      = $edition
        Architecture   = $arch
        OSArchitecture = [string](Get-DrmProp $os 'OSArchitecture')
        InstallDate    = (Format-DrmDate (Get-DrmProp $os 'InstallDate'))
        LastBoot       = (Format-DrmDate (Get-DrmProp $os 'LastBootUpTime') 'yyyy-MM-dd HH:mm')
        Language       = [Globalization.CultureInfo]::InstalledUICulture.Name
        FreeMemoryGB   = [Math]::Round([double](Get-DrmProp $os 'FreePhysicalMemory' 0) / 1MB, 1)
    }

    $info.Hardware = [pscustomobject]@{
        Manufacturer          = ([string](Get-DrmProp $cs 'Manufacturer')).Trim()
        Model                 = ([string](Get-DrmProp $cs 'Model')).Trim()
        SystemFamily          = [string](Get-DrmProp $cs 'SystemFamily')
        SystemSku             = [string](Get-DrmProp $cs 'SystemSKUNumber')
        ProductVersion        = [string](Get-DrmProp $csp 'Version')
        SerialNumber          = [string](Get-DrmProp $bios 'SerialNumber')
        IsLaptop              = $isLaptop
        ChassisTypes          = ($chassis -join ',')
        BiosVendor            = [string](Get-DrmProp $bios 'Manufacturer')
        BiosVersion           = [string](Get-DrmProp $bios 'SMBIOSBIOSVersion')
        BiosDate              = (Format-DrmDate (Get-DrmProp $bios 'ReleaseDate'))
        BaseboardManufacturer = ([string](Get-DrmProp $board 'Manufacturer')).Trim()
        BaseboardProduct      = ([string](Get-DrmProp $board 'Product')).Trim()
        TotalMemoryGB         = [Math]::Round([double](Get-DrmProp $cs 'TotalPhysicalMemory' 0) / 1GB, 1)
    }

    $info.Cpu = @()
    try {
        $info.Cpu = @(Get-CimInstance Win32_Processor -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ Name = ($_.Name).Trim(); Cores = $_.NumberOfCores; Threads = $_.NumberOfLogicalProcessors; MaxMHz = $_.MaxClockSpeed; Virtualization = $_.VirtualizationFirmwareEnabled }
            })
    } catch { $warn.Add('อ่านข้อมูล CPU ไม่ได้') }

    $info.Memory = @()
    try {
        $info.Memory = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ Slot = $_.DeviceLocator; CapacityGB = [Math]::Round($_.Capacity / 1GB, 1); SpeedMHz = $_.Speed; ConfiguredMHz = $_.ConfiguredClockSpeed; Manufacturer = ([string]$_.Manufacturer).Trim(); PartNumber = ([string]$_.PartNumber).Trim() }
            })
    } catch { }

    $info.Gpu = @()
    try {
        $info.Gpu = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; DriverVersion = $_.DriverVersion; DriverDate = (Format-DrmDate (ConvertTo-DrmDate $_.DriverDate)); Resolution = $(if ($_.CurrentHorizontalResolution) { '{0}x{1} @{2}Hz' -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution, $_.CurrentRefreshRate } else { '' }); PnpId = $_.PNPDeviceID; Status = $_.Status }
            })
    } catch { }

    $info.Disks = @()
    try {
        $info.Disks = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ Name = $_.FriendlyName; MediaType = [string]$_.MediaType; BusType = [string]$_.BusType; SizeGB = [Math]::Round($_.Size / 1GB, 0); Health = [string]$_.HealthStatus; Firmware = $_.FirmwareVersion }
            })
    } catch {
        try {
            $info.Disks = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{ Name = $_.Model; MediaType = [string]$_.MediaType; BusType = [string]$_.InterfaceType; SizeGB = [Math]::Round($_.Size / 1GB, 0); Health = [string]$_.Status; Firmware = $_.FirmwareRevision }
                })
        } catch { }
    }

    $sysDrive = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
    $info.SystemDrive = [pscustomobject]@{ Drive = $sysDrive; FreeGB = 0; SizeGB = 0; FreePercent = 0 }
    try {
        $ld = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $sysDrive) -ErrorAction Stop
        $info.SystemDrive.FreeGB = [Math]::Round($ld.FreeSpace / 1GB, 1)
        $info.SystemDrive.SizeGB = [Math]::Round($ld.Size / 1GB, 1)
        if ($ld.Size) { $info.SystemDrive.FreePercent = [Math]::Round($ld.FreeSpace * 100.0 / $ld.Size, 0) }
    } catch { }

    $info.Network = @()
    try {
        $info.Network = @(Get-NetAdapter -Physical -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Description = $_.InterfaceDescription; Status = [string]$_.Status; LinkSpeed = [string]$_.LinkSpeed; DriverVersion = $_.DriverVersionString; DriverDate = $_.DriverDate; DriverProvider = $_.DriverProvider }
            })
    } catch { }

    # ความปลอดภัยที่มีผลต่อการติดตั้งไดรเวอร์
    $secureBoot = 'ไม่ทราบ'
    try { $secureBoot = if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'เปิด' } else { 'ปิด' } }
    catch { if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State')) { $secureBoot = 'ไม่รองรับ (BIOS แบบ Legacy)' } }
    $tpm = 'ไม่พบ'
    try {
        $t = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($t) { $tpm = 'TPM {0} (เปิดใช้: {1})' -f (([string]$t.SpecVersion).Split(',')[0]).Trim(), $t.IsEnabled_InitialValue }
    } catch { }
    $hvci = 'ไม่ทราบ'
    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        $hvci = if (@($dg.SecurityServicesRunning) -contains 2) { 'เปิด (Memory Integrity)' } else { 'ปิด' }
    } catch { }
    $startOpts = [string](Get-DrmRegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SystemStartOptions')
    $bitlocker = 'ไม่ทราบ'
    try {
        $bv = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter ("DriveLetter='{0}'" -f $sysDrive) -ErrorAction Stop
        if ($bv) { $bitlocker = if ($bv.ProtectionStatus -eq 1) { 'เปิด' } else { 'ปิด' } }
    } catch { }
    $info.Security = [pscustomobject]@{
        SecureBoot   = $secureBoot
        Tpm          = $tpm
        Hvci         = $hvci
        TestSigning  = ($startOpts -match 'TESTSIGNING')
        NoIntegrity  = ($startOpts -match 'DISABLE_INTEGRITY_CHECKS')
        BitLocker    = $bitlocker
        UefiFirmware = (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State')
    }

    # พลังงานและการตั้งค่าเกม
    $plan = ''
    try {
        $pc = (& powercfg.exe /getactivescheme) 2>$null | Out-String
        if ($pc -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\((.+)\)') { $plan = '{0} ({1})' -f $Matches[2], $Matches[1] }
    } catch { }
    $info.Performance = [pscustomobject]@{
        PowerPlan = $plan
        GameMode  = (Get-DrmTweakState -Name 'GameMode')
        Hags      = (Get-DrmTweakState -Name 'HAGS')
    }

    # บริการที่ต้องใช้ในการติดตั้ง
    $info.Services = @()
    foreach ($svc in 'wuauserv', 'bits', 'cryptsvc', 'TrustedInstaller', 'msiserver', 'DeviceInstall') {
        try {
            $s = Get-Service -Name $svc -ErrorAction Stop
            $info.Services += [pscustomobject]@{ Name = $svc; Status = [string]$s.Status; StartType = [string]$s.StartType }
        } catch { $info.Services += [pscustomobject]@{ Name = $svc; Status = 'ไม่พบ'; StartType = '' } }
    }

    $wuPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $info.UpdatePolicy = [pscustomobject]@{
        ExcludeDrivers   = ([int](Get-DrmRegistryValue $wuPol 'ExcludeWUDriversInQualityUpdate') -eq 1)
        WsusServer       = [string](Get-DrmRegistryValue $wuPol 'WUServer')
        DriverSearchMode = Get-DrmRegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig'
    }

    $winget = Get-DrmWingetPath
    $wingetVer = ''
    if ($winget) { try { $wingetVer = ((& $winget --version) 2>$null | Out-String).Trim() } catch { } }
    $info.Tools = [pscustomobject]@{
        Winget        = $winget
        WingetVersion = $wingetVer
        PowerShell    = $PSVersionTable.PSVersion.ToString()
        NetFxRelease  = [int](Get-DrmRegistryValue 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release')
        SevenZip      = (Get-Drm7ZipPath)
    }

    $info.PendingReboot = Get-DrmPendingReboot
    $info.Internet = if ($SkipNetworkTest) { $null } else { Test-DrmUrlReachable }
    if ($Catalog) { $info.Lifecycle = Get-DrmWindowsLifecycle -Build $build -EditionId $edition -Catalog $Catalog }
    $info.IsAdmin = Test-DrmIsAdmin
    $info.Warnings = $warn.ToArray()
    $info.ScannedAt = Get-DrmTimestamp
    return [pscustomobject]$info
}

function ConvertTo-DrmSystemRows {
    <# แปลงข้อมูลระบบเป็นแถว (หมวด/หัวข้อ/ค่า/ระดับ) สำหรับตารางในหน้าต่างและรายงาน #>
    param([Parameter(Mandatory)]$System)
    $rows = New-Object System.Collections.Generic.List[object]
    $add = { param($s, $k, $v, $lvl) $rows.Add([pscustomobject]@{ Section = $s; Item = $k; Value = [string]$v; Level = [string]$lvl }) }
    $os = $System.OS; $hw = $System.Hardware
    & $add 'Windows' 'ระบบปฏิบัติการ' ('{0} {1} (บิลด์ {2}.{3})' -f $os.Caption, $os.DisplayVersion, $os.Build, $os.UBR) ''
    & $add 'Windows' 'รุ่น (Edition) / สถาปัตยกรรม' ('{0} / {1}' -f $os.EditionId, $os.Architecture) ''
    if ($System.PSObject.Properties['Lifecycle'] -and $System.Lifecycle) {
        $lv = switch ($System.Lifecycle.Status) { 'EndOfSupport' { 'error' } 'EndingSoon' { 'warn' } 'Unknown' { '' } default { 'ok' } }
        & $add 'Windows' 'การสนับสนุนจาก Microsoft' $System.Lifecycle.Message $lv
    }
    & $add 'Windows' 'ติดตั้งเมื่อ / บูตล่าสุด' ('{0} / {1}' -f $os.InstallDate, $os.LastBoot) ''
    $pr = $System.PendingReboot
    & $add 'Windows' 'รอรีสตาร์ท' $(if ($pr.Pending) { 'ใช่ — ' + ($pr.Reasons -join ', ') } else { 'ไม่' }) $(if ($pr.Pending) { 'warn' } else { 'ok' })
    & $add 'เครื่อง' 'ผู้ผลิต / รุ่น' ('{0} {1} {2}' -f $hw.Manufacturer, $hw.Model, $hw.ProductVersion).Trim() ''
    & $add 'เครื่อง' 'ประเภท' $(if ($hw.IsLaptop) { 'โน้ตบุ๊ก/พกพา' } else { 'เดสก์ท็อป' }) ''
    & $add 'เครื่อง' 'เมนบอร์ด' ('{0} {1}' -f $hw.BaseboardManufacturer, $hw.BaseboardProduct) ''
    & $add 'เครื่อง' 'BIOS' ('{0} {1} ({2})' -f $hw.BiosVendor, $hw.BiosVersion, $hw.BiosDate) ''
    & $add 'เครื่อง' 'Serial / Service Tag' $hw.SerialNumber ''
    foreach ($c in @($System.Cpu)) { & $add 'ฮาร์ดแวร์' 'CPU' ('{0} ({1} คอร์/{2} เธรด, VT: {3})' -f $c.Name, $c.Cores, $c.Threads, $c.Virtualization) '' }
    & $add 'ฮาร์ดแวร์' 'หน่วยความจำ' ('{0} GB ({1} แถว)' -f $hw.TotalMemoryGB, @($System.Memory).Count) $(if ($hw.TotalMemoryGB -lt 8) { 'warn' } else { '' })
    foreach ($m in @($System.Memory)) { & $add 'ฮาร์ดแวร์' ('RAM ' + $m.Slot) ('{0} GB {1} MHz {2} {3}' -f $m.CapacityGB, $m.ConfiguredMHz, $m.Manufacturer, $m.PartNumber) '' }
    foreach ($g in @($System.Gpu)) { & $add 'ฮาร์ดแวร์' 'การ์ดจอ' ('{0} — ไดรเวอร์ {1} ({2}) {3}' -f $g.Name, $g.DriverVersion, $g.DriverDate, $g.Resolution) '' }
    foreach ($d in @($System.Disks)) {
        $lvl = if ($d.Health -and $d.Health -notmatch 'Healthy|OK') { 'error' } else { '' }
        & $add 'ฮาร์ดแวร์' 'ดิสก์' ('{0} {1} GB {2}/{3} สุขภาพ {4} FW {5}' -f $d.Name, $d.SizeGB, $d.MediaType, $d.BusType, $d.Health, $d.Firmware) $lvl
    }
    $sd = $System.SystemDrive
    & $add 'ฮาร์ดแวร์' ('พื้นที่ว่าง ' + $sd.Drive) ('{0} GB จาก {1} GB ({2}%)' -f $sd.FreeGB, $sd.SizeGB, $sd.FreePercent) $(if ($sd.FreeGB -lt 15) { 'error' } elseif ($sd.FreeGB -lt 30) { 'warn' } else { 'ok' })
    foreach ($n in @($System.Network)) { & $add 'ฮาร์ดแวร์' 'เครือข่าย' ('{0} — {1} {2} ไดรเวอร์ {3}' -f $n.Description, $n.Status, $n.LinkSpeed, $n.DriverVersion) '' }
    $s = $System.Security
    & $add 'ความปลอดภัย' 'Secure Boot' $s.SecureBoot $(if ($s.SecureBoot -eq 'เปิด') { 'ok' } else { 'warn' })
    & $add 'ความปลอดภัย' 'TPM' $s.Tpm ''
    & $add 'ความปลอดภัย' 'Memory Integrity (HVCI)' $s.Hvci ''
    & $add 'ความปลอดภัย' 'BitLocker ไดรฟ์ระบบ' $s.BitLocker ''
    & $add 'ความปลอดภัย' 'โหมด Test Signing' $(if ($s.TestSigning) { 'เปิด (ไม่ปลอดภัย)' } else { 'ปิด' }) $(if ($s.TestSigning -or $s.NoIntegrity) { 'error' } else { 'ok' })
    $p = $System.Performance
    & $add 'ประสิทธิภาพ' 'แผนพลังงาน' $p.PowerPlan ''
    & $add 'ประสิทธิภาพ' 'Game Mode' $(if ($p.GameMode) { 'เปิด' } else { 'ปิด' }) ''
    & $add 'ประสิทธิภาพ' 'GPU scheduling (HAGS)' $(if ($p.Hags) { 'เปิด' } else { 'ปิด/ค่าเริ่มต้น' }) ''
    foreach ($svc in @($System.Services)) {
        $lvl = if ($svc.StartType -eq 'Disabled') { 'error' } else { '' }
        & $add 'บริการ' $svc.Name ('{0} ({1})' -f $svc.Status, $svc.StartType) $lvl
    }
    $up = $System.UpdatePolicy
    if ($up.ExcludeDrivers) { & $add 'นโยบาย' 'ไดรเวอร์จาก Windows Update' 'ถูกนโยบายปิดไว้ (ExcludeWUDriversInQualityUpdate)' 'warn' }
    if ($up.WsusServer) { & $add 'นโยบาย' 'WSUS' $up.WsusServer 'warn' }
    $t = $System.Tools
    & $add 'เครื่องมือ' 'winget' $(if ($t.Winget) { $t.WingetVersion } else { 'ไม่พบ — จะซ่อม/ติดตั้ง App Installer ให้' }) $(if ($t.Winget) { 'ok' } else { 'warn' })
    & $add 'เครื่องมือ' 'PowerShell' $t.PowerShell ''
    & $add 'เครื่องมือ' '7-Zip' $(if ($t.SevenZip) { $t.SevenZip } else { 'ไม่มี (ไฟล์ .7z/.rar จะใช้ tar.exe ของ Windows แทน)' }) ''
    if ($null -ne $System.Internet) { & $add 'เครือข่าย' 'เชื่อมต่อเซิร์ฟเวอร์ Microsoft' $(if ($System.Internet) { 'ได้' } else { 'ไม่ได้' }) $(if ($System.Internet) { 'ok' } else { 'error' }) }
    & $add 'สิทธิ์' 'Administrator' $(if ($System.IsAdmin) { 'ใช่' } else { 'ไม่ — ต้องรันแบบ Administrator' }) $(if ($System.IsAdmin) { 'ok' } else { 'error' })
    foreach ($w in @($System.Warnings)) { & $add 'คำเตือน' 'การสแกน' $w 'warn' }
    return , $rows.ToArray()
}

# ---------------------------------------------------------------------------
# อุปกรณ์ ไดรเวอร์ และลำดับการติดตั้ง
# ---------------------------------------------------------------------------
function Get-DrmDriverOrder {
    <# คืนลำดับติดตั้ง (Index ยิ่งน้อยยิ่งติดตั้งก่อน) จากคลาสและชื่อของไดรเวอร์/ไฟล์ #>
    param([string]$Class = '', [string]$Name = '')
    $generic = $Class -match $script:GenericClasses
    $byName = @()
    if ($Name) {
        foreach ($r in $script:OrderRules) {
            if ($r.Name -and $Name -match $r.Name) {
                if (-not $r.Class -or $generic -or $Class -match $r.Class) { $byName += $r }
            }
        }
    }
    if ($byName.Count -gt 0) {
        $best = $byName | Sort-Object { $_.Index } | Select-Object -First 1
        return [pscustomobject]@{ Index = $best.Index; Group = $best.Group }
    }
    if ($Class) {
        foreach ($r in $script:OrderRules) {
            if ($r.Class -and $Class -match $r.Class) { return [pscustomobject]@{ Index = $r.Index; Group = $r.Group } }
        }
    }
    return [pscustomobject]@{ Index = 90; Group = 'อื่น ๆ' }
}

function Get-DrmVendorId {
    param([string[]]$HardwareIds)
    foreach ($h in @($HardwareIds)) {
        if ($h -match '(?:VEN|VID)_([0-9A-Fa-f]{4})') { return $Matches[1].ToUpperInvariant() }
    }
    return ''
}

function Get-DrmCertLevelFromSigner {
    param([string]$Signer, $IsSigned, [string]$InfName)
    if ($InfName -and $InfName -notmatch '^oem\d+\.inf$') { return 'Inbox' }
    if ($Signer -match 'Microsoft Windows Hardware Compatibility Publisher') { return 'WHQL' }
    if ($Signer -match '^Microsoft Windows$|Microsoft Windows Publisher') { return 'Inbox' }
    if ($Signer -match 'Microsoft') { return 'Microsoft' }
    if ($null -ne $IsSigned -and -not [bool]$IsSigned) { return 'Unsigned' }
    if ($Signer) { return 'Vendor' }
    return 'Unknown'
}

function Get-DrmDriverPackages {
    <# แพ็กเกจไดรเวอร์ของผู้ผลิตใน Driver Store (oem*.inf) พร้อมระดับการรับรองจาก catalog #>
    [CmdletBinding()]
    param([switch]$SkipCertificates)
    $list = New-Object System.Collections.Generic.List[object]
    $pk = @()
    try { $pk = @(Get-WindowsDriver -Online -ErrorAction Stop) }
    catch { Write-DrmLog ("อ่าน Driver Store ไม่ได้: {0}" -f $_.Exception.Message) -Level Warn; return , $list.ToArray() }
    foreach ($p in $pk) {
        $orig = [string]$p.OriginalFileName
        $cat = $null; $level = 'Unknown'
        if (-not $SkipCertificates -and $orig) {
            $dir = Split-Path -Path $orig -Parent
            $cat = Get-ChildItem -LiteralPath $dir -Filter '*.cat' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cat) { $level = (Get-DrmFileSignature -Path $cat.FullName).CertLevel } else { $level = 'Unsigned' }
        }
        $list.Add([pscustomobject]@{
                PublishedName    = [string]$p.Driver
                OriginalFileName = $orig
                InfBaseName      = $(if ($orig) { [IO.Path]::GetFileName($orig) } else { '' })
                Provider         = [string]$p.ProviderName
                ClassName        = [string]$p.ClassName
                Version          = [string]$p.Version
                Date             = (Format-DrmDate $p.Date)
                BootCritical     = [bool]$p.BootCritical
                CatalogFile      = $(if ($cat) { $cat.FullName } else { '' })
                CertLevel        = $level
            })
    }
    return , $list.ToArray()
}

function Get-DrmDeviceInventory {
    [CmdletBinding()]
    param($Packages = @(), $Catalog)
    $vendorMap = @{}
    if ($Catalog -and $Catalog.vendorIds) { foreach ($p in $Catalog.vendorIds.PSObject.Properties) { $vendorMap[$p.Name.ToUpperInvariant()] = $p.Value } }
    $pkgMap = @{}
    foreach ($p in @($Packages)) { if ($p.PublishedName) { $pkgMap[$p.PublishedName.ToLowerInvariant()] = $p } }
    $signed = @{}
    try {
        foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)) { if ($d.DeviceID) { $signed[$d.DeviceID] = $d } }
    } catch { Write-DrmLog ("อ่าน Win32_PnPSignedDriver ไม่ได้: {0}" -f $_.Exception.Message) -Level Warn }
    $entities = @()
    try { $entities = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop) } catch { Write-DrmLog ("อ่าน Win32_PnPEntity ไม่ได้: {0}" -f $_.Exception.Message) -Level Error }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($e in $entities) {
        if (-not $e.DeviceID) { continue }
        $d = $signed[$e.DeviceID]
        $inf = [string](Get-DrmProp $d 'InfName' '')
        $pkg = $null
        if ($inf) { $pkg = $pkgMap[$inf.ToLowerInvariant()] }
        $cert = if (-not $d -or -not (Get-DrmProp $d 'DriverVersion')) { 'None' }
        elseif ($pkg -and $pkg.CertLevel -and $pkg.CertLevel -ne 'Unknown') { $pkg.CertLevel }
        else { Get-DrmCertLevelFromSigner -Signer ([string](Get-DrmProp $d 'Signer' '')) -IsSigned (Get-DrmProp $d 'IsSigned') -InfName $inf }
        $hw = @($e.HardwareID | Where-Object { $_ })
        $compat = @($e.CompatibleID | Where-Object { $_ })
        $vid = Get-DrmVendorId $hw
        $class = [string]$e.PNPClass
        $name = [string]$e.Name
        $ord = Get-DrmDriverOrder -Class $class -Name $name
        $code = [int]$e.ConfigManagerErrorCode
        $problem = if ($code -ne 0) { if ($script:ProblemText.ContainsKey($code)) { 'รหัส {0}: {1}' -f $code, $script:ProblemText[$code] } else { "รหัส $code" } } else { '' }
        $present = $true
        if ($e.PSObject.Properties['Present'] -and $null -ne $e.Present) { $present = [bool]$e.Present }
        $level = if ($code -ne 0 -and $code -ne 22) { 'error' } elseif ($cert -in 'Unsigned', 'Invalid') { 'error' } elseif ($cert -in 'Vendor', 'Attested') { 'warn' } else { '' }
        $list.Add([pscustomobject]@{
                DeviceId       = [string]$e.DeviceID
                Name           = $name
                Class          = $class
                Manufacturer   = [string]$e.Manufacturer
                Present        = $present
                Status         = [string]$e.Status
                ProblemCode    = $code
                ProblemText    = $problem
                HardwareIds    = $hw
                CompatibleIds  = $compat
                VendorId       = $vid
                VendorName     = $(if ($vid -and $vendorMap.ContainsKey($vid)) { $vendorMap[$vid] } else { '' })
                DriverVersion  = [string](Get-DrmProp $d 'DriverVersion' '')
                DriverDate     = (Format-DrmDate (ConvertTo-DrmDate (Get-DrmProp $d 'DriverDate')))
                DriverProvider = [string](Get-DrmProp $d 'DriverProviderName' '')
                InfName        = $inf
                Signer         = [string](Get-DrmProp $d 'Signer' '')
                CertLevel      = $cert
                CertText       = (Get-DrmCertText $cert)
                IsInbox        = ($cert -eq 'Inbox')
                OrderIndex     = $ord.Index
                OrderGroup     = $ord.Group
                Level          = $level
            })
    }
    $sorted = @($list.ToArray() | Sort-Object OrderIndex, Class, Name)
    return , $sorted
}

function Get-DrmOldDriverPackages {
    <# แพ็กเกจรุ่นเก่าที่มีรุ่นใหม่กว่าของแพ็กเกจเดียวกันอยู่แล้ว และไม่มีอุปกรณ์ใดใช้งาน (ลบได้อย่างปลอดภัยด้วย pnputil โดยไม่ใช้ /force) #>
    param($Packages = @(), $Devices = @())
    $inUse = @{}
    foreach ($d in @($Devices)) { if ($d.InfName) { $inUse[$d.InfName.ToLowerInvariant()] = $true } }
    $result = New-Object System.Collections.Generic.List[object]
    $groups = @($Packages) | Where-Object { $_.InfBaseName } | Group-Object { '{0}|{1}|{2}' -f $_.InfBaseName.ToLowerInvariant(), $_.Provider, $_.ClassName }
    foreach ($g in $groups) {
        if ($g.Count -lt 2) { continue }
        $newest = $null
        foreach ($p in $g.Group) {
            if (-not $newest) { $newest = $p; continue }
            $c = Compare-DrmVersion $p.Version $newest.Version
            if ($c -gt 0 -or ($c -eq 0 -and [string]$p.Date -gt [string]$newest.Date)) { $newest = $p }
        }
        foreach ($p in $g.Group) {
            if ($p -eq $newest) { continue }
            if ($inUse.ContainsKey($p.PublishedName.ToLowerInvariant())) { continue }
            if ($p.BootCritical) { continue }
            if ((Compare-DrmVersion $p.Version $newest.Version) -ge 0) { continue }
            $result.Add([pscustomobject]@{ PublishedName = $p.PublishedName; InfBaseName = $p.InfBaseName; Provider = $p.Provider; ClassName = $p.ClassName; Version = $p.Version; Date = $p.Date; NewerVersion = $newest.Version })
        }
    }
    return , $result.ToArray()
}

# ---------------------------------------------------------------------------
# ผู้ผลิตเครื่อง (OEM) และผู้ผลิตชิ้นส่วน
# ---------------------------------------------------------------------------
function Get-DrmOemProfile {
    param([Parameter(Mandatory)]$System, [Parameter(Mandatory)]$Catalog)
    $hw = $System.Hardware
    $junk = '^(System manufacturer|System Manufacturer|To Be Filled By O\.E\.M\.|Default string|O\.E\.M\.|OEM|Not Applicable|Not Specified|)$'
    $mf = [string]$hw.Manufacturer
    $isBoardVendor = $false
    if ($mf -match $junk) { $mf = [string]$hw.BaseboardManufacturer; $isBoardVendor = $true }
    $modelText = ('{0} {1} {2}' -f $hw.Model, $hw.ProductVersion, $hw.SystemFamily)
    foreach ($t in @($Catalog.oemTools)) {
        if ($mf -notmatch $t.match) { continue }
        $mm = Get-DrmProp $t 'modelMatch'
        if ($mm -and $modelText -notmatch $mm) { continue }
        $mx = Get-DrmProp $t 'modelExclude'
        if ($mx -and $modelText -match $mx) { continue }
        return [pscustomobject]@{
            Vendor        = $t.vendor
            Name          = $t.name
            Automated     = [bool](Get-DrmProp $t 'automated' $false)
            WindowsUpdate = [bool](Get-DrmProp $t 'windowsUpdate' $false)
            Winget        = [string](Get-DrmProp $t 'winget' '')
            Exe           = @(Get-DrmProp $t 'exe' @())
            ExeName       = [string](Get-DrmProp $t 'exeName' '')
            Launch        = @(Get-DrmProp $t 'launch' @())
            ScanArgs      = [string](Get-DrmProp $t 'scanArgs' '')
            ApplyArgs     = [string](Get-DrmProp $t 'applyArgs' '')
            Report        = [string](Get-DrmProp $t 'report' '')
            WaitProcess   = @(Get-DrmProp $t 'waitProcess' @())
            SuccessCodes  = @(Get-DrmProp $t 'successCodes' @(0))
            RebootCodes   = @(Get-DrmProp $t 'rebootCodes' @())
            NoUpdateCodes = @(Get-DrmProp $t 'noUpdateCodes' @())
            SupportUrl    = [string]$t.supportUrl
            Note          = [string](Get-DrmProp $t 'note' '')
            BoardVendor   = $isBoardVendor
            Manufacturer  = $mf
        }
    }
    return [pscustomobject]@{
        Vendor = 'Other'; Name = 'Windows Update + เครื่องมือผู้ผลิตชิ้นส่วน'; Automated = $false; WindowsUpdate = $true; Winget = ''; Exe = @(); ExeName = ''; Launch = @()
        ScanArgs = ''; ApplyArgs = ''; Report = ''; WaitProcess = @(); SuccessCodes = @(0); RebootCodes = @(); NoUpdateCodes = @(); SupportUrl = ''
        Note = "ไม่พบเครื่องมืออัปเดตเฉพาะของผู้ผลิต '$mf' — ใช้ไฟล์จากเว็บผู้ผลิต (แท็บติดตั้งจากไฟล์) ร่วมกับ Windows Update"
        BoardVendor = $isBoardVendor; Manufacturer = $mf
    }
}

function Find-DrmToolExe {
    param([Parameter(Mandatory)]$Tool)
    foreach ($p in @($Tool.Exe)) {
        $x = Expand-DrmPath $p
        if ($x -and (Test-Path -LiteralPath $x)) { return $x }
    }
    if ($Tool.ExeName) {
        $c = Get-Command $Tool.ExeName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $c.Source }
        if ($Tool.Winget) {
            foreach ($base in @((Expand-DrmPath '%LOCALAPPDATA%\Microsoft\WinGet\Packages'), (Expand-DrmPath '%ProgramFiles%\WinGet\Packages'))) {
                if (-not $base -or -not (Test-Path -LiteralPath $base)) { continue }
                $hit = Get-ChildItem -LiteralPath $base -Directory -Filter ($Tool.Winget + '*') -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -Filter $Tool.ExeName -File -ErrorAction SilentlyContinue } | Select-Object -First 1
                if ($hit) { return $hit.FullName }
            }
        }
    }
    return $null
}

function Get-DrmComponentVendorTools {
    param($Devices = @(), $Catalog, $OemProfile)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($v in @($Catalog.componentVendors)) {
        $ids = @($v.ids)
        $cm = Get-DrmProp $v 'classMatch'
        $hits = @($Devices | Where-Object { $_.VendorId -and $ids -contains $_.VendorId -and (-not $cm -or $_.Class -match $cm) })
        if ($hits.Count -eq 0) { continue }
        $diy = ($OemProfile -and ($OemProfile.Vendor -eq 'Other' -or $OemProfile.BoardVendor))
        $out.Add([pscustomobject]@{
                Vendor   = $v.vendor
                Name     = $v.name
                Winget   = [string](Get-DrmProp $v 'winget' '')
                Url      = [string]$v.url
                Note     = [string]$v.note
                Devices  = @($hits | Select-Object -ExpandProperty Name -Unique)
                Default  = ($diy -and [bool](Get-DrmProp $v 'winget'))
            })
    }
    return , $out.ToArray()
}

function Read-DrmOemReport {
    param([string]$Kind, [string]$Dir)
    $items = New-Object System.Collections.Generic.List[object]
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return , $items.ToArray() }
    try {
        if ($Kind -eq 'dell') {
            foreach ($f in Get-ChildItem -LiteralPath $Dir -Filter '*.xml' -Recurse -File -ErrorAction SilentlyContinue) {
                [xml]$x = [IO.File]::ReadAllText($f.FullName)
                foreach ($n in @($x.SelectNodes('//update'))) {
                    $get = { param($k) $c = $n.SelectSingleNode($k); if ($c) { $c.InnerText } else { '' } }
                    $items.Add([pscustomobject]@{ Name = (& $get 'name'); Version = (& $get 'version'); Category = (& $get 'category'); Type = (& $get 'type'); Date = (& $get 'date'); Urgency = (& $get 'urgency') })
                }
            }
        }
        elseif ($Kind -eq 'hpia') {
            foreach ($f in Get-ChildItem -LiteralPath $Dir -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue) {
                $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
                $recs = @()
                if ($j.PSObject.Properties['HPIA'] -and $j.HPIA.PSObject.Properties['Recommendations']) { $recs = @($j.HPIA.Recommendations) }
                foreach ($r in $recs) {
                    $items.Add([pscustomobject]@{ Name = (Get-DrmProp $r 'Name' ''); Version = (Get-DrmProp $r 'ReferenceVersion' ''); Installed = (Get-DrmProp $r 'TargetVersion' ''); Category = (Get-DrmProp $r 'TargetComponent' ''); Type = (Get-DrmProp $r 'RecommendationValue' ''); Date = ''; Urgency = (Get-DrmProp $r 'SoftPaqId' '') })
                }
            }
        }
    } catch { Write-DrmLog ("อ่านรายงานของผู้ผลิตไม่ได้: {0}" -f $_.Exception.Message) -Level Warn }
    return , $items.ToArray()
}

function Invoke-DrmOemTool {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Tool, [ValidateSet('Scan', 'Apply')][string]$Mode = 'Apply', [switch]$InstallTool, [string]$ItemId = 'oem')
    $session = Get-DrmSession
    if (-not $Tool.Automated) {
        if ($Mode -eq 'Apply') {
            if ($Tool.Winget -and $InstallTool) {
                $r = Install-DrmWingetPackage -Id $Tool.Winget -ItemId $ItemId
                Write-DrmLog ("{0}: {1}" -f $Tool.Name, $r.StatusText)
            }
            $launched = $false
            foreach ($l in @($Tool.Launch)) {
                $x = Expand-DrmPath $l
                if ($x -and (Test-Path -LiteralPath $x) -and -not $script:DrmState.DryRun) { Start-Process -FilePath $x; $launched = $true; break }
            }
            if (-not $launched -and $Tool.SupportUrl -and -not $script:DrmState.DryRun) { Start-Process $Tool.SupportUrl }
            if ($script:DrmState.DryRun) { return New-DrmResult -Status 'DryRun' -Detail ("จะเปิด {0}" -f $Tool.SupportUrl) }
            return New-DrmResult -Status 'Manual' -Detail $Tool.Note -Method 'oem-manual'
        }
        return [pscustomobject]@{ Status = 'Manual'; Updates = @(); Detail = $Tool.Note; ExitCode = $null; RebootRequired = $false }
    }
    $exe = Find-DrmToolExe -Tool $Tool
    if (-not $exe -and $InstallTool -and $Tool.Winget) {
        Write-DrmLog ("ติดตั้งเครื่องมือของผู้ผลิต: {0} ({1})" -f $Tool.Name, $Tool.Winget) -Level Step
        $r = Install-DrmWingetPackage -Id $Tool.Winget -ItemId $ItemId
        if ($r.Status -eq 'DryRun') { return $r }
        $exe = Find-DrmToolExe -Tool $Tool
    }
    if (-not $exe) {
        $msg = "ไม่พบ {0} — เลือกรายการนี้แล้วกดติดตั้งเพื่อให้โปรแกรมติดตั้งเครื่องมือของผู้ผลิตก่อน" -f $Tool.Name
        if ($Mode -eq 'Scan') { return [pscustomobject]@{ Status = 'Missing'; Updates = @(); Detail = $msg; ExitCode = $null; RebootRequired = $false } }
        return New-DrmResult -Status 'Failed' -Detail $msg -Method 'oem'
    }
    $stamp = Get-DrmTimestamp -Format 'HHmmss'
    $reportDir = Join-Path $session.WorkDir ("oem-{0}-{1}" -f $Mode.ToLowerInvariant(), $stamp)
    $downloadDir = Join-Path $session.WorkDir 'oem-downloads'
    New-Item -ItemType Directory -Force -Path $reportDir, $downloadDir | Out-Null
    $logFile = Join-Path $session.LogDir ("OEM_{0}_{1}_{2}.log" -f $Tool.Vendor, $Mode, $stamp)
    $tpl = if ($Mode -eq 'Scan') { $Tool.ScanArgs } else { $Tool.ApplyArgs }
    if (-not $tpl) {
        return [pscustomobject]@{ Status = 'Skipped'; Updates = @(); Detail = ("{0} ไม่มีโหมดสแกนแยก — จะติดตั้งทั้งหมดตอนกดติดตั้ง" -f $Tool.Name); ExitCode = $null; RebootRequired = $false }
    }
    $argLine = Expand-DrmTemplate $tpl @{ ReportDir = $reportDir; LogFile = $logFile; DownloadDir = $downloadDir }
    $r = Invoke-DrmProcess -FilePath $exe -Arguments $argLine -TimeoutMinutes 180 -Capture -WaitForProcessNames $Tool.WaitProcess -IgnoreDryRun:($Mode -eq 'Scan')
    $code = $r.ExitCode
    $reboot = ($null -ne $code -and @($Tool.RebootCodes) -contains [int]$code)
    $noUpdate = ($null -ne $code -and @($Tool.NoUpdateCodes) -contains [int]$code)
    $ok = ($null -ne $code -and @($Tool.SuccessCodes) -contains [int]$code)
    if ($Mode -eq 'Scan') {
        $updates = Read-DrmOemReport -Kind $Tool.Report -Dir $reportDir
        $status = if ($noUpdate -or ($ok -and $updates.Count -eq 0)) { 'UpToDate' } elseif ($ok) { 'Found' } else { 'Failed' }
        return [pscustomobject]@{ Status = $status; Updates = $updates; Detail = ("exit {0}, พบ {1} รายการ" -f (Format-DrmExitCode $code), $updates.Count); ExitCode = $code; RebootRequired = $reboot; LogFile = $logFile }
    }
    if ($r.DryRun) { return New-DrmResult -Status 'DryRun' -Detail $r.Command -Method 'oem' }
    if ($r.TimedOut) { return New-DrmResult -Status 'Failed' -Detail 'หมดเวลา — ตรวจ log ของผู้ผลิต' -Method 'oem' }
    if ($noUpdate) { return New-DrmResult -Status 'UpToDate' -Detail ("{0}: ไม่มีอัปเดตใหม่" -f $Tool.Name) -ExitCode $code -Method 'oem' }
    if ($ok) { return New-DrmResult -Status $(if ($reboot) { 'InstalledReboot' } else { 'Installed' }) -Detail ("log: {0}" -f $logFile) -ExitCode $code -RebootRequired $reboot -Method 'oem' }
    return New-DrmResult -Status 'Failed' -Detail ("{0} คืนรหัส {1} — ดู {2}" -f $Tool.Name, (Format-DrmExitCode $code), $logFile) -ExitCode $code -Method 'oem'
}

# ---------------------------------------------------------------------------
# Windows Update (ไดรเวอร์ที่ Microsoft รับรอง)
# ---------------------------------------------------------------------------
function Compare-DrmDriverOffer {
    <# เทียบไดรเวอร์ที่ Windows Update เสนอกับที่ติดตั้งอยู่ ใช้วันที่ก่อน (แบบเดียวกับการจัดอันดับของ PnP) แล้วจึงเวอร์ชัน #>
    param([string]$InstalledVersion, $InstalledDate, [string]$OfferedVersion, $OfferedDate, [int]$ProblemCode = 0, [bool]$HasDevice = $true)
    if (-not $HasDevice) { return 'NoDevice' }
    if ((@(1, 18, 28, 31, 39) -contains $ProblemCode) -or -not $InstalledVersion) { return 'Missing' }
    $id = ConvertTo-DrmDate $InstalledDate
    $od = ConvertTo-DrmDate $OfferedDate
    if ($id -and $od -and $id.Date -ne $od.Date) { if ($od.Date -gt $id.Date) { return 'Newer' } else { return 'Older' } }
    if ($OfferedVersion -and $InstalledVersion) {
        $c = Compare-DrmVersion $OfferedVersion $InstalledVersion
        if ($c -gt 0) { return 'Newer' }
        if ($c -lt 0) { return 'Older' }
        return 'Same'
    }
    return 'Unknown'
}

$script:ComparisonText = @{
    Missing = 'ยังไม่มีไดรเวอร์ — ควรติดตั้ง'; Newer = 'ใหม่กว่าที่ติดตั้งอยู่'; Same = 'รุ่นเดียวกัน'; Older = 'เก่ากว่าที่ติดตั้งอยู่'
    Unknown = 'เทียบไม่ได้'; NoDevice = 'ไม่พบอุปกรณ์ที่ตรงกันตอนนี้'
}

function Get-DrmWuSearch {
    param([switch]$Refresh)
    if (-not $Refresh -and $script:DrmState.WuCache) { return $script:DrmState.WuCache }
    Write-DrmLog 'ค้นหาไดรเวอร์จาก Windows Update (เซิร์ฟเวอร์ของ Microsoft)...' -Level Step
    $session = New-Object -ComObject Microsoft.Update.Session
    try { $session.ClientApplicationID = 'DriverRuntimeManager' } catch { }
    $searcher = $session.CreateUpdateSearcher()
    $searcher.ServerSelection = 2   # ssWindowsUpdate
    $searcher.Online = $true
    $result = $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    $script:DrmState.WuCache = @{ Session = $session; Result = $result; Time = (Get-Date) }
    return $script:DrmState.WuCache
}

function Find-DrmWindowsUpdateDrivers {
    [CmdletBinding()]
    param($Devices = @())
    $out = New-Object System.Collections.Generic.List[object]
    $wu = $null
    try { $wu = Get-DrmWuSearch -Refresh }
    catch {
        Write-DrmLog ("ค้นหา Windows Update ไม่สำเร็จ: {0}" -f $_.Exception.Message) -Level Error
        return , $out.ToArray()
    }
    # จับคู่ด้วย Hardware ID ก่อน แล้วจึงใช้ Compatible ID (แบบเดียวกับที่ PnP จัดอันดับ)
    $index = @{}
    foreach ($field in 'HardwareIds', 'CompatibleIds') {
        foreach ($d in @($Devices | Sort-Object { -not $_.Present })) {
            foreach ($h in @($d.$field)) { if ($h) { $k = $h.ToUpperInvariant(); if (-not $index.ContainsKey($k)) { $index[$k] = $d } } }
        }
    }
    foreach ($u in $wu.Result.Updates) {
        $hw = ([string]$u.DriverHardwareID).ToUpperInvariant()
        $dev = $null
        if ($hw -and $index.ContainsKey($hw)) { $dev = $index[$hw] }
        $offerVer = ConvertTo-DrmVersion ([string]$u.Title)
        $offerDate = $null
        try { $offerDate = $u.DriverVerDate } catch { }
        $cmp = Compare-DrmDriverOffer -InstalledVersion (Get-DrmProp $dev 'DriverVersion' '') -InstalledDate (Get-DrmProp $dev 'DriverDate') -OfferedVersion $offerVer -OfferedDate $offerDate -ProblemCode ([int](Get-DrmProp $dev 'ProblemCode' 0)) -HasDevice ([bool]$dev)
        $ord = Get-DrmDriverOrder -Class ([string]$u.DriverClass) -Name ([string]$u.Title)
        $size = 0
        try { $size = [Math]::Round([double]$u.MaxDownloadSize / 1MB, 1) } catch { }
        $out.Add([pscustomobject]@{
                Id               = 'wu:' + $u.Identity.UpdateID
                UpdateId         = [string]$u.Identity.UpdateID
                Title            = [string]$u.Title
                DriverClass      = [string]$u.DriverClass
                Manufacturer     = [string]$u.DriverManufacturer
                Model            = [string]$u.DriverModel
                Provider         = [string]$u.DriverProvider
                HardwareId       = $hw
                OfferedVersion   = $offerVer
                OfferedDate      = (Format-DrmDate $offerDate)
                DeviceName       = [string](Get-DrmProp $dev 'Name' '')
                InstalledVersion = [string](Get-DrmProp $dev 'DriverVersion' '')
                InstalledDate    = [string](Get-DrmProp $dev 'DriverDate' '')
                Comparison       = $cmp
                ComparisonText   = $script:ComparisonText[$cmp]
                Selected         = (@('Missing', 'Newer') -contains $cmp)
                SizeMB           = $size
                OrderIndex       = $ord.Index
                OrderGroup       = $ord.Group
            })
    }
    Write-DrmLog ("Windows Update เสนอไดรเวอร์ {0} รายการ" -f $out.Count) -Level Ok
    $sorted = @($out.ToArray() | Sort-Object OrderIndex, Title)
    return , $sorted
}

function Install-DrmWindowsUpdateDriver {
    param([Parameter(Mandatory)][string]$UpdateId, [string]$ItemId)
    if ($script:DrmState.DryRun) { return New-DrmResult -Status 'DryRun' -Detail ("จะดาวน์โหลดและติดตั้ง Windows Update {0}" -f $UpdateId) -Method 'windowsupdate' }
    $wu = Get-DrmWuSearch
    $u = $null
    foreach ($x in $wu.Result.Updates) { if ($x.Identity.UpdateID -eq $UpdateId) { $u = $x; break } }
    if (-not $u) { return New-DrmResult -Status 'NotOffered' -Detail 'Windows Update ไม่เสนอรายการนี้แล้ว (อาจติดตั้งรุ่นที่ใหม่กว่าจากผู้ผลิตไปแล้ว)' -Method 'windowsupdate' }
    try { if (-not $u.EulaAccepted) { $u.AcceptEula() } } catch { }
    $col = New-Object -ComObject Microsoft.Update.UpdateColl
    [void]$col.Add($u)
    Set-DrmItemStatus -Id $ItemId -Status 'Downloading'
    $dl = $wu.Session.CreateUpdateDownloader()
    $dl.Updates = $col
    $dr = $dl.Download()
    if (@(2, 3) -notcontains [int]$dr.ResultCode) { return New-DrmResult -Status 'Failed' -Detail ("ดาวน์โหลดไม่สำเร็จ (ResultCode {0}, HResult 0x{1:X8})" -f $dr.ResultCode, ($dr.HResult -band 0xFFFFFFFFL)) -Method 'windowsupdate' }
    Set-DrmItemStatus -Id $ItemId -Status 'Installing'
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $inst = $wu.Session.CreateUpdateInstaller()
            $inst.Updates = $col
            $ir = $inst.Install()
            break
        } catch {
            if ($attempt -ge 3) { return New-DrmResult -Status 'Failed' -Detail ("ติดตั้งไม่สำเร็จ: {0}" -f $_.Exception.Message) -Method 'windowsupdate' }
            Write-DrmLog 'Windows Update กำลังติดตั้งรายการอื่นอยู่ — รอ 30 วินาทีแล้วลองใหม่' -Level Warn
            Start-Sleep -Seconds 30
        }
    }
    $ur = $ir.GetUpdateResult(0)
    $hr = '0x{0:X8}' -f ([int64]$ur.HResult -band 0xFFFFFFFFL)
    switch ([int]$ur.ResultCode) {
        2 { return New-DrmResult -Status $(if ($ir.RebootRequired) { 'InstalledReboot' } else { 'Installed' }) -RebootRequired ([bool]$ir.RebootRequired) -Method 'windowsupdate' -ExitCode 0 }
        3 { return New-DrmResult -Status 'Installed' -Detail ("สำเร็จแต่มีคำเตือน {0}" -f $hr) -RebootRequired ([bool]$ir.RebootRequired) -Method 'windowsupdate' }
        default { return New-DrmResult -Status 'Failed' -Detail ("ResultCode {0}, HResult {1}" -f $ur.ResultCode, $hr) -Method 'windowsupdate' }
    }
}

# ---------------------------------------------------------------------------
# รันไทม์และโปรแกรมเสริม
# ---------------------------------------------------------------------------
function Get-DrmUninstallEntries {
    param([switch]$Refresh)
    if (-not $Refresh -and $script:DrmState.UninstallCache) { return $script:DrmState.UninstallCache }
    $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($p in $paths) {
        foreach ($e in @(Get-ItemProperty -Path $p -ErrorAction SilentlyContinue)) {
            $n = Get-DrmProp $e 'DisplayName'
            if ($n) { $list.Add([pscustomobject]@{ DisplayName = [string]$n; DisplayVersion = [string](Get-DrmProp $e 'DisplayVersion' ''); Publisher = [string](Get-DrmProp $e 'Publisher' '') }) }
        }
    }
    $script:DrmState.UninstallCache = $list.ToArray()
    return $script:DrmState.UninstallCache
}

function Get-DrmTweakState {
    param([string]$Name)
    try {
        switch ($Name) {
            'GameMode' {
                $v = Get-DrmRegistryValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
                return ($null -eq $v -or [int]$v -eq 1)
            }
            'HAGS' { return ([int](Get-DrmRegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode') -eq 2) }
            'PowerPlan' {
                $pc = (& powercfg.exe /getactivescheme) 2>$null | Out-String
                return ($pc -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c|e9a42b02-d5df-448d-aa00-03f14749eb61')
            }
        }
    } catch { }
    return $false
}

function Get-DrmDotnetChannels {
    param($Catalog, [switch]$Offline)
    if ($script:DrmState.DotnetIndex) { return $script:DrmState.DotnetIndex }
    $cfg = $Catalog.dotnet
    $channels = @()
    if (-not $Offline) {
        try {
            $idx = Get-DrmJson -Url $cfg.releaseIndexUrl
            foreach ($r in @($idx.'releases-index')) {
                $major = [int](([string]$r.'channel-version').Split('.')[0])
                if ($major -lt [int]$cfg.minimumMajor) { continue }
                $channels += [pscustomobject]@{ Channel = [string]$r.'channel-version'; Major = $major; Latest = [string]$r.'latest-runtime'; SupportPhase = [string]$r.'support-phase'; ReleaseType = [string]$r.'release-type'; EolDate = [string](Get-DrmProp $r 'eol-date' '') }
            }
        } catch { Write-DrmLog ("อ่าน .NET release metadata ไม่ได้ ({0}) — ใช้ค่าสำรองในแคตตาล็อก" -f $_.Exception.Message) -Level Warn }
    }
    if ($channels.Count -eq 0) {
        foreach ($f in @($cfg.fallbackChannels)) { $channels += [pscustomobject]@{ Channel = $f.channel; Major = [int]($f.channel.Split('.')[0]); Latest = ''; SupportPhase = $f.supportPhase; ReleaseType = [string](Get-DrmProp $f 'releaseType' ''); EolDate = '' } }
    }
    $script:DrmState.DotnetIndex = $channels
    return $channels
}

function Get-DrmDotnetInstalled {
    param([string]$Framework, [string]$Channel, [string]$Arch)
    if (-not $env:ProgramFiles) { return $null }
    # x64 บน Windows ARM64 ติดตั้งแยกไว้ที่ Program Files\dotnet\x64
    $dotnetRoot = if ($Arch -eq 'x86') { Join-Path (Expand-DrmPath '%ProgramFiles(x86)%') 'dotnet' }
    elseif ($Arch -eq 'x64' -and (Get-DrmArchitecture) -eq 'arm64') { Join-Path $env:ProgramFiles 'dotnet\x64' }
    else { Join-Path $env:ProgramFiles 'dotnet' }
    $dir = Join-Path $dotnetRoot ('shared\' + $Framework)
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $vers = Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ($Channel + '.*') } | ForEach-Object { $_.Name }
    $best = $null
    foreach ($v in @($vers)) { if (-not $best -or (Compare-DrmVersion $v $best) -gt 0) { $best = $v } }
    return $best
}

function Expand-DrmDotnetItems {
    param($Entry, $Catalog, [string]$Arch, [switch]$Offline)
    $channels = @(Get-DrmDotnetChannels -Catalog $Catalog -Offline:$Offline)
    $supported = @($channels | Where-Object { $_.SupportPhase -in 'active', 'maintenance' })
    $eol = @($channels | Where-Object { $_.SupportPhase -eq 'eol' } | Sort-Object Major -Descending | Select-Object -First ([int]$Catalog.dotnet.maxEolChannels))
    $archs = @($Arch)
    if ($Arch -eq 'arm64') { $archs += 'x64' }
    if ($Arch -ne 'x86') { $archs += 'x86' }
    $items = @()
    foreach ($ch in @($supported + $eol)) {
        foreach ($a in $archs) {
            $installed = Get-DrmDotnetInstalled -Framework $Entry.framework -Channel $ch.Channel -Arch $a
            $isSupported = $ch.SupportPhase -ne 'eol'
            $presets = @()
            if ($a -eq $Arch -and $isSupported) { $presets = @('recommended', 'gaming', 'work') }
            elseif ($installed) { $presets = @('recommended', 'gaming', 'work') }   # ติดตั้งอยู่แล้ว → อัปเดตแพตช์ล่าสุด
            $phase = if ($isSupported) { if ($ch.ReleaseType -eq 'lts') { 'LTS' } else { 'STS' } } else { 'หมดการสนับสนุน' }
            $wingetId = ([string]$Entry.wingetTemplate).Replace('{major}', [string]$ch.Major)
            $items += [pscustomobject]@{
                id             = ('{0}-{1}-{2}' -f $Entry.id, $ch.Channel, $a)
                name           = ('{0} {1} ({2}) [{3}]' -f $Entry.name, $ch.Channel, $a, $phase)
                group          = $Entry.group
                category       = $Entry.category
                order          = [int]$Entry.order + (100 - $ch.Major) + $(if ($a -eq 'x86') { 1 } else { 0 })
                presets        = $presets
                publisher      = $Entry.publisher
                latestVersion  = $ch.Latest
                successCodes   = @($Entry.successCodes)
                note           = $(if ($isSupported) { $Entry.note } else { "รุ่นนี้หมดการสนับสนุนแล้ว ($($ch.EolDate)) — ติดตั้ง/อัปเดตเฉพาะเมื่อโปรแกรมต้องใช้" })
                detectedVersion = $installed
                install        = @(
                    [pscustomobject]@{ type = 'dotnet'; channel = $ch.Channel; version = $ch.Latest; arch = $a; framework = $Entry.framework },
                    [pscustomobject]@{ type = 'winget'; id = $wingetId; architecture = $a }
                )
            }
        }
    }
    return $items
}

function Test-DrmDetection {
    <# ตรวจว่ารายการติดตั้งอยู่หรือยัง คืน @{Installed; Version; Source} #>
    param($Detect = @())
    foreach ($d in @($Detect)) {
        $t = Get-DrmProp $d 'type'
        try {
            switch ($t) {
                'registry' {
                    $v = Get-DrmRegistryValue $d.path $d.value
                    $flag = Get-DrmRegistryValue $d.path 'Installed'
                    if ($null -ne $flag -and [int]$flag -eq 0) { $v = $null }
                    if ($v) { return [pscustomobject]@{ Installed = $true; Version = [string](ConvertTo-DrmVersion ([string]$v)); Source = 'registry' } }
                }
                'uninstall' {
                    $hits = @(Get-DrmUninstallEntries | Where-Object { $_.DisplayName -match $d.pattern })
                    if ($hits.Count -gt 0) {
                        $best = ''
                        foreach ($h in $hits) { $hv = $h.DisplayVersion; if (-not $hv) { $hv = ConvertTo-DrmVersion $h.DisplayName }; if (-not $best -or (Compare-DrmVersion $hv $best) -gt 0) { $best = $hv } }
                        return [pscustomobject]@{ Installed = $true; Version = [string]$best; Source = 'uninstall' }
                    }
                }
                'file' {
                    $p = Expand-DrmPath $d.path
                    if ($p -and (Test-Path -LiteralPath $p)) {
                        $ok = $true
                        foreach ($extra in @(Get-DrmProp $d 'alsoRequire' @())) {
                            $x = Expand-DrmPath $extra
                            $parent = Split-Path -Path $x -Parent
                            if ((Test-Path -LiteralPath $parent) -and -not (Test-Path -LiteralPath $x)) { $ok = $false }
                        }
                        if ($ok) {
                            $vi = (Get-Item -LiteralPath $p).VersionInfo
                            $ver = if ($vi.ProductVersion) { $vi.ProductVersion } else { $vi.FileVersion }
                            return [pscustomobject]@{ Installed = $true; Version = [string](ConvertTo-DrmVersion $ver); Source = 'file' }
                        }
                    }
                }
                'feature' {
                    $f = Get-WindowsOptionalFeature -Online -FeatureName $d.name -ErrorAction Stop
                    if ($f.State -eq 'Enabled') { return [pscustomobject]@{ Installed = $true; Version = 'เปิดใช้งาน'; Source = 'feature' } }
                }
                'appx' {
                    $ver = $null
                    if ($PSVersionTable.PSEdition -eq 'Desktop') { $ver = (Get-AppxPackage -Name $d.name -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1).Version }
                    else { $ver = ((& powershell.exe -NoProfile -Command ("(Get-AppxPackage -Name '{0}' | Sort-Object Version -Descending | Select-Object -First 1).Version" -f $d.name)) 2>$null | Out-String).Trim() }
                    if ($ver) { return [pscustomobject]@{ Installed = $true; Version = [string]$ver; Source = 'appx' } }
                }
                'netfx' {
                    $rel = [int](Get-DrmRegistryValue 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release')
                    if ($rel -ge [int]$d.minRelease) { return [pscustomobject]@{ Installed = $true; Version = ('{0} (release {1})' -f $d.label, $rel); Source = 'netfx' } }
                }
                'command' {
                    $c = $null
                    if ($d.name -eq 'winget.exe') { $c = Get-DrmWingetPath } else { $cmd = Get-Command $d.name -ErrorAction SilentlyContinue | Select-Object -First 1; if ($cmd) { $c = $cmd.Source } }
                    if ($c) { return [pscustomobject]@{ Installed = $true; Version = ''; Source = 'command' } }
                }
                'setting' {
                    if (Get-DrmTweakState -Name $d.name) { return [pscustomobject]@{ Installed = $true; Version = 'เปิดอยู่'; Source = 'setting' } }
                }
                'wingetPackage' {
                    foreach ($base in @((Expand-DrmPath '%LOCALAPPDATA%\Microsoft\WinGet\Packages'), (Expand-DrmPath '%ProgramFiles%\WinGet\Packages'))) {
                        if ($base -and (Get-ChildItem -LiteralPath $base -Directory -Filter ($d.id + '_*') -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                            return [pscustomobject]@{ Installed = $true; Version = ''; Source = 'winget' }
                        }
                    }
                }
            }
        } catch { Write-DrmLog ("ตรวจ {0} ไม่สำเร็จ: {1}" -f $t, $_.Exception.Message) -Level Debug }
    }
    return [pscustomobject]@{ Installed = $false; Version = ''; Source = '' }
}

function Get-DrmRuntimeItems {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Catalog, [string]$Arch, $System, [switch]$Offline)
    if (-not $Arch) { $Arch = Get-DrmArchitecture }
    [void](Get-DrmUninstallEntries -Refresh)
    $isLaptop = $false
    if ($System) { $isLaptop = [bool]$System.Hardware.IsLaptop }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($e in @($Catalog.items)) {
        $expanded = @()
        if ((Get-DrmProp $e 'dynamic') -eq 'dotnet') { $expanded = @(Expand-DrmDotnetItems -Entry $e -Catalog $Catalog -Arch $Arch -Offline:$Offline) }
        else {
            $archs = @(Get-DrmProp $e 'arch' @())
            if ($archs.Count -gt 0 -and $archs -notcontains $Arch) { continue }
            $expanded = @($e)
        }
        foreach ($it in $expanded) {
            $det = $null
            $dv = Get-DrmProp $it 'detectedVersion'
            if ((Get-DrmProp $it 'id') -like 'dotnet-*') { $det = [pscustomobject]@{ Installed = [bool]$dv; Version = [string]$dv; Source = 'dotnet' } }
            else { $det = Test-DrmDetection -Detect (Get-DrmProp $it 'detect' @()) }
            $latest = [string](Get-DrmProp $it 'latestVersion' '')
            $presets = @(Get-DrmProp $it 'presets' @())
            $cond = Get-DrmProp $it 'condition'
            $condNote = ''
            if ($cond -eq 'desktop' -and $isLaptop) { $presets = @(); $condNote = ' (ไม่เลือกให้อัตโนมัติบนโน้ตบุ๊ก)' }
            $state = if (-not $det.Installed) { 'ยังไม่ติดตั้ง' }
            elseif ($latest -and $det.Version -and (Compare-DrmVersion $det.Version $latest) -lt 0) { 'มีรุ่นใหม่กว่า' }
            elseif ($latest -and $det.Version) { 'รุ่นล่าสุดแล้ว' }
            else { 'ติดตั้งแล้ว' }
            $out.Add([pscustomobject]@{
                    Id               = [string]$it.id
                    Name             = [string]$it.name
                    Group            = [string]$it.group
                    Category         = [string]$it.category
                    Order            = [int]$it.order
                    Presets          = $presets
                    Publisher        = [string](Get-DrmProp $it 'publisher' '')
                    Installed        = [bool]$det.Installed
                    InstalledVersion = [string]$det.Version
                    LatestVersion    = $latest
                    State            = $state
                    SkipIfInstalled  = [bool](Get-DrmProp $it 'skipIfInstalled' $false)
                    Methods          = @(Get-DrmProp $it 'install' @())
                    SuccessCodes     = @(Get-DrmProp $it 'successCodes' @(0, 3010, 1641))
                    Detect           = @(Get-DrmProp $it 'detect' @())
                    Note             = ([string](Get-DrmProp $it 'note' '')) + $condNote
                    Source           = (Get-DrmMethodSummary @(Get-DrmProp $it 'install' @()))
                })
        }
    }
    $sorted = @($out.ToArray() | Sort-Object Order)
    return , $sorted
}

function Get-DrmMethodSummary {
    param($Methods = @())
    $parts = foreach ($m in @($Methods)) {
        switch ($m.type) {
            'direct' { try { 'ดาวน์โหลดตรง ' + ([Uri]$m.url).Host } catch { 'ดาวน์โหลดตรง' } }
            'winget' { 'winget ' + $m.id }
            'dotnet' { 'builds.dotnet.microsoft.com' }
            'feature' { 'ฟีเจอร์ Windows ' + $m.name }
            'builtin' { 'ตั้งค่าในเครื่อง' }
            'url' { 'หน้าเว็บผู้ผลิต' }
        }
    }
    return ($parts -join ' → ')
}

function Install-DrmWingetPackage {
    param([Parameter(Mandatory)][string]$Id, [switch]$Upgrade, [string]$Architecture, [string]$ItemId)
    $wg = Get-DrmWingetPath
    $verb = if ($Upgrade) { 'upgrade' } else { 'install' }
    if ($script:DrmState.DryRun) {
        $note = if ($wg) { '' } else { ' (ต้องมี winget — เลือก "App Installer (winget)" ในแท็บรันไทม์)' }
        return New-DrmResult -Status 'DryRun' -Detail ("จะรัน winget {0} --id {1}{2}" -f $verb, $Id, $note) -Method 'winget'
    }
    if (-not $wg) { return New-DrmResult -Status 'Failed' -Detail 'ไม่พบ winget (App Installer)' -Method 'winget' }
    $common = '--id "{0}" --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity' -f $Id
    if ($Architecture) { $common += " --architecture $Architecture" }
    if ($Upgrade) { $common += ' --include-unknown' }
    Set-DrmItemStatus -Id $ItemId -Status 'Installing' -Detail ("winget {0} {1}" -f $verb, $Id)
    $r = Invoke-DrmProcess -FilePath $wg -Arguments ("{0} {1}" -f $verb, $common) -Capture -TimeoutMinutes 60
    if ($r.DryRun) { return New-DrmResult -Status 'DryRun' -Detail $r.Command -Method 'winget' }
    $code = if ($null -eq $r.ExitCode) { -1 } else { [int64]$r.ExitCode }
    $u = $code -band 0xFFFFFFFFL
    $text = ($r.Output + ' ' + $r.Error)
    $reboot = ($text -match '(?i)restart|reboot') -or ($u -eq 0x8A150109) -or ($u -eq 0x8A15010A)
    if ($u -eq 0) { return New-DrmResult -Status $(if ($reboot) { 'InstalledReboot' } else { 'Installed' }) -ExitCode $code -RebootRequired $reboot -Method "winget $verb" }
    if ($u -in 0x8A15002B, 0x8A150061, 0x8A15010D) { return New-DrmResult -Status 'UpToDate' -Detail 'winget: ไม่มีรุ่นใหม่กว่า/ติดตั้งอยู่แล้ว' -ExitCode $code -Method "winget $verb" }
    if ($u -in 0x8A150109, 0x8A15010A) { return New-DrmResult -Status 'InstalledReboot' -ExitCode $code -RebootRequired $true -Method "winget $verb" }
    if ($Upgrade -and $u -eq 0x8A150014) {
        Write-DrmLog 'winget ไม่พบแพ็กเกจที่ติดตั้งไว้ — สลับเป็น install' -Level Debug
        return Install-DrmWingetPackage -Id $Id -Architecture $Architecture -ItemId $ItemId
    }
    $lastLine = (($r.Output -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 1)
    return New-DrmResult -Status 'Failed' -Detail ("winget คืนรหัส {0} {1}" -f (Format-DrmExitCode $code), $lastLine) -ExitCode $code -Method "winget $verb"
}

function Resolve-DrmExitStatus {
    <# แปลง exit code ของตัวติดตั้งเป็นสถานะมาตรฐาน #>
    param($ExitCode, [int[]]$SuccessCodes = @(0), [int[]]$RebootCodes = @(3010, 1641), [int[]]$UpToDateCodes = @(1638), [int[]]$NotApplicableCodes = @())
    if ($null -eq $ExitCode) { return 'Failed' }
    $c = [int64]$ExitCode
    if ($UpToDateCodes -contains $c) { return 'UpToDate' }
    if ($NotApplicableCodes -contains $c) { return 'NotApplicable' }
    if ($RebootCodes -contains $c) { return 'InstalledReboot' }
    if ($SuccessCodes -contains $c) { return 'Installed' }
    return 'Failed'
}

function Invoke-DrmBuiltinAction {
    param([string]$Action, [string]$ItemId)
    if ($script:DrmState.DryRun) { return New-DrmResult -Status 'DryRun' -Detail ("จะตั้งค่า {0}" -f $Action) -Method 'builtin' }
    switch ($Action) {
        'RepairWinget' {
            if (Get-DrmWingetPath) { return New-DrmResult -Status 'UpToDate' -Detail 'มี winget แล้ว' -Method 'builtin' }
            try {
                $cmd = "Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop"
                $r = Invoke-DrmProcess -FilePath 'powershell.exe' -Arguments ('-NoProfile -ExecutionPolicy Bypass -Command "{0}"' -f $cmd) -Capture -TimeoutMinutes 10
                $script:DrmState.WingetPath = $null
                Start-Sleep -Seconds 3
                if (Get-DrmWingetPath) { return New-DrmResult -Status 'Installed' -Detail 'ลงทะเบียน App Installer (winget) ใหม่สำเร็จ' -Method 'builtin' }
            } catch { }
            return New-DrmResult -Status 'Failed' -Detail 'ลงทะเบียน App Installer ไม่สำเร็จ — จะลองดาวน์โหลดจาก Microsoft' -Method 'builtin'
        }
        'GameMode' {
            $k = 'HKCU:\Software\Microsoft\GameBar'
            $before = Get-DrmRegistryValue $k 'AutoGameModeEnabled'
            New-Item -Path $k -Force | Out-Null
            Set-ItemProperty -Path $k -Name 'AutoGameModeEnabled' -Value 1 -Type DWord
            Set-ItemProperty -Path $k -Name 'AllowAutoGameMode' -Value 1 -Type DWord
            Write-DrmLog ("Game Mode: ค่าเดิม AutoGameModeEnabled={0} → 1" -f $before)
            return New-DrmResult -Status 'Installed' -Detail 'เปิด Game Mode แล้ว' -Method 'builtin'
        }
        'HAGS' {
            $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
            $before = Get-DrmRegistryValue $k 'HwSchMode'
            Set-ItemProperty -Path $k -Name 'HwSchMode' -Value 2 -Type DWord
            Write-DrmLog ("HAGS: ค่าเดิม HwSchMode={0} → 2 (คืนค่าเดิมได้ด้วยค่า 1)" -f $before)
            return New-DrmResult -Status 'InstalledReboot' -RebootRequired $true -Detail 'มีผลหลังรีสตาร์ท (เฉพาะการ์ดจอที่รองรับ)' -Method 'builtin'
        }
        'PowerPlan' {
            $before = ((& powercfg.exe /getactivescheme) 2>$null | Out-String).Trim()
            Write-DrmLog ("แผนพลังงานเดิม: {0}" -f $before)
            & powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $dup = ((& powercfg.exe -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c) 2>$null | Out-String)
                if ($dup -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { & powercfg.exe /setactive $Matches[1] 2>$null | Out-Null }
            }
            if ($LASTEXITCODE -eq 0 -and (Get-DrmTweakState 'PowerPlan')) { return New-DrmResult -Status 'Installed' -Detail 'ใช้แผน High performance แล้ว' -Method 'builtin' }
            return New-DrmResult -Status 'NotApplicable' -Detail 'เครื่องนี้ไม่รองรับแผน High performance (ระบบ Modern Standby) — ใช้ Settings > System > Power > Power mode: Best performance' -Method 'builtin'
        }
    }
    return New-DrmResult -Status 'Failed' -Detail "ไม่รู้จักคำสั่ง $Action" -Method 'builtin'
}

function Install-DrmCatalogItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item, [string]$ItemId)
    if (-not $ItemId) { $ItemId = $Item.Id }
    $session = Get-DrmSession
    $det = if ($Item.Id -like 'dotnet-*') { [pscustomobject]@{ Installed = [bool]$Item.InstalledVersion; Version = $Item.InstalledVersion } } else { Test-DrmDetection -Detect $Item.Detect }
    $latest = [string]$Item.LatestVersion
    if ($det.Installed) {
        if ($latest -and $det.Version -and (Compare-DrmVersion $det.Version $latest) -ge 0) { return New-DrmResult -Status 'UpToDate' -Detail ("ติดตั้งรุ่น {0} อยู่แล้ว" -f $det.Version) -Version $det.Version }
        if ($Item.SkipIfInstalled -and -not $latest) { return New-DrmResult -Status 'UpToDate' -Detail ("ติดตั้งอยู่แล้ว {0}" -f $det.Version) -Version $det.Version }
    }
    $last = $null
    foreach ($m in @($Item.Methods)) {
        if (Test-DrmCancelRequested) { return New-DrmResult -Status 'Cancelled' }
        try {
            $r = $null
            switch ($m.type) {
                'builtin' { $r = Invoke-DrmBuiltinAction -Action $m.action -ItemId $ItemId }
                'winget' {
                    $arch = [string](Get-DrmProp $m 'architecture' '')
                    $r = Install-DrmWingetPackage -Id $m.id -Upgrade:([bool]$det.Installed) -Architecture $arch -ItemId $ItemId
                }
                'feature' {
                    Set-DrmItemStatus -Id $ItemId -Status 'Installing' -Detail ('เปิดฟีเจอร์ ' + $m.name + ' (ดาวน์โหลดจาก Windows Update อาจใช้เวลาหลายนาที)')
                    $p = Invoke-DrmProcess -FilePath 'dism.exe' -Arguments ('/Online /Enable-Feature /FeatureName:{0} /All /NoRestart /Quiet' -f $m.name) -Capture -TimeoutMinutes 60
                    $r = if ($p.DryRun) { New-DrmResult -Status 'DryRun' -Detail $p.Command } else { New-DrmResult -Status (Resolve-DrmExitStatus $p.ExitCode -SuccessCodes @(0) -RebootCodes @(3010)) -ExitCode $p.ExitCode -RebootRequired ($p.ExitCode -eq 3010) -Method 'dism' }
                }
                'url' {
                    if (-not $script:DrmState.DryRun) { Start-Process $m.url }
                    $r = New-DrmResult -Status 'Manual' -Detail $m.url -Method 'url'
                }
                'dotnet' {
                    $ver = [string]$m.version
                    if (-not $ver) { throw 'ไม่ทราบเวอร์ชันล่าสุดของ .NET (ออฟไลน์) — ลองวิธีถัดไป' }
                    if ($det.Installed -and (Compare-DrmVersion $det.Version $ver) -ge 0) { $r = New-DrmResult -Status 'UpToDate' -Version $det.Version; break }
                    $url = (Get-DrmCatalogCached).dotnet.downloadUrlTemplate.Replace('{version}', $ver).Replace('{arch}', $m.arch)
                    if ($script:DrmState.DryRun) { $r = New-DrmResult -Status 'DryRun' -Detail ("จะดาวน์โหลด {0}" -f $url); break }
                    Set-DrmItemStatus -Id $ItemId -Status 'Downloading'
                    $file = Save-DrmDownload -Url $url -DestinationDir (Join-Path $session.WorkDir 'runtimes') -ExpectedSigner 'Microsoft Corporation' -ItemId $ItemId
                    Set-DrmItemStatus -Id $ItemId -Status 'Installing'
                    $p = Invoke-DrmProcess -FilePath $file -Arguments '/install /quiet /norestart' -TimeoutMinutes 30
                    $r = New-DrmResult -Status (Resolve-DrmExitStatus $p.ExitCode -SuccessCodes $Item.SuccessCodes) -ExitCode $p.ExitCode -RebootRequired (@(3010, 1641) -contains [int]$p.ExitCode) -Method 'dotnet' -Version $ver
                }
                'direct' {
                    if ($script:DrmState.DryRun) { $r = New-DrmResult -Status 'DryRun' -Detail ("จะดาวน์โหลด {0} แล้วรัน {1}" -f $m.url, (Get-DrmProp $m 'args' '')); break }
                    Set-DrmItemStatus -Id $ItemId -Status 'Downloading'
                    $signer = [string](Get-DrmProp $m 'signer' 'Microsoft Corporation')
                    $file = Save-DrmDownload -Url $m.url -DestinationDir (Join-Path $session.WorkDir 'runtimes') -FileName (Get-DrmProp $m 'fileName') -ExpectedSigner $signer -ItemId $ItemId
                    if ((Get-DrmProp $m 'kind') -eq 'appx') {
                        Set-DrmItemStatus -Id $ItemId -Status 'Installing'
                        $r = Install-DrmLocalFile -Info ([pscustomobject]@{ Kind = 'Appx'; Path = $file; Args = ''; Name = [IO.Path]::GetFileName($file) }) -ItemId $ItemId
                        break
                    }
                    $fileVer = ConvertTo-DrmVersion ((Get-Item -LiteralPath $file).VersionInfo.FileVersion)
                    if ((Get-DrmProp $m 'compareVersion' $true) -and $det.Installed -and $fileVer -and $det.Version -and (Compare-DrmVersion $det.Version $fileVer) -ge 0) {
                        $r = New-DrmResult -Status 'UpToDate' -Detail ("ติดตั้ง {0} อยู่แล้ว (ไฟล์ล่าสุด {1})" -f $det.Version, $fileVer) -Version $det.Version
                        break
                    }
                    Set-DrmItemStatus -Id $ItemId -Status 'Installing' -Detail ("เวอร์ชัน {0}" -f $fileVer)
                    $p = Invoke-DrmProcess -FilePath $file -Arguments ([string](Get-DrmProp $m 'args' '')) -TimeoutMinutes 45
                    $st = Resolve-DrmExitStatus $p.ExitCode -SuccessCodes $Item.SuccessCodes
                    if ($st -eq 'Installed' -and [int]$p.ExitCode -eq 1638) { $st = 'UpToDate' }
                    $r = New-DrmResult -Status $st -ExitCode $p.ExitCode -RebootRequired (@(3010, 1641) -contains [int]$p.ExitCode) -Method ('direct ' + ([Uri]$m.url).Host) -Version $fileVer
                }
            }
            if ($r) {
                $last = $r
                if ($r.Status -in 'Installed', 'InstalledReboot', 'UpToDate', 'DryRun', 'Manual', 'NotApplicable') { return $r }
                Write-DrmLog ("วิธี {0} ไม่สำเร็จ ({1}) — ลองวิธีถัดไป" -f $m.type, $r.Detail) -Level Warn
            }
        }
        catch {
            $last = New-DrmResult -Status 'Failed' -Detail $_.Exception.Message -Method $m.type
            Write-DrmLog ("วิธี {0} ล้มเหลว: {1} — ลองวิธีถัดไป" -f $m.type, $_.Exception.Message) -Level Warn
        }
    }
    if (-not $last) { $last = New-DrmResult -Status 'Failed' -Detail 'ไม่มีวิธีติดตั้งที่ใช้ได้' }
    return $last
}

$script:CatalogCache = $null
function Set-DrmCatalogCached { param($Catalog) $script:CatalogCache = $Catalog }
function Get-DrmCatalogCached { if (-not $script:CatalogCache) { $script:CatalogCache = Get-DrmCatalog }; return $script:CatalogCache }

# ---------------------------------------------------------------------------
# ติดตั้งจากไฟล์ — รองรับทุกรูปแบบที่ Windows ติดตั้งได้
# ---------------------------------------------------------------------------
$script:KindByExtension = @{
    '.inf' = 'Inf'; '.exe' = 'Exe'; '.msi' = 'Msi'; '.msp' = 'Msp'; '.msu' = 'Msu'; '.cab' = 'Cab'
    '.msix' = 'Appx'; '.msixbundle' = 'Appx'; '.appx' = 'Appx'; '.appxbundle' = 'Appx'; '.appinstaller' = 'Appx'
    '.zip' = 'Archive'; '.7z' = 'Archive'; '.rar' = 'Archive'; '.tar' = 'Archive'; '.gz' = 'Archive'; '.tgz' = 'Archive'; '.xz' = 'Archive'; '.bz2' = 'Archive'
    '.iso' = 'Image'; '.img' = 'Image'; '.vhd' = 'Image'; '.vhdx' = 'Image'
    '.bat' = 'Script'; '.cmd' = 'Script'; '.ps1' = 'PowerShell'; '.reg' = 'Registry'; '.ppkg' = 'Provisioning'
}
$script:KindText = @{
    Inf = 'ไดรเวอร์ INF'; InfFolder = 'โฟลเดอร์ไดรเวอร์ INF'; Exe = 'ตัวติดตั้ง EXE'; Msi = 'Windows Installer (MSI)'; Msp = 'แพตช์ MSI'
    Msu = 'อัปเดต Windows (MSU)'; Cab = 'แพ็กเกจ CAB'; Appx = 'แอปแพ็กเกจ MSIX/APPX'; Archive = 'ไฟล์บีบอัด'; Image = 'อิมเมจดิสก์ (ISO/VHD)'
    Script = 'สคริปต์ CMD/BAT'; PowerShell = 'สคริปต์ PowerShell'; Registry = 'ไฟล์รีจิสทรี (.reg)'; Provisioning = 'Provisioning package'; Unknown = 'ไม่รู้จัก'
}
$script:EngineArgs = @{
    InnoSetup = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'; NSIS = '/S'; WixBurn = '/quiet /norestart'
    InstallShield = '/s /v"/qn REBOOT=ReallySuppress"'; AdvancedInstaller = '/exenoui /qn /norestart'; Wise = '/s'; SetupFactory = '/S'
    SevenZipSfx = ''; RarSfx = ''; Unknown = ''
}

function Get-DrmInstallerKind {
    param([string]$Path)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($script:KindByExtension.ContainsKey($ext)) { return $script:KindByExtension[$ext] }
    return 'Unknown'
}

function Get-DrmExeEngineFromText {
    <# จำแนกชนิดตัวติดตั้งจากข้อความใน version info และไบต์ของไฟล์ (ฟังก์ชันบริสุทธิ์ ทดสอบได้) #>
    param([string]$Meta = '', [string]$Text = '')
    if ($Meta -match 'Inno Setup' -or $Text -match 'Inno Setup Setup Data|JR\.Inno\.Setup') { return 'InnoSetup' }
    if ($Text -match 'Nullsoft Install System|NullsoftInst' -or $Meta -match 'Nullsoft') { return 'NSIS' }
    if ($Text -match '\.wixburn' -or $Meta -match 'WiX Toolset|Burn') { return 'WixBurn' }
    if ($Meta -match 'InstallShield' -or $Text -match 'InstallShield') { return 'InstallShield' }
    if ($Meta -match 'Advanced Installer' -or $Text -match 'Advanced Installer') { return 'AdvancedInstaller' }
    if ($Text -match '7-Zip SFX|;!@Install@!UTF-8!|7zS\.sfx') { return 'SevenZipSfx' }
    if ($Text -match 'WinRAR SFX|WinRAR self-extracting' -or $Meta -match 'WinRAR') { return 'RarSfx' }
    if ($Text -match 'Wise Installation') { return 'Wise' }
    if ($Text -match 'Setup Factory') { return 'SetupFactory' }
    return 'Unknown'
}

function Get-DrmExeEngine {
    param([string]$Path)
    $meta = ''
    try {
        $vi = (Get-Item -LiteralPath $Path).VersionInfo
        $meta = '{0} | {1} | {2} | {3} | {4}' -f $vi.CompanyName, $vi.FileDescription, $vi.ProductName, $vi.Comments, $vi.OriginalFilename
    } catch { }
    $text = ''
    try {
        $fs = [IO.File]::OpenRead($Path)
        try {
            $len = [int][Math]::Min($fs.Length, 4MB)
            $buf = New-Object byte[] $len
            [void]$fs.Read($buf, 0, $len)
            $text = [Text.Encoding]::GetEncoding(28591).GetString($buf)
        } finally { $fs.Dispose() }
    } catch { }
    return [pscustomobject]@{ Engine = (Get-DrmExeEngineFromText -Meta $meta -Text $text); Meta = $meta }
}

function Find-DrmInstallerRule {
    param([string]$FileName, [string]$Meta, $Catalog)
    foreach ($r in @($Catalog.installerRules)) {
        $fn = Get-DrmProp $r 'fileName'
        $co = Get-DrmProp $r 'company'
        $tx = Get-DrmProp $r 'text'
        if ($fn -and $FileName -notmatch $fn) { continue }
        if ($co -and $Meta -notmatch [regex]::Escape($co)) { continue }
        if ($tx -and $Meta -notmatch $tx) { continue }
        if (-not $fn -and -not $co -and -not $tx) { continue }
        return $r
    }
    return $null
}

function Read-DrmInfInfo {
    param([Parameter(Mandatory)][string]$Path)
    $info = [ordered]@{ Class = ''; Provider = ''; Version = ''; Date = ''; CatalogFile = '' }
    try { $text = [IO.File]::ReadAllText($Path) } catch { return [pscustomobject]$info }
    $strings = @{}
    $section = ''
    $raw = @{}
    foreach ($line in ($text -split "`r?`n")) {
        $l = ($line -replace ';.*$', '').Trim()
        if (-not $l) { continue }
        if ($l -match '^\[(.+)\]$') { $section = $Matches[1].Trim().ToLowerInvariant(); continue }
        if ($l -match '^([^=]+?)\s*=\s*(.*)$') {
            $k = $Matches[1].Trim(); $v = $Matches[2].Trim().Trim('"')
            if ($section -eq 'strings') { $strings[$k.ToLowerInvariant()] = $v }
            elseif ($section -eq 'version') { $raw[$k.ToLowerInvariant()] = $v }
        }
    }
    $resolve = { param($v) if ($v -match '^%(.+)%$' -and $strings.ContainsKey($Matches[1].ToLowerInvariant())) { $strings[$Matches[1].ToLowerInvariant()] } else { $v } }
    $info.Class = & $resolve ([string]$raw['class'])
    $info.Provider = & $resolve ([string]$raw['provider'])
    if ($raw['driverver'] -and $raw['driverver'] -match '^\s*([0-9/]+)\s*,\s*([0-9\.]+)') {
        $info.Date = Format-DrmDate (ConvertTo-DrmDate $Matches[1]); $info.Version = $Matches[2]
    }
    $catKey = @($raw.Keys | Where-Object { $_ -like 'catalogfile*' }) | Sort-Object { $_ -eq 'catalogfile' } -Descending | Select-Object -First 1
    if ($catKey) {
        $c = Join-Path (Split-Path -Path $Path -Parent) $raw[$catKey]
        if (Test-Path -LiteralPath $c) { $info.CatalogFile = $c }
    }
    return [pscustomobject]$info
}

function Get-DrmInstallerInfo {
    <# วิเคราะห์ไฟล์/โฟลเดอร์ที่ผู้ใช้เพิ่ม — คืนรายการพร้อมชนิด วิธีติดตั้ง ลายเซ็น และลำดับ #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, $Catalog)
    if (-not $Catalog) { $Catalog = Get-DrmCatalogCached }
    $results = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path)) { return , $results.ToArray() }
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        $infs = @(Get-ChildItem -LiteralPath $item.FullName -Filter '*.inf' -Recurse -File -ErrorAction SilentlyContinue)
        if ($infs.Count -gt 0) {
            $first = Read-DrmInfInfo -Path $infs[0].FullName
            $ord = Get-DrmDriverOrder -Class $first.Class -Name ($item.Name + ' ' + $first.Provider)
            $cert = if ($first.CatalogFile) { Get-DrmFileSignature -Path $first.CatalogFile } else { $null }
            $results.Add((New-DrmLocalInfo -Path $item.FullName -Kind 'InfFolder' -Name $item.Name -Engine ("{0} ไฟล์ .inf" -f $infs.Count) -SilentArgs '' -Signature $cert -ClassName $first.Class -Version $first.Version -Order $ord))
            return , $results.ToArray()
        }
        foreach ($child in Get-ChildItem -LiteralPath $item.FullName -File -ErrorAction SilentlyContinue) {
            if ((Get-DrmInstallerKind $child.FullName) -ne 'Unknown') { foreach ($x in (Get-DrmInstallerInfo -Path $child.FullName -Catalog $Catalog)) { $results.Add($x) } }
        }
        return , $results.ToArray()
    }
    $kind = Get-DrmInstallerKind $item.FullName
    $engine = ''; $silentArgs = ''; $sig = $null; $class = ''; $ver = ''; $rule = $null; $meta = ''
    switch ($kind) {
        'Inf' {
            $inf = Read-DrmInfInfo -Path $item.FullName
            $class = $inf.Class; $ver = $inf.Version
            $engine = 'pnputil /add-driver /install'
            if ($inf.CatalogFile) { $sig = Get-DrmFileSignature -Path $inf.CatalogFile } else { $sig = [pscustomobject]@{ IsValid = $false; Status = 'NotSigned'; CertLevel = 'Unsigned'; Organization = ''; Signer = '' } }
        }
        'Exe' {
            $e = Get-DrmExeEngine -Path $item.FullName
            $meta = $e.Meta
            $engine = $e.Engine
            $silentArgs = $script:EngineArgs[$engine]
            $rule = Find-DrmInstallerRule -FileName $item.Name -Meta ($e.Meta + ' ' + $item.Name) -Catalog $Catalog
            if ($rule) { $engine = $rule.name; $silentArgs = [string]$rule.args }
            $sig = Get-DrmFileSignature -Path $item.FullName
            try { $ver = ConvertTo-DrmVersion ($item.VersionInfo.ProductVersion) } catch { }
        }
        'Msi' { $engine = 'msiexec /i'; $silentArgs = '/qn /norestart'; $sig = Get-DrmFileSignature -Path $item.FullName }
        'Msp' { $engine = 'msiexec /p'; $silentArgs = '/qn /norestart'; $sig = Get-DrmFileSignature -Path $item.FullName }
        'Msu' { $engine = 'wusa /quiet'; $sig = Get-DrmFileSignature -Path $item.FullName }
        'Cab' { $engine = 'แตกไฟล์ → pnputil หรือ DISM'; $sig = Get-DrmFileSignature -Path $item.FullName }
        'Appx' { $engine = 'Add-AppxPackage'; if ($item.Extension -ne '.appinstaller') { $sig = Get-DrmFileSignature -Path $item.FullName } }
        'Archive' { $engine = 'แตกไฟล์แล้วติดตั้งตัวที่พบ' }
        'Image' { $engine = 'เมานต์แล้วติดตั้งตัวที่พบ' }
        'Script' { $engine = 'cmd.exe /c'; $sig = Get-DrmFileSignature -Path $item.FullName }
        'PowerShell' { $engine = 'powershell -File'; $sig = Get-DrmFileSignature -Path $item.FullName }
        'Registry' { $engine = 'reg import' }
        'Provisioning' { $engine = 'Install-ProvisioningPackage'; $sig = Get-DrmFileSignature -Path $item.FullName }
    }
    $nameForOrder = '{0} {1}' -f $item.BaseName, $meta
    $ord = Get-DrmDriverOrder -Class $class -Name $nameForOrder
    $info = New-DrmLocalInfo -Path $item.FullName -Kind $kind -Name $item.Name -Engine $engine -SilentArgs $silentArgs -Signature $sig -ClassName $class -Version $ver -Order $ord
    if ($rule) {
        $info.SuccessCodes = @(Get-DrmProp $rule 'successCodes' @(0, 3010, 1641))
        $info.RebootCodes = @(Get-DrmProp $rule 'rebootCodes' @(3010, 1641))
        $info.UpToDateCodes = @(Get-DrmProp $rule 'upToDateCodes' @())
        $info.NotApplicableCodes = @(Get-DrmProp $rule 'notApplicableCodes' @())
    }
    $results.Add($info)
    return , $results.ToArray()
}

function New-DrmLocalInfo {
    param([string]$Path, [string]$Kind, [string]$Name, [string]$Engine, [string]$SilentArgs, $Signature, [string]$ClassName, [string]$Version, $Order)
    $certLevel = if ($Signature) { [string]$Signature.CertLevel } elseif ($Kind -in 'Archive', 'Image') { 'Unknown' } else { 'Unsigned' }
    $valid = if ($Signature) { [bool]$Signature.IsValid } else { $Kind -in 'Archive', 'Image', 'Registry' }
    $sigText = if ($Signature -and $Signature.IsValid) { '{0} — {1}' -f (Get-DrmCertText $certLevel), $(if ($Signature.Organization) { $Signature.Organization } else { $Signature.Signer }) }
    elseif ($Kind -in 'Archive', 'Image') { 'ตรวจไฟล์ข้างในตอนติดตั้ง' }
    elseif ($Signature) { 'ไม่ผ่าน: ' + $Signature.Status }
    else { 'ไม่มีลายเซ็น' }
    [pscustomobject]@{
        Id                 = 'file:' + $Path.ToLowerInvariant()
        Path               = $Path
        Name               = $Name
        Kind               = $Kind
        KindText           = $(if ($script:KindText.ContainsKey($Kind)) { $script:KindText[$Kind] } else { $Kind })
        Engine             = $Engine
        Args               = $SilentArgs
        ClassName          = $ClassName
        Version            = $Version
        SignatureValid     = $valid
        CertLevel          = $certLevel
        SignatureText      = $sigText
        OrderIndex         = $Order.Index
        OrderGroup         = $Order.Group
        Selected           = ($valid -and $Kind -ne 'Registry')
        SuccessCodes       = @(0, 3010, 1641)
        RebootCodes        = @(3010, 1641)
        UpToDateCodes      = @(1638)
        NotApplicableCodes = @()
    }
}

function Expand-DrmArchive {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -eq '.zip') {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            [IO.Compression.ZipFile]::ExtractToDirectory($Path, $Destination)
            return $true
        } catch { Write-DrmLog ("แตก zip ด้วย .NET ไม่ได้ ({0}) — ลองเครื่องมืออื่น" -f $_.Exception.Message) -Level Debug }
    }
    $7z = Get-Drm7ZipPath
    if ($7z) {
        $r = Invoke-DrmProcess -FilePath $7z -Arguments ('x "{0}" -o"{1}" -y' -f $Path, $Destination) -Capture -IgnoreDryRun -TimeoutMinutes 30
        if ($r.ExitCode -in 0, 1) { return $true }
    }
    $tar = ('{0}\System32\tar.exe' -f (Get-DrmWindowsDir))
    if (Test-Path -LiteralPath $tar) {
        $r = Invoke-DrmProcess -FilePath $tar -Arguments ('-xf "{0}" -C "{1}"' -f $Path, $Destination) -Capture -IgnoreDryRun -TimeoutMinutes 30
        if ($r.ExitCode -eq 0) { return $true }
    }
    return $false
}

function Resolve-DrmExtractedInstaller {
    <# หาไฟล์ที่ควรติดตั้งในโฟลเดอร์ที่แตก/เมานต์: setup.exe → .msi → .inf → แพ็กเกจแอป → ไฟล์บีบอัดซ้อน #>
    param([Parameter(Mandatory)][string]$Dir)
    $top = @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue)
    $level2 = @(Get-ChildItem -LiteralPath $Dir -Directory -ErrorAction SilentlyContinue | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue })
    foreach ($set in @($top, $level2)) {
        $setup = $set | Where-Object { $_.Name -match '^(setup|install|installer|autorun|SetupChipset|Setup.*)\.exe$' } | Sort-Object { $_.Name -notmatch '^setup\.exe$' } | Select-Object -First 1
        if ($setup) { return $setup.FullName }
    }
    $msi = $top | Where-Object { $_.Extension -eq '.msi' } | Select-Object -First 1
    if ($msi) { return $msi.FullName }
    if (Get-ChildItem -LiteralPath $Dir -Filter '*.inf' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1) { return $Dir }
    $other = $top | Where-Object { (Get-DrmInstallerKind $_.FullName) -in 'Appx', 'Msu', 'Cab', 'Exe', 'Archive' } | Select-Object -First 1
    if ($other) { return $other.FullName }
    return $null
}

function Install-DrmLocalFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Info, [string]$ItemId, [switch]$AllowUnsigned, [int]$Depth = 0)
    if (-not $ItemId) { $ItemId = $Info.Id }
    $session = Get-DrmSession
    $path = $Info.Path
    $kind = $Info.Kind
    if ($Depth -gt 3) { return New-DrmResult -Status 'Failed' -Detail 'ไฟล์ซ้อนกันลึกเกินไป' }
    $sigValid = [bool](Get-DrmProp $Info 'SignatureValid' $true)
    if (-not $sigValid -and -not $AllowUnsigned -and $kind -notin 'Archive', 'Image', 'InfFolder') {
        return New-DrmResult -Status 'Skipped' -Detail 'ไม่มีลายเซ็นดิจิทัลที่ถูกต้อง — เปิดตัวเลือก "อนุญาตไฟล์ที่ไม่มีลายเซ็น" ถ้ามั่นใจว่ามาจากผู้ผลิต'
    }
    $logBase = Join-Path $session.LogDir ('{0}_{1}' -f (Get-DrmSafeFileName ([IO.Path]::GetFileNameWithoutExtension($path))), (Get-DrmTimestamp -Format 'HHmmss'))
    $succ = @(Get-DrmProp $Info 'SuccessCodes' @(0, 3010, 1641))
    $reb = @(Get-DrmProp $Info 'RebootCodes' @(3010, 1641))
    $upd = @(Get-DrmProp $Info 'UpToDateCodes' @(1638))
    $na = @(Get-DrmProp $Info 'NotApplicableCodes' @())
    $userArgs = [string](Get-DrmProp $Info 'Args' '')
    Set-DrmItemStatus -Id $ItemId -Status 'Installing'
    $p = $null
    switch ($kind) {
        'Inf' {
            $p = Invoke-DrmProcess -FilePath 'pnputil.exe' -Arguments ('/add-driver "{0}" /install' -f $path) -Capture
            return Resolve-DrmPnputilResult $p
        }
        'InfFolder' {
            $p = Invoke-DrmProcess -FilePath 'pnputil.exe' -Arguments ('/add-driver "{0}" /subdirs /install' -f (Join-Path $path '*.inf')) -Capture
            return Resolve-DrmPnputilResult $p
        }
        'Exe' {
            $a = Expand-DrmTemplate $userArgs @{ LogFile = ($logBase + '.log') }
            $p = Invoke-DrmProcess -FilePath $path -Arguments $a -WorkingDirectory (Split-Path -Path $path -Parent) -TimeoutMinutes 90
        }
        'Msi' {
            $a = '/i "{0}" {1} /l*v "{2}.msi.log"' -f $path, $(if ($userArgs) { $userArgs } else { '/qn /norestart' }), $logBase
            $p = Invoke-DrmProcess -FilePath 'msiexec.exe' -Arguments $a -TimeoutMinutes 60
            if ($p.ExitCode -eq 1618) { Write-DrmLog 'มีการติดตั้ง MSI อื่นค้างอยู่ — รอ 60 วินาทีแล้วลองใหม่' -Level Warn; Start-Sleep -Seconds 60; $p = Invoke-DrmProcess -FilePath 'msiexec.exe' -Arguments $a -TimeoutMinutes 60 }
        }
        'Msp' {
            $a = '/p "{0}" {1} /l*v "{2}.msp.log"' -f $path, $(if ($userArgs) { $userArgs } else { '/qn /norestart' }), $logBase
            $p = Invoke-DrmProcess -FilePath 'msiexec.exe' -Arguments $a -TimeoutMinutes 60
        }
        'Msu' {
            $p = Invoke-DrmProcess -FilePath 'wusa.exe' -Arguments ('"{0}" /quiet /norestart' -f $path) -TimeoutMinutes 90
            if ($p.DryRun) { return New-DrmResult -Status 'DryRun' -Detail $p.Command }
            $u = if ($null -ne $p.ExitCode) { [int64]$p.ExitCode -band 0xFFFFFFFFL } else { -1 }
            if ($u -eq 0x00240006) { return New-DrmResult -Status 'UpToDate' -Detail 'อัปเดตนี้ติดตั้งอยู่แล้ว' -ExitCode $p.ExitCode -Method 'wusa' }
            if ($u -eq 0x80240017) { return New-DrmResult -Status 'NotApplicable' -Detail 'อัปเดตนี้ไม่เข้ากับ Windows รุ่นนี้' -ExitCode $p.ExitCode -Method 'wusa' }
            return New-DrmResult -Status (Resolve-DrmExitStatus $p.ExitCode -SuccessCodes @(0) -RebootCodes @(3010)) -ExitCode $p.ExitCode -RebootRequired ($p.ExitCode -eq 3010) -Method 'wusa'
        }
        'Cab' {
            $dest = Join-Path $session.WorkDir ('cab_' + [IO.Path]::GetFileNameWithoutExtension($path))
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            [void](Invoke-DrmProcess -FilePath 'expand.exe' -Arguments ('"{0}" -F:* "{1}"' -f $path, $dest) -Capture -IgnoreDryRun)
            if (Get-ChildItem -LiteralPath $dest -Filter '*.inf' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1) {
                Write-DrmLog 'ไฟล์ CAB เป็นแพ็กเกจไดรเวอร์ (มี .inf) — ติดตั้งด้วย pnputil' -Level Info
                $p = Invoke-DrmProcess -FilePath 'pnputil.exe' -Arguments ('/add-driver "{0}" /subdirs /install' -f (Join-Path $dest '*.inf')) -Capture
                return Resolve-DrmPnputilResult $p
            }
            $p = Invoke-DrmProcess -FilePath 'dism.exe' -Arguments ('/Online /Add-Package /PackagePath:"{0}" /NoRestart /Quiet' -f $path) -Capture -TimeoutMinutes 60
            if ($p.DryRun) { return New-DrmResult -Status 'DryRun' -Detail $p.Command }
            return New-DrmResult -Status (Resolve-DrmExitStatus $p.ExitCode -SuccessCodes @(0) -RebootCodes @(3010)) -ExitCode $p.ExitCode -RebootRequired ($p.ExitCode -eq 3010) -Method 'dism'
        }
        'Appx' {
            $param = if ($path -match '\.appinstaller$') { '-AppInstallerFile' } else { '-Path' }
            $cmd = "Add-AppxPackage $param '{0}' -ForceApplicationShutdown -ErrorAction Stop" -f $path.Replace("'", "''")
            $p = Invoke-DrmProcess -FilePath 'powershell.exe' -Arguments ('-NoProfile -ExecutionPolicy Bypass -Command "{0}"' -f $cmd) -Capture -TimeoutMinutes 30
            if ($p.DryRun) { return New-DrmResult -Status 'DryRun' -Detail $p.Command }
            if ($p.ExitCode -eq 0) { return New-DrmResult -Status 'Installed' -Method 'appx' }
            if (($p.Error + $p.Output) -match '0x80073D06|higher version') { return New-DrmResult -Status 'UpToDate' -Detail 'มีรุ่นที่ใหม่กว่าติดตั้งอยู่แล้ว' -Method 'appx' }
            return New-DrmResult -Status 'Failed' -Detail (($p.Error -split "`r?`n" | Where-Object { $_ } | Select-Object -First 2) -join ' ') -ExitCode $p.ExitCode -Method 'appx'
        }
        'Archive' {
            $dest = Join-Path $session.WorkDir ('extract_' + (Get-DrmSafeFileName ([IO.Path]::GetFileNameWithoutExtension($path))) + '_' + (Get-DrmTimestamp -Format 'HHmmssfff'))
            Set-DrmItemStatus -Id $ItemId -Status 'Running' -Detail 'กำลังแตกไฟล์'
            if (-not (Expand-DrmArchive -Path $path -Destination $dest)) { return New-DrmResult -Status 'Failed' -Detail 'แตกไฟล์ไม่ได้ — ติดตั้ง 7-Zip จากแท็บรันไทม์แล้วลองใหม่' }
            return Install-DrmResolvedInstaller -Dir $dest -ItemId $ItemId -AllowUnsigned:$AllowUnsigned -Depth $Depth
        }
        'Image' {
            if ($script:DrmState.DryRun) { return New-DrmResult -Status 'DryRun' -Detail ("จะเมานต์ {0} แล้วติดตั้งตัวที่พบ" -f $path) }
            $img = Mount-DiskImage -ImagePath $path -PassThru -ErrorAction Stop
            try {
                Start-Sleep -Seconds 2
                $vol = $img | Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter } | Select-Object -First 1
                if (-not $vol) { return New-DrmResult -Status 'Failed' -Detail 'เมานต์แล้วไม่พบไดรฟ์' }
                return Install-DrmResolvedInstaller -Dir ('{0}:\' -f $vol.DriveLetter) -ItemId $ItemId -AllowUnsigned:$AllowUnsigned -Depth $Depth
            } finally { Dismount-DiskImage -ImagePath $path -ErrorAction SilentlyContinue | Out-Null }
        }
        'Script' { $p = Invoke-DrmProcess -FilePath 'cmd.exe' -Arguments ('/c ""{0}" {1}"' -f $path, $userArgs) -WorkingDirectory (Split-Path -Path $path -Parent) -TimeoutMinutes 60 }
        'PowerShell' { $p = Invoke-DrmProcess -FilePath 'powershell.exe' -Arguments ('-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $path, $userArgs) -WorkingDirectory (Split-Path -Path $path -Parent) -TimeoutMinutes 60 }
        'Registry' { $p = Invoke-DrmProcess -FilePath 'reg.exe' -Arguments ('import "{0}"' -f $path) -Capture }
        'Provisioning' {
            $cmd = "Install-ProvisioningPackage -PackagePath '{0}' -QuietInstall -ForceInstall -ErrorAction Stop" -f $path.Replace("'", "''")
            $p = Invoke-DrmProcess -FilePath 'powershell.exe' -Arguments ('-NoProfile -ExecutionPolicy Bypass -Command "{0}"' -f $cmd) -Capture
        }
        default { return New-DrmResult -Status 'Skipped' -Detail 'ไม่รู้จักชนิดไฟล์นี้' }
    }
    if (-not $p) { return New-DrmResult -Status 'Failed' -Detail 'ไม่ได้รันคำสั่ง' }
    if ($p.DryRun) { return New-DrmResult -Status 'DryRun' -Detail $p.Command }
    if ($p.TimedOut) { return New-DrmResult -Status 'Failed' -Detail 'หมดเวลา — ตัวติดตั้งอาจรอการกดยืนยัน ให้ใส่ตัวเลือกติดตั้งเงียบที่ถูกต้องในช่อง "ตัวเลือก"' }
    $st = Resolve-DrmExitStatus $p.ExitCode -SuccessCodes $succ -RebootCodes $reb -UpToDateCodes $upd -NotApplicableCodes $na
    return New-DrmResult -Status $st -ExitCode $p.ExitCode -RebootRequired ($st -eq 'InstalledReboot') -Method $kind -Detail $(if ($st -eq 'Failed') { "รหัส $(Format-DrmExitCode $p.ExitCode) — ดู log ของผู้ผลิตหรือ $logBase*" } else { '' })
}

function Install-DrmResolvedInstaller {
    param([string]$Dir, [string]$ItemId, [switch]$AllowUnsigned, [int]$Depth = 0)
    $target = Resolve-DrmExtractedInstaller -Dir $Dir
    if (-not $target) { return New-DrmResult -Status 'Failed' -Detail ("ไม่พบตัวติดตั้งใน {0}" -f $Dir) }
    Write-DrmLog ("พบตัวติดตั้งข้างใน: {0}" -f $target)
    $inner = Get-DrmInstallerInfo -Path $target
    if ($inner.Count -eq 0) { return New-DrmResult -Status 'Failed' -Detail ("ไม่รู้จักไฟล์ {0}" -f $target) }
    return Install-DrmLocalFile -Info $inner[0] -ItemId $ItemId -AllowUnsigned:$AllowUnsigned -Depth ($Depth + 1)
}

function Resolve-DrmPnputilResult {
    param($Process)
    if ($Process.DryRun) { return New-DrmResult -Status 'DryRun' -Detail $Process.Command }
    switch ([int]$Process.ExitCode) {
        0 { return New-DrmResult -Status 'Installed' -ExitCode 0 -Method 'pnputil' }
        3010 { return New-DrmResult -Status 'InstalledReboot' -ExitCode 3010 -RebootRequired $true -Method 'pnputil' }
        259 { return New-DrmResult -Status 'Staged' -Detail 'เพิ่มเข้า Driver Store แล้ว แต่ไม่มีอุปกรณ์ที่ตรงกัน หรือมีไดรเวอร์ที่ดีกว่าอยู่แล้ว' -ExitCode 259 -Method 'pnputil' }
        default {
            $tail = (($Process.Output -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' '
            return New-DrmResult -Status 'Failed' -Detail ("pnputil รหัส {0} {1}" -f (Format-DrmExitCode $Process.ExitCode), $tail) -ExitCode $Process.ExitCode -Method 'pnputil'
        }
    }
}

# ---------------------------------------------------------------------------
# ความปลอดภัยก่อนติดตั้ง: จุดคืนค่าและสำรองไดรเวอร์
# ---------------------------------------------------------------------------
function New-DrmRestorePoint {
    param([string]$Description = ('Driver & Runtime Manager ' + (Get-DrmTimestamp -Format 'yyyy-MM-dd HH:mm')))
    if ($script:DrmState.DryRun) { Write-DrmLog 'ทดลอง: จะสร้างจุดคืนค่าระบบ' -Level Debug; return $true }
    $freqKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $oldFreq = Get-DrmRegistryValue $freqKey 'SystemRestorePointCreationFrequency'
    try {
        Set-ItemProperty -Path $freqKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        $rpArgs = @{ Description = $Description; RestorePointType = [uint32]12; EventType = [uint32]100 }
        $r = Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore -MethodName CreateRestorePoint -Arguments $rpArgs -ErrorAction Stop
        if ($r.ReturnValue -ne 0) {
            Write-DrmLog 'System Protection ของไดรฟ์ระบบอาจปิดอยู่ — เปิดใช้แล้วลองใหม่' -Level Warn
            $drive = ($env:SystemDrive + '\')
            [void](Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore -MethodName Enable -Arguments @{ Drive = $drive } -ErrorAction Stop)
            $r = Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore -MethodName CreateRestorePoint -Arguments $rpArgs -ErrorAction Stop
        }
        if ($r.ReturnValue -eq 0) { Write-DrmLog ("สร้างจุดคืนค่าระบบแล้ว: {0}" -f $Description) -Level Ok; return $true }
        Write-DrmLog ("สร้างจุดคืนค่าไม่สำเร็จ (รหัส {0}) — ทำงานต่อ" -f $r.ReturnValue) -Level Warn
    } catch { Write-DrmLog ("สร้างจุดคืนค่าไม่สำเร็จ: {0} — ทำงานต่อ" -f $_.Exception.Message) -Level Warn }
    finally {
        if ($null -eq $oldFreq) { Remove-ItemProperty -Path $freqKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $freqKey -Name 'SystemRestorePointCreationFrequency' -Value $oldFreq -Type DWord -ErrorAction SilentlyContinue }
    }
    return $false
}

function Backup-DrmDrivers {
    param([string]$Destination)
    $session = Get-DrmSession
    if (-not $Destination) { $Destination = Join-Path (Join-Path $session.Root 'Backup') $session.Id }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Write-DrmLog ("สำรองไดรเวอร์ของผู้ผลิตทั้งหมดไปที่ {0}" -f $Destination) -Level Step
    $p = Invoke-DrmProcess -FilePath 'pnputil.exe' -Arguments ('/export-driver * "{0}"' -f $Destination) -Capture -TimeoutMinutes 60
    if ($p.DryRun -or $p.ExitCode -eq 0) { Write-DrmLog 'สำรองไดรเวอร์เสร็จ (คืนค่าได้ด้วย pnputil /add-driver <โฟลเดอร์>\*.inf /subdirs /install)' -Level Ok; return $Destination }
    Write-DrmLog ("สำรองไดรเวอร์ไม่สำเร็จ (รหัส {0})" -f (Format-DrmExitCode $p.ExitCode)) -Level Warn
    return $null
}

# ---------------------------------------------------------------------------
# แผนการติดตั้งและการรัน
# ---------------------------------------------------------------------------
function Get-DrmPlanPhase {
    param([Parameter(Mandatory)]$Item)
    switch ($Item.Kind) {
        'OemTool' { return 1 }
        'VendorTool' { return 2 }
        'Local' { return 3 }
        'WuDriver' { return 4 }
        'Catalog' {
            switch ($Item.Category) { 'prereq' { return 0 } 'runtime' { return 5 } 'tool' { return 6 } 'tweak' { return 7 } default { return 6 } }
        }
    }
    return 6
}

function New-DrmPlan {
    <# จัดลำดับ: เตรียมระบบ → OEM → ผู้ผลิตชิ้นส่วน → ไฟล์ผู้ผลิต (BIOS → ชิปเซ็ต → ... ) → Windows Update (รุ่นใหม่กว่า) → รันไทม์ → โปรแกรม → ปรับแต่ง #>
    param([object[]]$Items = @())
    $plan = foreach ($it in @($Items)) {
        $phase = Get-DrmPlanPhase $it
        $o = [ordered]@{}
        foreach ($p in $it.PSObject.Properties) { $o[$p.Name] = $p.Value }
        $o.Phase = $phase
        $o.PhaseName = $script:PhaseNames[$phase]
        if (-not $o.Contains('OrderIndex') -or $null -eq $o.OrderIndex) { $o.OrderIndex = 90 }
        [pscustomobject]$o
    }
    $seq = 0
    $sorted = @($plan | Sort-Object Phase, OrderIndex, Name)
    foreach ($p in $sorted) { $seq++; $p | Add-Member -NotePropertyName Sequence -NotePropertyValue $seq -Force }
    return , $sorted
}

function Get-DrmResumeFile { param([string]$Root) Join-Path $Root 'resume.json' }

function Save-DrmResumeState {
    param([object[]]$Remaining, $Options, $Session, $Snapshot, [int]$Attempt = 1, [string]$LauncherPath)
    $file = Get-DrmResumeFile $Session.Root
    $state = [ordered]@{
        SessionId = $Session.Id; Created = (Get-DrmTimestamp); Attempt = $Attempt
        Options = $Options; Snapshot = $Snapshot; Items = @($Remaining)
    }
    [IO.File]::WriteAllText($file, ($state | ConvertTo-Json -Depth 12), $script:Utf8Bom)
    if ($LauncherPath -and (Test-Path -LiteralPath $LauncherPath)) {
        $cmd = '"{0}" -Resume' -f $LauncherPath
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Force | Out-Null
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'DriverRuntimeManagerResume' -Value $cmd
        Write-DrmLog ("ตั้งให้ทำงานต่ออัตโนมัติหลังรีสตาร์ท: {0}" -f $cmd) -Level Ok
    }
    return $file
}

function Read-DrmResumeState {
    param([string]$Root)
    $f = Get-DrmResumeFile $Root
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}

function Clear-DrmResumeState {
    param([string]$Root)
    Remove-Item -LiteralPath (Get-DrmResumeFile $Root) -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'DriverRuntimeManagerResume' -ErrorAction SilentlyContinue
}

function Invoke-DrmPlanItem {
    param([Parameter(Mandatory)]$Item, $Options, $OemProfile)
    switch ($Item.Kind) {
        'OemTool' {
            $prof = $OemProfile
            if (-not $prof -and $Item.PSObject.Properties['Profile']) { $prof = $Item.Profile }
            return Invoke-DrmOemTool -Tool $prof -Mode Apply -InstallTool -ItemId $Item.Id
        }
        'VendorTool' {
            $res = $null
            if ($Item.Winget) { $res = Install-DrmWingetPackage -Id $Item.Winget -ItemId $Item.Id }
            if ($Item.Url -and -not $script:DrmState.DryRun) { Start-Process $Item.Url }
            if ($script:DrmState.DryRun) { return New-DrmResult -Status 'DryRun' -Detail ("จะติดตั้ง {0} และเปิด {1}" -f $Item.Winget, $Item.Url) }
            if ($res -and $res.Status -eq 'Failed') { return $res }
            return New-DrmResult -Status 'Manual' -Detail ("เปิดหน้า {0} แล้ว — ให้เครื่องมือของผู้ผลิตตรวจและติดตั้งต่อ" -f $Item.Url) -Method 'vendor'
        }
        'WuDriver' { return Install-DrmWindowsUpdateDriver -UpdateId $Item.UpdateId -ItemId $Item.Id }
        'Local' { return Install-DrmLocalFile -Info $Item.Info -ItemId $Item.Id -AllowUnsigned:([bool]$Options.AllowUnsigned) }
        'Catalog' { return Install-DrmCatalogItem -Item $Item.Info -ItemId $Item.Id }
    }
    return New-DrmResult -Status 'Skipped' -Detail ("ไม่รู้จักชนิด {0}" -f $Item.Kind)
}

function Invoke-DrmInstallPlan {
    <# รันแผนตามลำดับ บันทึก log ทุกขั้น ทำความสะอาด ตรวจผลซ้ำ และออกรายงาน #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Plan,
        [Parameter(Mandatory)]$Options,
        $Catalog,
        $System,
        $DevicesBefore = @(),
        $OemProfile,
        $Snapshot,
        [int]$ResumeAttempt = 0,
        [string]$LauncherPath
    )
    $session = Get-DrmSession
    if (-not $Catalog) { $Catalog = Get-DrmCatalogCached } else { Set-DrmCatalogCached $Catalog }
    $results = New-Object System.Collections.Generic.List[object]
    $opt = $Options
    $total = @($Plan).Count
    Write-DrmLog ("===== เริ่มติดตั้ง {0} รายการ (โหมดทดลอง: {1}) =====" -f $total, $script:DrmState.DryRun) -Level Step
    if (-not (Test-DrmIsAdmin) -and -not $script:DrmState.DryRun) { Write-DrmLog 'ไม่ได้รันด้วยสิทธิ์ Administrator — การติดตั้งส่วนใหญ่จะล้มเหลว' -Level Error }
    if ($System -and $System.SystemDrive.FreeGB -lt 10) { Write-DrmLog ("พื้นที่ว่างไดรฟ์ระบบเหลือ {0} GB — อาจไม่พอสำหรับไดรเวอร์ขนาดใหญ่" -f $System.SystemDrive.FreeGB) -Level Warn }
    $pending = Get-DrmPendingReboot
    if ($pending.Pending) { Write-DrmLog ("เครื่องรอรีสตาร์ทอยู่ก่อนแล้ว ({0}) — ตัวติดตั้งบางตัวอาจขอให้รีสตาร์ทก่อน" -f ($pending.Reasons -join ', ')) -Level Warn }
    if (-not $Snapshot) { $Snapshot = Get-DrmCleanupSnapshot }

    if ($ResumeAttempt -eq 0) {
        if ([bool](Get-DrmProp $opt 'CreateRestorePoint' $true)) { Set-DrmProgress 1 'สร้างจุดคืนค่าระบบ'; [void](New-DrmRestorePoint) }
        if ([bool](Get-DrmProp $opt 'BackupDrivers' $false)) { Set-DrmProgress 2 'สำรองไดรเวอร์เดิม'; [void](Backup-DrmDrivers) }
    }

    $needsWinget = @($Plan | Where-Object { $_.Kind -in 'OemTool', 'VendorTool' -or ($_.Kind -eq 'Catalog' -and (@($_.Info.Methods) | Where-Object { $_.type -eq 'winget' })) }).Count -gt 0
    if ($needsWinget -and -not (Get-DrmWingetPath) -and -not ($Plan | Where-Object { $_.Id -eq 'winget-appinstaller' })) {
        Write-DrmLog 'ไม่พบ winget — ลองลงทะเบียน App Installer ก่อน' -Level Warn
        [void](Invoke-DrmBuiltinAction -Action 'RepairWinget')
    }

    $i = 0
    $currentPhase = -1
    $rebootRequired = $false
    $checkpointHit = $false
    $remaining = @()
    # รายการ "ฐานระบบ" ตามคำแนะนำผู้ผลิต: อัปเดตจาก OEM และ BIOS/ชิปเซ็ต/ME จากไฟล์ — ถ้าต้องรีสตาร์ท ให้รีสตาร์ทก่อนติดตั้งส่วนที่เหลือ
    $isFoundation = { param($x) ($x.Phase -eq 1) -or ($x.Phase -eq 3 -and [int](Get-DrmProp $x 'OrderIndex' 90) -le 25) }
    $resumeEnabled = [bool](Get-DrmProp $opt 'ResumeAfterReboot' $true) -and -not $script:DrmState.DryRun -and $ResumeAttempt -lt 3
    foreach ($item in @($Plan)) {
        $i++
        if (Test-DrmCancelRequested) {
            Set-DrmItemStatus -Id $item.Id -Status 'Cancelled'
            $results.Add([pscustomobject]@{ Id = $item.Id; Name = $item.Name; Phase = $item.Phase; PhaseName = $item.PhaseName; Kind = $item.Kind; Result = (New-DrmResult -Status 'Cancelled') })
            continue
        }
        if ($resumeEnabled -and -not (& $isFoundation $item)) {
            $pendingFoundation = @($results | Where-Object { $_.Result.RebootRequired -and (& $isFoundation $_) })
            if ($pendingFoundation.Count -gt 0) {
                $remaining = @($Plan | Where-Object { $_.Sequence -ge $item.Sequence })
                $checkpointHit = $true
                break
            }
        }
        if ($item.Phase -ne $currentPhase) {
            $currentPhase = $item.Phase
            Write-DrmLog ("----- ขั้นที่ {0}: {1} -----" -f $currentPhase, $item.PhaseName) -Level Step
            if ($currentPhase -eq 4) { try { [void](Get-DrmWuSearch -Refresh) } catch { Write-DrmLog ("ค้นหา Windows Update ใหม่ไม่สำเร็จ: {0}" -f $_.Exception.Message) -Level Warn } }
            if ($currentPhase -ge 5) { [void](Get-DrmUninstallEntries -Refresh) }
        }
        Set-DrmProgress (5 + 80.0 * ($i - 1) / [Math]::Max(1, $total)) ("[{0}/{1}] {2}" -f $i, $total, $item.Name)
        Set-DrmItemStatus -Id $item.Id -Status 'Running'
        Write-DrmLog ("[{0}/{1}] {2}" -f $i, $total, $item.Name) -Level Step
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $r = $null
        try { $r = Invoke-DrmPlanItem -Item $item -Options $opt -OemProfile $OemProfile }
        catch { $r = New-DrmResult -Status 'Failed' -Detail $_.Exception.Message }
        $sw.Stop()
        if (-not $r) { $r = New-DrmResult -Status 'Failed' -Detail 'ไม่มีผลลัพธ์' }
        if ($r.RebootRequired) { $rebootRequired = $true }
        $lvl = switch ($r.Status) { 'Failed' { 'error' } 'Skipped' { 'warn' } 'NotApplicable' { 'warn' } 'Manual' { 'warn' } default { 'ok' } }
        Set-DrmItemStatus -Id $item.Id -Status $r.Status -Detail $r.Detail -Level $lvl
        $logLevel = switch ($r.Status) { 'Failed' { 'Error' } 'Skipped' { 'Warn' } 'Manual' { 'Warn' } 'NotApplicable' { 'Warn' } default { 'Ok' } }
        Write-DrmLog ("ผล: {0} {1} [exit {2}, {3:N0} วินาที]" -f $r.StatusText, $r.Detail, (Format-DrmExitCode $r.ExitCode), $sw.Elapsed.TotalSeconds) -Level $logLevel
        $results.Add([pscustomobject]@{ Id = $item.Id; Name = $item.Name; Phase = $item.Phase; PhaseName = $item.PhaseName; Kind = $item.Kind; OrderIndex = (Get-DrmProp $item 'OrderIndex' 90); Seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 0); Result = $r })
    }

    if ($checkpointHit) {
        Write-DrmLog 'ติดตั้ง BIOS/ชิปเซ็ตแล้วต้องรีสตาร์ท — ผู้ผลิตแนะนำให้รีสตาร์ทก่อนติดตั้งไดรเวอร์ส่วนที่เหลือ' -Level Step
        $file = Save-DrmResumeState -Remaining $remaining -Options $opt -Session $session -Snapshot $Snapshot -Attempt ($ResumeAttempt + 1) -LauncherPath $LauncherPath
        Write-DrmLog ("บันทึกงานที่เหลือ {0} รายการไว้ที่ {1}" -f $remaining.Count, $file)
        foreach ($rem in $remaining) { Set-DrmItemStatus -Id $rem.Id -Status 'รอทำต่อหลังรีสตาร์ท' }
        $summary = [pscustomobject]@{ Results = $results.ToArray(); RebootRequired = $true; Resume = $true; Report = $null; Remaining = $remaining.Count }
        Send-DrmEvent -Type 'InstallCheckpoint' -Data @{ Summary = $summary }
        if (-not $script:DrmState.DryRun) {
            Write-DrmLog 'รีสตาร์ทใน 60 วินาที (ยกเลิกได้ด้วยคำสั่ง shutdown /a)' -Level Warn
            & shutdown.exe /r /t 60 /c "Driver & Runtime Manager: รีสตาร์ทหลังติดตั้ง BIOS/ชิปเซ็ต แล้วจะทำงานต่ออัตโนมัติ" | Out-Null
        }
        return $summary
    }

    if ($ResumeAttempt -gt 0) { Clear-DrmResumeState -Root $session.Root }

    $cleanup = $null
    if ([bool](Get-DrmProp $opt 'Cleanup' $true)) {
        Set-DrmProgress 88 'ทำความสะอาดไฟล์ที่สร้างระหว่างติดตั้ง'
        $cleanup = Invoke-DrmCleanup -Snapshot $Snapshot -Options $opt
    }

    Set-DrmProgress 92 'ตรวจผลหลังติดตั้งและความเข้ากันได้'
    Write-DrmLog '===== ตรวจผลหลังติดตั้ง =====' -Level Step
    $packagesAfter = @(); $devicesAfter = @(); $runtimesAfter = @()
    try { $packagesAfter = Get-DrmDriverPackages } catch { }
    try { $devicesAfter = Get-DrmDeviceInventory -Packages $packagesAfter -Catalog $Catalog } catch { }
    try { $runtimesAfter = Get-DrmRuntimeItems -Catalog $Catalog -System $System -Offline } catch { }
    $systemAfter = $System
    try { $systemAfter = Get-DrmSystemInfo -Catalog $Catalog -SkipNetworkTest } catch { }
    $checks = Get-DrmCompatibilityChecks -System $systemAfter -Devices $devicesAfter -DevicesBefore $DevicesBefore -Runtimes $runtimesAfter -Results $results.ToArray() -OldPackages (Get-DrmOldDriverPackages -Packages $packagesAfter -Devices $devicesAfter)
    $report = New-DrmReport -Title 'รายงานการติดตั้ง' -System $systemAfter -Devices $devicesAfter -DevicesBefore $DevicesBefore -Runtimes $runtimesAfter -Results $results.ToArray() -Checks $checks -Cleanup $cleanup
    $ok = @($results | Where-Object { $_.Result.Status -in 'Installed', 'InstalledReboot', 'UpToDate', 'Staged', 'DryRun' }).Count
    $fail = @($results | Where-Object { $_.Result.Status -eq 'Failed' }).Count
    Write-DrmLog ("===== เสร็จสิ้น: สำเร็จ/เป็นปัจจุบัน {0}, ล้มเหลว {1}, อื่น ๆ {2} =====" -f $ok, $fail, ($results.Count - $ok - $fail)) -Level Step
    Write-DrmLog ("รายงาน: {0}" -f $report.Html) -Level Ok
    Write-DrmLog ("Log: {0}" -f $session.LogFile) -Level Ok
    $pendingAfter = (Get-DrmPendingReboot).Pending
    $summary = [pscustomobject]@{ Results = $results.ToArray(); RebootRequired = ($rebootRequired -or $pendingAfter); Resume = $false; Report = $report; Checks = $checks; Cleanup = $cleanup; Devices = $devicesAfter; Runtimes = $runtimesAfter; Succeeded = $ok; Failed = $fail }
    Set-DrmProgress 100 'เสร็จสิ้น'
    if ([bool](Get-DrmProp $opt 'Reboot' $false) -and -not $script:DrmState.DryRun) {
        Write-DrmLog 'รีสตาร์ทเครื่องใน 60 วินาที (ยกเลิกได้ด้วย shutdown /a)' -Level Warn
        & shutdown.exe /r /t 60 /c "Driver & Runtime Manager: ติดตั้งเสร็จ กำลังรีสตาร์ทเพื่อให้ไดรเวอร์ทำงานครบ" | Out-Null
    }
    return $summary
}

# ---------------------------------------------------------------------------
# ทำความสะอาดหลังติดตั้ง
# ---------------------------------------------------------------------------
function Get-DrmVendorExtractPaths {
    $sd = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
    foreach ($p in 'NVIDIA', 'AMD', 'Intel', 'SWSetup', 'DRIVERS', 'Dell\Drivers', 'Dell\UpdatePackage', 'Realtek', 'Lenovo\Drivers') { '{0}\{1}' -f $sd.TrimEnd('\'), $p }
}

function Get-DrmCleanupSnapshot {
    $existing = @(Get-DrmVendorExtractPaths | Where-Object { Test-Path -LiteralPath $_ })
    [pscustomobject]@{ Time = (Get-DrmTimestamp -Format 'yyyy-MM-ddTHH:mm:ss'); Existing = $existing }
}

function Remove-DrmPathSafe {
    param([string]$Path, [ref]$Bytes, [ref]$Count)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $size = 0
        try { $size = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch { }
        if ((Get-Item -LiteralPath $Path -Force).PSIsContainer -eq $false) { $size = (Get-Item -LiteralPath $Path -Force).Length }
        if ($script:DrmState.DryRun) { Write-DrmLog ("ทดลอง: จะลบ {0} ({1})" -f $Path, (Format-DrmSize $size)) -Level Debug; return }
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        $Bytes.Value += [double]$size
        $Count.Value++
    } catch { Write-DrmLog ("ลบไม่ได้ (อาจกำลังใช้งาน): {0}" -f $Path) -Level Debug }
}

function Invoke-DrmCleanup {
    [CmdletBinding()]
    param($Snapshot, $Options)
    $session = Get-DrmSession
    Write-DrmLog '===== ทำความสะอาดไฟล์ที่สร้างระหว่างติดตั้ง =====' -Level Step
    $bytes = [double]0; $count = 0
    $since = if ($Snapshot) { ConvertTo-DrmDate $Snapshot.Time } else { $null }
    $sinceFull = $null
    if ($Snapshot) { try { $sinceFull = [datetime]::ParseExact([string]$Snapshot.Time, 'yyyy-MM-ddTHH:mm:ss', $script:Invariant) } catch { $sinceFull = $since } }
    $details = New-Object System.Collections.Generic.List[string]

    # 1) ไฟล์ดาวน์โหลด/แตกไฟล์ของโปรแกรมนี้
    if (-not [bool](Get-DrmProp $Options 'KeepDownloads' $false)) {
        $work = $session.WorkDir
        if ($work -and $work.StartsWith($session.Root, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $work)) {
            Remove-DrmPathSafe -Path $work -Bytes ([ref]$bytes) -Count ([ref]$count)
            $details.Add('ลบโฟลเดอร์ดาวน์โหลด/แตกไฟล์ของโปรแกรม')
        }
    }
    # 2) โฟลเดอร์แตกไฟล์ของผู้ผลิตที่ถูกสร้างใหม่ระหว่างติดตั้ง
    if ([bool](Get-DrmProp $Options 'CleanVendorFolders' $true)) {
        $before = @(if ($Snapshot) { $Snapshot.Existing } else { Get-DrmVendorExtractPaths })
        foreach ($p in Get-DrmVendorExtractPaths) {
            if ((Test-Path -LiteralPath $p) -and ($before -notcontains $p)) {
                Write-DrmLog ("ลบโฟลเดอร์แตกไฟล์ของผู้ผลิตที่สร้างระหว่างติดตั้ง: {0}" -f $p)
                Remove-DrmPathSafe -Path $p -Bytes ([ref]$bytes) -Count ([ref]$count)
                $details.Add("ลบ $p")
            }
        }
    }
    # 3) ไฟล์ชั่วคราวที่สร้างหลังเริ่มติดตั้ง
    if ([bool](Get-DrmProp $Options 'CleanTemp' $true) -and $sinceFull) {
        $tempDirs = @($env:TEMP, ('{0}\Temp' -f (Get-DrmWindowsDir))) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
        $n = 0
        foreach ($t in $tempDirs) {
            foreach ($e in @(Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -ge $sinceFull })) {
                Remove-DrmPathSafe -Path $e.FullName -Bytes ([ref]$bytes) -Count ([ref]$count); $n++
            }
        }
        $details.Add("ตรวจไฟล์ชั่วคราวที่สร้างระหว่างติดตั้ง $n รายการ")
    }
    # 4) แคชดาวน์โหลดของ Windows Update ที่สร้างระหว่างติดตั้ง
    if ([bool](Get-DrmProp $Options 'CleanWuCache' $false) -and $sinceFull) {
        $sd = ('{0}\SoftwareDistribution\Download' -f (Get-DrmWindowsDir))
        foreach ($e in @(Get-ChildItem -LiteralPath $sd -Force -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -ge $sinceFull })) { Remove-DrmPathSafe -Path $e.FullName -Bytes ([ref]$bytes) -Count ([ref]$count) }
        $details.Add('ลบแคชดาวน์โหลด Windows Update ของรอบนี้')
    }
    # 5) แพ็กเกจไดรเวอร์รุ่นเก่าที่ไม่ได้ใช้ (ไม่ใช้ /force — ระบบจะปฏิเสธถ้ายังใช้อยู่)
    $removedPkgs = 0
    if ([bool](Get-DrmProp $Options 'RemoveOldDrivers' $false)) {
        $pk = Get-DrmDriverPackages -SkipCertificates
        $dev = Get-DrmDeviceInventory -Packages $pk
        foreach ($o in (Get-DrmOldDriverPackages -Packages $pk -Devices $dev)) {
            Write-DrmLog ("ลบแพ็กเกจไดรเวอร์รุ่นเก่า {0} ({1} {2} → มีรุ่น {3})" -f $o.PublishedName, $o.Provider, $o.Version, $o.NewerVersion)
            $p = Invoke-DrmProcess -FilePath 'pnputil.exe' -Arguments ('/delete-driver {0}' -f $o.PublishedName) -Capture
            if ($p.ExitCode -eq 0) { $removedPkgs++ }
        }
        $details.Add("ลบแพ็กเกจไดรเวอร์เก่า $removedPkgs แพ็กเกจ")
    }
    # 6) Component Store
    if ([bool](Get-DrmProp $Options 'ComponentCleanup' $false)) {
        Write-DrmLog 'ล้าง Component Store (DISM StartComponentCleanup) อาจใช้เวลา 5-20 นาที' -Level Info
        [void](Invoke-DrmProcess -FilePath 'dism.exe' -Arguments '/Online /Cleanup-Image /StartComponentCleanup /Quiet' -Capture -TimeoutMinutes 60)
        $details.Add('ล้าง Component Store แล้ว')
    }
    Write-DrmLog ("ทำความสะอาดเสร็จ: ลบ {0} รายการ คืนพื้นที่ {1}" -f $count, (Format-DrmSize $bytes)) -Level Ok
    return [pscustomobject]@{ Removed = $count; Freed = (Format-DrmSize $bytes); FreedBytes = $bytes; Details = $details.ToArray(); RemovedDriverPackages = $removedPkgs }
}

# ---------------------------------------------------------------------------
# ตรวจความเข้ากันได้และรายงาน
# ---------------------------------------------------------------------------
function Get-DrmCompatibilityChecks {
    param($System, $Devices = @(), $DevicesBefore = @(), $Runtimes = @(), $Results = @(), $OldPackages = @())
    $list = New-Object System.Collections.Generic.List[object]
    $add = { param($area, $check, $status, $detail) $list.Add([pscustomobject]@{ Area = $area; Check = $check; Status = $status; Detail = [string]$detail }) }
    if ($System) {
        if ($System.PSObject.Properties['Lifecycle'] -and $System.Lifecycle) {
            $st = switch ($System.Lifecycle.Status) { 'EndOfSupport' { 'ไม่ผ่าน' } 'EndingSoon' { 'เตือน' } 'Unknown' { 'ข้อมูล' } default { 'ผ่าน' } }
            & $add 'Windows' 'รุ่น Windows ยังได้รับการอัปเดต' $st $System.Lifecycle.Message
        }
        & $add 'Windows' 'สถาปัตยกรรม' 'ข้อมูล' ('{0} — เลือกรันไทม์ตามสถาปัตยกรรมนี้ (รวม x86 สำหรับโปรแกรม 32 บิต)' -f $System.OS.Architecture)
        $sec = $System.Security
        & $add 'ความปลอดภัย' 'Driver signature enforcement' $(if ($sec.TestSigning -or $sec.NoIntegrity) { 'ไม่ผ่าน' } else { 'ผ่าน' }) $(if ($sec.TestSigning) { 'เปิด Test Signing อยู่ — ควรปิด (bcdedit /set testsigning off)' } else { 'บังคับตรวจลายเซ็นไดรเวอร์ตามปกติ' })
        & $add 'ความปลอดภัย' 'Secure Boot' $(if ($sec.SecureBoot -eq 'เปิด') { 'ผ่าน' } else { 'เตือน' }) $sec.SecureBoot
        & $add 'ความปลอดภัย' 'Memory Integrity (HVCI)' 'ข้อมูล' ('{0} — ถ้าเปิด ไดรเวอร์ที่ไม่รองรับ HVCI จะถูกบล็อก (รหัส 48/52)' -f $sec.Hvci)
        $sd = $System.SystemDrive
        & $add 'พื้นที่' ('พื้นที่ว่าง ' + $sd.Drive) $(if ($sd.FreeGB -lt 15) { 'ไม่ผ่าน' } elseif ($sd.FreeGB -lt 30) { 'เตือน' } else { 'ผ่าน' }) ('{0} GB ({1}%)' -f $sd.FreeGB, $sd.FreePercent)
        & $add 'Windows' 'รอรีสตาร์ท' $(if ($System.PendingReboot.Pending) { 'เตือน' } else { 'ผ่าน' }) $(if ($System.PendingReboot.Pending) { 'ต้องรีสตาร์ทเพื่อให้การติดตั้งสมบูรณ์: ' + ($System.PendingReboot.Reasons -join ', ') } else { 'ไม่มีงานค้าง' })
        if ($System.UpdatePolicy.ExcludeDrivers) { & $add 'นโยบาย' 'ไดรเวอร์จาก Windows Update' 'เตือน' 'นโยบายองค์กรปิดการรับไดรเวอร์ผ่าน Windows Update' }
        & $add 'เครื่องมือ' 'winget' $(if ($System.Tools.Winget) { 'ผ่าน' } else { 'เตือน' }) $(if ($System.Tools.Winget) { $System.Tools.WingetVersion } else { 'ไม่พบ winget' })
    }
    $present = @($Devices | Where-Object { $_.Present })
    $problems = @($present | Where-Object { $_.ProblemCode -ne 0 -and $_.ProblemCode -ne 22 })
    $beforeProblems = @($DevicesBefore | Where-Object { $_.Present -and $_.ProblemCode -ne 0 -and $_.ProblemCode -ne 22 })
    $detail = if ($problems.Count -eq 0) { 'อุปกรณ์ทุกตัวทำงานปกติ' } else { (($problems | Select-Object -First 8 | ForEach-Object { '{0} ({1})' -f $_.Name, $_.ProblemText }) -join '; ') }
    if (@($DevicesBefore).Count -gt 0) { $detail = ('ก่อนติดตั้ง {0} → หลังติดตั้ง {1} — ' -f $beforeProblems.Count, $problems.Count) + $detail }
    & $add 'อุปกรณ์' 'อุปกรณ์ที่มีปัญหา/ไม่มีไดรเวอร์' $(if ($problems.Count -eq 0) { 'ผ่าน' } else { 'ไม่ผ่าน' }) $detail
    $third = @($present | Where-Object { $_.CertLevel -notin 'Inbox', 'None' })
    $whql = @($third | Where-Object { $_.CertLevel -eq 'WHQL' })
    $att = @($third | Where-Object { $_.CertLevel -eq 'Attested' })
    $vend = @($third | Where-Object { $_.CertLevel -in 'Vendor', 'Microsoft' })
    $uns = @($third | Where-Object { $_.CertLevel -in 'Unsigned', 'Invalid' })
    & $add 'การรับรอง' 'ไดรเวอร์ผู้ผลิตที่ Microsoft รับรอง (WHQL)' $(if ($uns.Count -gt 0) { 'ไม่ผ่าน' } elseif ($att.Count + $vend.Count -gt 0) { 'เตือน' } else { 'ผ่าน' }) ('WHQL {0}, Attestation {1}, ผู้ผลิตลงนามเอง {2}, ไม่มี/เสียลายเซ็น {3} (จากไดรเวอร์ผู้ผลิต {4} ตัว)' -f $whql.Count, $att.Count, $vend.Count, $uns.Count, $third.Count)
    if ($att.Count -gt 0) { & $add 'การรับรอง' 'ไดรเวอร์แบบ Attestation' 'ข้อมูล' (($att | Select-Object -First 10 | ForEach-Object { $_.Name }) -join '; ') }
    if ($uns.Count -gt 0) { & $add 'การรับรอง' 'ไดรเวอร์ไม่มีลายเซ็นที่ถูกต้อง' 'ไม่ผ่าน' (($uns | ForEach-Object { $_.Name }) -join '; ') }
    if (@($OldPackages).Count -gt 0) { & $add 'Driver Store' 'แพ็กเกจไดรเวอร์รุ่นเก่าที่ไม่ได้ใช้' 'ข้อมูล' ('{0} แพ็กเกจ — ลบได้ด้วยตัวเลือก "ลบแพ็กเกจไดรเวอร์รุ่นเก่า"' -f @($OldPackages).Count) }
    $rec = @($Runtimes | Where-Object { @($_.Presets) -contains 'recommended' })
    $missing = @($rec | Where-Object { -not $_.Installed })
    & $add 'รันไทม์' 'รันไทม์ที่แนะนำครบ' $(if ($missing.Count -eq 0) { 'ผ่าน' } else { 'เตือน' }) $(if ($missing.Count -eq 0) { 'ครบ {0} รายการ' -f $rec.Count } else { 'ยังขาด: ' + (($missing | ForEach-Object { $_.Name }) -join '; ') })
    foreach ($r in @($Results)) {
        $st = switch ($r.Result.Status) { 'Failed' { 'ไม่ผ่าน' } { $_ -in 'Skipped', 'NotApplicable', 'Manual', 'Cancelled' } { 'เตือน' } default { 'ผ่าน' } }
        & $add ('ติดตั้ง: ' + $r.PhaseName) $r.Name $st ('{0} {1}' -f $r.Result.StatusText, $r.Result.Detail).Trim()
    }
    return , $list.ToArray()
}

function ConvertTo-DrmHtml { param([AllowNull()]$Text) [Net.WebUtility]::HtmlEncode([string]$Text) }

function New-DrmReport {
    param([string]$Title = 'รายงานการตรวจระบบ', $System, $Devices = @(), $DevicesBefore = @(), $Runtimes = @(), $Results = @(), $Checks = @(), $Cleanup, $WuDrivers = @(), $OemScan)
    $session = Get-DrmSession
    $stamp = Get-DrmTimestamp -Format 'yyyyMMdd_HHmmss'
    $base = Join-Path $session.ReportDir ("DRM_Report_{0}" -f $stamp)
    $data = [ordered]@{
        Title = $Title; Generated = (Get-DrmTimestamp); Session = $session.Id; DryRun = $script:DrmState.DryRun; LogFile = $session.LogFile
        System = $System; Checks = @($Checks); Results = @($Results | ForEach-Object { [ordered]@{ Name = $_.Name; Phase = $_.PhaseName; Kind = $_.Kind; Status = $_.Result.Status; StatusText = $_.Result.StatusText; Detail = $_.Result.Detail; ExitCode = $_.Result.ExitCode; Reboot = $_.Result.RebootRequired; Method = $_.Result.Method; Seconds = (Get-DrmProp $_ 'Seconds' 0) } })
        Devices = @($Devices | Select-Object Name, Class, VendorName, DriverProvider, DriverVersion, DriverDate, InfName, CertLevel, ProblemCode, ProblemText, Present, OrderGroup, DeviceId)
        Runtimes = @($Runtimes | Select-Object Id, Name, Group, Installed, InstalledVersion, LatestVersion, State)
        WindowsUpdateDrivers = @($WuDrivers | Select-Object Title, DriverClass, DeviceName, InstalledVersion, OfferedVersion, OfferedDate, Comparison)
        OemScan = $OemScan; Cleanup = $Cleanup
    }
    [IO.File]::WriteAllText($base + '.json', ($data | ConvertTo-Json -Depth 8), $script:Utf8Bom)

    $sb = New-Object System.Text.StringBuilder
    $css = @'
body{font-family:"Leelawadee UI","Segoe UI",Tahoma,sans-serif;margin:0;background:#f4f6f9;color:#1d2733}
header{background:#1f4e79;color:#fff;padding:18px 28px}header h1{margin:0;font-size:22px}header p{margin:4px 0 0;opacity:.85}
main{padding:20px 28px}section{background:#fff;border-radius:8px;box-shadow:0 1px 3px rgba(0,0,0,.08);padding:14px 18px;margin-bottom:18px}
h2{font-size:17px;margin:0 0 10px;color:#1f4e79}table{border-collapse:collapse;width:100%;font-size:13px}th,td{border-bottom:1px solid #e3e8ee;padding:6px 8px;text-align:left;vertical-align:top}
th{background:#eef3f8}.ok{color:#1b7f3b;font-weight:600}.warn{color:#b26a00;font-weight:600}.err{color:#c62828;font-weight:600}.info{color:#4a5a6a}
.cards{display:flex;flex-wrap:wrap;gap:12px}.card{flex:1 1 160px;background:#eef3f8;border-radius:8px;padding:10px 14px}.card b{display:block;font-size:22px}
tr.error td{background:#fdecea}tr.warn td{background:#fff8e1}small{color:#667}
'@
    [void]$sb.Append('<!DOCTYPE html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>').Append((ConvertTo-DrmHtml $Title)).Append('</title><style>').Append($css).Append('</style></head><body>')
    $hw = if ($System) { '{0} {1}' -f $System.Hardware.Manufacturer, $System.Hardware.Model } else { '' }
    $osText = if ($System) { '{0} {1} บิลด์ {2}.{3} ({4})' -f $System.OS.Caption, $System.OS.DisplayVersion, $System.OS.Build, $System.OS.UBR, $System.OS.Architecture } else { '' }
    [void]$sb.AppendFormat('<header><h1>{0}{1}</h1><p>{2} — {3} — สร้างเมื่อ {4} — เซสชัน {5}</p></header><main>', (ConvertTo-DrmHtml $Title), $(if ($script:DrmState.DryRun) { ' (โหมดทดลอง)' } else { '' }), (ConvertTo-DrmHtml $hw), (ConvertTo-DrmHtml $osText), (Get-DrmTimestamp), (ConvertTo-DrmHtml $session.Id))
    $cls = { param($s) switch ($s) { 'ผ่าน' { 'ok' } 'เตือน' { 'warn' } 'ไม่ผ่าน' { 'err' } default { 'info' } } }
    if (@($Results).Count -gt 0) {
        $ok = @($Results | Where-Object { $_.Result.Status -in 'Installed', 'InstalledReboot', 'UpToDate', 'Staged', 'DryRun' }).Count
        $fail = @($Results | Where-Object { $_.Result.Status -eq 'Failed' }).Count
        [void]$sb.AppendFormat('<section><h2>สรุป</h2><div class="cards"><div class="card"><b>{0}</b>รายการทั้งหมด</div><div class="card"><b class="ok">{1}</b>สำเร็จ/เป็นรุ่นล่าสุด</div><div class="card"><b class="err">{2}</b>ล้มเหลว</div><div class="card"><b>{3}</b>อื่น ๆ (ข้าม/ทำต่อเอง)</div></div></section>', @($Results).Count, $ok, $fail, (@($Results).Count - $ok - $fail))
    }
    if (@($Checks).Count -gt 0) {
        [void]$sb.Append('<section><h2>ความถูกต้องและความเข้ากันได้</h2><table><tr><th>หมวด</th><th>รายการตรวจ</th><th>ผล</th><th>รายละเอียด</th></tr>')
        foreach ($c in $Checks) { [void]$sb.AppendFormat('<tr><td>{0}</td><td>{1}</td><td class="{2}">{3}</td><td>{4}</td></tr>', (ConvertTo-DrmHtml $c.Area), (ConvertTo-DrmHtml $c.Check), (& $cls $c.Status), (ConvertTo-DrmHtml $c.Status), (ConvertTo-DrmHtml $c.Detail)) }
        [void]$sb.Append('</table></section>')
    }
    if (@($Results).Count -gt 0) {
        [void]$sb.Append('<section><h2>ผลการติดตั้งตามลำดับ</h2><table><tr><th>#</th><th>ขั้น</th><th>รายการ</th><th>ผล</th><th>วิธี</th><th>exit</th><th>วินาที</th><th>รายละเอียด</th></tr>')
        $n = 0
        foreach ($r in $Results) {
            $n++
            $c = switch ($r.Result.Status) { 'Failed' { 'err' } { $_ -in 'Skipped', 'Manual', 'NotApplicable', 'Cancelled' } { 'warn' } default { 'ok' } }
            [void]$sb.AppendFormat('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td class="{3}">{4}</td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td></tr>', $n, (ConvertTo-DrmHtml $r.PhaseName), (ConvertTo-DrmHtml $r.Name), $c, (ConvertTo-DrmHtml $r.Result.StatusText), (ConvertTo-DrmHtml $r.Result.Method), (ConvertTo-DrmHtml (Format-DrmExitCode $r.Result.ExitCode)), (Get-DrmProp $r 'Seconds' ''), (ConvertTo-DrmHtml $r.Result.Detail))
        }
        [void]$sb.Append('</table></section>')
    }
    if ($Cleanup) {
        [void]$sb.AppendFormat('<section><h2>ทำความสะอาด</h2><p>ลบ {0} รายการ คืนพื้นที่ {1}</p><ul>', $Cleanup.Removed, (ConvertTo-DrmHtml $Cleanup.Freed))
        foreach ($d in @($Cleanup.Details)) { [void]$sb.AppendFormat('<li>{0}</li>', (ConvertTo-DrmHtml $d)) }
        [void]$sb.Append('</ul></section>')
    }
    if ($OemScan -and @($OemScan.Updates).Count -gt 0) {
        [void]$sb.Append('<section><h2>อัปเดตที่ผู้ผลิตเครื่องพบ</h2><table><tr><th>ชื่อ</th><th>เวอร์ชัน</th><th>หมวด</th><th>ประเภท</th></tr>')
        foreach ($u in $OemScan.Updates) { [void]$sb.AppendFormat('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>', (ConvertTo-DrmHtml $u.Name), (ConvertTo-DrmHtml $u.Version), (ConvertTo-DrmHtml $u.Category), (ConvertTo-DrmHtml $u.Type)) }
        [void]$sb.Append('</table></section>')
    }
    if (@($WuDrivers).Count -gt 0) {
        [void]$sb.Append('<section><h2>ไดรเวอร์จาก Windows Update (Microsoft รับรอง)</h2><table><tr><th>ไดรเวอร์</th><th>อุปกรณ์</th><th>ติดตั้งอยู่</th><th>ที่เสนอ</th><th>เทียบ</th></tr>')
        foreach ($w in $WuDrivers) { [void]$sb.AppendFormat('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3} ({4})</td><td>{5}</td></tr>', (ConvertTo-DrmHtml $w.Title), (ConvertTo-DrmHtml $w.DeviceName), (ConvertTo-DrmHtml $w.InstalledVersion), (ConvertTo-DrmHtml $w.OfferedVersion), (ConvertTo-DrmHtml $w.OfferedDate), (ConvertTo-DrmHtml $w.ComparisonText)) }
        [void]$sb.Append('</table></section>')
    }
    if ($System) {
        [void]$sb.Append('<section><h2>ข้อมูลระบบอย่างละเอียด</h2><table><tr><th>หมวด</th><th>หัวข้อ</th><th>ค่า</th></tr>')
        foreach ($row in (ConvertTo-DrmSystemRows -System $System)) { [void]$sb.AppendFormat('<tr class="{3}"><td>{0}</td><td>{1}</td><td>{2}</td></tr>', (ConvertTo-DrmHtml $row.Section), (ConvertTo-DrmHtml $row.Item), (ConvertTo-DrmHtml $row.Value), $row.Level) }
        [void]$sb.Append('</table></section>')
    }
    if (@($Devices).Count -gt 0) {
        $shown = @($Devices | Where-Object { $_.Present -and ($_.CertLevel -ne 'Inbox' -or $_.ProblemCode -ne 0) })
        [void]$sb.AppendFormat('<section><h2>ไดรเวอร์ผู้ผลิตและอุปกรณ์ที่มีปัญหา ({0} จากอุปกรณ์ทั้งหมด {1})</h2><table><tr><th>ลำดับติดตั้ง</th><th>อุปกรณ์</th><th>คลาส</th><th>ผู้ผลิต</th><th>เวอร์ชัน</th><th>วันที่</th><th>INF</th><th>การรับรอง</th><th>สถานะ</th></tr>', $shown.Count, @($Devices).Count)
        foreach ($d in $shown) { [void]$sb.AppendFormat('<tr class="{9}"><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td><td>{8}</td></tr>', (ConvertTo-DrmHtml $d.OrderGroup), (ConvertTo-DrmHtml $d.Name), (ConvertTo-DrmHtml $d.Class), (ConvertTo-DrmHtml $(if ($d.DriverProvider) { $d.DriverProvider } else { $d.VendorName })), (ConvertTo-DrmHtml $d.DriverVersion), (ConvertTo-DrmHtml $d.DriverDate), (ConvertTo-DrmHtml $d.InfName), (ConvertTo-DrmHtml $d.CertText), (ConvertTo-DrmHtml $(if ($d.ProblemText) { $d.ProblemText } else { 'ปกติ' })), $d.Level) }
        [void]$sb.Append('</table></section>')
    }
    if (@($Runtimes).Count -gt 0) {
        [void]$sb.Append('<section><h2>รันไทม์และโปรแกรมเสริม</h2><table><tr><th>กลุ่ม</th><th>รายการ</th><th>สถานะ</th><th>ติดตั้งอยู่</th><th>ล่าสุดที่ทราบ</th></tr>')
        foreach ($r in $Runtimes) {
            $c = if ($r.Installed) { 'ok' } else { 'warn' }
            [void]$sb.AppendFormat('<tr><td>{0}</td><td>{1}</td><td class="{2}">{3}</td><td>{4}</td><td>{5}</td></tr>', (ConvertTo-DrmHtml $r.Group), (ConvertTo-DrmHtml $r.Name), $c, (ConvertTo-DrmHtml $r.State), (ConvertTo-DrmHtml $r.InstalledVersion), (ConvertTo-DrmHtml $r.LatestVersion))
        }
        [void]$sb.Append('</table></section>')
    }
    [void]$sb.AppendFormat('<section><small>Log: {0}<br>JSON: {1}.json</small></section></main></body></html>', (ConvertTo-DrmHtml $session.LogFile), (ConvertTo-DrmHtml $base))
    [IO.File]::WriteAllText($base + '.html', $sb.ToString(), $script:Utf8Bom)
    return [pscustomobject]@{ Html = ($base + '.html'); Json = ($base + '.json') }
}

# ---------------------------------------------------------------------------
# งานหลัก: สแกน และตรวจหาอัปเดต
# ---------------------------------------------------------------------------
function Invoke-DrmScan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Catalog, [switch]$SkipCertificates, [switch]$Offline)
    Set-DrmCatalogCached $Catalog
    Write-DrmLog '===== เริ่มตรวจระบบอย่างละเอียด =====' -Level Step
    Set-DrmProgress 5 'อ่านข้อมูลระบบและฮาร์ดแวร์'
    $system = Get-DrmSystemInfo -Catalog $Catalog -SkipNetworkTest:$Offline
    Write-DrmLog ("เครื่อง: {0} {1} | {2} {3} บิลด์ {4}.{5} | {6}" -f $system.Hardware.Manufacturer, $system.Hardware.Model, $system.OS.Caption, $system.OS.DisplayVersion, $system.OS.Build, $system.OS.UBR, $system.OS.Architecture)
    if ($system.Lifecycle) { Write-DrmLog $system.Lifecycle.Message -Level $(if ($system.Lifecycle.Status -eq 'Supported') { 'Ok' } else { 'Warn' }) }
    Set-DrmProgress 25 'อ่าน Driver Store และตรวจใบรับรองของไดรเวอร์'
    $packages = Get-DrmDriverPackages -SkipCertificates:$SkipCertificates
    Set-DrmProgress 50 'ตรวจอุปกรณ์ทั้งหมดและไดรเวอร์ที่ใช้งาน'
    $devices = Get-DrmDeviceInventory -Packages $packages -Catalog $Catalog
    $present = @($devices | Where-Object { $_.Present })
    $problems = @($present | Where-Object { $_.ProblemCode -ne 0 -and $_.ProblemCode -ne 22 })
    Write-DrmLog ("อุปกรณ์ {0} ตัว (เชื่อมต่ออยู่ {1}), มีปัญหา {2}, แพ็กเกจไดรเวอร์ผู้ผลิต {3}" -f $devices.Count, $present.Count, $problems.Count, $packages.Count) -Level $(if ($problems.Count) { 'Warn' } else { 'Ok' })
    foreach ($p in $problems) { Write-DrmLog ("  ! {0} [{1}] {2}" -f $p.Name, $p.Class, $p.ProblemText) -Level Warn }
    $old = Get-DrmOldDriverPackages -Packages $packages -Devices $devices
    Set-DrmProgress 70 'ตรวจรันไทม์และโปรแกรมเสริม'
    $runtimes = Get-DrmRuntimeItems -Catalog $Catalog -Arch $system.OS.Architecture -System $system -Offline:$Offline
    $oem = Get-DrmOemProfile -System $system -Catalog $Catalog
    $vendors = Get-DrmComponentVendorTools -Devices $present -Catalog $Catalog -OemProfile $oem
    Write-DrmLog ("ผู้ผลิตเครื่อง: {0} → เครื่องมือ: {1}" -f $oem.Manufacturer, $oem.Name)
    $checks = Get-DrmCompatibilityChecks -System $system -Devices $devices -Runtimes $runtimes -OldPackages $old
    Set-DrmProgress 100 'ตรวจระบบเสร็จ'
    Write-DrmLog '===== ตรวจระบบเสร็จ =====' -Level Ok
    return [pscustomobject]@{ System = $system; SystemRows = (ConvertTo-DrmSystemRows -System $system); Devices = $devices; Packages = $packages; OldPackages = $old; Runtimes = $runtimes; OemProfile = $oem; VendorTools = $vendors; Checks = $checks }
}

function Invoke-DrmUpdateCheck {
    <# ตรวจอัปเดตตามลำดับที่ผู้ใช้กำหนด: ผู้ผลิตเครื่องก่อน แล้วค่อยไดรเวอร์ที่ Microsoft รับรองจาก Windows Update #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$OemProfile, $Devices = @(), [switch]$SkipOem, [switch]$SkipWindowsUpdate)
    $oemScan = $null
    if (-not $SkipOem) {
        Set-DrmProgress 10 ("ตรวจอัปเดตจากผู้ผลิต: {0}" -f $OemProfile.Name)
        Write-DrmLog ("===== 1) ตรวจอัปเดตจากผู้ผลิตเครื่อง: {0} =====" -f $OemProfile.Name) -Level Step
        try { $oemScan = Invoke-DrmOemTool -Tool $OemProfile -Mode Scan }
        catch { $oemScan = [pscustomobject]@{ Status = 'Failed'; Updates = @(); Detail = $_.Exception.Message } }
        Write-DrmLog ("ผลจากผู้ผลิต: {0} — {1}" -f $oemScan.Status, $oemScan.Detail)
        foreach ($u in @($oemScan.Updates)) { Write-DrmLog ("  • {0} {1} [{2}]" -f $u.Name, $u.Version, $u.Category) }
    }
    $wu = @()
    if (-not $SkipWindowsUpdate) {
        Set-DrmProgress 45 'ตรวจไดรเวอร์ที่ Microsoft รับรองจาก Windows Update'
        Write-DrmLog '===== 2) ตรวจไดรเวอร์ที่ Microsoft รับรอง (Windows Update) =====' -Level Step
        $wu = Find-DrmWindowsUpdateDrivers -Devices $Devices
        foreach ($w in $wu) { Write-DrmLog ("  • {0} — {1} (ติดตั้งอยู่ {2})" -f $w.Title, $w.ComparisonText, $(if ($w.InstalledVersion) { $w.InstalledVersion } else { '-' })) }
    }
    Set-DrmProgress 100 'ตรวจหาอัปเดตเสร็จ'
    return [pscustomobject]@{ OemScan = $oemScan; WindowsUpdate = $wu }
}

# ---------------------------------------------------------------------------
# สร้างรายการแผนจากสิ่งที่ผู้ใช้เลือก (ใช้ร่วมกันทั้ง GUI และโหมดคำสั่ง)
# ---------------------------------------------------------------------------
function New-DrmPlanItemFromRuntime {
    param([Parameter(Mandatory)]$Runtime)
    [pscustomobject]@{ Id = $Runtime.Id; Kind = 'Catalog'; Name = $Runtime.Name; Category = $Runtime.Category; OrderIndex = [int]$Runtime.Order; Info = $Runtime }
}

function New-DrmPlanItemFromLocal {
    param([Parameter(Mandatory)]$Info)
    [pscustomobject]@{ Id = $Info.Id; Kind = 'Local'; Name = ('{0} [{1}]' -f $Info.Name, $Info.OrderGroup); Category = 'driver'; OrderIndex = [int]$Info.OrderIndex; Info = $Info }
}

function New-DrmPlanItemFromWindowsUpdate {
    param([Parameter(Mandatory)]$Driver)
    [pscustomobject]@{ Id = $Driver.Id; Kind = 'WuDriver'; Name = $Driver.Title; Category = 'driver'; OrderIndex = [int]$Driver.OrderIndex; UpdateId = $Driver.UpdateId }
}

function New-DrmPlanItemFromOem {
    param([Parameter(Mandatory)]$OemProfile)
    [pscustomobject]@{ Id = 'oem'; Kind = 'OemTool'; Name = ('{0} — อัปเดตทั้งหมดจาก {1}' -f $OemProfile.Name, $OemProfile.Vendor); Category = 'driver'; OrderIndex = 5; Profile = $OemProfile }
}

function New-DrmPlanItemFromVendor {
    param([Parameter(Mandatory)]$Vendor)
    [pscustomobject]@{ Id = ('vendor:' + $Vendor.Vendor); Kind = 'VendorTool'; Name = $Vendor.Name; Category = 'driver'; OrderIndex = 50; Winget = $Vendor.Winget; Url = $Vendor.Url }
}

function Select-DrmRuntimeByPreset {
    <# เลือกรันไทม์ตามชุด: recommended / gaming / work / all / none #>
    param($Runtimes = @(), [string]$Preset = 'recommended', [string[]]$Ids = @())
    foreach ($r in @($Runtimes)) {
        $pick = $false
        if ($Ids -and $Ids -contains $r.Id) { $pick = $true }
        elseif ($Preset -eq 'all') { $pick = $true }
        elseif ($Preset -and $Preset -ne 'none') { $pick = (@($r.Presets) -contains $Preset) }
        if ($pick) { $r }
    }
}

Export-ModuleMember -Function *-Drm*
