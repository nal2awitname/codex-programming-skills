# รูปแบบแคตตาล็อกและแนวทางพัฒนาต่อ

`scripts/catalog.json` (UTF-8, LF) เป็นข้อมูลทั้งหมดที่เปลี่ยนตามเวลา แก้แล้วรัน
`powershell -File scripts\DriverRuntimeManager.ps1 -Mode SelfTest` และ `Invoke-Pester tests` ทุกครั้ง

## รายการรันไทม์/โปรแกรม (`items`)

```json
{
  "id": "vc14-x64",
  "name": "Visual C++ v14 Redistributable 2015–2026 (x64) รุ่นล่าสุด",
  "group": "Visual C++ Runtime",
  "category": "runtime",
  "order": 151,
  "arch": ["x64", "arm64"],
  "presets": ["recommended", "gaming", "work"],
  "publisher": "Microsoft",
  "latestVersion": "",
  "skipIfInstalled": false,
  "condition": "desktop",
  "detect": [ { "type": "registry", "path": "HKLM:\\...\\Runtimes\\x64", "value": "Version" } ],
  "install": [
    { "type": "direct", "url": "https://aka.ms/vc14/vc_redist.x64.exe", "args": "/install /quiet /norestart" },
    { "type": "winget", "id": "Microsoft.VCRedist.2015+.x64" }
  ],
  "successCodes": [0, 3010, 1641, 1638],
  "note": "ข้อความในคอลัมน์หมายเหตุ"
}
```

| ฟิลด์ | ความหมาย |
| --- | --- |
| `category` | `prereq` (ขั้น 0), `runtime` (5), `tool` (6), `tweak` (7) |
| `arch` | สถาปัตยกรรมเครื่องที่แสดงรายการนี้ (ไม่ระบุ = ทุกแบบ) โปรแกรม x86 ใช้ได้ทุกเครื่อง |
| `presets` | ปุ่มชุด `recommended`, `gaming`, `work` (ปุ่ม "ทั้งหมด" เลือกทุกรายการ) |
| `latestVersion` | รุ่นสุดท้ายที่ทราบ ถ้าติดตั้งรุ่นนี้หรือใหม่กว่าแล้วจะไม่ดาวน์โหลด |
| `skipIfInstalled` | ถ้าตรวจพบแล้วไม่ต้องติดตั้งซ้ำ (ใช้กับของที่อัปเดตตัวเอง/ไม่มีรุ่นใหม่) |
| `condition` | `desktop` = ไม่เลือกให้อัตโนมัติบนโน้ตบุ๊ก |

### วิธีตรวจ (`detect`, ลองตามลำดับ)

`registry` (path, value; ค่า `Installed=0` ถือว่าไม่มี), `uninstall` (regex ของ DisplayName ใน Uninstall ทั้ง 64/32 บิตและ HKCU),
`file` (path + `alsoRequire`), `feature` (ฟีเจอร์ Windows), `appx` (ชื่อแพ็กเกจ), `netfx` (`minRelease`), `command`,
`setting` (`GameMode`/`HAGS`/`PowerPlan`), `wingetPackage` (โฟลเดอร์แพ็กเกจ portable ของ winget)

### วิธีติดตั้ง (`install`, ลองตามลำดับจนสำเร็จ)

| type | ฟิลด์ | หมายเหตุ |
| --- | --- | --- |
| `direct` | `url` (https เท่านั้น), `args`, `fileName`, `signer`, `compareVersion`, `kind: appx` | รันไทม์/prereq ต้องอยู่ใน `trustedRuntimeHosts`; ดาวน์โหลด → ตรวจลายเซ็น → เทียบ FileVersion กับที่ติดตั้ง → ติดตั้งเมื่อใหม่กว่า |
| `winget` | `id`, `architecture` | ติดตั้งแล้วจะใช้ `upgrade --include-unknown`; 0x8A15002B/0x8A150061/0x8A15010D = เป็นปัจจุบัน |
| `dotnet` | สร้างอัตโนมัติจาก `dynamic: dotnet` | อ่าน `releases-index.json` ทุกครั้ง: ช่อง active/maintenance เลือกให้ ช่อง EOL สองช่องล่าสุดแสดงเป็นทางเลือก |
| `feature` | `name` | `dism /Online /Enable-Feature /All /NoRestart` |
| `builtin` | `action`: `RepairWinget`, `GameMode`, `HAGS`, `PowerPlan` | บันทึกค่าเดิมลง log เพื่อคืนค่าได้ |
| `url` | `url` | เปิดหน้าเว็บให้ผู้ใช้ทำต่อ |

## ส่วนอื่นของแคตตาล็อก

- `oemTools`: `vendor`, `match` (regex ผู้ผลิต), `modelMatch`/`modelExclude`, `name`, `winget`, `automated`, `exe[]`, `exeName`, `launch[]`,
  `scanArgs`, `applyArgs` (แทน `{ReportDir}` `{LogFile}` `{DownloadDir}`), `report` (`dell`/`hpia`), `waitProcess[]`, `successCodes`, `rebootCodes`, `noUpdateCodes`, `supportUrl`, `note`
  เรียงรายการเฉพาะเจาะจงไว้ก่อนรายการทั่วไปของผู้ผลิตเดียวกัน
- `componentVendors`: `vendor`, `ids[]` (PCI/USB vendor id), `classMatch`, `name`, `winget`, `url`, `note`
- `installerRules`: `name`, `fileName` (regex), `company`, `text` (regex ใน version info), `args`, `successCodes`, `rebootCodes`, `upToDateCodes`, `notApplicableCodes`
- `windowsLifecycle`: `build`, `homePro`, `enterprise`, `ltsc` (วันที่ ISO) จาก learn.microsoft.com/windows/release-health — อัปเดตเมื่อมี Windows รุ่นใหม่
- `vendorIds`: แผนที่ Vendor ID → ชื่อผู้ผลิตที่แสดงในตาราง
- `dotnet`: URL ของ release index, แม่แบบ URL ดาวน์โหลด, ช่องสำรองเมื่อออฟไลน์

## ฐานข้อมูลรหัสข้อผิดพลาด (`scripts/errors.json`)

```json
{ "code": "0x800F081F", "sources": ["dism"], "title": "ความหมายสั้น ๆ", "fix": "วิธีแก้ที่ทำได้จริง" }
```

| ฟิลด์ | ความหมาย |
| --- | --- |
| `code` | เลขฐานสิบ (`1603`) หรือฐานสิบหก (`0x80240017`) — ค่าติดลบแบบ HRESULT แปลงให้อัตโนมัติ |
| `sources` | บริบทที่ความหมายนี้ใช้: `msi`, `installer`, `wusa`, `windowsupdate`, `pnputil`, `winget`, `dism`, `appx`, `dcu`, `hpia`, `oem` — เว้นว่าง = ใช้ได้ทุกแหล่ง |
| `title` / `fix` | ข้อความภาษาไทยที่แสดงใน log หน้าต่าง และรายงาน |

`sourceHints` คือคำแนะนำทั่วไปต่อแหล่ง (เช่นให้เปิด `*.msi.log`) และ `deviceProblems` คือวิธีแก้ตามรหัสปัญหาของ Device Manager
รหัสที่ไม่มีในไฟล์: ถ้าเป็น Win32/`0x8007xxxx` จะใช้ข้อความระบบของ Windows ส่วน winget จะแนะนำ `winget error <รหัส>`
ฟังก์ชัน: `Get-DrmErrorInfo -Code -Source -Text`, `Get-DrmErrorSource -Method -Vendor`, `Get-DrmDeviceAdvice`
เพิ่มรหัสแล้วรัน Pester (ตรวจว่าทุกรหัสแปลงได้ มีข้อความ และไม่ซ้ำในบริบทเดียวกัน)

## ไฟล์ชุดที่เลือก (`-SelectionProfile` / `-ExportProfile` / ปุ่มในหน้าต่าง)

```json
{ "schemaVersion": 1, "runtimes": ["vc14-x64"], "includeOem": true, "includeWindowsUpdateDrivers": true,
  "vendorTools": ["Intel"], "files": [{ "path": "D:\\drv\\lan.zip", "args": "" }], "options": { "Reboot": false } }
```

รายการที่ไม่มีบนเครื่องปลายทาง (สถาปัตยกรรมต่าง/ไฟล์ไม่อยู่) จะถูกข้ามพร้อมบันทึกเตือน — `New-DrmSelectionProfile`, `Save-DrmSelectionProfile`, `Read-DrmSelectionProfile`

## ข้อตกลงของโค้ด

- โมดูลส่งออกทุกฟังก์ชันชื่อ `*-Drm*` GUI และโหมดคำสั่งเรียกฟังก์ชันชุดเดียวกัน
- ฟังก์ชันที่คืนรายการใช้ `return , $array` จึงได้อาร์เรย์เสมอ (แม้ว่าง/มีตัวเดียว): เก็บใส่ตัวแปรก่อน `| Where-Object` และอย่าครอบด้วย `@()`
- ต้องรองรับ Windows PowerShell 5.1: ไม่ใช้ `??`, `?.`, ternary, `ForEach-Object -Parallel`, `Join-Path` แบบสามอาร์กิวเมนต์; ระวังตัวแปรอัตโนมัติ (`$args`, `$input`, `$PROFILE`)
- ไฟล์ .ps1/.psm1 เป็น UTF-8 มี BOM (ข้อความไทย), .cmd เป็น ASCII + CRLF; วันที่จัดรูปแบบด้วย InvariantCulture
- GUI ทำงานหนักใน runspace แยก ส่งข้อความผ่าน `ConcurrentQueue` (`Log`, `Progress`, `Download`, `ItemStatus`, `ScanResult`, `UpdateResult`, `FileInfo`, `InstallResult`, `InstallCheckpoint`) และ DispatcherTimer อัปเดตหน้าจอทุก 150 ms
- โหมดทดลอง (`-DryRun`) ต้องไม่เปลี่ยนแปลงระบบ: ทุกคำสั่งผ่าน `Invoke-DrmProcess` ซึ่งจะบันทึกแทนการรัน
- เปิดหน้าเว็บ/โปรแกรมของผู้ผลิตผ่าน `Open-DrmTarget` เท่านั้น (ข้ามในโหมดทดลองและ `-NoBrowser` ของโหมดคำสั่ง)
- คำสั่ง `-Capture` ที่ล้มเหลวเก็บผลลัพธ์เต็มที่ `Logs\Output_*.txt` (คืนใน `OutputFile`) และ `Invoke-DrmInstallPlan` เติม `Advice` ให้รายการที่ล้มเหลว/ไม่เข้ากัน/ข้าม
- GUI ส่งข้อความเพิ่ม `DiagResult` และใช้ runspace แยก 3 ช่อง: `main` (สแกน/ติดตั้ง), `files` (วิเคราะห์ไฟล์), `diag` (ชุดดีบัก)
- เปิดได้ทีละหน้าต่าง/การติดตั้ง (mutex `Global\DriverRuntimeManager.Instance`) — exit code 3 เมื่อมีตัวอื่นทำงานอยู่

## ทดสอบ

- `Invoke-Pester tests` — ตรรกะ (เวอร์ชัน ลำดับ OEM วงจรชีวิต EKU ชนิดไฟล์ INF แคตตาล็อก รายงาน และรันแผนทั้งหมดแบบทดลอง)
- `-Mode SelfTest` (ต้อง `-STA`) — โหลด XAML และตัวควบคุมครบ
- `-Mode Gui -SmokeTestSeconds 900 -SmokeTestReport x.json` — เปิดหน้าต่างจริง สแกนและตรวจอัปเดตผ่าน runspace เลือกชุดเล่นเกม
  เปลี่ยนตัวกรอง แล้วติดตั้งแบบทดลองจากหน้าต่าง บันทึกผล (จำนวนแถวในแต่ละตาราง แผน ผลลัพธ์ ข้อผิดพลาด) แล้วปิดเอง
- CI `.github/workflows/driver-runtime-manager.yml` — Pester บน Linux + Windows (5.1 และ 7), ตรวจลิงก์ดาวน์โหลดทางการทุกลิงก์,
  สแกนจริงพร้อมค้นหา Windows Update, ทดลองติดตั้งทุกรายการ, และติดตั้งจริงบางรายการจาก Microsoft แล้วตรวจซ้ำว่าตรวจพบ
