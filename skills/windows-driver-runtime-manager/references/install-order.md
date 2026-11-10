# ลำดับการติดตั้งและเครื่องมือของผู้ผลิต

## แหล่งที่มาเรียงตามความสำคัญ (ตามที่ผู้ใช้กำหนด)

| ขั้น | แหล่ง | เหตุผล |
| --- | --- | --- |
| 0 เตรียมระบบ | App Installer (winget) | ใช้ติดตั้งเครื่องมือผู้ผลิตและรันไทม์ที่ไม่มีลิงก์ตรง |
| 1 ผู้ผลิตเครื่อง (OEM) | Dell Command \| Update, Lenovo System Update, HP Image Assistant ฯลฯ | ไดรเวอร์ที่ผู้ผลิตเครื่องทดสอบกับรุ่นนั้น ครอบคลุม BIOS/EC/เฟิร์มแวร์ และติดตั้งตามลำดับของผู้ผลิตเอง |
| 2 ผู้ผลิตชิ้นส่วน | Intel DSA, NVIDIA App, AMD Auto-Detect | สำหรับเครื่องประกอบเอง/เมนบอร์ด หรือเมื่อ OEM ไม่มีรุ่นใหม่ |
| 3 ไฟล์จากเว็บผู้ผลิต | ไฟล์ที่ผู้ใช้ดาวน์โหลดเอง (แท็บติดตั้งจากไฟล์) | เรียงตามคลาสไดรเวอร์ด้านล่าง |
| 4 Windows Update | ไดรเวอร์ที่ Microsoft ลงนาม/รับรอง | ค้นใหม่หลังขั้น 1–3 และเลือกเฉพาะ "ใหม่กว่า" หรือ "ยังไม่มีไดรเวอร์" |
| 5–7 | รันไทม์ → โปรแกรมเสริม → ปรับแต่ง | ไม่ขึ้นกับไดรเวอร์ |

การเทียบ "ใหม่กว่า" ใช้วิธีเดียวกับการจัดอันดับของ PnP: ดูวันที่ DriverVer ก่อน ถ้าวันเท่ากันจึงเทียบเวอร์ชัน
(`Compare-DrmDriverOffer`). Windows Update เสนอเฉพาะไดรเวอร์ที่จัดอันดับดีกว่าอยู่แล้ว แต่เราแสดงผลเทียบให้ผู้ใช้เห็นและไม่เลือกรายการที่เก่ากว่า/เท่ากัน

## ลำดับไดรเวอร์ (OrderIndex)

อ้างอิงแนวทาง Dell "How to Install Dell Drivers in the Correct Order" (KB 000132394) และหน้า Driver Install Order ของแต่ละรุ่น:
BIOS และชิปเซ็ตก่อน รีสตาร์ท แล้วจึงติดตั้งส่วนที่เหลือ

| Index | กลุ่ม | ตัวอย่างคลาส/ชื่อ |
| --- | --- | --- |
| 10 | BIOS / เฟิร์มแวร์ | `Firmware`, BIOS, UEFI, Embedded Controller |
| 20 | ชิปเซ็ต / แพลตฟอร์ม | Chipset, Serial IO, GPIO, I2C, SMBus, DPTF/Dynamic Tuning, ISH, NPU |
| 25 | Management Engine / ความปลอดภัย | Intel ME/MEI/CSME, AMD PSP, TPM |
| 30 | Storage | `HDC`, `SCSIAdapter`, RST/VMD, NVMe, SATA |
| 40 | กราฟิก | `Display` |
| 50 | เสียง | `MEDIA`, `AudioEndpoint`, `AudioProcessingObject`, Smart Sound |
| 60 | เครือข่าย | `Net` (LAN, Wi-Fi, Killer) |
| 65 | Bluetooth | `Bluetooth` |
| 70 | USB / Thunderbolt | `USB`, Thunderbolt, USB4 |
| 80 | อินพุต | `HIDClass`, `Keyboard`, `Mouse`, Touchpad |
| 85 | กล้อง / ไบโอเมตริก | `Camera`, `Image`, `Biometric` |
| 88 | การ์ดรีดเดอร์ | `SDHost`, `SmartCardReader` |
| 90 | อื่น ๆ | ที่เหลือทั้งหมด |

การจับคู่ใช้ชื่อก่อน (เฉพาะเมื่อคลาสตรงหรือเป็นคลาสกลาง เช่น System/Extension/SoftwareComponent) แล้วจึงใช้คลาส —
`Get-DrmDriverOrder`. ไฟล์ .exe ใช้ชื่อไฟล์และ version info (FileDescription/ProductName) ในการจัดกลุ่ม

### จุดรีสตาร์ทและทำงานต่อ

ถ้ารายการ "ฐานระบบ" (ขั้น OEM หรือไฟล์ที่ Index ≤ 25) คืนสถานะต้องรีสตาร์ท ก่อนเริ่มรายการถัดไปที่ไม่ใช่ฐานระบบ
เครื่องมือจะบันทึกงานที่เหลือใน `%ProgramData%\DriverRuntimeManager\resume.json` ตั้ง `HKLM\...\RunOnce\DriverRuntimeManagerResume`
แล้วรีสตาร์ทใน 60 วินาที (ยกเลิกได้ด้วย `shutdown /a`) หลังล็อกอินโปรแกรมจะเปิดด้วย `-Resume` และทำต่อ (สูงสุด 3 รอบ)
ปิดได้ด้วยตัวเลือก "รีสตาร์ทหลัง BIOS/ชิปเซ็ตแล้วทำต่ออัตโนมัติ"

## เครื่องมือของผู้ผลิตเครื่อง (catalog `oemTools`)

ระบุผู้ผลิตจาก `Win32_ComputerSystem.Manufacturer` (ถ้าเป็นค่าว่าง/"System manufacturer"/"To Be Filled By O.E.M." ใช้ผู้ผลิตเมนบอร์ดแทน)
และรุ่นจาก Model + `Win32_ComputerSystemProduct.Version` (Lenovo เก็บชื่อรุ่นจริงไว้ที่นี่) รายการแรกที่ตรงเงื่อนไขจะถูกใช้

| ผู้ผลิต | เครื่องมือ (winget id) | ทำงานอัตโนมัติ | คำสั่งที่ใช้ |
| --- | --- | --- | --- |
| Dell (ยกเว้น Alienware) | Dell Command \| Update (`Dell.CommandUpdate`) | ใช่ | สแกน `dcu-cli /scan -silent -report=<dir>`; ติดตั้ง `/applyUpdates -silent -reboot=disable -autoSuspendBitLocker=enable -outputLog=<log>`; exit 0 สำเร็จ, 1/5 ต้องรีสตาร์ท, 500 ไม่มีอัปเดต |
| Lenovo ThinkPad/ThinkCentre/ThinkStation | Lenovo System Update (`Lenovo.SystemUpdate`) | ใช่ | `tvsu.exe /CM -search A -action INSTALL -noicon -includerebootpackages 1,3,4 -noreboot` แล้วรอโปรเซส Tvsukernel จบ |
| HP เชิงธุรกิจ | HP Image Assistant (`HP.ImageAssistant`) | ใช่ | `/Operation:Analyze /Category:BIOS,Drivers,Firmware /Selection:All /Action:List|Install /Silent ...`; 256 ไม่มีอัปเดต, 257/3010/3020 ต้องรีสตาร์ท |
| HP ผู้ใช้ทั่วไป | HP Support Assistant (`HP.SupportAssistant`) | ไม่ (ต้องกดในหน้าต่าง HP) | ติดตั้งแล้วเปิดโปรแกรม |
| Lenovo IdeaPad/Legion/Yoga/ThinkBook | Lenovo Vantage | ไม่ | เปิดหน้า pcsupport.lenovo.com |
| Surface | Windows Update | — | ใช้รายการ Windows Update |
| ASUS ROG/TUF, ASUS อื่น, MSI, Acer, Gigabyte, ASRock, Samsung, Razer, Dynabook | Armoury Crate / MSI Center / หน้า Support | ไม่ | ติดตั้งเครื่องมือ (ถ้ามี winget id) และเปิดหน้าดาวน์โหลดทางการ |

ผลสแกนของ Dell อ่านจาก XML (`//update` → name, version, category, type) และ HP อ่านจาก JSON (`HPIA.Recommendations`).
รหัส exit ของผู้ผลิตมาจากเอกสาร/ชุมชนของผู้ผลิต — ถ้ารุ่นเครื่องมือเปลี่ยน ให้ตรวจ log ของผู้ผลิตใน `%ProgramData%\DriverRuntimeManager\Logs\OEM_*.log`

## ผู้ผลิตชิ้นส่วน (catalog `componentVendors`)

ตรวจจาก Vendor ID ใน Hardware ID (`VEN_xxxx`/`VID_xxxx`): Intel 8086/8087 → Intel Driver & Support Assistant,
NVIDIA 10DE (เฉพาะ Display) → NVIDIA App, AMD 1002/1022 → AMD Auto-Detect เลือกให้อัตโนมัติเฉพาะเมื่อเป็นเครื่องประกอบเอง
(ไม่มีเครื่องมือ OEM) และมี winget id เพราะโน้ตบุ๊กควรใช้ไดรเวอร์ที่ OEM ปรับแต่งก่อน
