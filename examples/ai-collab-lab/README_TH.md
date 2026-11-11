# AI Collab Lab — ห้องจำลองให้ AI ทำงานร่วมกัน

AI Collab Lab คือโปรแกรม GUI บนเบราว์เซอร์ที่จำลอง "ออฟฟิศเสมือน" ให้ทีม AI หลายตัวสื่อสารและช่วยกันทำงานผ่านเครื่องมือชุดเดียวกัน มีห้องแชต ข้อความส่วนตัว บอร์ดงาน พื้นที่ไฟล์ คลังความรู้ กระดานข้อเท็จจริง และการโหวต คุณคุยกับทีมได้เหมือนเป็นหัวหน้างาน และใช้เครื่องมือเดียวกับที่ AI ใช้ได้ทุกตัว

- ใช้ Python 3.10 ขึ้นไป ไม่ต้องติดตั้งแพ็กเกจเพิ่มสำหรับโหมดออฟไลน์ หน้าเว็บไม่โหลดอะไรจากอินเทอร์เน็ต
- เอเจนต์มีสองแบบ: **SIM** (ทำงานตามบทบาทแบบออฟไลน์ ไม่ต้องใช้คีย์) และ **CLAUDE** (โมเดลจริงผ่าน Anthropic API)
- ทุกการกระทำของ AI ผ่านเครื่องมือ 30 ชนิด จึงเห็นย้อนหลังได้ทั้งหมดในแท็บ Activity

## เริ่มใช้งาน

**Windows:** ดับเบิลคลิก `start.cmd` ในโฟลเดอร์นี้ โปรแกรมจะเปิดเบราว์เซอร์ให้เอง

**ทุกระบบ:** เปิด terminal ในโฟลเดอร์นี้แล้วรัน

```sh
python collab_lab.py
```

หน้าเว็บอยู่ที่ `http://127.0.0.1:8765/` (ถ้าพอร์ตไม่ว่างจะเลื่อนไปพอร์ตถัดไปและพิมพ์ URL ให้) กด `Ctrl+C` ใน terminal เพื่อปิด

## ลองครั้งแรก

1. ในแท็บ **Chat** กดปุ่มตัวอย่าง เช่น "Build a temperature converter…" หรือพิมพ์คำขอเอง เป็นภาษาไทยก็ได้ เช่น "ช่วยสร้างโปรแกรมคำนวณภาษีมูลค่าเพิ่ม 7%"
2. Nova (ผู้ประสานงาน) แตกงานเป็น 5 การ์ดบนบอร์ด แล้วทีมส่งต่องานกันทีละ tick: Sage ค้นคว้า → Bolt เขียนโค้ด → Iris รีวิว และ Tess เขียนเทสต์ → Quill เขียนเอกสาร
3. เมื่อครบ Nova เปิดโหวต "Ship?" ให้ผู้รีวิวและผู้ทดสอบลงคะแนน แล้วเขียนรายงาน `reports/<ชื่องาน>.md` และแจ้งผลกลับมาในแชต
4. เปิดแท็บ **Files** ดูโค้ด เทสต์ เอกสาร และรายงานที่ทีมสร้าง แท็บ **Activity** ดูทุก tool call พร้อม arguments/ผลลัพธ์ และแท็บ **Network** ดูเส้นทางการสื่อสาร

ทั้งหมดนี้ใช้เวลาประมาณ 8 tick และไม่ต้องมี API key

## ส่วนต่าง ๆ ของหน้าจอ

| ส่วน | ใช้ทำอะไร |
| --- | --- |
| Team (ซ้าย) | การ์ดเอเจนต์พร้อมสถานะ (idle, working, thinking, waiting, error) กดการ์ดเพื่อแก้บทบาท สมอง โมเดล effort สี persona และสิทธิ์เครื่องมือ; ปุ่ม Nudge ปลุกเอเจนต์, DM เปิดแชตส่วนตัว |
| Chat | ช่อง `#general`, `#dev`, แชตส่วนตัวกับแต่ละเอเจนต์ และ "All traffic" ดูทุกข้อความรวมที่เอเจนต์คุยกันเอง; ลิงก์ไฟล์และเลขงาน (T-1) กดเปิดได้ |
| Tasks | บอร์ด To do / In progress / Review / Blocked / Done สร้างงานเอง เปลี่ยนผู้รับผิดชอบ สถานะ หรือเพิ่มโน้ตได้ |
| Files | พื้นที่ทำงานร่วมกัน ดูโค้ดพร้อมเลขบรรทัด ดูเอกสาร Markdown แบบจัดรูปแบบ แก้ไข/สร้าง/ลบไฟล์ในนามของคุณ |
| Activity | ไทม์ไลน์เหตุการณ์ทั้งหมด กรองตามชนิดหรือผู้กระทำได้ "Thoughts" คือคำอธิบายสั้น ๆ ของการตัดสินใจ |
| Network | กราฟว่าใครคุยกับใคร เส้นหนาตามปริมาณข้อความ ข้อความล่าสุดวิ่งเป็นจุด |
| Tools | ใช้เครื่องมือของเอเจนต์ด้วยตัวเองผ่านฟอร์มที่สร้างจาก schema และเห็นผลเป็น JSON |
| Knowledge | ค้นและอ่านคลังความรู้ เพิ่มโน้ตเพื่อสอนทีม |
| Overview / Polls / Blackboard (ขวา) | สถิติ งบการเรียก Claude ผลโหวต และข้อเท็จจริงที่ทีมแชร์กัน |
| แถบบน | Run / Pause / Step (ทีละ tick) / Reset, โหลดฉากจำลอง, ⚙ Settings (ความเร็ว ขีดจำกัด API key การรันโค้ด Export/Import) |

## ทีมเริ่มต้น

| เอเจนต์ | บทบาท | งานในโหมด SIM |
| --- | --- | --- |
| Nova | coordinator | รับคำขอ ค้นคลังความรู้ วางแผนงานพร้อม dependencies ติดตามงาน แจ้งเมื่อมีงานติดขัด เปิดโหวต และเขียนรายงาน |
| Sage | researcher | ค้นคลังความรู้ เขียน `notes/<งาน>-research.md` และประกาศ fact เช่น `<งาน>.recipe` |
| Bolt | coder | เขียน `src/<module>.py` จากสูตรในคลังความรู้ ตรวจด้วย `check_python` และแก้ตามที่รีวิวขอ |
| Iris | reviewer | ตรวจตาม checklist (docstring, TODO, ความยาวบรรทัด, tab, ช่องว่างท้ายบรรทัด) ขอแก้หรืออนุมัติ |
| Tess | tester | เขียน `tests/test_<module>.py` และรันจริงเมื่อเปิดสิทธิ์รันโค้ด ถ้าไม่เปิดจะบอกตรง ๆ ว่ายังไม่ได้รัน |
| Quill | writer | รวบรวมผลจากทีมเขียน `docs/<งาน>.md` |

คำสั่งพิเศษที่ Nova (SIM) เข้าใจ: `help`, `status` (ดูสถานะโปรเจกต์), `retry` (เริ่มงานที่ติดขัดใหม่) ข้อความอื่นถือเป็นคำขอใหม่ ส่งใน DM ถึง Nova หรือใน `#general` โดยไม่ mention ใคร

## เครื่องมือ 30 ชนิด

| หมวด | เครื่องมือ |
| --- | --- |
| communication | `send_message`, `read_messages`, `list_agents`, `list_channels`, `create_channel` |
| tasks | `create_task`, `update_task`, `list_tasks`, `get_task` |
| workspace | `write_file`, `append_file`, `read_file`, `list_files`, `delete_file`, `search_files` |
| knowledge | `search_knowledge`, `read_knowledge`, `add_knowledge`, `remember`, `recall`, `set_fact`, `get_facts` |
| decisions | `create_poll`, `vote`, `close_poll`, `list_polls` |
| utilities | `calculate` (คำนวณแบบปลอดภัย), `check_python` (ตรวจโค้ดโดยไม่รัน), `run_python` (ปิดไว้เป็นค่าเริ่มต้น), `get_status` |

ทุกเครื่องมือตรวจ argument ตาม schema และตอบ error เป็นรหัสที่ชัดเจน เช่น `invalid_path` หรือ `dependencies_pending` ให้ AI อ่านแล้วแก้ไขเองได้ path ของไฟล์ถูกจำกัดให้อยู่ในพื้นที่ทำงานเสมือนเท่านั้น

## ใช้ Claude เป็นสมองของเอเจนต์

1. ติดตั้ง SDK: `pip install anthropic`
2. ตั้ง `ANTHROPIC_API_KEY` ในระบบ หรือใส่คีย์ใน ⚙ Settings (เก็บในหน่วยความจำเท่านั้น ไม่เขียนลงดิสก์หรือไฟล์ export)
3. กดการ์ดเอเจนต์ → เปลี่ยน Brain เป็น `claude` หรือโหลดฉาก "Hybrid team" / "All-Claude team"

รายละเอียดการเรียก API: โมเดลเริ่มต้น `claude-opus-5-5` (เปลี่ยนต่อเอเจนต์ได้ เช่น `claude-sonnet-5-5`, `claude-haiku-5-5`), ใช้ adaptive thinking พร้อมสรุปความคิดที่แสดงใน Activity, ตั้ง effort ต่อเอเจนต์, เปิด prompt caching และ server-side refusal fallback (`fallbacks: "default"`) สำหรับรุ่นที่รองรับ แต่ละเอเจนต์มีบทสนทนาของตัวเองแบบต่อท้ายอย่างเดียว ผลของเครื่องมือทั้งหมดในรอบเดียวกันถูกส่งกลับในข้อความเดียว

การควบคุมค่าใช้จ่าย: "Claude call budget" จำกัดจำนวนการเรียกทั้งหมด (ค่าเริ่มต้น 60) และ "Tool calls per Claude turn" จำกัดเครื่องมือต่อหนึ่งตา (ค่าเริ่มต้น 8) ถ้าคีย์ผิดหรือไม่ได้ติดตั้ง SDK ระบบจะหยุดและแสดงสาเหตุบนการ์ด ข้อความที่ยังไม่ได้ประมวลผลจะไม่หาย แก้ค่าแล้วกด Nudge เพื่อให้ทำต่อ ส่วนข้อผิดพลาดชั่วคราว (rate limit, เครือข่าย) จะลองใหม่เองหลัง 3 tick

## สอนความรู้ใหม่ให้ทีม SIM

เอเจนต์ SIM ไม่เข้าใจภาษา มันสร้างโค้ดจาก "สูตร" ในคลังความรู้ (`collablab/knowledge/*.md`) ซึ่งมี 11 สูตรพร้อมเทสต์: แปลงอุณหภูมิ, Fibonacci, จำนวนเฉพาะ, palindrome, นับคำ, FizzBuzz, เครื่องคิดเลข, VAT, BMI, to-do list และตัดเกรด ถ้าคำขอไม่ตรงกับสูตรใด Bolt จะเขียนโครงไว้ ตั้งงานเป็น Blocked และ Nova จะถามคุณ

วิธีช่วยทีม: แท็บ Knowledge → **+ Add note** ใส่ keyword (ภาษาใดก็ได้) และวางโค้ดในบล็อก ```` ```python module ```` (และ ```` ```python tests ```` ถ้ามี) แล้วพิมพ์ `retry` ถึง Nova หรือเปลี่ยน Bolt เป็นสมอง Claude แล้วพิมพ์ `retry`

## จังหวะเวลาและการตื่นของเอเจนต์

เวลาเดินเป็น tick ในแต่ละ tick เอเจนต์ที่ "ตื่น" จะได้เล่นหนึ่งตาตามลำดับในทีม เอเจนต์ตื่นเมื่อมีข้อความถึงตัวเอง ถูก mention หรือมีโพสต์ในช่องที่ติดตาม, เมื่องานหรือโหวตที่เกี่ยวข้องถูกคนอื่นเปลี่ยน หรือเมื่อคุณกด Nudge ทุกคนเห็นโลก ณ ต้น tick สิ่งที่เกิดระหว่าง tick จะเห็นใน tick ถัดไป การส่งต่องานจึงเห็นเป็นขั้น ๆ เมื่อไม่มีใครตื่น การรันจะหยุดเองและรอข้อความใหม่

## ความปลอดภัย

- เซิร์ฟเวอร์ผูกกับ `127.0.0.1` เป็นค่าเริ่มต้น คำขอที่เปลี่ยนข้อมูลต้องเป็น JSON และมี header `X-Collab-Lab: 1` และ Host ต้องเป็นของเซิร์ฟเวอร์นี้ เพื่อกันเว็บอื่นสั่งงานแทนคุณ
- `run_python` รันโค้ดใน workspace บนเครื่องของคุณจริง (ในโฟลเดอร์ชั่วคราว มี timeout) **ไม่ใช่ sandbox** เปิดใช้เฉพาะเมื่อไว้ใจโค้ดที่เอเจนต์เขียน
- API key ไม่ถูกบันทึกลงไฟล์ ไม่อยู่ใน export และไม่ถูกส่งกลับไปที่หน้าเว็บ
- ใช้ `--host 0.0.0.0` เฉพาะในเครือข่ายที่เชื่อถือได้ เพราะไม่มีระบบล็อกอิน

## บรรทัดคำสั่ง

| ตัวเลือก | ความหมาย |
| --- | --- |
| `--port N`, `--host H` | พอร์ตและ interface (ค่าเริ่มต้น 8765 และ 127.0.0.1) |
| `--no-browser` | ไม่เปิดเบราว์เซอร์อัตโนมัติ |
| `--scenario ID` | โหลดฉาก: `offline-team`, `hybrid-team`, `claude-team`, `review-drill` |
| `--load FILE` | โหลด state ที่ export จาก Settings |
| `--allow-code-execution` | เปิดเครื่องมือ `run_python` |
| `--demo [--request TEXT]` | รันทีม SIM แบบไม่มี GUI แล้วพิมพ์สรุป JSON; exit 0 เมื่องานครบทุกการ์ด, 1 เมื่อมีงานค้าง |
| `--version` | แสดงเวอร์ชัน |

```sh
python collab_lab.py --demo --allow-code-execution --request "Write a prime number checker"
```

## ทดสอบ

```sh
python -B -m unittest discover -s tests -v
```

ผลระหว่างสร้าง: 65 tests ผ่านบน Python 3.10.20, 3.12 และ 3.13 (Linux) โดย skip 2 tests ที่ต้องมี Anthropic SDK เมื่อติดตั้ง `anthropic` 2.8.0 แล้วผ่านครบ 65 tests รวมการเรียก SDK จริงไปยัง Messages API จำลองในเครื่อง ซึ่งยืนยันรูปแบบคำขอ (beta header ของ fallback, adaptive thinking, effort, cache control) การวนเครื่องมือ และการจัดการ error 401/429 หน้า GUI ตรวจด้วย Chromium (Playwright) ทั้งขนาด 1440×900 และมือถือ 390×844: ส่งคำขอจนงานครบ 5 การ์ด เปิดไฟล์ ใช้เครื่องมือ เปิดหน้าต่างตั้งค่า โหลดฉาก และกรณีไม่มี SDK โดยไม่มี error ใน console

## ข้อจำกัด

- ยังไม่ได้ทดสอบกับ Claude API จริง เพราะเครื่องที่สร้างไม่มี API key; รูปแบบคำขอทดสอบกับ SDK จริงและเซิร์ฟเวอร์จำลองเท่านั้น
- เอเจนต์ SIM เลือกสูตรด้วยการจับ keyword ไม่ได้เข้าใจความหมาย คำขอที่ซับซ้อนต้องใช้ Claude
- state อยู่ในหน่วยความจำ ปิดโปรแกรมแล้วหายถ้าไม่ได้ Export; บทสนทนาภายในของเอเจนต์ Claude ไม่ถูก export (เริ่มบทสนทนาใหม่หลัง import แต่โลกยังอยู่ครบ)
- `start.cmd` ยังไม่ได้รันบน Windows จริงในรอบนี้ (ชุดทดสอบ Python รันบน Windows ใน CI ของรีโป)

## โครงสร้างไฟล์

```text
ai-collab-lab/
  collab_lab.py          launcher and CLI
  start.cmd              Windows double-click launcher
  collablab/
    world.py             shared state, validation, events, export/import
    tools.py             30 tools, argument validation, permissions
    engine.py            ticks, wake rules, budgets, background run, scenarios
    brains/scripted.py   offline role playbooks
    brains/claude.py     Claude tool-use loop
    knowledge/*.md       recipes and articles
    server.py            local HTTP server and JSON API
    web/                 index.html, style.css, app.js
  scenarios/*.json       team presets
  tests/                 unittest suites
```

สำหรับนักพัฒนาที่จะต่อยอด (เพิ่มเครื่องมือ บทบาท หรือโมเดล) ดูสกิล [multi-agent-collab-lab](../../skill%20for%20creating%20code/multi-agent-collab-lab/SKILL.md)
