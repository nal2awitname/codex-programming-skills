"""Human-readable analyst report; never included in the builder export."""

from .common import read_json
from .runner import verification_current
from .workflow import readiness, session


def report(work):
    work, _ = session(work)
    ready = readiness(work)
    index = read_json(work / "analyst/inventory.json")
    ledger = read_json(work / "analyst/ledger.json")
    def cell(value):
        return str(value).replace("|", "\\|").replace("\n", " ").replace("\r", " ")
    lines = ["# ARB v2 — analyst report", "", "Global completeness: **not proven**.", "",
             "These are discovery metadata, analyst-authored explanations and actual test records; "
             "inventory counts are not semantic understanding.", "", "## Files", "",
             "| File | Language evidence | Parser | Review | Explanation |",
             "| --- | --- | --- | --- | --- |"]
    rows = {f["path"]: f for f in ledger["files"]}
    for item in index["files"]:
        row = rows.get(item["path"], {})
        language = item["confirmed_language"] or (item["language_hint"] + " (hint)")
        lines.append("| " + " | ".join(cell(v) for v in [item["path"], language, item["parser"],
                       row.get("state", "missing"), row.get("summary", "")]) + " |")
    lines += ["", "## Discovered units", "", "| ID | File:line | Symbol | Kind | State | Explanation |",
              "| --- | --- | --- | --- | --- | --- |"]
    units = {u["id"]: u for u in ledger["units"]}
    for item in index["files"]:
        for unit in item["symbols"]:
            row = units.get(unit["id"], {})
            lines.append("| " + " | ".join(cell(v) for v in [unit["id"], item["path"] + ":" + str(unit["line"]),
                unit["qualified_name"], unit["kind"], row.get("state", "missing"), row.get("summary", "")]) + " |")
    lines += ["", "## Manual feature discovery", "", cell(ledger.get("feature_discovery", "Not reviewed")), ""]
    for feature in ledger.get("features", []):
        lines.append("- " + cell(feature.get("id")) + ": " + cell(feature.get("summary", "")) +
                     " (" + cell(feature.get("state", "unreviewed")) + ")")
    lines += ["", "## Handoff blockers", ""]
    lines += ["- " + cell(x) for x in ready["issues"]] or ["No current metadata/coverage blockers; analyst audit still required."]
    lines += ["", "## Exclusions and skipped files", ""]
    for item in index["skipped"] + index["policy_exclusions"]:
        lines.append("- " + cell(item["path"]) + ": " + cell(item["reason"]))
    path = work / "analyst/verification.json"
    if path.exists():
        record = read_json(path)
        current = verification_current(work, record)
        lines += ["", "## Verification", "", "Current: " + str(current),
                  "Oracle: " + record["oracle"], "", "| Case | Passed | Capture valid |", "| --- | --- | --- |"]
        for result in record["results"]:
            lines.append("| " + cell(result["id"]) + " | " + str(bool(current and result.get("passed"))) +
                         " | " + str(result["valid"]) + " |")
    target = work / "analyst/report.md"
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {"report": str(target), "builder_export": False, "ready_for_handoff": ready["ready_for_handoff"]}
