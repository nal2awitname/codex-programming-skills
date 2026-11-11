#!/usr/bin/env python3
"""Check release integrity; optionally install and test extracted release contents."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tempfile
import zipfile


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def unique_pairs(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"Duplicate manifest key: {key}")
        value[key] = item
    return value


def safe_member(name: str, root: str) -> bool:
    if not isinstance(name, str) or "\\" in name:
        return False
    parts = PurePosixPath(name).parts
    if len(parts) <= 1 or parts[0] != root or name.startswith("/"):
        return False
    for part in name.split("/"):
        if (part in {"", ".", ".."} or part.endswith((".", " "))
                or any(ord(char) < 32 or char in ':*?<>|"' for char in part)
                or re.fullmatch(r"(?:con|prn|aux|nul|com[1-9]|lpt[1-9])", part.split(".", 1)[0], re.I)):
            return False
    return True


def verify(release_dir: Path, smoke: bool = False) -> dict:
    release_dir = release_dir.resolve()
    manifest_path = release_dir / "release-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"), object_pairs_hook=unique_pairs)
    if type(manifest.get("schema_version")) is not int or manifest["schema_version"] != 1 or not re.fullmatch(r"\d+\.\d+\.\d+", manifest.get("version", "")):
        raise ValueError("Unsupported release manifest schema/version")
    records = manifest.get("archives")
    if not isinstance(records, list) or not records:
        raise ValueError("Manifest must contain archives")
    names = set()
    for record in records:
        name, root = record["name"], record["root"]
        if (not isinstance(name, str) or not re.fullmatch(r"[a-z0-9][a-z0-9.-]*\.zip", name)
                or name in names or not re.fullmatch(r"[a-z0-9][a-z0-9.-]*", root)):
            raise ValueError("Invalid/duplicate archive name or root")
        names.add(name)
        archive = release_dir / name
        if archive.is_symlink() or not archive.is_file() or digest(archive.read_bytes()) != record["sha256"]:
            raise ValueError(f"Archive checksum mismatch or missing file: {name}")
        expected = {row["path"]: row for row in record["files"]}
        if len(expected) != len(record["files"]) or not expected:
            raise ValueError(f"Empty or duplicate manifest files: {name}")
        with zipfile.ZipFile(archive) as bundle:
            members = bundle.infolist()
            if len({member.filename.casefold() for member in members}) != len(members):
                raise ValueError(f"Duplicate ZIP member: {name}")
            if {member.filename for member in members} != set(expected):
                raise ValueError(f"ZIP inventory differs from manifest: {name}")
            for member in members:
                if not safe_member(member.filename, root) or member.is_dir() or member.flag_bits & 1 or stat.S_ISLNK(member.external_attr >> 16):
                    raise ValueError(f"Unsafe ZIP member: {member.filename}")
                row = expected[member.filename]
                if member.file_size != row["size"] or digest(bundle.read(member)) != row["sha256"]:
                    raise ValueError(f"ZIP file checksum mismatch: {member.filename}")
        record["index"] = expected
    source = [row for row in records if row.get("kind") == "source"]
    skills = [row for row in records if row.get("kind") == "skill"]
    if len(source) != 1 or len(source) + len(skills) != len(records):
        raise ValueError("Expected one source archive and per-skill archives")
    source = source[0]
    source_skill_names = sorted(name.split("/")[2] for name in source["index"]
                                if name.startswith(source["root"] + "/skills/")
                                and len(name.split("/")) == 4 and name.endswith("/SKILL.md"))
    if source_skill_names != source["skills"]:
        raise ValueError("Source ZIP skill inventory differs from manifest")
    with zipfile.ZipFile(release_dir / source["name"]) as bundle:
        source_version = bundle.read(source["root"] + "/VERSION").decode("utf-8").strip()
    if source_version != manifest["version"]:
        raise ValueError("Source VERSION differs from manifest")
    skill_names = [row["skill"] for row in skills]
    if len(set(skill_names)) != len(skill_names) or sorted(skill_names) != source["skills"]:
        raise ValueError("Per-skill archives do not match source skill inventory")
    for row in skills:
        skill = row["skill"]
        if row["root"] != skill or f"{skill}/SKILL.md" not in row["index"]:
            raise ValueError(f"Invalid standalone skill layout: {skill}")
        prefix = f"{source['root']}/skills/{skill}/"
        source_files = {name[len(prefix):]: data["sha256"] for name, data in source["index"].items() if name.startswith(prefix)}
        skill_files = {name[len(skill) + 1:]: data["sha256"] for name, data in row["index"].items()}
        if source_files != skill_files:
            raise ValueError(f"Standalone skill differs from source: {skill}")
    checksums = {}
    for line in (release_dir / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
        checksum, name = line.split("  ", 1)
        if name in checksums or name not in names | {manifest_path.name}:
            raise ValueError("Invalid/duplicate SHA256SUMS entry")
        checksums[name] = checksum
    if set(checksums) != names | {manifest_path.name}:
        raise ValueError("Incomplete SHA256SUMS")
    for name, checksum in checksums.items():
        if digest((release_dir / name).read_bytes()) != checksum:
            raise ValueError(f"SHA256SUMS mismatch: {name}")
    if smoke:
        smoke_test(release_dir, source, skills, manifest["version"])
    return {"version": manifest["version"], "archives_verified": len(records), "skills": sorted(skill_names),
            "integrity": "passed", "installed_tests": "passed" if smoke else "not_requested"}


def extract_checked(archive: Path, destination: Path) -> None:
    # verify() validates every archive member before this extraction is reached.
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            target = destination / member.filename
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(bundle.read(member))


def smoke_test(release_dir: Path, source: dict, skills: list[dict], version: str) -> None:
    with tempfile.TemporaryDirectory(prefix="skill release smoke ") as temporary:
        base = Path(temporary).resolve()
        extract_checked(release_dir / source["name"], base / "source")
        package = base / "source" / source["root"]
        environment = os.environ.copy()
        environment.pop("PYTHONPATH", None)
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        installer = package / "scripts/install_skills.py"
        installed = base / "installed skills"
        subprocess.run([sys.executable, "-B", str(installer), "--source", str(package), "--destination",
                        str(installed), "--all"], cwd=base, env=environment, check=True)
        for skill in skills:
            standalone = base / "standalone" / skill["skill"]
            extract_checked(release_dir / skill["name"], standalone)
            subprocess.run([sys.executable, "-B", str(installer), "--source", str(standalone / skill["root"]),
                            "--destination", str(base / "individual skills"), "--all"],
                           cwd=base, env=environment, check=True)
        for installation in (installed, base / "individual skills"):
            for relative in ("analyze-and-rebuild/scripts/arb.py", "rebuild-windows-from-behavior/scripts/rebuild.py"):
                for flag in ("--version", "--help"):
                    result = subprocess.run([sys.executable, "-B", str(installation / relative), flag], cwd=base,
                                            env=environment, check=True, capture_output=True, text=True)
                    if flag == "--version" and result.stdout.strip() != version:
                        raise ValueError(f"Installed toolkit version mismatch: {relative}")
        standalone_arb_tests = base / "individual skills/analyze-and-rebuild/tests"
        subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", str(standalone_arb_tests),
                        "-p", "test_cli_workflow.py", "-v"], cwd=base, env=environment, check=True)
        # Run the actual source-package tests, including real CLI lifecycle tests.
        # This also catches runtime files omitted from an otherwise valid archive.
        environment["REBUILD_SKILL_DIR"] = str(base / "individual skills/rebuild-windows-from-behavior")
        # Runner tests execute the standalone installed copy, not the source tree.
        environment["CODE_RUNNER_SKILL_DIR"] = str(base / "individual skills/powershell-code-runner")
        subprocess.run([sys.executable, "-B", str(package / "scripts/check_repo.py"), "--test"],
                       cwd=package, env=environment, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-dir", type=Path, required=True)
    parser.add_argument("--smoke", action="store_true", help="install packages and execute their test suites")
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.release_dir, args.smoke), indent=2))
    except (OSError, ValueError, KeyError, TypeError, AttributeError, zipfile.BadZipFile, RuntimeError, NotImplementedError, subprocess.CalledProcessError) as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
