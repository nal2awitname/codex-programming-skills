# สกิลตรวจโค้ดและพัฒนาโปรแกรม — 2.1.0

ชุด Agent Skills สำหรับ Codex ของ [nal2awitname](https://github.com/nal2awitname) เก็บขั้นตอนตรวจโค้ด สร้างโปรแกรม และแก้บั๊กที่นำกลับมาใช้ได้ในหลายโครงการ

| สกิล | ความสามารถ | ตัวอย่างเรียก |
| --- | --- | --- |
| [code-review](skills/code-review/SKILL.md) | ตรวจบั๊กและ regression พร้อมหลักฐานและตำแหน่งโค้ด | `ใช้ $code-review ตรวจ branch นี้เทียบกับ main` |
| [app-builder](skills/app-builder/SKILL.md) | สร้างโปรแกรมหรือเพิ่มฟีเจอร์ให้รันและตรวจรับได้ | `ใช้ $app-builder สร้าง Python CLI รวมไฟล์ CSV` |
| [debug-and-fix](skills/debug-and-fix/SKILL.md) | ทำซ้ำอาการ หาสาเหตุ แก้ไข และตรวจผล | `ใช้ $debug-and-fix แก้ error นี้พร้อม regression test` |
| [windows-simulator](skills/windows-simulator/SKILL.md) | เลือกและตั้งระบบจำลอง/ทดสอบ Windows พร้อมเทียบตัวเลือก | `ใช้ $windows-simulator ตั้งระบบทดสอบสคริปต์ PowerShell บน Windows` |
| [analyze-and-rebuild](skills/analyze-and-rebuild/SKILL.md) | วิเคราะห์ภาษาและโครงสร้าง สร้างใหม่โดยไม่คัดลอก พร้อมจัดส่วนประกอบส่ง GitHub | `ใช้ $analyze-and-rebuild วิเคราะห์และสร้างโปรแกรมนี้ใหม่` |
| [rebuild-windows-from-behavior](skills/rebuild-windows-from-behavior/SKILL.md) | วิเคราะห์โปรแกรม Windows และสร้างใหม่จากพฤติกรรม พร้อมเครื่องมือตรวจ contract | `ใช้ $rebuild-windows-from-behavior วิเคราะห์ EXE นี้และสร้างใหม่ตามขอบเขตที่ตรวจได้` |

## ติดตั้ง

ส่งคำขอนี้ใน Codex:

```text
ใช้ $skill-installer ติดตั้งสกิลจาก repository nal2awitname/codex-programming-skills
ที่ paths skills/code-review, skills/app-builder และ skills/debug-and-fix
```

เริ่ม Codex ใหม่หลังติดตั้ง หากใช้เฉพาะโครงการ ให้คัดลอกโฟลเดอร์สกิลไปไว้ใน `.agents/skills/` ของโครงการนั้น ดูขั้นตอนและตัวอย่างเพิ่มเติมใน [คู่มือภาษาไทย](SKILLS_GUIDE_TH.md)

สกิลทำงานร่วมกับ runtime และเครื่องมือที่แชตเข้าถึงได้ การใช้ GitHub หรือรันทดสอบต้องอาศัยการเชื่อมต่อและสิทธิ์ที่มีอยู่ สกิลนี้ไม่ได้ตั้ง automation ให้ทำงานเอง

## วิเคราะห์โปรแกรมและสร้างใหม่

**รุ่นปัจจุบัน 2.1.0 มีเครื่องมือ Python/PowerShell ที่รันได้จริง:** [เริ่มใช้และพัฒนาต่อ](docs/analyze-and-rebuild/V2_TH.md)

สกิล `analyze-and-rebuild` แยกรายงานวิเคราะห์ต้นฉบับออกจากข้อกำหนดที่ใช้เขียนใหม่ กำหนดห้ามคัดลอกหรือแปลโค้ดทีละบรรทัด และเตรียมซอร์สใหม่ เอกสาร และชุดทดสอบให้พัฒนาต่อได้

- [คู่มือใช้งานและส่วนประกอบ](docs/analyze-and-rebuild/README_TH.md)
- [แนวทางพัฒนาสกิลต่อ](docs/analyze-and-rebuild/DEVELOPMENT.md)
- [แม่แบบข้อกำหนดพฤติกรรม](templates/analyze-and-rebuild/behavior-contract.md)
- [แม่แบบแผนผังส่วนประกอบ](templates/analyze-and-rebuild/components.md)
- [แม่แบบบันทึกการสร้างใหม่](templates/analyze-and-rebuild/reconstruction-record.md)

## สคริปต์เสริม

- [scripts/New-Win11ProMedia.ps1](scripts/New-Win11ProMedia.ps1) สร้างชุดติดตั้ง Windows 11 ที่มีเฉพาะรุ่น Pro (รันบน Windows ด้วยสิทธิ์ Administrator; ผ่าน parser และการทดสอบแบบ mock บน PowerShell 7 แต่ยังไม่ได้ทดสอบ DISM/USB จริงบน Windows)


## รุ่น 2.1.0 และการตรวจสอบ

ดู [รายการแก้ไข](CHANGELOG.md) และ [ผลตรวจพร้อมข้อจำกัด](docs/RELEASE_2.1.0_TH.md) รุ่นนี้รักษา JSON schema เดิมของแต่ละ toolkit; ไฟล์ของ ARB และ Windows toolkit ใช้แทนกันไม่ได้

จาก repository checkout ใช้ Python 3.10 ขึ้นไป โดยไม่ต้องติดตั้ง Python dependencies เพิ่ม:

```sh
python -B scripts/check_repo.py
python -B scripts/check_repo.py --test
python -B scripts/build_release.py --output-dir dist/2.1.0
```

คำสั่งแรกตรวจ metadata ชื่อสกิล ลิงก์ภายในสกิล syntax Python และเลขเวอร์ชัน คำสั่งที่สองรันทุกชุดทดสอบใน process แยกกัน PowerShell tests ต้องมี `pwsh` หรือ `powershell` ใน PATH; GUI tests ของ Windows ต้องรันบน Windows ผลที่ข้ามจะรายงานเป็น skipped

คำสั่งสุดท้ายสร้าง ZIP ของไฟล์ที่ Git track พร้อม `SHA256SUMS` และไม่เขียนทับโฟลเดอร์ปลายทาง ต้อง `git add` ไฟล์รุ่นใหม่ที่ตั้งใจรวมก่อน build; ไฟล์ local ที่ไม่ track จะไม่ถูกรวม การ build จาก bytes เดียวกันให้ ZIP เหมือนเดิม รวมคู่มือ สคริปต์ ตัวอย่าง และชุดทดสอบไว้ด้วย แตก ZIP แล้วติดตั้งเฉพาะโฟลเดอร์สกิลที่ต้องการจาก `skills/` ตามวิธีข้างต้น

CI รวมการตรวจทั้งชุดบน Ubuntu, Windows และ macOS ด้วย Python 3.10/3.12 และสร้าง artifact สำหรับดาวน์โหลดเมื่อ job ที่เกี่ยวข้องผ่าน การมี workflow ไม่ถือเป็นผลทดสอบจนกว่า GitHub Actions จะรันสำเร็จจริง

แนวทางแก้บั๊ก เพิ่ม regression test และเตรียมแพ็กเกจสำหรับพัฒนาต่ออยู่ใน [คู่มือผู้พัฒนา](CONTRIBUTING_TH.md)
