"""End-to-end collaboration of the offline scripted team."""
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from collablab.brains.scripted import autofix, review_findings, slugify, task_context  # noqa: E402
from collablab.engine import Engine, list_scenarios, read_scenario  # noqa: E402
from collablab.tools import analyze_python  # noqa: E402
from collablab.world import USER_ID, WorldError  # noqa: E402


def team(**settings):
    engine = Engine(settings={"auto_run": False, **settings})
    engine.install_team()
    return engine


def wait_until_stopped(engine, timeout=20.0):
    deadline = time.monotonic() + timeout
    while engine.running and time.monotonic() < deadline:
        time.sleep(0.02)
    return not engine.running


def replies_to_user(engine):
    return [m["text"] for m in engine.world.messages if m["to"] == USER_ID]


class ProjectFlowTests(unittest.TestCase):
    def test_request_becomes_reviewed_tested_documented_project(self):
        engine = team()
        engine.user_message("nova", "Build a temperature converter for Celsius, Fahrenheit and Kelvin")
        ticks = engine.run_until_quiet(60)
        world = engine.world
        self.assertLess(ticks, 60, "the team must go quiet on its own")
        self.assertEqual([t["status"] for t in world.tasks.values()], ["done"] * 5)
        self.assertEqual([t["assignee"] for t in world.tasks.values()], ["sage", "bolt", "iris", "tess", "quill"])
        self.assertEqual(sorted(world.files), ["docs/temperature.md", "notes/temperature-research.md",
                                               "reports/temperature.md", "src/temperature.py",
                                               "tests/test_temperature.py"])
        poll = world.polls["P-1"]
        self.assertEqual((poll["status"], poll["result"]["winner"], sorted(poll["votes"])),
                         ("closed", "ship", ["iris", "tess"]))
        self.assertTrue(replies_to_user(engine)[-1].startswith("✅ Project 'temperature' is complete"))
        self.assertIn("not run", world.tasks["T-4"]["result"], "without execution the tester must not claim a pass")
        self.assertTrue(all(a.status == "idle" for a in world.agents.values()))

    def test_handoffs_take_one_tick_each(self):
        engine = team()
        engine.user_message("nova", "Build a BMI calculator")
        engine.run_until_quiet(60)
        done = {t["title"].split(":")[0]: t["updated_tick"] for t in engine.world.tasks.values()}
        self.assertEqual(done, {"Research": 2, "Implement": 3, "Review": 4, "Test": 4, "Document": 5})

    def test_code_execution_runs_recipe_tests(self):
        engine = team(allow_code_execution=True)
        engine.user_message("nova", "Create a VAT calculator with a 7% rate")
        engine.run_until_quiet(60)
        result = engine.world.tasks["T-4"]["result"]
        self.assertRegex(result, r"^3 test\(s\) passed: tests/test_vat.py")

    def test_thai_request_in_channel_gets_channel_reply(self):
        engine = team()
        request = "\u0e0a\u0e48\u0e27\u0e22\u0e2a\u0e23\u0e49\u0e32\u0e07\u0e42\u0e1b\u0e23\u0e41\u0e01\u0e23\u0e21" \
                  "\u0e04\u0e33\u0e19\u0e27\u0e13\u0e20\u0e32\u0e29\u0e35\u0e21\u0e39\u0e25\u0e04\u0e48\u0e32" \
                  "\u0e40\u0e1e\u0e34\u0e48\u0e21"
        engine.user_message("#general", request)
        engine.run_until_quiet(60)
        self.assertIn("src/vat.py", engine.world.files)
        self.assertTrue(engine.world.messages[-1]["text"].startswith("✅"))
        self.assertEqual(engine.world.messages[-1]["to"], "#general")

    def test_unknown_request_escalates_then_user_knowledge_unblocks(self):
        engine = team()
        engine.user_message("nova", "Build a quantum flux scheduler")
        engine.run_until_quiet(60)
        implement = engine.world.tasks["T-2"]
        self.assertEqual(implement["status"], "blocked")
        self.assertIn("NotImplementedError", engine.world.files["src/quantum_flux_scheduler.py"]["content"])
        self.assertIn("is blocked", replies_to_user(engine)[-1])
        self.assertEqual(engine.world.tasks["T-3"]["status"], "todo", "review waits for the blocked implementation")
        body = "Notes.\n\n```python module\n\"\"\"Flux scheduler.\"\"\"\n\n\ndef schedule(jobs: list) -> list:\n" \
               "    \"\"\"Return jobs in priority order.\"\"\"\n    return sorted(jobs)\n```\n"
        self.assertTrue(engine.toolbox.call(USER_ID, "add_knowledge",
                                            {"title": "Flux scheduler", "body": body,
                                             "keywords": ["flux scheduler"]})["ok"])
        engine.user_message("nova", "retry")
        engine.run_until_quiet(60)
        self.assertEqual([t["status"] for t in engine.world.tasks.values()], ["done"] * 5)
        self.assertIn("def schedule", engine.world.files["src/quantum_flux_scheduler.py"]["content"])
        self.assertIn("smoke test", engine.world.tasks["T-4"]["result"])
        self.assertIn("is complete", replies_to_user(engine)[-1])

    def test_status_help_and_direct_messages(self):
        engine = team()
        engine.user_message("nova", "help")
        engine.user_message("sage", "What are you doing?")
        engine.run_until_quiet(10)
        texts = replies_to_user(engine)
        self.assertTrue(any("Commands" in t for t in texts))
        self.assertTrue(any(t.startswith("Hi! I'm Sage") for t in texts))
        self.assertEqual(engine.world.tasks, {}, "help and chat must not create projects")

    def test_two_projects_get_unique_slugs(self):
        engine = team()
        engine.user_message("nova", "Build a palindrome checker")
        engine.user_message("nova", "Another palindrome checker please")
        engine.run_until_quiet(80)
        projects = engine.world.agents["nova"].memory["projects"]
        self.assertEqual(sorted(projects), ["palindrome", "palindrome_2"])
        self.assertTrue(all(p["status"] == "done" for p in projects.values()))


class ReviewLoopTests(unittest.TestCase):
    def test_review_drill_requests_changes_then_approves(self):
        engine = Engine(settings={"auto_run": False})
        engine.load_scenario(read_scenario("review-drill"))
        engine.run_until_quiet(30)
        texts = [m["text"] for m in engine.world.messages]
        self.assertTrue(texts[0].startswith("CHANGES REQUESTED for src/legacy.py"))
        self.assertTrue(texts[1].startswith("FIXED src/legacy.py"))
        self.assertTrue(texts[2].startswith("Approved src/legacy.py v2"))
        report = analyze_python(engine.world.files["src/legacy.py"]["content"])
        self.assertEqual(review_findings(report), [])
        self.assertEqual(engine.world.tasks["T-1"]["status"], "done")

    def test_unfixable_findings_block_the_review(self):
        engine = Engine(settings={"auto_run": False})
        engine.install_team([{"id": "iris", "name": "Iris", "role": "reviewer"}])
        engine.world.write_file(USER_ID, "src/wip.py", '"""Work."""\n\n\ndef go():\n    """Go."""\n    # TODO finish\n')
        engine.world.create_task(USER_ID, "Review: wip", "Project: wip\nModule: wip", "iris")
        engine.run_until_quiet(10)
        task = engine.world.tasks["T-1"]
        self.assertEqual(task["status"], "blocked")
        self.assertIn("TODO", task["notes"][-1]["text"])

    def test_autofix_is_idempotent(self):
        source = "def f(a):\n\treturn a  \n"
        fixed, changes = autofix(source)
        self.assertTrue(changes)
        self.assertEqual(review_findings(analyze_python(fixed)), [])
        self.assertEqual(autofix(fixed), (fixed, []))


class EngineTests(unittest.TestCase):
    def test_idle_world_does_not_tick_forever(self):
        engine = team()
        self.assertFalse(engine.has_work())
        self.assertEqual(engine.run_until_quiet(10), 0)

    def test_nudge_wakes_one_agent(self):
        engine = team()
        engine.nudge("quill")
        self.assertEqual(engine.step()["acted"], ["quill"])
        self.assertFalse(engine.has_work())

    def test_background_run_reaches_waiting(self):
        engine = team(speed_ms=0)
        engine.settings["auto_run"] = True
        engine.user_message("nova", "Write a palindrome checker")
        self.assertTrue(wait_until_stopped(engine))
        self.assertEqual(engine.status, "waiting")
        self.assertEqual(len(engine.world.tasks), 5)

    def test_run_limit_pauses(self):
        engine = team(speed_ms=0, max_ticks_per_run=2)
        engine.user_message("nova", "Write a palindrome checker")
        engine.start()
        self.assertTrue(wait_until_stopped(engine))
        self.assertEqual((engine.status, engine.world.tick), ("paused", 2))

    def test_policy_crash_is_contained(self):
        engine = team()
        engine.world.agents["sage"].nudged = True
        original = engine.brains["scripted"].take_turn

        def explode(agent, observation, eng):
            if agent.id == "sage":
                raise RuntimeError("boom")
            return original(agent, observation, eng)

        engine.brains["scripted"].take_turn = explode
        engine.step()
        self.assertEqual(engine.world.agents["sage"].status, "error")
        self.assertIn("boom", engine.world.agents["sage"].status_detail)

    def test_settings_validation_and_secret_redaction(self):
        engine = team()
        with self.assertRaises(WorldError):
            engine.update_settings({"speed_ms": -1})
        with self.assertRaises(WorldError):
            engine.update_settings({"unknown": 1})
        public = engine.update_settings({"api_key": "sk-test-secret"})
        self.assertTrue(public["has_api_key"])
        self.assertNotIn("sk-test-secret", repr(public))
        self.assertNotIn("sk-test-secret", repr(engine.export_state()))
        self.assertNotIn("sk-test-secret", repr(engine.snapshot()))

    def test_state_export_import_continues_work(self):
        engine = team()
        engine.user_message("nova", "Build a fizzbuzz program")
        engine.step()
        engine.step()
        saved = engine.export_state()
        other = Engine(settings={"auto_run": False})
        other.import_state(saved)
        other.run_until_quiet(60)
        self.assertEqual([t["status"] for t in other.world.tasks.values()], ["done"] * 5)

    def test_scenarios_are_valid(self):
        ids = [item["id"] for item in list_scenarios()]
        self.assertEqual(sorted(ids), ["claude-team", "hybrid-team", "offline-team", "review-drill"])
        for scenario_id in ids:
            engine = Engine(settings={"auto_run": False})
            engine.load_scenario(read_scenario(scenario_id))
            self.assertTrue(engine.world.agents)
        with self.assertRaises(WorldError):
            read_scenario("../secrets")


class HelperTests(unittest.TestCase):
    def test_slug_and_task_context(self):
        self.assertEqual(slugify("Please build a VAT calculator for invoices"), "vat_calculator_invoices")
        self.assertEqual(slugify("\u0e2a\u0e27\u0e31\u0e2a\u0e14\u0e35"), "")
        task = {"id": "T-9", "title": "Implement: x", "description": "Project: demo\nRequest: Do it\nModule: demo_mod"}
        self.assertEqual(task_context(task), ("demo", "Do it", "demo_mod"))
        bare = {"id": "T-3", "title": "Fix login bug", "description": "details"}
        self.assertEqual(task_context(bare)[0], "fix_login_bug")


if __name__ == "__main__":
    unittest.main()
