"""Exercise complete probe flows with fake CLI, metadata and sockets; never AWS."""

import contextlib
import importlib
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
common = importlib.import_module("probe_common")
private = importlib.import_module("private_probe")
public = importlib.import_module("public_probe")
console = importlib.import_module("read_console")

ACCOUNT = "123456789012"
INSTANCE = "i-0123456789abcdef0"
IDENTITY = {"accountId": ACCOUNT, "region": "eu-west-1", "instanceId": INSTANCE}


class FakeAws:
    def __init__(self, corrupt=False, no_version=False, allow_create=False):
        self.current = b""
        self.version = 0
        self.commands = []
        self.corrupt, self.no_version, self.allow_create = corrupt, no_version, allow_create

    def __call__(self, command, **kwargs):
        self.commands.append(command)
        if command == ["aws", "--version"]:
            return subprocess.CompletedProcess(command, 0, "aws-cli/2.40.0 Python/3.13", "")
        service_index = next(i for i, value in enumerate(command) if value in {"s3api", "sts", "iam", "cloudtrail"})
        service, operation = command[service_index:service_index + 2]
        output = {}
        allowed = False
        if service == "sts":
            allowed = True
            output = {"Account": ACCOUNT, "Arn": f"arn:aws:sts::{ACCOUNT}:assumed-role/lab-app/{INSTANCE}"}
        elif service == "iam" and self.allow_create:
            allowed = True
        elif service == "s3api" and "--bucket" in command:
            bucket = command[command.index("--bucket") + 1]
            key = command[command.index("--key") + 1] if "--key" in command else ""
            if bucket == "lab-documents" and key == "app/documents/probe/local-test/document.txt" and "--version-id" not in command:
                if operation == "put-object":
                    allowed = True
                    self.current = Path(command[command.index("--body") + 1]).read_bytes()
                    self.version += 1
                    output = {} if self.no_version else {"VersionId": f"version-{self.version}", "ETag": "synthetic"}
                elif operation == "get-object":
                    allowed = True
                    Path(command[-1]).write_bytes(b"corrupt" if self.corrupt else self.current)
        if allowed:
            return subprocess.CompletedProcess(command, 0, json.dumps(output), "")
        return subprocess.CompletedProcess(command, 254, "", "An error occurred (AccessDenied) when calling operation: synthetic")


def run_probe(location, fake):
    argv = ["probe", "--execute", "--region", "eu-west-1", "--account-id", ACCOUNT,
            "--role-name", "lab-app", "--documents-bucket", "lab-documents",
            "--logs-bucket", "lab-logs", "--run-id", "local-test"]
    if location == "public":
        argv += ["--private-ip", "10.42.1.10", "--trail-arn",
                 f"arn:aws:cloudtrail:eu-west-1:{ACCOUNT}:trail/lab-audit"]

    def fake_listener(probe):
        probe.emit(kind="listener", test_id="P20-control", passed=True, port=8080)

    def fake_network(host, port, timeout=5):
        if location == "public" and host == "example.com":
            return "connected", "('93.184.215.14', 443)"
        return "timeout", str((host, port))

    stream = io.StringIO()
    with mock.patch.object(sys, "argv", argv), mock.patch.object(common.shutil, "which", return_value="/fake/aws"), \
            mock.patch.object(common, "instance_identity", return_value=IDENTITY), \
            mock.patch.object(common.subprocess, "run", side_effect=fake), \
            mock.patch.object(common, "tcp_check", side_effect=fake_network), \
            mock.patch.object(private, "listener", side_effect=fake_listener), contextlib.redirect_stdout(stream):
        code = (private if location == "private" else public).main()
    return code, stream.getvalue()


class ProbeExecutionTests(unittest.TestCase):
    def test_complete_private_probe_and_console_extraction(self):
        fake = FakeAws()
        code, text = run_probe("private", fake)
        self.assertEqual(code, 0)
        report = console.extract(text, "local-test", "private", INSTANCE)
        self.assertTrue(report["complete"])
        self.assertTrue(report["probe_passed"])
        self.assertIn("requires operator", report["matrix_status"])
        commands = [command for command in fake.commands if "s3api" in command]
        self.assertTrue(all("--expected-bucket-owner" in command for command in commands))
        self.assertNotIn("synthetic:local-test:v1", text)

    def test_corrupt_download_fails_even_with_successful_get(self):
        code, text = run_probe("private", FakeAws(corrupt=True))
        self.assertEqual(code, 1)
        report = console.extract(text, "local-test", "private", INSTANCE)
        self.assertFalse(report["probe_passed"])
        self.assertIn("P02-content", report["records"][-1]["failed_tests"])

    def test_missing_version_aborts_and_reports_incomplete(self):
        code, text = run_probe("private", FakeAws(no_version=True))
        self.assertEqual(code, 1)
        report = console.extract(text, "local-test", "private", INSTANCE)
        self.assertFalse(report["complete"])
        self.assertIn("P09-read", report["missing_subtests"])

    def test_public_probe_denials_and_positive_network_control(self):
        fake = FakeAws()
        # Every document request in this location must be denied.
        original = fake.__call__

        def outside(command, **kwargs):
            if "s3api" in command:
                return subprocess.CompletedProcess(command, 254, "", "An error occurred (AccessDenied) when calling operation")
            return original(command, **kwargs)
        code, text = run_probe("public", outside)
        self.assertEqual(code, 0)
        self.assertTrue(console.extract(text, "local-test", "public", INSTANCE)["probe_passed"])
        update = next(command for command in fake.commands if "update-trail" in command)
        self.assertIn("--enable-log-file-validation", update)
        self.assertNotIn("--no-is-multi-region-trail", update)
        self.assertFalse(any("stop-logging" in command or "delete-trail" in command for command in fake.commands))

    def test_unexpected_create_role_is_failure(self):
        code, text = run_probe("public", FakeAws(allow_create=True))
        self.assertEqual(code, 1)
        self.assertIn("P15", json.loads(text.splitlines()[-1])["failed_tests"])

    def test_environment_cannot_replace_instance_identity_or_endpoint(self):
        with mock.patch.dict(common.os.environ, {
            "AWS_ACCESS_KEY_ID": "test-secret", "AWS_PROFILE": "other",
            "AWS_ENDPOINT_URL": "https://untrusted.invalid", "HTTPS_PROXY": "https://proxy.invalid",
            "AWS_CONTAINER_CREDENTIALS_FULL_URI": "https://untrusted.invalid"}, clear=True):
            env = common.instance_environment("eu-west-1")
        self.assertNotIn("AWS_ACCESS_KEY_ID", env)
        self.assertNotIn("AWS_PROFILE", env)
        self.assertNotIn("AWS_ENDPOINT_URL", env)
        self.assertNotIn("AWS_CONTAINER_CREDENTIALS_FULL_URI", env)
        self.assertNotIn("HTTPS_PROXY", env)
        self.assertEqual(env["AWS_EC2_METADATA_DISABLED"], "false")

    def test_client_timeout_and_invalid_json_never_count_as_denied(self):
        args = mock.Mock(region="eu-west-1", account_id=ACCOUNT, role_name="lab-app", run_id="local-test")
        with mock.patch.object(common, "instance_identity", return_value=IDENTITY), contextlib.redirect_stdout(io.StringIO()):
            probe = common.Probe(args, "private")
            for result in [subprocess.TimeoutExpired(["aws"], 20),
                           subprocess.CompletedProcess(["aws"], 0, "not-json", ""),
                           subprocess.CompletedProcess(["aws"], 0, "[]", "")]:
                with self.subTest(result=result), mock.patch.object(common.subprocess, "run") as run:
                    if isinstance(result, Exception):
                        run.side_effect = result
                    else:
                        run.return_value = result
                    _, passed = probe.call("negative", "iam", "create-role", "denied")
                    self.assertFalse(passed)

    def test_dns_failure_is_inconclusive_not_network_block(self):
        with mock.patch.object(common.socket, "getaddrinfo", side_effect=common.socket.gaierror()):
            self.assertEqual(common.tcp_check("example.com", 443), ("dns_error", None))


if __name__ == "__main__":
    unittest.main()
