# RangeTotalsCLI

CLI สรุปรายการจำนวนเต็ม: จำนวนสมาชิก (`count`), ช่วงค่าสูงสุดลบต่ำสุด
(`span`) และผลรวม (`total`) เขียนใหม่จากสัญญาพฤติกรรม โดยใช้ Python 3.10+
และ standard library เท่านั้น ไม่ต้องติดตั้งแพ็กเกจเพิ่ม

## รันบน Windows

เปิด **Command Prompt (cmd.exe)** ในโฟลเดอร์นี้ โดยติดตั้ง Python และคำสั่ง `py` ไว้แล้ว:

```bat
range_totals.cmd "{\"values\": [6, 2, 9]}"
```

หรือเรียก Python ตรง:

```bat
py -3 range_totals.py "{\"values\": [6, 2, 9]}"
```

ผลลัพธ์:

```json
{"count":3,"span":7,"total":17}
```

ตัวอย่างข้างต้นใช้กฎการใส่เครื่องหมายคำพูดของ **cmd.exe** ส่วนการเรียกจาก
โปรแกรมอื่นให้ส่ง JSON เป็น argument เดียว รายการว่างคืน `span: null`
โปรแกรมอ่านเฉพาะ argument แรกและละ argument ที่เหลือตามสัญญา

บน Linux/macOS:

```sh
python3 range_totals.py '{"values":[6,2,9]}'
```

## รูปแบบข้อมูล

object ต้องมี property `values` เพียงตัวเดียว และเป็น array ของจำนวนเต็ม
ไม่รับ Boolean, ทศนิยม, null หรือข้อความเป็นสมาชิก ผลข้อผิดพลาดยังออกทาง
stdout เป็น JSON และ exit status เท่ากับ 0:

| กรณี | ค่า `error` |
| --- | --- |
| ไม่มี argument หรือ JSON อ่านไม่ได้ | `invalid_json` |
| โครงสร้าง object ผิดหรือมี property เกิน | `invalid_request` |
| `values` หรือสมาชิกไม่ใช่รายการจำนวนเต็ม | `integer_list_required` |

## ทดสอบและพัฒนาต่อ

```bat
py -3 -m unittest discover -s tests -v
```

Linux ใช้ `python3 -m unittest discover -s tests -v`

ตรวจแล้วบน Linux / Python 3.12.14: acceptance 29 กรณีและ property tests 9 ข้อผ่าน
ผลเทียบกับโปรแกรมอ้างอิงที่เรียกแยกกันตรงทั้งหมด 29 กรณีตามสัญญาและอีก 109 กรณี
ชุดเพิ่มเติมที่เทียบกับโปรแกรมอ้างอิงรันบน Linux ส่วนการทดสอบ candidate บน
Windows, Linux และ macOS รวม launcher `.cmd` บน Windows อยู่ใน
[GitHub Actions](https://github.com/nal2awitname/codex-programming-skills/actions/workflows/windows-behavior-rebuild.yml)
ให้ดูผลของ commit ล่าสุด ไม่ได้ส่งมอบไฟล์ EXE หรือ installer

- [สัญญาพฤติกรรม](docs/behavior-contract.md) และ [ข้อมูลทดสอบ](docs/contract.json)
- [แผนที่ส่วนประกอบ](docs/components.md)
- [ผลการตรวจ](docs/verification.md)
- [บันทึกการสร้างใหม่](docs/reconstruction-record.md)
