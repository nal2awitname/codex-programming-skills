"""Claude-powered agents using the Anthropic Python SDK (optional dependency).

Each agent keeps its own append-only conversation. A turn sends the agent's
new observations, executes every tool call Claude makes against the shared
world, returns all results in one user message and repeats until Claude stops
calling tools or the per-turn tool budget is spent.
"""
from __future__ import annotations

from ..tools import render
from . import BrainUnavailable, TurnResult

MAX_TOKENS = 16000
FALLBACK_BETA = "server-side-fallback-2026-07-01"
# Models that accept server-side refusal fallbacks with fallbacks="default".
FALLBACK_MODELS = {"claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-2", "claude-fable-5-1"}
SUGGESTED_MODELS = ("claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2")

ROLE_GUIDES = {
    "coordinator": "Turn user requests into a small plan on the task board: one owner per task, explicit "
                   "dependencies, descriptions that start with 'Project: <slug>' and 'Request: <text>'. Follow "
                   "progress, unblock teammates, run a ship/hold poll with the reviewer and tester when all tasks "
                   "are done, then write reports/<slug>.md and report back to the user.",
    "researcher": "Investigate assigned tasks with search_knowledge, read_knowledge and the workspace. Write "
                  "findings to notes/<slug>-research.md, publish key decisions with set_fact, then hand off.",
    "coder": "Implement assigned tasks as small, documented Python modules under src/. Validate inputs, keep "
             "lines under 100 characters, check your file with check_python, and tell reviewers what changed.",
    "reviewer": "Review code with read_file and check_python against the code-review checklist. Request changes "
                "with line numbers and concrete fixes, or approve explicitly and mark the task done.",
    "tester": "Write unittest files under tests/ that cover main paths, edge cases and invalid input. Run them "
              "with run_python when it is available and report exact results; never claim untested results.",
    "writer": "Write clear documentation under docs/ from the team's files, task results and review outcomes.",
    "custom": "Help the team in whatever way your persona describes.",
}


def classify_error(error: Exception) -> tuple[bool, str]:
    """Return (fatal, message). Fatal errors need the operator; others are retried later."""
    try:
        import anthropic
    except ImportError:  # pragma: no cover - the SDK raised the error, so it is installed
        anthropic = None
    if anthropic is not None:
        if isinstance(error, anthropic.AuthenticationError):
            return True, "Authentication failed: check the API key in Settings or ANTHROPIC_API_KEY."
        if isinstance(error, anthropic.PermissionDeniedError):
            return True, "The API key is not allowed to use this model or feature."
        if isinstance(error, anthropic.NotFoundError):
            return True, "Model not found: check the agent's model name."
        if isinstance(error, anthropic.BadRequestError):
            return True, f"The API rejected the request: {getattr(error, 'message', error)}"
        if isinstance(error, anthropic.RateLimitError):
            return False, "Rate limited by the API; the agent will retry shortly."
        if isinstance(error, anthropic.APIStatusError):
            status = getattr(error, "status_code", 0) or 0
            return status < 500, f"API error {status}: {getattr(error, 'message', error)}"
        if isinstance(error, anthropic.APIConnectionError):
            return False, "Network error while contacting the API; the agent will retry shortly."
    status = getattr(error, "status_code", None)
    if status in (400, 401, 403, 404):
        return True, f"API error {status}: {error}"
    return False, f"{type(error).__name__}: {error}"


class ClaudeBrain:
    kind = "claude"

    def __init__(self, client_factory=None):
        self.client_factory = client_factory
        self.histories: dict[str, list] = {}
        self._client = None
        self._client_key: object = object()

    # ------------------------------------------------------------- client
    def client(self, api_key: str | None):
        if self._client is not None and api_key == self._client_key:
            return self._client
        if self.client_factory is not None:
            self._client = self.client_factory(api_key)
        else:
            try:
                import anthropic
            except ImportError:
                raise BrainUnavailable("The Claude brain needs the Anthropic SDK: pip install anthropic") from None
            try:
                # Without an explicit key the SDK resolves ANTHROPIC_API_KEY or a stored profile.
                self._client = anthropic.Anthropic(api_key=api_key) if api_key else anthropic.Anthropic()
            except anthropic.AnthropicError as error:
                raise BrainUnavailable(f"No Anthropic credentials: set ANTHROPIC_API_KEY or enter a key in "
                                       f"Settings ({error})") from None
        self._client_key = api_key
        return self._client

    def forget(self, agent_id: str | None = None) -> None:
        if agent_id is None:
            self.histories.clear()
        else:
            self.histories.pop(agent_id, None)

    # ------------------------------------------------------------- prompts
    @staticmethod
    def system_prompt(agent, world, settings: dict) -> str:
        roster = "\n".join(f"- {a.id}: {a.name}, {a.role} ({a.brain} brain)" for a in world.agents.values())
        persona = f"\nPersona: {agent.persona}" if agent.persona else ""
        return (
            f"You are {agent.name} (id: {agent.id}), the {agent.role} on a team of AI agents collaborating "
            "inside AI Collab Lab, a simulated shared workspace with chat channels, direct messages, a task "
            "board, workspace files, a knowledge base, a shared blackboard of facts and polls.\n"
            f"Team:\n{roster}\n- user: the human operator\n"
            f"Your role: {ROLE_GUIDES.get(agent.role, ROLE_GUIDES['custom'])}{persona}\n\n"
            "How this world works:\n"
            "- You can only act through tools. Teammates see only what you put in messages, tasks, files and "
            "facts, so hand off explicitly by naming files and task ids.\n"
            "- You are woken when something relevant happens: a message to you, a mention, a channel post, or a "
            "change to a task or poll you care about. Each turn ends when you reply without calling tools; "
            "make that final reply a one-line summary of what you did.\n"
            f"- You may make at most {settings.get('max_tool_calls_per_turn', 8)} tool calls per turn.\n"
            "- Tasks have one owner. Move yours to in_progress when you start, add short notes, finish with "
            "status done and a result, or set blocked with a note that says what you need.\n"
            "- Keep messages short and concrete; put long content in files. Do not repeat work a teammate "
            "already reported.\n"
            "- Talk to the human with send_message to 'user'. Write to the user in the language they use.\n"
            "- run_python exists only when the operator enables code execution; never claim tests passed "
            "unless a tool result shows it."
        )

    @staticmethod
    def render_observation(agent, world, observation: dict) -> str:
        lines = [f"Tick {observation['tick']}. Updates since your last turn:"]
        if observation["messages"]:
            lines.append("New messages:")
            for message in observation["messages"]:
                if message["to"].startswith("#"):
                    where = message["to"]
                else:
                    where = "direct to you" if message["to"] == agent.id else f"direct to {message['to']}"
                lines.append(f"- [{message['id']} {where}] {world.display_name(message['sender'])} "
                             f"({message['sender']}): {message['text']}")
        if observation["task_changes"]:
            lines.append("Task changes:")
            for task in observation["task_changes"]:
                ready = "ready" if world.task_ready(task) else "waiting for " + ", ".join(world.pending_dependencies(task))
                lines.append(f"- {task['id']} '{task['title']}' status={task['status']} assignee={task['assignee']} "
                             f"({ready}; last change by {task.get('updated_by')})")
        if observation["poll_changes"]:
            lines.append("Poll changes:")
            for poll in observation["poll_changes"]:
                lines.append(f"- {poll['id']} '{poll['question']}' {poll['status']} options={poll['options']} "
                             f"votes={ {k: v['option'] for k, v in poll['votes'].items()} }")
        mine = [t for t in world.tasks.values() if t["assignee"] == agent.id and t["status"] != "done"]
        if mine:
            lines.append("Your open tasks: " + "; ".join(
                f"{t['id']} {t['title']} ({t['status']}{', ready' if world.task_ready(t) else ', waiting'})"
                for t in mine))
        pending = [p["id"] for p in world.polls.values()
                   if p["status"] == "open" and agent.id in p["voters"] and agent.id not in p["votes"]]
        if pending:
            lines.append("Polls waiting for your vote: " + ", ".join(pending))
        if observation.get("nudged"):
            lines.append("The operator nudged you to check in and continue your work.")
        if len(lines) == 1:
            lines.append("Nothing new. Check your tasks and continue if anything is unfinished.")
        lines.append("Act with tools now. Finish with a one-line summary and no tool calls.")
        return "\n".join(lines)

    # ---------------------------------------------------------------- turn
    def request_args(self, agent, system: str, tools: list, messages: list) -> dict:
        args = {
            "model": agent.model,
            "max_tokens": MAX_TOKENS,
            "system": system,
            "tools": tools,
            "messages": messages,
            "thinking": {"type": "adaptive", "display": "summarized"},
            "output_config": {"effort": agent.effort},
            "cache_control": {"type": "ephemeral"},
        }
        if agent.model in FALLBACK_MODELS:
            args["betas"] = [FALLBACK_BETA]
            args["fallbacks"] = "default"
        return args

    def take_turn(self, agent, observation: dict, engine) -> TurnResult:
        world = engine.world
        with world.lock:
            system = self.system_prompt(agent, world, engine.settings)
            prompt = self.render_observation(agent, world, observation)
            tools = [{"name": spec.name, "description": spec.description, "input_schema": spec.input_schema()}
                     for spec in engine.toolbox.available(agent.id)]
        history = self.histories.setdefault(agent.id, [])
        history.append({"role": "user", "content": prompt})
        result = TurnResult()
        limit = int(engine.settings.get("max_tool_calls_per_turn", 8))
        produced = refused = False
        try:
            client = self.client(engine.settings.get("api_key"))
            while True:
                if not engine.reserve_llm_call():
                    result.error, result.retry = "LLM call budget reached; raise it in Settings to continue.", True
                    break
                response = client.beta.messages.create(**self.request_args(agent, system, tools, history))
                result.llm_calls += 1
                engine.record_usage(agent, getattr(response, "usage", None))
                stop = getattr(response, "stop_reason", None)
                if stop == "refusal":
                    details = getattr(response, "stop_details", None)
                    category = getattr(details, "category", None) if details else None
                    result.error = f"Claude declined this turn (category: {category or 'unspecified'})."
                    refused = True
                    break
                history.append({"role": "assistant", "content": response.content})
                produced = True
                text = self._log_blocks(world, agent, response.content)
                calls = [block for block in response.content if getattr(block, "type", None) == "tool_use"]
                if stop == "pause_turn" and not calls:
                    continue
                if not calls:
                    result.summary = text or result.summary
                    if stop == "max_tokens":
                        result.error = "Response hit max_tokens; the turn ended early."
                    break
                outputs = []
                for block in calls:
                    if stop == "max_tokens":
                        outcome = {"ok": False, "error": {"code": "truncated",
                                                          "message": "Not executed: the response was cut off."}}
                    elif result.tool_calls >= limit:
                        outcome = {"ok": False, "error": {"code": "turn_budget",
                                                          "message": "Tool budget for this turn is used up."}}
                    else:
                        outcome = engine.toolbox.call(agent.id, block.name, block.input)
                        result.tool_calls += 1
                    outputs.append({"type": "tool_result", "tool_use_id": block.id, "content": render(outcome),
                                    "is_error": not outcome["ok"]})
                history.append({"role": "user", "content": outputs})
                if stop == "max_tokens" or result.tool_calls >= limit:
                    result.summary = result.summary or f"stopped after {result.tool_calls} tool calls"
                    break
        except BrainUnavailable as error:
            result.error, result.fatal = str(error), True
        except Exception as error:  # SDK and transport errors are classified, not hidden
            result.fatal, result.error = classify_error(error)
            result.retry = not result.fatal
        if not produced and history and history[-1].get("content") == prompt:
            # Nothing reached the model's side of the conversation; resend this observation next time.
            history.pop()
            # Fatal errors wait for the operator; refusals would only repeat, so neither is retried.
            result.retry = result.retry or (result.error is not None and not refused and not result.fatal)
            result.requeue = result.error is not None and not refused
        return result

    @staticmethod
    def _log_blocks(world, agent, content) -> str:
        text_parts = []
        with world.lock:
            for block in content:
                kind = getattr(block, "type", None)
                if kind == "thinking" and getattr(block, "thinking", ""):
                    world.log("thought", agent.id, block.thinking.strip()[:300], source="thinking")
                elif kind == "text" and getattr(block, "text", "").strip():
                    text_parts.append(block.text.strip())
                    world.log("thought", agent.id, block.text.strip()[:300], source="text")
                elif kind == "fallback":
                    world.log("system", agent.id, "a fallback model continued this turn after a refusal")
        return " ".join(text_parts)[:300]

