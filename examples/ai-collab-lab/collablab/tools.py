"""Tool registry: every action an agent (or the user) can take in the world.

Tools are described with a small JSON-schema subset so the same definitions
serve the Claude API, the GUI tool console and the scripted brains. Arguments
are validated here before a handler runs; failures come back as structured
errors instead of exceptions so a model can read them and recover.
"""
from __future__ import annotations

import ast
import json
import math
import operator
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from . import knowledge
from .world import TASK_STATUSES, USER_ID, World, WorldError

MAX_RESULT_CHARS = 12_000


@dataclass(frozen=True)
class ToolSpec:
    name: str
    category: str
    description: str
    properties: dict
    required: tuple
    handler: Callable[["ToolContext", dict], Any]
    requires_setting: str | None = None

    def input_schema(self) -> dict:
        return {"type": "object", "properties": self.properties, "required": list(self.required),
                "additionalProperties": False}

    def describe(self) -> dict:
        return {"name": self.name, "category": self.category, "description": self.description,
                "input_schema": self.input_schema(), "requires_setting": self.requires_setting}


@dataclass
class ToolContext:
    world: World
    actor: str
    settings: dict


REGISTRY: dict[str, ToolSpec] = {}


def tool(name, category, description, properties=None, required=(), requires_setting=None):
    def register(handler):
        REGISTRY[name] = ToolSpec(name, category, description, properties or {}, tuple(required), handler,
                                  requires_setting)
        return handler
    return register


def S(description, **extra):
    return {"type": "string", "description": description, **extra}


def I(description, **extra):
    return {"type": "integer", "description": description, **extra}


# ------------------------------------------------------------------ validation
def validate_args(spec: ToolSpec, args) -> dict:
    if args is None:
        args = {}
    if not isinstance(args, dict):
        raise WorldError("invalid_arguments", "Tool input must be a JSON object")
    unknown = sorted(set(args) - set(spec.properties))
    if unknown:
        raise WorldError("invalid_arguments", f"Unknown argument(s): {', '.join(unknown)}")
    missing = [name for name in spec.required if name not in args]
    if missing:
        raise WorldError("invalid_arguments", f"Missing required argument(s): {', '.join(missing)}")
    for name, value in args.items():
        _check(name, value, spec.properties[name])
    return args


def _check(name: str, value, schema: dict) -> None:
    kind = schema.get("type")
    valid = {
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "array": isinstance(value, list),
    }.get(kind, True)
    if not valid:
        raise WorldError("invalid_arguments", f"'{name}' must be of type {kind}")
    if "enum" in schema and value not in schema["enum"]:
        raise WorldError("invalid_arguments", f"'{name}' must be one of: {', '.join(map(str, schema['enum']))}")
    if kind == "string" and len(value) > schema.get("maxLength", 200_000):
        raise WorldError("invalid_arguments", f"'{name}' is longer than {schema['maxLength']} characters")
    if kind in {"integer", "number"}:
        if value < schema.get("minimum", -math.inf) or value > schema.get("maximum", math.inf):
            raise WorldError("invalid_arguments",
                             f"'{name}' must be between {schema.get('minimum')} and {schema.get('maximum')}")
    if kind == "array":
        if len(value) > schema.get("maxItems", 50):
            raise WorldError("invalid_arguments", f"'{name}' has too many items")
        for index, item in enumerate(value):
            _check(f"{name}[{index}]", item, schema.get("items", {}))


# ------------------------------------------------------------- communication
@tool("send_message", "communication",
      "Send a message. 'to' is a channel such as #general, an agent id, or 'user' for the human operator. "
      "Mention teammates with @id inside the text to notify them in a channel.",
      {"to": S("Channel (#general) or participant id (agent id or 'user')", maxLength=40),
       "text": S("Message text; be concise and actionable", maxLength=8000)}, ("to", "text"))
def _send_message(ctx, args):
    message = ctx.world.post_message(ctx.actor, args["to"], args["text"])
    return {"message_id": message["id"], "delivered_to": args["to"], "mentions": message["mentions"]}


@tool("read_messages", "communication",
      "Read recent history of a channel or of your direct conversation with one participant.",
      {"with": S("Channel (#dev) or participant id", maxLength=40),
       "limit": I("How many recent messages (1-50)", minimum=1, maximum=50)}, ("with",))
def _read_messages(ctx, args):
    items = ctx.world.conversation(ctx.actor, args["with"], args.get("limit", 15))
    return {"messages": [{"id": m["id"], "tick": m["tick"], "from": m["sender"], "to": m["to"], "text": m["text"]}
                         for m in items]}


@tool("list_agents", "communication", "List teammates with their role, brain type and current status.")
def _list_agents(ctx, args):
    return {"you": ctx.actor, "team": [
        {"id": a.id, "name": a.name, "role": a.role, "brain": a.brain, "status": a.status,
         "persona": a.persona[:160]} for a in ctx.world.agents.values()] + [
        {"id": USER_ID, "name": "Human operator", "role": "user", "brain": "human", "status": "available"}]}


@tool("list_channels", "communication", "List chat channels and their topics.")
def _list_channels(ctx, args):
    return {"channels": list(ctx.world.channels.values())}


@tool("create_channel", "communication", "Create a new chat channel; every agent is subscribed automatically.",
      {"name": S("Channel name such as #design", maxLength=33), "topic": S("Short purpose", maxLength=200)},
      ("name",))
def _create_channel(ctx, args):
    return ctx.world.create_channel(ctx.actor, args["name"], args.get("topic", ""))


# --------------------------------------------------------------------- tasks
def _task_view(world: World, task: dict, full: bool = False) -> dict:
    view = {"id": task["id"], "title": task["title"], "status": task["status"], "assignee": task["assignee"],
            "depends_on": task["depends_on"], "ready": world.task_ready(task), "created_by": task["created_by"]}
    if full:
        view.update(description=task["description"], notes=task["notes"], result=task["result"])
    elif task["result"]:
        view["result"] = task["result"][:200]
    return view


@tool("create_task", "tasks", "Create a task on the shared board, optionally assigned and with dependencies.",
      {"title": S("Short imperative title", maxLength=160), "description": S("Details and acceptance criteria"),
       "assignee": S("Agent id or 'user' (optional)", maxLength=40),
       "depends_on": {"type": "array", "items": {"type": "string"}, "description": "Task ids that must be done first"}},
      ("title",))
def _create_task(ctx, args):
    task = ctx.world.create_task(ctx.actor, args["title"], args.get("description", ""), args.get("assignee"),
                                 args.get("depends_on"))
    return _task_view(ctx.world, task, True)


@tool("update_task", "tasks",
      "Change a task's status, assignee, add a progress note, or record its result. Status values: "
      + ", ".join(TASK_STATUSES) + ". in_progress/review/done require finished dependencies.",
      {"task_id": S("Task id such as T-3", maxLength=12), "status": S("New status", enum=list(TASK_STATUSES)),
       "assignee": S("New assignee id, or empty string to unassign", maxLength=40),
       "note": S("Progress note visible to everyone"), "result": S("Final outcome summary")}, ("task_id",))
def _update_task(ctx, args):
    task = ctx.world.update_task(ctx.actor, args["task_id"], args.get("status"), args.get("assignee"),
                                 args.get("note"), args.get("result"))
    return _task_view(ctx.world, task, True)


@tool("list_tasks", "tasks", "List tasks on the board, optionally filtered by status or assignee.",
      {"status": S("Filter by status", enum=list(TASK_STATUSES)), "assignee": S("Filter by assignee id", maxLength=40)})
def _list_tasks(ctx, args):
    items = [t for t in ctx.world.tasks.values()
             if args.get("status") in (None, t["status"]) and args.get("assignee") in (None, t["assignee"])]
    return {"tasks": [_task_view(ctx.world, t) for t in items]}


@tool("get_task", "tasks", "Read one task in full, including description, notes and result.",
      {"task_id": S("Task id such as T-3", maxLength=12)}, ("task_id",))
def _get_task(ctx, args):
    return _task_view(ctx.world, ctx.world.get_task(args["task_id"]), True)


# ----------------------------------------------------------------- workspace
@tool("write_file", "workspace", "Create or overwrite a text file in the shared workspace.",
      {"path": S("Relative path such as src/app.py", maxLength=160), "content": S("Full file content")},
      ("path", "content"))
def _write_file(ctx, args):
    record = ctx.world.write_file(ctx.actor, args["path"], args["content"])
    return {"path": record["path"], "version": record["version"], "size": record["size"]}


@tool("append_file", "workspace", "Append text to a workspace file, creating it if needed.",
      {"path": S("Relative path", maxLength=160), "content": S("Text to append")}, ("path", "content"))
def _append_file(ctx, args):
    record = ctx.world.append_file(ctx.actor, args["path"], args["content"])
    return {"path": record["path"], "version": record["version"], "size": record["size"]}


@tool("read_file", "workspace", "Read a workspace file.", {"path": S("Relative path", maxLength=160)}, ("path",))
def _read_file(ctx, args):
    record = ctx.world.read_file(args["path"])
    return {"path": record["path"], "version": record["version"], "author": record["author"],
            "content": record["content"]}


@tool("list_files", "workspace", "List workspace files, optionally under a folder prefix.",
      {"prefix": S("Folder prefix such as src/", maxLength=160)})
def _list_files(ctx, args):
    prefix = args.get("prefix", "").strip().replace("\\", "/")
    return {"files": [{"path": f["path"], "size": f["size"], "version": f["version"], "author": f["author"]}
                      for path, f in sorted(ctx.world.files.items()) if path.startswith(prefix)]}


@tool("delete_file", "workspace", "Delete a workspace file.", {"path": S("Relative path", maxLength=160)}, ("path",))
def _delete_file(ctx, args):
    ctx.world.delete_file(ctx.actor, args["path"])
    return {"deleted": World.normalize_path(args["path"])}


@tool("search_files", "workspace", "Find lines containing text across all workspace files (case-insensitive).",
      {"query": S("Text to look for", maxLength=200)}, ("query",))
def _search_files(ctx, args):
    return {"matches": ctx.world.search_files(args["query"])}


# --------------------------------------------------------- knowledge & memory
@tool("search_knowledge", "knowledge",
      "Search the team knowledge base (articles, code recipes and notes added by agents).",
      {"query": S("Free-text query", maxLength=500), "limit": I("Maximum results (1-10)", minimum=1, maximum=10)},
      ("query",))
def _search_knowledge(ctx, args):
    return {"results": knowledge.search(ctx.world.documents, args["query"], args.get("limit", 5))}


@tool("read_knowledge", "knowledge", "Read one knowledge document, including any code it contains.",
      {"doc_id": S("Document id from search_knowledge", maxLength=80)}, ("doc_id",))
def _read_knowledge(ctx, args):
    document = ctx.world.get_document(args["doc_id"])
    return {key: document[key] for key in ("id", "title", "kind", "module", "keywords", "body", "code")}


@tool("add_knowledge", "knowledge", "Share a lesson or reference with the team by adding a knowledge note.",
      {"title": S("Note title", maxLength=120), "body": S("Markdown body", maxLength=8000),
       "keywords": {"type": "array", "items": {"type": "string", "maxLength": 40}, "maxItems": 12,
                    "description": "Search keywords"}}, ("title", "body"))
def _add_knowledge(ctx, args):
    document = ctx.world.add_document(ctx.actor, args["title"], args["body"], args.get("keywords"))
    return {"doc_id": document["id"], "title": document["title"]}


@tool("remember", "knowledge", "Save a private note in your own memory (empty value deletes the key).",
      {"key": S("Memory key", maxLength=80), "value": S("Value to keep", maxLength=4000)}, ("key", "value"))
def _remember(ctx, args):
    if ctx.actor == USER_ID:
        raise WorldError("not_allowed", "Only agents have private memory")
    ctx.world.remember(ctx.actor, args["key"], args["value"])
    return {"saved": args["key"], "keys": sorted(ctx.world.agents[ctx.actor].memory)}


@tool("recall", "knowledge", "Read your private memory: one key, or all keys when omitted.",
      {"key": S("Memory key", maxLength=80)})
def _recall(ctx, args):
    if ctx.actor == USER_ID:
        raise WorldError("not_allowed", "Only agents have private memory")
    memory = ctx.world.agents[ctx.actor].memory
    if "key" in args:
        return {"key": args["key"], "value": memory.get(args["key"])}
    return {"memory": memory}


@tool("set_fact", "knowledge", "Publish a shared fact on the team blackboard (empty value clears it).",
      {"key": S("Fact key such as project.language", maxLength=80), "value": S("Fact value", maxLength=2000)},
      ("key", "value"))
def _set_fact(ctx, args):
    return ctx.world.set_fact(ctx.actor, args["key"], args["value"])


@tool("get_facts", "knowledge", "Read shared blackboard facts; optional key prefix filter.",
      {"prefix": S("Key prefix", maxLength=80)})
def _get_facts(ctx, args):
    prefix = args.get("prefix", "")
    return {"facts": [fact for key, fact in sorted(ctx.world.facts.items()) if key.startswith(prefix)]}


# ----------------------------------------------------------------- decisions
@tool("create_poll", "decisions", "Ask the team to decide by vote. With voters listed, the poll closes when all vote.",
      {"question": S("Question", maxLength=300),
       "options": {"type": "array", "items": {"type": "string", "maxLength": 60}, "maxItems": 6,
                   "description": "2-6 distinct options"},
       "voters": {"type": "array", "items": {"type": "string"}, "description": "Participant ids allowed to vote"}},
      ("question", "options"))
def _create_poll(ctx, args):
    return ctx.world.create_poll(ctx.actor, args["question"], args["options"], args.get("voters"))


@tool("vote", "decisions", "Vote on an open poll, with an optional reason.",
      {"poll_id": S("Poll id such as P-1", maxLength=12), "option": S("Chosen option", maxLength=60),
       "reason": S("Why", maxLength=300)}, ("poll_id", "option"))
def _vote(ctx, args):
    return ctx.world.vote(ctx.actor, args["poll_id"], args["option"], args.get("reason", ""))


@tool("close_poll", "decisions", "Close an open poll early and publish the tally.",
      {"poll_id": S("Poll id", maxLength=12)}, ("poll_id",))
def _close_poll(ctx, args):
    poll = ctx.world.get_poll(args["poll_id"])
    if ctx.actor not in {poll["created_by"], USER_ID}:
        raise WorldError("not_allowed", "Only the poll creator or the user can close it early")
    return ctx.world.close_poll(ctx.actor, args["poll_id"])


@tool("list_polls", "decisions", "List polls with votes so far.",
      {"status": S("open or closed", enum=["open", "closed"])})
def _list_polls(ctx, args):
    return {"polls": [p for p in ctx.world.polls.values() if args.get("status") in (None, p["status"])]}


# ----------------------------------------------------------- code & utilities
_BINARY = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv,
           ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod, ast.Pow: operator.pow}
_UNARY = {ast.UAdd: operator.pos, ast.USub: operator.neg}
_FUNCTIONS = {name: getattr(math, name) for name in
              ("sqrt", "sin", "cos", "tan", "log", "log10", "exp", "floor", "ceil", "radians", "degrees")}
_FUNCTIONS.update(abs=abs, round=round, min=min, max=max)
_CONSTANTS = {"pi": math.pi, "e": math.e, "tau": math.tau}


def evaluate(expression: str):
    """Evaluate arithmetic without exec/eval: only numbers, operators and math functions."""
    try:
        tree = ast.parse(expression.strip(), mode="eval")
    except SyntaxError as error:
        raise WorldError("invalid_expression", f"Not valid arithmetic: {error.msg}") from None

    def walk(node):
        if isinstance(node, ast.Expression):
            return walk(node.body)
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            return node.value
        if isinstance(node, ast.Name) and node.id in _CONSTANTS:
            return _CONSTANTS[node.id]
        if isinstance(node, ast.BinOp) and type(node.op) in _BINARY:
            left, right = walk(node.left), walk(node.right)
            if isinstance(node.op, ast.Pow) and (abs(right) > 1000 or abs(left) > 1e6):
                raise WorldError("invalid_expression", "Exponent or base too large")
            value = _BINARY[type(node.op)](left, right)
            if isinstance(value, int) and value.bit_length() > 4096:
                raise WorldError("invalid_expression", "Result too large")
            return value
        if isinstance(node, ast.UnaryOp) and type(node.op) in _UNARY:
            return _UNARY[type(node.op)](walk(node.operand))
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in _FUNCTIONS
                and not node.keywords and len(node.args) <= 4):
            return _FUNCTIONS[node.func.id](*[walk(arg) for arg in node.args])
        raise WorldError("invalid_expression", f"Unsupported syntax: {type(node).__name__}")

    try:
        result = walk(tree)
    except (ZeroDivisionError, ValueError, OverflowError, TypeError) as error:
        raise WorldError("invalid_expression", str(error)) from None
    if isinstance(result, complex):
        raise WorldError("invalid_expression", "Complex results are not supported")
    return result


@tool("calculate", "utilities", "Evaluate an arithmetic expression safely, e.g. '(37 * 9 / 5) + 32' or 'sqrt(2)'.",
      {"expression": S("Arithmetic expression", maxLength=300)}, ("expression",))
def _calculate(ctx, args):
    return {"expression": args["expression"], "value": evaluate(args["expression"])}


def analyze_python(source: str) -> dict:
    """Static facts about Python source. Parses only; never executes it."""
    lines = source.splitlines()
    report = {"lines": len(lines), "syntax_ok": True, "error": None, "module_docstring": False,
              "functions": [], "classes": [], "imports": [], "todo_count": 0, "long_lines": [],
              "tabs": any("\t" in line for line in lines),
              "trailing_whitespace": [n for n, line in enumerate(lines, 1) if line != line.rstrip()][:20],
              "final_newline": source.endswith("\n") or not source}
    report["todo_count"] = sum(line.count("TODO") + line.count("FIXME") for line in lines)
    report["long_lines"] = [n for n, line in enumerate(lines, 1) if len(line) > 100][:20]
    try:
        tree = ast.parse(source)
    except SyntaxError as error:
        report.update(syntax_ok=False, error={"line": error.lineno, "message": error.msg})
        return report
    report["module_docstring"] = ast.get_docstring(tree) is not None
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            report["functions"].append({
                "name": node.name, "line": node.lineno, "args": [a.arg for a in node.args.args],
                "docstring": ast.get_docstring(node) is not None, "returns": node.returns is not None,
                "summary": (ast.get_docstring(node) or "").strip().split("\n")[0][:160],
                "raises_not_implemented": any(isinstance(n, ast.Raise) and "NotImplementedError" in ast.dump(n)
                                              for n in ast.walk(node))})
        elif isinstance(node, ast.ClassDef):
            report["classes"].append({"name": node.name, "line": node.lineno,
                                      "docstring": ast.get_docstring(node) is not None})
        elif isinstance(node, ast.Import):
            report["imports"].extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            report["imports"].append(node.module or ".")
    return report


@tool("check_python", "utilities",
      "Statically inspect a workspace Python file: syntax, functions, docstrings, TODOs, style. Does not run it.",
      {"path": S("Workspace path of a .py file", maxLength=160)}, ("path",))
def _check_python(ctx, args):
    record = ctx.world.read_file(args["path"])
    return {"path": record["path"], **analyze_python(record["content"])}


@tool("run_python", "utilities",
      "Run a workspace Python file in a temporary copy of the workspace with a timeout and return its output. "
      "Only available when the operator enabled code execution.",
      {"path": S("Workspace path of a .py file", maxLength=160),
       "timeout_seconds": I("Timeout 1-20 seconds", minimum=1, maximum=20)}, ("path",),
      requires_setting="allow_code_execution")
def _run_python(ctx, args):
    record = ctx.world.read_file(args["path"])
    with tempfile.TemporaryDirectory(prefix="collab-lab-run-") as temporary:
        root = Path(temporary)
        for path, item in ctx.world.files.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(item["content"], encoding="utf-8")
        environment = {key: os.environ[key] for key in ("PATH", "SYSTEMROOT", "TEMP", "TMP") if key in os.environ}
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        try:
            completed = subprocess.run([sys.executable, "-I", "-X", "utf8", record["path"]], cwd=root,
                                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                                       timeout=args.get("timeout_seconds", 10), env=environment, check=False)
        except subprocess.TimeoutExpired as error:
            return {"path": record["path"], "timed_out": True, "exit_code": None,
                    "stdout": (error.stdout or "")[-3000:] if isinstance(error.stdout, str) else "",
                    "stderr": "Timed out"}
    return {"path": record["path"], "timed_out": False, "exit_code": completed.returncode,
            "passed": completed.returncode == 0, "stdout": completed.stdout[-4000:],
            "stderr": completed.stderr[-4000:]}


@tool("get_status", "utilities", "Overview for you: current tick, your open tasks, unread count and team status.")
def _get_status(ctx, args):
    world = ctx.world
    open_tasks = [_task_view(world, t) for t in world.tasks.values()
                  if t["assignee"] == ctx.actor and t["status"] != "done"]
    team = {a.id: a.status for a in world.agents.values()}
    return {"tick": world.tick, "you": ctx.actor, "open_tasks": open_tasks, "team_status": team,
            "open_polls": [p["id"] for p in world.polls.values() if p["status"] == "open"],
            "files": len(world.files), "settings": {"allow_code_execution": bool(ctx.settings.get("allow_code_execution"))}}


# ------------------------------------------------------------------- toolbox
CATEGORIES = ("communication", "tasks", "workspace", "knowledge", "decisions", "utilities")


def catalog() -> list[dict]:
    return [spec.describe() for spec in REGISTRY.values()]


class Toolbox:
    """Executes tools for one world, enforcing permissions and logging calls."""

    def __init__(self, world: World, settings: dict):
        self.world = world
        self.settings = settings

    def available(self, actor: str) -> list[ToolSpec]:
        allowed = None
        if actor != USER_ID and actor in self.world.agents:
            allowed = self.world.agents[actor].tools
        return [spec for spec in REGISTRY.values()
                if (allowed is None or spec.name in allowed)
                and (spec.requires_setting is None or self.settings.get(spec.requires_setting))]

    def call(self, actor: str, name: str, args=None) -> dict:
        with self.world.lock:
            spec = REGISTRY.get(name)
            try:
                if spec is None:
                    raise WorldError("unknown_tool", f"No tool named '{name}'")
                self.world.require_participant(actor)
                if spec not in self.available(actor):
                    if spec.requires_setting and not self.settings.get(spec.requires_setting):
                        raise WorldError("disabled", f"{name} is disabled; the operator must enable "
                                                     f"'{spec.requires_setting}' in Settings")
                    raise WorldError("not_allowed", f"{name} is not in your tool permissions")
                clean = validate_args(spec, args)
                result = spec.handler(ToolContext(self.world, actor, self.settings), clean)
                outcome = {"ok": True, "result": result}
            except WorldError as error:
                outcome = {"ok": False, "error": {"code": error.code, "message": error.message}}
            if actor in self.world.agents:
                stats = self.world.agents[actor].stats
                stats["tool_calls"] += 1
                stats["errors"] += 0 if outcome["ok"] else 1
            preview = json.dumps(args if isinstance(args, dict) else {}, ensure_ascii=False)[:160]
            status = "ok" if outcome["ok"] else f"error {outcome['error']['code']}"
            self.world.log("tool_call", actor, f"{name}({preview}) → {status}", tool=name,
                           args=args if isinstance(args, dict) else {}, ok=outcome["ok"],
                           result=summarize(outcome))
            return outcome


def summarize(outcome: dict, limit: int = 600) -> str:
    text = json.dumps(outcome.get("result") if outcome["ok"] else outcome["error"], ensure_ascii=False)
    return text if len(text) <= limit else text[: limit - 1] + "…"


def render(outcome: dict) -> str:
    """Serialize a tool outcome for a model, bounded in size."""
    text = json.dumps(outcome["result"] if outcome["ok"] else outcome["error"], ensure_ascii=False, indent=1)
    if len(text) > MAX_RESULT_CHARS:
        text = text[:MAX_RESULT_CHARS] + "\n... (truncated)"
    return text
