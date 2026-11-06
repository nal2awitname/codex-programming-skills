"""Validate and evaluate the neutral JSON scenario interface."""

from .core import LabError, OwnedIntBuffer, Scanner


DEMO_INITIAL = (137, 20, 137, -3, 137, 0)


def demo_scenario() -> dict:
    return {
        "initial": list(DEMO_INITIAL),
        "steps": [
            {"action": "first", "mode": "exact", "value": 137},
            {"action": "set", "index": 2, "value": 120},
            {"action": "next", "mode": "exact", "value": 120},
        ],
    }


def _fields(step: dict, allowed: set[str]) -> None:
    if set(step) - allowed:
        raise LabError("invalid_scenario")


def _evaluate(data: object) -> dict:
    if type(data) is not dict or set(data) != {"initial", "steps"}:
        raise LabError("invalid_scenario")
    if type(data["steps"]) is not list:
        raise LabError("invalid_scenario")
    buffer = OwnedIntBuffer(data["initial"])
    scanner = Scanner(buffer)
    history = []
    for step in data["steps"]:
        if type(step) is not dict:
            raise LabError("invalid_scenario")
        action = step.get("action")
        if type(action) is not str:
            raise LabError("invalid_scenario")
        if action in ("first", "next"):
            mode = step.get("mode")
            _fields(step, {"action", "mode", "value"})
            if mode != "exact" and "value" in step:
                raise LabError("invalid_scenario")
            operation = scanner.first if action == "first" else scanner.next
            history.append(operation(mode, step.get("value")))
        elif action == "set":
            _fields(step, {"action", "index", "value"})
            buffer.write(step.get("index"), step.get("value"))
        elif action == "reset":
            _fields(step, {"action"})
            scanner.reset()
        else:
            raise LabError("invalid_scenario")
    return {"history": history}


def evaluate_scenario(data: object) -> dict:
    """Return history on success, or exactly {\"error\": name} on failure.

    Mutations are local to a fresh allocation; evaluating a scenario never alters
    the supplied Python object or an earlier evaluation's scan state.
    """
    try:
        return _evaluate(data)
    except LabError as error:
        return {"error": error.name}
