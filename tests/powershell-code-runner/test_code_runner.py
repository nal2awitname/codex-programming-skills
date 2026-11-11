"""Run the PowerShell code runner, launchers and checker with real shells and toolchains."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SKILL = Path(os.environ.get("CODE_RUNNER_SKILL_DIR") or ROOT / "skills/powershell-code-runner")
RUNNER = SKILL / "scripts/Invoke-Code.ps1"
CHECKER = SKILL / "scripts/Test-PowerShellScript.ps1"
FIXTURES = HERE / "fixtures"
WINDOWS = os.name == "nt"
THAI = "\u0e20\u0e32\u0e29\u0e32\u0e44\u0e17\u0e22"


def find_shells():
    found = []
    for candidate in (os.environ.get("POWERSHELL_EXE"), shutil.which("pwsh"),
                      shutil.which("powershell") if WINDOWS else None):
        if candidate and os.path.normcase(candidate) not in [os.path.normcase(item) for item in found]:
            found.append(candidate)
    return found


SHELLS = find_shells()
# Windows PowerShell 5.1 is the one shell every Windows computer has, so it drives the language matrix there.
PRIMARY = next((shell for shell in SHELLS if Path(shell).stem.lower() == "powershell"), SHELLS[0] if SHELLS else None)


def run_script(shell, script, *arguments, cwd=None, env=None, timeout=600):
    command = [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(script)]
    result = subprocess.run(command + [str(item) for item in arguments], cwd=cwd, env=env, capture_output=True,
                            stdin=subprocess.DEVNULL, timeout=timeout)
    return (result.returncode, result.stdout.decode("utf-8", "replace").replace("\r\n", "\n"),
            result.stderr.decode("utf-8", "replace").replace("\r\n", "\n"))


def run(shell, *arguments, **options):
    return run_script(shell, RUNNER, *arguments, **options)


class SourceFormatTests(unittest.TestCase):
    def test_powershell_sources_are_ascii(self):
        # ASCII parses identically in every Windows PowerShell 5.1 code page.
        for path in list((SKILL / "scripts").glob("*.ps1")) + list((SKILL / "assets").glob("*.ps1")) + [HERE / "runner_unit.ps1"]:
            with self.subTest(path=path.name):
                self.assertTrue(path.read_bytes().isascii())

    def test_batch_files_use_crlf(self):
        # cmd.exe misreads labels and long lines in LF-only batch files.
        for path in list((SKILL / "scripts").glob("*.cmd")) + [FIXTURES / "hello.cmd"]:
            with self.subTest(path=path.name):
                data = path.read_bytes()
                self.assertTrue(data.isascii())
                self.assertEqual(data.count(b"\n"), data.count(b"\r\n"))


@unittest.skipUnless(SHELLS, "PowerShell (pwsh or powershell) is required")
class RunnerUnitTests(unittest.TestCase):
    def test_quoting_and_option_parsing(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code, out, err = run_script(shell, HERE / "runner_unit.ps1", "-RunnerPath", RUNNER)
                self.assertEqual(code, 0, out + err)
                self.assertIn("ALL PASS", out)


@unittest.skipUnless(SHELLS, "PowerShell (pwsh or powershell) is required")
class RunnerBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="code runner ")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.work = self.base / ("folder with spaces " + THAI)
        self.work.mkdir()
        self.env = dict(os.environ, CODE_RUNNER_BUILD_ROOT=str(self.base / "build-root"))
        (self.base / "build-root").mkdir()

    def write(self, name, text):
        path = self.work / name
        path.write_text(text, encoding="utf-8", newline="\n")
        return path

    def test_arguments_reach_the_program_exactly(self):
        script = self.write("echo_args.py", "import json, sys\nprint(json.dumps(sys.argv[1:]))\n")
        arguments = ["-v", "", "a b", 'q"uote', "back\\", "--", "-Quiet", "-Language", "%PATH%", "a&b", THAI]
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code, out, err = run(shell, "-Quiet", script, *arguments, cwd=self.work, env=self.env)
                self.assertEqual(code, 0, err)
                self.assertEqual(json.loads(out.strip().splitlines()[-1]), arguments)

    def test_exit_code_unicode_output_and_working_directory(self):
        script = self.write("report.py", "import os, sys\nprint('" + THAI + "')\nprint(os.getcwd())\nsys.exit(7)\n")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code, out, err = run(shell, script, cwd=self.base, env=self.env)
                self.assertEqual(code, 7, err)
                lines = out.strip().splitlines()
                self.assertEqual(lines[0], THAI)
                self.assertEqual(os.path.normcase(lines[1]), os.path.normcase(str(self.base)))
                self.assertIn("Program exited with code 7", err)
                self.assertNotIn("[code-runner]", out)

    def test_inline_code_keeps_program_flags(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code, out, err = run(shell, "-Quiet", "-Language", "python", "-Code",
                                     "import sys; print(sys.argv[1:]); sys.exit(5)", "-v", "--help", "-Plan",
                                     cwd=self.work, env=self.env)
                self.assertEqual(code, 5, err)
                self.assertEqual(out.strip(), "['-v', '--help', '-Plan']")

    def test_input_file_timeout_and_working_directory_option(self):
        data = self.write("input.txt", "first\nsecond\n")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code, out, err = run(shell, "-Quiet", "-InputFile", data, "-WorkingDirectory", self.base, "-Language", "py",
                                     "-Code", "import os, sys; print(sys.stdin.read().upper().strip()); print(os.getcwd())",
                                     cwd=self.work, env=self.env)
                self.assertEqual(code, 0, err)
                self.assertEqual(out.strip().splitlines(), ["FIRST", "SECOND", str(self.base)])
                started = time.monotonic()
                code, out, err = run(shell, "-TimeoutSeconds", "2", "-Language", "python", "-Code",
                                     "import time; time.sleep(60)", cwd=self.work, env=self.env)
                self.assertEqual(code, 124, err)
                self.assertLess(time.monotonic() - started, 45)
                self.assertIn("Time limit", err)

    def test_runner_error_codes(self):
        unknown = self.write("data.unknownext", "x\n")
        cases = [
            (("missing.py",), 66), ((unknown,), 64), (("-Bogus", "x.py"), 64), ((), 64),
            (("-Language", "nosuchlanguage", "-Code", "x"), 64), (("-InputFile", "missing.txt", "-Language", "py", "-Code", "1"), 66),
            (("-Code", "print(1)"), 64), (("-Toolchain", "nosuchtool", "-Language", "py", "-Code", "1"), 64),
        ]
        for shell in SHELLS:
            for arguments, expected in cases:
                with self.subTest(shell=shell, arguments=arguments):
                    code, out, err = run(shell, *arguments, cwd=self.work, env=self.env)
                    self.assertEqual(code, expected, out + err)
                    self.assertIn("ERROR", err)
            with self.subTest(shell=shell, case="no toolchain"):
                env = dict(self.env, PATH="")
                code, out, err = run(shell, "-Language", "cobol", "-Code", "x", cwd=self.work, env=env)
                self.assertEqual(code, 69, out + err)
                self.assertIn("Install:", err)
            with self.subTest(shell=shell, case="help"):
                code, out, err = run(shell, "-Help", cwd=self.work, env=self.env)
                self.assertEqual(code, 0, err)
                self.assertIn("Usage:", out)

    def test_build_failure_returns_65(self):
        broken = self.write("broken.c", "int main( { return 0; }\n")
        code, out, err = run(PRIMARY, "-Plan", broken, cwd=self.work, env=self.env)
        if code == 69:
            self.skipTest("no C compiler on this machine")
        code, out, err = run(PRIMARY, "-Quiet", broken, cwd=self.work, env=self.env)
        self.assertEqual(code, 65, out + err)
        self.assertIn("Build failed", err)
        self.assertEqual(out, "")

    def test_plan_runs_nothing_and_list_reports_python(self):
        marker = self.work / "marker.txt"
        script = self.write("touch.py", "open(r'" + str(marker) + "', 'w').close()\n")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code, out, err = run(shell, "-Plan", script, "arg", cwd=self.work, env=self.env)
                self.assertEqual(code, 0, err)
                self.assertIn("Steps:", out)
                self.assertIn("[run]", out)
                self.assertIn("extension .py", out)
                self.assertFalse(marker.exists())
                code, out, err = run(shell, "-List", cwd=self.work, env=self.env)
                self.assertEqual(code, 0, err)
                python_row = next(line for line in out.splitlines() if line.startswith("python "))
                self.assertIn("ready", python_row)
        self.assertEqual(list((self.base / "build-root").iterdir()), [])

    def test_build_folders_are_removed_unless_kept(self):
        root = self.base / "build-root"
        code, out, err = run(PRIMARY, "-Quiet", "-Language", "python", "-Code", "print(1)", cwd=self.work, env=self.env)
        self.assertEqual((code, out.strip()), (0, "1"), err)
        self.assertEqual(list(root.iterdir()), [])
        code, out, err = run(PRIMARY, "-KeepBuild", "-Language", "python", "-Code", "print(2)", cwd=self.work, env=self.env)
        self.assertEqual(code, 0, err)
        self.assertIn("Build folder kept", err)
        self.assertEqual(len(list(root.iterdir())), 1)

    def test_shebang_and_project_folder_detection(self):
        self.write("tool", "#!/usr/bin/env python3\nimport sys\nprint('shebang', sys.argv[1:])\n")
        project = self.work / "project"
        project.mkdir()
        (project / "main.py").write_text("import os\nprint('project', os.path.basename(os.getcwd()))\n", encoding="utf-8")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code, out, err = run(shell, "-Quiet", "tool", "x", cwd=self.work, env=self.env)
                self.assertEqual((code, out.strip()), (0, "shebang ['x']"), err)
                code, out, err = run(shell, "-Quiet", "project", cwd=self.work, env=self.env)
                self.assertEqual((code, out.strip()), (0, "project " + self.work.name), err)

    def test_crlf_shell_script_runs_from_lf_copy(self):
        script = self.work / "windows.sh"
        script.write_bytes(b"echo crlf-ok\r\nexit 4\r\n")
        code, out, err = run(PRIMARY, "-Plan", script, cwd=self.work, env=self.env)
        if code == 69:
            self.skipTest("bash is not installed")
        code, out, err = run(PRIMARY, script, cwd=self.work, env=self.env)
        self.assertEqual((code, out.strip()), (4, "crlf-ok"), err)
        self.assertIn("CRLF", err)

    def test_in_process_call_flattens_values_and_sets_last_exit_code(self):
        script = self.write("echo_args.py", "import json, sys\nprint(json.dumps(sys.argv[1:]))\nsys.exit(9)\n")
        command = ("& '" + str(RUNNER).replace("'", "''") + "' -Quiet '" + str(script).replace("'", "''") +
                   "' -v '' a,b -n:3; 'exit=' + $LASTEXITCODE")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = subprocess.run([shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                                         "-Command", command], cwd=self.work, env=self.env, capture_output=True,
                                        stdin=subprocess.DEVNULL, timeout=300)
                out = result.stdout.decode("utf-8", "replace")
                lines = [line for line in out.splitlines() if line.strip()]
                self.assertEqual(json.loads(lines[-2]), ["-v", "", "a", "b", "-n:3"], out)
                self.assertEqual(lines[-1].strip(), "exit=9")

    @unittest.skipUnless(WINDOWS, "cmd.exe launchers are Windows-only")
    def test_cmd_launchers(self):
        fixture = FIXTURES / "hello.py"
        for launcher in ("run-code.cmd", "run-code-wait.cmd"):
            with self.subTest(launcher=launcher):
                line = 'cmd.exe /d /s /c ""{}" -Quiet "{}" "a b" c"'.format(SKILL / "scripts" / launcher, fixture)
                result = subprocess.run(line, cwd=self.work, env=self.env, capture_output=True,
                                        stdin=subprocess.DEVNULL, timeout=300)
                out = result.stdout.decode("utf-8", "replace")
                self.assertEqual(result.returncode, 3, out + result.stderr.decode("utf-8", "replace"))
                self.assertIn("OK:a b|c", out.splitlines())


@unittest.skipUnless(SHELLS, "PowerShell (pwsh or powershell) is required")
class LanguageMatrixTests(unittest.TestCase):
    """Every fixture prints OK: plus its arguments joined by | and exits with 3."""

    VARIANTS = [("hello.c", "clang"), ("hello.cpp", "clang++"), ("hello.cs", "csc"), ("hello.cs", "mono"),
                ("hello.ts", "node"), ("hello.ts", "ts-node"), ("hello.js", "bun"), ("hello.js", "deno"),
                ("Hello.java", "java"), ("hello.ps1", "powershell"), ("hello.ps1", "pwsh")]

    def run_fixture(self, fixture, toolchain=None):
        options = ["-Toolchain", toolchain] if toolchain else []
        code, out, err = run(PRIMARY, "-Plan", *options, fixture, cwd=HERE)
        if code == 69 or (code == 64 and "not defined for" in err):
            return "skipped"
        self.assertEqual(code, 0, out + err)
        code, out, err = run(PRIMARY, "-Quiet", *options, fixture, "a b", "c", cwd=HERE)
        self.assertEqual(code, 3, out + err)
        self.assertIn("OK:a b|c", out.splitlines(), out + err)
        return "passed"

    def test_every_fixture_with_an_installed_toolchain(self):
        results = {}
        for fixture in sorted(FIXTURES.iterdir()):
            with self.subTest(fixture=fixture.name):
                results[fixture.name] = self.run_fixture(fixture)
        for name, toolchain in self.VARIANTS:
            with self.subTest(fixture=name, toolchain=toolchain):
                results[name + " via " + toolchain] = self.run_fixture(FIXTURES / name, toolchain)
        ran = sorted(key for key, value in results.items() if value == "passed")
        print("\nRunner matrix with {}: passed {}; skipped (not installed) {}".format(
            Path(PRIMARY).name, ", ".join(ran), ", ".join(sorted(set(results) - set(ran)))))
        self.assertIn("hello.py", ran)


@unittest.skipUnless(SHELLS, "PowerShell (pwsh or powershell) is required")
class CheckerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="checker ")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)

    def check(self, shell, *arguments):
        code, out, err = run_script(shell, CHECKER, "-Json", *arguments)
        report = json.loads(out) if out.strip().startswith("{") else {"Findings": []}
        findings = report["Findings"]
        if isinstance(findings, dict):
            findings = [findings]
        return code, {item["Rule"] for item in findings}, out + err

    def test_skill_scripts_and_template_are_clean(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code, rules, output = self.check(shell, "-FailOnWarning", SKILL / "scripts", SKILL / "assets")
                self.assertEqual((code, rules), (0, set()), output)

    def test_compatibility_and_safety_findings(self):
        compat = self.base / "compat.ps1"
        compat.write_text("\n".join([
            "if ($IsWindows) { ls }", "curl https://example.com", "Get-ChildItem | % { $_ } | ? { $_ }",
            "Get-Content a.txt -AsByteStream", "Set-Content -Path b.txt -Value 1 -Encoding utf8NoBOM",
            "ConvertFrom-Json '{}' -AsHashtable", "Join-Path a b c", "Invoke-Expression 'Get-Date'",
            "$file = 'C:\\Users\\someone\\Desktop\\x.txt'", "Set-ExecutionPolicy Unrestricted",
            "Split-Path -Leaf 'C:\\x'", "Select-Object -Skip 1", "git status", ""]), encoding="utf-8")
        modern = self.base / "modern.ps1"
        modern.write_text("$a = $true ? 1 : 2\n$b = $null ?? 'x'\ngit status && Write-Output done\n", encoding="utf-8")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code, rules, output = self.check(shell, compat)
                self.assertEqual(code, 1, output)
                self.assertLessEqual({"PS102", "PS103", "PS201", "PS202", "PS301", "PS302", "PS303", "PS401", "PS402", "PS403"},
                                     rules, output)
                code, rules, output = self.check(shell, modern)
                self.assertEqual(code, 1, output)
                # Windows PowerShell 5.1 cannot parse 7-only syntax, so it reports a syntax error instead.
                self.assertTrue(rules & {"PS101", "PS001"}, output)
                code, rules, output = self.check(shell, "-Target", "Core", modern)
                self.assertNotIn("PS101", rules, output)

    def test_encoding_syntax_and_missing_path(self):
        thai = self.base / "thai.ps1"
        thai.write_bytes(("Write-Output '" + THAI + "'\n").encode("utf-8"))
        thai_bom = self.base / "thai-bom.ps1"
        thai_bom.write_bytes(b"\xef\xbb\xbf" + ("Set-StrictMode -Version 3.0\n$ErrorActionPreference = 'Stop'\n"
                                                 "Write-Output '" + THAI + "'\n").encode("utf-8"))
        invalid = self.base / "invalid.ps1"
        invalid.write_bytes(b"Write-Output '\xff\xfe\xfd'\n")
        broken = self.base / "broken.ps1"
        broken.write_text('Write-Output "unterminated\n', encoding="utf-8")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.assertIn("PS002", self.check(shell, thai)[1])
                self.assertEqual(self.check(shell, thai_bom)[:2], (0, set()))
                self.assertIn("PS003", self.check(shell, invalid)[1])
                self.assertIn("PS001", self.check(shell, broken)[1])
                code, out, err = run_script(shell, CHECKER, self.base / "missing.ps1")
                self.assertEqual(code, 2, out + err)


if __name__ == "__main__":
    unittest.main()
