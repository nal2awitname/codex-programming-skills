"""HTTP API, static files and request protections."""
import http.client
import json
import sys
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from collablab.engine import Engine  # noqa: E402
from collablab.server import make_server  # noqa: E402


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.engine = Engine(settings={"speed_ms": 0})
        self.engine.install_team()
        self.server = make_server(self.engine, "127.0.0.1", 0)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.engine.pause(wait=5)
        self.server.shutdown()
        self.server.server_close()

    def request(self, method, path, body=None, headers=None, raw=False):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        default = {"X-Collab-Lab": "1", "Content-Type": "application/json"} if method == "POST" else {}
        default.update(headers or {})
        payload = json.dumps(body).encode() if body is not None else None
        connection.request(method, path, body=payload, headers=default)
        response = connection.getresponse()
        data = response.read()
        connection.close()
        if raw:
            return response, data
        return response.status, json.loads(data)

    def wait_idle(self, timeout=15):
        deadline = time.monotonic() + timeout
        while self.engine.running and time.monotonic() < deadline:
            time.sleep(0.02)

    def test_static_files_and_security_headers(self):
        for path, kind in (("/", "text/html"), ("/static/app.js", "text/javascript"), ("/static/style.css", "text/css"),
                           ("/static/icon.svg", "image/svg+xml")):
            response, body = self.request("GET", path, raw=True)
            self.assertEqual(response.status, 200, path)
            self.assertTrue(response.getheader("Content-Type").startswith(kind), path)
            self.assertIn("script-src 'self'", response.getheader("Content-Security-Policy"))
            self.assertTrue(body)
        status, data = self.request("GET", "/static/../server.py")
        self.assertEqual(status, 404)

    def test_state_meta_and_incremental_updates(self):
        status, meta = self.request("GET", "/api/meta")
        self.assertEqual(status, 200)
        self.assertGreaterEqual(len(meta["tools"]), 30)
        self.assertIn("claude-opus-5-5", meta["models"])
        _, state = self.request("GET", "/api/state")
        self.assertEqual(len(state["agents"]), 6)
        seq = state["seq"]
        self.engine.world.post_message("user", "#general", "hello")
        _, later = self.request("GET", f"/api/state?since={seq}")
        self.assertEqual([m["text"] for m in later["messages"]], ["hello"])
        self.assertTrue(all(e["id"] > seq for e in later["events"]))

    def test_post_requires_custom_header_json_and_known_host(self):
        status, data = self.request("POST", "/api/message", {"to": "nova", "text": "hi"}, {"X-Collab-Lab": ""})
        self.assertEqual((status, data["error"]["code"]), (403, "missing_header"))
        status, data = self.request("POST", "/api/message", {"to": "nova", "text": "hi"},
                                    {"Content-Type": "text/plain"})
        self.assertEqual(status, 415)
        status, data = self.request("GET", "/api/state", headers={"Host": "attacker.example"})
        self.assertEqual((status, data["error"]["code"]), (403, "bad_host"))
        status, _ = self.request("GET", "/api/state", headers={"Host": f"localhost:{self.port}"})
        self.assertEqual(status, 200)
        self.assertEqual(self.engine.world.messages, [])

    def test_message_runs_the_team_to_completion(self):
        status, data = self.request("POST", "/api/message", {"to": "nova", "text": "Build a fizzbuzz program"})
        self.assertEqual((status, data["ok"]), (200, True))
        self.wait_idle()
        _, state = self.request("GET", "/api/state")
        self.assertEqual([t["status"] for t in state["tasks"]], ["done"] * 5)
        self.assertEqual(state["engine"]["status"], "waiting")
        status, record = self.request("GET", "/api/file?path=src/fizzbuzz.py")
        self.assertEqual(status, 200)
        self.assertIn("def fizzbuzz", record["content"])
        status, data = self.request("GET", "/api/file?path=../secret")
        self.assertEqual((status, data["error"]["code"]), (400, "invalid_path"))

    def test_tool_console_and_validation_errors(self):
        status, data = self.request("POST", "/api/tool", {"name": "calculate", "args": {"expression": "6*7"}})
        self.assertEqual((status, data["result"]["value"]), (200, 42))
        status, data = self.request("POST", "/api/tool", {"name": "calculate", "args": {"expression": "__import__('os')"}})
        self.assertEqual((status, data["error"]["code"]), (400, "invalid_expression"))
        status, data = self.request("POST", "/api/message", {"to": "#missing", "text": "x"})
        self.assertEqual(status, 400)

    def test_agent_management(self):
        status, data = self.request("POST", "/api/agents", {"action": "add", "agent": {
            "id": "orion", "name": "Orion", "role": "custom", "brain": "claude", "color": "#123456"}})
        self.assertEqual(status, 200)
        self.assertEqual(data["agent"]["model"], "claude-opus-5-5")
        status, data = self.request("POST", "/api/agents", {"action": "update", "id": "orion",
                                                            "changes": {"effort": "low", "tools": ["send_message"]}})
        self.assertEqual((data["agent"]["effort"], data["agent"]["tools"]), ("low", ["send_message"]))
        status, data = self.request("GET", "/api/agent?id=orion")
        self.assertEqual((status, data["history_turns"]), (200, 0))
        status, data = self.request("POST", "/api/agents", {"action": "update", "id": "orion", "changes": {"role": "x"}})
        self.assertEqual(status, 400)
        status, _ = self.request("POST", "/api/agents", {"action": "remove", "id": "orion"})
        self.assertEqual(status, 200)
        self.assertNotIn("orion", self.engine.world.agents)

    def test_settings_hide_the_api_key(self):
        status, data = self.request("POST", "/api/settings", {"api_key": "sk-secret-value", "speed_ms": 100})
        self.assertEqual(status, 200)
        self.assertTrue(data["settings"]["has_api_key"])
        response, body = self.request("GET", "/api/state", raw=True)
        self.assertNotIn(b"sk-secret-value", body)
        response, body = self.request("GET", "/api/export", raw=True)
        self.assertNotIn(b"sk-secret-value", body)
        self.assertIn("attachment", response.getheader("Content-Disposition"))
        status, data = self.request("POST", "/api/settings", {"speed_ms": "fast"})
        self.assertEqual(status, 400)

    def test_export_import_and_scenarios(self):
        self.request("POST", "/api/tool", {"name": "write_file", "args": {"path": "notes/keep.md", "content": "keep"}})
        response, body = self.request("GET", "/api/export", raw=True)
        state = json.loads(body)
        self.request("POST", "/api/control", {"action": "clear"})
        self.assertEqual(self.engine.world.files, {})
        status, _ = self.request("POST", "/api/import", {"state": state})
        self.assertEqual(status, 200)
        self.assertIn("notes/keep.md", self.engine.world.files)
        status, data = self.request("POST", "/api/import", {"state": {"format": "nope"}})
        self.assertEqual((status, data["error"]["code"]), (400, "invalid_state"))
        status, _ = self.request("POST", "/api/scenario", {"id": "review-drill"})
        self.assertEqual(status, 200)
        self.assertEqual(sorted(self.engine.world.agents), ["bolt", "iris", "nova"])
        status, _ = self.request("POST", "/api/scenario", {"id": "../../etc/passwd"})
        self.assertEqual(status, 400)

    def test_controls(self):
        status, data = self.request("POST", "/api/control", {"action": "explode"})
        self.assertEqual(status, 400)
        self.engine.nudge("quill")
        self.engine.settings["auto_run"] = False
        status, _ = self.request("POST", "/api/control", {"action": "step"})
        self.assertEqual(status, 200)
        deadline = time.monotonic() + 5
        while self.engine.world.tick < 1 and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertEqual(self.engine.world.tick, 1)
        status, _ = self.request("POST", "/api/control", {"action": "reset"})
        self.assertEqual((status, self.engine.world.tick, len(self.engine.world.agents)), (200, 0, 6))

    def test_knowledge_endpoint(self):
        status, data = self.request("GET", "/api/knowledge?q=palindrome")
        self.assertEqual(data["results"][0]["id"], "palindrome")
        status, data = self.request("GET", "/api/knowledge?id=palindrome")
        self.assertIn("is_palindrome", data["code"]["module"])
        status, data = self.request("GET", "/api/knowledge?id=missing")
        self.assertEqual(status, 400)


if __name__ == "__main__":
    unittest.main()
