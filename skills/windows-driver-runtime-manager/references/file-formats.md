# ติดตั้งไฟล์ทุกรูปแบบ

`Get-DrmInstallerInfo` วิเคราะห์ไฟล์/โฟลเดอร์ แล้ว `Install-DrmLocalFile` ติดตั้งตามชนิด ทุกคำสั่งบันทึกลง log พร้อม exit code

| ชนิด | นามสกุล | วิธีติดตั้ง | ผลลัพธ์พิเศษ |
| --- | --- | --- | --- |
| Inf | `.inf` | `pnputil /add-driver "x.inf" /install` | 3010 = รีสตาร์ท, 259 = เพิ่มเข้า Driver Store แต่ไม่มีอุปกรณ์ตรง/มีที่ดีกว่า |
| InfFolder | โฟลเดอร์ที่มี `.inf` | `pnputil /add-driver "<dir>\*.inf" /subdirs /install` | เหมือน Inf |
| Exe | `.exe` | รันพร้อมตัวเลือกติดตั้งเงียบตามชนิดตัวติดตั้ง (แก้ได้ในช่อง "ตัวเลือก") | ไม่รู้จักชนิด → เปิดหน้าต่างผู้ผลิตให้กดเอง |
| Msi | `.msi` | `msiexec /i x.msi /qn /norestart /l*v log` | 1618 = มีการติดตั้งอื่นอยู่ รอ 60 วินาทีแล้วลองใหม่; 1638 = มีรุ่นอื่นอยู่แล้ว |
| Msp | `.msp` | `msiexec /p x.msp /qn /norestart` | |
| Msu | `.msu` | `wusa x.msu /quiet /norestart` | 0x240006 = ติดตั้งแล้ว, 0x80240017 = ไม่เข้ากับ Windows รุ่นนี้ |
| Cab | `.cab` | `expand -F:*` → ถ้ามี `.inf` ใช้ pnputil (ไดรเวอร์จาก Microsoft Update Catalog) ไม่งั้น `dism /Online /Add-Package` | |
| Appx | `.msix .msixbundle .appx .appxbundle .appinstaller` | `Add-AppxPackage -Path` / `-AppInstallerFile` (ผ่าน Windows PowerShell) | 0x80073D06 = มีรุ่นใหม่กว่าแล้ว |
| Archive | `.zip .7z .rar .tar .gz .tgz .xz .bz2` | แตกไฟล์ (zip ด้วย .NET, อื่น ๆ ด้วย 7-Zip หรือ `tar.exe` ของ Windows) แล้วติดตั้งตัวที่พบ | ซ้อนได้ 3 ชั้น |
| Image | `.iso .img .vhd .vhdx` | `Mount-DiskImage` → ติดตั้งตัวที่พบ → `Dismount-DiskImage` | |
| Script | `.bat .cmd` | `cmd /c` | ตรวจลายเซ็น |
| PowerShell | `.ps1` | `powershell -NoProfile -ExecutionPolicy Bypass -File` | ตรวจลายเซ็น |
| Registry | `.reg` | `reg import` | ไม่ถูกเลือกให้อัตโนมัติ |
| Provisioning | `.ppkg` | `Install-ProvisioningPackage -QuietInstall` | |

ลำดับค้นหาตัวติดตั้งในโฟลเดอร์ที่แตก/เมานต์ (`Resolve-DrmExtractedInstaller`): `setup.exe`/`install.exe`/`SetupChipset.exe` ในชั้นบนสุดหรือชั้นที่สอง
→ `.msi` → โฟลเดอร์ที่มี `.inf` → แพ็กเกจแอป/MSU/CAB/EXE/ไฟล์บีบอัดซ้อน

## ตัวเลือกติดตั้งเงียบตามชนิดตัวติดตั้ง EXE

ตรวจจาก version info และไบต์ 4 MB แรกของไฟล์ (`Get-DrmExeEngineFromText`)

| ตัวติดตั้ง | สัญลักษณ์ที่ตรวจ | ตัวเลือก |
| --- | --- | --- |
| Inno Setup | "Inno Setup" | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` |
| NSIS | "Nullsoft Install System" | `/S` |
| WiX Burn | section `.wixburn` | `/quiet /norestart` |
| InstallShield | "InstallShield" | `/s /v"/qn REBOOT=ReallySuppress"` (แบบ InstallScript อาจต้องใช้ไฟล์ตอบ setup.iss) |
| Advanced Installer | "Advanced Installer" | `/exenoui /qn /norestart` |
| 7-Zip / WinRAR SFX | ";!@Install@!UTF-8!" / "WinRAR SFX" | ไม่มี — แตกด้วย 7-Zip ได้ถ้าใส่เป็นไฟล์บีบอัด |
| ไม่รู้จัก | — | ไม่มี (เปิดหน้าต่างผู้ผลิต) |

กฎเฉพาะผู้ผลิต (`installerRules` ในแคตตาล็อก) มีผลก่อนการเดาชนิด:

| กฎ | เงื่อนไข | ตัวเลือก | รหัสพิเศษ |
| --- | --- | --- | --- |
| Dell Update Package | CompanyName "Dell" + ข้อความ Update Package/BIOS/Driver | `/s /l="{LogFile}"` | 2/6 รีสตาร์ท, 3 เป็นปัจจุบัน, 5 ไม่เข้ากับเครื่อง |
| HP SoftPaq | ชื่อ `sp12345.exe` | `/s` | |
| Intel Chipset Device Software | ชื่อ `SetupChipset*.exe` | `-s -norestart` | 14/3010 รีสตาร์ท |
| NVIDIA Install Application | ข้อความ "NVIDIA Install Application" | `-s -noreboot` | |

`{LogFile}` ในตัวเลือกจะถูกแทนด้วยไฟล์ log ในโฟลเดอร์ Logs ของเซสชัน

## ระยะเวลาและการหยุด

ตัวติดตั้ง EXE/สคริปต์หมดเวลา 90/60 นาที เมื่อหมดเวลาจะบันทึกเตือนและไปรายการถัดไปโดยไม่ฆ่าโปรเซส
ปุ่ม "หยุด" ตั้งสถานะยกเลิก รายการที่ยังไม่เริ่มจะเป็น "ยกเลิก" ส่วนตัวติดตั้งที่ทำงานอยู่จะปล่อยให้จบเพื่อไม่ให้ระบบเสียหาย
