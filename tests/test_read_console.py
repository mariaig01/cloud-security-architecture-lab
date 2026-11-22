"""Reject truncated, mismatched or contradictory console evidence."""

import base64
import importlib
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
console = importlib.import_module("read_console")


def record(kind, **fields):
    return dict(kind=kind, run_id="run", location="public", instance_id="i-test", **fields)


class ConsoleTests(unittest.TestCase):
    def extract(self, records):
        return console.extract("\n".join(json.dumps(record) for record in records), "run", "public", "i-test")

    def test_summary_alone_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, "identity"):
            self.extract([record("summary", passed=True, failed_tests=[])])

    def test_summary_without_subtests_is_incomplete(self):
        report = self.extract([record("identity"), record("summary", passed=True, failed_tests=[])])
        self.assertFalse(report["complete"])
        self.assertFalse(report["probe_passed"])

    def test_truncated_report_has_no_summary(self):
        with self.assertRaisesRegex(ValueError, "summary"):
            self.extract([record("identity"), record("operation", test_id="P14", passed=True)])

    def test_mixed_identity_rejected(self):
        with self.assertRaisesRegex(ValueError, "identity"):
            self.extract([record("identity"), dict(record("summary", passed=True, failed_tests=[]), run_id="other")])

    def test_contradictory_summary_rejected(self):
        with self.assertRaisesRegex(ValueError, "contradicts"):
            self.extract([record("identity"), record("operation", passed=False),
                          record("summary", passed=True, failed_tests=[])])

    def test_base64_api_and_decoded_cli_console(self):
        text = "\n".join(json.dumps(r) for r in [record("identity"), record("summary", passed=False, failed_tests=["P14"])])
        for output in [text, base64.b64encode(text.encode()).decode()]:
            with self.subTest(output=output[:20]):
                envelope = json.dumps({"InstanceId": "i-test", "Output": output})
                self.assertFalse(console.extract(envelope, "run", "public", "i-test")["probe_passed"])

    def test_wrong_instance_envelope_rejected(self):
        with self.assertRaisesRegex(ValueError, "another instance"):
            console.extract(json.dumps({"InstanceId": "i-wrong", "Output": ""}), "run", "public", "i-test")


if __name__ == "__main__":
    unittest.main()
