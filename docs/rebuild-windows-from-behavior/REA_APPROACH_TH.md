# นำแนวทาง REA มาใช้กับการสร้างโปรแกรมใหม่

อ้างอิง [โปรเจกต์ rea ของผู้ใช้](https://github.com/nal2awitname/rea) ที่ commit `d3ab0faf52a02ff5a618f3ed7beb608b78752abd` ซึ่ง manifest ระบุแพ็กเกจ 6.8.0 นำกระบวนการสำรวจและตรวจหลักฐานมาปรับใช้กับสกิล `rebuild-windows-from-behavior` โดยยังห้ามคัดลอกหรือแปลโค้ดต้นฉบับเข้าสู่โปรแกรมใหม่

## แนวทางที่เพิ่มแล้ว

| หลักจาก REA | สิ่งที่ใช้ในงานนี้ |
| --- | --- |
| เลือกเป้าหมายจริงก่อนเครื่องมือ | ระบุไฟล์ รุ่น และ digest ของต้นฉบับ แยกจากไฟล์ metadata และโปรแกรมตัวอย่าง |
| ตั้งคำถามก่อนขยายการวิเคราะห์ | แยก First Scan, Next Scan, baseline/state, error, cancellation และ side effects พร้อมหลักฐานที่แต่ละคำถามต้องใช้ |
| เลือกเครื่องมือจากชนิด artifact และความพร้อมจริง | ตรวจ directory/PE/managed/Electron ตามข้อมูลที่พบ ใช้ schema ของเครื่องมือที่มีจริง |
| รักษาหลักฐานและขอบเขต | บันทึกแหล่งที่มา ความครบถ้วน ข้อจำกัด และคำถามที่ยังตอบไม่ได้ ใช้ retained parent evidence เมื่อรองรับ |
| แยก static กับ runtime | เอกสาร, imports, pseudocode และ analysis-memory bytes ไม่ใช่การสังเกตว่าโปรแกรมรันอย่างไร |
| ตรวจตาม OS และ provider | Windows Ghidra เป็นเส้นทาง static; native UI ในคู่มือ REA ที่อ่านเป็น macOS และ process capture ใหม่เป็น Linux/macOS |
| ตรวจความเทียบเท่าเป็นรายข้อ | เปรียบเทียบ reference/candidate captures ของกรณีเดียวกัน ผลจำนวนจำกัดไม่ยืนยันทุกฟังก์ชัน |
| แยกผู้วิเคราะห์กับผู้สร้าง | เก็บผลถอดรหัสและรายละเอียดภายในไว้ฝั่งวิเคราะห์ ส่งเฉพาะ contract และข้อมูลสังเคราะห์ที่ตรวจแล้วให้ผู้เขียนใหม่ |

แนวทางฉบับใช้งานในสกิลอยู่ที่ [rea-investigation.md](../../skills/rebuild-windows-from-behavior/references/rea-investigation.md) REA เป็นโครงการ MIT โดย morluto และผู้ใช้มี fork; การปรับครั้งนี้เพิ่มคำแนะนำโดยไม่ bundle โค้ด REA หรือแก้ repository `rea`

## สถานะ Cheat Engine ตามแนวทางนี้

| คำถาม | หลักฐานปัจจุบัน | สถานะ |
| --- | --- | --- |
| ชุดสร้าง/ตัวบ่งชี้ภาษาอะไร | README และ Lazarus metadata ที่ตรวจไว้ สนับสนุน Object Pascal/Delphi mode | ตอบได้บางส่วน; ยังไม่ผูกกับ binary รุ่นใด |
| ไฟล์ executable รุ่นใด และ hash อะไร | ยังไม่ได้รับ executable ต้นฉบับ | ยังไม่ทราบ |
| First Scan/Next Scan ของต้นฉบับทำงานจริงอย่างไร | มีเอกสารทางการ; ยังไม่มี capture จาก Cheat Engine จริง | ยังไม่ยืนยัน runtime |
| ValueScanLab ทำงานตามข้อกำหนดของตัวอย่างหรือไม่ | 22 กรณีสังเคราะห์และ GUI smoke ของตัวอย่างผ่าน Windows CI | ยืนยันเฉพาะตัวอย่าง |
| ตัวอย่างเทียบเท่า Cheat Engine หรือไม่ | ยังไม่มี reference/candidate comparison จากต้นฉบับ | ยังยืนยันไม่ได้ |

ดู [การทดลองเดิม](../cheat-engine-case-study/ANALYSIS_TH.md) และ [แผนตรวจจริง](../cheat-engine-case-study/rea-investigation.json) ไฟล์ JSON เป็นบันทึกสถานะและงานถัดไปของโครงการนี้ เมื่อลงมือเรียก REA ให้ยึด schema/CLI help ของรุ่นที่ติดตั้ง

## ขั้นตอนถัดไปที่เตรียมไว้

1. รับไฟล์ Cheat Engine หรือโฟลเดอร์ติดตั้งของรุ่นที่ต้องการตรวจ เก็บสำเนาต้นฉบับและคำนวณ identity ตาม bytes จริง
2. ตรวจ REA MCP ที่เชื่อมอยู่ หรือ CLI ที่ติดตั้งจริง พร้อม provider ที่รองรับชนิดไฟล์ การเชื่อม GitHub และการมีสกิลไม่ยืนยันว่า REA engine พร้อมใช้งาน
3. เริ่มจาก inventory/PE facts แล้วค่อยลงฟังก์ชันหรือ state ที่ตอบคำถามสแกนค่า โดยรักษา raw decompilation ไว้เฉพาะฝั่งวิเคราะห์
4. เก็บการทดลองต้นฉบับบน Windows ด้วยข้อมูลสังเคราะห์และ adapter ที่มีจริง บันทึก input/actions/output/errors/สถานะก่อนหลังและการ cleanup ให้แยกจากการทดสอบ ValueScanLab
5. ปรับ contract ตามหลักฐานจริง ตรวจว่าไม่มีโค้ดหรือโครงสร้างภายในต้นฉบับ แล้วให้ผู้เขียนใหม่ปรับ implementation และเปรียบเทียบกรณีที่ตรวจได้

ทบทวนสถานะล่าสุดเมื่อ 10 พฤศจิกายน 2026: สภาพแวดล้อมที่ตรวจคือ executor Linux, Node 24.22.1; ไม่พบ REA MCP tools ในเซสชันหรือ `rea` CLI บน PATH ข้อมูลนี้ไม่ใช่การตรวจเครื่อง Windows ของผู้ใช้ และไม่ได้ติดตั้งหรือเปลี่ยน client configuration

## แหล่งแนวทางที่อ่าน

- [Workflow หลักของ REA](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/.agents/skills/reverse-engineer-anything/SKILL.md)
- [Evidence และ finite verification](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/.agents/skills/reverse-engineer-anything/references/evidence-workflows.md)
- [Runtime และขอบเขต OS](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/.agents/skills/reverse-engineer-anything/references/runtime-observation.md)
- [Desktop installation inventory](https://github.com/nal2awitname/rea/blob/d3ab0faf52a02ff5a618f3ed7beb608b78752abd/docs/desktop-applications.md)

ตรวจเฉพาะการปรับเอกสารและ workflow: skill validation ผ่าน และทดลองให้บริบทใหม่จัดทำแผนจากข้อมูลที่มีจริง โดยไม่ติดตั้งหรือรันต้นฉบับ ไม่มีการเปลี่ยน runtime code ของเครื่องมือหรือ ValueScanLab ในรอบนี้
