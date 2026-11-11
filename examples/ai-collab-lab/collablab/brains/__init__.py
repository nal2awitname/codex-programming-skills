"""Decision makers for agents: a deterministic offline policy and Claude."""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class TurnResult:
    summary: str = ""
    tool_calls: int = 0
    llm_calls: int = 0
    error: str | None = None
    fatal: bool = False
    retry: bool = False
    requeue: bool = False  # the observation was never processed; deliver it again next time
    notes: list = field(default_factory=list)


class BrainUnavailable(Exception):
    """The brain cannot run with the current configuration (missing SDK or credentials)."""
