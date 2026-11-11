"""Offline, deterministic role policies.

Scripted agents do not understand language. They follow a fixed playbook per
role and act only through the same tools a Claude agent uses, so their work
shows up in the same timeline, task board and files. Code they produce comes
from knowledge-base recipes; requests without a recipe are escalated to the
user instead of being guessed.
"""
from __future__ import annotations

import ast
import re

from ..world import USER_ID
from . import TurnResult

_FIELD = re.compile(r"^(Project|Request|Module):[ \t]*(.+)$", re.M)
_STOPWORDS = set("""a an the to of for in on with and or that this please build create make write implement
research review test tests document docs function functions program app application tool module code
script simple small new me my our we i you can could would should need want some python using use""".split())
_CODE_PATH = re.compile(r"\b((?:src|tests)/[A-Za-z0-9_./-]+\.py)\b")


def slugify(text: str, limit: int = 3) -> str:
    words = [w for w in re.findall(r"[a-z][a-z0-9]*", text.lower()) if w not in _STOPWORDS and len(w) > 1]
    return "_".join(words[:limit])[:40].strip("_")


def identifier(text: str) -> str:
    name = re.sub(r"[^a-z0-9_]", "_", text.lower()).strip("_") or "feature"
    return name if name[0].isalpha() else "feature_" + name


def task_context(task: dict) -> tuple[str, str, str | None]:
    """Return (project slug, request text, module hint) for a task."""
    fields = {key.lower(): value.strip() for key, value in _FIELD.findall(task["description"])}
    slug = fields.get("project") or slugify(task["title"]) or task["id"].lower().replace("-", "_")
    request = fields.get("request") or f"{task['title']}. {task['description']}".strip()
    return slug, request, fields.get("module")


class _Turn:
    def __init__(self, agent, observation: dict, engine):
        self.agent = agent
        self.obs = observation
        self.engine = engine
        self.world = engine.world
        self.calls = 0
        self.done: list[str] = []
        self.last_error: dict | None = None

    def act(self, name: str, **args):
        outcome = self.engine.toolbox.call(self.agent.id, name, args)
        self.calls += 1
        if outcome["ok"]:
            return outcome["result"]
        self.last_error = outcome["error"]
        return None

    def think(self, text: str) -> None:
        self.world.log("thought", self.agent.id, text)

    def say(self, to: str, text: str) -> None:
        self.act("send_message", to=to, text=text)

    def settled(self, item: dict) -> bool:
        """True when a change happened before this tick, so every agent has had a chance to see it."""
        return item.get("updated_tick", item.get("tick", 0)) < self.world.tick

    def ready_tasks(self, statuses=("todo",)) -> list[dict]:
        return [task for task in self.world.tasks.values()
                if task["assignee"] == self.agent.id and task["status"] in statuses and self.world.task_ready(task)
                and all(self.settled(self.world.tasks[dep]) for dep in task["depends_on"])]

    def facts(self, slug: str) -> dict:
        found = self.act("get_facts", prefix=f"{slug}.") or {"facts": []}
        return {fact["key"][len(slug) + 1:]: fact["value"] for fact in found["facts"]}

    def mention_dependents(self, task: dict) -> str:
        owners = []
        for other in self.world.tasks.values():
            if task["id"] in other["depends_on"] and other["assignee"] in self.world.agents:
                owners.append(f"@{other['assignee']}")
        return " ".join(dict.fromkeys(owners))


class ScriptedBrain:
    kind = "scripted"

    def take_turn(self, agent, observation: dict, engine) -> TurnResult:
        turn = _Turn(agent, observation, engine)
        with engine.world.lock:
            policy = POLICIES.get(agent.role, custom_policy)
            policy(turn)
            if agent.role != "coordinator":
                answer_direct_messages(turn)
        summary = "; ".join(turn.done) if turn.done else "nothing to do"
        return TurnResult(summary=summary, tool_calls=turn.calls)


# ------------------------------------------------------------------ helpers
def find_recipe(turn: _Turn, request: str) -> dict | None:
    found = turn.act("search_knowledge", query=request[:500], limit=5) or {"results": []}
    for item in found["results"]:
        if item["score"] >= 3 and item["kind"] != "article":
            document = turn.act("read_knowledge", doc_id=item["id"])
            if document and document["code"].get("module"):
                return document
    return None


def recipe_for(turn: _Turn, facts: dict, request: str) -> dict | None:
    if facts.get("recipe") not in (None, "none"):
        document = turn.act("read_knowledge", doc_id=facts["recipe"])
        if document and document["code"].get("module"):
            return document
    return find_recipe(turn, request)


def code_path(turn: _Turn, slug: str, facts: dict, module_hint: str | None) -> str:
    if facts.get("code"):
        return facts["code"]
    return f"src/{identifier(facts.get('module') or module_hint or slug)}.py"


def answer_direct_messages(turn: _Turn) -> None:
    for message in turn.obs["messages"]:
        if message["sender"] != USER_ID or message["to"] != turn.agent.id:
            continue
        mine = [f"{t['id']} {t['title']} ({t['status']})" for t in turn.world.tasks.values()
                if t["assignee"] == turn.agent.id]
        tasks = "; ".join(mine) if mine else "none yet"
        turn.say(USER_ID, f"Hi! I'm {turn.agent.name}, a scripted {turn.agent.role}: I follow a fixed playbook "
                          f"and act on tasks assigned to me. My tasks: {tasks}. For open-ended conversation, "
                          f"switch my brain to Claude in my settings.")
        turn.done.append("answered the user")


def vote_on_polls(turn: _Turn) -> None:
    for poll in turn.world.polls.values():
        if (poll["status"] != "open" or turn.agent.id not in poll["voters"] or turn.agent.id in poll["votes"]
                or poll["tick"] >= turn.world.tick):
            continue
        match = re.search(r"project (\S+?)\?", poll["question"])
        slug = match[1] if match else ""
        mine = [t for t in turn.world.tasks.values()
                if t["assignee"] == turn.agent.id and task_context(t)[0] == slug]
        ready = bool(mine) and all(t["status"] == "done" for t in mine)
        reason = (f"my {', '.join(t['id'] for t in mine)} passed" if ready
                  else "my part is not finished or failed")
        if turn.act("vote", poll_id=poll["id"], option="ship" if ready else "hold", reason=reason):
            turn.done.append(f"voted on {poll['id']}")


# ---------------------------------------------------------------- coordinator
HELP = ("Send me a request such as 'Build a VAT calculator' and I will plan it with the team. "
        "Commands: 'status' lists projects, 'retry' restarts blocked tasks.")


def coordinator_policy(turn: _Turn) -> None:
    for message in turn.obs["messages"]:
        if message["sender"] != USER_ID:
            continue
        direct = message["to"] == turn.agent.id
        mentioned = turn.agent.id in message["mentions"]
        if direct or mentioned or (message["to"] == "#general" and not message["mentions"]):
            handle_user_message(turn, message)
    review_projects(turn)


def handle_user_message(turn: _Turn, message: dict) -> None:
    text = re.sub(r"@[a-z][a-z0-9_-]*", "", message["text"]).strip()
    reply_to = message["to"] if message["to"].startswith("#") else USER_ID
    command = text.lower().strip(" !.?")
    projects = turn.agent.memory.setdefault("projects", {})
    if command in {"help", ""}:
        turn.say(reply_to, HELP)
    elif command == "status":
        lines = [f"{slug}: {p['status']} ({', '.join(p['tasks'].values())})" for slug, p in projects.items()]
        turn.say(reply_to, "Projects — " + ("; ".join(lines) if lines else "none yet. " + HELP))
    elif command.startswith("retry"):
        retried = []
        for project in projects.values():
            for task_id in project["tasks"].values():
                task = turn.world.tasks.get(task_id)
                if task and task["status"] == "blocked":
                    if turn.act("update_task", task_id=task_id, status="todo", note="Retry requested by the user"):
                        retried.append(task_id)
                        project["status"] = "active"
                        if task_id in project["blocked_notified"]:
                            project["blocked_notified"].remove(task_id)
        turn.say(reply_to, f"Retrying {', '.join(retried)}." if retried else "Nothing is blocked right now.")
        turn.done.append("handled retry")
    else:
        plan_project(turn, text, reply_to)


def plan_project(turn: _Turn, text: str, reply_to: str) -> None:
    world = turn.world
    projects = turn.agent.memory.setdefault("projects", {})
    turn.think(f"New request: {text[:160]}. Checking the knowledge base before planning.")
    found = turn.act("search_knowledge", query=text[:500], limit=3) or {"results": []}
    recipe = next((r for r in found["results"] if r["kind"] == "recipe" and r["score"] >= 3), None)
    base = recipe["module"] if recipe else (slugify(text) or f"project_{len(projects) + 1}")
    slug, number = base, 2
    while slug in projects:
        slug, number = f"{base}_{number}", number + 1
    module = identifier(recipe["module"] if recipe else slug)
    title = text.splitlines()[0][:70]
    team = {}
    for role in ("researcher", "coder", "reviewer", "tester", "writer"):
        members = [a for a in world.agents.values() if a.role == role and a.id != turn.agent.id]
        if members:
            team[role] = members[0].id
    if "coder" not in team:
        turn.say(reply_to, "I need at least one agent with the coder role before I can plan this request.")
        return
    header = f"Project: {slug}\nRequest: {text}\nModule: {module}\n\n"
    specs = (
        ("research", "researcher", f"Research: {title}",
         f"Find recipes, references and constraints in the knowledge base. Write notes/{slug}-research.md "
         f"and publish the facts {slug}.recipe and {slug}.module.", ()),
        ("implement", "coder", f"Implement: {title}",
         f"Write src/{module}.py with docstrings and input validation. Publish {slug}.code.", ("research",)),
        ("review", "reviewer", f"Review: {title}",
         "Review the code against the code-review checklist and request changes until it passes.", ("implement",)),
        ("test", "tester", f"Test: {title}",
         f"Write tests/test_{module}.py and run it when code execution is enabled.", ("implement",)),
        ("docs", "writer", f"Document: {title}",
         f"Write docs/{slug}.md: purpose, files, public API, verification and limitations.", ("review", "test")),
    )
    tasks: dict[str, str] = {}
    for key, role, task_title, body, depends in specs:
        if role not in team:
            continue
        created = turn.act("create_task", title=task_title, description=header + body, assignee=team[role],
                           depends_on=[tasks[name] for name in depends if name in tasks])
        if created:
            tasks[key] = created["id"]
    turn.act("set_fact", key=f"{slug}.request", value=text[:2000])
    turn.act("set_fact", key=f"{slug}.module", value=module)
    plan = "; ".join(f"{task_id} {key} → @{team[role]}"
                     for key, task_id in tasks.items()
                     for spec_key, role, *_ in specs if spec_key == key)
    turn.say("#general", f"New project '{slug}'. Plan: {plan}. Dependencies are on the board.")
    hint = f" The knowledge base has a recipe: {recipe['title']}." if recipe else \
        " I found no recipe, so the coder may need help."
    turn.say(reply_to, f"Got it! I split “{title}” into {len(tasks)} tasks for the team.{hint} "
                       "Watch the Tasks board; I'll report back here.")
    projects[slug] = {"title": title, "request": text, "module": module, "tasks": tasks, "status": "active",
                      "poll": None, "reply_to": reply_to, "blocked_notified": []}
    turn.done.append(f"planned {slug}")


def review_projects(turn: _Turn) -> None:
    world = turn.world
    for slug, project in turn.agent.memory.get("projects", {}).items():
        if project["status"] not in {"active", "voting"}:
            continue
        tasks = [world.tasks[task_id] for task_id in project["tasks"].values() if task_id in world.tasks]
        for task in tasks:
            if task["status"] == "blocked" and task["id"] not in project["blocked_notified"]:
                note = task["notes"][-1]["text"] if task["notes"] else "no details"
                turn.say(project["reply_to"], f"⚠️ {task['id']} ({task['title']}) is blocked: {note} "
                                              "Reply 'retry' once it can continue.")
                project["blocked_notified"].append(task["id"])
                turn.done.append(f"escalated {task['id']}")
        if not tasks or any(task["status"] != "done" or not turn.settled(task) for task in tasks):
            continue
        if project["poll"] is None:
            voters = [world.tasks[project["tasks"][key]]["assignee"] for key in ("review", "test")
                      if key in project["tasks"]]
            voters = [voter for voter in voters if voter in world.agents]
            poll = None
            if voters:
                poll = turn.act("create_poll", question=f"Ship project {slug}?", options=["ship", "hold"],
                                voters=voters)
            if poll:
                project["poll"], project["status"] = poll["id"], "voting"
                turn.say("#general", f"All tasks for {slug} are done. {' '.join('@' + v for v in voters)} "
                                     f"please vote on {poll['id']}.")
                turn.done.append(f"opened {poll['id']}")
            else:
                finish_project(turn, slug, project, None)
            continue
        poll = world.polls.get(project["poll"])
        if poll and poll["status"] == "closed":
            if poll["result"]["winner"] == "ship":
                finish_project(turn, slug, project, poll)
            else:
                project["status"] = "on_hold"
                reasons = "; ".join(f"{v}: {b['reason']}" for v, b in poll["votes"].items())
                turn.say(project["reply_to"], f"The team voted to hold {slug} ({reasons}). Tell me how to proceed.")


def finish_project(turn: _Turn, slug: str, project: dict, poll: dict | None) -> None:
    world = turn.world
    lines = [f"# Project report: {project['title']}", "", f"Request: {project['request']}", "", "## Tasks", ""]
    for task_id in project["tasks"].values():
        task = world.tasks[task_id]
        lines.append(f"- {task_id} {task['title']} — {world.display_name(task['assignee'])}: "
                     f"{task['result'] or task['status']}")
    produced = [path for path in sorted(world.files) if slug in path or project["module"] in path]
    lines += ["", "## Files", ""] + [f"- {path}" for path in produced]
    if poll:
        lines += ["", f"## Release vote ({poll['id']})", ""]
        lines += [f"- {world.display_name(v)}: {b['option']} — {b['reason']}" for v, b in poll["votes"].items()]
    path = f"reports/{slug}.md"
    turn.act("write_file", path=path, content="\n".join(lines) + "\n")
    project["status"] = "done"
    turn.say(project["reply_to"], f"✅ Project '{slug}' is complete. Report: {path}. "
                                  f"Files: {', '.join(produced) or 'none'}.")
    turn.done.append(f"finished {slug}")


# ----------------------------------------------------------------- workers
def researcher_policy(turn: _Turn) -> None:
    for task in turn.ready_tasks():
        slug, request, _ = task_context(task)
        turn.act("update_task", task_id=task["id"], status="in_progress", note="Searching the knowledge base")
        found = turn.act("search_knowledge", query=request[:500], limit=5) or {"results": []}
        recipe = find_recipe(turn, request)
        lines = [f"# Research notes: {slug}", "", f"Request: {request}", "", "## Knowledge base matches", ""]
        lines += [f"- `{r['id']}` {r['title']} ({r['kind']}, score {r['score']}): {r['snippet']}"
                  for r in found["results"]] or ["- No matching documents."]
        lines += ["", "## Recommendation", ""]
        if recipe:
            lines.append(f"Use recipe `{recipe['id']}` and name the module `{recipe['module']}`. "
                         "It includes reference tests.")
        else:
            lines.append("No recipe covers this request. The implementation needs original work.")
        path = f"notes/{slug}-research.md"
        turn.act("write_file", path=path, content="\n".join(lines) + "\n")
        turn.act("set_fact", key=f"{slug}.recipe", value=recipe["id"] if recipe else "none")
        if recipe:
            turn.act("set_fact", key=f"{slug}.module", value=identifier(recipe["module"]))
        result = f"Recipe '{recipe['title']}' fits." if recipe else "No recipe found; original work needed."
        turn.act("update_task", task_id=task["id"], status="done", result=f"{result} Notes in {path}.")
        turn.say("#dev", f"Research for {slug} done: {result} See {path}. {turn.mention_dependents(task)}".strip())
        turn.done.append(f"researched {slug}")


STUB = '''"""Placeholder for: {request}"""


def main():
    """Entry point that still needs a real implementation."""
    raise NotImplementedError("TODO: implement {slug}")
'''


def coder_policy(turn: _Turn) -> None:
    for message in turn.obs["messages"]:
        if message["text"].startswith("CHANGES REQUESTED"):
            apply_review(turn, message)
    for task in turn.ready_tasks():
        slug, request, module_hint = task_context(task)
        turn.act("update_task", task_id=task["id"], status="in_progress", note="Reading research notes and facts")
        facts = turn.facts(slug)
        notes = f"notes/{slug}-research.md"
        if notes in turn.world.files:
            turn.act("read_file", path=notes)
        module = identifier(facts.get("module") or module_hint or slug)
        path = f"src/{module}.py"
        recipe = recipe_for(turn, facts, request)
        if recipe is None:
            turn.act("write_file", path=path, content=STUB.format(request=request.replace('"', "'")[:120],
                                                                   slug=slug))
            turn.act("update_task", task_id=task["id"], status="blocked",
                     note=f"No recipe for this request. I wrote a stub at {path}. Switch me to a Claude brain, "
                          "or add a knowledge note with a 'python module' code block, then reply 'retry'.")
            turn.say(task["created_by"] if task["created_by"] in turn.world.agents else "#dev",
                     f"BLOCKED {task['id']}: no recipe for '{slug}'. Stub written to {path}.")
            turn.done.append(f"blocked on {task['id']}")
            continue
        turn.act("write_file", path=path, content=recipe["code"]["module"])
        report = turn.act("check_python", path=path)
        if not report or not report["syntax_ok"]:
            turn.act("update_task", task_id=task["id"], status="blocked", note=f"{path} does not parse")
            continue
        public = [f["name"] for f in report["functions"] if not f["name"].startswith("_")]
        turn.act("set_fact", key=f"{slug}.code", value=path)
        turn.act("update_task", task_id=task["id"], status="done",
                 result=f"Wrote {path} from recipe '{recipe['title']}' ({', '.join(public)}).")
        turn.say("#dev", f"{path} is ready ({task['id']}). {turn.mention_dependents(task)} "
                         "please review and test.".strip())
        turn.done.append(f"implemented {path}")


def autofix(source: str) -> tuple[str, list[str]]:
    """Fix mechanical review findings; returns the new source and what changed."""
    changes = []
    lines = source.splitlines()
    if any("\t" in line for line in lines):
        lines = [line.expandtabs(4) for line in lines]
        changes.append("replaced tabs")
    if any(line != line.rstrip() for line in lines):
        lines = [line.rstrip() for line in lines]
        changes.append("removed trailing whitespace")
    try:
        tree = ast.parse("\n".join(lines))
    except SyntaxError:
        tree = None
    if tree is not None:
        inserts = []
        for node in ast.walk(tree):
            if (isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and not node.name.startswith("_")
                    and ast.get_docstring(node) is None and node.body and node.body[0].lineno > node.lineno):
                first = node.body[0]
                words = node.name.replace("_", " ").strip().capitalize()
                inserts.append((first.lineno - 1, " " * first.col_offset + f'"""{words}."""'))
        for index, text in sorted(inserts, reverse=True):
            lines.insert(index, text)
        if inserts:
            changes.append(f"added {len(inserts)} function docstring(s)")
        if ast.get_docstring(tree) is None:
            lines[0:0] = ['"""Module generated by the AI Collab Lab team."""', "", ""]
            changes.append("added a module docstring")
    fixed = "\n".join(lines) + "\n"
    if fixed != source and not changes:
        changes.append("added the final newline")
    return fixed, changes


def apply_review(turn: _Turn, message: dict) -> None:
    match = _CODE_PATH.search(message["text"])
    if not match or match[1] not in turn.world.files:
        return
    path = match[1]
    current = turn.act("read_file", path=path)
    if not current:
        return
    fixed, changes = autofix(current["content"])
    if changes:
        turn.act("write_file", path=path, content=fixed)
        turn.say(message["sender"], f"FIXED {path}: {', '.join(changes)}. Please re-review.")
        turn.done.append(f"fixed {path}")
    else:
        turn.say(message["sender"], f"I cannot fix the remaining findings in {path} automatically.")


def review_findings(report: dict) -> list[tuple[str, bool]]:
    """Return (finding, fixable automatically) pairs from a check_python report."""
    if not report["syntax_ok"]:
        return [(f"line {report['error']['line']}: syntax error ({report['error']['message']})", False)]
    findings = []
    if not report["module_docstring"]:
        findings.append(("add a module docstring", True))
    for function in report["functions"]:
        if not function["name"].startswith("_") and not function["docstring"]:
            findings.append((f"line {function['line']}: {function['name']} needs a docstring", True))
        if function["raises_not_implemented"]:
            findings.append((f"{function['name']} is not implemented", False))
    if report["todo_count"]:
        findings.append((f"remove {report['todo_count']} TODO/FIXME marker(s)", False))
    if report["long_lines"]:
        findings.append((f"lines {report['long_lines']} exceed 100 characters", False))
    if report["tabs"]:
        findings.append(("indent with spaces, not tabs", True))
    if report["trailing_whitespace"]:
        findings.append((f"trailing whitespace on lines {report['trailing_whitespace']}", True))
    if not report["final_newline"]:
        findings.append(("end the file with a newline", True))
    return findings


def reviewer_policy(turn: _Turn) -> None:
    vote_on_polls(turn)
    reviewed = turn.agent.memory.setdefault("reviewed_versions", {})
    rounds = turn.agent.memory.setdefault("review_rounds", {})
    for task in turn.ready_tasks(("todo", "in_progress")):
        slug, _, module_hint = task_context(task)
        path = code_path(turn, slug, turn.facts(slug), module_hint)
        record = turn.world.files.get(path)
        if record is None:
            if task["status"] == "todo":
                turn.act("update_task", task_id=task["id"], status="blocked", note=f"No code found at {path}")
            continue
        if reviewed.get(task["id"]) == record["version"]:
            continue
        if task["status"] == "todo":
            turn.act("update_task", task_id=task["id"], status="in_progress", note=f"Reviewing {path}")
        report = turn.act("check_python", path=path)
        if report is None:
            continue
        reviewed[task["id"]] = record["version"]
        rounds[task["id"]] = rounds.get(task["id"], 0) + 1
        findings = review_findings(report)
        author = record["author"] if record["author"] in turn.world.agents else "#dev"
        if not findings:
            turn.act("update_task", task_id=task["id"], status="done",
                     result=f"Approved {path} v{record['version']} after {rounds[task['id']]} round(s): parses, "
                            "documented, no TODOs, style clean.")
            turn.say(author, f"Approved {path} v{record['version']}. Nice work!")
            turn.done.append(f"approved {path}")
        elif all(fixable for _, fixable in findings) and rounds[task["id"]] <= 3:
            listing = "\n- ".join(text for text, _ in findings)
            turn.act("update_task", task_id=task["id"], note=f"Changes requested on v{record['version']}")
            turn.say(author, f"CHANGES REQUESTED for {path} ({task['id']}):\n- {listing}")
            turn.done.append(f"requested changes on {path}")
        else:
            listing = "; ".join(text for text, _ in findings)
            turn.act("update_task", task_id=task["id"], status="blocked", note=f"Review failed: {listing}")
            turn.done.append(f"blocked review of {path}")


SMOKE_TEST = '''import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

import {module}


class SmokeTests(unittest.TestCase):
    def test_public_functions_exist(self):
        for name in {names!r}:
            self.assertTrue(callable(getattr({module}, name)), name)


if __name__ == "__main__":
    unittest.main()
'''


def tester_policy(turn: _Turn) -> None:
    vote_on_polls(turn)
    for task in turn.ready_tasks():
        slug, request, module_hint = task_context(task)
        facts = turn.facts(slug)
        path = code_path(turn, slug, facts, module_hint)
        if path not in turn.world.files:
            turn.act("update_task", task_id=task["id"], status="blocked", note=f"No code found at {path}")
            continue
        turn.act("update_task", task_id=task["id"], status="in_progress", note=f"Preparing tests for {path}")
        module = path.rsplit("/", 1)[-1][:-3]
        recipe = recipe_for(turn, facts, request)
        report = turn.act("check_python", path=path) or {"functions": []}
        if recipe and recipe["code"].get("tests"):
            content, origin = recipe["code"]["tests"], f"recipe '{recipe['title']}'"
        else:
            names = [f["name"] for f in report["functions"] if not f["name"].startswith("_")]
            content, origin = SMOKE_TEST.format(module=module, names=names), "a generated smoke test"
        test_path = f"tests/test_{module}.py"
        turn.act("write_file", path=test_path, content=content)
        static = turn.act("check_python", path=test_path) or {"functions": []}
        count = len([f for f in static["functions"] if f["name"].startswith("test")])
        if turn.engine.settings.get("allow_code_execution"):
            run = turn.act("run_python", path=test_path, timeout_seconds=15)
            ran = re.search(r"Ran (\d+) tests?", (run or {}).get("stderr", ""))
            if run and run.get("passed"):
                result = f"{ran[1] if ran else count} test(s) passed: {test_path} (from {origin})."
                turn.act("update_task", task_id=task["id"], status="done", result=result)
            else:
                tail = ((run or {}).get("stderr") or "no output").strip().splitlines()[-3:]
                turn.act("update_task", task_id=task["id"], status="blocked",
                         note=f"Tests failed: {' | '.join(tail)}")
                turn.say("#dev", f"BLOCKED {task['id']}: {test_path} failed. {turn.world.files[path]['author']} "
                                 "please take a look.")
                continue
        else:
            result = (f"Wrote {test_path} with {count} test(s) from {origin}; static checks passed. Code execution "
                      "is disabled, so the tests were not run (enable it in Settings).")
            turn.act("update_task", task_id=task["id"], status="done", result=result)
        turn.say("#dev", f"Testing {slug}: {result} {turn.mention_dependents(task)}".strip())
        turn.done.append(f"tested {slug}")


def writer_policy(turn: _Turn) -> None:
    for task in turn.ready_tasks():
        slug, request, module_hint = task_context(task)
        facts = turn.facts(slug)
        path = code_path(turn, slug, facts, module_hint)
        turn.act("update_task", task_id=task["id"], status="in_progress", note="Collecting results from the team")
        report = turn.act("check_python", path=path) if path in turn.world.files else None
        related = [t for t in turn.world.tasks.values() if task_context(t)[0] == slug and t["id"] != task["id"]]
        lines = [f"# {slug.replace('_', ' ').title()}", "", f"> Request: {request}", "", "## Files", ""]
        lines += [f"- `{p}`" for p in sorted(turn.world.files) if slug in p or p in (path, f"tests/test_{path[4:]}")]
        lines += ["", "## Public API", ""]
        if report and report.get("syntax_ok"):
            lines += [f"- `{f['name']}({', '.join(f['args'])})` — {f['summary'] or 'no description'}"
                      for f in report["functions"] if not f["name"].startswith("_")]
            lines += [f"- class `{c['name']}`" for c in report["classes"]]
        else:
            lines.append("- No parseable source was available.")
        lines += ["", "## How the team built and checked it", ""]
        lines += [f"- {t['id']} {t['title']} ({turn.world.display_name(t['assignee'])}): {t['result'] or t['status']}"
                  for t in related]
        lines += ["", "## Usage", "", f"Import the module from `src/` or run `python {path}` for a quick example.", ""]
        doc_path = f"docs/{slug}.md"
        turn.act("write_file", path=doc_path, content="\n".join(lines))
        turn.act("update_task", task_id=task["id"], status="done", result=f"Wrote {doc_path}.")
        turn.say("#general", f"Documentation for {slug} is ready: {doc_path}")
        turn.done.append(f"documented {slug}")


def custom_policy(turn: _Turn) -> None:
    acknowledged = turn.agent.memory.setdefault("acknowledged", [])
    for task in turn.ready_tasks():
        if task["id"] in acknowledged:
            continue
        turn.act("update_task", task_id=task["id"],
                 note=f"{turn.agent.name} is a scripted custom agent with no playbook. Switch it to Claude or "
                      "reassign this task.")
        acknowledged.append(task["id"])
        turn.done.append(f"acknowledged {task['id']}")


POLICIES = {"coordinator": coordinator_policy, "researcher": researcher_policy, "coder": coder_policy,
            "reviewer": reviewer_policy, "tester": tester_policy, "writer": writer_policy, "custom": custom_policy}
