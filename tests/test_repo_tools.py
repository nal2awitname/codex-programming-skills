"""Exercise release reproducibility, installability and validation failures."""
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_release import build
from check_repo import validate
from verify_release import safe_member, verify


class RepositoryToolsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.repo = self.base / "fixture"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        (self.repo / "VERSION").write_text("2.1.0\n", encoding="utf-8")
        for name in ("README.md", "SKILLS_GUIDE_TH.md", "CHANGELOG.md"):
            (self.repo / name).write_text("Fixture\n", encoding="utf-8")
        for name, version_path, declaration in (
            ("analyze-and-rebuild", "scripts/arbkit/__init__.py", '__version__ = "2.1.0"'),
            ("rebuild-windows-from-behavior", "scripts/rebuild.py", 'VERSION = "2.1.0"'),
        ):
            skill = self.repo / "skills" / name
            version = skill / version_path
            version.parent.mkdir(parents=True)
            version.write_text(declaration + "\n", encoding="utf-8")
            (skill / "SKILL.md").write_text(f"---\nname: {name}\ndescription: Example skill\n---\n", encoding="utf-8")
            (skill / "agents").mkdir()
            (skill / "agents/openai.yaml").write_text(
                f'interface:\n  display_name: "Example"\n  short_description: "Example skill"\n  default_prompt: "Use ${name}"\n', encoding="utf-8")
        subprocess.run(["git", "add", "."], cwd=self.repo, check=True)

    def test_version_mismatch_is_reported(self):
        (self.repo / "VERSION").write_text("2.2.0\n", encoding="utf-8")
        self.assertEqual(sum("version differs" in e for e in validate(self.repo)), 2)

    def test_missing_reference_and_external_skill_link_are_reported(self):
        skill = self.repo / "skills/analyze-and-rebuild/SKILL.md"
        with skill.open("a", encoding="utf-8") as out:
            out.write("[Missing](references/missing.md)\n[External](../../VERSION)\n")
        errors = validate(self.repo)
        self.assertTrue(any("broken link" in e for e in errors))
        self.assertTrue(any("leaves installable skill" in e for e in errors))

    def test_reproducible_archive_excludes_untracked_files(self):
        (self.repo / "local-secret.txt").write_text("never package", encoding="utf-8")
        archives = [build(self.base / f"output-{n}", self.repo) for n in range(2)]
        self.assertEqual(archives[0].read_bytes(), archives[1].read_bytes())
        digest = hashlib.sha256(archives[0].read_bytes()).hexdigest()
        checksums = dict(line.split("  ", 1)[::-1] for line in (archives[0].parent / "SHA256SUMS").read_text(encoding="utf-8").splitlines())
        self.assertEqual(checksums[archives[0].name], digest)
        self.assertEqual(set(checksums), {p.name for p in archives[0].parent.iterdir()} - {"SHA256SUMS"})
        for first in archives[0].parent.iterdir():
            self.assertEqual(first.read_bytes(), (archives[1].parent / first.name).read_bytes())
        with zipfile.ZipFile(archives[0]) as archive:
            self.assertFalse(any("local-secret" in name for name in archive.namelist()))
            self.assertEqual(len([n for n in archive.namelist() if n.endswith("/SKILL.md")]), 2)

    def test_missing_required_file_is_a_validation_error(self):
        (self.repo / "VERSION").unlink()
        self.assertTrue(any("Cannot read required" in e for e in validate(self.repo)))

    def test_untracked_required_inputs_prevent_incomplete_release(self):
        subprocess.run(["git", "rm", "--cached", "VERSION"], cwd=self.repo, check=True, stdout=subprocess.PIPE)
        with self.assertRaisesRegex(ValueError, "Untracked release inputs"):
            build(self.base / "incomplete", self.repo)
        self.assertFalse((self.base / "incomplete").exists())

    def test_per_skill_packages_match_source_and_manifest(self):
        archive = build(self.base / "verified", self.repo)
        result = verify(archive.parent)
        self.assertEqual(result["archives_verified"], 3)
        self.assertEqual(result["skills"], ["analyze-and-rebuild", "rebuild-windows-from-behavior"])
        self.assertEqual(result["installed_tests"], "not_requested")

    def test_changed_archive_is_rejected(self):
        archive = build(self.base / "tampered", self.repo)
        with archive.open("ab") as stream:
            stream.write(b"changed")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            verify(archive.parent)

    def test_archive_path_traversal_is_rejected_before_extraction(self):
        archive = build(self.base / "unsafe", self.repo)
        manifest_path = archive.parent / "release-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        record = manifest["archives"][0]
        unsafe = record["root"] + "/../escape.py"
        data = b"escaped"
        with zipfile.ZipFile(archive, "a") as bundle:
            bundle.writestr(unsafe, data)
        record["sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
        record["files"].append({"path": unsafe, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Unsafe ZIP member"):
            verify(archive.parent)
        self.assertFalse((self.base / "escape.py").exists())

    def test_source_policy_allows_prose_but_rejects_code(self):
        sample = self.repo / "language-policy.md"
        text = chr(0x0E01)
        sample.write_text(text + "\n", encoding="utf-8")
        self.assertEqual(validate(self.repo), [])
        sample.write_text("```python\n" + text + "\n```\n", encoding="utf-8")
        self.assertTrue(any("Thai text" in error for error in validate(self.repo)))
        sample.unlink()
        (self.repo / "scripts").mkdir()
        (self.repo / "scripts/policy.py").write_text("# " + text + "\n", encoding="utf-8")
        self.assertTrue(any("Thai text" in error for error in validate(self.repo)))

    def test_windows_device_and_alias_names_are_not_extractable(self):
        for name in ("pkg/NUL", "pkg/CON.txt", "pkg/file.", "pkg/file ", "pkg/a:b", "pkg/../escape"):
            with self.subTest(name=name):
                self.assertFalse(safe_member(name, "pkg"))
        self.assertTrue(safe_member("pkg/path with spaces/normal.py", "pkg"))

    def test_source_inventory_and_version_must_match_manifest(self):
        for scenario in ("inventory", "version"):
            with self.subTest(scenario=scenario):
                archive = build(self.base / scenario, self.repo)
                path = archive.parent / "release-manifest.json"
                manifest = json.loads(path.read_text(encoding="utf-8"))
                if scenario == "inventory":
                    manifest["archives"][0]["skills"].pop()
                    expected = "skill inventory"
                else:
                    manifest["version"] = "9.9.9"
                    expected = "VERSION differs"
                path.write_text(json.dumps(manifest), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, expected):
                    verify(archive.parent)

    def test_case_alias_zip_members_are_rejected(self):
        archive = build(self.base / "case-alias", self.repo)
        path = archive.parent / "release-manifest.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        record = manifest["archives"][0]
        alias = record["root"] + "/version"
        with zipfile.ZipFile(archive, "a") as bundle:
            bundle.writestr(alias, b"alias")
        record["sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
        record["files"].append({"path": alias, "size": 5, "sha256": hashlib.sha256(b"alias").hexdigest()})
        path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Duplicate ZIP member"):
            verify(archive.parent)

    def test_existing_output_is_preserved(self):
        output = self.base / "existing"
        output.mkdir()
        marker = output / "preserve.txt"
        marker.write_bytes(b"preserve")
        with self.assertRaisesRegex(ValueError, "already exists"):
            build(output, self.repo)
        self.assertEqual(marker.read_bytes(), b"preserve")

    def test_tracked_symbolic_link_is_rejected(self):
        link = self.repo / "linked.txt"
        try:
            link.symlink_to(self.repo / "VERSION")
        except OSError as error:
            self.skipTest(f"Symlinks unavailable: {error}")
        subprocess.run(["git", "add", "linked.txt"], cwd=self.repo, check=True)
        with self.assertRaisesRegex(ValueError, "not a regular file"):
            build(self.base / "symlink-output", self.repo)
        self.assertFalse((self.base / "symlink-output").exists())


if __name__ == "__main__":
    unittest.main()
