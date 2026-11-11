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
| ARB workbench | 28 | ผ่านทั้งหมด รวม PowerShell parser/wrapper |
| Windows behavior toolkit | 38 | ผ่านทั้งหมด รวม PowerShell wrapper |
| Windows media script | 2 | ผ่านทั้งหมด รวม 8 สถานการณ์ mock |
| RangeTotals example | 10 | ผ่านทั้งหมด |
| ValueScanLab example | 52 | ผ่าน 51; ข้าม Windows GUI 1 |
| รวม | 137 | ผ่าน 136; ข้าม 1; ไม่พบ test failure |

ตรวจ metadata/ชื่อสกิล ลิงก์อ้างอิงภายในสกิล syntax Python และเลขเวอร์ชันทั้งสอง toolkit ผ่าน `git diff --check` ผ่าน ตรวจ release ZIP สองครั้งจาก source bytes เดียวกันให้ SHA-256 ตรงกันและไม่มีไฟล์ untracked รวมอยู่ ทดสอบเปิด `--help`/`--version` จากสกิลที่แตก ZIP แล้วได้ และตัวอย่าง ValueScanLab `--demo` รันสำเร็จ

## ปัญหาที่แก้พร้อม regression tests

- ARB PowerShell wrapper: รองรับหลาย Python executable ใน PATH โดยตรวจทีละ executable แทนการเรียก array ของ paths ซึ่งล้มบน CI ที่มี Python หลายตัว
- ARB command freshness: hash ไฟล์คำสั่งก่อนโหลดและรัน เพื่อไม่ให้โปรแกรมเปลี่ยนไฟล์คำสั่งระหว่างจับผลแล้วผลเดิมยังถูกมองว่าเป็นปัจจุบัน
- ARB: JSON key ซ้ำและตัวเลข infinity/overflow เคยทำให้เปรียบเทียบผลที่กำกวมได้; ผลจับข้อมูลที่จบเพราะหยุดโปรเซสลูกต้องถือว่าไม่ครบ; ผล verify ต้องหมดอายุเมื่อ observations หรือต้นฉบับเปลี่ยน
- Windows toolkit: JSONL ที่ record สุดท้ายไม่มี newline ทำให้ record ใหม่ต่อกันจนเสีย; Unicode line separator ภายใน string ต้องไม่ถูกแยกเป็น record ใหม่
- ValueScanLab: จำนวนเต็มที่เกินขีดจำกัด Python ต้องคืน error JSON ตามรูปแบบ CLI แทน traceback
- Media script: ป้องกันโฟลเดอร์ปลายทางซ้อนต้นทาง/ลิงก์ ป้องกัน mount ระหว่าง WhatIf รักษา ISO ที่ผู้ใช้ mount ไว้ และเลือก architecture/index จากอิมเมจจริง พร้อมปฏิเสธ source image ที่กำกวมหรือ export เดิม
- Release tooling: ไม่เขียนทับปลายทาง ตรวจไฟล์บังคับและลิงก์หาย ปฏิเสธ tracked symlink และไฟล์รุ่นใหม่ที่ยังไม่ track ก่อนสร้าง ZIP

## ข้อจำกัดและการตรวจต่อ

การรัน local ไม่ได้ทดสอบ GUI Windows, DISM, mount ISO จริง หรือเขียน USB จริง การทดสอบ media ใช้ PowerShell 7 กับ Windows command mocks; การเพิ่ม BOM ช่วยการอ่าน source ใน PowerShell 5.1 แต่ไม่ใช่ผลยืนยันการทำงานทั้งหมดบน 5.1

CI ตรวจ Ubuntu/Windows/macOS ด้วย Python 3.10/3.12 รวม Windows GUI, launcher และ installer และเก็บ ZIP/checksum เป็น artifact [รอบที่แก้ PATH/macOS แล้ว](https://github.com/nal2awitname/codex-programming-skills/actions/runs/42948600417) ผ่านครบ 6 jobs ที่ commit `1111b1d` สำหรับการแก้เพิ่มเติมให้ตรวจผล CI ของ commit ล่าสุดใน PR และบน main หลัง merge แยกจากผล local ด้านบน

รูปแบบ contract ไม่เปลี่ยน: ARB schema 2 และ Windows toolkit schema 1 แยกกัน ผู้ใช้ workspace ARB เดิมควรรัน `verify` อีกครั้งเพื่อบันทึก hash ของ observations รุ่นนี้ไม่รับรองความเทียบเท่าของโปรแกรมเป้าหมายใดจากการผ่าน tests ของ toolkit

## การตรวจ GitHub Actions เพิ่มเติม

[CI รอบแรก](https://github.com/nal2awitname/codex-programming-skills/actions/runs/42948247752) ยืนยัน Windows/Python 3.10 และ 3.12 ผ่าน รวม GUI จริงของ ValueScanLab, CMD launcher และการติดตั้งแบบ WhatIf/ไม่เขียนทับ แต่พบปัญหาบน Ubuntu/macOS เมื่อ PATH มี Python หลายตัว และ media fixture บน macOS ใช้ `/var` ที่เป็น symlink

แก้ resolver ให้ตรวจ Python ทีละ executable พร้อม regression test และเปลี่ยนเฉพาะ fixture ให้ใช้ physical temp path โดยรักษาการป้องกัน reparse ของ production script ผล CI ล่าสุดให้ตรวจจาก [PR #1](https://github.com/nal2awitname/codex-programming-skills/pull/1) ตาม commit สุดท้าย

คู่มือเริ่มพัฒนาต่อและคำสั่งตรวจแต่ละส่วนอยู่ใน [CONTRIBUTING_TH.md](../CONTRIBUTING_TH.md) คอมเมนต์ใกล้จุดแก้อธิบายสาเหตุของบั๊กและเหตุผลที่ต้องรักษาวิธีแก้นั้นไว้
