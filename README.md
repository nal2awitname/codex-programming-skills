# สกิลตรวจโค้ดและพัฒนาโปรแกรม

ชุด Agent Skills สำหรับ Codex ของ [nal2awitname](https://github.com/nal2awitname) เก็บขั้นตอนตรวจโค้ด สร้างโปรแกรม และแก้บั๊กที่นำกลับมาใช้ได้ในหลายโครงการ

| สกิล | ความสามารถ | ตัวอย่างเรียก |
| --- | --- | --- |
| [code-review](skills/code-review/SKILL.md) | ตรวจบั๊กและ regression พร้อมหลักฐานและตำแหน่งโค้ด | `ใช้ $code-review ตรวจ branch นี้เทียบกับ main` |
| [app-builder](skills/app-builder/SKILL.md) | สร้างโปรแกรมหรือเพิ่มฟีเจอร์ให้รันและตรวจรับได้ | `ใช้ $app-builder สร้าง Python CLI รวมไฟล์ CSV` |
| [debug-and-fix](skills/debug-and-fix/SKILL.md) | ทำซ้ำอาการ หาสาเหตุ แก้ไข และตรวจผล | `ใช้ $debug-and-fix แก้ error นี้พร้อม regression test` |

## ติดตั้ง

ส่งคำขอนี้ใน Codex:

```text
ใช้ $skill-installer ติดตั้งสกิลจาก repository nal2awitname/codex-programming-skills
ที่ paths skills/code-review, skills/app-builder และ skills/debug-and-fix
```

เริ่ม Codex ใหม่หลังติดตั้ง หากใช้เฉพาะโครงการ ให้คัดลอกโฟลเดอร์สกิลไปไว้ใน `.agents/skills/` ของโครงการนั้น ดูขั้นตอนและตัวอย่างเพิ่มเติมใน [คู่มือภาษาไทย](SKILLS_GUIDE_TH.md)

สกิลทำงานร่วมกับ runtime และเครื่องมือที่แชตเข้าถึงได้ การใช้ GitHub หรือรันทดสอบต้องอาศัยการเชื่อมต่อและสิทธิ์ที่มีอยู่ สกิลนี้ไม่ได้ตั้ง automation ให้ทำงานเอง
