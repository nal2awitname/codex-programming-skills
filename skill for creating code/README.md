# skill for creating code — สารบัญสกิลแยกตามหมวด

โฟลเดอร์นี้รวบรวมสกิลทั้งหมดในรีโปที่ใช้เพิ่มประสิทธิภาพการสร้างและแก้ไขโค้ด/สคริปต์คำสั่ง จัดตามหมวดพร้อมคำอธิบาย
ตัวสกิลจริงอยู่ในโฟลเดอร์ [`skills/`](../skills) (โครงสร้างที่ `$skill-installer` และ Codex ใช้ติดตั้ง) ลิงก์ด้านล่างพาไปยังสกิลแต่ละตัว

## 1. ระบบ Windows ไดรเวอร์ และรันไทม์

| สกิล | ใช้เมื่อ | สิ่งที่ได้ |
| --- | --- | --- |
| [windows-driver-runtime-manager](../skills/windows-driver-runtime-manager/SKILL.md) | ตรวจเครื่อง Windows ตรวจ/อัปเดตไดรเวอร์ ติดตั้งรันไทม์สำหรับเกมและงาน ติดตั้งไฟล์ไดรเวอร์ทุกรูปแบบ | หน้าต่าง GUI ติ๊กเลือก (PowerShell + WPF), อัปเดตจากผู้ผลิตก่อนแล้วจึง WHQL ที่ใหม่กว่า, ลำดับตามผู้ผลิตแนะนำ, log, ทำความสะอาด, รายงานความเข้ากันได้ — [คู่มือ](../docs/windows-driver-runtime-manager/README_TH.md) |
| [windows-simulator](../skills/windows-simulator/SKILL.md) | ต้องทดสอบสคริปต์/โปรแกรมบน Windows แต่เครื่องที่ใช้ไม่ใช่ Windows | ตัวเลือก CI runner, VM, Docker, Wine พร้อมไฟล์ตั้งค่าที่รันซ้ำได้ |

## 2. สร้างโปรแกรมและเพิ่มฟีเจอร์

| สกิล | ใช้เมื่อ | สิ่งที่ได้ |
| --- | --- | --- |
| [app-builder](../skills/app-builder/SKILL.md) | สร้างโปรแกรมใหม่หรือเพิ่มฟีเจอร์ | โค้ดที่รันได้ตามโจทย์ พร้อมคำสั่งรันและทดสอบ |

## 3. ตรวจโค้ดและแก้บั๊ก

| สกิล | ใช้เมื่อ | สิ่งที่ได้ |
| --- | --- | --- |
| [code-review](../skills/code-review/SKILL.md) | ตรวจ PR/branch หาบั๊กและ regression | รายการปัญหาพร้อมหลักฐานและตำแหน่ง path:line |
| [debug-and-fix](../skills/debug-and-fix/SKILL.md) | มี error หรืออาการผิดปกติที่ต้องหาสาเหตุ | ทำซ้ำอาการ แก้ที่สาเหตุ และ regression test |

## 4. วิเคราะห์และสร้างโปรแกรมใหม่โดยไม่คัดลอก

| สกิล | ใช้เมื่อ | สิ่งที่ได้ |
| --- | --- | --- |
| [analyze-and-rebuild](../skills/analyze-and-rebuild/SKILL.md) | วิเคราะห์ภาษาและโครงสร้างโปรแกรมแล้วสร้างใหม่ | รายงานวิเคราะห์ ข้อกำหนดพฤติกรรม ซอร์สใหม่และชุดทดสอบ |
| [rebuild-windows-from-behavior](../skills/rebuild-windows-from-behavior/SKILL.md) | สร้างโปรแกรม Windows ใหม่จากพฤติกรรมที่สังเกตได้ | เครื่องมือ Python/PowerShell บันทึกพฤติกรรม ส่งออกข้อกำหนด และเทียบผล |

## วิธีเรียกใช้

```text
ใช้ $windows-driver-runtime-manager ตรวจฮาร์ดแวร์และชุดไดรเวอร์ทั้งหมดของเครื่องนี้
อัปเดตจากผู้ผลิตก่อน แล้วติดตั้งไดรเวอร์ที่ Microsoft รับรองซึ่งใหม่กว่า พร้อมรันไทม์สำหรับเล่นเกม
```

ติดตั้งสกิลเข้า Codex: `ใช้ $skill-installer ติดตั้งสกิลจาก repository nal2awitname/codex-programming-skills ที่ path skills/<ชื่อสกิล>`
หรือคัดลอกโฟลเดอร์สกิลไปไว้ใน `.agents/skills/` ของโครงการ รายละเอียดอยู่ใน [คู่มือภาษาไทย](../SKILLS_GUIDE_TH.md)

## เพิ่มสกิลใหม่

1. สร้างโฟลเดอร์ `skills/<ชื่อ>/` ที่มี `SKILL.md` (frontmatter `name`, `description`) และ `agents/openai.yaml`
2. ใส่สคริปต์ใน `scripts/`, เอกสารอ้างอิงใน `references/`, ชุดทดสอบใน `tests/` และ workflow ใน `.github/workflows/` ถ้ามีโค้ดที่รันได้
3. เพิ่มแถวในหมวดที่เหมาะสมของไฟล์นี้ และในตารางของ [README.md](../README.md) กับ [SKILLS_GUIDE_TH.md](../SKILLS_GUIDE_TH.md)
