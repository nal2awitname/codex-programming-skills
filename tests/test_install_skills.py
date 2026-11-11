"""Exercise complete skill installation, preflight and rollback behavior."""
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from install_skills import discover_skills, install


class InstallSkillsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.source = self.base / "extracted bundle"
        self.source.mkdir()
        self.skills = self.source / "skills"
        self.skills.mkdir()
        self.make_skill("first-skill")
        self.make_skill("second-skill")
        self.destination = self.base / "project with spaces" / ".agents" / "skills"

    def make_skill(self, name):
        skill = self.skills / name
        (skill / "agents").mkdir(parents=True)
        (skill / "references").mkdir()
        (skill / "scripts").mkdir()
        (skill / "assets").mkdir()
        (skill / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: Example skill for synthetic tests\n---\n"
            "Read [the guide](references/guide.md).\n", encoding="utf-8")
        (skill / "references/guide.md").write_text("Run the included script.\n", encoding="utf-8")
        (skill / "scripts/tool.py").write_text("print('example')\n", encoding="utf-8")
        (skill / "assets/icon.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>\n', encoding="utf-8")
        (skill / "agents/openai.yaml").write_text(
            f'interface:\n  display_name: "{name}"\n  short_description: "Synthetic skill"\n'
            f'  default_prompt: "Use ${name}"\n  icon_small: "assets/icon.svg"\n', encoding="utf-8")
        return skill

    def make_link(self, link, target):
        try:
            link.symlink_to(target, target_is_directory=target.is_dir())
        except OSError as error:
            self.skipTest(f"Symlinks unavailable: {error}")

    def test_install_all_preserves_runtime_files_and_ignores_caches(self):
        cache = self.skills / "first-skill/scripts/__pycache__"
        cache.mkdir()
        (cache / "tool.pyc").write_bytes(b"cache")
        result = install(self.source, self.destination)
        self.assertEqual(result["installed"], ["first-skill", "second-skill"])
        for name in result["installed"]:
            self.assertEqual((self.destination / name / "scripts/tool.py").read_bytes(),
                             (self.skills / name / "scripts/tool.py").read_bytes())
            self.assertTrue((self.destination / name / "references/guide.md").is_file())
            self.assertTrue((self.destination / name / "assets/icon.svg").is_file())
            self.assertFalse((self.destination / name / "scripts/__pycache__").exists())

    def test_standalone_and_collection_sources(self):
        for source in (self.skills / "first-skill", self.skills):
            with self.subTest(source=source):
                target = self.base / ("standalone" if source.name == "first-skill" else "collection")
                result = install(source, target, ["first-skill"])
                self.assertEqual(result["installed"], ["first-skill"])
                self.assertTrue((target / "first-skill/SKILL.md").is_file())

    def test_dry_run_does_not_create_parent_directories(self):
        result = install(self.source, self.destination, dry_run=True)
        self.assertEqual(result["installed"], [])
        self.assertEqual(result["planned"], ["first-skill", "second-skill"])
        self.assertFalse(self.destination.parent.parent.exists())

    def test_existing_unrelated_skills_are_preserved(self):
        unrelated = self.destination / "unrelated"
        unrelated.mkdir(parents=True)
        marker = unrelated / "keep.txt"
        marker.write_bytes(b"keep")
        install(self.source, self.destination, ["first-skill"])
        self.assertEqual(marker.read_bytes(), b"keep")
        with self.assertRaisesRegex(ValueError, "already exists"):
            install(self.source, self.destination, ["first-skill"])
        self.assertEqual(marker.read_bytes(), b"keep")

    def test_all_selected_skills_are_validated_before_writing(self):
        (self.skills / "second-skill/agents/openai.yaml").unlink()
        with self.assertRaisesRegex(ValueError, "Missing agents"):
            install(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_dangling_target_and_source_links_are_rejected(self):
        self.destination.mkdir(parents=True)
        dangling = self.destination / "first-skill"
        self.make_link(dangling, self.base / "missing")
        with self.assertRaisesRegex(ValueError, "already exists"):
            install(self.source, self.destination, ["first-skill"])
        self.assertTrue(os.path.lexists(dangling))
        dangling.unlink()
        linked = self.skills / "first-skill/scripts/linked.py"
        self.make_link(linked, self.skills / "first-skill/scripts/tool.py")
        with self.assertRaisesRegex(ValueError, "Linked or reparse"):
            install(self.source, self.destination)
        self.assertFalse((self.destination / "second-skill").exists())

    def test_linked_ancestors_and_source_destination_overlap_are_rejected(self):
        alias = self.base / "linked bundle"
        self.make_link(alias, self.source)
        with self.assertRaisesRegex(ValueError, "Linked or reparse"):
            install(alias, self.destination)
        with self.assertRaisesRegex(ValueError, "overlap"):
            install(self.skills / "first-skill", self.skills / "first-skill" / "nested")
        self.assertFalse((self.skills / "first-skill/nested").exists())

    def test_missing_and_escaping_references_are_rejected(self):
        guide = self.skills / "first-skill/references/guide.md"
        for target, expected in (("missing.md", "Missing skill reference"), ("../../outside.md", "leaves installable")):
            with self.subTest(target=target):
                guide.write_text(f"[Reference]({target})\n", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, expected):
                    install(self.source, self.destination, ["first-skill"])
                self.assertFalse(self.destination.exists())

    def test_failed_copy_rolls_back_only_new_targets(self):
        unrelated = self.destination / "unrelated"
        unrelated.mkdir(parents=True)
        marker = unrelated / "keep.txt"
        marker.write_bytes(b"keep")
        copytree = shutil.copytree

        def fail_second_skill(source, target, *args, **kwargs):
            if Path(source).name == "second-skill":
                self.assertTrue((self.destination / "first-skill/scripts/tool.py").is_file())
                raise OSError("synthetic copy failure")
            return copytree(source, target, *args, **kwargs)

        with patch("install_skills.shutil.copytree", side_effect=fail_second_skill):
            with self.assertRaisesRegex(OSError, "synthetic copy failure"):
                install(self.source, self.destination)
        self.assertEqual(list(self.destination.iterdir()), [unrelated])
        self.assertEqual(marker.read_bytes(), b"keep")

    def test_cli_list_install_and_failure_emit_json(self):
        script = ROOT / "scripts/install_skills.py"
        prefix = [sys.executable, "-B", str(script), "--source", str(self.source)]
        listing = subprocess.run(prefix + ["--list"], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(listing.stdout)["skills"], ["first-skill", "second-skill"])
        args = ["--destination", str(self.destination), "--skill", "first-skill"]
        installed = subprocess.run(prefix + args, capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(installed.stdout)["installed"], ["first-skill"])
        failed = subprocess.run(prefix + args, capture_output=True, text=True)
        self.assertEqual(failed.returncode, 2)
        self.assertIn("already exists", json.loads(failed.stderr)["error"])


if __name__ == "__main__":
    unittest.main()
