#!/usr/bin/env python3
"""EC2 public comparison probe. Never exports a role session."""

import json
from pathlib import Path
import tempfile

from probe_common import Probe, arguments


def main():
    args = arguments("public")
    probe = Probe(args, "public")
    caller, ok = probe.call("identity-sts", "sts", "get-caller-identity", "allowed")
    expected = f"arn:aws:sts::{args.account_id}:assumed-role/{args.role_name}/"
    if not ok or caller.get("Account") != args.account_id or not caller.get("Arn", "").startswith(expected):
        probe.failures.append("identity-sts")
        return probe.summary("Unexpected caller identity; abort")
    with tempfile.TemporaryDirectory(prefix="cslab-public-") as directory:
        root = Path(directory)
        source = root / "synthetic.txt"
        source.write_text(f"synthetic:{args.run_id}:unauthorized\n", encoding="utf-8")
        key = f"{args.prefix}probe/{args.run_id}/document.txt"
        log_key = f"probe-fixtures/{args.run_id}/audit-canary.txt"
        probe.emit(kind="resource", documents_key=key, logs_key=log_key)
        probe.s3("P14", "get-object", args.documents_bucket, "denied", "--key", key, root / "document.txt")
        probe.s3("P10", "get-object", args.logs_bucket, "denied", "--key", log_key, root / "log.txt")
        probe.s3("P11-write", "put-object", args.logs_bucket, "denied", "--key", log_key, "--body", source)
        probe.s3("P11-delete", "delete-object", args.logs_bucket, "denied", "--key", log_key)
    trust = json.dumps({"Version": "2012-10-17", "Statement": [{"Effect": "Allow",
                        "Principal": {"Service": "ec2.amazonaws.com"}, "Action": "sts:AssumeRole"}]})
    # RoleName has a 64-character maximum, including the fixed prefix.
    role = f"cslab-denied-{args.run_id[:51]}"
    probe.emit(kind="canary", role_name=role)
    probe.call("P15", "iam", "create-role", "denied", "--role-name", role,
               "--assume-role-policy-document", trust)
    # Send the exact audit.tf configuration; never disable logging.
    probe.call("P17", "cloudtrail", "update-trail", "denied", "--name", args.trail_arn,
               "--s3-bucket-name", args.logs_bucket, "--is-multi-region-trail",
               "--include-global-service-events", "--enable-log-file-validation")
    probe.network("P18-control", "example.com", 443, blocked=False)
    probe.network("P20", args.private_ip, 8080)
    return probe.summary()


if __name__ == "__main__":
    raise SystemExit(main())
