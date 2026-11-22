#!/usr/bin/env python3
"""Offline extraction of EC2 probe records. Does not contact AWS or certify the matrix."""

import argparse
import base64
import binascii
import hashlib
import json
from pathlib import Path
import re


def extract(text, run_id, location, instance_id):
    """Accept decoded console text or an EC2 get-console-output JSON response."""
    try:
        envelope = json.loads(text)
    except ValueError:
        envelope = None
    if isinstance(envelope, dict) and "Output" in envelope:
        if envelope.get("InstanceId") != instance_id:
            raise ValueError("Console response belongs to another instance")
        text = envelope["Output"]
        if not isinstance(text, str):
            raise ValueError("Console output is unavailable")
        if not re.search(r'\{[^\n]*"kind"', text):
            try:
                text = base64.b64decode(text, validate=True).decode("utf-8")
            except (ValueError, binascii.Error, UnicodeDecodeError) as error:
                raise ValueError("Console is neither decoded text nor valid base64") from error
    records = []
    for line in text.splitlines():
        start = line.find("{")
        if start < 0:
            continue
        try:
            record = json.loads(line[start:])
        except ValueError:
            continue
        if not isinstance(record, dict) or "kind" not in record:
            continue
        if (record.get("run_id"), record.get("location"), record.get("instance_id")) != (run_id, location, instance_id):
            raise ValueError("Mixed or unexpected probe identity in console")
        if record.get("kind") not in {"identity", "resource", "operation", "content_check",
                                      "version_check", "listener", "network", "canary", "summary"}:
            raise ValueError("Unknown probe record")
        records.append(record)
    if not records or records[0]["kind"] != "identity":
        raise ValueError("Missing initial identity record; console may be truncated")
    if records[-1]["kind"] != "summary" or sum(r["kind"] == "summary" for r in records) != 1:
        raise ValueError("Missing or ambiguous final summary; console is incomplete")
    summary = records[-1]
    if type(summary.get("passed")) is not bool or not isinstance(summary.get("failed_tests"), list):
        raise ValueError("Invalid summary schema")
    if summary["passed"] and (summary["failed_tests"] or any(r.get("passed") is False for r in records)):
        raise ValueError("Summary contradicts failed records")
    # Require every probe subtest. A summary alone cannot hide missing operations.
    private = {"P01", "P02", "P02-content", "P03", "P03-version", "P04", "P05", "P06",
               "P07", "P08", "P09-delete", "P09-read", "P10", "P11-write", "P11-delete",
               "P18", "P19-iam", "P19-cloudtrail", "P20-control"}
    public = {"identity-sts", "P10", "P11-write", "P11-delete", "P14", "P15",
              "P17", "P18-control", "P20"}
    required = private if location == "private" else public
    missing = required - {r.get("test_id") for r in records}
    return {"run_id": run_id, "location": location, "instance_id": instance_id,
            "complete": not missing, "missing_subtests": sorted(missing),
            "probe_passed": summary["passed"] and not missing,
            "matrix_status": "requires operator checks and CloudTrail correlation",
            "records": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("console", type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--location", choices=("private", "public"), required=True)
    parser.add_argument("--instance-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = extract(args.console.read_text(), args.run_id, args.location, args.instance_id)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    report["console_sha256"] = hashlib.sha256(args.console.read_bytes()).hexdigest()
    # Caller chooses a local raw-evidence path. This file is NOT sanitized for publication.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Probe complete={report['complete']}, passed={report['probe_passed']}; matrix still requires operator checks")
    return int(not report["probe_passed"])


if __name__ == "__main__":
    raise SystemExit(main())
