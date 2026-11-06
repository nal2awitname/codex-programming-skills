# ValueScanLab

ห้องทดลองค้นหาค่าในบัฟเฟอร์ที่โปรแกรมจัดสรรเองด้วย `ctypes` ใช้ Python 3.10+ และ standard library เท่านั้น GUI ใช้ Tkinter และต้องมี desktop/display

เปิด terminal ในโฟลเดอร์นี้แล้วรัน:

```sh
python scan_lab.py --demo
python scan_lab.py --scenario examples/demo.json
python scan_lab.py
python -m unittest discover -s tests -v
```

คำสั่งที่ไม่มี arguments เปิด GUI ส่วน `--demo` และ `--scenario` ส่ง JSON ทาง stdout; สำเร็จ exit 0 และ scenario ผิดพลาด exit 1

ตัวอย่างเริ่มจาก `[137,20,137,-3,137,0]`: ค้นหา exact `137` ได้ offsets `[0,8,16]` แก้ slot 2 เป็น `120` แล้ว refine exact `120` เหลือ offset `[8]` ค่า `[120]`

ใน GUI กด **Initial search → Lower sample (−17)** เปลี่ยน Search value เป็น `120` แล้วกด **Refine**; **Restart** คืนค่าตั้งต้นและล้างผล

## Scenario JSON

ใช้รูปแบบใน [examples/demo.json](examples/demo.json): top-level มี `initial` เป็น array ของ integers และ `steps` เป็น array ของ actions

| Action | Fields | ผล |
| --- | --- | --- |
| `first` | `mode: exact`, `value` | ค้นหาค่าเท่ากันในทุก slot |
| `first` | `mode: unknown` | เก็บทุก slot |
| `next` | `mode: exact`, `value` | กรองเฉพาะผลเดิมที่ตรงค่า |
| `next` | `mode: changed/unchanged/increased/decreased` | เทียบกับค่าจากสแกนที่เสร็จครั้งก่อน |
| `set` | `index`, `value` | เปลี่ยนค่าของ slot ตาม index เริ่มที่ 0 |
| `reset` | ไม่มี fields เพิ่ม | ล้างสถานะสแกน ค่าบัฟเฟอร์ยังอยู่ |

แต่ละ slot เป็น signed 32-bit little-endian; byte offset = index × 4 และผลเรียง offset ขึ้น `increased/decreased` ใช้มากกว่า/น้อยกว่าแบบเคร่งครัด `first` ใหม่เริ่มค้นหาทั้งบัฟเฟอร์อีกครั้ง

`history` บันทึกเฉพาะ `first/next` แต่ละรายการมี `offsets` และ `values` ณ ครั้งนั้น `set/reset` ไม่เพิ่มรายการ หากเกิด error จะคืนเพียง `{"error":"ชื่อข้อผิดพลาด"}`

| Error | ความหมาย |
| --- | --- |
| `invalid_value` | ไม่ใช่ integer จริง รวม boolean หรือเกินช่วง −2147483648 ถึง 2147483647 |
| `invalid_index` | index ไม่ใช่ integer จริงหรืออยู่นอกบัฟเฟอร์ |
| `invalid_mode` | mode ไม่รองรับสำหรับขั้นนั้น |
| `scan_not_started` | refine ก่อน first หรือหลัง reset |
| `invalid_scenario` | โครงสร้าง/ชื่อ action/fields ไม่ถูกต้อง |
| `invalid_json`, `io_error` | JSON เสีย หรืออ่านไฟล์ UTF-8 ไม่ได้ |
| `gui_unavailable` | เปิด Tkinter/display ไม่ได้; CLI แจ้งทาง stderr |

การตรวจโครงสร้างเป็นกติกาของ lab นี้: ไม่รับ fields เกิน, exact ต้องมี `value`, modes อื่นไม่มี `value`

## ทดสอบ Windows GUI

ชุดทดสอบปกติจะ skip GUI ชัดเจนหากไม่มี Windows/Tkinter/display สำหรับ Windows runner ที่ต้องยืนยัน GUI จริง ให้ตั้งค่า PowerShell:

```powershell
$env:VALUE_SCAN_REQUIRE_GUI = '1'
python -m unittest discover -s tests -v
```

เมื่อค่านี้เป็น `1` การไม่มี Windows/Tkinter/display ทำให้ test fail ชุด smoke สร้างหน้าต่างจริง ใช้ `invoke()` กดปุ่มและ `update()` ตรวจ `137 → 120` จากนั้น Restart และ `destroy()`

ผลระยะสร้างบน Linux / Python 3.12.14: **51 tests, ผ่าน 50, skip Windows GUI 1**; acceptance scenarios ทั้ง 22 ผ่านครบ ผลของ Windows/Python 3.10 และ 3.12 หลังเผยแพร่ตรวจได้จาก [GitHub Actions](https://github.com/nal2awitname/codex-programming-skills/actions/workflows/value-scan-lab.yml) ซึ่งบังคับ GUI test บน Windows ให้ fail หากสร้างหน้าต่างไม่ได้ ดู [บันทึกการสร้างและตรวจสอบ](docs/BUILD_RECORD.md)

ตัวอย่างนี้เป็นกรณีศึกษาจากเอกสารและข้อมูลโครงการของ Cheat Engine ไม่ได้รันหรือวัดเทียบกับ Cheat Engine ตัวจริง รายละเอียดภาษา หลักฐาน และขอบเขตอยู่ใน [รายงานการทดลอง](../../docs/cheat-engine-case-study/ANALYSIS_TH.md)

## ส่วนประกอบและพัฒนาต่อ

| ไฟล์ | หน้าที่ |
| --- | --- |
| `scan_lab.py`, `valuescanlab/cli.py` | entrypoint, JSON/ไฟล์และ exit status |
| `valuescanlab/core.py` | owned allocation, validation, candidates และค่าจากสแกนก่อน |
| `valuescanlab/scenario.py` | scenario actions และ demo |
| `valuescanlab/gui.py` | Tkinter และปุ่มสำหรับบัฟเฟอร์ตัวอย่าง |
| `tests/` | 22 acceptance cases, type/state, CLI, contract hash, Windows GUI |
| `docs/contract.json` | สำเนา audited contract ตรงกับ handoff ทุก byte |

หากเพิ่มพฤติกรรม ให้จัดทำ contract ฉบับใหม่ที่ตรวจแล้ว เพิ่ม acceptance case และอัปเดต contract hash test ก่อนเปลี่ยน component ที่เกี่ยวข้อง แล้วรันคำสั่งทดสอบเดิม

Builder ได้รับเฉพาะ contract และคำแนะนำ handoff ใหม่ ไม่เห็น source อ้างอิงและไม่ได้รันโปรแกรมอ้างอิง งานนี้แยกข้อมูลตามคำสั่งบน filesystem ที่ใช้ร่วมกัน ไม่มี filesystem isolation ที่บังคับจริง ผลทดสอบแสดงการผ่าน contract ของ lab เท่านั้น
