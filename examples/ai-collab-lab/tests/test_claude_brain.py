"""Claude brain: tool-use loop, error handling and the real SDK request shape.

Most tests use a fake client. One class drives the real Anthropic SDK against a
local mock of the Messages API; it is skipped when the SDK is not installed.
"""
import json
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace as NS

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from collablab.brains import BrainUnavailable  # noqa: E402
from collablab.brains.claude import FALLBACK_BETA, ClaudeBrain  # noqa: E402
from collablab.engine import Engine  # noqa: E402
from collablab.world import USER_ID  # noqa: E402

try:
    import anthropic
except ImportError:
    anthropic = None


def text(value):
    return NS(type="text", text=value)


def use(block_id, name, args):
    return NS(type="tool_use", id=block_id, name=name, input=args)


def reply(stop, *content, usage=(10, 2)):
    return NS(stop_reason=stop, content=list(content), usage=NS(input_tokens=usage[0], output_tokens=usage[1]),
              stop_details=None)


class StatusError(Exception):
    def __init__(self, status):
        super().__init__(f"status {status}")
        self.status_code = status


class FakeClient:
    """Returns scripted responses; records every request."""

    def __init__(self, *responses):
        self.responses = list(responses)
        self.requests = []
        self.beta = NS(messages=NS(create=self.create))

    def create(self, **kwargs):
        self.requests.append({**kwargs, "messages": list(kwargs["messages"])})
        item = self.responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def claude_engine(client, **settings):
    engine = Engine(settings={"auto_run": False, **settings}, client_factory=lambda key: client)
    engine.add_agent({"id": "ava", "name": "Ava", "role": "coordinator", "brain": "claude"})
    engine.add_agent({"id": "bolt", "name": "Bolt", "role": "coder"})
    return engine


class ToolLoopTests(unittest.TestCase):
    def test_tools_run_and_all_results_return_in_one_message(self):
        client = FakeClient(
            reply("tool_use", NS(type="thinking", thinking="Plan first."), text("Creating a task."),
                  use("t1", "create_task", {"title": "Write code", "assignee": "bolt"}),
                  use("t2", "write_file", {"path": "../escape", "content": "x"})),
            reply("end_turn", text("Planned one task.")))
        engine = claude_engine(client)
        engine.user_message("ava", "Plan the work")
        engine.step()
        agent = engine.world.agents["ava"]
        self.assertEqual((agent.status, agent.status_detail), ("idle", "Planned one task."))
        self.assertEqual(engine.world.tasks["T-1"]["assignee"], "bolt")
        second = client.requests[1]["messages"]
        self.assertEqual([m["role"] for m in second], ["user", "assistant", "user"])
        results = second[2]["content"]
        self.assertEqual([(r["tool_use_id"], r["is_error"]) for r in results], [("t1", False), ("t2", True)])
        self.assertIn("invalid_path", results[1]["content"])
        thoughts = [e["summary"] for e in engine.world.events if e["type"] == "thought"]
        self.assertEqual(thoughts[:2], ["Plan first.", "Creating a task."])
        self.assertEqual((agent.stats["llm_calls"], agent.stats["input_tokens"]), (2, 20))

    def test_observation_lists_messages_tasks_and_votes(self):
        client = FakeClient(reply("end_turn", text("ok")))
        engine = claude_engine(client)
        engine.world.create_task(USER_ID, "Review spec", assignee="ava")
        engine.world.create_poll(USER_ID, "Ship?", ["ship", "hold"], ["ava"])
        engine.user_message("#general", "Morning @ava")
        engine.step()
        prompt = client.requests[0]["messages"][0]["content"]
        for expected in ("Morning @ava", "T-1 'Review spec'", "Polls waiting for your vote: P-1", "[M-1 #general]"):
            self.assertIn(expected, prompt)
        system = client.requests[0]["system"]
        self.assertIn("You are Ava (id: ava), the coordinator", system)
        self.assertIn("- bolt: Bolt, coder (scripted brain)", system)

    def test_history_is_append_only_across_turns(self):
        first_reply = reply("end_turn", text("one"))
        client = FakeClient(first_reply, reply("end_turn", text("two")))
        engine = claude_engine(client)
        engine.user_message("ava", "first")
        engine.step()
        first = list(client.requests[0]["messages"])
        engine.user_message("ava", "second")
        engine.step()
        later = client.requests[1]["messages"]
        self.assertEqual(later[: len(first)], first)
        self.assertIs(later[1]["content"], first_reply.content, "assistant content is replayed unchanged")
        self.assertEqual(len(later), 3)

    def test_turn_tool_budget_returns_errors_for_extra_calls(self):
        calls = [use(f"t{i}", "set_fact", {"key": f"k{i}", "value": "v"}) for i in range(3)]
        client = FakeClient(reply("tool_use", *calls))
        engine = claude_engine(client, max_tool_calls_per_turn=2)
        engine.user_message("ava", "go")
        engine.step()
        self.assertEqual(sorted(engine.world.facts), ["k0", "k1"])
        last = engine.claude.histories["ava"][-1]["content"]
        self.assertEqual([r["is_error"] for r in last], [False, False, True])
        self.assertEqual(len(client.requests), 1, "the turn ends when the budget is spent")

    def test_truncated_tool_use_is_not_executed(self):
        client = FakeClient(reply("max_tokens", use("t1", "write_file", {"path": "a.py", "content": "partial"})))
        engine = claude_engine(client)
        engine.user_message("ava", "go")
        engine.step()
        self.assertNotIn("a.py", engine.world.files)
        self.assertIn("cut off", engine.claude.histories["ava"][-1]["content"][0]["content"])

    def test_request_arguments(self):
        brain = ClaudeBrain()
        opus = brain.request_args(NS(model="claude-opus-5-5", effort="high"), "sys", [], [])
        self.assertEqual(opus["thinking"], {"type": "adaptive", "display": "summarized"})
        self.assertEqual(opus["output_config"], {"effort": "high"})
        self.assertEqual((opus["betas"], opus["fallbacks"]), ([FALLBACK_BETA], "default"))
        self.assertEqual(opus["cache_control"], {"type": "ephemeral"})
        haiku = brain.request_args(NS(model="claude-haiku-5-5", effort="low"), "sys", [], [])
        self.assertNotIn("fallbacks", haiku)
        self.assertNotIn("betas", haiku)

    def test_disabled_tools_are_not_offered(self):
        client = FakeClient(reply("end_turn", text("ok")), reply("end_turn", text("ok")))
        engine = claude_engine(client)
        engine.user_message("ava", "go")
        engine.step()
        names = [tool["name"] for tool in client.requests[0]["tools"]]
        self.assertNotIn("run_python", names)
        engine.update_settings({"allow_code_execution": True})
        engine.update_agent("ava", {"tools": ["send_message", "run_python"]})
        engine.user_message("ava", "again")
        engine.step()
        self.assertEqual([tool["name"] for tool in client.requests[1]["tools"]], ["send_message", "run_python"])


class FailureTests(unittest.TestCase):
    def test_refusal_is_reported_and_not_retried(self):
        refusal = reply("refusal")
        refusal.stop_details = NS(category="cyber", explanation="")
        client = FakeClient(refusal)
        engine = claude_engine(client)
        engine.user_message("ava", "something")
        engine.step()
        agent = engine.world.agents["ava"]
        self.assertIn("declined", agent.status_detail)
        self.assertEqual(engine.claude.histories["ava"], [], "a refused observation is not kept")
        self.assertFalse(engine.has_work())

    def test_transient_error_restores_inbox_and_backs_off(self):
        client = FakeClient(StatusError(529), reply("end_turn", text("recovered")))
        engine = claude_engine(client)
        engine.user_message("ava", "hello")
        engine.step()
        agent = engine.world.agents["ava"]
        self.assertEqual(agent.status, "waiting")
        self.assertEqual(engine.claude.histories["ava"], [])
        for _ in range(2):
            self.assertEqual(engine.step()["acted"], [], "backoff skips the agent for a few ticks")
        engine.step()
        self.assertEqual(agent.status_detail, "recovered")
        self.assertIn("hello", client.requests[1]["messages"][0]["content"], "the message is delivered again")

    def test_fatal_error_stops_the_run(self):
        client = FakeClient(StatusError(401))
        engine = claude_engine(client, speed_ms=0)
        engine.user_message("ava", "hello")
        engine.start()
        engine._stop.wait(5)
        for _ in range(100):
            if not engine.running:
                break
            threading.Event().wait(0.02)
        self.assertEqual(engine.status, "stopped")
        self.assertEqual(engine.world.agents["ava"].status, "error")
        self.assertFalse(engine.has_work(), "an errored agent waits for the operator")
        engine.nudge("ava")
        self.assertTrue(engine.has_work())

    def test_unprocessed_request_survives_a_fatal_error(self):
        client = FakeClient(StatusError(401))
        engine = Engine(settings={"auto_run": False}, client_factory=lambda key: client)
        engine.install_team()
        engine.update_agent("nova", {"brain": "claude"})
        engine.user_message("nova", "Build a palindrome checker")
        engine.step()
        self.assertEqual(engine.world.agents["nova"].status, "error")
        engine.update_agent("nova", {"brain": "scripted"})
        engine.nudge("nova")
        engine.run_until_quiet(40)
        self.assertEqual([t["status"] for t in engine.world.tasks.values()], ["done"] * 5)

    def test_missing_sdk_or_credentials_is_fatal_with_guidance(self):
        def factory(key):
            raise BrainUnavailable("The Claude brain needs the Anthropic SDK: pip install anthropic")
        engine = Engine(settings={"auto_run": False}, client_factory=factory)
        engine.add_agent({"id": "ava", "name": "Ava", "role": "coordinator", "brain": "claude"})
        engine.user_message("ava", "hi")
        engine.step()
        self.assertIn("pip install anthropic", engine.world.agents["ava"].status_detail)

    def test_llm_budget_stops_claude_agents(self):
        client = FakeClient(reply("tool_use", use("t1", "send_message", {"to": "#general", "text": "a"})))
        engine = claude_engine(client, max_llm_calls=1)
        engine.user_message("ava", "go")
        engine.step()
        self.assertEqual(engine.llm_calls, 1)
        self.assertIn("budget", engine.world.agents["ava"].status_detail)
        self.assertEqual(len(client.requests), 1)
        engine.user_message("ava", "more")
        ava = engine.world.agents["ava"]
        engine.backoff.clear()
        self.assertFalse(engine.is_awake(ava), "Claude agents sleep once the budget is spent")
        engine.update_settings({"max_llm_calls": 5})
        self.assertTrue(engine.is_awake(ava))


class MockMessagesApi(BaseHTTPRequestHandler):
    def log_message(self, *args):
        return

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.requests.append({"path": self.path, "headers": dict(self.headers), "body": body})
        status, payload = self.server.replies.pop(0)
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def message(stop, content):
    return {"id": "msg_test", "type": "message", "role": "assistant", "model": "claude-opus-5-5", "content": content,
            "stop_reason": stop, "stop_sequence": None, "usage": {"input_tokens": 12, "output_tokens": 3}}


@unittest.skipIf(anthropic is None, "Anthropic SDK not installed; real SDK request shape not exercised")
class RealSdkTests(unittest.TestCase):
    def setUp(self):
        self.api = ThreadingHTTPServer(("127.0.0.1", 0), MockMessagesApi)
        self.api.requests, self.api.replies = [], []
        threading.Thread(target=self.api.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{self.api.server_address[1]}"
        self.engine = Engine(settings={"auto_run": False}, client_factory=lambda key: anthropic.Anthropic(
            api_key="test-key", base_url=url, max_retries=0))
        self.engine.add_agent({"id": "ava", "name": "Ava", "role": "coordinator", "brain": "claude"})

    def tearDown(self):
        self.api.shutdown()
        self.api.server_close()

    def test_sdk_round_trip_with_tool_use(self):
        self.api.replies = [
            (200, message("tool_use", [{"type": "thinking", "thinking": "Short plan.", "signature": "sig"},
                                       {"type": "tool_use", "id": "toolu_1", "name": "set_fact",
                                        "input": {"key": "plan", "value": "ready"}}])),
            (200, message("end_turn", [{"type": "text", "text": "Done."}])),
        ]
        self.engine.user_message("ava", "Publish the plan")
        self.engine.step()
        self.assertEqual(self.engine.world.facts["plan"]["value"], "ready")
        self.assertEqual(self.engine.world.agents["ava"].status_detail, "Done.")
        first, second = self.api.requests
        self.assertTrue(first["path"].startswith("/v1/messages"))
        self.assertIn(FALLBACK_BETA, first["headers"].get("anthropic-beta", ""))
        body = first["body"]
        self.assertEqual(body["model"], "claude-opus-5-5")
        self.assertEqual(body["fallbacks"], "default")
        self.assertEqual(body["thinking"], {"type": "adaptive", "display": "summarized"})
        self.assertEqual(body["output_config"], {"effort": "medium"})
        self.assertEqual(body["cache_control"], {"type": "ephemeral"})
        self.assertIn("set_fact", [tool["name"] for tool in body["tools"]])
        replayed = second["body"]["messages"]
        self.assertEqual(replayed[1]["content"][0], {"type": "thinking", "thinking": "Short plan.", "signature": "sig"})
        self.assertEqual(replayed[2]["content"][0]["tool_use_id"], "toolu_1")

    def test_sdk_errors_are_classified(self):
        error = {"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}
        self.api.replies = [(401, error)]
        self.engine.user_message("ava", "hi")
        self.engine.step()
        agent = self.engine.world.agents["ava"]
        self.assertEqual(agent.status, "error")
        self.assertIn("Authentication failed", agent.status_detail)
        self.engine.nudge("ava")
        self.api.replies = [(429, {"type": "error", "error": {"type": "rate_limit_error", "message": "slow down"}})]
        self.engine.step()
        self.assertEqual(agent.status, "waiting")
        self.assertIn("Rate limited", agent.status_detail)


if __name__ == "__main__":
    unittest.main()
