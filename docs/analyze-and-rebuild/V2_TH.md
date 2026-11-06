# analyze-and-rebuild 2.0 — เครื่องมือที่ใช้งานได้

รุ่นนี้เพิ่มเครื่องมือ Python ที่รันได้จริงและตัวเรียกผ่าน PowerShell สำหรับสำรวจไฟล์/ฟังก์ชัน ทำบัญชีความเข้าใจ เก็บหลักฐาน ตรวจชุดส่งต่อ และเทียบพฤติกรรมกับโปรแกรมใหม่ โดยให้ Codex หรือผู้พัฒนาทำการวิเคราะห์เชิงความหมายและเขียน implementation ใหม่เอง

## สิ่งที่ทำได้จริง

| ส่วน | สิ่งที่ทำ | ขอบเขตจริง |
| --- | --- | --- |
| Inventory | อ่านไฟล์และ hash; ทำบัญชี class/function/async/lambda ของ Python ด้วย AST | ไม่รันต้นฉบับ; ไม่ถือว่ารู้ความหมายจากชื่อฟังก์ชัน |
| PowerShell parser | ใช้ AST ของ PowerShell อ่าน named function/method/type เมื่อมี runtime | ไม่ execute script ต้นฉบับ; ต้องตรวจ dynamic behavior ต่อ |
| ภาษาอื่น/ไฟล์โปรแกรม | แสดงไฟล์ ภาษาแบบ hint, JS/TS candidates และลายเซ็นไฟล์ binary/package | ไม่อ้างว่าแจกแจงทุกฟังก์ชันของ EXE/APK หรือทุกภาษาได้อัตโนมัติ |
| Evidence / Ledger | ผูกคำอธิบายกับ hash/ตำแหน่งโค้ดหรือผลสังเกตจริง พร้อม map requirement/test | ผู้วิเคราะห์ต้องอ่าน อธิบาย input/output/error/state และตรวจหลักฐานจริง |
| Readiness gate | ตรวจหน่วย/ไฟล์/ฟีเจอร์ที่ยังไม่เข้าใจ unknowns หลักฐานและกรณีทดสอบที่ขาด | ระงับชุดส่งต่อที่ยังไม่พร้อม; ไม่คำนวณเปอร์เซ็นต์ความเข้าใจสมมติ |
| Builder handoff | ส่งออกเฉพาะ contract, cases, build brief และ manifest | ไม่รวม source/report ภายใน/asset/binary ของต้นฉบับ; ต้องให้ผู้เขียนใหม่ใช้บริบทแยก |
| Observe / Verify | รัน CLI จาก argv array จับ exit/stdout/stderr และเทียบ text/JSON | มี timeout/ขนาดผลลัพธ์; ไม่ใช่ OS sandbox และไม่ใช่ GUI automation |
| Report | สร้างตารางฟังก์ชัน ฟีเจอร์ หลักฐาน สถานะ และผลทดสอบใน Markdown | รายงานภายในผู้วิเคราะห์ ไม่ส่งเข้า builder package |

## เริ่มจาก PowerShell

ต้องมี Python 3.10 ขึ้นไป ไม่ต้องติดตั้งแพ็กเกจ Python เพิ่ม หากมี clone เดิม ให้เข้าโฟลเดอร์คลังแล้วอัปเดต:

```powershell
git pull --ff-only
$arbTool = Join-Path (Get-Location) 'skills\analyze-and-rebuild\scripts\Analyze-Rebuild.ps1'
& $arbTool -Action init -Source 'C:\OriginalProgram' -Work 'C:\RebuildLab'
& $arbTool -Action status -Work 'C:\RebuildLab'
& $arbTool -Action report -Work 'C:\RebuildLab'
```

เปลี่ยน path เป็นของจริง โฟลเดอร์งานต้องเป็นโฟลเดอร์ใหม่ที่แยกจากต้นฉบับ รายงานอยู่ที่ `C:\RebuildLab\analyst\report.md` ตัวสกิลที่ติดตั้งแยกไว้ยังต้องอัปเดตจากสำเนานี้เมื่อเปลี่ยนเวอร์ชัน

หากเครื่องไม่อนุญาตให้รัน `.ps1` ใช้ Python โดยตรงจากคลังได้:

```powershell
py -3 .\skills\analyze-and-rebuild\scripts\arb.py init --source 'C:\OriginalProgram' --work 'C:\RebuildLab'
```

หากสร้าง lab ไปแล้ว ให้ใช้ `status` แทน `init` ไม่สร้างทับงานเดิม ตัว wrapper รองรับ `-WhatIf` และส่ง exit code ของเครื่องมือกลับออกมา

## ขั้นตอนวิเคราะห์และสร้างใหม่

1. ให้ Codex อ่านต้นฉบับและ `analyst/inventory.json` ตรวจทุกไฟล์ หน่วยที่ค้นพบ จุดเข้าใช้งาน UI/API/CLI/storage รวมถึงฟังก์ชันที่เกิดระหว่างรัน
2. อธิบายพฤติกรรมด้วยคำของตนเองใน ledger พร้อมหลักฐาน `E-...` หรือผลสังเกต `O-C-...` ส่วนที่เข้าไม่ถึงให้คงเป็น unknown หรือระบุขอบเขตที่ตัดออกอย่างชัดเจน
3. เขียน `contract.json` และ `cases.json` จากพฤติกรรมจริง ใช้ข้อมูลสังเคราะห์และ expected interface results ที่เขียนเอง ไม่ถอดหรือแปล source เป็น pseudocode
4. ตรวจ schema/coverage ด้วย `check` แล้วตรวจเนื้อหาโดยผู้วิเคราะห์จริง ก่อน `seal --reviewed` และ `handoff` flag นี้คือบันทึกว่างานตรวจเสร็จ ไม่ใช่การถามอนุมัติผู้ใช้ซ้ำ
5. ให้ผู้เขียนใหม่ในบริบทใหม่รับเฉพาะ builder package ออกแบบและเขียนโค้ดใหม่เอง ไม่ให้ดูต้นฉบับหรือรายงานภายในระหว่างเขียน
6. กลับมารันทดสอบจากฝั่งผู้วิเคราะห์ด้วย `verify` แก้ส่วนที่ไม่ตรง แล้วจัดโค้ดใหม่ เอกสาร และ tests เข้า GitHub ตามปลายทางที่ได้รับอนุญาต

ดูคำสั่งและ schema ที่ใช้จริงทั้งหมดใน [toolkit-guide.md](../../skills/analyze-and-rebuild/references/toolkit-guide.md) และ [workflow หลัก](../../skills/analyze-and-rebuild/SKILL.md)

## ส่วนประกอบสำหรับพัฒนาต่อ

| ไฟล์ | หน้าที่ |
| --- | --- |
| [arb.py](../../skills/analyze-and-rebuild/scripts/arb.py) | CLI, คำสั่งย่อย และ exit codes |
| [inventory.py](../../skills/analyze-and-rebuild/scripts/arbkit/inventory.py) | การค้นไฟล์ ภาษา/ลายเซ็น และ parser adapters |
| [workflow.py](../../skills/analyze-and-rebuild/scripts/arbkit/workflow.py) | workspace, evidence, ledger gates และชุดส่งต่อ |
| [runner.py](../../skills/analyze-and-rebuild/scripts/arbkit/runner.py) | รัน/จับผล CLI และตรวจความสดของผลทดสอบ |
| [reporting.py](../../skills/analyze-and-rebuild/scripts/arbkit/reporting.py) | รายงานที่อ่านง่ายจากหลักฐานและสถานะจริง |
| [common.py](../../skills/analyze-and-rebuild/scripts/arbkit/common.py) | JSON, hash และ path helpers |
| [Analyze-Rebuild.ps1](../../skills/analyze-and-rebuild/scripts/Analyze-Rebuild.ps1) | ตัวเรียกใช้งานบน PowerShell |
| [powershell-index.ps1](../../skills/analyze-and-rebuild/scripts/powershell-index.ps1) | ตัวอ่าน PowerShell AST |
| [test_arb.py](../../skills/analyze-and-rebuild/tests/test_arb.py) | ชุดทดสอบพฤติกรรมด้วย fixture สังเคราะห์ที่เขียนเอง |

รันชุดทดสอบจากโฟลเดอร์คลัง:

```powershell
py -3 -B -m unittest discover -s .\skills\analyze-and-rebuild\tests -v
```

## ขอบเขตการยืนยันผล

ผลตรวจบน Python/Linux ไม่ใช่ผลทดสอบ Windows ตัวทดสอบ native PowerShell จะข้ามเมื่อไม่มี runtime และต้องบันทึกว่าไม่ได้ทดสอบ การค้น source แบบ static ไม่ยืนยัน dynamic functions ทั้งหมดหรือบริการที่เข้าไม่ถึง ต้องตรวจโปรแกรมจริงและบอกขอบเขตหลักฐานทุกครั้ง

ไม่มีตัวตรวจข้อความใดพิสูจน์ว่าไม่คัดลอกได้ทุกกรณี รุ่นนี้ใช้การไม่ส่งต้นฉบับให้ผู้เขียนใหม่ การตรวจสเปกจริง และการตรวจการรั่วที่เครื่องมือจับได้ร่วมกัน ไม่อ้างว่าการแยกบริบทบน filesystem เดียวกันเป็นการปิดกั้นการเข้าถึงแล้ว

## ผลตรวจรุ่น 2.0

ตรวจบน Python 3.12.14 / Linux: ชุดทดสอบ 20 รายการ ผ่าน 19 รายการ และข้ามการทดสอบ native PowerShell 1 รายการเพราะไม่มี runtime ยังไม่ได้ทดสอบบน Windows จริง

ทดลองกระบวนการเต็มกับโปรแกรม Python JSON-lines สังเคราะห์ โดยผู้เขียนใหม่ใช้บริบทใหม่และรับเฉพาะชุดข้อกำหนดที่ตรวจแล้ว พบและแก้ความต่างในกรณีตัวเลขเล็กมากจากผลสังเกตจริง ก่อนจบด้วยผลเทียบต้นฉบับ 22/22 กรณีที่ผ่าน ทั้งนี้ไม่มีการบังคับสิทธิ์แยก filesystem และผลดังกล่าวไม่ยืนยันความครบทุกพฤติกรรมของทุกโปรแกรม
