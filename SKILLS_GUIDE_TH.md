# สกิลสำหรับตรวจโค้ดและพัฒนาโปรแกรม

ชุดนี้เป็น Agent Skills สำหรับ Codex แต่ละโฟลเดอร์มี `SKILL.md` และ metadata สำหรับแสดงในรายการสกิล รองรับการเรียกด้วยชื่อสกิลหรือเลือกใช้ตามลักษณะงาน

| สกิล | ใช้ทำอะไร | ตัวอย่างคำสั่ง |
| --- | --- | --- |
| [code-review](skills/code-review/SKILL.md) | ตรวจบั๊กและ regression พร้อมตำแหน่ง ผลกระทบ และหลักฐาน | `ใช้ $code-review ตรวจ PR นี้ โดยเน้น logic และความเข้ากันได้กับข้อมูลเดิม` |
| [app-builder](skills/app-builder/SKILL.md) | สร้างโปรแกรมหรือเพิ่มฟีเจอร์จนรันและตรวจรับได้ | `ใช้ $app-builder สร้าง CLI ด้วย Python สำหรับรวมไฟล์ CSV ตามรหัสสินค้า` |
| [debug-and-fix](skills/debug-and-fix/SKILL.md) | ทำซ้ำอาการ หาสาเหตุ แก้บั๊ก และยืนยันผล | `ใช้ $debug-and-fix แก้ปัญหาตั้ง limit เป็น 0 แล้วกลับได้ค่าเริ่มต้น` |
| [windows-simulator](skills/windows-simulator/SKILL.md) | เลือกและตั้งระบบจำลอง/ทดสอบ Windows (CI, VM, Docker, Wine) | `ใช้ $windows-simulator ตั้งระบบทดสอบสคริปต์ PowerShell บน Windows` |
| [analyze-and-rebuild](skills/analyze-and-rebuild/SKILL.md) | วิเคราะห์ source/artifact และจัดทำข้อกำหนดสำหรับเขียนใหม่อย่างอิสระ | `ใช้ $analyze-and-rebuild วิเคราะห์ CLI นี้ แล้วสร้างใหม่จากข้อกำหนด` |
| [rebuild-windows-from-behavior](skills/rebuild-windows-from-behavior/SKILL.md) | วิเคราะห์พฤติกรรมโปรแกรม Windows พร้อม toolkit ตรวจ contract | `ใช้ $rebuild-windows-from-behavior ตรวจ EXE นี้และสรุปพฤติกรรมที่พิสูจน์ได้` |

สกิลเหล่านี้เป็นขั้นตอนให้ AI ทำงานร่วมกับเครื่องมือและ runtime ที่มีในแต่ละแชต ความสามารถในการรัน ทดสอบ หรือเข้าถึง GitHub ขึ้นกับ environment และสิทธิ์ที่เชื่อมต่อไว้ ผลทดสอบต้องมาจากการรันจริง

## ติดตั้งจาก GitHub

ใน Codex ส่งคำสั่งนี้เพื่อให้สกิลตัวติดตั้งดาวน์โหลดทั้งสามโฟลเดอร์:

```text
Use $skill-installer to install skills from nal2awitname/codex-programming-skills
at paths skills/code-review, skills/app-builder, and skills/debug-and-fix.
```

หากมีสกิลชื่อเดียวกันอยู่แล้ว ให้เลือกว่าจะเก็บของเดิมหรือเปลี่ยนชื่อชุดใหม่ก่อนแทนที่
เมื่อสกิลไม่ปรากฏในรายการ ให้เปิดแชตใหม่หรือเริ่ม Codex ใหม่

## ใช้เฉพาะในโครงการ

คัดลอกโฟลเดอร์ที่ต้องการจาก `skills/` ไปไว้ใน `.agents/skills/` ของโครงการเป้าหมาย เช่น:

```text
my-project/
  .agents/
    skills/
      code-review/
        SKILL.md
        agents/openai.yaml
      app-builder/
        SKILL.md
        agents/openai.yaml
      debug-and-fix/
        SKILL.md
        agents/openai.yaml
```

Codex อ่านชื่อและ description เพื่อเลือกสกิลตามงาน หรือเรียกเองด้วย `$code-review`, `$app-builder` และ `$debug-and-fix`
รายละเอียดรูปแบบ การค้นหาสกิล และการติดตั้งอยู่ใน [คู่มือ OpenAI](https://learn.chatgpt.com/docs/build-skills)

## ตัวอย่างงานที่ระบุผลลัพธ์ชัดเจน

```text
Use $code-review to review the current branch against main.
Report only evidenced bugs with their triggers and path:line locations.
```

```text
Use $app-builder to add a product management API to this project.
Use the existing stack and database; support create, update, delete, and search.
Provide run commands and tests for invalid input.
```

```text
Use $debug-and-fix to reproduce the following error locally.
Fix the cause while preserving the existing API and run relevant regression tests.
```

## เลือก toolkit สำหรับงานวิเคราะห์และสร้างใหม่

- `analyze-and-rebuild`: วิเคราะห์โครงสร้าง ไฟล์ และฟังก์ชัน พร้อม ledger/evidence และรัน CLI probes ด้วย `skills/analyze-and-rebuild/scripts/arb.py`
- `rebuild-windows-from-behavior`: เริ่มจาก artifact และพฤติกรรม Windows เก็บ observation ที่ผู้ใช้หรือเครื่องมือจับจริง แล้วตรวจ contract ด้วย `skills/rebuild-windows-from-behavior/scripts/rebuild.py`

ทั้งสอง CLI ใช้ Python 3.10+ และมี PowerShell wrapper; ไม่ติดตั้ง VM หรือรันโปรแกรม Windows โดยอัตโนมัติ JSON schema ของทั้งสองต่างกัน อ่านคู่มือ toolkit ที่อยู่ในสกิลที่เลือกก่อนเตรียมไฟล์

ติดตั้งสกิลเพิ่มผ่าน `$skill-installer` โดยระบุ path ที่ตรงกับชื่อในตาราง หรือคัดลอกทั้งโฟลเดอร์ไป `.agents/skills/` ห้ามคัดลอกเฉพาะ `SKILL.md` เพราะบางสกิลต้องใช้ `scripts/` และ `references/` ด้วย

รุ่นปัจจุบัน **2.2.0**: ดู [รายการแก้ไข](CHANGELOG.md) และ [วิธีตรวจทั้งรีโป/สร้าง ZIP](README.md#ทดสอบและสร้างแพ็กเกจจริง)


## ตัวติดตั้งและแพ็กเกจรุ่น 2.2.0

คำสั่งสกิลและ metadata เป็นภาษาอังกฤษเพื่อลดความกำกวมในการเรียกใช้ AI ตอบภาษาของผู้ใช้ได้ แต่โค้ดและ configuration ที่สร้างต้องเป็นภาษาอังกฤษ ตัวตรวจแยกเอกสารภาษาไทยออกจากไฟล์โค้ดและ code blocks

ใช้ source ZIP เพื่อรับตัวติดตั้งและตัวตรวจแพ็กเกจครบ หรือเลือก ZIP รายสกิลและคัดลอกทั้งโฟลเดอร์ หลังแตก source bundle:

```sh
python -B scripts/install_skills.py --list
python -B scripts/install_skills.py --all --destination ../my-project/.agents/skills --dry-run
python -B scripts/install_skills.py --all --destination ../my-project/.agents/skills
```

หากปลายทางมีสกิลชื่อเดิม ตัวติดตั้งจะหยุดและไม่เปลี่ยนไฟล์เดิม เลือกปลายทางใหม่หรือสำรองและย้ายสำเนาเดิมด้วยตนเองก่อนติดตั้ง รุ่นนี้ไม่แอบแทนที่สกิลที่ใช้งานอยู่
