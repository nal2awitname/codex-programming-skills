"""Explicit, bounded text/JSON CLI probes. This is not a sandbox."""

import json
import os
import signal
import subprocess
import threading
from pathlib import Path

from .common import below, digest, file_hash, read_json, write_json
from .workflow import load_cases, load_contract, unchanged
from .inventory import scan


def load_command(path):
    data = read_json(path)
    if not isinstance(data, dict) or set(data) != {"argv", "cwd"}:
        raise ValueError("command file requires exactly argv and cwd")
    if not isinstance(data["argv"], list) or not data["argv"] or not all(isinstance(x, str) and x and "\0" not in x for x in data["argv"]):
        raise ValueError("argv must be a nonempty argument array; shell strings are not accepted")
    if not isinstance(data["cwd"], str) or not Path(data["cwd"]).is_dir():
        raise ValueError("command cwd must exist")
    data["cwd"] = str(Path(data["cwd"]).resolve())
    return data


def run(command, stdin, timeout=10, limit=1024 * 1024):
    if not 0.05 <= timeout <= 120 or not 1 <= limit <= 16 * 1024 * 1024:
        raise ValueError("timeout must be 0.05..120 seconds; output limit 1..16 MiB bytes")
    flags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    proc = subprocess.Popen(command["argv"], cwd=command["cwd"], shell=False,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            start_new_session=os.name != "nt", creationflags=flags)
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    overflow = threading.Event()
    def stop():
        try:
            if os.name == "nt":
                subprocess.run(["taskkill.exe", "/PID", str(proc.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5,
                               check=False)
                if proc.poll() is None: proc.kill()
            else:
                os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, OSError, subprocess.TimeoutExpired):
            if proc.poll() is None: proc.kill()
    def drain(pipe, name):
        try:
            while True:
                chunk = pipe.read(8192)
                if not chunk: break
                room = max(0, limit - len(buffers[name]))
                buffers[name].extend(chunk[:room])
                if len(chunk) > room:
                    overflow.set()
                    stop()
                    break
        finally:
            pipe.close()
    def feed():
        try:
            proc.stdin.write(stdin.encode("utf-8"))
        except (BrokenPipeError, OSError):
            pass
        finally:
            try: proc.stdin.close()
            except (BrokenPipeError, OSError): pass
    threads = [threading.Thread(target=drain, args=(proc.stdout, "stdout"), daemon=True),
               threading.Thread(target=drain, args=(proc.stderr, "stderr"), daemon=True),
               threading.Thread(target=feed, daemon=True)]
    for thread in threads: thread.start()
    timed_out = False
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        stop()
        proc.wait(timeout=6)
    # Do not leave probe descendants keeping capture streams open.
    for thread in threads: thread.join(timeout=0.1)
    if any(thread.is_alive() for thread in threads):
        stop()
        for thread in threads: thread.join(timeout=1)
    valid = not timed_out and not overflow.is_set() and not any(t.is_alive() for t in threads)
    result = {"exit_code": proc.returncode, "timed_out": timed_out,
              "output_limited": overflow.is_set(), "valid": valid}
    for name, raw in buffers.items():
        try: result[name] = raw.decode("utf-8")
        except UnicodeDecodeError:
            result[name] = ""
            result["valid"] = False
            result["encoding_error"] = True
    return result


def comparable(result, mode):
    if not result.get("valid", True):
        raise ValueError("incomplete, limited, timed-out or non-UTF-8 capture")
    output = result["stdout"]
    if mode == "json":
        def invalid(value): raise ValueError("non-finite JSON output")
        output = json.loads(output, parse_constant=invalid)
    return {"exit_code": result["exit_code"], "stdout": output, "stderr": result["stderr"]}


def execute(work, command_file, action, timeout=10, limit=1024 * 1024):
    work, meta, index = unchanged(work)
    cases = load_cases(work)
    command = load_command(command_file)
    contract = load_contract(work) if action == "verify" else None
    if action == "verify":
        reference_argument = False
        for argument in command["argv"]:
            try:
                candidate = Path(argument)
                if not candidate.is_absolute(): candidate = Path(command["cwd"]) / candidate
                if candidate.exists() and below(candidate, meta["source"]):
                    reference_argument = True
            except (OSError, ValueError):
                # An arbitrary long/non-path CLI argument need not be a filename.
                continue
        if below(command["cwd"], meta["source"]) or reference_argument or any(meta["source"] in x for x in command["argv"]):
            raise ValueError("rebuilt command must not run from or directly reference the original tree")
    if action == "verify" and below(work, command["cwd"]):
        raise ValueError("rebuilt cwd must not contain the analyst workspace; use a separate rebuilt directory")
    observed = None
    if action == "verify" and (work / "analyst/observations.json").exists():
        observed = read_json(work / "analyst/observations.json")
        if observed.get("cases_digest") != digest(cases) or observed.get("source_fingerprint") != index["fingerprint"]:
            raise ValueError("reference observations are stale; rerun observe")
        observed = {x["id"]: x for x in observed["results"]}
    results = []
    for case in cases["cases"]:
        actual = run(command, case["stdin"], timeout, limit)
        row = {"id": case["id"], **actual}
        try:
            normalized = comparable(actual, case["mode"])
            if action == "observe":
                if "expected" in case and digest(normalized) != digest(case["expected"]):
                    row.update(valid=False, reason="reference disagrees with specified expectation")
            else:
                if observed is not None:
                    if case["id"] not in observed: raise ValueError("reference case is missing")
                    expected = comparable(observed[case["id"]], case["mode"])
                elif "expected" in case:
                    expected = case["expected"]
                else:
                    raise ValueError("no reference observation or specified expectation")
                row["passed"] = digest(normalized) == digest(expected)
        except (ValueError, KeyError, TypeError) as error:
            row.update(valid=False, reason=str(error))
            if action == "verify": row["passed"] = False
        results.append(row)
    record = {"schema_version": 2, "cases_digest": digest(cases),
              "source_fingerprint": index["fingerprint"], "command": command,
              "command_file_sha256": file_hash(command_file), "results": results}
    if action == "verify":
        record["contract_digest"] = digest(contract)
        record["rebuilt_fingerprint"] = scan(command["cwd"])["fingerprint"]
        record["command_file"] = str(Path(command_file).resolve())
        record["oracle"] = "observed_reference" if observed is not None else "specified_expectations_only"
        record["all_passed"] = all(x.get("passed") and x["valid"] for x in results)
    else:
        record["all_valid"] = all(x["valid"] for x in results)
    write_json(work / ("analyst/observations.json" if action == "observe" else "analyst/verification.json"), record)
    return {"action": action, "cases": len(results),
            "valid": sum(x["valid"] for x in results),
            "passed": sum(bool(x.get("passed")) for x in results) if action == "verify" else None,
            "success": record.get("all_passed", record.get("all_valid")),
            "oracle": record.get("oracle", "reference_capture"), "sandbox_created": False}


def verification_current(work, record):
    try:
        return (record.get("cases_digest") == digest(load_cases(work))
                and record.get("contract_digest") == digest(load_contract(work))
                and record.get("command_file_sha256") == file_hash(record["command_file"])
                and record.get("rebuilt_fingerprint") == scan(record["command"]["cwd"])["fingerprint"])
    except (OSError, ValueError, KeyError, TypeError):
        return False
