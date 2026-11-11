"""Workspace, evidence, coverage gates, and an allowlisted builder handoff."""

import json
import re
import shutil
import tempfile
from pathlib import Path

from .common import below, digest, file_hash, read_json, source_file, source_text, write_json
from .inventory import scan


def session(work):
    work = Path(work).resolve()
    data = read_json(work / "analyst/session.json")
    if data.get("schema_version") != 2:
        raise ValueError("unsupported workspace schema")
    return work, data


def unchanged(work):
    work, meta = session(work)
    old = read_json(work / "analyst/inventory.json")
    current = scan(meta["source"], **old["limits"])
    if current["fingerprint"] != old["fingerprint"]:
        raise ValueError("reference changed since discovery; initialize a new workspace")
    return work, meta, old


def initialize(source, work, max_files=5000, max_bytes=2 * 1024 * 1024):
    source, work = Path(source).resolve(), Path(work).resolve()
    if below(work, source) or below(source, work):
        raise ValueError("source and work must be separate, non-nested directories")
    if work.exists():
        raise ValueError("workspace already exists; refusing to overwrite")
    index = scan(source, max_files=max_files, max_bytes=max_bytes)
    file_rows, units = [], []
    for item in index["files"] + index["skipped"]:
        file_rows.append({"path": item["path"], "scope": "in", "state": "unreviewed",
                          "summary": "", "discovery_review": "", "evidence_ids": [],
                          "exclusion_reason": ""})
        for symbol in item.get("symbols", []):
            units.append({"id": symbol["id"], "scope": "in", "state": "unreviewed",
                          "summary": "", "evidence_ids": [], "requirement_ids": [],
                          "exclusion_reason": ""})
    work.mkdir(parents=True)
    write_json(work / "analyst/session.json", {"schema_version": 2, "source": str(source)})
    write_json(work / "analyst/inventory.json", index)
    write_json(work / "analyst/ledger.json", {"schema_version": 2, "files": file_rows, "units": units,
                                             "feature_discovery": "", "features": []})
    write_json(work / "analyst/evidence.json", {"schema_version": 2, "items": []})
    write_json(work / "contract.json", {"schema_version": 2, "project": "", "scope": "",
               "requirements": [], "compatibility_facts": [], "unknowns": []})
    write_json(work / "cases.json", {"schema_version": 2, "cases": []})
    return {"workspace": str(work), "files": len(index["files"]), "units": len(units),
            "skipped": len(index["skipped"]), "global_completeness": "not_proven"}


def add_evidence(work, evidence_id, relative, start, end, summary):
    work, meta, index = unchanged(work)
    if not re.fullmatch(r"E-[A-Za-z0-9_-]+", evidence_id) or not summary.strip():
        raise ValueError("use an E-identifier and a nonempty evidence summary")
    item = next((x for x in index["files"] if x["path"] == relative), None)
    if not item or not (1 <= start <= end <= item.get("line_count", 0)):
        raise ValueError("evidence must reference an inspected text file and valid line range")
    source_file(meta["source"], relative)
    evidence = read_json(work / "analyst/evidence.json")
    if any(x["id"] == evidence_id for x in evidence["items"]):
        raise ValueError("evidence identifier already exists")
    evidence["items"].append({"id": evidence_id, "kind": "source-confirmed",
        "file": relative, "sha256": item["sha256"], "start": start, "end": end,
        "summary": summary})
    write_json(work / "analyst/evidence.json", evidence)
    return {"recorded": evidence_id, "contains_source_code": False}


def load_contract(work):
    contract = read_json(Path(work) / "contract.json")
    allowed = {"schema_version", "project", "scope", "requirements", "compatibility_facts", "unknowns"}
    if not isinstance(contract, dict) or set(contract) != allowed or contract["schema_version"] != 2:
        raise ValueError("contract fields do not match schema v2")
    for key in ["project", "scope"]:
        if not isinstance(contract[key], str) or not contract[key].strip():
            raise ValueError("contract requires a nonempty " + key)
    if not isinstance(contract["requirements"], list) or not contract["requirements"]:
        raise ValueError("at least one behavioral requirement is required")
    ids = set()
    for req in contract["requirements"]:
        if not isinstance(req, dict) or set(req) != {"id", "behavior", "evidence_ids", "case_ids"}:
            raise ValueError("invalid requirement fields")
        if not isinstance(req["id"], str) or not re.fullmatch(r"R-[A-Za-z0-9_-]+", req["id"]) or req["id"] in ids:
            raise ValueError("requirements need unique R-identifiers")
        ids.add(req["id"])
        if not isinstance(req["behavior"], str) or not req["behavior"].strip():
            raise ValueError("requirement behavior must be explained")
        for field in ["evidence_ids", "case_ids"]:
            if not isinstance(req[field], list) or not req[field] or not all(isinstance(x, str) for x in req[field]):
                raise ValueError("requirement needs evidence and cases")
    if not isinstance(contract["compatibility_facts"], list) or not isinstance(contract["unknowns"], list):
        raise ValueError("compatibility_facts and unknowns must be arrays")
    for fact in contract["compatibility_facts"]:
        if not isinstance(fact, dict) or set(fact) != {"value", "reason"} or not all(isinstance(v, str) and v.strip() for v in fact.values()):
            raise ValueError("compatibility fact requires a value and reason")
    return contract


def attach_observation(work, evidence_id, artifact, method, summary):
    work, _, _ = unchanged(work)
    artifact = Path(artifact).resolve()
    if not re.fullmatch(r"E-[A-Za-z0-9_-]+", evidence_id) or not method.strip() or not summary.strip():
        raise ValueError("observation requires an E-identifier, actual method and summary")
    if not artifact.is_file():
        raise ValueError("observation artifact must be an existing tool output, trace or capture")
    evidence = read_json(work / "analyst/evidence.json")
    if any(x["id"] == evidence_id for x in evidence["items"]):
        raise ValueError("evidence identifier already exists")
    evidence["items"].append({"id": evidence_id, "kind": "tool-observed",
        "artifact": str(artifact), "sha256": file_hash(artifact), "method": method, "summary": summary})
    write_json(work / "analyst/evidence.json", evidence)
    return {"recorded": evidence_id, "artifact_copied": False}


def load_cases(work):
    data = read_json(Path(work) / "cases.json")
    if not isinstance(data, dict) or set(data) != {"schema_version", "cases"} or data["schema_version"] != 2:
        raise ValueError("cases fields do not match schema v2")
    if not isinstance(data["cases"], list) or not data["cases"]:
        raise ValueError("at least one independently written case is required")
    identifiers = set()
    for case in data["cases"]:
        if not isinstance(case, dict) or not {"id", "requirements", "stdin", "mode"} <= set(case) or set(case) - {"id", "requirements", "stdin", "mode", "expected"}:
            raise ValueError("invalid case fields")
        key = case["id"]
        if not isinstance(key, str) or not re.fullmatch(r"C-[A-Za-z0-9_-]+", key) or key in identifiers:
            raise ValueError("cases need unique C-identifiers")
        identifiers.add(key)
        if case["mode"] not in ["json", "text"] or not isinstance(case["stdin"], str):
            raise ValueError("case mode must be json/text with string stdin")
        if len(case["stdin"].encode("utf-8")) > 1024 * 1024:
            raise ValueError("case stdin exceeds 1 MiB")
        if not isinstance(case["requirements"], list) or not case["requirements"] or not all(isinstance(x, str) for x in case["requirements"]):
            raise ValueError("case requires requirement identifiers")
        if "expected" in case:
            expected = case["expected"]
            if not isinstance(expected, dict) or set(expected) != {"exit_code", "stdout", "stderr"}:
                raise ValueError("expected requires exit_code, stdout, stderr")
            if type(expected["exit_code"]) is not int or not isinstance(expected["stderr"], str):
                raise ValueError("invalid expected exit code or stderr")
            if case["mode"] == "text" and not isinstance(expected["stdout"], str):
                raise ValueError("text expectation stdout must be a string")
    return data


def _leaks(meta, index, contract, cases):
    texts = []
    def strings(value):
        if isinstance(value, str):
            texts.append(value)
        elif isinstance(value, dict):
            for v in value.values(): strings(v)
        elif isinstance(value, list):
            for v in value: strings(v)
    strings([contract, cases])
    joined = "\n".join(texts)
    normalized_joined = " ".join(joined.split())
    issues = []
    if str(Path(meta["source"]).resolve()) in joined or "```" in joined:
        issues.append("handoff contains source root or fenced implementation material")
    allowed_names = {f["value"] for f in contract["compatibility_facts"]}
    for item in index["files"]:
        for unit in item["symbols"]:
            name = unit["name"]
            if name.startswith("_") and not name.startswith("__") and name not in allowed_names:
                if re.search(r"(?<!\w)" + re.escape(name) + r"(?!\w)", joined):
                    issues.append("private symbol leaked: " + unit["id"])
        if item.get("artifact_kind"):
            continue
        raw = source_file(meta["source"], item["path"]).read_bytes()
        for line in source_text(raw).splitlines():
            normalized = " ".join(line.split())
            if len(normalized) >= 36 and normalized in normalized_joined:
                issues.append("possible copied source line from analyst file: " + item["path"])
                break
    return sorted(set(issues))


def readiness(work):
    work, meta, index = unchanged(work)
    issues = []
    try:
        contract, cases = load_contract(work), load_cases(work)
    except (ValueError, KeyError, TypeError) as error:
        return {"ready_for_handoff": False, "issues": [str(error)],
                "discovered_units": sum(len(f["symbols"]) for f in index["files"]),
                "files_accounted_for": len(index["files"]) + len(index["skipped"]),
                "global_completeness": "not_proven"}
    requirements = {x["id"]: x for x in contract["requirements"]}
    case_map = {x["id"]: x for x in cases["cases"]}
    evidence = read_json(work / "analyst/evidence.json")["items"]
    ev_ids = set()
    by_file = {x["path"]: x for x in index["files"]}
    for ev in evidence:
        if ev.get("kind") == "tool-observed":
            if (re.fullmatch(r"E-[A-Za-z0-9_-]+", ev.get("id", "")) and ev["id"] not in ev_ids
                and isinstance(ev.get("method"), str) and ev["method"].strip()
                and isinstance(ev.get("summary"), str) and ev["summary"].strip()
                and Path(ev.get("artifact", "")).is_file()
                and file_hash(ev["artifact"]) == ev.get("sha256")):
                ev_ids.add(ev["id"])
            else: issues.append("missing or stale tool observation artifact")
            continue
        item = by_file.get(ev.get("file"))
        if ev.get("kind") == "source-confirmed" and item and ev.get("sha256") == item["sha256"] and type(ev.get("start")) is int and type(ev.get("end")) is int and 1 <= ev["start"] <= ev["end"] <= item.get("line_count", 0) and isinstance(ev.get("summary"), str) and ev["summary"].strip() and re.fullmatch(r"E-[A-Za-z0-9_-]+", ev.get("id", "")) and ev["id"] not in ev_ids:
            ev_ids.add(ev["id"])
        else:
            issues.append("invalid evidence record")
    observations_path = work / "analyst/observations.json"
    if observations_path.exists():
        observed = read_json(observations_path)
        if observed.get("cases_digest") != digest(cases) or observed.get("source_fingerprint") != index["fingerprint"]:
            issues.append("stale observations; rerun observe")
        else:
            ev_ids.update("O-" + x["id"] for x in observed["results"] if x["valid"])
    if contract["unknowns"]:
        issues.append("in-scope unknowns remain; resolve or explicitly narrow scope")
    for req in requirements.values():
        if not set(req["evidence_ids"]) <= ev_ids:
            issues.append("missing evidence for " + req["id"])
        for cid in req["case_ids"]:
            if cid not in case_map or req["id"] not in case_map[cid]["requirements"]:
                issues.append("missing reciprocal case mapping for " + req["id"])
    for case in case_map.values():
        if not set(case["requirements"]) <= requirements.keys():
            issues.append("unknown requirement in " + case["id"])
        if "expected" not in case:
            issues.append("builder test expectation missing for " + case["id"])
        for rid in case["requirements"]:
            if rid in requirements and case["id"] not in requirements[rid]["case_ids"]:
                issues.append("missing reciprocal requirement mapping for " + case["id"])
    ledger = read_json(work / "analyst/ledger.json")
    features = ledger.get("features", [])
    if not isinstance(ledger.get("feature_discovery"), str) or not ledger["feature_discovery"].strip() or not isinstance(features, list) or not features:
        issues.append("manual feature/runtime-surface inventory is missing")
        features = []
    feature_ids = [x.get("id") for x in features]
    if len(set(feature_ids)) != len(feature_ids) or not all(isinstance(x, str) and re.fullmatch(r"B-[A-Za-z0-9_-]+", x) for x in feature_ids):
        issues.append("features require unique B-identifiers")
    covered = set()
    for feature in features:
        if feature.get("scope") == "excluded" and feature.get("exclusion_reason"):
            continue
        if feature.get("scope") != "in" or feature.get("state") != "understood" or not isinstance(feature.get("summary"), str) or not feature["summary"].strip() or not feature.get("evidence_ids") or not set(feature["evidence_ids"]) <= ev_ids or not feature.get("requirement_ids") or not set(feature["requirement_ids"]) <= requirements.keys():
            issues.append("feature lacks understanding/evidence/mapping: " + str(feature.get("id")))
        else:
            covered.update(feature["requirement_ids"])
    if not requirements.keys() <= covered:
        issues.append("requirements are not all accounted for in the manual feature inventory")
    expected_units = {u["id"] for f in index["files"] for u in f["symbols"]}
    expected_files = {f["path"] for f in index["files"] + index["skipped"]}
    for kind, key, expected in [("units", "id", expected_units), ("files", "path", expected_files)]:
        rows = ledger.get(kind, [])
        keys = [x.get(key) for x in rows]
        if len(keys) != len(set(keys)) or set(keys) != expected:
            issues.append("ledger does not account for every discovered " + kind)
        for row in rows:
            identifier = row.get(key, "unknown")
            if row.get("scope") == "excluded":
                if not isinstance(row.get("exclusion_reason"), str) or not row["exclusion_reason"].strip():
                    issues.append("exclusion reason missing: " + identifier)
                continue
            if row.get("scope") != "in" or row.get("state") != "understood" or not isinstance(row.get("summary"), str) or not row["summary"].strip() or not isinstance(row.get("evidence_ids"), list) or not row["evidence_ids"] or not set(row["evidence_ids"]) <= ev_ids:
                issues.append("not understood with evidence: " + identifier)
            if kind == "units" and (not row.get("requirement_ids") or not set(row["requirement_ids"]) <= requirements.keys()):
                issues.append("unit lacks behavioral mapping: " + identifier)
            if kind == "files" and (not isinstance(row.get("discovery_review"), str) or not row["discovery_review"].strip()):
                issues.append("file lacks dynamic/unsupported-discovery review: " + identifier)
    issues.extend(_leaks(meta, index, contract, cases))
    return {"ready_for_handoff": not issues, "issues": sorted(set(issues)),
            "files_accounted_for": len(expected_files), "discovered_units": len(expected_units),
            "requirements": len(requirements), "cases": len(case_map),
            "manual_features": len(features),
            "global_completeness": "not_proven", "policy_exclusions": index["policy_exclusions"]}


def review_digest(work):
    work, meta = session(work)
    names = ["contract.json", "cases.json", "analyst/inventory.json", "analyst/ledger.json",
             "analyst/evidence.json"]
    if (work / "analyst/observations.json").exists(): names.append("analyst/observations.json")
    return digest({name: file_hash(work / name) for name in names})


def seal(work, reviewed):
    if not reviewed:
        raise ValueError("--reviewed records that the analyst actually audited the spec and tests; it is not user permission")
    report = readiness(work)
    if not report["ready_for_handoff"]:
        raise ValueError("handoff blocked: " + "; ".join(report["issues"]))
    work, _ = session(work)
    record = {"schema_version": 2, "review_digest": review_digest(work),
              "meaning": "analyst audit recorded; not an automatic originality or semantic-understanding proof"}
    write_json(work / "analyst/review.json", record)
    return {"sealed": True, "review_digest": record["review_digest"]}


def handoff(work, destination):
    work, meta = session(work)
    report = readiness(work)
    review = read_json(work / "analyst/review.json")
    if not report["ready_for_handoff"] or review.get("review_digest") != review_digest(work):
        raise ValueError("handoff is blocked or review is stale; audit and seal current material")
    target = Path(destination).resolve()
    if target.exists() or below(target, meta["source"]) or below(target, work / "analyst") or target == work:
        raise ValueError("handoff requires a new directory outside reference and analyst areas")
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".arb-handoff-", dir=target.parent))
    try:
        for name in ["contract.json", "cases.json"]:
            shutil.copyfile(work / name, temporary / name)
        (temporary / "BUILD_BRIEF.md").write_text(
            "# Independent builder\n\nImplement contract.json using your own design. "
            "Use only this handoff and independent public documentation. Do not seek the reference, "
            "analyst records, private symbols, or source-derived code. Write your own implementation "
            "and tests. Run all acceptance cases and report actual results. A fresh context on a shared "
            "filesystem is not enforced access isolation. The toolkit does not provide an AI model "
            "or generate the implementation; an AI agent or developer must perform this work.\n",
            encoding="utf-8")
        write_json(temporary / "manifest.json", {"schema_version": 2,
            "files": {p.name: file_hash(p) for p in sorted(temporary.iterdir())},
            "isolation": "audited input package; filesystem access controls not provided"})
        temporary.rename(target)
    finally:
        if temporary.exists(): shutil.rmtree(temporary)
    return {"handoff": str(target), "files": ["contract.json", "cases.json", "BUILD_BRIEF.md", "manifest.json"]}
