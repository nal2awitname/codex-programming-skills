# พัฒนาสกิลและสคริปต์ต่อ

ใช้ Python 3.10+; Python toolkit ใช้ standard library ไม่ต้องติดตั้งแพ็กเกจเพิ่ม สำหรับ native PowerShell tests ให้มี `pwsh` หรือ Windows `powershell` ใน PATH การทดสอบ GUI ต้องใช้ Windows ที่มี Tk และ desktop ที่ใช้งานได้

## เริ่มงานจาก main

```sh
git clone https://github.com/nal2awitname/codex-programming-skills.git
cd codex-programming-skills
git switch main
git pull --ff-only
git switch -c fix/describe-the-problem
python -B scripts/check_repo.py --test
```

หากมี checkout อยู่แล้ว ให้เก็บงานที่ทำค้างไว้ก่อนเปลี่ยนสาขา คำสั่งตรวจรายงานทั้ง failure และ skipped; การข้ามไม่ถือเป็นผลยืนยัน runtime นั้น

## จุดแก้และชุดทดสอบ

| ส่วนประกอบ | โค้ดหรือเอกสาร | ชุดทดสอบ |
| --- | --- | --- |
| ขั้นตอนทำงานของสกิล | `skills/<name>/SKILL.md`, `references/`, `agents/openai.yaml` | `python -B scripts/check_repo.py` และทดลองคำขอตามขอบเขต |
| ARB workbench | `skills/analyze-and-rebuild/scripts/` | `python -B -m unittest discover -s skills/analyze-and-rebuild/tests -v` |
| Windows behavior toolkit | `skills/rebuild-windows-from-behavior/scripts/` | `python -B -m unittest discover -s tests/rebuild-windows-from-behavior -v` |
| Windows media script | `scripts/New-Win11ProMedia.ps1` | `python -B -m unittest discover -s tests/windows-media -v` |
| Repository/release tooling | `scripts/check_repo.py`, `scripts/build_release.py`, `scripts/install_skills.py`, `scripts/verify_release.py` | `python -B -m unittest discover -s tests -v` |
| ตัวอย่างโปรแกรม | `examples/<name>/` | รัน unittest จากโฟลเดอร์ตัวอย่างนั้น หรือใช้คำสั่งตรวจรวม |

แก้บั๊กโดยเพิ่ม regression test ที่แสดงเงื่อนไขและพฤติกรรมที่ถูกต้อง ใส่คอมเมนต์ใกล้จุดแก้เมื่อสาเหตุไม่ชัดจากโค้ด เช่น ความต่างของ JSON error, การเลือก Python หลาย path หรือการตรวจความเก่าของหลักฐาน คอมเมนต์ควรอธิบายว่าเหตุใดต้องทำเช่นนี้ ไม่ทวนคำสั่งทีละบรรทัด

PowerShell media tests ใช้ Windows command mocks จึงไม่ยืนยัน DISM, mount ISO หรือการเขียน USB จริง การเปลี่ยนส่วนเหล่านั้นต้องมีผลตรวจจาก Windows จริงก่อนอ้างว่าทำงานครบ

## ก่อนรวมการแก้ไข

```sh
python -B scripts/check_repo.py --test
git diff --check
```

ตรวจ diff และ stage เฉพาะไฟล์ที่ตั้งใจเผยแพร่ก่อนสร้างแพ็กเกจ:

```sh
python -B scripts/build_release.py --output-dir dist/review-build
python -B scripts/verify_release.py --release-dir dist/review-build --smoke
```

ปลายทางต้องเป็นโฟลเดอร์ใหม่ ZIP รวมเฉพาะไฟล์ที่ Git track และมี `SHA256SUMS` ไฟล์ source ใหม่ที่ยังไม่ track จะทำให้ build หยุด เพื่อป้องกันแพ็กเกจตกหล่น เปิด ZIP ตรวจจำนวนสกิลและทดลอง CLI จากไฟล์ที่แตกแล้ว

CI ใน `.github/workflows/skills.yml` ตรวจ Ubuntu/Windows/macOS ด้วย Python 3.10/3.12 รวม GUI/launcher/installer บน Windows อ้างผลจาก commit ล่าสุดของ PR และตรวจ run บน `main` หลัง merge ด้วย หากแก้บั๊กเพิ่มหลัง CI ผ่าน ต้องตรวจ commit ใหม่ก่อนรวม

เมื่อออกเวอร์ชันถัดไป อัปเดต `VERSION`, เลขเวอร์ชันของ toolkit ทั้งสอง, `CHANGELOG.md` และคู่มือที่เกี่ยวข้องให้ตรงกัน รักษา contract schema เดิมหากยังไม่มีเหตุผลและแผนย้ายข้อมูลสำหรับเปลี่ยน schema


โค้ด คอมเมนต์ configuration metadata และ fenced code blocks ต้องไม่มีภาษาไทย ใส่คำอธิบายภาษาไทยเป็น prose ในเอกสารภายนอกแทน ตัวตรวจ `check_repo.py` บังคับนโยบายนี้ด้วย ZIP รุ่น 2.2.0 แยกทั้ง source และรายสกิล พร้อม manifest/hash; `--smoke` ทดสอบการติดตั้งและเรียก runtime จากแพ็กเกจที่แตกแล้วโดยตรง
