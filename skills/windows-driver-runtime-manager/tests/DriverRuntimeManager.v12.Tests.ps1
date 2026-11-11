#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.3.0' }
# ทดสอบการแก้ข้อบกพร่องรอบ v1.2 (DRM-101 ถึง DRM-121) — อ้างอิง references/known-issues.md
# รัน: Invoke-Pester -Path ./tests -Output Detailed

BeforeDiscovery {
    $script:OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:ScriptsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    Import-Module (Join-Path $script:ScriptsDir 'DriverRuntimeManager.psm1') -Force -DisableNameChecking
    $script:Catalog = Get-DrmCatalog -Path (Join-Path $script:ScriptsDir 'catalog.json')
    $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('drm-v12-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:TestRoot | Out-Null
    $script:Session = Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser
    Set-DrmCatalogCached $script:Catalog
    $script:OnWin = ($PSVersionTable.PSEdition -eq 'Desktop') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
    # Linux/macOS ตัด exit code เหลือ 0-255
    function Get-ExitAs([int]$Code) { if ($script:OnWin) { $Code } else { $Code % 256 } }
    function New-FakeHw([string]$Mf, [string]$Model, [string]$Board = '', [string]$Family = '') {
        [pscustomobject]@{ Hardware = [pscustomobject]@{ Manufacturer = $Mf; Model = $Model; ProductVersion = ''; SystemFamily = $Family; BaseboardManufacturer = $Mf; BaseboardProduct = $Board } }
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'DRM-112: ฟังก์ชันคืนรายการทาง pipeline (ว่าง/หนึ่ง/หลายรายการ)' {
    It 'รายการว่างไม่ได้ $null ซ้อนในอาร์เรย์' {
        @(Test-DrmCatalog -Catalog $script:Catalog).Count | Should -Be 0
        @(Get-DrmCompatibilityChecks -Devices @()).Count | Should -BeGreaterThan 0
        @(New-DrmPlan -Items @()).Count | Should -Be 0
    }
    It 'หนึ่งรายการ: @() ได้ 1 ไม่ใช่อาร์เรย์ซ้อน' {
        $one = @(New-DrmPlan -Items @([pscustomobject]@{ Id = 'a'; Kind = 'Catalog'; Category = 'runtime'; Name = 'A'; OrderIndex = 1 }))
        $one.Count | Should -Be 1
        $one[0].Id | Should -Be 'a'
        $one[0] -is [array] | Should -BeFalse
    }
    It 'pipe ตรง ๆ แล้วตัวกรองเห็นทีละรายการ (ต้นเหตุของ DRM-019)' {
        @(Get-DrmRuntimeItems -Catalog $script:Catalog -Arch 'x64' -Offline | Where-Object { $_.Id -eq 'vc14-x64' }).Count | Should -Be 1
        @(New-DrmPlan -Items @(
                [pscustomobject]@{ Id = 'a'; Kind = 'Catalog'; Category = 'runtime'; Name = 'A'; OrderIndex = 1 },
                [pscustomobject]@{ Id = 'b'; Kind = 'Catalog'; Category = 'tool'; Name = 'B'; OrderIndex = 2 }) | Where-Object { $_.Id -eq 'b' }).Count | Should -Be 1
    }
    It 'ไม่มีฟังก์ชันใดในโมดูลที่ยังใช้ return , (ข้อตกลงเดิม)' {
        $text = [IO.File]::ReadAllText((Join-Path $script:ScriptsDir 'DriverRuntimeManager.psm1'))
        $text | Should -Not -Match 'return\s*,\s*\$'
    }
}

Describe 'DRM-106: แคชระดับการรับรองของ .cat' {
    BeforeAll {
        $script:Cat = Join-Path $script:TestRoot 'pkg\driver.cat'
        New-Item -ItemType Directory -Force -Path (Split-Path $script:Cat) | Out-Null
        [IO.File]::WriteAllBytes($script:Cat, [byte[]](1..64))
    }
    It 'ตรวจครั้งแรก เก็บแคช แล้วครั้งถัดไปไม่ตรวจซ้ำ' {
        Mock -ModuleName DriverRuntimeManager Get-DrmFileSignature { [pscustomobject]@{ CertLevel = 'WHQL' } }
        $cache = @{}
        $a = Get-DrmCatalogCertLevel -Path $script:Cat -Cache $cache
        $b = Get-DrmCatalogCertLevel -Path $script:Cat -Cache $cache
        $a.Level | Should -Be 'WHQL'; $a.Cached | Should -BeFalse
        $b.Level | Should -Be 'WHQL'; $b.Cached | Should -BeTrue
        Should -Invoke -ModuleName DriverRuntimeManager Get-DrmFileSignature -Times 1 -Exactly
    }
    It 'ไฟล์เปลี่ยน (ขนาด/เวลา) หรือแคชเก่าเกิน 30 วัน ต้องตรวจใหม่' {
        Mock -ModuleName DriverRuntimeManager Get-DrmFileSignature { [pscustomobject]@{ CertLevel = 'Attested' } }
        $cache = @{}
        [void](Get-DrmCatalogCertLevel -Path $script:Cat -Cache $cache)
        [IO.File]::WriteAllBytes($script:Cat, [byte[]](1..80))
        (Get-DrmCatalogCertLevel -Path $script:Cat -Cache $cache).Cached | Should -BeFalse
        (Get-DrmCatalogCertLevel -Path $script:Cat -Cache $cache -Now (Get-Date).AddDays(40)).Cached | Should -BeFalse
        Should -Invoke -ModuleName DriverRuntimeManager Get-DrmFileSignature -Times 3 -Exactly
    }
    It 'ไม่เก็บผล Invalid/Unknown ไว้ในแคช' {
        Mock -ModuleName DriverRuntimeManager Get-DrmFileSignature { [pscustomobject]@{ CertLevel = 'Invalid' } }
        $cache = @{}
        [void](Get-DrmCatalogCertLevel -Path $script:Cat -Cache $cache)
        $cache.Count | Should -Be 0
    }
    It 'บันทึกและอ่านไฟล์แคชกลับได้ (ไฟล์เสียแล้วเริ่มใหม่)' {
        $f = Join-Path $script:TestRoot 'cert-cache.json'
        $cache = @{ 'c:\windows\system32\driverstore\x.cat' = @{ Stamp = '1|2'; Level = 'WHQL'; Checked = '2026-11-10' } }
        Save-DrmCertCache -Cache $cache -Path $f
        $back = Read-DrmCertCache -Path $f
        $back['c:\windows\system32\driverstore\x.cat'].Level | Should -Be 'WHQL'
        [IO.File]::WriteAllText($f, '{ broken')
        (Read-DrmCertCache -Path $f).Count | Should -Be 0
    }
}

Describe 'DRM-107: .NET จาก releases.json พร้อม SHA512' {
    BeforeAll { $script:Rel = [IO.File]::ReadAllText((Join-Path $script:Fixtures 'dotnet-releases-10.0.json')) | ConvertFrom-Json }
    It 'เลือกไฟล์ windowsdesktop .exe ตามสถาปัตยกรรม: <Arch>' -ForEach @(@{ Arch = 'x64' }, @{ Arch = 'x86' }, @{ Arch = 'arm64' }) {
        $f = Select-DrmDotnetFile -Releases $script:Rel -Arch $Arch -Version '10.0.15'
        $f.Version | Should -Be '10.0.15'
        $f.Url | Should -Be ("https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/10.0.15/windowsdesktop-runtime-10.0.15-win-{0}.exe" -f $Arch)
        $f.Sha512 | Should -Match '^[0-9A-F]{128}$'
    }
    It 'เลือกรุ่นตามที่ขอ และคืน $null เมื่อไม่มีรุ่นนั้น' {
        (Select-DrmDotnetFile -Releases $script:Rel -Arch 'x64' -Version '10.0.14').Version | Should -Be '10.0.14'
        Select-DrmDotnetFile -Releases $script:Rel -Arch 'x64' -Version '10.0.99' | Should -BeNullOrEmpty
    }
    It 'ใช้ releases.json เมื่ออ่านได้ และใช้แม่แบบ URL เมื่ออ่านไม่ได้หรือโฮสต์ไม่น่าเชื่อถือ' {
        $m = [pscustomobject]@{ type = 'dotnet'; version = '10.0.15'; arch = 'x64'; releasesJson = 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json' }
        $rel = $script:Rel
        Mock -ModuleName DriverRuntimeManager Get-DrmJson { $rel }
        $ok = Resolve-DrmDotnetDownload -Method $m -Catalog $script:Catalog
        $ok.Source | Should -Be 'releases.json'
        $ok.Sha512 | Should -Not -BeNullOrEmpty
        Mock -ModuleName DriverRuntimeManager Get-DrmJson { throw 'offline' }
        $fb = Resolve-DrmDotnetDownload -Method $m -Catalog $script:Catalog
        $fb.Source | Should -Be 'template'
        $fb.Sha512 | Should -BeNullOrEmpty
        $fb.Url | Should -Match 'windowsdesktop-runtime-10\.0\.15-win-x64\.exe$'
        $evil = [IO.File]::ReadAllText((Join-Path $script:Fixtures 'dotnet-releases-10.0.json')).Replace('builds.dotnet.microsoft.com', 'example.invalid') | ConvertFrom-Json
        Mock -ModuleName DriverRuntimeManager Get-DrmJson { $evil }
        (Resolve-DrmDotnetDownload -Method $m -Catalog $script:Catalog).Source | Should -Be 'template'
    }
    It 'ช่อง .NET เก็บ URL ของ releases.json ไว้ใช้ตอนติดตั้ง' {
        $idx = [pscustomobject]@{ 'releases-index' = @([pscustomobject]@{ 'channel-version' = '10.0'; 'latest-runtime' = '10.0.15'; 'latest-release' = '10.0.15'; 'support-phase' = 'active'; 'release-type' = 'lts'; 'releases.json' = 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json' }) }
        Mock -ModuleName DriverRuntimeManager Get-DrmJson { $idx }
        InModuleScope DriverRuntimeManager { $script:DrmState.DotnetIndex = $null }
        $ch = @(Get-DrmDotnetChannels -Catalog $script:Catalog)
        $ch[0].ReleasesJson | Should -Match '10\.0/releases\.json$'
        InModuleScope DriverRuntimeManager { $script:DrmState.DotnetIndex = $null }
    }
}

Describe 'DRM-108: winget อัปเดตแหล่งข้อมูลแล้วลองใหม่' {
    It 'รหัสกลุ่มแหล่งข้อมูลถูกจัดว่าเป็นปัญหาแหล่งข้อมูล' {
        Test-DrmWingetSourceError -Code -1978335163 | Should -BeTrue     # 0x8A150045
        Test-DrmWingetSourceError -Code 0x8A15000AL | Should -BeTrue
        Test-DrmWingetSourceError -Code -1978335189 | Should -BeFalse    # 0x8A15002B ไม่มีรุ่นใหม่
        Test-DrmWingetSourceError -Code 1 -Text 'Failed when opening source(s); try the source reset command' | Should -BeTrue
        Test-DrmWingetSourceError -Code 0 -Text 'source' | Should -BeFalse
    }
    It 'ล้มเหลวเพราะแหล่งข้อมูล → winget source update หนึ่งครั้ง → ติดตั้งสำเร็จ' {
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'winget') -NoBrowser | Out-Null
        $global:DrmWgCalls = New-Object System.Collections.Generic.List[string]
        Mock -ModuleName DriverRuntimeManager Get-DrmWingetPath { 'C:\fake\winget.exe' }
        Mock -ModuleName DriverRuntimeManager Invoke-DrmProcess {
            $global:DrmWgCalls.Add($Arguments)
            $installs = @($global:DrmWgCalls | Where-Object { $_ -like 'install*' }).Count
            $code = if ($Arguments -like 'source update*') { 0 } elseif ($installs -eq 1) { -1978335163 } else { 0 }
            [pscustomobject]@{ ExitCode = $code; TimedOut = $false; Output = ''; Error = ''; Command = $Arguments; DryRun = $false; OutputFile = $null }
        }
        $r = Install-DrmWingetPackage -Id 'Contoso.App' -ItemId 'x'
        $r.Status | Should -Be 'Installed'
        @($global:DrmWgCalls | Where-Object { $_ -like 'source update*' }).Count | Should -Be 1
        @($global:DrmWgCalls | Where-Object { $_ -like 'install*' }).Count | Should -Be 2
        Remove-Variable -Name DrmWgCalls -Scope Global
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser | Out-Null
    }
    It 'ยังล้มเหลวหลังอัปเดตแหล่งข้อมูล → รายงานว่าลองแล้ว และไม่วนซ้ำ' {
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'winget2') -NoBrowser | Out-Null
        Mock -ModuleName DriverRuntimeManager Get-DrmWingetPath { 'C:\fake\winget.exe' }
        Mock -ModuleName DriverRuntimeManager Invoke-DrmProcess { [pscustomobject]@{ ExitCode = $(if ($Arguments -like 'source update*') { 0 } else { -1978335163 }); TimedOut = $false; Output = ''; Error = ''; Command = $Arguments; DryRun = $false; OutputFile = $null } }
        $r = Install-DrmWingetPackage -Id 'Contoso.App' -ItemId 'x'
        $r.Status | Should -Be 'Failed'
        $r.Detail | Should -Match 'winget source update'
        Should -Invoke -ModuleName DriverRuntimeManager Invoke-DrmProcess -Times 3 -Exactly
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser | Out-Null
    }
}

Describe 'DRM-109: Game Mode เขียนโปรไฟล์ของผู้ใช้ที่ล็อกอิน' {
    It '<Case>' -ForEach @(
        @{ Case = 'ผู้ใช้เดียวกัน → HKCU'; Sid = 'S-1-5-21-1-1001'; Cur = 'S-1-5-21-1-1001'; Loaded = $true; Expect = 'HKCU:\Software\Microsoft\GameBar' }
        @{ Case = 'ยกระดับด้วยบัญชี Admin อื่น → HKEY_USERS ของผู้ใช้ที่ล็อกอิน'; Sid = 'S-1-5-21-1-1001'; Cur = 'S-1-5-21-1-500'; Loaded = $true; Expect = 'Registry::HKEY_USERS\S-1-5-21-1-1001\Software\Microsoft\GameBar' }
        @{ Case = 'hive ไม่ได้โหลด → HKCU'; Sid = 'S-1-5-21-1-1001'; Cur = 'S-1-5-21-1-500'; Loaded = $false; Expect = 'HKCU:\Software\Microsoft\GameBar' }
        @{ Case = 'หา explorer.exe ไม่เจอ → HKCU'; Sid = ''; Cur = 'S-1-5-21-1-500'; Loaded = $true; Expect = 'HKCU:\Software\Microsoft\GameBar' }
    ) {
        Resolve-DrmUserHivePath -SubKey 'Software\Microsoft\GameBar' -InteractiveSid $Sid -CurrentSid $Cur -HiveLoaded $Loaded | Should -Be $Expect
    }
}

Describe 'DRM-101: อ่านรายงานดิบของ Dell / HP' {
    It 'Dell DCUApplicableUpdates.xml แบบ element' {
        $u = @(ConvertFrom-DrmDellReport -Text ([IO.File]::ReadAllText((Join-Path $script:Fixtures 'dell-DCUApplicableUpdates.xml'))))
        $u.Count | Should -Be 3
        $u[0].Name | Should -Be 'Dell Latitude 5440 System BIOS'
        $u[0].Version | Should -Be '1.12.0'
        $u[0].Category | Should -Be 'BIOS'
        $u[0].Urgency | Should -Be 'Urgent'
        $u[1].Id | Should -Be 'FGHIJ'
    }
    It 'Dell แบบ attribute และมี namespace' {
        $u = @(ConvertFrom-DrmDellReport -Text ([IO.File]::ReadAllText((Join-Path $script:Fixtures 'dell-attributes.xml'))))
        $u.Count | Should -Be 2
        $u[1].Name | Should -Match 'Management Engine'
        $u[0].Id | Should -Be 'ABCDE'
    }
    It 'HPIA JSON แบบรายการเดียว (มีสถานะติดตั้ง)' {
        $u = @(ConvertFrom-DrmHpiaReport -Text ([IO.File]::ReadAllText((Join-Path $script:Fixtures 'hpia-flat.json'))) -Format json)
        $u.Count | Should -Be 3
        $u[0].Name | Should -Be 'HP Notebook System BIOS Update'
        $u[0].Version | Should -Be '01.12.00'
        $u[0].Installed | Should -Be '01.10.00'
        $u[0].Id | Should -Be 'sp150000'
        $u[2].Status | Should -Be 'Failed'
        $u[2].ReturnCode | Should -Be 1603
    }
    It 'HPIA JSON แบบจัดกลุ่มตามหมวด' {
        $u = @(ConvertFrom-DrmHpiaReport -Text ([IO.File]::ReadAllText((Join-Path $script:Fixtures 'hpia-grouped.json'))) -Format json)
        $u.Count | Should -Be 2
        ($u | ForEach-Object { $_.Category }) -join ',' | Should -Be 'BIOS,Drivers'
        $u[1].Id | Should -Be 'sp150001'
    }
    It 'HPIA XML (HPIA/Recommendations/<หมวด>/Recommendation)' {
        $u = @(ConvertFrom-DrmHpiaReport -Text ([IO.File]::ReadAllText((Join-Path $script:Fixtures 'hpia-report.xml'))) -Format xml)
        $u.Count | Should -Be 2
        $u[0].Name | Should -Be 'HP Notebook System BIOS Update'
        $u[0].Id | Should -Be 'sp150000'
        $u[1].Category | Should -Be 'Drivers'
    }
    It 'Read-DrmOemReport อ่านทั้งโฟลเดอร์ ไม่นับซ้ำเมื่อมีทั้ง JSON และ XML' {
        $d = Join-Path $script:TestRoot 'oem-scan-hp'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        Copy-Item (Join-Path $script:Fixtures 'hpia-flat.json') $d
        Copy-Item (Join-Path $script:Fixtures 'hpia-report.xml') $d
        @(Read-DrmOemReport -Kind 'hpia' -Dir $d).Count | Should -Be 3
        $dd = Join-Path $script:TestRoot 'oem-scan-dell'
        New-Item -ItemType Directory -Force -Path $dd | Out-Null
        Copy-Item (Join-Path $script:Fixtures 'dell-DCUApplicableUpdates.xml') $dd
        @(Read-DrmOemReport -Kind 'dell' -Dir $dd).Count | Should -Be 3
        @(Read-DrmOemReport -Kind 'dell' -Dir (Join-Path $script:TestRoot 'missing')).Count | Should -Be 0
    }
}

Describe 'DRM-119/121: เลือกเครื่องมือ HP และรหัสของ Dell/HP' {
    It '<Model> ใช้ <Tool> (เดาจากชื่อรุ่นเมื่อไม่มีรายการของ HP)' -ForEach @(
        @{ Model = 'HP EliteBook 840 G10 Notebook PC'; Tool = 'HP Image Assistant' }
        @{ Model = 'HP ProBook 450 15.6 inch G10 Notebook PC'; Tool = 'HP Image Assistant' }
        @{ Model = 'HP ZBook Firefly 14 G10'; Tool = 'HP Image Assistant' }
        @{ Model = 'HP Z2 Tower G9 Workstation'; Tool = 'HP Image Assistant' }
        @{ Model = 'HP 250 G10 Notebook PC'; Tool = 'HP Image Assistant' }
        @{ Model = 'HP Pro Mini 400 G9 Desktop PC'; Tool = 'HP Image Assistant' }
        @{ Model = 'HP Laptop 15s-fq5xxx'; Tool = 'HP Support Assistant' }
        @{ Model = 'Victus by HP Gaming Laptop 16-r0xxx'; Tool = 'HP Support Assistant' }
        @{ Model = 'HP ENVY x360 2-in-1 Laptop 14-fc0xxx'; Tool = 'HP Support Assistant' }
        @{ Model = 'OMEN by HP Transcend Gaming Laptop 14'; Tool = 'HP Support Assistant' }
    ) {
        (Get-DrmOemProfile -System (New-FakeHw 'HP' $Model) -Catalog $script:Catalog).Name | Should -Be $Tool
    }
    It 'รายการรุ่นที่ HPIA รองรับจาก HP ชี้ขาดแทนชื่อรุ่น' {
        $ids = @(ConvertFrom-DrmHpiaPlatformXml -Text ([IO.File]::ReadAllText((Join-Path $script:Fixtures 'hpia-platformList.xml'))))
        $ids | Should -Contain '8AB8'
        $ids | Should -Contain '8A78'
        $ids | Should -Contain '8B42'
        # System ID เทียบแบบไม่สนตัวพิมพ์ (Win32_BaseBoard.Product บางเครื่องเป็นตัวเล็ก)
        (Get-DrmOemProfile -System (New-FakeHw 'HP' 'HP Laptop 15s' '8b41') -Catalog $script:Catalog -HpiaPlatforms $ids).Name | Should -Be 'HP Image Assistant'
        $p = Get-DrmOemProfile -System (New-FakeHw 'HP' 'HP Laptop 15s' '8B41') -Catalog $script:Catalog -HpiaPlatforms $ids
        $p.Name | Should -Be 'HP Image Assistant'
        $p.MatchedBy | Should -Match '8B41'
        (Get-DrmOemProfile -System (New-FakeHw 'HP' 'HP EliteBook 840 G10' 'FFFF') -Catalog $script:Catalog -HpiaPlatforms $ids).Name | Should -Be 'HP Support Assistant'
    }
    It 'รหัสของ Dell Command | Update ตรงตามเอกสาร Dell (4 = ไม่ใช่ Admin, 7 = ไม่รองรับรุ่น)' {
        (Get-DrmErrorInfo -Code 4 -Source 'dcu').Title | Should -Match 'Administrator'
        (Get-DrmErrorInfo -Code 7 -Source 'dcu').Title | Should -Match 'ไม่รองรับ'
        $dcu = $script:Catalog.oemTools | Where-Object { $_.name -eq 'Dell Command | Update' }
        @($dcu.successCodes) | Should -Not -Contain 5
        @($dcu.unsupportedCodes) | Should -Contain 7
        @($dcu.pendingRebootCodes) | Should -Contain 5
    }
    It 'รหัสของ HP Image Assistant: 3020 = บางรายการล้มเหลว ไม่ใช่สำเร็จ, 257 = ไม่มีรายการ' {
        $hpia = $script:Catalog.oemTools | Where-Object { $_.name -eq 'HP Image Assistant' }
        @($hpia.successCodes) | Should -Not -Contain 3020
        @($hpia.noUpdateCodes) | Should -Contain 257
        @($hpia.rebootCodes) | Should -Not -Contain 257
        (Get-DrmErrorInfo -Code 3020 -Source 'hpia').Title | Should -Match 'ไม่สำเร็จ'
    }
}

Describe 'DRM-105: เครื่องมือ OEM ไม่รองรับรุ่นนี้ → ทำต่อเองจากหน้าเว็บผู้ผลิต' {
    BeforeAll {
        $script:Dell = Get-DrmOemProfile -System (New-FakeHw 'Dell Inc.' 'Inspiron 16 5640') -Catalog $script:Catalog
    }
    It 'ติดตั้ง: exit 7 ได้สถานะ "ทำต่อเอง" ไม่ใช่ล้มเหลว (และไม่เปิดเบราว์เซอร์ในโหมด -NoBrowser)' {
        Mock -ModuleName DriverRuntimeManager Find-DrmToolExe { 'C:\fake\dcu-cli.exe' }
        Mock -ModuleName DriverRuntimeManager Invoke-DrmProcess { [pscustomobject]@{ ExitCode = 7; TimedOut = $false; Output = ''; Error = ''; Command = 'dcu-cli'; DryRun = $false; OutputFile = $null } }
        $r = Invoke-DrmOemTool -Tool $script:Dell -Mode Apply
        $r.Status | Should -Be 'Manual'
        $r.Detail | Should -Match 'ไม่รองรับ'
        $r.Detail | Should -Match 'dell\.com'
    }
    It 'สแกน: exit 7 = Unsupported, exit 5 = RebootPending' {
        Mock -ModuleName DriverRuntimeManager Find-DrmToolExe { 'C:\fake\dcu-cli.exe' }
        Mock -ModuleName DriverRuntimeManager Invoke-DrmProcess { [pscustomobject]@{ ExitCode = 7; TimedOut = $false; Output = ''; Error = ''; Command = 'dcu-cli'; DryRun = $false; OutputFile = $null } }
        (Invoke-DrmOemTool -Tool $script:Dell -Mode Scan).Status | Should -Be 'Unsupported'
        Mock -ModuleName DriverRuntimeManager Invoke-DrmProcess { [pscustomobject]@{ ExitCode = 5; TimedOut = $false; Output = ''; Error = ''; Command = 'dcu-cli'; DryRun = $false; OutputFile = $null } }
        $s = Invoke-DrmOemTool -Tool $script:Dell -Mode Scan
        $s.Status | Should -Be 'RebootPending'
        $s.RebootRequired | Should -BeTrue
        $a = Invoke-DrmOemTool -Tool $script:Dell -Mode Apply
        $a.Status | Should -Be 'Manual'
        $a.RebootRequired | Should -BeTrue
    }
}

Describe 'DRM-104: Lenovo System Update ไม่ถามข้อตกลง' {
    It 'แคตตาล็อกตั้ง DisplayLicenseNotice/DisplayLicenseNoticeSU = NO ก่อนรัน /CM' {
        $p = Get-DrmOemProfile -System (New-FakeHw 'LENOVO' '21AH00BQUS' '' 'ThinkPad T14 Gen 3') -Catalog $script:Catalog
        $p.Name | Should -Be 'Lenovo System Update'
        @($p.Preferences | Where-Object { $_.name -eq 'DisplayLicenseNotice' -and $_.value -eq 'NO' }).Count | Should -BeGreaterThan 0
        @($p.Preferences | Where-Object { $_.name -eq 'DisplayLicenseNoticeSU' }).Count | Should -BeGreaterThan 0
        @($p.LogDirs).Count | Should -BeGreaterThan 0
    }
    It 'เขียนค่าที่ยังไม่ตรง บันทึกค่าเดิม และข้ามค่าที่ตั้งไว้แล้ว' {
        $p = Get-DrmOemProfile -System (New-FakeHw 'LENOVO' '21AH00BQUS' '' 'ThinkPad T14 Gen 3') -Catalog $script:Catalog
        Mock -ModuleName DriverRuntimeManager Get-DrmRegistryValue { if ($Name -eq 'DisplayLicenseNoticeSU') { 'NO' } else { 'YES' } }
        Mock -ModuleName DriverRuntimeManager Set-DrmRegistryValue { }
        $n = Set-DrmOemPreferences -Tool $p
        $expected = if ([Environment]::Is64BitOperatingSystem) { 2 } else { 1 }
        $n | Should -Be $expected
        Should -Invoke -ModuleName DriverRuntimeManager Set-DrmRegistryValue -Times $expected -Exactly -ParameterFilter { $Name -eq 'DisplayLicenseNotice' -and $Value -eq 'NO' -and $Type -eq 'String' }
        Should -Invoke -ModuleName DriverRuntimeManager Set-DrmRegistryValue -Times 0 -Exactly -ParameterFilter { $Name -eq 'DisplayLicenseNoticeSU' }
    }
}

Describe 'DRM-102: รีสตาร์ทแล้วทำต่อ (ไม่รีสตาร์ทจริง)' {
    It 'BIOS คืน 3010 → บันทึกงานที่เหลือ → ทำต่อด้วย -Resume → ลบไฟล์สถานะ' {
        $root = Join-Path $script:TestRoot 'resume'
        $s = Initialize-DrmSession -Root $root -NoBrowser
        $exe = (Get-Process -Id $PID).Path
        $codes = @(0, 3010, (Get-ExitAs 3010))
        $bios = [pscustomobject]@{ Id = 'file:bios'; Path = $exe; Name = 'BIOS_test.exe'; Kind = 'Exe'; Args = '-NoProfile -Command "exit 3010"'; SignatureValid = $true; OrderIndex = 10; OrderGroup = 'BIOS'; SuccessCodes = $codes; RebootCodes = @(3010, (Get-ExitAs 3010)); UpToDateCodes = @(); NotApplicableCodes = @() }
        $lan = [pscustomobject]@{ Id = 'file:lan'; Path = $exe; Name = 'LAN_test.exe'; Kind = 'Exe'; Args = '-NoProfile -Command "exit 0"'; SignatureValid = $true; OrderIndex = 60; OrderGroup = 'Network'; SuccessCodes = $codes; RebootCodes = @(3010); UpToDateCodes = @(); NotApplicableCodes = @() }
        $plan = @(New-DrmPlan -Items @((New-DrmPlanItemFromLocal -Info $lan), (New-DrmPlanItemFromLocal -Info $bios)))
        $plan[0].Id | Should -Be 'file:bios'
        $opt = [pscustomobject]@{ CreateRestorePoint = $false; ResumeAfterReboot = $true; RestartAfterCheckpoint = $false; Cleanup = $false }
        $sum = Invoke-DrmInstallPlan -Plan $plan -Options $opt -Catalog $script:Catalog
        $sum.Resume | Should -BeTrue
        $sum.Remaining | Should -Be 1
        $state = Read-DrmResumeState -Root $root
        $state | Should -Not -BeNullOrEmpty
        [int]$state.Attempt | Should -Be 1
        @($state.Items).Count | Should -Be 1
        @($state.Items)[0].Id | Should -Be 'file:lan'
        [IO.File]::ReadAllText($s.LogFile) | Should -Match 'RestartAfterCheckpoint'

        $sum2 = Invoke-DrmInstallPlan -Plan @($state.Items) -Options $state.Options -Catalog $script:Catalog -ResumeAttempt ([int]$state.Attempt)
        $sum2.Resume | Should -BeFalse
        @($sum2.Results).Count | Should -Be 1
        @($sum2.Results)[0].Result.Status | Should -Be 'Installed'
        Read-DrmResumeState -Root $root | Should -BeNullOrEmpty
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser | Out-Null
    }
    It 'คำสั่งใน RunOnce สำหรับ .cmd และ .ps1 (ส่ง -Root ต่อเมื่อไม่ใช่ค่าเริ่มต้น)' {
        Get-DrmResumeCommand -LauncherPath 'C:\Tools\Driver Tools (1)\Start-DriverRuntimeManager.cmd' | Should -Be '"C:\Tools\Driver Tools (1)\Start-DriverRuntimeManager.cmd" -Resume'
        Get-DrmResumeCommand -LauncherPath 'C:\Tools\DriverRuntimeManager.ps1' -Root 'D:\DRM\' | Should -Be 'powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "C:\Tools\DriverRuntimeManager.ps1" -Resume -Root "D:\DRM"'
        Get-DrmResumeCommand -LauncherPath '' | Should -BeNullOrEmpty
    }
}

Describe 'DRM-103: จุดคืนค่าระบบบน Windows Server' {
    It 'ข้ามพร้อมบันทึกเหตุผลเมื่อเป็น Windows Server' {
        Mock -ModuleName DriverRuntimeManager Test-DrmIsServer { $true }
        New-DrmRestorePoint | Should -BeFalse
        [IO.File]::ReadAllText((Get-DrmSession).LogFile) | Should -Match 'Windows Server'
    }
}

Describe 'DRM-110/114/115/116: ปรับปรุงย่อย' {
    It 'แนะนำ Windows Terminal เฉพาะคอนโซลเก่าบน Windows' {
        Test-DrmLegacyConsole -Environment @{} -HostName 'ConsoleHost' -OnWindows $true -OutputRedirected $false | Should -BeTrue
        Test-DrmLegacyConsole -Environment @{ WT_SESSION = 'x' } -HostName 'ConsoleHost' -OnWindows $true -OutputRedirected $false | Should -BeFalse
        Test-DrmLegacyConsole -Environment @{} -HostName 'Visual Studio Code Host' -OnWindows $true -OutputRedirected $false | Should -BeFalse
        Test-DrmLegacyConsole -Environment @{} -HostName 'ConsoleHost' -OnWindows $false -OutputRedirected $false | Should -BeFalse
        Test-DrmLegacyConsole -Environment @{} -HostName 'ConsoleHost' -OnWindows $true -OutputRedirected $true | Should -BeFalse
    }
    It 'ซ่อนอัปเดต: UpdateID ผิดรูปแบบถูกปฏิเสธ และโหมดทดลองไม่แตะระบบ' {
        { Hide-DrmWindowsUpdateDriver -UpdateId "x'; drop" } | Should -Throw
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'hide') -DryRun -NoBrowser | Out-Null
        (Hide-DrmWindowsUpdateDriver -UpdateId '6a3f1c2e-0d4b-4e8a-9c1f-2b7d5e6f8a90').Status | Should -Be 'DryRun'
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser | Out-Null
    }
    It 'เวลาหมดของ EXE: InstallShield เงียบ 20 นาที อื่น ๆ 90 นาที ไม่มีตัวเลือก 120 นาที' {
        Get-DrmExeTimeout -Engine 'InstallShield' -Arguments '/s /v"/qn"' | Should -Be 20
        Get-DrmExeTimeout -Engine 'InnoSetup' -Arguments '/VERYSILENT' | Should -Be 90
        Get-DrmExeTimeout -Engine 'InstallShield' -Arguments '  ' | Should -Be 120
    }
    It 'ไฟล์บีบอัดแยกหลายส่วน: ติดตั้งจากส่วนแรกเท่านั้น' {
        Get-DrmInstallerKind 'D:\drv\lan.7z.001' | Should -Be 'Archive'
        Get-DrmInstallerKind 'D:\drv\lan.7z.002' | Should -Be 'Unknown'
        Get-DrmInstallerKind 'D:\drv\gpu.part1.rar' | Should -Be 'Archive'
        Get-DrmInstallerKind 'D:\drv\gpu.part01.rar' | Should -Be 'Archive'
        Get-DrmInstallerKind 'D:\drv\gpu.part2.rar' | Should -Be 'Unknown'
        Get-DrmInstallerKind 'D:\drv\old.z01' | Should -Be 'Unknown'
        Get-DrmInstallerKind 'D:\drv\driver.rar' | Should -Be 'Archive'
    }
    It '7-Zip ได้รหัสผ่านเสมอ (ไม่ค้างรอพิมพ์) และตรวจข้อความรหัสผ่านผิดได้' {
        Get-Drm7ZipArguments -Path 'a.7z' -Destination 'out' | Should -Match '-p"DRM-NO-PASSWORD"'
        Get-Drm7ZipArguments -Path 'a.7z' -Destination 'out' -Password 's3cret' | Should -Match '-p"s3cret"'
        { Get-Drm7ZipArguments -Path 'a.7z' -Destination 'out' -Password 'a"b' } | Should -Throw
        Test-DrmArchivePasswordError 'ERROR: Wrong password : driver.inf' | Should -BeTrue
        Test-DrmArchivePasswordError 'Everything is Ok' | Should -BeFalse
    }
    It 'รหัสผ่านไม่ถูกบันทึกลง log' {
        $s = Initialize-DrmSession -Root (Join-Path $script:TestRoot 'secret') -NoBrowser
        $exe = (Get-Process -Id $PID).Path
        [void](Invoke-DrmProcess -FilePath $exe -Arguments '-NoProfile -Command "exit 0 # -p TopSecret123"' -Capture -Secret 'TopSecret123' -TimeoutMinutes 2)
        $log = [IO.File]::ReadAllText($s.LogFile)
        $log | Should -Not -Match 'TopSecret123'
        $log | Should -Match '\*\*\*\*\*\*\*\*'
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser | Out-Null
    }
}

Describe 'DRM-127: ค้นหา Windows Update มีเวลาหมด และโหมดทดลองไม่ค้นหา' {
    BeforeAll {
        function New-FakeSearcher([bool]$AsyncWorks = $true, [bool]$Completes = $true) {
            $job = [pscustomobject]@{ IsCompleted = $Completes; Aborted = $false }
            $job | Add-Member -MemberType ScriptMethod -Name RequestAbort -Value { $this.Aborted = $true }
            $s = [pscustomobject]@{ Job = $job; AsyncWorks = $AsyncWorks; SyncCalls = 0 }
            $s | Add-Member -MemberType ScriptMethod -Name BeginSearch -Value { param($c, $cb, $st) if (-not $this.AsyncWorks) { throw 'E_INVALIDARG' }; $this.Job }
            $s | Add-Member -MemberType ScriptMethod -Name EndSearch -Value { param($j) 'async-result' }
            $s | Add-Member -MemberType ScriptMethod -Name Search -Value { param($c) $this.SyncCalls++; 'sync-result' }
            $s
        }
    }
    It 'ใช้ผลแบบ asynchronous เมื่อทำได้' {
        $s = New-FakeSearcher
        Invoke-DrmWuSearcher -Searcher $s -Criteria 'x' | Should -Be 'async-result'
        $s.SyncCalls | Should -Be 0
    }
    It 'BeginSearch ใช้ไม่ได้ → ค้นหาแบบรอจนจบ (พฤติกรรมเดิม)' {
        $s = New-FakeSearcher -AsyncWorks $false
        Invoke-DrmWuSearcher -Searcher $s -Criteria 'x' | Should -Be 'sync-result'
        $s.SyncCalls | Should -Be 1
    }
    It 'ค้างเกินเวลา → ยกเลิกงานและแจ้งข้อผิดพลาดที่อ่านเข้าใจได้' {
        $s = New-FakeSearcher -Completes $false
        { Invoke-DrmWuSearcher -Searcher $s -Criteria 'x' -TimeoutMinutes 0 } | Should -Throw -ExpectedMessage '*เกิน 0 นาที*'
        $s.Job.Aborted | Should -BeTrue
    }
    It 'แผนโหมดทดลองที่มีไดรเวอร์ Windows Update ไม่เรียกค้นหาใหม่' {
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'drywu') -DryRun -NoBrowser | Out-Null
        Mock -ModuleName DriverRuntimeManager Get-DrmWuSearch { throw 'ไม่ควรถูกเรียกในโหมดทดลอง' }
        $plan = @(New-DrmPlan -Items @(New-DrmPlanItemFromWindowsUpdate -Driver ([pscustomobject]@{ Id = 'wu:1'; UpdateId = '00000000-0000-0000-0000-000000000001'; Title = 'Intel - System - 10.1.19.6'; OrderIndex = 20 })))
        $sum = Invoke-DrmInstallPlan -Plan $plan -Options ([pscustomobject]@{ CreateRestorePoint = $false; Cleanup = $false }) -Catalog $script:Catalog
        @($sum.Results)[0].Result.Status | Should -Be 'DryRun'
        Should -Invoke -ModuleName DriverRuntimeManager Get-DrmWuSearch -Times 0 -Exactly
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser | Out-Null
    }
}

Describe 'DRM-120: รายงานเทียบไดรเวอร์ก่อน/หลังติดตั้ง' {
    BeforeAll {
        $script:Before = @(
            [pscustomobject]@{ DeviceId = 'PCI\A'; Name = 'Wi-Fi'; Class = 'Net'; DriverVersion = '22.1.0.1'; InfName = 'oem1.inf'; ProblemCode = 0; Present = $true }
            [pscustomobject]@{ DeviceId = 'PCI\B'; Name = 'Audio'; Class = 'MEDIA'; DriverVersion = ''; InfName = ''; ProblemCode = 28; Present = $true }
            [pscustomobject]@{ DeviceId = 'PCI\C'; Name = 'GPU'; Class = 'Display'; DriverVersion = '31.0.1'; InfName = 'oem3.inf'; ProblemCode = 0; Present = $true }
            [pscustomobject]@{ DeviceId = 'PCI\D'; Name = 'USB'; Class = 'USB'; DriverVersion = '10.0'; InfName = 'usb.inf'; ProblemCode = 0; Present = $true }
        )
        $script:After = @(
            [pscustomobject]@{ DeviceId = 'PCI\A'; Name = 'Wi-Fi'; Class = 'Net'; DriverVersion = '23.10.0.7'; InfName = 'oem9.inf'; ProblemCode = 0; Present = $true }
            [pscustomobject]@{ DeviceId = 'PCI\B'; Name = 'Audio'; Class = 'MEDIA'; DriverVersion = '6.0.1'; InfName = 'oem10.inf'; ProblemCode = 0; Present = $true }
            [pscustomobject]@{ DeviceId = 'PCI\C'; Name = 'GPU'; Class = 'Display'; DriverVersion = '31.0.1'; InfName = 'oem3.inf'; ProblemCode = 43; Present = $true }
            [pscustomobject]@{ DeviceId = 'PCI\D'; Name = 'USB'; Class = 'USB'; DriverVersion = '10.0'; InfName = 'usb.inf'; ProblemCode = 0; Present = $true }
            [pscustomobject]@{ DeviceId = 'PCI\E'; Name = 'Card reader'; Class = 'SD'; DriverVersion = '1.0'; InfName = 'oem11.inf'; ProblemCode = 0; Present = $true }
        )
    }
    It 'จำแนก อัปเดต / แก้ปัญหาแล้ว / เกิดปัญหา / ใหม่ และไม่แสดงตัวที่ไม่เปลี่ยน' {
        $c = @(Get-DrmDriverChanges -Before $script:Before -After $script:After)
        $c.Count | Should -Be 4
        ($c | Where-Object DeviceId -eq 'PCI\A').Change | Should -Be 'Updated'
        ($c | Where-Object DeviceId -eq 'PCI\B').Change | Should -Be 'UpdatedFixed'
        ($c | Where-Object DeviceId -eq 'PCI\C').Change | Should -Be 'Broken'
        ($c | Where-Object DeviceId -eq 'PCI\C').Level | Should -Be 'error'
        ($c | Where-Object DeviceId -eq 'PCI\E').Change | Should -Be 'New'
        @($c | Where-Object DeviceId -eq 'PCI\D').Count | Should -Be 0
    }
    It 'รายงาน HTML/JSON มีตารางการเปลี่ยนแปลง' {
        $r = New-DrmReport -Title 'ทดสอบ' -Devices $script:After -DevicesBefore $script:Before
        [IO.File]::ReadAllText($r.Html) | Should -Match 'ไดรเวอร์ที่เปลี่ยนแปลงหลังติดตั้ง \(4\)'
        @(([IO.File]::ReadAllText($r.Json) | ConvertFrom-Json).DriverChanges).Count | Should -Be 4
    }
}

Describe 'v1.2: Windows จริง' -Tag 'Windows' -Skip:(-not $script:OnWindows) {
    It 'DRM-106: สแกน Driver Store รอบสองใช้แคชใบรับรองและได้ผลเท่าเดิม' {
        $s = Initialize-DrmSession -Root (Join-Path $script:TestRoot 'certcache') -NoBrowser
        $a = @(Get-DrmDriverPackages)
        $b = @(Get-DrmDriverPackages)
        $b.Count | Should -Be $a.Count
        (($b | ForEach-Object { $_.CertLevel }) -join ',') | Should -Be (($a | ForEach-Object { $_.CertLevel }) -join ',')
        Test-Path -LiteralPath (Join-Path $s.Root 'cert-cache.json') | Should -Be ($a.Count -gt 0)
        if (@($a | Where-Object { $_.CatalogFile }).Count -gt 0) { [IO.File]::ReadAllText($s.LogFile) | Should -Match 'ใช้แคช [1-9]' }
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser | Out-Null
    }
    It 'DRM-102: ตั้งและลบ RunOnce ได้จริง (ต้องเป็น Administrator)' -Skip:(-not (Test-DrmIsAdmin)) {
        $root = Join-Path $script:TestRoot 'runonce'
        $s = Initialize-DrmSession -Root $root -NoBrowser
        $launcher = Join-Path $script:ScriptsDir 'Start-DriverRuntimeManager.cmd'
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
        [void](Save-DrmResumeState -Remaining @([pscustomobject]@{ Id = 'x'; Name = 'x' }) -Options @{} -Session $s -Attempt 1 -LauncherPath $launcher)
        $v = (Get-ItemProperty -LiteralPath $key -Name 'DriverRuntimeManagerResume').DriverRuntimeManagerResume
        $v | Should -Match 'Start-DriverRuntimeManager\.cmd" -Resume -Root "'
        Clear-DrmResumeState -Root $root
        (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).PSObject.Properties['DriverRuntimeManagerResume'] | Should -BeNullOrEmpty
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser | Out-Null
    }
    It 'DRM-119: ดาวน์โหลดรายการรุ่นที่ HPIA รองรับ ตรวจลายเซ็น HP แตกด้วย expand.exe และอ่าน System ID ได้' {
        $s = Initialize-DrmSession -Root (Join-Path $script:TestRoot 'hpia') -NoBrowser
        $ids = @(Get-DrmHpiaPlatformList)
        $log = [IO.File]::ReadAllText($s.LogFile)
        if ($ids.Count -eq 0) { throw ("ไม่ได้รายการ: " + (($log -split "`n" | Where-Object { $_ -match 'HP|platformList|ลายเซ็น' }) -join ' | ')) }
        $ids.Count | Should -BeGreaterThan 100
        @($ids | Where-Object { $_ -notmatch '^[0-9A-F]{4}$' }).Count | Should -BeLessThan ([Math]::Max(1, [int]($ids.Count / 20)))
        Test-Path -LiteralPath (Join-Path $s.Root 'hpia-platformList.xml') | Should -BeTrue
        Initialize-DrmSession -Root (Join-Path $script:TestRoot 'root') -NoBrowser | Out-Null
    }
    It 'DRM-103/109: ตรวจ Windows Server และ hive ของผู้ใช้ที่ล็อกอินได้' {
        $isServer = ([int](Get-CimInstance Win32_OperatingSystem).ProductType -ne 1)
        Test-DrmIsServer | Should -Be $isServer
        Get-DrmUserRegistryPath -SubKey 'Software\Microsoft\GameBar' | Should -Match '^(HKCU:|Registry::HKEY_USERS\\S-1-)'
    }
}

Describe 'v1.2: รุ่นและเอกสาร' {
    It 'รุ่นเป็น 1.2.0 และบันทึกข้อบกพร่องไม่มีรายการที่ "เปิด" โดยไม่มีเหตุผล' {
        Get-DrmVersion | Should -Be '1.2.0'
        $ki = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'references/known-issues.md'))
        $ki | Should -Match 'DRM-121'
        $ki | Should -Not -Match '\| เปิด \|'
    }
}
