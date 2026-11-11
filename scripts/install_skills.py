#!/usr/bin/env python3
"""Install complete skills from an extracted bundle without overwriting files."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
SKIP_DIRS = {"__pycache__", ".pytest_cache"}
SKIP_SUFFIXES = {".pyc", ".pyo"}


def _is_link(path: Path) -> bool:
    info = path.lstat()
    return stat.S_ISLNK(info.st_mode) or bool(
        getattr(info, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    )


def _check_ancestors(path: Path) -> None:
    for candidate in (path, *path.parents):
        if os.path.lexists(candidate) and _is_link(candidate):
            raise ValueError(f"Linked or reparse paths are not supported: {candidate}")


def _valid_name(name: str) -> None:
    if len(name) > 64 or not NAME.fullmatch(name):
        raise ValueError(f"Invalid skill name: {name}")


def discover_skills(source: Path) -> dict[str, Path]:
    """Return named skill directories from a bundle, collection or one skill."""
    source = Path(source).absolute()
    _check_ancestors(source)
    if not source.is_dir():
        raise ValueError(f"Source is not a directory: {source}")
    if (source / "SKILL.md").is_file():
        _valid_name(source.name)
        return {source.name: source}
    collection = source / "skills" if (source / "skills").is_dir() else source
    _check_ancestors(collection)
    result = {}
    for item in sorted(collection.iterdir()):
        if item.name in SKIP_DIRS:
            continue
        if os.path.lexists(item) and _is_link(item):
            raise ValueError(f"Linked or reparse source entries are not supported: {item}")
        if not item.is_dir():
            continue
        _valid_name(item.name)
        if not (item / "SKILL.md").is_file():
            raise ValueError(f"Skill is missing SKILL.md: {item}")
        result[item.name] = item
    if not result:
        raise ValueError(f"No skills found in source: {source}")
    return result


def _skill_files(skill: Path) -> list[Path]:
    files = []
    for current, dirs, names in os.walk(skill, followlinks=False):
        folder = Path(current)
        for name in sorted(dirs + names):
            item = folder / name
            if _is_link(item):
                raise ValueError(f"Linked or reparse source entries are not supported: {item}")
            if not item.is_file() and not item.is_dir():
                raise ValueError(f"Source entry is not a regular file or directory: {item}")
        dirs[:] = sorted(name for name in dirs if name not in SKIP_DIRS)
        files.extend(folder / name for name in sorted(names) if (folder / name).suffix not in SKIP_SUFFIXES)
    return files


def _local_reference(skill: Path, document: Path, target: str) -> None:
    target = target.strip().strip("<>")
    if not target or target.startswith("#") or re.match(r"[a-z][a-z0-9+.-]*:", target, re.I):
        return
    relative = unquote(target.split("#", 1)[0])
    resolved = (document.parent / relative).resolve()
    if not resolved.is_relative_to(skill.resolve()):
        raise ValueError(f"Reference leaves installable skill: {document}: {target}")
    if not resolved.is_file():
        raise ValueError(f"Missing skill reference: {document}: {target}")


def _validate_skill(skill: Path) -> None:
    _check_ancestors(skill)
    files = _skill_files(skill)
    text = (skill / "SKILL.md").read_text(encoding="utf-8-sig")
    front = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", text, re.S)
    if not front:
        raise ValueError(f"Missing YAML frontmatter: {skill / 'SKILL.md'}")
    name = re.search(r"^name:\s*['\"]?([^'\"\r\n]+)['\"]?\s*$", front[1], re.M)
    if not name or name[1].strip() != skill.name:
        raise ValueError(f"Skill frontmatter name differs from directory: {skill}")
    if not re.search(r"^description:\s*\S.+$", front[1], re.M):
        raise ValueError(f"Missing skill description: {skill}")
    metadata = skill / "agents/openai.yaml"
    if not metadata.is_file():
        raise ValueError(f"Missing agents/openai.yaml: {skill}")
    content = metadata.read_text(encoding="utf-8-sig")
    for field in ("display_name", "short_description", "default_prompt"):
        if not re.search(rf"^  {field}:\s*\S.+$", content, re.M):
            raise ValueError(f"Missing interface.{field}: {metadata}")
    for icon in re.findall(r"^  icon_(?:small|large):\s*['\"]?([^'\"\r\n]+)", content, re.M):
        _local_reference(skill, skill / "SKILL.md", icon.strip())
    for document in files:
        if document.suffix.lower() == ".md":
            for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", document.read_text(encoding="utf-8-sig")):
                _local_reference(skill, document, target)


def _ignore_cache(folder: str, names: list[str]) -> set[str]:
    return {name for name in names if name in SKIP_DIRS or Path(name).suffix in SKIP_SUFFIXES}


def install(source: Path, destination: Path, names: list[str] | None = None,
            dry_run: bool = False) -> dict:
    """Preflight selected skills, then copy each into a new named directory."""
    available = discover_skills(source)
    selected = sorted(available) if names is None else list(dict.fromkeys(names))
    if not selected:
        raise ValueError("Select at least one skill")
    destination = Path(destination).absolute()
    _check_ancestors(destination)
    if os.path.lexists(destination) and not destination.is_dir():
        raise ValueError(f"Destination is not a directory: {destination}")
    for name in selected:
        _valid_name(name)
        if name not in available:
            raise ValueError(f"Unknown skill: {name}")
        skill = available[name]
        _validate_skill(skill)
        target = destination / name
        if os.path.lexists(target):
            raise ValueError(f"Destination already exists: {target}")
        # A destination inside the source can recurse while copying; the inverse
        # can also let cleanup or future edits affect the original installation.
        for output in (destination, target):
            if output.resolve().is_relative_to(skill.resolve()) or skill.resolve().is_relative_to(output.resolve()):
                raise ValueError(f"Source and destination overlap: {skill}: {output}")
    result = {"source": str(Path(source).absolute()), "destination": str(destination),
              "names": selected, "planned": selected, "installed": [], "dry_run": dry_run}
    if dry_run:
        return result
    created_targets = []
    created_parents = []
    try:
        missing = []
        parent = destination
        while not os.path.lexists(parent):
            missing.append(parent)
            parent = parent.parent
        for folder in reversed(missing):
            folder.mkdir()
            created_parents.append(folder)
        for name in selected:
            target = destination / name
            # Claim ownership before copytree so rollback never removes a target
            # another process created between preflight and the copy operation.
            target.mkdir()
            created_targets.append(target)
            shutil.copytree(available[name], target, dirs_exist_ok=True, ignore=_ignore_cache)
            result["installed"].append(name)
    except BaseException:
        for target in reversed(created_targets):
            shutil.rmtree(target)
        for folder in reversed(created_parents):
            try:
                folder.rmdir()
            except OSError:
                pass
        raise
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT)
    parser.add_argument("--destination", type=Path)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--skill", action="append", dest="names", metavar="NAME")
    selection.add_argument("--all", action="store_true", help="install every discovered skill")
    parser.add_argument("--list", action="store_true", help="validate and list available skills")
    parser.add_argument("--dry-run", action="store_true", help="validate and show the plan without writing")
    args = parser.parse_args(argv)
    if not args.list and (args.destination is None or (args.names is None and not args.all)):
        parser.error("installation requires --destination and either --all or --skill")
    try:
        if args.list:
            available = discover_skills(args.source)
            for path in available.values():
                _validate_skill(path)
            result = {"source": str(args.source.absolute()), "skills": list(available)}
        else:
            result = install(args.source, args.destination, args.names, args.dry_run)
        print(json.dumps(result, ensure_ascii=True, indent=2))
        return 0
    except (OSError, UnicodeError, ValueError, shutil.Error) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
