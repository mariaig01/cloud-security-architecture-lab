"""Local classifier tests. Never import an AWS SDK or contact AWS."""

import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

PROBE = Path(__file__).resolve().parents[1] / "scripts" / "private_probe.py"
sys.path.insert(0, str(PROBE.parent))
SPEC = importlib.util.spec_from_file_location("private_probe", PROBE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class ProbeClassificationTests(unittest.TestCase):
    def test_success_requires_zero_exit(self):
        self.assertEqual(probe.classify(0, ""), "allowed")
        self.assertEqual(probe.classify(1, ""), "error")

    def test_explicit_authorization_error(self):
        self.assertEqual(probe.classify(254, "An error occurred (AccessDenied) when calling the GetObject operation: Access Denied"), "denied")

    def test_connectivity_failure_is_not_authorization(self):
        for message in ["Could not connect to endpoint URL", "Name or service not known", "Read timeout", "AccessDenied mentioned in a local log"]:
            with self.subTest(message=message):
                self.assertEqual(probe.classify(255, message), "error")

    def test_bad_credentials_are_not_authorization(self):
        for code in ["ExpiredToken", "InvalidAccessKeyId", "SignatureDoesNotMatch", "NoSuchKey"]:
            with self.subTest(code=code):
                self.assertEqual(probe.classify(254, f"An error occurred ({code}) when calling the GetObject operation"), "error")

    def test_no_execute_exits_before_dependencies_or_network(self):
        result = subprocess.run([
            sys.executable, str(PROBE), "--region", "eu-west-1", "--account-id", "123456789012",
            "--role-name", "cloud-security-lab-app", "--documents-bucket", "test-documents",
            "--logs-bucket", "test-logs", "--run-id", "local-only",
        ], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn("No operations performed", result.stderr)


if __name__ == "__main__":
    unittest.main()
