# รุ่น 2.2.0: แพ็กเกจที่ติดตั้งและทดสอบได้

รุ่นนี้เริ่มจาก `main` commit `9779016434551534889ef7bc62476b1dc4ea7c52` ปรับคำสั่ง AI ทั้งหกสกิลให้ใช้ภาษาอังกฤษและมีลำดับงานที่ระบุเงื่อนไขตรวจรับชัดเจน ไม่ขอให้เปิดเผยกระบวนการคิดภายใน อธิบายแผนเป็นการกระทำและผลที่ตรวจได้ ลดคำสั่งซ้ำ แต่ยังรักษาขอบเขตงาน หลักฐาน และการสร้างโปรแกรมใหม่โดยไม่คัดลอก

## ไฟล์แพ็กเกจ

- source ZIP รวม source, scripts, tests และเอกสาร
- ZIP แยกหกสกิล โดยแต่ละ ZIP มีโฟลเดอร์ชื่อสกิลพร้อมไฟล์ที่ต้องใช้ครบ
- `release-manifest.json` บันทึกรายการ ZIP รายการไฟล์ ขนาด และ SHA-256
- `SHA256SUMS` สำหรับตรวจ source ZIP, ZIP รายสกิล และ manifest

ตัวติดตั้ง Python ใช้กับ checkout, source ที่แตก ZIP หรือโฟลเดอร์สกิลเดี่ยวได้ ไม่ต้องมี Git ตอนติดตั้ง ตรวจทุกสกิลที่เลือกก่อนเริ่มเขียน ปฏิเสธไฟล์เดิม/ลิงก์/พาธซ้อน และย้อนคืนเฉพาะโฟลเดอร์ใหม่เมื่อคัดลอกล้มเหลว

```sh
python -B scripts/install_skills.py --list
python -B scripts/install_skills.py --all --destination ../my-project/.agents/skills --dry-run
python -B scripts/install_skills.py --all --destination ../my-project/.agents/skills
```

## การตรวจจริง

Python 3.12.14 / PowerShell 7.4.13 บน Linux:

| ชุดทดสอบ | จำนวน |
| --- | ---: |
| Installer และ release tools | 24 |
| ARB workbench และ CLI lifecycle | 29 |
| Windows toolkit | 38 |
| Media script / 9 mock scenarios | 2 |
| RangeTotals | 10 |
| ValueScanLab | 52 |
| รวม | 155 |

ผล local: ผ่าน 154 รายการ ข้าม Windows GUI บน Linux 1 รายการ ไม่พบ test failure การตรวจจากแพ็กเกจที่แตกแล้วผ่านเช่นกัน รวมการติดตั้งทั้งหกสกิลจาก bundle และจาก ZIP รายสกิล การเรียก CLI help/version และการรัน ARB lifecycle จาก standalone installation อีกหนึ่งครั้ง

สร้าง release directory ซ้ำสองครั้งจาก source bytes เดียวกัน พบว่า ZIP ทั้งเจ็ด manifest และ SHA256SUMS เหมือนกันทุก byte

คำสั่งตรวจรวมและแพ็กเกจ:

```sh
python -B scripts/check_repo.py --test
python -B scripts/build_release.py --output-dir dist/2.2.0
python -B scripts/verify_release.py --release-dir dist/2.2.0 --smoke
```

ตัวตรวจแพ็กเกจเปรียบเทียบ hash และรายการไฟล์จริง ตรวจว่า ZIP รายสกิลตรงกับ source ปฏิเสธ path traversal, symbolic link, Windows device names และชื่อชนกัน จากนั้นติดตั้งทั้ง bundle และ ZIP รายสกิลในพื้นที่ชั่วคราวที่มีช่องว่างใน path เรียก help/version ของ toolkit ที่ติดตั้งจริง รันวงจร CLI ของ ARB จาก standalone installation และรันชุดทดสอบจาก source ที่แตกแพ็กเกจแล้ว

ตัวตรวจนโยบายผ่านเมื่อไม่มีภาษาไทยในไฟล์โค้ด/config และ fenced code blocks คำอธิบายภาษาไทยอยู่ภายนอกโค้ด ผล CI ของ commit สุดท้ายให้ตรวจใน PR และ run บน main หลัง merge โดยอ้างอิง SHA ที่ตรงกัน

## ปัญหาที่แก้

- `evidence --file` เดิมเทียบ path ตรงตัว จึงไม่พบไฟล์เมื่อใส่ `./` หรือ native Windows separators ปรับเป็นรูปแบบ inventory ก่อนเทียบและมี CLI lifecycle test จาก installed skill
- PowerShell อาจยก error สำหรับ `robocopy` exit 1 ทั้งที่คัดลอกสำเร็จ เมื่อเปิด native error preference ปรับนโยบายเฉพาะในฟังก์ชันคัดลอกและยังตรวจ exit 8 ขึ้นไป โดยไม่เปลี่ยนค่าของ caller
- การแจก ZIP เดี่ยวและการตรวจ manifest ช่วยตรวจ runtime ตกหล่น/สกิลไม่ครบก่อนส่งมอบ ไม่อ้างว่าการมี checksum รับรองผู้สร้างหรือความถูกต้องของทุกพฤติกรรม

## ขอบเขต

การตรวจโครงสร้างและติดตั้งสกิลที่เป็นคำสั่ง AI ไม่เท่ากับการเรียกใช้งานผ่าน AI host ทุกชนิด สี่สกิลเป็น workflow ส่วนสอง reconstruction toolkits มี executable CLI ที่ทดสอบได้จริง ต้องเปิดแชตใหม่หรือเริ่ม Codex ใหม่หลังติดตั้งตาม host ที่ใช้

บน Linux ข้าม GUI smoke ของ Windows หนึ่งรายการ CI บน Windows บังคับทดสอบ GUI จริง ส่วน media tests ใช้ mocks; ยังไม่ได้รัน DISM, mount ISO, แบ่ง WIM หรือเขียน USB จริง ไม่รับรองว่าทดสอบ mocks แล้วเท่ากับทดสอบ media ทั้งหมด

รูปแบบ contract ยังเป็น ARB schema 2 และ Windows toolkit schema 1 แยกกัน Python ขั้นต่ำยังเป็น 3.10
