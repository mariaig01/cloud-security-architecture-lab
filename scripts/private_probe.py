#!/usr/bin/env python3
"""EC2 private probe. No AWS operations occur without --execute."""

import hashlib
from pathlib import Path
import socket
import tempfile
import threading
import time

from probe_common import Probe, arguments, classify


def listener(probe):
    """Keep a verified synthetic TCP listener available for the public P20 probe."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", 8080))
    server.listen(4)
    server.settimeout(1)
    with socket.create_connection(("127.0.0.1", 8080), timeout=2):
        pass
    connection, _ = server.accept()
    connection.close()
    probe.emit(kind="listener", test_id="P20-control", passed=True, port=8080)

    def serve():
        until = time.monotonic() + 1500
        with server:
            while time.monotonic() < until:
                try:
                    connection, _ = server.accept()
                except socket.timeout:
                    continue
                connection.close()
    # Keep listening after the summary; the boot watchdog stops the VM.
    threading.Thread(target=serve, daemon=False).start()


def main():
    args = arguments("private")
    probe = Probe(args, "private")
    listener(probe)
    with tempfile.TemporaryDirectory(prefix="cslab-probe-") as directory:
        root = Path(directory)
        source, downloaded = root / "synthetic.txt", root / "downloaded.txt"
        key = f"{args.prefix}probe/{args.run_id}/document.txt"
        probe.emit(kind="resource", documents_key=key,
                   logs_key=f"probe-fixtures/{args.run_id}/audit-canary.txt")
        source.write_text(f"synthetic:{args.run_id}:v1\n", encoding="utf-8")
        first, created = probe.s3("P01", "put-object", args.documents_bucket, "allowed",
                                   "--key", key, "--body", source)
        if not created or not first.get("VersionId") or first["VersionId"] == "null":
            probe.failures.append("P01-version")
            return probe.summary("Versioned positive control failed; dependent tests not run")
        _, read_ok = probe.s3("P02", "get-object", args.documents_bucket, "allowed",
                              "--key", key, downloaded)
        valid = read_ok and downloaded.exists() and downloaded.read_bytes() == source.read_bytes()
        probe.check("P02-content", valid, kind="content_check",
                    sha256=hashlib.sha256(source.read_bytes()).hexdigest())
        source.write_text(f"synthetic:{args.run_id}:v2\n", encoding="utf-8")
        second, overwritten = probe.s3("P03", "put-object", args.documents_bucket, "allowed",
                                       "--key", key, "--body", source)
        probe.check("P03-version", overwritten and second.get("VersionId") not in
                    {None, "null", first["VersionId"]}, kind="version_check")
        probe.s3("P04", "get-object", args.documents_bucket, "denied", "--key",
                 f"restricted/{args.run_id}/fixture.txt", root / "restricted.txt")
        probe.s3("P05", "put-object", args.documents_bucket, "denied", "--key",
                 f"restricted/{args.run_id}/unexpected.txt", "--body", source)
        probe.s3("P06", "put-object", args.documents_bucket, "denied", "--key",
                 f"{args.prefix.rstrip('/')}-other/{args.run_id}/unexpected.txt", "--body", source)
        probe.s3("P07", "list-objects-v2", args.documents_bucket, "denied", "--prefix", args.prefix)
        probe.s3("P08", "delete-object", args.documents_bucket, "denied", "--key", key)
        probe.s3("P09-delete", "delete-object", args.documents_bucket, "denied", "--key", key,
                 "--version-id", first["VersionId"])
        probe.s3("P09-read", "get-object", args.documents_bucket, "denied", "--key", key,
                 "--version-id", first["VersionId"], root / "old-version.txt")
        log_key = f"probe-fixtures/{args.run_id}/audit-canary.txt"
        probe.s3("P10", "get-object", args.logs_bucket, "denied", "--key", log_key, root / "log.txt")
        probe.s3("P11-write", "put-object", args.logs_bucket, "denied", "--key", log_key, "--body", source)
        probe.s3("P11-delete", "delete-object", args.logs_bucket, "denied", "--key", log_key)
    probe.network("P18", "example.com", 443)
    probe.network("P19-iam", "iam.amazonaws.com", 443)
    probe.network("P19-cloudtrail", f"cloudtrail.{args.region}.amazonaws.com", 443)
    return probe.summary()


if __name__ == "__main__":
    raise SystemExit(main())
