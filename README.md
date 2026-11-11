# Codex programming skills — 2.2.0

ชุด Agent Skills สำหรับตรวจโค้ด สร้างโปรแกรม แก้บั๊ก เตรียมระบบทดสอบ Windows และวิเคราะห์เพื่อสร้างโปรแกรมใหม่อย่างอิสระ คำสั่งสกิล metadata โค้ด คอมเมนต์ และ code blocks ใช้ภาษาอังกฤษ ส่วนคำอธิบายภาษาไทยแยกไว้ในเอกสาร

| Skill | การใช้งาน |
| --- | --- |
| [code-review](skills/code-review/SKILL.md) | รายงานบั๊กพร้อมเงื่อนไข ผลกระทบ และหลักฐาน |
| [app-builder](skills/app-builder/SKILL.md) | สร้างหรือเพิ่มฟีเจอร์ให้รันและตรวจรับได้ |
| [debug-and-fix](skills/debug-and-fix/SKILL.md) | ทำซ้ำอาการ หาสาเหตุ แก้ และทดสอบ regression |
| [windows-simulator](skills/windows-simulator/SKILL.md) | เลือกและตั้ง runtime/CI/VM สำหรับการทดสอบ Windows |
| [analyze-and-rebuild](skills/analyze-and-rebuild/SKILL.md) | วิเคราะห์หลักฐาน สร้าง contract และเขียนใหม่โดยไม่คัดลอก |
| [rebuild-windows-from-behavior](skills/rebuild-windows-from-behavior/SKILL.md) | วิเคราะห์และสร้างโปรแกรม Windows ใหม่จากพฤติกรรมที่ตรวจได้ |

## โปรแกรมตัวอย่างและสกิลเสริม

- [AI Collab Lab](examples/ai-collab-lab/README_TH.md): GUI บนเบราว์เซอร์ที่จำลองออฟฟิศให้ทีม AI สื่อสารและช่วยกันทำงานผ่านเครื่องมือ 30 ชนิด (แชต บอร์ดงาน ไฟล์ คลังความรู้ โหวต) รันออฟไลน์ได้ทันทีด้วย `python collab_lab.py` หรือเปลี่ยนเอเจนต์เป็น Claude
- [skill for creating code](skill%20for%20creating%20code/README_TH.md): สกิลเสริมที่จัดตามหมวด เช่น `multi-agent-collab-lab` สำหรับเพิ่มเครื่องมือ บทบาท หรือโมเดลให้ AI Collab Lab ติดตั้งด้วย `--source "skill for creating code"`

## ติดตั้งจากแพ็กเกจหรือ checkout

ใช้ Python 3.10+ ไม่ต้องเพิ่ม Python dependencies แตก source ZIP หรือ clone repository แล้วรันจากโฟลเดอร์ที่มี `scripts/` ระบุปลายทางเป็นโฟลเดอร์สกิลของโครงการหรือบัญชีที่ต้องการ:

```sh
python -B scripts/install_skills.py --list
python -B scripts/install_skills.py --all --destination ../my-project/.agents/skills --dry-run
python -B scripts/install_skills.py --all --destination ../my-project/.agents/skills
```

ติดตั้งเฉพาะสกิลได้ด้วย `--skill` แทน `--all` ตัวติดตั้งตรวจไฟล์อ้างอิงและ runtime ก่อนเขียน ไม่เขียนทับสกิลเดิม และย้อนคืนเฉพาะโฟลเดอร์ใหม่หากติดตั้งล้มเหลว เปิดแชตใหม่หรือเริ่ม Codex ใหม่หลังติดตั้ง

ZIP รายสกิลมีโฟลเดอร์ชื่อสกิลพร้อม `SKILL.md`, metadata, references และ scripts ที่ต้องใช้ คัดลอกทั้งโฟลเดอร์ไป `.agents/skills/` หรือใช้ตัวติดตั้งจาก source bundle:

```sh
python -B scripts/install_skills.py --source ../extracted/code-review --all --destination ../my-project/.agents/skills
```

เรียกผ่านชื่อสกิล เช่น `$debug-and-fix` หรือ `$analyze-and-rebuild` ดูตัวอย่างและแนวทางเลือกใน [คู่มือภาษาไทย](SKILLS_GUIDE_TH.md)

## ทดสอบและสร้างแพ็กเกจจริง

จาก Git checkout ที่ stage ไฟล์รุ่นใหม่ครบแล้ว:

```sh
python -B scripts/check_repo.py --test
python -B scripts/build_release.py --output-dir dist/2.2.0
python -B scripts/verify_release.py --release-dir dist/2.2.0 --smoke
```

ได้ source ZIP, ZIP แยกทั้งหกสกิล, `release-manifest.json` และ `SHA256SUMS` ตัวตรวจตรวจ checksum และรายการไฟล์ทุก ZIP เทียบไฟล์รายสกิลกับ source แล้วติดตั้งทั้งสองรูปแบบในพื้นที่ชั่วคราวนอกรีโปที่มีช่องว่างใน path ทดสอบ CLI ที่ติดตั้งจริงและรันชุดทดสอบจาก source ที่แตก ZIP แล้ว `--smoke` จึงใช้เวลามากกว่าการตรวจ checksum อย่างเดียว

ตัวตรวจนโยบายปฏิเสธภาษาไทยในไฟล์โค้ด/config และ fenced code blocks เอกสารบรรยายภายนอก code block ใช้ภาษาไทยได้ CI ตรวจ Ubuntu/Windows/macOS ด้วย Python 3.10/3.12 พร้อม GUI/launcher/installer บน Windows และตรวจแพ็กเกจที่ build จริงก่อนเก็บ artifact

## ขอบเขตผลทดสอบ

สี่สกิลที่เป็นคำสั่ง AI ตรวจโครงสร้าง metadata และ references ได้ แต่ไม่ได้เป็น executable โปรแกรม สอง reconstruction toolkits มี CLI ที่รันและทดสอบวงจรงานได้จริง การติดตั้งสกิลไม่สร้าง VM หรือให้สิทธิ์เครื่อง/บัญชีภายนอกอัตโนมัติ

Media tests ของ [New-Win11ProMedia.ps1](scripts/New-Win11ProMedia.ps1) ใช้ PowerShell กับ Windows command mocks และทดสอบ native copy exit status; ยังไม่ยืนยัน DISM, mount ISO หรือการเขียน USB จริง รูปแบบ contract ของ ARB เป็น schema 2 และ Windows toolkit เป็น schema 1 ใช้แทนกันไม่ได้

ดู [รายการเปลี่ยนแปลง](CHANGELOG.md), [ผลตรวจรุ่น 2.2.0](docs/RELEASE_2.2.0_TH.md) และ [คู่มือพัฒนาต่อ](CONTRIBUTING_TH.md)
