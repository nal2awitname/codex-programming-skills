"""World rules and tool validation."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from collablab import knowledge  # noqa: E402
from collablab.tools import REGISTRY, Toolbox, analyze_python, catalog, evaluate  # noqa: E402
from collablab.world import USER_ID, Agent, World, WorldError  # noqa: E402


def make_world():
    world = World()
    world.add_agent(Agent(id="ada", name="Ada", role="coder"))
    world.add_agent(Agent(id="bo", name="Bo", role="reviewer"))
    return world


class WorldTests(unittest.TestCase):
    def test_message_routing_and_unread(self):
        world = make_world()
        world.post_message(USER_ID, "ada", "direct")
        world.post_message("bo", "#general", "hello @ada")
        world.post_message("ada", "#dev", "own message")
        ada = [m["text"] for m in world.unread("ada", 0)]
        self.assertEqual(ada, ["direct", "hello @ada"])
        self.assertEqual([m["text"] for m in world.unread("bo", 0)], ["own message"])
        self.assertEqual(world.messages[1]["mentions"], ["ada"])
        self.assertEqual([m["text"] for m in world.unread(USER_ID, 0)], [])

    def test_message_validation(self):
        world = make_world()
        for to, text, code in (("#nope", "x", "unknown_channel"), ("ghost", "x", "unknown_participant"),
                               ("ada", "   ", "invalid_argument"), ("ada", "x" * 9000, "too_large")):
            with self.assertRaises(WorldError) as caught:
                world.post_message(USER_ID, to, text)
            self.assertEqual(caught.exception.code, code)
        with self.assertRaises(WorldError):
            world.post_message("ada", "ada", "self")

    def test_task_dependencies_and_change_tracking(self):
        world = make_world()
        first = world.create_task(USER_ID, "Research", assignee="ada")
        second = world.create_task(USER_ID, "Build", assignee="bo", depends_on=[first["id"]])
        with self.assertRaises(WorldError) as caught:
            world.update_task("bo", second["id"], status="in_progress")
        self.assertEqual(caught.exception.code, "dependencies_pending")
        cursor = world.seq
        world.update_task("ada", first["id"], status="done", result="ok")
        self.assertEqual([t["id"] for t in world.task_changes_for("bo", cursor)], [first["id"]])
        self.assertEqual(world.task_changes_for("ada", cursor), [], "own changes must not wake the author")
        world.update_task("bo", second["id"], status="in_progress", note="started")
        self.assertEqual(world.tasks[second["id"]]["notes"][0]["author"], "bo")
        with self.assertRaises(WorldError):
            world.update_task("bo", second["id"])

    def test_paths_are_confined_to_workspace(self):
        world = make_world()
        for bad in ("../x", "/etc/passwd", "C:/x", "a/../../b", ".hidden", "src/.git/config", "", "a\0b"):
            with self.assertRaises(WorldError, msg=bad):
                world.write_file(USER_ID, bad, "x")
        record = world.write_file(USER_ID, "src\\app.py", "print(1)\n")
        self.assertEqual(record["path"], "src/app.py")
        self.assertEqual(world.write_file(USER_ID, "./src/app.py", "")["version"], 2)

    def test_polls_close_when_all_voters_voted(self):
        world = make_world()
        poll = world.create_poll("ada", "Ship?", ["ship", "hold"], ["ada", "bo"])
        with self.assertRaises(WorldError):
            world.vote(USER_ID, poll["id"], "ship")
        world.vote("ada", poll["id"], "ship")
        self.assertEqual(poll["status"], "open")
        world.vote("bo", poll["id"], "ship")
        self.assertEqual(poll["status"], "closed")
        self.assertEqual(poll["result"]["winner"], "ship")
        with self.assertRaises(WorldError):
            world.vote("bo", poll["id"], "hold")

    def test_export_import_round_trip(self):
        world = make_world()
        world.post_message(USER_ID, "ada", "hi")
        world.write_file("ada", "notes/a.md", "# A\n")
        world.create_task(USER_ID, "Task", assignee="bo")
        world.add_document(USER_ID, "Custom", "Body", ["custom"])
        world.agents["ada"].memory["projects"] = {"x": {"status": "active"}}
        data = world.export()
        restored = World()
        restored.load(data)
        self.assertEqual(restored.files["notes/a.md"]["content"], "# A\n")
        self.assertEqual(restored.agents["ada"].memory["projects"]["x"]["status"], "active")
        self.assertIn("note-1", [d["id"] for d in restored.documents])
        self.assertEqual(len(restored.documents), len(world.documents))
        with self.assertRaises(WorldError):
            restored.load({"format": "other"})
        broken = world.export()
        broken["agents"][0]["role"] = "wizard"
        with self.assertRaises(WorldError):
            restored.load(broken)
        self.assertIn("ada", restored.agents, "a failed import must leave the previous state intact")

    def test_agent_validation(self):
        world = make_world()
        for bad in (Agent(id="Bad Id", name="x", role="coder"), Agent(id="user", name="x", role="coder"),
                    Agent(id="ok", name="x", role="wizard"), Agent(id="ok2", name="x", role="coder", color="red")):
            with self.assertRaises(WorldError):
                world.add_agent(bad)
        with self.assertRaises(WorldError):
            world.add_agent(Agent(id="ada", name="Dup", role="coder"))
        world.update_agent("ada", {"brain": "claude", "effort": "high"})
        with self.assertRaises(WorldError):
            world.update_agent("ada", {"effort": "extreme"})
        self.assertEqual(world.agents["ada"].effort, "high")


class ToolTests(unittest.TestCase):
    def setUp(self):
        self.world = make_world()
        self.settings = {"allow_code_execution": False}
        self.tools = Toolbox(self.world, self.settings)

    def test_catalog_is_complete_and_schemas_are_strict(self):
        self.assertGreaterEqual(len(REGISTRY), 30)
        for spec in catalog():
            schema = spec["input_schema"]
            self.assertFalse(schema["additionalProperties"])
            self.assertTrue(set(schema["required"]) <= set(schema["properties"]), spec["name"])
            self.assertTrue(spec["description"])

    def test_argument_validation_errors_are_structured(self):
        cases = [("send_message", {"to": "#general"}, "invalid_arguments"),
                 ("send_message", {"to": "#general", "text": "x", "extra": 1}, "invalid_arguments"),
                 ("read_messages", {"with": "#general", "limit": True}, "invalid_arguments"),
                 ("update_task", {"task_id": "T-1", "status": "finished"}, "invalid_arguments"),
                 ("nope", {}, "unknown_tool"),
                 ("run_python", {"path": "x.py"}, "disabled")]
        for name, args, code in cases:
            outcome = self.tools.call("ada", name, args)
            self.assertFalse(outcome["ok"], name)
            self.assertEqual(outcome["error"]["code"], code, name)
        self.assertEqual(self.world.agents["ada"].stats["errors"], len(cases))

    def test_permissions_limit_tools(self):
        self.world.agents["bo"].tools = ["read_file"]
        outcome = self.tools.call("bo", "write_file", {"path": "a.txt", "content": "x"})
        self.assertEqual(outcome["error"]["code"], "not_allowed")
        self.assertEqual([s.name for s in self.tools.available("bo")], ["read_file"])

    def test_calculate_is_safe(self):
        self.assertAlmostEqual(evaluate("(37 * 9 / 5) + 32"), 98.6)
        self.assertAlmostEqual(evaluate("sqrt(16) + pi - pi"), 4.0)
        for bad in ("__import__('os')", "().__class__", "2 ** 100000", "9 ** 9 ** 9", "1/0", "x", "open('f')", "[1]"):
            with self.assertRaises(WorldError, msg=bad):
                evaluate(bad)

    def test_check_python_never_executes(self):
        self.world.write_file(USER_ID, "src/boom.py", "raise SystemExit('executed')\n\ndef f(x):\n    return x\n")
        outcome = self.tools.call(USER_ID, "check_python", {"path": "src/boom.py"})
        self.assertTrue(outcome["ok"])
        self.assertEqual([f["name"] for f in outcome["result"]["functions"]], ["f"])
        report = analyze_python("def f(:\n")
        self.assertFalse(report["syntax_ok"])
        self.assertEqual(report["error"]["line"], 1)

    def test_run_python_executes_in_a_copy_when_enabled(self):
        self.settings["allow_code_execution"] = True
        self.world.write_file(USER_ID, "src/mod.py", "VALUE = 41\n")
        self.world.write_file(USER_ID, "main.py", "import sys\nsys.path.insert(0, 'src')\nimport mod\n"
                                                  "open('created.txt', 'w').write('x')\nprint(mod.VALUE + 1)\n")
        outcome = self.tools.call(USER_ID, "run_python", {"path": "main.py", "timeout_seconds": 10})
        self.assertTrue(outcome["ok"], outcome)
        self.assertEqual(outcome["result"]["stdout"].strip(), "42")
        self.assertNotIn("created.txt", self.world.files, "runs must not write back into the workspace")
        self.world.write_file(USER_ID, "loop.py", "while True:\n    pass\n")
        slow = self.tools.call(USER_ID, "run_python", {"path": "loop.py", "timeout_seconds": 1})
        self.assertTrue(slow["result"]["timed_out"])

    def test_tool_calls_are_logged(self):
        self.tools.call("ada", "set_fact", {"key": "lang", "value": "python"})
        event = self.world.events[-1]
        self.assertEqual((event["type"], event["actor"], event["data"]["tool"]), ("tool_call", "ada", "set_fact"))
        self.assertEqual(self.world.facts["lang"]["value"], "python")

    def test_memory_is_private_to_agents(self):
        self.assertTrue(self.tools.call("ada", "remember", {"key": "plan", "value": "x"})["ok"])
        self.assertEqual(self.tools.call("ada", "recall", {"key": "plan"})["result"]["value"], "x")
        self.assertEqual(self.tools.call("bo", "recall", {"key": "plan"})["result"]["value"], None)
        self.assertEqual(self.tools.call(USER_ID, "recall", {})["error"]["code"], "not_allowed")


class KnowledgeTests(unittest.TestCase):
    def test_recipes_parse_with_code_and_match_thai_keywords(self):
        documents = knowledge.load_builtin()
        recipes = [d for d in documents if d["kind"] == "recipe"]
        self.assertGreaterEqual(len(recipes), 10)
        for recipe in recipes:
            self.assertIn("module", recipe["code"], recipe["id"])
            self.assertIn("tests", recipe["code"], recipe["id"])
            self.assertTrue(recipe["module"].isidentifier(), recipe["id"])
        thai_request = "\u0e0a\u0e48\u0e27\u0e22\u0e17\u0e33\u0e15\u0e31\u0e27\u0e41\u0e1b\u0e25\u0e07" \
                       "\u0e2d\u0e38\u0e13\u0e2b\u0e20\u0e39\u0e21\u0e34"
        self.assertEqual(knowledge.search(documents, thai_request, 1)[0]["id"], "temperature")
        self.assertEqual(knowledge.search(documents, "compute VAT on an invoice", 1)[0]["id"], "vat")
        self.assertEqual(knowledge.search(documents, "zzzz qqqq"), [])


if __name__ == "__main__":
    unittest.main()
