# PowerShell Code Runner — คู่มือภาษาไทย

สกิล [powershell-code-runner](../../skills/powershell-code-runner/SKILL.md) มีสองหน้าที่:

1. **รันโค้ดได้แทบทุกภาษาจาก PowerShell ด้วยคำสั่งเดียว** — `Invoke-Code.ps1` ดูนามสกุลไฟล์ (หรือบรรทัด `#!` ด้านบนไฟล์) หาคอมไพเลอร์/อินเทอร์พรีเตอร์ที่ติดตั้งและใช้งานได้จริง คอมไพล์ในโฟลเดอร์ชั่วคราว รันโปรแกรม แล้วคืนรหัสออก (exit code) ของโปรแกรม ลบไฟล์ build ให้เองเมื่อจบ รองรับ 53 รายการ เช่น Python, C, C++, C#, Java, JavaScript, TypeScript, Go, Rust, PHP, Ruby, Kotlin, Swift, Batch, VBScript, Bash และโฟลเดอร์โปรเจกต์ Cargo/Go/.NET/npm
2. **เขียนสคริปต์ PowerShell ที่อ่านเข้าใจง่ายและรันได้บนคอมพิวเตอร์ Windows ทุกเครื่อง** — AI เริ่มจากเทมเพลต ทำตามกฎความเข้ากันได้ของ Windows PowerShell 5.1 (มีในทุกเครื่อง) และ PowerShell 7 แล้วตรวจด้วย `Test-PowerShellScript.ps1` ก่อนรันจริง

## ไฟล์ในสกิล

| ไฟล์ | ใช้ทำอะไร |
| --- | --- |
| `scripts/Invoke-Code.ps1` | ตัวรันโค้ดหลายภาษา |
| `scripts/run-code.cmd` | เรียกตัวรันจาก cmd หรือโปรแกรมอื่น แม้เครื่องปิดการรันสคริปต์ PowerShell ไว้ |
| `scripts/run-code-wait.cmd` | ลากไฟล์โค้ดมาวางบนไฟล์นี้ หน้าต่างจะค้างไว้ให้อ่านผลจนกด Enter |
| `scripts/Test-PowerShellScript.ps1` | ตรวจสคริปต์ PowerShell โดยไม่รัน: syntax, ความเข้ากันได้ 5.1/7, encoding ภาษาไทย, alias ที่ความหมายต่างกันในแต่ละเครื่อง |
| `assets/Script-Template.ps1` | เทมเพลตสคริปต์ใหม่: มี help, ตรวจพารามิเตอร์, strict mode, จัดการ error และ exit code |
| `references/runner.md` | คู่มือตัวรันฉบับเต็ม (อังกฤษ) พร้อมตารางทุกภาษาและลำดับเครื่องมือที่ลอง |
| `references/powershell-rules.md` | กฎเขียนสคริปต์ให้รันได้ทุกเครื่อง (อังกฤษ) |
| `references/troubleshooting.md` | อาการ สาเหตุ และวิธีแก้ที่พบบ่อย (อังกฤษ) |

## เริ่มใช้บน Windows

วิธีที่ง่ายที่สุดคือลากไฟล์โค้ด เช่น `hello.py` หรือ `main.cpp` ไปวางบน `run-code-wait.cmd` ใน Explorer

จาก Command Prompt หรือโปรแกรมอื่น ใช้ `run-code.cmd` ตัวเปิดนี้เลือก PowerShell 7 ถ้ามี ถ้าไม่มีจะใช้ Windows PowerShell 5.1 และข้ามนโยบายการรันสคริปต์ (execution policy) เฉพาะครั้งนั้น ไม่เปลี่ยนการตั้งค่าเครื่อง:

```bat
run-code.cmd hello.py
run-code.cmd main.cpp --name "two words"
run-code.cmd -InputFile input.txt -TimeoutSeconds 5 solve.java
```

จาก PowerShell:

```powershell
.\Invoke-Code.ps1 -List
.\Invoke-Code.ps1 -Plan .\Program.cs
.\Invoke-Code.ps1 .\hello.go arg1 "arg 2"
.\Invoke-Code.ps1 -Language javascript -Code 'console.log(6 * 7)'
powershell -NoProfile -ExecutionPolicy Bypass -File .\Invoke-Code.ps1 .\app.rs
```

กติกาสำคัญข้อเดียว: **ตัวเลือกของตัวรันต้องอยู่ก่อนชื่อไฟล์** ทุกอย่างหลังชื่อไฟล์ส่งให้โปรแกรมตรงตัว รวมถึง `-v`, `--help`, ข้อความว่าง และข้อความมีช่องว่าง

## ตัวเลือก

| ตัวเลือก | ความหมาย |
| --- | --- |
| `-List` | แสดงเวอร์ชัน PowerShell, execution policy, code page ของคอนโซล และทุกภาษาว่าพร้อม (`ready`) หรือยังไม่ได้ติดตั้ง (`missing`) พร้อมคำสั่งติดตั้ง |
| `-Plan` | อ่านและอธิบายก่อนรัน: บอกภาษาที่ตรวจพบและเหตุผล เครื่องมือที่ใช้ และคำสั่ง build/run ทุกขั้นแบบคัดลอกไปรันเองได้ โดยไม่รันอะไรเลย |
| `-Language <ชื่อ>` | บังคับภาษา เช่น `python`, `cpp`, `c#`, `ts` ใช้กับไฟล์นามสกุลแปลก หรือคู่กับ `-Code` |
| `-Code <ข้อความ>` | รันโค้ดสั้น ๆ โดยไม่ต้องสร้างไฟล์ |
| `-Toolchain <ชื่อ>` | เลือกเครื่องมือเอง เช่น `clang`, `bun`, `csc` |
| `-BuildArg <ค่า>` | เพิ่มตัวเลือกคอมไพเลอร์ ใส่ซ้ำได้ เช่น `-BuildArg -O2 -BuildArg -std=c++20` |
| `-InputFile <ไฟล์>` | ส่งไฟล์เป็น input มาตรฐาน (stdin) เหมาะกับโจทย์แข่งเขียนโปรแกรม |
| `-TimeoutSeconds <วินาที>` | หยุดโปรแกรมและโปรเซสลูกเมื่อเกินเวลา |
| `-WorkingDirectory <โฟลเดอร์>` | โฟลเดอร์ทำงานของโปรแกรม (ค่าเริ่มต้นคือโฟลเดอร์ปัจจุบัน) |
| `-Quiet` | แสดงเฉพาะผลของโปรแกรม |
| `-KeepBuild` | เก็บโฟลเดอร์ build ไว้ตรวจ |
| `-NoUtf8` | ไม่สลับคอนโซลและ runtime เป็น UTF-8 |
| `-Pause` | รอกด Enter ก่อนปิด (ใช้ใน `run-code-wait.cmd`) |

ข้อความของตัวรันออกทาง stderr จึงใช้ `> output.txt` เก็บเฉพาะผลของโปรแกรมได้

## รหัสออก

ตัวรันคืนรหัสออกของโปรแกรมเอง ยกเว้นกรณีต่อไปนี้:

| รหัส | ความหมาย |
| --- | --- |
| 64 | ใช้คำสั่งผิด เช่น ตัวเลือกไม่รู้จัก หรือบอกภาษาไม่ได้ (ให้เติม `-Language`) |
| 65 | คอมไพล์ไม่ผ่าน ข้อความ error ของคอมไพเลอร์แสดงด้านบน |
| 66 | ไม่พบไฟล์โค้ด ไฟล์ input หรือโฟลเดอร์ |
| 69 | ยังไม่ได้ติดตั้งภาษา ข้อความบอกคำสั่งติดตั้ง เช่น `winget install -e --id Python.Python.3.13` |
| 70 | ข้อผิดพลาดภายในตัวรัน |
| 124 | เกินเวลาที่กำหนดด้วย `-TimeoutSeconds` |

รหัสแครชของ Windows มีคำอธิบายให้ด้วย เช่น `-1073741515` หมายถึงหา DLL ที่โปรแกรมต้องใช้ไม่พบ

## สิ่งที่ทำให้รันได้เสถียร

- ส่งอาร์กิวเมนต์ด้วยกฎ quoting แบบเดียวกับ Windows จริงทั้งใน PowerShell 5.1 และ 7 จึงได้ค่าเดียวกันแม้มีช่องว่าง เครื่องหมายคำพูด ข้อความว่าง หรือภาษาไทย
- ทดลองเรียกเครื่องมือแต่ละตัวก่อนใช้ จึงข้ามตัวที่เสีย เช่น `python.exe` ปลอมของ Microsoft Store ได้ และค้นหาในโฟลเดอร์ติดตั้งมาตรฐานแม้ไม่ได้อยู่ใน `PATH`
- สลับคอนโซลเป็น UTF-8 ระหว่างรันแล้วคืนค่าเดิม ตั้งค่า UTF-8 ให้ Python และ Java เพื่อให้แสดงภาษาไทยถูก
- คอมไพล์ C/C++/Fortran ด้วย MinGW แบบ `-static` จึงไม่ต้องหา DLL ตอนรัน และหลีกเลี่ยงโฟลเดอร์ temp ที่มีชื่อผู้ใช้ภาษาไทยซึ่งเครื่องมือเก่าบางตัวอ่านไม่ได้
- C# ใช้ได้แม้ไม่มี .NET SDK เพราะ Windows ทุกเครื่องมี `csc.exe` (C# 5) ของ .NET Framework
- สคริปต์ Bash ที่บันทึกแบบ CRLF จะรันจากสำเนา LF พร้อมคำเตือน

## ความหมายของ "รันได้ชัวร์"

สิ่งที่ตรวจแล้วจริง: ชุดทดสอบอัตโนมัติ 19 ชุดเรียก PowerShell และคอมไพเลอร์จริง ผ่านครบทั้ง 6 งานของ GitHub Actions (Windows, Ubuntu, macOS × Python 3.10/3.12) บน **Windows PowerShell 5.1** ซึ่งมีในทุกเครื่อง Windows ตัวรันคอมไพล์และรันได้ 32 แบบ ได้แก่ Batch, VBScript, PowerShell 5.1 และ 7, Python, JavaScript, TypeScript, C/C++ (gcc, clang), C# (dotnet และ csc.exe ที่มากับ Windows), VB.NET, F#, Java, Kotlin, Go, Rust, Haskell, Julia, R, Ruby, Perl, PHP, Bash (Git Bash), AWK, Tcl, Fortran รวมถึงไฟล์ `run-code.cmd` และ `run-code-wait.cmd` บน Ubuntu/macOS ผ่านเพิ่มอีก เช่น Swift และ Zsh ระหว่างพัฒนายังรัน Lua, Pascal, COBOL, Lisp, Scheme, OCaml และโฟลเดอร์โปรเจกต์ Cargo/Go/.NET/npm ได้ ชุดทดสอบยังตรวจการส่งอาร์กิวเมนต์ที่มีช่องว่าง เครื่องหมายคำพูด ข้อความว่าง และภาษาไทย, stdin, timeout, รหัสออก และตัวตรวจสคริปต์ ทั้งใน PowerShell 5.1 และ 7

สิ่งที่ตัวรันรับประกันไม่ได้: ภาษานั้นต้องติดตั้งอยู่ในเครื่อง (ถ้าไม่มีจะได้รหัส 69 พร้อมคำสั่งติดตั้ง) และตัวรันไม่แก้บั๊กในโค้ดของโปรแกรมเอง ภาษาที่ไม่มีเครื่องมือในเครื่องทดสอบใช้คำสั่งตามเอกสารของเครื่องมือนั้น ดูรายการที่ผ่านจริงในผล CI ล่าสุด

## ให้ AI ใช้สกิลนี้

เรียกสกิลด้วย `$powershell-code-runner` ตัวอย่าง:

- `ใช้ $powershell-code-runner เขียนสคริปต์ PowerShell สำรองโฟลเดอร์ Documents ไปไดรฟ์ D ทุกวัน ให้รันได้บน Windows 10 และ 11`
- `ใช้ $powershell-code-runner รันไฟล์ main.cpp นี้พร้อม input.txt และบอกว่าผิดตรงไหนถ้าคอมไพล์ไม่ผ่าน`
- `ใช้ $powershell-code-runner อธิบายสคริปต์นี้ทีละส่วน และตรวจว่าจะรันบนเครื่องที่มีแต่ PowerShell 5.1 ได้ไหม`

AI จะตรวจสคริปต์ด้วย `Test-PowerShellScript.ps1 -FailOnWarning` รันทดสอบจริง และส่งคำสั่งที่คัดลอกไปรันได้ทันที

## ตรวจสคริปต์ PowerShell ด้วยตัวเอง

```powershell
.\Test-PowerShellScript.ps1 .\my-script.ps1
.\Test-PowerShellScript.ps1 -FailOnWarning .\scripts
```

รหัสกฎหลัก: `PS001` syntax ผิด, `PS002` มีภาษาไทยแต่ไฟล์ไม่มี BOM (5.1 จะอ่านเพี้ยน ให้บันทึกเป็น "UTF-8 with BOM"), `PS101`–`PS103` ใช้ความสามารถที่มีเฉพาะ PowerShell 7, `PS201` alias ที่ความหมายต่างกัน เช่น `curl`, `PS301` ใช้ `Invoke-Expression`, `PS403` เรียกโปรแกรมภายนอกแต่ไม่ตรวจ `$LASTEXITCODE`

## ติดตั้งสกิล

Codex หรือโฟลเดอร์สกิลของโครงการ:

```sh
python -B scripts/install_skills.py --skill powershell-code-runner --destination ../my-project/.agents/skills
```

Claude: บีบอัดโฟลเดอร์ `skills/powershell-code-runner` ทั้งโฟลเดอร์เป็น ZIP (หรือใช้ ZIP รายสกิลจาก release) แล้วอัปโหลดในหน้าตั้งค่า Skills ของ Claude ต้องเก็บ `scripts/`, `assets/` และ `references/` ไว้ด้วย ไม่ใช่แค่ `SKILL.md`

## ทดสอบ

```sh
python -B -m unittest discover -s tests/powershell-code-runner -v
```

ต้องมี `pwsh` หรือ `powershell` ใน PATH ชุดทดสอบภาษาจะรันทุก fixture ที่เครื่องมีเครื่องมือ และแสดงรายการภาษาที่ผ่านและที่ข้ามเพราะไม่ได้ติดตั้ง
