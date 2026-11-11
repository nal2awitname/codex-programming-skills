# Extension recipes

Templates that match the current code. Paths are relative to `examples/ai-collab-lab`.

## Add a tool

Register the handler in `collablab/tools.py`. The decorator arguments are the name, category (one of `CATEGORIES`), description shown to models and people, the property schemas, and the required names. Helpers `S()` and `I()` build string and integer schemas.

```python
@tool("rename_file", "workspace", "Rename a workspace file, keeping its content and history version.",
      {"path": S("Current path", maxLength=160), "new_path": S("New path", maxLength=160)},
      ("path", "new_path"))
def _rename_file(ctx, args):
    record = ctx.world.read_file(args["path"])
    created = ctx.world.write_file(ctx.actor, args["new_path"], record["content"])
    ctx.world.delete_file(ctx.actor, args["path"])
    return {"path": created["path"], "version": created["version"]}
```

- Put state changes in a `World` method when more than one tool or the engine needs them; raise `WorldError` with a stable code.
- Tools that touch the host (processes, network, disk outside the world) take `requires_setting="..."`, a matching boolean in `SETTING_TYPES` and `DEFAULT_SETTINGS` (default `False`), and a warning in the settings dialog.
- The GUI tool console, the Claude tool list and agent permission checkboxes read the registry automatically.
- Test valid input, each error code, and permission or setting gates in `tests/test_world_tools.py`.

## Add or change a scripted role

A policy is a function that receives a `_Turn`. Use `turn.act(tool, **args)` for every action (it returns the result or `None` and stores `turn.last_error`), `turn.ready_tasks()` for work whose dependencies settled before this tick, `turn.facts(slug)` for blackboard values, and `turn.done.append(...)` for the turn summary.

```python
def translator_policy(turn):
    for task in turn.ready_tasks():
        slug, request, _ = task_context(task)
        turn.act("update_task", task_id=task["id"], status="in_progress", note="Translating")
        source = turn.act("read_file", path=f"docs/{slug}.md")
        if source is None:
            turn.act("update_task", task_id=task["id"], status="blocked", note=f"Missing docs/{slug}.md")
            continue
        turn.act("write_file", path=f"docs/{slug}.th.md", content=source["content"])
        turn.act("update_task", task_id=task["id"], status="done", result=f"Wrote docs/{slug}.th.md")
        turn.done.append(f"translated {slug}")
```

Register it in `POLICIES`, add the role name to `ROLES` in `world.py`, add a guide line to `ROLE_GUIDES` in `brains/claude.py`, and, when the coordinator should plan for it, add a spec to `plan_project`. Remember per-agent progress in `turn.agent.memory` so repeated wake-ups do not repeat work.

## Add a brain or model provider

A brain exposes `kind` and `take_turn(agent, observation, engine) -> TurnResult`. Keep network calls outside `world.lock`; execute tools through `engine.toolbox.call`; call `engine.reserve_llm_call()` before each request and `engine.record_usage(agent, usage)` after it.

```python
class EchoBrain:
    kind = "echo"

    def take_turn(self, agent, observation, engine):
        for message in observation["messages"]:
            engine.toolbox.call(agent.id, "send_message", {"to": message["sender"], "text": message["text"]})
        return TurnResult(summary=f"echoed {len(observation['messages'])} message(s)")
```

Register it in `Engine.__init__` (`self.brains`), add the name to `BRAINS` in `world.py`, and expose any model list through `/api/meta`. Set `TurnResult.retry` for transient failures (cursors restored, backoff), `fatal` for configuration problems (run stops, agent waits for the operator), and `requeue` when the observation was never processed. Use each provider's official SDK as an optional import with a clear install message.

## Add a knowledge recipe

Create `collablab/knowledge/<id>.md`. Header lines come right after the title; code blocks tagged `python module` and `python tests` become the recipe.

````markdown
# Unit price calculator
Kind: recipe
Keywords: unit price, price per unit, cost per item
Module: unit_price

One paragraph that explains the approach and its limits.

```python module
"""Unit price helpers."""


def unit_price(total: float, quantity: int) -> float:
    """Return the price of one unit."""
    if quantity <= 0:
        raise ValueError("quantity must be positive")
    return round(total / quantity, 2)
```

```python tests
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from unit_price import unit_price


class UnitPriceTests(unittest.TestCase):
    def test_price(self):
        self.assertEqual(unit_price(10, 4), 2.5)


if __name__ == "__main__":
    unittest.main()
```
````

Keywords may include any language because matching uses substrings. Run every recipe's tests against its module, keep lines at most 100 characters, and give public functions docstrings so the reviewer approves on the first round.

## Add a scenario

`scenarios/<id>.json` accepts `name`, `description`, `agents` (fields of `Engine.add_agent`), optional `settings` (never `api_key`), `files` (`path`, `content`), `tasks` (`title`, `description`, `assignee`, `depends_on`) and `messages` (`to`, `text`, sent as the user). Add the id to `test_scenarios_are_valid`.

## Add an API route or GUI panel

Add a handler method to `Handler` in `server.py`, register it in `GET_ROUTES` or `POST_ROUTES`, and read POST bodies only through `self._body()`. In `app.js`, call `api.get` or `api.post`, escape every value with `esc()` or `rich()` before inserting HTML, and guard re-renders with `changed(key, value)`. Add a route test in `tests/test_server.py` and check the GUI at desktop and phone widths.
