#!/usr/bin/env python3
"""Build a reproducible skill bundle and SHA256SUMS in a new output directory."""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from check_repo import ROOT, validate


def build(output: Path, root: Path = ROOT) -> Path:
    errors = validate(root)
    if errors:
        raise ValueError("Repository validation failed:\n" + "\n".join(errors))
    output = output.absolute()
    if output.exists() or output.is_symlink():
        raise ValueError(f"Output already exists: {output}")
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    name = f"codex-programming-skills-{version}"
    # Package tracked files only, never local logs, secrets or build artifacts.
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
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".skill-release-", dir=output.parent))
    try:
        archive = staging / f"{name}.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
            for relative in entries:
                path = root / relative
                if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()) or not path.is_file():
                    raise ValueError(f"Release input is not a regular file: {relative}")
                if "__pycache__" in relative.parts or path.suffix in {".pyc", ".pyo"}:
                    raise ValueError(f"Tracked cache file must be removed before release: {relative}")
                info = zipfile.ZipInfo(f"{name}/{relative.as_posix()}", date_time=(2020, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                bundle.writestr(info, path.read_bytes(), compresslevel=9)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (staging / "SHA256SUMS").write_text(f"{digest}  {archive.name}\n", encoding="utf-8", newline="\n")
        # Refuse replacing an output directory created during the build.
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
