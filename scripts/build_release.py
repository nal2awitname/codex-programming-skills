#!/usr/bin/env python3
"""Build reproducible source and per-skill archives with an integrity manifest."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from check_repo import ROOT, validate


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_archive(path: Path, entries: list[tuple[str, bytes]]) -> list[dict]:
    records = []
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name, data in sorted(entries):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, data, compresslevel=9)
            records.append({"path": name, "size": len(data), "sha256": sha256(data)})
    return records


def build(output: Path, root: Path = ROOT) -> Path:
    errors = validate(root)
    if errors:
        raise ValueError("Repository validation failed:\n" + "\n".join(errors))
    output = output.absolute()
    if output.exists() or output.is_symlink():
        raise ValueError(f"Output already exists: {output}")
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    name = f"codex-programming-skills-{version}"
    # Tracked inputs prevent local logs, credentials and caches entering releases.
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=root)
    entries = sorted(PurePosixPath(os.fsdecode(item)) for item in tracked.split(b"\0") if item)
    required = {"VERSION", "README.md", "SKILLS_GUIDE_TH.md", "CHANGELOG.md"}
    missing = required - {entry.as_posix() for entry in entries}
    untracked = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard", "-z", "--",
         "skills", "scripts", "tests", "examples", "docs", "templates"], cwd=root,
    )
    if missing or untracked:
        paths = sorted(missing | {os.fsdecode(item) for item in untracked.split(b"\0") if item})
        raise ValueError("Untracked release inputs; use git add for intended files before packaging: " + ", ".join(paths))
    sources = []
    for relative in entries:
        path = root / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError(f"Release input is not a regular file: {relative}")
        if "__pycache__" in relative.parts or path.suffix in {".pyc", ".pyo"}:
            raise ValueError(f"Tracked cache file must be removed before release: {relative}")
        sources.append((relative.as_posix(), path.read_bytes()))
    skills = sorted(path.name for path in (root / "skills").iterdir() if path.is_dir())
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".skill-release-", dir=output.parent))
    try:
        archives = []
        source_archive = staging / f"{name}.zip"
        files = write_archive(source_archive, [(f"{name}/{path}", data) for path, data in sources])
        archives.append({"name": source_archive.name, "kind": "source", "root": name,
                         "skills": skills, "files": files, "sha256": sha256(source_archive.read_bytes())})
        for skill in skills:
            prefix = f"skills/{skill}/"
            members = [(f"{skill}/{path[len(prefix):]}", data) for path, data in sources if path.startswith(prefix)]
            if not any(path == f"{skill}/SKILL.md" for path, _ in members):
                raise ValueError(f"Skill has no tracked SKILL.md: {skill}")
            archive = staging / f"{skill}-{version}.zip"
            files = write_archive(archive, members)
            archives.append({"name": archive.name, "kind": "skill", "root": skill,
                             "skill": skill, "files": files, "sha256": sha256(archive.read_bytes())})
        manifest = {"schema_version": 1, "version": version, "archives": archives}
        (staging / "release-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
        checksums = "".join(f"{sha256(path.read_bytes())}  {path.name}\n" for path in sorted(staging.iterdir()))
        (staging / "SHA256SUMS").write_text(checksums, encoding="utf-8", newline="\n")
        # mkdir is exclusive, so a concurrently created target is never replaced.
        output.mkdir()
        try:
            for path in staging.iterdir():
                path.rename(output / path.name)
        except BaseException:
            shutil.rmtree(output)
            raise
    finally:
        shutil.rmtree(staging)
    return output / f"{name}.zip"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True, help="new directory; existing paths are refused")
    args = parser.parse_args()
    try:
        print(build(args.output_dir))
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"error: {exc}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
