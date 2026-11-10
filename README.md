# สกิลตรวจโค้ดและพัฒนาโปรแกรม

ชุด Agent Skills สำหรับ Codex ของ [nal2awitname](https://github.com/nal2awitname) เก็บขั้นตอนตรวจโค้ด สร้างโปรแกรม และแก้บั๊กที่นำกลับมาใช้ได้ในหลายโครงการ

| สกิล | ความสามารถ | ตัวอย่างเรียก |
| --- | --- | --- |
| [code-review](skills/code-review/SKILL.md) | ตรวจบั๊กและ regression พร้อมหลักฐานและตำแหน่งโค้ด | `ใช้ $code-review ตรวจ branch นี้เทียบกับ main` |
| [app-builder](skills/app-builder/SKILL.md) | สร้างโปรแกรมหรือเพิ่มฟีเจอร์ให้รันและตรวจรับได้ | `ใช้ $app-builder สร้าง Python CLI รวมไฟล์ CSV` |
| [debug-and-fix](skills/debug-and-fix/SKILL.md) | ทำซ้ำอาการ หาสาเหตุ แก้ไข และตรวจผล | `ใช้ $debug-and-fix แก้ error นี้พร้อม regression test` |
| [windows-simulator](skills/windows-simulator/SKILL.md) | เลือกและตั้งระบบจำลอง/ทดสอบ Windows พร้อมเทียบตัวเลือก | `ใช้ $windows-simulator ตั้งระบบทดสอบสคริปต์ PowerShell บน Windows` |
| [analyze-and-rebuild](skills/analyze-and-rebuild/SKILL.md) | วิเคราะห์ภาษาและโครงสร้าง สร้างใหม่โดยไม่คัดลอก พร้อมจัดส่วนประกอบส่ง GitHub | `ใช้ $analyze-and-rebuild วิเคราะห์และสร้างโปรแกรมนี้ใหม่` |
| [windows-driver-runtime-manager](skills/windows-driver-runtime-manager/SKILL.md) | หน้าต่าง GUI ตรวจระบบและไดรเวอร์ทั้งหมด อัปเดตจากผู้ผลิตก่อนแล้วจึง WHQL ที่ใหม่กว่า ติดตั้งรันไทม์/ไฟล์ทุกรูปแบบ พร้อม log และรายงาน | `ใช้ $windows-driver-runtime-manager ตรวจและอัปเดตไดรเวอร์กับรันไทม์ของเครื่องนี้` |

## ติดตั้ง

ส่งคำขอนี้ใน Codex:

```text
ใช้ $skill-installer ติดตั้งสกิลจาก repository nal2awitname/codex-programming-skills
ที่ paths skills/code-review, skills/app-builder และ skills/debug-and-fix
```

เริ่ม Codex ใหม่หลังติดตั้ง หากใช้เฉพาะโครงการ ให้คัดลอกโฟลเดอร์สกิลไปไว้ใน `.agents/skills/` ของโครงการนั้น ดูขั้นตอนและตัวอย่างเพิ่มเติมใน [คู่มือภาษาไทย](SKILLS_GUIDE_TH.md)

สกิลทำงานร่วมกับ runtime และเครื่องมือที่แชตเข้าถึงได้ การใช้ GitHub หรือรันทดสอบต้องอาศัยการเชื่อมต่อและสิทธิ์ที่มีอยู่ สกิลนี้ไม่ได้ตั้ง automation ให้ทำงานเอง

## วิเคราะห์โปรแกรมและสร้างใหม่

**รุ่น 2.0 มีเครื่องมือ Python/PowerShell ที่รันได้จริง:** [เริ่มใช้และพัฒนาต่อ](docs/analyze-and-rebuild/V2_TH.md)

สกิล `analyze-and-rebuild` แยกรายงานวิเคราะห์ต้นฉบับออกจากข้อกำหนดที่ใช้เขียนใหม่ กำหนดห้ามคัดลอกหรือแปลโค้ดทีละบรรทัด และเตรียมซอร์สใหม่ เอกสาร และชุดทดสอบให้พัฒนาต่อได้

- [คู่มือใช้งานและส่วนประกอบ](docs/analyze-and-rebuild/README_TH.md)
- [แนวทางพัฒนาสกิลต่อ](docs/analyze-and-rebuild/DEVELOPMENT.md)
- [แม่แบบข้อกำหนดพฤติกรรม](templates/analyze-and-rebuild/behavior-contract.md)
- [แม่แบบแผนผังส่วนประกอบ](templates/analyze-and-rebuild/components.md)
- [แม่แบบบันทึกการสร้างใหม่](templates/analyze-and-rebuild/reconstruction-record.md)

สารบัญสกิลแยกตามหมวดพร้อมคำอธิบายอยู่ที่ [skill for creating code](skill%20for%20creating%20code/README.md)

## ตัวจัดการไดรเวอร์และรันไทม์ Windows

ดับเบิลคลิก [`Start-DriverRuntimeManager.cmd`](skills/windows-driver-runtime-manager/scripts/Start-DriverRuntimeManager.cmd) บนเครื่อง Windows
เพื่อเปิดหน้าต่างตรวจระบบ ตรวจชุดไดรเวอร์และระดับการรับรอง (WHQL/Attestation/ผู้ผลิต) อัปเดตจากผู้ผลิตเครื่อง (Dell/Lenovo/HP ...) ก่อน
แล้วติดตั้งไดรเวอร์ที่ Microsoft รับรองซึ่งใหม่กว่า รันไทม์ Visual C++/.NET/DirectX/WebView2 จาก Microsoft โดยตรง และไฟล์ติดตั้งทุกรูปแบบ
ตามลำดับที่ผู้ผลิตแนะนำ — [คู่มือภาษาไทย](docs/windows-driver-runtime-manager/README_TH.md)

## สคริปต์เสริม

- [scripts/New-Win11ProMedia.ps1](scripts/New-Win11ProMedia.ps1) สร้างชุดติดตั้ง Windows 11 ที่มีเฉพาะรุ่น Pro (รันบน Windows ด้วยสิทธิ์ Administrator; ยังไม่ได้ทดสอบบน Windows จริง)

