#!/usr/bin/env python3
"""Run reproducible local checks only; never run a real AWS plan or apply."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def broken_links():
    missing = []
    for document in [ROOT / "README.md", ROOT / "PLAN.md", *sorted((ROOT / "docs").glob("*.md"))]:
        for target in re.findall(r"\[[^\]]*\]\(([^\s)]+)(?:\s+[^)]*)?\)", document.read_text()):
            if target.startswith(("http:", "https:", "mailto:", "#")):
                continue
            path = target.split("#", 1)[0]
            if path and not (document.parent / path).exists():
                missing.append(f"{document.relative_to(ROOT)} -> {target}")
    return missing


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--terraform", default="terraform")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts" / "local")
    args = parser.parse_args()
    terraform = shutil.which(args.terraform)
    if not terraform:
        parser.error("Terraform is missing. Install the version in .terraform-version, then retry.")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith("AWS_")}
    env.update(AWS_EC2_METADATA_DISABLED="true", AWS_CONFIG_FILE="/dev/null",
               AWS_SHARED_CREDENTIALS_FILE="/dev/null", CHECKPOINT_DISABLE="1",
               TF_IN_AUTOMATION="1", TF_INPUT="0")
    # Never allow a real test provider to be introduced silently.
    for path in (ROOT / "tests").rglob("*.tftest.hcl"):
        if not re.search(r'mock_provider\s+"aws"\s*\{', path.read_text()):
            parser.error(f"{path.name} must explicitly mock AWS")
    checks = [
        ("version", [terraform, "version", "-json"]),
        ("fmt", [terraform, "fmt", "-check", "-recursive"]),
        ("init", [terraform, "init", "-backend=false", "-input=false", "-lockfile=readonly", "-no-color"]),
        ("validate", [terraform, "validate", "-no-color"]),
        ("terraform-test", [terraform, "test", "-no-color"]),
        ("python-test", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-v"]),
    ]
    results = []
    for name, command in checks:
        print(f"Checking {name}...", flush=True)
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
            code, log = result.returncode, result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            code, log = 124, "Local check timed out after 600 seconds\n"
        (output / f"{name}.log").write_text(log, encoding="utf-8")
        results.append({"name": name, "passed": code == 0, "exit_code": code, "log": f"{name}.log"})
        if code:
            print(log, file=sys.stderr)
            break
    missing = broken_links()
    (output / "links.log").write_text("\n".join(missing) + ("\n" if missing else "All local Markdown links resolve.\n"))
    results.append({"name": "links", "passed": not missing, "exit_code": int(bool(missing)), "log": "links.log"})
    hashes = {}
    for pattern in ("*.tf", "*.hcl", "*.example", ".gitignore", ".terraform-version", "scripts/*", "tests/*", "docs/*.md", "*.md", ".github/workflows/*.yml"):
        for path in ROOT.glob(pattern):
            if path.is_file():
                hashes[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    report = {
        "time_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "scope": "local only; AWS provider mocked; no AWS deployment",
        "passed": len(results) == len(checks) + 1 and all(check["passed"] for check in results),
        "checks": results,
        "source_sha256": dict(sorted(hashes.items())),
    }
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Local validation {'PASSED' if report['passed'] else 'FAILED'}: {output / 'report.json'}")
    return int(not report["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
