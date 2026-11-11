"""The simulated shared environment: people, messages, tasks, files and facts.

Every mutation goes through a method that validates input and raises
``WorldError`` with a stable error code. Every mutation also records an event
so the GUI timeline, the network view and exports all share one history.
Callers must hold ``world.lock`` while reading or mutating state.
"""
from __future__ import annotations

import copy
import posixpath
import re
import threading
from dataclasses import asdict, dataclass, field, fields

from . import knowledge

USER_ID = "user"
TASK_STATUSES = ("todo", "in_progress", "review", "blocked", "done")
ROLES = ("coordinator", "researcher", "coder", "reviewer", "tester", "writer", "custom")
BRAINS = ("scripted", "claude")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
DEFAULT_MODEL = "claude-opus-5-5"
DEFAULT_CHANNELS = {"#general": "Team-wide announcements and requests",
                    "#dev": "Implementation, review and testing talk"}
MAX_FILE_CHARS = 200_000
MAX_FILES = 400
MAX_TEXT = 8_000
MAX_EVENTS = 5_000
MAX_MESSAGES = 5_000
_AGENT_ID = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
_CHANNEL = re.compile(r"^#[a-z0-9][a-z0-9_-]{0,31}$")
_KEY = re.compile(r"^[A-Za-z0-9_.:/-]{1,80}$")
_MENTION = re.compile(r"@([a-z][a-z0-9_-]{0,31})")


class WorldError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _new_stats() -> dict:
    return {"turns": 0, "tool_calls": 0, "messages_sent": 0, "llm_calls": 0,
            "input_tokens": 0, "output_tokens": 0, "errors": 0}


@dataclass
class Agent:
    id: str
    name: str
    role: str
    brain: str = "scripted"
    model: str = DEFAULT_MODEL
    effort: str = "medium"
    persona: str = ""
    tools: list | None = None
    color: str = "#6c8cff"
    channels: list = field(default_factory=lambda: list(DEFAULT_CHANNELS))
    status: str = "idle"
    status_detail: str = ""
    inbox_cursor: int = 0
    task_cursor: int = 0
    nudged: bool = False
    memory: dict = field(default_factory=dict)
    stats: dict = field(default_factory=_new_stats)

    CONFIG_FIELDS = ("name", "role", "brain", "model", "effort", "persona", "tools", "color", "channels")

    def public(self) -> dict:
        data = asdict(self)
        data["memory_keys"] = sorted(self.memory)
        data.pop("memory")
        return data


def _text(value, name: str, limit: int = MAX_TEXT, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise WorldError("invalid_argument", f"{name} must be a string")
    value = value.strip() if not allow_empty else value
    if not value and not allow_empty:
        raise WorldError("invalid_argument", f"{name} must not be empty")
    if len(value) > limit:
        raise WorldError("too_large", f"{name} exceeds {limit} characters")
    return value


class World:
    def __init__(self, documents: list[dict] | None = None):
        self.lock = threading.RLock()
        self._builtin_docs = documents if documents is not None else knowledge.load_builtin()
        self.reset()

    # ----------------------------------------------------------------- state
    def reset(self) -> None:
        with self.lock:
            self.seq = 0
            self.tick = 0
            self.agents: dict[str, Agent] = {}
            self.channels = {name: {"name": name, "topic": topic, "created_by": "system"}
                             for name, topic in DEFAULT_CHANNELS.items()}
            self.messages: list[dict] = []
            self.tasks: dict[str, dict] = {}
            self.files: dict[str, dict] = {}
            self.facts: dict[str, dict] = {}
            self.polls: dict[str, dict] = {}
            self.documents = copy.deepcopy(self._builtin_docs)
            self.events: list[dict] = []
            self.counters = {"task": 0, "poll": 0, "message": 0, "doc": 0}

    def next_seq(self) -> int:
        self.seq += 1
        return self.seq

    def log(self, kind: str, actor: str, summary: str, **data) -> dict:
        event = {"id": self.next_seq(), "tick": self.tick, "type": kind, "actor": actor,
                 "summary": summary[:300], "data": data}
        self.events.append(event)
        if len(self.events) > MAX_EVENTS:
            del self.events[: len(self.events) - MAX_EVENTS]
        return event

    # ---------------------------------------------------------------- agents
    def participant_ids(self) -> list[str]:
        return [USER_ID, *self.agents]

    def require_participant(self, participant: str) -> None:
        if participant != USER_ID and participant not in self.agents:
            raise WorldError("unknown_participant", f"No agent or user named '{participant}'")

    def add_agent(self, agent: Agent) -> Agent:
        if not _AGENT_ID.fullmatch(agent.id or "") or agent.id in {USER_ID, "system"}:
            raise WorldError("invalid_argument", "Agent id must be 1-32 lowercase letters, digits, - or _")
        if agent.id in self.agents:
            raise WorldError("duplicate", f"Agent '{agent.id}' already exists")
        self._validate_agent(agent)
        agent.inbox_cursor = agent.task_cursor = self.seq
        self.agents[agent.id] = agent
        self.log("agent_added", "system", f"{agent.name} joined as {agent.role}", agent=agent.id)
        return agent

    def update_agent(self, agent_id: str, changes: dict) -> Agent:
        agent = self.get_agent(agent_id)
        unknown = set(changes) - set(Agent.CONFIG_FIELDS)
        if unknown:
            raise WorldError("invalid_argument", f"Unknown agent fields: {', '.join(sorted(unknown))}")
        candidate = copy.deepcopy(agent)
        for key, value in changes.items():
            setattr(candidate, key, value)
        self._validate_agent(candidate)
        for key in changes:
            setattr(agent, key, getattr(candidate, key))
        self.log("agent_updated", USER_ID, f"{agent.name} settings changed", agent=agent.id,
                 fields=sorted(changes))
        return agent

    def remove_agent(self, agent_id: str) -> None:
        agent = self.get_agent(agent_id)
        del self.agents[agent_id]
        for task in self.tasks.values():
            if task["assignee"] == agent_id and task["status"] != "done":
                task["assignee"] = None
                task["updated_seq"] = self.next_seq()
                task["updated_by"] = "system"
        self.log("agent_removed", "system", f"{agent.name} left the team", agent=agent_id)

    def get_agent(self, agent_id: str) -> Agent:
        if agent_id not in self.agents:
            raise WorldError("unknown_participant", f"No agent named '{agent_id}'")
        return self.agents[agent_id]

    def agents_with_role(self, role: str) -> list[Agent]:
        return [agent for agent in self.agents.values() if agent.role == role]

    def display_name(self, participant: str) -> str:
        if participant == USER_ID:
            return "You"
        agent = self.agents.get(participant)
        return agent.name if agent else participant

    def _validate_agent(self, agent: Agent, channels: dict | None = None) -> None:
        channels = self.channels if channels is None else channels
        agent.name = _text(agent.name, "name", 40)
        if agent.role not in ROLES:
            raise WorldError("invalid_argument", f"role must be one of {', '.join(ROLES)}")
        if agent.brain not in BRAINS:
            raise WorldError("invalid_argument", f"brain must be one of {', '.join(BRAINS)}")
        if agent.effort not in EFFORTS:
            raise WorldError("invalid_argument", f"effort must be one of {', '.join(EFFORTS)}")
        agent.model = _text(agent.model, "model", 80)
        agent.persona = _text(agent.persona, "persona", 2_000, allow_empty=True)
        if not isinstance(agent.color, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", agent.color):
            raise WorldError("invalid_argument", "color must look like #12abef")
        if agent.tools is not None and (not isinstance(agent.tools, list)
                                        or not all(isinstance(name, str) for name in agent.tools)):
            raise WorldError("invalid_argument", "tools must be a list of tool names or null")
        if not isinstance(agent.channels, list) or not all(name in channels for name in agent.channels):
            raise WorldError("invalid_argument", "channels must list existing channels")

    # -------------------------------------------------------------- messages
    def create_channel(self, author: str, name: str, topic: str = "") -> dict:
        name = name.strip().lower()
        if not name.startswith("#"):
            name = "#" + name
        if not _CHANNEL.fullmatch(name):
            raise WorldError("invalid_argument", "Channel names look like #design (lowercase, digits, - or _)")
        if name in self.channels:
            raise WorldError("duplicate", f"Channel {name} already exists")
        channel = {"name": name, "topic": _text(topic, "topic", 200, allow_empty=True), "created_by": author}
        self.channels[name] = channel
        for agent in self.agents.values():
            agent.channels.append(name)
        self.log("channel_created", author, f"created {name}", channel=name)
        return channel

    def post_message(self, sender: str, to: str, text: str) -> dict:
        self.require_participant(sender)
        text = _text(text, "text")
        to = (to or "").strip()
        if to.startswith("#"):
            if to not in self.channels:
                raise WorldError("unknown_channel", f"Channel {to} does not exist")
        else:
            self.require_participant(to)
            if to == sender:
                raise WorldError("invalid_argument", "Cannot send a direct message to yourself")
        mentions = sorted({name for name in _MENTION.findall(text) if name in self.agents or name == USER_ID})
        self.counters["message"] += 1
        message = {"id": f"M-{self.counters['message']}", "seq": self.next_seq(), "tick": self.tick,
                   "sender": sender, "to": to, "text": text, "mentions": mentions}
        self.messages.append(message)
        if len(self.messages) > MAX_MESSAGES:
            del self.messages[: len(self.messages) - MAX_MESSAGES]
        if sender in self.agents:
            self.agents[sender].stats["messages_sent"] += 1
        where = to if to.startswith("#") else f"@{to}"
        self.log("message", sender, f"{self.display_name(sender)} → {where}: {text}",
                 message=message["id"], to=to)
        return message

    def is_relevant(self, message: dict, participant: str) -> bool:
        if message["sender"] == participant:
            return False
        if message["to"] == participant or participant in message["mentions"]:
            return True
        if message["to"].startswith("#"):
            if participant == USER_ID:
                return False
            agent = self.agents.get(participant)
            return bool(agent and message["to"] in agent.channels)
        return False

    def unread(self, participant: str, after_seq: int, upto: int | None = None) -> list[dict]:
        upto = self.seq if upto is None else upto
        return [m for m in self.messages
                if after_seq < m["seq"] <= upto and self.is_relevant(m, participant)]

    def conversation(self, viewer: str, target: str, limit: int = 20) -> list[dict]:
        if target.startswith("#"):
            if target not in self.channels:
                raise WorldError("unknown_channel", f"Channel {target} does not exist")
            items = [m for m in self.messages if m["to"] == target]
        else:
            self.require_participant(target)
            pair = {viewer, target}
            items = [m for m in self.messages if not m["to"].startswith("#") and {m["sender"], m["to"]} == pair]
        return items[-max(1, min(limit, 100)):]

    # ----------------------------------------------------------------- tasks
    def create_task(self, author: str, title: str, description: str = "", assignee: str | None = None,
                    depends_on: list | None = None) -> dict:
        title = _text(title, "title", 160)
        description = _text(description or "", "description", MAX_TEXT, allow_empty=True)
        if assignee:
            self.require_participant(assignee)
        depends_on = list(depends_on or [])
        for dependency in depends_on:
            if dependency not in self.tasks:
                raise WorldError("unknown_task", f"Dependency {dependency} does not exist")
        self.counters["task"] += 1
        task_id = f"T-{self.counters['task']}"
        task = {"id": task_id, "title": title, "description": description, "status": "todo",
                "assignee": assignee or None, "created_by": author, "depends_on": depends_on,
                "notes": [], "result": "", "created_tick": self.tick, "updated_tick": self.tick,
                "updated_seq": self.next_seq(), "updated_by": author}
        self.tasks[task_id] = task
        owner = f" for {self.display_name(assignee)}" if assignee else ""
        self.log("task_created", author, f"{task_id} {title}{owner}", task=task_id, assignee=assignee)
        return task

    def update_task(self, author: str, task_id: str, status: str | None = None, assignee: str | None = None,
                    note: str | None = None, result: str | None = None) -> dict:
        task = self.get_task(task_id)
        if status is not None and status not in TASK_STATUSES:
            raise WorldError("invalid_argument", f"status must be one of {', '.join(TASK_STATUSES)}")
        if status in {"in_progress", "review", "done"} and not self.task_ready(task):
            raise WorldError("dependencies_pending", f"{task_id} waits for {', '.join(self.pending_dependencies(task))}")
        if assignee is not None and assignee != "":
            self.require_participant(assignee)
        changes = []
        if status is not None and status != task["status"]:
            changes.append(f"{task['status']} → {status}")
            task["status"] = status
        if assignee is not None and (assignee or None) != task["assignee"]:
            task["assignee"] = assignee or None
            changes.append(f"assigned to {self.display_name(assignee) if assignee else 'nobody'}")
        if note:
            task["notes"].append({"tick": self.tick, "author": author, "text": _text(note, "note")})
            changes.append("note added")
        if result is not None:
            task["result"] = _text(result, "result", MAX_TEXT, allow_empty=True)
            changes.append("result recorded")
        if not changes:
            raise WorldError("no_change", "Provide a new status, assignee, note or result")
        task["updated_tick"] = self.tick
        task["updated_seq"] = self.next_seq()
        task["updated_by"] = author
        self.log("task_updated", author, f"{task_id}: {', '.join(changes)}", task=task_id, status=task["status"])
        return task

    def get_task(self, task_id: str) -> dict:
        if task_id not in self.tasks:
            raise WorldError("unknown_task", f"Task {task_id} does not exist")
        return self.tasks[task_id]

    def pending_dependencies(self, task: dict) -> list[str]:
        return [dep for dep in task["depends_on"] if self.tasks.get(dep, {}).get("status") != "done"]

    def task_ready(self, task: dict) -> bool:
        return not self.pending_dependencies(task)

    def task_changes_for(self, agent_id: str, after_seq: int, upto: int | None = None) -> list[dict]:
        """Tasks an agent cares about that changed since it last looked."""
        mine = [t for t in self.tasks.values() if t["assignee"] == agent_id or t["created_by"] == agent_id]
        watched = {t["id"] for t in mine}
        watched.update(dep for task in mine if task["status"] != "done" for dep in task["depends_on"])
        upto = self.seq if upto is None else upto
        return [t for t in self.tasks.values()
                if after_seq < t["updated_seq"] <= upto and t["id"] in watched and t.get("updated_by") != agent_id]

    def poll_changes_for(self, agent_id: str, after_seq: int, upto: int | None = None) -> list[dict]:
        """Polls an agent created or may vote on that others changed since it last looked."""
        upto = self.seq if upto is None else upto
        return [p for p in self.polls.values()
                if after_seq < p["updated_seq"] <= upto and p["updated_by"] != agent_id
                and (p["created_by"] == agent_id or agent_id in p["voters"])]

    # ----------------------------------------------------------------- files
    @staticmethod
    def normalize_path(path) -> str:
        if not isinstance(path, str) or not path.strip():
            raise WorldError("invalid_path", "path must be a non-empty string")
        raw = path.strip().replace("\\", "/")
        if raw.startswith("/") or re.match(r"^[A-Za-z]:", raw):
            raise WorldError("invalid_path", "Use a relative workspace path such as src/app.py")
        clean = posixpath.normpath(raw)
        if clean in {".", ""} or clean.startswith("../") or clean == "..":
            raise WorldError("invalid_path", "Path leaves the workspace")
        if len(clean) > 160 or not re.fullmatch(r"[A-Za-z0-9_./ -]+", clean):
            raise WorldError("invalid_path", "Path may use letters, digits, space, _ - . and /")
        if any(part.startswith(".") for part in clean.split("/")):
            raise WorldError("invalid_path", "Hidden path segments are not allowed")
        return clean

    def write_file(self, author: str, path: str, content: str) -> dict:
        path = self.normalize_path(path)
        content = _text(content, "content", MAX_FILE_CHARS, allow_empty=True)
        existing = self.files.get(path)
        if existing is None and len(self.files) >= MAX_FILES:
            raise WorldError("too_large", f"The workspace holds at most {MAX_FILES} files")
        version = existing["version"] + 1 if existing else 1
        record = {"path": path, "content": content, "author": author, "version": version,
                  "updated_tick": self.tick, "updated_seq": self.next_seq(), "size": len(content)}
        self.files[path] = record
        verb = "updated" if existing else "created"
        self.log("file_written", author, f"{verb} {path} (v{version}, {len(content)} chars)", path=path,
                 version=version)
        return record

    def append_file(self, author: str, path: str, content: str) -> dict:
        path = self.normalize_path(path)
        before = self.files[path]["content"] if path in self.files else ""
        return self.write_file(author, path, before + _text(content, "content", MAX_FILE_CHARS, allow_empty=True))

    def read_file(self, path: str) -> dict:
        path = self.normalize_path(path)
        if path not in self.files:
            raise WorldError("not_found", f"No file at {path}")
        return self.files[path]

    def delete_file(self, author: str, path: str) -> None:
        path = self.normalize_path(path)
        if path not in self.files:
            raise WorldError("not_found", f"No file at {path}")
        del self.files[path]
        self.log("file_deleted", author, f"deleted {path}", path=path)

    def search_files(self, query: str, limit: int = 20) -> list[dict]:
        needle = _text(query, "query", 200).lower()
        hits = []
        for path in sorted(self.files):
            for number, line in enumerate(self.files[path]["content"].splitlines(), 1):
                if needle in line.lower():
                    hits.append({"path": path, "line": number, "text": line.strip()[:200]})
                    if len(hits) >= limit:
                        return hits
        return hits

    # ------------------------------------------------------- facts & memory
    @staticmethod
    def _key(key) -> str:
        if not isinstance(key, str) or not _KEY.fullmatch(key):
            raise WorldError("invalid_argument", "key must be 1-80 chars of letters, digits, _ . : / -")
        return key

    def set_fact(self, author: str, key: str, value: str) -> dict:
        key = self._key(key)
        if value == "":
            self.facts.pop(key, None)
            self.log("fact_cleared", author, f"cleared fact {key}", key=key)
            return {"key": key, "cleared": True}
        fact = {"key": key, "value": _text(value, "value", 2_000), "author": author, "tick": self.tick}
        self.facts[key] = fact
        self.log("fact_set", author, f"fact {key} = {fact['value']}", key=key)
        return fact

    def remember(self, agent_id: str, key: str, value) -> None:
        agent = self.get_agent(agent_id)
        key = self._key(key)
        if value is None or value == "":
            agent.memory.pop(key, None)
        else:
            agent.memory[key] = value

    # ----------------------------------------------------------------- polls
    def create_poll(self, author: str, question: str, options: list, voters: list | None = None) -> dict:
        question = _text(question, "question", 300)
        if not isinstance(options, list) or not 2 <= len(options) <= 6:
            raise WorldError("invalid_argument", "options must list 2-6 choices")
        options = [_text(option, "option", 60) for option in options]
        if len(set(options)) != len(options):
            raise WorldError("invalid_argument", "options must be unique")
        voters = list(voters or [])
        for voter in voters:
            self.require_participant(voter)
        self.counters["poll"] += 1
        poll = {"id": f"P-{self.counters['poll']}", "question": question, "options": options, "voters": voters,
                "votes": {}, "status": "open", "created_by": author, "result": None, "tick": self.tick,
                "updated_seq": self.next_seq(), "updated_by": author}
        self.polls[poll["id"]] = poll
        self.log("poll_created", author, f"{poll['id']}: {question} ({' / '.join(options)})", poll=poll["id"])
        return poll

    def vote(self, voter: str, poll_id: str, option: str, reason: str = "") -> dict:
        poll = self.get_poll(poll_id)
        if poll["status"] != "open":
            raise WorldError("poll_closed", f"{poll_id} is closed")
        if poll["voters"] and voter not in poll["voters"]:
            raise WorldError("not_allowed", f"{self.display_name(voter)} is not a voter on {poll_id}")
        if option not in poll["options"]:
            raise WorldError("invalid_argument", f"option must be one of {', '.join(poll['options'])}")
        poll["votes"][voter] = {"option": option, "reason": _text(reason, "reason", 300, allow_empty=True)}
        poll["updated_seq"], poll["updated_by"] = self.next_seq(), voter
        self.log("vote", voter, f"voted '{option}' on {poll_id}", poll=poll_id, option=option)
        if poll["voters"] and all(name in poll["votes"] for name in poll["voters"]):
            self.close_poll("system", poll_id)
        return poll

    def close_poll(self, author: str, poll_id: str) -> dict:
        poll = self.get_poll(poll_id)
        if poll["status"] != "open":
            raise WorldError("poll_closed", f"{poll_id} is already closed")
        tally = {option: 0 for option in poll["options"]}
        for ballot in poll["votes"].values():
            tally[ballot["option"]] += 1
        best = max(tally.values()) if tally else 0
        winners = [option for option, count in tally.items() if count == best and count > 0]
        poll["status"] = "closed"
        poll["result"] = {"tally": tally, "winner": winners[0] if len(winners) == 1 else None}
        poll["updated_seq"], poll["updated_by"] = self.next_seq(), author
        outcome = poll["result"]["winner"] or "tie/no votes"
        self.log("poll_closed", author, f"{poll_id} closed: {outcome}", poll=poll_id, winner=poll["result"]["winner"])
        return poll

    def get_poll(self, poll_id: str) -> dict:
        if poll_id not in self.polls:
            raise WorldError("unknown_poll", f"Poll {poll_id} does not exist")
        return self.polls[poll_id]

    # ------------------------------------------------------------- knowledge
    def get_document(self, doc_id: str) -> dict:
        for document in self.documents:
            if document["id"] == doc_id:
                return document
        raise WorldError("not_found", f"No knowledge document '{doc_id}'")

    def add_document(self, author: str, title: str, body: str, keywords: list | None = None) -> dict:
        self.counters["doc"] += 1
        doc_id = f"note-{self.counters['doc']}"
        text = f"# {_text(title, 'title', 120)}\nKind: note\nKeywords: {', '.join(keywords or [])}\n" \
               f"Author: {author}\n\n{_text(body, 'body')}"
        document = knowledge.parse_document(doc_id, text)
        self.documents.append(document)
        self.log("knowledge_added", author, f"added knowledge '{document['title']}'", doc=doc_id)
        return document

    # ------------------------------------------------------------ snapshots
    def snapshot(self, since: int = 0) -> dict:
        return {
            "tick": self.tick,
            "seq": self.seq,
            "agents": [agent.public() for agent in self.agents.values()],
            "channels": list(self.channels.values()),
            "messages": [m for m in self.messages if m["seq"] > since],
            "tasks": list(self.tasks.values()),
            "files": [{k: v for k, v in f.items() if k != "content"} for f in self.files.values()],
            "facts": list(self.facts.values()),
            "polls": list(self.polls.values()),
            "events": [e for e in self.events if e["id"] > since],
            "documents": [{"id": d["id"], "title": d["title"], "kind": d["kind"]} for d in self.documents],
        }

    def export(self) -> dict:
        builtin = {doc["id"] for doc in self._builtin_docs}
        return copy.deepcopy({
            "format": "ai-collab-lab", "version": 1, "seq": self.seq, "tick": self.tick,
            "counters": self.counters, "agents": [asdict(agent) for agent in self.agents.values()],
            "channels": self.channels, "messages": self.messages, "tasks": self.tasks, "files": self.files,
            "facts": self.facts, "polls": self.polls, "events": self.events,
            "documents": [doc for doc in self.documents if doc["id"] not in builtin],
        })

    def load(self, data: dict) -> None:
        if not isinstance(data, dict) or data.get("format") != "ai-collab-lab" or data.get("version") != 1:
            raise WorldError("invalid_state", "Not an AI Collab Lab export (format/version mismatch)")
        names = {f.name for f in fields(Agent)}
        try:
            agents = {}
            for item in data["agents"]:
                agent = Agent(**{key: value for key, value in item.items() if key in names})
                agents[agent.id] = agent
            restored = {
                "seq": int(data["seq"]), "tick": int(data["tick"]), "counters": dict(data["counters"]),
                "channels": dict(data["channels"]), "messages": list(data["messages"]),
                "tasks": dict(data["tasks"]), "files": dict(data["files"]), "facts": dict(data["facts"]),
                "polls": dict(data["polls"]), "events": list(data["events"]),
                "documents": copy.deepcopy(self._builtin_docs) + list(data.get("documents", [])),
            }
            for agent in agents.values():
                if not _AGENT_ID.fullmatch(agent.id):
                    raise ValueError(f"invalid agent id {agent.id!r}")
                self._validate_agent(agent, restored["channels"])
        except (KeyError, TypeError, ValueError, AttributeError, WorldError) as error:
            raise WorldError("invalid_state", f"Export is incomplete or invalid: {error}") from error
        with self.lock:
            self.agents = agents
            for key, value in restored.items():
                setattr(self, key, copy.deepcopy(value))
            self.log("system", "system", "state imported")
