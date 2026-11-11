# ผลตรวจรุ่น 2.1.0

วันที่ 11 พฤศจิกายน 2026 เริ่มพัฒนาจาก commit `4e9f1825c7000a698aa3cdb788aca644b0a0e960` ของ `nal2awitname/codex-programming-skills` ดูการเปลี่ยนแปลงใน [CHANGELOG](../CHANGELOG.md)

## ผลที่รันจริงในสภาพแวดล้อมนี้

ระบบ Linux, Python 3.12.14, PowerShell 7.4.13 โดยเพิ่มตำแหน่ง `pwsh` ใน PATH:

```sh
python -B scripts/check_repo.py --test
```

| ชุดทดสอบ | จำนวน | ผล |
| --- | ---: | --- |
| Repository/release tools | 7 | ผ่านทั้งหมด |
| ARB workbench | 26 | ผ่านทั้งหมด รวม PowerShell parser/wrapper |
| Windows behavior toolkit | 38 | ผ่านทั้งหมด รวม PowerShell wrapper |
| Windows media script | 2 | ผ่านทั้งหมด รวม 8 สถานการณ์ mock |
| RangeTotals example | 10 | ผ่านทั้งหมด |
| ValueScanLab example | 52 | ผ่าน 51; ข้าม Windows GUI 1 |
| รวม | 135 | ผ่าน 134; ข้าม 1; ไม่พบ test failure |

ตรวจ metadata/ชื่อสกิล ลิงก์อ้างอิงภายในสกิล syntax Python และเลขเวอร์ชันทั้งสอง toolkit ผ่าน `git diff --check` ผ่าน ตรวจ release ZIP สองครั้งจาก source bytes เดียวกันให้ SHA-256 ตรงกันและไม่มีไฟล์ untracked รวมอยู่ ทดสอบเปิด `--help`/`--version` จากสกิลที่แตก ZIP แล้วได้ และตัวอย่าง ValueScanLab `--demo` รันสำเร็จ

## ปัญหาที่แก้พร้อม regression tests

- ARB: JSON key ซ้ำและตัวเลข infinity/overflow เคยทำให้เปรียบเทียบผลที่กำกวมได้; ผลจับข้อมูลที่จบเพราะหยุดโปรเซสลูกต้องถือว่าไม่ครบ; ผล verify ต้องหมดอายุเมื่อ observations หรือต้นฉบับเปลี่ยน
- Windows toolkit: JSONL ที่ record สุดท้ายไม่มี newline ทำให้ record ใหม่ต่อกันจนเสีย; Unicode line separator ภายใน string ต้องไม่ถูกแยกเป็น record ใหม่
- ValueScanLab: จำนวนเต็มที่เกินขีดจำกัด Python ต้องคืน error JSON ตามรูปแบบ CLI แทน traceback
- Media script: ป้องกันโฟลเดอร์ปลายทางซ้อนต้นทาง/ลิงก์ ป้องกัน mount ระหว่าง WhatIf รักษา ISO ที่ผู้ใช้ mount ไว้ และเลือก architecture/index จากอิมเมจจริง พร้อมปฏิเสธ source image ที่กำกวมหรือ export เดิม
- Release tooling: ไม่เขียนทับปลายทาง ตรวจไฟล์บังคับและลิงก์หาย ปฏิเสธ tracked symlink และไฟล์รุ่นใหม่ที่ยังไม่ track ก่อนสร้าง ZIP

## ข้อจำกัดและการตรวจต่อ

ยังไม่ได้รัน GUI Windows, DISM, mount ISO จริง หรือเขียน USB จริงในสภาพแวดล้อมนี้ การทดสอบ media ใช้ PowerShell 7 กับ Windows command mocks; การเพิ่ม BOM ช่วยการอ่าน source ใน PowerShell 5.1 แต่ไม่ใช่ผลยืนยันการทำงานทั้งหมดบน 5.1

CI ใหม่ตั้งให้ตรวจ Ubuntu/Windows/macOS ด้วย Python 3.10/3.12 รวม Windows GUI, launcher และ installer และเก็บ ZIP/checksum เป็น artifact ผล CI ต้องตรวจจาก run ของ commit ที่ส่งขึ้นจริง เอกสารนี้บันทึกผล local ข้างต้น ไม่อ้างว่า matrix ผ่านแล้ว

รูปแบบ contract ไม่เปลี่ยน: ARB schema 2 และ Windows toolkit schema 1 แยกกัน ผู้ใช้ workspace ARB เดิมควรรัน `verify` อีกครั้งเพื่อบันทึก hash ของ observations รุ่นนี้ไม่รับรองความเทียบเท่าของโปรแกรมเป้าหมายใดจากการผ่าน tests ของ toolkit
