#!/usr/bin/env python3
"""AI Collab Lab launcher: start the web GUI or run an offline demonstration."""
from __future__ import annotations

import argparse
import errno
import json
import sys
import threading
import webbrowser
from pathlib import Path

from collablab import __version__
from collablab.engine import Engine, read_scenario
from collablab.server import make_server
from collablab.world import WorldError

DEMO_REQUEST = "Build a temperature converter for Celsius, Fahrenheit and Kelvin"


def run_demo(request: str, allow_code_execution: bool) -> int:
    engine = Engine(settings={"auto_run": False, "allow_code_execution": allow_code_execution})
    engine.install_team()
    outcome = engine.user_message("nova", request)
    if not outcome["ok"]:
        print(json.dumps({"error": outcome["error"]}), file=sys.stderr)
        return 1
    ticks = engine.run_until_quiet(200)
    world = engine.world
    tasks = [{"id": t["id"], "title": t["title"], "assignee": t["assignee"], "status": t["status"],
              "result": t["result"]} for t in world.tasks.values()]
    summary = {
        "request": request,
        "ticks": ticks,
        "tasks": tasks,
        "files": sorted(world.files),
        "polls": [{"id": p["id"], "question": p["question"], "result": p["result"]} for p in world.polls.values()],
        "messages": len(world.messages),
        "tool_calls": sum(agent.stats["tool_calls"] for agent in world.agents.values()),
        "final_reply": next((m["text"] for m in reversed(world.messages) if m["sender"] == "nova"), None),
        "code_execution": allow_code_execution,
    }
    # Escape non-ASCII when stdout cannot encode it (for example a redirected Windows console).
    utf8 = (sys.stdout.encoding or "").lower().replace("-", "") == "utf8"
    print(json.dumps(summary, ensure_ascii=not utf8, indent=2))
    return 0 if tasks and all(t["status"] == "done" for t in tasks) else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", help="interface to bind (default: 127.0.0.1, this computer only)")
    parser.add_argument("--port", type=int, default=None, help="port (default: first free port from 8765)")
    parser.add_argument("--no-browser", action="store_true", help="do not open a browser window")
    parser.add_argument("--scenario", help="scenario id from the scenarios folder to load at start")
    parser.add_argument("--load", type=Path, help="state JSON exported from the GUI to load at start")
    parser.add_argument("--allow-code-execution", action="store_true", help="enable the run_python tool")
    parser.add_argument("--demo", action="store_true", help="run an offline team demonstration and print JSON")
    parser.add_argument("--request", default=DEMO_REQUEST, help="request text for --demo")
    parser.add_argument("--version", action="version", version=__version__)
    args = parser.parse_args(argv)

    if args.demo:
        return run_demo(args.request, args.allow_code_execution)

    engine = Engine(settings={"allow_code_execution": args.allow_code_execution})
    try:
        if args.load:
            engine.import_state(json.loads(args.load.read_text(encoding="utf-8")))
        elif args.scenario:
            engine.load_scenario(read_scenario(args.scenario))
        else:
            engine.install_team()
    except (OSError, ValueError, WorldError) as error:
        parser.exit(1, f"error: cannot prepare the world: {error}\n")

    ports = [args.port] if args.port is not None else list(range(8765, 8785))
    server = None
    for port in ports:
        try:
            server = make_server(engine, args.host, port)
            break
        except OSError as error:
            if error.errno not in (errno.EADDRINUSE, errno.EACCES) or port == ports[-1]:
                parser.exit(1, f"error: cannot listen on {args.host}:{port}: {error}\n")
    print(f"AI Collab Lab {__version__} is running at {server.url}", flush=True)
    print("Press Ctrl+C to stop.", flush=True)
    if not args.no_browser:
        threading.Timer(0.6, webbrowser.open, args=(server.url,)).start()
    try:
        server.serve_forever(poll_interval=0.3)
    except KeyboardInterrupt:
        print("\nStopping...", flush=True)
    finally:
        engine.pause(wait=5)
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
