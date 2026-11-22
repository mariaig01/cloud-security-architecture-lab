"""Shared EC2 helpers. Importing this module never contacts AWS."""

import argparse
import datetime
import errno
import json
import os
import re
import shutil
import socket
import subprocess
import urllib.request


def classify(returncode, stderr):
    if returncode == 0:
        return "allowed"
    match = re.search(r"An error occurred \(([^)]+)\)", stderr)
    if match and match.group(1) in {"AccessDenied", "AccessDeniedException", "UnauthorizedOperation"}:
        return "denied"
    return "error"


def instance_environment(region):
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("AWS_") and key.lower() not in
           {"http_proxy", "https_proxy", "all_proxy", "no_proxy"}}
    env.update(AWS_CONFIG_FILE="/dev/null", AWS_SHARED_CREDENTIALS_FILE="/dev/null",
               AWS_REGION=region, AWS_DEFAULT_REGION=region,
               AWS_EC2_METADATA_DISABLED="false", AWS_PAGER="", AWS_MAX_ATTEMPTS="1")
    return env


def instance_identity(expected_account, expected_role):
    # Read identity and role NAME only, never the credentials.
    client = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    base = "http://169.254.169.254/latest/"
    request = urllib.request.Request(base + "api/token", method="PUT",
                                     headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"})
    with client.open(request, timeout=3) as response:
        token = response.read().decode()

    def read(path):
        request = urllib.request.Request(base + path, headers={"X-aws-ec2-metadata-token": token})
        with client.open(request, timeout=3) as response:
            return response.read().decode()

    identity = json.loads(read("dynamic/instance-identity/document"))
    role_name = read("meta-data/iam/security-credentials/").strip()
    if identity["accountId"] != expected_account or role_name != expected_role:
        raise RuntimeError("Unexpected instance account or application role")
    return identity


def arguments(location):
    parser = argparse.ArgumentParser(description=f"Synthetic {location} EC2 probe; opt-in only")
    parser.add_argument("--execute", action="store_true")
    for name in ("region", "account-id", "role-name", "documents-bucket", "logs-bucket", "run-id"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--prefix", default="app/documents/")
    if location == "public":
        parser.add_argument("--private-ip", required=True)
        parser.add_argument("--trail-arn", required=True)
    args = parser.parse_args()
    if not args.execute:
        parser.error("No operations performed. --execute is required on the authorized lab instance.")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", args.run_id):
        parser.error("run-id must be 1-64 safe characters")
    if not re.fullmatch(r"(?:[A-Za-z0-9_-]+/)+", args.prefix) or len(args.prefix) > 200:
        parser.error("prefix must contain safe segments ending in /, up to 200 characters")
    if args.prefix.startswith(("restricted/", "probe-fixtures/")):
        parser.error("prefix collides with negative-control fixtures")
    if not shutil.which("aws"):
        parser.error("AWS CLI v2 must already be installed; no dependencies are downloaded")
    version = subprocess.run(["aws", "--version"], capture_output=True, text=True, timeout=5)
    if version.returncode or not version.stdout.startswith("aws-cli/2."):
        parser.error("AWS CLI v2 is required")
    return args


def tcp_check(host, port, timeout=5):
    try:
        target = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)[0][4]
    except socket.gaierror:
        return "dns_error", None
    try:
        with socket.create_connection(target, timeout=timeout):
            return "connected", str(target)
    except (TimeoutError, socket.timeout):
        return "timeout", str(target)
    except OSError as error:
        actual = "unreachable" if error.errno in {errno.ENETUNREACH, errno.EHOSTUNREACH} else "error"
        return actual, str(target)


class Probe:
    def __init__(self, args, location):
        self.args, self.location = args, location
        self.identity = instance_identity(args.account_id, args.role_name)
        if self.identity["region"] != args.region:
            raise RuntimeError("Instance and bucket regions must match")
        self.env = instance_environment(args.region)
        self.failures = []
        self.emit(kind="identity", account_id=args.account_id, role_name=args.role_name,
                  region=args.region)

    def emit(self, **record):
        record.update(run_id=self.args.run_id, location=self.location,
                      instance_id=self.identity["instanceId"],
                      time_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
        print(json.dumps(record, sort_keys=True), flush=True)

    def check(self, test_id, passed, **record):
        if not passed:
            self.failures.append(test_id)
        self.emit(test_id=test_id, passed=passed, **record)

    def call(self, test_id, service, operation, expected, *arguments):
        command = ["aws", "--region", self.args.region, "--output", "json",
                   "--cli-connect-timeout", "5", "--cli-read-timeout", "10"]
        if service == "s3api":
            command += ["--endpoint-url", f"https://s3.{self.args.region}.amazonaws.com"]
        command += [service, operation, *map(str, arguments)]
        try:
            result = subprocess.run(command, env=self.env, capture_output=True, text=True, timeout=20)
            actual, code = classify(result.returncode, result.stderr), result.returncode
            match = re.search(r"An error occurred \(([^)]+)\)", result.stderr)
            error = match.group(1) if match else ("client_error" if code else "")
            output = json.loads(result.stdout or "{}") if code == 0 else {}
            if not isinstance(output, dict):
                raise ValueError("Expected JSON object")
        except subprocess.TimeoutExpired:
            actual, code, error, output = "error", None, "client_timeout", {}
        except (ValueError, OSError):
            actual, code, error, output = "error", None, "invalid_response_or_client", {}
        passed = actual == expected
        self.check(test_id, passed, kind="operation", action=f"{service}:{operation}",
                   expected=expected, actual=actual, exit_code=code, error=error,
                   version_id=output.get("VersionId"), etag=output.get("ETag"))
        return output, passed

    def s3(self, test_id, operation, bucket, expected, *arguments):
        return self.call(test_id, "s3api", operation, expected, "--bucket", bucket,
                         "--expected-bucket-owner", self.args.account_id, *arguments)

    def network(self, test_id, host, port, blocked=True):
        actual, target = tcp_check(host, port)
        passed = actual in {"timeout", "unreachable"} if blocked else actual == "connected"
        self.check(test_id, passed, kind="network", actual=actual, target=target,
                   note="Requires operator route/SG inspection and matching positive control")

    def summary(self, reason=""):
        self.emit(kind="summary", passed=not self.failures,
                  failed_tests=sorted(set(self.failures)), reason=reason)
        return int(bool(self.failures))
