# skill for creating code

โฟลเดอร์นี้เก็บสกิลเสริมที่สร้างขึ้นระหว่างพัฒนาโปรแกรม เพื่อให้ AI แก้ไขหรือต่อยอดโค้ดชุดนั้นได้เร็วและถูกต้องในครั้งต่อไป แต่ละสกิลเป็นโฟลเดอร์ที่มี `SKILL.md` (คำสั่งภาษาอังกฤษตามมาตรฐานของรีโป), `agents/openai.yaml` (ชื่อและคำสั่งเริ่มต้น) และ `references/` (ตัวอย่างโค้ดหรือแม่แบบ)

## หมวดหมู่และคำอธิบาย

### 1. ระบบหลายเอเจนต์และการจำลองสภาพแวดล้อม (Multi-agent & simulation)

| สกิล | ใช้กับ | ใช้เมื่อ |
| --- | --- | --- |
| [multi-agent-collab-lab](multi-agent-collab-lab/SKILL.md) | [AI Collab Lab](../examples/ai-collab-lab/README_TH.md) | เพิ่มเครื่องมือให้เอเจนต์ เพิ่มบทบาทใหม่ เชื่อมโมเดล AI ค่ายอื่น เพิ่มสูตรโค้ดในคลังความรู้ เพิ่มฉากจำลอง ปรับหน้าจอ GUI หรือแก้อาการเอเจนต์ไม่ตื่น วนซ้ำ ข้อความหาย |

สิ่งที่สกิลนี้ให้:

- **แผนที่ไฟล์** บอกว่าส่วนไหนรับผิดชอบอะไร (world, tools, engine, brains, server, web)
- **กฎที่ห้ามทำลาย** เช่น เปลี่ยน state ผ่าน `World` เท่านั้น, จังหวะ tick แบบพร้อมกัน, ประวัติสนทนาของ Claude ต้องต่อท้ายอย่างเดียว, ห้ามบันทึก API key, ห้ามภาษาไทยในไฟล์โค้ด
- **ขั้นตอนพร้อมแม่แบบโค้ด** สำหรับเพิ่ม tool, role, brain, recipe, scenario และ API/GUI ใน [extension-recipes.md](multi-agent-collab-lab/references/extension-recipes.md)
- **ตารางอาการ → สาเหตุ** สำหรับดีบัก และคำสั่งตรวจที่ต้องรันก่อนส่งงาน

## วิธีติดตั้งและเรียกใช้

ติดตั้งทุกสกิลในโฟลเดอร์นี้ไปยังโครงการที่ต้องการ (รันจากรากของรีโป):

```sh
python -B scripts/install_skills.py --source "skill for creating code" --all --destination ../my-project/.agents/skills --dry-run
python -B scripts/install_skills.py --source "skill for creating code" --all --destination ../my-project/.agents/skills
```

จากนั้นเปิดแชตใหม่แล้วสั่งงาน เช่น:

```text
Use $multi-agent-collab-lab to add a "translate_text" tool and a translator role, then run the tests.
```

ถ้าใช้ในรีโปนี้โดยตรง ให้ AI อ่าน `skill for creating code/multi-agent-collab-lab/SKILL.md` ก่อนแก้ `examples/ai-collab-lab`

## เพิ่มสกิลใหม่ในโฟลเดอร์นี้

1. สร้างโฟลเดอร์ชื่อสกิล (ตัวพิมพ์เล็ก ใช้ `-` คั่น) ที่มี `SKILL.md` ซึ่ง frontmatter `name` ตรงกับชื่อโฟลเดอร์และมี `description`
2. เพิ่ม `agents/openai.yaml` ที่มี `display_name`, `short_description` และ `default_prompt` ที่เรียก `$ชื่อสกิล`
3. ลิงก์ในเอกสารของสกิลต้องชี้ไฟล์ภายในโฟลเดอร์สกิลเท่านั้น เพื่อให้ติดตั้งแยกได้
4. เพิ่มแถวในตารางหมวดหมู่ด้านบน (สร้างหมวดใหม่ได้ เช่น เครื่องมือ GUI, การเชื่อมต่อ API, งานอัตโนมัติบน Windows)
5. ทดสอบด้วยคำสั่ง `--dry-run` ด้านบน ตัวติดตั้งจะตรวจ frontmatter, metadata และลิงก์ให้
