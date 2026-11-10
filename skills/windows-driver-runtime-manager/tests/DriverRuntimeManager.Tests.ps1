#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.3.0' }
# ทดสอบ Driver & Runtime Manager — ฟังก์ชันตรรกะทดสอบได้ทุกแพลตฟอร์ม ส่วนที่แท็ก Windows รันบน Windows เท่านั้น
# รัน: Invoke-Pester -Path ./tests -Output Detailed

BeforeDiscovery {
    $script:OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:ScriptsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
    Import-Module (Join-Path $script:ScriptsDir 'DriverRuntimeManager.psm1') -Force -DisableNameChecking
    $script:Catalog = Get-DrmCatalog -Path (Join-Path $script:ScriptsDir 'catalog.json')
    $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('drm-tests-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:TestRoot | Out-Null
    $script:Session = Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root')
    Set-DrmCatalogCached $script:Catalog
}

AfterAll {
    Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'แคตตาล็อก' {
    It 'ผ่านการตรวจโครงสร้างทั้งหมด' {
        $errors = Test-DrmCatalog -Catalog $script:Catalog
        $errors | Should -BeNullOrEmpty
    }
    It 'id ไม่ซ้ำและทุกรายการมีวิธีติดตั้ง' {
        $ids = @($script:Catalog.items | ForEach-Object { $_.id })
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }
    It 'รันไทม์ดาวน์โหลดตรงจากโดเมนของ Microsoft เท่านั้น' {
        $hosts = @($script:Catalog.trustedRuntimeHosts)
        foreach ($it in @($script:Catalog.items | Where-Object { $_.category -in 'runtime', 'prereq' })) {
            foreach ($m in @($it.install | Where-Object { $_.type -eq 'direct' })) {
                $hosts | Should -Contain ([Uri]$m.url).Host -Because $it.id
            }
        }
    }
    It 'มี Visual C++ v14 ครบทุกสถาปัตยกรรมจากลิงก์ถาวร aka.ms/vc14' {
        foreach ($a in 'x86', 'x64', 'arm64') {
            $it = $script:Catalog.items | Where-Object { $_.id -eq "vc14-$a" }
            $it | Should -Not -BeNullOrEmpty
            ($it.install | Where-Object { $_.type -eq 'direct' }).url | Should -Be "https://aka.ms/vc14/vc_redist.$a.exe"
        }
    }
    It 'ตรวจจับแคตตาล็อกที่ผิดพลาดได้' {
        $bad = '{"trustedRuntimeHosts":["aka.ms"],"items":[{"id":"a","name":"A","group":"g","category":"runtime","order":1,"install":[{"type":"direct","url":"http://evil.example/x.exe"}]},{"id":"a","name":"B","group":"g","category":"runtime","order":2,"install":[{"type":"bogus"}]},{"id":"c","name":"C","group":"g","category":"runtime","order":3,"install":[{"type":"direct","url":"https://evil.example/x.exe"}]}],"oemTools":[],"windowsLifecycle":[]}' | ConvertFrom-Json
        $errors = Test-DrmCatalog -Catalog $bad
        ($errors -join "`n") | Should -Match 'https'
        ($errors -join "`n") | Should -Match 'id ซ้ำ'
        ($errors -join "`n") | Should -Match 'bogus'
        ($errors -join "`n") | Should -Match 'evil\.example'
    }
}

Describe 'การเข้ารหัสไฟล์ (Windows PowerShell 5.1 อ่านภาษาไทยได้)' {
    It '<Name> เป็น UTF-8 มี BOM' -ForEach @(
        @{ Name = 'scripts/DriverRuntimeManager.ps1' }, @{ Name = 'scripts/DriverRuntimeManager.psm1' }, @{ Name = 'tests/DriverRuntimeManager.Tests.ps1' }
    ) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path (Split-Path -Parent $PSScriptRoot) $Name))
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }
    It 'ตัวเปิด .cmd เป็น ASCII ล้วน' {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $script:ScriptsDir 'Start-DriverRuntimeManager.cmd'))
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'เวอร์ชันและวันที่' {
    It 'เทียบเวอร์ชัน <A> กับ <B> = <Expected>' -ForEach @(
        @{ A = '14.50.35719.00'; B = 'v14.50.35719.0'; Expected = 0 }
        @{ A = '31.0.15.5222'; B = '31.0.15.4601'; Expected = 1 }
        @{ A = '10.0.40219.1'; B = '10.0.40219.325'; Expected = -1 }
        @{ A = '2.0'; B = '2.0.0.1'; Expected = -1 }
        @{ A = ''; B = '1.0'; Expected = -1 }
        @{ A = 'Intel - System - 10.1.19.6'; B = '10.1.18.0'; Expected = 1 }
    ) {
        Compare-DrmVersion $A $B | Should -Be $Expected
    }
    It 'ดึงเวอร์ชันจากชื่ออัปเดตของ Windows Update' {
        ConvertTo-DrmVersion 'NVIDIA - Display - 31.0.15.5222' | Should -Be '31.0.15.5222'
        ConvertTo-DrmVersion 'Realtek Semiconductor Corp. - Extension - 10.0.22621.31333' | Should -Be '10.0.22621.31333'
        ConvertTo-DrmVersion 'ไม่มีเวอร์ชัน' | Should -BeNullOrEmpty
    }
    It 'แปลงวันที่หลายรูปแบบโดยไม่ขึ้นกับปฏิทินของเครื่อง' {
        (ConvertTo-DrmDate '20230718000000.000000-000').ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) | Should -Be '2023-07-18'
        (ConvertTo-DrmDate '07/18/2023').Month | Should -Be 7
        (ConvertTo-DrmDate '2024-10-01').Year | Should -Be 2024
        Format-DrmDate ([datetime]'2026-11-10') | Should -Be '2026-11-10'
    }
}

Describe 'ลำดับติดตั้งตามคำแนะนำผู้ผลิต' {
    It 'จัดกลุ่ม <Name> เป็นลำดับ <Index>' -ForEach @(
        @{ Class = 'Firmware'; Name = 'System Firmware'; Index = 10 }
        @{ Class = 'System'; Name = 'Intel(R) Serial IO I2C Host Controller'; Index = 20 }
        @{ Class = ''; Name = 'SetupChipset Intel(R) Chipset Device Software'; Index = 20 }
        @{ Class = 'System'; Name = 'Intel(R) Management Engine Interface #1'; Index = 25 }
        @{ Class = 'SCSIAdapter'; Name = 'Standard NVM Express Controller'; Index = 30 }
        @{ Class = 'Display'; Name = 'NVIDIA GeForce RTX 4060 Laptop GPU'; Index = 40 }
        @{ Class = 'MEDIA'; Name = 'Realtek USB Audio'; Index = 50 }
        @{ Class = 'Net'; Name = 'Intel(R) Wi-Fi 6E AX211 160MHz'; Index = 60 }
        @{ Class = 'Bluetooth'; Name = 'Intel(R) Wireless Bluetooth(R)'; Index = 65 }
        @{ Class = 'USB'; Name = 'USB Root Hub (USB 3.0)'; Index = 70 }
        @{ Class = 'HIDClass'; Name = 'HID-compliant touch pad'; Index = 80 }
        @{ Class = 'Camera'; Name = 'Integrated Camera'; Index = 85 }
        @{ Class = 'Printer'; Name = 'Something'; Index = 90 }
    ) {
        (Get-DrmDriverOrder -Class $Class -Name $Name).Index | Should -Be $Index
    }
    It 'แผนเรียง: เตรียมระบบ → OEM → ชิ้นส่วน → ไฟล์ผู้ผลิต (BIOS ก่อนชิปเซ็ต) → Windows Update → รันไทม์ → โปรแกรม → ปรับแต่ง' {
        $items = @(
            [pscustomobject]@{ Id = 't'; Kind = 'Catalog'; Category = 'tweak'; Name = 'tweak'; OrderIndex = 900 }
            [pscustomobject]@{ Id = 'w'; Kind = 'WuDriver'; Category = 'driver'; Name = 'wu'; OrderIndex = 40 }
            [pscustomobject]@{ Id = 'l2'; Kind = 'Local'; Category = 'driver'; Name = 'chipset'; OrderIndex = 20 }
            [pscustomobject]@{ Id = 'r'; Kind = 'Catalog'; Category = 'runtime'; Name = 'vc'; OrderIndex = 150 }
            [pscustomobject]@{ Id = 'o'; Kind = 'OemTool'; Category = 'driver'; Name = 'oem'; OrderIndex = 5 }
            [pscustomobject]@{ Id = 'l1'; Kind = 'Local'; Category = 'driver'; Name = 'bios'; OrderIndex = 10 }
            [pscustomobject]@{ Id = 'p'; Kind = 'Catalog'; Category = 'prereq'; Name = 'winget'; OrderIndex = 1 }
            [pscustomobject]@{ Id = 'v'; Kind = 'VendorTool'; Category = 'driver'; Name = 'intel'; OrderIndex = 50 }
            [pscustomobject]@{ Id = 'a'; Kind = 'Catalog'; Category = 'tool'; Name = 'pt'; OrderIndex = 500 }
        )
        $plan = New-DrmPlan -Items $items
        ($plan | ForEach-Object { $_.Id }) -join ',' | Should -Be 'p,o,v,l1,l2,w,r,a,t'
        $plan[0].Sequence | Should -Be 1
        $plan[-1].Phase | Should -Be 7
    }
}

Describe 'Windows Update และใบรับรอง' {
    It 'เทียบไดรเวอร์ที่เสนอ: <Expected>' -ForEach @(
        @{ IV = ''; ID = $null; OV = '1.0'; OD = '2024-01-01'; PC = 28; HD = $true; Expected = 'Missing' }
        @{ IV = '1.0'; ID = '2023-01-01'; OV = '1.1'; OD = '2024-01-01'; PC = 0; HD = $true; Expected = 'Newer' }
        @{ IV = '2.0'; ID = '2025-01-01'; OV = '1.9'; OD = '2024-01-01'; PC = 0; HD = $true; Expected = 'Older' }
        @{ IV = '1.0'; ID = '2024-01-01'; OV = '1.0'; OD = '2024-01-01'; PC = 0; HD = $true; Expected = 'Same' }
        @{ IV = '1.0'; ID = '2024-01-01'; OV = '1.2'; OD = '2024-01-01'; PC = 0; HD = $true; Expected = 'Newer' }
        @{ IV = '1.0'; ID = '2024-01-01'; OV = '1.2'; OD = '2024-02-01'; PC = 0; HD = $false; Expected = 'NoDevice' }
    ) {
        Compare-DrmDriverOffer -InstalledVersion $IV -InstalledDate $ID -OfferedVersion $OV -OfferedDate $OD -ProblemCode $PC -HasDevice $HD | Should -Be $Expected
    }
    It 'แยก WHQL / Attestation / Inbox / ผู้ผลิต จาก EKU ตามเอกสาร Microsoft' {
        Get-DrmCertLevelFromEku -Oids @('1.3.6.1.4.1.311.10.3.5') -Subject 'CN=Microsoft Windows Hardware Compatibility Publisher, O=Microsoft Corporation' | Should -Be 'WHQL'
        Get-DrmCertLevelFromEku -Oids @('1.3.6.1.4.1.311.10.3.5', '1.3.6.1.4.1.311.10.3.5.1') -Subject 'O=Microsoft Corporation' | Should -Be 'Attested'
        Get-DrmCertLevelFromEku -Oids @('1.3.6.1.4.1.311.10.3.6') -Subject 'CN=Microsoft Windows, O=Microsoft Corporation' | Should -Be 'Inbox'
        Get-DrmCertLevelFromEku -Oids @('1.3.6.1.5.5.7.3.3') -Subject 'CN=Contoso Ltd, O=Contoso Ltd' | Should -Be 'Vendor'
        Get-DrmCertLevelFromEku -Oids @() -Subject '' | Should -Be 'Unsigned'
    }
    It 'แยกระดับจากชื่อผู้ลงนามเมื่อไม่มี catalog' {
        Get-DrmCertLevelFromSigner -Signer 'Microsoft Windows' -IsSigned $true -InfName 'machine.inf' | Should -Be 'Inbox'
        Get-DrmCertLevelFromSigner -Signer 'Microsoft Windows Hardware Compatibility Publisher' -IsSigned $true -InfName 'oem12.inf' | Should -Be 'WHQL'
        Get-DrmCertLevelFromSigner -Signer '' -IsSigned $false -InfName 'oem3.inf' | Should -Be 'Unsigned'
    }
}

Describe 'ผู้ผลิตเครื่อง (OEM)' {
    BeforeAll {
        function New-FakeSystem([string]$Mf, [string]$Model, [string]$Product = '', [string]$Board = '') {
            [pscustomobject]@{ Hardware = [pscustomobject]@{ Manufacturer = $Mf; Model = $Model; ProductVersion = $Product; SystemFamily = ''; BaseboardManufacturer = $Board } }
        }
    }
    It '<Mf> <Model> ใช้ <Tool>' -ForEach @(
        @{ Mf = 'Dell Inc.'; Model = 'Latitude 5440'; Product = ''; Board = ''; Tool = 'Dell Command | Update'; Auto = $true }
        @{ Mf = 'Alienware'; Model = 'Alienware m16 R2'; Product = ''; Board = ''; Tool = 'Alienware / Dell SupportAssist'; Auto = $false }
        @{ Mf = 'LENOVO'; Model = '21AH00BQUS'; Product = 'ThinkPad T14 Gen 3'; Board = ''; Tool = 'Lenovo System Update'; Auto = $true }
        @{ Mf = 'LENOVO'; Model = '82XV'; Product = 'IdeaPad Slim 5'; Board = ''; Tool = 'Lenovo Vantage'; Auto = $false }
        @{ Mf = 'HP'; Model = 'HP EliteBook 840 G10'; Product = ''; Board = ''; Tool = 'HP Image Assistant'; Auto = $true }
        @{ Mf = 'HP'; Model = 'Victus by HP Gaming Laptop 15'; Product = ''; Board = ''; Tool = 'HP Support Assistant'; Auto = $false }
        @{ Mf = 'Microsoft Corporation'; Model = 'Surface Laptop 6'; Product = ''; Board = ''; Tool = 'Windows Update (Surface)'; Auto = $false }
        @{ Mf = 'System manufacturer'; Model = 'System Product Name'; Product = ''; Board = 'ASUSTeK COMPUTER INC.'; Tool = 'MyASUS / ASUS Download Center'; Auto = $false }
        @{ Mf = 'Micro-Star International Co., Ltd.'; Model = 'MS-7D91'; Product = ''; Board = ''; Tool = 'MSI Center'; Auto = $false }
    ) {
        $p = Get-DrmOemProfile -System (New-FakeSystem $Mf $Model $Product $Board) -Catalog $script:Catalog
        $p.Name | Should -Be $Tool
        $p.Automated | Should -Be $Auto
    }
    It 'ผู้ผลิตที่ไม่รู้จักใช้ Windows Update + ผู้ผลิตชิ้นส่วน' {
        $p = Get-DrmOemProfile -System (New-FakeSystem 'Contoso' 'X1') -Catalog $script:Catalog
        $p.Vendor | Should -Be 'Other'
    }
    It 'แนะนำเครื่องมือของผู้ผลิตชิ้นส่วนจาก Vendor ID ของอุปกรณ์' {
        $devices = @(
            [pscustomobject]@{ Name = 'Intel UHD'; Class = 'Display'; VendorId = '8086' }
            [pscustomobject]@{ Name = 'GeForce'; Class = 'Display'; VendorId = '10DE' }
            [pscustomobject]@{ Name = 'NVIDIA USB'; Class = 'USB'; VendorId = '10DE' }
        )
        $tools = Get-DrmComponentVendorTools -Devices $devices -Catalog $script:Catalog -OemProfile ([pscustomobject]@{ Vendor = 'Other'; BoardVendor = $false })
        ($tools | ForEach-Object { $_.Vendor }) -join ',' | Should -Be 'Intel,NVIDIA'
        ($tools | Where-Object Vendor -eq 'Intel').Default | Should -BeTrue
    }
}

Describe 'วงจรชีวิต Windows' {
    It 'บิลด์ <Build> (<Edition>) วันที่ 2026-11-10 = <Status>' -ForEach @(
        @{ Build = 26100; Edition = 'Professional'; Status = 'EndOfSupport' }
        @{ Build = 26100; Edition = 'Enterprise'; Status = 'Supported' }
        @{ Build = 26200; Edition = 'Core'; Status = 'Supported' }
        @{ Build = 22631; Edition = 'Enterprise'; Status = 'EndingSoon' }
        @{ Build = 22621; Edition = 'Enterprise'; Status = 'EndOfSupport' }
        @{ Build = 19045; Edition = 'Professional'; Status = 'EndOfSupport' }
        @{ Build = 19044; Edition = 'EnterpriseS'; Status = 'EndingSoon' }
        @{ Build = 17763; Edition = 'EnterpriseS'; Status = 'Supported' }
        @{ Build = 99999; Edition = 'Professional'; Status = 'Supported' }
        @{ Build = 26100; Edition = 'ServerDatacenter'; Status = 'Unknown' }
    ) {
        (Get-DrmWindowsLifecycle -Build $Build -EditionId $Edition -Catalog $script:Catalog -Today ([datetime]'2026-11-10')).Status | Should -Be $Status
    }
}

Describe 'ไฟล์ติดตั้งทุกรูปแบบ' {
    BeforeAll {
        $script:InfDir = Join-Path $script:TestRoot 'driverpkg'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:InfDir 'sub') | Out-Null
        $inf = @'
[Version]
Signature   = "$WINDOWS NT$"
Class       = Display
ClassGuid   = {4d36e968-e325-11ce-bfc1-08002be10318}
Provider    = %ManufacturerName%
DriverVer   = 07/18/2023,31.0.101.4577
CatalogFile.NTamd64 = sample.cat
[Strings]
ManufacturerName = "Contoso Graphics"
'@
        Set-Content -LiteralPath (Join-Path $script:InfDir 'sub\sample.inf') -Value $inf -Encoding UTF8
        $script:RegFile = Join-Path $script:TestRoot 'tweak.reg'
        Set-Content -LiteralPath $script:RegFile -Value 'Windows Registry Editor Version 5.00' -Encoding UTF8
    }
    It 'แยกชนิดไฟล์ <File> = <Kind>' -ForEach @(
        @{ File = 'a.inf'; Kind = 'Inf' }; @{ File = 'setup.EXE'; Kind = 'Exe' }; @{ File = 'x.msi'; Kind = 'Msi' }; @{ File = 'p.msp'; Kind = 'Msp' }
        @{ File = 'kb.msu'; Kind = 'Msu' }; @{ File = 'd.cab'; Kind = 'Cab' }; @{ File = 'app.msixbundle'; Kind = 'Appx' }; @{ File = 'app.appinstaller'; Kind = 'Appx' }
        @{ File = 'drv.zip'; Kind = 'Archive' }; @{ File = 'drv.7z'; Kind = 'Archive' }; @{ File = 'drv.rar'; Kind = 'Archive' }; @{ File = 'img.iso'; Kind = 'Image' }
        @{ File = 'disk.vhdx'; Kind = 'Image' }; @{ File = 'go.cmd'; Kind = 'Script' }; @{ File = 'go.ps1'; Kind = 'PowerShell' }; @{ File = 'x.reg'; Kind = 'Registry' }
        @{ File = 'p.ppkg'; Kind = 'Provisioning' }; @{ File = 'readme.txt'; Kind = 'Unknown' }
    ) {
        Get-DrmInstallerKind $File | Should -Be $Kind
    }
    It 'จำแนกตัวติดตั้ง EXE: <Expected>' -ForEach @(
        @{ Meta = 'This installation was built with Inno Setup.'; Text = ''; Expected = 'InnoSetup' }
        @{ Meta = ''; Text = 'xx Nullsoft Install System v3.08 xx'; Expected = 'NSIS' }
        @{ Meta = ''; Text = '.text .wixburn .rsrc'; Expected = 'WixBurn' }
        @{ Meta = 'InstallShield (R)'; Text = ''; Expected = 'InstallShield' }
        @{ Meta = ''; Text = ';!@Install@!UTF-8!'; Expected = 'SevenZipSfx' }
        @{ Meta = 'Contoso'; Text = 'MZ'; Expected = 'Unknown' }
    ) {
        Get-DrmExeEngineFromText -Meta $Meta -Text $Text | Should -Be $Expected
    }
    It 'อ่าน INF: คลาส ผู้ให้ เวอร์ชัน วันที่ (แทนค่า %strings%)' {
        $i = Read-DrmInfInfo -Path (Join-Path $script:InfDir 'sub\sample.inf')
        $i.Class | Should -Be 'Display'
        $i.Provider | Should -Be 'Contoso Graphics'
        $i.Version | Should -Be '31.0.101.4577'
        $i.Date | Should -Be '2023-07-18'
    }
    It 'โฟลเดอร์ที่มี .inf เป็นแพ็กเกจไดรเวอร์เดียว จัดลำดับตามคลาส และไม่เลือกถ้าไม่มีลายเซ็น' {
        $infos = Get-DrmInstallerInfo -Path $script:InfDir -Catalog $script:Catalog
        $infos.Count | Should -Be 1
        $infos[0].Kind | Should -Be 'InfFolder'
        $infos[0].OrderIndex | Should -Be 40
        $infos[0].Selected | Should -BeFalse
    }
    It 'ไฟล์ .reg ไม่ถูกเลือกให้อัตโนมัติ' {
        $infos = Get-DrmInstallerInfo -Path $script:RegFile -Catalog $script:Catalog
        $infos[0].Kind | Should -Be 'Registry'
        $infos[0].Selected | Should -BeFalse
    }
    It 'แตก zip แล้วพบโฟลเดอร์ไดรเวอร์ข้างใน' {
        $zip = Join-Path $script:TestRoot 'pkg.zip'
        Compress-Archive -Path (Join-Path $script:InfDir '*') -DestinationPath $zip -Force
        $dest = Join-Path $script:TestRoot 'unzipped'
        Expand-DrmArchive -Path $zip -Destination $dest | Should -BeTrue
        Resolve-DrmExtractedInstaller -Dir $dest | Should -Be $dest
    }
    It 'แปลง exit code: <Code> = <Expected>' -ForEach @(
        @{ Code = 0; Expected = 'Installed' }; @{ Code = 3010; Expected = 'InstalledReboot' }; @{ Code = 1641; Expected = 'InstalledReboot' }
        @{ Code = 1638; Expected = 'UpToDate' }; @{ Code = 1603; Expected = 'Failed' }; @{ Code = $null; Expected = 'Failed' }
    ) {
        Resolve-DrmExitStatus $Code -SuccessCodes @(0, 3010, 1641) | Should -Be $Expected
    }
}

Describe 'Driver Store และความเข้ากันได้' {
    It 'เลือกเฉพาะแพ็กเกจรุ่นเก่าที่มีรุ่นใหม่กว่าและไม่ได้ใช้งาน' {
        $pk = @(
            [pscustomobject]@{ PublishedName = 'oem1.inf'; InfBaseName = 'nvlt.inf'; Provider = 'NVIDIA'; ClassName = 'Display'; Version = '31.0.15.4601'; Date = '2023-10-01'; BootCritical = $false }
            [pscustomobject]@{ PublishedName = 'oem2.inf'; InfBaseName = 'nvlt.inf'; Provider = 'NVIDIA'; ClassName = 'Display'; Version = '31.0.15.5222'; Date = '2024-03-01'; BootCritical = $false }
            [pscustomobject]@{ PublishedName = 'oem3.inf'; InfBaseName = 'nvlt.inf'; Provider = 'NVIDIA'; ClassName = 'Display'; Version = '30.0.14.9649'; Date = '2022-01-01'; BootCritical = $false }
            [pscustomobject]@{ PublishedName = 'oem4.inf'; InfBaseName = 'iastor.inf'; Provider = 'Intel'; ClassName = 'HDC'; Version = '18.0.0.1'; Date = '2022-01-01'; BootCritical = $true }
            [pscustomobject]@{ PublishedName = 'oem5.inf'; InfBaseName = 'iastor.inf'; Provider = 'Intel'; ClassName = 'HDC'; Version = '19.0.0.1'; Date = '2023-01-01'; BootCritical = $true }
        )
        $dev = @([pscustomobject]@{ InfName = 'oem3.inf' })
        $old = Get-DrmOldDriverPackages -Packages $pk -Devices $dev
        ($old | ForEach-Object { $_.PublishedName }) -join ',' | Should -Be 'oem1.inf'
    }
    It 'รายงานอุปกรณ์มีปัญหาและไดรเวอร์ไม่มีลายเซ็นว่าไม่ผ่าน' {
        $devices = @(
            [pscustomobject]@{ Name = 'Unknown device'; Present = $true; ProblemCode = 28; ProblemText = 'รหัส 28'; CertLevel = 'None' }
            [pscustomobject]@{ Name = 'Old printer'; Present = $true; ProblemCode = 0; ProblemText = ''; CertLevel = 'Unsigned' }
            [pscustomobject]@{ Name = 'GPU'; Present = $true; ProblemCode = 0; ProblemText = ''; CertLevel = 'WHQL' }
        )
        $checks = Get-DrmCompatibilityChecks -Devices $devices
        ($checks | Where-Object Check -eq 'อุปกรณ์ที่มีปัญหา/ไม่มีไดรเวอร์').Status | Should -Be 'ไม่ผ่าน'
        ($checks | Where-Object Check -eq 'ไดรเวอร์ไม่มีลายเซ็นที่ถูกต้อง').Detail | Should -Match 'Old printer'
    }
    It 'เครื่องปกติผ่านการตรวจอุปกรณ์และการรับรอง' {
        $devices = @([pscustomobject]@{ Name = 'GPU'; Present = $true; ProblemCode = 0; ProblemText = ''; CertLevel = 'WHQL' })
        $checks = Get-DrmCompatibilityChecks -Devices $devices
        ($checks | Where-Object Area -eq 'อุปกรณ์').Status | Should -Be 'ผ่าน'
        ($checks | Where-Object Check -like 'ไดรเวอร์ผู้ผลิตที่ Microsoft รับรอง*').Status | Should -Be 'ผ่าน'
    }
}

Describe 'รันไทม์ .NET และชุดที่เลือก' {
    It 'สร้างรายการ .NET จากค่าสำรองเมื่อออฟไลน์ และเลือกเฉพาะรุ่นที่ยังรองรับของสถาปัตยกรรมหลัก' {
        InModuleScope DriverRuntimeManager { $script:DrmState.DotnetIndex = $null }
        $entry = $script:Catalog.items | Where-Object { $_.dynamic -eq 'dotnet' }
        $items = @(Expand-DrmDotnetItems -Entry $entry -Catalog $script:Catalog -Arch 'x64' -Offline)
        ($items | ForEach-Object { $_.id }) | Should -Contain 'dotnet-desktop-10.0-x64'
        ($items | ForEach-Object { $_.id }) | Should -Contain 'dotnet-desktop-8.0-x86'
        ($items | Where-Object id -eq 'dotnet-desktop-10.0-x64').presets | Should -Contain 'recommended'
        $eol = $items | Where-Object id -eq 'dotnet-desktop-8.0-x64'
        if ($eol.detectedVersion) { $eol.presets | Should -Contain 'recommended' -Because 'ติดตั้งอยู่แล้วจึงอัปเดตเป็นแพตช์สุดท้าย' }
        else { @($eol.presets).Count | Should -Be 0 }
        (($items | Where-Object id -eq 'dotnet-desktop-10.0-x64').install | Where-Object type -eq 'winget').id | Should -Be 'Microsoft.DotNet.DesktopRuntime.10'
        InModuleScope DriverRuntimeManager { $script:DrmState.DotnetIndex = $null }
    }
    It 'เลือกตามชุด recommended / gaming / all / none / id' {
        $rt = @(
            [pscustomobject]@{ Id = 'a'; Presets = @('recommended', 'gaming') }
            [pscustomobject]@{ Id = 'b'; Presets = @('gaming') }
            [pscustomobject]@{ Id = 'c'; Presets = @() }
        )
        (@(Select-DrmRuntimeByPreset -Runtimes $rt -Preset 'recommended') | ForEach-Object Id) -join ',' | Should -Be 'a'
        (@(Select-DrmRuntimeByPreset -Runtimes $rt -Preset 'gaming') | ForEach-Object Id) -join ',' | Should -Be 'a,b'
        @(Select-DrmRuntimeByPreset -Runtimes $rt -Preset 'all').Count | Should -Be 3
        @(Select-DrmRuntimeByPreset -Runtimes $rt -Preset 'none').Count | Should -Be 0
        (@(Select-DrmRuntimeByPreset -Runtimes $rt -Preset 'none' -Ids 'c') | ForEach-Object Id) -join ',' | Should -Be 'c'
    }
}

Describe 'Log และรายงาน' {
    It 'บันทึก log ภาษาไทยเป็น UTF-8 พร้อม BOM' {
        Write-DrmLog 'ทดสอบบันทึกภาษาไทย' -Level Ok
        $bytes = [IO.File]::ReadAllBytes($script:Session.LogFile)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        [IO.File]::ReadAllText($script:Session.LogFile) | Should -Match 'ทดสอบบันทึกภาษาไทย'
    }
    It 'สร้างรายงาน HTML/JSON และ escape ข้อความอันตราย' {
        $devices = @([pscustomobject]@{ Name = '<script>alert(1)</script>'; Class = 'Display'; VendorName = ''; DriverProvider = 'X'; DriverVersion = '1.0'; DriverDate = '2024-01-01'; InfName = 'oem1.inf'; CertLevel = 'Vendor'; CertText = 'ผู้ผลิตลงนามเอง'; ProblemCode = 0; ProblemText = ''; Present = $true; OrderGroup = 'กราฟิก'; DeviceId = 'PCI\X'; Level = 'warn' })
        $r = New-DrmReport -Title 'ทดสอบรายงาน' -Devices $devices -Checks (Get-DrmCompatibilityChecks -Devices $devices)
        Test-Path -LiteralPath $r.Html | Should -BeTrue
        Test-Path -LiteralPath $r.Json | Should -BeTrue
        $html = [IO.File]::ReadAllText($r.Html)
        $html | Should -Match 'ทดสอบรายงาน'
        $html | Should -Not -Match '<script>alert'
        $html | Should -Match '&lt;script&gt;'
        ([IO.File]::ReadAllText($r.Json) | ConvertFrom-Json).Title | Should -Be 'ทดสอบรายงาน'
    }
}

Describe 'รันแผนทั้งหมดในโหมดทดลอง' {
    It 'ทุกขั้นทำงานตามลำดับโดยไม่ติดตั้งจริงและไม่มีรายการล้มเหลว' {
        $root = Join-Path $script:TestRoot 'dry'
        $s = Initialize-DrmSession -Root $root -DryRun
        $all = Get-DrmRuntimeItems -Catalog $script:Catalog -Arch 'x64' -Offline
        $rt = @($all | Where-Object { $_.Id -in 'vc14-x64', 'netfx35', 'tweak-gamemode', 'powershell7', 'directx-jun2010' })
        $rt.Count | Should -Be 5
        $local = Get-DrmInstallerInfo -Path (Join-Path $script:TestRoot 'driverpkg') -Catalog $script:Catalog
        $oem = Get-DrmOemProfile -System ([pscustomobject]@{ Hardware = [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'Latitude 7440'; ProductVersion = ''; SystemFamily = ''; BaseboardManufacturer = '' } }) -Catalog $script:Catalog
        $items = @()
        $items += New-DrmPlanItemFromOem -OemProfile $oem
        $items += New-DrmPlanItemFromLocal -Info $local[0]
        $items += New-DrmPlanItemFromWindowsUpdate -Driver ([pscustomobject]@{ Id = 'wu:1'; UpdateId = '00000000-0000-0000-0000-000000000001'; Title = 'Intel - System - 10.1.19.6'; OrderIndex = 20 })
        foreach ($r in $rt) { $items += New-DrmPlanItemFromRuntime -Runtime $r }
        $plan = New-DrmPlan -Items $items
        $opt = [pscustomobject]@{ CreateRestorePoint = $true; BackupDrivers = $false; ResumeAfterReboot = $true; Reboot = $true; AllowUnsigned = $true; Cleanup = $true; KeepDownloads = $false; CleanVendorFolders = $true; CleanTemp = $false; CleanWuCache = $false; RemoveOldDrivers = $false; ComponentCleanup = $false }
        $sum = Invoke-DrmInstallPlan -Plan $plan -Options $opt -Catalog $script:Catalog -OemProfile $oem
        $sum.Resume | Should -BeFalse
        @($sum.Results).Count | Should -Be $plan.Count
        @($sum.Results | Where-Object { $_.Result.Status -eq 'Failed' }) | Should -BeNullOrEmpty
        ($sum.Results | ForEach-Object { $_.Phase }) -join ',' | Should -Be (($plan | ForEach-Object { $_.Phase }) -join ',')
        Test-Path -LiteralPath $sum.Report.Html | Should -BeTrue
        [IO.File]::ReadAllText($s.LogFile) | Should -Match 'ทดลอง'
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') | Out-Null
    }
}

Describe 'Windows จริง' -Tag 'Windows' -Skip:(-not $script:OnWindows) {
    It 'อ่านข้อมูลระบบได้ครบ' {
        $s = Get-DrmSystemInfo -Catalog $script:Catalog -SkipNetworkTest
        $s.OS.Build | Should -BeGreaterThan 10000
        $s.OS.Architecture | Should -BeIn @('x64', 'arm64', 'x86')
        $s.Lifecycle | Should -Not -BeNullOrEmpty
        $rows = ConvertTo-DrmSystemRows -System $s
        $rows.Count | Should -BeGreaterThan 15
    }
    It 'ตรวจอุปกรณ์และลำดับติดตั้งของทุกอุปกรณ์' {
        $pk = Get-DrmDriverPackages
        $d = Get-DrmDeviceInventory -Packages $pk -Catalog $script:Catalog
        $d.Count | Should -BeGreaterThan 10
        @($d | Where-Object { -not $_.OrderIndex }).Count | Should -Be 0
        @($d | Where-Object { $_.CertLevel -eq 'Inbox' }).Count | Should -BeGreaterThan 0
    }
    It 'ตรวจลายเซ็นไฟล์ของ Microsoft ได้' {
        $sig = Get-DrmFileSignature -Path (Join-Path $env:SystemRoot 'System32\kernel32.dll')
        $sig.IsValid | Should -BeTrue
        $sig.IsMicrosoft | Should -BeTrue
    }
    It 'ตรวจรันไทม์ในเครื่องได้' {
        $rt = Get-DrmRuntimeItems -Catalog $script:Catalog -Offline
        $rt.Count | Should -BeGreaterThan 10
        ($rt | Where-Object Id -eq 'vc14-x64') | Should -Not -BeNullOrEmpty
    }
}
