#!/usr/bin/env python3
"""Evaluate only explicitly mapped synthetic gold fields; report remaining gaps."""
import argparse
import json
import pathlib
import sqlite3

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=pathlib.Path)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
rubric = json.loads((root / "tests/Fixtures/discovery-expectations.json").read_text())
report = json.loads((args.directory / "report.json").read_text())
connection = sqlite3.connect(f"file:{args.directory / 'replay.sqlite3'}?mode=ro", uri=True)
company = json.loads(connection.execute("SELECT payload FROM entities WHERE kind='company'").fetchone()[0])
rules = rubric["calls"][report["call"]]
checks = []
for key, rule in rules.items():
    fact = company["facts"].get(key, {})
    value = fact.get("value")
    passed = True
    if "equals" in rule:
        passed &= value == rule["equals"]
    if "contains" in rule:
        passed &= all(word.lower() in str(value).lower() for word in rule["contains"])
    if "excludes" in rule:
        passed &= all(word.lower() not in str(value).lower() for word in rule["excludes"])
    if "absent" in rule:
        passed &= value is None
    if "absent_or" in rule:
        passed &= value is None or value == rule["absent_or"]
    if "other_detail" in rule:
        passed &= str(fact.get("otherDetail", "")).lower() == rule["other_detail"].lower()
    if "other_detail_one_of" in rule:
        passed &= str(fact.get("otherDetail", "")).casefold() in {name.casefold() for name in rule["other_detail_one_of"]}
    checks.append({"field": key, "pass": bool(passed), "actual": value, "actual_other_detail": fact.get("otherDetail"), "expected": rule})
    print(f"{'PASS' if passed else 'FAIL'} {key}: {value}")
unscored = {key: fact["value"] for key, fact in company["facts"].items() if key not in rules and fact["value"] is not None}
result = {
    "configuration_revision": report.get("configuration_revision"),
    "call": report["call"], "passed": sum(c["pass"] for c in checks), "total": len(checks),
    "checks": checks, "unscored_populated_fields": unscored,
    "unmapped_source_fields": rubric["unmapped_source_fields"],
    "manual_review_required": rubric["manual_review"],
    "latency_pass": not report.get("resumed", False) and report.get("error") is None and
        report["pending"] == 0 and report["sentences_processed"] == report["sentences_sent"] and report["p95_seconds"] <= 5
        and report.get("update_p95_seconds", report["p95_seconds"]) <= 5,
    "scope": rubric["scope"],
}
(args.directory / "evaluation.json").write_text(json.dumps(result, indent=2) + "\n")
print(f"Mapped checks: {result['passed']}/{result['total']}; {len(unscored)} populated fields still require review.")
print("Latency gate:", "PASS" if result["latency_pass"] else "NOT MET (incomplete, resumed, or above five seconds)")
