# รายการทดสอบด้วยมือ (สิ่งที่ CI ทดสอบไม่ได้)

CI ทดสอบบน Windows Server VM ที่ไม่มีหน้าจอจริง ไม่มีเมาส์ และไม่ใช่เครื่องของ Dell/Lenovo/HP รายการด้านล่างต้องทดสอบด้วยมือ
บนเครื่องจริงหรือ VM Windows 11 ก่อนออกรุ่นที่แตะส่วนนั้น บันทึกผลในตาราง "รอยืนยันบนเครื่องจริง" ของ [known-issues.md](known-issues.md)
(ใส่วันที่ รุ่น Windows/PowerShell รุ่นของเครื่อง และแนบไฟล์ชุดดีบัก `-Mode Diagnose`)

เตรียม: VM Windows 11 (Hyper-V/VMware) สร้าง checkpoint ก่อนเริ่มทุกหัวข้อ เปิดโปรแกรมจาก `Start-DriverRuntimeManager.cmd`

## 1. หน้าต่างที่ DPI สูง (DRM-117)

| ขั้น | ผลที่ต้องได้ |
| --- | --- |
| Settings > Display > Scale = 100%, 150%, 200% (ออกจากระบบทุกครั้ง) แล้วเปิดโปรแกรม | ตัวอักษรไทยคมชัด ไม่ถูกตัด ปุ่มและหัวตารางไม่ซ้อนกัน |
| ย่อหน้าต่างให้เล็กสุด (1000×650) | ตารางมีแถบเลื่อน ปุ่มด้านล่างยังเห็นครบ |
| ย้ายหน้าต่างไปจอที่สองที่ DPI ต่างกัน | หน้าต่างปรับขนาดตาม ไม่เบลอ |

## 2. ลากวางและเมนูคลิกขวา (DRM-117)

| ขั้น | ผลที่ต้องได้ |
| --- | --- |
| ลากไฟล์ .inf, .exe, .zip และโฟลเดอร์จาก Explorer มาวางในแท็บ 4 | ทุกไฟล์ขึ้นในตาราง ชนิดและลายเซ็นถูกต้อง |
| ลาก `lan.7z.001` + `lan.7z.002` พร้อมกัน | ขึ้นเฉพาะ `.001` (DRM-116) |
| ไฟล์ zip ที่มีรหัสผ่าน: ไม่ใส่รหัส → ติดตั้ง | ล้มเหลวพร้อมข้อความให้ใส่รหัสผ่าน ไม่ค้าง |
| ใส่รหัสผ่านในช่องตัวเลือก → ติดตั้ง | แตกไฟล์และติดตั้งได้ ใน log เห็น `********` ไม่เห็นรหัสผ่าน |
| คลิกขวาที่อุปกรณ์ในแท็บ 1 → ค้นหาใน Microsoft Update Catalog / คัดลอก Hardware ID / รายละเอียด | เปิดเบราว์เซอร์ด้วยสิทธิ์ผู้ใช้ปกติ (DRM-111: Task Manager > Details > คอลัมน์ Elevated = No) |
| คลิกขวาที่ไดรเวอร์จาก Windows Update → ซ่อน (DRM-114) | รายการหายจากตาราง และไม่กลับมาเมื่อกดตรวจหาอัปเดตใหม่ |

## 3. รีสตาร์ทแล้วทำต่อ (DRM-102)

1. คัดลอก `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` ไปเป็น `C:\Test\BIOS_test.exe` (ชื่อขึ้นต้นด้วย BIOS = ลำดับ 10)
   เพิ่มไฟล์นี้ในแท็บ 4 แล้วแก้ช่องตัวเลือกเป็น `-NoProfile -Command "exit 3010"` (จำลองตัวติดตั้ง BIOS ที่ขอรีสตาร์ท) หรือใช้ตัวติดตั้ง BIOS จริงของผู้ผลิต
2. เพิ่มไฟล์ไดรเวอร์อื่นหรือเลือกรันไทม์อีก 1 รายการ แล้วกดติดตั้ง (ไม่เปิดโหมดทดลอง)
3. ต้องเห็น: กล่องข้อความ "รีสตาร์ทตามคำแนะนำผู้ผลิต", ไฟล์ `%ProgramData%\DriverRuntimeManager\resume.json`,
   ค่า `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce\DriverRuntimeManagerResume`
4. หลังรีสตาร์ทและล็อกอิน: UAC ถามสิทธิ์ → หน้าต่างเปิดเองและทำต่อเฉพาะรายการที่เหลือ → `resume.json` และค่า RunOnce ถูกลบ
5. ทำซ้ำโดยคัดลอกเฉพาะ `.ps1/.psm1/.json` (ไม่มี `.cmd`) → RunOnce ต้องเรียก `powershell.exe ... -File "...ps1" -Resume`

## 4. จุดคืนค่าระบบ (DRM-103)

| ขั้น | ผลที่ต้องได้ |
| --- | --- |
| Windows 10/11 ที่ปิด System Protection → ติดตั้ง 1 รายการ | log บอกว่าเปิด System Protection แล้วสร้างจุดคืนค่าได้ (`rstrui.exe` เห็นรายการ) |
| ติดตั้งซ้ำภายใน 24 ชั่วโมง | ยังสร้างได้ และค่า `SystemRestorePointCreationFrequency` กลับเป็นค่าเดิม |
| Windows Server | log บอกว่าข้ามเพราะ Windows Server ไม่มี System Restore |

## 5. เครื่องมือของผู้ผลิตเครื่อง (DRM-101, 104, 105, 119)

| เครื่อง | ทดสอบ | เก็บหลักฐาน |
| --- | --- | --- |
| Dell Latitude/OptiPlex/Precision | ตรวจหาอัปเดต → จำนวน/ชื่อรายการตรงกับหน้าต่าง Dell Command \| Update | `oem_*.xml` ในชุดดีบัก |
| Dell Inspiron/Vostro (ผู้ใช้ทั่วไป) | ถ้า DCU คืน 7 ต้องได้ "ทำต่อเอง" และเปิดหน้า Dell Support ไม่ใช่ "ล้มเหลว" | log บรรทัด `ไม่รองรับเครื่องรุ่นนี้` |
| Lenovo ThinkPad | ติดตั้งครั้งแรกต้องไม่มีหน้าต่างข้อตกลงค้าง (DisplayLicenseNotice = NO) บันทึก exit code ของ `tvsu.exe` | `oemlog_*` ในชุดดีบัก |
| HP EliteBook/ProBook | ใช้ HP Image Assistant และ System ID อยู่ในรายการของ HP (log: `อยู่ในรายการรุ่นที่ HP Image Assistant รองรับ`) | `oem_*.json` |
| HP Pavilion/Victus/HP Laptop | ใช้ HP Support Assistant | หน้าจอแท็บ 2 |

## 6. คอนโซลเก่าและภาษาไทย (DRM-110)

เปิด `cmd.exe` (ไม่ใช่ Windows Terminal) แล้วรัน `powershell -File scripts\DriverRuntimeManager.ps1 -Mode Scan -NoElevate`
ต้องเห็นบรรทัดภาษาอังกฤษ `Tip: Thai text may appear as boxes...` และใน Windows Terminal ต้องไม่เห็นบรรทัดนี้
