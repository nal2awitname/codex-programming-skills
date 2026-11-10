# การรับรองไดรเวอร์และการตรวจลายเซ็น

## ระดับการรับรองที่เครื่องมือแสดง

| ระดับ | ความหมาย | วิธีตรวจ |
| --- | --- | --- |
| WHQL | ผ่านการทดสอบ Windows HLK และ Microsoft ลงนาม catalog | EKU ของใบรับรองผู้ลงนาม catalog มี `1.3.6.1.4.1.311.10.3.5` (Windows Hardware Driver Verification) และไม่มี `.5.1` |
| Attested | Microsoft ลงนามแบบ attestation (ยังไม่ผ่าน HLK) | EKU มี `1.3.6.1.4.1.311.10.3.5.1` (Windows Hardware Driver Attested Verification) |
| Inbox | ไดรเวอร์ที่มากับ Windows | INF ไม่ใช่ `oem*.inf` หรือ EKU `1.3.6.1.4.1.311.10.3.6` (Windows System Component Verification) |
| Microsoft | Microsoft ลงนามแต่ไม่ใช่ EKU ของไดรเวอร์ | Subject มี `O=Microsoft Corporation` |
| Vendor | ผู้ผลิตลงนามเอง (ไม่ใช่ WHQL) | ใบรับรองของผู้ผลิต |
| Unsigned / Invalid | ไม่มีลายเซ็น หรือ HashMismatch/NotTrusted | `Get-AuthenticodeSignature` |

ที่มา: Microsoft Learn "Validate the Microsoft signature" — OID ของ Windows Hardware Driver Verification ลงท้าย 5 = ไม่ใช่ attestation,
ลงท้าย 1 = attestation (learn.microsoft.com/windows-hardware/drivers/dashboard/code-signing-validate)

## ขั้นตอนตรวจของเครื่องมือ

1. `Get-WindowsDriver -Online` รายการแพ็กเกจผู้ผลิตใน Driver Store (`oemN.inf` → `OriginalFileName` ใน FileRepository)
2. หาไฟล์ `.cat` ในโฟลเดอร์แพ็กเกจ แล้วอ่านใบรับรองผู้ลงนามด้วย `Get-AuthenticodeSignature`
   ถ้าไม่ได้ใบรับรองจะถอด PKCS#7 ด้วย `SignedCms` แล้วอ่าน EKU (`Get-DrmCertificateEku`, `Get-DrmCertLevelFromEku`)
3. จับคู่กับ `Win32_PnPSignedDriver.InfName` ของอุปกรณ์ ถ้าไม่มี catalog ใช้ชื่อผู้ลงนามแทน (`Get-DrmCertLevelFromSigner`)
4. รายงานนับ WHQL/Attestation/ผู้ผลิตลงนามเอง/ไม่มีลายเซ็น และแสดงชื่ออุปกรณ์ที่ไม่ใช่ WHQL

## ไฟล์ที่ดาวน์โหลด

- รันไทม์และเครื่องมือที่ดาวน์โหลดตรงต้องมีลายเซ็น `Valid` และ `O=Microsoft Corporation` (กำหนดอื่นได้ด้วย `signer` ในแคตตาล็อก) ไม่ผ่านจะลบทิ้งและลองวิธีถัดไป
- .NET ตรวจลายเซ็น Microsoft ของไฟล์จาก `builds.dotnet.microsoft.com` (เวอร์ชันล่าสุดจาก `releases-index.json`)
- แพ็กเกจ MSIX ที่ `Get-AuthenticodeSignature` อ่านไม่ได้ (`NotSupportedFileFormat`) ให้ Windows ตรวจตอน `Add-AppxPackage`
- winget ตรวจ SHA256 จาก manifest ที่ Microsoft ดูแลก่อนติดตั้ง

## ไฟล์ที่ผู้ใช้เพิ่มเอง

- INF ตรวจลายเซ็นของ catalog ที่ประกาศใน `CatalogFile[.NTamd64]`; EXE/MSI/MSU/CAB/MSIX/PS1/CMD ตรวจลายเซ็นไฟล์
- ไฟล์ที่ไม่มีลายเซ็นถูกต้องจะ "ไม่ถูกเลือก" และจะถูกข้ามตอนติดตั้ง เว้นแต่ผู้ใช้เปิด "อนุญาตไฟล์ที่ไม่มีลายเซ็น"
- Windows 64 บิตบังคับลายเซ็นไดรเวอร์โหมด kernel อยู่แล้ว เครื่องมือไม่ปิด Driver Signature Enforcement และเตือนเมื่อเปิด Test Signing

## ความเข้ากันได้ที่ตรวจหลังติดตั้ง (`Get-DrmCompatibilityChecks`)

รุ่น Windows ยังได้รับอัปเดต (ตาราง `windowsLifecycle`), สถาปัตยกรรม, Driver signature enforcement/Test Signing, Secure Boot,
Memory Integrity (ไดรเวอร์ที่ไม่รองรับ HVCI จะถูกบล็อกด้วยรหัส 48/52), พื้นที่ว่าง, งานรอรีสตาร์ท, นโยบายห้ามไดรเวอร์จาก Windows Update/WSUS,
winget, อุปกรณ์ที่มีปัญหา (ก่อน→หลัง), สัดส่วนการรับรอง, แพ็กเกจไดรเวอร์เก่า, รันไทม์ที่แนะนำครบหรือไม่ และผลของทุกรายการที่ติดตั้ง
