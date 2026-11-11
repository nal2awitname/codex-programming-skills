# Skill for creating code — คลังสกิลสำหรับสร้างโค้ด

โฟลเดอร์นี้เป็นสารบัญของสกิลทั้งหมดในรีโป จัดเป็นหมวดตามงาน พร้อมคำอธิบายว่าใช้เมื่อไร ได้อะไร และเรียกอย่างไร ตัวสกิลที่ติดตั้งได้จริงอยู่ใน [`skills/`](../skills) เพราะตัวติดตั้ง ตัวตรวจ CI และแพ็กเกจ ZIP อ่านจากโครงสร้างนั้น การเก็บไฟล์ชุดเดียวทำให้สารบัญกับสกิลไม่หลุดกัน

สกิลใหม่ที่สร้างขึ้นเพื่อช่วยงานเขียนโค้ดหรือสคริปต์คำสั่งจะถูกเพิ่มในหมวดที่ตรงกันในหน้านี้

## หมวด 1: เขียนและรันโค้ด / สคริปต์คำสั่ง

### [powershell-code-runner](../skills/powershell-code-runner/SKILL.md) — ใหม่ในรุ่น 2.3.0

- **ใช้เมื่อ:** ต้องการคำสั่งหรือสคริปต์ PowerShell, ต้องการรันโค้ดภาษาใดก็ได้จาก terminal, หรือสคริปต์ที่รันได้ในเครื่องหนึ่งแต่พังอีกเครื่อง
- **ได้อะไร:** `Invoke-Code.ps1` รันโค้ด 53 ภาษา/รูปแบบด้วยคำสั่งเดียว (`-Plan` อธิบายก่อนรัน, `-List` ดูว่าเครื่องพร้อมภาษาใด) ตัวตรวจ `Test-PowerShellScript.ps1` เทมเพลตสคริปต์ และไฟล์ `.cmd` สำหรับดับเบิลคลิกหรือลากไฟล์มาวาง
- **ตัวอย่าง:** `ใช้ $powershell-code-runner เขียนสคริปต์ลบไฟล์ log ที่เก่ากว่า 30 วัน ให้มีโหมดทดลอง -WhatIf และรันได้บน Windows ทุกเครื่อง`
- **คู่มือ:** [ภาษาไทย](../docs/powershell-code-runner/README_TH.md), [ตัวรัน](../skills/powershell-code-runner/references/runner.md), [กฎเขียนสคริปต์](../skills/powershell-code-runner/references/powershell-rules.md)

### [app-builder](../skills/app-builder/SKILL.md)

- **ใช้เมื่อ:** สร้างโปรแกรมใหม่หรือเพิ่มฟีเจอร์ในโปรเจกต์ที่มีอยู่
- **ได้อะไร:** โค้ดที่รันได้ คำสั่งรัน และการทดสอบตามเกณฑ์ตรวจรับ
- **ตัวอย่าง:** `ใช้ $app-builder สร้าง CLI ด้วย Python สำหรับรวมไฟล์ CSV ตามรหัสสินค้า`

## หมวด 2: ตรวจและแก้บั๊ก

### [code-review](../skills/code-review/SKILL.md)

- **ใช้เมื่อ:** ต้องการรายงานปัญหาก่อน merge โดยยังไม่แก้โค้ด
- **ได้อะไร:** บั๊กพร้อมตำแหน่ง เงื่อนไขที่ทำให้เกิด ผลกระทบ และหลักฐาน
- **ตัวอย่าง:** `ใช้ $code-review ตรวจ branch นี้เทียบกับ main เน้น logic และข้อมูลเดิม`

### [debug-and-fix](../skills/debug-and-fix/SKILL.md)

- **ใช้เมื่อ:** มี error, test ล้ม หรือโปรแกรมทำงานผิดจากที่คาด
- **ได้อะไร:** ทำซ้ำอาการ หาสาเหตุที่มีหลักฐาน แก้เฉพาะจุด และทดสอบ regression
- **ตัวอย่าง:** `ใช้ $debug-and-fix แก้ปัญหาตั้ง limit เป็น 0 แล้วได้ค่าเริ่มต้นกลับมา`

## หมวด 3: วิเคราะห์และสร้างโปรแกรมใหม่

### [analyze-and-rebuild](../skills/analyze-and-rebuild/SKILL.md)

- **ใช้เมื่อ:** ต้องการเข้าใจโค้ดหรือโปรแกรมเดิม แล้วเขียนใหม่โดยไม่คัดลอก
- **ได้อะไร:** หลักฐาน ข้อกำหนดพฤติกรรม (contract) และ CLI `arb.py` สำหรับ probe และตรวจผล
- **ตัวอย่าง:** `ใช้ $analyze-and-rebuild วิเคราะห์ CLI นี้ แล้วสร้างใหม่จากข้อกำหนด`

### [rebuild-windows-from-behavior](../skills/rebuild-windows-from-behavior/SKILL.md)

- **ใช้เมื่อ:** มีแต่ไฟล์โปรแกรม Windows (EXE) และต้องการสร้างใหม่จากพฤติกรรมที่สังเกตได้
- **ได้อะไร:** บันทึกพฤติกรรม contract และ toolkit `rebuild.py` ตรวจว่าตัวใหม่ทำงานตรงกัน
- **ตัวอย่าง:** `ใช้ $rebuild-windows-from-behavior ตรวจ EXE นี้และสรุปพฤติกรรมที่พิสูจน์ได้`

## หมวด 4: ระบบทดสอบบน Windows

### [windows-simulator](../skills/windows-simulator/SKILL.md)

- **ใช้เมื่อ:** ต้องทดสอบโปรแกรมหรือสคริปต์บน Windows แต่ไม่มีเครื่อง Windows หรือต้องการ CI/VM
- **ได้อะไร:** คำแนะนำเลือกและตั้ง GitHub Actions, VM, Docker หรือ Wine ตามงาน
- **ตัวอย่าง:** `ใช้ $windows-simulator ตั้งระบบทดสอบสคริปต์ PowerShell บน Windows`

## เลือกสกิลอย่างรวดเร็ว

| งานที่ต้องการ | สกิล |
| --- | --- |
| รันไฟล์โค้ด / ทดลองโค้ดภาษาใดก็ได้ | powershell-code-runner |
| เขียนหรืออธิบายสคริปต์ PowerShell, คำสั่ง terminal | powershell-code-runner |
| สร้างโปรแกรมหรือฟีเจอร์ใหม่ | app-builder |
| หาบั๊กโดยไม่แก้ | code-review |
| แก้บั๊กให้หาย | debug-and-fix |
| เข้าใจโค้ดเดิมแล้วเขียนใหม่ | analyze-and-rebuild |
| สร้างโปรแกรม Windows ใหม่จากพฤติกรรม EXE | rebuild-windows-from-behavior |
| เตรียมเครื่อง/CI สำหรับทดสอบ Windows | windows-simulator |

## ติดตั้ง

ติดตั้งทั้งหมดหรือเลือกรายสกิลจากรากของรีโป (Python 3.10+):

```sh
python -B scripts/install_skills.py --list
python -B scripts/install_skills.py --all --destination ../my-project/.agents/skills
python -B scripts/install_skills.py --skill powershell-code-runner --destination ../my-project/.agents/skills
```

สำหรับ Claude ให้บีบอัดโฟลเดอร์สกิลทั้งโฟลเดอร์ (เช่น `skills/powershell-code-runner`) เป็น ZIP แล้วอัปโหลดในหน้าตั้งค่า Skills ห้ามแยกเฉพาะ `SKILL.md` เพราะหลายสกิลใช้ `scripts/`, `assets/` และ `references/`

## เพิ่มสกิลใหม่ในคลัง

1. สร้าง `skills/<ชื่อ-สกิล>/SKILL.md` ที่มี frontmatter `name` ตรงกับชื่อโฟลเดอร์และ `description` บอกว่าใช้เมื่อไร
2. เพิ่ม `agents/openai.yaml` ที่มี `display_name`, `short_description` และ `default_prompt` ซึ่งเรียก `$<ชื่อ-สกิล>`
3. เขียนคำสั่งสกิล โค้ด และ code block เป็นภาษาอังกฤษ คำอธิบายภาษาไทยอยู่ในเอกสารภายนอก
4. เพิ่มสกิลในหมวดที่ตรงกันในหน้านี้ แล้วรัน `python -B scripts/check_repo.py --test`
