"""Exercise release reproducibility, installability and validation failures."""
import hashlib
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
        self.assertEqual((archives[0].parent / "SHA256SUMS").read_text(encoding="utf-8"), f"{digest}  {archives[0].name}\n")
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
