# Windows Behavior Rebuild 2.0 — Windows

สกิลสำหรับวิเคราะห์พฤติกรรม ภาษาและแนวคิดของโปรแกรม แล้วเขียนใหม่จากข้อกำหนดที่ตรวจแล้ว ห้ามคัดลอกโค้ดต้นฉบับแม้แต่บรรทัดเดียว ห้ามแปลโค้ดทีละบรรทัด เปลี่ยนชื่อเพื่ออำพราง หรือใช้โปรแกรมต้นฉบับทำงานแทนอยู่เบื้องหลัง

## สิ่งที่ใช้งานได้

| ส่วน | ทำอะไร |
| --- | --- |
| สกิลสำหรับ AI | สำรวจฟีเจอร์ อธิบายภาษา/แนวคิด แยกส่วนประกอบ กำหนดพฤติกรรม ออกแบบ เขียนและทดสอบโปรแกรมใหม่ |
| `inspect` | ตรวจไฟล์หรือโฟลเดอร์แบบ static: PE, สถาปัตยกรรม, การประกาศ CLR, ตัวบ่งชี้ภาษา/แพ็กเกจ และ SHA-256 ตามขีดจำกัด |
| `init` / `observe` | แยกพื้นที่วิเคราะห์กับข้อกำหนด และบันทึกผลสังเกตที่ผู้วิเคราะห์ป้อน |
| `validate-contract` | ตรวจรูปแบบ JSON, รหัสข้อกำหนด/กรณีทดสอบ และความเชื่อมโยง |
| `export` | ส่งออกเฉพาะข้อกำหนดที่ตรวจแล้ว คำแนะนำผู้เขียนใหม่ และ manifest; ไม่ส่งโค้ดหรือรายงานต้นฉบับ |
| `compare` | เทียบผล JSON ที่จับแยกจากสองโปรแกรมกับข้อกำหนดและเทียบกัน ตรวจกรณีขาดหายด้วย |
| PowerShell / CI | ตัวเรียกบน Windows, ตัวติดตั้งแบบไม่เขียนทับ และชุดทดสอบ Linux/Windows/macOS |

CLI ช่วยจัดข้อมูลและตรวจสอบอย่างเป็นระบบ การวิเคราะห์และเขียนโปรแกรมเป็นงานของ AI/ผู้พัฒนา CLI ไม่ได้สร้างแอปทุกชนิดอัตโนมัติ ไม่ติดตั้งหรือรันโปรแกรมอ้างอิง และไม่ใช่เครื่องบันทึก GUI

## เริ่มใช้บน Windows

ต้องมี Git, Python 3.10 ขึ้นไป และเครื่องมือ AI ที่รองรับสกิลเมื่อต้องการวิเคราะห์/เขียนโปรแกรมอัตโนมัติ ตัว CLI ใช้ Python standard library โดยไม่ต้อง `pip install`

```powershell
git clone https://github.com/nal2awitname/codex-programming-skills.git
cd codex-programming-skills
.\scripts\Install-WindowsBehaviorRebuild.ps1
```

ตัวติดตั้งคัดลอกสกิลไปที่ `$env:USERPROFILE\.agents\skills\rebuild-windows-from-behavior` และปฏิเสธเขียนทับของเดิม สำรองหรือย้ายของเดิมเองก่อนเมื่อต้องการเปลี่ยนรุ่น ใช้ `-WhatIf` เพื่อดูปลายทาง หรือ `-Destination` เพื่อเลือกโฟลเดอร์อื่น สกิลที่ติดตั้งใน ChatGPT กับสำเนาบน Windows/GitHub ต้องอัปเดตแต่ละแห่งตามที่ต้องการ

ตรวจไฟล์ได้ทันทีจากโฟลเดอร์คลัง แม้ยังไม่คัดลอกสกิล ตัวอย่างนี้ให้แทนชื่อโปรแกรมและเลือกไฟล์รายงานที่ยังไม่มี:

```powershell
python .\skills\rebuild-windows-from-behavior\scripts\rebuild.py init C:\Rebuild\Lab --name IndependentApp
python .\skills\rebuild-windows-from-behavior\scripts\rebuild.py inspect 'C:\Program Files\YourApp' --out C:\Rebuild\Lab\analyst\inventory.json
```

หรือใช้ `.\skills\rebuild-windows-from-behavior\scripts\Invoke-Rebuild.ps1` แทน `python ...\rebuild.py` หากเครื่องบล็อกสคริปต์ PowerShell ให้ใช้คำสั่ง Python ข้างบนโดยตรง

เรียก AI ด้วยข้อความนี้และแนบไฟล์/ข้อมูลการทดสอบจริง:

```text
Use $rebuild-windows-from-behavior to analyze this Windows program from behavior.
Identify languages from evidence, explain components, and inventory accessible features.
Create a source-free contract and implement it with an independent design.
Never copy, translate, or adapt original implementation code.
Test the contract, report unverified scope, and prepare the project for continued development.
```

## กระบวนการใช้งาน

1. เก็บไฟล์ต้นฉบับไว้นอกโครงการใหม่ ตรวจ identity/version และทำ inventory แบบอ่านอย่างเดียว
2. บน Windows/VM ที่เข้าถึงได้ ทดลองอินพุตสังเคราะห์และบันทึกผลจริง ครอบคลุมฟีเจอร์ ปุ่ม เมนู ไฟล์ บันทึกสถานะ ข้อผิดพลาด และข้อจำกัดที่เกี่ยวข้อง ไม่อ้างว่าทราบฟังก์ชันที่ยังค้นไม่พบ
3. ใช้ `observe` เก็บแต่ละผลลง `analyst/observations.jsonl` และแก้ `spec/contract.json` เป็นข้อกำหนดพฤติกรรม รายละเอียดรูปแบบอยู่ใน [toolkit.md](../../skills/rebuild-windows-from-behavior/references/toolkit.md)
4. ตรวจข้อกำหนดทั้งหมด รวมตัวอย่าง input/expected และ exact literals ให้ไม่มีโค้ด private symbols โครงสร้างภายใน หรือชุดทดสอบต้นฉบับ บันทึกผู้ตรวจและผลใน `handoff_review` ก่อน `export`
5. ให้ผู้เขียนใหม่รับเฉพาะโฟลเดอร์ที่ export เลือกภาษา โครงสร้างข้อมูล และวิธีแก้ปัญหาเอง บันทึกตามจริงว่าแยกเพียงข้อมูล/บริบท หรือมีการควบคุมการเข้าถึงต้นฉบับจริง
6. รัน build/test ของโปรแกรมใหม่ จับผลอ้างอิงและผลใหม่แยกกัน ใช้ `compare` สำหรับ JSON; GUI/ไฟล์ไบนารี/ฮาร์ดแวร์ต้องมีการทดสอบเฉพาะด้านเพิ่ม
7. ส่ง GitHub เฉพาะโค้ดใหม่ ข้อกำหนดสะอาด ชุดทดสอบที่เขียนเอง และวิธีพัฒนาต่อ ห้ามรวมโค้ด ไฟล์ decompile ทรัพยากร หรือบันทึกส่วนตัวจากต้นฉบับ

การแยกโฟลเดอร์ manifest และ schema checker ช่วยลดความผิดพลาด แต่ไม่พิสูจน์ว่าปลอดการคัดลอก ผู้ตรวจต้องอ่านเนื้อหาทั้งชุด การใช้ agent บน filesystem ร่วมกันไม่ใช่การแยกสิทธิ์เข้าถึงจริง

## ขอบเขต Windows

รองรับการรับงานสำรวจโปรแกรม Windows ทั่วไปและจัดวิธีตรวจตามชนิดของโปรแกรม เช่น native EXE/DLL/SYS, .NET, Electron, scripts, MSI/MSIX, services, COM และโปรแกรมที่ต่อฮาร์ดแวร์ รายละเอียดใน [windows-workflow.md](../../skills/rebuild-windows-from-behavior/references/windows-workflow.md)

ไม่สามารถรับรองว่าสร้างใหม่ได้ครบทุกโปรแกรมหรือทุกฟังก์ชันจากไฟล์เดียว ภาษาเดิมของ native binary อาจระบุไม่ได้ การมี CLR ไม่ยืนยันว่าเป็น C# ส่วน cloud backend, driver, DRM, รูปแบบเฉพาะ, CAD kernel, เกมและฮาร์ดแวร์อาจต้องมีเครื่องมือ ข้อมูล และสภาพแวดล้อมเพิ่มเติม ต้องระบุว่าไม่ทราบหรือยังไม่ได้ทดสอบเมื่อหลักฐานไม่พอ

## พัฒนาต่อและทดสอบ

```powershell
python -m unittest discover -s tests/rebuild-windows-from-behavior -v
```

| เปลี่ยนอะไร | แก้ที่ |
| --- | --- |
| กระบวนการและข้อห้ามคัดลอก | `skills/rebuild-windows-from-behavior/SKILL.md` |
| การตรวจ PE/ภาษา, contract, handoff, comparison | `skills/rebuild-windows-from-behavior/scripts/rebuild.py` |
| แนวทางสำรวจ GUI/Windows/ฟีเจอร์ | `skills/rebuild-windows-from-behavior/references/windows-workflow.md` |
| คำสั่งและ schema | `skills/rebuild-windows-from-behavior/references/toolkit.md` |
| ตัวติดตั้ง Windows | `scripts/Install-WindowsBehaviorRebuild.ps1` |
| การตรวจการเปลี่ยนแปลง | `tests/rebuild-windows-from-behavior/test_toolkit.py` และ `.github/workflows/windows-behavior-rebuild.yml` |

เพิ่มความสามารถโดยเริ่มจากข้อกำหนดและกรณีทดสอบสังเคราะห์ แล้วเพิ่ม detector/adapter โดยไม่รันเป้าหมายระหว่าง static triage อย่าเปลี่ยน schema หรือยอมให้ส่งออกโฟลเดอร์วิเคราะห์ทั้งชุดโดยไม่ทบทวนขอบเขตข้อมูล

มี [ตัวอย่างโปรแกรมที่สร้างใหม่จากพฤติกรรม](../../examples/rebuild-windows-from-behavior/README.md) พร้อมข้อกำหนดและชุดทดสอบที่เขียนเอง โดยไม่รวมโค้ดอ้างอิง

สถานะการทดสอบและข้อจำกัดของรุ่นนี้บันทึกใน [VALIDATION_V2.md](VALIDATION_V2.md) ผลใน GitHub Actions เป็นผลจริงของแต่ละระบบ ไม่ใช้ผล Linux แทนการยืนยัน Windows

ตำแหน่งติดตั้งแบบผู้ใช้ของ Codex อ้างอิง [เอกสาร OpenAI](https://learn.chatgpt.com/docs/build-skills) ตรวจเมื่อ 6 พฤศจิกายน 2026
