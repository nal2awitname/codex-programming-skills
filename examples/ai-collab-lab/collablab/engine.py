"""Simulation engine: decides who acts, runs turns and enforces budgets.

Time advances in ticks. At each tick every *awake* agent takes one turn in
roster order. An agent is awake when it has unread messages, when a task or
poll it cares about was changed by someone else, or when the operator nudged
it. When nobody is awake the run pauses until something new happens.
"""
from __future__ import annotations

import copy
import json
import threading
import time
from pathlib import Path

from .brains import TurnResult
from .brains.claude import ClaudeBrain
from .brains.scripted import ScriptedBrain
from .tools import Toolbox
from .world import DEFAULT_MODEL, USER_ID, Agent, World, WorldError

SCENARIO_DIR = Path(__file__).resolve().parent.parent / "scenarios"
DEFAULT_SETTINGS = {
    "speed_ms": 350,
    "max_ticks_per_run": 200,
    "max_llm_calls": 60,
    "max_tool_calls_per_turn": 8,
    "allow_code_execution": False,
    "auto_run": True,
    "default_model": DEFAULT_MODEL,
    "api_key": None,
}
SETTING_TYPES = {"speed_ms": (int, 0, 5000), "max_ticks_per_run": (int, 1, 5000), "max_llm_calls": (int, 0, 5000),
                 "max_tool_calls_per_turn": (int, 1, 40), "allow_code_execution": (bool,), "auto_run": (bool,),
                 "default_model": (str,), "api_key": (str,)}
DEFAULT_TEAM = [
    {"id": "nova", "name": "Nova", "role": "coordinator", "color": "#7c5cff",
     "persona": "Calm project lead who plans, delegates and reports back."},
    {"id": "sage", "name": "Sage", "role": "researcher", "color": "#22a699",
     "persona": "Curious researcher who cites the knowledge base."},
    {"id": "bolt", "name": "Bolt", "role": "coder", "color": "#ef8a17",
     "persona": "Pragmatic engineer who writes small, documented modules."},
    {"id": "iris", "name": "Iris", "role": "reviewer", "color": "#e0457b",
     "persona": "Meticulous reviewer who enforces the checklist."},
    {"id": "tess", "name": "Tess", "role": "tester", "color": "#3b82f6",
     "persona": "Skeptical tester who wants proof."},
    {"id": "quill", "name": "Quill", "role": "writer", "color": "#7aa52a",
     "persona": "Clear technical writer."},
]
BACKOFF_TICKS = 3


class Engine:
    def __init__(self, world: World | None = None, settings: dict | None = None, client_factory=None):
        self.world = world or World()
        self.settings = copy.deepcopy(DEFAULT_SETTINGS)
        self.llm_calls = 0
        self._budget_logged = False
        if settings:
            self.update_settings(settings)
        self.toolbox = Toolbox(self.world, self.settings)
        self.claude = ClaudeBrain(client_factory)
        self.brains = {"scripted": ScriptedBrain(), "claude": self.claude}
        self.status = "idle"
        self.status_detail = "Send a request to start."
        self.backoff: dict[str, int] = {}
        self._step_lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    # ----------------------------------------------------------- settings
    def update_settings(self, changes: dict) -> dict:
        clean = {}
        for key, value in changes.items():
            if key not in SETTING_TYPES:
                raise WorldError("invalid_argument", f"Unknown setting '{key}'")
            kind = SETTING_TYPES[key]
            if key == "api_key":
                clean[key] = (value.strip() or None) if isinstance(value, str) else None
                continue
            if kind[0] is int and (not isinstance(value, int) or isinstance(value, bool)
                                   or not kind[1] <= value <= kind[2]):
                raise WorldError("invalid_argument", f"{key} must be an integer from {kind[1]} to {kind[2]}")
            if kind[0] is not int and not isinstance(value, kind[0]):
                raise WorldError("invalid_argument", f"{key} must be a {kind[0].__name__}")
            if key == "default_model":
                value = value.strip()
                if not value or len(value) > 80:
                    raise WorldError("invalid_argument", "default_model must be 1-80 characters")
            clean[key] = value
        with self.world.lock:
            self.settings.update(clean)
            if "max_llm_calls" in clean:
                self._budget_logged = False
        return self.public_settings()

    def public_settings(self) -> dict:
        data = {key: value for key, value in self.settings.items() if key != "api_key"}
        data["has_api_key"] = bool(self.settings.get("api_key"))
        data["llm_calls_used"] = self.llm_calls
        return data

    # --------------------------------------------------------------- team
    def install_team(self, members: list[dict] | None = None) -> None:
        with self.world.lock:
            for member in members if members is not None else DEFAULT_TEAM:
                self.add_agent(dict(member))

    def add_agent(self, data: dict) -> Agent:
        data = dict(data)
        data.setdefault("model", self.settings["default_model"])
        allowed = {"id", "name", "role", "brain", "model", "effort", "persona", "tools", "color", "channels"}
        unknown = set(data) - allowed
        if unknown:
            raise WorldError("invalid_argument", f"Unknown agent fields: {', '.join(sorted(unknown))}")
        if "channels" not in data:
            data["channels"] = list(self.world.channels)
        try:
            agent = Agent(**data)
        except TypeError as error:
            raise WorldError("invalid_argument", f"Agent needs id, name and role ({error})") from None
        with self.world.lock:
            return self.world.add_agent(agent)

    def update_agent(self, agent_id: str, changes: dict) -> Agent:
        with self.world.lock:
            agent = self.world.update_agent(agent_id, changes)
            if "brain" in changes or "model" in changes:
                self.claude.forget(agent_id)
            if agent.status == "error":
                agent.status, agent.status_detail = "idle", ""
            return agent

    def remove_agent(self, agent_id: str) -> None:
        with self.world.lock:
            self.world.remove_agent(agent_id)
            self.claude.forget(agent_id)
            self.backoff.pop(agent_id, None)

    def nudge(self, agent_id: str) -> None:
        with self.world.lock:
            agent = self.world.get_agent(agent_id)
            agent.nudged = True
            if agent.status == "error":
                agent.status, agent.status_detail = "idle", ""
            self.backoff.pop(agent_id, None)
            self.world.log("nudge", USER_ID, f"nudged {agent.name}", agent=agent_id)

    # ------------------------------------------------------------ budgets
    def reserve_llm_call(self) -> bool:
        with self.world.lock:
            if self.llm_calls >= self.settings["max_llm_calls"]:
                if not self._budget_logged:
                    self.world.log("system", "system", "LLM call budget reached; Claude agents are waiting. "
                                                       "Raise it in Settings to continue.")
                    self._budget_logged = True
                return False
            self.llm_calls += 1
            return True

    def record_usage(self, agent: Agent, usage) -> None:
        with self.world.lock:
            agent.stats["llm_calls"] += 1
            if usage is not None:
                agent.stats["input_tokens"] += int(getattr(usage, "input_tokens", 0) or 0)
                agent.stats["output_tokens"] += int(getattr(usage, "output_tokens", 0) or 0)

    # ---------------------------------------------------------- scheduling
    def is_awake(self, agent: Agent, horizon: int | None = None) -> bool:
        world = self.world
        if agent.nudged:
            return True
        if agent.status == "error" or self.backoff.get(agent.id, -1) > world.tick:
            return False
        if agent.brain == "claude" and self.llm_calls >= self.settings["max_llm_calls"]:
            return False
        return bool(world.unread(agent.id, agent.inbox_cursor, horizon)
                    or world.task_changes_for(agent.id, agent.task_cursor, horizon)
                    or world.poll_changes_for(agent.id, agent.task_cursor, horizon))

    def observe(self, agent: Agent, horizon: int) -> dict:
        """What changed for an agent up to the start of this tick (later changes arrive next tick)."""
        world = self.world
        observation = {
            "tick": world.tick,
            "messages": world.unread(agent.id, agent.inbox_cursor, horizon),
            "task_changes": world.task_changes_for(agent.id, agent.task_cursor, horizon),
            "poll_changes": world.poll_changes_for(agent.id, agent.task_cursor, horizon),
            "nudged": agent.nudged,
            "cursors": (agent.inbox_cursor, agent.task_cursor),
        }
        agent.inbox_cursor = agent.task_cursor = max(horizon, agent.inbox_cursor)
        agent.nudged = False
        return observation

    def step(self) -> dict:
        """Advance one tick; returns the ids of agents that acted."""
        with self._step_lock:
            with self.world.lock:
                self.world.tick += 1
                horizon = self.world.seq
                queue = [agent.id for agent in self.world.agents.values() if self.is_awake(agent, horizon)]
            acted = []
            for agent_id in queue:
                with self.world.lock:
                    agent = self.world.agents.get(agent_id)
                    if agent is None or not self.is_awake(agent, horizon):
                        continue
                    observation = self.observe(agent, horizon)
                    agent.status = "thinking" if agent.brain == "claude" else "working"
                    agent.status_detail = ""
                result = self._run_turn(agent, observation)
                acted.append(agent_id)
                with self.world.lock:
                    self._finish_turn(agent, observation, result)
            return {"tick": self.world.tick, "acted": acted}

    def _run_turn(self, agent: Agent, observation: dict) -> TurnResult:
        try:
            return self.brains[agent.brain].take_turn(agent, observation, self)
        except Exception as error:  # a policy bug must not kill the simulation thread
            return TurnResult(error=f"{type(error).__name__}: {error}", fatal=True)

    def _finish_turn(self, agent: Agent, observation: dict, result: TurnResult) -> None:
        world = self.world
        agent.stats["turns"] += 1
        if result.error:
            agent.stats["errors"] += 1
            world.log("error", agent.id, result.error)
            if result.retry or result.requeue:
                agent.inbox_cursor, agent.task_cursor = observation["cursors"]
            if result.retry:
                self.backoff[agent.id] = world.tick + BACKOFF_TICKS
                agent.status, agent.status_detail = "waiting", result.error
            elif result.fatal:
                agent.status, agent.status_detail = "error", result.error
                if agent.brain == "claude":
                    self.status, self.status_detail = "stopped", f"{agent.name}: {result.error}"
                    self._stop.set()
            else:
                agent.status, agent.status_detail = "idle", result.error
        else:
            agent.status, agent.status_detail = "idle", result.summary[:200]
        if result.summary and result.summary != "nothing to do":
            world.log("turn", agent.id, f"{agent.name}: {result.summary}", tool_calls=result.tool_calls,
                      llm_calls=result.llm_calls)

    def has_work(self) -> bool:
        with self.world.lock:
            return any(self.is_awake(agent) for agent in self.world.agents.values())

    def run_until_quiet(self, max_ticks: int = 200) -> int:
        """Run synchronously until nobody is awake; returns ticks used."""
        ticks = 0
        while ticks < max_ticks and self.has_work():
            self.step()
            ticks += 1
        return ticks

    # ---------------------------------------------------------- background
    @property
    def running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def start(self) -> None:
        with self.world.lock:
            if self.running:
                return
            self._stop.clear()
            self.status, self.status_detail = "running", ""
            self._thread = threading.Thread(target=self._loop, name="collab-lab-engine", daemon=True)
            self._thread.start()

    def pause(self, wait: float = 30.0) -> None:
        self._stop.set()
        thread = self._thread
        if thread is not None and thread is not threading.current_thread():
            thread.join(wait)
        with self.world.lock:
            if self.status in {"running", "paused"} and not self.running:
                self.status, self.status_detail = "paused", "Paused by the operator."

    def _loop(self) -> None:
        ticks = 0
        try:
            while not self._stop.is_set():
                with self.world.lock:
                    # Checked under the lock so a message posted right now is never stranded.
                    if not self.has_work():
                        self._exit("waiting", "Everyone is idle. Send a message to continue.")
                        return
                self.step()
                ticks += 1
                if ticks >= self.settings["max_ticks_per_run"]:
                    self._exit("paused", f"Stopped after {ticks} ticks (run limit).")
                    return
                self._stop.wait(self.settings["speed_ms"] / 1000)
            if self.status == "running":
                self._exit("paused", "Paused.")
            else:
                self._exit(self.status, self.status_detail)
        except Exception as error:  # surface unexpected failures in the GUI instead of dying silently
            self._exit("stopped", f"Engine error: {error}")
            with self.world.lock:
                self.world.log("error", "system", f"Engine error: {error}")

    def _exit(self, status: str, detail: str) -> None:
        with self.world.lock:
            if self._thread is threading.current_thread():
                self._thread = None
            self.status, self.status_detail = status, detail

    # --------------------------------------------------------- operations
    def user_message(self, to: str, text: str) -> dict:
        outcome = self.toolbox.call(USER_ID, "send_message", {"to": to, "text": text})
        if outcome["ok"] and self.settings["auto_run"]:
            self.start()
        return outcome

    def reset(self, team: bool = True) -> None:
        self.pause()
        with self.world.lock:
            self.world.reset()
            self.claude.forget()
            self.backoff.clear()
            self.llm_calls = 0
            self._budget_logged = False
            self.status, self.status_detail = "idle", "Send a request to start."
            if team:
                self.install_team()

    def load_scenario(self, scenario: dict) -> None:
        if not isinstance(scenario, dict) or not isinstance(scenario.get("agents"), list):
            raise WorldError("invalid_argument", "A scenario needs an 'agents' list")
        self.reset(team=False)
        with self.world.lock:
            if scenario.get("settings"):
                self.update_settings({k: v for k, v in scenario["settings"].items() if k != "api_key"})
            self.install_team(scenario["agents"])
            for item in scenario.get("files", []):
                self.world.write_file(USER_ID, item["path"], item["content"])
            for item in scenario.get("tasks", []):
                self.world.create_task(USER_ID, item["title"], item.get("description", ""), item.get("assignee"),
                                       item.get("depends_on"))
            self.world.log("system", "system", f"Scenario loaded: {scenario.get('name', 'unnamed')}")
        for message in scenario.get("messages", []):
            self.user_message(message["to"], message["text"])

    def export_state(self) -> dict:
        with self.world.lock:
            data = self.world.export()
            data["settings"] = {k: v for k, v in self.settings.items() if k != "api_key"}
            return data

    def import_state(self, data: dict) -> None:
        self.pause()
        with self.world.lock:
            self.world.load(data)
            if isinstance(data.get("settings"), dict):
                self.update_settings({k: v for k, v in data["settings"].items() if k in SETTING_TYPES
                                      and k != "api_key"})
            self.claude.forget()
            self.backoff.clear()
            self.status, self.status_detail = "idle", "State imported. Claude agents start fresh conversations."

    def snapshot(self, since: int = 0) -> dict:
        with self.world.lock:
            data = self.world.snapshot(since)
            data["engine"] = {"status": self.status, "detail": self.status_detail, "running": self.running,
                              "llm_calls": self.llm_calls, "awake": [a.id for a in self.world.agents.values()
                                                                     if self.is_awake(a)]}
            data["settings"] = self.public_settings()
            data["time"] = time.time()
            # Copied under the lock: the engine thread keeps mutating tasks and polls while the server serializes.
            return copy.deepcopy(data)


def list_scenarios() -> list[dict]:
    items = []
    for path in sorted(SCENARIO_DIR.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            items.append({"id": path.stem, "name": data.get("name", path.stem),
                          "description": data.get("description", "")})
        except (OSError, ValueError):
            continue
    return items


def read_scenario(scenario_id: str) -> dict:
    if not scenario_id.replace("-", "").replace("_", "").isalnum():
        raise WorldError("invalid_argument", "Unknown scenario")
    path = SCENARIO_DIR / f"{scenario_id}.json"
    if not path.is_file():
        raise WorldError("not_found", f"No scenario named '{scenario_id}'")
    return json.loads(path.read_text(encoding="utf-8"))
