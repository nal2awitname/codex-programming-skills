#!/usr/bin/env python3
"""ARB v2: inventory -> evidence -> audited contract -> independent build -> verification."""

import argparse
import json
import sys
import subprocess
from pathlib import Path

sys.dont_write_bytecode = True

from arbkit import __version__
from arbkit.common import digest, read_json
from arbkit.runner import execute, verification_current
from arbkit.reporting import report
from arbkit.workflow import add_evidence, attach_observation, handoff, initialize, readiness, seal


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", action="version", version=__version__)
    subs = parser.add_subparsers(dest="action", required=True)
    for action in ["init", "evidence", "attach", "status", "report", "check", "seal", "handoff", "observe", "verify"]:
        sub = subs.add_parser(action)
        sub.add_argument("--work", required=True, type=Path)
        if action == "init":
            sub.add_argument("--source", required=True, type=Path)
            sub.add_argument("--max-files", type=int, default=5000)
            sub.add_argument("--max-bytes", type=int, default=2 * 1024 * 1024)
        if action == "evidence":
            sub.add_argument("--id", required=True)
            sub.add_argument("--file", required=True)
            sub.add_argument("--start", type=int, required=True)
            sub.add_argument("--end", type=int, required=True)
            sub.add_argument("--summary", required=True)
        if action == "attach":
            sub.add_argument("--id", required=True)
            sub.add_argument("--artifact", required=True, type=Path)
            sub.add_argument("--method", required=True)
            sub.add_argument("--summary", required=True)
        if action == "seal": sub.add_argument("--reviewed", action="store_true")
        if action == "handoff": sub.add_argument("--destination", required=True, type=Path)
        if action in ["observe", "verify"]:
            sub.add_argument("--command", required=True, type=Path)
            sub.add_argument("--timeout", type=float, default=10)
            sub.add_argument("--output-limit", type=int, default=1024 * 1024)
    args = parser.parse_args(argv)
    try:
        action = args.action
        if action == "init":
            result = initialize(args.source, args.work, args.max_files, args.max_bytes)
        elif action == "evidence":
            result = add_evidence(args.work, args.id, args.file, args.start, args.end, args.summary)
        elif action == "attach":
            result = attach_observation(args.work, args.id, args.artifact, args.method, args.summary)
        elif action in ["check", "status"]:
            result = readiness(args.work)
            path = args.work / "analyst/verification.json"
            if path.exists():
                verification = read_json(path)
                current = verification_current(args.work, verification)
                result["verification"] = {"current": current, "all_passed": verification.get("all_passed") if current else False,
                                           "oracle": verification.get("oracle")}
        elif action == "seal": result = seal(args.work, args.reviewed)
        elif action == "report": result = report(args.work)
        elif action == "handoff": result = handoff(args.work, args.destination)
        else: result = execute(args.work, args.command, action, args.timeout, args.output_limit)
        print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
        if action == "check" and not result["ready_for_handoff"]: return 2
        if action in ["observe", "verify"] and not result["success"]: return 2
        return 0
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
