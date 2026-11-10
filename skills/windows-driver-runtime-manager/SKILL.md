---
name: windows-driver-runtime-manager
description: ตรวจระบบและชุดไดรเวอร์ทั้งหมดของเครื่อง Windows ที่รันอยู่ ดาวน์โหลดและติดตั้งไดรเวอร์จากผู้ผลิตก่อน แล้วจึงไดรเวอร์ที่ Microsoft รับรอง (WHQL/Windows Update) เฉพาะรุ่นที่ใหม่กว่า ติดตั้งรันไทม์และโปรแกรมเสริมจาก Microsoft ตามลำดับที่ผู้ผลิตแนะนำ พร้อมหน้าต่าง GUI ติ๊กเลือก log ทำความสะอาด รีสตาร์ท และรายงานความเข้ากันได้. Use when the user wants to check, download, update or install Windows drivers, chipset/BIOS/GPU packages, Visual C++/.NET/DirectX/WebView2 runtimes, gaming or work add-ons, install driver files of any format (inf/exe/msi/msu/cab/msix/zip/iso), or verify WHQL/Microsoft certification on the current machine. Not for non-Windows systems or for building unrelated apps.
---

# Windows Driver & Runtime Manager

เครื่องมือ PowerShell + WPF ที่รันบนเครื่อง Windows เป้าหมายเอง (Windows 10/11, PowerShell 5.1 หรือ 7) ไม่ต้องติดตั้งอะไรเพิ่ม
ตอบผู้ใช้เป็นภาษาของผู้ใช้ (ค่าเริ่มต้นภาษาไทย) และรายงานผลจากการรันจริงเท่านั้น

`SKILL_DIR` คือโฟลเดอร์ที่มีไฟล์นี้ ส่วนประกอบ:

| ไฟล์ | หน้าที่ |
| --- | --- |
| `scripts/Start-DriverRuntimeManager.cmd` | ดับเบิลคลิกเปิด GUI ขอสิทธิ์ Administrator ให้อัตโนมัติ ส่งอาร์กิวเมนต์ต่อให้สคริปต์ได้ |
| `scripts/DriverRuntimeManager.ps1` | หน้าต่าง GUI และโหมดคำสั่ง `-Mode Gui|Scan|Install|SelfTest` |
| `scripts/DriverRuntimeManager.psm1` | แกนหลัก: ตรวจระบบ อุปกรณ์ ใบรับรอง OEM Windows Update รันไทม์ ไฟล์ทุกรูปแบบ แผน ทำความสะอาด รายงาน |
| `scripts/catalog.json` | ข้อมูลที่แก้ได้โดยไม่แตะโค้ด: รันไทม์ เครื่องมือ OEM วงจรชีวิต Windows กฎตัวติดตั้ง |
| `tests/DriverRuntimeManager.Tests.ps1` | ชุดทดสอบ Pester 5 (ตรรกะทุกแพลตฟอร์ม + ส่วน Windows จริง) |

อ่านเพิ่มตามงาน: ลำดับติดตั้งและเครื่องมือผู้ผลิต [references/install-order.md](references/install-order.md),
การรับรอง WHQL/ลายเซ็น [references/certification.md](references/certification.md),
ไฟล์ติดตั้งทุกรูปแบบ [references/file-formats.md](references/file-formats.md),
รูปแบบแคตตาล็อกและการพัฒนาต่อ [references/catalog-format.md](references/catalog-format.md)

## ขั้นตอนทำงาน

1. **ยืนยันเครื่องเป้าหมาย** ต้องรันบน Windows เครื่องที่จะติดตั้งจริงด้วยสิทธิ์ Administrator
   ถ้าเซสชันนี้ไม่ใช่ Windows ให้ส่งมอบสคริปต์พร้อมวิธีรัน และบอกชัดว่ายังไม่ได้ตรวจเครื่องผู้ใช้ ห้ามเดาฮาร์ดแวร์
2. **ตรวจระบบอย่างละเอียด** ใช้ GUI (`Start-DriverRuntimeManager.cmd`) หรือโหมดคำสั่ง
   `powershell -ExecutionPolicy Bypass -File scripts\DriverRuntimeManager.ps1 -Mode Scan -CheckUpdates`
   ผลที่ได้: OS/บิลด์/วงจรชีวิต, เครื่อง/BIOS/เมนบอร์ด, CPU/RAM/GPU/ดิสก์/เครือข่าย, Secure Boot/TPM/HVCI/Test Signing,
   อุปกรณ์ทุกตัวพร้อมไดรเวอร์ เวอร์ชัน วันที่ INF ผู้ลงนาม ระดับการรับรอง รหัสปัญหา และลำดับติดตั้ง, Driver Store,
   รันไทม์ที่มี/ขาด, เครื่องมือของผู้ผลิตเครื่องและชิ้นส่วน, รายงาน HTML/JSON
3. **เรียงรายการจากหลักฐาน** อ่านรายงานแล้วสรุปเป็นรายการ: อุปกรณ์ที่มีปัญหา/ไม่มีไดรเวอร์, ไดรเวอร์ที่ไม่ใช่ WHQL,
   อัปเดตจากผู้ผลิตเครื่อง, ไดรเวอร์ Windows Update ที่ "ใหม่กว่า" หรือ "ยังไม่มี", รันไทม์ที่ขาดสำหรับงานและเกม
4. **ลำดับแหล่งที่มา (ห้ามสลับ)** ผู้ผลิตเครื่อง (Dell Command | Update, Lenovo System Update, HP Image Assistant ฯลฯ) →
   ไฟล์จากเว็บทางการของผู้ผลิต/ผู้ผลิตชิ้นส่วน → ไดรเวอร์ที่ Microsoft รับรองจาก Windows Update เฉพาะที่ใหม่กว่าของที่ติดตั้งหลังขั้นผู้ผลิต
   → รันไทม์จาก Microsoft โดยตรง → โปรแกรมเสริม → ปรับแต่ง เครื่องมือค้นหา Windows Update ใหม่หลังขั้นผู้ผลิตเสมอ
5. **ลำดับไดรเวอร์ตามผู้ผลิตแนะนำ** BIOS/เฟิร์มแวร์ → ชิปเซ็ต/Serial IO → Management Engine → Storage → กราฟิก → เสียง → LAN/Wi-Fi →
   Bluetooth → USB/Thunderbolt → อินพุต → กล้อง/ไบโอเมตริก → อื่น ๆ หลัง BIOS/ชิปเซ็ตที่ต้องรีสตาร์ท เครื่องมือจะรีสตาร์ทแล้วทำต่ออัตโนมัติ
6. **ทดลองก่อนติดตั้งจริง** รัน `-Mode Install ... -DryRun` หรือติ๊ก "โหมดทดลอง" เพื่อดูลำดับและคำสั่งทั้งหมดใน log
   แล้วจึงติดตั้งจริง ตัวอย่าง: `-Mode Install -Preset gaming -IncludeOem -IncludeWindowsUpdateDrivers -Files "D:\Drivers\chipset.zip;D:\Drivers\lan.inf"`
7. **ทำความสะอาด รีสตาร์ท และรายงาน** ลบเฉพาะไฟล์ที่ถูกสร้างระหว่างรอบนี้ (งานดาวน์โหลด, C:\NVIDIA/C:\AMD/C:\SWSetup ที่เกิดใหม่, TEMP)
   ตัวเลือกเพิ่ม: แคช Windows Update, แพ็กเกจไดรเวอร์รุ่นเก่า (pnputil ไม่ใช้ /force), DISM component cleanup
   แสดง log และตารางความเข้ากันได้ทั้งหมด แล้วรีสตาร์ทเมื่อผู้ใช้เลือก
8. **ส่งมอบ** บอกตำแหน่ง log (`%ProgramData%\DriverRuntimeManager\Logs`) รายงาน (`...\Reports\*.html|json`) รายการที่สำเร็จ/ล้มเหลว/ต้องทำต่อเอง
   รหัส exit และสิ่งที่ยังต้องรีสตาร์ท ห้ามอ้างว่าติดตั้งสำเร็จถ้า log ไม่ยืนยัน

## กฎความปลอดภัยและแหล่งที่มา

- ดาวน์โหลดเฉพาะแหล่งทางการ: เครื่องมือของผู้ผลิตผ่าน winget (manifest มี hash), ลิงก์ถาวรของ Microsoft (aka.ms/vc14, go.microsoft.com, download.microsoft.com),
  .NET จาก release metadata ของ Microsoft ตรวจลายเซ็นผู้ลงนาม `Microsoft Corporation` ทุกไฟล์ก่อนรัน ไฟล์ที่ไม่ผ่านจะถูกลบทิ้ง
- ไม่ใช้โปรแกรม "driver updater/booster" ของบุคคลที่สาม ไม่ปิด Driver Signature Enforcement ไม่เปิด Test Signing ไม่ติดตั้งไฟล์ไม่มีลายเซ็นโดยอัตโนมัติ
- โน้ตบุ๊กที่ผู้ผลิตปรับแต่งไดรเวอร์ (กราฟิกสลับ, เสียง, ปุ่มฟังก์ชัน) ให้ใช้ของผู้ผลิตเครื่องก่อนไดรเวอร์ทั่วไปของผู้ผลิตชิ้นส่วน
- สร้างจุดคืนค่าระบบก่อนติดตั้ง (เลือกสำรองไดรเวอร์เดิมได้) ไม่บังคับปิดตัวติดตั้งกลางคัน ปุ่มหยุดจะหยุดหลังรายการปัจจุบันจบ
- รายการ Visual C++ 2005–2013 หมดการสนับสนุนจาก Microsoft แล้ว ติดตั้งเมื่อเกม/โปรแกรมรุ่นเก่าต้องใช้ (อยู่ในชุด "เล่นเกม")
- .NET รุ่นที่หมดการสนับสนุนจะไม่ถูกเลือกให้ เว้นแต่ติดตั้งอยู่แล้ว (จะอัปเดตเป็นแพตช์สุดท้าย)

## พัฒนาต่อและตรวจรับ

- เพิ่มรันไทม์/เครื่องมือ OEM/กฎตัวติดตั้งใน `catalog.json` ตาม [references/catalog-format.md](references/catalog-format.md) แล้วรัน `-Mode SelfTest`
- ข้อตกลงของโมดูล: ฟังก์ชันที่คืนรายการคืน "อาร์เรย์เสมอ" (`return , $list`) ให้เก็บใส่ตัวแปรก่อนส่งต่อ pipeline และห้ามครอบด้วย `@()`;
  โค้ดต้องรันบน PowerShell 5.1 (ไม่ใช้ `??`, `?:`, `-Parallel`); ไฟล์ .ps1/.psm1 บันทึกเป็น UTF-8 มี BOM; วันที่ใช้ InvariantCulture (เครื่องไทยใช้ปฏิทินพุทธ)
- ตรวจรับ: `Invoke-Pester tests` (ทุกแพลตฟอร์ม), `-Mode SelfTest` ด้วย `-STA` บน Windows, workflow `.github/workflows/driver-runtime-manager.yml`
  ทดสอบบน Windows จริงทั้ง PowerShell 5.1 และ 7 รวมการติดตั้งจริงจาก Microsoft ผล Linux ไม่ใช่หลักฐานว่าใช้ได้บน Windows
