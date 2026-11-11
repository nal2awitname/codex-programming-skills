#!/usr/bin/env python3
"""Validate repository skills and optionally run every test suite (Python 3.10+)."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CODE_SUFFIXES = {".py", ".ps1", ".psm1", ".cmd", ".bat", ".sh", ".bash", ".yaml", ".yml",
                 ".json", ".toml", ".js", ".ts", ".tsx", ".jsx", ".c", ".h", ".cpp", ".cs"}
SKIP_DIRS = {".git", "dist", "__pycache__", ".venv", "node_modules", ".pytest_cache"}


def source_policy_errors(root: Path) -> list[str]:
    """Keep executable/configuration sources and Markdown code blocks in English."""
    errors = []
    for path in sorted(root.rglob("*")):
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        if not path.is_file() or path.suffix.lower() not in CODE_SUFFIXES | {".md"}:
            continue
        text = path.read_text(encoding="utf-8-sig")
        fence = None
        for number, line in enumerate(text.splitlines(), 1):
            marker = re.match(r"^\s*(`{3,}|~{3,})", line) if path.suffix.lower() == ".md" else None
            if marker:
                token = marker[1]
                if fence is None:
                    fence = token
                elif token[0] == fence[0] and len(token) >= len(fence):
                    fence = None
                continue
            if (path.suffix.lower() != ".md" or fence) and any(0x0E00 <= ord(char) <= 0x0E7F for char in line):
                errors.append(f"{path.relative_to(root)}:{number}: Thai text is not allowed in source/code blocks")
    return errors

SUITES = (
    ("tests", "test_*.py"),
    ("skills/analyze-and-rebuild/tests", "test_*.py"),
    ("tests/rebuild-windows-from-behavior", "test_*.py"),
    ("tests/windows-media", "test_*.py"),
    ("examples/rebuild-windows-from-behavior/tests", "test_*.py"),
    ("examples/value-scan-lab/tests", "test_*.py"),
)


def _validate(root: Path) -> list[str]:
    errors = []
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        errors.append("VERSION must contain a semantic release version")
    for path, prefix in (
        ("skills/analyze-and-rebuild/scripts/arbkit/__init__.py", "__version__"),
        ("skills/rebuild-windows-from-behavior/scripts/rebuild.py", "VERSION"),
    ):
        contents = (root / path).read_text(encoding="utf-8")
        if not re.search(rf'^{prefix} = "{re.escape(version)}"$', contents, re.M):
            errors.append(f"{path}: version differs from VERSION ({version})")
    skills = sorted((root / "skills").iterdir())
    if not skills:
        errors.append("No skills found")
    for skill in skills:
        if not skill.is_dir() or skill.is_symlink():
            errors.append(f"Invalid skill directory: {skill.name}")
            continue
        path = skill / "SKILL.md"
        if not path.is_file():
            errors.append(f"{skill.name}: missing SKILL.md")
            continue
        text = path.read_text(encoding="utf-8")
        front = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", text, re.S)
        if not front:
            errors.append(f"{skill.name}: missing YAML frontmatter")
        else:
            if not re.search(rf"^name: {re.escape(skill.name)}$", front[1], re.M):
                errors.append(f"{skill.name}: frontmatter name differs from folder")
            if not re.search(r"^description: \S.+$", front[1], re.M):
                errors.append(f"{skill.name}: missing description")
        metadata = skill / "agents/openai.yaml"
        if not metadata.is_file():
            errors.append(f"{skill.name}: missing agents/openai.yaml")
        else:
            content = metadata.read_text(encoding="utf-8")
            for field in ("display_name", "short_description", "default_prompt"):
                if not re.search(rf"^  {field}: \S.+$", content, re.M):
                    errors.append(f"{skill.name}: missing interface.{field}")
            if f"${skill.name}" not in content:
                errors.append(f"{skill.name}: default prompt must invoke ${skill.name}")
        # Links are local Markdown file references, not web URLs or anchor-only links.
        for document in skill.rglob("*.md"):
            for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", document.read_text(encoding="utf-8")):
                if re.match(r"[a-z][a-z0-9+.-]*:", target, re.I) or target.startswith("#"):
                    continue
                relative = target.split("#", 1)[0]
                resolved = (document.parent / relative).resolve()
                if not resolved.is_relative_to(skill.resolve()):
                    errors.append(f"{document.relative_to(root)}: link leaves installable skill: {target}")
                elif not resolved.is_file():
                    errors.append(f"{document.relative_to(root)}: broken link: {target}")
        for script in skill.rglob("*.py"):
            try:
                compile(script.read_bytes(), str(script), "exec")
            except (SyntaxError, ValueError) as exc:
                errors.append(f"{script.relative_to(root)}: {exc}")
    errors.extend(source_policy_errors(root))
    return errors


def validate(root: Path = ROOT) -> list[str]:
    try:
        return _validate(root)
    except (OSError, UnicodeError) as exc:
        return [f"Cannot read required repository files: {exc}"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", action="store_true", help="also run all six test suites")
    args = parser.parse_args()
    errors = validate()
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Skill metadata, references, syntax, versions and English code policy: OK", flush=True)
    failed = False
    if args.test:
        for relative, pattern in SUITES:
            test_dir = ROOT / relative
            # Examples rely on their own working directory; avoid import collisions.
            cwd = test_dir.parent
            print(f"\nTesting {relative}", flush=True)
            result = subprocess.run(
                [sys.executable, "-B", "-m", "unittest", "discover", "-s", str(test_dir), "-p", pattern, "-v"],
                cwd=cwd, check=False,
            )
            failed |= result.returncode != 0
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
