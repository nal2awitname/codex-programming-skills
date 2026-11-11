---
name: multi-agent-collab-lab
description: "Extend or debug AI Collab Lab (examples/ai-collab-lab), the local multi-agent workbench where scripted or Claude agents collaborate through shared tools. Use when adding tools, agent roles, brains or model providers, knowledge recipes, scenarios or GUI panels, or when agents never wake, loop, lose messages or report false results."
---

# Extend AI Collab Lab

AI Collab Lab is a Python 3.10+ standard-library application with an optional Anthropic SDK dependency. A browser GUI talks to a local JSON API; a tick-based engine wakes agents that act only through validated tools on a shared world. Respond in the user's language; write code, comments, identifiers and machine-facing configuration in English.

## Map

| File | Owns |
| --- | --- |
| `collablab/world.py` | Shared state (agents, channels, messages, tasks, files, facts, polls, knowledge), validation, events, export/import |
| `collablab/tools.py` | Tool registry, argument validation, permissions, safe calculator, static Python analysis, opt-in `run_python` |
| `collablab/engine.py` | Settings, team setup, wake rules, tick loop, budgets, background run, scenarios, snapshots |
| `collablab/brains/scripted.py` | Offline role playbooks (coordinator, researcher, coder, reviewer, tester, writer, custom) |
| `collablab/brains/claude.py` | Claude tool-use loop, prompts, request arguments, error classification |
| `collablab/knowledge/*.md` | Knowledge documents and code recipes the scripted team builds from |
| `collablab/server.py` | Static files and `/api/*` routes with host, header and JSON checks |
| `collablab/web/` | `index.html`, `style.css`, `app.js` (no external dependencies) |
| `scenarios/*.json`, `tests/` | Presets and the unittest suites |

Read [extension recipes](references/extension-recipes.md) before writing a new tool, role policy, brain, recipe or API route.

## Invariants

1. **One way to change the world.** Mutate state only through `World` methods while holding `world.lock`; agents and the GUI tool console go through `Toolbox.call`. Each mutation records an event.
2. **Synchronous ticks.** An agent observes changes up to the sequence number at the start of the tick and sees later changes next tick. Scripted readiness also requires dependencies settled before the current tick. Keep both, or hand-offs collapse into one tick.
3. **Wake rules.** Agents wake for relevant unread messages, task or poll changes made by someone else (`updated_seq`, `updated_by`), or a nudge. New shared state that should wake agents needs the same two fields and must be added to `is_awake` and `observe`.
4. **Structured tool errors.** Tools validate input against their schema subset (`additionalProperties: false`) and raise `WorldError(code, message)` for bad input. Models read these errors and recover; never let user input raise another exception.
5. **Claude conversations are append-only.** Append `response.content` unchanged, return all `tool_result` blocks for one response in a single user message, never trim or edit history, and requeue an observation when the model produced nothing.
6. **Honest results.** Agents and docs must not claim tests passed unless `run_python` output shows it. Scripted agents escalate requests without a recipe instead of guessing.
7. **Secrets and safety.** Keep the API key in memory only; exports, snapshots and logs exclude it. Bind to 127.0.0.1 by default, require `X-Collab-Lab: 1` plus JSON on POST, check the Host header, and keep `run_python` disabled unless the operator enables it.
8. **Repository language policy.** No Thai text in `.py`, `.js`, `.json` or Markdown code blocks; use `\u` escapes in tests. Thai belongs in Markdown prose and in knowledge `Keywords:` lines.

## Workflow

1. **Locate.** Identify the layer the request touches with the map. Read the relevant test file first; it documents the expected behavior.
2. **Implement.** Follow the matching recipe. Keep tool names, error codes, event types and scenario fields backward compatible; exported state must still import.
3. **Cover.** Add a unittest next to the closest existing case: world/tool rules in `test_world_tools.py`, team behavior in `test_scripted_team.py`, model loop in `test_claude_brain.py` (fake client; real SDK only against the local mock), routes in `test_server.py`, launcher in `test_cli.py`.
4. **Verify.** From `examples/ai-collab-lab`:

```sh
python -B -m unittest discover -s tests -v
python -B collab_lab.py --demo --allow-code-execution
python -B collab_lab.py --no-browser --port 8799
```

From the repository root run `python -B scripts/check_repo.py --test`. For GUI changes, open the page, exercise the changed interaction, and check the browser console. With the Anthropic SDK installed, the real-SDK tests run; without it they are skipped, which is not a pass for SDK behavior.

## Debugging

| Symptom | Usual cause |
| --- | --- |
| Agent never acts | Not awake: message not relevant (channel subscription, mention), change made by the agent itself, status `error`, backoff, or the Claude call budget is spent |
| Work finishes in one tick or out of order | Observation horizon or `settled()` check bypassed |
| Endless turns | A policy writes state that wakes itself or a partner every tick without progress; compare versions or remember what was handled |
| Message lost after an error | Cursor not restored: set `retry` or `requeue` on the `TurnResult` |
| Claude 400 after edits | History edited, tool results split across messages, or unsupported request field for the chosen model |
| GUI shows stale or doubled data | Refresh not serialized, or a render guard keyed on the wrong signature |

## Completion

Report what changed, the commands run with their results, and anything unverified (for example real Claude calls without an API key, or Windows-only behavior checked on another OS).
