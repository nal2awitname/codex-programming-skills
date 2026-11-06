# บันทึกการสร้าง ValueScanLab

วันที่ตรวจ: 2026-11-06

## Inputs และขอบเขตจริง

- Builder รับเฉพาะ task, audited `contract.json`, `BUILDER.md`, `manifest.json` และคำแนะนำ skill สำหรับการสร้างใหม่จากพฤติกรรม
- ไม่ได้รับ ไม่เปิด ไม่ค้นหา และไม่รัน source, binary, tests, assets หรือ report ของโปรแกรมอ้างอิง ตัวตน/เวอร์ชันของ artifact อ้างอิงจึงไม่ทราบใน builder context นี้
- Context นี้ไม่เคยเห็น implementation อ้างอิง การแยกทำโดยคำสั่ง allowlist และแยกโฟลเดอร์ข้อมูลเท่านั้น filesystem ใช้ร่วมกันและไม่มี access isolation ที่บังคับจริง ไม่อ้างว่าเป็น enforced clean room
- ไฟล์ที่เขียนและ temporary files ของ tests อยู่ภายในโปรเจกต์นี้ ไม่มี reference runtime dependency, external process attachment, network operation หรือ target process อื่น
- โปรแกรมและ tests เขียนใหม่จากคุณสมบัติใน contract และ synthetic scenarios ไม่ใช่การสร้าง source เดิมกลับคืน

## Contract และ dependencies

`docs/contract.json` เป็นสำเนาทุก byte จาก audited handoff ตรวจ SHA-256 ก่อนนำมาใช้และมี test ป้องกันการแก้โดยเงียบ:

```text
c24796ad9fe73b97caba1a0175957f02ed66ab7925d21e9818ce442762a4c58a
```

กำหนด `docs/contract.json text eol=lf` ใน `.gitattributes` เพื่อให้ checkout บน Windows ที่เปิด `core.autocrlf` ยังคง byte hash เดิม การตรวจ hash ไม่ได้ถูกลดความเข้มงวด

Contract ระบุ 9 requirements และ 22 synthetic acceptance cases โดย cases เป็น **proposed** acceptance expectations ไม่ใช่ผลรันโปรแกรมอ้างอิง `compatibility_literals` ของ contract ว่าง ชื่อ JSON actions/modes/errors, fixture และ signed 32-bit/offset conventions คงไว้เพราะเป็น interface ของ lab ฉบับใหม่นี้ ไม่มีข้ออ้างว่าตรง interface ของโปรแกรมอ้างอิง

Runtime ใช้ Python 3.10+ standard library เท่านั้น ไม่มี third-party package, original assets หรือ binary ที่ bundle เพิ่ม GUI ต้องมี Tkinter/Tcl/Tk และ desktop จริง Imports ตรวจจาก AST ของไฟล์ใหม่แล้ว: runtime ใช้ `argparse`, `ctypes`, `json`, `pathlib`, `sys`, `tkinter` และ modules ภายในโปรเจกต์; tests เพิ่ม `copy`, `hashlib`, `os`, `subprocess`, `tempfile`, `unittest` และ test module ภายใน ไม่มี symlinks ในไฟล์ Python ที่ตรวจ

## แบบใหม่ที่เลือก

- `OwnedIntBuffer` เก็บ bytes ด้วย ctypes allocation ของ instance เอง อ่าน/เขียน 4 bytes หลังตรวจ index และ signed integer ก่อนใช้ pointer ทุกครั้ง กำหนด byte order ชัดเจนโดยไม่อาศัย native integer layout
- `Scanner` แยกสถานะยังไม่เริ่มจาก candidate set ว่าง เก็บ slot และค่าของสแกนที่สำเร็จครั้งล่าสุด Refinement ผ่าน candidates เดิมตามลำดับ offset และอัปเดต baseline เมื่อสแกนสำเร็จเท่านั้น
- Scenario แต่ละครั้งมีบัฟเฟอร์ใหม่ จึงไม่แก้ input และไม่แชร์ state ข้ามการเรียก History เป็น snapshots แยกจาก scan state
- Tkinter ใช้ domain engine เดียวกับ CLI ปุ่ม Lower sample เปลี่ยนเฉพาะ slot 2 จำนวน −17 การ refresh ตารางอ่านค่าปัจจุบันโดยไม่เลื่อน baseline; Restart สร้าง fixture ใหม่และล้างผล
- การตรวจ fields เกิน/fields ที่ขาดและชื่อ errors สำหรับ I/O เป็นข้อกำหนด adapter ที่เลือกใหม่และอธิบายใน README โดยไม่แก้ audited contract

## Requirement → การตรวจ

| Requirement | Component | Acceptance cases | ผลที่รันบน host นี้ |
| --- | --- | --- | --- |
| REQ-001 initial exact | `core.Scanner` | 001, 019 | ผ่าน |
| REQ-002 candidate refinement | `core.Scanner` | 001, 002, 019 | ผ่าน |
| REQ-003 previous completed scan | `core.Scanner` | 003–006, 021 | ผ่าน พร้อม baseline/state tests |
| REQ-004 initial unknown | `core.Scanner` | 003, 008 | ผ่าน |
| REQ-005 int32/offset/type | `core.OwnedIntBuffer` | 007, 008, 010–012, 017, 020, 022 | ผ่าน พร้อม raw bytes/index/write tests |
| REQ-006 lifecycle/modes/reset | `core.Scanner` | 009, 013–015, 018 | ผ่าน พร้อม failed-operation/state tests |
| REQ-007 owned demo buffer | `core`, `scenario` | 001, 016 | ผ่าน; memory addresses derive จาก allocation ของ object |
| REQ-008 scenario CLI | `cli`, `scenario` | 001 และ error cases | ผ่าน รวม subprocess CLI 7 tests |
| REQ-009 desktop | `gui` | 001 + Windows button smoke | เขียนแล้ว; GUI smoke skip บน Linux ยังไม่ยืนยัน Windows runtime |

หมายเลข cases ข้างต้นตรงกับ `CASE-` ใน contract ทุก case มี unittest ที่เขียน assertions แยกใน `tests/test_acceptance.py` ไม่โหลด expected จาก contract มาเป็น implementation

## คำสั่งและผลที่รันจริง

สภาพแวดล้อม: Python **3.12.14**, Linux x86_64, kernel 6.18.57, glibc 2.39

```sh
python3 scan_lab.py --demo
python3 -m unittest discover -s tests -v
```

- Demo exit **0**: history แรก offsets `[0,8,16]` values `[137,137,137]`; history ที่สอง offset `[8]` value `[120]`
- Suite exit **0**, **51 tests**, **50 ผ่าน**, **1 skipped** ข้อความ skip: `Windows-only GUI smoke: host linux has no Windows desktop/display; not exercised`
- ทดสอบ JSON scenario ผ่าน subprocess จริง รวม malformed JSON, invalid schema/value, missing file และ UTF-8 ที่อ่านไม่ได้; error ทุกกรณีที่ทดสอบได้ named JSON และ nonzero exit ตามกำหนด
- ตรวจ input ทั้ง 22 cases จากสำเนา contract กับ evaluator อีกครั้ง ทุก actual output ตรง expected; การตรวจนี้เป็น contract consistency ของโปรแกรมใหม่ ไม่มี reference capture

ตรวจ negative gate ของ Windows GUI ด้วยคำสั่งต่อไปนี้บน Linux:

```sh
VALUE_SCAN_REQUIRE_GUI=1 python3 -m unittest discover -s tests -p test_gui_windows.py -v
```

ได้ exit **1**, test **FAIL** ตามตั้งใจ เพราะไม่มี Windows desktop/display แสดงว่าเมื่อบังคับ GUI แล้วจะไม่รายงาน skip แทนการทดสอบจริง ผลนี้ไม่ใช่ GUI pass และไม่ใช่ข้อผิดพลาดของ suite ปกติ

Windows smoke ที่เตรียมไว้สร้าง `Tk()`, เรียก `update()`, กดปุ่ม Initial/Lower/Refine/Restart ด้วย `invoke()`, ตรวจสาม matches ของ 137 เหลือ offset 8 ค่า 120 และตรวจคืน fixture แล้ว `destroy()` ใน `finally` หากสร้าง Tk ไม่ได้จะ skip ตามจริง หรือ fail เมื่อ `VALUE_SCAN_REQUIRE_GUI=1`

## ข้อจำกัด

บันทึกระยะสร้างนี้ทดสอบเฉพาะ Linux/Python 3.12 ผล Windows/Python 3.10 และ GUI button smoke ที่เพิ่มภายหลังให้ตรวจใน [workflow](https://github.com/nal2awitname/codex-programming-skills/actions/workflows/value-scan-lab.yml) ไม่ใช้ผล Linux ยืนยัน desktop behavior ยังไม่ครอบคลุม visual layout ทุกสภาพแวดล้อม, installer/EXE packaging หรือความเทียบเท่ากับ binary/version อ้างอิงใด ๆ ขอบเขตจำกัด signed 32-bit aligned slots ในบัฟเฟอร์ตัวเอง ไม่มีฟังก์ชันนอก contract เช่น driver, injection, debugger, freezing หรือ pointer scan
